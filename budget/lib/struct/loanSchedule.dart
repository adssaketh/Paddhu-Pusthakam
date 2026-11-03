// Maths for instalment loans such as "Instant Loan on Credit Card": a fixed rate on the reducing balance,
// equal monthly instalments (EMI), 18% GST on every month's interest and on the one-time processing fee.
//
// Pure Dart (no Flutter or database imports) so it can be checked with `dart run`.

/// Rounds to paise.
double round2(double v) => (v * 100).roundToDouble() / 100;

class LoanTerms {
  LoanTerms({
    required this.principal,
    required this.annualRatePct,
    required this.months,
    required this.emi,
    required this.firstEmiDate,
    this.feeAmount = 0,
    this.gstPct = 18,
    this.feePaid = false,
    Set<int>? paidInstalments,
    this.walletPk,
    this.note = '',
  }) : paidInstalments = paidInstalments ?? <int>{};

  final double principal;
  final double annualRatePct;
  final int months;

  /// Monthly instalment as written in the sanction letter (before GST).
  final double emi;
  final DateTime firstEmiDate;

  /// One-time processing fee (before GST).
  final double feeAmount;

  /// GST on interest and on the fee, in percent.
  final double gstPct;

  /// True when the fee (with its GST) is already paid, for example taken out of the amount you received.
  final bool feePaid;

  /// Instalments (1 = first) you have already paid, from before or outside the app's transactions.
  final Set<int> paidInstalments;

  /// Account the loan sits on (for display only).
  final String? walletPk;
  final String note;

  LoanTerms copyWith({
    double? principal,
    double? annualRatePct,
    int? months,
    double? emi,
    DateTime? firstEmiDate,
    double? feeAmount,
    double? gstPct,
    bool? feePaid,
    Set<int>? paidInstalments,
    String? walletPk,
    String? note,
  }) =>
      LoanTerms(
        principal: principal ?? this.principal,
        annualRatePct: annualRatePct ?? this.annualRatePct,
        months: months ?? this.months,
        emi: emi ?? this.emi,
        firstEmiDate: firstEmiDate ?? this.firstEmiDate,
        feeAmount: feeAmount ?? this.feeAmount,
        gstPct: gstPct ?? this.gstPct,
        feePaid: feePaid ?? this.feePaid,
        paidInstalments: paidInstalments ?? this.paidInstalments,
        walletPk: walletPk ?? this.walletPk,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'principal': principal,
        'rate': annualRatePct,
        'months': months,
        'emi': emi,
        'first': firstEmiDate.toIso8601String(),
        'fee': feeAmount,
        'gst': gstPct,
        'feePaid': feePaid,
        'paid': (paidInstalments.toList()..sort()),
        'wallet': walletPk,
        'note': note,
      };

