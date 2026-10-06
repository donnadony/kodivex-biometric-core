# Cambios v2

Resumen de lo que cambió respecto a la primera versión del módulo.

## 1. Estado de disponibilidad común

- Nuevo enum `BiometricAvailabilityStatus` en iOS y Android con cuatro casos: `available`, `notAvailable`, `notEnrolled` y `lockedOut`.
- `BiometricAvailability` ahora guarda `type` y `status`. `isEnrolled` e `isLockedOut` siguen existiendo como propiedades calculadas, y el inicializador anterior con booleanos se mantiene por compatibilidad.
- `canAuthenticate` es verdadero solo si `status == available` y el tipo no es `none`.
- iOS: el estado sale del `LAError` de `canEvaluatePolicy`. `biometryNotAvailable` da `notAvailable` aunque `biometryType` sea `.faceID` (caso del permiso de Face ID negado, que antes se reportaba como "no enrolado"). `biometryNotEnrolled` y `passcodeNotSet` dan `notEnrolled`, y `biometryLockout` da `lockedOut`.
- `BiometricSession` decide el corto circuito con `status`: `lockedOut` va a PIN, `notEnrolled` y `notAvailable` muestran no disponible con su propia razón.
- Pigeon: `BiometricAvailabilityDto` suma el campo `status`. La API Dart expone `BiometricAvailabilityStatus` y ambos adaptadores del plugin lo envían.
- README: nota sobre `NSFaceIDUsageDescription` en el `Info.plist` de las apps iOS.

## 2. Reinicio automático de intentos

- `BiometricSession` (actor en iOS, clase en Android) vuelve el contador a cero después de una decisión terminal (`grantAccess` o `requirePin`). `reset()` sigue disponible.
- `Decision` ganó dos propiedades en ambas plataformas: `kind` (código estable para serializar) e `isTerminal`.
- ADR-0001 aclara que `maxAttempts` cuenta prompts y que cada prompt del sistema ya permite varios intentos internos.

## 3. La política se expone a Flutter

- Pigeon: nuevo `BiometricDecisionDto` (`kind`, `remaining`, `reason`) y dos métodos en el HostApi: `runSession(reason, maxAttempts)` asíncrono y `resetSession()`.
- Los adaptadores nativos guardan una `BiometricSession`, la reutilizan mientras `maxAttempts` no cambie y traducen la decisión al DTO. `resetSession` descarta la sesión, así la siguiente llamada empieza en cero sin carreras.
- Dart: nueva clase sellada `BiometricDecision` (`GrantAccess`, `RetryPrompt`, `RequirePin`, `ShowUnavailable`) y métodos `runSession` y `resetSession`. Se llama `RetryPrompt` y no `Retry` para no chocar con la anotación `Retry` de `package:test`. Un `kind` desconocido se trata como `RequirePin`, nunca como acceso.
- ADR-0001 y README explican que Flutter consume la política nativa en vez de reimplementarla.
- Los archivos generados por Pigeon 22.7.4 (`messages.g.dart`, `Messages.g.swift`, `Messages.g.kt`) ahora vienen en el repo.

## 4. Ajustes de Android

- `availability()` prefiere huella sobre rostro cuando el equipo tiene ambos, con un comentario que explica por qué (el rostro suele ser Clase 2 y pedimos `BIOMETRIC_STRONG`).
- `BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED`, `BIOMETRIC_ERROR_UNSUPPORTED`, `BIOMETRIC_STATUS_UNKNOWN` y cualquier código desconocido ahora dan `notAvailable` en vez de disponible.
- El mapeo del prompt también trata `ERROR_SECURITY_UPDATE_REQUIRED` como `notAvailable`, para ser coherente con lo anterior.
- Tabla del ADR alineada: `notEnrolled` lista `ERROR_NO_BIOMETRICS` (prompt) y `BIOMETRIC_ERROR_NONE_ENROLLED` (BiometricManager); `notAvailable` lista `ERROR_HW_NOT_PRESENT` y `ERROR_HW_UNAVAILABLE`. Se agregó una segunda tabla con el mapeo de disponibilidad.
- Nuevos `android/gradle.properties` (`android.useAndroidX=true`) y `consumer-rules.pro` vacío, que el build ya referenciaba.

