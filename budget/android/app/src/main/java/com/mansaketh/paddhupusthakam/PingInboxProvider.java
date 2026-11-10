package com.mansaketh.paddhupusthakam;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.pm.SigningInfo;
import android.os.Build;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * The door Ping uses to hand over a new bank SMS while Paddhu Pusthakam is closed (Ping > Settings > "Send new
 * bank messages to Paddhu Pusthakam automatically").
 *
 * It does no parsing and no database work. It only checks who is calling, and writes the small JSON text Ping sent
 * (same format as the "Add to Paddhu" button, see ShareReceiverActivity) into files/ping_inbox/, one file per SMS.
 * The Flutter side reads that folder the next time Paddhu Pusthakam opens (lib/struct/pingInbox.dart), saves the
 * messages it is sure about and puts the rest in the review list.
 *
 * One file per SMS, written under a temporary name and then renamed, so the Dart side never reads a half-written file
 * and nothing is ever appended to a file that is being read.
 *
 * Keep INBOX_DIR in step with kPingInboxDirName in lib/struct/pingInbox.dart, and the authority in step with
 * PaddhuInbox.java in Ping.
 */
public class PingInboxProvider extends ContentProvider {
    /** Same as the "authorities" value in AndroidManifest.xml and PaddhuInbox.AUTHORITY in Ping. */
    static final String AUTHORITY = "com.mansaketh.paddhupusthakam.pinginbox";
    /** Only this app may hand messages over. The system fills in the caller, it cannot be faked in the call. */
    static final String ALLOWED_CALLER = "com.ping.sms";
    /**
     * SHA-256 of Ping's release signing certificate (contract/ping-paddhu/SPEC.md section 7). The caller must have the
     * right package name AND be signed with this certificate. Read from Ping's `dev` APK with apksigner on 10 Nov 2026;
     * CI in Ping checks that the `prod` APK has the same digest. More than one digest can be listed (for a key change).
     */
    static final String[] PINNED_CERT_SHA256 = {
        "12cb1f4ff2ddcd91feda62d09f555ccc6c10a8f270c031908e6ee38dec20a502"
    };
    static final String METHOD_ENQUEUE = "enqueue";
    static final String INBOX_DIR = "ping_inbox";

    private static final int MAX_JSON_CHARS = 20000;
    private static final int MAX_FILES = 2000;
    private static final AtomicInteger COUNTER = new AtomicInteger();
    private static final Object LOCK = new Object();

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        Bundle result = new Bundle();
        if (!METHOD_ENQUEUE.equals(method)) {
            result.putBoolean("ok", false);
            result.putString("error", "unknown method");
            return result;
        }
        String caller = getCallingPackage();
        if (!ALLOWED_CALLER.equals(caller)) {
            result.putBoolean("ok", false);
            result.putString("error", "caller not allowed");
            return result;
        }
        if (arg == null || arg.length() > MAX_JSON_CHARS || !arg.trim().startsWith("{")) {
            result.putBoolean("ok", false);
            result.putString("error", "nothing usable was sent");
            return result;
        }
        Context context = getContext();
        if (context == null) {
            result.putBoolean("ok", false);
            result.putString("error", "no context");
            return result;
        }
        if (!callerHasPinnedCertificate(context, caller)) {
            result.putBoolean("ok", false);
            result.putString("error", "caller not allowed");
            return result;
        }

        try {
            synchronized (LOCK) {
                File dir = new File(context.getFilesDir(), INBOX_DIR);
                if (!dir.isDirectory() && !dir.mkdirs()) {
                    throw new IllegalStateException("could not create the inbox folder");
                }
                String[] existing = dir.list();
                if (existing != null && existing.length >= MAX_FILES) {
                    throw new IllegalStateException("the inbox is full, open Paddhu Pusthakam to empty it");
                }
                String name = System.currentTimeMillis() + "-" + COUNTER.incrementAndGet() + "-"
                    + Integer.toHexString(arg.hashCode());
                File tmp = new File(dir, name + ".tmp");
                File done = new File(dir, name + ".json");
                try (OutputStream out = new FileOutputStream(tmp, false)) {
                    out.write(arg.getBytes("UTF-8"));
                    out.flush();
                }
                if (!tmp.renameTo(done)) {
                    tmp.delete();
                    throw new IllegalStateException("could not save the message");
                }
            }
            result.putBoolean("ok", true);
        } catch (Throwable e) {
            result.putBoolean("ok", false);
            result.putString("error", String.valueOf(e.getMessage()));
        }
        return result;
    }

    /** true when [caller] is signed (only) with a certificate whose SHA-256 is in [PINNED_CERT_SHA256]. */
    private static boolean callerHasPinnedCertificate(Context context, String caller) {
        try {
            PackageManager pm = context.getPackageManager();
            Signature[] signers;
            if (Build.VERSION.SDK_INT >= 28) {
                PackageInfo info = pm.getPackageInfo(caller, PackageManager.GET_SIGNING_CERTIFICATES);
                SigningInfo signing = info.signingInfo;
                if (signing == null) return false;
                signers = signing.hasMultipleSigners() ? signing.getApkContentsSigners() : signing.getSigningCertificateHistory();
            } else {
                @SuppressWarnings("deprecation")
                PackageInfo info = pm.getPackageInfo(caller, PackageManager.GET_SIGNATURES);
                @SuppressWarnings("deprecation")
                Signature[] legacy = info.signatures;
                signers = legacy;
            }
            if (signers == null || signers.length == 0) return false;
            // every signer must be pinned (a second, unknown signer is refused)
            for (Signature signer : signers) {
                if (!PingCertCheck.isPinned(signer.toByteArray(), PINNED_CERT_SHA256)) return false;
            }
            return true;
        } catch (Throwable e) {
            return false; // cannot check = not allowed
        }
    }

    // The provider has no tables: everything goes through call().
    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        return null;
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        return 0;
    }
}
