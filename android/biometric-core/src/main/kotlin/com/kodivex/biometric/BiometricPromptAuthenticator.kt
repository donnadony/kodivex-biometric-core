package com.kodivex.biometric

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Implementación Android del contrato usando androidx.biometric.
 * Traduce los códigos de BiometricPrompt al BiometricResult común (tabla "Resultado del prompt" en docs/spec/error-mapping.md).
 */
class BiometricPromptAuthenticator(
    private val activityProvider: () -> FragmentActivity,
) : BiometricAuthenticator {

    override fun availability(): BiometricAvailability {
        val activity = activityProvider()
        val manager = BiometricManager.from(activity)
        val status = manager.canAuthenticate(BIOMETRIC_STRONG)

        // Android no distingue face/fingerprint de forma pública y estable; se reporta por features.
        // Preferimos huella sobre rostro: en muchos equipos el rostro es Clase 2 (débil) y
        // nosotros pedimos BIOMETRIC_STRONG, así que si hay ambos el prompt casi siempre
        // terminará usando la huella. Reportar FACE ahí sería engañoso para la UI.
        val pm = activity.packageManager
        val type = when {
            pm.hasSystemFeature("android.hardware.fingerprint") -> BiometricType.FINGERPRINT
            pm.hasSystemFeature("android.hardware.biometrics.face") -> BiometricType.FACE
            else -> BiometricType.NONE
        }

        // BiometricManager no informa bloqueo: LOCKED_OUT llega después, como ERROR_LOCKOUT del prompt.
        return when (status) {
            BiometricManager.BIOMETRIC_SUCCESS ->
                BiometricAvailability(type, BiometricAvailabilityStatus.AVAILABLE)
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED ->
                BiometricAvailability(type, BiometricAvailabilityStatus.NOT_ENROLLED)
            // Sin hardware de Clase 3: lo que haya (por ejemplo rostro débil) no nos sirve.
            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE ->
                BiometricAvailability(BiometricType.NONE, BiometricAvailabilityStatus.NOT_AVAILABLE)
            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE,
            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED,
            BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED,
            BiometricManager.BIOMETRIC_STATUS_UNKNOWN ->
                BiometricAvailability(type, BiometricAvailabilityStatus.NOT_AVAILABLE)
            // Cualquier código nuevo que no conozcamos: fallamos cerrado, nunca "disponible".
            else -> BiometricAvailability(type, BiometricAvailabilityStatus.NOT_AVAILABLE)
        }
    }

    override suspend fun authenticate(reason: String, allowPinFallback: Boolean): BiometricResult =
        suspendCancellableCoroutine { cont ->
            val activity = activityProvider()
            val executor = ContextCompat.getMainExecutor(activity)

            val callback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    if (cont.isActive) cont.resume(BiometricResult.Success)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (cont.isActive) cont.resume(map(errorCode, errString.toString(), allowPinFallback))
                }

                // onAuthenticationFailed = intento no reconocido; el prompt sigue abierto.
                // No resolvemos aquí: el usuario puede reintentar dentro del mismo prompt.
            }

            val prompt = BiometricPrompt(activity, executor, callback)
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Verifica tu identidad")
                .setSubtitle(reason)
                .setNegativeButtonText(if (allowPinFallback) "Usar PIN" else "Cancelar")
                .setAllowedAuthenticators(BIOMETRIC_STRONG)
                .setConfirmationRequired(false)
                .build()

            prompt.authenticate(info)
            cont.invokeOnCancellation { prompt.cancelAuthentication() }
        }

    companion object {
        internal fun map(code: Int, message: String, allowPinFallback: Boolean): BiometricResult = when (code) {
            BiometricPrompt.ERROR_NEGATIVE_BUTTON ->
                if (allowPinFallback) BiometricResult.FallbackToPin else BiometricResult.Cancelled
            BiometricPrompt.ERROR_USER_CANCELED,
            BiometricPrompt.ERROR_CANCELED -> BiometricResult.Cancelled
            BiometricPrompt.ERROR_LOCKOUT,
            BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> BiometricResult.LockedOut
            BiometricPrompt.ERROR_NO_BIOMETRICS -> BiometricResult.NotEnrolled
            BiometricPrompt.ERROR_HW_NOT_PRESENT,
            BiometricPrompt.ERROR_HW_UNAVAILABLE,
            BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED -> BiometricResult.NotAvailable
            else -> BiometricResult.Failed("BiometricPrompt error $code: $message")
        }
    }
}
