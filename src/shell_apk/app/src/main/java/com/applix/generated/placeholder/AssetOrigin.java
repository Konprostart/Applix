package com.applix.generated.placeholder;

/**
 * Single source of truth for where the app document is served from.
 *
 * Phase 1 of the architecture upgrade: the app is served over the secure
 * WebViewAssetLoader origin instead of file://, so the WebView gets a real
 * https origin. That unlocks ES modules, Web Workers, IndexedDB, fetch() for
 * same-origin assets and a working Content-Security-Policy. The bridge
 * (addJavascriptInterface) does not depend on the origin and stays untouched.
 *
 * When anything goes wrong with asset interception, the shell falls back to
 * {@link #FALLBACK_URL}, which is the pre-0.3 behaviour.
 */
public final class AssetOrigin {

    /** Secure virtual origin provided by androidx.webkit. */
    public static final String ORIGIN = "https://appassets.androidplatform.net";

    /** Path prefix the asset loader is mounted on. */
    public static final String ASSETS_PATH = "/assets/";

    /** The injected app entry point on the secure origin. */
    public static final String APP_URL = ORIGIN + ASSETS_PATH + "app/index.html";

    /** The legacy location inside the APK, used only as a fallback. */
    public static final String FALLBACK_URL = "file:///android_asset/app/index.html";

    /** Asset path (relative to the assets/ folder) of the app entry point. */
    public static final String APP_ASSET_PATH = "app/index.html";

    private AssetOrigin() {
    }

    /** Maps an assets-relative path to its secure-origin URL. */
    public static String urlFor(String assetPath) {
        if (assetPath == null) return ORIGIN + ASSETS_PATH;
        String clean = assetPath.startsWith("/") ? assetPath.substring(1) : assetPath;
        return ORIGIN + ASSETS_PATH + clean;
    }

    /** True when the URL is served by the asset loader. */
    public static boolean isAppOrigin(String url) {
        return url != null && url.startsWith(ORIGIN + ASSETS_PATH);
    }

    /**
     * True when a failed main-frame load should be retried on file://.
     * Only an app-origin failure qualifies, and only once per page load.
     */
    public static boolean shouldFallbackToFile(String failingUrl, boolean alreadyTried) {
        return !alreadyTried && isAppOrigin(failingUrl);
    }
}
