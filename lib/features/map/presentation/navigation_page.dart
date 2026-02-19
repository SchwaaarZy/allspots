import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../../core/widgets/glass_app_bar.dart';
import 'package:url_launcher/url_launcher.dart';

class NavigationPage extends StatefulWidget {
  final LatLng start;
  final LatLng destination;
  final String destinationName;

  const NavigationPage({
    super.key,
    required this.start,
    required this.destination,
    required this.destinationName,
  });

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  GoogleMapController? _controller;
  bool _loading = true;
  String? _error;
  List<LatLng> _routePoints = [];
  double? _distanceMeters;
  double? _durationSeconds;

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final start = widget.start;
    final dest = widget.destination;
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${dest.longitude},${dest.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final res = await http.get(url);
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) {
        throw Exception('Aucun itineraire');
      }

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List<dynamic>;

      final points = coords
          .map((c) => LatLng(c[1] as double, c[0] as double))
          .toList();

      setState(() {
        _routePoints = points;
        _distanceMeters = (route['distance'] as num?)?.toDouble();
        _durationSeconds = (route['duration'] as num?)?.toDouble();
        _loading = false;
      });

      _fitBounds(points);
    } catch (e) {
      setState(() {
        _error = 'Impossible de charger l\'itineraire';
        _loading = false;
      });
    }
  }

  void _fitBounds(List<LatLng> points) {
    if (_controller == null || points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  String _formatDuration(double? seconds) {
    if (seconds == null) return '-';
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins min';
    final hours = mins ~/ 60;
    final rem = mins % 60;
    return '${hours}h ${rem}m';
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '-';
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  Future<void> _launchNavigation() async {
    final destLat = widget.destination.latitude;
    final destLng = widget.destination.longitude;
    
    // Construire l'URL Waze
    final wazeUrl = Uri.parse(
      'https://waze.com/ul?ll=$destLat,$destLng&navigate=yes',
    );

    if (await canLaunchUrl(wazeUrl)) {
      await launchUrl(wazeUrl, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir Waze. Vérifiez qu\'il est installé.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('start'),
        position: widget.start,
        infoWindow: const InfoWindow(title: 'Votre position'),
      ),
      Marker(
        markerId: const MarkerId('dest'),
        position: widget.destination,
        infoWindow: InfoWindow(title: widget.destinationName),
      ),
    };

    final polylines = <Polyline>{
      if (_routePoints.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('route'),
          points: _routePoints,
          color: Theme.of(context).colorScheme.primary,
          width: 6,
        ),
    };

    return Scaffold(
      appBar: GlassAppBar(
        title: widget.destinationName,
        showBackButton: true,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.start,
              zoom: 14,
            ),
            markers: markers,
            polylines: polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (c) => _controller = c,
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 4),
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatDuration(_durationSeconds),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDistance(_distanceMeters),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _fetchRoute,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Recalculer'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _launchNavigation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.navigation, color: Colors.white),
                          label: const Text(
                            'Lancer la navigation',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
