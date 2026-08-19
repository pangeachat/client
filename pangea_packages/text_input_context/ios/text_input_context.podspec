Pod::Spec.new do |s|
  s.name             = 'text_input_context'
  s.version          = '0.1.0'
  s.summary          = 'Per-field keyboard language persistence for Flutter text input on iOS.'
  s.description      = <<-DESC
Gives Flutter's iOS text input view a UIKit textInputContextIdentifier, so iOS
restores the keyboard language the user last chose for that field.
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
