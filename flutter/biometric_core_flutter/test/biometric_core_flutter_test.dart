import 'package:biometric_core_flutter/biometric_core_flutter.dart';
import 'package:biometric_core_flutter/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

/// HostApi falso: evita platform channels y devuelve DTOs predefinidos.
class FakeHostApi extends BiometricCoreHostApi {
  FakeHostApi({this.availabilityDto, List<BiometricDecisionDto>? decisions})
      : decisions = decisions ?? [];

  BiometricAvailabilityDto? availabilityDto;
  final List<BiometricDecisionDto> decisions;
  final List<int> maxAttemptsSeen = [];
  int resetCalls = 0;

  @override
  Future<BiometricAvailabilityDto> availability() async => availabilityDto!;

  @override
  Future<BiometricDecisionDto> runSession(String reason, int maxAttempts) async {
    maxAttemptsSeen.add(maxAttempts);
    return decisions.removeAt(0);
  }

  @override
  Future<void> resetSession() async => resetCalls++;
}

void main() {
  group('BiometricDecision.fromDto', () {
    test('mapea cada kind del contrato', () {
      expect(BiometricDecision.fromDto(BiometricDecisionDto(kind: 'grantAccess')), isA<GrantAccess>());
      expect(
        (BiometricDecision.fromDto(BiometricDecisionDto(kind: 'retry', remaining: 2)) as RetryPrompt).remaining,
        2,
      );
      expect(
        (BiometricDecision.fromDto(BiometricDecisionDto(kind: 'requirePin', reason: 'x')) as RequirePin).reason,
        'x',
      );
      expect(
        (BiometricDecision.fromDto(BiometricDecisionDto(kind: 'showUnavailable', reason: 'notEnrolled'))
                as ShowUnavailable)
            .reason,
        'notEnrolled',
      );
    });

    test('un kind desconocido nunca da acceso', () {
      expect(BiometricDecision.fromDto(BiometricDecisionDto(kind: 'otro')), isA<RequirePin>());
    });
  });

  group('BiometricCore', () {
    test('availability usa status y no los booleanos', () async {
      final core = BiometricCore(
        api: FakeHostApi(
          availabilityDto: BiometricAvailabilityDto(
            type: 'face',
            status: 'notAvailable',
            isEnrolled: false,
            isLockedOut: false,
          ),
        ),
      );
      final a = await core.availability();
      expect(a.type, BiometricType.face);
      expect(a.status, BiometricAvailabilityStatus.notAvailable);
      expect(a.canAuthenticate, isFalse);
    });

    test('un status desconocido se trata como notAvailable', () async {
      final core = BiometricCore(
        api: FakeHostApi(
          availabilityDto: BiometricAvailabilityDto(
            type: 'fingerprint',
            status: 'nuevoEstado',
            isEnrolled: true,
            isLockedOut: false,
          ),
        ),
      );
      expect((await core.availability()).status, BiometricAvailabilityStatus.notAvailable);
    });

    test('runSession delega en la sesión nativa y resetSession la reinicia', () async {
      final api = FakeHostApi(decisions: [
        BiometricDecisionDto(kind: 'retry', remaining: 2),
        BiometricDecisionDto(kind: 'grantAccess'),
      ]);
      final core = BiometricCore(api: api);

      expect(await core.runSession(reason: 'test', maxAttempts: 3), isA<RetryPrompt>());
      expect(await core.runSession(reason: 'test', maxAttempts: 3), isA<GrantAccess>());
      expect(api.maxAttemptsSeen, [3, 3]);

      await core.resetSession();
      expect(api.resetCalls, 1);
    });
  });
}
