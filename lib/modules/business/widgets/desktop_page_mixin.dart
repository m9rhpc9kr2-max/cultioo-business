import 'package:flutter/material.dart';
import '../../../shared/widgets/desktop_optimized_widgets.dart';

/// Mixin for desktop-optimized page layouts
/// Provides consistent desktop styling across all business pages
mixin DesktopPageMixin {
  /// Get desktop-optimized page padding
  EdgeInsets getPagePadding(BuildContext context) {
    return EdgeInsets.all(DesktopOptimizedWidgets.getPadding() * 2);
  }

  /// Get desktop-optimized page title style
  TextStyle getPageTitleStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DesktopOptimizedWidgets.getDesktopHeadingStyle(
      color: isDark ? Colors.white : Colors.black,
      fontSize: 24,
      fontWeight: FontWeight.w700,
    );
  }

  /// Get desktop-optimized section title style
  TextStyle getSectionTitleStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DesktopOptimizedWidgets.getDesktopHeadingStyle(
      color: isDark ? Colors.white : Colors.black,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
  }

  /// Get desktop-optimized body text style
  TextStyle getBodyTextStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DesktopOptimizedWidgets.getDesktopTextStyle(
      color: isDark ? Colors.grey[300]! : Colors.grey[700]!,
      fontSize: DesktopOptimizedWidgets.getFontSize(),
      fontWeight: FontWeight.w400,
    );
  }

  /// Get desktop-optimized label text style
  TextStyle getLabelTextStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DesktopOptimizedWidgets.getDesktopTextStyle(
      color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
      fontSize: DesktopOptimizedWidgets.getFontSize() - 1,
      fontWeight: FontWeight.w500,
    );
  }

  /// Get desktop-optimized spacing
  double getSpacing() => DesktopOptimizedWidgets.getSpacing();

  /// Get desktop-optimized padding
  double getPadding() => DesktopOptimizedWidgets.getPadding();

  /// Get desktop-optimized border radius
  double getBorderRadius() => DesktopOptimizedWidgets.getBorderRadius();

  /// Build a desktop-optimized page header
  Widget buildPageHeader(
    BuildContext context, {
    required String title,
    Widget? subtitle,
    Widget? trailing,
    bool showDivider = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: getPageTitleStyle(context),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: getSpacing()),
                    subtitle,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: getPadding()),
              trailing,
            ],
          ],
        ),
        if (showDivider) ...[
          SizedBox(height: getPadding()),
          Divider(
            thickness: DesktopOptimizedWidgets.getDividerThickness(),
            color: DesktopOptimizedWidgets.getDividerColor(context),
          ),
        ],
        SizedBox(height: getPadding()),
      ],
    );
  }

  /// Build a desktop-optimized section
  Widget buildSection(
    BuildContext context, {
    required String title,
    required Widget child,
    Widget? trailing,
    bool showDivider = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: getSectionTitleStyle(context),
            ),
            if (trailing != null) trailing,
          ],
        ),
        SizedBox(height: getSpacing() * 1.5),
        child,
        if (showDivider) ...[
          SizedBox(height: getPadding()),
          Divider(
            thickness: DesktopOptimizedWidgets.getDividerThickness(),
            color: DesktopOptimizedWidgets.getDividerColor(context),
          ),
        ],
      ],
    );
  }

  /// Build a desktop-optimized card
  Widget buildCard(
    BuildContext context, {
    required Widget child,
    Color? backgroundColor,
    EdgeInsets? padding,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: DesktopOptimizedWidgets.getDesktopBoxDecoration(
        backgroundColor: backgroundColor ?? (isDark ? Colors.grey[900]! : Colors.white),
        borderRadius: getBorderRadius(),
        showShadow: true,
      ),
      padding: padding ?? DesktopOptimizedWidgets.getDesktopCardPadding(),
      child: child,
    );
  }

  /// Build a desktop-optimized list item
  Widget buildListItem(
    BuildContext context, {
    required Widget title,
    Widget? subtitle,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
    bool showDivider = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          hoverColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: getSpacing(),
              horizontal: getPadding(),
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading,
                  SizedBox(width: getSpacing() * 1.5),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      if (subtitle != null) ...[
                        SizedBox(height: getSpacing() / 2),
                        subtitle,
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  SizedBox(width: getSpacing()),
                  trailing,
                ],
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            thickness: DesktopOptimizedWidgets.getDividerThickness(),
            color: DesktopOptimizedWidgets.getDividerColor(context),
            height: 1,
          ),
      ],
    );
  }

  /// Build a desktop-optimized grid
  Widget buildGrid(
    BuildContext context, {
    required List<Widget> children,
    int crossAxisCount = 3,
    double? childAspectRatio,
  }) {
    return GridView.count(
      crossAxisCount: crossAxisCount,
      childAspectRatio: childAspectRatio ?? 1.2,
      mainAxisSpacing: getPadding(),
      crossAxisSpacing: getPadding(),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }

  /// Build a desktop-optimized empty state
  Widget buildEmptyState(
    BuildContext context, {
    required String title,
    required String description,
    Widget? icon,
    Widget? action,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            icon,
            SizedBox(height: getPadding() * 2),
          ],
          Text(
            title,
            style: getSectionTitleStyle(context),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: getSpacing()),
          Text(
            description,
            style: getBodyTextStyle(context),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            SizedBox(height: getPadding() * 2),
            action,
          ],
        ],
      ),
    );
  }

  /// Build a desktop-optimized loading state
  Widget buildLoadingState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          SizedBox(height: getPadding()),
          Text(
            'Loading...',
            style: getBodyTextStyle(context),
          ),
        ],
      ),
    );
  }

  /// Build a desktop-optimized error state
  Widget buildErrorState(
    BuildContext context, {
    required String message,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: DesktopOptimizedWidgets.getIconSize() * 2,
            color: Colors.red[400],
          ),
          SizedBox(height: getPadding()),
          Text(
            'Error',
            style: getSectionTitleStyle(context),
          ),
          SizedBox(height: getSpacing()),
          Text(
            message,
            style: getBodyTextStyle(context),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            SizedBox(height: getPadding()),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  /// Build a responsive page layout
  Widget buildResponsiveLayout(
    BuildContext context, {
    required Widget child,
    double maxWidth = 1200,
  }) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: getPagePadding(context),
            child: child,
          ),
        ),
      ),
    );
  }
}
