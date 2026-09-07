/// Hands a trip link to whatever the device shares with.
///
/// Copying to the clipboard was the only option, which leaves the person to
/// find WhatsApp themselves and paste it somewhere — and on a phone, where
/// most of this gets sent, the share sheet is one tap to exactly the right
/// conversation.
///
/// The clipboard stays as the fallback rather than the default. Web Share
/// exists only over HTTPS, only inside a real user gesture, and not at all in
/// several desktop browsers; a share button that silently does nothing on a
/// laptop would be worse than the copy it replaced.
library;

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// What actually happened, so the caller can say the right thing.
enum ShareOutcome {
  /// The share sheet opened.
  shared,

  /// No share sheet here, so the link is on the clipboard instead.
  copied,

  /// Neither worked.
  failed,
}

/// Offers [link] through the share sheet, falling back to the clipboard.
///
/// Must be called straight from a tap. Browsers only allow Web Share inside
/// the gesture that triggered it, so anything awaited first — a Firestore
/// write, a render — has to happen before this, not inside it.
Future<ShareOutcome> shareLink(String link, {required String message}) async {
  if (link.isEmpty) return ShareOutcome.failed;

  try {
    final result = await Share.shareWithResult('$message\n\n$link');
    // Dismissing the sheet is not a failure and must not trigger the
    // fallback: copying a link somebody just decided not to send would leave
    // it on their clipboard unasked.
    if (result.status != ShareResultStatus.unavailable) {
      return ShareOutcome.shared;
    }
  } catch (_) {
    // No share sheet on this platform. Fall through.
  }

  try {
    await Clipboard.setData(ClipboardData(text: link));
    return ShareOutcome.copied;
  } catch (_) {
    return ShareOutcome.failed;
  }
}

/// What to tell the user afterwards.
String shareMessageFor(ShareOutcome outcome, {required String copied}) =>
    switch (outcome) {
      ShareOutcome.shared => 'Sent.',
      ShareOutcome.copied => copied,
      ShareOutcome.failed =>
        'That could not be shared. Copy the link from the address bar '
            'instead.',
    };
