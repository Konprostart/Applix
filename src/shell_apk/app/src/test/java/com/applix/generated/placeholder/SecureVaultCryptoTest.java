package com.applix.generated.placeholder;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import javax.crypto.AEADBadTagException;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

/**
 * The vault's on-disk format is version byte + IV + ciphertext + GCM tag,
 * Base64 encoded. These tests run on a plain JVM: they prove the crypto is
 * real (AES-GCM, random IV, tamper detection) without needing the Android
 * Keystore, which is exercised on-device.
 */
public class SecureVaultCryptoTest {

    private static SecretKey aesKey() throws Exception {
        KeyGenerator generator = KeyGenerator.getInstance("AES");
        generator.init(256);
        return generator.generateKey();
    }

    @Test
    public void roundTripsAsciiUnicodeAndEmptyValues() throws Exception {
        SecretKey key = aesKey();
        for (String value : new String[]{"", "s3cr3t-token", "šđčćž 🔐 ключ"}) {
            String sealed = SecureVault.seal(key, value);
            assertEquals(value, SecureVault.open(key, sealed));
        }
    }

    @Test
    public void everySealUsesAFreshIv() throws Exception {
        SecretKey key = aesKey();
        String first = SecureVault.seal(key, "same-value");
        String second = SecureVault.seal(key, "same-value");
        assertFalse("IV reuse: two seals are identical", first.equals(second));
        assertEquals("same-value", SecureVault.open(key, first));
        assertEquals("same-value", SecureVault.open(key, second));
    }

    @Test
    public void thePlaintextNeverAppearsInTheSealedBlob() throws Exception {
        SecretKey key = aesKey();
        String value = "super-secret-password-42";
        String sealed = SecureVault.seal(key, value);
        assertFalse(sealed.contains(value));
        String raw = new String(Base64.getDecoder().decode(sealed), StandardCharsets.ISO_8859_1);
        assertFalse(raw.contains(value));
    }

    @Test
    public void aTamperedPayloadIsRejected() throws Exception {
        SecretKey key = aesKey();
        byte[] raw = Base64.getDecoder().decode(SecureVault.seal(key, "balance=100"));
        raw[raw.length - 1] ^= 0x01;
        try {
            SecureVault.open(key, Base64.getEncoder().encodeToString(raw));
            fail("tampered ciphertext was accepted");
        } catch (AEADBadTagException expected) {
            // GCM authentication tag caught it.
        }
    }

    @Test
    public void aDifferentKeyCannotOpenTheValue() throws Exception {
        String sealed = SecureVault.seal(aesKey(), "private");
        try {
            SecureVault.open(aesKey(), sealed);
            fail("a different AES key decrypted the value");
        } catch (AEADBadTagException expected) {
            // Wrong key.
        }
    }

    @Test
    public void malformedBlobsAreRejectedWithoutCrashing() throws Exception {
        SecretKey key = aesKey();
        for (String bad : new String[]{"", "AA==", "not-base64!!", "////"}) {
            try {
                String opened = SecureVault.open(key, bad);
                fail("accepted malformed blob: " + opened);
            } catch (Exception expected) {
                assertNotNull(expected.getMessage());
            }
        }
    }

    @Test
    public void sealProducesAVersionedBase64Blob() throws Exception {
        SecretKey key = aesKey();
        byte[] raw = Base64.getDecoder().decode(SecureVault.seal(key, "x"));
        int ivLength = raw[0] & 0xFF;
        assertTrue("unexpected IV length " + ivLength, ivLength >= 12 && ivLength <= 16);
        assertTrue("payload is too short to hold a GCM tag", raw.length >= 1 + ivLength + 16);
    }
}
