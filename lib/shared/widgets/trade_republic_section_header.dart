import 'package:flutter/material.dart';
import 'trade_republic_theme.dart';

/// Trade Republic styled section header
///
/// A consistent section title with optional subtitle and trailing action.
/// Use this to separate sections in bottom sheets, pages, or lists.
///
/// Example:
/// ```dart
/// TradeRepublicSectionHeader(
///   title: 'Personal data',
///   subtitle: 'Edit your profile',
///   trailing: Icon(Icons.edit),
/// )
/// ```
class TradeRepublicSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const TradeRepublicSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.padding = EdgeInsets.only(bottom: 12),
    this.onTap,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    Widget header = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  style: titleStyle ?? TradeRepublicTheme.titleMedium(context)),
                if (subtitle != null) ...[
                  SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: subtitleStyle ?? TradeRepublicTheme.bodySmall(context)),
                ],
              ])),
          ?trailing,
        ]));

    if (onTap != null) {
      header = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: header);
    }

    return header;
  }
}
