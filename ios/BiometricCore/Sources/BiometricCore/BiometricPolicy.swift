import Foundation

/// Lógica de negocio sobre el contrato: cuántos intentos permitimos y cuándo
/// mandamos al usuario a PIN. No conoce LocalAuthentication ni BiometricPrompt.
///
/// `maxAttempts` cuenta prompts, no lecturas del sensor: cada prompt del sistema
/// ya permite varios intentos internos antes de devolver un error (ver ADR-0001).
///
/// Semana 7 del plan: esta pieza se mueve a Kotlin Multiplatform (`shared/`).
public struct BiometricPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case grantAccess
        case retry(remaining: Int)
        case requirePin(reason: String)
        case showUnavailable(reason: String)

        /// Código estable para serializar hacia Flutter / analytics (mismo valor que en Android).
        public var kind: String {
            switch self {
            case .grantAccess: return "grantAccess"
            case .retry: return "retry"
            case .requirePin: return "requirePin"
            case .showUnavailable: return "showUnavailable"
            }
        }

        /// Decisión que cierra el flujo biométrico. Después de ella la sesión
        /// vuelve a contar intentos desde cero.
        public var isTerminal: Bool {
            switch self {
            case .grantAccess, .requirePin: return true
            case .retry, .showUnavailable: return false
            }
        }
    }

    public let maxAttempts: Int

    public init(maxAttempts: Int = 3) {
        self.maxAttempts = max(1, maxAttempts)
    }

    public func decide(result: BiometricResult, attempt: Int) -> Decision {
        switch result {
        case .success:
            return .grantAccess
        case .fallbackToPin:
            return .requirePin(reason: "El usuario eligió PIN")
        case .lockedOut:
            return .requirePin(reason: "Biometría bloqueada por el sistema")
        case .notAvailable, .notEnrolled:
            return .showUnavailable(reason: result.code)
        case .cancelled:
            return .requirePin(reason: "Cancelado por el usuario")
        case .failed:
            let remaining = maxAttempts - attempt
            return remaining > 0
                ? .retry(remaining: remaining)
                : .requirePin(reason: "Se agotaron los intentos")
        }
    }
}

/// Orquesta autenticador + política. Es lo que la UI (SwiftUI) y el plugin de
/// Flutter consumen.
public actor BiometricSession {
    private let authenticator: any BiometricAuthenticator
    private let policy: BiometricPolicy
    private var attempt = 0

    public init(authenticator: any BiometricAuthenticator, policy: BiometricPolicy = .init()) {
        self.authenticator = authenticator
        self.policy = policy
    }

    public func run(reason: String) async -> BiometricPolicy.Decision {
        let availability = authenticator.availability()
        guard availability.canAuthenticate else {
            return finish(Self.shortCircuit(for: availability))
        }
        attempt += 1
        let result = await authenticator.authenticate(reason: reason, allowPinFallback: true)
        return finish(policy.decide(result: result, attempt: attempt))
    }

    public func reset() { attempt = 0 }

    /// Reinicia el contador después de una decisión terminal (grantAccess o requirePin),
    /// así el siguiente login vuelve a tener todos sus intentos.
    private func finish(_ decision: BiometricPolicy.Decision) -> BiometricPolicy.Decision {
        if decision.isTerminal { attempt = 0 }
        return decision
    }

    /// Decisión cuando no tiene sentido lanzar el prompt. Usa `status`, no los
    /// booleanos, para no confundir "permiso negado" con "no enrolado".
    private static func shortCircuit(for availability: BiometricAvailability) -> BiometricPolicy.Decision {
        switch availability.status {
        case .lockedOut:
            return .requirePin(reason: "Biometría bloqueada")
        case .notEnrolled:
            return .showUnavailable(reason: BiometricAvailabilityStatus.notEnrolled.rawValue)
        case .notAvailable, .available:
            // `.available` solo llega aquí si el tipo es `.none`: no hay biometría utilizable.
            return .showUnavailable(reason: BiometricAvailabilityStatus.notAvailable.rawValue)
        }
    }
}
