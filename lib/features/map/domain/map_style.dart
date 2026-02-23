/// Styles de carte disponibles avec leurs configurations
enum MapStyle {
  openStreetMapFrance(
    name: 'OSM France',
    urlTemplate: 'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    maxZoom: 20,
  ),
  esriWorldImagery(
    name: 'Satellite',
    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    subdomains: [],
    maxZoom: 19,
  );

  const MapStyle({
    required this.name,
    required this.urlTemplate,
    required this.subdomains,
    required this.maxZoom,
  });

  final String name;
  final String urlTemplate;
  final List<String> subdomains;
  final int maxZoom;

  /// Icône représentative pour l'UI
  String get icon {
    switch (this) {
      case MapStyle.openStreetMapFrance:
        return '🇫🇷';
      case MapStyle.esriWorldImagery:
        return '🛰️';
    }
  }
}
