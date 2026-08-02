import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Returns a [NumberFormat] that groups digits appropriately for the given
/// currency code.
///
/// * INR uses the Indian numbering system (1,00,000 for a lakh).
/// * All other supported currencies use the Western grouping (100,000).
NumberFormat groupedNumberFormat(String currencyCode) {
  final locale = currencyCode.toUpperCase() == 'INR' ? 'en_IN' : 'en_US';
  return NumberFormat.decimalPattern(locale);
}

/// Formats a numeric string as the user types by inserting thousand
/// separators based on the currently selected currency's convention.
///
/// The input is stripped of anything that is not a digit, and the resulting
/// integer is reformatted with grouping. The cursor is placed at the end of
/// the formatted text, which is the natural position when typing amounts.
///
/// Use together with [FilteringTextInputFormatter.digitsOnly] is unnecessary
/// because this formatter already discards non-digits.
class CurrencyInputFormatter extends TextInputFormatter {
  CurrencyInputFormatter({required this.currencyCode, this.maxDigits = 15});

  /// ISO 4217 currency code (e.g. 'USD', 'INR', 'EUR').
  final String currencyCode;

  /// Hard cap on digits, to keep the value inside a safe int range.
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final trimmed = digitsOnly.length > maxDigits
        ? digitsOnly.substring(0, maxDigits)
        : digitsOnly;

    // Strip any leading zeros (except when the entire input is "0").
    final normalized = trimmed.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final parsed = int.tryParse(normalized) ?? 0;
    final formatted = groupedNumberFormat(currencyCode).format(parsed);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
