import XCTest
@testable import BiometricCore

/// Autenticador falso: devuelve una secuencia de resultados predefinida.
final class FakeAuthenticator: BiometricAuthenticator, @unchecked Sendable {
    var availabilityValue = BiometricAvailability(type: .face, status: .available)
    var results: [BiometricResult]
    private(set) var authenticateCalls = 0

    init(results: [BiometricResult]) { self.results = results }

    func availability() -> BiometricAvailability { availabilityValue }
    func authenticate(reason: String, allowPinFallback: Bool) async -> BiometricResult {
        authenticateCalls += 1
        return results.isEmpty ? .failed(reason: "no more results") : results.removeFirst()
    }
}

final class BiometricPolicyTests: XCTestCase {
    func testSuccessGrantsAccess() {
        XCTAssertEqual(BiometricPolicy().decide(result: .success, attempt: 1), .grantAccess)
    }

    func testFailedRetriesUntilMaxThenRequiresPin() {
        let policy = BiometricPolicy(maxAttempts: 3)
        XCTAssertEqual(policy.decide(result: .failed(reason: "x"), attempt: 1), .retry(remaining: 2))
        XCTAssertEqual(policy.decide(result: .failed(reason: "x"), attempt: 2), .retry(remaining: 1))
        XCTAssertEqual(policy.decide(result: .failed(reason: "x"), attempt: 3), .requirePin(reason: "Se agotaron los intentos"))
    }

    func testLockedOutRequiresPin() {
        if case .requirePin = BiometricPolicy().decide(result: .lockedOut, attempt: 1) {} else {
            XCTFail("lockedOut debe caer a PIN")
        }
    }

    func testNotEnrolledShowsUnavailable() {
        XCTAssertEqual(BiometricPolicy().decide(result: .notEnrolled, attempt: 1), .showUnavailable(reason: "notEnrolled"))
    }

    func testDecisionKindIsStable() {
        XCTAssertEqual(BiometricPolicy.Decision.grantAccess.kind, "grantAccess")
        XCTAssertEqual(BiometricPolicy.Decision.retry(remaining: 1).kind, "retry")
        XCTAssertEqual(BiometricPolicy.Decision.requirePin(reason: "x").kind, "requirePin")
        XCTAssertEqual(BiometricPolicy.Decision.showUnavailable(reason: "x").kind, "showUnavailable")
    }
}

final class BiometricAvailabilityTests: XCTestCase {
    func testCanAuthenticateOnlyWhenAvailableAndTypeKnown() {
        XCTAssertTrue(BiometricAvailability(type: .face, status: .available).canAuthenticate)
        XCTAssertFalse(BiometricAvailability(type: .none, status: .available).canAuthenticate)
        XCTAssertFalse(BiometricAvailability(type: .face, status: .notAvailable).canAuthenticate)
        XCTAssertFalse(BiometricAvailability(type: .face, status: .notEnrolled).canAuthenticate)
        XCTAssertFalse(BiometricAvailability(type: .face, status: .lockedOut).canAuthenticate)
    }

    func testCompatibilityFlagsDeriveFromStatus() {
        let lockedOut = BiometricAvailability(type: .fingerprint, status: .lockedOut)
        XCTAssertTrue(lockedOut.isEnrolled)
        XCTAssertTrue(lockedOut.isLockedOut)

        let denied = BiometricAvailability(type: .face, status: .notAvailable)
        XCTAssertFalse(denied.isEnrolled)
        XCTAssertFalse(denied.isLockedOut)
    }

    func testLegacyInitializerMapsToStatus() {
        XCTAssertEqual(BiometricAvailability(type: .face, isEnrolled: true, isLockedOut: false).status, .available)
        XCTAssertEqual(BiometricAvailability(type: .face, isEnrolled: false, isLockedOut: false).status, .notEnrolled)
        XCTAssertEqual(BiometricAvailability(type: .face, isEnrolled: true, isLockedOut: true).status, .lockedOut)
        XCTAssertEqual(BiometricAvailability(type: .none, isEnrolled: true, isLockedOut: false).status, .notAvailable)
    }
}

final class BiometricSessionTests: XCTestCase {
    func testSessionCountsAttemptsAcrossRuns() async {
        let fake = FakeAuthenticator(results: [.failed(reason: "1"), .failed(reason: "2"), .success])
        let session = BiometricSession(authenticator: fake, policy: .init(maxAttempts: 3))

        let first = await session.run(reason: "test")
        XCTAssertEqual(first, .retry(remaining: 2))
        let second = await session.run(reason: "test")
        XCTAssertEqual(second, .retry(remaining: 1))
        let third = await session.run(reason: "test")
        XCTAssertEqual(third, .grantAccess)
    }

