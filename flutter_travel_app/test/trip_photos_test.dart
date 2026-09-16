import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/trip_photos.dart';

void main() {
  group('reading a photo\'s own time and place', () {
    test('finds when and where it was taken', () {
      // A real JPEG carrying real EXIF: Hawa Mahal, 14 Sep 2026, 11:40.
      // This is the whole reason a reel can run in the order a trip happened
      // and put each picture where it belongs.
      final bytes = File('test/fixtures/jaipur_exif.jpg').readAsBytesSync();
      final origin = readOrigin(bytes);

      expect(origin.takenAt, DateTime(2026, 9, 14, 11, 40, 32));
      expect(origin.lat, closeTo(26.9239, 0.01));
      expect(origin.lng, closeTo(75.8267, 0.01));
    });

    test('a photo with no EXIF is not a broken photo', () {
      // Most photos arrive this way: sharing apps strip it, and screenshots
      // never had it. Nothing may depend on it being there.
      final bytes = File('test/fixtures/no_exif.jpg').readAsBytesSync();
      final origin = readOrigin(bytes);

      expect(origin.takenAt, isNull);
      expect(origin.lat, isNull);
      expect(origin.lng, isNull);
    });

    test('rubbish bytes do not throw', () {
      final origin = readOrigin(Uint8List.fromList([1, 2, 3, 4]));
      expect(origin.takenAt, isNull);
      expect(origin.lat, isNull);
    });
  });

  group('what may be published', () {
    ReelPhoto photo(PhotoVerdict verdict) => ReelPhoto(
          id: 'p', tripId: 't', by: 'me', verdict: verdict);

    test('only an actual approval', () {
      expect(photo(PhotoVerdict.approved).canPublish, isTrue);
      expect(photo(PhotoVerdict.rejected).canPublish, isFalse);
      expect(photo(PhotoVerdict.waiting).canPublish, isFalse);
    });

    test('"could not check" is not a yes', () {
      // The bug this whole state exists for: both failure paths used to
      // return approved, so a broken checker published the documents and ID
      // cards it was built to keep out.
      expect(photo(PhotoVerdict.unchecked).canPublish, isFalse);
    });
  });
}
