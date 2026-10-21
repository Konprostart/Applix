package com.applix.generated.placeholder;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;

import android.content.Context;
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
 * Integration test of the real {@link WebViewAssetLoader.AssetsPathHandler}:
 * it serves files from the APK assets through the same handler the shell
 * installs. If this breaks, the secure origin serves nothing and the app
 * would silently fall back to file:// - exactly the failure this phase must
 * prevent.
 */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 34)
public class AssetLoaderServingTest {

    @Test
    public void servesAssetsAppResources() throws Exception {
        Context context = RuntimeEnvironment.getApplication();
        WebViewAssetLoader.AssetsPathHandler handler =
                new WebViewAssetLoader.AssetsPathHandler(context);

        WebResourceResponse response = handler.handle("/app/loader_probe.txt");
        assertNotNull("the probe asset was not served", response);
        assertEquals("applix-loader-ok", readAll(response.getData()).trim());
    }

    @Test
    public void missingAssetFailsInsteadOfReturningGarbage() {
        Context context = RuntimeEnvironment.getApplication();
        WebViewAssetLoader.AssetsPathHandler handler =
                new WebViewAssetLoader.AssetsPathHandler(context);
        assertNull(handler.handle("/app/does-not-exist.txt"));
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
