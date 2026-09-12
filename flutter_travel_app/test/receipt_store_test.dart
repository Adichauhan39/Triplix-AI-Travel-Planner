import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_travel_app/services/receipt_store.dart';

/// Noise: the worst case for JPEG, and nothing like a bill. Used only where
/// the point is that compression cannot always win.
Uint8List noise({required int width, required int height}) {
  final canvas = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      canvas.setPixelRgb(x, y, (x * 7 + y * 13) % 256, (x * 3) % 256,
          (y * 11 + x) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 100));
}

/// Something shaped like a photo of a bill: pale paper, dark lines of text,
/// a bit of grain. This is what the budget is actually sized for, so it is
/// what the budget is tested against.
Uint8List bill({required int width, required int height}) {
  final canvas = img.Image(width: width, height: height);
  img.fill(canvas, color: img.ColorRgb8(246, 244, 240));
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      // Grain, so it does not compress like a flat colour.
      final grain = ((x * 31 + y * 17) % 11) - 5;
      // Lines of "text" across the paper.
      final onLine = (y ~/ (height / 40)) % 2 == 0 &&
          x > width * 0.1 &&
          x < width * 0.9 &&
          (x ~/ 6) % 3 != 0;
      final shade = onLine ? 40 : 246 + grain;
      canvas.setPixelRgb(x, y, shade, shade, shade);
    }
  }
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 100));
}

void main() {
  group('shrinking a receipt', () {
    test('a camera-sized photo comes back inside the budget', () {
      // The point of the whole function: a 12MP photo is several megabytes,
      // and a Firestore document cannot hold one.
      final big = bill(width: 2400, height: 1800);
      expect(big.length, greaterThan(maxReceiptBytes),
          reason: 'the fixture has to be too big, or this proves nothing');

      final small = shrinkReceipt(big);
      expect(small, isNotNull);
      expect(small!.length, lessThanOrEqualTo(maxReceiptBytes));
    });

    test('the long edge is brought down to the limit', () {
      final small = shrinkReceipt(bill(width: 2400, height: 1800));
      final decoded = img.decodeImage(small!)!;
      expect(decoded.width, receiptMaxEdge);
      expect(decoded.height, 1050, reason: 'the shape is kept');
    });

    test('a portrait photo is measured on its own long edge', () {
      final small = shrinkReceipt(bill(width: 1500, height: 3000));
      final decoded = img.decodeImage(small!)!;
      expect(decoded.height, receiptMaxEdge);
      expect(decoded.width, 700);
    });

    test('a small photo is not blown up', () {
      // Enlarging a picture of a bill adds no detail and costs bytes.
      final small = shrinkReceipt(bill(width: 600, height: 400));
      final decoded = img.decodeImage(small!)!;
      expect(decoded.width, 600);
      expect(decoded.height, 400);
    });

    test('quality drops as far as it has to, and no further', () {
      // A tight budget must still produce something rather than giving up.
      final small = shrinkReceipt(bill(width: 2400, height: 1800),
          budget: 90 * 1024);
      expect(small, isNotNull);
      expect(small!.length, lessThanOrEqualTo(90 * 1024));
    });

    test('an impossible budget fails rather than storing something broken', () {
      expect(shrinkReceipt(noise(width: 2400, height: 1800), budget: 200),
          isNull);
    });

    test('bytes that are not an image are refused', () {
      expect(shrinkReceipt(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
      expect(shrinkReceipt(Uint8List(0)), isNull);
    });

    test('what comes back is a readable JPEG', () {
      // Stored base64 is useless if it does not decode on the way out.
      final small = shrinkReceipt(bill(width: 2000, height: 1500));
      expect(img.decodeJpg(small!), isNotNull);
    });
  });
}
