# ADR-0001: Un contrato de resultado común para biometría en iOS, Android y Flutter

- **Estado:** Aceptado
- **Fecha:** 2026-10-05
- **Actualizado:** 2026-10-05 (estado de disponibilidad, auto reinicio de intentos, política expuesta a Flutter)
- **Autor:** Dony Mollo
- **Revisores:** N/A

## Contexto

Una app bancaria necesita login biométrico con el mismo comportamiento en iOS y Android, y una futura app secundaria en Flutter reutilizará la misma funcionalidad. `LocalAuthentication` (iOS) y `BiometricPrompt` (Android) exponen errores, fallbacks y políticas de bloqueo distintas. Si cada app interpreta esos errores por su cuenta, la lógica de negocio (reintentos, caída a PIN, mensajes) se duplica y diverge.

## Decisión

Definir un **contrato único** `BiometricAuthenticator` con un resultado cerrado (`BiometricResult`), un estado de disponibilidad cerrado (`BiometricAvailabilityStatus`) y una `BiometricPolicy` que contiene la lógica de negocio. `BiometricSession` orquesta autenticador y política. Cada plataforma implementa el contrato traduciendo sus errores nativos a los valores comunes.

Flutter consume el contrato **y la política** a través de un plugin generado con Pigeon: `runSession` ejecuta la `BiometricSession` nativa y devuelve la decisión ya tomada (`grantAccess`, `retry`, `requirePin` o `showUnavailable`). Así Flutter no reimplementa reintentos ni caída a PIN. `authenticate` queda disponible como prompt crudo para casos especiales.

### Resultado del prompt (`BiometricResult`)

| Resultado | iOS (LAError) | Android (BiometricPrompt) |
|---|---|---|
| `success` | `evaluatePolicy` devuelve `true` | `onAuthenticationSucceeded` |
| `cancelled` | `userCancel`, `systemCancel`, `appCancel` | `ERROR_USER_CANCELED`, `ERROR_CANCELED`, `ERROR_NEGATIVE_BUTTON` cuando no hay caída a PIN |
| `lockedOut` | `biometryLockout` | `ERROR_LOCKOUT`, `ERROR_LOCKOUT_PERMANENT` |
| `notAvailable` | `biometryNotAvailable` | `ERROR_HW_NOT_PRESENT`, `ERROR_HW_UNAVAILABLE`, `ERROR_SECURITY_UPDATE_REQUIRED` |
| `notEnrolled` | `biometryNotEnrolled`, `passcodeNotSet` | `ERROR_NO_BIOMETRICS` (prompt), `BIOMETRIC_ERROR_NONE_ENROLLED` (BiometricManager, ver tabla siguiente) |
| `fallbackToPin` | `userFallback` | `ERROR_NEGATIVE_BUTTON` con el botón configurado como "Usar PIN" |
| `failed(reason)` | cualquier otro | cualquier otro |

### Disponibilidad antes del prompt (`BiometricAvailabilityStatus`)

| Estado | iOS (`canEvaluatePolicy`) | Android (`BiometricManager.canAuthenticate(BIOMETRIC_STRONG)`) | Decisión de `BiometricSession` |
|---|---|---|---|
| `available` | devuelve `true` | `BIOMETRIC_SUCCESS` | lanza el prompt |
| `notAvailable` | `biometryNotAvailable` (incluye permiso de Face ID negado, aunque `biometryType` siga en `.faceID`), cualquier otro error | `BIOMETRIC_ERROR_NO_HARDWARE`, `BIOMETRIC_ERROR_HW_UNAVAILABLE`, `BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED`, `BIOMETRIC_ERROR_UNSUPPORTED`, `BIOMETRIC_STATUS_UNKNOWN`, cualquier otro | `showUnavailable("notAvailable")` |
| `notEnrolled` | `biometryNotEnrolled`, `passcodeNotSet` | `BIOMETRIC_ERROR_NONE_ENROLLED` | `showUnavailable("notEnrolled")` |
| `lockedOut` | `biometryLockout` | N/A: `BiometricManager` no informa bloqueo, llega después como `ERROR_LOCKOUT` del prompt | `requirePin` |

`canAuthenticate` es verdadero solo si el estado es `available` y el tipo no es `none`. `isEnrolled` e `isLockedOut` se mantienen por compatibilidad y se derivan del estado.

En Android el tipo se deduce por features del sistema y se prefiere huella sobre rostro: en muchos equipos el rostro es Clase 2 (débil) y nosotros pedimos `BIOMETRIC_STRONG`, así que con ambos sensores el prompt casi siempre termina usando la huella.

## Alternativas consideradas

| Opción | Pros | Contras | Por qué no |
|---|---|---|---|
| Cada app maneja errores nativos directamente | Cero abstracción, máximo control | Lógica duplicada y divergente; Flutter tendría que conocer ambos SDK | No escala a 3 consumidores |
| Flutter como única implementación (todo vía plugin de terceros) | Un solo código | Dependencia externa en un flujo de seguridad; las apps nativas existentes no lo usarían | Riesgo en auditoría bancaria |
| Flutter recibe solo `authenticate` y escribe su propia política | Plugin más simple | La política de reintentos y PIN se escribiría una tercera vez, en Dart | Rompe el objetivo de escribir la política una sola vez |
| Contrato común + implementación nativa por plataforma, política expuesta a Flutter (elegida) | Lógica de negocio escrita una vez; auditable; nativo donde importa | Mantener 2 implementaciones del contrato | Costo aceptable: el contrato es pequeño |

## Consecuencias

- **Positivas:** la política de reintentos y fallback se escribe y testea una vez por plataforma nativa, y Flutter la consume vía `runSession` sin duplicarla; los consumidores (SwiftUI, Compose, Flutter) no conocen `LAError` ni códigos de `BiometricPrompt`; el mapeo de errores queda documentado y versionado aquí, y cada fila de las tablas tiene un test (`LocalAuthenticationAuthenticatorTests`, `BiometricPromptAuthenticatorTest`).
- **Cómo se cuentan los intentos:** `maxAttempts` cuenta **prompts**, no lecturas del sensor. Cada prompt del sistema ya permite varios intentos internos (Face ID, Touch ID y `BiometricPrompt` reintentan solos antes de devolver un error), así que `maxAttempts = 3` significa hasta 3 prompts, cada uno con sus propios intentos del sistema. `BiometricSession` reinicia el contador sola después de una decisión terminal (`grantAccess` o `requirePin`); `reset()` queda para casos explícitos como cerrar sesión.
- **Negativas / deuda que aceptamos:** `BiometricPolicy` existe hoy en Swift y en Kotlin por separado (duplicación controlada). Plan: moverla a Kotlin Multiplatform en la semana 7 (ADR futuro). La biometría sigue siendo un evento (booleano), no un secreto criptográfico: se aborda en ADR-0002.
- **Qué nos haría revisar esta decisión:** que Apple o Google expongan un nuevo estado que no mapee limpiamente, o que el módulo KMP resulte más costoso de mantener que la duplicación.

## Referencias

- Apple, LocalAuthentication: `LAError`, `LAContext.canEvaluatePolicy(_:error:)`
- AndroidX Biometric: códigos de error de `BiometricPrompt` y estados de `BiometricManager`
- OWASP MASVS v2, MASVS-AUTH-2 (autenticación local)
- ADR-0002: biometría ligada a criptografía
