import '../lib/struct/phonePeParser.dart';

void check(bool ok, String msg) {
  if (!ok) throw Exception('FAILED: $msg');
  print('ok  $msg');
}

void main() {
  final paytm = parseUpiScreenshotText('''Paytm
Paid Successfully
₹697.43
Rupees Six Hundred Ninety Seven and
Forty Three Paise Only
To: Indian Oil Petrol
Pump 2 Srichakra
Fuels Station
UPI ID: q311353638@ybl
From: Adhikarla
Dinakara Srinivasa
Saketh
UPI ID:
saketh.adhikarla@ptaxis
Axis Bank - 6372
UPI Ref No: 628671952568
02:12 PM, 13 Oct 2026
Paytm | Powered by UPI | AXIS BANK''')!;
  check(paytm.app == 'Paytm' && paytm.amount == 697.43 && paytm.isExpense, 'paytm amount/app ${paytm.amount} ${paytm.app}');
  check(paytm.party == 'Indian Oil Petrol Pump 2 Srichakra Fuels Station', 'paytm party "${paytm.party}"');
  check(paytm.date == DateTime(2026, 10, 13, 14, 12), 'paytm date ${paytm.date}');
  check(paytm.utr == '628671952568' && paytm.accountDigits == '6372', 'paytm ref/account ${paytm.utr} ${paytm.accountDigits}');
  check(phonePeToRow(paytm).walletName == 'Saketh - Axis', 'paytm wallet ${phonePeToRow(paytm).walletName}');

  final gpay = parseUpiScreenshotText('''S
To SWIGGY
₹304
Completed
30 Oct 2025, 5:45pm
State Bank of India
652898XXXXXXXX64
Payment of ₹304 completed
Receiver's bank has confirmed
deposit of money to SWIGGY's bank
account
UPI transaction ID
566939649602
To: SWIGGY
••••iggy@icici
From: A D SRINIVASA SAKETH (State
Bank of India)
••••la-8@okicici on Google Pay
Google transaction ID
CICAgMjA8OWRAg
Google Pay''')!;
  check(gpay.app == 'Google Pay' && gpay.amount == 304 && gpay.party == 'Swiggy', 'gpay ${gpay.app} ${gpay.amount} "${gpay.party}"');
  check(gpay.date == DateTime(2025, 10, 30, 17, 45), 'gpay date ${gpay.date}');
  check(gpay.utr == '566939649602' && gpay.accountDigits == '64', 'gpay ref/account ${gpay.utr} ${gpay.accountDigits}');

  final bhim = parseUpiScreenshotText('''BHIM - Bharat's Own Payments App
Paid
₹184.00
Banking Name
Zepto
Transaction ID
Date & Time
213607712405
31st Oct 26,
09:36 pm
To UPI ID
Remarks
cf.zepto12@ca
NO REMARK
shfreensdlpb
Debited account
AXIS BANK
XX566372
Process details
Payment initiated by ADHIKARLA
Payment received by Zepto
Hide details
Split this expense
BHIM UPI''')!;
  check(bhim.app == 'BHIM' && bhim.amount == 184 && bhim.party == 'Zepto', 'bhim ${bhim.app} ${bhim.amount} "${bhim.party}"');
  check(bhim.date == DateTime(2026, 10, 31, 21, 36), 'bhim date ${bhim.date}');
  check(bhim.accountDigits == '566372' && bhim.utr == '213607712405', 'bhim account/ref ${bhim.accountDigits} ${bhim.utr}');
  check(phonePeToRow(bhim).walletName == 'Saketh - Axis', 'bhim wallet');

  final cred = parseUpiScreenshotText('''X
Pavan Medical And General...
₹132
SUCCESSFUL
05:26pm, 22nd sep'26
Paid via CRED
SBI RUPAY CREDIT CARD
RuPay xxxx XX64
PAID VIA UPI
Check limit
payment initiated from your SBI RUPAY
CREDIT CARD Rupay credit card
amount deducted from Saketh's Rupay
paying them again?''')!;
  check(cred.app == 'CRED' && cred.amount == 132 && cred.party == 'Pavan Medical And General', 'cred ${cred.app} ${cred.amount} "${cred.party}"');
  check(cred.date == DateTime(2026, 9, 22, 17, 26) && cred.accountDigits == '64', 'cred date/account ${cred.date} ${cred.accountDigits}');
  check(phonePeToRow(cred).smsId.startsWith('pp-'), 'cred has a stable id without a ref: ${phonePeToRow(cred).smsId}');

  final mk = parseUpiScreenshotText('''₹133.19
UPIIntent
UPI Payment Successful
28 Oct '26 at 11:11AM
To
Z
Zomato Limited
zomato2.payu@indus
From
Adhikarla Dinakara Srinivasa
Saketh
9550002618@ikwik
AXIS BANK - 6372
MobiKwik Order ID
OMK27d0f82087ad20d
UPI Transaction ID
104332350049
Powered By UPI HDFC BANK''')!;
  check(mk.amount == 133.19 && mk.party == 'Zomato Limited', 'mobikwik ${mk.amount} "${mk.party}"');
  check(mk.date == DateTime(2026, 10, 28, 11, 11) && mk.utr == '104332350049' && mk.accountDigits == '6372', 'mobikwik date/ref/account ${mk.date} ${mk.utr} ${mk.accountDigits}');

  // ---- the amount must be the paid amount, never an id or a number inside another word
  String phonePe(String amounts) => '''Transaction Successful
06:04 am on 06 Nov 2026
Paid to
B
Blinkit
blinkit.payu@hdfcbank
$amounts
Transfer Details
Message
UPIIntent
PhonePe Transaction ID
T2611060604060808497253
Debited from
XXXX566372
₹286
UTR: 995940082093''';
  final PhonePeEntry normal = parseUpiScreenshotText(phonePe('₹286'))!;
  check(normal.amount == 286 && normal.isExpense, 'phonepe amount ${normal.amount}');
  check(normal.party == 'Blinkit' && normal.date == DateTime(2026, 11, 6, 6, 4), 'phonepe party/date "${normal.party}" ${normal.date}');
  check(parseUpiScreenshotText(phonePe('₹ 7000000000000'))!.amount == 286,
      'a long number after a rupee sign is not an amount');
  check(parseUpiScreenshotText(phonePe('₹\n7995940082093'))!.amount == 286,
      'a UTR-sized number on the next line is not an amount');
  check(parseUpiScreenshotText(phonePe('Offers 500\n₹286'))!.amount == 286,
      'Rs inside another word ("Offers 500") is not a rupee sign');
  check(parseUpiScreenshotText(phonePe('₹28\n₹286'))!.amount == 286,
      'the amount shown twice wins over one that was read once');
  check(parseUpiScreenshotText(phonePe('₹286\n₹28'))!.amount == 286, 'the same, in the other order');
  check(parseUpiScreenshotText(phonePe('INR 1,250.50\nINR 1,250.50'))!.amount == 1250.5, 'INR with commas and paise');
  check(
      parseUpiScreenshotText('''Transaction Successful
06:04 am on 06 Nov 2026
Paid to
Blinkit
₹ 7000000000000
T2611060604060808497253''') ==
          null,
      'when only an impossible amount is found, nothing is guessed');
  check(kMaxPlausiblePaymentAmount == 10000000, 'the limit for one payment');

  // ---- the rupee sign read as a digit: the amount is flagged, not trusted
  check(!normal.amountUnconfirmed, 'an amount with a rupee sign is confirmed');
  final PhonePeEntry misread = parseUpiScreenshotText('''Transaction Successful
06:04 am on 06 Nov 2026
Paid to
B
Blinkit
blinkit.payu@hdfcbank
7286
Transfer Details
Message
UPIIntent
PhonePe Transaction ID
T2611060604060808497253
Debited from
XXXX566372
7286
UTR: 995940082093''')!;
  check(misread.amountUnconfirmed, 'an amount found without any rupee sign is flagged');
  check(phonePeToRow(misread).note.contains('CHECK THE AMOUNT'), 'the note asks to check the amount');
  check(!phonePeToRow(normal).note.contains('CHECK THE AMOUNT'), 'a confirmed amount has no such note');
  final PhonePeEntry tPrefix = parseUpiScreenshotText(phonePe('T286').replaceAll('₹286', 'T286'))!;
  check(tPrefix.amount == 286 && tPrefix.amountUnconfirmed, 'a "T" read for the rupee sign still gives 286, flagged');

  check(parseUpiScreenshotText('Payment failed\n₹50\nUPI\n1 Nov 2026 5:00 pm') == null, 'failed ignored');
  check(parseUpiScreenshotText('hello 12 Oct 2026') == null, 'random text ignored');

  // ---- the best of several readings of one picture
  PhonePeEntry reading(double amount, {bool unconfirmed = false}) => PhonePeEntry(
      amount: amount, isExpense: true, party: 'x', date: DateTime(2026, 1, 1), amountUnconfirmed: unconfirmed);
  check(chooseBestReading([]) == null && chooseBestReading([null, null]) == null, 'no readings, no result');
  check(chooseBestReading([reading(7286, unconfirmed: true), reading(286)])!.amount == 286,
      'a reading with a rupee sign beats one without');
  check(chooseBestReading([reading(7286, unconfirmed: true)])!.amount == 7286,
      'with nothing better the only reading stays');
  check(chooseBestReading([reading(286), reading(280), reading(280)])!.amount == 280,
      'the amount seen most often wins');
  check(chooseBestReading([reading(286), reading(280)])!.amount == 286, 'a tie goes to the earlier reading');
  check(chooseBestReading([null, reading(50)])!.amount == 50, 'a failed reading is skipped');

  // ---- the rupee sign read as a 7 ("₹286" became "7286")
  final misread = parseUpiScreenshotText('''Transaction Successful
06:04 am on 06 Nov 2026
Paid to
Blinkit
7286
blinkit.payu@hdfcbank
Transfer Details
Message
UPIIntent
PhonePe Transaction ID
T2611060604060808497253
Debited from
XXXX566372
7286
UTR: 995940082093
Powered by''');
  check(misread != null && misread.amount == 286 && misread.amountUnconfirmed,
      'a rupee sign read as 7 is dropped: ${misread?.amount}');
  final real = parseUpiScreenshotText('''Transaction Successful
06:04 am on 06 Nov 2026
Paid to
Blinkit
₹7,286
blinkit.payu@hdfcbank
Debited from
XXXX566372
₹7,286
UTR: 995940082093''');
  check(real != null && real.amount == 7286 && !real.amountUnconfirmed, 'a real 7,286 with a rupee sign stays');
}
