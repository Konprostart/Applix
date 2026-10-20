// MIT License — Copyright (c) 2026 iappyx

package com.konprostart.applix

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Calendar

/**
 * The master key of Applix.
 *
 * Every app that Applix generates is signed with this one key, so an update of
 * a generated app always carries the same signature and Android accepts it.
 *
 * The key is stored as ONE keystore file in the private storage of the app:
 *
 *  - it survives every update of Applix itself,
 *  - it does not depend on a keystore provider (the AndroidKeyStore key cannot
 *    be exported and is invalidated when the container is reinstalled with a
 *    different signature, when the app data is cleared or after a restore),
 *  - the user can export and import it, so a new phone or a restored backup
 *    can keep updating the apps that were built with it.
 *
 * If the file exists it is ALWAYS used - the key is never silently replaced,
 * because that would break the update of every app that was signed before.
 */
object KeystoreService {
    private const val TAG = "Applix"

    /** The alias of the key inside the keystore file. */
    const val MASTER_ALIAS = "applix"

    /** The password of the keystore file. The file itself lives in the
     *  private storage of the app - that is what actually protects it. */
    private const val STORE_PASSWORD = "applix-master-key"

    private const val KEY_DIR = "keys"
    private const val KEY_FILE = "applix_master.p12"
    private const val KEY_TYPE = "PKCS12"

    // The raw files that an earlier version used. They are migrated into the
    // keystore file so the key (and therefore every signature) stays the same.
    private const val LEGACY_KEY_FILE = "applix_master.key"
    private const val LEGACY_CERT_FILE = "applix_master.crt"

    // ── file locations ───────────────────────────────────────────────────────

    private fun dir(context: Context): File {
        val d = File(context.filesDir, KEY_DIR)
        if (!d.exists()) d.mkdirs()
        return d
    }

    fun masterKeyFile(context: Context): File = File(dir(context), KEY_FILE)

    /** True when a master key is stored. */
    fun keyExists(context: Context): Boolean = masterKeyFile(context).exists()

    // ── the key ──────────────────────────────────────────────────────────────

    /** The master key: the private key plus its certificate. */
    class MasterKey(
        val privateKey: PrivateKey,
        val certificate: X509Certificate,
        val fingerprint: String,
    )

    /**
     * Loads the master key, creating it exactly once if it does not exist.
     * An existing key is never replaced - if the file cannot be read the call
     * fails loudly instead of signing with a new key.
     */
    @Synchronized
    fun loadOrCreate(context: Context): MasterKey {
        val file = masterKeyFile(context)

        if (file.exists() && file.length() > 0) {
            return try {
                val key = read(file)
                Log.i(TAG, "Master signing key loaded (${key.fingerprint})")
                key
            } catch (e: Exception) {
                Log.e(TAG, "The stored signing key cannot be read: ${e.message}")
                throw IllegalStateException(
                    "The stored signing key is damaged. Import your key backup in " +
                        "Settings → Signing Key, or delete the key file to start with a new one. " +
                        "Apps that were built with the old key cannot be updated anymore.",
                    e
                )
            }
        }

        // No key file yet - migrate the files of an earlier version if they are
        // there, otherwise create the key exactly once.
        val migrated = migrateLegacyFiles(context)
        if (migrated != null) {
            Log.i(TAG, "Master signing key migrated (${migrated.fingerprint})")
            return migrated
        }

        val key = createKey()
        writeFile(context, key)
        Log.i(TAG, "New master signing key created (${key.fingerprint})")
        return key
    }

    private fun read(file: File): MasterKey {
        val store = KeyStore.getInstance(KEY_TYPE)
        FileInputStream(file).use { store.load(it, STORE_PASSWORD.toCharArray()) }
        if (!store.containsAlias(MASTER_ALIAS)) {
            throw IllegalStateException("The keystore file does not contain the master key")
        }
        val key = store.getKey(MASTER_ALIAS, STORE_PASSWORD.toCharArray()) as PrivateKey
        val cert = store.getCertificate(MASTER_ALIAS) as X509Certificate
        if (!keyMatchesCertificate(key, cert)) {
            throw IllegalStateException("The certificate does not match the private key")
        }
        return MasterKey(key, cert, digest(cert.encoded))
    }

    private fun writeFile(context: Context, key: MasterKey) {
        val store = KeyStore.getInstance(KEY_TYPE)
        store.load(null, STORE_PASSWORD.toCharArray())
        store.setKeyEntry(
            MASTER_ALIAS,
            key.privateKey,
            STORE_PASSWORD.toCharArray(),
            arrayOf(key.certificate)
        )
        val file = masterKeyFile(context)
        FileOutputStream(file).use { store.store(it, STORE_PASSWORD.toCharArray()) }
    }

