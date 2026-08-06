import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Triplix booking redirect (affiliate) service.
///
/// Triplix does NOT take payment or issue tickets. When a user chooses to book,
/// we send them to a travel partner's site with our affiliate tracking attached
/// and earn a commission on completed bookings. This file is the single place
/// that owns that behaviour.
///
/// HOW TO GO LIVE (once your affiliate applications are approved):
///   1. Paste your IDs into [AffiliateConfig] below.
///   2. That's it — every "Book" button in the app starts earning.
///
/// Until then, links still open normally (users can still book), you just
/// don't earn commission yet — so nothing is blocked while approvals pend.
/// ─────────────────────────────────────────────────────────────────────────

/// Central affiliate configuration — the ONE place to edit when your
/// affiliate accounts are approved.
class AffiliateConfig {
  AffiliateConfig._();

  /// TravelPayouts publisher "marker" id — the single account behind both
  /// flights and hotels on Aviasales. Apply at https://www.travelpayouts.com/
  ///
  /// Currently UNUSED: hotel links go through a TravelPayouts short link that
  /// already carries attribution. Only needed if you swap the short link for a
  /// full aviasales.com URL with query params. Keep in sync with
  /// TRAVELPAYOUTS_MARKER_ID in .env, which services/affiliate_links.dart reads.
  static const String travelpayoutsMarker = '';

  /// A tracking sub-id / label sent where a partner supports it, so your
  /// affiliate dashboard shows that a click came from the Triplix app.
  static const String subId = 'triplix_app';

  /// OPTIONAL affiliate-network wrapper (Cuelinks / EarnKaro / INRDeals).
  /// Indian programs (EaseMyTrip, MakeMyTrip, ixigo) are usually tracked by
  /// wrapping the merchant URL through a network. If you use one, paste its
  /// template here using {url} as the placeholder for the encoded destination,
  /// e.g. 'https://linksredirect.com/?pub_id=XXXXX&source=triplix&url={url}'.
  /// If set, EVERY outgoing link is auto-tracked with no per-merchant setup.
  static const String networkWrapperTemplate = '';
}

/// The kind of thing being booked. Drives which partner URL we build.
enum BookingCategory { flight, train, bus, hotel, activity, unknown }

class BookingRedirect {
  BookingRedirect._();

  /// Infer the booking category from a swipe/booking item map. Robust to the
  /// two shapes used across the app: swipe cards (`name`/`city`/`type`) and
  /// booking cards (`title`/`location`).
  static BookingCategory categoryOf(Map<String, dynamic> item) {
    final type = (item['type'] ?? '').toString().toLowerCase();
    final name =
        (item['name'] ?? item['title'] ?? '').toString().toLowerCase();
    final hay = '$type $name';

    if (type.contains('hotel') || type.contains('accommodation')) {
      return BookingCategory.hotel;
    }
    if (type.contains('attraction') || type.contains('activity')) {
      return BookingCategory.activity;
    }

    // Travel cards only say type == "travel"; disambiguate mode from the name.
    if (_hasAny(hay, const [
      'flight', 'air', 'airway', 'indigo', 'vistara', 'spicejet', 'akasa'
    ])) {
      return BookingCategory.flight;
    }
    if (_hasAny(hay, const [
      'train', 'rail', 'express', 'rajdhani', 'shatabdi', 'duronto', 'vande'
    ])) {
      return BookingCategory.train;
    }
    if (_hasAny(hay, const ['bus', 'volvo', 'sleeper coach'])) {
      return BookingCategory.bus;
    }

    // Fallbacks by broad type.
    if (type.contains('travel') || type.contains('transport')) {
      return BookingCategory.flight; // generic travel → flight search
    }
    if (type.contains('destination')) {
      return BookingCategory.hotel; // a place → find stays there
    }
    return BookingCategory.unknown;
  }

