Pod::Spec.new do |s|
  s.name             = 'keyboard_languages'
  s.version          = '0.1.0'
  s.summary          = 'Reports the language of every keyboard the user has enabled on the device.'
  s.description      = <<-DESC
Reports the language of every keyboard the user has enabled on the device, on
iOS and Android.
                       DESC
  s.homepage         = 'https://github.com/pangeachat/client'
  s.license          = { :type => 'AGPL-3.0', :file => '../LICENSE' }
  s.author           = { 'Pangea Chat' => 'dev@pangea.chat' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
