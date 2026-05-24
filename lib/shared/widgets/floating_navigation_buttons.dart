import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_settings.dart';

/// Floating Navigation Buttons Widget (Island Style)
///
/// This widget creates a floating "island" at the bottom of the screen
/// with transparent background and consistent styling across all steps.
///
/// Usage:
/// ```dart
/// body: Stack(
///   children: [
///     // Your main content with bottom padding: 100
///     SingleChildScrollView(
///       padding: EdgeInsets.only(bottom: 100),
///       child: // Your content
///     ),
///
///     // Floating buttons
///     FloatingNavigationButtons(
///       onBack: () => // Back action,
///       onNext: () => // Next action,
///       nextText: 'Continue to Next Step',
///       nextIcon: Icons.arrow_forward,
///       isNextEnabled: true, // Set to false to disable
///     ),
///   ],
/// )
/// ```
class FloatingNavigationButtons extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextText;
  final IconData nextIcon;
  final bool isNextEnabled;
  final bool showBackButton;
  final Color? nextButtonColor;

  const FloatingNavigationButtons({
    super.key,
    this.onBack,
    this.onNext,
    this.nextText = 'Continue',
    this.nextIcon = Icons.arrow_forward,
    this.isNextEnabled = true,
    this.showBackButton = true,
    this.nextButtonColor,
  });

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final bool isLight = appSettings.isLightMode(context);

    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).padding.bottom + 20,
      child: Container(
        decoration: BoxDecoration(
          color: (isLight ? Colors.white : Colors.black).withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Back Button (conditional)
            if (showBackButton && onBack != null) ...[
              Expanded(child: SizedBox(height: 56, child: Container())),
              const SizedBox(width: 16),
            ],

            // Next Button
            Expanded(
              flex: showBackButton ? 2 : 1,
              child: SizedBox(height: 56, child: Container()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alternative: Simple Continue Button (for first step without back)
class FloatingContinueButton extends StatelessWidget {
  final VoidCallback? onNext;
  final String nextText;
  final IconData nextIcon;
  final bool isNextEnabled;
  final Color? buttonColor;

  const FloatingContinueButton({
    super.key,
    this.onNext,
    this.nextText = 'Continue',
    this.nextIcon = Icons.arrow_forward,
    this.isNextEnabled = true,
    this.buttonColor,
  });

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final bool isLight = appSettings.isLightMode(context);

    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).padding.bottom + 20,
      child: Container(
        decoration: BoxDecoration(
          color: (isLight ? Colors.white : Colors.black).withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: isLight
                  ? [Colors.black, Colors.black.withOpacity(0.7)]
                  : [Colors.white, Colors.white.withOpacity(0.15)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
    );
  }
}
