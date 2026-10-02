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
  s.resource_bundles = {'just_gamepads_privacy' => ['just_gamepads/Sources/just_gamepads/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'
  s.frameworks = 'GameController'

  # GCExtendedGamepad's buttonMenu/buttonOptions and GCController's
  # productCategory need macOS 10.15, which is also Flutter's minimum.
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
