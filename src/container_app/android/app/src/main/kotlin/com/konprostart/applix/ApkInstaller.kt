/*
 * MIT License
 *
 * Copyright (c) 2026 iappyx
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Installs generated APKs via the Android PackageInstaller session API.

package com.konprostart.applix

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Applix APK Installer
 *
 * Installs APKs using Android's PackageInstaller API.
 * No root required. Shows the standard Android install dialog.
 *
 * This is the same API used by:
 * - Google Play Store
 * - Firefox (web app shortcuts)
 * - Any app that installs other APKs legitimately
 */
class ApkInstaller(private val context: Context) {

    companion object {
        private const val TAG = "Applix"
        private const val ACTION_INSTALL_RESULT = "com.konprostart.applix.INSTALL_RESULT"
    }

    /**
     * Install an APK. Shows the system install dialog.
     * Suspends until the user taps Install or Cancel.
     *
     * Requires: android.permission.REQUEST_INSTALL_PACKAGES
     * The user must also enable "Install unknown apps" for the container app.
     */
    suspend fun install(apkFile: File): Unit = installInternal(apkFile, null)

    /**
     * Install an APK after verifying its SHA-256 against [expectedSha256].
     *
     * The verification happens on the file that is about to be installed, so a
     * file that was truncated, swapped or purged between the download and the
     * install can never reach the package installer.
     */
    suspend fun installVerified(apkFile: File, expectedSha256: String): Unit =
        installInternal(apkFile, expectedSha256)

    private suspend fun installInternal(apkFile: File, expectedSha256: String?): Unit =
        suspendCancellableCoroutine { cont ->
        val packageInstaller = context.packageManager.packageInstaller

        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        ).apply {
            setAppLabel("Applix Generated App")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
            }
        }

        // The app needs the "install unknown apps" permission - without it the
        // system refuses the install with a generic error.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !context.packageManager.canRequestPackageInstalls()
            ) {
                cont.resumeWithException(
                    InstallException("ALLOW_INSTALL_UNKNOWN: allow Applix to install apps")
                )
                return@suspendCancellableCoroutine
            }
        } catch (ignored: Exception) {
        }

        // Validate the file before anything is staged.
        if (!apkFile.exists() || apkFile.length() <= 0L) {
            cont.resumeWithException(InstallException("The APK file is missing or empty"))
            return@suspendCancellableCoroutine
        }
        if (!expectedSha256.isNullOrBlank()) {
            val actual = sha256(apkFile)
            if (!actual.equals(expectedSha256.trim(), ignoreCase = true)) {
                cont.resumeWithException(
                    InstallException("Checksum mismatch - the APK changed before it could be installed")
                )
                return@suspendCancellableCoroutine
            }
        }

        val sessionId = packageInstaller.createSession(params)
        val session = packageInstaller.openSession(sessionId)

        // Write APK bytes to session.
        // The written byte count is verified against the file size BEFORE the
        // session is committed: a short write would otherwise be committed as
        // a truncated package and the system would report it as invalid.
        val expectedLength = apkFile.length()
        try {
            var written = 0L
            apkFile.inputStream().use { input ->
                session.openWrite("package", 0, expectedLength).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        output.write(buffer, 0, read)
                        written += read
                    }
                    if (written != expectedLength) {
                        throw java.io.IOException(
                            "Only $written of $expectedLength bytes reached the install session"
                        )
                    }
                    session.fsync(output)
                }
            }
        } catch (e: Exception) {
            session.close()
            throw e
        }

        // State tracking: flip to false when the receiver is unregistered, so re-entry
        // and cancellation can't double-unregister (IllegalArgumentException crash) or
        // drop a final-status broadcast that arrives while we were briefly unregistered.
        var registered = false
        lateinit var receiver: BroadcastReceiver
        val unregisterSafely: () -> Unit = {
            if (registered) {
                try { context.unregisterReceiver(receiver) } catch (_: Exception) {}
                registered = false
            }
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)

                when (status) {
                    PackageInstaller.STATUS_SUCCESS -> {
                        // Terminal — unregister and resume.
                        unregisterSafely()
                        Log.i(TAG, "Install success")
                        cont.resume(Unit)
                    }

                    PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                        // NOT terminal. Keep receiver registered so the follow-up
                        // STATUS_SUCCESS/STATUS_FAILURE broadcast still lands here.
                        val confirmIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(Intent.EXTRA_INTENT)
                        }
                        if (confirmIntent != null) {
                            confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(confirmIntent)
                        }
                    }

                    else -> {
                        // Terminal failure — unregister and resume with exception.
                        unregisterSafely()
                        Log.e(TAG, "Install failed (status $status): $message")
                        cont.resumeWithException(
                            InstallException("Install failed: $message (status $status)")
                        )
                    }
                }
            }
        }

        val intent = Intent(ACTION_INSTALL_RESULT).apply {
            setPackage(context.packageName)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pendingIntent = PendingIntent.getBroadcast(context, sessionId, intent, flags)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(
                receiver,
                IntentFilter(ACTION_INSTALL_RESULT),
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, IntentFilter(ACTION_INSTALL_RESULT))
        }
        registered = true

        session.commit(pendingIntent.intentSender)
        session.close()

        cont.invokeOnCancellation { unregisterSafely() }
    }

    /** SHA-256 of a file, hex encoded. */
    private fun sha256(file: File): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    class InstallException(message: String) : Exception(message)
}
