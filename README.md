# kodivex-biometric-core

[![CI](https://github.com/donnadony/kodivex-biometric-core/actions/workflows/ci.yml/badge.svg)](https://github.com/donnadony/kodivex-biometric-core/actions/workflows/ci.yml)

Módulo de autenticación biométrica con **un solo contrato** y tres consumidores:

| Capa | Tecnología | Carpeta |
|---|---|---|
| Contrato + implementación iOS | Swift Package, `LocalAuthentication` | `ios/BiometricCore` |
| Contrato + implementación Android | Android library, `androidx.biometric` | `android/biometric-core` |
| Puente Flutter | Plugin con Pigeon (platform channels tipados) | `flutter/biometric_core_flutter` |
| Decisiones | [ADRs](docs/adr/README.md) (formato MADR 4) | `docs/adr` |

## Idea central

Face ID / Touch ID y `BiometricPrompt` se comportan distinto. En vez de exponer esas diferencias a la app, cada plataforma traduce sus errores a valores comunes.

Resultado del prompt:

```
success | cancelled | lockedOut | notAvailable | notEnrolled | fallbackToPin | failed(reason)
```

Disponibilidad antes del prompt (`BiometricAvailability.status`):

```
available | notAvailable | notEnrolled | lockedOut
```

La política de negocio (cuántos intentos, cuándo caer a PIN, cuándo volver a pedir) vive en `BiometricPolicy` y `BiometricSession`, y se escribe una vez por plataforma nativa con la misma firma. **Flutter no la reimplementa:** llama a `runSession`, que ejecuta la sesión nativa y devuelve la decisión. El objetivo de la semana 7 del plan es mover la política a un módulo KMP `shared/`.

Dos detalles de la política:

- `maxAttempts` cuenta prompts, no lecturas del sensor. Cada prompt del sistema ya permite varios intentos internos.
- La sesión reinicia el contador sola después de `grantAccess` o `requirePin`.

Las tablas completas de mapeo están en la [especificación de errores](docs/spec/error-mapping.md); el porqué de este diseño, en [ADR-0001](docs/adr/0001-shared-contract.md).

## Estructura

```
kodivex-biometric-core/
├── .github/workflows/ci.yml  # swift test + gradle :biometric-core:test
├── docs/
│   ├── adr/                  # índice, plantilla MADR, 0001 y 0002
│   ├── spec/                 # error-mapping.md (fuente normativa del mapeo)
│   └── design/               # notas de implementación (crypto-bound)
├── ios/BiometricCore/        # swift build / swift test
├── android/biometric-core/   # gradle :biometric-core:test
└── flutter/biometric_core_flutter/
    ├── pigeons/messages.dart # contrato Dart <-> nativo
    ├── lib/                  # API pública Dart (+ src/messages.g.dart generado)
    ├── ios/
    │   ├── biometric_core_flutter/          # Swift Package del plugin (SwiftPM)
    │   │   ├── Package.swift                # depende de ios/BiometricCore por ruta relativa
    │   │   └── Sources/biometric_core_flutter/
    │   └── biometric_core_flutter.podspec   # CocoaPods, mismas fuentes
    └── android/src/          # usa biometric-core (gradle)
```

## Cómo empezar

```bash
# iOS
cd ios/BiometricCore && swift build && swift test

# Android (requiere Android SDK + JDK 17). El repo no trae Gradle wrapper:
# usa Gradle 8.9 o genera uno con `gradle wrapper --gradle-version 8.9`.
cd android && gradle :biometric-core:test

# Flutter (regenerar el puente después de cambiar pigeons/messages.dart)
cd flutter/biometric_core_flutter
dart run pigeon --input pigeons/messages.dart
```

### Requisito en apps iOS

La app que use el módulo (nativa o Flutter) debe declarar `NSFaceIDUsageDescription` en su `Info.plist`, con un texto que explique para qué usa Face ID. Sin esa clave iOS no muestra Face ID. Si el usuario niega el permiso, `availability()` devuelve `status = notAvailable` aunque el tipo siga siendo `face`.

```xml
<key>NSFaceIDUsageDescription</key>
<string>Usamos Face ID para que ingreses a tu cuenta de forma segura.</string>
```

### Uso desde Flutter

```dart
final biometric = BiometricCore();

Future<void> login() async {
  final decision = await biometric.runSession(reason: 'Ingresa a tu cuenta', maxAttempts: 3);
  switch (decision) {
    case GrantAccess():
      goHome();
    case RetryPrompt(:final remaining):
      showMessage('Te quedan $remaining intentos'); // y volver a llamar login()
    case RequirePin():
      goToPin();
    case ShowUnavailable(:final reason):
      showUnavailable(reason); // notAvailable o notEnrolled
  }
}
```

En Android la Activity debe extender `FlutterFragmentActivity`.

### Plugin Flutter en iOS: Swift Package Manager y CocoaPods

El plugin sigue el layout oficial de Flutter para Swift Package Manager: `ios/biometric_core_flutter/Package.swift` con las fuentes en `Sources/biometric_core_flutter/`. Con SwiftPM (Flutter 3.44 o superior, donde viene activado por defecto) `BiometricCore` se resuelve solo desde `ios/BiometricCore` del repo; `Package.swift` resuelve el symlink que Flutter crea en `ios/Flutter/ephemeral/Packages/.packages/` para que la ruta relativa apunte a la carpeta real.

Esto asume que la app consume el plugin desde una copia completa de este repo (por ejemplo con `path:` en `pubspec.yaml`), porque `BiometricCore` vive fuera de la carpeta del plugin.

Con CocoaPods el podspec usa las mismas fuentes, pero `BiometricCore` hay que agregarlo a mano como Swift Package local al proyecto iOS de la app. El registro de CocoaPods pasa a solo lectura el 2 de diciembre de 2026, así que SwiftPM es el camino recomendado.

## Roadmap (ligado al plan de 6 meses)

- [x] Contrato común + implementación iOS
- [x] Contrato común + implementación Android
- [x] Plugin Flutter con Pigeon
- [x] Estado de disponibilidad común y política expuesta a Flutter (`runSession`)
- [x] Tests de mapeo de errores + CI en GitHub Actions
- [ ] En curso: [ADR-0002](docs/adr/0002-crypto-bound-biometrics.md), biometría ligada a criptografía (Keychain con `.biometryCurrentSet`, Keystore con `CryptoObject`)
- [ ] Semana 6: pantalla demo en Compose
- [ ] Semana 7: `shared/` en Kotlin Multiplatform con `BiometricPolicy`
- [ ] Semana 9: fitness functions (cold start, tamaño, cobertura)
- [ ] Semana 11: eventos de observabilidad (éxito, fallo, fallback)
- [ ] Semana 14: señal on-device de riesgo

## Licencia

MIT. Kodivex, 2026.
