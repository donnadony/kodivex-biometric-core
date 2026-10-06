package com.kodivex.biometric.flutter

import androidx.fragment.app.FragmentActivity
import com.kodivex.biometric.BiometricPolicy
import com.kodivex.biometric.BiometricPromptAuthenticator
import com.kodivex.biometric.BiometricResult
import com.kodivex.biometric.BiometricSession
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch

/**
 * Adapta biometric-core al HostApi generado por Pigeon (Messages.g.kt).
 * Requiere que la Activity de Flutter extienda FlutterFragmentActivity.
 *
 * La política (reintentos, caída a PIN) vive en BiometricSession: Flutter solo
 * recibe la decisión ya tomada, no la reimplementa (ADR-0001).
 */
class BiometricCoreFlutterPlugin : FlutterPlugin, ActivityAware, BiometricCoreHostApi {
    private var activity: FragmentActivity? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** Sesión nativa que guarda el contador de intentos. Solo se usa en el hilo principal. */
    private var session: BiometricSession? = null
    private var sessionMaxAttempts: Int? = null

    private val authenticator by lazy {
        BiometricPromptAuthenticator {
            activity ?: error("Activity no disponible. Usa FlutterFragmentActivity.")
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BiometricCoreHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BiometricCoreHostApi.setUp(binding.binaryMessenger, null)
        // Cancelamos solo las corrutinas en curso. `scope.cancel()` dejaría el scope
        // inservible si el engine se vuelve a adjuntar a esta misma instancia.
        scope.coroutineContext.cancelChildren()
        session = null
        sessionMaxAttempts = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }
    override fun onDetachedFromActivity() { activity = null }

    override fun availability(): BiometricAvailabilityDto {
        val a = authenticator.availability()
        return BiometricAvailabilityDto(
            type = a.type.name.lowercase(),
            status = a.status.code,
            isEnrolled = a.isEnrolled,
            isLockedOut = a.isLockedOut,
        )
    }

    override fun authenticate(
        reason: String,
        allowPinFallback: Boolean,
        callback: (Result<BiometricResultDto>) -> Unit,
    ) {
        scope.launch {
            val result = authenticator.authenticate(reason, allowPinFallback)
            val dto = BiometricResultDto(
                code = result.code,
                reason = (result as? BiometricResult.Failed)?.reason,
            )
            callback(Result.success(dto))
        }
    }

    override fun runSession(
        reason: String,
        maxAttempts: Long,
        callback: (Result<BiometricDecisionDto>) -> Unit,
    ) {
        val current = currentSession(maxAttempts.toInt())
        scope.launch {
            callback(Result.success(current.run(reason).toDto()))
        }
    }

    override fun resetSession() {
        // Misma semántica que en iOS: descartamos la sesión y la próxima runSession
        // empieza con el contador en cero.
        session = null
        sessionMaxAttempts = null
    }

    /** Reutiliza la sesión mientras `maxAttempts` no cambie; si cambia, empieza una nueva. */
    private fun currentSession(maxAttempts: Int): BiometricSession {
        val existing = session
        if (existing != null && sessionMaxAttempts == maxAttempts) return existing
        return BiometricSession(authenticator, BiometricPolicy(maxAttempts)).also {
            session = it
            sessionMaxAttempts = maxAttempts
        }
    }
}

internal fun BiometricPolicy.Decision.toDto(): BiometricDecisionDto = when (this) {
    BiometricPolicy.Decision.GrantAccess -> BiometricDecisionDto(kind = kind)
    is BiometricPolicy.Decision.Retry -> BiometricDecisionDto(kind = kind, remaining = remaining.toLong())
    is BiometricPolicy.Decision.RequirePin -> BiometricDecisionDto(kind = kind, reason = reason)
    is BiometricPolicy.Decision.ShowUnavailable -> BiometricDecisionDto(kind = kind, reason = reason)
}
