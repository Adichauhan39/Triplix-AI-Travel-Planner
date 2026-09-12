import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/plan_diff.dart';

/// The two conversations the trip agent needs to have before it changes a plan.
///
/// Shared by the owner's screen and a guest's, because both ask the same two
/// questions and the last time these screens each grew their own copy of
/// something, one person ended up with two different names on one page.

/// Puts the agent's question to whoever made the request.
///
/// The options are buttons: they are the agent's own reading of the plan --
/// "Day 1" and "Day 3" when a place sits on both -- and retyping them by hand
/// invites a third spelling of the same thing. A free answer stays available
/// for anything the options do not cover.
Future<String?> askAgentQuestion(
  BuildContext context,
  String question,
  List<String> options,
) {
  final typed = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('One thing first'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 14),
          for (final option in options.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext, option),
                  child: Text(option, textAlign: TextAlign.center),
                ),
              ),
            ),
          if (options.isEmpty)
            TextField(
              controller: typed,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Your answer'),
              onSubmitted: (value) =>
                  Navigator.pop(dialogContext, value.trim()),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        if (options.isEmpty)
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, typed.text.trim()),
            child: const Text('Send'),
          ),
      ],
    ),
  );
}

/// Shows what a request is about to do, before it does it.
///
/// The agent answers with the whole plan rewritten, which used to be applied
/// sight unseen -- so a model that quietly dropped a place the user had chosen
/// looked exactly like one that had done as it was told. Reviewing the
/// difference costs one tap and makes that impossible to miss.
Future<bool?> confirmPlanChanges(
  BuildContext context,
  List<PlanChange> changes,
) {
  IconData iconFor(PlanChange change) => switch (change.kind) {
        'add' => Icons.add_circle_outline,
        'remove' => Icons.remove_circle_outline,
        _ => Icons.swap_horiz,
      };

  String wordsFor(PlanChange change) => switch (change.kind) {
        'add' => 'Add ${change.title} to Day ${change.dayIndex + 1}',
        'remove' => 'Remove ${change.title} from Day ${change.dayIndex + 1}',
        _ => 'Move ${change.title} from Day ${(change.fromDayIndex ?? 0) + 1} '
            'to Day ${change.dayIndex + 1}',
      };

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(changes.length == 1
          ? 'One change'
          : '${changes.length} changes'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final change in changes.take(10))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(iconFor(change),
                        size: 16, color: AppConfig.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(wordsFor(change),
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            if (changes.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('…and ${changes.length - 10} more',
                    style:
                        TextStyle(fontSize: 12, color: AppConfig.textTertiary)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConfig.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Apply'),
        ),
      ],
    ),
  );
}
