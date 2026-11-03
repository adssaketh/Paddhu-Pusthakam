// Where fixed deposits are kept: in the app's settings under "fixedDeposits" (part of the backup, no
// database change needed), plus the maturity reminders.

import 'package:budget/struct/fixedDeposit.dart';
import 'package:budget/struct/notificationsGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/settingsMerge.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

List<FixedDeposit> loadFixedDeposits() {
  final dynamic stored = appStateSettings["fixedDeposits"];
  if (stored is! List) return [];
  final List<FixedDeposit> out = [];
  for (final dynamic j in stored) {
    if (isDeletedItem(j)) continue;
    final FixedDeposit? fd = FixedDeposit.fromJson(j);
    if (fd != null) out.add(fd);
  }
  return out;
}

Future<void> saveFixedDeposits(List<FixedDeposit> list) async {
  final dynamic stored = appStateSettings["fixedDeposits"];
  final Map<String, dynamic> before = {
    if (stored is List)
      for (final dynamic j in stored)
        if (j is Map) '${j['id']}': j
  };
  final Set<String> keep = {for (final FixedDeposit fd in list) fd.id};
  final List<Map<String, dynamic>> items = [];
  for (final FixedDeposit fd in list) {
    final Map<String, dynamic> json = fd.toJson();
    final dynamic old = before[fd.id];
    // unchanged deposits keep their time, so an old copy never overwrites a newer one on another device
    final bool same = old is Map && !isDeletedItem(old) && _sameFields(old, json);
    items.add(same ? Map<String, dynamic>.from(old) : stampItem(json));
  }
  // deposits that were removed leave a marker
  for (final MapEntry<String, dynamic> e in before.entries) {
    if (keep.contains(e.key)) continue;
    items.add(isDeletedItem(e.value) ? Map<String, dynamic>.from(e.value as Map) : {'id': e.key, ...deletedMarker()});
  }
  await updateSettings(
    "fixedDeposits",
    items,
    updateGlobalState: false,
    pagesNeedingRefresh: [0],
    setStateAllPageFrameworks: true,
  );
  await scheduleFixedDepositReminders();
}

bool _sameFields(Map old, Map json) {
  for (final String k in json.keys) {
    if ('${old[k]}' != '${json[k]}') return false;
  }
  return true;
}

/// Adds the deposit unless the same one is already there. true when it was added.
Future<bool> addFixedDepositIfNew(FixedDeposit fd) async {
  final List<FixedDeposit> all = loadFixedDeposits();
  for (final FixedDeposit other in all) {
    if (sameDeposit(other, fd)) return false;
  }
  all.add(fd);
  await saveFixedDeposits(all);
  return true;
}

Future<void> upsertFixedDeposit(FixedDeposit fd) async {
  final List<FixedDeposit> all = loadFixedDeposits();
  final int i = all.indexWhere((e) => e.id == fd.id);
  if (i >= 0) {
    all[i] = fd;
  } else {
    all.add(fd);
  }
  await saveFixedDeposits(all);
}

Future<void> deleteFixedDeposit(String id) async {
  final List<FixedDeposit> all = loadFixedDeposits()..removeWhere((e) => e.id == id);
  await saveFixedDeposits(all);
}

String newFixedDepositId() => 'fd-${DateTime.now().microsecondsSinceEpoch}';

const int _firstReminderId = 900000;

/// A notification 7 days before and on the day of maturity (9:00), for every open deposit.
Future<void> scheduleFixedDepositReminders() async {
  try {
    final dynamic old = appStateSettings["fdReminderCount"];
    for (int i = 0; i < (old is int ? old : 0); i++) {
      await flutterLocalNotificationsPlugin.cancel(_firstReminderId + i);
    }
    int count = 0;
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    const AndroidNotificationDetails android = AndroidNotificationDetails(
      'fixedDepositReminders',
      'Fixed deposit reminders',
      importance: Importance.max,
      priority: Priority.high,
    );
    for (final FixedDeposit fd in loadFixedDeposits()) {
      if (fd.closed) continue;
      for (final int before in const [7, 0]) {
        final tz.TZDateTime when = tz.TZDateTime(
            tz.local, fd.maturityDate.year, fd.maturityDate.month, fd.maturityDate.day - before, 9);
        if (!when.isAfter(now)) continue;
        final String number = fd.fdNumber.isEmpty ? '' : ' ••${fd.fdNumber.length > 4 ? fd.fdNumber.substring(fd.fdNumber.length - 4) : fd.fdNumber}';
        await flutterLocalNotificationsPlugin.zonedSchedule(
          _firstReminderId + count,
          before == 0 ? 'Fixed deposit matures today' : 'Fixed deposit matures in 7 days',
          '${fd.bank}$number · about ₹${maturityValue(fd).round()} at maturity',
          when,
          const NotificationDetails(android: android),
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        count++;
      }
    }
    await updateSettings("fdReminderCount", count, updateGlobalState: false);
  } catch (_) {
    // reminders are a convenience: never break saving a deposit
  }
}
