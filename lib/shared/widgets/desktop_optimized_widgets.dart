import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

/// Desktop-optimized widget utilities for Cultioo Business App
/// Provides responsive sizing and styling for desktop platforms (macOS, Windows, Linux)
class DesktopOptimizedWidgets {
  DesktopOptimizedWidgets._();

  /// Check if running on desktop platform
  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Desktop-optimized button height (more compact than mobile)
  static const double buttonHeightDesktop = 40;
  static const double buttonHeightMobile = 48;

  /// Get adaptive button height based on platform
  static double getButtonHeight() =>
      isDesktopPlatform ? buttonHeightDesktop : buttonHeightMobile;

  /// Desktop-optimized text field height
  static const double textFieldHeightDesktop = 44;
  static const double textFieldHeightMobile = 56;

  /// Get adaptive text field height based on platform
  static double getTextFieldHeight() =>
      isDesktopPlatform ? textFieldHeightDesktop : textFieldHeightMobile;

  /// Desktop-optimized padding (more compact)
  static const double paddingDesktop = 12;
  static const double paddingMobile = 16;

  /// Get adaptive padding based on platform
  static double getPadding() =>
      isDesktopPlatform ? paddingDesktop : paddingMobile;

  /// Desktop-optimized border radius (slightly tighter)
  static const double borderRadiusDesktop = 12;
  static const double borderRadiusMobile = 16;

  /// Get adaptive border radius based on platform
  static double getBorderRadius() =>
      isDesktopPlatform ? borderRadiusDesktop : borderRadiusMobile;

  /// Desktop-optimized font size (slightly smaller)
  static const double fontSizeDesktop = 14;
  static const double fontSizeMobile = 16;

  /// Get adaptive font size based on platform
  static double getFontSize() =>
      isDesktopPlatform ? fontSizeDesktop : fontSizeMobile;

  /// Desktop-optimized icon size
  static const double iconSizeDesktop = 18;
  static const double iconSizeMobile = 24;

  /// Get adaptive icon size based on platform
  static double getIconSize() =>
      isDesktopPlatform ? iconSizeDesktop : iconSizeMobile;

  /// Desktop-optimized spacing between elements
  static const double spacingDesktop = 8;
  static const double spacingMobile = 12;

  /// Get adaptive spacing based on platform
  static double getSpacing() =>
      isDesktopPlatform ? spacingDesktop : spacingMobile;

  /// Desktop-optimized card elevation (flatter design)
  static const double elevationDesktop = 0.5;
  static const double elevationMobile = 2;

  /// Get adaptive elevation based on platform
  static double getElevation() =>
      isDesktopPlatform ? elevationDesktop : elevationMobile;

  /// Desktop-optimized shadow blur radius
  static const double shadowBlurDesktop = 4;
  static const double shadowBlurMobile = 8;

  /// Get adaptive shadow blur based on platform
  static double getShadowBlur() =>
      isDesktopPlatform ? shadowBlurDesktop : shadowBlurMobile;

  /// Desktop-optimized animation duration (faster on desktop)
  static const Duration animationDurationDesktop = Duration(milliseconds: 100);
  static const Duration animationDurationMobile = Duration(milliseconds: 150);

  /// Get adaptive animation duration based on platform
  static Duration getAnimationDuration() =>
      isDesktopPlatform ? animationDurationDesktop : animationDurationMobile;

  /// Desktop-optimized cursor behavior
  static MouseCursor getCursorForButton(bool isEnabled) =>
      isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic;

  /// Desktop-optimized hover effects
  static Color getHoverColor(Color baseColor, bool isLight) {
    if (isLight) {
      return baseColor.withValues(alpha: 0.85);
    } else {
      return baseColor.withValues(alpha: 0.85);
    }
  }

  /// Desktop-optimized pressed effects
  static Color getPressedColor(Color baseColor, bool isLight) {
    if (isLight) {
      return baseColor.withValues(alpha: 0.70);
    } else {
      return baseColor.withValues(alpha: 0.70);
    }
  }

  /// Desktop-optimized disabled effects
  static Color getDisabledColor(Color baseColor) {
    return baseColor.withValues(alpha: 0.45);
  }

