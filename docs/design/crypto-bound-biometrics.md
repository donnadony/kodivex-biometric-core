# Nota de diseño: biometría ligada a criptografía

Detalle de implementación de [ADR-0002](../adr/0002-crypto-bound-biometrics.md). A diferencia del ADR, esta nota se actualiza a medida que avanza el spike.

## iOS

- **Guardar:** ítem de Keychain (`kSecClassGenericPassword`) con `SecAccessControlCreateWithFlags`, accesibilidad `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` y bandera `.biometryCurrentSet`.
  - `ThisDeviceOnly`: el ítem no viaja en backups ni migra a otro equipo.
  - `WhenPasscodeSet`: si el usuario quita el código del dispositivo, el ítem se borra. Sin código no se puede guardar, por eso `passcodeNotSet` necesita un motivo propio en el contrato y no puede seguir cayendo en `notEnrolled`.
  - `.biometryCurrentSet`: agregar o quitar una huella, o volver a enrolar Face ID, invalida el ítem.
- **Leer:** `SecItemCopyMatching` con un `LAContext` **nuevo** en `kSecUseAuthenticationContext`. El sistema muestra Face ID o Touch ID y solo entrega el dato si la biometría es válida.
  - No reutilizar un `LAContext` ya autenticado ni fijar `touchIDAuthenticationAllowableReuseDuration`: un contexto autenticado autoriza más lecturas sin volver a pedir biometría.
- **Dónde vive el secreto:** el Secure Enclave protege la clave de la fila del Keychain y decide la biometría, pero tras un unlock el secreto llega **en claro** a la app. Para que el secreto nunca salga del chip haría falta una clave EC con `kSecAttrTokenIDSecureEnclave` (opción de challenge en ADR-0002).
- **Errores:**

| Situación | `OSStatus` | Resultado del contrato |
|---|---|---|
| Ítem invalidado por cambio de enrolamiento | `errSecItemNotFound` (hasta iOS 14), `errSecAuthFailed` (iOS 15 o superior) | `keyInvalidated` |
| Usuario cancela el prompt | `errSecUserCanceled` | `cancelled` |
| Éxito | `errSecSuccess` | secreto |

El cambio de código en iOS 15 está reportado por la comunidad ([Apple Developer Forums](https://developer.apple.com/forums/thread/690546)), no documentado por Apple: tratar ambos códigos igual y confirmarlo en el spike.

## Android

- **Generar la clave:** AES en Android Keystore con `KeyGenParameterSpec.Builder`:
  - `setUserAuthenticationRequired(true)`.
  - API 30 o superior: `setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)` (timeout 0 = autenticación en cada uso).
  - API 23 a 29: basta con `setUserAuthenticationRequired(true)`, que por defecto ya exige autenticación en cada uso. No usar `setUserAuthenticationValidityDurationSeconds` (deprecado desde API 30).
  - `setInvalidatedByBiometricEnrollment(true)`: ya es el valor por defecto, se deja explícito por claridad. Solo aplica a claves de autenticación en cada uso.
  - No agregar `AUTH_DEVICE_CREDENTIAL`: con esa bandera la clave deja de invalidarse cuando cambia el enrolamiento.
  - `setIsStrongBoxBacked(true)` en API 28 o superior, con caída a TEE si el equipo lanza `StrongBoxUnavailableException`.
- **Usar la clave:** inicializar un `Cipher`, envolverlo en `BiometricPrompt.CryptoObject` y llamar `authenticate(promptInfo, cryptoObject)`. Descifrar con `result.cryptoObject?.cipher` dentro de `onAuthenticationSucceeded`.
  - El modo con `CryptoObject` no acepta biometría Clase 2 (débil), ni `DEVICE_CREDENTIAL` antes de API 30 (lanza `IllegalArgumentException`). Pedimos `BIOMETRIC_STRONG`, así que cumple.
  - Considerar `setConfirmationRequired(true)` para rostro pasivo ([MASTG-BEST-0038](https://mas.owasp.org/MASTG/best-practices/MASTG-BEST-0038/)).
- **Errores:**

| Situación | Señal | Resultado del contrato |
|---|---|---|
| Enrolamiento cambió | `KeyPermanentlyInvalidatedException` en `Cipher.init` | `keyInvalidated` |
| Resto de errores del prompt | códigos de `BiometricPrompt` | según [`docs/spec/error-mapping.md`](../spec/error-mapping.md) |

- **A futuro:** [Key Attestation](https://developer.android.com/privacy-and-security/security-key-attestation) para que el backend verifique que la clave vive en hardware seguro (opción de challenge en ADR-0002).

## Contrato

```
BiometricSecretStore
  store(secret)        -> Result<Unit, BiometricResult>
  unlock(reason)       -> Result<Secret, BiometricResult>
  invalidate()
```

- `unlock` reutiliza los valores de `BiometricResult` y agrega `keyInvalidated`.
- La política trata `keyInvalidated` como `requirePin` más una marca para pedir reactivar la biometría tras el login con PIN.
- Clave AES: guardar también exige autenticación. Si se necesita guardar sin prompt (por ejemplo al rotar el refresh token en background), usar una clave asimétrica: cifrar con la pública sin prompt y exigir biometría solo al descifrar con la privada.

## Flutter

El secreto no cruza a Dart si no es necesario. El plugin expone operaciones de alto nivel (desbloquear y usar el secreto en nativo) en vez de devolver los bytes.

## Plan del spike

1. iOS: store, unlock, cancelar, agregar huella o volver a enrolar Face ID, verificar `keyInvalidated`.
2. Android: lo mismo en un equipo con StrongBox y en uno de gama baja; medir la tasa de errores de Keystore.
3. Anotar en esta nota los códigos reales observados y actualizar la especificación de errores.
