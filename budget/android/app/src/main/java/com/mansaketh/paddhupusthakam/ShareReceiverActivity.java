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
 * Receives the file that Ping shares ("Send to Paddhu Pusthakam" in Ping's settings) through Android's share
 * sheet. It copies the file into the app's cache and then opens the main screen with an app link, which
 * opens the import screen (see "importFromPing" in appLinks.dart). It has no screen of its own.
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
        if (uri == null) throw new IllegalStateException("no file was shared");

        File target = new File(getCacheDir(), IMPORT_FILE_NAME);
        try (InputStream in = getContentResolver().openInputStream(uri);
             OutputStream out = new FileOutputStream(target, false)) {
            if (in == null) throw new IllegalStateException("could not open the shared file");
            byte[] buffer = new byte[65536];
            int n;
            while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
        }

        // Open the main screen with an app link. The "t" value makes every share a new link.
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        ComponentName main = launch != null ? launch.getComponent() : null;
        Intent open = new Intent(Intent.ACTION_VIEW,
            Uri.parse("https://cashewapp.web.app/importFromPing?t=" + System.currentTimeMillis()));
        if (main != null) open.setComponent(main);
        else open.setPackage(getPackageName());
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(open);
    }
}
