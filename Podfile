platform :ios, '16.0'

ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'AiBeaversServeDetect.xcodeproj'

target 'AiBeaversServeDetect' do
  use_frameworks!
  use_modular_headers!

  pod 'GoogleMLKit/PoseDetection', '9.0.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
