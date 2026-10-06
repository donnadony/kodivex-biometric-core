#if canImport(LocalAuthentication)
import Foundation
import LocalAuthentication

/// Implementación iOS/macOS del contrato usando LocalAuthentication.
/// Traduce LAError al BiometricResult común (tabla "Resultado del prompt" en docs/spec/error-mapping.md).
///
/// La app que lo use necesita `NSFaceIDUsageDescription` en su Info.plist;
/// sin esa clave iOS no muestra Face ID.
public final class LocalAuthenticationAuthenticator: BiometricAuthenticator, @unchecked Sendable {
    private let makeContext: @Sendable () -> LAContext

    public init(makeContext: @escaping @Sendable () -> LAContext = { LAContext() }) {
        self.makeContext = makeContext
    }

    public func availability() -> BiometricAvailability {
        let context = makeContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        // biometryType solo es confiable después de llamar canEvaluatePolicy.
        // Ojo: si el usuario negó el permiso de Face ID, sigue valiendo .faceID
        // aunque canEvaluatePolicy falle con biometryNotAvailable.
        let type: BiometricType
        switch context.biometryType {
        case .faceID: type = .face
        case .touchID: type = .fingerprint
        default: type = .none
        }

        return BiometricAvailability(type: type, status: Self.status(canEvaluate: canEvaluate, error: error))
    }

    public func authenticate(reason: String, allowPinFallback: Bool) async -> BiometricResult {
        let context = makeContext()
        context.localizedFallbackTitle = allowPinFallback ? "Usar PIN" : ""
        context.localizedCancelTitle = "Cancelar"

        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return ok ? .success : .failed(reason: "evaluatePolicy returned false")
        } catch let error as LAError {
            return Self.map(error)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    /// Traduce el resultado de canEvaluatePolicy al estado común (tabla "Disponibilidad antes del prompt" en docs/spec/error-mapping.md).
    static func status(canEvaluate: Bool, error: NSError?) -> BiometricAvailabilityStatus {
        if canEvaluate { return .available }
        guard let error, error.domain == LAErrorDomain,
              let code = LAError.Code(rawValue: error.code) else {
            return .notAvailable
        }
        switch code {
        case .biometryLockout: return .lockedOut
        case .biometryNotEnrolled, .passcodeNotSet: return .notEnrolled
        // biometryNotAvailable incluye "permiso de Face ID negado": es notAvailable
        // aunque biometryType diga .faceID.
        case .biometryNotAvailable: return .notAvailable
        default: return .notAvailable
        }
    }

    static func map(_ error: LAError) -> BiometricResult {
        switch error.code {
        case .userCancel, .systemCancel, .appCancel: return .cancelled
        case .userFallback: return .fallbackToPin
        case .biometryLockout: return .lockedOut
        case .biometryNotAvailable: return .notAvailable
        case .biometryNotEnrolled, .passcodeNotSet: return .notEnrolled
        default: return .failed(reason: "LAError \(error.code.rawValue)")
        }
    }
}
#endif
