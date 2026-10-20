// MIT License — Copyright (c) 2026 iappyx

package com.konprostart.applix

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.security.keystore.KeyProtection
import android.util.Log
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.Certificate
import java.security.cert.X509Certificate

/**
 * A durable backup of the master signing key.
 *
 * The master key itself lives in the AndroidKeyStore of Applix - that is the
 * proven mechanism and it survives every update. The AndroidKeyStore is bound to
 * the app data though: uninstall Applix (or clear its data) and the key is gone
 * forever. Every app that was signed with it then fails to update with
 * "signed with a different key", because Android can never verify a signature
 * whose key no longer exists.
 *
 * This class keeps ONE record of the key in the shared Downloads folder. That
 * record is not removed when Applix is uninstalled, so the key can be restored
 * and every generated app stays updatable. The record is a single file with a
 * magic header and a checksum - it is never appended to or duplicated.
 */
object KeyBackup {
    private const val TAG = "Applix"

    /** The name of the record in the shared Downloads folder. */
    const val RECORD_NAME = "applix_master_key.aplixkey"

    private val MAGIC = "APPLIXKEY1".toByteArray(Charsets.US_ASCII)
    private const val STORE_PASSWORD = "applix-master-key"
    private const val KEY_ALIAS = "applix_signing_key"
    private const val KEY_STORE = "AndroidKeyStore"
    private const val KEY_TYPE = "PKCS12"

    /** True when a backup record exists in the shared storage. */
    fun exists(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
            val resolver = context.contentResolver
            val projection = arrayOf(MediaStore.Downloads._ID)
            val selection = "${MediaStore.Downloads.DISPLAY_NAME}=?"
            val args = arrayOf(RECORD_NAME)
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, projection, selection, args, null
            )?.use { it.moveToFirst() } ?: false
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Writes the current master key into the shared Downloads folder.
     * Returns the path of the record or null on failure.
     */
    fun save(context: Context): String? {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
            val keyStore = KeyStore.getInstance(KEY_STORE)
            keyStore.load(null)
            if (!keyStore.containsAlias(KEY_ALIAS)) {
                Log.w(TAG, "No master key to back up")
                return null
            }
            val privateKey = keyStore.getKey(KEY_ALIAS, null) as? PrivateKey ?: return null
            val cert = keyStore.getCertificate(KEY_ALIAS) as X509Certificate

            // The key and its certificate in one PKCS#12 container.
            val p12 = KeyStore.getInstance(KEY_TYPE)
            p12.load(null, STORE_PASSWORD.toCharArray())
            p12.setKeyEntry(
                "applix",
                privateKey,
                STORE_PASSWORD.toCharArray(),
                arrayOf<Certificate>(cert)
            )
            val keyBytes = ByteArrayOutputStream().use { out ->
                p12.store(out, STORE_PASSWORD.toCharArray())
                out.toByteArray()
            }

            // The record: magic + digest + the key container.
            val payload = ByteArrayOutputStream()
            payload.write(MAGIC)
            payload.write(MessageDigest.getInstance("SHA-256").digest(keyBytes))
            payload.write(keyBytes)
            val bytes = payload.toByteArray()

            val resolver = context.contentResolver
            // Replace an older record instead of piling up copies.
            resolver.delete(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                "${MediaStore.Downloads.DISPLAY_NAME}=?",
                arrayOf(RECORD_NAME)
            )
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, RECORD_NAME)
                put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return null
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            Log.i(TAG, "Master key backed up to the shared Downloads folder")
            RECORD_NAME
        } catch (e: Exception) {
            Log.w(TAG, "Could not back up the master key: ${e.message}")
            null
        }
    }

    /**
     * Restores the master key from the shared record into the AndroidKeyStore.
     * The key itself is unchanged, so every app that was signed with it keeps
     * the same signature and can be updated again.
     */
    fun restore(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
            val resolver = context.contentResolver
            val projection = arrayOf(MediaStore.Downloads._ID)
            val selection = "${MediaStore.Downloads.DISPLAY_NAME}=?"
            val args = arrayOf(RECORD_NAME)
            val bytes = resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, projection, selection, args, null
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return false
                val id = cursor.getLong(0)
                val uri = MediaStore.Downloads.EXTERNAL_CONTENT_URI.buildUpon()
                    .appendPath(id.toString()).build()
                resolver.openInputStream(uri)?.use { it.readBytes() }
            } ?: return false

            if (bytes.size <= MAGIC.size + 32) return false
            for (i in MAGIC.indices) {
                if (bytes[i] != MAGIC[i]) return false
            }
            val expected = bytes.copyOfRange(MAGIC.size, MAGIC.size + 32)
            val keyBytes = bytes.copyOfRange(MAGIC.size + 32, bytes.size)
            if (!MessageDigest.getInstance("SHA-256").digest(keyBytes).contentEquals(expected)) {
                Log.w(TAG, "The key backup is damaged")
                return false
            }

            val p12 = KeyStore.getInstance(KEY_TYPE)
            p12.load(ByteArrayInputStream(keyBytes), STORE_PASSWORD.toCharArray())
            if (!p12.containsAlias("applix")) return false
            val privateKey = p12.getKey("applix", STORE_PASSWORD.toCharArray()) as? PrivateKey
                ?: return false
            val chain = p12.getCertificateChain("applix") ?: return false

            // Put the very same key back into the AndroidKeyStore. The key was
            // created with the standard parameters, so the imported entry needs
            // no protection parameter of its own.
            val keyStore = KeyStore.getInstance(KEY_STORE)
            keyStore.load(null)
            keyStore.setEntry(
                KEY_ALIAS,
                KeyStore.PrivateKeyEntry(privateKey, chain),
                KeyProtection.Builder()
                    .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
                    .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                    .build()
            )
            Log.i(TAG, "Master key restored from the shared backup")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Could not restore the master key: ${e.message}")
            false
        }
    }

    /** Removes the record from the shared storage. */
    fun delete(context: Context) {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
            context.contentResolver.delete(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                "${MediaStore.Downloads.DISPLAY_NAME}=?",
                arrayOf(RECORD_NAME)
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not remove the key backup: ${e.message}")
        }
    }
}
