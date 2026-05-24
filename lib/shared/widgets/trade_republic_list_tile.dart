import 'package:flutter/material.dart';
import 'pointer_safe.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'trade_republic_theme.dart';
import 'trade_republic_switch.dart';

/// Trade Republic styled list tile
///
/// A clean, minimal list item with icon, title, subtitle, and trailing widget.
/// Use for settings pages, option lists, account menus, etc.
///
/// Variants:
/// - `TradeRepublicListTile(...)` — standard list tile
/// - `TradeRepublicListTile.navigation(...)` — with chevron arrow
/// - `TradeRepublicListTile.toggle(...)` — with switch/toggle
/// - `TradeRepublicListTile.destructive(...)` — emphasized monochrome action
class TradeRepublicListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? titleColor;
  final bool enableHaptics;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final int? subtitleMaxLines;
  final bool isDestructive;

  const TradeRepublicListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.padding = EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    this.titleColor,
    this.enableHaptics = true,
    this.backgroundColor,
    this.borderRadius,
    this.subtitleMaxLines,
    this.isDestructive = false,
  });

  /// List tile with a navigation chevron (→)
  factory TradeRepublicListTile.navigation({
    Key? key,
    required String title,
    String? subtitle,
    Widget? leading,
    required VoidCallback onTap,
    EdgeInsets padding = EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    int? subtitleMaxLines,
  }) {
    return _TradeRepublicNavigationTile(
      key: key,
      title: title,
      subtitle: subtitle,
      leading: leading,
      onTap: onTap,
      padding: padding,
      subtitleMaxLines: subtitleMaxLines);
  }

  /// List tile with a toggle switch
  factory TradeRepublicListTile.toggle({
    Key? key,
    required String title,
    String? subtitle,
    Widget? leading,
    required bool value,
    required ValueChanged<bool> onChanged,
    EdgeInsets padding = EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    int? subtitleMaxLines,
  }) {
    return _TradeRepublicToggleTile(
      key: key,
      title: title,
      subtitle: subtitle,
      leading: leading,
      value: value,
      onChanged: onChanged,
      padding: padding,
      subtitleMaxLines: subtitleMaxLines);
  }

  /// Emphasized list tile for critical actions (monochrome style)
  factory TradeRepublicListTile.destructive({
    Key? key,
    required String title,
    String? subtitle,
    Widget? leading,
    required VoidCallback onTap,
    EdgeInsets padding = EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    int? subtitleMaxLines,
  }) {
    return TradeRepublicListTile(
      key: key,
      title: title,
      subtitle: subtitle,
      leading: leading,
      onTap: onTap,
      padding: padding,
      isDestructive: true,
      subtitleMaxLines: subtitleMaxLines);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTitleColor = isDestructive
        ? TradeRepublicTheme.destructiveColor(context)
        : (titleColor ?? (backgroundColor != null ? _contrastColor(backgroundColor!) : TradeRepublicTheme.textColor(context)));

    Widget tile = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[
            _buildLeadingContainer(context),
            SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.25,
                    color: effectiveTitleColor)),
                if (subtitle != null) ...[
                  SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: backgroundColor != null
                        ? TradeRepublicTheme.bodySmall(context).copyWith(
                            color: _contrastColor(backgroundColor!).withValues(alpha: 0.6))
                        : TradeRepublicTheme.bodySmall(context),
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis),
                ],
              ])),
          if (trailing != null) ...[
            SizedBox(width: 12),
            trailing!,
          ],
        ]));

    if (backgroundColor != null) {
      tile = AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius ?? BorderRadius.circular(12)),
        child: tile);
    }

    if (onTap != null) {
      tile = _HoverableTile(
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        onTap: () {
          if (enableHaptics) HapticFeedback.lightImpact();
          onTap!();
        },
        child: tile);
    }

    return tile;
  }

  /// Returns white for dark backgrounds, black for light backgrounds
  static Color _contrastColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.4 ? Colors.black : Colors.white;
  }

  Widget _buildLeadingContainer(BuildContext context) {
    final isLight = TradeRepublicTheme.isLight(context);
    final base = backgroundColor != null
        ? _contrastColor(backgroundColor!)
        : (isLight ? Colors.black : Colors.white);
    const size = 40.0;
    const radius = 12.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isLight ? base.withValues(alpha: 0.10) : Colors.transparent,
        border: null,
        borderRadius: BorderRadius.circular(radius)),
      child: Center(child: leading));
  }
}

/// Hoverable wrapper for list tiles on desktop
class _HoverableTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  const _HoverableTile({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });
  @override
  State<_HoverableTile> createState() => _HoverableTileState();
}

class _HoverableTileState extends State<_HoverableTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        scheduleAfterPointerUpdate(() {
          if (!mounted) return;
          setState(() => _hovered = true);
        });
      },
      onExit: (_) {
        scheduleAfterPointerUpdate(() {
          if (!mounted) return;
          setState(() => _hovered = false);
        });
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _hovered
                ? (isLight
                    ? Colors.black.withValues(alpha: 0.04)
                    : Colors.white.withValues(alpha: 0.05))
                : Colors.transparent,
            borderRadius: widget.borderRadius),
          child: widget.child)));
  }
}

/// Internal: navigation tile with chevron
class _TradeRepublicNavigationTile extends TradeRepublicListTile {
  const _TradeRepublicNavigationTile({
    super.key,
    required super.title,
    super.subtitle,
    super.leading,
    required super.onTap,
    super.padding,
    super.subtitleMaxLines,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = TradeRepublicTheme.iconColor(context, opacity: 0.3);

    Widget tile = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[            _buildLeadingContainer(context),
            SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: TradeRepublicTheme.textColor(context))),
                if (subtitle != null) ...[
                  SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TradeRepublicTheme.bodySmall(context),
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis),
                ],
              ])),
          Icon(
            CupertinoIcons.chevron_right,
            size: 17,
            color: iconColor),
        ]));

    return _HoverableTile(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (enableHaptics) HapticFeedback.lightImpact();
        onTap!();
      },
      child: tile);
  }
}

/// Internal: toggle tile with switch
class _TradeRepublicToggleTile extends TradeRepublicListTile {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TradeRepublicToggleTile({
    super.key,
    required super.title,
    super.subtitle,
    super.leading,
    required this.value,
    required this.onChanged,
    super.padding,
    super.subtitleMaxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[            _buildLeadingContainer(context),
            SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: TradeRepublicTheme.textColor(context))),
                if (subtitle != null) ...[
                  SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TradeRepublicTheme.bodySmall(context),
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis),
                ],
              ])),
          SizedBox(width: 12),
          TradeRepublicSwitch(
            value: value,
            onChanged: (v) {
              onChanged(v);
            },
            size: 44),
        ]));
  }
}
