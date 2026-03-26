#!/usr/bin/env ruby
# Add WorkoutSharingTests.swift to Xcode project

pbxproj_path = "LOGIT.xcodeproj/project.pbxproj"
content = File.read(pbxproj_path)

def safe_sub!(content, pattern, replacement, description)
  unless content.sub!(pattern, replacement)
require 'securerandom'

def generate_unique_pbx_id(content)
  loop do
    id = SecureRandom.hex(12).upcase # 24-character hex string
    return id unless content.include?(id)
  end
end

pbxproj_path = "LOGIT.xcodeproj/project.pbxproj"
content = File.read(pbxproj_path)

file_ref_id = generate_unique_pbx_id(content)
build_file_id = generate_unique_pbx_id(content)
file_name = "WorkoutSharingTests.swift"

# 1. Add PBXBuildFile entry (after the last 80NEWTEST line in build files section)
build_file_line = "\t\t#{build_file_id} /* #{file_name} in Sources */ = {isa = PBXBuildFile; fileRef = #{file_ref_id} /* #{file_name} */; };\n"
safe_sub!(
  content,
  /(\t\t80NEWTEST009 \/\* ServicesTests\.swift in Sources \*\/ = \{[^}]+\};\n)/,
  "\\1#{build_file_line}",
  "insert PBXBuildFile for #{file_name} after ServicesTests.swift in Sources"
)

# 2. Add PBXFileReference entry (after ServicesTests.swift file ref)
file_ref_line = "\t\t#{file_ref_id} /* #{file_name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{file_name}; sourceTree = \"<group>\"; };\n"
safe_sub!(
  content,
  /(\t\t80NEWTEST00A \/\* ServicesTests\.swift \*\/ = \{[^}]+\};\n)/,
  "\\1#{file_ref_line}",
  "insert PBXFileReference for #{file_name} after ServicesTests.swift file reference"
)

# 3. Add to LOGITTests group children (after WeightConvertingTests.swift)
safe_sub!(
  content,
  /(\t\t\t\t80NEWTEST004 \/\* WeightConvertingTests\.swift \*\/,\n)(\t\t\t\t7959F4CE)/,
  "\\1\t\t\t\t#{file_ref_id} /* #{file_name} */,\n\\2",
  "add #{file_name} to LOGITTests group children after WeightConvertingTests.swift"
)

# 4. Add to Sources build phase (after ServicesTests.swift in Sources)
safe_sub!(
  content,
  /(\t\t\t\t80NEWTEST009 \/\* ServicesTests\.swift in Sources \*\/,\n)(\t\t\t\);)/,
  "\\1\t\t\t\t#{build_file_id} /* #{file_name} in Sources */,\n\\2",
  "add #{file_name} build file to Sources build phase after ServicesTests.swift in Sources"
)

File.write(pbxproj_path, content)
puts "Successfully added #{file_name} to project"
