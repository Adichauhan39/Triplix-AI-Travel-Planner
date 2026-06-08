import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/material.dart';

class VoiceInputService {
  static html.SpeechRecognition? _recognition;
  static bool _isListening = false;
  
  /// Initialize speech recognition (Web Speech API)
  static void initialize() {
    if (_recognition == null) {
      try {
        // Check if supported first
        if (!isSupported()) {
          print('❌ Speech recognition not supported in this browser');
          return;
        }

        _recognition = html.SpeechRecognition();
        _recognition!.continuous = false;  // Stop after one phrase (better for commands)
        _recognition!.interimResults = true;
        _recognition!.lang = 'en-IN'; // Indian English
        _recognition!.maxAlternatives = 1;
        print('🎤 Voice recognition initialized (continuous: false, lang: en-IN)');
      } catch (e) {
        print('❌ Failed to initialize speech recognition: $e');
        _recognition = null;
      }
    }
  }
  
  /// Start listening to voice input
  static Future<String?> startListening({
    required Function(String) onResult,
    required Function(String) onPartialResult,
    required Function() onEnd,
    Function(String)? onError,
  }) async {
    initialize();
    
    if (_recognition == null) {
      print('❌ Speech recognition not available');
      if (onError != null) {
        onError('Speech recognition not available');
      }
      return null;
    }
    
    if (_isListening) {
      print('⚠️ Already listening, stopping previous session...');
      stopListening();
      // Wait a bit before starting new session
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    String? finalTranscript;
    
    try {
      _recognition!.onResult.listen((event) {
        try {
          // Use js_util to safely access JavaScript properties
          final dynamic jsResults = js_util.getProperty(event, 'results');
          
          if (jsResults != null) {
            // Get the length using js_util
            final int length = js_util.getProperty(jsResults, 'length') as int;
            
            if (length > 0) {
              // Access the last result (most recent)
              final dynamic lastResult = js_util.callMethod(jsResults, 'item', [length - 1]);
              
              // Access the first alternative (best match)
              final dynamic firstAlternative = js_util.callMethod(lastResult, 'item', [0]);
              
              // Get transcript and isFinal flag using js_util
              final String transcript = js_util.getProperty(firstAlternative, 'transcript') as String? ?? '';
              final bool isFinal = js_util.getProperty(lastResult, 'isFinal') as bool? ?? false;

              print('🎤 Speech result - isFinal: $isFinal, text: "$transcript"');

              if (isFinal) {
                // Final result
                finalTranscript = transcript;
                print('✅ FINAL TRANSCRIPT: "$transcript"');
                onResult(transcript);
              } else {
                // Partial/interim result
                print('⏳ Partial: "$transcript"');
                onPartialResult(transcript);
              }
            }
          }
        } catch (e) {
          print('❌ Error processing speech result: $e');
          if (onError != null) {
            onError('Error processing speech result: $e');
          }
        }
      });
      
      _recognition!.onEnd.listen((_) {
        _isListening = false;
        print('🛑 Recognition ended');
        onEnd();
      });

      _recognition!.onStart.listen((_) {
        print('🎙️ Speech recognition started successfully');
      });
      
      _recognition!.onError.listen((error) {
        _isListening = false;
        try {
          final errorMessage = error.error ?? 'Unknown error';
          print('❌ Speech recognition error: $errorMessage');
          if (onError != null) {
            onError(errorMessage);
          }
        } catch (e) {
          print('❌ Error handling speech recognition error: $e');
          if (onError != null) {
            onError('Speech recognition error occurred');
          }
        }
      });
      
      print('▶️ Starting speech recognition...');
      _recognition!.start();
      _isListening = true;

      // Add timeout in case recognition doesn't start
      Future.delayed(const Duration(seconds: 5), () {
        if (_isListening && finalTranscript == null) {
          print('⏰ Speech recognition timeout - stopping');
          stopListening();
          if (onError != null) {
            onError('Speech recognition timeout');
          }
        }
      });
      
    } catch (e) {
      print('❌ Error starting speech recognition: $e');
      _isListening = false;
      if (onError != null) {
        onError(e.toString());
      }
    }
    
    return finalTranscript;
  }
  
  /// Stop listening
  static void stopListening() {
    if (_recognition != null && _isListening) {
      _recognition!.stop();
      _isListening = false;
    }
  }
  
  /// Check if currently listening
  static bool get isListening => _isListening;
  
  /// Check if speech recognition is supported in this browser
  static bool isSupported() {
    return html.SpeechRecognition.supported;
  }
}

/// Voice Input Button Widget
class VoiceInputButton extends StatefulWidget {
  final Function(String) onTranscript;
  final String tooltip;
  final Color? color;
  final double size;
  
