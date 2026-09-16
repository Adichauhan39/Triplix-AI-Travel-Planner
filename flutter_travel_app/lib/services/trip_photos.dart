/// Reel photos, kept with the trip they belong to.
///
/// They used to live in a list in memory and nowhere else: a refresh lost every
/// photo and every analysis paid for. Nothing tied them to a trip either, so a
/// reel could not know a picture was taken at Nahargarh Fort on day four -- it
/// was a slideshow of whatever happened to be in RAM.
///
/// Stored the way receipts are, for the same reason: the bytes in their own
/// document beneath the metadata, so a screen can list a trip's photos, their
/// verdicts and where they were taken without downloading a single image.
library;

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_shrink.dart';

/// What the checker decided about a photo.
enum PhotoVerdict {
  /// Looked at and considered fit for a reel.
  approved,

  /// Looked at and turned down -- a document, a screenshot, a blurry frame.
  rejected,

  /// Not looked at yet.
  waiting,

  /// The check could not be made.
  ///
  /// Deliberately its own answer rather than folded into approved. The filter
  /// exists to keep documents, ID cards and worse out of something the
  /// traveller is about to post, and both failure paths used to return
  /// "approved" -- so the moment it broke it published exactly what it was
  /// built to stop. Now the person decides.
  unchecked,
}

/// One photo in a trip's reel.
class ReelPhoto {
  const ReelPhoto({
    required this.id,
    required this.tripId,
    required this.by,
    required this.verdict,
    this.score = 0,
    this.caption = '',
    this.reason = '',
    this.category = 'other',
    this.takenAt,
    this.lat,
    this.lng,
    this.bytes = 0,
    this.thumb,
  });

  factory ReelPhoto.fromDoc(
      String tripId, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ReelPhoto(
      id: doc.id,
      tripId: tripId,
      by: (data['by'] ?? '').toString(),
      verdict: _verdictOf((data['verdict'] ?? 'waiting').toString()),
      score: (data['score'] as num?)?.toDouble() ?? 0,
      caption: (data['caption'] ?? '').toString(),
      reason: (data['reason'] ?? '').toString(),
      category: (data['category'] ?? 'other').toString(),
      takenAt: (data['taken_at'] as Timestamp?)?.toDate(),
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      bytes: (data['bytes'] as num?)?.round() ?? 0,
      thumb: _decodeThumb(data['thumb']),
    );
  }

  final String id;
  final String tripId;
  final String by;
  final PhotoVerdict verdict;

  /// 0-100, the checker's own rating.
  final double score;

  final String caption;

  /// Why it was turned down, or why it could not be checked.
  final String reason;

  final String category;

  /// When the photo was actually taken, out of the file itself rather than
  /// when it happened to be uploaded. This is what lets a reel run in the
  /// order the trip happened.
  final DateTime? takenAt;

  /// Where it was taken, out of the file's own GPS. Absent for a great many
  /// photos -- most phones strip it when sharing, and screenshots never had
  /// it -- so nothing may depend on it being there.
  final double? lat;
  final double? lng;

  final int bytes;

  /// A small copy, carried with the metadata.
  ///
  /// The grid has to show something, and fetching every full photo to draw a
  /// wall of thumbnails would pull megabytes to render a screen of
  /// postage stamps. Kept deliberately tiny -- a couple of hundred pixels --
  /// because a Firestore listener hands back whole documents.
  final Uint8List? thumb;

  bool get hasPlace => lat != null && lng != null;

  /// Whether this may go in a reel somebody shares.
  ///
  /// Only an actual approval. "Could not check" is not a yes.
  bool get canPublish => verdict == PhotoVerdict.approved;
}

/// A stored thumbnail, or null when there is not one. A photo saved before
/// thumbnails existed simply has no small copy, which the grid handles.
Uint8List? _decodeThumb(Object? value) {
  final encoded = (value ?? '').toString();
  if (encoded.isEmpty) return null;
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}

