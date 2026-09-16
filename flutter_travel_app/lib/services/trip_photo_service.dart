import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'image_shrink.dart';
import 'trip_photos.dart';

/// Manages trip photos: capture, store, AI-filter, and reel generation.
class TripPhotoService extends ChangeNotifier {
  static final TripPhotoService _instance = TripPhotoService._();
  factory TripPhotoService() => _instance;
  TripPhotoService._();

  final ImagePicker _picker = ImagePicker();
  final TripPhotoStore _store = TripPhotoStore();
  final List<TripPhoto> _photos = [];
  bool _isAnalyzing = false;

  /// The trip these photos belong to.
  ///
  /// Empty means nothing can be saved: a photo with no trip has nowhere to
  /// live and nothing to be a reel of. The screen says so rather than
  /// collecting pictures that will vanish on the next refresh.
  String _tripId = '';

  String get tripId => _tripId;
  bool get canSave => _tripId.isNotEmpty;

  List<TripPhoto> get photos => List.unmodifiable(_photos);
  List<TripPhoto> get approvedPhotos =>
      _photos.where((p) => p.status == PhotoStatus.approved).toList();
  List<TripPhoto> get rejectedPhotos =>
      _photos.where((p) => p.status == PhotoStatus.rejected).toList();
  List<TripPhoto> get pendingPhotos =>
      _photos.where((p) => p.status == PhotoStatus.pending).toList();

  /// Photos the checker could not reach a verdict on. Shown to the person
  /// rather than quietly included or quietly dropped.
  List<TripPhoto> get uncheckedPhotos =>
      _photos.where((p) => p.status == PhotoStatus.unchecked).toList();
  bool get isAnalyzing => _isAnalyzing;

  /// Points the reel at a trip and loads what is already there.
  ///
  /// Called when the Reel tab opens. Switching trips clears the list first,
  /// so one trip's pictures never appear under another's name.
  Future<void> bindTrip(String tripId) async {
    if (tripId == _tripId) return;
    _tripId = tripId;
    _photos.clear();
    notifyListeners();
    if (tripId.isEmpty) return;

    final saved = await _store.watch(tripId).first;
    if (tripId != _tripId) return; // They moved on while this was loading.

    for (final row in saved) {
      _photos.add(TripPhoto(
        id: row.id,
        // The small copy. The full image is fetched when something needs to
        // show it large, which is the point of storing the two apart.
        bytes: row.thumb ?? Uint8List(0),
        fileName: row.caption.isEmpty ? 'photo.jpg' : row.caption,
        capturedAt: row.takenAt ?? DateTime.now(),
        timeFromPhoto: row.takenAt != null,
        lat: row.lat,
        lng: row.lng,
        status: _statusOf(row.verdict),
        qualityScore: row.score,
        aiCaption: row.caption,
        rejectionReason: row.reason,
      ));
    }
    notifyListeners();
  }

  static PhotoStatus _statusOf(PhotoVerdict verdict) => switch (verdict) {
        PhotoVerdict.approved => PhotoStatus.approved,
        PhotoVerdict.rejected => PhotoStatus.rejected,
        PhotoVerdict.unchecked => PhotoStatus.unchecked,
        PhotoVerdict.waiting => PhotoStatus.pending,
      };

  static PhotoVerdict _verdictOf(PhotoStatus status) => switch (status) {
        PhotoStatus.approved => PhotoVerdict.approved,
        PhotoStatus.rejected => PhotoVerdict.rejected,
        PhotoStatus.unchecked => PhotoVerdict.unchecked,
        PhotoStatus.pending => PhotoVerdict.waiting,
      };

  /// The full-size photo, for showing one large or putting it in a film.
  Future<Uint8List?> fullImage(String photoId) =>
      _store.image(tripId: _tripId, photoId: photoId);

