package com.kodivex.biometric

/**
 * Resultado común de una autenticación biométrica. Mismo contrato que
 * ios/BiometricCore (ver docs/adr/0001-shared-contract.md).
 */
sealed class BiometricResult(val code: String) {
    data object Success : BiometricResult("success")
    data object Cancelled : BiometricResult("cancelled")
    data object LockedOut : BiometricResult("lockedOut")
    data object NotAvailable : BiometricResult("notAvailable")
    data object NotEnrolled : BiometricResult("notEnrolled")
    data object FallbackToPin : BiometricResult("fallbackToPin")
    data class Failed(val reason: String) : BiometricResult("failed")
}

enum class BiometricType { FACE, FINGERPRINT, NONE }

/**
 * Estado de la biometría antes de lanzar el prompt. `code` es el valor estable
 * que viaja a Flutter (mismo valor que el rawValue en iOS).
 */
enum class BiometricAvailabilityStatus(val code: String) {
    /** Hay biometría enrolada y lista para usarse. */
    AVAILABLE("available"),
    /** No hay hardware, está ocupado, falta un parche de seguridad o el estado es desconocido. */
    NOT_AVAILABLE("notAvailable"),
    /** Hay hardware pero no hay biometría enrolada. */
    NOT_ENROLLED("notEnrolled"),
    /** El sistema bloqueó la biometría por demasiados intentos fallidos. */
    LOCKED_OUT("lockedOut"),
}

data class BiometricAvailability(
    val type: BiometricType,
    val status: BiometricAvailabilityStatus,
) {
    /**
     * Constructor anterior, se mantiene por compatibilidad. Deduce `status`
     * a partir de los booleanos; el código nuevo debería pasar `status` directo.
     */
    constructor(type: BiometricType, isEnrolled: Boolean, isLockedOut: Boolean) :
        this(type, statusFromFlags(type, isEnrolled, isLockedOut))

    /** Compatibilidad: hay biometría enrolada (aunque esté bloqueada). */
    val isEnrolled: Boolean
        get() = status == BiometricAvailabilityStatus.AVAILABLE || status == BiometricAvailabilityStatus.LOCKED_OUT

    /** Compatibilidad: el sistema bloqueó la biometría. */
    val isLockedOut: Boolean get() = status == BiometricAvailabilityStatus.LOCKED_OUT

    val canAuthenticate: Boolean
        get() = status == BiometricAvailabilityStatus.AVAILABLE && type != BiometricType.NONE
}

private fun statusFromFlags(type: BiometricType, isEnrolled: Boolean, isLockedOut: Boolean) = when {
    isLockedOut -> BiometricAvailabilityStatus.LOCKED_OUT
    !isEnrolled -> BiometricAvailabilityStatus.NOT_ENROLLED
    type == BiometricType.NONE -> BiometricAvailabilityStatus.NOT_AVAILABLE
    else -> BiometricAvailabilityStatus.AVAILABLE
}

/** Contrato que toda implementación nativa debe cumplir. */
interface BiometricAuthenticator {
    fun availability(): BiometricAvailability
    suspend fun authenticate(reason: String, allowPinFallback: Boolean): BiometricResult
}
