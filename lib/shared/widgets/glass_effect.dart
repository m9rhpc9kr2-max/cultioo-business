import 'package:flutter/material.dart';
import 'dart:ui';
import '../services/app_settings.dart';

class GlassEffect {
  static Widget container({
    required Widget child,
    double? width,
    double? height,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? accentColor,
  }) {
    return Builder(
      builder: (context) {
        final AppSettings appSettings = AppSettings();
        final isLight = appSettings.isLightMode(context);

        return Container(
          width: width,
          height: height,
          margin: margin,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: accentColor != null
                        ? [
                            accentColor.withValues(alpha: 0.05),
                            accentColor.withValues(alpha: 0.04),
                          ]
                        : isLight
                        ? [
                            Colors.black.withValues(alpha: 0.03),
                            Colors.black.withValues(alpha: 0.02),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.08),
                            Colors.white.withValues(alpha: 0.04),
                          ])),
                child: child))));
      });
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return GlassEffect.container(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      child: child);
  }
}

// iOS-style Cultioo Glass Container with native blur effects
class CultiooGlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blur;
  final double opacity;
  final double borderRadius;

  const CultiooGlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.blur = 10,
    this.opacity = 0.1,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = AppSettings();
    final isLight = appSettings.isLightMode(context);

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isLight
                    ? [
                        Colors.white.withValues(alpha: 0.8),
                        Colors.white.withValues(alpha: 0.4),
                      ]
                    : [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.black.withValues(alpha: 0.2),
                      ]),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.1 : 0.3),
                  blurRadius: 20,
                  spreadRadius: -5,
                  offset: const Offset(0, 10)),
              ]),
            child: child))));
  }
}

class FloatingGlassDock extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final double height;
  final bool isLight;

  const FloatingGlassDock({
    super.key,
    required this.children,
    required this.isLight,
    this.mainAxisAlignment = MainAxisAlignment.spaceEvenly,
    this.height = 70,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isLight
                    ? [
                        Colors.black.withValues(alpha: 0.04),
                        Colors.black.withValues(alpha: 0.02),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.12),
                        Colors.white.withValues(alpha: 0.06),
                      ])),
            child: Row(
              mainAxisAlignment: mainAxisAlignment,
              children: children)))));
  }
}