  /// Desktop-optimized text style
  static TextStyle getDesktopTextStyle({
    required Color color,
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize ?? getFontSize(),
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }

  /// Desktop-optimized heading style
  static TextStyle getDesktopHeadingStyle({
    required Color color,
    double? fontSize,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize ?? (getFontSize() + 4),
      fontWeight: fontWeight,
      letterSpacing: -0.2,
    );
  }

  /// Desktop-optimized button style
  static TextStyle getDesktopButtonStyle({
    required Color color,
    double? fontSize,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize ?? (getFontSize() + 1),
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    );
  }

  /// Desktop-optimized box decoration
  static BoxDecoration getDesktopBoxDecoration({
    required Color backgroundColor,
    Color? borderColor,
    double? borderRadius,
    bool showShadow = true,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      border: borderColor != null
          ? Border.all(color: borderColor, width: 1)
          : null,
      borderRadius: BorderRadius.circular(borderRadius ?? getBorderRadius()),
      boxShadow: showShadow
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: getShadowBlur(),
                offset: const Offset(0, 1),
              ),
            ]
          : null,
    );
  }

  /// Desktop-optimized edge insets for content
  static EdgeInsets getDesktopContentPadding({
    double? horizontal,
    double? vertical,
  }) {
    return EdgeInsets.symmetric(
      horizontal: horizontal ?? getPadding(),
      vertical: vertical ?? (getPadding() / 2),
    );
  }

  /// Desktop-optimized edge insets for buttons
  static EdgeInsets getDesktopButtonPadding() {
    return EdgeInsets.symmetric(
      horizontal: getPadding() * 1.5,
      vertical: getPadding() / 2,
    );
  }

  /// Desktop-optimized edge insets for cards
  static EdgeInsets getDesktopCardPadding() {
    return EdgeInsets.all(getPadding() * 1.5);
  }

  /// Desktop-optimized list tile height
  static const double listTileHeightDesktop = 44;
  static const double listTileHeightMobile = 56;

  /// Get adaptive list tile height based on platform
  static double getListTileHeight() =>
      isDesktopPlatform ? listTileHeightDesktop : listTileHeightMobile;

  /// Desktop-optimized divider thickness
  static const double dividerThicknessDesktop = 0.5;
  static const double dividerThicknessMobile = 1;

  /// Get adaptive divider thickness based on platform
  static double getDividerThickness() =>
      isDesktopPlatform ? dividerThicknessDesktop : dividerThicknessMobile;

  /// Desktop-optimized divider color
  static Color getDividerColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12);
  }

  /// Desktop-optimized scale for hover effects
  static const double hoverScaleDesktop = 0.98;
  static const double hoverScaleMobile = 0.97;

  /// Get adaptive hover scale based on platform
  static double getHoverScale() =>
      isDesktopPlatform ? hoverScaleDesktop : hoverScaleMobile;

  /// Desktop-optimized scale for pressed effects
  static const double pressedScaleDesktop = 0.95;
  static const double pressedScaleMobile = 0.97;

  /// Get adaptive pressed scale based on platform
  static double getPressedScale() =>
      isDesktopPlatform ? pressedScaleDesktop : pressedScaleMobile;
}

/// Desktop-optimized container widget
class DesktopOptimizedContainer extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final bool showShadow;
  final double? width;
  final double? height;

  const DesktopOptimizedContainer({
    super.key,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.padding,
    this.margin,
    this.showShadow = true,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor ?? (isDark ? Colors.grey[900] : Colors.white);

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding ?? DesktopOptimizedWidgets.getDesktopContentPadding(),
      decoration: DesktopOptimizedWidgets.getDesktopBoxDecoration(
        backgroundColor: bgColor!,
        borderColor: borderColor,
        borderRadius: borderRadius,
        showShadow: showShadow,
      ),
      child: child,
    );
  }
}

/// Desktop-optimized divider
class DesktopOptimizedDivider extends StatelessWidget {
  final double? height;
  final double? thickness;
  final Color? color;
  final EdgeInsets? padding;

  const DesktopOptimizedDivider({
    super.key,
    this.height,
    this.thickness,
    this.color,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.symmetric(
        vertical: DesktopOptimizedWidgets.getSpacing(),
      ),
      child: Divider(
        height: height ?? 1,
        thickness: thickness ?? DesktopOptimizedWidgets.getDividerThickness(),
        color: color ?? DesktopOptimizedWidgets.getDividerColor(context),
      ),
    );
  }
}

/// Desktop-optimized spacing widget
class DesktopOptimizedSpacing extends StatelessWidget {
  final double? width;
  final double? height;

  const DesktopOptimizedSpacing({
    super.key,
    this.width,
    this.height,
  });

  factory DesktopOptimizedSpacing.horizontal({
    Key? key,
    double? width,
  }) {
    return DesktopOptimizedSpacing(
      key: key,
      width: width ?? DesktopOptimizedWidgets.getSpacing(),
    );
  }

  factory DesktopOptimizedSpacing.vertical({
    Key? key,
    double? height,
  }) {
    return DesktopOptimizedSpacing(
      key: key,
      height: height ?? DesktopOptimizedWidgets.getSpacing(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height);
  }
}
