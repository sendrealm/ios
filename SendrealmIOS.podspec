Pod::Spec.new do |s|
  s.name         = "SendrealmIOS"
  s.version      = "0.1.0"
  s.summary      = "Native iOS SDK for Sendrealm."
  s.license      = "MIT"
  s.homepage     = "https://sendrealm.com"
  s.author       = "Sendrealm"
  s.platforms    = { :ios => "13.4" }
  s.source       = { :git => "https://github.com/sendrealm/ios.git", :tag => s.version.to_s }
  s.source_files = "Sources/SendrealmIOS/**/*.{swift}"
  s.exclude_files = "Example/**/*"
  s.frameworks   = "UIKit", "UserNotifications"
  s.swift_version = "5.9"
end
