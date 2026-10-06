package com.kodivex.biometric

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeAuthenticator(
    private val results: ArrayDeque<BiometricResult>,
    var availabilityValue: BiometricAvailability =
        BiometricAvailability(BiometricType.FACE, BiometricAvailabilityStatus.AVAILABLE),
) : BiometricAuthenticator {
    var authenticateCalls = 0
        private set

    override fun availability() = availabilityValue
    override suspend fun authenticate(reason: String, allowPinFallback: Boolean): BiometricResult {
        authenticateCalls += 1
        return results.removeFirstOrNull() ?: BiometricResult.Failed("no more results")
    }
}

private fun results(vararg values: BiometricResult) = ArrayDeque(values.toList())

class BiometricPolicyTest {
    @Test fun successGrantsAccess() {
        assertEquals(BiometricPolicy.Decision.GrantAccess, BiometricPolicy().decide(BiometricResult.Success, 1))
    }

    @Test fun failedRetriesUntilMaxThenRequiresPin() {
        val policy = BiometricPolicy(maxAttempts = 3)
        assertEquals(BiometricPolicy.Decision.Retry(2), policy.decide(BiometricResult.Failed("x"), 1))
        assertEquals(BiometricPolicy.Decision.Retry(1), policy.decide(BiometricResult.Failed("x"), 2))
        assertEquals(
            BiometricPolicy.Decision.RequirePin("Se agotaron los intentos"),
            policy.decide(BiometricResult.Failed("x"), 3),
        )
    }

    @Test fun notEnrolledShowsUnavailable() {
        assertEquals(
            BiometricPolicy.Decision.ShowUnavailable("notEnrolled"),
            BiometricPolicy().decide(BiometricResult.NotEnrolled, 1),
        )
    }

    @Test fun decisionKindIsStable() {
        assertEquals("grantAccess", BiometricPolicy.Decision.GrantAccess.kind)
        assertEquals("retry", BiometricPolicy.Decision.Retry(1).kind)
        assertEquals("requirePin", BiometricPolicy.Decision.RequirePin("x").kind)
        assertEquals("showUnavailable", BiometricPolicy.Decision.ShowUnavailable("x").kind)
    }
}

class BiometricAvailabilityTest {
    @Test fun canAuthenticateOnlyWhenAvailableAndTypeKnown() {
        assertTrue(BiometricAvailability(BiometricType.FINGERPRINT, BiometricAvailabilityStatus.AVAILABLE).canAuthenticate)
        assertFalse(BiometricAvailability(BiometricType.NONE, BiometricAvailabilityStatus.AVAILABLE).canAuthenticate)
        assertFalse(BiometricAvailability(BiometricType.FACE, BiometricAvailabilityStatus.NOT_AVAILABLE).canAuthenticate)
        assertFalse(BiometricAvailability(BiometricType.FACE, BiometricAvailabilityStatus.NOT_ENROLLED).canAuthenticate)
        assertFalse(BiometricAvailability(BiometricType.FACE, BiometricAvailabilityStatus.LOCKED_OUT).canAuthenticate)
    }

    @Test fun legacyConstructorMapsToStatus() {
        assertEquals(
            BiometricAvailabilityStatus.AVAILABLE,
            BiometricAvailability(BiometricType.FACE, isEnrolled = true, isLockedOut = false).status,
        )
        assertEquals(
            BiometricAvailabilityStatus.NOT_ENROLLED,
            BiometricAvailability(BiometricType.FACE, isEnrolled = false, isLockedOut = false).status,
        )
        assertEquals(
            BiometricAvailabilityStatus.LOCKED_OUT,
            BiometricAvailability(BiometricType.FACE, isEnrolled = true, isLockedOut = true).status,
        )
        assertEquals(
            BiometricAvailabilityStatus.NOT_AVAILABLE,
            BiometricAvailability(BiometricType.NONE, isEnrolled = true, isLockedOut = false).status,
        )
    }

    @Test fun statusCodesMatchIos() {
        assertEquals(
            listOf("available", "notAvailable", "notEnrolled", "lockedOut"),
            BiometricAvailabilityStatus.entries.map { it.code },
        )
    }
}

class BiometricSessionTest {
    @Test fun sessionCountsAttemptsAcrossRuns() = runTest {
        val fake = FakeAuthenticator(
            results(BiometricResult.Failed("1"), BiometricResult.Failed("2"), BiometricResult.Success),
        )
        val session = BiometricSession(fake, BiometricPolicy(maxAttempts = 3))

        assertEquals(BiometricPolicy.Decision.Retry(2), session.run("test"))
        assertEquals(BiometricPolicy.Decision.Retry(1), session.run("test"))
        assertEquals(BiometricPolicy.Decision.GrantAccess, session.run("test"))
    }

