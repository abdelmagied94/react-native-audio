require 'json'

Pod::Spec.new do |s|
  # NPM package specification
  package = JSON.parse(File.read(File.join(File.dirname(__FILE__), 'package.json')))

  s.name           = 'RNAudio'
  s.version        = package['version']
  s.license        = 'MIT'
  s.summary        = 'Audio recorder library for React Native'
  s.author         = { 'Joshua Sierles' => 'joshua@diluvia.net' }
  s.homepage       = "https://github.com/abdelmagied94/react-native-audio-recorder"
  s.source         = { :git => 'https://github.com/abdelmagied94/react-native-audio-recorder.git', :tag => "v#{s.version}"}
  s.platform       = :ios, '8.0'
  s.preserve_paths = '*.js'
  s.frameworks     = 'AVFoundation'

  s.dependency 'React-Core'

  s.source_files = 'ios/AudioRecorderManager.{h,m}'
end

