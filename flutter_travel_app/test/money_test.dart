import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/money.dart';

void main() {
  group('India stays exactly as it was', () {
    test('rupees, grouped the Indian way', () {
      expect(formatMoney(50000, 'INR'), '₹500');
      expect(formatMoney(10000000, 'INR'), '₹1,00,000');
      expect(formatMoney(123456789, 'INR'), '₹12,34,567.89');
    });

    test('no currency named means rupees, because that is what the data is', () {
      // Every expense written before trips had a currency is in paise.
      // Defaulting to anything else would silently reprice the database.
      expect(formatMoney(50000, null), '₹500');
      expect(formatMoney(50000, ''), '₹500');
      expect(legacyCurrency, 'INR');
    });
  });

  group('the rest of the world', () {
    test('threes, not lakhs', () {
      expect(formatMoney(10000000, 'USD'), '\$100,000');
      expect(formatMoney(123456789, 'GBP'), '£1,234,567.89');
      expect(formatMoney(100000, 'EUR'), '€1,000');
    });

    test('currencies with no small change are not multiplied', () {
      // ¥500 is five hundred yen. Treating it as 500 sen would show ¥5.
      expect(formatMoney(500, 'JPY'), '¥500');
      expect(toMinorUnits(500, 'JPY'), 500);
      expect(toMinorUnits(500, 'USD'), 50000);
    });

    test('a symbol that follows the number', () {
      expect(formatMoney(150000, 'VND'), '150,000₫');
    });

    test('an unknown currency uses its own code rather than pretending', () {
      expect(formatMoney(50000, 'XYZ'), 'XYZ 500');
    });
  });

  group('turning typed amounts into stored ones', () {
    test('two decimals where there are two', () {
      expect(toMinorUnits(12.34, 'USD'), 1234);
      expect(toMinorUnits(500, 'INR'), 50000);
    });

    test('and back again', () {
      expect(fromMinorUnits(1234, 'USD'), 12.34);
      expect(fromMinorUnits(500, 'JPY'), 500);
    });

    test('rounding lands on whole minor units, never fractions of a cent', () {
      // Money in fractions of a cent is how a split stops adding up.
      expect(toMinorUnits(0.015, 'USD'), 2);
      expect(toMinorUnits(33.333, 'INR'), 3333);
    });
  });
}
