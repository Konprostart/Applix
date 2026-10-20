// MIT License — Copyright (c) 2026 iappyx

package com.konprostart.applix

import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.security.KeyPair
import java.security.interfaces.RSAPublicKey
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Creates a self signed X.509 certificate for the master key.
 *
 * The AndroidKeyStore cannot export a private key and the JKS provider
 * (which would generate a self signed certificate for us) reaches into
 * sun.security.* internals that are not part of the Android runtime. So the
 * certificate is encoded here by hand - a small, well defined DER writer.
 */
object SelfSignedCert {

    /** The ASN.1 NULL parameter (no content). */
    private val NULL = byteArrayOf(0x05, 0x00)

    private val OID_RSA_ENCRYPTION = byteArrayOf(
        0x2A.toByte(), 0x86.toByte(), 0x48.toByte(), 0x86.toByte(), 0xF7.toByte(),
        0x0D.toByte(), 0x01.toByte(), 0x01.toByte(), 0x01
    )
    private val OID_SHA256_WITH_RSA = byteArrayOf(
        0x2A.toByte(), 0x86.toByte(), 0x48.toByte(), 0x86.toByte(), 0xF7.toByte(),
        0x0D.toByte(), 0x01.toByte(), 0x01.toByte(), 0x0B.toByte()
    )
    private val OID_CN = byteArrayOf(0x55, 0x04, 0x03)
    private val OID_O = byteArrayOf(0x55, 0x04, 0x0A)
    private val OID_C = byteArrayOf(0x55, 0x04, 0x06)

    /**
     * @param subject a slash separated DN, e.g. "CN=Applix/O=Konprostart/C=NL"
     */
    fun create(
        keyPair: KeyPair,
        subject: String,
        notBefore: Date,
        notAfter: Date,
        serial: BigInteger = BigInteger.valueOf(System.currentTimeMillis()),
    ): X509Certificate {
        val name = encodeName(subject)

        val tbs = der(
            0x30,
            der(0xA0, der(0x02, byteArrayOf(0x02))) +                       // version v3
                der(0x02, serial.toPositiveDer()) +                     // serial number
                der(0x30, der(0x06, OID_SHA256_WITH_RSA) + NULL) +
                name +                                                        // issuer
                der(0x30, der(0x18, generalTime(notBefore)) + der(0x18, generalTime(notAfter))) +
                name +                                                        // subject
                der(0x30, der(0x30, der(0x06, OID_RSA_ENCRYPTION) + NULL) +
                    der(0x03, bitString(rsaPublicKeyDer(keyPair))))          // public key
        )

        val signature = Signature.getInstance("SHA256withRSA").run {
            initSign(keyPair.private)
            update(tbs)
            sign()
        }

        val certDer = der(
            0x30,
            tbs +
                der(0x30, der(0x06, OID_SHA256_WITH_RSA) + NULL) +
                der(0x03, bitString(signature))
        )

        return CertificateFactory.getInstance("X.509")
            .generateCertificate(certDer.inputStream()) as X509Certificate
    }

    // ── DER helpers ──────────────────────────────────────────────────────────

    private fun der(tag: Int, content: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(tag)
        out.write(derLength(content.size))
        out.write(content)
        return out.toByteArray()
    }

    private fun derLength(length: Int): ByteArray {
        if (length < 0x80) return byteArrayOf(length.toByte())
        val bytes = ArrayList<Byte>()
        var value = length
        while (value > 0) {
            bytes.add(0, (value and 0xFF).toByte())
            value = value ushr 8
        }
        val out = ByteArrayOutputStream()
        out.write(0x80 or bytes.size)
        bytes.forEach { out.write(it.toInt()) }
        return out.toByteArray()
    }

    /** A BIT STRING with no unused bits. */
    private fun bitString(data: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(0x00) // unused bits
        out.write(data)
        return out.toByteArray()
    }

    /** GeneralizedTime - UTCTime cannot express years after 2049. */
    private fun generalTime(date: Date): ByteArray {
        val format = SimpleDateFormat("yyyyMMddHHmmss'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(date).toByteArray(Charsets.US_ASCII)
    }

    /** The raw PKCS#1 RSAPublicKey (the content of the SubjectPublicKeyInfo
     *  BIT STRING) - that is what goes into the certificate. */
    private fun rsaPublicKeyDer(keyPair: KeyPair): ByteArray {
        val public = keyPair.public as RSAPublicKey
        return der(
            0x30,
            der(0x02, public.modulus.toPositiveDer()) +
                der(0x02, public.publicExponent.toPositiveDer())
        )
    }

    /** A positive BigInteger as DER INTEGER content. */
    private fun BigInteger.toPositiveDer(): ByteArray {
        val raw = toByteArray()
        if (raw.isEmpty()) return byteArrayOf(0)
        if (raw[0].toInt() < 0) return byteArrayOf(0) + raw
        return raw
    }

    /** A DN like "CN=Applix/O=Konprostart/C=NL" as an X.501 Name. */
    private fun encodeName(subject: String): ByteArray {
        val rdns = ArrayList<ByteArray>()
        for (part in subject.split('/')) {
            if (part.isBlank()) continue
            val idx = part.indexOf('=')
            if (idx <= 0) continue
            val type = part.substring(0, idx).trim().uppercase(Locale.US)
            val value = part.substring(idx + 1).trim()
            val oid = when (type) {
                "CN" -> OID_CN
                "O" -> OID_O
                "C" -> OID_C
                else -> continue
            }
            val attribute = der(0x31, der(0x30, der(0x06, oid) + der(0x0C, value.toByteArray(Charsets.UTF_8))))
            rdns.add(attribute)
        }
        val content = ByteArrayOutputStream()
        rdns.forEach { content.write(it) }
        return der(0x30, content.toByteArray())
    }
}
