import re

# Reference implementation. The Dart port in lib/struct/smsTransactionParser.dart must give the same
# answers; keep every pattern identical.

NOT_TXN = re.compile(r"requested money|will be debited|is due|due on|not completed|if debited|passbook|has been initiated|e-mandate|mandate|\botp\b|one.?time password|verification code|balance enquiry|statement|total amt due|min amt due", re.I)
AMT_RE = re.compile(r"(?:rs\.?|inr|\u20b9)\s*(\d[\d,]*(?:\.\d+)?)", re.I)
AMT_BY_RE = re.compile(r"(?:debited|credited)\s+(?:by|for|with)\s+(\d[\d,]*(?:\.\d+)?)", re.I)
DEBIT_RE = re.compile(r"\bdebit(?:ed)?\b(?! card)|spent|\bpaid\b|withdrawn|\bsent\b|purchase|payment of|transaction number \d+ for", re.I)
CREDIT_RE = re.compile(r"credited|received|refund|deposited", re.I)
CARD_BILL_RE = re.compile(r"payment of .{0,24}(?:has been|is) received (?:on|towards) your .{0,60}credit card|credit ?card payment|payment .{0,30}towards your .{0,40}credit card|thank you for payment .{0,40}credit card", re.I)
DEBIT_THEN_CREDIT_RE = re.compile(r";\s*.+? credited\.", re.I)
DEBITED_RE = re.compile(r"\bdebited\b", re.I)

M_AXIS = re.compile(r"UPI/P2[MA]/\d+/(.+?)\s+Not you", re.I)
M_SBI = re.compile(r"(?:transfer|trf)\s+to\s+(.+?)\s+Ref\s?no", re.I)
M_FROM = re.compile(r"\bfrom\s+([A-Za-z][A-Za-z .&']+?)\.\s*UPI", re.I)
M_ICICI_ON = re.compile(r"\bon \d{1,2}-[A-Za-z]{3}-\d{2,4} on (.+?)\s*(?:-\s*)?\.", re.I)
M_AT_SIGN = re.compile(r"@\s*([A-Za-z0-9 .*&\-]+?)\s+\d{2}-\d{2}-\d{2,4}", re.I)
M_AT = re.compile(r"\bat\s+(.+?)(?:\s+on\s+\d|\s*\.\s+(?:Avl|Available))", re.I)
M_ICICI_SEMI = re.compile(r";\s*(.+?)\s+credited\.", re.I)
M_UPI_DASH = re.compile(r"UPI-\d+-([A-Za-z0-9 .&]+?)(?:\.|\s*To dispute|$)", re.I)
M_USING = re.compile(r"using\s+([A-Za-z ]+?)\s+is successful", re.I)
M_AGAINST = re.compile(r"against\s+([A-Za-z ]+?)(?:,|\.)", re.I)
M_VPA = re.compile(r"to VPA\s+([A-Za-z0-9._\-]+)@", re.I)
M_INFO_DASH = re.compile(r"\bInfo\s*-\s*([A-Za-z][A-Za-z ]+)", re.I)
M_INFO = re.compile(r"Info[:\-]?\s*([A-Za-z]+)[*\-]", re.I)
M_ORDER = re.compile(r"\b(zepto|swiggy|zomato|blinkit|amazon|flipkart|myntra)\b", re.I)
ATM_RE = re.compile(r"withdrawn at .{0,40}\bATM\b|\bATM\b.{0,30}withdrawn|cash withdrawal", re.I)
VPA_TAIL_RE = re.compile(r"(?:[-.]\d{4,}.*|\.(?:payu|rzp|cc)\b.*)$", re.I)
VPA_DIGITS_RE = re.compile(r"\d{4,}$")
VPA_NOISE_RE = re.compile(r"^(?:[\d.\-]+|gpay-\d+|paytmqr\d*[a-z0-9]*|q\d+)$", re.I)
TERMINAL_RE = re.compile(r"^(?=.*\d)[A-Za-z0-9]{6,10}$")
SPACES_RE = re.compile(r"\s+")

