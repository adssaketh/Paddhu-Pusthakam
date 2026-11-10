package com.mansaketh.paddhupusthakam;

import java.security.MessageDigest;

/**
 * The pure part of Ping's certificate check in PingInboxProvider (no Android classes, so tool/PingCertCheckTest.java
 * can run it with a plain `java` command).
 */
final class PingCertCheck {
    private PingCertCheck() {}

    /** Lower-case hex SHA-256 of the DER certificate bytes. */
    static String sha256Hex(byte[] certificate) throws Exception {
        byte[] d = MessageDigest.getInstance("SHA-256").digest(certificate);
        StringBuilder sb = new StringBuilder(d.length * 2);
        for (byte b : d) sb.append(String.format("%02x", b & 0xff));
        return sb.toString();
    }

    /** true when the certificate's digest equals one of [pinned] (hex, any case, optional ':' separators). */
    static boolean isPinned(byte[] certificate, String[] pinned) {
        if (certificate == null || certificate.length == 0 || pinned == null) return false;
        try {
            String actual = sha256Hex(certificate);
            for (String p : pinned) {
                if (p == null) continue;
                if (actual.equals(p.replace(":", "").trim().toLowerCase())) return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }
}
