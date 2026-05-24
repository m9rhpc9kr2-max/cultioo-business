import 'package:flutter/material.dart';
import 'trade_republic_tap.dart';

class AnimatedNotification {
  static OverlayEntry? _overlayEntry;
  static bool _isShowing = false;

  static void show(
    BuildContext context, {
    required String message,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onTap,
  }) {
    if (_isShowing) {
      hide();
    }

    _isShowing = true;

    _overlayEntry = OverlayEntry(
      builder: (context) => AnimatedNotificationWidget(
        message: message,
        type: type,
        duration: duration,
        onTap: onTap,
        onDismiss: () {
          hide();
        }));

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void hide() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      _isShowing = false;
    }
  }
}

enum NotificationType { success, error, warning, info }

class AnimatedNotificationWidget extends StatefulWidget {
  final String message;
  final NotificationType type;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const AnimatedNotificationWidget({
    super.key,
    required this.message,
    required this.type,
    required this.duration,
    this.onTap,
    required this.onDismiss,
  });

  @override
  State<AnimatedNotificationWidget> createState() =>
      _AnimatedNotificationWidgetState();
}

class _AnimatedNotificationWidgetState extends State<AnimatedNotificationWidget>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this);

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut));

    // Start animations
    _slideController.forward();
    _fadeController.forward();

    // Auto dismiss after duration
    Future.delayed(widget.duration, () {
      _dismiss();
    });
  }

  void _dismiss() async {
    await _fadeController.reverse();
    await _slideController.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Color _getBackgroundColor() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return isLight ? Colors.black : Colors.white;
  }

  IconData _getIcon() {
    switch (widget.type) {
      case NotificationType.success:
        return Icons.check_circle;
      case NotificationType.error:
        return Icons.error;
      case NotificationType.warning:
        return Icons.warning;
      case NotificationType.info:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: Container(
              margin: EdgeInsets.all(16),
              child: Material(
                color: Colors.transparent,
                child: TradeRepublicTap(
                  onTap: widget.onTap ?? _dismiss,
                  onVerticalDragUpdate: (details) {
                    if (details.delta.dy < 0) {
                      _dismiss();
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getBackgroundColor(),
                      borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20)),
                          child: Icon(
                            _getIcon(),
                            color: Colors.white,
                            size: 24)),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500))),
                        TradeRepublicTap(
                          onTap: _dismiss,
                          child: Container(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 18))),
                      ])))))))));
  }
}
