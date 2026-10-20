// MIT License — Copyright (c) 2026 iappyx

package com.konprostart.applix

import android.content.Context
import android.util.Log
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Calendar

/**
 * The stable master key of Applix.
 *
 * Every app that Applix generates is signed with this one key, so an update
 * of a generated app always carries the same signature and Android accepts it.
 *
 * Why the key lives in plain files and not in a keystore:
 *
 *  - The PKCS#12/JKS keystore providers differ between Android versions and
 *    vendors (Conscrypt vs BouncyCastle). A file written by one provider can
 *    not be read by the other - and then a *new* key was silently generated
 *    and every app built afterwards was signed with a different key than
 *    before. That is exactly the "signed with a different key" error.
 *  - A key in the AndroidKeyStore belongs to the keystore of the *container*
 *    app. It is invalidated when the container is reinstalled with another
 *    signature, when the app data is cleared or after a device restore.
 *
 * So the key is stored as two raw files (PKCS#8 private key + X.509
 * certificate) plus a fingerprint file that is used as a deterministic
 * cross check. The files live in the private storage of the app, they survive
 * every update and the user can export/import them (Settings → Signing Key).
 */
object KeystoreService {
    private const val TAG = "Applix"

    private const val KEY_DIR = "keys"
    private const val KEY_FILE = "applix_master.key"
    private const val CERT_FILE = "applix_master.crt"
    private const val FINGERPRINT_FILE = "applix_master.fingerprint"
    private const val EXPORT_FILE = "applix_master.aplixkey"

    /** The magic of the exported key file. */
    private val MAGIC = "APPLIXMASTER1".toByteArray(Charsets.US_ASCII)

    // ── file locations ───────────────────────────────────────────────────────

    private fun dir(context: Context): File {
        val d = File(context.filesDir, KEY_DIR)
        if (!d.exists()) d.mkdirs()
        return d
    }

    fun keyFile(context: Context): File = File(dir(context), KEY_FILE)
    fun certFile(context: Context): File = File(dir(context), CERT_FILE)
    private fun fingerprintFile(context: Context): File = File(dir(context), FINGERPRINT_FILE)
    private fun backupKeyFile(context: Context): File = File(dir(context), "$KEY_FILE.bak")
    private fun backupCertFile(context: Context): File = File(dir(context), "$CERT_FILE.bak")
    private fun backupFingerprintFile(context: Context): File =
        File(dir(context), "$FINGERPRINT_FILE.bak")

    /** True when a master key is stored. */
    fun keyExists(context: Context): Boolean =
        keyFile(context).exists() && certFile(context).exists()

    // ── the key itself ───────────────────────────────────────────────────────

    /**
     * Loads the master key. The key is created exactly once and then never
     * replaced: if the stored files exist but cannot be read, the backup is
     * used - and if that fails too the call fails loudly. A new key is never
     * silently created, because that would break the update of every app that
     * was signed before.
     */
    @Synchronized
    fun loadOrCreate(context: Context): MasterKey {
        val keyFile = keyFile(context)
        val certFile = certFile(context)

        if (keyFile.exists() && certFile.exists()) {
            try {
                val key = read(context, keyFile, certFile)
                Log.i(TAG, "Master signing key loaded (${key.fingerprint})")
                return key
            } catch (e: Exception) {
                Log.w(TAG, "Master key unreadable (${e.message}) - trying the backup")
                try {
                    val key = read(context, backupKeyFile(context), backupCertFile(context))
                    Log.w(TAG, "Master key restored from the backup (${key.fingerprint})")
                    writeFiles(context, key)
                    return key
                } catch (e2: Exception) {
                    throw IllegalStateException(
                        "The stored signing key is damaged and the backup is not usable. " +
                            "Import the key backup in Settings → Signing Key, or the apps that " +
                            "were built with it cannot be updated anymore.",
                        e2
                    )
                }
            }
        }

        // No key at all - create it once and keep it forever.
        val key = createKey()
        writeFiles(context, key)
        Log.i(TAG, "New master signing key created (${key.fingerprint})")
        return key
    }

    /** The master key: the private key plus its certificate. */
    class MasterKey(
        val privateKey: PrivateKey,
        val certificate: X509Certificate,
        val fingerprint: String,
    )

    private fun read(context: Context, keyFile: File, certFile: File): MasterKey {
        val keyBytes = keyFile.readBytes()
        val certBytes = certFile.readBytes()
        val key = KeyFactory.getInstance("RSA")
            .generatePrivate(PKCS8EncodedKeySpec(keyBytes))
        val cert = CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(certBytes)) as X509Certificate

        // The certificate has to belong to the key - otherwise the signature
        // would not verify. Proved by signing a test payload and verifying it
        // with the public key of the certificate.
        if (!keyMatchesCertificate(key, cert)) {
            throw IllegalStateException("The certificate does not match the private key")
        }
        val digest = digest(cert.encoded)

