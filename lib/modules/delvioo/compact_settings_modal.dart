import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../shared/services/app_settings.dart';
import '../../shared/services/app_localizations.dart';

import '../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../shared/widgets/trade_republic_slider.dart';
import '../../shared/widgets/drag_handle.dart';
import '../../shared/widgets/trade_republic_tap.dart';

void showCompactSettingsModal(
  BuildContext context,
  double currentRadius,
  Function(double) onRadiusChanged,
) {
  double tempSearchRadius = currentRadius;

  TradeRepublicBottomSheet.show(
    context: context,
    bottomPadding: 20.0,
    child: StatefulBuilder(
      builder: (context, setModalState) {
        final isLight = Theme.of(context).brightness == Brightness.light;

        return SizedBox(
          height: 280, // Very compact
          child: Column(
            children: [
              // Kompakter Header
              DragHandle(),
              Padding(
                padding: const EdgeInsets.all(0),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.slider_horizontal_3,
                      color: isLight ? Colors.black : Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)?.mapSettings ?? 'Map Settings',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                    // Close Button
                    TradeRepublicTap(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFFFF5F56), // macOS red close button top
                              Color(
                                0xFFE74C3C,
                              ), // macOS red close button bottom
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            CupertinoIcons.xmark,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Search Radius Slider - very compact
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Consumer<AppSettings>(
                      builder: (context, appSettings, _) => Text(
                        '${AppLocalizations.of(context)?.searchRadius ?? "Search Radius"}: ${appSettings.formatDistance(tempSearchRadius.toDouble())}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isLight ? Colors.black87 : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Consumer<AppSettings>(
                      builder: (context, appSettings, _) =>
                          TradeRepublicContinuousSlider(
                        value: tempSearchRadius,
                        min: 1.0,
                        max: 50.0,
                        divisions: 49,
                        labelBuilder: (v) => appSettings.formatDistance(v),
                        onChanged: (v) =>
                            setModalState(() => tempSearchRadius = v),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 20),

              // Buttons - kompakt
              Row(
                  children: [
                    const Spacer(),
                    const SizedBox(width: 16),
                    const Spacer(),
                  ],
                ),
            ],
          ),
        );
      },
    ),
  );
}
