import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../shared/widgets/trade_republic_tap.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double width;
  final double height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final bool isLight;
  final Color? color;
  final double blur;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    required this.isLight,
    this.width = double.infinity,
    this.height = double.infinity,
    this.padding,
    this.margin,
    this.borderRadius = 25,
    this.color,
    this.blur = 15,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height == double.infinity ? null : height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow:
            boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: -2),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4)),
            ]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: color != null
                    ? [color!.withOpacity(0.2), color!.withOpacity(0.1)]
                    : isLight
                    ? [
                        Colors.white.withOpacity(0.25),
                        Colors.white.withOpacity(0.15),
                      ]
                    : [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.2),
                      ])),
            child: child))));
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool isLight;
  final Color? accentColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    required this.isLight,
    this.padding = EdgeInsets.all(20),
    this.margin = EdgeInsets.only(bottom: 16),
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget cardWidget = GlassContainer(
      isLight: isLight,
      padding: padding,
      margin: margin,
      color: accentColor,
      child: child);

    if (onTap != null) {
      return TradeRepublicTap(onTap: onTap, child: cardWidget);
    }

    return cardWidget;
  }
}
