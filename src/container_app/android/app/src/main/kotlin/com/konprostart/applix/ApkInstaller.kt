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
import androidx.core.content.FileProvider
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
        private val HEX = "0123456789abcdef".toCharArray()
    }

    /**
     * Install an APK. Shows the system install dialog.
     * Suspends until the user taps Install or Cancel.
     *
     * Requires: android.permission.REQUEST_INSTALL_PACKAGES
     * The user must also enable "Install unknown apps" for the container app.
     */
    suspend fun install(apkFile: File, packageName: String? = null): Unit =
        installInternal(apkFile, null, packageName)

    /**
     * Install an APK after verifying its SHA-256 against [expectedSha256].
     *
     * The verification happens on the file that is about to be installed, so a
     * file that was truncated, swapped or purged between the download and the
     * install can never reach the package installer.
     */
    suspend fun installVerified(apkFile: File, expectedSha256: String, packageName: String? = null): Unit =
        installInternal(apkFile, expectedSha256, packageName)

    private suspend fun installInternal(apkFile: File, expectedSha256: String?, packageName: String?): Unit =
        suspendCancellableCoroutine { cont ->
        // The application context outlives the Activity - the install must keep
        // working (and keep its receiver) when the Activity is destroyed, which is
        // exactly what happens when the system replaces the app with a new version.
        val appContext = context.applicationContext
        val packageInstaller = appContext.packageManager.packageInstaller

        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        ).apply {
            setAppLabel("Applix App")
            // Telling the system which package and how big the file is makes the
            // install smoother (it can pre-allocate and validate up front).
            if (!packageName.isNullOrBlank()) {
                try { setAppPackageName(packageName) } catch (ignored: Exception) {}
            }
            try { setSize(apkFile.length()) } catch (ignored: Exception) {}
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
            }
        }

        // The app needs the "install unknown apps" permission - without it the
        // system refuses the install with a generic error.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !appContext.packageManager.canRequestPackageInstalls()
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
        // The file that is about to be installed must carry the master signature -
        // this is the last checkpoint before the system sees it.
        val archiveProblem = verifyArchiveSignature(apkFile)
        if (archiveProblem != null) {
            cont.resumeWithException(InstallException(archiveProblem))
            return@suspendCancellableCoroutine
        }
        // An older copy of this app with a different signature is installed:
        // the system would only say "package invalid". Detect it here so the
        // app can offer to replace it.
        val conflict = detectSignatureConflict(apkFile)
        if (conflict != null) {
            cont.resumeWithException(InstallException(conflict))
            return@suspendCancellableCoroutine
        }
        // The archive must be signed with the same key as the installed app and
        // must be newer - otherwise Android refuses it with a cryptic message.
        val problem = verifyArchive(apkFile)
        if (problem != null) {
            cont.resumeWithException(InstallException(problem))
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

        // Log exactly which file goes to the system, so a problem can be traced.
        Log.i(TAG, "Installing ${apkFile.absolutePath} (${apkFile.length()} bytes)")

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
            if (written != expectedLength) {
                session.close()
                throw java.io.IOException(
                    "Only $written of $expectedLength bytes reached the install session"
                )
            }
            Log.i(TAG, "Staged $written bytes in the install session")
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
                try { appContext.unregisterReceiver(receiver) } catch (_: Exception) {}
                registered = false
            }
        }

        // The continuation can be resumed at most once. A second resume (or a resume
        // after the coroutine was cancelled) throws inside the broadcast receiver and
        // takes the whole app down - this flag makes that impossible.
        val finished = java.util.concurrent.atomic.AtomicBoolean(false)

        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                try {
                    val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
                    val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)

                    when (status) {
                        PackageInstaller.STATUS_SUCCESS -> {
                            // Terminal - unregister and resume.
                            if (finished.compareAndSet(false, true)) {
                                unregisterSafely()
                                Log.i(TAG, "Install success")
                                if (cont.isActive) cont.resume(Unit)
                            }
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
                                try {
                                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    appContext.startActivity(confirmIntent)
                                } catch (e: Exception) {
                                    Log.e(TAG, "Could not show the install dialog: ${e.message}")
                                    if (finished.compareAndSet(false, true)) {
                                        unregisterSafely()
                                        if (cont.isActive) {
                                            cont.resumeWithException(
                                                InstallException("The system install dialog could not be shown")
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        else -> {
                            // Terminal failure - unregister and resume with exception.
                            if (finished.compareAndSet(false, true)) {
                                unregisterSafely()
                                Log.e(TAG, "Install failed (status $status): $message")
                                if (cont.isActive) {
                                    cont.resumeWithException(
                                        InstallException("Install failed: $message (status $status)")
                                    )
                                }
                            }
                        }
                    }
                } catch (t: Throwable) {
                    // An uncaught exception inside a BroadcastReceiver kills the app.
                    Log.e(TAG, "Install receiver error: ${t.message}")
                    if (finished.compareAndSet(false, true)) {
                        unregisterSafely()
                        if (cont.isActive) {
                            cont.resumeWithException(InstallException("Install failed: ${t.message}"))
                        }
                    }
                }
            }
        }

        val intent = Intent(ACTION_INSTALL_RESULT).apply {
            setPackage(appContext.packageName)
        }

        // FLAG_MUTABLE is REQUIRED on Android 12+: the package installer fills the
        // status extras into this PendingIntent. Do not "fix" this to IMMUTABLE -
        // the install would never report its result.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT

        val pendingIntent = PendingIntent.getBroadcast(appContext, sessionId, intent, flags)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                appContext.registerReceiver(
                    receiver,
                    IntentFilter(ACTION_INSTALL_RESULT),
                    Context.RECEIVER_NOT_EXPORTED
                )
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                appContext.registerReceiver(receiver, IntentFilter(ACTION_INSTALL_RESULT))
            }
            registered = true
        } catch (e: Exception) {
            try { session.close() } catch (_: Exception) {}
            cont.resumeWithException(InstallException("Could not watch the install: ${e.message}"))
            return@suspendCancellableCoroutine
        }

        try {
            session.commit(pendingIntent.intentSender)
        } catch (e: Exception) {
            unregisterSafely()
            try { session.close() } catch (_: Exception) {}
            Log.e(TAG, "Commit failed: ${e.message}")
            cont.resumeWithException(InstallException("Could not start the install: ${e.message}"))
            return@suspendCancellableCoroutine
        }
        session.close()

        cont.invokeOnCancellation { unregisterSafely() }
    }

    /**
     * Opens the system installer for an APK file (the classic ACTION_VIEW path).
     *
     * This is the fallback when the package installer session does not produce
     * a result: the file is handed to the system installer through a
     * FileProvider content:// URI, the user confirms and Android installs it.
     */
    fun installViaSystemInstaller(apkFile: File): Boolean {
        return try {
            if (!apkFile.exists() || apkFile.length() <= 0L) return false
            val uri = FileProvider.getUriForFile(
                context,
                context.packageName + ".fileprovider",
                apkFile
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "System installer could not be opened: ${e.message}")
            false
        }
    }

    /**
     * Reads the signers out of an APK file with the platform parser and compares
     * them with the master key. Returns an error message or null when the file
     * carries the right signature.
     */
    private fun verifyArchiveSignature(apkFile: File): String? {
        return try {
            val pm = context.packageManager
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                0
            }
            val archive = pm.getPackageArchiveInfo(apkFile.absolutePath, flags)
                ?: return "The built APK cannot be read - it is not a valid package"
            val digests = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                archive.signingInfo?.apkContentsSigners?.map { KeystoreService.digest(it.toByteArray()) }
                    ?: emptyList()
            } else {
                @Suppress("DEPRECATION")
                archive.signatures?.map { KeystoreService.digest(it.toByteArray()) } ?: emptyList()
            }
            if (digests.isEmpty()) {
                return "The built APK carries no signature"
            }
            val master = KeystoreService.fingerprint(context)
            if (!digests.contains(master)) {
                Log.e(TAG, "APK signature $digests does not match the master key $master")
                return "The built APK is signed with a different key than Applix uses"
            }
            Log.i(TAG, "APK signature verified against the master key (${apkFile.absolutePath})")
            null
        } catch (e: Exception) {
            "Could not verify the signature of the APK: ${e.message}"
        }
    }

    /**
     * Detects an installed copy of the app that was signed with a different key.
     * Returns "SIGNATURE_CONFLICT:<package>" or null when there is no conflict.
     */
    private fun detectSignatureConflict(apkFile: File): String? {
        return try {
            val pm = context.packageManager
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                0
            }
            val archive = pm.getPackageArchiveInfo(apkFile.absolutePath, flags) ?: return null
            val packageName = archive.packageName ?: return null
            val installed = try {
                pm.getPackageInfo(packageName, flags)
            } catch (e: Exception) {
                return null // not installed -> nothing to replace
            }
            val installedSigs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                installed.signingInfo?.apkContentsSigners?.map { KeystoreService.digest(it.toByteArray()) }
                    ?: emptyList()
            } else {
                @Suppress("DEPRECATION")
                installed.signatures?.map { KeystoreService.digest(it.toByteArray()) } ?: emptyList()
            }
            val archiveSigs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                archive.signingInfo?.apkContentsSigners?.map { KeystoreService.digest(it.toByteArray()) }
                    ?: emptyList()
            } else {
                @Suppress("DEPRECATION")
                archive.signatures?.map { KeystoreService.digest(it.toByteArray()) } ?: emptyList()
            }
            if (installedSigs.isEmpty() || archiveSigs.isEmpty()) return null
            if (installedSigs.toSet() == archiveSigs.toSet()) return null
            Log.w(TAG, "Signature conflict for $packageName: installed $installedSigs, new $archiveSigs")
            "SIGNATURE_CONFLICT:$packageName"
        } catch (e: Exception) {
            Log.w(TAG, "Could not check for a signature conflict: ${e.message}")
            null
        }
    }

    /**
     * Checks the downloaded APK against the installed app: same signature and
     * a higher version code. Returns an error message or null when it is fine.
     */
    private fun verifyArchive(apkFile: File): String? {
        return try {
            val pm = context.packageManager
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                0
            }
            val archive = pm.getPackageArchiveInfo(apkFile.absolutePath, flags)
                ?: return "The downloaded file is not a valid APK"
            val installed = pm.getPackageInfo(context.packageName, flags)

            // Signature
            val archiveSigners = signersOf(archive)
            val installedSigners = signersOf(installed)
            if (archiveSigners.isEmpty() || installedSigners.isEmpty()) {
                return "Could not read the signature of the update"
            }
            if (archiveSigners.toSet() != installedSigners.toSet()) {
                return "The update is signed with a different key than the installed app"
            }

            // Version
            val archiveVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                archive.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                archive.versionCode.toLong()
            }
            val installedVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                installed.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                installed.versionCode.toLong()
            }
            if (archiveVersion <= installedVersion) {
                return "The update (version code $archiveVersion) is not newer than the " +
                    "installed app (version code $installedVersion)"
            }
            null
        } catch (e: Exception) {
            "Could not check the update: ${e.message}"
        }
    }

    @Suppress("DEPRECATION")
    private fun signersOf(info: android.content.pm.PackageInfo): List<String> {
        val signatures = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.signingInfo?.apkContentsSigners?.map { it.toByteArray().toHex() } ?: emptyList()
            } else {
                info.signatures?.map { it.toByteArray().toHex() } ?: emptyList()
            }
        } catch (e: Exception) {
            emptyList()
        }
        return signatures
    }

    private fun ByteArray.toHex(): String {
        val out = StringBuilder(size * 2)
        for (b in this) {
            val v = b.toInt() and 0xFF
            out.append(HEX[v ushr 4]).append(HEX[v and 0x0F])
        }
        return out.toString()
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
