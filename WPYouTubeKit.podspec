Pod::Spec.new do |s|
  s.name                   = "WPYouTubeKit"
  s.version                = "1.0.1"
  s.summary                = "YouTube video player for iOS and OS X."
  s.homepage               = "https://github.com/WPMedia"
  s.license                = { :type => "MIT", :file => "LICENSE" }
  s.author                 = { "Cédric Luthi" => "cedric.luthi@gmail.com" }
  s.source                 = { :git => "https://github.com/WPMedia/WPYouTubeKit.git", :tag => s.version.to_s }
  s.ios.deployment_target  = "8.0"
  s.osx.deployment_target  = "10.9"
  s.tvos.deployment_target = "9.0"
  s.source_files           = "XCDYouTubeKit"
  s.public_header_files    = "XCDYouTubeKit/XCDYouTube{Client,Error,Kit,Logger,Operation,Video,VideoOperation,VideoQueryOperation}.h"
  s.osx.frameworks         = "JavaScriptCore"
  s.tvos.frameworks        = "JavaScriptCore"
  s.requires_arc           = true
end
