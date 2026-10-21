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
 * There is no file:// fallback: file access is disabled entirely, so a
 * failed main-frame load shows the offline page instead of weakening the
 * WebView to the pre-0.3 behaviour.
 */
public final class AssetOrigin {

    /** Secure virtual origin provided by androidx.webkit. */
    public static final String ORIGIN = "https://appassets.androidplatform.net";

    /** Path prefix the asset loader is mounted on. */
    public static final String ASSETS_PATH = "/assets/";

    /** The injected app entry point on the secure origin. */
    public static final String APP_URL = ORIGIN + ASSETS_PATH + "app/index.html";

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
     * True for URLs the WebView may load itself: the app's own asset origin,
     * in-memory blobs/data URLs and about:blank. Everything else is either
     * opened by the system browser or blocked.
     */
    public static boolean isTrustedUrl(String url) {
        if (url == null) return false;
        if (url.equals("about:blank")) return true;
        if (url.startsWith("data:") || url.startsWith("blob:")) return true;
        return url.startsWith(ORIGIN + "/") || url.equals(ORIGIN);
    }

    /** True when an http(s) URL points somewhere other than the app origin. */
    public static boolean isExternalHttp(String url) {
        if (url == null) return false;
        boolean http = url.startsWith("http://") || url.startsWith("https://");
        return http && !isTrustedUrl(url);
    }

    /** file:// is never loadable: file access is disabled on the WebView. */
    public static boolean isBlockedScheme(String url) {
        return url != null && url.startsWith("file://");
    }
}
