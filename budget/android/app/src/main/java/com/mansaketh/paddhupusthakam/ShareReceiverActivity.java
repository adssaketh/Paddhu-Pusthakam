package com.mansaketh.paddhupusthakam;

import android.app.Activity;
import android.content.ClipData;
import android.content.ComponentName;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Receives what Ping sends to Paddhu Pusthakam:
 *  - a JSON file through Android's share sheet ("Send to Paddhu Pusthakam" in Ping's settings), or
 *  - one SMS as a small JSON text (Ping's "Add to Paddhu" button on a notification, and the long-press option).
 * Either way it saves the JSON into the app's cache and then opens the main screen with an app link, which opens
 * the import screen (see "importFromPing" in appLinks.dart). It has no screen of its own.
 */
public class ShareReceiverActivity extends Activity {
    /** Same name as kPingImportFileName in lib/struct/pingImport.dart. */
    private static final String IMPORT_FILE_NAME = "ping-import.json";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            handle(getIntent());
        } catch (Throwable e) {
            Toast.makeText(this, "Could not read the shared file: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
        finish();
    }

    @SuppressWarnings("deprecation")
    private void handle(Intent intent) throws Exception {
        if (intent == null || !Intent.ACTION_SEND.equals(intent.getAction())) return;

        Uri uri = null;
        Object extra = intent.getParcelableExtra(Intent.EXTRA_STREAM);
        if (extra instanceof Uri) uri = (Uri) extra;
        if (uri == null) {
            ClipData clip = intent.getClipData();
            if (clip != null && clip.getItemCount() > 0) uri = clip.getItemAt(0).getUri();
        }

        File target = new File(getCacheDir(), IMPORT_FILE_NAME);
        boolean single = false;
        if (uri != null) {
            try (InputStream in = getContentResolver().openInputStream(uri);
                 OutputStream out = new FileOutputStream(target, false)) {
                if (in == null) throw new IllegalStateException("could not open the shared file");
                byte[] buffer = new byte[65536];
                int n;
                while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
            }
        } else {
            // one SMS, sent as a small JSON text
            CharSequence text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
            if (text == null || !text.toString().trim().startsWith("{")) {
                throw new IllegalStateException("nothing was shared");
            }
            try (OutputStream out = new FileOutputStream(target, false)) {
                out.write(text.toString().getBytes("UTF-8"));
            }
            single = true;
        }

        // Open the main screen with an app link. The "t" value makes every share a new link.
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        ComponentName main = launch != null ? launch.getComponent() : null;
        Intent open = new Intent(Intent.ACTION_VIEW,
            Uri.parse("https://cashewapp.web.app/importFromPing?single=" + (single ? "1" : "0")
                + "&t=" + System.currentTimeMillis()));
        if (main != null) open.setComponent(main);
        else open.setPackage(getPackageName());
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(open);
    }
}
