import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Available blur styles for macOS
enum BlurStyle {
  light('light'),
  dark('dark'),
  ultraThin('ultraThin'),
  thin('thin'),
  thick('thick'),
  regular('regular');

  const BlurStyle(this.value);
  final String value;
}

/// macOS-optimized service for Liquid Glass effects with Flutter BackdropFilter
class LiquidGlassService {
  static bool get isSupported => Platform.isMacOS || Platform.isIOS;

  /// Returns blur strength based on style
  static double getBlurSigma(BlurStyle style) {
    switch (style) {
      case BlurStyle.ultraThin:
        return 10.0;
      case BlurStyle.thin:
        return 15.0;
      case BlurStyle.regular:
        return 20.0;
      case BlurStyle.thick:
        return 30.0;
      case BlurStyle.light:
      case BlurStyle.dark:
        return 20.0;
    }
  }

  /// Returns tint color based on style
  static Color getTintColor(BlurStyle style, {required bool isLight}) {
    switch (style) {
      case BlurStyle.light:
        return Colors.white.withOpacity(0.3);
      case BlurStyle.dark:
        return Colors.black.withOpacity(0.3);
      case BlurStyle.ultraThin:
        return isLight
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.1);
      case BlurStyle.thin:
        return isLight
            ? Colors.white.withOpacity(0.2)
            : Colors.black.withOpacity(0.2);
      case BlurStyle.regular:
        return isLight
            ? Colors.white.withOpacity(0.25)
            : Colors.black.withOpacity(0.25);
      case BlurStyle.thick:
        return isLight
            ? Colors.white.withOpacity(0.35)
            : Colors.black.withOpacity(0.35);
    }
  }
}

/// Widget for macOS/iOS Liquid Glass effect with Flutter BackdropFilter
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final BlurStyle blurStyle;
  final BorderRadius? borderRadius;
  final double? opacity;
  final Color? tintColor;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.blurStyle = BlurStyle.regular,
    this.borderRadius,
    this.opacity,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;

    final blurSigma = LiquidGlassService.getBlurSigma(blurStyle);
    final defaultTint = LiquidGlassService.getTintColor(
      blurStyle,
      isLight: isLight);
    final effectiveTint = tintColor ?? defaultTint;
    final effectiveOpacity = opacity ?? 0.95;

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            decoration: BoxDecoration(
              color: effectiveTint.withOpacity(effectiveOpacity),
              borderRadius: borderRadius ?? BorderRadius.circular(20)),
            child: child))));
  }
}
