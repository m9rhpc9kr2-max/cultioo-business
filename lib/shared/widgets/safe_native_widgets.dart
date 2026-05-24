import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/macos_native_service.dart';

/// Safe wrapper for native blur view that prevents infinite size errors
class SafeNativeBlurView extends StatelessWidget {
  final BlurMaterial material;
  final BlurBlendingMode blendingMode;
  final double cornerRadius;
  final Widget? child;
  final double? width;
  final double? height;

  const SafeNativeBlurView({
    super.key,
    this.material = BlurMaterial.window,
    this.blendingMode = BlurBlendingMode.behindWindow,
    this.cornerRadius = 0,
    this.child,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    // Only use native view on macOS
    if (!MacOSNativeService.isMacOS) {
      return _buildFallback();
    }

    // Ensure we have valid dimensions
    return SizedBox(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Prevent infinite/NaN constraints
          final safeWidth = _getSafeSize(
            constraints.maxWidth,
            width,
            fallback: 100);
          final safeHeight = _getSafeSize(
            constraints.maxHeight,
            height,
            fallback: 100);

          // If constraints are still invalid, use fallback
          if (!safeWidth.isFinite || !safeHeight.isFinite) {
            return _buildFallback();
          }

          return SizedBox(
            width: safeWidth,
            height: safeHeight,
            child: Stack(
              children: [
                // Native platform view
                _buildPlatformView(safeWidth, safeHeight),
                // Overlay child if provided
                if (child != null) child!,
              ]));
        }));
  }

  Widget _buildPlatformView(double width, double height) {
    return UiKitView(
      viewType: 'cupertino_native_better/blur_view',
      creationParams: {
        'material': material.name,
        'blendingMode': blendingMode.name,
        'cornerRadius': cornerRadius,
        'width': width,
        'height': height,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (_) {});
  }

  Widget _buildFallback() {
    // Fallback for non-macOS or when native view fails
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: cornerRadius > 0
            ? BorderRadius.circular(cornerRadius)
            : null),
      child: child);
  }

  double _getSafeSize(
    double constraint,
    double? preferred, {
    required double fallback,
  }) {
    if (preferred != null && preferred.isFinite && preferred > 0) {
      return preferred;
    }
    if (constraint.isFinite && constraint > 0) {
      return constraint;
    }
    return fallback;
  }
}

/// Safe wrapper for constrained native views
/// Use this to wrap any native platform view to prevent infinity errors
class SafeNativeViewWrapper extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double minWidth;
  final double minHeight;
  final double maxWidth;
  final double maxHeight;

  const SafeNativeViewWrapper({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.minWidth = 1.0,
    this.minHeight = 1.0,
    this.maxWidth = 10000.0,
    this.maxHeight = 10000.0,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth,
        minHeight: minHeight,
        maxWidth: width ?? maxWidth,
        maxHeight: height ?? maxHeight),
      child: SizedBox(width: width, height: height, child: child));
  }
}

/// Safe blur container that works on all platforms
class SafeBlurContainer extends StatelessWidget {
  final Widget? child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BlurMaterial material;
  final double cornerRadius;
  final Color? fallbackColor;

  const SafeBlurContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.material = BlurMaterial.window,
    this.cornerRadius = 12.0,
    this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveChild = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    Widget content;

    if (MacOSNativeService.isMacOS) {
      // Use native blur on macOS
      content = SafeNativeBlurView(
        material: material,
        cornerRadius: cornerRadius,
        width: width,
        height: height,
        child: effectiveChild);
    } else {
      // Fallback for other platforms
      content = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color:
              fallbackColor ??
              Theme.of(context).colorScheme.surface.withOpacity(0.8),
          borderRadius: BorderRadius.circular(cornerRadius)),
        child: effectiveChild);
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}

/// Extension for easy native blur wrapping
extension NativeBlurExtension on Widget {
  /// Wrap this widget with a safe native blur effect
  Widget withBlur({
    BlurMaterial material = BlurMaterial.window,
    double cornerRadius = 12.0,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
  }) {
    return SafeBlurContainer(
      material: material,
      cornerRadius: cornerRadius,
      padding: padding,
      margin: margin,
      child: this);
  }

  /// Wrap this widget with safe constraints for native views
  Widget withSafeConstraints({
    double? width,
    double? height,
    double minWidth = 1.0,
    double minHeight = 1.0,
  }) {
    return SafeNativeViewWrapper(
      width: width,
      height: height,
      minWidth: minWidth,
      minHeight: minHeight,
      child: this);
  }
}

/// Cupertino-style blur background
class CupertinoBlurBackground extends StatelessWidget {
  final Widget child;
  final BlurMaterial material;

  const CupertinoBlurBackground({
    super.key,
    required this.child,
    this.material = BlurMaterial.sidebar,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Blur background
        Positioned.fill(
          child: SafeNativeViewWrapper(
            child: SafeNativeBlurView(
              material: material,
              blendingMode: BlurBlendingMode.behindWindow))),
        // Content
        child,
      ]);
  }
}

/// Intrinsic size wrapper that prevents infinity
class SafeIntrinsicWrapper extends StatelessWidget {
  final Widget child;
  final Axis? direction;

  const SafeIntrinsicWrapper({super.key, required this.child, this.direction});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Check if we have finite constraints
        final hasFiniteWidth = constraints.maxWidth.isFinite;
        final hasFiniteHeight = constraints.maxHeight.isFinite;

        // Only use intrinsic sizing if we have room to do so
        if (direction == null && hasFiniteWidth && hasFiniteHeight) {
          return IntrinsicHeight(child: IntrinsicWidth(child: child));
        } else if (direction == Axis.vertical && hasFiniteHeight) {
          return IntrinsicHeight(child: child);
        } else if (direction == Axis.horizontal && hasFiniteWidth) {
          return IntrinsicWidth(child: child);
        }

        // Return child directly if intrinsic sizing would cause issues
        return child;
      });
  }
}
