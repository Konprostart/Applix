
// Manages the RSA-2048 signing key in Android Keystore for APK v2 signatures.
//
// This is the original iappyxOS mechanism, unchanged: the key lives in the
// AndroidKeyStore of the container app, it is generated exactly once and it is
// never replaced while it exists. Every app that Applix generates is signed
// with it, so an update of a generated app always carries the same signature.
//
// The key is bound to the identity of Applix itself: it survives every update
// of Applix, and it is only lost when Applix is uninstalled or its data is
// cleared. That is the one case where the generated apps can no longer be
// updated - the build log and the "update required" dialog show the fingerprint
// of both keys so it is obvious what happened.

package com.konprostart.applix

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.util.Calendar

/**
 * Applix Key Manager
 *
 * Manages the signing key used for all generated APKs.
 *
 * The key lives in the AndroidKeyStore - a hardware-backed secure enclave on
 * modern devices. The raw private key bytes never leave the chip.
 *
 * The same key is used for all generated apps, which means:
 * - Apps can be updated (the same signature is required for updates)
 * - All generated apps are "trusted" by the same signer
 * - The key is created once on the first run and persists indefinitely
 */
object KeyManager {

    private const val TAG = "Applix"
    const val KEY_ALIAS = "applix_signing_key"
    private const val KEY_STORE = "AndroidKeyStore"

    /**
     * Ensure the signing key exists. Call this once on app startup.
     * If the key already exists, nothing happens - it is never regenerated.
     * If not, generates a new RSA-2048 key pair in the secure enclave.
     */
    fun ensureKeyExists(context: Context) {
        try {
            val keyStore = KeyStore.getInstance(KEY_STORE)
            keyStore.load(null)
            if (keyStore.containsAlias(KEY_ALIAS)) {
                Log.i(TAG, "Signing key already exists (${fingerprint()})")
                return
            }
            Log.i(TAG, "Generating new signing key...")
            generateKey()
            Log.i(TAG, "Signing key generated and stored in AndroidKeyStore (${fingerprint()})")
        } catch (e: Exception) {
            Log.e(TAG, "Could not prepare the signing key: ${e.message}")
        }
    }

    /**
     * Returns true if the signing key exists.
     */
    fun keyExists(context: Context): Boolean = try {
        val keyStore = KeyStore.getInstance(KEY_STORE)
        keyStore.load(null)
        keyStore.containsAlias(KEY_ALIAS)
    } catch (e: Exception) {
        false
    }

    /**
     * Delete the signing key. Use with caution -
     * existing generated apps can no longer be updated after this.
     */
    fun deleteKey(context: Context) {
        try {
            val keyStore = KeyStore.getInstance(KEY_STORE)
            keyStore.load(null)
            if (keyStore.containsAlias(KEY_ALIAS)) {
                keyStore.deleteEntry(KEY_ALIAS)
                Log.w(TAG, "Signing key deleted")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Could not delete the signing key: ${e.message}")
        }
    }

    /**
     * Get the signing certificate for display (fingerprint, expiry).
     */
    fun getCertificateInfo(context: Context): String {
        val fingerprint = fingerprint()
        if (fingerprint.isEmpty()) return "No key"
        return "SHA-256: ${fingerprint.take(29)}..."
    }

    /**
     * The full SHA-256 fingerprint of the signing certificate (empty when there
     * is no key). Two builds with the same fingerprint sign the same way.
     */
    fun fingerprint(): String {
        return try {
            val keyStore = KeyStore.getInstance(KEY_STORE)
            keyStore.load(null)
            if (!keyStore.containsAlias(KEY_ALIAS)) return ""
            sigDigest(keyStore.getCertificate(KEY_ALIAS).encoded)
        } catch (e: Exception) {
            Log.w(TAG, "Fingerprint unavailable: ${e.message}")
            ""
        }
    }

    /**
     * Check whether an installed app's signing certificate matches this device's key.
     * Returns: "not_installed", "same_signer", or "different_signer".
     */
    fun checkSignatureMatch(context: Context, packageName: String): String {
        val pm = context.packageManager
        val installedSigs = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val pi = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                pi.signingInfo?.apkContentsSigners?.map { sigDigest(it.toByteArray()) } ?: emptyList()
            } else {
                @Suppress("DEPRECATION")
                val pi = pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                @Suppress("DEPRECATION")
                pi.signatures?.map { sigDigest(it.toByteArray()) } ?: emptyList()
            }
        } catch (e: PackageManager.NameNotFoundException) {
            return "not_installed"
        }
        if (installedSigs.isEmpty()) return "not_installed"

        val localDigest = fingerprint()
        if (localDigest.isEmpty()) return "different_signer"

        return if (installedSigs.contains(localDigest)) "same_signer" else "different_signer"
    }

    /**
     * The fingerprint of the signer of an installed app (null when the app is
     * not installed or its signature cannot be read).
     */
    fun getInstalledSigner(context: Context, packageName: String): String? {
        val pm = context.packageManager
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val pi = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                pi.signingInfo?.apkContentsSigners?.firstOrNull()
                    ?.let { sigDigest(it.toByteArray()) }
            } else {
                @Suppress("DEPRECATION")
                val pi = pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                @Suppress("DEPRECATION")
                pi.signatures?.firstOrNull()?.let { sigDigest(it.toByteArray()) }
            }
        } catch (e: Exception) {
            null
        }
    }

    /** The SHA-256 fingerprint of a certificate, uppercase hex with colons. */
    fun digestOf(certBytes: ByteArray): String = sigDigest(certBytes)

    private fun sigDigest(certBytes: ByteArray): String {
        return MessageDigest.getInstance("SHA-256").digest(certBytes)
            .joinToString(":") { "%02X".format(it) }
    }

    // ─────────────────────────────────────────────
    // Private
    // ─────────────────────────────────────────────

    private fun generateKey() {
        val validityEnd = Calendar.getInstance().apply {
            add(Calendar.YEAR, 25) // 25-year validity, same as typical app signing keys
        }

        val keyGenSpec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setKeySize(2048)
            .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
            .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
            .setCertificateSubject(
                javax.security.auth.x500.X500Principal(
                    "CN=Applix, O=Konprostart, C=NL"
                )
            )
            .setCertificateSerialNumber(java.math.BigInteger.ONE)
            .setCertificateNotBefore(Calendar.getInstance().time)
            .setCertificateNotAfter(validityEnd.time)
            // Don't require user authentication — the key is used in background
            .setUserAuthenticationRequired(false)
            .build()

        val keyPairGenerator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_RSA,
            KEY_STORE
        )
        keyPairGenerator.initialize(keyGenSpec)
        keyPairGenerator.generateKeyPair()
    }
}
