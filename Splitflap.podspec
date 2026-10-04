require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "Splitflap"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/enavermate/react-native-splitflap.git", :tag => "v#{s.version}" }

  # cpp/ holds the shadow node the iOS view and the Android JNI library share.
  s.source_files = "ios/**/*.{h,m,mm}", "cpp/**/*.{h,cpp}"
  s.private_header_files = "ios/**/*.h", "cpp/**/*.h"

  s.pod_target_xcconfig = {
    "HEADER_SEARCH_PATHS" => "\"$(PODS_TARGET_SRCROOT)/cpp\"",
  }

  install_modules_dependencies(s)

  # With frameworks the textlayoutmanager headers are not on the default search path.
  if ENV["USE_FRAMEWORKS"] != nil
    add_dependency(s, "React-FabricComponents", :additional_framework_paths => [
      "react/renderer/textlayoutmanager/platform/ios",
    ])
  end
end
