import 'package:flutter/material.dart';
import '../../features/map/domain/map_style.dart';

/// Widget de sélection du style de carte
class MapStyleSelector extends StatelessWidget {
  final MapStyle currentStyle;
  final ValueChanged<MapStyle> onStyleChanged;
  final bool closeOnSelect;
  final bool hasSatelliteAccess;

  const MapStyleSelector({
    super.key,
    required this.currentStyle,
    required this.onStyleChanged,
    this.closeOnSelect = true,
    this.hasSatelliteAccess = true,
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
              final isSatellite = style == MapStyle.esriWorldImagery;
              final isDisabled = isSatellite && !hasSatelliteAccess;
              
              return ListTile(
                dense: true,
                leading: Text(
                  style.icon,
                  style: TextStyle(
                    fontSize: 24,
                    color: isDisabled ? Colors.grey.shade400 : null,
                  ),
                ),
                title: Text(
                  style.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isDisabled
                        ? Colors.grey.shade500
                        : isSelected
                            ? Colors.blue.shade700
                            : Colors.black87,
                  ),
                ),
                subtitle: isDisabled
                    ? const Text(
                        'AllSPOTS+ requis',
                        style: TextStyle(fontSize: 11),
                      )
                    : null,
                trailing: isDisabled
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF6D8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE3B317)),
                        ),
                        child: const Text(
                          'AllSPOTS+',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF856A00),
                          ),
                        ),
                      )
                    : isSelected
                        ? Icon(Icons.check_circle,
                            color: Colors.blue.shade700, size: 20)
                        : null,
                selected: isSelected,
                selectedTileColor: Colors.blue.shade50,
                onTap: () {
                  if (isDisabled) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Le mode satellite est reserve aux comptes premium.',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }

                  onStyleChanged(style);
                  if (closeOnSelect) {
                    Navigator.of(context).maybePop();
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
