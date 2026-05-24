import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_switch.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../config/api_config.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/trade_republic_tap.dart';

class DriverStep7Consent extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final Map<String, dynamic> initialData;

  const DriverStep7Consent({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.initialData,
  });

  @override
  State<DriverStep7Consent> createState() => _DriverStep7ConsentState();
}

class _DriverStep7ConsentState extends State<DriverStep7Consent> {
  // Stripe Tax Information State
  bool _isLoadingStripe = false;
  String? _stripeAccountId; // Stripe Connected Account ID for 1099 generation
  String? _taxFormStatus; // 'pending', 'completed'
  String? _taxFormUrl; // URL to Stripe Tax Form

  // Form State
  bool _agreeTerms = false;

  // Validation
  bool _formValid = false;
  final _formKey = GlobalKey<FormState>();

  // Check if selected country is USA (requires W-8/W-9)
  bool get _isUSCountry {
    final country = widget.initialData['country']?.toString() ?? '';
    return country == 'United States' || country == 'USA';
  }

  // Get country name for display
  String get _selectedCountry {
    return widget.initialData['country']?.toString() ??
        (AppLocalizations.of(context)?.unknown ?? '');
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _validateForm();
  }

  void _loadInitialData() {
    // Load existing Stripe data if any
    _stripeAccountId = widget.initialData['stripeAccountId']?.toString();
    _taxFormStatus =
        widget.initialData['taxFormStatus']?.toString() ?? 'pending';
    _taxFormUrl = widget.initialData['taxFormUrl']?.toString();
    _agreeTerms = widget.initialData['agreeTerms'] == true;
  }

  void _validateForm() {
    setState(() {
      if (_isUSCountry) {
        // US requires Stripe tax form (W-8/W-9) completion
        _formValid = _taxFormStatus == 'completed' && _agreeTerms;
      } else {
        // Non-US countries: Only need to agree to terms
        _formValid = _agreeTerms;
      }
    });
  }