    func testSessionShortCircuitsWhenNotEnrolled() async {
        let fake = FakeAuthenticator(results: [.success])
        fake.availabilityValue = BiometricAvailability(type: .face, status: .notEnrolled)
        let session = BiometricSession(authenticator: fake)

        let decision = await session.run(reason: "test")
        XCTAssertEqual(decision, .showUnavailable(reason: "notEnrolled"))
        XCTAssertEqual(fake.authenticateCalls, 0)
    }

    /// Permiso de Face ID negado: el tipo sigue siendo .face pero el estado es notAvailable.
    /// Antes se reportaba como "notEnrolled".
    func testSessionReportsNotAvailableWhenFaceIDPermissionDenied() async {
        let fake = FakeAuthenticator(results: [.success])
        fake.availabilityValue = BiometricAvailability(type: .face, status: .notAvailable)
        let session = BiometricSession(authenticator: fake)

        let decision = await session.run(reason: "test")
        XCTAssertEqual(decision, .showUnavailable(reason: "notAvailable"))
        XCTAssertEqual(fake.authenticateCalls, 0)
    }

    func testSessionReportsNotAvailableWhenNoBiometryType() async {
        let fake = FakeAuthenticator(results: [.success])
        fake.availabilityValue = BiometricAvailability(type: .none, status: .available)
        let session = BiometricSession(authenticator: fake)

        let decision = await session.run(reason: "test")
        XCTAssertEqual(decision, .showUnavailable(reason: "notAvailable"))
    }

    func testSessionRequiresPinWhenLockedOut() async {
        let fake = FakeAuthenticator(results: [.success])
        fake.availabilityValue = BiometricAvailability(type: .fingerprint, status: .lockedOut)
        let session = BiometricSession(authenticator: fake)

        let decision = await session.run(reason: "test")
        XCTAssertEqual(decision, .requirePin(reason: "Biometría bloqueada"))
        XCTAssertEqual(fake.authenticateCalls, 0)
    }

    func testSessionAutoResetsAfterRequirePin() async {
        let fake = FakeAuthenticator(results: [.failed(reason: "1"), .failed(reason: "2"), .failed(reason: "3"), .failed(reason: "4")])
        let session = BiometricSession(authenticator: fake, policy: .init(maxAttempts: 3))

        _ = await session.run(reason: "test")
        _ = await session.run(reason: "test")
        let exhausted = await session.run(reason: "test")
        XCTAssertEqual(exhausted, .requirePin(reason: "Se agotaron los intentos"))

        // Sin llamar reset(): el siguiente login vuelve a tener todos sus intentos.
        let next = await session.run(reason: "test")
        XCTAssertEqual(next, .retry(remaining: 2))
    }

    func testSessionAutoResetsAfterGrantAccess() async {
        let fake = FakeAuthenticator(results: [.failed(reason: "1"), .success, .failed(reason: "2")])
        let session = BiometricSession(authenticator: fake, policy: .init(maxAttempts: 3))

        let first = await session.run(reason: "test")
        XCTAssertEqual(first, .retry(remaining: 2))
        let granted = await session.run(reason: "test")
        XCTAssertEqual(granted, .grantAccess)

        let next = await session.run(reason: "test")
        XCTAssertEqual(next, .retry(remaining: 2))
    }

    func testSessionAutoResetsAfterUserChoosesPin() async {
        let fake = FakeAuthenticator(results: [.failed(reason: "1"), .fallbackToPin, .failed(reason: "2")])
        let session = BiometricSession(authenticator: fake, policy: .init(maxAttempts: 3))

        _ = await session.run(reason: "test")
        let pin = await session.run(reason: "test")
        XCTAssertEqual(pin, .requirePin(reason: "El usuario eligió PIN"))

        let next = await session.run(reason: "test")
        XCTAssertEqual(next, .retry(remaining: 2))
    }

    func testRetryDoesNotResetCounter() async {
        let fake = FakeAuthenticator(results: [.failed(reason: "1"), .failed(reason: "2")])
        let session = BiometricSession(authenticator: fake, policy: .init(maxAttempts: 2))

        let first = await session.run(reason: "test")
        XCTAssertEqual(first, .retry(remaining: 1))
        let second = await session.run(reason: "test")
        XCTAssertEqual(second, .requirePin(reason: "Se agotaron los intentos"))
    }
}
