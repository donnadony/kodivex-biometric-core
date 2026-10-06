package com.kodivex.biometric

/**
 * Lógica de negocio sobre el contrato. Espejo de BiometricPolicy.swift.
 *
 * `maxAttempts` cuenta prompts, no lecturas del sensor: cada prompt del sistema
 * ya permite varios intentos internos antes de devolver un error (ver ADR-0001).
 *
 * Semana 7 del plan: pasa a Kotlin Multiplatform y iOS la consume desde `shared/`.
 */
class BiometricPolicy(maxAttempts: Int = 3) {
    val maxAttempts: Int = maxOf(1, maxAttempts)

    sealed class Decision(val kind: String) {
        data object GrantAccess : Decision("grantAccess")
        data class Retry(val remaining: Int) : Decision("retry")
        data class RequirePin(val reason: String) : Decision("requirePin")
        data class ShowUnavailable(val reason: String) : Decision("showUnavailable")

        /**
         * Decisión que cierra el flujo biométrico. Después de ella la sesión
         * vuelve a contar intentos desde cero.
         */
        val isTerminal: Boolean get() = this is GrantAccess || this is RequirePin
    }

    fun decide(result: BiometricResult, attempt: Int): Decision = when (result) {
        BiometricResult.Success -> Decision.GrantAccess
        BiometricResult.FallbackToPin -> Decision.RequirePin("El usuario eligió PIN")
        BiometricResult.LockedOut -> Decision.RequirePin("Biometría bloqueada por el sistema")
        BiometricResult.NotAvailable, BiometricResult.NotEnrolled -> Decision.ShowUnavailable(result.code)
        BiometricResult.Cancelled -> Decision.RequirePin("Cancelado por el usuario")
        is BiometricResult.Failed -> {
            val remaining = maxAttempts - attempt
            if (remaining > 0) Decision.Retry(remaining) else Decision.RequirePin("Se agotaron los intentos")
        }
    }
}

/** Orquesta autenticador + política. Es lo que la UI (Compose) y el plugin de Flutter consumen. */
class BiometricSession(
    private val authenticator: BiometricAuthenticator,
    private val policy: BiometricPolicy = BiometricPolicy(),
) {
    private var attempt = 0

    suspend fun run(reason: String): BiometricPolicy.Decision {
        val availability = authenticator.availability()
        if (!availability.canAuthenticate) {
            return finish(shortCircuit(availability))
        }
        attempt += 1
        val result = authenticator.authenticate(reason, allowPinFallback = true)
        return finish(policy.decide(result, attempt))
    }

    fun reset() { attempt = 0 }

    /**
     * Reinicia el contador después de una decisión terminal (GrantAccess o RequirePin),
     * así el siguiente login vuelve a tener todos sus intentos.
     */
    private fun finish(decision: BiometricPolicy.Decision): BiometricPolicy.Decision {
        if (decision.isTerminal) attempt = 0
        return decision
    }

    /**
     * Decisión cuando no tiene sentido lanzar el prompt. Usa `status`, no los
     * booleanos, para no confundir "no disponible" con "no enrolado".
     */
    private fun shortCircuit(availability: BiometricAvailability): BiometricPolicy.Decision =
        when (availability.status) {
            BiometricAvailabilityStatus.LOCKED_OUT ->
                BiometricPolicy.Decision.RequirePin("Biometría bloqueada")
            BiometricAvailabilityStatus.NOT_ENROLLED ->
                BiometricPolicy.Decision.ShowUnavailable(BiometricAvailabilityStatus.NOT_ENROLLED.code)
            // AVAILABLE solo llega aquí si el tipo es NONE: no hay biometría utilizable.
            BiometricAvailabilityStatus.NOT_AVAILABLE,
            BiometricAvailabilityStatus.AVAILABLE ->
                BiometricPolicy.Decision.ShowUnavailable(BiometricAvailabilityStatus.NOT_AVAILABLE.code)
        }
}
