import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'desktop_optimized_widgets.dart';

/// Global wrapper for desktop app optimization
/// Automatically applies desktop-specific styling to all pages
class DesktopAppWrapper {
  DesktopAppWrapper._();

  /// Check if running on desktop
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Get max content width for desktop
  static const double maxContentWidth = 1400;

  /// Get sidebar width for desktop
  static const double sidebarWidth = 280;

  /// Wrap a page with desktop-optimized constraints
  static Widget wrapPage(Widget child) {
    if (!isDesktop) return child;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );
  }

  /// Get adaptive font scale for desktop
  static double getFontScale() => isDesktop ? 0.95 : 1.0;

  /// Get adaptive padding for pages
  static EdgeInsets getPagePadding() {
    if (!isDesktop) return const EdgeInsets.all(16);
    return const EdgeInsets.all(24);
  }

  /// Get adaptive horizontal padding
  static double getHorizontalPadding() => isDesktop ? 24 : 16;

  /// Get adaptive vertical padding
  static double getVerticalPadding() => isDesktop ? 20 : 16;

  /// Build desktop-optimized scaffold
  static Widget buildScaffold({
    required BuildContext context,
    required Widget body,
    Color? backgroundColor,
    PreferredSizeWidget? appBar,
    Widget? floatingActionButton,
    FloatingActionButtonLocation? floatingActionButtonLocation,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor ?? (isDark ? Colors.black : Colors.white);

    if (!isDesktop) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: appBar,
      body: wrapPage(body),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }

  /// Build desktop-optimized app bar
  static PreferredSizeWidget buildAppBar({
    required BuildContext context,
    required String title,
    List<Widget>? actions,
    Widget? leading,
    bool centerTitle = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isDesktop) {
      return AppBar(
        title: Text(title),
        actions: actions,
        leading: leading,
        centerTitle: centerTitle,
      );
    }

    return AppBar(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
      elevation: 0,
      backgroundColor: isDark ? Colors.black : Colors.white,
    );
  }

  /// Build desktop-optimized text field
  static Widget buildTextField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool obscureText = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DesktopOptimizedWidgets.getDesktopTextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                DesktopOptimizedWidgets.getBorderRadius(),
              ),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: DesktopOptimizedWidgets.getPadding(),
              vertical: DesktopOptimizedWidgets.getPadding() / 2,
            ),
          ),
        ),
      ],
    );
  }

  /// Build desktop-optimized button
  static Widget buildButton({
    required BuildContext context,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = true,
    bool isLoading = false,
    double? width,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: width,
      height: DesktopOptimizedWidgets.getButtonHeight(),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? Colors.blue
              : (isDark ? Colors.grey[800] : Colors.grey[200]),
          foregroundColor: isPrimary ? Colors.white : Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              DesktopOptimizedWidgets.getBorderRadius(),
            ),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                style: DesktopOptimizedWidgets.getDesktopButtonStyle(
                  color: isPrimary ? Colors.white : Colors.black,
                ),
              ),
      ),
    );
  }

  /// Build desktop-optimized card
  static Widget buildCard({
    required BuildContext context,
    required Widget child,
    EdgeInsets? padding,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? Colors.grey[900] : Colors.white,
      borderRadius: BorderRadius.circular(
        DesktopOptimizedWidgets.getBorderRadius(),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          DesktopOptimizedWidgets.getBorderRadius(),
        ),
        child: Container(
          decoration: DesktopOptimizedWidgets.getDesktopBoxDecoration(
            backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
            borderRadius: DesktopOptimizedWidgets.getBorderRadius(),
          ),
          padding: padding ??
              DesktopOptimizedWidgets.getDesktopCardPadding(),
          child: child,
        ),
      ),
    );
  }

  /// Build desktop-optimized list item
  static Widget buildListItem({
    required BuildContext context,
    required String title,
    String? subtitle,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: DesktopOptimizedWidgets.getSpacing(),
            horizontal: DesktopOptimizedWidgets.getPadding(),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading,
                SizedBox(width: DesktopOptimizedWidgets.getSpacing() * 1.5),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: DesktopOptimizedWidgets.getDesktopTextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: DesktopOptimizedWidgets.getDesktopTextStyle(
                          color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                          fontSize:
                              DesktopOptimizedWidgets.getFontSize() - 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: DesktopOptimizedWidgets.getSpacing()),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build desktop-optimized dialog
  static Future<T?> showDialog<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    List<Widget>? actions,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dialog',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: DesktopOptimizedWidgets.getAnimationDuration(),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ScaleTransition(
          scale: animation,
          child: Dialog(
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                DesktopOptimizedWidgets.getBorderRadius(),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                padding: DesktopOptimizedWidgets.getDesktopCardPadding(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: DesktopOptimizedWidgets.getDesktopHeadingStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    content,
                    if (actions != null) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
