#!/usr/bin/env ruby
# frozen_string_literal: true

# One-time bootstrap: adds the `LOGITUITests` UI test target to the Xcode
# project so fastlane snapshot can run. This is idempotent - re-running it
# is a no-op if the target already exists.
#
# Usage:
#   bundle exec ruby fastlane/bootstrap_uitest_target.rb
#
# The `xcodeproj` gem ships with fastlane, so no extra install is needed
# once `bundle install` has run at the repo root.

require "xcodeproj"

PROJECT_PATH  = File.expand_path("../LOGIT.xcodeproj", __dir__)
TARGET_NAME   = "LOGITUITests"
APP_TARGET    = "LOGIT"
TEAM_ID       = "S2F6F7JZ8C"
BUNDLE_ID     = "com.lukaskbl.LOGITUITests"
DEPLOYMENT    = "17.0"
UITEST_DIR    = File.expand_path("../LOGITUITests", __dir__)
SWIFT_SOURCES = %w[SnapshotHelper.swift LOGITScreenshots.swift].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "[bootstrap] #{TARGET_NAME} target already exists - nothing to do."
  exit 0
end

host_target = project.targets.find { |t| t.name == APP_TARGET }
raise "Could not find #{APP_TARGET} target" unless host_target

puts "[bootstrap] Creating #{TARGET_NAME} target..."

test_target = project.new_target(
  :ui_test_bundle,
  TARGET_NAME,
  :ios,
  DEPLOYMENT,
  nil,
  :swift
)

# Build settings: signing, bundle id, test host.
test_target.build_configurations.each do |config|
  bs = config.build_settings
  bs["DEVELOPMENT_TEAM"]         = TEAM_ID
  bs["PRODUCT_BUNDLE_IDENTIFIER"] = BUNDLE_ID
  bs["CODE_SIGN_STYLE"]          = "Automatic"
  bs["IPHONEOS_DEPLOYMENT_TARGET"] = DEPLOYMENT
  bs["SWIFT_VERSION"]            = "5.0"
  bs["TARGETED_DEVICE_FAMILY"]   = "1,2"
  bs["TEST_TARGET_NAME"]         = APP_TARGET
  bs["GENERATE_INFOPLIST_FILE"]  = "YES"
  bs["PRODUCT_NAME"]             = "$(TARGET_NAME)"
  bs["INFOPLIST_KEY_CFBundleDisplayName"] = TARGET_NAME
  bs["LD_RUNPATH_SEARCH_PATHS"]  = ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]
end

# Create a Project navigator group + add Swift sources to the target.
group = project.main_group.find_subpath(TARGET_NAME, true)
group.set_source_tree("<group>")
group.set_path(TARGET_NAME)

SWIFT_SOURCES.each do |file_name|
  file_path = File.join(UITEST_DIR, file_name)
  unless File.exist?(file_path)
    warn "[bootstrap] WARNING: #{file_path} not found - skipping"
    next
  end

  file_ref = group.new_reference(file_name)
  test_target.add_file_references([file_ref])
  puts "[bootstrap]   + #{file_name}"
end

# Make the UI test target depend on the app target so Xcode builds them in
# the right order.
test_target.add_dependency(host_target)

# Register the UI test target in the primary scheme so `xcodebuild test`
# (and fastlane snapshot) can find it.
scheme_path = Xcodeproj::XCScheme.shared_data_dir(PROJECT_PATH) + "#{APP_TARGET}.xcscheme"
if File.exist?(scheme_path)
  scheme = Xcodeproj::XCScheme.new(scheme_path.to_s)
  already_in_scheme = scheme.test_action.testables.any? do |t|
    t.buildable_references.any? { |ref| ref.target_name == TARGET_NAME }
  end

  unless already_in_scheme
    testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
    scheme.test_action.add_testable(testable)
    scheme.save!
    puts "[bootstrap] Added #{TARGET_NAME} to the #{APP_TARGET} scheme."
  end
else
  warn "[bootstrap] NOTE: #{scheme_path} not found. Open Xcode once to generate the shared scheme, then re-run."
end

project.save
puts "[bootstrap] Done. Open Xcode, verify the target, then run:"
puts "    bundle exec fastlane screenshots"