  /// Capture a photo from camera
  Future<TripPhoto?> capturePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      if (image == null) return null;
      return await _addPhoto(image);
    } catch (e) {
      debugPrint('[TripPhotoService] Camera error: $e');
      return null;
    }
  }

  /// Pick photo from gallery
  Future<TripPhoto?> pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      if (image == null) return null;
      return await _addPhoto(image);
    } catch (e) {
      debugPrint('[TripPhotoService] Gallery error: $e');
      return null;
    }
  }

  /// Pick multiple photos from gallery
  Future<List<TripPhoto>> pickMultiple() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      final results = <TripPhoto>[];
      for (final img in images) {
        final photo = await _addPhoto(img);
        if (photo != null) results.add(photo);
      }
      return results;
    } catch (e) {
      debugPrint('[TripPhotoService] Multi-pick error: $e');
      return [];
    }
  }

  Future<TripPhoto?> _addPhoto(XFile file) async {
    try {
      final raw = await file.readAsBytes();

      // The time and place out of the photo's own EXIF, read before the
      // resize: re-encoding drops the metadata, and this is what lets a reel
      // run in the order the trip happened.
      final origin = readOrigin(raw);

      // Shrunk once, then used for everything -- the checker, the store and
      // the screen. A phone photo is four megabytes and none of the three
      // wants that.
      final small = shrinkImage(raw, maxEdge: 1600) ?? raw;

      final photo = TripPhoto(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        bytes: small,
        fileName: file.name,
        capturedAt: origin.takenAt ?? DateTime.now(),
        timeFromPhoto: origin.takenAt != null,
        lat: origin.lat,
        lng: origin.lng,
        status: PhotoStatus.pending,
      );
      _photos.add(photo);
      notifyListeners();

      // Checked first, then saved with its verdict, so a photo never sits in
      // the trip as "approved" before anything has looked at it.
      await _analyzePhoto(photo);
      await _persist(photo, small, origin);
      return photo;
    } catch (e) {
      debugPrint('[TripPhotoService] Add photo error: $e');
      return null;
    }
  }

  /// Writes a photo and its verdict to the trip.
  Future<void> _persist(
      TripPhoto photo, Uint8List bytes, PhotoOrigin origin) async {
    if (!canSave) return;
    final id = await _store.save(
      tripId: _tripId,
      shrunk: bytes,
      origin: origin,
      verdict: _verdictOf(photo.status),
      score: photo.qualityScore,
      caption: photo.aiCaption,
      reason: photo.rejectionReason,
    );
    // The stored id replaces the local one, so a later verdict change or
    // delete addresses the document that actually exists.
    if (id != null) photo.storedId = id;
  }

  /// Use AI to classify the photo
  Future<void> _analyzePhoto(TripPhoto photo) async {
    try {
      final base64Image = base64Encode(photo.bytes);

      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/api/analyze-photo'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'image_base64': base64Image,
              'file_name': photo.fileName,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // The server says whether it managed to look at all. A reply it
        // could not parse comes back checked: false rather than as a pass.
        final checked = data['checked'] != false;
        final isTravel = data['is_travel_photo'] ?? false;
        final score = (data['quality_score'] ?? 50).toDouble();
        final caption = data['caption'] ?? '';
        final reason = data['rejection_reason'] ?? '';

        photo.qualityScore = score;
        photo.aiCaption = caption;
        photo.rejectionReason = checked
            ? reason
            : 'We could not check this one — have a look before it goes in.';
        photo.status = !checked
            ? PhotoStatus.unchecked
            : isTravel && score >= 40
                ? PhotoStatus.approved
                : PhotoStatus.rejected;
      } else {
        // Not approved.
        //
        // A server error means nothing was checked, and approving on a 500
        // is how a receipt or an ID card ends up in a reel. The photo is
        // kept and handed back to the person to decide about.
        photo.status = PhotoStatus.unchecked;
        photo.qualityScore = 0;
        photo.aiCaption = '';
        photo.rejectionReason =
            'We could not check this one — have a look before it goes in.';
      }
    } catch (e) {
      debugPrint('[TripPhotoService] AI analysis error: $e');
      // Same again: an unreachable checker is not a pass.
      photo.status = PhotoStatus.unchecked;
      photo.qualityScore = 0;
      photo.aiCaption = '';
      photo.rejectionReason =
          'We could not check this one — have a look before it goes in.';
    }
    notifyListeners();
  }

  /// Batch analyze all pending photos
  Future<void> analyzeAllPending() async {
    _isAnalyzing = true;
    notifyListeners();
    for (final photo in pendingPhotos) {
      await _analyzePhoto(photo);
    }
    _isAnalyzing = false;
    notifyListeners();
  }

  /// Asks the checker to look at a photo again.
  ///
  /// The first thing to try on one it could not judge. Most of those failures
  /// are a moment's trouble -- a timeout, a hiccup, a reply that did not
  /// parse -- and the photograph itself is perfectly decidable, so asking
  /// again settles most of them without the person having to judge anything.
  Future<void> recheck(String photoId) async {
    final photo = _photos.where((p) => p.id == photoId).firstOrNull;
    if (photo == null) return;

    photo.status = PhotoStatus.pending;
    photo.rejectionReason = '';
    notifyListeners();

    await _analyzePhoto(photo);

    // The new verdict replaces the old one in the trip, so the answer sticks
    // rather than reverting on the next refresh.
    final stored = photo.storedId;
    if (canSave && stored != null) {
      await _store.setVerdict(
          tripId: _tripId,
          photoId: stored,
          verdict: _verdictOf(photo.status));
    }
    notifyListeners();
  }

  /// Manually override a photo's status.
  ///
  /// This is a person deciding -- overruling the checker, or settling one it
  /// could not check -- so it is written to the trip rather than held in
  /// memory until the next refresh undoes it.
  Future<void> overrideStatus(String photoId, PhotoStatus status) async {
    final photo = _photos.firstWhere((p) => p.id == photoId,
        orElse: () => _photos.first);
    photo.status = status;
    photo.rejectionReason = '';
    notifyListeners();

    final stored = photo.storedId;
    if (canSave && stored != null) {
      await _store.setVerdict(
          tripId: _tripId, photoId: stored, verdict: _verdictOf(status));
    }
  }

  /// Remove a photo.
  Future<void> removePhoto(String photoId) async {
    final photo = _photos.where((p) => p.id == photoId).firstOrNull;
    _photos.removeWhere((p) => p.id == photoId);
    notifyListeners();

    final stored = photo?.storedId;
    if (canSave && stored != null) {
      await _store.remove(tripId: _tripId, photoId: stored);
    }
  }

  /// Clear all photos
  void clearAll() {
    _photos.clear();
    notifyListeners();
  }

  /// Load demo travel photos from Unsplash for demo/presentation mode.
  /// Includes a mix of good travel photos AND bad ones (documents, blurry)
  /// so the AI filtering is visibly demonstrated.
  Future<void> loadDemoPhotos() async {
    if (_photos.isNotEmpty) return; // Don't reload if already loaded

    _isAnalyzing = true;
    notifyListeners();

    // Good travel photos (should be APPROVED by AI)
    // Position and time attached here rather than read from the files.
    //
    // These are stock pictures fetched over HTTP and they carry no metadata
    // whatsoever, so without this the demo could never show the part that
    // reads it. Everything downstream is the real path: the server looks each
    // position up the same way it would for a photograph off somebody's
    // phone, and the screen says plainly that these are samples.
    final demoImages = <Map<String, dynamic>>[
      {
        'url':
            'https://images.unsplash.com/photo-1524492412937-b28074a5d7da?w=800',
        'name': 'taj_mahal.jpg',
        'lat': 27.1751,
        'lng': 78.0421,
        'at': DateTime(2026, 9, 13, 6, 40)
      },
      {
        'url':
            'https://images.unsplash.com/photo-1477587458883-47145ed94245?w=800',
        'name': 'kerala_backwaters.jpg',
        'lat': 9.4981,
        'lng': 76.3388,
        'at': DateTime(2026, 9, 13, 9, 15)
      },
      {
        'url':
            'https://images.unsplash.com/photo-1506461883276-594a12b11cf3?w=800',
        'name': 'jaipur_palace.jpg',
        'lat': 26.9255,
        'lng': 75.8235,
        'at': DateTime(2026, 9, 13, 11, 30)
      },
      {
        'url':
            'https://images.unsplash.com/photo-1512343879784-a960bf40e7f2?w=800',
        'name': 'goa_beach.jpg',
        'lat': 15.5527,
        'lng': 73.7517,
        'at': DateTime(2026, 9, 13, 17, 50)
      },
      {
        'url':
            'https://images.unsplash.com/photo-1585135497273-1a86d9d39438?w=800',
        'name': 'varanasi_ghats.jpg',
        'lat': 25.282,
        'lng': 83.01,
        'at': DateTime(2026, 9, 14, 5, 55)
      },
      {
        'url':
            'https://images.unsplash.com/photo-1567157577867-05ccb1388e13?w=800',
        'name': 'mumbai_gateway.jpg',
        'lat': 18.922,
        'lng': 72.8347,
        'at': DateTime(2026, 9, 14, 10, 20)
      },
      {
        'url':
            'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=800',
        'name': 'rajasthan_fort.jpg',
        'lat': 26.9855,
        'lng': 75.8513,
        'at': DateTime(2026, 9, 14, 16, 5)
      },
      {
        'url':
            'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=800',
        'name': 'indian_food.jpg',
        'lat': 26.9196,
        'lng': 75.8267,
        'at': DateTime(2026, 9, 14, 19, 40)
      },
      // Bad photos (should be REJECTED by AI) — a document and a blurry text image
      {
        'url':
            'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=800',
        'name': 'receipt_document.jpg'
      },
      {
        'url':
            'https://images.unsplash.com/photo-1586281380349-632531db7ed4?w=800',
        'name': 'spreadsheet_doc.jpg'
      },
    ];

    for (final img in demoImages) {
      try {
        final response = await http
            .get(Uri.parse(img['url']!))
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final when = img['at'] as DateTime?;
          final photo = TripPhoto(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            bytes: response.bodyBytes,
            fileName: img['name'] as String,
            capturedAt: when ?? DateTime.now(),
            timeFromPhoto: when != null,
            lat: (img['lat'] as num?)?.toDouble(),
            lng: (img['lng'] as num?)?.toDouble(),
            status: PhotoStatus.pending,
          );
          _photos.add(photo);
          notifyListeners();
          // Analyze each photo through AI
          await _analyzePhoto(photo);
        }
      } catch (e) {
        debugPrint('[TripPhotoService] Demo photo load error: $e');
      }
    }

    _isAnalyzing = false;
    notifyListeners();
  }
}

