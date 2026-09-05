/// Hand-written, called from the graph through a `Dart Code` node (§7.8).
///
/// A coordinate lookup is exactly the kind of thing a node library should not
/// try to express: it is a table, and Dart already has tables.
const Map<String, (double latitude, double longitude)> _cities = {
  'berlin': (52.52, 13.41),
  'london': (51.51, -0.13),
  'paris': (48.86, 2.35),
  'madrid': (40.42, -3.70),
  'new york': (40.71, -74.01),
  'tokyo': (35.68, 139.69),
  'shanghai': (31.23, 121.47),
  'sydney': (-33.87, 151.21),
};

/// Builds an Open-Meteo request for [city]. No API key, no account.
///
/// Throws for an unknown city; the generated handler catches it and shows the
/// message, which is why the error text is written for a reader.
String forecastUrl(String city) {
  final match = _cities[city.trim().toLowerCase()];
  if (match == null) {
    throw ArgumentError(
      'Unknown city "$city". Known: ${_cities.keys.join(', ')}.',
    );
  }
  final (latitude, longitude) = match;
  return 'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude&longitude=$longitude&current_weather=true';
}
