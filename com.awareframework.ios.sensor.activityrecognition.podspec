#
# Be sure to run `pod lib lint com.awareframework.ios.sensor.activityrecognition.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'com.awareframework.ios.sensor.activityrecognition'
  s.version       = '0.5.0'
  s.summary          = 'An Activity Recognition Sensor Module for AWARE Framework.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
**Aware Activity Recognition** (com.awareframework.ios.sensor.activityrecognition) is a plugin for AWARE Framework which is one of an open-source context-aware instrument. This plugin allows us to manage motion activity data (such as running, walking, and automotive) that is provided by iOS [CMMotionActivityManager](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager).
                       DESC

  s.homepage         = 'https://github.com/awareframework/com.awareframework.ios.sensor.activityrecognition'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'Apache2', :file => 'LICENSE' }
  s.author           = { 'Yuuki Nishiyama' => 'yuukin@iis.u-tokyo.ac.jp' }
  s.source           = { :git => 'https://github.com/awareframework/com.awareframework.ios.sensor.activityrecognition.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '10.0'
  
  s.swift_version = '4.2'

  s.source_files = 'com.awareframework.ios.sensor.activityrecognition/Classes/**/*'
  
  s.frameworks = 'CoreMotion'
  s.dependency 'com.awareframework.ios.sensor.core', '~> 0.4.3'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
    
end
