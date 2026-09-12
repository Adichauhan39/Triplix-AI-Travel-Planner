/// The photo of the bill, attached to the expense it belongs to.
///
/// Every competing app has this, and it is the thing that ends an argument:
/// "I paid 1,800 for dinner" is a claim, and the bill is not. It also rescues
/// a ledger nobody filled in at the time -- the photos are still on somebody's
/// phone, and each one is a row.
///
/// Stored in Firestore rather than Firebase Storage. Storage is the right home
/// for large files and it is not set up on this project; provisioning a new
/// service, its rules and the CORS its web uploads need is a bigger change
/// than a receipt is worth. A bill compresses to a couple of hundred
/// kilobytes, which fits a document with room to spare.
///
/// The bytes live in their own document underneath the metadata, so a screen
/// can listen for which expenses have a receipt without pulling every image
/// down: Firestore listeners have no way to ask for some fields and not
/// others, so the only way to keep the index cheap is to keep the blob out of
/// it.
library;

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

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

/// What is known about a receipt without downloading it.
class ReceiptInfo {
  const ReceiptInfo({
    required this.expenseId,
    required this.by,
    required this.bytes,
    this.at,
  });

  factory ReceiptInfo.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ReceiptInfo(
      expenseId: doc.id,
      by: (data['by'] ?? '').toString(),
      bytes: (data['bytes'] as num?)?.round() ?? 0,
      at: (data['at'] as Timestamp?)?.toDate(),
    );
  }

  /// The expense this is a bill for. The receipt's id *is* the expense's id,
  /// so there is no way to have two receipts disagree about one row.
  final String expenseId;

  /// Who attached it.
  final String by;

  final int bytes;
  final DateTime? at;
}

/// Shrinks a photo to something storable, and says so when it cannot.
///
/// Pure apart from the decoding: give it bytes, it gives bytes back, which is
/// what makes the size guarantee testable rather than hoped for.
Uint8List? shrinkReceipt(
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

/// Receipts for one trip.
class ReceiptStore {
  ReceiptStore({FirebaseFirestore? store, FirebaseAuth? auth})
      : _store = store ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _store;
  final FirebaseAuth _auth;
  final ImagePicker _picker = ImagePicker();

  CollectionReference<Map<String, dynamic>> _receiptsOf(String tripId) =>
      _store.collection('trips').doc(tripId).collection('receipts');

  DocumentReference<Map<String, dynamic>> _imageOf(
          String tripId, String expenseId) =>
      _receiptsOf(tripId).doc(expenseId).collection('image').doc('data');

  /// Which expenses have a bill attached. Metadata only, so this can be
  /// listened to for a whole trip without downloading a single photo.
  Stream<Map<String, ReceiptInfo>> watch(String tripId) {
    if (tripId.isEmpty) {
      return const Stream<Map<String, ReceiptInfo>>.empty();
    }
    return _receiptsOf(tripId).snapshots().map((snapshot) => {
          for (final doc in snapshot.docs)
            doc.id: ReceiptInfo.fromDoc(doc),
        }).handleError((Object e) {
      debugPrint('ReceiptStore.watch failed: $e');
    });
  }

  /// Takes or picks a photo, shrinks it, and attaches it to an expense.
  ///
  /// Returns a message to show when it did not work, and null when it did --
  /// every failure here has a different fix, and "that did not work" tells
  /// somebody nothing about which one they are looking at.
  Future<String?> attach({
    required String tripId,
    required String expenseId,
    required bool fromCamera,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return 'Sign in first.';
    if (tripId.isEmpty || expenseId.isEmpty) return 'Nothing to attach it to.';

    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        // Asked for here as well as done below. Where the platform honours
        // it, the photo arrives already small and the work below is cheap;
        // on the web it is ignored, which is why the resize is not left to it.
        maxWidth: 2000,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('ReceiptStore.attach pick failed: $e');
      return fromCamera
          ? 'The camera could not be opened. Choosing a photo instead works '
              'the same.'
          : 'That photo could not be opened.';
    }
    if (picked == null) return null;

    final raw = await picked.readAsBytes();
    final small = shrinkReceipt(raw);
    if (small == null) {
      return 'That image could not be made small enough to store. A photo of '
          'the bill rather than a screenshot of a document usually works.';
    }

    try {
      // Metadata and bytes in two documents, written metadata-last so a
      // half-finished upload never shows as a receipt with nothing behind it.
      await _imageOf(tripId, expenseId).set({
        'jpeg': base64Encode(small),
        'by': uid,
      });
      await _receiptsOf(tripId).doc(expenseId).set({
        'by': uid,
        'bytes': small.length,
        'at': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      debugPrint('ReceiptStore.attach write failed: $e');
      return 'That could not be saved. Check your connection.';
    }
  }

  /// The bill itself, fetched only when somebody asks to see it.
  Future<Uint8List?> image({
    required String tripId,
    required String expenseId,
  }) async {
    try {
      final doc = await _imageOf(tripId, expenseId).get();
      final encoded = (doc.data()?['jpeg'] ?? '').toString();
      if (encoded.isEmpty) return null;
      return base64Decode(encoded);
    } catch (e) {
      debugPrint('ReceiptStore.image failed: $e');
      return null;
    }
  }

  /// Removes a receipt. The bytes go first: a metadata row with no image is
  /// a broken attachment, while an image with no metadata is invisible and
  /// harmless.
  Future<bool> remove({
    required String tripId,
    required String expenseId,
  }) async {
    try {
      await _imageOf(tripId, expenseId).delete();
      await _receiptsOf(tripId).doc(expenseId).delete();
      return true;
    } catch (e) {
      debugPrint('ReceiptStore.remove failed: $e');
      return false;
    }
  }
}
