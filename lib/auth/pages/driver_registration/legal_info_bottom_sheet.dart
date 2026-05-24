import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/drag_handle.dart';

import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_tap.dart';

class LegalInfoBottomSheet {
  static void show(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // Handle Bar
            DragHandle(),

            // ── Sheet header ──
            Row(
              children: [
                Icon(CupertinoIcons.doc_text, size: 22, color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.legalInformation ?? 'Legal Information',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
              ]),

            SizedBox(height: 30),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Terms & Conditions
                    _buildLegalSection(
                      icon: CupertinoIcons.doc_text,
                      title: AppLocalizations.of(context)?.termsConditions ?? 'Terms & Conditions',
                      subtitle: AppLocalizations.of(context)?.readOurTermsAndConditions ?? 'Read our terms and conditions',
                      isLight: isLight,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showTermsAndConditions(context, isLight);
                      }),

                    // Privacy Policy
                    _buildLegalSection(
                      icon: CupertinoIcons.lock_shield,
                      title: AppLocalizations.of(context)?.privacyPolicy ?? 'Privacy Policy',
                      subtitle: AppLocalizations.of(context)?.howWeHandleYourData ?? 'How we handle your data',
                      isLight: isLight,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showPrivacyPolicy(context, isLight);
                      }),

                    // Independent Contractor Agreement
                    _buildLegalSection(
                      icon: CupertinoIcons.hand_thumbsup,
                      title: AppLocalizations.of(context)?.independentContractorAgreement ?? 'Independent Contractor Agreement',
                      subtitle: AppLocalizations.of(context)?.driverContractorAgreementTerms ?? 'Driver contractor agreement terms',
                      isLight: isLight,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showIndependentContractorAgreement(context, isLight);
                      }),

                    // Contact
                    _buildLegalSection(
                      icon: CupertinoIcons.question_circle,
                      title: AppLocalizations.of(context)?.contact ?? 'Contact',
                      subtitle: AppLocalizations.of(context)?.getInTouchWithUs ?? 'Get in touch with us',
                      isLight: isLight,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showContactInfo(context, isLight);
                      }),
                  ]))),

            SizedBox(height: 12),

            // Close Button
            TradeRepublicButton(
                    label: AppLocalizations.of(context)?.close ?? 'Close',
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }),
          ])));
  }

  static Widget _buildLegalSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLight,
    required VoidCallback onTap,
  }) {
    return TradeRepublicTap(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isLight
              ? Colors.black.withOpacity(0.05)
              : const Color(0xFF121212),
          borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(20)),
              child: Icon(
                icon,
                size: 20,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.8))),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.2)),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5))),
                ])),
            Icon(
              CupertinoIcons.arrow_right,
              size: 16,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.3)),
          ])));
  }

  static void _showTermsAndConditions(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // Handle Bar
            DragHandle(),

            // ── Sheet header ──
            Row(
              children: [
                Icon(CupertinoIcons.doc_text_search, size: 22, color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.termsAndConditions ?? 'Terms and Conditions',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
              ]),

            SizedBox(height: 20),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'DRIVER TERMS AND CONDITIONS\n\n'
                  'Last Updated: October 25, 2025\n\n'
                  '1. ACCEPTANCE OF TERMS\n'
                  'By registering as a driver with Cultioo Business App, you agree to be bound by these Terms and Conditions.\n\n'
                  '2. DRIVER REQUIREMENTS\n'
                  '- Must be at least 21 years of age\n'
                  '- Valid driver\'s license in good standing\n'
                  '- Clean driving record\n'
                  '- Vehicle registration and insurance documents\n'
                  '- Successfully pass background check\n\n'
                  '3. DRIVER RESPONSIBILITIES\n'
                  '- Maintain valid license, registration, and insurance\n'
                  '- Operate vehicle safely and according to traffic laws\n'
                  '- Provide professional and courteous service\n'
                  '- Track deliveries accurately\n'
                  '- Report any incidents or accidents immediately\n\n'
                  '4. COMPENSATION\n'
                  '- Independent contractor status\n'
                  '- Payment based on completed deliveries\n'
                  '- Weekly payments via bank account\n'
                  '- Driver responsible for taxes and expenses\n'
                  '- Transparent fee structure\n\n'
                  '5. INSURANCE AND LIABILITY\n'
                  '- Drivers must maintain adequate insurance coverage\n'
                  '- Cultioo is not liable for incidents during delivery\n'
                  '- Drivers are responsible for their own vehicles\n\n'
                  '6. TERMINATION\n'
                  'Either party may terminate the agreement at any time with written notice. Cultioo reserves the right to immediately terminate for violations of these terms.\n\n'
                  '7. PRIVACY AND DATA\n'
                  'By accepting these terms, you acknowledge our Privacy Policy and consent to data collection necessary for platform operation.\n\n'
                  'For questions: support@cultioo.com',
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7),
                    fontSize: 16,
                    height: 1.6)))),

            // Close Button
            TradeRepublicButton(
                    label: AppLocalizations.of(context)?.close ?? 'Close',
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }),
          ])));
  }

  static void _showPrivacyPolicy(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // Handle Bar
            DragHandle(),

            // ── Sheet header ──
            Row(
              children: [
                Icon(CupertinoIcons.lock_shield, size: 22, color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.privacyPolicy ?? 'Privacy Policy',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
              ]),

            SizedBox(height: 20),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'PRIVACY POLICY\n\n'
                  'Last Updated: October 25, 2025\n\n'
                  '1. INFORMATION WE COLLECT\n'
                  '- Personal Information (name, date of birth, contact information)\n'
                  '- Driver\'s License number and verification documents\n'
                  '- Social Security Number or Tax ID for payment processing\n'
                  '- Bank account information for payouts\n'
                  '- Vehicle registration and insurance details\n'
                  '- Location data during deliveries\n'
                  '- Device information and app usage data\n\n'
                  '2. HOW WE USE YOUR INFORMATION\n'
                  '- Verify identity and eligibility to drive\n'
                  '- Process background checks for safety\n'
                  '- Facilitate payments and tax reporting\n'
                  '- Track deliveries and optimize routes\n'
                  '- Improve platform performance and user experience\n'
                  '- Communicate important updates and notifications\n'
                  '- Comply with legal and regulatory requirements\n\n'
                  '3. INFORMATION SHARING\n'
                  'We may share your information with:\n'
                  '- Customers (name, photo, vehicle info for delivery tracking)\n'
                  '- Verification services for background checks\n'
                  '- Payment processors for secure transactions\n'
                  '- Law enforcement when required by law\n'
                  '- Service providers who assist in platform operation\n\n'
                  'We do NOT sell your personal data to third parties.\n\n'
                  '4. DATA SECURITY\n'
                  'We implement industry-standard security measures to protect your information:\n'
                  '- Encryption of sensitive data in transit and at rest\n'
                  '- Secure servers and regular security audits\n'
                  '- Access controls and authentication\n'
                  '- Regular security training for our team\n\n'
                  '5. YOUR RIGHTS\n'
                  'You have the right to:\n'
                  '- Access your personal data\n'
                  '- Request corrections to inaccurate information\n'
                  '- Request deletion of your data (subject to legal obligations)\n'
                  '- Opt-out of marketing communications\n'
                  '- Export your data in a portable format\n\n'
                  '6. DATA RETENTION\n'
                  'We retain your information as long as necessary for:\n'
                  '- Providing our services\n'
                  '- Complying with legal obligations\n'
                  '- Resolving disputes\n'
                  '- Enforcing our agreements\n\n'
                  '7. CHILDREN\'S PRIVACY\n'
                  'Our service is not directed to individuals under 18 years of age. We do not knowingly collect information from children.\n\n'
                  '8. CHANGES TO THIS POLICY\n'
                  'We may update this Privacy Policy from time to time. We will notify you of significant changes via email or app notification.\n\n'
                  'Contact us about privacy:\n'
                  'Email: privacy@cultioo.com\n'
                  'Data Protection Officer: dpo@cultioo.com',
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7),
                    fontSize: 16,
                    height: 1.6)))),

            // Close Button
            TradeRepublicButton(
                    label: AppLocalizations.of(context)?.close ?? 'Close',
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }),
          ])));
  }

  static void _showIndependentContractorAgreement(
    BuildContext context,
    bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // Handle Bar
            DragHandle(),

            // ── Sheet header ──
            Row(
              children: [
                Icon(CupertinoIcons.doc_checkmark, size: 22, color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.independentContractorAgreement ?? 'Independent Contractor Agreement',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
              ]),

            SizedBox(height: 20),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'INDEPENDENT CONTRACTOR AGREEMENT\n\n'
                  'Last Updated: October 25, 2025\n\n'
                  '1. INDEPENDENT CONTRACTOR STATUS\n'
                  'This Agreement establishes an independent contractor relationship between you (the "Driver") and Cultioo Inc. ("Company"). You are NOT an employee, agent, or partner of the Company.\n\n'
                  'Key Points:\n'
                  '- You control when, where, and how you work\n'
                  '- You are responsible for your own taxes and insurance\n'
                  '- You may work for other companies simultaneously\n'
                  '- No employee benefits (health insurance, paid leave, etc.)\n\n'
                  '2. SERVICES PROVIDED\n'
                  'As an independent contractor, you agree to:\n'
                  '- Accept delivery requests at your discretion\n'
                  '- Pick up items from designated locations\n'
                  '- Deliver items safely and promptly to customers\n'
                  '- Maintain professional communication with customers\n'
                  '- Use your own vehicle and equipment\n\n'
                  '3. COMPENSATION STRUCTURE\n'
                  'Payment Terms:\n'
                  '- Per-delivery compensation based on distance and complexity\n'
                  '- Weekly direct deposit to your bank account\n'
                  '- Bonuses for high-volume periods and excellent ratings\n'
                  '- Transparent fee structure visible in the app\n'
                  '- No guaranteed minimum earnings\n\n'
                  'You are responsible for:\n'
                  '- Self-employment taxes\n'
                  '- Vehicle expenses (gas, maintenance, insurance)\n'
                  '- Mobile phone and data costs\n'
                  '- Any applicable business licenses or permits\n\n'
                  '4. VEHICLE AND INSURANCE REQUIREMENTS\n'
                  'You must maintain:\n'
                  '- Valid vehicle registration in your name\n'
                  '- Comprehensive auto insurance meeting state requirements\n'
                  '- Valid driver\'s license without restrictions\n'
                  '- Vehicle in safe, clean, and operational condition\n\n'
                  'The Company does NOT provide:\n'
                  '- Vehicle insurance coverage\n'
                  '- Liability coverage for accidents\n'
                  '- Reimbursement for vehicle damage\n\n'
                  '5. WORKING HOURS AND FLEXIBILITY\n'
                  'As an independent contractor:\n'
                  '- You choose your own working hours\n'
                  '- You can accept or decline any delivery request\n'
                  '- You determine your own work schedule\n'
                  '- No minimum hours required\n'
                  '- You may work for competing platforms\n\n'
                  '6. PERFORMANCE EXPECTATIONS\n'
                  'While you have flexibility, we expect:\n'
                  '- Professional behavior and appearance\n'
                  '- Timely deliveries once accepted\n'
                  '- Respectful communication with customers\n'
                  '- Compliance with traffic laws and regulations\n'
                  '- Accurate tracking and reporting\n\n'
                  'Poor performance may result in:\n'
                  '- Lower priority for delivery requests\n'
                  '- Suspension from the platform\n'
                  '- Termination of this agreement\n\n'
                  '7. INTELLECTUAL PROPERTY\n'
                  '- Company retains all rights to the app, logo, and brand\n'
                  '- You may use Company materials only while active\n'
                  '- Customer data remains confidential and proprietary\n'
                  '- No unauthorized use of Company trademarks\n\n'
                  '8. CONFIDENTIALITY\n'
                  'You agree to:\n'
                  '- Keep customer information private\n'
                  '- Not disclose delivery details to third parties\n'
                  '- Protect customer addresses and contact information\n'
                  '- Maintain confidentiality of Company business practices\n\n'
                  '9. TERMINATION\n'
                  'Either party may terminate this agreement:\n'
                  '- At any time, for any reason\n'
                  '- With or without notice\n'
                  '- Company may terminate immediately for violations\n\n'
                  'Upon termination:\n'
                  '- Complete any pending deliveries\n'
                  '- Return any Company property\n'
                  '- Final payment processed within 14 days\n'
                  '- Access to platform will be revoked\n\n'
                  '10. DISPUTE RESOLUTION\n'
                  '- Disputes will be resolved through binding arbitration\n'
                  '- Governed by the laws of California, USA\n'
                  '- No class action lawsuits permitted\n\n'
                  '11. ENTIRE AGREEMENT\n'
                  'This Agreement, together with the Terms and Conditions and Privacy Policy, constitutes the entire agreement between you and the Company.\n\n'
                  'By accepting this agreement, you acknowledge that you:\n'
                  '- Have read and understood all terms\n'
                  '- Agree to work as an independent contractor\n'
                  '- Accept responsibility for taxes and expenses\n'
                  '- Understand you are not an employee\n\n'
                  'For questions about this agreement:\n'
                  'Email: contracts@cultioo.com\n'
                  'Legal Department: legal@cultioo.com',
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7),
                    fontSize: 16,
                    height: 1.6)))),

            // Close Button
            TradeRepublicButton(
                    label: AppLocalizations.of(context)?.close ?? 'Close',
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }),
          ])));
  }

  static void _showContactInfo(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // Handle Bar
            DragHandle(),

            // ── Sheet header ──
            Row(
              children: [
                Icon(CupertinoIcons.envelope, size: 22, color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.contactUs ?? 'Contact Us',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
              ]),

            SizedBox(height: 30),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Support Contact
                    _buildContactCard(
                      icon: CupertinoIcons.person_2,
                      title: AppLocalizations.of(context)?.driverSupport ?? 'Driver Support',
                      subtitle: AppLocalizations.of(context)?.getHelpWithDeliveriesAndAccountIssues ?? 'Get help with deliveries and account issues',
                      contactInfo: 'support@cultioo.com',
                      isLight: isLight),

                    SizedBox(height: 16),

                    // Emergency Contact
                    _buildContactCard(
                      icon: CupertinoIcons.exclamationmark_triangle,
                      title: AppLocalizations.of(context)?.emergencyHotline ?? 'Emergency Hotline',
                      subtitle: AppLocalizations.of(context)?.forUrgentSafetyOrSecurityIssues ?? 'For urgent safety or security issues',
                      contactInfo: '+1 (800) 555-0911',
                      isLight: isLight),

                    SizedBox(height: 16),

                    // Technical Support
                    _buildContactCard(
                      icon: CupertinoIcons.ant,
                      title: AppLocalizations.of(context)?.technicalSupport ?? 'Technical Support',
                      subtitle: AppLocalizations.of(context)?.reportBugsOrTechnicalProblems ?? 'Report bugs or technical problems',
                      contactInfo: 'tech@cultioo.com',
                      isLight: isLight),

                    SizedBox(height: 16),

                    // Privacy Inquiries
                    _buildContactCard(
                      icon: CupertinoIcons.lock_shield,
                      title: AppLocalizations.of(context)?.privacyInquiries ?? 'Privacy Inquiries',
                      subtitle: AppLocalizations.of(context)?.questionsAboutYourDataAndPrivacy ?? 'Questions about your data and privacy',
                      contactInfo: 'privacy@cultioo.com',
                      isLight: isLight),

                    SizedBox(height: 16),

                    // Business Hours
                    _buildInfoCard(
                      icon: CupertinoIcons.time,
                      title: AppLocalizations.of(context)?.businessHours ?? 'Business Hours',
                      info:
                          'Monday - Friday: 8:00 AM - 8:00 PM EST\nSaturday - Sunday: 10:00 AM - 6:00 PM EST',
                      isLight: isLight),

                    SizedBox(height: 16),

                    // Office Address
                    _buildInfoCard(
                      icon: CupertinoIcons.location,
                      title: AppLocalizations.of(context)?.officeAddress ?? 'Office Address',
                      info:
                          'Cultioo Inc.\n123 Business Street\nSan Francisco, CA 94105\nUnited States',
                      isLight: isLight),
                  ]))),

            // Close Button
            TradeRepublicButton(
                    label: AppLocalizations.of(context)?.close ?? 'Close',
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }),
          ])));
  }

  static Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String contactInfo,
    required bool isLight,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.black.withOpacity(0.05)
            : const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20)),
                child: Icon(
                  icon,
                  size: 24,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.8))),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.2)),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),
                  ])),
            ]),
          SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20)),
            child: Text(
              contactInfo,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF007AFF),
                letterSpacing: -0.2),
              textAlign: TextAlign.center)),
        ]));
  }

  static Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String info,
    required bool isLight,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.black.withOpacity(0.05)
            : const Color(0xFF121212),
        borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20)),
            child: Icon(
              icon,
              size: 24,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.8))),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.2)),
                SizedBox(height: 8),
                Text(
                  info,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7),
                    height: 1.5)),
              ])),
        ]));
  }
}
