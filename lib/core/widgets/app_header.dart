import 'package:flutter/material.dart';

import 'glass_app_bar.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final Widget? leadingWidget;
  final List<Widget>? actions;
  final double height;
  final String? backgroundImage;
  final String? title;
  final Widget? titleWidget;
  final Widget? bottomWidget;
  final EdgeInsetsGeometry bottomWidgetPadding;

  const AppHeader({
    super.key,
    this.showBackButton = false,
    this.onBackPressed,
    this.leadingWidget,
    this.actions,
    this.height = GlassAppBar.defaultHeight,
    this.backgroundImage,
    this.title,
    this.titleWidget,
    this.bottomWidget,
    this.bottomWidgetPadding = const EdgeInsets.only(bottom: 6),
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final resolvedTitleWidget = titleWidget ??
        (title == null
            ? SizedBox(
                height: height * 0.6,
                child: Image.asset(
                  'assets/images/allspots_simple_logo.png',
                  fit: BoxFit.contain,
                ),
              )
            : null);

    return GlassAppBar(
      height: height,
      showBackButton: showBackButton,
      onBackPressed: onBackPressed,
      leadingWidget: leadingWidget,
      actions: actions,
      backgroundImage: backgroundImage,
      title: title,
      titleWidget: resolvedTitleWidget,
      bottomWidget: bottomWidget,
      bottomWidgetPadding: bottomWidgetPadding,
    );
  }
}
