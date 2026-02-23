import 'package:flutter/material.dart';

class RadiusSelector extends StatefulWidget {
  final double currentRadius;
  final ValueChanged<double> onRadiusChanged;
  final List<double> radiusOptions;
  final bool compact;

  const RadiusSelector({
    super.key,
    required this.currentRadius,
    required this.onRadiusChanged,
    this.radiusOptions = const [5000, 10000, 15000, 20000],
    this.compact = false,
  });

  @override
  State<RadiusSelector> createState() => _RadiusSelectorState();
}

class _RadiusSelectorState extends State<RadiusSelector> {
  late double _currentRadius;

  @override
  void initState() {
    super.initState();
    _currentRadius = widget.currentRadius;
  }

  String _formatRadius(double meters) {
    return '${(meters / 1000).toStringAsFixed(0)} km';
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.compact ? 8.0 : 12.0;
    final titleSize = widget.compact ? 12.0 : 13.0;
    final badgeFontSize = widget.compact ? 11.0 : 12.0;
    final badgePadding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 4);
    final barHeight = widget.compact ? 28.0 : 36.0;
    final valueFontSize = widget.compact ? 10.0 : 11.0;
    final unitFontSize = widget.compact ? 8.0 : 9.0;
    final bottomSpacing = widget.compact ? 2.0 : 3.0;
    final rowSpacing = widget.compact ? 6.0 : 10.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rayon de recherche',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: titleSize,
                ),
              ),
              Container(
                padding: badgePadding,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatRadius(_currentRadius),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                    fontSize: badgeFontSize,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: rowSpacing),
          // Jauge avec boutons
          Row(
            children: widget.radiusOptions.map((radius) {
              final isSelected = (_currentRadius - radius).abs() < 100;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _currentRadius = radius);
                      widget.onRadiusChanged(radius);
                    },
                    child: Column(
                      children: [
                        Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Colors.blue.shade700 : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${(radius / 1000).toInt()}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : Colors.grey.shade600,
                                fontSize: valueFontSize,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: bottomSpacing),
                        Text(
                          'km',
                          style: TextStyle(
                            fontSize: unitFontSize,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
