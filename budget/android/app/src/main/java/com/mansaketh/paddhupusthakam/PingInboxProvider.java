package com.mansaketh.paddhupusthakam;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
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
