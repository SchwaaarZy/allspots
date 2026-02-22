import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class NavigationAppOption {
  final String title;
  final IconData icon;
  final bool isAllSpots;
  final Future<bool> Function() launch;

  const NavigationAppOption({
    required this.title,
    required this.icon,
    required this.isAllSpots,
    required this.launch,
  });
}

Future<void> showNavigationAppPicker({
  required BuildContext context,
  required LatLng destination,
  required String destinationName,
  required Future<void> Function() onAllSpotsNavigation,
}) async {
  final options = await _buildOptions(
    destination: destination,
    onAllSpotsNavigation: onAllSpotsNavigation,
  );

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final externalCount = options.where((e) => !e.isAllSpots).length;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Choisir une navigation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                destinationName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
            for (final option in options)
              ListTile(
                leading: Icon(option.icon),
                title: Text(option.title),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final launched = await option.launch();
                  if (launched || !context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Impossible d\'ouvrir cette application de navigation.'),
                    ),
                  );
                },
              ),
            if (externalCount == 0)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  "Aucune application externe détectée. All'SPOTS Navigation reste disponible.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<List<NavigationAppOption>> _buildOptions({
  required LatLng destination,
  required Future<void> Function() onAllSpotsNavigation,
}) async {
  final options = <NavigationAppOption>[
    NavigationAppOption(
      title: "All'SPOTS Navigation",
      icon: Icons.navigation,
      isAllSpots: true,
      launch: () async {
        await onAllSpotsNavigation();
        return true;
      },
    ),
  ];

  if (await _isWazeAvailable(destination)) {
    options.add(
      NavigationAppOption(
        title: 'Waze',
        icon: Icons.alt_route,
        isAllSpots: false,
        launch: () => _launchWaze(destination),
      ),
    );
  }

  if (await _isGoogleMapsAvailable(destination)) {
    options.add(
      NavigationAppOption(
        title: 'Google Maps',
        icon: Icons.map,
        isAllSpots: false,
        launch: () => _launchGoogleMaps(destination),
      ),
    );
  }

  if (await _isAppleMapsAvailable(destination)) {
    options.add(
      NavigationAppOption(
        title: 'Apple Plans',
        icon: Icons.map_outlined,
        isAllSpots: false,
        launch: () => _launchAppleMaps(destination),
      ),
    );
  }

  return options;
}

Future<bool> _isWazeAvailable(LatLng destination) {
  final uri = Uri.parse('waze://?ll=${destination.latitude},${destination.longitude}&navigate=yes');
  return canLaunchUrl(uri);
}

Future<bool> _isGoogleMapsAvailable(LatLng destination) {
  if (Platform.isAndroid) {
    return canLaunchUrl(
      Uri.parse('google.navigation:q=${destination.latitude},${destination.longitude}&mode=d'),
    );
  }
  if (Platform.isIOS) {
    return canLaunchUrl(Uri.parse('comgooglemaps://'));
  }
  return Future.value(false);
}

Future<bool> _isAppleMapsAvailable(LatLng destination) {
  if (!Platform.isIOS) return Future.value(false);
  return canLaunchUrl(
    Uri.parse('maps://?daddr=${destination.latitude},${destination.longitude}&dirflg=d'),
  );
}

Future<bool> _launchWaze(LatLng destination) {
  return _launchFirstAvailable([
    Uri.parse('waze://?ll=${destination.latitude},${destination.longitude}&navigate=yes'),
    Uri.parse('https://waze.com/ul?ll=${destination.latitude},${destination.longitude}&navigate=yes'),
  ]);
}

Future<bool> _launchGoogleMaps(LatLng destination) {
  final destinationCoords = '${destination.latitude},${destination.longitude}';
  return _launchFirstAvailable([
    if (Platform.isAndroid)
      Uri.parse('google.navigation:q=$destinationCoords&mode=d'),
    if (Platform.isIOS)
      Uri.parse('comgooglemaps://?daddr=$destinationCoords&directionsmode=driving'),
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$destinationCoords&travelmode=driving'),
  ]);
}

Future<bool> _launchAppleMaps(LatLng destination) {
  return _launchFirstAvailable([
    Uri.parse('maps://?daddr=${destination.latitude},${destination.longitude}&dirflg=d'),
  ]);
}

Future<bool> _launchFirstAvailable(List<Uri> uris) async {
  for (final uri in uris) {
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
  return false;
}