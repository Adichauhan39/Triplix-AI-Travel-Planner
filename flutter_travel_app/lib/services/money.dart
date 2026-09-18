/// Money, in whatever currency a trip is settled in.
///
/// The ledger was written for one country: amounts were "paise", formatting was
/// "formatRupees", and a number with no currency named meant Indian rupees.
/// None of that survives the app being used anywhere else, and the failures are
/// silent ones -- the worst kind for money.
///
/// Three assumptions had to go.
///
/// Digit grouping is not universal. Indian grouping writes a hundred thousand
/// as 1,00,000; almost everywhere else writes 100,000. Printing lakhs to
/// somebody in London is not a rounding error but it reads as a typo, and it
/// makes the app look like it was not meant for them.
///
/// Not every currency has hundredths. Yen, won, dong and rupiah have no minor
/// unit at all: ¥500 is five hundred, not fifty thousand. Multiplying those by
/// a hundred on the way in would inflate every Japanese expense a
/// hundredfold, and the settlement would divide the inflated number without
/// anything looking wrong.
///
/// And "the home currency" is a property of the trip, not of the app. A trip
/// settled in pounds should treat rupees as the foreign money to convert.
///
/// Amounts are stored as whole minor units -- integers -- as they always were.
/// Money in fractions of a cent is how a split stops adding up.
library;

/// How one currency is written and divided.
class CurrencyStyle {
  const CurrencyStyle({
    required this.code,
    required this.symbol,
    this.decimals = 2,
    this.indianGrouping = false,
    this.symbolAfter = false,
  });

  final String code;
  final String symbol;

  /// How many minor units make one: 2 for most, 0 for the currencies that
  /// have no coins below the unit.
  final int decimals;

  /// 1,00,000 rather than 100,000. Used across the subcontinent.
  final bool indianGrouping;

  /// Some currencies are written with the symbol after the number.
  final bool symbolAfter;

  /// 100 for most currencies, 1 for the ones with no minor unit.
  int get minorPerUnit {
    var factor = 1;
    for (var i = 0; i < decimals; i++) {
      factor *= 10;
    }
    return factor;
  }
}

/// The currencies this app knows how to write.
///
/// A currency that is not here still works: it falls back to its own code and
/// two decimals, which is right for most of the world and wrong for nobody in
/// a way that loses money.
const Map<String, CurrencyStyle> currencyStyles = {
  'INR': CurrencyStyle(
      code: 'INR', symbol: '₹', indianGrouping: true),
  'PKR': CurrencyStyle(code: 'PKR', symbol: 'Rs', indianGrouping: true),
  'LKR': CurrencyStyle(code: 'LKR', symbol: 'Rs', indianGrouping: true),
  'NPR': CurrencyStyle(code: 'NPR', symbol: 'Rs', indianGrouping: true),
  'BDT': CurrencyStyle(code: 'BDT', symbol: '৳', indianGrouping: true),
  'USD': CurrencyStyle(code: 'USD', symbol: '\$'),
  'EUR': CurrencyStyle(code: 'EUR', symbol: '€'),
  'GBP': CurrencyStyle(code: 'GBP', symbol: '£'),
  'AUD': CurrencyStyle(code: 'AUD', symbol: 'A\$'),
  'CAD': CurrencyStyle(code: 'CAD', symbol: 'C\$'),
  'SGD': CurrencyStyle(code: 'SGD', symbol: 'S\$'),
  'AED': CurrencyStyle(code: 'AED', symbol: 'AED '),
  'SAR': CurrencyStyle(code: 'SAR', symbol: 'SAR '),
  'CHF': CurrencyStyle(code: 'CHF', symbol: 'CHF '),
  'THB': CurrencyStyle(code: 'THB', symbol: '฿'),
  'MYR': CurrencyStyle(code: 'MYR', symbol: 'RM'),
  'HKD': CurrencyStyle(code: 'HKD', symbol: 'HK\$'),
  'NZD': CurrencyStyle(code: 'NZD', symbol: 'NZ\$'),
  'ZAR': CurrencyStyle(code: 'ZAR', symbol: 'R'),
  'BRL': CurrencyStyle(code: 'BRL', symbol: 'R\$'),
  'MVR': CurrencyStyle(code: 'MVR', symbol: 'MVR '),
  'BTN': CurrencyStyle(code: 'BTN', symbol: 'Nu.', indianGrouping: true),
  // No minor unit. Multiplying these by a hundred would inflate every
  // expense a hundredfold, silently.
  'JPY': CurrencyStyle(code: 'JPY', symbol: '¥', decimals: 0),
  'KRW': CurrencyStyle(code: 'KRW', symbol: '₩', decimals: 0),
  'VND': CurrencyStyle(code: 'VND', symbol: '₫', decimals: 0,
      symbolAfter: true),
  'IDR': CurrencyStyle(code: 'IDR', symbol: 'Rp', decimals: 0),
};

/// What the app falls back to when a trip does not say.
///
/// Every expense written before trips had a currency is in Indian paise, so
/// this is not a preference -- it is what the existing data actually is.
/// Changing it would silently reprice every ledger in the database.
const String legacyCurrency = 'INR';

CurrencyStyle styleOf(String? code) {
  final wanted = (code ?? '').trim().toUpperCase();
  if (wanted.isEmpty) return currencyStyles[legacyCurrency]!;
  return currencyStyles[wanted] ??
      // Unknown but named: use its own code as the symbol, with a space, and
      // the usual two decimals. Better than pretending it is dollars.
      CurrencyStyle(code: wanted, symbol: '$wanted ');
}

/// Turns an amount somebody typed into whole minor units of [code].
///
/// 12.34 dollars is 1234 cents; 500 yen is 500, because a yen has no
/// hundredths.
int toMinorUnits(double amount, String? code) =>
    (amount * styleOf(code).minorPerUnit).round();

/// Minor units back to the amount, for arithmetic that needs a real number.
double fromMinorUnits(int minor, String? code) =>
    minor / styleOf(code).minorPerUnit;

/// Groups the whole part of a number the way [style] is written.
String _group(String whole, CurrencyStyle style) {
  if (!style.indianGrouping) {
    // Threes, from the right: 1234567 -> 1,234,567.
    final out = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
      out.write(whole[i]);
    }
    return out.toString();
  }

  // The subcontinent groups the last three, then twos: 1234567 -> 12,34,567.
  if (whole.length <= 3) return whole;
  final last3 = whole.substring(whole.length - 3);
  var rest = whole.substring(0, whole.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last3';
}

/// Money as somebody reading it expects to see it.
///
/// Always unsigned: a balance decides its own sign, since "+₹350" and
/// "owes ₹350" are different sentences about the same number and only the
/// caller knows which one it is making.
String formatMoney(int minor, String? code) {
  final style = styleOf(code);
  final value = minor.abs() / style.minorPerUnit;

  final text = style.decimals == 0
      ? value.round().toString()
      : (value == value.roundToDouble()
          ? value.round().toString()
          : value.toStringAsFixed(style.decimals));

  final parts = text.split('.');
  final whole = _group(parts[0], style);
  final shown = parts.length > 1 ? '$whole.${parts[1]}' : whole;

  return style.symbolAfter ? '$shown${style.symbol}' : '${style.symbol}$shown';
}