    @Test fun sessionShortCircuitsWhenNotEnrolled() = runTest {
        val fake = FakeAuthenticator(results(BiometricResult.Success)).apply {
            availabilityValue = BiometricAvailability(BiometricType.FINGERPRINT, BiometricAvailabilityStatus.NOT_ENROLLED)
        }
        assertEquals(BiometricPolicy.Decision.ShowUnavailable("notEnrolled"), BiometricSession(fake).run("test"))
        assertEquals(0, fake.authenticateCalls)
    }

    @Test fun sessionReportsNotAvailableEvenWithKnownType() = runTest {
        val fake = FakeAuthenticator(results(BiometricResult.Success)).apply {
            availabilityValue = BiometricAvailability(BiometricType.FINGERPRINT, BiometricAvailabilityStatus.NOT_AVAILABLE)
        }
        assertEquals(BiometricPolicy.Decision.ShowUnavailable("notAvailable"), BiometricSession(fake).run("test"))
        assertEquals(0, fake.authenticateCalls)
    }

    @Test fun sessionReportsNotAvailableWhenNoBiometricType() = runTest {
        val fake = FakeAuthenticator(results(BiometricResult.Success)).apply {
            availabilityValue = BiometricAvailability(BiometricType.NONE, BiometricAvailabilityStatus.AVAILABLE)
        }
        assertEquals(BiometricPolicy.Decision.ShowUnavailable("notAvailable"), BiometricSession(fake).run("test"))
    }

    @Test fun sessionRequiresPinWhenLockedOut() = runTest {
        val fake = FakeAuthenticator(results(BiometricResult.Success)).apply {
            availabilityValue = BiometricAvailability(BiometricType.FINGERPRINT, BiometricAvailabilityStatus.LOCKED_OUT)
        }
        assertEquals(BiometricPolicy.Decision.RequirePin("Biometría bloqueada"), BiometricSession(fake).run("test"))
        assertEquals(0, fake.authenticateCalls)
    }

    @Test fun sessionAutoResetsAfterRequirePin() = runTest {
        val fake = FakeAuthenticator(
            results(
                BiometricResult.Failed("1"),
                BiometricResult.Failed("2"),
                BiometricResult.Failed("3"),
                BiometricResult.Failed("4"),
            ),
        )
        val session = BiometricSession(fake, BiometricPolicy(maxAttempts = 3))

        session.run("test")
        session.run("test")
        assertEquals(BiometricPolicy.Decision.RequirePin("Se agotaron los intentos"), session.run("test"))

        // Sin llamar reset(): el siguiente login vuelve a tener todos sus intentos.
        assertEquals(BiometricPolicy.Decision.Retry(2), session.run("test"))
    }

    @Test fun sessionAutoResetsAfterGrantAccess() = runTest {
        val fake = FakeAuthenticator(
            results(BiometricResult.Failed("1"), BiometricResult.Success, BiometricResult.Failed("2")),
        )
        val session = BiometricSession(fake, BiometricPolicy(maxAttempts = 3))

        assertEquals(BiometricPolicy.Decision.Retry(2), session.run("test"))
        assertEquals(BiometricPolicy.Decision.GrantAccess, session.run("test"))
        assertEquals(BiometricPolicy.Decision.Retry(2), session.run("test"))
    }

    @Test fun sessionAutoResetsAfterUserChoosesPin() = runTest {
        val fake = FakeAuthenticator(
            results(BiometricResult.Failed("1"), BiometricResult.FallbackToPin, BiometricResult.Failed("2")),
        )
        val session = BiometricSession(fake, BiometricPolicy(maxAttempts = 3))

        session.run("test")
        assertEquals(BiometricPolicy.Decision.RequirePin("El usuario eligió PIN"), session.run("test"))
        assertEquals(BiometricPolicy.Decision.Retry(2), session.run("test"))
    }

    @Test fun retryDoesNotResetCounter() = runTest {
        val fake = FakeAuthenticator(results(BiometricResult.Failed("1"), BiometricResult.Failed("2")))
        val session = BiometricSession(fake, BiometricPolicy(maxAttempts = 2))

        assertEquals(BiometricPolicy.Decision.Retry(1), session.run("test"))
        assertEquals(BiometricPolicy.Decision.RequirePin("Se agotaron los intentos"), session.run("test"))
    }
}
