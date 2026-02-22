class AppConfig {
  const AppConfig._();

  // Simple runtime switch to disable Google Places without deleting code.
  static const bool enableGooglePlaces = false;

  // Enable OSM API backend (Render) as a free alternative.
  static const bool enableOsmApi = true;

  // replace with your Render URL once deployed.
  static const String osmApiBaseUrl = 'https://allspots.onrender.com/';
}
