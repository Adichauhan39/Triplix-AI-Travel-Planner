/// Closing a debt: pay it, or record that it is paid.
///
/// The settlement said "Surendra owes you 433.35" and would have said it for
/// ever. Every competing app closes this loop and this one had no way to --
/// which makes the whole ledger read as an accusation nobody can answer.
///
/// The payment itself happens in whatever UPI app is on the phone. Nothing
/// here moves money: it fills in a payment form, hands it over, and then asks
/// whether it went through. Recording is deliberately a separate step from
/// opening the app, because opening an app is not paying -- somebody can get
/// to the PIN screen and change their mind, and a ledger that marked that as
/// settled would be lying to the person owed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/brand.dart';
import '../services/expense_columns.dart';
import '../services/settle_up.dart';

/// What the sheet decided.
class SettleResult {
  const SettleResult({required this.paise, required this.method});

  /// How much to record. Editable, so part payments work: somebody who owes
  /// ₹433 and hands over ₹400 has not settled, and pretending otherwise puts
  /// the error in the other person's column.
  final int paise;

  /// 'upi' or 'cash'.
  final String method;
}

/// Offers to settle one debt, returning what was actually paid.
///
/// Returns null when nothing was recorded, which includes opening the UPI app
/// and coming back without confirming.
Future<SettleResult?> showSettleUpSheet(
  BuildContext context, {
  required Debt debt,
  required String fromName,
  required String toName,
  required String toUpiId,
  required bool iAmPayer,
  required String tripLabel,
}) {
  return showModalBottomSheet<SettleResult>(
    context: context,
    backgroundColor: Brand.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _SettleSheet(
        debt: debt,
        fromName: fromName,
        toName: toName,
        toUpiId: toUpiId,
        iAmPayer: iAmPayer,
        tripLabel: tripLabel,
      ),
    ),
  );
}

class _SettleSheet extends StatefulWidget {
  const _SettleSheet({
    required this.debt,
    required this.fromName,
    required this.toName,
    required this.toUpiId,
    required this.iAmPayer,
    required this.tripLabel,
  });

  final Debt debt;
  final String fromName;
  final String toName;
  final String toUpiId;
  final bool iAmPayer;
  final String tripLabel;

  @override
  State<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<_SettleSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: (widget.debt.paise / 100).toStringAsFixed(2),
  );

  /// Set once the UPI app has been opened, so the confirm button can say
  /// "I have paid" rather than "mark as paid" -- and so somebody who came
  /// back without paying is not nudged into confirming.
  bool _opened = false;
  String? _problem;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// What the box says, in paise, or null when it is not a payment.
  int? get _typedPaise {
    final value = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (value == null || value <= 0) return null;
    final paise = rupeesToPaise(value);
    // More than the debt is not a settlement, it is a new debt the other way
    // round, and this sheet has no way to explain that.
    if (paise > widget.debt.paise) return null;
    return paise;
  }

  Future<void> _payByUpi() async {
    final paise = _typedPaise;
    if (paise == null) {
      setState(() => _problem = 'Enter an amount up to '
          '${formatRupees(widget.debt.paise)}.');
      return;
    }

    final link = upiPaymentLink(
      upiId: widget.toUpiId,
      payeeName: widget.toName,
      paise: paise,
      note: widget.tripLabel,
    );
    if (link == null) {
      setState(() => _problem =
          '${widget.toName} has not added a UPI id, so there is nothing to '
          'open. You can still record a payment below.');
      return;
    }

    try {
      final opened = await launchUrl(link, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      setState(() {
        _opened = opened;
        _problem = opened
            ? null
            : 'No UPI app answered. On a laptop there usually is not one -- '
                'pay from your phone, then record it here.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _problem =
          'That could not be opened. Pay however you normally would, then '
          'record it here.');
    }
  }

  void _record(String method) {
    final paise = _typedPaise;
    if (paise == null) {
      setState(() => _problem =
          'Enter an amount up to ${formatRupees(widget.debt.paise)}.');
      return;
    }
    Navigator.pop(context, SettleResult(paise: paise, method: method));
  }

  @override
  Widget build(BuildContext context) {
    final link = upiPaymentLink(
      upiId: widget.toUpiId,
      payeeName: widget.toName,
      paise: widget.debt.paise,
    );
    final canUpi = widget.iAmPayer && link != null;

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

            Text(
              widget.iAmPayer
                  ? 'Pay ${widget.toName}'
                  : '${widget.fromName} pays ${widget.toName}',
              style: Brand.heading,
            ),
            const SizedBox(height: Brand.tight),
            Text(
              'Owed: ${formatRupees(widget.debt.paise)}',
              style: Brand.caption,
            ),
            const SizedBox(height: Brand.pad),

            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) {
                if (_problem != null) setState(() => _problem = null);
              },
              decoration: InputDecoration(
                labelText: 'Amount paid',
                prefixText: '₹ ',
                // Said out loud, because part payments are the reason this
                // box is editable at all.
                helperText: 'Less than the full amount is fine -- the rest '
                    'stays owed.',
                helperMaxLines: 2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.radiusSmall),
                ),
              ),
            ),

            if (_problem != null) ...[
              const SizedBox(height: Brand.tight),
              Text(_problem!,
                  style: const TextStyle(fontSize: 12, color: Brand.danger)),
            ],

            const SizedBox(height: Brand.pad),

            if (canUpi) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _payByUpi,
                  icon: const Icon(Icons.account_balance_wallet_outlined,
                      size: 18),
                  label: Text('Pay by UPI to ${widget.toUpiId}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Brand.teal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.radius),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Brand.tight),
              // The honest bit. Opening the app is not paying, and only the
              // person who did it knows whether it went through.
              Text(
                _opened
                    ? 'Once it has gone through, confirm it below so '
                        '${widget.toName} sees it.'
                    : 'This opens your UPI app with the amount filled in. '
                        'Nothing is recorded until you confirm it.',
                style: Brand.caption,
              ),
              const SizedBox(height: Brand.gap),
            ] else if (widget.iAmPayer) ...[
              Container(
                padding: const EdgeInsets.all(Brand.gap),
                decoration: Brand.card(color: Brand.fill),
                child: Text(
                  '${widget.toName} has not added a UPI id. Ask them to add '
                  'one from the badge next to "Shared spending" and this will '
                  'pay them in one tap.',
                  style: Brand.caption,
                ),
              ),
              const SizedBox(height: Brand.gap),
            ],

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _record(_opened ? 'upi' : 'cash'),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(_opened
                    ? 'I have paid — record it'
                    : widget.iAmPayer
                        ? 'Record that I paid in cash'
                        : 'Record this as paid'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Brand.text,
                  side: const BorderSide(color: Brand.hairline),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.radius),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
