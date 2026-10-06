# ADR-0002: Ligar la biometría a una clave criptográfica en vez de un evento

- **Estado:** Propuesto
- **Fecha:** 2026-10-05
- **Autor:** Dony Mollo
- **Revisores:** N/A

## Contexto

Hoy la biometría es un **evento**: en iOS `evaluatePolicy` devuelve un `Bool` y en Android llega `onAuthenticationSucceeded`. La app confía en ese booleano para dar acceso. En un equipo con jailbreak o root, una herramienta como Frida puede enganchar esas llamadas y devolver "éxito" sin que nadie haya puesto el dedo o la cara. OWASP MASVS-AUTH-2 pide autenticación local según las buenas prácticas de cada plataforma, y para una app bancaria eso significa que la biometría debe **desbloquear un secreto** guardado en hardware seguro (Secure Enclave en iOS, TEE o StrongBox en Android), no solo emitir un evento. ADR-0001 dejó anotada esta deuda.

## Decisión

Pasar de biometría por evento a **biometría ligada a criptografía** (crypto-bound): el secreto que habilita el login (por ejemplo un refresh token o una clave de dispositivo) solo se puede leer o usar después de una autenticación biométrica válida, verificada por el sistema operativo y no por nuestro código.

- **iOS:** guardar el secreto como ítem del Keychain protegido con `SecAccessControlCreateWithFlags`, accesibilidad `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` y la bandera `.biometryCurrentSet`. Leerlo con `SecItemCopyMatching` pasando un `LAContext` en `kSecUseAuthenticationContext`: el sistema muestra Face ID o Touch ID y solo entrega el dato si la biometría es válida. Con `.biometryCurrentSet`, agregar o quitar una huella o un rostro invalida el ítem.
- **Android:** generar una clave AES en el Android Keystore con `KeyGenParameterSpec.Builder`, `setUserAuthenticationRequired(true)` y `setInvalidatedByBiometricEnrollment(true)` (en API 30 o superior, además `setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)` para exigir autenticación en cada uso). Inicializar un `Cipher` con esa clave, envolverlo en `BiometricPrompt.CryptoObject` y llamar `authenticate(promptInfo, cryptoObject)`. El secreto se descifra con `result.cryptoObject?.cipher` dentro de `onAuthenticationSucceeded`. `CryptoObject` exige `BIOMETRIC_STRONG`, que ya es lo que pedimos.
- **Contrato:** se agrega una pieza nueva, `BiometricSecretStore`, con `store(secret)`, `unlock(reason)` e `invalidate()`. `unlock` devuelve el secreto o un `BiometricResult` de error, así la tabla de ADR-0001 se reutiliza. Se suma un caso nuevo, `keyInvalidated`, para cuando cambió el enrolamiento: en iOS el ítem ya no se puede leer (`errSecItemNotFound` o `errSecAuthFailed`) y en Android `Cipher.init` lanza `KeyPermanentlyInvalidatedException`. La política lo trata como `requirePin` y pide volver a activar la biometría.
- **Flutter:** el secreto no cruza a Dart si no es necesario. El plugin expone operaciones de alto nivel (desbloquear y usar el secreto en nativo) en vez de devolver los bytes.

## Alternativas consideradas

| Opción | Pros | Contras | Por qué no |
|---|---|---|---|
| Mantener biometría por evento (hoy) | Simple; ya funciona en las tres plataformas | Se salta con hooks en equipos con jailbreak o root; no sigue la buena práctica de MASVS-AUTH-2 | Riesgo inaceptable para banca |
| Evento + detección de jailbreak o root | Barato de agregar | La detección también se evade con las mismas herramientas; no ataca la causa | Complementa, no reemplaza |
| Ítem de Keychain y clave de Keystore protegidos por biometría (elegida) | El secreto solo sale del hardware seguro tras biometría válida; se invalida al cambiar el enrolamiento; no requiere cambios de backend | Más código nativo; hay que manejar invalidación y migración de usuarios actuales | Elegida |
| Clave privada en Secure Enclave o Keystore que firma un challenge del servidor | Máxima garantía: el secreto nunca sale del dispositivo y el backend verifica cada login | Requiere backend nuevo (registro de clave pública, endpoint de challenge) | Siguiente paso cuando el backend esté listo (ADR futuro) |

## Consecuencias

- **Positivas:** enganchar `evaluatePolicy` u `onAuthenticationSucceeded` ya no basta, porque sin biometría real no hay secreto; cambiar las huellas o rostros del equipo invalida la clave, lo que protege contra alguien que conoce el código del dispositivo y enrola su propia biometría; el diseño queda alineado con MASVS-AUTH-2 y es fácil de defender en una auditoría.
- **Negativas / deuda que aceptamos:** el contrato crece (`BiometricSecretStore`, caso `keyInvalidated`) y hay que actualizar las tablas de ADR-0001, el DTO de Pigeon y el plugin; los usuarios actuales necesitan una migración (primer login con PIN, luego activar biometría); Keychain y Keystore no se pueden probar en tests unitarios de JVM ni en `swift test`, así que hacen falta pruebas instrumentadas en simulador, emulador y equipos reales; algunos equipos Android tienen implementaciones de Keystore poco confiables, lo que exige monitorear errores en producción.
- **Qué nos haría revisar esta decisión:** que el backend pueda soportar challenge y respuesta (pasaríamos a la alternativa de firma), que Apple o Google cambien las APIs de Keychain o Keystore, o que passkeys cubran el caso de login.

## Referencias

- OWASP MASVS v2, MASVS-AUTH-2 (autenticación local) y las guías de autenticación local de OWASP MASTG para iOS y Android
- Apple: `SecAccessControlCreateWithFlags`, `SecAccessControlCreateFlags.biometryCurrentSet`, "Accessing Keychain Items with Face ID or Touch ID"
- Android: `KeyGenParameterSpec.Builder`, `BiometricPrompt.CryptoObject`, guía "Show a biometric authentication dialog" (sección de solución criptográfica)
- ADR-0001: contrato de resultado común
