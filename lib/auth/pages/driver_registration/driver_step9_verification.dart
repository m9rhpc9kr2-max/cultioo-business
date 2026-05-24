import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import '../../../shared/services/app_settings.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import '../../../shared/widgets/trade_republic_switch.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../config/api_config.dart';
import 'legal_info_bottom_sheet.dart';
import 'driver_step10_success.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';

// Uppercase Text Input Formatter
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class DriverStep9Verification extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const DriverStep9Verification({
    super.key,
    required this.initialData,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<DriverStep9Verification> createState() =>
      _DriverStep9VerificationState();
}

class _DriverStep9VerificationState extends State<DriverStep9Verification> {
  // Form key for validation
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers for signature
  final TextEditingController _signatureNameController =
      TextEditingController();

  // Agreement checkboxes
  bool _agreeTermsConditions = false;
  bool _agreePrivacyPolicy = false;

  // Current date and time for signature
  late String _currentDateTime;
  late String _currentDate;
  late String _currentTime;

  // Error states
  bool _signatureNameError = false;
  bool _termsError = false;
  bool _privacyError = false;

  @override
  void initState() {
    super.initState();
    _updateDateTime();
    _loadInitialData();
  }

  void _updateDateTime() {
    final now = DateTime.now();
    _currentDateTime = DateFormat('MMMM dd, yyyy - HH:mm:ss').format(now);
    _currentDate = DateFormat('MMMM dd, yyyy').format(now);
    _currentTime = DateFormat('HH:mm:ss').format(now);
  }

  void _loadInitialData() {
    // Don't pre-fill the signature field - user must type it themselves
    // Only load if they're coming back to this step
    _signatureNameController.text =
        widget.initialData['signatureName']?.toString() ?? '';
    _agreeTermsConditions = widget.initialData['agreeTermsConditions'] ?? false;
    _agreePrivacyPolicy = widget.initialData['agreePrivacyPolicy'] ?? false;
  }

  @override
  void dispose() {
    _signatureNameController.dispose();
    super.dispose();
  }

  void _validateAndContinue() async {
    bool isValid = true;

    setState(() {
      _signatureNameError = false;
      _termsError = false;
      _privacyError = false;
    });

    // Get the expected full name from registration
    final String firstName = widget.initialData['firstName']?.toString().trim() ?? '';
    final String lastName = widget.initialData['lastName']?.toString().trim() ?? '';
    final String expectedName = '$firstName $lastName'
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase();
    final String signedName = _signatureNameController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase();

    // Check if signature is empty
    if (signedName.isEmpty) {
      _signatureNameError = true;
      isValid = false;
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterFullNameAsSignature ?? 'Please enter your full name as signature',
        );
      }
    }
    // Check if signature matches the registered name
    else if (signedName != expectedName) {
      _signatureNameError = true;
      isValid = false;
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.signatureMustMatchName ?? 'Signature must match your registered name:'} $expectedName',
        );
      }
    }

    if (!_agreeTermsConditions) {
      _termsError = true;
      isValid = false;
    }

    if (!_agreePrivacyPolicy) {
      _privacyError = true;
      isValid = false;
    }

    if (!isValid) {
      setState(() {});
      return;
    }

    widget.initialData.addAll({
      'signatureName': _signatureNameController.text,
      'signatureDate': _currentDate,
      'signatureTime': _currentTime,
      'signatureDateTime': _currentDateTime,
      'agreeTermsConditions': _agreeTermsConditions,
      'agreePrivacyPolicy': _agreePrivacyPolicy,
      'agreedAt': DateTime.now().toIso8601String(),
    });

    print(
      'DEBUG Step 11: Signature completed - ${_signatureNameController.text}',
    );
    print('DEBUG Step 11: Complete registration data: ${widget.initialData}');

    // Submit registration to backend
    await _submitRegistration();
  }

  Future<void> _submitRegistration() async {
    // Track if dialog is open
    bool isDialogOpen = true;

    // Show loading bottom sheet
    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      enableDrag: false,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CultiooLoadingIndicator(),
          SizedBox(height: 16),
        ],
      ),
    );

    try {
      final String baseUrl = ApiConfig.baseUrl;
      final String apiEndpoint =
          '$baseUrl/api/driver-registration/complete-registration';

      print('DEBUG: Submitting registration to: $apiEndpoint');
      print(
        'DEBUG: isSingleDriver value: ${widget.initialData['isSingleDriver']}',
      );
      print(
        'DEBUG: isSingleDriver type: ${widget.initialData['isSingleDriver'].runtimeType}',
      );

      // Convert date format from MM/DD/YYYY to YYYY-MM-DD for database
      final Map<String, dynamic> registrationData = Map<String, dynamic>.from(
        widget.initialData,
      );

      if (registrationData['birthdate'] != null &&
          registrationData['birthdate'].toString().isNotEmpty) {
        final String birthdate = registrationData['birthdate'].toString();
        // Check if format is MM/DD/YYYY
        if (birthdate.contains('/')) {
          try {
            final parts = birthdate.split('/');
            if (parts.length == 3) {
              // Convert MM/DD/YYYY to YYYY-MM-DD
              final String month = parts[0].padLeft(2, '0');
              final String day = parts[1].padLeft(2, '0');
              final String year = parts[2];
              registrationData['birthdate'] = '$year-$month-$day';
              print(
                'DEBUG: Converted birthdate from $birthdate to ${registrationData['birthdate']}',
              );
            }
          } catch (e) {
            print('DEBUG: Error converting birthdate: $e');
          }
        }
      }

      final response = await http
          .post(
            Uri.parse(apiEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(registrationData),
          )
          .timeout(const Duration(seconds: 30));

      // Close loading dialog safely - only once
      if (isDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: false).pop();
        isDialogOpen = false;
      }

      print('DEBUG: Response status code: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          print('DEBUG: Registration successful!');

          // Navigate to success page (Step 9)
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) =>
                    DriverStep10Success(registrationData: widget.initialData),
              ),
            );
          }
        } else {
          // Parse error message for better user feedback
          String errorMessage =
              responseData['message'] ?? AppLocalizations.of(context)?.registrationFailed ?? 'Registration failed';

          // Check for specific error types
          if (errorMessage.contains('Duplicate entry') &&
              errorMessage.contains('username')) {
            errorMessage =
                AppLocalizations.of(context)?.usernameAlreadyTaken ?? 'This username is already taken. Please choose a different username.';
          } else if (errorMessage.contains('Duplicate entry') &&
              errorMessage.contains('email')) {
            errorMessage =
                AppLocalizations.of(context)?.emailAlreadyRegistered ?? 'This email is already registered. Please use a different email.';
          }

          throw Exception(errorMessage);
        }
      } else {
        // Handle non-200 status codes
        try {
          final Map<String, dynamic> errorData = json.decode(response.body);
          String errorMessage =
              errorData['message'] ?? 'Server error: ${response.statusCode}';

          // Check for specific error types in error responses
          if (errorMessage.contains('Duplicate entry') &&
              errorMessage.contains('username')) {
            errorMessage =
                AppLocalizations.of(context)?.usernameAlreadyTaken ?? 'This username is already taken. Please choose a different username.';
          } else if (errorMessage.contains('Duplicate entry') &&
              errorMessage.contains('email')) {
            errorMessage =
                AppLocalizations.of(context)?.emailAlreadyRegistered ?? 'This email is already registered. Please use a different email.';
          }

          throw Exception(errorMessage);
        } catch (e) {
          if (e is Exception && e.toString().contains('username')) {
            rethrow;
          }
          throw Exception('Server error: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('DEBUG: Registration error: $e');

      // Close loading dialog if still open - ONLY CLOSE THE DIALOG, NOT THE PAGE
      if (isDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: false).pop();
        isDialogOpen = false;
      }

      // Show error message - STAY ON THIS PAGE
      if (mounted) {
        String errorMessage = e.toString();
        if (errorMessage.startsWith('Exception: ')) {
          errorMessage = errorMessage.substring(
            11,
          ); // Remove 'Exception: ' prefix
        }

        TopNotification.error(context, errorMessage);
      }
      // DO NOT navigate away - user stays on Step 8 and can try again
    }
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
            MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isLight ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        CupertinoIcons.checkmark_rectangle,
                        color: isLight ? Colors.white : Colors.black,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.of(context)?.finalVerification ?? 'Final Verification',
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)?.step8ReviewAndSign ?? 'Step 9 of 10 - Review and sign agreements',
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              _buildSectionHeader(AppLocalizations.of(context)?.legalAgreements ?? 'Legal Agreements', isLight),
              const SizedBox(height: 16),
              _buildAgreementCard(
                title: AppLocalizations.of(context)?.termsAndConditions ?? 'Terms and Conditions',
                description:
                    AppLocalizations.of(context)?.iAgreeToTermsAndConditions ?? 'I have read and agree to the Terms and Conditions',
                isAgreed: _agreeTermsConditions,
                hasError: _termsError,
                onTap: () => setState(() {
                  _agreeTermsConditions = !_agreeTermsConditions;
                  _termsError = false;
                }),
                onReadDocument: () =>
                    LegalInfoBottomSheet.show(context, isLight),
                isLight: isLight,
              ),
              const SizedBox(height: 16),
              _buildAgreementCard(
                title: AppLocalizations.of(context)?.privacyPolicy ?? 'Privacy Policy',
                description: AppLocalizations.of(context)?.iAgreeToPrivacyPolicy ?? 'I have read and agree to the Privacy Policy',
                isAgreed: _agreePrivacyPolicy,
                hasError: _privacyError,
                onTap: () => setState(() {
                  _agreePrivacyPolicy = !_agreePrivacyPolicy;
                  _privacyError = false;
                }),
                onReadDocument: () =>
                    LegalInfoBottomSheet.show(context, isLight),
                isLight: isLight,
              ),
              const SizedBox(height: 32),
              _buildSectionHeader(AppLocalizations.of(context)?.electronicSignature ?? 'Electronic Signature', isLight),
              const SizedBox(height: 8),

              // Instruction text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (isLight
                      ? Colors.blue.shade50
                      : Colors.blue.shade900.withOpacity(0.2)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.info,
                      color: isLight
                          ? Colors.blue.shade700
                          : Colors.blue.shade300,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)?.typeNameInCapitalsToSign ?? 'Please type your full name in CAPITAL LETTERS to sign this agreement',
                        style: TextStyle(
                          color: isLight
                              ? Colors.blue.shade900
                              : Colors.blue.shade100,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Show the expected name from Step 1 as reference
              _buildNameReferenceCard(isLight),

              const SizedBox(height: 16),
              _buildModernTextField(
                controller: _signatureNameController,
                label: AppLocalizations.of(context)?.fullNameSignature ?? 'Full Name (Signature)',
                icon: CupertinoIcons.pencil,
                isLight: isLight,
                hasError: _signatureNameError,
                hint: AppLocalizations.of(context)?.typeFullLegalNameHere ?? 'Type your full legal name here',
              ),
              const SizedBox(height: 32),
              _buildSectionHeader(AppLocalizations.of(context)?.signatureDateAndTime ?? 'Signature Date & Time', isLight),
              const SizedBox(height: 16),
              _buildDateTimeCard(isLight),
              const SizedBox(height: 40),
              _buildLegalNotice(isLight),

              const SizedBox(height: 24),

              // Legal Info Button
              TradeRepublicButton(
                label: AppLocalizations.of(context)?.termsPrivacyContact ?? 'Terms, Privacy & Contact',
                icon: Icon(CupertinoIcons.info, size: 18),
                onPressed: () {
                  LegalInfoBottomSheet.show(context, isLight);
                },
              ),

              const SizedBox(height: 40),

              // Navigation Buttons
              Row(
                children: [
                  // Back Button
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: TradeRepublicButton.icon(
                            icon: Icon(CupertinoIcons.chevron_back, size: 18),
                            onPressed: widget.onBack,
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Submit Button - Full Width with Gradient
                  Expanded(
                    child: TradeRepublicButton(
                            label: AppLocalizations.of(context)?.submitApplication ?? 'Submit Application',
                            icon: Icon(CupertinoIcons.checkmark_seal_fill, size: 18),
                            onPressed: _validateAndContinue,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isLight) {
    return Text(
      title,
      style: TextStyle(
        color: isLight ? Colors.black : Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildNameReferenceCard(bool isLight) {
    // Get the full name from Step 1 as reference
    final String firstName = widget.initialData['firstName']?.toString().trim() ?? '';
    final String lastName = widget.initialData['lastName']?.toString().trim() ?? '';
    final String fullNameUppercase = '$firstName $lastName'
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toUpperCase();

    if (fullNameUppercase.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.person_circle,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your name from registration:',
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fullNameUppercase,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isLight,
    bool hasError = false,
    String? hint,
    bool readOnly = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: hasError ? Colors.red.withOpacity(0.08) : (isLight ? Colors.white : Colors.black),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    icon,
                    color: isLight ? Colors.white : Colors.black,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TradeRepublicTextField(
              useFormField: true,
              controller: controller,
              readOnly: readOnly,
              inputFormatters: [
                UpperCaseTextFormatter(), // Force uppercase
              ],
              hintText: hint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgreementCard({
    required String title,
    required String description,
    required bool isAgreed,
    required bool hasError,
    required VoidCallback onTap,
    required VoidCallback onReadDocument,
    required bool isLight,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: hasError ? Colors.red.withOpacity(0.08) : (isLight ? Colors.white : Colors.black),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.doc_text,
                color: isLight ? Colors.black : Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.readDocument ?? 'Read Document',
            icon: Icon(CupertinoIcons.eye, size: 18),
            onPressed: onReadDocument,
          ),
          const SizedBox(height: 16),
          TradeRepublicTap(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isAgreed
                    ? Colors.green.withOpacity(0.08)
                    : (isLight ? Colors.black : Colors.white).withOpacity(0.03),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      description,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TradeRepublicSwitch(
                    value: isAgreed,
                    onChanged: (val) => onTap(),
                    selectedLabel: 'Y',
                    unselectedLabel: 'N',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeCard(bool isLight) {
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(20),
      ),

      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isLight ? Colors.black : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  CupertinoIcons.calendar,
                  color: isLight ? Colors.white : Colors.black,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)?.dateLabel ?? 'Date',
                    style: TextStyle(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _currentDate,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isLight ? Colors.black : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  CupertinoIcons.time,
                  color: isLight ? Colors.white : Colors.black,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)?.timeLabel ?? 'Time',
                    style: TextStyle(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _currentTime,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegalNotice(bool isLight) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.info,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'By typing your name above, you agree that this constitutes a legal electronic signature and has the same effect as a handwritten signature.',
              style: TextStyle(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
