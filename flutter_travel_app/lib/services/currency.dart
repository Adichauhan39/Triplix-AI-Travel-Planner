/// Money spent in somebody else's currency.
///
/// The expense reader treated every number as rupees, so "50 dollars for the
/// taxi" was filed as ₹50 -- a hundredth of what it cost -- and "1000 nepali
/// rupees for the permit" as ₹1,000, which is more than it cost. Silently, both
/// ways, on exactly the trips where people most need the arithmetic done for
/// them.
///
/// Two halves. Reading the currency out of what somebody typed is pure and
/// tested. Converting it uses real published rates, fetched on the device and
/// kept, so an expense added with no signal still converts at the last rate
/// the phone saw -- and says that is what it did.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_store.dart';

/// An amount in a currency other than rupees.
class ForeignAmount {
  const ForeignAmount({
    required this.amount,
    required this.code,
    required this.matched,
  });

  final double amount;

  /// ISO 4217, e.g. USD.
  final String code;

  /// The exact text that named the money -- "50 dollars", "$50" -- so the
  /// caller can take it out of the sentence before reading what it was for.
  final String matched;
}

/// What each currency is called, by the words people actually type.
///
/// Longest names first within each currency is not needed here: matching runs
/// over [_words] sorted by length, so "nepali rupees" is tried before
/// "rupees" and never lost to it.
const Map<String, String> _words = {
  // United States, and the default for a bare "$" or "dollars": by far the
  // likeliest one for somebody travelling from India, and the others are
  // named when meant.
  'usd': 'USD', 'dollar': 'USD', 'dollars': 'USD', 'us dollars': 'USD',
  'singapore dollar': 'SGD', 'singapore dollars': 'SGD', 'sgd': 'SGD',
  'australian dollar': 'AUD', 'australian dollars': 'AUD', 'aud': 'AUD',
  'canadian dollar': 'CAD', 'canadian dollars': 'CAD', 'cad': 'CAD',
  'hong kong dollars': 'HKD', 'hkd': 'HKD',
  'euro': 'EUR', 'euros': 'EUR', 'eur': 'EUR',
  'pound': 'GBP', 'pounds': 'GBP', 'gbp': 'GBP', 'quid': 'GBP',
  'dirham': 'AED', 'dirhams': 'AED', 'aed': 'AED',
  'riyal': 'SAR', 'riyals': 'SAR', 'sar': 'SAR',
  'qar': 'QAR', 'qatari riyal': 'QAR', 'qatari riyals': 'QAR',
  'omr': 'OMR', 'omani rial': 'OMR',
  'baht': 'THB', 'thb': 'THB',
  'ringgit': 'MYR', 'myr': 'MYR',
  'rupiah': 'IDR', 'idr': 'IDR',
  'dong': 'VND', 'vnd': 'VND',
  'yen': 'JPY', 'jpy': 'JPY',
  'francs': 'CHF', 'chf': 'CHF', 'swiss francs': 'CHF',
  // Rupees that are not Indian rupees. Named with their country, because a
  // bare "rupees" from somebody in India means ours.
  'nepali rupee': 'NPR', 'nepali rupees': 'NPR', 'nepalese rupees': 'NPR',
  'npr': 'NPR',
  'sri lankan rupee': 'LKR', 'sri lankan rupees': 'LKR', 'lkr': 'LKR',
  'pakistani rupees': 'PKR', 'pkr': 'PKR',
  'maldivian rufiyaa': 'MVR', 'rufiyaa': 'MVR', 'mvr': 'MVR',
  'ngultrum': 'BTN', 'btn': 'BTN',
  'taka': 'BDT', 'bdt': 'BDT',
};

/// Symbols that name a currency on their own.
const Map<String, String> _symbols = {
  r'$': 'USD',
  '€': 'EUR',
  '£': 'GBP',
  '฿': 'THB',
  '¥': 'JPY',
};

/// What people call each currency back to them, for the confirmation.
const Map<String, String> currencyNames = {
  'USD': 'US dollars', 'SGD': 'Singapore dollars', 'AUD': 'Australian dollars',
  'CAD': 'Canadian dollars', 'HKD': 'Hong Kong dollars', 'EUR': 'euros',
  'GBP': 'pounds', 'AED': 'dirhams', 'SAR': 'riyals', 'QAR': 'Qatari riyals',
  'OMR': 'Omani rials', 'THB': 'baht', 'MYR': 'ringgit', 'IDR': 'rupiah',
  'VND': 'dong', 'JPY': 'yen', 'CHF': 'Swiss francs',
  'NPR': 'Nepali rupees', 'LKR': 'Sri Lankan rupees', 'PKR': 'Pakistani rupees',
  'MVR': 'rufiyaa', 'BTN': 'ngultrum', 'BDT': 'taka',
};

const String _number = r'(\d[\d,]*(?:\.\d+)?)';