    /**
     * Moves the key of the raw-file version into the keystore file - the key
     * itself does not change, so no app loses its signature.
     */
    private fun migrateLegacyFiles(context: Context): MasterKey? {
        val keyFile = File(dir(context), LEGACY_KEY_FILE)
        val certFile = File(dir(context), LEGACY_CERT_FILE)
        if (!keyFile.exists() || !certFile.exists()) return null
        return try {
            val key = KeyFactory.getInstance("RSA")
                .generatePrivate(PKCS8EncodedKeySpec(keyFile.readBytes()))
            val cert = CertificateFactory.getInstance("X.509")
                .generateCertificate(certFile.inputStream()) as X509Certificate
            if (!keyMatchesCertificate(key, cert)) return null
            val master = MasterKey(key, cert, digest(cert.encoded))
            writeFile(context, master)
            keyFile.delete()
            certFile.delete()
            master
        } catch (e: Exception) {
            Log.w(TAG, "Could not migrate the previous key files: ${e.message}")
            null
        }
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

    /**
     * Checks that the private key belongs to the certificate by signing a test
     * payload and verifying it with the public key of the certificate.
     */
    private fun keyMatchesCertificate(privateKey: PrivateKey, cert: X509Certificate): Boolean {
        return try {
            val payload = "applix-key-check".toByteArray()
            val signer = java.security.Signature.getInstance("SHA256withRSA")
            signer.initSign(privateKey)
            signer.update(payload)
            val bytes = signer.sign()
            val verifier = java.security.Signature.getInstance("SHA256withRSA")
            verifier.initVerify(cert.publicKey)
            verifier.update(payload)
            verifier.verify(bytes)
            true
        } catch (e: Exception) {
            false
        }
    }

    // ── export / import ──────────────────────────────────────────────────────

    /**
     * Copies the master key into a file the user can share and back up.
     * The file goes to the cache directory - the file provider of the app can
     * share it from there.
     */
    fun exportKey(context: Context): File? {
        return try {
            val key = loadOrCreate(context)
            val store = KeyStore.getInstance(KEY_TYPE)
            store.load(null, STORE_PASSWORD.toCharArray())
            store.setKeyEntry(
                MASTER_ALIAS,
                key.privateKey,
                STORE_PASSWORD.toCharArray(),
                arrayOf(key.certificate)
            )
            // The file provider shares cacheDir/share/ - the export has to be there.
            val shareDir = File(context.cacheDir, "share")
            if (!shareDir.exists()) shareDir.mkdirs()
            val out = File(shareDir, "applix_master_key.p12")
            FileOutputStream(out).use { store.store(it, STORE_PASSWORD.toCharArray()) }
            Log.i(TAG, "Master key exported to ${out.absolutePath}")
            out
        } catch (e: Exception) {
            Log.e(TAG, "Export failed: ${e.message}")
            null
        }
    }

    /**
     * Imports a master key from a backup file. The imported key replaces the
     * current one, so the apps that were built with it can be updated again.
     */
    fun importKey(context: Context, source: File): String {
        return try {
            val store = KeyStore.getInstance(KEY_TYPE)
            FileInputStream(source).use { store.load(it, STORE_PASSWORD.toCharArray()) }
            if (!store.containsAlias(MASTER_ALIAS)) {
                return "That file is not an Applix master key"
            }
            val key = store.getKey(MASTER_ALIAS, STORE_PASSWORD.toCharArray()) as PrivateKey
            val cert = store.getCertificate(MASTER_ALIAS) as X509Certificate
            if (!keyMatchesCertificate(key, cert)) {
                return "The key file is damaged"
            }
            val master = MasterKey(key, cert, digest(cert.encoded))
            writeFile(context, master)
            Log.i(TAG, "Master key imported (${master.fingerprint})")
            "Master key imported - rebuild your apps so they use it"
        } catch (e: Exception) {
            "Could not import the key: ${e.message}"
        }
    }

    /** Deletes the master key. Existing apps can no longer be updated. */
    fun deleteKey(context: Context) {
        listOf(
            masterKeyFile(context),
            File(dir(context), LEGACY_KEY_FILE),
            File(dir(context), LEGACY_CERT_FILE),
        ).forEach { if (it.exists()) it.delete() }
        Log.w(TAG, "Master signing key deleted")
    }
}
