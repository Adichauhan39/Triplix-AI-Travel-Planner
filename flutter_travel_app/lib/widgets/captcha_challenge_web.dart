// Web-only implementation of the reCAPTCHA v2 checkbox challenge.
//
// Uses:
//  * dart:html to create the DOM container that Google's grecaptcha script binds to
//  * dart:ui_web platformViewRegistry to embed that container inside Flutter
//  * dart:js_util to call grecaptcha.render() with our sitekey and callbacks
//
// This file is only imported on Flutter Web (see captcha_challenge.dart).

// ignore_for_file: avoid_web_libraries_in_flutter, uri_does_not_exist, undefined_prefixed_name

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

int _instanceCounter = 0;

Widget buildCaptcha({
  required String siteKey,
  required void Function(String token) onVerified,
}) {
  return _WebRecaptchaCheckbox(siteKey: siteKey, onVerified: onVerified);
}

class _WebRecaptchaCheckbox extends StatefulWidget {
  const _WebRecaptchaCheckbox({
    required this.siteKey,
    required this.onVerified,
  });

  final String siteKey;
  final void Function(String token) onVerified;

  @override
  State<_WebRecaptchaCheckbox> createState() => _WebRecaptchaCheckboxState();
}

class _WebRecaptchaCheckboxState extends State<_WebRecaptchaCheckbox> {
  late final String _viewType;
  late final html.DivElement _container;
  bool _renderRequested = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final int idx = _instanceCounter++;
    _viewType = 'triplix-recaptcha-view-$idx';
    _container = html.DivElement()
      ..id = 'triplix-recaptcha-container-$idx'
      ..style.width = '304px'
      ..style.height = '78px'
      ..style.display = 'flex'
      ..style.justifyContent = 'center'
      ..style.alignItems = 'center';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _container,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryRenderRecaptcha();
    });
  }

  Future<void> _tryRenderRecaptcha() async {
    if (_renderRequested) return;
    _renderRequested = true;

    // Wait until grecaptcha script is loaded (up to ~10 seconds).
    Object? grecaptcha;
    for (int i = 0; i < 100; i++) {
      final candidate = js_util.getProperty(html.window, 'grecaptcha');
      if (candidate != null && js_util.hasProperty(candidate, 'render')) {
        grecaptcha = candidate;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (grecaptcha == null) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not load reCAPTCHA. Check your internet connection and try again.';
      });
      return;
    }

    try {
      final params = js_util.jsify(<String, dynamic>{
        'sitekey': widget.siteKey,
        'theme': 'light',
        'size': 'normal',
        'callback': js_util.allowInterop((dynamic token) {
          // Force to string regardless of JS type wrappers.
          final tokenStr = token?.toString() ?? '';
          debugPrint('[reCAPTCHA] Received token (len=${tokenStr.length})');
          if (tokenStr.isNotEmpty) {
            widget.onVerified(tokenStr);
          }
        }),
        'expired-callback': js_util.allowInterop(() {
          debugPrint('[reCAPTCHA] Token expired');
        }),
        'error-callback': js_util.allowInterop(() {
          debugPrint('[reCAPTCHA] Error callback fired');
        }),
      });

      final result = js_util
          .callMethod(grecaptcha, 'render', <Object?>[_container, params]);
      debugPrint('[reCAPTCHA] Rendered with widget id: $result');
    } catch (e, st) {
      debugPrint('[reCAPTCHA] Render failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'reCAPTCHA failed to render. Verify your site key and domain settings.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      );
    }
    return SizedBox(
      width: 304,
      height: 78,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
