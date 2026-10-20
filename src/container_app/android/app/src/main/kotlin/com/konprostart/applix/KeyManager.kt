
// Manages the RSA-2048 signing key used for every app that Applix generates.
//
// The key itself lives in KeystoreService (a stable file in the private
// storage of the app). This class is the thin, stable API around it that the
// rest of the app uses.

package com.konprostart.applix

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/**
 * Applix Key Manager
 *
 * All generated apps are signed with ONE master key, so:
 * - an update of a generated app always has the same signature
 * - all generated apps share the same signer
 * - the key survives app updates and can be exported/imported by the user
 */
object KeyManager {

    private const val TAG = "Applix"

    /** Legacy alias of the key in the AndroidKeyStore. Kept for the migration
     *  path - new apps are signed with the master key. */
    const val KEY_ALIAS = "applix_signing_key"

    /**
     * Ensure the master signing key exists. Call this once on app startup.
     * If the key already exists, nothing happens - it is never regenerated.
     */
    fun ensureKeyExists(context: Context) {
        try {
            KeystoreService.loadOrCreate(context)
        } catch (e: Exception) {
            Log.e(TAG, "Could not prepare the master signing key: ${e.message}")
        }
    }

    /**
     * Returns true if the signing key exists.
     */
    fun keyExists(context: Context): Boolean = KeystoreService.keyExists(context)

    /**
     * Delete the signing key. Use with caution -
     * existing generated apps can no longer be updated after this.
     */
    fun deleteKey(context: Context) = KeystoreService.deleteKey(context)

    /**
     * Get the signing certificate for display (fingerprint, expiry).
     */
    fun getCertificateInfo(context: Context): String {
        val fingerprint = try {
            KeystoreService.fingerprint(context)
        } catch (e: Exception) {
            return "No key"
        }
        if (fingerprint.isEmpty()) return "No key"
        return "SHA-256: ${fingerprint.take(29)}..."
    }

    /** The full SHA-256 fingerprint of the signing certificate (empty when
     *  there is no key). Two builds with the same fingerprint sign the same way. */
    fun fullFingerprint(context: Context): String {
        return try {
            KeystoreService.fingerprint(context)
        } catch (e: Exception) {
            ""
        }
    }

    /**
     * Check whether an installed app's signing certificate matches this
     * device's master key.
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

        val localDigest = try {
            KeystoreService.digest(KeystoreService.certificate(context).encoded)
        } catch (e: Exception) {
            return "different_signer"
        }

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

    private fun sigDigest(certBytes: ByteArray): String =
        KeystoreService.digest(certBytes)
}
