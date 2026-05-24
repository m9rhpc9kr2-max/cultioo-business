import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../shared/services/app_settings.dart';
import '../../shared/services/api_service.dart';
import '../../shared/services/nominatim_service.dart';
import '../../shared/helpers/notification_helper.dart';
import '../../shared/widgets/trade_republic_button.dart';
import '../../shared/widgets/trade_republic_text_field.dart';
import '../../shared/widgets/drag_handle.dart';
import '../../shared/widgets/trade_republic_list_tile.dart';

import '../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../shared/services/app_localizations.dart';
import '../../shared/widgets/cultioo_spinner.dart';
import '../../shared/widgets/trade_republic_tap.dart';

class BusinessInfoPage extends StatefulWidget {
  final String email;

  const BusinessInfoPage({super.key, required this.email});

  @override
  State<BusinessInfoPage> createState() => _BusinessInfoPageState();
}

class _BusinessInfoPageState extends State<BusinessInfoPage>
    with TickerProviderStateMixin {
  final _businessNameController = TextEditingController();
  final _businessEmailController = TextEditingController();
  final _businessPhoneController = TextEditingController();
  final _businessAddressController = TextEditingController();
  final _businessDescriptionController = TextEditingController();
  final _businessWebsiteController = TextEditingController();
  final _taxVatNumberController = TextEditingController();
  final _addressFocusNode = FocusNode();
  String _selectedBusinessSize = 'Small (1-100 employees)';
  String _selectedCountry = 'United States';
  String _selectedPhoneCode = '+1';
  String? _businessLogoPath;
  bool _isLoading = false;
  bool _showAddressSuggestions = false;
  List<String> _filteredAddressSuggestions = [];
  bool _isAddressValid = true;
  bool _isLoadingAddresses = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
        );

    // Start animations
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _slideController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 60),

                      // Step progress indicator
                      Row(
                        children: [
                          // Step 1 - Completed
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Center(
                              child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                ),
                            ),
                          ),

                          // Connection line
                          Expanded(
                            child: Container(
                              height: 2,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),

                          // Step 2 - Active
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Center(
                              child: Text(
                                '2',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      Text(
                        AppLocalizations.of(context)?.businessInformation ?? 'Business Information',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)?.completeBusinessProfile ?? 'Complete your business profile',
                        style: TextStyle(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Business Name
                      _buildTextField(
                        AppLocalizations.of(context)?.businessName ?? 'Business Name',
                        'Enter your business name',
                        _businessNameController,
                        isLight,
                      ),

                      const SizedBox(height: 24),

                      // Business Email
                      _buildTextField(
                        'Business Email',
                        'Enter your business email',
                        _businessEmailController,
                        isLight,
                        keyboardType: TextInputType.emailAddress,
                      ),

                      const SizedBox(height: 24),

                      // Business Size Selection
                      _buildSelectionField(
                        AppLocalizations.of(context)?.businessSize ?? 'Business Size',
                        _selectedBusinessSize,
                        () => _showBusinessSizeBottomSheet(),
                        isLight,
                      ),

                      const SizedBox(height: 24),

                      // Country Selection
                      _buildSelectionField(
                        AppLocalizations.of(context)?.businessCountry ?? 'Business Country',
                        _selectedCountry,
                        () => _showCountryBottomSheet(),
                        isLight,
                      ),

                      const SizedBox(height: 24),

                      // Business Phone with Country Code
                      _buildPhoneField(isLight),

                      const SizedBox(height: 24),

                      // Business Address
                      _buildAddressField(isLight),

                      const SizedBox(height: 24),

                      // Business Description
                      _buildTextField(
                        'Business Description (Optional)',
                        'Brief description of your business',
                        _businessDescriptionController,
                        isLight,
                        maxLines: 3,
                      ),

                      const SizedBox(height: 24),

                      // Business Website
                      _buildTextField(
                        'Website (Optional)',
                        'https://www.yourcompany.com',
                        _businessWebsiteController,
                        isLight,
                        keyboardType: TextInputType.url,
                      ),

                      const SizedBox(height: 24),

                      // Tax ID Number
                      _buildTextField(
                        'Tax ID Number (EIN)',
                        'Enter your Employer Identification Number',
                        _taxVatNumberController,
                        isLight,
                      ),

                      const SizedBox(height: 24),

                      // Business Logo Upload
                      _buildLogoUploadField(isLight),

                      const SizedBox(height: 60),

                      // Complete button
                      SizedBox(
                        width: double.infinity,
                        child: Platform.isIOS
                            ? TradeRepublicButton(
                                onPressed: _isLoading
                                    ? null
                                    : _completeBusinessUpgrade,
                                label: AppLocalizations.of(context)?.completeUpgrade ?? 'Complete Upgrade',
                              )
                            : TradeRepublicTap(
                                onTap: _isLoading
                                    ? null
                                    : _completeBusinessUpgrade,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: LinearGradient(
                                      colors: _isLoading
                                          ? [
                                              (isLight
                                                      ? Colors.black
                                                      : Colors.white)
                                                  .withOpacity(0.5),
                                              (isLight
                                                      ? Colors.black
                                                      : Colors.white)
                                                  .withOpacity(0.5),
                                            ]
                                          : [Colors.blue, Colors.blue.shade700],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const Center(
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CultiooLoadingIndicator(size: 20),
                                          ),
                                        )
                                      : Text(
                                          AppLocalizations.of(context)?.completeUpgrade ?? 'Complete Upgrade',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 18,
                                          ),
                                        ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: 60,
            left: 20,
            child: TradeRepublicTap(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isLight ? Colors.white : Colors.black).withOpacity(
                    0.9,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.arrow_back,
                  color: isLight ? Colors.black : Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    String hint,
    TextEditingController controller,
    bool isLight, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        TradeRepublicTextField(
          controller: controller,
          hintText: hint,
          keyboardType: keyboardType,
          maxLines: maxLines,
        ),
      ],
    );
  }

  Widget _buildSelectionField(
    String label,
    String value,
    VoidCallback onTap,
    bool isLight,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          child: TradeRepublicTap(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.businessPhone ?? 'Business Phone',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              // Country Code Selector
              TradeRepublicTap(
                onTap: () => _showPhoneCodeBottomSheet(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      isLight ? 0.05 : 0.7,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedPhoneCode,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              // Phone Number Input
              Expanded(
                child: TradeRepublicTextField(
                  controller: _businessPhoneController,
                  keyboardType: TextInputType.phone,
                  hintText: AppLocalizations.of(context)?.enterPhoneNumber ?? 'Enter phone number',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressField(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.businessAddress ?? 'Business Address',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              TradeRepublicTextField(
                controller: _businessAddressController,
                focusNode: _addressFocusNode,
                hintText: AppLocalizations.of(context)?.enterCompleteBusinessAddress ?? 'Enter your complete business address',
                onChanged: (value) async {
                  setState(() {
                    // Reset validation state when user types
                    _isAddressValid = true;
                  });

                  // Use Nominatim for real address suggestions
                  await _searchAddresses(value);
                },
              ),
              // Address suggestions list
              if (_showAddressSuggestions &&
                  _filteredAddressSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(
                    maxHeight: 200,
                  ), // Limit height
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _filteredAddressSuggestions.length,
                    itemBuilder: (context, index) {
                      final address = _filteredAddressSuggestions[index];
                      return TradeRepublicTap(
                        onTap: () {
                          setState(() {
                            _businessAddressController.text = address;
                            _showAddressSuggestions = false;
                            _filteredAddressSuggestions = [];
                            _isAddressValid =
                                true; // Mark as valid when selected from list
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: Colors.blue,
                                size: 18,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  address,
                                  style: TextStyle(
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        if (!_isAddressValid)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 16),
            child: Text(
              AppLocalizations.of(context)?.enterBusinessAddress ?? 'Please enter a valid business address',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Future<void> _searchAddresses(String query) async {
    if (query.length < 3) {
      setState(() {
        _showAddressSuggestions = false;
        _filteredAddressSuggestions = [];
      });
      return;
    }

    setState(() {
      _isLoadingAddresses = true;
    });

    try {
      final addresses = await NominatimService.searchAddresses(query);

      setState(() {
        _filteredAddressSuggestions = addresses;
        _showAddressSuggestions = addresses.isNotEmpty;
        _isLoadingAddresses = false;
      });

      // Show info notification for successful address search
      if (addresses.isNotEmpty && query.length >= 5) {
        NotificationHelper.showAddressSearchInfo(context, addresses.length);
      }
    } catch (e) {
      print('Address search error: $e');
      setState(() {
        _showAddressSuggestions = false;
        _filteredAddressSuggestions = [];
        _isLoadingAddresses = false;
      });
    }
  }

  void _completeBusinessUpgrade() async {
    // Validate address selection
    final addressSuggestions = [
      'Main Street 123, 12344 Nevada, USA',
      'Broadway Avenue 456, 10001 New York, USA',
      'Oak Avenue 789, 90210 California, USA',
      'Pine Street 101, 60601 Illinois, USA',
      'First Avenue 202, 33101 Florida, USA',
      'Second Street 303, 75201 Texas, USA',
      'Park Road 404, 02101 Massachusetts, USA',
      'Washington Boulevard 505, 20001 Washington DC, USA',
      'Eider Street 606, 80202 Colorado, USA',
      'Eiderdorf Avenue 707, 95101 California, USA',
      'Test Street 123, 12345 Test City, USA',
      'Sample Road 456, 67890 Sample Town, USA',
      'Apple Street 800, 94102 San Francisco, USA',
      'Google Way 900, 94043 Mountain View, USA',
      'Microsoft Avenue 1000, 98052 Redmond, USA',
      'Amazon Drive 1100, 98109 Seattle, USA',
      'Facebook Lane 1200, 94025 Menlo Park, USA',
      'Tesla Road 1300, 94304 Palo Alto, USA',
    ];

    bool isAddressFromSuggestions = addressSuggestions.contains(
      _businessAddressController.text,
    );

    if (_businessNameController.text.isEmpty ||
        _businessEmailController.text.isEmpty ||
        _businessPhoneController.text.isEmpty ||
        _businessAddressController.text.isEmpty ||
        _taxVatNumberController.text.isEmpty) {
      _showError(AppLocalizations.of(context)?.pleaseFillAllRequiredBusinessInfo ?? 'Please fill in all required business information');
      return;
    }

    // Validate address is from suggestions
    if (!isAddressFromSuggestions) {
      setState(() {
        _isAddressValid = false;
      });
      _showError(AppLocalizations.of(context)?.pleaseSelectValidAddress ?? 'Please select a valid address from the suggestions');
      return;
    }

    // Validate email format
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(_businessEmailController.text)) {
      _showError(AppLocalizations.of(context)?.pleaseEnterValidBusinessEmail ?? 'Please enter a valid business email address');
      return;
    }

    // Validate website URL if provided
    if (_businessWebsiteController.text.isNotEmpty) {
      final urlRegex = RegExp(r'^https?:\/\/.+\..+');
      if (!urlRegex.hasMatch(_businessWebsiteController.text)) {
        _showError(
          'Please enter a valid website URL (starting with http:// or https://)',
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Get the auth token from AppSettings
      final AppSettings appSettings = Provider.of<AppSettings>(
        context,
        listen: false,
      );
      final String? token = appSettings.authToken;

      if (token == null) {
        _showError(AppLocalizations.of(context)?.authTokenNotFoundPleaseLogin ?? 'Authentication token not found. Please login again.');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      print('🔄 Updating business information...');

      // Call the API to save business information
      final result = await ApiService.updateBusinessInfo(
        token: token,
        businessName: _businessNameController.text,
        businessEmail: _businessEmailController.text,
        businessSize: _selectedBusinessSize,
        businessCountry: _selectedCountry,
        businessPhone: '$_selectedPhoneCode ${_businessPhoneController.text}',
        businessAddress: _businessAddressController.text,
        taxVatNumber: _taxVatNumberController.text,
        businessDescription: _businessDescriptionController.text.isNotEmpty
            ? _businessDescriptionController.text
            : null,
        businessWebsite: _businessWebsiteController.text.isNotEmpty
            ? _businessWebsiteController.text
            : null,
        businessLogoPath: _businessLogoPath,
      );

      setState(() {
        _isLoading = false;
      });

      if (result['success'] == true) {
        print('✅ Business information saved successfully');

        // Set user as business user and navigate to main app
        appSettings.setIsLoggedIn(true);
        appSettings.setUserType(AppLocalizations.of(context)?.businessLabel ?? 'Business');

        // Show success message
        _showSuccess('🎉 ${AppLocalizations.of(context)?.businessInfoUpdated ?? 'Business upgrade completed successfully!'}');

        // Navigate to main app after a short delay
        Future.delayed(const Duration(seconds: 1), () {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/main', (route) => false);
        });
      } else {
        print('❌ Failed to save business information: ${result['message']}');

        // Check if user already upgraded
        if (result['alreadyUpgraded'] == true) {
          _showError(
            'Your business account has already been upgraded. Redirecting to main app...',
          );

          // Set user as logged in and redirect
          appSettings.setIsLoggedIn(true);
          appSettings.setUserType(AppLocalizations.of(context)?.businessLabel ?? 'Business');

          Future.delayed(const Duration(seconds: 2), () {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/main', (route) => false);
          });
        } else {
          _showError(
            result['message'] ??
                (AppLocalizations.of(context)?.failedToCompleteBusinessUpgrade ?? 'Failed to complete business upgrade. Please try again.'),
          );
        }
      }
    } catch (e) {
      print('💥 Error during business upgrade: $e');
      setState(() {
        _isLoading = false;
      });
      _showError(AppLocalizations.of(context)?.failedToCompleteBusinessUpgrade ?? 'Failed to complete business upgrade. Please try again.');
    }
  }

  void _showError(String message) {
    NotificationHelper.showError(context, message);
  }

  void _showSuccess(String message) {
    NotificationHelper.showSuccess(context, message);
  }

  Widget _buildLogoUploadField(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.businessLogoOptional ?? 'Business Logo (Optional)',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
          child: TradeRepublicTap(
            onTap: _pickBusinessLogo,
            child: Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _businessLogoPath != null
                  ? Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          height: 120,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.file(
                              File(_businessLogoPath!),
                              width: double.infinity,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: double.infinity,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.business,
                                        color: Colors.blue,
                                        size: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        AppLocalizations.of(context)?.logoSelected ?? 'Logo Selected',
                                        style: TextStyle(
                                          color: Colors.blue,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: TradeRepublicTap(
                            onTap: () {
                              setState(() {
                                _businessLogoPath = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context)?.uploadBusinessLogo ?? 'Upload Business Logo',
                          style: TextStyle(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.5),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context)?.pngJpgUpTo5mb ?? 'PNG, JPG up to 5MB',
                          style: TextStyle(
                            color: isLight ? Colors.black38 : Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  void _pickBusinessLogo() async {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false,
    );
    final isLight = appSettings.isLightMode(context);

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DragHandle(),
            Row(
              children: [
                Icon(CupertinoIcons.photo, size: 22, color: isLight ? Colors.black : Colors.white),
                const SizedBox(width: 12),
                Flexible(child: Text(
                  AppLocalizations.of(context)?.chooseImageSource ?? 'Choose Image Source',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                )),
              ],
            ),
            const SizedBox(height: 4),

            Row(
              children: [
                Expanded(
                  child: TradeRepublicTap(
                    onTap: () async {
                      Navigator.pop(context);
                      await _pickImageFromGallery();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(isLight ? 0.05 : 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.photo_library,
                            color: Colors.blue,
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.of(context)?.gallery ?? 'Gallery',
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TradeRepublicTap(
                    onTap: () async {
                      Navigator.pop(context);
                      await _pickImageFromCamera();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(isLight ? 0.05 : 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                                  Icons.camera_alt,
                                  color: Colors.blue,
                                  size: 32,
                                ),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.of(context)?.camera ?? 'Camera',
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
    );
  }

  void _showBusinessSizeBottomSheet() {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false,
    );
    final isLight = appSettings.isLightMode(context);

    final businessSizes = [
      'Small (1-100 employees)',
      'Medium (101-500 employees)',
      'Large (501-5000 employees)',
      'Enterprise (5000+ employees)',
    ];

    if (Platform.isIOS) {
      // Use CN Popup Menu for iOS/macOS
      TradeRepublicBottomSheet.show(
        context: context,
        bottomPadding: 20.0,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DragHandle(),
              Row(
                children: [
                  Icon(CupertinoIcons.person_2, size: 22, color: isLight ? Colors.black : Colors.white),
                  const SizedBox(width: 12),
                  Flexible(child: Text(
                    AppLocalizations.of(context)?.businessSize ?? 'Business Size',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                  )),
                ],
              ),
              const SizedBox(height: 4),
              ...businessSizes.map(
                (size) => TradeRepublicListTile(
                  title: size,
                  trailing: _selectedBusinessSize == size
                      ? const Icon(Icons.check, color: Colors.blue, size: 20)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedBusinessSize = size;
                    });
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
      );
    } else {
      _showSelectionBottomSheet(
        title: AppLocalizations.of(context)?.businessSize ?? 'Business Size',
        options: businessSizes,
        selectedOption: _selectedBusinessSize,
        onOptionSelected: (option) {
          setState(() {
            _selectedBusinessSize = option;
          });
        },
        isLight: isLight,
        isScrollable: false,
      );
    }
  }

  void _showCountryBottomSheet() {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false,
    );
    final isLight = appSettings.isLightMode(context);

    final countries = [
      // North America
      'United States',
      'Canada',
      'Mexico',
      // EU Countries
      'Germany',
      'Austria',
      'France',
      'Italy',
      'Spain',
      'Netherlands',
      'Belgium',
      'Poland',
      'Portugal',
      'Greece',
      'Ireland',
      'Sweden',
      'Denmark',
      'Finland',
      'Czech Republic',
      'Hungary',
      'Romania',
      'Bulgaria',
      'Croatia',
      'Slovakia',
      'Slovenia',
      'Estonia',
      'Latvia',
      'Lithuania',
      'Malta',
      'Cyprus',
      'Luxembourg',
      // Russia
      'Russia',
    ];

    if (Platform.isIOS) {
      // Use CN Components for iOS/macOS
      TradeRepublicBottomSheet.show(
        context: context,
        bottomPadding: 20.0,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DragHandle(),
              Row(
                children: [
                  Icon(CupertinoIcons.globe, size: 22, color: isLight ? Colors.black : Colors.white),
                  const SizedBox(width: 12),
                  Flexible(child: Text(
                    AppLocalizations.of(context)?.businessCountry ?? 'Business Country',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                  )),
                ],
              ),
              const SizedBox(height: 20),
              ...countries.map(
                (country) => TradeRepublicListTile(
                  leading: Icon(
                      country == 'United States' ? Icons.flag : Icons.flag_outlined,
                      size: 20,
                      color: country == 'United States' ? Colors.red : Colors.black,
                    ),
                  title: country,
                  trailing: _selectedCountry == country
                      ? const Icon(Icons.check, color: Colors.blue, size: 20)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedCountry = country;
                    });
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
      );
    } else {
      _showSelectionBottomSheet(
        title: AppLocalizations.of(context)?.businessCountry ?? 'Business Country',
        options: countries,
        selectedOption: _selectedCountry,
        onOptionSelected: (option) {
          setState(() {
            _selectedCountry = option;
          });
        },
        isLight: isLight,
        isScrollable: true,
      );
    }
  }

  void _showPhoneCodeBottomSheet() {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false,
    );
    final isLight = appSettings.isLightMode(context);

    final phoneCodes = [
      // North America
      '+1 (USA)',
      '+1 (Canada)',
      '+52 (Mexico)',
      // UK
      '+44 (United Kingdom)',
      // EU Countries
      '+43 (Austria)',
      '+32 (Belgium)',
      '+359 (Bulgaria)',
      '+385 (Croatia)',
      '+357 (Cyprus)',
      '+420 (Czech Republic)',
      '+45 (Denmark)',
      '+372 (Estonia)',
      '+358 (Finland)',
      '+33 (France)',
      '+49 (Germany)',
      '+30 (Greece)',
      '+36 (Hungary)',
      '+353 (Ireland)',
      '+39 (Italy)',
      '+371 (Latvia)',
      '+370 (Lithuania)',
      '+352 (Luxembourg)',
      '+356 (Malta)',
      '+31 (Netherlands)',
      '+47 (Norway)',
      '+48 (Poland)',
      '+351 (Portugal)',
      '+40 (Romania)',
      '+421 (Slovakia)',
      '+386 (Slovenia)',
      '+34 (Spain)',
      '+46 (Sweden)',
      '+41 (Switzerland)',
      // Russia
      '+7 (Russia)',
    ];

    TradeRepublicBottomSheet.show(
      context: context,
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
            children: [
              DragHandle(),
              Row(
                children: [
                  Icon(CupertinoIcons.phone, size: 22, color: isLight ? Colors.black : Colors.white),
                  const SizedBox(width: 12),
                  Flexible(child: Text(
                    AppLocalizations.of(context)?.selectCountryCode ?? 'Select Country Code',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                  )),
                ],
              ),
              const SizedBox(height: 4),

              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: phoneCodes.length,
                  itemBuilder: (context, index) {
                    final phoneCode = phoneCodes[index];
                    final code = phoneCode.split(' ')[0];
                    final isSelected = _selectedPhoneCode == code;

                    return TradeRepublicTap(
                      onTap: () {
                        setState(() {
                          _selectedPhoneCode = code;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue.withOpacity(0.15)
                              : (isLight ? Colors.black : Colors.white)
                                    .withOpacity(isLight ? 0.05 : 0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Text(
                              phoneCode,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.blue
                                    : (isLight ? Colors.black : Colors.white),
                                fontSize: 16,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            const Spacer(),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.blue,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
      ),
    );
  }

  void _showSelectionBottomSheet({
    required String title,
    required List<String> options,
    required String selectedOption,
    required void Function(String) onOptionSelected,
    required bool isLight,
    bool isScrollable = false,
  }) {
    if (isScrollable) {
      // Use DraggableScrollableSheet for longer lists
      TradeRepublicBottomSheet.show(
        context: context,
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Column(
              children: [
                DragHandle(),

                Row(
                  children: [
                    Icon(CupertinoIcons.list_bullet, size: 22, color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 12),
                    Flexible(child: Text(
                      title,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                    )),
                  ],
                ),
                const SizedBox(height: 4),

                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final isSelected = selectedOption == option;

                      return TradeRepublicTap(
                        onTap: () {
                          onOptionSelected(option);
                          Navigator.pop(context);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue.withOpacity(0.15)
                                : (isLight ? Colors.black : Colors.white)
                                      .withOpacity(isLight ? 0.05 : 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Text(
                                option,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.blue
                                      : (isLight ? Colors.black : Colors.white),
                                  fontSize: 16,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              const Spacer(),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
        ),
      );
    } else {
      // Use regular BottomSheet for shorter lists
      TradeRepublicBottomSheet.show(
        context: context,
        bottomPadding: 20.0,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DragHandle(),
              Row(
                children: [
                  Icon(CupertinoIcons.list_bullet, size: 22, color: isLight ? Colors.black : Colors.white),
                  const SizedBox(width: 12),
                  Flexible(child: Text(
                    title,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                  )),
                ],
              ),
              const SizedBox(height: 4),

              Column(
                children: options.map((option) {
                  final isSelected = selectedOption == option;

                  return TradeRepublicTap(
                    onTap: () {
                      onOptionSelected(option);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blue.withOpacity(0.15)
                            : (isLight ? Colors.black : Colors.white)
                                  .withOpacity(isLight ? 0.05 : 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            option,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.blue
                                  : (isLight ? Colors.black : Colors.white),
                              fontSize: 16,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          const Spacer(),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle,
                              color: Colors.blue,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
      );
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _businessNameController.dispose();
    _businessEmailController.dispose();
    _businessPhoneController.dispose();
    _businessAddressController.dispose();
    _businessDescriptionController.dispose();
    _businessWebsiteController.dispose();
    _taxVatNumberController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _businessLogoPath = image.path;
        });
        print('📸 Gallery image selected: ${image.path}');

        // Show success notification for logo selection
        NotificationHelper.showImageUploadSuccess(context, 'gallery');
      }
    } catch (e) {
      print('❌ Gallery picker error: $e');
      if (mounted) {
        NotificationHelper.showImageUploadError(context, 'gallery');
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _businessLogoPath = image.path;
        });
        print('📸 Camera image captured: ${image.path}');

        // Show success notification for camera capture
        NotificationHelper.showImageUploadSuccess(context, 'camera');
      }
    } catch (e) {
      print('❌ Camera picker error: $e');
      if (mounted) {
        NotificationHelper.showImageUploadError(context, 'camera');
      }
    }
  }
}
