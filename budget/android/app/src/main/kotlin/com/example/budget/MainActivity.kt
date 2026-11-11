package com.mansaketh.paddhupusthakam

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "View SMS in Ping" (lib/struct/pingOpen.dart)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PING_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openInPing") {
                val date = (call.argument<Any>("date") as? Number)?.toLong()
                result.success(openInPing(call.argument<String>("smsId"), call.argument<String>("address"), date))
            } else if (call.method == "getLogo") {
                // a business logo from Ping's logo provider (contract section 10); may wait for Ping's download, so not on the UI thread
                val brandKey = call.argument<String>("brandKey")
                val sender = call.argument<String>("sender")
                Thread {
                    val bytes = try { loadLogo(brandKey, sender) } catch (e: Throwable) { null }
                    runOnUiThread { result.success(bytes) }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }

    /** Explicit intent to Ping. Returns ok, notInstalled, needsNewerPing or error. */
    private fun openInPing(smsId: String?, address: String?, date: Long?): String {
        try {
            packageManager.getPackageInfo(PING_PACKAGE, 0)
        } catch (e: PackageManager.NameNotFoundException) {
            return "notInstalled"
        }
        val intent = Intent(PING_ACTION_OPEN_SMS).setPackage(PING_PACKAGE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (smsId != null) intent.putExtra("smsId", smsId)
        if (address != null) intent.putExtra("address", address)
        if (date != null) intent.putExtra("date", date) // a Long, as Ping expects
        return try {
            startActivity(intent)
            "ok"
        } catch (e: ActivityNotFoundException) {
            "needsNewerPing"
        } catch (e: Exception) {
            "error"
        }
    }

    /**
     * The logo of a business sender, from Ping (never from the internet). Only Ping's real provider is read: its package must be
     * com.ping.sms AND signed with the pinned certificate. Kept in the cache for 24 hours (the online logos Ping gets may not be
     * stored longer). Null = no logo, Ping not installed or not allowed yet: the screen shows what it showed before.
     */
    private fun loadLogo(brandKey: String?, sender: String?): ByteArray? {
        val key = brandKey?.takeIf { Regex("^[a-z0-9]{1,40}$").matches(it) }
        val path = when {
            key != null -> "brand/$key"
            !sender.isNullOrBlank() && sender.length <= 40 -> "sender/" + android.net.Uri.encode(sender)
            else -> return null
        }
        val cacheName = (key ?: ("s" + sender.hashCode().toString(16))) + ".img"
        val dir = java.io.File(cacheDir, "ping-logos").apply { mkdirs() }
        val cached = java.io.File(dir, cacheName)
        if (cached.exists() && System.currentTimeMillis() - cached.lastModified() < LOGO_TTL_MS) {
            return if (cached.length() == 0L) null else cached.readBytes() // an empty file = Ping had no logo today
        }
        val provider = packageManager.resolveContentProvider(LOGO_AUTHORITY, 0) ?: return null
        if (provider.packageName != PING_PACKAGE || !PingInboxProvider.callerHasPinnedCertificate(this, PING_PACKAGE)) return null
        val bytes = try {
            contentResolver.openInputStream(android.net.Uri.parse("content://$LOGO_AUTHORITY/$path"))?.use { it.readBytes() }
        } catch (e: java.io.FileNotFoundException) {
            cached.writeBytes(ByteArray(0)); return null // Ping has no logo for it
        } catch (e: SecurityException) {
            return null // Ping does not know this Paddhu yet: try again next time
        }
        if (bytes == null || bytes.size > 600 * 1024) return null
        cached.writeBytes(bytes)
        return bytes
    }

    companion object {
        const val LOGO_AUTHORITY = "com.ping.sms.logos"
        const val LOGO_TTL_MS = 24L * 60 * 60 * 1000
        const val PING_CHANNEL = "com.mansaketh.paddhupusthakam/ping"
        const val PING_PACKAGE = "com.ping.sms"
        const val PING_ACTION_OPEN_SMS = "com.ping.sms.action.OPEN_SMS"
    }
}
