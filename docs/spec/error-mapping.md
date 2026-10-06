# Especificación: mapeo de errores nativos al contrato común

Fuente normativa del mapeo decidido en [ADR-0001](../adr/0001-shared-contract.md). Esta especificación sí se actualiza cuando cambia una plataforma; cada cambio debe venir con su test (`LocalAuthenticationAuthenticatorTests` en iOS, `BiometricPromptAuthenticatorTest` en Android).

## Resultado del prompt (`BiometricResult`)

| Resultado | iOS (`LAError`) | Android (`BiometricPrompt`) |
|---|---|---|
| `success` | `evaluatePolicy` devuelve `true` | `onAuthenticationSucceeded` |
| `cancelled` | `userCancel`, `systemCancel`, `appCancel` | `ERROR_USER_CANCELED`, `ERROR_CANCELED`, `ERROR_NEGATIVE_BUTTON` cuando no hay caída a PIN |
| `lockedOut` | `biometryLockout` | `ERROR_LOCKOUT` (temporal), `ERROR_LOCKOUT_PERMANENT` (exige la credencial del equipo) |
| `notAvailable` | `biometryNotAvailable` | `ERROR_HW_NOT_PRESENT`, `ERROR_HW_UNAVAILABLE`, `ERROR_SECURITY_UPDATE_REQUIRED` |
| `notEnrolled` | `biometryNotEnrolled`, `passcodeNotSet` | `ERROR_NO_BIOMETRICS` (prompt), `BIOMETRIC_ERROR_NONE_ENROLLED` (`BiometricManager`) |
| `fallbackToPin` | `userFallback` | `ERROR_NEGATIVE_BUTTON` con el botón configurado como "Usar PIN" |
| `failed(reason)` | cualquier otro | cualquier otro |

## Disponibilidad antes del prompt (`BiometricAvailabilityStatus`)

| Estado | iOS (`canEvaluatePolicy`) | Android (`BiometricManager.canAuthenticate(BIOMETRIC_STRONG)`) | Decisión de `BiometricSession` |
|---|---|---|---|
| `available` | devuelve `true` | `BIOMETRIC_SUCCESS` | lanza el prompt |
| `notAvailable` | `biometryNotAvailable`, cualquier otro error | `BIOMETRIC_ERROR_NO_HARDWARE`, `BIOMETRIC_ERROR_HW_UNAVAILABLE`, `BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED`, `BIOMETRIC_ERROR_UNSUPPORTED`, `BIOMETRIC_STATUS_UNKNOWN`, cualquier otro | `showUnavailable("notAvailable")` |
| `notEnrolled` | `biometryNotEnrolled`, `passcodeNotSet` | `BIOMETRIC_ERROR_NONE_ENROLLED` | `showUnavailable("notEnrolled")` |
| `lockedOut` | `biometryLockout` | N/A: `BiometricManager` no informa bloqueo; llega después como `ERROR_LOCKOUT` del prompt | `requirePin` |

`canAuthenticate` es verdadero solo si el estado es `available` y el tipo no es `none`. `isEnrolled` e `isLockedOut` se mantienen por compatibilidad y se derivan del estado.

## Notas por plataforma

- **iOS, permiso de Face ID negado:** se observa como `biometryNotAvailable` aunque `biometryType` siga en `.faceID`. Es comportamiento observado, no documentado por Apple; se valida en equipo real. Sin `NSFaceIDUsageDescription` en el `Info.plist`, el sistema no permite Face ID.
- **iOS, `passcodeNotSet`:** hoy cae en `notEnrolled`, pero la acción del usuario es distinta (crear un código del dispositivo, no enrolar biometría). Pendiente: motivo propio (ver [ADR-0002](../adr/0002-crypto-bound-biometrics.md), que además lo necesita porque sin código no se puede guardar el secreto).
- **Android, tipo de biometría:** se deduce por features del sistema y se prefiere huella sobre rostro. En muchos equipos el rostro es Clase 2 (débil) y pedimos `BIOMETRIC_STRONG`, así que con ambos sensores el prompt casi siempre termina usando la huella.
- **Android, bloqueo:** `ERROR_LOCKOUT` y `ERROR_LOCKOUT_PERMANENT` llevan a la misma decisión (`requirePin`), pero el mensaje al usuario y la telemetría deberían distinguirlos.

## Pendientes conocidos

Hoy caen en `failed` / "cualquier otro" y conviene mapearlos explícitamente:

- Android: `ERROR_NO_DEVICE_CREDENTIAL` (14) y `ERROR_IDENTITY_CHECK_NOT_ACTIVE` / `BIOMETRIC_ERROR_IDENTITY_CHECK_NOT_ACTIVE` (20).

## Referencias

- Apple: [`LAError`](https://developer.apple.com/documentation/localauthentication/laerror-swift.struct), [`LAError.passcodeNotSet`](https://developer.apple.com/documentation/localauthentication/laerror-swift.struct/passcodenotset)
- AndroidX: [`BiometricPrompt`](https://developer.android.com/reference/androidx/biometric/BiometricPrompt), [`BiometricManager`](https://developer.android.com/reference/androidx/biometric/BiometricManager)