## 5. Plugin Flutter

- iOS: la respuesta a Flutter se entrega en el hilo principal con `Task { @MainActor in ... }`.
- iOS: los métodos del HostApi pasan de `public` a internos, porque Pigeon genera el protocolo y los DTO como `internal` y un método público no puede exponer tipos internos (la versión anterior no compilaba por eso).
- iOS: soporte de Swift Package Manager con el layout oficial de Flutter: `ios/biometric_core_flutter/Package.swift` y fuentes en `Sources/biometric_core_flutter/`. Depende de `FlutterFramework` y de `ios/BiometricCore` por ruta relativa, resolviendo antes el symlink que crea Flutter. Se eliminó `ios/Classes`.
- iOS: el podspec apunta a las nuevas fuentes y documenta cómo agregar `BiometricCore` con CocoaPods.
- Android: `onDetachedFromEngine` ya no cancela el scope para siempre; ahora usa `scope.coroutineContext.cancelChildren()` y limpia la sesión.
- Versión del plugin: 0.2.0.

## 6. Tests y CI

- iOS: `LocalAuthenticationAuthenticatorTests` cubre cada fila de la tabla del ADR con `LAError(.userCancel)` y similares, más el mapeo de disponibilidad. Van dentro de `#if canImport(LocalAuthentication)`.
- iOS: nuevos tests de `BiometricAvailability`, del corto circuito por estado y del reinicio automático en `BiometricSession`.
- Android: `BiometricPromptAuthenticatorTest` cubre cada código, incluido el botón negativo con y sin caída a PIN. Nuevos tests de disponibilidad y de reinicio automático con un autenticador falso.
- Flutter: `test/biometric_core_flutter_test.dart` con un HostApi falso.
- `.github/workflows/ci.yml` con dos jobs: `ios` (`swift test` en macOS) y `android` (JDK 17, el Android SDK que ya trae el runner y Gradle 8.9 fijo, porque el repo no trae wrapper).
- README con badge de CI para `github.com/donnadony/kodivex-biometric-core`.

## 7. ADR-0002 y documentación

- Nuevo `docs/adr/0002-crypto-bound-biometrics.md` (Estado: Propuesto): pasar de biometría por evento a biometría ligada a criptografía, con Keychain y `.biometryCurrentSet` en iOS, y Keystore con `setUserAuthenticationRequired(true)`, `setInvalidatedByBiometricEnrollment(true)` y `BiometricPrompt.CryptoObject` en Android. Referencia MASVS-AUTH-2.
- Roadmap del README con ADR-0002 en curso.
- Se quitaron las rayas largas de README y ADRs; las celdas vacías de tablas ahora dicen N/A o describen el caso.

## 8. ADRs al formato MADR 4

- Plantilla `0000-template.md` basada en MADR 4: front matter YAML, resumen en una línea (Y-Statement) con TL;DR en inglés, criterios de decisión, opción elegida con nivel de confianza, sección de confirmación y pros y contras por opción.
- Nuevo índice `docs/adr/README.md` con estados, diagrama de relaciones y la regla de no editar ADRs aceptados.
- Las tablas de mapeo salieron de ADR-0001 a `docs/spec/error-mapping.md`, que pasa a ser la fuente normativa. ADR-0001 cita MASWE-0021 y su confirmación indica qué tests cubren cada tabla (falta un test unitario para la tabla de disponibilidad de Android).
- ADR-0002 corregido tras verificar contra la documentación de Apple, Android y OWASP: códigos de iOS al invalidarse el ítem (incluido el cambio en iOS 15), `LAContext` nuevo por lectura, configuración en API 23 a 29, StrongBox con caída a TEE, aclaración de que sube la barrera contra hooks pero no da inmunidad, referencias MASWE y MASTG concretas, y tres alternativas nuevas (ventana de validez, passkeys, App Attest y Play Integrity).
- El detalle de APIs de ADR-0002 pasó a `docs/design/crypto-bound-biometrics.md`.
