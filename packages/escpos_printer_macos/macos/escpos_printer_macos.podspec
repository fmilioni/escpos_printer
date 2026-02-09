Pod::Spec.new do |s|
  s.name             = 'escpos_printer_macos'
  s.version          = '0.0.1'
  s.summary          = 'ESC/POS thermal printer plugin.'
  s.description      = <<-DESC
ESC/POS thermal printer plugin for Flutter.
                       DESC
  s.homepage         = 'https://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'FMilioni' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.frameworks = 'IOBluetooth', 'IOKit'

  s.platform = :osx, '10.13'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
