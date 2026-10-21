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
    public void trustsOnlyTheAppOriginAndInMemoryUrls() {
        assertTrue(AssetOrigin.isTrustedUrl(AssetOrigin.APP_URL));
        assertTrue(AssetOrigin.isTrustedUrl("about:blank"));
        assertTrue(AssetOrigin.isTrustedUrl("data:text/html,x"));
        assertTrue(AssetOrigin.isTrustedUrl("blob:https://appassets.androidplatform.net/1"));
        assertFalse(AssetOrigin.isTrustedUrl("https://example.com/app.js"));
        assertFalse(AssetOrigin.isTrustedUrl("file:///android_asset/app/index.html"));
        assertFalse(AssetOrigin.isTrustedUrl(null));
    }

    @Test
    public void externalHttpIsEverythingButTheAppOrigin() {
        assertTrue(AssetOrigin.isExternalHttp("https://example.com"));
        assertTrue(AssetOrigin.isExternalHttp("http://example.com"));
        assertFalse(AssetOrigin.isExternalHttp(AssetOrigin.APP_URL));
        assertFalse(AssetOrigin.isExternalHttp("mailto:a@b.com"));
        assertFalse(AssetOrigin.isExternalHttp(null));
    }

    @Test
    public void fileSchemeIsBlocked() {
        assertTrue(AssetOrigin.isBlockedScheme("file:///android_asset/app/index.html"));
        assertFalse(AssetOrigin.isBlockedScheme(AssetOrigin.APP_URL));
        assertFalse(AssetOrigin.isBlockedScheme(null));
    }
}
