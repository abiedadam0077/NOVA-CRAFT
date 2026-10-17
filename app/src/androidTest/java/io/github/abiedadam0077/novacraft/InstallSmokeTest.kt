package io.github.abiedadam0077.novacraft

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.goterl.lazysodium.LazySodiumAndroid
import com.goterl.lazysodium.SodiumAndroid
import io.github.abiedadam0077.novacraft.core.SecureStore
import io.github.abiedadam0077.novacraft.ui.Strings
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real emulator tests: no GitHub credentials or synthetic server metrics. */
@RunWith(AndroidJUnit4::class)
class InstallSmokeTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun firstLaunchOnboardingAndActivityRecreation() {
        val start = Strings.t("ar", "get_started")
        val auth = Strings.t("ar", "connect_github")
        compose.waitUntil(30_000) {
            compose.onAllNodesWithText(start).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText(start).assertIsDisplayed().performClick()
        compose.waitUntil(30_000) {
            compose.onAllNodesWithText(auth).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText(auth).assertIsDisplayed()
        compose.activityRule.scenario.recreate()
        compose.waitUntil(30_000) {
            compose.onAllNodesWithText(auth).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText(auth).assertIsDisplayed()
    }

    @Test fun androidKeystoreRoundTripAndTamperRejection() {
        val store = SecureStore(compose.activity)
        val first = store.encrypt("instrumentation-test-only")
        val second = store.encrypt("instrumentation-test-only")
        assertNotEquals(first, second)
        assertEquals("instrumentation-test-only", store.decrypt(first))
        assertNull(store.decrypt("invalid-ciphertext"))
    }

    @Test fun packagedNativeEncryptionLibraryLoadsAndSeals() {
        // Exercise the same native operation used to encrypt repository secrets.
        val sodium = LazySodiumAndroid(SodiumAndroid()).sodium
        val publicKey = ByteArray(32).apply { this[0] = 9 }
        val message = "not-a-real-secret".toByteArray()
        val encrypted = ByteArray(message.size + 48)
        assertEquals(0, sodium.crypto_box_seal(encrypted, message, message.size.toLong(), publicKey))
        assertFalse(encrypted.all { it == 0.toByte() })
    }
}
