import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/app_localizations.dart';
import '../services/biometric_auth_service.dart';
import '../widgets/trade_republic_bottom_sheet.dart';
import '../widgets/trade_republic_button.dart';
import '../../shared/widgets/cultioo_spinner.dart';

class AuthenticationWrapper extends StatefulWidget {
  final Widget child;

  const AuthenticationWrapper({super.key, required this.child});

  @override
  State<AuthenticationWrapper> createState() => _AuthenticationWrapperState();
}

class _AuthenticationWrapperState extends State<AuthenticationWrapper> {
  bool _isAuthenticated = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    // Check if authentication is bypassed (user already authenticated this session)
    final bool isBypassed = await BiometricAuthService.isAuthBypassed();

    if (isBypassed) {
      setState(() {
        _isAuthenticated = true;
        _isLoading = false;
      });
      return;
    }

    // Check what authentication method should be used
    final String authMethod =
        await BiometricAuthService.getAuthenticationMethod();

    setState(() {
      _isLoading = false;
    });

    // If no authentication is set up, allow access
    if (authMethod == 'password') {
      // For now, if only password is available and no specific setup, allow access
      // In production, you might want to always require some form of authentication
      setState(() {
        _isAuthenticated = true;
      });
      await BiometricAuthService.setAuthBypass(true);
      return;
    }

    // Perform authentication
    await _performAuthentication();
  }

  Future<void> _performAuthentication() async {
    if (!mounted) return;

    final bool success = await BiometricAuthService.authenticate(context);

    if (success) {
      setState(() {
        _isAuthenticated = true;
      });
      await BiometricAuthService.setAuthBypass(true);
    } else {
      // If authentication fails, show retry option
      _showAuthenticationFailedDialog();
    }
  }

  void _showAuthenticationFailedDialog() {
    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      enableDrag: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.lock_shield, size: 48, color: Colors.white),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(context)?.authenticationFailed ?? 'Authentication Failed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 12),
          Text(AppLocalizations.of(context)?.authenticationRequiredToAccessApp ?? 'Authentication is required to access the app.', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: TradeRepublicButton(label: AppLocalizations.of(context)?.retry ?? 'Retry', onPressed: () {
            Navigator.of(context).pop();
            _performAuthentication();
          })),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: TradeRepublicButton(label: AppLocalizations.of(context)?.exit ?? 'Exit', isDestructive: true, onPressed: () {
            Navigator.of(context).pop();
          })),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.security,
                  size: 64,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)?.initializingSecurity ?? 'Initializing Security',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              CultiooLoadingIndicator(),
            ],
          ),
        ),
      );
    }

    if (!_isAuthenticated) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.lock, size: 64, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)?.authenticationRequired ?? 'Authentication Required',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TradeRepublicButton(
                label: AppLocalizations.of(context)?.authenticate ?? 'Authenticate',
                onPressed: _performAuthentication,
                icon: const Icon(Icons.fingerprint),
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}
