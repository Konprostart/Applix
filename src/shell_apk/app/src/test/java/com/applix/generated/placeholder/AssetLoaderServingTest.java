package com.applix.generated.placeholder;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;

import android.content.Context;
import android.net.Uri;
import android.webkit.WebResourceResponse;

import androidx.webkit.WebViewAssetLoader;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

/**
 * Integration test of the real {@link WebViewAssetLoader} configured exactly
 * like the shell configures it: the loader is built with the same
 * {@link AssetOrigin#ASSETS_PATH} mount and asked to intercept the same URL
 * the shell loads. If this breaks, the secure origin serves nothing and the
 * app would fall back to file:// - the regression this phase must prevent.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class AssetLoaderServingTest {

    private static WebViewAssetLoader newLoader() {
        Context context = RuntimeEnvironment.getApplication();
        return new WebViewAssetLoader.Builder()
                .addPathHandler(AssetOrigin.ASSETS_PATH,
                        new WebViewAssetLoader.AssetsPathHandler(context))
                .build();
    }

    @Test
    public void servesAnAppAssetThroughTheSecureOrigin() throws Exception {
        WebResourceResponse response =
                newLoader().shouldInterceptRequest(Uri.parse(AssetOrigin.urlFor("app/loader_probe.txt")));
        assertNotNull("the secure origin served nothing", response);
        assertEquals("applix-loader-ok", readAll(response.getData()).trim());
    }

    @Test
    public void doesNotInterceptForeignOrigins() {
        assertNull("the loader must not hijack other origins",
                newLoader().shouldInterceptRequest(Uri.parse("https://example.com/app.js")));
    }

    @Test
    public void doesNotInterceptTheFileFallback() {
        assertNull("the loader must not claim file:// URLs",
                newLoader().shouldInterceptRequest(Uri.parse(AssetOrigin.FALLBACK_URL)));
    }

    private static String readAll(InputStream in) throws Exception {
        assertNotNull(in);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[4096];
        int read;
        while ((read = in.read(buffer)) != -1) out.write(buffer, 0, read);
        in.close();
        return out.toString("UTF-8");
    }
}
