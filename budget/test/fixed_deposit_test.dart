import '../lib/struct/fixedDeposit.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

void main() {
  final fd = FixedDeposit(
      id: 'a', bank: 'X', principal: 100000, ratePct: 7, startDate: DateTime(2026, 1, 1), maturityDate: DateTime(2027, 1, 1));
  final mv = maturityValue(fd);
  print('maturity $mv');
  check(mv > 107000 && mv < 107300, 'quarterly 7% for 1 year ~107,186');
  check(accruedInterest(fd, DateTime(2025, 12, 1)) == 0, 'nothing before start');
  check(accruedInterest(fd, DateTime(2028, 1, 1)) == interestAtMaturity(fd), 'all interest after maturity');
  final half = accruedInterest(fd, DateTime(2026, 7, 2));
  check(half > 3400 && half < 3600, 'half year ~3,5xx ($half)');
  check(maturityValue(fd.copyWith(compounding: 0)) == 107000, 'simple 7% = 107,000');
  check(maturityValue(fd.copyWith(maturityAmount: 107500)) == 107500, 'bank figure wins');
  check(FixedDeposit.fromJson(fd.toJson())!.principal == 100000, 'json round trip');
  check(daysToMaturity(fd, DateTime(2026, 12, 2)) == 30, '30 days to go');

  const s1 =
      'Dear Customer, your Fixed Deposit of Rs. 1,50,000.00 has been booked on 03-Nov-2026 for 12 months at 7.10% p.a. Maturity date: 03-Nov-2027. Maturity amount Rs. 1,60,900. FD No. XXXX5521. -Axis Bank';
  final p1 = parseFixedDepositSms(body: s1, sender: 'AX-AXISBK', smsDate: DateTime(2026, 11, 3))!.deposit;
  check(p1.principal == 150000 && p1.ratePct == 7.1, 'principal and rate');
  check(p1.maturityDate == DateTime(2027, 11, 3) && p1.startDate == DateTime(2026, 11, 3), 'dates');
  check(p1.maturityAmount == 160900 && p1.fdNumber == '5521' && p1.bank == 'Axis Bank', 'maturity amount, number, bank');

  const s2 = 'Your FD of INR 50000 is created for a tenure of 6 months. ROI 6.5%. A/c 90012345. HDFC Bank';
  final p2 = parseFixedDepositSms(body: s2, sender: 'VM-HDFCBK', smsDate: DateTime(2026, 11, 3))!.deposit;
  check(p2.maturityDate == DateTime(2027, 5, 3) && p2.ratePct == 6.5, 'tenure fallback');

  check(parseFixedDepositSms(body: 'Your FD of Rs 50000 has matured and proceeds credited', sender: 'AX-AXISBK', smsDate: DateTime.now()) == null, 'matured is not a booking');
  check(parseFixedDepositSms(body: 'Rs 500 debited for UPI txn', sender: 'AX-AXISBK', smsDate: DateTime.now()) == null, 'ordinary debit ignored');
  check(parseFixedDepositSms(body: 'Your FD has been booked', sender: 'AX-AXISBK', smsDate: DateTime.now()) == null, 'no amount -> not guessed');
  check(sameDeposit(p1, p1.copyWith(note: 'x')), 'same deposit detected');
}
