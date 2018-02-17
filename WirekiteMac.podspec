#
# Be sure to run `pod lib lint WirekiteMac.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'WirekiteMac'
  s.version          = '0.5.0'
  s.summary          = 'Wire up digital and analog IOs to your Mac.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
Wire up digital and analog IOs to your Mac and control them with your Swift or Objective-C code run on your Mac.
To connect the inputs and outputs, use a Teensy development board connected via USB.
It looks a lot like an Arduino Nano connected for loading the code.
Yet with Wirekite the custom code is written for and run on your Mac.
DESC

  s.homepage         = 'https://github.com/manuelbl/WirekiteMac'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'manuelbl' => 'manuelbl@users.noreply.github.com' }
  s.source           = { :git => 'https://github.com/manuelbl/WirekiteMac.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.osx.deployment_target  = '10.10'

  s.source_files = 'WirekiteMacLib/Sources/**/*'
  s.public_header_files = 'WirekiteMacLib/Sources/**/*.h'
  
  # s.resource_bundles = {
  #   'WirekiteMac' => ['WirekiteMac/Assets/*.png']
  # }

  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
  s.libraries = 'c++'
end
