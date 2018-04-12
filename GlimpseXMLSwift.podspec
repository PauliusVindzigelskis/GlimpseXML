#
# Be sure to run `pod lib lint GlimpseXMLSwift.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'GlimpseXMLSwift'
  s.version          = '1.0.0'
  s.summary          = 'Fast DOM parser & serializer'

  s.description      = 'Fast DOM parser & serializer in pure Swift for iOS & Mac'

  s.homepage         = 'https://github.com/PauliusVindzigelskis/GlimpseXML'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Paulius Vindzigelskis' => 'p.vindzigelskis@gmail.com' }
  s.source           = { :git => 'https://github.com/PauliusVindzigelskis/GlimpseXML.git', :tag => s.version.to_s }

  s.ios.deployment_target = '8.0'

  s.source_files = 'GlimpseXML/GlimpseXML.swift'

  s.libraries    = 'xml2'
  s.xcconfig     = { 'OTHER_LDFLAGS' => '-lxml2' }
end
