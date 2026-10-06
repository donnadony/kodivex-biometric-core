/// API pública del plugin. Expone el mismo contrato que iOS y Android.
///
/// Para login usa [BiometricCore.runSession]: la política de reintentos y caída
/// a PIN vive en nativo (BiometricSession) y aquí solo llega la decisión.
library biometric_core_flutter;

import 'src/messages.g.dart';

enum BiometricType { face, fingerprint, none }

/// Mismo estado que BiometricAvailabilityStatus en iOS y Android.
enum BiometricAvailabilityStatus { available, notAvailable, notEnrolled, lockedOut }

sealed class BiometricResult {
  const BiometricResult();
  static BiometricResult fromDto(BiometricResultDto dto) => switch (dto.code) {
        'success' => const Success(),
        'cancelled' => const Cancelled(),
        'lockedOut' => const LockedOut(),
        'notAvailable' => const NotAvailable(),
        'notEnrolled' => const NotEnrolled(),
        'fallbackToPin' => const FallbackToPin(),
        _ => Failed(dto.reason ?? 'unknown'),
      };
}

class Success extends BiometricResult { const Success(); }
class Cancelled extends BiometricResult { const Cancelled(); }
class LockedOut extends BiometricResult { const LockedOut(); }
class NotAvailable extends BiometricResult { const NotAvailable(); }
class NotEnrolled extends BiometricResult { const NotEnrolled(); }
class FallbackToPin extends BiometricResult { const FallbackToPin(); }
class Failed extends BiometricResult {
  const Failed(this.reason);
  final String reason;
}

/// Espejo de BiometricPolicy.Decision. La decisión la toma la sesión nativa.
sealed class BiometricDecision {
  const BiometricDecision();
  static BiometricDecision fromDto(BiometricDecisionDto dto) => switch (dto.kind) {
        'grantAccess' => const GrantAccess(),
        'retry' => RetryPrompt(dto.remaining ?? 0),
        'requirePin' => RequirePin(dto.reason ?? ''),
        'showUnavailable' => ShowUnavailable(dto.reason ?? 'notAvailable'),
        // Fallamos cerrado: un valor desconocido nunca da acceso.
        _ => RequirePin('Decisión desconocida: ${dto.kind}'),
      };
}

class GrantAccess extends BiometricDecision { const GrantAccess(); }
/// Equivale a `retry(remaining)` en nativo. No se llama `Retry` para no chocar
/// con la anotación `Retry` de package:test.
class RetryPrompt extends BiometricDecision {
  const RetryPrompt(this.remaining);
  final int remaining;
}
class RequirePin extends BiometricDecision {
  const RequirePin(this.reason);
  final String reason;
}
class ShowUnavailable extends BiometricDecision {
  const ShowUnavailable(this.reason);
  /// `notAvailable` o `notEnrolled`.
  final String reason;
}

class BiometricAvailability {
  const BiometricAvailability({
    required this.type,
    required this.status,
  });
  final BiometricType type;
  final BiometricAvailabilityStatus status;

  /// Compatibilidad: hay biometría enrolada (aunque esté bloqueada).
  bool get isEnrolled =>
      status == BiometricAvailabilityStatus.available || status == BiometricAvailabilityStatus.lockedOut;

  /// Compatibilidad: el sistema bloqueó la biometría.
  bool get isLockedOut => status == BiometricAvailabilityStatus.lockedOut;

  bool get canAuthenticate => status == BiometricAvailabilityStatus.available && type != BiometricType.none;
}

class BiometricCore {
  BiometricCore({BiometricCoreHostApi? api}) : _api = api ?? BiometricCoreHostApi();
  final BiometricCoreHostApi _api;

  Future<BiometricAvailability> availability() async {
    final dto = await _api.availability();
    return BiometricAvailability(
      type: BiometricType.values.firstWhere(
        (t) => t.name == dto.type,
        orElse: () => BiometricType.none,
      ),
      status: BiometricAvailabilityStatus.values.firstWhere(
        (s) => s.name == dto.status,
        orElse: () => BiometricAvailabilityStatus.notAvailable,
      ),
    );
  }

  /// Prompt crudo, sin política. Para login usa [runSession].
  Future<BiometricResult> authenticate({
    required String reason,
    bool allowPinFallback = true,
  }) async {
    final dto = await _api.authenticate(reason, allowPinFallback);
    return BiometricResult.fromDto(dto);
  }

  /// Ejecuta un intento de la sesión nativa: revisa disponibilidad, lanza el prompt
  /// y aplica BiometricPolicy. Si devuelve [RetryPrompt], vuelve a llamarla; el contador
  /// se reinicia solo después de [GrantAccess] o [RequirePin].
  ///
  /// `maxAttempts` cuenta prompts, no lecturas del sensor. Cambiarlo entre
  /// llamadas inicia una sesión nueva.
  Future<BiometricDecision> runSession({
    required String reason,
    int maxAttempts = 3,
  }) async {
    final dto = await _api.runSession(reason, maxAttempts);
    return BiometricDecision.fromDto(dto);
  }

  /// Reinicia el contador de intentos de la sesión nativa (por ejemplo, al cerrar sesión).
  Future<void> resetSession() => _api.resetSession();
}
