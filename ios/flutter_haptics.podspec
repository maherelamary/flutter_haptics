#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_haptics.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_haptics'
  s.version          = '1.0.0'
  s.summary          = 'A powerful, type-safe haptic feedback plugin for Flutter using Core Haptics.'
  s.description      = <<-DESC
A type-safe haptic feedback plugin for Flutter. Compose haptic patterns with
parameter curves and play them through Core Haptics, falling back to UIKit
feedback generators on devices without it.
                       DESC
  s.homepage         = 'https://github.com/maherelamary/flutter_haptics'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Link Development' => 'maher.alamary@linkdev.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_haptics/Sources/flutter_haptics/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # The plugin collects nothing and uses no required-reason APIs; the manifest
  # says so explicitly so apps embedding it inherit a correct declaration.
  s.resource_bundles = {
    'flutter_haptics_privacy' => ['flutter_haptics/Sources/flutter_haptics/PrivacyInfo.xcprivacy']
  }
end