  const VoiceInputButton({
    super.key,
    required this.onTranscript,
    this.tooltip = 'Tap to speak',
    this.color,
    this.size = 24,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  bool _isListening = false;
  String _partialText = '';
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    // Stop animation first
    if (_animationController.isAnimating) {
      _animationController.stop();
    }
    _animationController.dispose();
    
    // Stop listening if active
    if (_isListening) {
      VoiceInputService.stopListening();
    }
    
    super.dispose();
  }

  void _toggleListening() {
    if (!VoiceInputService.isSupported()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not supported in this browser. Please use Chrome or Edge.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_isListening) {
      VoiceInputService.stopListening();
      _animationController.stop();
      _animationController.reset();
      setState(() {
        _isListening = false;
        _partialText = '';
      });
    } else {
      setState(() {
        _isListening = true;
        _partialText = 'Listening...';
      });
      _animationController.repeat(reverse: true);

      VoiceInputService.startListening(
        onResult: (transcript) {
          print('✅ [VoiceButton] Final transcript received: "$transcript"');
          final cleanTranscript = transcript.trim();
          if (cleanTranscript.isNotEmpty && mounted) {
            print('📤 [VoiceButton] Calling onTranscript callback with: "$cleanTranscript"');
            // Call the callback IMMEDIATELY
            widget.onTranscript(cleanTranscript);
            print('✅ [VoiceButton] Callback executed');
          } else {
            print('⚠️ [VoiceButton] Empty transcript, skipping callback');
          }
          if (mounted) {
            _animationController.stop();
            _animationController.reset();
            setState(() {
              _isListening = false;
              _partialText = '';
            });
          }
        },
        onPartialResult: (transcript) {
          print('⏳ [VoiceButton] Partial transcript: "$transcript"');
          if (mounted) {
            setState(() {
              _partialText = transcript;
            });
          }
        },
        onEnd: () {
          print('🛑 [VoiceButton] Recognition ended');
          if (mounted) {
            _animationController.stop();
            _animationController.reset();
            setState(() {
              _isListening = false;
              _partialText = '';
            });
          }
        },
        onError: (error) {
          print('❌ [VoiceButton] Error: $error');
          if (mounted) {
            _animationController.stop();
            _animationController.reset();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Voice Error: $error'),
                backgroundColor: Colors.red,
              ),
            );
            setState(() {
              _isListening = false;
              _partialText = '';
            });
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: widget.tooltip,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              // Safety check to prevent animation issues
              if (!mounted) return const SizedBox.shrink();
              
              return Transform.scale(
                scale: _isListening ? _scaleAnimation.value : 1.0,
                child: IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    size: widget.size,
                    color: _isListening
                        ? Colors.red
                        : (widget.color ?? Theme.of(context).primaryColor),
                  ),
                  onPressed: _toggleListening,
                  tooltip: _isListening ? 'Stop listening' : 'Start voice input',
                ),
              );
            },
          ),
        ),
        if (_partialText.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Text(
              _partialText,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.blue,
              ),
            ),
          ),
      ],
    );
  }
}

/// Floating Voice Assistant Button (like Google Assistant)
class FloatingVoiceButton extends StatelessWidget {
  final Function(String) onTranscript;
  final String tooltip;

  const FloatingVoiceButton({
    super.key,
    required this.onTranscript,
    this.tooltip = 'Voice Assistant',
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.mic, color: Colors.blue),
                SizedBox(width: 8),
                Text('Voice Assistant'),
              ],
            ),
            content: VoiceInputButton(
              onTranscript: (transcript) {
                Navigator.pop(context);
                onTranscript(transcript);
              },
              size: 48,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
      tooltip: tooltip,
      child: const Icon(Icons.mic),
    );
  }
}
