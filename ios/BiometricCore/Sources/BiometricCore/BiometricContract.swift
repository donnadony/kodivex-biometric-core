import Foundation

/// Resultado común de una autenticación biométrica. Es el contrato que comparten
/// iOS, Android y el plugin de Flutter (ver docs/adr/0001-shared-contract.md).
public enum BiometricResult: Equatable, Sendable {
    case success
    case cancelled
    case lockedOut
    case notAvailable
    case notEnrolled
    case fallbackToPin
    case failed(reason: String)

    /// Código estable para serializar hacia Flutter / analytics.
    public var code: String {
        switch self {
        case .success: return "success"
        case .cancelled: return "cancelled"
        case .lockedOut: return "lockedOut"
        case .notAvailable: return "notAvailable"
        case .notEnrolled: return "notEnrolled"
        case .fallbackToPin: return "fallbackToPin"
        case .failed: return "failed"
        }
    }
}

/// Tipo de biometría disponible en el dispositivo.
public enum BiometricType: String, Sendable {
    case face, fingerprint, none
}

/// Estado de la biometría antes de lanzar el prompt. El rawValue es el código
/// estable que viaja a Flutter (mismo valor que en Android).
public enum BiometricAvailabilityStatus: String, Equatable, Sendable {
    /// Hay biometría enrolada y lista para usarse.
    case available
    /// No hay hardware, está ocupado o el usuario negó el permiso (Face ID).
    case notAvailable
    /// Hay hardware pero no hay biometría (o código del dispositivo) configurada.
    case notEnrolled
    /// El sistema bloqueó la biometría por demasiados intentos fallidos.
    case lockedOut
}

/// Contrato que toda implementación nativa debe cumplir.
public protocol BiometricAuthenticator: Sendable {
    /// Qué biometría hay y si está lista para usarse.
    func availability() -> BiometricAvailability
    /// Lanza el prompt del sistema.
    func authenticate(reason: String, allowPinFallback: Bool) async -> BiometricResult
}

public struct BiometricAvailability: Equatable, Sendable {
    public let type: BiometricType
    public let status: BiometricAvailabilityStatus

    public init(type: BiometricType, status: BiometricAvailabilityStatus) {
        self.type = type
        self.status = status
    }

    /// Inicializador anterior, se mantiene por compatibilidad. Deduce `status`
    /// a partir de los booleanos; el código nuevo debería pasar `status` directo.
    public init(type: BiometricType, isEnrolled: Bool, isLockedOut: Bool) {
        let status: BiometricAvailabilityStatus
        if isLockedOut {
            status = .lockedOut
        } else if !isEnrolled {
            status = .notEnrolled
        } else if type == .none {
            status = .notAvailable
        } else {
            status = .available
        }
        self.init(type: type, status: status)
    }

    /// Compatibilidad: hay biometría enrolada (aunque esté bloqueada).
    public var isEnrolled: Bool { status == .available || status == .lockedOut }

    /// Compatibilidad: el sistema bloqueó la biometría.
    public var isLockedOut: Bool { status == .lockedOut }

    public var canAuthenticate: Bool { status == .available && type != .none }
}
