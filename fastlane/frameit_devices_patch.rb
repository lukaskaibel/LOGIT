# Teaches fastlane/frameit about newer iPhones (15/16/17 families).
#
# Upstream ships a hard-coded device list in frameit/lib/frameit/device_types.rb
# that stops at the iPhone 14 family, so anything shot on an iPhone 15+ crashes
# with `Unsupported screen size`. This file monkey-patches the Devices module
# by appending the missing entries with the correct portrait/landscape pixel
# resolutions. Resolutions are sourced from Apple's "Human Interface Guidelines
# - Designing for iOS - Specifications" reference.
#
# Required for our marketing pipeline because Apple mandates 6.9" screenshots,
# which today means iPhone 17 Pro Max (1320x2868). iPhone 16 Plus (1290x2796)
# also works as the 6.7" marketing size.

require "fastlane"
require "frameit/device_types"
require "frameit/editor"

module Frameit
  module Color
    DEEP_BLUE ||= "Deep Blue"
    COSMIC_ORANGE ||= "Cosmic Orange"
    LAVENDER ||= "Lavender"
    MIST_BLUE ||= "Mist Blue"
    SAGE ||= "Sage"
    TEAL ||= "Teal"
    ULTRAMARINE ||= "Ultramarine"
    BLACK_TITANIUM ||= "Black Titanium"
    NATURAL_TITANIUM ||= "Natural Titanium"
    DESERT_TITANIUM ||= "Desert Titanium"
    WHITE_TITANIUM ||= "White Titanium"
  end

  module Devices
    # iPhone 15 family
    IPHONE_15 ||= Device.new("iphone-15", "Apple iPhone 15", 13, [[1179, 2556], [2556, 1179]], 460, Color::BLACK, Platform::IOS)
    IPHONE_15_PLUS ||= Device.new("iphone-15-plus", "Apple iPhone 15 Plus", 13, [[1290, 2796], [2796, 1290]], 458, Color::BLACK, Platform::IOS)
    IPHONE_15_PRO ||= Device.new("iphone-15-pro", "Apple iPhone 15 Pro", 13, [[1179, 2556], [2556, 1179]], 460, Color::BLACK_TITANIUM, Platform::IOS)
    IPHONE_15_PRO_MAX ||= Device.new("iphone15-pro-max", "Apple iPhone 15 Pro Max", 13, [[1290, 2796], [2796, 1290]], 460, Color::BLACK_TITANIUM, Platform::IOS)

    # iPhone 16 family
    IPHONE_16 ||= Device.new("iphone-16", "Apple iPhone 16", 14, [[1179, 2556], [2556, 1179]], 460, Color::BLACK, Platform::IOS)
    IPHONE_16_PLUS ||= Device.new("iphone-16-plus", "Apple iPhone 16 Plus", 14, [[1290, 2796], [2796, 1290]], 458, Color::BLACK, Platform::IOS)
    IPHONE_16_PRO ||= Device.new("iphone-16-pro", "Apple iPhone 16 Pro", 14, [[1206, 2622], [2622, 1206]], 460, Color::BLACK_TITANIUM, Platform::IOS)
    IPHONE_16_PRO_MAX ||= Device.new("iphone16-pro-max", "Apple iPhone 16 Pro Max", 14, [[1320, 2868], [2868, 1320]], 460, Color::BLACK_TITANIUM, Platform::IOS)

    # iPhone 17 family
    IPHONE_17 ||= Device.new("iphone-17", "Apple iPhone 17", 15, [[1206, 2622], [2622, 1206]], 460, Color::BLACK, Platform::IOS)
    IPHONE_17_PRO ||= Device.new("iphone-17-pro", "Apple iPhone 17 Pro", 15, [[1206, 2622], [2622, 1206]], 460, Color::DEEP_BLUE, Platform::IOS)
    IPHONE_17_PRO_MAX ||= Device.new("iphone17-pro-max", "Apple iPhone 17 Pro Max", 15, [[1320, 2868], [2868, 1320]], 460, Color::DEEP_BLUE, Platform::IOS)
  end

  # Upstream frameit's editor.rb sets ImageMagick's `-fill` AFTER `-draw`, so
  # the colour never takes effect and all text renders in whatever the
  # default fill is (usually white). Override `build_text_images` so that
  # `fill` is emitted first, which matches the rest of frameit's behaviour
  # and finally lets the per-filter keyword colour in Framefile.json show
  # up. See: https://github.com/fastlane/fastlane/issues/21959
  class Editor
    private

    alias_method :__logit_original_build_text_images, :build_text_images

    def build_text_images(max_width, max_height)
      words = [:keyword, :title].keep_if { |a| fetch_text(a) }
      results = {}
      trim_boxes = {}
      top_vertical_trim_offset = Float::INFINITY
      bottom_vertical_trim_offset = 0

      words.each do |key|
        empty_path = File.join(Frameit::ROOT, "lib/assets/empty.png")
        text_image = MiniMagick::Image.open(empty_path)
        image_height = max_height
        text_image.combine_options do |i|
          i.resize("#{max_width * 5.0}x#{image_height}!")
        end

        current_font = font(key)
        text = fetch_text(key)
        UI.verbose("Using #{current_font} as font the #{key} of #{screenshot.path}") if current_font
        UI.verbose("Adding text '#{text}'")

        text = text.gsub('\n', "\n").gsub(/(?<!\\)(')/) { |s| "\\#{s}" }

        interline_spacing = @config["interline_spacing"]

        color_value = @config[key.to_s]["color"]

        # Frameit's upstream editor composes `-fill` AFTER `-draw` in the same
        # magick invocation, which means ImageMagick sees the text already
        # rasterised by the time the colour is set, so it silently drops the
        # fill. Pre-building a single-command line where `-fill` precedes the
        # draw makes the colour stick. We work outside MiniMagick's
        # combine_options DSL because the DSL preserves author order but also
        # auto-escapes arguments - which is exactly what we still want, so we
        # emit the args manually via `MiniMagick::Tool`.
        MiniMagick::Tool::Mogrify.new do |m|
          m.font(current_font) if current_font
          m.weight(@config[key.to_s]["font_weight"]) if @config[key.to_s]["font_weight"]
          m.gravity("Center")
          m.pointsize(actual_font_size(key))
          m.interline_spacing(interline_spacing) if interline_spacing
          m.fill(color_value)
          m.draw("text 0,0 '#{text}'")
          m << text_image.path
        end

        results[key] = text_image

        calculated_trim_box = text_image.identify do |b|
          b.format("%@")
        end

        trim_box = Frameit::Trimbox.new(calculated_trim_box)

        if trim_box.offset_y < top_vertical_trim_offset
          top_vertical_trim_offset = trim_box.offset_y
        end

        if (trim_box.offset_y + trim_box.height) > bottom_vertical_trim_offset
          bottom_vertical_trim_offset = trim_box.offset_y + trim_box.height
        end

        trim_boxes[key] = trim_box
      end

      words.each do |key|
        trim_box = trim_boxes[key]

        if trim_box.offset_y > top_vertical_trim_offset
          trim_box.height += trim_box.offset_y - top_vertical_trim_offset
          trim_box.offset_y = top_vertical_trim_offset
          UI.verbose("Trim box for key \"#{key}\" is adjusted to align top: #{trim_box.json_string_format}")
        end

        if (trim_box.offset_y + trim_box.height) < bottom_vertical_trim_offset
          trim_box.height = bottom_vertical_trim_offset - trim_box.offset_y
          UI.verbose("Trim box for key \"#{key}\" is adjusted to align bottom: #{trim_box.json_string_format}")
        end

        results[key].crop(trim_box.string_format)
      end

      results
    end
  end
end
