// qr_scanner_sheet.dart — full-screen QR scanner bottom sheet (Trade Republic style)
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../shared/services/app_localizations.dart';
import 'cultioo_spinner.dart';
import 'trade_republic_bottom_sheet.dart';

/// Shows a full-height dark QR scanner bottom sheet.
///
/// Usage:
/// ```dart
/// await showQRScannerSheet(
///   context: context,
///   controller: myController,
///   onDetect: _onQRCodeDetected,
///   scanSuccessController: _scanSuccessController,
///   scanSuccessScaleAnimation: _scanSuccessScaleAnimation,
///   scanSuccessFadeAnimation: _scanSuccessFadeAnimation,
///   isLoadingNotifier: _isLoadingNotifier,
///   resultNotifier: _resultNotifier,
///   onSheetReady: ({setter, close}) { ... },
/// );
/// ```
Future<void> showQRScannerSheet({
  required BuildContext context,
  required MobileScannerController controller,
  required void Function(BarcodeCapture) onDetect,
  required AnimationController scanSuccessController,
  required Animation<double> scanSuccessScaleAnimation,
  required Animation<double> scanSuccessFadeAnimation,
  /// Notifier for the loading overlay (validating…)
  required ValueNotifier<bool> isLoadingNotifier,
  /// Notifier for the result text ('', '✅ …', '❌ …')
  required ValueNotifier<String> resultNotifier,
  /// Called once the sheet is built, giving back a StateSetter + close cb
  void Function({
    required StateSetter setter,
    required VoidCallback close,
  })? onSheetReady,
}) async {
  // Pre-create close callback so callers can dismiss the sheet programmatically
  final nav = Navigator.of(context);
  void close() { try { nav.pop(); } catch (_) {} }
  onSheetReady?.call(setter: (_) {}, close: close);

  await TradeRepublicBottomSheet.show(
    context: context,
    showDragHandle: true,
    isDismissible: true,
    enableDrag: true,
    child: _QRScannerSheetContent(
      controller: controller,
      onDetect: onDetect,
      scanSuccessController: scanSuccessController,
      scanSuccessScaleAnimation: scanSuccessScaleAnimation,
      scanSuccessFadeAnimation: scanSuccessFadeAnimation,
      isLoadingNotifier: isLoadingNotifier,
      resultNotifier: resultNotifier));
}

// ─── Internal full-screen sheet content ──────────────────────────────────────

class _QRScannerSheetContent extends StatelessWidget {
  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final AnimationController scanSuccessController;
  final Animation<double> scanSuccessScaleAnimation;
  final Animation<double> scanSuccessFadeAnimation;
  final ValueNotifier<bool> isLoadingNotifier;
  final ValueNotifier<String> resultNotifier;

  const _QRScannerSheetContent({
    required this.controller,
    required this.onDetect,
    required this.scanSuccessController,
    required this.scanSuccessScaleAnimation,
    required this.scanSuccessFadeAnimation,
    required this.isLoadingNotifier,
    required this.resultNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            // ── Title row ────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12)),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                    size: 20)),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.openQrScanner ?? 'Scan QR Code',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      fontFamily: 'Poppins'))),
              ]),
            SizedBox(height: 16),

            // ── Camera + overlays ─────────────────────────────────────
            SizedBox(
              height: screenH * 0.52,
              child: Padding(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      scanSuccessController,
                      isLoadingNotifier,
                      resultNotifier,
                    ]),
                    builder: (ctx, _) {
                      final isLoading  = isLoadingNotifier.value;
                      final result     = resultNotifier.value;
                      final isSuccess  =
                          scanSuccessController.status == AnimationStatus.forward ||
                          scanSuccessController.status == AnimationStatus.completed;
                      final isIdle     = !isLoading && result.isEmpty && !isSuccess;

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          // Camera feed
                          Container(
                            color: Colors.black,
                            child: MobileScanner(
                              controller: controller,
                              onDetect: onDetect)),

                          // Vignette
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment.center,
                                  radius: 1.1,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.45),
                                  ])))),

                          // Scan-frame corners (idle state)
                          if (isIdle)
                            Center(
                              child: SizedBox(
                                width: 240, height: 240,
                                child: CustomPaint(painter: _ScanFramePainter()))),

                          // Validating overlay
                          if (isLoading && !isSuccess)
                            Container(
                              color: Colors.black.withOpacity(0.75),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CultiooLoadingIndicator(size: 28),
                                    SizedBox(height: 16),
                                    Text(
                                      AppLocalizations.of(ctx)?.validating ?? 'Validating...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600)),
                                  ]))),

                          // Success animation overlay
                          if (isSuccess)
                            Container(
                              color: Colors.black.withOpacity(
                                0.65 * scanSuccessFadeAnimation.value),
                              child: Center(
                                child: Transform.scale(
                                  scale: scanSuccessScaleAnimation.value,
                                  child: Container(
                                    width: 100, height: 100,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFFFF),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFFFFFF).withOpacity(0.35),
                                          blurRadius: 32,
                                          spreadRadius: 8),
                                      ]),
                                    child: Icon(
                                      Icons.check_rounded,
                                      color: Colors.black,
                                      size: 58))))),

                          // Error / success result pill
                          if (result.isNotEmpty && !isSuccess)
                            Positioned(
                              bottom: 20, left: 20, right: 20,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                                decoration: BoxDecoration(
                                  color: result.startsWith('❌')
                                      ? Colors.black.withOpacity(0.90)
                                      : Colors.white.withOpacity(0.90),
                                  borderRadius: BorderRadius.circular(16)),
                                child: Text(
                                  result,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: result.startsWith('❌')
                                        ? Colors.white
                                        : Colors.black,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)))),
                        ]);
                    })))),

            // ── Instruction ──────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(0, 16, 0, 4),
              child: Text(
                AppLocalizations.of(context)?.scanQrCodeFromBusiness ??
                    'Hold the QR code in front of the camera',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black).withOpacity(0.35),
                  fontSize: 14,
                  fontWeight: FontWeight.w500))),
          ]);
  }
}

// ─── Scan-frame corner painter ────────────────────────────────────────────────

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const c = 30.0; // arm length
    const r = 6.0;  // arc radius (unused — kept for symmetry)

    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x + dx * r, y), Offset(x + dx * c, y), paint);
      canvas.drawLine(Offset(x, y + dy * r), Offset(x, y + dy * c), paint);
    }

    corner(0, 0, 1, 1);
    corner(size.width, 0, -1, 1);
    corner(0, size.height, 1, -1);
    corner(size.width, size.height, -1, -1);
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) => false;
}
