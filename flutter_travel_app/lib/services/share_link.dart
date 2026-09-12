/// Hands a trip link to whoever it is for.
///
/// The one rule here: tapping share must always leave the link on the
/// clipboard. It used to try the device's share sheet first and copy only if
/// that sheet was reported unavailable -- so on desktop Chrome, where the
/// sheet opens but offers Mail and little else, somebody who closed it was
/// left with nothing copied and no link. That is the bug this file exists to
/// not have.
///
/// So the copy happens first, unconditionally, and the choices are offered
/// afterwards. Worst case the person pastes it themselves, which is what they
/// were doing before any of this.
///
/// The named apps are plain web links -- wa.me, t.me, mailto:, sms: -- rather
/// than installed-app integrations, because this ships as a web app. They work
/// from a laptop browser and from a phone browser, and on a phone they open
/// the real app when it is installed.
library;

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Puts [link] on the clipboard, and says whether it landed.
///
/// Call this straight from the tap. Clipboard writes in a browser need the
/// page to be focused and, in some browsers, to be inside the gesture.
Future<bool> copyLink(String link) async {
  if (link.isEmpty) return false;
  try {
    await Clipboard.setData(ClipboardData(text: link));
    return true;
  } catch (_) {
    return false;
  }
}

/// The message and the link together, as it gets sent.
String shareText({required String link, required String message}) =>
    '$message\n\n$link';

/// One place a link can be sent.
class ShareTarget {
  const ShareTarget({
    required this.id,
    required this.label,
    required this.url,
  });

  /// Which app, so the screen can pick its icon and colour without this file
  /// having to import anything visual.
  final String id;

  final String label;
  final Uri url;
}

/// Where a link can be sent from a browser.
///
/// Ordered by what people here actually use: nearly every trip link in India
/// is sent on WhatsApp, so it goes first and needs no hunting.
List<ShareTarget> shareTargets({
  required String link,
  required String message,
}) {
  if (link.isEmpty) return const [];

  final full = Uri.encodeComponent(shareText(link: link, message: message));
  final onlyLink = Uri.encodeComponent(link);
  final onlyMessage = Uri.encodeComponent(message);
  final subject = Uri.encodeComponent('Join my trip on Triplix');

  return [
    ShareTarget(
      id: 'whatsapp',
      label: 'WhatsApp',
      // No number in the path, so WhatsApp asks which chat rather than this
      // app having to know anybody's number.
      url: Uri.parse('https://wa.me/?text=$full'),
    ),
    ShareTarget(
      id: 'telegram',
      label: 'Telegram',
      url: Uri.parse('https://t.me/share/url?url=$onlyLink&text=$onlyMessage'),
    ),
    ShareTarget(
      id: 'email',
      label: 'Email',
      url: Uri.parse('mailto:?subject=$subject&body=$full'),
    ),
    ShareTarget(
      id: 'sms',
      label: 'Message',
      url: Uri.parse('sms:?body=$full'),
    ),
  ];
}

/// Opens one of the [shareTargets].
///
/// Returns false when nothing opened -- no mail app, a blocked popup -- and
/// the screen then falls back on saying the link is already copied, which by
/// this point it is.
Future<bool> openTarget(ShareTarget target) async {
  try {
    return await launchUrl(target.url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// The device's own share sheet: every app on the phone, not just the four
/// named above.
///
/// Must be called straight from a tap. Browsers only allow Web Share inside
/// the gesture that triggered it.
Future<bool> shareToApps({required String link, required String message}) async {
  if (link.isEmpty) return false;
  try {
    final result =
        await Share.shareWithResult(shareText(link: link, message: message));
    return result.status != ShareResultStatus.unavailable;
  } catch (_) {
    // No share sheet on this platform.
    return false;
  }
}