PhotoVerdict _verdictOf(String raw) => switch (raw) {
      'approved' => PhotoVerdict.approved,
      'rejected' => PhotoVerdict.rejected,
      'unchecked' => PhotoVerdict.unchecked,
      _ => PhotoVerdict.waiting,
    };

String _nameOf(PhotoVerdict verdict) => switch (verdict) {
      PhotoVerdict.approved => 'approved',
      PhotoVerdict.rejected => 'rejected',
      PhotoVerdict.unchecked => 'unchecked',
      PhotoVerdict.waiting => 'waiting',
    };

/// When and where a photo was taken, read out of the file.
class PhotoOrigin {
  const PhotoOrigin({this.takenAt, this.lat, this.lng});

  final DateTime? takenAt;
  final double? lat;
  final double? lng;
}

/// Reads the time and place out of a photo's own EXIF.
///
/// A phone records both at the moment of the shot, and both are already in
/// the bytes being uploaded -- so the order of a reel and the place each
/// picture belongs to cost nothing to know. Everything here is optional:
/// sharing apps strip EXIF, screenshots never had it, and a photo without it
/// is still a perfectly good photo.
PhotoOrigin readOrigin(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const PhotoOrigin();
    final exif = decoded.exif;

    // Numeric tags, not names.
    //
    // The library keys these directories by the EXIF tag number -- printing
    // the keys of a real photo gives 306 and 36867, not "DateTime". String
    // lookups silently returned null, so every photo read as having no
    // metadata at all and the whole feature quietly did nothing.
    const dateTimeOriginal = 0x9003; // 36867, when the shutter fired
    const dateTime = 0x0132; //        306,   when the file was written
    const latRef = 1, lat = 2, lngRef = 3, lng = 4;

    final raw = (exif.exifIfd[dateTimeOriginal] ?? exif.imageIfd[dateTime])
            ?.toString() ??
        '';

    DateTime? taken;
    // EXIF writes "2026:09:14 11:40:32" -- colons where a date wants dashes,
    // which DateTime.parse will not accept.
    final match =
        RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
            .firstMatch(raw.trim());
    if (match != null) {
      taken = DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    }

    return PhotoOrigin(
      takenAt: taken,
      lat: _degrees(exif.gpsIfd[lat], exif.gpsIfd[latRef]?.toString()),
      lng: _degrees(exif.gpsIfd[lng], exif.gpsIfd[lngRef]?.toString()),
    );
  } catch (e) {
    // A photo whose metadata cannot be read is not a broken photo.
    debugPrint('readOrigin failed: $e');
    return const PhotoOrigin();
  }
}

/// EXIF keeps a position as degrees, minutes and seconds plus a hemisphere.
double? _degrees(img.IfdValue? value, String? ref) {
  if (value == null || value.length < 3) return null;
  try {
    final decimal =
        value.toDouble(0) + value.toDouble(1) / 60 + value.toDouble(2) / 3600;
    if (decimal.isNaN || decimal.isInfinite || decimal > 180) return null;

    // S and W are the same number counted the other way.
    final hemisphere = (ref ?? '').trim().toUpperCase();
    final negative = hemisphere.startsWith('S') || hemisphere.startsWith('W');
    return negative ? -decimal : decimal;
  } catch (e) {
    debugPrint('_degrees failed: $e');
    return null;
  }
}

/// A trip's reel photos.
class TripPhotoStore {
  TripPhotoStore({FirebaseFirestore? store, FirebaseAuth? auth})
      : _store = store ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _store;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _photosOf(String tripId) =>
      _store.collection('trips').doc(tripId).collection('photos');

  DocumentReference<Map<String, dynamic>> _imageOf(
          String tripId, String photoId) =>
      _photosOf(tripId).doc(photoId).collection('image').doc('data');

