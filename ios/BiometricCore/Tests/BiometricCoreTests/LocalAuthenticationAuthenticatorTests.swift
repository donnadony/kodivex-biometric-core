#if canImport(LocalAuthentication)
import XCTest
import LocalAuthentication
@testable import BiometricCore

/// Una prueba por fila de la tabla de ADR-0001 (columna iOS).
final class LocalAuthenticationAuthenticatorMapTests: XCTestCase {
    private func map(_ code: LAError.Code) -> BiometricResult {
        LocalAuthenticationAuthenticator.map(LAError(code))
    }

    func testCancelCodesMapToCancelled() {
        XCTAssertEqual(map(.userCancel), .cancelled)
        XCTAssertEqual(map(.systemCancel), .cancelled)
        XCTAssertEqual(map(.appCancel), .cancelled)
    }

    func testUserFallbackMapsToFallbackToPin() {
        XCTAssertEqual(map(.userFallback), .fallbackToPin)
    }

    func testBiometryLockoutMapsToLockedOut() {
        XCTAssertEqual(map(.biometryLockout), .lockedOut)
    }

    func testBiometryNotAvailableMapsToNotAvailable() {
        XCTAssertEqual(map(.biometryNotAvailable), .notAvailable)
    }

    func testNotEnrolledCodesMapToNotEnrolled() {
        XCTAssertEqual(map(.biometryNotEnrolled), .notEnrolled)
        XCTAssertEqual(map(.passcodeNotSet), .notEnrolled)
    }

    func testOtherCodesMapToFailedWithRawValue() {
        XCTAssertEqual(map(.authenticationFailed), .failed(reason: "LAError \(LAError.Code.authenticationFailed.rawValue)"))
        XCTAssertEqual(map(.invalidContext), .failed(reason: "LAError \(LAError.Code.invalidContext.rawValue)"))
        XCTAssertEqual(map(.notInteractive), .failed(reason: "LAError \(LAError.Code.notInteractive.rawValue)"))
    }
}

/// Segunda tabla de ADR-0001: canEvaluatePolicy hacia BiometricAvailabilityStatus.
final class LocalAuthenticationAuthenticatorStatusTests: XCTestCase {
    private func status(_ code: LAError.Code) -> BiometricAvailabilityStatus {
        LocalAuthenticationAuthenticator.status(
            canEvaluate: false,
            error: NSError(domain: LAErrorDomain, code: code.rawValue)
        )
    }

    func testCanEvaluateIsAvailable() {
        XCTAssertEqual(LocalAuthenticationAuthenticator.status(canEvaluate: true, error: nil), .available)
    }

    /// Caso del permiso de Face ID negado: iOS devuelve biometryNotAvailable.
    func testBiometryNotAvailableIsNotAvailable() {
        XCTAssertEqual(status(.biometryNotAvailable), .notAvailable)
    }

    func testNotEnrolledCodesAreNotEnrolled() {
        XCTAssertEqual(status(.biometryNotEnrolled), .notEnrolled)
        XCTAssertEqual(status(.passcodeNotSet), .notEnrolled)
    }

    func testBiometryLockoutIsLockedOut() {
        XCTAssertEqual(status(.biometryLockout), .lockedOut)
    }

    func testUnknownOrForeignErrorsAreNotAvailable() {
        XCTAssertEqual(status(.invalidContext), .notAvailable)
        XCTAssertEqual(LocalAuthenticationAuthenticator.status(canEvaluate: false, error: nil), .notAvailable)
        XCTAssertEqual(
            LocalAuthenticationAuthenticator.status(
                canEvaluate: false,
                error: NSError(domain: "OtroDominio", code: LAError.Code.biometryLockout.rawValue)
            ),
            .notAvailable
        )
    }
}
#endif
