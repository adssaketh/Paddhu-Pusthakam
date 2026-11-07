import 'package:budget/struct/householdMergeRules.dart';

int failures = 0;
void check(String name, bool ok) {
  if (!ok) failures++;
  print("${ok ? 'PASS' : 'FAIL'}  $name");
}

void main() {
  final DateTime now = DateTime(2026, 11, 7, 12);
  final DateTime old = now.subtract(const Duration(hours: 1));
  final DateTime fresh = now.subtract(const Duration(seconds: 20));
  const String me = "me", other = "other";

  var plan = householdReconcilePlan(
    local: [
      HouseholdLocalRow("ghost", other, old),
      HouseholdLocalRow("there", other, old),
      HouseholdLocalRow("mineMissing", me, old),
      HouseholdLocalRow("mineThere", me, old),
    ],
    serverIds: {"there", "mineThere"},
    deletedHere: {},
    myUid: me,
    now: now,
  );
  check("ghost foreign row is removed", plan.deletePks.length == 1 && plan.deletePks.first == "ghost");
  check("own row missing on server goes up again", plan.reuploadPks.length == 1 && plan.reuploadPks.first == "mineMissing");

  plan = householdReconcilePlan(
    local: [HouseholdLocalRow("justUp", me, fresh), HouseholdLocalRow("gone", me, old)],
    serverIds: {},
    deletedHere: {"gone"},
    myUid: me,
    now: now,
  );
  check("row uploaded seconds ago is left alone", !plan.reuploadPks.contains("justUp"));
  check("row deleted here is not resurrected", !plan.reuploadPks.contains("gone"));

  plan = householdReconcilePlan(
    local: [
      HouseholdLocalRow("personal", "", old),
      HouseholdLocalRow("unclaimed", null, null),
      HouseholdLocalRow("neverUp", me, null),
    ],
    serverIds: {},
    deletedHere: {},
    myUid: me,
    now: now,
  );
  check("personal, unclaimed and never-uploaded rows are untouched",
      plan.deletePks.isEmpty && plan.reuploadPks.isEmpty);

  check("server owner wins over local owner", householdServerOwnerWins(localOwnerUid: me, serverOwnerId: other));
  check("same owner is not an ownership conflict", !householdServerOwnerWins(localOwnerUid: other, serverOwnerId: other));
  check("unclaimed local row is replaced by the server owner", householdServerOwnerWins(localOwnerUid: null, serverOwnerId: other));

  if (failures > 0) throw Exception("$failures failed");
}
