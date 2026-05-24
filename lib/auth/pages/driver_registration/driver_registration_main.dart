import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/services/app_settings.dart';
import 'driver_step1_personal_info.dart';
import 'driver_step2_document_upload.dart';
import 'driver_step3_document_back.dart';
import 'driver_step4_license_front.dart';
import 'driver_step5_license_back.dart';
import 'driver_step6_face_verification.dart';
import 'driver_step7_consent.dart';
import 'driver_step8_company.dart';
import 'driver_step9_verification.dart';
import 'driver_step10_success.dart';

class DriverRegistrationMain extends StatefulWidget {
  const DriverRegistrationMain({super.key});

  @override
  State<DriverRegistrationMain> createState() => _DriverRegistrationMainState();
}

class _DriverRegistrationMainState extends State<DriverRegistrationMain> {
  int _currentStep = 0;
  final PageController _pageController = PageController();
  final Map<String, dynamic> _registrationData = {};

  @override
  void initState() {
    super.initState();
    print('📋 REGISTRATION: Starting at step ${_currentStep + 1}');
    print(
      '📋 REGISTRATION: PageController initial page: ${_pageController.initialPage}');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    print('🚀 NAVIGATION: _nextStep() called from step ${_currentStep + 1}');
    print('🚀 NAVIGATION: Current _currentStep value: $_currentStep');
    print(
      '🚀 NAVIGATION: PageController current page: ${_pageController.page}');

    if (_currentStep < 9) {
      // 10 steps total (0-9), last step is success page
      final nextStep = _currentStep + 1;
      print(
        '🚀 NAVIGATION: Moving from step ${_currentStep + 1} to step ${nextStep + 1}');
      print(
        '🚀 NAVIGATION: Setting _currentStep from $_currentStep to $nextStep');

      setState(() {
        _currentStep = nextStep;
      });

      print(
        '🚀 NAVIGATION: After setState - _currentStep is now: $_currentStep');
      print('🚀 NAVIGATION: Calling animateToPage($nextStep)');

      // Use animateToPage for better control
      _pageController
          .animateToPage(
            nextStep,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut)
          .then((_) {
            print(
              '🚀 NAVIGATION: Animation completed - now at step ${_currentStep + 1}');
            print(
              '🚀 NAVIGATION: PageController page after animation: ${_pageController.page}');
            print(
              '🚀 NAVIGATION: SUCCESS - Should be on Step ${_currentStep + 1}');
          });
    } else {
      print('🚀 NAVIGATION: Already at final step ${_currentStep + 1}');
    }
  }

  void _previousStep() {
    print(
      '🔙 NAVIGATION: _previousStep() called from step ${_currentStep + 1}');
    print(
      '🔙 NAVIGATION: !!!WARNING!!! Going BACKWARD - this should NOT happen from Step 4 Continue button!');
    print('🔙 NAVIGATION: Current _currentStep value: $_currentStep');
    print(
      '🔙 NAVIGATION: PageController current page: ${_pageController.page}');

    if (_currentStep > 0) {
      final prevStep = _currentStep - 1;
      print(
        '🔙 NAVIGATION: Moving BACKWARD from step ${_currentStep + 1} to step ${prevStep + 1}');

      setState(() {
        _currentStep = prevStep;
      });

      _pageController
          .animateToPage(
            prevStep,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut)
          .then((_) {
            print(
              '🔙 NAVIGATION: BACKWARD animation completed - now at step ${_currentStep + 1}');
            print(
              '🔙 NAVIGATION: PageController page after animation: ${_pageController.page}');
          });
    } else {
      print('🔙 NAVIGATION: At first step, popping navigation');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: PageView(
        controller: _pageController,
        physics:
            const NeverScrollableScrollPhysics(), // Disable swipe navigation
        onPageChanged: (index) {
          print(
            '📄 PAGEVIEW: Page changed to index $index (Step ${index + 1})');
        },
        children: [
          // Step 1: Personal Info
          DriverStep1PersonalInfo(
            key: const ValueKey('step_1_personal_info'),
            initialData: _registrationData,
            onNext: _nextStep,
            onBack: _previousStep),

          // Step 2: Document Upload (Front)
          DriverStep2DocumentUpload(
            key: const ValueKey('step_2_document_front'),
            initialData: _registrationData,
            onNext: _nextStep,
            onBack: _previousStep),

          // Step 3: Document Upload (Back)
          DriverStep3DocumentBack(
            key: const ValueKey('step_3_document_back'),
            initialData: _registrationData,
            onNext: _nextStep,
            onBack: _previousStep),

          // Step 4: License Front
          DriverStep4LicenseFront(
            key: const ValueKey('step_4_license_front'),
            initialData: _registrationData,
            onNext: _nextStep,
            onBack: _previousStep),

          // Step 5: License Back
          DriverStep5LicenseBack(
            key: const ValueKey('step_5_license_back'),
            initialData: _registrationData,
            onNext: _nextStep,
            onBack: _previousStep),

          // Step 6: Face Verification (AI)
          DriverStep6FaceVerification(
            key: const ValueKey('step_6_face_verification'),
            initialData: _registrationData,
            onNext: _nextStep,
            onBack: _previousStep),

          // Step 7: Consent
          DriverStep7Consent(
            key: const ValueKey('step_7_consent'),
            onBack: _previousStep,
            onNext: _nextStep,
            initialData: _registrationData),

          // Step 8: Company Information
          DriverStep8Company(
            key: const ValueKey('step_8_company'),
            initialData: _registrationData,
            onNext: _nextStep,
            onBack: _previousStep),

          // Step 9: Verification
          DriverStep9Verification(
            key: const ValueKey('step_9_verification'),
            initialData: _registrationData,
            onNext: _nextStep,
            onBack: _previousStep),

          // Step 10: Success
          DriverStep10Success(
            key: const ValueKey('step_10_success'),
            registrationData: _registrationData),
        ]));
  }
}
