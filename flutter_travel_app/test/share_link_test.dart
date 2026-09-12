import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_travel_app/services/share_link.dart';

void main() {
  const link = 'https://triplix-ai.web.app/#/t/abc123';
  const message = 'Come and split the costs of this trip with me on Triplix.';

  group('shareText', () {
    test('puts the message above the link', () {
      expect(shareText(link: link, message: message), '$message\n\n$link');
    });
  });

  group('shareTargets', () {
    test('offers the apps people here actually use, WhatsApp first', () {
      final ids = shareTargets(link: link, message: message)
          .map((t) => t.id)
          .toList();
      expect(ids, ['whatsapp', 'telegram', 'email', 'sms']);
    });

    test('nothing to offer without a link', () {
      expect(shareTargets(link: '', message: message), isEmpty);
    });

    test('the whole link survives encoding', () {
      // A link mangled in the query string is a share that leads nowhere,
      // and the # in the route is exactly the character that breaks if it is
      // pasted in raw.
      for (final target in shareTargets(link: link, message: message)) {
        // The whole query, not one parameter: Telegram carries the link in
        // `url` and the words in `text`, the others carry both together.
        expect(Uri.decodeComponent(target.url.query), contains(link),
            reason: target.id);
      }
    });

    test('the # is escaped, not left to cut the link short', () {
      final whatsapp = shareTargets(link: link, message: message).first;
      expect(whatsapp.url.toString(), contains('%23'));
      expect(whatsapp.url.fragment, isEmpty);
    });

    test('WhatsApp names no number, so it asks which chat', () {
      final whatsapp = shareTargets(link: link, message: message).first;
      expect(whatsapp.url.host, 'wa.me');
      expect(whatsapp.url.path, '/');
    });

    test('email carries a subject as well as the link', () {
      final email =
          shareTargets(link: link, message: message).firstWhere((t) => t.id == 'email');
      expect(email.url.scheme, 'mailto');
      expect(email.url.query, contains('subject='));
      expect(Uri.decodeComponent(email.url.query), contains(link));
    });

    test('every target has a label to put under its icon', () {
      for (final target in shareTargets(link: link, message: message)) {
        expect(target.label, isNotEmpty);
      }
    });
  });
}
