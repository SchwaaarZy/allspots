import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  static const double defaultHeight = 84;

  final String? title;
  final Widget? titleWidget;
  final bool centerTitle;

  final bool showBackButton;
  final VoidCallback? onBackPressed;

  final Widget? leadingWidget;

  final List<Widget>? actions;

  final Widget? bottomWidget;
  final EdgeInsetsGeometry bottomWidgetPadding;

  /// Hauteur de la barre (utile pour agrandir un logo)
  final double height;

  /// Image de background pour le header
  final String? backgroundImage;

  const GlassAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.centerTitle = true,
    this.showBackButton = false,
    this.onBackPressed,
    this.actions,
    this.bottomWidget,
    this.bottomWidgetPadding = const EdgeInsets.only(bottom: 6),
    this.leadingWidget,
    this.height = defaultHeight,
    this.backgroundImage,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    const topBlue = Color(0xFF38BDF8);
    const bottomBlue = Color(0xFF7DD3FC);
    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle;
    final resolvedBackgroundImage =
        backgroundImage ?? 'assets/images/bg_header_allspots.png';

    return AppBar(
      toolbarHeight: height,
      title: titleWidget != null
          ? DefaultTextStyle.merge(style: titleStyle, child: titleWidget!)
          : (title != null
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title!.toUpperCase(),
                    maxLines: 1,
                    softWrap: false,
                  ),
                )
              : null),
      centerTitle: centerTitle,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,

      // ✅ status bar = même teinte que le haut du dégradé
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: topBlue,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),

      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(resolvedBackgroundImage),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    colorFilter: ColorFilter.mode(
                      Colors.white.withValues(alpha: 0.35),
                      BlendMode.srcOver,
                    ),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      topBlue.withValues(alpha: 0.85),
                      bottomBlue.withValues(alpha: 0.75),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                ),
              ),
              if (bottomWidget != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: bottomWidgetPadding,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: bottomWidget,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),

      leading: leadingWidget ??
          (showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBackPressed ?? () => Navigator.pop(context),
                )
              : null),
      actions: actions,
    );
  }
}