  /// Human label for the partner an item will open on — use it for button text
  /// like "Book on Aviasales →".
  static String partnerLabelFor(Map<String, dynamic> item) {
    switch (categoryOf(item)) {
      case BookingCategory.hotel:
        return 'Aviasales';
      case BookingCategory.flight:
      case BookingCategory.train:
      case BookingCategory.bus:
        return 'EaseMyTrip';
      case BookingCategory.activity:
      case BookingCategory.unknown:
        return 'partner site';
    }
  }

  /// Build the outgoing (affiliate-wrapped) booking URL for an item.
  static Uri buildUrl(Map<String, dynamic> item) {
    final category = categoryOf(item);
    final name = (item['name'] ?? item['title'] ?? '').toString().trim();
    final city = (item['city'] ?? item['location'] ?? '').toString().trim();

    late Uri raw;
    switch (category) {
      case BookingCategory.hotel:
        raw = _aviasalesHotelUrl(name: name, city: city);
        break;
      case BookingCategory.flight:
        raw = _easeMyTripUrl(section: 'flights', query: '$name $city'.trim());
        break;
      case BookingCategory.train:
        raw = _easeMyTripUrl(section: 'railways', query: '$name $city'.trim());
        break;
      case BookingCategory.bus:
        raw = _easeMyTripUrl(section: 'bus', query: '$name $city'.trim());
        break;
      case BookingCategory.activity:
      case BookingCategory.unknown:
        raw = _googleSearchUrl('$name $city book tickets'.trim());
        break;
    }
    return _wrapAffiliate(raw);
  }

  /// Open the booking page in the external browser (new tab on web).
  /// Returns true if it launched. Pass [context] to surface a friendly error.
  static Future<bool> launch(
    Map<String, dynamic> item, {
    BuildContext? context,
  }) async {
    final url = buildUrl(item);
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok && context != null && context.mounted) {
        _snack(context, "Couldn't open the booking page. Please try again.");
      }
      return ok;
    } catch (_) {
      if (context != null && context.mounted) {
        _snack(context, "Couldn't open the booking page. Please try again.");
      }
      return false;
    }
  }

  // ── Partner URL builders ───────────────────────────────────────────────
  // NOTE: search-page URLs are intentionally simple and stable. Verify the
  // exact affiliate param names against your approved dashboard and tweak here
  // if a partner requires a specific format — this is the only place to change.

  /// Aviasales hotels, via the TravelPayouts short link from the dashboard —
  /// attribution is already baked into the link, so nothing is appended.
  /// Aviasales forwards on to Booking.com itself with its own aid; that hop
  /// is Aviasales' business, not ours.
  ///
  /// The short link is a fixed destination, so [name]/[city] can't be carried
  /// through — the user searches again on Aviasales. Kept in the signature so
  /// this can go back to a query-bearing URL without touching callers.
  static Uri _aviasalesHotelUrl({required String name, required String city}) {
    return Uri.parse('https://aviasales.tpo.li/ntQoEoPm');
  }

  /// EaseMyTrip covers flights / hotels / railways / bus under one affiliate
  /// account — the all-in-one partner for the India-first flow.
  static Uri _easeMyTripUrl({required String section, required String query}) {
    return Uri.https('www.easemytrip.com', '/$section/', {
      if (query.isNotEmpty) 'q': query,
      'utm_source': AffiliateConfig.subId,
    });
  }

  static Uri _googleSearchUrl(String query) =>
      Uri.https('www.google.com', '/search', {'q': query});

  // ── Affiliate-network wrapper ──────────────────────────────────────────

  static Uri _wrapAffiliate(Uri raw) {
    const tmpl = AffiliateConfig.networkWrapperTemplate;
    if (tmpl.isEmpty) return raw;
    final encoded = Uri.encodeComponent(raw.toString());
    return Uri.parse(tmpl.replaceAll('{url}', encoded));
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static bool _hasAny(String haystack, List<String> needles) =>
      needles.any(haystack.contains);

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
