import 'package:flutter/material.dart';
import '../../features/map/domain/map_style.dart';

/// Widget de sélection du style de carte
class MapStyleSelector extends StatelessWidget {
  final MapStyle currentStyle;
  final ValueChanged<MapStyle> onStyleChanged;

  const MapStyleSelector({
    super.key,
    required this.currentStyle,
    required this.onStyleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // En-tête
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), 
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.layers, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Style de carte',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
          ),
          
          // Liste des styles
          ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: MapStyle.values.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final style = MapStyle.values[index];
              final isSelected = style == currentStyle;
              
              return ListTile(
                dense: true,
                leading: Text(
                  style.icon,
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(
                  style.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? Colors.blue.shade700 : Colors.black87,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: Colors.blue.shade700, size: 20)
                    : null,
                selected: isSelected,
                selectedTileColor: Colors.blue.shade50,
                onTap: () {
                  onStyleChanged(style);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