/// What is known about a photo.
///
/// `unchecked` is deliberately separate from `approved`. The checker exists
/// to keep documents, receipts, ID cards and worse out of a reel somebody is
/// about to post, and every failure path here used to return `approved` -- so
/// the moment it broke it published exactly what it was built to stop. A
/// check that did not happen is not a pass.
enum PhotoStatus { pending, approved, rejected, unchecked }

class TripPhoto {
  final String id;
  final Uint8List bytes;
  final String fileName;
  final DateTime capturedAt;
  PhotoStatus status;
  double qualityScore;
  String aiCaption;
  String rejectionReason;

  /// Where the photograph was taken, when it knows.
  ///
  /// Null for anything that arrived through a sharing app -- they strip the
  /// metadata -- and for a phone with location switched off. Nothing may
  /// depend on it being here.
  double? lat;
  double? lng;

  bool get hasPlace => lat != null && lng != null;

  /// Whether [capturedAt] is the photograph's own time or merely when it
  /// was added.
  ///
  /// The two must not be confused where anybody can see them. A photo that
  /// reached the phone through a sharing app has no EXIF at all -- most of
  /// them strip it -- so its time falls back to the upload, and printing that
  /// under a holiday picture states a time the photograph was not taken. Only
  /// a real one is ever shown.
  bool timeFromPhoto = false;

  /// The id this has in the trip, once it has been written there.
  ///
  /// Separate from [id], which is a local timestamp made before anything was
  /// saved: a verdict change has to address the document that exists, not the
  /// moment the photo was picked.
  String? storedId;

  TripPhoto({
    required this.id,
    required this.bytes,
    required this.fileName,
    required this.capturedAt,
    this.status = PhotoStatus.pending,
    this.qualityScore = 0,
    this.aiCaption = '',
    this.rejectionReason = '',
    this.timeFromPhoto = false,
    this.lat,
    this.lng,
  });
}
