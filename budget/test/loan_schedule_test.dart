import '../lib/struct/loanSchedule.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

void main() {
  final t = _sample();
  final s = buildSchedule(t);
  final sum = summarize(t);
  print('instalments ${s.length}, last ${s.last.emi}, last due ${s.last.dueDate}');
  print('interest ${sum.totalInterest} gst ${sum.gstOnInterest} gstFee ${sum.gstOnFee} total ${sum.totalPayable}');
  check(s.length == 24, '24 instalments');
  check(s.first.dueDate == DateTime(2026, 1, 14), 'first due 14 Jan 2026');
  check(s.last.dueDate == DateTime(2027, 12, 14), 'last due 14 Dec 2027');
  check((sum.gstOnInterest - 9967).abs() < 2, 'GST on interest ~9,967');
  check(sum.gstOnFee == 1620, 'GST on fee 1,620');
  check((sum.totalPayable - 525954).abs() < 10, 'total payable ~5,25,954');
  final due = instalmentsDueBy(t, DateTime(2026, 11, 3));
  check(due.length == 10, '10 EMIs due by 3 Nov 2026 (14 Jan..14 Oct)');
  final ticked = t.copyWith(paidInstalments: due);
  final s2 = summarize(ticked);
  print('paid ticks ${s2.paidFromTicks} outstanding ${s2.outstandingBeforePayments}');
  check((s2.paidFromTicks - (210570 + s.take(10).fold(0.0, (a, b) => a + b.gstOnInterest))).abs() < 1, 'paid = 10 EMI + their GST');
  final back = LoanTerms.fromJson(ticked.toJson())!;
  check(back.paidInstalments.length == 10 && back.emi == 21057, 'json round trip');
  check(_addCheck(), "month end rollover");
  progressTest();
}

bool _addCheck() {
  final t = LoanTerms(principal: 1200, annualRatePct: 0, months: 3, emi: 400, firstEmiDate: DateTime(2026, 1, 31));
  final s = buildSchedule(t);
  return s[1].dueDate == DateTime(2026, 2, 28) && s[2].dueDate == DateTime(2026, 3, 31);
}

void progressTest() {
  final t = _sample();
  final due = instalmentsDueBy(t, DateTime(2026, 11, 3));
  final p0 = loanProgress(t.copyWith(paidInstalments: due), 0);
  final p1 = loanProgress(t.copyWith(paidInstalments: due), -21057 - 0.0);
  check((p0.outstanding - p1.outstanding - 21057).abs() < 0.01, 'a 21,057 payment lowers outstanding by 21,057');
  check(loanProgress(t, 1000).repaid == 0, 'income linked is not a payment');
}

// A sample loan only for the tests: 4,50,000 at 11.4% for 24 months, EMI 21,057, fee 9,000, first EMI 14 Jan 2026.
LoanTerms _sample() => LoanTerms(
    principal: 450000,
    annualRatePct: 11.4,
    months: 24,
    emi: 21057,
    firstEmiDate: DateTime(2026, 1, 14),
    feeAmount: 9000);
