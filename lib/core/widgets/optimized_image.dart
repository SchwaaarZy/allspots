import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Widget optimisé pour afficher des images depuis le réseau avec cache automatique
class OptimizedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final safeMemCacheHeight =
      (height != null && height!.isFinite && height! > 0)
        ? (height! * 2).round()
        : null;
    final safeMemCacheWidth =
      (width != null && width!.isFinite && width! > 0)
        ? (width! * 2).round()
        : null;

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) =>
          placeholder ??
          // OPTIMISÉ: Placeholder ultra-léger (pas de spinner lourd)
          Container(
            color: Colors.grey.shade200,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(Colors.grey),
                ),
              ),
            ),
          ),
      errorWidget: (context, url, error) =>
          errorWidget ??
          Container(
            color: Colors.grey.shade200,
            child: const Icon(
              Icons.broken_image,
              color: Colors.grey,
            ),
          ),
      fadeOutDuration: const Duration(milliseconds: 200),
      fadeInDuration: const Duration(milliseconds: 300),
      memCacheHeight: safeMemCacheHeight,
      memCacheWidth: safeMemCacheWidth,
    );
  }
}
