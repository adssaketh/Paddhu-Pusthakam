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

    companion object {
        const val PING_CHANNEL = "com.mansaketh.paddhupusthakam/ping"
        const val PING_PACKAGE = "com.ping.sms"
        const val PING_ACTION_OPEN_SMS = "com.ping.sms.action.OPEN_SMS"
    }
}
