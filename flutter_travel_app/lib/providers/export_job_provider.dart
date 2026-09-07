import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/local_store.dart';
import '../services/python_adk_service.dart';

/// A film or PDF being built on the server, watched from anywhere in the app.
///
/// This used to live inside the trip screen, which meant the watching stopped
/// the moment you left it: the poll checked `mounted` and cancelled itself, so
/// switching to Budget or Bookings abandoned the render. Coming back started
/// the count again from zero. The render itself was always server-side; only
/// the watching was tied to a page, and now it is not.
///
/// Being a provider rather than a screen field also means the "your film is
/// ready" message can be shown wherever the person happens to be standing.
class ExportJobProvider extends ChangeNotifier {
  ExportJobProvider({PythonADKService? adk})
      : _adk = adk ?? PythonADKService();

  final PythonADKService _adk;
  Timer? _poll;

  String? _jobId;
  String _format = 'mp4';
  double _progress = 0;
  String _stage = '';
  String? _error;
  Uint8List? _bytes;

  /// Set when a finished file has not yet been handed to the user, so a
  /// notification is shown once and not on every rebuild.
  bool _announced = false;

  String? get jobId => _jobId;
  String get format => _format;
  double get progress => _progress;
  String get stage => _stage;
  String? get error => _error;
  Uint8List? get bytes => _bytes;

  bool get isRunning => _jobId != null;
  bool get isReady => _bytes != null;

  /// Whether a finished file still needs announcing. Reading it clears the
  /// flag, so the message appears once however many screens are listening.
  bool takeAnnouncement() {
    if (!_announced) return false;
    _announced = false;
    return true;
  }

  /// Picks up a render that was already running.
  ///
  /// The job lives on the server, so reopening the app should find the film
  /// waiting rather than starting it again.
  void restore() {
    if (_jobId != null) return;
    final stored = LocalStore.load(LocalStore.keyExportJob);
    final jobId = (stored?['job_id'] ?? '').toString();
    if (jobId.isEmpty) return;
    _jobId = jobId;
    _format = (stored?['format'] ?? 'mp4').toString();
    _stage = 'Still working';
    _startPolling();
  }

  /// Queues a render and starts watching it.
  Future<bool> start({
    required List<Map<String, dynamic>> days,
    required String destination,
    required String format,
    bool includePhotos = true,
  }) async {
    _format = format;
    _progress = 0;
    _stage = 'Starting';
    _error = null;
    _bytes = null;
    notifyListeners();

    final queued = await _adk.startExport(
      days: days,
      destination: destination,
      format: format,
      includePhotos: includePhotos,
    );
    final jobId = (queued?['job_id'] ?? '').toString();
    if (jobId.isEmpty) {
      _error = "Couldn't start the $format. Check your connection.";
      _stage = '';
      notifyListeners();
      return false;
    }

    LocalStore.save(
        LocalStore.keyExportJob, {'job_id': jobId, 'format': format});
    _jobId = jobId;
    notifyListeners();
    _startPolling();
    return true;
  }

  /// How many polls in a row have come back empty.
  ///
  /// One failed poll is not a failed render -- the server may simply be busy
  /// with the frame it is on -- but an unbroken run of them means the request
  /// is not getting through, and saying so beats a bar that never moves.
  int _silentPolls = 0;

  void _startPolling() {
    _poll?.cancel();
    _silentPolls = 0;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  Future<void> _tick() async {
    final jobId = _jobId;
    if (jobId == null) {
      _poll?.cancel();
      return;
    }

    final status = await _adk.exportStatus(jobId);

    if (status == null) {
      _silentPolls++;
      if (_silentPolls >= 15) {
        _fail('Lost contact with the server while building your $_format. '
            'Try again when you are back online.');
      }
      return;
    }
    _silentPolls = 0;

    // A job the server no longer has.
    //
    // The renders live in the server's memory and their files on its disk, so
    // a restart -- a deploy, or the instance being recycled when idle --
    // forgets every one of them. The reply then carries no "state" at all,
    // which the old code read as an empty string: not "error", not "done", so
    // it kept polling a job that no longer existed, showing 0% for ever. Said
    // plainly instead, so the render can be started again.
    if ((status['status'] ?? '').toString() == 'error' ||
        status['state'] == null) {
      final reason = (status['message'] ?? '').toString();
      if (reason == 'unknown_job') {
        _fail('The server restarted and lost this render. Start it again '
            'when you are ready.');
      } else {
        _fail("Couldn't build the $_format${reason.isEmpty ? '' : ' — $reason'}.");
      }
      return;
    }

    final state = (status['state'] ?? '').toString();
    if (state == 'error') {
      _fail("Couldn't build the $_format — ${status['message']}");
      return;
    }

    _progress = (status['progress'] as num?)?.toDouble() ?? _progress;
    _stage = (status['stage'] ?? '').toString();
    notifyListeners();

    if (state != 'done') return;

    _poll?.cancel();
    final bytes = await _adk.fetchExport(jobId);
    LocalStore.save(LocalStore.keyExportJob, null);
    _jobId = null;
    if (bytes == null) {
      _error = 'The file was built but could not be collected.';
    } else {
      _error = null;
      _bytes = Uint8List.fromList(bytes);
      _announced = true;
    }
    notifyListeners();
  }

  void _fail(String message) {
    _poll?.cancel();
    LocalStore.save(LocalStore.keyExportJob, null);
    _jobId = null;
    _progress = 0;
    _stage = '';
    _error = message;
    notifyListeners();
  }

  /// Clears a finished file once it has been handed over.
  void clearReady() {
    _bytes = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Abandons the render. The server finishes it regardless; this only stops
  /// us waiting.
  void cancel() {
    _poll?.cancel();
    LocalStore.save(LocalStore.keyExportJob, null);
    _jobId = null;
    _progress = 0;
    _stage = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
