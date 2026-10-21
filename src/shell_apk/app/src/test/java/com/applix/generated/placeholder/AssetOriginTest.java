package com.applix.generated.placeholder;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** Pure JVM tests for the secure-origin contract (no Android runtime). */
public class AssetOriginTest {

    @Test
    public void appUrlIsServedFromTheSecureOrigin() {
        assertEquals("https://appassets.androidplatform.net/assets/app/index.html",
                AssetOrigin.APP_URL);
        assertTrue(AssetOrigin.APP_URL.startsWith("https://"));
    }

    @Test
    public void fallbackIsTheLegacyFileUrl() {
        assertEquals("file:///android_asset/app/index.html", AssetOrigin.FALLBACK_URL);
    }

    @Test
    public void urlForKeepsTheAssetsPrefix() {
        assertEquals("https://appassets.androidplatform.net/assets/app/main.js",
                AssetOrigin.urlFor("app/main.js"));
        assertEquals("https://appassets.androidplatform.net/assets/app/main.js",
                AssetOrigin.urlFor("/app/main.js"));
    }

    @Test
    public void recognisesAppOriginUrls() {
        assertTrue(AssetOrigin.isAppOrigin(AssetOrigin.APP_URL));
        assertTrue(AssetOrigin.isAppOrigin(AssetOrigin.urlFor("app/vendor/vue.js")));
        assertFalse(AssetOrigin.isAppOrigin("https://example.com/x.js"));
        assertFalse(AssetOrigin.isAppOrigin("file:///android_asset/app/index.html"));
        assertFalse(AssetOrigin.isAppOrigin(null));
    }

    @Test
    public void fallsBackOnlyOnceAndOnlyForTheAppOrigin() {
        assertTrue(AssetOrigin.shouldFallbackToFile(AssetOrigin.APP_URL, false));
        assertFalse(AssetOrigin.shouldFallbackToFile(AssetOrigin.APP_URL, true));
        assertFalse(AssetOrigin.shouldFallbackToFile("https://example.com", false));
        assertFalse(AssetOrigin.shouldFallbackToFile(null, false));
    }
}
