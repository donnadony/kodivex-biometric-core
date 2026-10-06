package com.kodivex.biometric

import androidx.biometric.BiometricPrompt
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Una prueba por fila de la tabla "Resultado del prompt" de docs/spec/error-mapping.md (columna Android).
 * Las constantes ERROR_* son `static final int`, Kotlin las inlinea y no hace
 * falta Robolectric para probar el mapeo.
 */
class BiometricPromptAuthenticatorTest {
    private fun map(code: Int, allowPinFallback: Boolean = true, message: String = "msg") =
        BiometricPromptAuthenticator.map(code, message, allowPinFallback)

    @Test fun negativeButtonWithPinFallbackMapsToFallbackToPin() {
        assertEquals(BiometricResult.FallbackToPin, map(BiometricPrompt.ERROR_NEGATIVE_BUTTON, allowPinFallback = true))
    }

    @Test fun negativeButtonWithoutPinFallbackMapsToCancelled() {
        assertEquals(BiometricResult.Cancelled, map(BiometricPrompt.ERROR_NEGATIVE_BUTTON, allowPinFallback = false))
    }

    @Test fun cancelCodesMapToCancelled() {
        for (pin in listOf(true, false)) {
            assertEquals(BiometricResult.Cancelled, map(BiometricPrompt.ERROR_USER_CANCELED, pin))
            assertEquals(BiometricResult.Cancelled, map(BiometricPrompt.ERROR_CANCELED, pin))
        }
    }

    @Test fun lockoutCodesMapToLockedOut() {
        assertEquals(BiometricResult.LockedOut, map(BiometricPrompt.ERROR_LOCKOUT))
        assertEquals(BiometricResult.LockedOut, map(BiometricPrompt.ERROR_LOCKOUT_PERMANENT))
    }

    @Test fun noBiometricsMapsToNotEnrolled() {
        assertEquals(BiometricResult.NotEnrolled, map(BiometricPrompt.ERROR_NO_BIOMETRICS))
    }

    @Test fun hardwareCodesMapToNotAvailable() {
        assertEquals(BiometricResult.NotAvailable, map(BiometricPrompt.ERROR_HW_NOT_PRESENT))
        assertEquals(BiometricResult.NotAvailable, map(BiometricPrompt.ERROR_HW_UNAVAILABLE))
        assertEquals(BiometricResult.NotAvailable, map(BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED))
    }

    @Test fun otherCodesMapToFailedWithCodeAndMessage() {
        assertEquals(
            BiometricResult.Failed("BiometricPrompt error ${BiometricPrompt.ERROR_TIMEOUT}: Tiempo agotado"),
            map(BiometricPrompt.ERROR_TIMEOUT, message = "Tiempo agotado"),
        )
        for (code in listOf(
            BiometricPrompt.ERROR_UNABLE_TO_PROCESS,
            BiometricPrompt.ERROR_NO_SPACE,
            BiometricPrompt.ERROR_VENDOR,
            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
        )) {
            assertEquals(BiometricResult.Failed("BiometricPrompt error $code: msg"), map(code))
        }
    }
}