/// Finds money in a foreign currency in what somebody typed, or null.
///
/// Null is the common answer and the safe one: anything that does not name a
/// foreign currency is left to the ordinary reader, which treats it as rupees
/// exactly as before. "500 rupees", "₹500", "rs 500" and a bare "500" are all
/// ours.
ForeignAmount? readForeignAmount(String text) {
  final lower = text.toLowerCase();

  double? parse(String raw) => double.tryParse(raw.replaceAll(',', ''));

  // Symbols, which sit in front of the number: $50, €20, £10.50.
  for (final entry in _symbols.entries) {
    final symbol = RegExp.escape(entry.key);
    final match = RegExp('$symbol\\s*$_number').firstMatch(lower);
    if (match != null) {
      final amount = parse(match.group(1)!);
      if (amount != null && amount > 0) {
        return ForeignAmount(
            amount: amount, code: entry.value, matched: match.group(0)!);
      }
    }
  }

  // Words and codes, after the number or before it: "50 dollars",
  // "usd 50", "50usd". Longest names first, so "nepali rupees" is found
  // before a shorter name inside it could be.
  final names = _words.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final name in names) {
    final word = RegExp.escape(name);
    final after = RegExp('$_number\\s*$word\\b').firstMatch(lower);
    final before = RegExp('\\b$word\\s*$_number').firstMatch(lower);
    final match = after ?? before;
    if (match == null) continue;

    final amount = parse(match.group(1)!);
    if (amount == null || amount <= 0) continue;
    return ForeignAmount(
        amount: amount, code: _words[name]!, matched: match.group(0)!);
  }

  return null;
}

/// A rate, and whether it could be trusted to be today's.
class RateQuote {
  const RateQuote({
    required this.code,
    required this.rupeesPerUnit,
    required this.asOf,
    required this.fromSaved,
  });

  final String code;

  /// How many rupees one unit costs: 1 USD = 96.02.
  final double rupeesPerUnit;

  /// When the source published it.
  final DateTime asOf;

  /// True when this came from the copy on the device rather than a fresh
  /// fetch -- no signal, or the source was down. Said to the traveller, since
  /// a rate from last week is still a rate but should not look like today's.
  final bool fromSaved;

  int rupeesToPaise(double amount) => (amount * rupeesPerUnit * 100).round();
}

/// Converts foreign money to rupees at published rates.
class CurrencyRates {
  /// ExchangeRate-API's open endpoint: no key, updated daily, and it covers
  /// the currencies Indian travellers actually use -- Nepal, Sri Lanka, the
  /// Gulf, Thailand, Bhutan -- which several larger free sources do not.
  /// Their terms ask for attribution, which the screen gives.
  static const String _source = 'https://open.er-api.com/v6/latest/INR';

  static const String _savedKey = 'triplix.fx_rates';

  /// How long a fetched table is used before fetching again. The source
  /// publishes once a day, so asking more often gets the same numbers.
  static const Duration _fresh = Duration(hours: 6);

  /// The rate for one currency.
  ///
  /// Tries the saved table if it is recent, then the network, then the saved
  /// table however old it is -- and returns null only when there has never
  /// been a rate on this device at all.
  static Future<RateQuote?> quote(String code) async {
    final wanted = code.toUpperCase();
    final saved = LocalStore.load(_savedKey);

    RateQuote? fromTable(Map<String, dynamic>? table, {required bool saved}) {
      if (table == null) return null;
      final rates = (table['rates'] as Map?)?.cast<String, dynamic>();
      // The table is priced from rupees: rates[USD] is dollars per rupee.
      final perRupee = (rates?[wanted] as num?)?.toDouble();
      if (perRupee == null || perRupee <= 0) return null;
      final stamp = (table['time_last_update_unix'] as num?)?.toInt() ?? 0;
      return RateQuote(
        code: wanted,
        rupeesPerUnit: 1 / perRupee,
        asOf: DateTime.fromMillisecondsSinceEpoch(stamp * 1000),
        fromSaved: saved,
      );
    }

    final savedAt = DateTime.tryParse((saved?['saved_at'] ?? '').toString());
    final recent =
        savedAt != null && DateTime.now().difference(savedAt) < _fresh;
    if (recent) {
      final quote = fromTable(saved, saved: false);
      if (quote != null) return quote;
    }

    try {
      final response = await http
          .get(Uri.parse(_source))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final table = json.decode(response.body) as Map<String, dynamic>;
        if (table['result'] == 'success') {
          await LocalStore.save(
              _savedKey, {...table, 'saved_at': DateTime.now().toIso8601String()});
          final quote = fromTable(table, saved: false);
          if (quote != null) return quote;
        }
      }
    } catch (e) {
      debugPrint('CurrencyRates.quote could not fetch: $e');
    }

    // Whatever the device last saw, however old. Better a known rate marked
    // as old than refusing to record money somebody has already spent.
    return fromTable(saved, saved: true);
  }
}