  /// The trip's photos, newest shot first, without their bytes.
  Stream<List<ReelPhoto>> watch(String tripId) {
    if (tripId.isEmpty) return const Stream<List<ReelPhoto>>.empty();
    return _photosOf(tripId).snapshots().map((snapshot) {
      final rows = [
        for (final doc in snapshot.docs) ReelPhoto.fromDoc(tripId, doc)
      ];
      // In the order the trip happened, which is the order a reel should run
      // in. Photos with no timestamp of their own go last rather than first,
      // so they never open the film with an unplaceable frame.
      rows.sort((a, b) {
        final left = a.takenAt;
        final right = b.takenAt;
        if (left == null && right == null) return a.id.compareTo(b.id);
        if (left == null) return 1;
        if (right == null) return -1;
        return left.compareTo(right);
      });
      return rows;
    }).handleError((Object e) {
      debugPrint('TripPhotoStore.watch failed: $e');
    });
  }

  /// Saves one photo against a trip.
  ///
  /// [shrunk] is the already-resized JPEG; the caller shrinks it because the
  /// same bytes are sent to the checker, and doing it twice would be a second
  /// pass over a several-megabyte image for nothing.
  Future<String?> save({
    required String tripId,
    required Uint8List shrunk,
    required PhotoOrigin origin,
    required PhotoVerdict verdict,
    double score = 0,
    String caption = '',
    String reason = '',
    String category = 'other',
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || tripId.isEmpty || shrunk.isEmpty) return null;
    try {
      final doc = _photosOf(tripId).doc();
      // Bytes first, metadata second: a half-finished upload then reads as a
      // photo that is not there yet rather than one whose image is missing.
      await _imageOf(tripId, doc.id).set({
        'jpeg': base64Encode(shrunk),
        'by': uid,
      });
      // Small enough to sit in the metadata document without making the
      // listener expensive: 240px at low quality is a handful of kilobytes,
      // and this is what the grid draws.
      final thumb = shrinkImage(shrunk, maxEdge: 240, budget: 28 * 1024);

      await doc.set({
        'by': uid,
        if (thumb != null) 'thumb': base64Encode(thumb),
        'verdict': _nameOf(verdict),
        'score': score,
        'caption': caption,
        'reason': reason,
        'category': category,
        'bytes': shrunk.length,
        if (origin.takenAt != null)
          'taken_at': Timestamp.fromDate(origin.takenAt!),
        if (origin.lat != null) 'lat': origin.lat,
        if (origin.lng != null) 'lng': origin.lng,
        'at': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      debugPrint('TripPhotoStore.save failed: $e');
      return null;
    }
  }

  /// Changes a verdict, when the person overrules the checker or decides
  /// about one it could not check.
  Future<bool> setVerdict({
    required String tripId,
    required String photoId,
    required PhotoVerdict verdict,
  }) async {
    if (tripId.isEmpty || photoId.isEmpty) return false;
    try {
      await _photosOf(tripId).doc(photoId).update({
        'verdict': _nameOf(verdict),
        // The reason belonged to the checker's opinion, which no longer
        // stands once a person has looked at it themselves.
        'reason': '',
      });
      return true;
    } catch (e) {
      debugPrint('TripPhotoStore.setVerdict failed: $e');
      return false;
    }
  }

  /// One photo's bytes, fetched only when something needs to show it.
  Future<Uint8List?> image({
    required String tripId,
    required String photoId,
  }) async {
    try {
      final doc = await _imageOf(tripId, photoId).get();
      final encoded = (doc.data()?['jpeg'] ?? '').toString();
      if (encoded.isEmpty) return null;
      return base64Decode(encoded);
    } catch (e) {
      debugPrint('TripPhotoStore.image failed: $e');
      return null;
    }
  }

  Future<bool> remove({
    required String tripId,
    required String photoId,
  }) async {
    try {
      await _imageOf(tripId, photoId).delete();
      await _photosOf(tripId).doc(photoId).delete();
      return true;
    } catch (e) {
      debugPrint('TripPhotoStore.remove failed: $e');
      return false;
    }
  }
}
