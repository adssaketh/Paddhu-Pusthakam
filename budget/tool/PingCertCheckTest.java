// Plain-Java check of PingCertCheck (the pure part of the certificate pinning in PingInboxProvider.java):
//
//   javac -d /tmp/pcc android/app/src/main/java/com/mansaketh/paddhupusthakam/PingCertCheck.java tool/PingCertCheckTest.java && java -cp /tmp/pcc com.mansaketh.paddhupusthakam.PingCertCheckTest
package com.mansaketh.paddhupusthakam;

public class PingCertCheckTest {
    static int failures = 0;

    static void check(String name, boolean want, boolean got) {
        if (want != got) {
            failures++;
            System.out.println("  MISMATCH " + name + ": want " + want + ", got " + got);
        }
    }

    public static void main(String[] args) throws Exception {
        byte[] cert = "synthetic certificate bytes".getBytes("UTF-8");
        String digest = PingCertCheck.sha256Hex(cert);
        check("digest is 64 hex chars", true, digest.matches("[0-9a-f]{64}"));
        check("exact digest", true, PingCertCheck.isPinned(cert, new String[] {digest}));
        check("upper case digest", true, PingCertCheck.isPinned(cert, new String[] {digest.toUpperCase()}));
        StringBuilder colons = new StringBuilder();
        for (int i = 0; i < digest.length(); i += 2) colons.append(i == 0 ? "" : ":").append(digest, i, i + 2);
        check("colon separated digest", true, PingCertCheck.isPinned(cert, new String[] {colons.toString()}));
        check("second entry of the list", true, PingCertCheck.isPinned(cert, new String[] {"00", digest}));
        check("other certificate", false, PingCertCheck.isPinned("other".getBytes("UTF-8"), new String[] {digest}));
        check("empty list", false, PingCertCheck.isPinned(cert, new String[] {}));
        check("null list", false, PingCertCheck.isPinned(cert, null));
        check("empty certificate", false, PingCertCheck.isPinned(new byte[0], new String[] {digest}));
        check("empty pinned entry", false, PingCertCheck.isPinned(cert, new String[] {"", null}));
        check("prefix of the digest", false, PingCertCheck.isPinned(cert, new String[] {digest.substring(0, 32)}));
        if (failures == 0) System.out.println("PASS  PingCertCheck (11 checks)");
        else { System.out.println("FAIL  " + failures); System.exit(1); }
    }
}