  static LoanTerms? fromJson(dynamic json) {
    if (json is! Map) return null;
    try {
      double d(dynamic v, [double fallback = 0]) =>
          v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);
      final DateTime? first = DateTime.tryParse('${json['first']}');
      final int months = d(json['months']).round();
      if (first == null || months <= 0) return null;
      return LoanTerms(
        principal: d(json['principal']),
        annualRatePct: d(json['rate']),
        months: months,
        emi: d(json['emi']),
        firstEmiDate: first,
        feeAmount: d(json['fee']),
        gstPct: d(json['gst'], 18),
        feePaid: json['feePaid'] == true,
        paidInstalments: {
          for (final dynamic v in (json['paid'] is List ? json['paid'] as List : []))
            if (v is num) v.toInt()
        },
        walletPk: json['wallet']?.toString(),
        note: (json['note'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

class LoanInstalment {
  const LoanInstalment({
    required this.number,
    required this.dueDate,
    required this.openingBalance,
    required this.interest,
    required this.principalPart,
    required this.emi,
    required this.gstOnInterest,
  });

  final int number;
  final DateTime dueDate;
  final double openingBalance;
  final double interest;
  final double principalPart;
  final double emi;
  final double gstOnInterest;

  /// What leaves your account for this month: EMI plus the GST charged on its interest.
  double get totalDue => round2(emi + gstOnInterest);
}

/// The EMI for these terms by the standard formula (used to suggest a value; the letter's EMI wins).
double suggestedEmi(double principal, double annualRatePct, int months) {
  if (months <= 0) return 0;
  final double r = annualRatePct / 12 / 100;
  if (r == 0) return round2(principal / months);
  final double f = _pow(1 + r, months);
  return round2(principal * r * f / (f - 1));
}

double _pow(double base, int exp) {
  double result = 1;
  for (int i = 0; i < exp; i++) {
    result *= base;
  }
  return result;
}

DateTime _addMonths(DateTime d, int months) {
  final int total = d.month - 1 + months;
  final int year = d.year + total ~/ 12;
  final int month = total % 12 + 1;
  final int lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > lastDay ? lastDay : d.day);
}

/// Every instalment, with the interest of that month and the GST on it. The last instalment is adjusted
/// so the balance ends at exactly zero.
List<LoanInstalment> buildSchedule(LoanTerms t) {
  final List<LoanInstalment> out = [];
  double balance = t.principal;
  final double monthlyRate = t.annualRatePct / 12 / 100;
  for (int i = 1; i <= t.months; i++) {
    final double interest = round2(balance * monthlyRate);
    double emi = t.emi;
    double principalPart = round2(emi - interest);
    if (i == t.months || principalPart > balance) {
      principalPart = round2(balance);
      emi = round2(principalPart + interest);
    }
    out.add(LoanInstalment(
      number: i,
      dueDate: _addMonths(t.firstEmiDate, i - 1),
      openingBalance: round2(balance),
      interest: interest,
      principalPart: principalPart,
      emi: emi,
      gstOnInterest: round2(interest * t.gstPct / 100),
    ));
    balance = round2(balance - principalPart);
    if (balance <= 0) break;
  }
  return out;
}

class LoanSummary {
  const LoanSummary({
    required this.principal,
    required this.totalInterest,
    required this.gstOnInterest,
    required this.fee,
    required this.gstOnFee,
    required this.totalPayable,
    required this.paidFromTicks,
  });

  final double principal;
  final double totalInterest;
  final double gstOnInterest;
  final double fee;
  final double gstOnFee;

  /// Principal + interest + GST on interest + fee + GST on fee.
  final double totalPayable;

  /// What the ticked instalments (and the fee, when marked paid) already account for.
  final double paidFromTicks;

  double get outstandingBeforePayments => round2(totalPayable - paidFromTicks);
}

LoanSummary summarize(LoanTerms t) {
  final List<LoanInstalment> schedule = buildSchedule(t);
  double interest = 0, gstInterest = 0, paid = 0;
  for (final LoanInstalment s in schedule) {
    interest += s.interest;
    gstInterest += s.gstOnInterest;
    if (t.paidInstalments.contains(s.number)) paid += s.totalDue;
  }
  final double gstFee = round2(t.feeAmount * t.gstPct / 100);
  if (t.feePaid) paid += t.feeAmount + gstFee;
  return LoanSummary(
    principal: t.principal,
    totalInterest: round2(interest),
    gstOnInterest: round2(gstInterest),
    fee: t.feeAmount,
    gstOnFee: gstFee,
    totalPayable: round2(t.principal + interest + gstInterest + t.feeAmount + gstFee),
    paidFromTicks: round2(paid),
  );
}

/// Ticks every instalment whose due date is on or before [today]. Used once, when a loan is first set up.
Set<int> instalmentsDueBy(LoanTerms t, DateTime today) {
  final DateTime end = DateTime(today.year, today.month, today.day);
  return {
    for (final LoanInstalment s in buildSchedule(t))
      if (!s.dueDate.isAfter(end)) s.number
  };
}

class LoanProgress {
  const LoanProgress(this.totalPayable, this.repaid);
  final double totalPayable;
  final double repaid;
  double get outstanding => round2(totalPayable - repaid < 0 ? 0 : totalPayable - repaid);
  double get fraction => totalPayable <= 0 ? 0 : (repaid / totalPayable).clamp(0.0, 1.0).toDouble();
}

/// [linkedSum] is the sum of the amounts of the transactions linked to the loan ("Long term loan" in Add
/// Transaction): payments are expenses, so they are negative. Money paid = ticked instalments + payments.
LoanProgress loanProgress(LoanTerms t, double linkedSum) {
  final LoanSummary s = summarize(t);
  final double payments = linkedSum < 0 ? -linkedSum : 0;
  return LoanProgress(s.totalPayable, round2(s.paidFromTicks + payments));
}
