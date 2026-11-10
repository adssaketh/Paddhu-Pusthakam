// "View SMS in Ping": starts Ping on one message (contract/ping-paddhu/SPEC.md section 8) through a small
// Android channel in MainActivity.kt (explicit intent to com.ping.sms, action com.ping.sms.action.OPEN_SMS).

import 'package:budget/struct/pingImport.dart';
import 'package:flutter/services.dart';

const MethodChannel _pingChannel =
    MethodChannel('com.mansaketh.paddhupusthakam/ping');

/// One of: `ok`, `notInstalled` (Ping is not on this phone), `needsNewerPing` (an older Ping that does not
/// know this action), `error`.
Future<String> openSmsInPing(PingSmsRef ref) async {
  try {
    final String? result = await _pingChannel.invokeMethod<String>('openInPing', {
      if (ref.smsId != null) 'smsId': ref.smsId,
      if (ref.address != null) 'address': ref.address,
      if (ref.date != null) 'date': ref.date,
    });
    return result ?? 'error';
  } on PlatformException {
    return 'error';
  } on MissingPluginException {
    return 'error';
  }
}

/// The sentence shown when [openSmsInPing] did not open Ping, or null when it did.
String? openSmsInPingMessage(String result) {
  switch (result) {
    case 'ok':
      return null;
    case 'notInstalled':
      return 'Ping is not installed on this phone.';
    case 'needsNewerPing':
      return 'Update Ping to open a message from here.';
    default:
      return 'Could not open Ping.';
  }
}
