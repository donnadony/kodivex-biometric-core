---
status: propuesto
date: 2026-10-05
decision-makers: Dony Mollo
consulted: N/A
---

# ADR-0002: Ligar la biometría a una clave criptográfica en vez de un evento

> **En resumen:** En el contexto del login biométrico de una app bancaria, frente a que hoy la biometría es un booleano que se puede falsear con hooks en equipos con jailbreak o root, decidimos guardar el secreto de login en Keychain y Keystore protegido por biometría fuerte y autenticación en cada uso para que el secreto solo salga del hardware seguro tras una biometría verificada por el sistema operativo, aceptando más código nativo, una migración de usuarios y pruebas en equipo real.
>
> **TL;DR (EN):** Move from event-based to crypto-bound biometrics: the login secret lives in Keychain/Keystore and is released only after OS-verified strong biometrics, per use.

## Contexto y problema

Hoy la biometría es un **evento**: en iOS `evaluatePolicy` devuelve un `Bool` y en Android llega `onAuthenticationSucceeded`. La app confía en ese booleano para dar acceso. En un equipo con jailbreak o root, una herramienta como Frida puede enganchar esas llamadas y devolver "éxito" sin que nadie haya puesto el dedo o la cara. OWASP lo cataloga como [MASWE-0020](https://mas.owasp.org/MASWE/MASVS-AUTH/MASWE-0020/) ("Local Authentication Can Be Bypassed"), y la buena práctica [MASTG-BEST-0036](https://mas.owasp.org/MASTG/best-practices/MASTG-BEST-0036/) es que la biometría desbloquee material criptográfico en hardware seguro. [ADR-0001](0001-shared-contract.md) dejó anotada esta deuda.

## Criterios de decisión

- Sin biometría real no debe haber acceso, aunque nuestro código esté enganchado.
- Cambiar el enrolamiento del equipo (agregar una huella o un rostro) debe invalidar el acceso ([MASWE-0022](https://mas.owasp.org/MASWE/MASVS-AUTH/MASWE-0022/)).
- Implementable hoy, sin cambios de backend.
- Encaja en el contrato de ADR-0001 sin romper a los consumidores actuales.

## Opciones consideradas

1. Mantener la biometría por evento.
2. Evento más detección de jailbreak o root.
3. Secreto en Keychain / Keystore protegido por biometría, autenticación en cada uso.
4. Igual que 3, pero con ventana de validez (la clave queda usable N segundos tras autenticar).
5. Clave asimétrica en Secure Enclave / Keystore que firma un challenge del servidor.
6. Passkeys (FIDO2 / WebAuthn).

## Decisión

**Opción elegida: "Secreto protegido por biometría, autenticación en cada uso"**, porque es la única que cumple los cuatro criterios: sube la barrera contra hooks, se invalida al cambiar el enrolamiento y no requiere backend nuevo.

**Confianza:** media. Las APIs están documentadas y probadas por la industria, pero falta un spike en equipos reales (en especial Android de gama baja) antes de aceptar el ADR.

En concreto:

- **iOS:** ítem de Keychain con `.biometryCurrentSet` y accesibilidad `WhenPasscodeSetThisDeviceOnly`; un `LAContext` nuevo en cada lectura.
- **Android:** clave AES en Keystore que exige `BIOMETRIC_STRONG` en cada uso e invalida con nuevo enrolamiento; se usa vía `BiometricPrompt.CryptoObject`.
- **Contrato:** pieza nueva `BiometricSecretStore` (`store`, `unlock`, `invalidate`) y un resultado nuevo `keyInvalidated`, que la política trata como `requirePin` más reactivar biometría.
- **Flutter:** el secreto no cruza a Dart; el plugin expone operaciones de alto nivel.

El detalle de APIs, errores por plataforma y casos borde está en la nota de diseño [`docs/design/crypto-bound-biometrics.md`](../design/crypto-bound-biometrics.md).

### Consecuencias

- **Buenas:** enganchar `evaluatePolicy` u `onAuthenticationSucceeded` ya no basta, porque sin biometría real el sistema no entrega el secreto; cambiar las huellas o rostros invalida la clave, lo que protege contra alguien que conoce el código del dispositivo y enrola su propia biometría; queda alineado con MASTG-BEST-0036 y 0037.
- **Malas / deuda que aceptamos:**
  - **Sube la barrera, no da inmunidad:** tras un unlock legítimo el secreto está en memoria de la app, y en un equipo comprometido se puede leer o se puede enganchar la lógica posterior. Mitigación parcial: mantener el secreto en nativo el menor tiempo posible.
  - El contrato crece (`BiometricSecretStore`, `keyInvalidated`) y hay que actualizar la especificación de errores, el DTO de Pigeon y el plugin.
  - Usuarios actuales necesitan migración: primer login con PIN y luego activar la biometría.
  - Keychain y Keystore no se prueban en `swift test` ni en tests de JVM: hacen falta pruebas instrumentadas y en equipos reales.
  - Algunos equipos Android tienen Keystore poco confiable: hay que monitorear errores en producción.
- **Qué nos haría revisar esta decisión:** que el backend soporte challenge y respuesta (pasaríamos a la opción 5), que passkeys cubran el login de la app, o que Apple o Google cambien las APIs de Keychain o Keystore.

### Confirmación

Antes de pasar a **aceptado**:

1. Spike en iOS (simulador más un equipo con Face ID) y Android (un equipo con StrongBox y uno de gama baja) que pruebe store, unlock, cancelación e invalidación al agregar una huella.
2. Repasar los tests de OWASP MASTG que aplican: [MASTG-TEST-0266 a 0271](https://mas.owasp.org/MASTG/tests/) en iOS y 0326 a 0330 en Android.
3. Revisión por pares del ADR y de la nota de diseño.

Una vez implementado: tests instrumentados en CI para el flujo de invalidación y una fila nueva en la especificación de errores por cada caso agregado.

## Pros y contras de las opciones

### Biometría por evento (hoy)

- Bien, porque es simple y ya funciona en las tres plataformas.
- Mal, porque se salta con hooks en equipos con jailbreak o root (MASWE-0020). Riesgo inaceptable para banca.

### Evento más detección de jailbreak o root

- Bien, porque es barato de agregar.
- Mal, porque la detección se evade con las mismas herramientas y no ataca la causa. Complementa, no reemplaza. Algo similar aplica a App Attest y Play Integrity: suman verificación del lado del servidor, pero no ligan la biometría a nada.

### Secreto protegido por biometría, autenticación en cada uso (elegida)

- Bien, porque el secreto solo sale del hardware seguro tras biometría válida, se invalida al cambiar el enrolamiento y no requiere backend.
- Mal, porque implica más código nativo, migración de usuarios y que el secreto termina en memoria de la app.

### Igual, pero con ventana de validez

- Bien, porque permite varias operaciones con un solo prompt.
- Mal, porque durante la ventana la clave se usa sin biometría; OWASP (MASTG-TEST-0330) marca las ventanas largas como hallazgo, y con `AUTH_DEVICE_CREDENTIAL` la clave deja de invalidarse por enrolamiento.

### Clave asimétrica que firma un challenge del servidor

- Bien, porque es la máxima garantía: la clave privada nunca sale del chip y el backend verifica cada login (con Key Attestation en Android, incluso que la clave vive en hardware).
- Mal, porque requiere backend nuevo (registro de clave pública y endpoint de challenge). Siguiente paso cuando el backend esté listo (ADR futuro).

### Passkeys (FIDO2 / WebAuthn)

- Bien, porque es estándar, resistente a phishing y sincronizable entre equipos.
- Mal, porque reemplaza el modelo de login completo (backend WebAuthn, recuperación de cuenta) y la sincronización entre equipos choca con la política bancaria de "solo este dispositivo". Se reevalúa junto con la opción anterior.

## Más información

- Nota de diseño: [`docs/design/crypto-bound-biometrics.md`](../design/crypto-bound-biometrics.md)
- OWASP: [MASVS-AUTH-2](https://mas.owasp.org/MASVS/controls/MASVS-AUTH-2/), [MASWE-0020](https://mas.owasp.org/MASWE/MASVS-AUTH/MASWE-0020/), [MASWE-0022](https://mas.owasp.org/MASWE/MASVS-AUTH/MASWE-0022/), [MASTG-BEST-0036](https://mas.owasp.org/MASTG/best-practices/MASTG-BEST-0036/)
- Apple: [Accessing Keychain Items with Face ID or Touch ID](https://developer.apple.com/documentation/localauthentication/accessing-keychain-items-with-face-id-or-touch-id), [Keychain data protection](https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web)
- Android: [Show a biometric authentication dialog](https://developer.android.com/identity/sign-in/biometric-auth), [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- Anterior: [ADR-0001](0001-shared-contract.md), contrato de resultado común
