/// Making a photograph small enough to store, without making it useless.
///
/// Shared by receipts and by reel photos, which want the same thing at
/// different sizes: a phone camera produces four or five megabytes and a
/// Firestore document holds one, so something has to give and it should be
/// the pixels nobody was reading.
library;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A Firestore document must stay under 1 MiB including field names and
/// overhead, so the image itself is held well below that. Base64 costs a
/// third on top of the raw bytes, and this is the budget after that cost.
const int maxReceiptBytes = 700 * 1024;

/// The longest edge a stored receipt keeps.
///
/// A bill has to be readable, not archival: 1,400px across is enough to read
/// the line items on a restaurant bill on a phone screen, and a 12MP camera
/// photo of one is four megabytes of table cloth.
const int receiptMaxEdge = 1400;

/// Shrinks a photo to something storable, and says so when it cannot.
///
/// Pure apart from the decoding: give it bytes, it gives bytes back, which is
/// what makes the size guarantee testable rather than hoped for.
Uint8List? shrinkImage(
  Uint8List original, {
  int maxEdge = receiptMaxEdge,
  int budget = maxReceiptBytes,
}) {
  // Wrapped, because decodeImage does not merely return null on rubbish: it
  // hands the bytes to each format decoder in turn and one of them throws on
  // a short or truncated file. A picker can return a truncated file, and the
  // person holding the phone should see "that photo could not be read", not
  // a crash.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(original);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;

  // Orientation first. A photo taken in portrait carries its rotation in EXIF
  // rather than in the pixels, and a receipt shown on its side is a receipt
  // nobody can read.
  final upright = img.bakeOrientation(decoded);

  // Size first, then quality, and both step down until it fits.
  //
  // A single fixed setting either wastes space on a plain bill or fails on an
  // awkward one -- a photo of a receipt on a patterned tablecloth can be
  // twice the size of the same bill on a table at the same quality. And
  // quality alone is not always enough: past a point the only thing left to
  // give is pixels, so a smaller but readable bill beats no bill at all.
  //
  // Ordered so the best result that fits is the one returned: the full size
  // at good quality is tried before anything is thrown away.
  for (final edge in [maxEdge, 1000, 800, 600]) {
    if (edge > maxEdge) continue;

    final longest =
        upright.width > upright.height ? upright.width : upright.height;
    final resized = longest > edge
        ? img.copyResize(
            upright,
            width: upright.width >= upright.height ? edge : null,
            height: upright.height > upright.width ? edge : null,
            interpolation: img.Interpolation.average,
          )
        : upright;

    for (final quality in [70, 55, 40, 28]) {
      final encoded = img.encodeJpg(resized, quality: quality);
      if (encoded.length <= budget) return Uint8List.fromList(encoded);
    }

    // Already as small as the source: shrinking further would be inventing
    // a smaller original, and there is nothing left to try.
    if (longest <= edge) break;
  }
  return null;
}