CATEGORY_RULES = [
    ('transfer',      re.compile(r"bank account|own account|self transfer|\bidfc first bank\b", re.I)),
    ('travel',        re.compile(r"irctc|redbus|abhibus|makemytrip|goibibo|cleartrip|yatra|indigo|air ?india|vistara|akasa|oyo\b|lodge|resort|airbnb|trainman|ixigo", re.I)),
    ('transit',       re.compile(r"\buber\b|\bola\b|rapido|metro|fuel|petrol|diesel|hpcl|bpcl|iocl|fastag|tsrtc|apsrtc|parking|\btoll\b|namma yatri", re.I)),
    ('entertainment', re.compile(r"netflix|hotstar|spotify|prime video|bookmyshow|\bpvr\b|\binox\b|youtube|jiocinema|sonyliv|zee5|steam|playstation|play ?store|google play|cinema|movie", re.I)),
    ('bills_fees',    re.compile(r"\bjio\b|airtel|vodafone|\bvi\b|bsnl|tata ?sky|tata ?play|\bdth\b|electric|bescom|tsspdcl|tgspdcl|apspdcl|water board|broadband|fibernet|insurance|\blic\b|premium|\bemi\b|\bfees?\b|charges|bil\*|billdesk|\bbill\b|recharge|\bloan\b|\brent\b", re.I)),
    ('beauty',        re.compile(r"nykaa|salon|parlou?r|\bspa\b|beauty|cosmetic|barber|grooming|lakme|urban company", re.I)),
    ('gifts',         re.compile(r"\bgifts?\b|florist|flowers|archies", re.I)),
    ('work',          re.compile(r"github|\baws\b|amazon web|google cloud|digitalocean|notion|linkedin|openai|anthropic|godaddy|hosting|coworking|\bzoom\b", re.I)),
    ('groceries',     re.compile(r"zepto|blinkit|instamart|bigbasket|d-?mart|reliance smart|smart bazaar|supermarket|fruits?|vegetable|kirana|provision|grocer|ksheera|dairy|\bmilk\b|ratnadeep|spencer|more retail|\bsmart \d+", re.I)),
    ('dining',        re.compile(r"swiggy|zomato|food|restaurant|cafe|chai|\btea\b|bakery|biryani|pizza|\bkfc\b|mcdonald|domino|burger|momo|frankie|sweets|juice|ice ?cream|kitchen|dhaba|tiffin|canteen|\bmess\b|coffee|\bccd\b|starbucks|eatery|brew|hotel", re.I)),
    ('shopping',      re.compile(r"amazon|flipkart|myntra|ajio|meesho|tanishq|fancy|bangles|\bstores?\b|shoe|mobiles?|poorvika|ikea|lenskart|croma|decathlon|jewel|textile|clothing|fashion|boutique|saravana|pothys|trends|ecommerce|fsn|\bshop\b", re.I)),
    ('health',        re.compile(r"pharmacy|medplus|apollo|medical|hospital|clinic|diagnostic|pharma|1mg|netmeds|dental", re.I)),
]
CREDIT_INCOME_RE = re.compile(r"salary|interest|dividend|cashback|payout", re.I)


def clean(s):
    s = SPACES_RE.sub(" ", s)
    return s.strip(" .-*")


def merchant_of(body):
    if ATM_RE.search(body):
        return 'ATM withdrawal'
    for rx in (M_AXIS, M_SBI, M_FROM, M_ICICI_ON, M_AT_SIGN, M_AT, M_ICICI_SEMI, M_UPI_DASH, M_USING, M_AGAINST, M_INFO_DASH):
        m = rx.search(body)
        if m:
            v = clean(m.group(1))
            if v and not TERMINAL_RE.match(v):
                return v
    m = M_VPA.search(body)
    if m:
        h = m.group(1)
        if VPA_NOISE_RE.match(h):
            return ''
        return clean(VPA_DIGITS_RE.sub('', VPA_TAIL_RE.sub('', h)))
    m = M_INFO.search(body)
    if m:
        v = clean(m.group(1))
        return 'BillDesk' if v.upper() == 'BIL' else v
    m = M_ORDER.search(body)
    if m:
        return clean(m.group(1))
    return ''


def categorize(direction, merchant, body):
    if direction == 'credit':
        return 'income' if CREDIT_INCOME_RE.search(body) else ''
    for label, rx in CATEGORY_RULES:
        if rx.search(merchant):
            return label
    return ''


def title_case(s):
    if s == s.upper() or s == s.lower():
        return " ".join((w[:1].upper() + w[1:].lower()) for w in s.split(" ") if w)
    return s


def parse_full(body):
    """-> dict or None when the SMS is not a real, completed money movement."""
    if CARD_BILL_RE.search(body):
        am0 = AMT_RE.search(body)
        amount0 = float(am0.group(1).replace(',', '')) if am0 else 0.0
        return dict(amount=amount0, direction='debit', merchant='', cardPayment=True,
                    category='', title='Card bill payment')
    if NOT_TXN.search(body):
        return None
    am = AMT_BY_RE.search(body) or AMT_RE.search(body)
    if not am:
        return None
    amount = float(am.group(1).replace(',', ''))
    d = DEBIT_RE.search(body)
    c = CREDIT_RE.search(body)
    if not d and not c:
        return None
    if d and c:
        direction = 'debit' if d.start() < c.start() else 'credit'
    else:
        direction = 'debit' if d else 'credit'
    # "... debited for Rs 25.00 ...; Hyderabad Metro credited." is still a debit
    if DEBITED_RE.search(body) and DEBIT_THEN_CREDIT_RE.search(body):
        direction = 'debit'
    merchant = merchant_of(body)
    category = categorize(direction, merchant, body)
    if merchant:
        title = title_case(merchant)
    else:
        title = 'Payment' if direction == 'debit' else 'Money received'
    title = title[:60].strip()
    return dict(amount=amount, direction=direction, merchant=merchant, cardPayment=False,
                category=category, title=title)
