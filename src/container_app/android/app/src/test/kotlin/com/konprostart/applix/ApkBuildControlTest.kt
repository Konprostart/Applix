/*
 * Control test for the two things that broke user apps before:
 *
 *  1. The app name has to be exactly what the user typed - no placeholder
 *     left over and a correct string pool length in the binary manifest.
 *  2. The UI Kit has to be applied to every template.
 *
 * The test runs on the real shell template (the APK the generated apps are
 * built from), so it fails if the shell and the injector ever drift apart.
 */
package com.konprostart.applix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.zip.ZipFile

class ApkBuildControlTest {

    private val injector = ApkInjector()

    private fun templateManifest(): ByteArray {
        val candidates = listOf(
            File("../../assets/shell_template.apk"),
            File("src/container_app/assets/shell_template.apk")
        )
        val apk = candidates.firstOrNull { it.exists() }
            ?: error("shell template not found (looked at ${candidates.map { it.path }})")
        return ZipFile(apk).use { zip ->
            val entry = zip.getEntry("AndroidManifest.xml")
                ?: error("AndroidManifest.xml missing in ${apk.path}")
            zip.getInputStream(entry).readBytes()
        }
    }

    /** The length prefix of a string pool entry is the two bytes before it. */
    private fun storedLength(data: ByteArray, needle: ByteArray): Int {
        val idx = data.indexOf(needle)
        assertTrue("string not found in the patched manifest", idx > 1)
        return (data[idx - 2].toInt() and 0xFF) or ((data[idx - 1].toInt() and 0xFF) shl 8)
    }

    private fun ByteArray.indexOf(needle: ByteArray): Int {
        outer@ for (i in 0..size - needle.size) {
            for (j in needle.indices) if (this[i + j] != needle[j]) continue@outer
            return i
        }
        return -1
    }

    @Test
    fun theAppNameIsExactlyTheNameTheUserTyped() {
        val name = "Moj Radio"
        val packageName = "com.applix.gen.radio.a1b2c3"
        val patched = injector.patchManifest(templateManifest(), packageName, name)

        val nameUtf16 = name.toByteArray(Charsets.UTF_16LE)
        assertTrue("the app name is not in the manifest", patched.indexOf(nameUtf16) > 0)
        assertFalse(
            "the label placeholder is still in the manifest",
            patched.indexOf(ApkInjector.LABEL_PLACEHOLDER.toByteArray(Charsets.UTF_16LE)) >= 0
        )
        assertEquals("wrong string pool length for the app name", name.length, storedLength(patched, nameUtf16))
    }

    @Test
    fun thePackageIsReplacedEverywhere() {
        val packageName = "com.applix.gen.radio.a1b2c3"
        val patched = injector.patchManifest(templateManifest(), packageName, "Radio")

        assertFalse(
            "the template package is still in the manifest",
            patched.indexOf(ApkInjector.TEMPLATE_PACKAGE.toByteArray(Charsets.UTF_16LE)) >= 0
        )
        assertTrue(
            "the new package is not in the manifest",
            patched.indexOf(packageName.toByteArray(Charsets.UTF_16LE)) > 0
        )
    }

    @Test
    fun aNameThatDoesNotFitThePlaceholderIsRejected() {
        val tooLong = "x".repeat(ApkInjector.LABEL_PLACEHOLDER.length + 1)
        val failed = try {
            injector.patchManifest(templateManifest(), "com.applix.gen.radio.a1b2c3", tooLong)
            false
        } catch (e: IllegalArgumentException) {
            true
        }
        assertTrue("a name that does not fit must be rejected", failed)
    }

    @Test
    fun aNameThatFitsExactlyIsAccepted() {
        val exact = "x".repeat(ApkInjector.LABEL_PLACEHOLDER.length)
        val patched = injector.patchManifest(templateManifest(), "com.applix.gen.radio.a1b2c3", exact)
        assertTrue(
            "the exact length name is not in the manifest",
            patched.indexOf(exact.toByteArray(Charsets.UTF_16LE)) > 0
        )
    }

    @Test
    fun theUiKitIsAppliedToEveryTemplate() {
        val cssFile = File("../../assets/applix-ui.css").takeIf { it.exists() }
            ?: File("src/container_app/assets/applix-ui.css")
        val css = cssFile.readText()
        val html = "<html><head><title>T</title></head><body><h1>Hello</h1></body></html>"

        val themed = AppGenerator.applyUiKit(html, css)
        assertTrue("the UI Kit is not in the template", themed.contains("id=\"applix-ui-kit\""))
        assertTrue("the UI Kit is not the first stylesheet", themed.indexOf("applix-ui-kit") < themed.indexOf("</head>"))

        val twice = AppGenerator.applyUiKit(themed, css)
        assertEquals("the UI Kit was injected twice", themed, twice)
    }

    @Test
    fun theUiKitModuleIsShippedAndSelfContained() {
        val jsFile = File("../../assets/applix-ui.js").takeIf { it.exists() }
            ?: File("src/container_app/assets/applix-ui.js")
        val js = jsFile.readText()
        assertTrue("the UI Kit module has no version", js.contains("export const UI_KIT_VERSION"))
        for (fn in listOf(
            "toast", "openSheet", "confirmDialog", "mountTabs",
            "mountBottomNav", "mountSegmented", "stagger"
        )) {
            assertTrue("the UI Kit module does not export $fn", js.contains("export function $fn("))
        }
        assertFalse(
            "the UI Kit module must not depend on other modules",
            Regex("(?m)^\\s*import\\s").containsMatchIn(js)
        )
        assertFalse("the UI Kit module must not call the bridge", js.contains("iappyx"))
    }

    @Test
    fun aTemplateCanOptOutOfTheUiKit() {
        val cssFile = File("../../assets/applix-ui.css").takeIf { it.exists() }
            ?: File("src/container_app/assets/applix-ui.css")
        val css = cssFile.readText()
        val html = "<html><head><meta name=\"applix-ui\" content=\"off\"></head><body></body></html>"
        assertEquals("the opt out was ignored", html, AppGenerator.applyUiKit(html, css))
    }
}
