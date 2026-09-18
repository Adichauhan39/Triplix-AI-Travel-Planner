import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/currency.dart';

void main() {
  ForeignAmount? read(String s) => readForeignAmount(s);

  group('foreign money is recognised', () {
    test('words after the number', () {
      expect(read('50 dollars for taxi')?.code, 'USD');
      expect(read('50 dollars for taxi')?.amount, 50);
      expect(read('200 dirhams for dinner')?.code, 'AED');
      expect(read('500 baht for massage')?.code, 'THB');
      expect(read('20 euros for museum')?.code, 'EUR');
    });

    test('symbols in front', () {
      expect(read('\$50 for taxi')?.code, 'USD');
      expect(read('€20 museum')?.code, 'EUR');
      expect(read('£10.50 coffee')?.amount, 10.5);
    });

    test('codes either side', () {
      expect(read('USD 20 for sim card')?.code, 'USD');
      expect(read('20 usd sim')?.code, 'USD');
      expect(read('aed 150 taxi')?.code, 'AED');
    });

    test('commas in big numbers', () {
      final r = read('150,000 rupiah for villa');
      expect(r?.code, 'IDR');
      expect(r?.amount, 150000);
    });

    test('other rupees are named with their country', () {
      // The case that overcharged: 1000 Nepali rupees is about ₹620.
      expect(read('1000 nepali rupees for trek permit')?.code, 'NPR');
      expect(read('3000 sri lankan rupees tuk tuk')?.code, 'LKR');
    });

    test('the more specific dollar wins over plain dollars', () {
      expect(read('40 singapore dollars for chilli crab')?.code, 'SGD');
      expect(read('30 australian dollars')?.code, 'AUD');
    });

    test('says which words it matched, so they can be taken out', () {
      expect(read('paid 50 dollars for taxi')?.matched, '50 dollars');
    });
  });

  group('our own money is left alone', () {
    // Null here means "treat it as rupees exactly as before", which is what
    // every one of these is.
    test('rupees, however it is written', () {
      expect(read('500 rupees for cab'), isNull);
      expect(read('₹500 cab'), isNull);
      expect(read('rs 500 cab'), isNull);
      expect(read('inr 500 cab'), isNull);
      expect(read('500 for the cab'), isNull);
    });

    test('a bare rupees is Indian, not Nepali', () {
      expect(read('1000 rupees for trek permit'), isNull);
    });

    test('no amount, no currency', () {
      expect(read('dollars'), isNull);
      expect(read('I love euros'), isNull);
    });

    test('a word that merely contains a currency name is not one', () {
      // "cad" inside "cadbury", "dong" inside "dongle".
      expect(read('200 for cadbury'), isNull);
      expect(read('500 for a usb dongle'), isNull);
    });
  });

  group('turning it into rupees', () {
    test('rupees per unit times the amount, in paise', () {
      final q = RateQuote(
        code: 'USD',
        rupeesPerUnit: 96.02,
        asOf: DateTime(2026, 9, 17),
        fromSaved: false,
      );
      expect(q.rupeesToPaise(50), 480100, reason: '50 x 96.02 = ₹4,801.00');
    });

    test('a currency worth less than a rupee', () {
      final q = RateQuote(
        code: 'NPR',
        rupeesPerUnit: 0.625,
        asOf: DateTime(2026, 9, 17),
        fromSaved: false,
      );
      expect(q.rupeesToPaise(1000), 62500, reason: '₹625, not ₹1,000');
    });
  });
}
