---
status: aceptado
date: 2026-10-05
decision-makers: Dony Mollo
consulted: N/A
---

# ADR-0001: Un contrato de resultado común para biometría en iOS, Android y Flutter

> **En resumen:** En el contexto de una app bancaria con login biométrico en iOS, Android y una futura app Flutter, frente a APIs nativas que reportan errores y bloqueos de forma distinta, decidimos un contrato común con resultado cerrado y la política de negocio en código nativo (expuesta a Flutter vía Pigeon) para escribir y testear la lógica de reintentos y caída a PIN una sola vez por plataforma, aceptando mantener dos implementaciones del contrato hasta moverlo a KMP.
>
> **TL;DR (EN):** One closed result contract for biometrics across iOS, Android and Flutter; business policy stays native and Flutter consumes it through Pigeon instead of reimplementing it.

## Contexto y problema

Una app bancaria necesita login biométrico con el mismo comportamiento en iOS y Android, y una futura app secundaria en Flutter reutilizará la misma funcionalidad. `LocalAuthentication` (iOS) y `BiometricPrompt` (Android) exponen errores, fallbacks y políticas de bloqueo distintas. Si cada app interpreta esos errores por su cuenta, la lógica de negocio (reintentos, caída a PIN, mensajes) se duplica y diverge.

## Criterios de decisión

- La política de reintentos y caída a PIN se escribe y se testea una sola vez por plataforma nativa.
- Las UIs (SwiftUI, Compose, Flutter) no conocen `LAError` ni códigos de `BiometricPrompt`.
- Sin dependencias de terceros en un flujo de seguridad: tiene que poder defenderse en una auditoría bancaria.
- Costo de mantenimiento proporcional a un equipo pequeño.

## Opciones consideradas

1. Cada app maneja los errores nativos directamente.
2. Flutter como única implementación, con un plugin de terceros.
3. Contrato común nativo, pero Flutter recibe solo `authenticate` y escribe su propia política.
4. Contrato común nativo con la política expuesta a Flutter.

## Decisión

**Opción elegida: "Contrato común nativo con la política expuesta a Flutter"**, porque es la única que cumple el primer criterio en los tres consumidores sin agregar dependencias externas.

**Confianza:** alta. El contrato es pequeño (siete resultados y cuatro estados de disponibilidad) y ya está implementado y testeado en ambas plataformas.

En concreto:

- `BiometricAuthenticator` es el contrato. Devuelve un `BiometricResult` cerrado y un `BiometricAvailabilityStatus` cerrado.
- `BiometricPolicy` contiene la lógica de negocio y `BiometricSession` orquesta autenticador y política.
- Cada plataforma traduce sus errores nativos a los valores comunes. El mapeo fila por fila es normativo y vive en la especificación [`docs/spec/error-mapping.md`](../spec/error-mapping.md), no en este ADR.
- Flutter llama a `runSession`, que ejecuta la `BiometricSession` nativa y devuelve la decisión ya tomada (`grantAccess`, `retry`, `requirePin` o `showUnavailable`). `authenticate` queda como prompt crudo para casos especiales.
- `maxAttempts` cuenta **prompts**, no lecturas del sensor: cada prompt del sistema ya reintenta internamente antes de devolver error. La sesión reinicia el contador sola después de una decisión terminal (`grantAccess` o `requirePin`); `reset()` queda para casos explícitos como cerrar sesión.

### Consecuencias

- **Buenas:** la política se escribe una vez por plataforma y Flutter la consume sin duplicarla; los consumidores no conocen códigos nativos; el mapeo queda versionado en una especificación con tests.
- **Malas / deuda que aceptamos:** `BiometricPolicy` existe en Swift y en Kotlin por separado (duplicación controlada; plan: moverla a Kotlin Multiplatform en un ADR futuro). La caída a PIN es un fallback a credencial no biométrica: aceptable para login, no para transacciones sensibles (OWASP MASWE-0021). La biometría sigue siendo un evento (booleano) y no un secreto criptográfico: se aborda en [ADR-0002](0002-crypto-bound-biometrics.md).
- **Qué nos haría revisar esta decisión:** que Apple o Google expongan un estado que no mapee limpiamente, o que el módulo KMP resulte más costoso de mantener que la duplicación.

### Confirmación

- **iOS:** `LocalAuthenticationAuthenticatorTests` cubre cada fila de las dos tablas de la especificación (por ejemplo `testCancelCodesMapToCancelled` y `testUnknownOrForeignErrorsAreNotAvailable`). `BiometricPolicyTests` cubre la política y el reinicio de la sesión (`testSessionAutoResetsAfterRequirePin`).
- **Android:** `BiometricPromptAuthenticatorTest` cubre la tabla de resultados del prompt. `BiometricPolicyTest` cubre la política, la sesión y que los códigos de estado coinciden con iOS (`statusCodesMatchIos`). La tabla de disponibilidad (`BiometricManager`) todavía no tiene test unitario porque depende del SDK; pendiente extraer el mapeo a una función pura.
- Los dos jobs de CI (`swift test` y `gradle :biometric-core:test`) corren en cada push y PR.

## Pros y contras de las opciones

### Cada app maneja los errores nativos

- Bien, porque no hay abstracción y el control es máximo.
- Mal, porque la lógica se duplica y diverge, y Flutter tendría que conocer ambos SDK. No escala a tres consumidores.

### Flutter como única implementación (plugin de terceros)

- Bien, porque hay un solo código.
- Mal, porque mete una dependencia externa en un flujo de seguridad y las apps nativas existentes no lo usarían.

### Flutter solo recibe `authenticate`

- Bien, porque el plugin es más simple.
- Mal, porque la política se escribiría una tercera vez, en Dart.

### Contrato común con la política expuesta a Flutter (elegida)

- Bien, porque la lógica de negocio se escribe una vez, es auditable y es nativa donde importa.
- Mal, porque hay que mantener dos implementaciones del contrato (costo aceptable: el contrato es pequeño).

## Más información

- Especificación del mapeo: [`docs/spec/error-mapping.md`](../spec/error-mapping.md)
- OWASP MASVS v2, [MASVS-AUTH-2](https://mas.owasp.org/MASVS/controls/MASVS-AUTH-2/) (autenticación local) y [MASWE-0021](https://mas.owasp.org/MASWE/MASVS-AUTH/MASWE-0021/) (fallback a credencial no biométrica)
- Apple: [`LAError`](https://developer.apple.com/documentation/localauthentication/laerror-swift.struct), `LAContext.canEvaluatePolicy(_:error:)`
- AndroidX: [`BiometricPrompt`](https://developer.android.com/reference/androidx/biometric/BiometricPrompt), [`BiometricManager`](https://developer.android.com/reference/androidx/biometric/BiometricManager)
- Siguiente: [ADR-0002](0002-crypto-bound-biometrics.md), biometría ligada a criptografía
