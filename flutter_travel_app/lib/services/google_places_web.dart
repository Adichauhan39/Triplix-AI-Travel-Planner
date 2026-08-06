/// Web-only implementation that calls the already-loaded Google Maps JS
/// `google.maps.places.AutocompleteService` for city autocomplete.
///
/// Uses `dart:js_util` for lightweight interop (works with the Maps JS SDK
/// loaded via `<script>` tag in `web/index.html`).
library;
import 'dart:async';
// ignore: deprecated_member_use
import 'dart:js_util' as js_util;

Future<List<Map<String, String>>> autocompleteCitiesWeb(String query) async {
  try {
    final google = js_util.getProperty(js_util.globalThis, 'google');
    if (google == null) return const [];
    final maps = js_util.getProperty(google, 'maps');
    if (maps == null) return const [];
    final places = js_util.getProperty(maps, 'places');
    if (places == null) return const [];
    final serviceCtor = js_util.getProperty(places, 'AutocompleteService');
    if (serviceCtor == null) return const [];

    final service = js_util.callConstructor(serviceCtor, const []);
    final completer = Completer<List<Map<String, String>>>();

    final request = js_util.jsify({
      'input': query,
      'types': ['(cities)'],
    });

    js_util.callMethod(service, 'getPlacePredictions', [
      request,
      js_util.allowInterop((preds, status) {
        if (completer.isCompleted) return;
        if (preds == null) {
          completer.complete(const []);
          return;
        }
        final list = <Map<String, String>>[];
        final rawLength = js_util.getProperty(preds, 'length');
        final count = (rawLength is num) ? rawLength.toInt() : 0;
        for (var i = 0; i < count; i++) {
          final pred = js_util.getProperty(preds, '$i');
          if (pred == null) continue;
          String main = '';
          String secondary = '';
          final structured = js_util.getProperty(pred, 'structured_formatting');
          if (structured != null) {
            final m = js_util.getProperty(structured, 'main_text');
            final s = js_util.getProperty(structured, 'secondary_text');
            if (m != null) main = m.toString();
            if (s != null) secondary = s.toString();
          }
          final desc = js_util.getProperty(pred, 'description');
          list.add({
            'city': main,
            'country': secondary,
            'description': desc == null ? '' : desc.toString(),
          });
        }
        completer.complete(list);
      }),
    ]);

    return completer.future
        .timeout(const Duration(seconds: 5), onTimeout: () => const []);
  } catch (_) {
    return const [];
  }
}
