/// The one share sheet, used by every share button in the app.
///
/// Before this there were three of them: the trip copied and showed a dialog,
/// the ledger opened the device sheet, and the invite bar said "Copy link"
/// while sometimes copying nothing. Same job, three behaviours, and only one
/// of them reliably put the link where the person could paste it.
library;

import 'package:flutter/material.dart';

import '../config/brand.dart';
import '../services/share_link.dart' as sharing;

/// Copies [link], then offers the ways to send it.
///
/// The copy happens before the sheet is even built, so the link is on the
/// clipboard whatever the person does next -- picks an app, or closes this and
/// pastes it themselves.
///
/// [note] is the one line about what happens when somebody opens the link.
/// It differs by what is being shared, and it is the part people need to read
/// before sending it to anyone.
Future<void> showShareSheet(
  BuildContext context, {
  required String link,
  required String message,
  required String note,
}) async {
  if (link.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('There is nothing to share yet.'),
    ));
    return;
  }

  final copied = await sharing.copyLink(link);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Brand.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _ShareSheet(
      link: link,
      message: message,
      note: note,
      copied: copied,
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.link,
    required this.message,
    required this.note,
    required this.copied,
  });

  final String link;
  final String message;
  final String note;

  /// Whether the copy on open worked. False means the browser refused it, and
  /// the sheet says so rather than claiming a copy that did not happen.
  final bool copied;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late bool _copied = widget.copied;

  /// Icon and colour per target. Kept here so the service stays free of
  /// anything visual and can be tested without Flutter.
  static const Map<String, (IconData, Color)> _looks = {
    'whatsapp': (Icons.chat_bubble, Color(0xFF25D366)),
    'telegram': (Icons.send, Color(0xFF229ED9)),
    'email': (Icons.mail_outline, Brand.teal),
    'sms': (Icons.sms_outlined, Brand.sun),
  };

  Future<void> _copy() async {
    final ok = await sharing.copyLink(widget.link);
    if (!mounted) return;
    setState(() => _copied = ok);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Link copied. Paste it anywhere.'
          : 'Your browser would not let us copy. Select the link above and '
              'copy it by hand.'),
    ));
  }

  Future<void> _open(sharing.ShareTarget target) async {
    final ok = await sharing.openTarget(target);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${target.label} would not open. The link is already '
            'copied, so you can paste it there yourself.'),
      ));
    }
  }

  Future<void> _more() async {
    final shared = await sharing.shareToApps(
      link: widget.link,
      message: widget.message,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!shared) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This device has no share menu. The link is copied -- '
            'paste it wherever you like.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets =
        sharing.shareTargets(link: widget.link, message: widget.message);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Brand.pad, Brand.gap, Brand.pad, Brand.pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Brand.hairline,
                  borderRadius: BorderRadius.circular(Brand.radiusPill),
                ),
              ),
            ),
            const SizedBox(height: Brand.pad),
            const Text('Share', style: Brand.heading),
            const SizedBox(height: Brand.tight),
            Text(widget.note, style: Brand.caption),
            const SizedBox(height: Brand.pad),

            // The link itself, selectable. When a browser refuses the
            // clipboard there has to be something to select by hand.
            Container(
              padding: const EdgeInsets.all(Brand.gap),
              decoration: Brand.card(color: Brand.fill),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      widget.link,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Brand.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: Brand.tight),
                  TextButton.icon(
                    onPressed: _copy,
                    icon: Icon(_copied ? Icons.check : Icons.copy_rounded,
                        size: 16),
                    label: Text(_copied ? 'Copied' : 'Copy',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    style: TextButton.styleFrom(
                      foregroundColor: _copied ? Brand.good : Brand.teal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Brand.pad),

            const Text('Send it with', style: Brand.caption),
            const SizedBox(height: Brand.gap),
            Row(
              children: [
                for (final target in targets)
                  Expanded(
                    child: _TargetButton(
                      label: target.label,
                      icon: _looks[target.id]?.$1 ?? Icons.link,
                      color: _looks[target.id]?.$2 ?? Brand.teal,
                      onTap: () => _open(target),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Brand.gap),

            // Everything else on the device. On a phone this is the whole app
            // drawer; on a laptop it may not exist, which is why it is the
            // last option rather than the first thing that happens.
            OutlinedButton.icon(
              onPressed: _more,
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('More apps'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.text,
                side: const BorderSide(color: Brand.hairline),
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Brand.radius),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetButton extends StatelessWidget {
  const _TargetButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Brand.tight),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Brand.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
