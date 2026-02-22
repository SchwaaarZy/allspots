import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'navigation_app_picker.dart';

/// Page de navigation simplifiée (OSM Migration)
/// Affiche les coordonnées et distance, sans dépendance Google Maps
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
  double? _distanceKm;

  @override
  void initState() {
    super.initState();
    _distanceKm = _calculateDistance(widget.start, widget.destination);
  }

  double _calculateDistance(LatLng start, LatLng end) {
    const earthRadius = 6371; // km
    final dLat = _toRadian(end.latitude - start.latitude);
    final dLon = _toRadian(end.longitude - start.longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadian(start.latitude)) *
            math.cos(_toRadian(end.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadian(double degree) => degree * 3.14159265359 / 180;

  Future<void> _launchNavigation() async {
    if (!mounted) return;
    await showNavigationAppPicker(
      context: context,
      destination: widget.destination,
      destinationName: widget.destinationName,
      onAllSpotsNavigation: () async {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Navigation AllSpots: activez votre GPS'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.destinationName),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                'Navigation vers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                widget.destinationName,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_distanceKm != null) ...[
                        Text(
                          'Distance',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_distanceKm!.toStringAsFixed(1)} km',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: Colors.green),
                        ),
                        const Divider(height: 24),
                      ],
                      Text(
                        'Point de départ',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.start.latitude.toStringAsFixed(4)}\n${widget.start.longitude.toStringAsFixed(4)}',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const Divider(height: 24),
                      Text(
                        'Destination',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.destination.latitude.toStringAsFixed(4)}\n${widget.destination.longitude.toStringAsFixed(4)}',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.green,
                  ),
                  onPressed: _launchNavigation,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Commencer la navigation'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
