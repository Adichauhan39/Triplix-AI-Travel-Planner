import 'dart:async';

import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/trip_photo_service.dart';

/// Full-screen Trip Reel — an Instagram Reels-style vertical slideshow
/// of AI-curated travel photos with captions and transitions.
class TripReelScreen extends StatefulWidget {
  final List<TripPhoto> photos;
  const TripReelScreen({super.key, required this.photos});

  @override
  State<TripReelScreen> createState() => _TripReelScreenState();
}

class _TripReelScreenState extends State<TripReelScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _progressController;
  int _currentIndex = 0;
  bool _isPaused = false;
  Timer? _autoAdvanceTimer;

  static const _slideDuration = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _progressController = AnimationController(
      vsync: this,
      duration: _slideDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_isPaused) {
          _nextSlide();
        }
      });
    _progressController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressController.dispose();
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  void _nextSlide() {
    if (_currentIndex < widget.photos.length - 1) {
      setState(() => _currentIndex++);
      _pageController.animateToPage(_currentIndex,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      _progressController.reset();
      _progressController.forward();
    } else {
      // Loop back or finish
      setState(() => _currentIndex = 0);
      _pageController.animateToPage(0,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      _progressController.reset();
      _progressController.forward();
    }
  }

  void _prevSlide() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _pageController.animateToPage(_currentIndex,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      _progressController.reset();
      _progressController.forward();
    }
  }

  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
    if (_isPaused) {
      _progressController.stop();
    } else {
      _progressController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('No approved photos for reel',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.localPosition.dx < width / 3) {
            _prevSlide();
          } else if (details.localPosition.dx > width * 2 / 3) {
            _nextSlide();
          } else {
            _togglePause();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo slides
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.photos.length,
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                return _buildSlide(photo, index);
              },
            ),

            // Progress bars at top
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: List.generate(widget.photos.length, (i) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 3,
                      child: i < _currentIndex
                          ? Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            )
                          : i == _currentIndex
                              ? AnimatedBuilder(
                                  animation: _progressController,
                                  builder: (_, __) => ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: _progressController.value,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.3),
                                      valueColor:
                                          const AlwaysStoppedAnimation(
                                              Colors.white),
                                      minHeight: 3,
                                    ),
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                    ),
                  );
                }),
              ),
            ),

            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Pause indicator
            if (_isPaused)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.pause,
                      color: Colors.white, size: 48),
                ),
              ),

            // Bottom caption & counter
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    20, 40, 20, MediaQuery.of(context).padding.bottom + 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.photos[_currentIndex].aiCaption.isNotEmpty)
                      Text(
                        widget.photos[_currentIndex].aiCaption,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(blurRadius: 8, color: Colors.black54)
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppConfig.primaryColor.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.photos.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (widget
                            .photos[_currentIndex].qualityScore > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _scoreColor(widget
                                      .photos[_currentIndex].qualityScore)
                                  .withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.auto_awesome,
                                    size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.photos[_currentIndex].qualityScore.toInt()}%',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(TripPhoto photo, int index) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Image.memory(
        photo.bytes,
        key: ValueKey(photo.id),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 80) return AppConfig.successColor;
    if (score >= 60) return AppConfig.warningColor;
    return AppConfig.errorColor;
  }
}
