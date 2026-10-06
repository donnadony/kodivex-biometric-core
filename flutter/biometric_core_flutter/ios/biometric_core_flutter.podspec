Pod::Spec.new do |s|
  s.name             = 'biometric_core_flutter'
  s.version          = '0.2.0'
  s.summary          = 'Puente Flutter al contrato BiometricCore.'
  s.homepage         = 'https://kodivex.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Kodivex' => 'hola@kodivex.com' }
  s.source           = { :path => '.' }
  # Mismas fuentes que usa Swift Package Manager (biometric_core_flutter/Package.swift).
  s.source_files     = 'biometric_core_flutter/Sources/biometric_core_flutter/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  # Con Swift Package Manager (Flutter 3.44 o superior, el camino recomendado) BiometricCore
  # se resuelve solo desde Package.swift. Con CocoaPods hay que agregarlo a mano como
  # Swift Package local al proyecto iOS de la app:
  #   File > Add Package Dependencies > Add Local... > ios/BiometricCore
  # Alternativa: publicar BiometricCore como pod y usar `s.dependency 'BiometricCore'`.
  # Ojo: el registro de CocoaPods (trunk) pasa a solo lectura el 2 de diciembre de 2026.
end
