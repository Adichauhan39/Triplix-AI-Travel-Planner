/// Attaching a bill to an expense, and looking at one.
///
/// "I paid 1,800 for dinner" is a claim; the bill is not. This is also how a
/// ledger nobody filled in at the time gets filled in afterwards -- the photos
/// are still on somebody's phone, and each one is a row.
library;

import 'package:flutter/material.dart';

import '../config/brand.dart';
import '../services/receipt_store.dart';

/// Offers the ways to attach a bill, and returns what was chosen.
enum ReceiptAction { camera, gallery, view, remove }

Future<ReceiptAction?> askAboutReceipt(
  BuildContext context, {
  required bool has,
  required bool canRemove,
}) {
  return showModalBottomSheet<ReceiptAction>(
    context: context,
    backgroundColor: Brand.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Brand.gap),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Brand.hairline,
              borderRadius: BorderRadius.circular(Brand.radiusPill),
            ),
          ),
          const SizedBox(height: Brand.gap),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Brand.pad),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(has ? 'The bill' : 'Attach the bill',
                  style: Brand.heading),
            ),
          ),
          const SizedBox(height: Brand.tight),
          if (has)
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Brand.teal),
              title: const Text('See the bill'),
              onTap: () => Navigator.pop(sheetContext, ReceiptAction.view),
            ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(has ? 'Take a new photo' : 'Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ReceiptAction.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            // Named as the thing that actually happens on a laptop, where
            // there is no camera roll to open.
            title: Text(has ? 'Choose a different photo' : 'Choose a photo'),
            subtitle: const Text('Also how it works on a computer',
                style: TextStyle(fontSize: 11)),
            onTap: () => Navigator.pop(sheetContext, ReceiptAction.gallery),
          ),
          if (has && canRemove)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Brand.danger),
              title: const Text('Remove the bill',
                  style: TextStyle(color: Brand.danger)),
              onTap: () => Navigator.pop(sheetContext, ReceiptAction.remove),
            ),
          const SizedBox(height: Brand.tight),
        ],
      ),
    ),
  );
}

/// Shows a bill, zoomable.
///
/// A receipt is read, not glanced at: the total is often the smallest print on
/// it, so pinch and pan are the whole point of this screen.
Future<void> showReceipt(
  BuildContext context, {
  required ReceiptStore store,
  required String tripId,
  required String expenseId,
  required String title,
}) async {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Brand.surface,
      insetPadding: const EdgeInsets.all(Brand.gap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Brand.pad, Brand.gap, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Brand.heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
          ),
          Flexible(
            child: FutureBuilder(
              future: store.image(tripId: tripId, expenseId: expenseId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  );
                }
                final bytes = snapshot.data;
                if (bytes == null) {
                  return const Padding(
                    padding: EdgeInsets.all(Brand.pad),
                    child: Text(
                      'That bill could not be loaded. It may have been '
                      'removed.',
                      style: Brand.caption,
                    ),
                  );
                }
                return InteractiveViewer(
                  maxScale: 5,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                );
              },
            ),
          ),
          const SizedBox(height: Brand.gap),
        ],
      ),
    ),
  );
}
