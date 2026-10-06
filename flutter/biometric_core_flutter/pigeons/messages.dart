// Contrato Dart <-> nativo. Regenerar con:
//   dart run pigeon --input pigeons/messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  // Layout de Swift Package Manager para plugins (el podspec apunta a la misma carpeta).
  swiftOut: 'ios/biometric_core_flutter/Sources/biometric_core_flutter/Messages.g.swift',
  kotlinOut: 'android/src/main/kotlin/com/kodivex/biometric/flutter/Messages.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.kodivex.biometric.flutter'),
))

/// Espejo de BiometricResult.code. Se transporta como string para no acoplar
/// el enum de Dart al orden de los enums nativos.
class BiometricResultDto {
  BiometricResultDto({required this.code, this.reason});
  String code; // success | cancelled | lockedOut | notAvailable | notEnrolled | fallbackToPin | failed
  String? reason;
}

class BiometricAvailabilityDto {
  BiometricAvailabilityDto({
    required this.type,
    required this.status,
    required this.isEnrolled,
    required this.isLockedOut,
  });
  String type; // face | fingerprint | none
  String status; // available | notAvailable | notEnrolled | lockedOut
  // Se mantienen por compatibilidad; se derivan de `status` en nativo.
  bool isEnrolled;
  bool isLockedOut;
}

/// Espejo de BiometricPolicy.Decision. La política vive en nativo: Flutter solo
/// recibe la decisión ya tomada.
class BiometricDecisionDto {
  BiometricDecisionDto({required this.kind, this.remaining, this.reason});
  String kind; // grantAccess | retry | requirePin | showUnavailable
  int? remaining; // solo en retry
  String? reason; // solo en requirePin y showUnavailable
}

@HostApi()
abstract class BiometricCoreHostApi {
  BiometricAvailabilityDto availability();

  /// Prompt crudo, sin política. Útil para casos especiales; para login usar runSession.
  @async
  BiometricResultDto authenticate(String reason, bool allowPinFallback);

  /// Ejecuta un intento de BiometricSession nativo (disponibilidad, prompt y política).
  @async
  BiometricDecisionDto runSession(String reason, int maxAttempts);

  /// Reinicia el contador de intentos de la sesión nativa.
  void resetSession();
}
