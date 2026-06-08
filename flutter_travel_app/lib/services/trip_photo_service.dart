import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Manages trip photos: capture, store, AI-filter, and reel generation.
class TripPhotoService extends ChangeNotifier {
  static final TripPhotoService _instance = TripPhotoService._();
  factory TripPhotoService() => _instance;
  TripPhotoService._();

  final ImagePicker _picker = ImagePicker();
  final List<TripPhoto> _photos = [];
  bool _isAnalyzing = false;

  List<TripPhoto> get photos => List.unmodifiable(_photos);
  List<TripPhoto> get approvedPhotos =>
      _photos.where((p) => p.status == PhotoStatus.approved).toList();
  List<TripPhoto> get rejectedPhotos =>
      _photos.where((p) => p.status == PhotoStatus.rejected).toList();
  List<TripPhoto> get pendingPhotos =>
      _photos.where((p) => p.status == PhotoStatus.pending).toList();
  bool get isAnalyzing => _isAnalyzing;

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
      final bytes = await file.readAsBytes();
      final photo = TripPhoto(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        bytes: bytes,
        fileName: file.name,
        capturedAt: DateTime.now(),
        status: PhotoStatus.pending,
      );
      _photos.add(photo);
      notifyListeners();
      // Auto-analyze in background
      _analyzePhoto(photo);
      return photo;
    } catch (e) {
      debugPrint('[TripPhotoService] Add photo error: $e');
      return null;
    }
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
        final isTravel = data['is_travel_photo'] ?? false;
        final score = (data['quality_score'] ?? 50).toDouble();
        final caption = data['caption'] ?? '';
        final reason = data['rejection_reason'] ?? '';

        photo.qualityScore = score;
        photo.aiCaption = caption;
        photo.rejectionReason = reason;
        photo.status = isTravel && score >= 40
            ? PhotoStatus.approved
            : PhotoStatus.rejected;
      } else {
        // Fallback: approve all on server error
        photo.status = PhotoStatus.approved;
        photo.qualityScore = 70;
        photo.aiCaption = 'Travel moment';
      }
    } catch (e) {
      debugPrint('[TripPhotoService] AI analysis error: $e');
      // Fallback: approve on error
      photo.status = PhotoStatus.approved;
      photo.qualityScore = 60;
      photo.aiCaption = 'Travel photo';
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

  /// Manually override a photo's status
  void overrideStatus(String photoId, PhotoStatus status) {
    final photo =
        _photos.firstWhere((p) => p.id == photoId, orElse: () => _photos.first);
    photo.status = status;
    notifyListeners();
  }

  /// Remove a photo
  void removePhoto(String photoId) {
    _photos.removeWhere((p) => p.id == photoId);
    notifyListeners();
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
    final demoImages = <Map<String, String>>[
      {
        'url':
            'https://images.unsplash.com/photo-1524492412937-b28074a5d7da?w=800',
        'name': 'taj_mahal.jpg'
      },
      {
        'url':
            'https://images.unsplash.com/photo-1477587458883-47145ed94245?w=800',
        'name': 'kerala_backwaters.jpg'
      },
      {
        'url':
            'https://images.unsplash.com/photo-1506461883276-594a12b11cf3?w=800',
        'name': 'jaipur_palace.jpg'
      },
      {
        'url':
            'https://images.unsplash.com/photo-1512343879784-a960bf40e7f2?w=800',
        'name': 'goa_beach.jpg'
      },
      {
        'url':
            'https://images.unsplash.com/photo-1585135497273-1a86d9d39438?w=800',
        'name': 'varanasi_ghats.jpg'
      },
      {
        'url':
            'https://images.unsplash.com/photo-1567157577867-05ccb1388e13?w=800',
        'name': 'mumbai_gateway.jpg'
      },
      {
        'url':
            'https://images.unsplash.com/photo-1596422846543-75c6fc197f07?w=800',
        'name': 'rajasthan_fort.jpg'
      },
      {
        'url':
            'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=800',
        'name': 'indian_food.jpg'
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
          final photo = TripPhoto(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            bytes: response.bodyBytes,
            fileName: img['name']!,
            capturedAt: DateTime.now(),
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

enum PhotoStatus { pending, approved, rejected }

class TripPhoto {
  final String id;
  final Uint8List bytes;
  final String fileName;
  final DateTime capturedAt;
  PhotoStatus status;
  double qualityScore;
  String aiCaption;
  String rejectionReason;

  TripPhoto({
    required this.id,
    required this.bytes,
    required this.fileName,
    required this.capturedAt,
    this.status = PhotoStatus.pending,
    this.qualityScore = 0,
    this.aiCaption = '',
    this.rejectionReason = '',
  });
}