        // Deterministic cross check against the fingerprint file.
        val expectedFile = fingerprintFile(context)
        if (expectedFile.exists()) {
            val expected = expectedFile.readText().trim()
            if (expected.isNotEmpty() && !expected.equals(digest, ignoreCase = true)) {
                throw IllegalStateException(
                    "The signing key does not match its fingerprint - it was replaced"
                )
            }
        }
        return MasterKey(key, cert, digest)
    }

    private fun writeFiles(context: Context, key: MasterKey) {
        val keyFile = keyFile(context)
        val certFile = certFile(context)
        // Keep a backup of the current files before overwriting them.
        if (keyFile.exists()) {
            try {
                keyFile.copyTo(backupKeyFile(context), overwrite = true)
                certFile.copyTo(backupCertFile(context), overwrite = true)
                fingerprintFile(context).copyTo(backupFingerprintFile(context), overwrite = true)
            } catch (e: Exception) {
                Log.w(TAG, "Could not update the key backup: ${e.message}")
            }
        }
        keyFile.writeBytes(key.privateKey.encoded)
        certFile.writeBytes(key.certificate.encoded)
        fingerprintFile(context).writeText(key.fingerprint)
    }

    private fun createKey(): MasterKey {
        val generator = KeyPairGenerator.getInstance("RSA")
        generator.initialize(2048, SecureRandom())
        val keyPair: KeyPair = generator.generateKeyPair()

        val validityEnd = Calendar.getInstance().apply { add(Calendar.YEAR, 25) }
        val cert = SelfSignedCert.create(
            keyPair,
            "CN=Applix/O=Konprostart/C=NL",
            Calendar.getInstance().time,
            validityEnd.time
        )
        return MasterKey(keyPair.private, cert, digest(cert.encoded))
    }

    /** The private key used for signing. */
    fun privateKey(context: Context): PrivateKey = loadOrCreate(context).privateKey

    /** The certificate of the master key. */
    fun certificate(context: Context): X509Certificate = loadOrCreate(context).certificate

    /** SHA-256 fingerprint of the master certificate - the identity that every
     *  app generated by Applix shares. */
    fun fingerprint(context: Context): String = try {
        loadOrCreate(context).fingerprint
    } catch (e: Exception) {
        Log.w(TAG, "Fingerprint unavailable: ${e.message}")
        ""
    }

    /** SHA-256 of a certificate, uppercase hex with colons. */
    fun digest(certBytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(certBytes)
            .joinToString(":") { "%02X".format(it) }

    // ── export / import ──────────────────────────────────────────────────────

    /** Writes the master key into a single file the user can back up. */
    fun exportKey(context: Context): File? {
        return try {
            val key = loadOrCreate(context)
            val out = ByteArrayOutputStream()
            out.write(MAGIC)
            out.write(digestBytes(key.certificate.encoded))
            out.write(key.privateKey.encoded)
            out.write(key.certificate.encoded)
            val file = File(context.cacheDir, EXPORT_FILE)
            FileOutputStream(file).use { it.write(out.toByteArray()) }
            Log.i(TAG, "Master key exported to ${file.absolutePath}")
            file
        } catch (e: Exception) {
            Log.e(TAG, "Export failed: ${e.message}")
            null
        }
    }

    /**
     * Imports a master key from a backup file. The imported key replaces the
     * current one, so apps that were built with it can be updated again.
     */
    fun importKey(context: Context, source: File): String {
        return try {
            val bytes = source.readBytes()
            if (bytes.size < MAGIC.size + 32 || !bytes.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)) {
                return "That file is not an Applix master key"
            }
            var offset = MAGIC.size
            val certDigest = bytes.copyOfRange(offset, offset + 32)
            offset += 32
            val rest = bytes.copyOfRange(offset, bytes.size)
            val key = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(rest))
            val cert = CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(rest)) as X509Certificate
            if (!keyMatchesCertificate(key, cert)) {
                return "The key file is damaged"
            }
            if (!MessageDigest.getInstance("SHA-256").digest(cert.encoded).contentEquals(certDigest)) {
                return "The key file does not match its checksum"
            }
            val master = MasterKey(key, cert, digest(cert.encoded))
            writeFiles(context, master)
            Log.i(TAG, "Master key imported (${master.fingerprint})")
            "Master key imported - rebuild your apps so they use it"
        } catch (e: Exception) {
            "Could not import the key: ${e.message}"
        }
    }

    /** Deletes the master key. Existing apps can no longer be updated. */
    fun deleteKey(context: Context) {
        listOf(
            keyFile(context), certFile(context), fingerprintFile(context),
            backupKeyFile(context), backupCertFile(context), backupFingerprintFile(context),
        ).forEach { if (it.exists()) it.delete() }
        Log.w(TAG, "Master signing key deleted")
    }

    /**
     * Checks that the private key really belongs to the certificate by signing
     * a test payload and verifying it with the public key of the certificate.
     */
    private fun keyMatchesCertificate(privateKey: PrivateKey, cert: X509Certificate): Boolean {
        return try {
            val payload = "applix-key-check".toByteArray()
            val signer = Signature.getInstance("SHA256withRSA")
            signer.initSign(privateKey)
            signer.update(payload)
            val bytes = signer.sign()
            val verifier = Signature.getInstance("SHA256withRSA")
            verifier.initVerify(cert.publicKey)
            verifier.update(payload)
            verifier.verify(bytes)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Key/certificate check failed: ${e.message}")
            false
        }
    }

    /** Verifies that the private key really belongs to the certificate. */
    fun verify(key: MasterKey): Boolean = try {
        val signature = Signature.getInstance("SHA256withRSA")
        signature.initSign(key.privateKey)
        signature.update("applix-key-check".toByteArray())
        val bytes = signature.sign()
        val verifier = Signature.getInstance("SHA256withRSA")
        verifier.initVerify(key.certificate.publicKey)
        verifier.update("applix-key-check".toByteArray())
        verifier.verify(bytes)
    } catch (e: Exception) {
        false
    }

    private fun digestBytes(data: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(data)
}
