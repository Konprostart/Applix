package com.applix.generated.placeholder;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Log;
import android.webkit.JavascriptInterface;

import org.json.JSONArray;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.List;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Keystore-backed vault for passwords, tokens and API keys.
 *
 * The AES-256-GCM key lives in the Android Keystore and never leaves it; only
 * ciphertext (version byte + IV + tag + payload, Base64) is written to
 * SharedPreferences. Values are therefore unreadable on a rooted device
 * without the keystore entry, and are bound to this app's UID.
 *
 * Exposed to apps as `iappyx.secure.*`. Never log values.
 */
public class SecureVault {
    private static final String TAG = "ApplixVault";
    private static final String KEYSTORE = "AndroidKeyStore";
    private static final String ALIAS = "applix_secure_vault_v1";
    private static final String PREFS = "iappyx_vault";
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int TAG_BITS = 128;
    private static final int MAX_VALUE_BYTES = 256 * 1024;
    private static final int MAX_KEY_LENGTH = 200;

    private final Context context;
    private final Object lock = new Object();

    public SecureVault(Context context) {
        this.context = context.getApplicationContext();
    }

    private SharedPreferences prefs() {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** The keystore key, created on first use. */
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance(KEYSTORE);
        store.load(null);
        KeyStore.Entry entry = store.getEntry(ALIAS, null);
        if (entry instanceof KeyStore.SecretKeyEntry) {
            return ((KeyStore.SecretKeyEntry) entry).getSecretKey();
        }
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE);
        generator.init(new KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(false)
                .setRandomizedEncryptionRequired(true)
                .build());
        return generator.generateKey();
    }

    private static boolean validKey(String key) {
        return key != null && !key.isEmpty() && key.length() <= MAX_KEY_LENGTH;
    }

    @JavascriptInterface
    public boolean set(String key, String value) {
        if (!validKey(key) || value == null) return false;
        if (value.getBytes(StandardCharsets.UTF_8).length > MAX_VALUE_BYTES) return false;
        synchronized (lock) {
            try {
                return prefs().edit().putString(key, seal(key(), value)).commit();
            } catch (Exception e) {
                Log.w(TAG, "set failed: " + e.getClass().getSimpleName());
                return false;
            }
        }
    }

    @JavascriptInterface
    public String get(String key) {
        if (!validKey(key)) return null;
        synchronized (lock) {
            String sealed = prefs().getString(key, null);
            if (sealed == null) return null;
            try {
                return open(key(), sealed);
            } catch (Exception e) {
                Log.w(TAG, "get failed: " + e.getClass().getSimpleName());
                return null;
            }
        }
    }

    @JavascriptInterface
    public boolean has(String key) {
        return validKey(key) && prefs().contains(key);
    }

    @JavascriptInterface
    public boolean remove(String key) {
        if (!validKey(key)) return false;
        synchronized (lock) {
            return prefs().edit().remove(key).commit();
        }
    }

    @JavascriptInterface
    public void clear() {
        synchronized (lock) {
            prefs().edit().clear().commit();
        }
    }

    /** Names only - values always require decryption. */
    @JavascriptInterface
    public String keys() {
        JSONArray array = new JSONArray();
        synchronized (lock) {
            List<String> names = new ArrayList<>(prefs().getAll().keySet());
            Collections.sort(names);
            for (String name : names) array.put(name);
        }
        return array.toString();
    }

    @JavascriptInterface
    public int size() {
        synchronized (lock) {
            return prefs().getAll().size();
        }
    }

    @JavascriptInterface
    public boolean isAvailable() {
        try {
            key();
            return true;
        } catch (Exception e) {
            Log.w(TAG, "keystore unavailable: " + e.getClass().getSimpleName());
            return false;
        }
    }

    // ── crypto ────────────────────────────────────────────────────────────
    // Package-private and Android-free so the format can be unit tested on a
    // plain JVM: version byte (IV length) + IV + ciphertext + GCM tag.

    static String seal(SecretKey key, String plaintext) throws Exception {
        Cipher cipher = Cipher.getInstance(TRANSFORMATION);
        cipher.init(Cipher.ENCRYPT_MODE, key);
        byte[] iv = cipher.getIV();
        byte[] payload = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
        byte[] out = new byte[1 + iv.length + payload.length];
        out[0] = (byte) iv.length;
        System.arraycopy(iv, 0, out, 1, iv.length);
        System.arraycopy(payload, 0, out, 1 + iv.length, payload.length);
        return Base64.getEncoder().encodeToString(out);
    }

    static String open(SecretKey key, String sealed) throws Exception {
        byte[] all = Base64.getDecoder().decode(sealed);
        if (all.length < 2) throw new IllegalArgumentException("sealed value too short");
        int ivLength = all[0] & 0xFF;
        if (ivLength < 12 || ivLength > 16 || all.length < 1 + ivLength + 16) {
            throw new IllegalArgumentException("invalid sealed value");
        }
        Cipher cipher = Cipher.getInstance(TRANSFORMATION);
        cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, all, 1, ivLength));
        byte[] plain = cipher.doFinal(all, 1 + ivLength, all.length - 1 - ivLength);
        return new String(plain, StandardCharsets.UTF_8);
    }
}
