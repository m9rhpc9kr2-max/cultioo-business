import 'package:flutter/material.dart';
import 'dart:io';

import 'trade_republic_button.dart';
import '../services/app_localizations.dart';

/// Adds an iOS/macOS "Fertig" button above the software keyboard.
///
/// ARCHITECTURE NOTE — why the MediaQuery read lives in a *child* widget:
/// ───────────────────────────────────────────────────────────────────────
/// If [KeyboardToolbar.build] called `MediaQuery.of(context).viewInsets.bottom`
/// directly, Flutter would register the KeyboardToolbar element as a dependent
/// of MediaQuery.  Every keyboard show/hide → MediaQuery changes → KeyboardToolbar
/// rebuilds → Stack rebuilds → Flutter reconciles the Navigator (first Stack
/// child) → NavigatorState.build fires while the Navigator is mid-transition →
/// `_history.isNotEmpty` assertion crashes the app.
///
/// Delegating the MediaQuery read to [_KeyboardFertigButton] means only *that*
/// leaf element rebuilds on keyboard changes.  The Navigator is untouched.
class KeyboardToolbar extends StatelessWidget {
  final Widget child;

  const KeyboardToolbar({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    // Only active on Apple platforms.
    if (!Platform.isIOS && !Platform.isMacOS) return child;

    // DO NOT call MediaQuery.of(context) here — see the class comment above.
    return Stack(
      children: [
        Positioned.fill(child: child),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _KeyboardFertigButton(),
        ),
      ],
    );
  }
}

/// Self-contained widget that tracks keyboard height via [WidgetsBindingObserver]
/// instead of [MediaQuery.of]. This ensures that keyboard show/hide events do NOT
/// trigger a [MaterialApp] builder rebuild, which would force the Navigator to
/// rebuild while [pushNamedAndRemoveUntil] has an empty history → assert crash.
class _KeyboardFertigButton extends StatefulWidget {
  const _KeyboardFertigButton();

  @override
  State<_KeyboardFertigButton> createState() => _KeyboardFertigButtonState();
}

class _KeyboardFertigButtonState extends State<_KeyboardFertigButton>
    with WidgetsBindingObserver {
  double _bottomInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view == null) return;
    final insetPx = view.viewInsets.bottom;
    final dpr = view.devicePixelRatio;
    final insetDp = insetPx / dpr;
    if (insetDp != _bottomInset && mounted) {
      setState(() => _bottomInset = insetDp);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bottomInset <= 0) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: _bottomInset + 8, right: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          type: MaterialType.transparency,
          child: TradeRepublicButton(
            label: AppLocalizations.of(context)?.done ?? 'Done',
            height: 32,
            width: 72,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            borderRadius: BorderRadius.circular(10),
            isSecondary: false,
            showShadow: true,
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
            },
          ),
        ),
      ),
    );
  }
}
