import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/two_factor_service.dart';
import '../services/app_localizations.dart';
import '../widgets/drag_handle.dart';
import '../widgets/trade_republic_text_field.dart';
import '../widgets/trade_republic_button.dart';
import '../widgets/top_notification.dart';

import '../../shared/widgets/trade_republic_bottom_sheet.dart';

class TwoFactorSetupBottomSheet extends StatefulWidget {
  final bool isEnabled;
  final VoidCallback? onSuccess;

  const TwoFactorSetupBottomSheet({
    super.key,
    required this.isEnabled,
    this.onSuccess,
  });

  @override
  _TwoFactorSetupBottomSheetState createState() =>
      _TwoFactorSetupBottomSheetState();

  static Future<void> show(
    BuildContext context, {
    required bool isEnabled,
    VoidCallback? onSuccess,
  }) async {
    await TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: true,
      child: TwoFactorSetupBottomSheet(
        isEnabled: isEnabled,
        onSuccess: onSuccess));
  }
}

class _TwoFactorSetupBottomSheetState extends State<TwoFactorSetupBottomSheet> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.isEnabled) {
      _loadCurrentCode();
    }
  }

  Future<void> _loadCurrentCode() async {
    final currentCode = await TwoFactorService.getLocalTwoFactorCode();
    if (currentCode != null && mounted) {
      setState(() {
        _codeController.text = currentCode;
      });
    }
  }

  Future<void> _handleSubmit() async {
    if (_codeController.text.length != 8) {
      setState(() {
        _errorMessage = 'Code must be exactly 8 digits';
      });
      return;
    }

    // Validate that code contains only numbers
    if (!RegExp(r'^\d{8}$').hasMatch(_codeController.text)) {
      setState(() {
        _errorMessage = 'Code must contain only numbers (0-9)';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    Map<String, dynamic> result;

    if (widget.isEnabled) {
      // Update existing code
      result = await TwoFactorService.updateTwoFactorCode(_codeController.text);
    } else {
      // Enable 2FA with new code
      result = await TwoFactorService.enableTwoFactor(_codeController.text);
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (result['success'] == true) {
        // Show success message
        TopNotification.success(context, result['message']);

        // Close bottom sheet and notify parent
        Navigator.of(context).pop(true);
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        }
      } else {
        setState(() {
          _errorMessage = result['message'];
        });
      }
    }
  }

  Future<void> _handleDisable() async {
    final isLight = Theme.of(context).brightness == Brightness.light;

    // Show confirmation bottom sheet
    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      enableDrag: true,
      isDismissible: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DragHandle(),
          Row(
            children: [
              Icon(CupertinoIcons.shield, size: 22),
              SizedBox(width: 12),
              const Flexible(child: Text(
                'Disable Two-Factor Authentication',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4))),
            ]),
          SizedBox(height: 12),
          // Content
          Text(
            'Are you sure you want to disable two-factor authentication?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black.withOpacity(0.5))),
          SizedBox(height: 24),
          // Buttons
          Row(
            children: [
              Expanded(child: Container()),
              SizedBox(width: 16),
              Expanded(child: Container()),
            ]),
          SizedBox(height: 16),
        ]));

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await TwoFactorService.disableTwoFactor();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result['success'] == true) {
          TopNotification.success(context, result['message']);

          Navigator.of(context).pop(true);
          if (widget.onSuccess != null) {
            widget.onSuccess!();
          }
        } else {
          setState(() {
            _errorMessage = result['message'];
          });
        }
      }
    }
  }

  String _generateRandomCode() {
    return TwoFactorService.generateRandomCode();
  }

  void _useRandomCode() {
    setState(() {
      _codeController.text = _generateRandomCode();
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DragHandle(),

        // Header
        Row(
          children: [
            Icon(
              Icons.security,
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.black
                  : Colors.white,
              size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isEnabled
                        ? AppLocalizations.of(context)?.change2FACode ?? 'Change 2FA Code'
                        : AppLocalizations.of(context)?.enableTwoFactorAuth ?? 'Enable Two-Factor Authentication',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  Text(
                    'Enter an 8-digit numeric code',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withOpacity(0.5))),
                ])),
            TradeRepublicButton.icon(
              icon: Icon(Icons.close, size: 20),
              size: 36,
              isSecondary: true,
              onPressed: () => Navigator.of(context).pop()),
          ]),

        SizedBox(height: 24),

        // Code input field
        TradeRepublicTextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          hintText: '12345678',
          textAlign: TextAlign.center,
          onChanged: (value) {
            if (_errorMessage != null) {
              setState(() {
                _errorMessage = null;
              });
            }
          }),

        if (_errorMessage != null) ...[
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.white))),
              ])),
        ],

        SizedBox(height: 24),

        // Info box
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.black.withOpacity(0.05)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                    size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Important Notes:',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white)),
                ]),
              SizedBox(height: 8),
              Text(
                '• Code must be exactly 8 digits (0-9 only)\n'
                '• Remember this code well\n'
                '• You will need it for every login\n'
                '• Use the refresh button to generate a random code',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black.withOpacity(0.7)
                      : Colors.white.withOpacity(0.7))),
            ])),

        SizedBox(height: 24),

        // Action buttons
        Row(
          children: [
            if (widget.isEnabled) ...[
              const Spacer(),
              SizedBox(width: 12),
            ],
            const Spacer(),
          ]),
      ]);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
