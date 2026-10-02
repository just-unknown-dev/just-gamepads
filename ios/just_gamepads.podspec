#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint just_gamepads.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'just_gamepads'
  s.version          = '0.1.0'
  s.summary          = 'Gamepad input for Flutter through Apple\'s GameController framework.'
  s.description      = <<-DESC
Reports Xbox, PlayStation, Switch Pro and MFi controllers to the just_gamepads
Flutter plugin through Apple's GameController framework.
                       DESC
  s.homepage         = 'https://github.com/just-unknown-dev/just-gamepads'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'JustUnknown' => 'https://github.com/just-unknown-dev' }
  s.source           = { :path => '.' }
  s.source_files = 'just_gamepads/Sources/just_gamepads/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'GameController'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'just_gamepads_privacy' => ['just_gamepads/Sources/just_gamepads/PrivacyInfo.xcprivacy']}
end
