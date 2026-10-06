import Flutter
import BiometricCore

/// Adapta BiometricCore (Swift Package) al HostApi generado por Pigeon.
/// Messages.g.swift se genera con `dart run pigeon --input pigeons/messages.dart`.
///
/// La política (reintentos, caída a PIN) vive en BiometricSession: Flutter solo
/// recibe la decisión ya tomada, no la reimplementa (ADR-0001).
public final class BiometricCoreFlutterPlugin: NSObject, FlutterPlugin, BiometricCoreHostApi {
    private let authenticator: any BiometricAuthenticator = LocalAuthenticationAuthenticator()

    /// Sesión nativa que guarda el contador de intentos entre llamadas desde Dart.
    /// Solo se lee y escribe en el hilo principal: Pigeon invoca el HostApi ahí.
    private var session: BiometricSession?
    private var sessionMaxAttempts: Int?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BiometricCoreFlutterPlugin()
        BiometricCoreHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    }

    // Los métodos del HostApi son internos: Pigeon genera el protocolo y los DTO
    // como `internal`, y un método `public` no puede exponer tipos internos.
    func availability() throws -> BiometricAvailabilityDto {
        let a = authenticator.availability()
        return BiometricAvailabilityDto(
            type: a.type.rawValue,
            status: a.status.rawValue,
            isEnrolled: a.isEnrolled,
            isLockedOut: a.isLockedOut
        )
    }

    func authenticate(reason: String, allowPinFallback: Bool,
                      completion: @escaping (Result<BiometricResultDto, Error>) -> Void) {
        let authenticator = self.authenticator
        // El prompt corre fuera del main actor (función async no aislada) y la
        // respuesta a Flutter vuelve al hilo principal, como exige el engine.
        Task { @MainActor in
            let result = await authenticator.authenticate(reason: reason, allowPinFallback: allowPinFallback)
            var dto = BiometricResultDto(code: result.code)
            if case .failed(let reason) = result { dto.reason = reason }
            completion(.success(dto))
        }
    }

    func runSession(reason: String, maxAttempts: Int64,
                    completion: @escaping (Result<BiometricDecisionDto, Error>) -> Void) {
        let session = currentSession(maxAttempts: Int(maxAttempts))
        Task { @MainActor in
            let decision = await session.run(reason: reason)
            completion(.success(Self.dto(from: decision)))
        }
    }

    func resetSession() throws {
        // Descartamos la sesión en vez de llamar `await session.reset()`: eso exigiría
        // un Task que podría ejecutarse después del siguiente runSession. La próxima
        // llamada crea una sesión nueva con el contador en cero.
        session = nil
        sessionMaxAttempts = nil
    }

    /// Reutiliza la sesión mientras `maxAttempts` no cambie; si cambia, empieza una nueva.
    private func currentSession(maxAttempts: Int) -> BiometricSession {
        if let session, sessionMaxAttempts == maxAttempts { return session }
        let newSession = BiometricSession(
            authenticator: authenticator,
            policy: BiometricPolicy(maxAttempts: maxAttempts)
        )
        session = newSession
        sessionMaxAttempts = maxAttempts
        return newSession
    }

    static func dto(from decision: BiometricPolicy.Decision) -> BiometricDecisionDto {
        switch decision {
        case .grantAccess:
            return BiometricDecisionDto(kind: decision.kind)
        case .retry(let remaining):
            return BiometricDecisionDto(kind: decision.kind, remaining: Int64(remaining))
        case .requirePin(let reason), .showUnavailable(let reason):
            return BiometricDecisionDto(kind: decision.kind, reason: reason)
        }
    }
}
