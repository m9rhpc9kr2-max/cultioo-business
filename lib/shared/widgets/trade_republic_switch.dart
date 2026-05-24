import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'dart:io';


/// Trade Republic styled toggle switch.
///
/// On iOS uses the native CNSwitch (system green when on, system gray when off
/// — iOS only exposes the on-tint colour). On all other platforms a custom
/// pill switch is rendered with: On = green, Off = red (overridable via
/// [selectedColor] / [unselectedColor]).
class TradeRepublicSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Kept for API compatibility — not rendered in the pill switch.
  final String selectedLabel;
  final String unselectedLabel;

  /// Background color when the switch is ON. Defaults to green.
  final Color? selectedColor;

  /// Background color when the switch is OFF. Defaults to red.
  final Color? unselectedColor;

  /// Logical track height. The track width is `size * 1.7`.
  final double size;

  const TradeRepublicSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.selectedLabel = 'Y',
    this.unselectedLabel = 'N',
    this.selectedColor,
    this.unselectedColor,
    this.size = 44,
  });

  @override
  State<TradeRepublicSwitch> createState() => _TradeRepublicSwitchState();
}

class _TradeRepublicSwitchState extends State<TradeRepublicSwitch> {
  static final bool _isIOS = Platform.isIOS;
  CNSwitchController? _controller;

  @override
  void initState() {
    super.initState();
    if (_isIOS) {
      _controller = CNSwitchController();
    }
  }

  void _handleTap() {
    if (widget.onChanged != null) {
      HapticFeedback.lightImpact();
      widget.onChanged!(!widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    // iOS: use the native system switch (green on-tint, system gray off).
    if (_isIOS) {
      const onColor = Color(0xFF34C759); // iOS system green
      return CNSwitch(
        value: widget.value,
        onChanged: (val) => widget.onChanged?.call(val),
        controller: _controller,
        color: widget.selectedColor ?? onColor,
      );
    }

    // Non-iOS: render as a circular toggle (filled circle that changes color)
    final circleSize = widget.size * 0.72;

    const onColor = Color(0xFF34C759); // system green
    const offColor = Color(0xFFFF3B30); // system red

    final bgColor = widget.value
        ? (widget.selectedColor ?? onColor)
        : (widget.unselectedColor ?? offColor);

    final isDisabled = widget.onChanged == null;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isDisabled ? null : _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              widget.value ? Icons.check : Icons.close,
              color: Colors.white,
              size: circleSize * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
