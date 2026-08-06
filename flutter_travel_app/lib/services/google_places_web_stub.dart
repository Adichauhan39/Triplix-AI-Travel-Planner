/// Non-web stub for Google Places autocomplete.
/// The real implementation is in `google_places_web.dart` and is selected
/// via conditional imports for the web build.
Future<List<Map<String, String>>> autocompleteCitiesWeb(String query) async {
  return const <Map<String, String>>[];
}
