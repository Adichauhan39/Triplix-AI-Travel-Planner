import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/trip_plan.dart';
import '../providers/trip_plan_provider.dart';
import '../services/python_adk_service.dart';

/// A "change my plan" box that can sit on any screen.
///
/// The plan lives in a provider shared across the app, so an instruction typed
/// while browsing hotels can update the itinerary just as well as one typed on
/// the trip screen. Previously the only way in was the box at the bottom of
/// the trip screen, which meant noticing something while searching flights and
/// having to navigate away to act on it.
///
/// Drop [PlanQuickEditButton] into a Scaffold's floatingActionButton and the
/// whole flow comes with it.
class PlanQuickEditButton extends StatelessWidget {
  const PlanQuickEditButton({super.key});

  @override
  Widget build(BuildContext context) {
    // Hidden until there is a plan to change. A button that can only ever
    // report "no trip yet" is noise on every screen it appears on.
    final hasPlan = context.watch<TripPlanProvider>().hasPlan;
    if (!hasPlan) return const SizedBox.shrink();

    return FloatingActionButton.extended(
      onPressed: () => PlanQuickEditSheet.show(context),
      backgroundColor: AppConfig.primaryColor,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.edit_calendar, size: 20),
      label: const Text('Change plan'),
    );
  }
}

class PlanQuickEditSheet extends StatefulWidget {
  const PlanQuickEditSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PlanQuickEditSheet(),
    );
  }

  @override
  State<PlanQuickEditSheet> createState() => _PlanQuickEditSheetState();
}

class _PlanQuickEditSheetState extends State<PlanQuickEditSheet> {
  final TextEditingController _controller = TextEditingController();
  final PythonADKService _adk = PythonADKService();

  bool _applying = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final request = _controller.text.trim();
    final provider = context.read<TripPlanProvider>();
    final plan = provider.plan;
    if (request.isEmpty || plan == null || _applying) return;

    setState(() {
      _applying = true;
      _error = null;
      _done = null;
    });

    final updated = await _adk.adjustPlan(
      days: plan.toJson(),
      request: request,
      destination: plan.destination,
    );
    if (!mounted) return;

    if (updated == null) {
      // The plan is left exactly as it was: losing someone's itinerary
      // because one instruction failed would be far worse than not applying
      // it.
      setState(() {
        _applying = false;
        _error = "Couldn't apply that — check the server is running.";
      });
      return;
    }

    provider.replaceDays(updated.map(PlanDay.fromJson).toList());
    if (!mounted) return;
    setState(() {
      _applying = false;
      _controller.clear();
      _done = 'Plan updated.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<TripPlanProvider>().plan;
    final destination = plan?.destination.split(',').first ?? '';

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            destination.isEmpty
                ? 'Change your plan'
                : 'Change your $destination plan',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Say what to change and it updates your day-by-day plan.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              hintText: 'e.g. make it 2 days, or add a park on Day 2',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConfig.radiusMedium),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Concrete starters rather than an empty box: the useful requests
          // are not obvious, and a blank field invites the vague ones this
          // cannot honour.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final example in const [
                'Make it 2 days',
                'Add a park on Day 2',
                'Move everything a day later',
                'Fewer places each day',
              ])
                ActionChip(
                  label: Text(example, style: const TextStyle(fontSize: 12)),
                  onPressed: _applying
                      ? null
                      : () {
                          _controller.text = example;
                          _apply();
                        },
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.orange[800]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_error!,
                      style:
                          TextStyle(fontSize: 12, color: Colors.orange[800])),
                ),
              ],
            ),
          ],
          if (_done != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: Colors.green),
                const SizedBox(width: 6),
                Text(_done!,
                    style: const TextStyle(fontSize: 12, color: Colors.green)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _applying ? null : _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: _applying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Update my plan'),
            ),
          ),
        ],
      ),
    );
  }
}