  // Create Stripe Tax Collection Session
  Future<void> _createStripeTaxSession() async {
    setState(() {
      _isLoadingStripe = true;
      // Reset old session data to force new session creation
      _taxFormUrl = null;
      _stripeAccountId = null;
      _taxFormStatus = 'pending';
    });

    try {
      print('📤 Creating Stripe Tax Collection Session...');

      // Use ApiConfig for consistent backend URL
      final String baseUrl = ApiConfig.baseUrl;
      final uri = Uri.parse('$baseUrl/api/stripe/create-tax-session');

      // Get user data from Step 1
      final email = widget.initialData['email'] ?? '';
      final firstName = widget.initialData['firstName'] ?? '';
      final lastName = widget.initialData['lastName'] ?? '';
        final country = widget.initialData['country'] ??
          (AppLocalizations.of(context)?.unitedStates ?? '');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'firstName': firstName,
          'lastName': lastName,
          'country': country,
        }));

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          final String sessionUrl = responseData['data']['url'];
          final String accountId = responseData['data']['accountId'];

          setState(() {
            _taxFormUrl = sessionUrl;
            _stripeAccountId = accountId;
            _taxFormStatus = 'pending';
          });

          // Save to initialData
          widget.initialData['stripeAccountId'] = accountId;
          widget.initialData['taxFormUrl'] = sessionUrl;
          widget.initialData['taxFormStatus'] = 'pending';

          print('✅ Stripe session created: $sessionUrl');

          // Open Stripe Tax Form in browser
          await _openStripeTaxForm(sessionUrl);
        } else {
          throw Exception(
            responseData['message'] ??
                (AppLocalizations.of(context)?.failedToCreateSession ?? ''));
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error creating Stripe session: $e');

      TopNotification.show(
        context,
        message: AppLocalizations.of(context)?.failedToCreateTaxForm ?? 'Failed to create tax form. Please try again.',
        type: NotificationType.error);
    } finally {
      setState(() {
        _isLoadingStripe = false;
      });
    }
  }

  // Open Stripe Tax Form
  Future<void> _openStripeTaxForm(String url) async {
    try {
      print('🌐 Opening tax form URL: $url');

      final Uri uri = Uri.parse(url);

      // Use the same pattern as business_account_page.dart with explicit error handling
      if (await canLaunchUrl(uri)) {
        bool launched = false;

        // Try inAppBrowserView first (SFSafariViewController on iOS, Chrome Custom Tabs on Android)
        try {
          launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
          if (launched) {
            print('✅ Successfully opened with inAppBrowserView');
          }
        } catch (e) {
          print('❌ inAppBrowserView failed: $e');
        }

        // If that failed, fall back to platformDefault
        if (!launched) {
          try {
            launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
            if (launched) {
              print('✅ Successfully opened with platformDefault');
            }
          } catch (e) {
            print('❌ platformDefault failed: $e');
          }
        }

        if (launched) {
          TopNotification.show(
            context,
            message: AppLocalizations.of(context)?.completeTaxFormInBrowser ?? 'Complete the tax form in browser, then return to verify',
            type: NotificationType.info);
        } else {
          print('❌ All launch modes failed, showing manual dialog');
          TopNotification.show(
            context,
            message: AppLocalizations.of(context)?.couldNotOpenBrowserManual ?? 'Could not open browser. Showing manual option.',
            type: NotificationType.warning);
          _showEmbeddedTaxForm(url);
        }
      } else {
        print('❌ Cannot launch URL, showing manual dialog');
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.couldNotOpenBrowser ?? 'Could not open browser',
          type: NotificationType.error);
        _showEmbeddedTaxForm(url);
      }
    } catch (e) {
      print('❌ Error launching URL: $e');
      TopNotification.show(
        context,
        message: '${AppLocalizations.of(context)?.errorOpeningBrowser ?? 'Error opening browser'}: $e',
        type: NotificationType.error);

      // Show bottom sheet with URL that user can copy as fallback
      final bool isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
      TradeRepublicBottomSheet.show(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(AppLocalizations.of(context)?.taxFormUrl ?? 'Tax Form URL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              ]),
            SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(AppLocalizations.of(context)?.pleaseOpenThisUrlInYourBrowser ?? 'Please open this URL in your browser:')),
            SizedBox(height: 10),
            SelectableText(
              url,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace')),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)?.copyUrl ?? 'Copy URL',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  Navigator.of(context).pop();
                  TopNotification.show(
                    context,
                    message: AppLocalizations.of(context)?.urlCopiedToClipboard ?? 'URL copied to clipboard!',
                    type: NotificationType.success);
                })),
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)?.close ?? 'Close',
                isSecondary: true,
                onPressed: () => Navigator.of(context).pop())),
          ]));
    }
  }

  // Verify Tax Form Completion
  Future<void> _verifyTaxFormCompletion() async {
    if (_stripeAccountId == null) {
      TopNotification.show(
        context,
        message: AppLocalizations.of(context)?.pleaseStartTheTaxFormFirst ?? 'Please start the tax form first',
        type: NotificationType.error);
      return;
    }

    setState(() {
      _isLoadingStripe = true;
    });

    try {
      print('🔍 Verifying tax form completion...');

      // Use ApiConfig for consistent backend URL
      final String baseUrl = ApiConfig.baseUrl;
      final uri = Uri.parse(
        '$baseUrl/api/stripe/verify-tax-completion?accountId=$_stripeAccountId');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          final bool isCompleted = responseData['data']['isCompleted'] ?? false;

          setState(() {
            _taxFormStatus = isCompleted ? 'completed' : 'pending';
          });

          widget.initialData['taxFormStatus'] = _taxFormStatus;

          if (isCompleted) {
            TopNotification.show(
              context,
              message: AppLocalizations.of(context)?.taxFormCompletedSuccessfully ?? '✅ Tax form completed successfully!',
              type: NotificationType.success);
            _validateForm();
          } else {
            TopNotification.show(
              context,
              message:
                  'Tax form not yet completed. Please finish it in your browser.',
              type: NotificationType.info);
          }
        }
      }
    } catch (e) {
      print('❌ Error verifying tax form: $e');
      TopNotification.show(
        context,
        message: AppLocalizations.of(context)?.failedToVerifyTaxFormPleaseTryAgain ?? 'Failed to verify tax form. Please try again.',
        type: NotificationType.error);
    } finally {
      setState(() {
        _isLoadingStripe = false;
      });
    }
  }

  // Show embedded WebView as fallback
  void _showEmbeddedTaxForm(String url) {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final bool isLight = appSettings.isLightMode(context);
    // Show bottom sheet with URL that user can copy
    TradeRepublicBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(AppLocalizations.of(context)?.taxForm ?? 'Tax Form', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            ]),
          SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context)?.pleaseOpenUrlInBrowserToCompleteTaxForm ?? 'Please open this URL in your browser to complete the tax form:',
              style: TextStyle(fontSize: 14))),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isLight ? Colors.black : Colors.white).withOpacity(
                0.05),
              borderRadius: BorderRadius.circular(20)),
            child: SelectableText(
              url,
              style: TextStyle(fontSize: 12, fontFamily: 'monospace'))),
          SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context)?.afterCompletingFormReturnHere ?? 'After completing the form, return here and tap "Verify" to continue.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
          SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.copyUrl ?? 'Copy URL',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.of(context).pop();
                TopNotification.show(
                  context,
                  message: AppLocalizations.of(context)?.urlCopiedToClipboardOpenItInSafariChrome ?? 'URL copied to clipboard! Open it in Safari/Chrome',
                  type: NotificationType.success);
              })),
          SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.close ?? 'Close',
              isSecondary: true,
              onPressed: () => Navigator.of(context).pop())),
        ]));
  }

  void _showErrorDialog(String message) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_circle, color: Colors.red),
              SizedBox(width: 8),
              Text(AppLocalizations.of(context)?.error ?? 'Error', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(message)),
          SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.ok ?? 'OK',
              onPressed: () => Navigator.of(context).pop())),
        ]));
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final bool isLight = appSettings.isLightMode(context);

    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          primary: false,
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.of(context).padding.top + 20,
            24,
            MediaQuery.of(context).padding.bottom + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header - Step 1 Style
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isLight ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                      child: Icon(
                        CupertinoIcons.doc_text,
                        color: isLight ? Colors.white : Colors.black,
                        size: 40)),
                    SizedBox(height: 20),
                    Text(
                      AppLocalizations.of(context)?.taxInformation ?? 'Tax Information',
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text(
                      _isUSCountry
                          ? (AppLocalizations.of(context)?.stepSixTaxCompliance ?? 'Step 6 of 9 – Tax compliance')
                          : '${AppLocalizations.of(context)?.stepSixTaxCompliance ?? 'Step 6 of 9 – Tax compliance'} ($_selectedCountry)',
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        fontSize: 16)),
                  ])),

              SizedBox(height: 40),

              // Stripe Tax Compliance Section (US only)
              if (_isUSCountry) ...[
                _buildSectionHeader('Tax Compliance via Stripe', isLight),
                SizedBox(height: 16),
                _buildStripeTaxSection(isLight),
                SizedBox(height: 32),
              ] else ...[
                _buildNonUSTaxSection(isLight),
                SizedBox(height: 32),
              ],

              // Terms Agreement
              _buildConsentItem(
                title: AppLocalizations.of(context)?.termsAgreement ?? 'Terms Agreement',
                description: _isUSCountry
                    ? '${AppLocalizations.of(context)?.iAgreeAccurateTaxInfo ?? 'I agree to provide accurate tax information via Stripe for IRS 1099 reporting.'} '
                    : 'I agree to provide accurate information, comply with local tax regulations in $_selectedCountry, and accept the ',
                value: _agreeTerms,
                onChanged: (value) => setState(() {
                  _agreeTerms = value!;
                  _validateForm();
                }),
                isLight: isLight,
                hasLinks: true),

              SizedBox(height: 40),

              // Navigation Buttons
              Row(
                children: [
                  // Back Button
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: TradeRepublicButton.icon(
                      icon: Icon(CupertinoIcons.chevron_back, size: 18),
                      onPressed: widget.onBack)),

                  SizedBox(width: 12),

                  // Continue Button - Full Width with Gradient
                  Expanded(
                    child: Opacity(
                      opacity: _formValid ? 1.0 : 0.5,
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)?.continueToCompany ?? 'Continue to Company',
                        icon: Icon(CupertinoIcons.arrow_right, size: 18),
                        onPressed: _formValid ? _proceedToVerification : () {}))),
                ]),
            ]))))));
  }

  void _proceedToVerification() {
    if (!_formValid) {
      _showErrorDialog(AppLocalizations.of(context)?.pleaseCompleteTaxFormAndAgree ?? 'Please complete the tax form and agree to terms');
      return;
    }

    // Save tax information based on country
    if (_isUSCountry) {
      // US: Stripe tax form data
      widget.initialData['stripeAccountId'] = _stripeAccountId;
      widget.initialData['taxFormStatus'] = _taxFormStatus;
      widget.initialData['taxFormType'] = 'w9';
      widget.initialData['taxCountry'] = 'United States';
      widget.initialData['taxCurrency'] = 'USD';
    } else {
      // Non-US: Local tax info (auto-completed)
      final taxInfo = _countryTaxInfo;
      widget.initialData['stripeAccountId'] = null;
      widget.initialData['taxFormStatus'] =
          'completed'; // Auto-complete for non-US
      widget.initialData['taxFormType'] = 'local';
      widget.initialData['taxCountry'] = _selectedCountry;
      widget.initialData['taxAuthority'] = taxInfo['authority'];
      widget.initialData['taxIdType'] = taxInfo['taxId'];
      widget.initialData['vatIdType'] = taxInfo['vatId'];
      // Set currency based on country
      widget.initialData['taxCurrency'] = _getCountryCurrency(_selectedCountry);
    }
    widget.initialData['agreeTerms'] = _agreeTerms;

    widget.onNext();
  }

  // Get currency for country
  String _getCountryCurrency(String country) {
    switch (country) {
      case 'United States':
        return 'USD';
      case 'Germany':
      case 'Austria':
      case 'France':
      case 'Italy':
      case 'Spain':
      case 'Netherlands':
        return 'EUR';
      case 'Switzerland':
        return 'CHF';
      case 'Poland':
        return 'PLN';
      case 'United Kingdom':
        return 'GBP';
      default:
        return 'EUR';
    }
  }

  // Stripe Tax Form Section
  Widget _buildStripeTaxSection(bool isLight) {
    if (_taxFormStatus == 'completed') {
      // Tax form is completed - Modern success design
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green.withOpacity(0.15),
              Colors.teal.withOpacity(0.1),
            ])),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with success animation
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C853), Color(0xFF4CAF50)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)),
                  child: Icon(
                    CupertinoIcons.checkmark_seal,
                    color: Colors.white,
                    size: 28)),
                SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.taxInformationComplete ?? 'Tax Information Complete',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4)),
                      SizedBox(height: 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          AppLocalizations.of(context)?.verifiedByStripe ?? 'Verified by Stripe',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2))),
                    ])),
              ]),

            SizedBox(height: 24),

            // Benefits section
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isLight
                    ? Colors.black.withOpacity(0.05)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  _buildCompletionBenefit(
                    icon: CupertinoIcons.doc_text,
                    title: AppLocalizations.of(context)?.formsReady1099 ?? '1099 Forms Ready',
                    subtitle: AppLocalizations.of(context)?.automaticYearEndTaxDocumentGeneration ?? 'Automatic year-end tax document generation',
                    isLight: isLight),
                  SizedBox(height: 16),
                  _buildCompletionBenefit(
                    icon: CupertinoIcons.lock_shield,
                    title: AppLocalizations.of(context)?.secureTaxStorage ?? 'Secure Tax Storage',
                    subtitle: AppLocalizations.of(context)?.yourInformationIsSafelyEncryptedByStripe ?? 'Your information is safely encrypted by Stripe',
                    isLight: isLight),
                  SizedBox(height: 16),
                  _buildCompletionBenefit(
                    icon: CupertinoIcons.mail,
                    title: AppLocalizations.of(context)?.emailDelivery ?? 'Email Delivery',
                    subtitle: AppLocalizations.of(context)?.taxFormsDeliveredDirectlyToYourInbox ?? 'Tax forms delivered directly to your inbox',
                    isLight: isLight),
                ])),

            SizedBox(height: 20),

            // Status footer
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    Colors.green.withOpacity(0.1),
                    Colors.teal.withOpacity(0.05),
                  ])),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                      shape: BoxShape.circle)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.irsCompliantAndReady ?? 'IRS compliant and ready for earnings tracking',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 14,
                        fontWeight: FontWeight.w500))),
                  Icon(
                    CupertinoIcons.check_mark_circled,
                    color: Colors.green,
                    size: 20),
                ])),
          ]));
    } else if (_taxFormStatus == 'pending' && _taxFormUrl != null) {
      // Tax form in progress - Beautiful modern design
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.withOpacity(0.1),
              Colors.purple.withOpacity(0.1),
            ])),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with animated icon
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Colors.blue, Colors.purple],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)),
                  child: Icon(
                    CupertinoIcons.hourglass,
                    color: Colors.white,
                    size: 24)),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.taxFormInProgress ?? 'Tax Form In Progress',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3)),
                      SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context)?.stripeConnectSessionActive ?? 'Stripe Connect Session Active',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                    ])),
              ]),

            SizedBox(height: 20),

            // Progress indicator
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isLight
                    ? Colors.black.withOpacity(0.05)
                    : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(20)),
                        child: Icon(
                          CupertinoIcons.globe,
                          color: Colors.white,
                          size: 18)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)?.completeTaxFormInBrowser ?? 'Complete the tax form in your browser',
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500))),
                    ]),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20)),
                        child: Icon(
                          CupertinoIcons.device_phone_portrait,
                          color: Colors.white,
                          size: 18)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Return here and tap "Verify" to continue',
                          style: TextStyle(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.5),
                            fontSize: 15))),
                    ]),
                ])),

            SizedBox(height: 20),

            // Action buttons with better spacing
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20)),
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.restart ?? 'Restart',
                      icon: Icon(CupertinoIcons.refresh, size: 20),
                      onPressed: _createStripeTaxSession,
                      backgroundColor: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.05)))),
                SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Colors.blue, Colors.purple],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight)),
                    child: TradeRepublicButton(
                      label: _isLoadingStripe ? 'Checking...' : AppLocalizations.of(context)?.verify ?? 'Verify',
                      icon: Icon(CupertinoIcons.checkmark_seal, size: 20),
                      onPressed: _isLoadingStripe
                          ? null
                          : _verifyTaxFormCompletion,
                      backgroundColor: Colors.transparent))),
              ]),
          ]));
    } else {
      // No tax form started yet
      return Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                  child: Icon(
                    CupertinoIcons.building_2_fill,
                    color: isLight ? Colors.white : Colors.black,
                    size: 24)),
                SizedBox(width: 15),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.irsTaxInformation ?? 'IRS Tax Information',
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700))),
              ]),
            SizedBox(height: 15),
            Text(
              'To comply with IRS regulations, we collect your tax information via Stripe. This enables:',
              style: TextStyle(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                fontSize: 14)),
            SizedBox(height: 12),
            _buildInfoBullet(
              'Automatic 1099 form generation at year-end',
              isLight),
            _buildInfoBullet('Secure tax data storage by Stripe', isLight),
            _buildInfoBullet(
              'IRS compliance for gig economy payments',
              isLight),
            _buildInfoBullet(
              AppLocalizations.of(context)?.automaticTaxFormDelivery ?? 'Automatic tax form delivery to your email',
              isLight),
            SizedBox(height: 15),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  Icon(CupertinoIcons.info, color: Colors.blue, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You will complete W-9 (US) or W-8 (foreign) form securely via Stripe.',
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        fontSize: 13))),
                ])),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TradeRepublicButton(
                label: _isLoadingStripe
                    ? AppLocalizations.of(context)?.creatingSession ?? 'Creating Session…'
                    : 'Start Tax Form with Stripe',
                icon: Icon(CupertinoIcons.doc_text, size: 20),
                onPressed: _isLoadingStripe ? null : _createStripeTaxSession)),
          ]));
    }
  }

  Widget _buildInfoBullet(String text, bool isLight) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•  ',
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                fontSize: 14))),
        ]));
  }

  Widget _buildCompletionBenefit({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLight,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20)),
          child: Icon(icon, color: Colors.green.shade600, size: 20)),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2)),
              SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.5),
                  fontSize: 13,
                  letterSpacing: -0.1)),
            ])),
        Icon(
          CupertinoIcons.check_mark_circled,
          color: Colors.green.shade400,
          size: 18),
      ]);
  }

  // Get country-specific tax info
  Map<String, dynamic> get _countryTaxInfo {
    switch (_selectedCountry) {
      case 'Germany':
        return {
          'emoji': '🇩🇪',
          'authority': 'Tax Office (Finanzamt)',
          'taxId': 'Tax Number (Steuernummer)',
          'vatId': 'VAT ID (USt-IdNr)',
          'requirements': [
            'Register with tax office as self-employed',
            AppLocalizations.of(context)?.applyForTaxNumber ?? 'Apply for tax number',
            AppLocalizations.of(context)?.reportIncomeInTaxReturn ?? 'Report income in annual tax return',
            'VAT required if revenue exceeds 22,000{currencySymbol}/year',
            'Small business exemption (§19 UStG) available',
          ],
          'note':
              'We recommend a tax advisor for small business regulations and VAT.',
        };
      case 'Austria':
        return {
          'emoji': '🇦🇹',
          'authority': 'Tax Office Austria (Finanzamt)',
          'taxId': 'Tax Number (Steuernummer)',
          'vatId': 'VAT ID (UID-Nummer)',
          'requirements': [
            'Register with tax office as self-employed',
            AppLocalizations.of(context)?.applyForTaxNumber ?? 'Apply for tax number',
            AppLocalizations.of(context)?.reportIncomeInTaxReturn ?? 'Report income in annual tax return',
            'VAT required if revenue exceeds 35,000{currencySymbol}/year',
            AppLocalizations.of(context)?.smallBusinessExemption ?? 'Small business exemption available',
          ],
          'note': 'We recommend a tax advisor for Austrian tax regulations.',
        };
      case 'Switzerland':
        return {
          'emoji': '🇨🇭',
          'authority': 'Cantonal Tax Administration',
          'taxId': 'AHV Number (Social Security)',
          'vatId': 'VAT Number (MWST)',
          'requirements': [
            AppLocalizations.of(context)?.registerWithCantonalTax ?? 'Register with cantonal tax administration',
            'Pay AHV contributions as self-employed',
            'VAT required if revenue exceeds {currencySymbol} 100,000/year',
            AppLocalizations.of(context)?.reportIncomeInTaxReturn ?? 'Report income in annual tax return',
            'Consider occupational pension (BVG)',
          ],
          'note': 'We recommend a fiduciary for cantonal tax regulations.',
        };
      case 'France':
        return {
          'emoji': '🇫🇷',
          'authority': 'Tax Authority (DGFIP)',
          'taxId': 'SIRET Number',
          'vatId': 'EU VAT Number',
          'requirements': [
            'Register as auto-entrepreneur or micro-entrepreneur',
            AppLocalizations.of(context)?.quarterlyUrssaf ?? 'Quarterly or monthly URSSAF declaration',
            AppLocalizations.of(context)?.annualIncomeTax ?? 'Annual income tax declaration',
            'VAT exempt up to 34,400{currencySymbol}/year (services)',
            'Social contributions at 22% of revenue',
          ],
          'note':
              'We recommend an accountant for micro-entrepreneur regulations.',
        };
      case 'Italy':
        return {
          'emoji': '🇮🇹',
          'authority': 'Revenue Agency (Agenzia delle Entrate)',
          'taxId': 'Tax Code (Codice Fiscale)',
          'vatId': 'VAT Number (Partita IVA)',
          'requirements': [
            AppLocalizations.of(context)?.openVatNumber ?? 'Open VAT number at Revenue Agency',
            AppLocalizations.of(context)?.registerInps ?? 'Register with INPS social security',
            'Flat-rate regime available up to 85,000{currencySymbol}/year',
            AppLocalizations.of(context)?.electronicInvoicing ?? 'Electronic invoicing mandatory',
            AppLocalizations.of(context)?.annualIncomeTax ?? 'Annual income tax declaration',
          ],
          'note':
              'We recommend an accountant for flat-rate regime and invoicing.',
        };
      case 'Spain':
        return {
          'emoji': '🇪🇸',
          'authority': 'Tax Agency (Agencia Tributaria)',
          'taxId': 'Tax ID (NIF)',
          'vatId': AppLocalizations.of(context)?.vatNumber ?? 'VAT Number',
          'requirements': [
            'Register as self-employed (Form 036/037)',
            'Register with Social Security (RETA)',
            'Quarterly VAT declaration (Form 303)',
            'Quarterly income tax declaration (Form 130)',
            'Monthly self-employed contribution',
          ],
          'note': 'We recommend a tax advisor for quarterly declarations.',
        };
      case 'Netherlands':
        return {
          'emoji': '🇳🇱',
          'authority': 'Tax Authority (Belastingdienst)',
          'taxId': 'Citizen Service Number (BSN)',
          'vatId': 'VAT Number (BTW)',
          'requirements': [
            'Register with Chamber of Commerce (KvK)',
            AppLocalizations.of(context)?.applyForVatNumber ?? 'Apply for VAT number at Tax Authority',
            'Small business scheme (KOR) available',
            AppLocalizations.of(context)?.annualIncomeTax ?? 'Annual income tax declaration',
            AppLocalizations.of(context)?.quarterlyVatDeclaration ?? 'Quarterly VAT declaration',
          ],
          'note': 'We recommend a bookkeeper for small business regulations.',
        };
      case 'Poland':
        return {
          'emoji': '🇵🇱',
          'authority': 'Tax Office (Urząd Skarbowy)',
          'taxId': 'Tax ID (NIP)',
          'vatId': AppLocalizations.of(context)?.vatNumber ?? 'VAT Number',
          'requirements': [
            AppLocalizations.of(context)?.registerBusinessCeidg ?? 'Register business in CEIDG',
            AppLocalizations.of(context)?.obtainNipTaxNumber ?? 'Obtain NIP tax number',
            AppLocalizations.of(context)?.payZusSocialSecurity ?? 'Pay ZUS social security contributions',
            'VAT exempt up to PLN 200,000/year',
            AppLocalizations.of(context)?.annualPitReturn ?? 'Annual PIT tax return',
          ],
          'note':
              'We recommend consulting an accountant for flat-rate taxation.',
        };
      case 'United Kingdom':
        return {
          'emoji': '🇬🇧',
          'authority': 'HMRC (Her Majesty\'s Revenue and Customs)',
          'taxId': 'UTR (Unique Taxpayer Reference)',
          'vatId': 'VAT Registration Number',
          'requirements': [
            'Register as self-employed with HMRC',
            AppLocalizations.of(context)?.getUtrNumber ?? 'Get a UTR number',
            AppLocalizations.of(context)?.fileSelfAssessment ?? 'File Self Assessment tax return annually',
            'Pay Class 2 and Class 4 National Insurance',
            'VAT registration required over 85,000{currencySymbol}/year',
          ],
          'note':
              'We recommend an accountant for Self Assessment and Making Tax Digital.',
        };
      default:
        return {
          'emoji': '🌍',
          'authority': 'Local Tax Authority',
          'taxId': AppLocalizations.of(context)?.taxId ?? 'Tax ID',
          'vatId': AppLocalizations.of(context)?.vatNumber ?? 'VAT Number',
          'requirements': [
            'Register as self-employed with local tax authority',
            AppLocalizations.of(context)?.reportEarningsForTax ?? 'Report your earnings for income tax',
            AppLocalizations.of(context)?.maintainAccountingRecords ?? 'Maintain proper accounting records',
            AppLocalizations.of(context)?.payApplicableTaxes ?? 'Pay applicable taxes in your country',
            AppLocalizations.of(context)?.provideValidInvoices ?? 'Provide valid invoices when required',
          ],
          'note':
              'We recommend consulting a local tax advisor for specific requirements.',
        };
    }
  }

  // Non-US Tax Section (EU and other countries)
  Widget _buildNonUSTaxSection(bool isLight) {
    final taxInfo = _countryTaxInfo;
    final requirements = taxInfo['requirements'] as List<String>;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
                child: Center(
                  child: Text(
                    taxInfo['emoji'] as String,
                    style: TextStyle(fontSize: 24)))),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.taxInformation ?? 'Tax Information',
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text(
                      _selectedCountry,
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                  ])),
            ]),
          SizedBox(height: 20),

          // Tax Authority Info
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.building_2_fill,
                      color: Colors.blue,
                      size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        taxInfo['authority'] as String,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600))),
                  ]),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.taxId ?? 'Tax ID',
                            style: TextStyle(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.5),
                              fontSize: 12)),
                          SizedBox(height: 2),
                          Text(
                            taxInfo['taxId'] as String,
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                        ])),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.vatId ?? 'VAT ID',
                            style: TextStyle(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.5),
                              fontSize: 12)),
                          SizedBox(height: 2),
                          Text(
                            taxInfo['vatId'] as String,
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                        ])),
                  ]),
              ])),

          SizedBox(height: 20),

          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.checkmark_seal,
                  color: Colors.green,
                  size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No US W-8/W-9 tax form required',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 15,
                      fontWeight: FontWeight.w500))),
              ])),

          SizedBox(height: 20),

          Text(
            'Requirements in $_selectedCountry:',
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600)),
          SizedBox(height: 12),

          ...requirements.map((req) => _buildInfoBullet(req, isLight)),

          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(CupertinoIcons.lightbulb, color: Colors.orange, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    taxInfo['note'] as String,
                    style: TextStyle(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.7),
                      fontSize: 13))),
              ])),
        ]));
  }

  // Section Header
  Widget _buildSectionHeader(String title, bool isLight) {
    return Padding(
      padding: EdgeInsets.only(left: 4, bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isLight ? Colors.black : Colors.white)));
  }

  Widget _buildConsentItem({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool?> onChanged,
    required bool isLight,
    bool hasLinks = false,
  }) {
    return TradeRepublicTap(
      onTap: () => onChanged(!value),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: value
              ? Colors.green.withOpacity(0.08)
              : (isLight ? Colors.white : Colors.black),
          borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white)),
                  SizedBox(height: 4),
                  if (hasLinks)
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 14,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.7)),
                        children: [
                          TextSpan(text: description),
                          TextSpan(
                            text: AppLocalizations.of(context)?.termsConditions ?? 'Terms & Conditions',
                            style: TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () async {
                                final url = Uri.parse(
                                  'https://cultioo.com/us/us_legal_app#delvioo_terms');
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(
                                    url,
                                    mode: LaunchMode.inAppBrowserView);
                                }
                              }),
                          TextSpan(text: ' and '),
                          TextSpan(
                            text: AppLocalizations.of(context)?.privacyPolicy ?? 'Privacy Policy',
                            style: TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () async {
                                final url = Uri.parse(
                                  'https://cultioo.com/us/us_legal_app#delvioo_privacy');
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(
                                    url,
                                    mode: LaunchMode.inAppBrowserView);
                                }
                              }),
                          TextSpan(text: '.'),
                        ]))
                  else
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.7))),
                ])),
            SizedBox(width: 16),
            TradeRepublicSwitch(
              value: value,
              onChanged: (val) => onChanged(val),
              selectedLabel: 'Y',
              unselectedLabel: 'N'),
          ])));
  }
}
