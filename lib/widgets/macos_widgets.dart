import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:io';
import '../services/liquid_glass_service.dart';
import '../shared/widgets/trade_republic_tap.dart';

/// macOS-optimierte Control Bar mit Liquid Glass Effekt
class MacOSControlBar extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets? padding;
  final double? height;
  final VoidCallback? onClose;

  const MacOSControlBar({
    super.key,
    required this.children,
    this.padding,
    this.height,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return _buildMacOSNativeBar(context);
    } else {
      return _buildFallbackBar(context);
    }
  }

  /// Native macOS Bar mit SwiftUI Liquid Glass
  Widget _buildMacOSNativeBar(BuildContext context) {
    return LiquidGlassContainer(
      blurStyle: BlurStyle.regular,
      borderRadius: BorderRadius.circular(14),
      opacity: 0.95,
      tintColor: Colors.white,
      child: Container(
        height: height ?? 52,
        padding:
            padding ?? EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Traffic Light Buttons (macOS Style)
            _buildTrafficLights(),

            // Content
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: children)),
          ])));
  }

  /// Fallback for other platforms
  Widget _buildFallbackBar(BuildContext context) {
    return Container(
      height: height ?? 52,
      padding:
          padding ?? EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.2)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: children))));
  }

  /// macOS Traffic Light Buttons
  Widget _buildTrafficLights() {
    return Row(
      children: [
        _TrafficLight(color: const Color(0xFFFF5F57), onTap: onClose),
        SizedBox(width: 8),
        _TrafficLight(
          color: const Color(0xFFFFBD2E),
          onTap: () {
            // Minimize action
          }),
        SizedBox(width: 8),
        _TrafficLight(
          color: const Color(0xFF28CA42),
          onTap: () {
            // Fullscreen action
          }),
        SizedBox(width: 16),
      ]);
  }
}

/// Individual Traffic Light Button
class _TrafficLight extends StatefulWidget {
  final Color color;
  final VoidCallback? onTap;

  const _TrafficLight({required this.color, this.onTap});

  @override
  State<_TrafficLight> createState() => _TrafficLightState();
}

class _TrafficLightState extends State<_TrafficLight> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: TradeRepublicTap(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.4),
                blurRadius: isHovered ? 4 : 2,
                offset: const Offset(0, 1)),
            ]),
          child: isHovered
              ? Icon(
                  _getIconForColor(widget.color),
                  size: 8,
                  color: Colors.black.withOpacity(0.7))
              : null)));
  }

  IconData _getIconForColor(Color color) {
    if (color.value == 0xFFFF5F57) return Icons.close; // Red - Close
    if (color.value == 0xFFFFBD2E) return Icons.remove; // Yellow - Minimize
    if (color.value == 0xFF28CA42) {
      return Icons.fullscreen; // Green - Fullscreen
    }
    return Icons.circle;
  }
}

/// macOS Card mit Liquid Glass Effekt
class MacOSCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;
  final EdgeInsets? padding;
  final double? elevation;
  final BlurStyle? blurStyle;

  const MacOSCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.elevation,
    this.blurStyle,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: margin,
      padding: padding ?? EdgeInsets.all(14),
      child: child);

    if (Platform.isMacOS) {
      return LiquidGlassContainer(
        blurStyle: blurStyle ?? BlurStyle.regular,
        borderRadius: BorderRadius.circular(14),
        opacity: 0.95,
        child: content);
    } else {
      return Card(
        margin: margin,
        elevation: elevation ?? 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: padding ?? EdgeInsets.all(14),
          child: child));
    }
  }
}

/// macOS Bottom Sheet mit Liquid Glass
class MacOSBottomSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final double? height;
  final VoidCallback? onClose;

  const MacOSBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.height,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final sheetHeight = height ?? screenHeight * 0.7;

    if (Platform.isMacOS) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 1200 ? 860 : 680,
            maxHeight: sheetHeight),
          child: _buildMacOSSheet()));
    }

    return SizedBox(height: sheetHeight, child: _buildFallbackSheet());
  }

  Widget _buildMacOSSheet() {
    return LiquidGlassContainer(
      blurStyle: BlurStyle.regular,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          if (title != null) _buildHeader(),
          Expanded(child: child),
        ]));
  }

  Widget _buildFallbackSheet() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5)),
        ]),
      child: Column(
        children: [
          if (title != null) _buildHeader(),
          Expanded(child: child),
        ]));
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title!,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (onClose != null)
            TradeRepublicTap(
              onTap: onClose,
              child: Container(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 20,
                    color: Colors.black.withValues(alpha: 0.6)))),
        ]));
  }
}
