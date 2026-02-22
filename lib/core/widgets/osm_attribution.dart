import 'package:flutter/material.dart';

/// Widget d'attribution OSM (obligatoire par licence ODbL).
/// À placer en bas de la carte ou écran.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300, width: 0.5),
        ),
        child: GestureDetector(
          onTap: () => _openOsmWebsite(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '© ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'OpenStreetMap',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
              Text(
                ' contributors',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openOsmWebsite(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Visit https://www.openstreetmap.org/copyright'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}
