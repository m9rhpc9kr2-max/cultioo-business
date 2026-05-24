import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../config/api_config.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';


class DriverStep1PersonalInfo extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final VoidCallback? onNext;
  final VoidCallback? onBack;

  const DriverStep1PersonalInfo({
    super.key,
    required this.initialData,
    this.onNext,
    this.onBack,
  });

  @override
  State<DriverStep1PersonalInfo> createState() =>
      _DriverStep1PersonalInfoState();
}

class _DriverStep1PersonalInfoState extends State<DriverStep1PersonalInfo> {
  // Form key for validation
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers for ID document style fields
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _streetNumberController = TextEditingController();
  final TextEditingController _zipCodeController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();

  // Countries data structure with ISO codes - North America + EU countries
  Map<String, Map<String, String>> get _countriesWithCodes => {
    // North America
    'United States': {'code': '+1', 'iso': 'US'},
    'Canada': {'code': '+1', 'iso': 'CA'},
    'Mexico': {'code': '+52', 'iso': 'MX'},
    // UK & Switzerland
    'United Kingdom': {'code': '+44', 'iso': 'GB'},
    'Switzerland': {'code': '+41', 'iso': 'CH'},
    // EU Countries (alphabetical)
    'Austria': {'code': '+43', 'iso': 'AT'},
    'Belgium': {'code': '+32', 'iso': 'BE'},
    'Bulgaria': {'code': '+359', 'iso': 'BG'},
    'Croatia': {'code': '+385', 'iso': 'HR'},
    'Cyprus': {'code': '+357', 'iso': 'CY'},
    'Czech Republic': {'code': '+420', 'iso': 'CZ'},
    'Denmark': {'code': '+45', 'iso': 'DK'},
    'Estonia': {'code': '+372', 'iso': 'EE'},
    'Finland': {'code': '+358', 'iso': 'FI'},
    'France': {'code': '+33', 'iso': 'FR'},
    'Germany': {'code': '+49', 'iso': 'DE'},
    'Greece': {'code': '+30', 'iso': 'GR'},
    'Hungary': {'code': '+36', 'iso': 'HU'},
    'Ireland': {'code': '+353', 'iso': 'IE'},
    'Italy': {'code': '+39', 'iso': 'IT'},
    'Latvia': {'code': '+371', 'iso': 'LV'},
    'Lithuania': {'code': '+370', 'iso': 'LT'},
    'Luxembourg': {'code': '+352', 'iso': 'LU'},
    'Malta': {'code': '+356', 'iso': 'MT'},
    'Netherlands': {'code': '+31', 'iso': 'NL'},
    'Poland': {'code': '+48', 'iso': 'PL'},
    'Portugal': {'code': '+351', 'iso': 'PT'},
    'Romania': {'code': '+40', 'iso': 'RO'},
    'Slovakia': {'code': '+421', 'iso': 'SK'},
    'Slovenia': {'code': '+386', 'iso': 'SI'},
    'Spain': {'code': '+34', 'iso': 'ES'},
    'Sweden': {'code': '+46', 'iso': 'SE'},
  };

  // Helper to convert ISO code to flag emoji
  String _isoToFlag(String iso) {
    // Convert ISO code (e.g., "US") to flag emoji (🇺🇸)
    // Each letter becomes a regional indicator symbol
    final int base = 0x1F1E6 - 65; // 'A' = 65
    return String.fromCharCodes(
      iso.toUpperCase().codeUnits.map((c) => base + c),
    );
  }

  // Selected values
  String? _selectedCountryString;
  String _selectedPhoneCode = '+1'; // Default to USA
  String _selectedPhoneIso = 'US'; // Default ISO code

  // Password visibility
  bool _passwordVisible = false;
  bool get _obscurePassword => !_passwordVisible;

  // Error states for validation
  bool _firstNameError = false;
  bool _lastNameError = false;
  bool _birthdateError = false;
  bool _emailError = false;
  bool _phoneError = false;
  bool _usernameError = false;
  bool _passwordError = false;
  bool _confirmPasswordError = false;
  bool _countryError = false;
  bool _streetError = false;
  bool _streetNumberError = false;
  bool _zipCodeError = false;
  bool _cityError = false;

  // Username availability checking
  Timer? _usernameCheckTimer;
  bool _isCheckingUsername = false;
  bool?
  _usernameAvailable; // null = not checked, true = available, false = taken
  String _lastCheckedUsername = '';

  // Email availability checking
  Timer? _emailCheckTimer;
  bool _isCheckingEmail = false;
  bool? _emailAvailable; // null = not checked, true = available, false = taken
  String _lastCheckedEmail = '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _setupUsernameListener();
    _setupEmailListener();
  }

  void _setupUsernameListener() {
    _usernameController.addListener(() {
      final username = _usernameController.text;

      // Cancel previous timer
      _usernameCheckTimer?.cancel();

      // Reset state if username is too short
      if (username.isEmpty || username.length < 3) {
        setState(() {
          _usernameAvailable = null;
          _isCheckingUsername = false;
        });
        return;
      }

      // Don't check if it's the same as last checked
      if (username == _lastCheckedUsername && _usernameAvailable != null) {
        return;
      }

      // Set checking state
      setState(() {
        _isCheckingUsername = true;
        _usernameAvailable = null;
      });

      // Start new timer (wait 800ms after user stops typing)
      _usernameCheckTimer = Timer(const Duration(milliseconds: 800), () {
        _checkUsernameLive(username);
      });
    });
  }

  void _setupEmailListener() {
    _emailController.addListener(() {
      final email = _emailController.text;

      // Cancel previous timer
      _emailCheckTimer?.cancel();

      // Reset state if email is invalid
      if (email.isEmpty ||
          !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        setState(() {
          _emailAvailable = null;
          _isCheckingEmail = false;
        });
        return;
      }

      // Don't check if it's the same as last checked
      if (email == _lastCheckedEmail && _emailAvailable != null) {
        return;
      }

      // Set checking state
      setState(() {
        _isCheckingEmail = true;
        _emailAvailable = null;
      });

      // Start new timer (wait 800ms after user stops typing)
      _emailCheckTimer = Timer(const Duration(milliseconds: 800), () {
        _checkEmailLive(email);
      });
    });
  }

  void _loadInitialData() {
    // NOTE: This runs inside initState(), so we CANNOT use
    // AppLocalizations.of(context) here — inherited widgets are not yet
    // available. Empty-string fallbacks are sufficient for pre-filled data.
    _firstNameController.text = widget.initialData['firstName'] ?? '';
    _lastNameController.text = widget.initialData['lastName'] ?? '';
    _birthdateController.text = widget.initialData['birthdate'] ?? '';
    _emailController.text = widget.initialData['email'] ?? '';
    _usernameController.text = widget.initialData['username'] ?? '';
    _selectedCountryString = widget.initialData['country'];
    _streetController.text = widget.initialData['street'] ?? '';
    _streetNumberController.text = widget.initialData['streetNumber'] ?? '';
    _zipCodeController.text = widget.initialData['zipCode'] ?? '';
    _cityController.text = widget.initialData['city'] ?? '';

    // Parse phone number and code
    String fullPhone = widget.initialData['phone'] ?? '';
    if (fullPhone.isNotEmpty) {
      // Split by space to get code and number
      List<String> phoneParts = fullPhone.split(' ');
      if (phoneParts.length >= 2) {
        _selectedPhoneCode = phoneParts[0]; // e.g., "+1"
        _phoneController.text = phoneParts
            .sublist(1)
            .join(' '); // rest of the number

        // Set the corresponding ISO code by looking up in countries map
        for (var entry in _countriesWithCodes.entries) {
          if (entry.value['code'] == _selectedPhoneCode) {
            _selectedPhoneIso = entry.value['iso']!;
            break;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _usernameCheckTimer?.cancel();
    _emailCheckTimer?.cancel();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _birthdateController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _streetController.dispose();
    _streetNumberController.dispose();
    _zipCodeController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  // Date picker method (US format) - iOS drum-roll style
  Future<void> _selectDate(BuildContext context) async {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false,
    );
    final isLight = appSettings.isLightMode(context);
    final loc = AppLocalizations.of(context);

    DateTime selectedDate = DateTime.now().subtract(
      const Duration(days: 6570),
    ); // default: 18 years ago

    // Parse existing date if available (MM/DD/YYYY)
    if (_birthdateController.text.isNotEmpty) {
      try {
        final parts = _birthdateController.text.split('/');
        if (parts.length == 3) {
          selectedDate = DateTime(
            int.parse(parts[2]), // year
            int.parse(parts[0]), // month
            int.parse(parts[1]), // day
          );
        }
      } catch (_) {}
    }

    await TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),

          // ── Header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    CupertinoIcons.calendar,
                    size: 20,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  loc?.dateOfBirth ?? AppLocalizations.of(context)!.tr('Date of Birth'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── iOS drum-roll picker ─────────────────────────────────────
          SizedBox(
            height: 216,
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: isLight ? Brightness.light : Brightness.dark,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: selectedDate,
                minimumDate: DateTime(1924),
                maximumDate: DateTime.now().subtract(
                  const Duration(days: 6570),
                ),
                onDateTimeChanged: (DateTime newDate) {
                  selectedDate = newDate;
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Confirm button ───────────────────────────────────────────
          TradeRepublicButton(
            label: loc?.confirm ?? AppLocalizations.of(context)!.tr('Confirm'),
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                // MM/DD/YYYY
                _birthdateController.text =
                    '${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.year}';
                _birthdateError = false;
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // Live check without dialog (silent)
  Future<void> _checkUsernameLive(String username) async {
    try {
      print('DEBUG: Live checking username: $username');

      final String baseUrl = ApiConfig.baseUrl;
      final String apiEndpoint =
          '$baseUrl/api/auth/check-username?username=${Uri.encodeComponent(username)}';

      final response = await http
          .get(
            Uri.parse(apiEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      print('DEBUG: Response status code: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        setState(() {
          _lastCheckedUsername = username;
          _usernameAvailable = data['available'] == true;
          _isCheckingUsername = false;

          if (_usernameAvailable == false) {
            _usernameError = true;
          } else {
            _usernameError = false;
          }
        });

        print('DEBUG: Username available: $_usernameAvailable');
      } else {
        setState(() {
          _isCheckingUsername = false;
          _usernameAvailable = null;
        });
      }
    } catch (e) {
      print('DEBUG: Error checking username: $e');
      setState(() {
        _isCheckingUsername = false;
        _usernameAvailable = null;
      });
    }
  }

  // Live check email without dialog (silent)
  Future<void> _checkEmailLive(String email) async {
    try {
      print('DEBUG: Live checking email: $email');

      final String baseUrl = ApiConfig.baseUrl;
      final String apiEndpoint =
          '$baseUrl/api/auth/check-email?email=${Uri.encodeComponent(email)}';

      final response = await http
          .get(
            Uri.parse(apiEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      print('DEBUG: Response status code: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        setState(() {
          _lastCheckedEmail = email;
          _emailAvailable = data['exists'] != true;
          _isCheckingEmail = false;

          if (_emailAvailable == false) {
            _emailError = true;
          } else {
            _emailError = false;
          }
        });

        print('DEBUG: Email available: $_emailAvailable');
      } else {
        setState(() {
          _isCheckingEmail = false;
          _emailAvailable = null;
        });
      }
    } catch (e) {
      print('DEBUG: Error checking email: $e');
      setState(() {
        _isCheckingEmail = false;
        _emailAvailable = null;
      });
    }
  }

  // Check username availability with Google Cloud Database (with dialog)
  Future<bool> _checkUsernameAvailability(String username) async {
    try {
      print('DEBUG: Checking username availability for: $username');

      // Show loading indicator
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

      // Use backend API endpoint from ApiConfig (supports Google Cloud)
      final String baseUrl = ApiConfig.baseUrl;
      final String apiEndpoint =
          '$baseUrl/api/auth/check-username?username=${Uri.encodeComponent(username)}';

      print('DEBUG: Making request to: $apiEndpoint');

      final response = await http
          .get(
            Uri.parse(apiEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      // Close loading dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('DEBUG: Response status code: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        print('DEBUG: Parsed response data: $data');

        if (data['available'] == false) {
          // Username is taken
          print('DEBUG: Username is already taken');
          TopNotification.error(
            context,
            'Username "$username" is already taken. Please choose a different one.',
          );
          return false;
        } else {
          // Username is available
          print('DEBUG: Username is available');
          TopNotification.success(
            context,
            'Username "$username" is available!',
          );
          return true;
        }
      } else {
        print(
          'DEBUG: HTTP error - status code: ${response.statusCode}, body: ${response.body}',
        );
        throw Exception('Failed to check username: ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: Exception caught during username check: $e');
      print('DEBUG: Exception type: ${e.runtimeType}');

      // Close loading dialog if still open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      String errorMessage = 'Unknown error';
      if (e.toString().contains('TimeoutException')) {
        errorMessage =
            'Connection timeout. Please check your internet connection.';
      } else if (e.toString().contains('SocketException')) {
        errorMessage = 'Network error. Please check your connection.';
      } else if (e.toString().contains('FormatException')) {
        errorMessage = 'Invalid response from server.';
      } else {
        errorMessage = e.toString();
      }

      // Handle API error
      TopNotification.error(context, '${AppLocalizations.of(context)?.errorCheckingUsername ?? AppLocalizations.of(context)!.tr('Error checking username')}: $errorMessage');

      // In case of error, allow user to continue (you might want to change this behavior)
      return true;
    }
  }

  // Validation method
  void _validateAndContinue() async {
    bool isValid = true;

    // Reset all error states
    setState(() {
      _firstNameError = false;
      _lastNameError = false;
      _birthdateError = false;
      _emailError = false;
      _phoneError = false;
      _usernameError = false;
      _passwordError = false;
      _confirmPasswordError = false;
      _countryError = false;
      _streetError = false;
      _streetNumberError = false;
      _zipCodeError = false;
      _cityError = false;
    });

    // Validate individual fields and set error states
    if (_firstNameController.text.isEmpty) {
      _firstNameError = true;
      isValid = false;
    }

    if (_lastNameController.text.isEmpty) {
      _lastNameError = true;
      isValid = false;
    }

    if (_birthdateController.text.isEmpty) {
      _birthdateError = true;
      isValid = false;
    }

    if (_emailController.text.isEmpty ||
        !RegExp(
          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
        ).hasMatch(_emailController.text)) {
      _emailError = true;
      isValid = false;
    }

    if (_phoneController.text.isEmpty) {
      _phoneError = true;
      isValid = false;
    }

    if (_usernameController.text.isEmpty ||
        _usernameController.text.length < 3) {
      _usernameError = true;
      isValid = false;
    }

    if (_passwordController.text.isEmpty ||
        _passwordController.text.length < 6) {
      _passwordError = true;
      isValid = false;
    }

    if (_confirmPasswordController.text.isEmpty ||
        _confirmPasswordController.text != _passwordController.text) {
      _confirmPasswordError = true;
      isValid = false;
    }

    if (_selectedCountryString == null) {
      _countryError = true;
      isValid = false;
    }

    if (_streetController.text.isEmpty) {
      _streetError = true;
      isValid = false;
    }

    if (_streetNumberController.text.isEmpty) {
      _streetNumberError = true;
      isValid = false;
    }

    if (_zipCodeController.text.isEmpty) {
      _zipCodeError = true;
      isValid = false;
    }

    if (_cityController.text.isEmpty) {
      _cityError = true;
      isValid = false;
    }

    // Update UI to show errors
    if (!isValid) {
      setState(() {});
      return;
    }

    // Check email availability if form is valid so far
    if (_emailController.text.isNotEmpty) {
      // If email was already checked and is not available, block
      if (_emailAvailable == false) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.tr('This email is already registered. Please use a different email.') ?? AppLocalizations.of(context)!.tr('This email is already registered. Please use a different email.'),
        );
        setState(() {
          _emailError = true;
        });
        return;
      }

      // If email wasn't checked yet, check it now
      if (_emailAvailable == null) {
        await _checkEmailLive(_emailController.text);
        // Check result after live check
        if (_emailAvailable == false) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.tr('This email is already registered. Please use a different email.') ?? AppLocalizations.of(context)!.tr('This email is already registered. Please use a different email.'),
          );
          setState(() {
            _emailError = true;
          });
          return;
        }
      }
    }

    // Check username availability if form is valid so far
    if (_usernameController.text.isNotEmpty) {
      // If username was already checked and is not available, block
      if (_usernameAvailable == false) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.tr('This username is already taken. Please choose a different username.') ?? AppLocalizations.of(context)!.tr('This username is already taken. Please choose a different username.'),
        );
        setState(() {
          _usernameError = true;
        });
        return;
      }

      // If username wasn't checked yet, check it now
      if (_usernameAvailable == null) {
        bool usernameAvailable = await _checkUsernameAvailability(
          _usernameController.text,
        );
        if (!usernameAvailable) {
          setState(() {
            _usernameError = true;
          });
          return;
        }
      }
    }

    if (isValid) {
      // Create data map for sharing across steps
      final Map<String, dynamic> formData = {
        'firstName': _firstNameController.text,
        'lastName': _lastNameController.text,
        'birthdate': _birthdateController.text,
        'email': _emailController.text,
        'username': _usernameController.text,
        'password': _passwordController.text, // ← PASSWORD ADDED!
        'phone': '$_selectedPhoneCode ${_phoneController.text}',
        'country': _selectedCountryString,
        'street': _streetController.text,
        'streetNumber': _streetNumberController.text,
        'zipCode': _zipCodeController.text,
        'city': _cityController.text,
      };

      // Add to widget.initialData if it's modifiable, otherwise use our own copy
      try {
        widget.initialData.addAll(formData);
      } catch (e) {
        // Handle unmodifiable map by using our own data
        print('DEBUG: initialData is unmodifiable, using local data copy');
      }

      // Debug: Print saved data
      print('DEBUG Step 1: Saved data: $formData');

      // Use the onNext callback if provided
      if (widget.onNext != null) {
        widget.onNext!();
      } else {
        // Fallback navigation to simple step 2
        Navigator.pushNamed(context, '/driver-step2');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);

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
              // Back Button (top left)
              Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: TradeRepublicButton.icon(
                      icon: Icon(CupertinoIcons.chevron_back, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 24),

              // Main Header
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
                        CupertinoIcons.person_add,
                        color: isLight ? Colors.white : Colors.black,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.of(context)?.personalInformation ?? AppLocalizations.of(context)!.tr('Personal Information'),
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)?.stepOfDriverRegistration ?? AppLocalizations.of(context)!.tr('Step 1 of 10 - Driver Registration'),
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

              // PERSONAL DETAILS SECTION
              _buildSectionHeader('Personal Details', isLight),
              const SizedBox(height: 16),

              // Name Fields Row
              Row(
                children: [
                  Expanded(
                    child: _buildModernTextField(
                      controller: _firstNameController,
                      label: AppLocalizations.of(context)?.firstName ?? AppLocalizations.of(context)!.tr('First Name'),
                      icon: CupertinoIcons.person,
                      isLight: isLight,
                      hasError: _firstNameError,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLocalizations.of(context)?.pleaseEnterFirstName ?? AppLocalizations.of(context)!.tr('Please enter your first name');
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildModernTextField(
                      controller: _lastNameController,
                      label: AppLocalizations.of(context)?.lastName ?? AppLocalizations.of(context)!.tr('Last Name'),
                      icon: CupertinoIcons.person,
                      isLight: isLight,
                      hasError: _lastNameError,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLocalizations.of(context)?.pleaseEnterLastName ?? AppLocalizations.of(context)!.tr('Please enter your last name');
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Birthdate Field
              _buildDateField(isLight, hasError: _birthdateError),

              const SizedBox(height: 32),

              // CONTACT INFORMATION SECTION
              _buildSectionHeader('Contact Information', isLight),
              const SizedBox(height: 16),

              // Email Field with Live Availability Check
              _buildEmailFieldWithLiveCheck(isLight),

              const SizedBox(height: 16),

              // Phone Field with Country Code
              _buildPhoneFieldWithCode(isLight, hasError: _phoneError),

              const SizedBox(height: 32),

              // ACCOUNT SECTION
              _buildSectionHeader('Account Information', isLight),
              const SizedBox(height: 16),

              // Username Field with Live Availability Check
              _buildUsernameFieldWithLiveCheck(isLight),

              const SizedBox(height: 16),

              // Password Field
              _buildModernTextField(
                controller: _passwordController,
                label: AppLocalizations.of(context)?.password ?? AppLocalizations.of(context)!.tr('Password'),
                icon: CupertinoIcons.lock,
                isLight: isLight,
                hasError: _passwordError,
                obscureText: _obscurePassword,
                suffixIcon: TradeRepublicTap(
                  onTap: () {
                    setState(() {
                      _passwordVisible = !_passwordVisible;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      _obscurePassword
                          ? CupertinoIcons.eye_slash
                          : CupertinoIcons.eye,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 20,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)?.pleaseEnterPassword ?? AppLocalizations.of(context)!.tr('Please enter a password');
                  }
                  if (value.length < 6) {
                    return AppLocalizations.of(context)?.passwordMustBeAtLeast6Chars ?? AppLocalizations.of(context)!.tr('Password must be at least 6 characters');
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Confirm Password Field
              _buildModernTextField(
                controller: _confirmPasswordController,
                label: AppLocalizations.of(context)?.confirmPassword ?? AppLocalizations.of(context)!.tr('Confirm Password'),
                icon: CupertinoIcons.lock,
                isLight: isLight,
                hasError: _confirmPasswordError,
                obscureText: _obscurePassword,
                suffixIcon: TradeRepublicTap(
                  onTap: () {
                    setState(() {
                      _passwordVisible = !_passwordVisible;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      _obscurePassword
                          ? CupertinoIcons.eye_slash
                          : CupertinoIcons.eye,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 20,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return AppLocalizations.of(context)?.pleaseConfirmPassword ?? AppLocalizations.of(context)!.tr('Please confirm your password');
                  }
                  if (value != _passwordController.text) {
                    return AppLocalizations.of(context)?.passwordsDoNotMatch ?? AppLocalizations.of(context)!.tr('Passwords do not match');
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // ADDRESS SECTION
              _buildSectionHeader('Address Information', isLight),
              const SizedBox(height: 16),

              // Street and Number Row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildModernTextField(
                      controller: _streetController,
                      label: AppLocalizations.of(context)?.streetName ?? AppLocalizations.of(context)!.tr('Street Name'),
                      icon: CupertinoIcons.house,
                      isLight: isLight,
                      hasError: _streetError,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLocalizations.of(context)?.pleaseEnterStreetName ?? AppLocalizations.of(context)!.tr('Please enter street name');
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: _buildModernTextField(
                      controller: _streetNumberController,
                      label: AppLocalizations.of(context)?.nr ?? AppLocalizations.of(context)!.tr('Nr'),
                      icon: CupertinoIcons.number,
                      isLight: isLight,
                      hasError: _streetNumberError,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ZIP and City Row
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: _buildModernTextField(
                      controller: _zipCodeController,
                      label: AppLocalizations.of(context)?.zip ?? AppLocalizations.of(context)!.tr('ZIP'),
                      icon: CupertinoIcons.location,
                      isLight: isLight,
                      hasError: _zipCodeError,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLocalizations.of(context)?.pleaseEnterZipCode ?? AppLocalizations.of(context)!.tr('Please enter ZIP code');
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _buildModernTextField(
                      controller: _cityController,
                      label: AppLocalizations.of(context)?.city ?? AppLocalizations.of(context)!.tr('City'),
                      icon: CupertinoIcons.building_2_fill,
                      isLight: isLight,
                      hasError: _cityError,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLocalizations.of(context)?.pleaseEnterCity ?? AppLocalizations.of(context)!.tr('Please enter city');
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Country Field
              _buildCountryField(isLight, hasError: _countryError),

              const SizedBox(height: 40),

              // Continue Button
              TradeRepublicButton(
                label: AppLocalizations.of(context)?.continueAction ?? AppLocalizations.of(context)!.tr('Continue'),
                icon: Icon(CupertinoIcons.arrow_right, size: 18),
                onPressed: _validateAndContinue,
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }

  // Section Header Builder
  Widget _buildSectionHeader(String title, bool isLight) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: isLight ? Colors.black : Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // Modern TextField Builder
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isLight,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
    VoidCallback? onTap,
    bool readOnly = false,
    Widget? suffixIcon,
    bool hasError = false,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final container = Container(
      margin: const EdgeInsets.only(bottom: 16),
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
            // Clean header with icon and title
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
                    size: 18,
                    color: isLight ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // TradeRepublicTextField without extra wrapper
            TradeRepublicTextField(
              useFormField: true,
              controller: controller,
              keyboardType: keyboardType,
              obscureText: obscureText,
              showVisibilityToggle: obscureText,
              validator: validator,
              inputFormatters: inputFormatters,
              readOnly: readOnly,
              hintText: '${AppLocalizations.of(context)?.enterLabel ?? AppLocalizations.of(context)!.tr('Enter')} $label',
              suffixIcon: suffixIcon,
            ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return TradeRepublicTap(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AbsorbPointer(child: container),
      );
    }
    return container;
  }

  // Phone Field with Country Code
  Widget _buildPhoneFieldWithCode(bool isLight, {bool hasError = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      height: 140, // Increased height for better input field size
      decoration: BoxDecoration(
        color: hasError ? Colors.red.withOpacity(0.08) : (isLight ? Colors.white : Colors.black),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Clean header with icon and title
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
                    CupertinoIcons.phone,
                    size: 18,
                    color: isLight ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.phoneNumber ?? AppLocalizations.of(context)!.tr('Phone Number'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Enhanced phone input with TradeRepublicTextField styling
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    isLight ? 0.05 : 0.05,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    // Country Code Dropdown with Flag
                    TradeRepublicTap(
                      onTap: () => _showPhoneCodeBottomSheet(context, isLight),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            bottomLeft: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isoToFlag(_selectedPhoneIso),
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedPhoneCode,
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              CupertinoIcons.chevron_down,
                              size: 10,
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Separator
                    Container(
                      width: 1,
                      height: double.infinity,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.1),
                    ),
                    // Phone Number Field
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: TradeRepublicTextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          useFormField: true,
                          inputFormatters: _selectedPhoneCode == '+1'
                              ? [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(
                                    10,
                                  ), // US format: 10 digits
                                  _USPhoneFormatter(),
                                ]
                              : [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(
                                    15,
                                  ), // Max 15 digits for international numbers
                                ],
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                          hintText: _selectedPhoneCode == '+1'
                              ? '(555) 123-4567'
                              : AppLocalizations.of(context)?.phoneNumber ?? AppLocalizations.of(context)!.tr('Phone Number'),
                          hintStyle: TextStyle(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.5),
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                          filled: false,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return AppLocalizations.of(context)?.pleaseEnterPhoneNumber ?? AppLocalizations.of(context)!.tr('Please enter your phone number');
                            }

                            // Different validation for US numbers vs international
                            if (_selectedPhoneCode == '+1') {
                              // US phone number validation
                              final digitsOnly = value.replaceAll(
                                RegExp(r'[^\d]'),
                                '',
                              );
                              if (digitsOnly.length != 10) {
                                return AppLocalizations.of(context)?.pleaseEnterValidUsPhoneNumber ?? AppLocalizations.of(context)!.tr('Please enter a valid US phone number');
                              }
                            } else {
                              // International phone number validation
                              if (value.length < 7) {
                                return AppLocalizations.of(context)?.phoneNumberTooShort ?? AppLocalizations.of(context)!.tr('Phone number too short');
                              }
                              if (value.length > 15) {
                                return AppLocalizations.of(context)?.phoneNumberTooLong ?? AppLocalizations.of(context)!.tr('Phone number too long');
                              }
                              // Basic format check - only digits allowed
                              if (!RegExp(r'^\d+$').hasMatch(value)) {
                                return AppLocalizations.of(context)?.pleaseEnterOnlyNumbers ?? AppLocalizations.of(context)!.tr('Please enter only numbers');
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show Phone Code Bottom Sheet
  void _showPhoneCodeBottomSheet(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
              children: [
                DragHandle(),

                Row(
                  children: [
                    Icon(CupertinoIcons.phone, size: 22, color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 12),
                    Flexible(child: Text(
                      AppLocalizations.of(context)?.countryCode ?? AppLocalizations.of(context)!.tr('Country Code'),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                    )),
                  ],
                ),

                const SizedBox(height: 20),

                // Scrollable Options
                Expanded(
                  child: ListView(
                    children: _countriesWithCodes.entries.map((entry) {
                      final countryName = entry.key;
                      final countryData = entry.value;
                      final isSelected =
                          _selectedPhoneCode == countryData['code'];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildBottomSheetOption(
                          countryName,
                          countryData['code']!,
                          countryData['iso']!,
                          isSelected,
                          () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _selectedPhoneCode = countryData['code']!;
                              _selectedPhoneIso = countryData['iso']!;
                              // Clear phone number when changing country code to avoid format conflicts
                              _phoneController.clear();
                            });
                            Navigator.pop(context);
                          },
                          isLight,
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 12),

                // Cancel button
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                  isSecondary: true,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
      );
  }

  Widget _buildBottomSheetOption(
    String countryName,
    String countryCode,
    String isoCode,
    bool isSelected,
    VoidCallback onTap,
    bool isLight,
  ) {
    return TradeRepublicTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : (isLight
                    ? Colors.black.withOpacity(0.04)
                    : const Color(0xFF121212)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text(_isoToFlag(isoCode), style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$countryName ($countryCode)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? (isLight ? Colors.white : Colors.black)
                      : (isLight ? Colors.black : Colors.white),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                CupertinoIcons.check_mark_circled,
                color: isLight ? Colors.white : Colors.black,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  // Date Field
  Widget _buildDateField(bool isLight, {bool hasError = false}) {
    return _buildModernTextField(
      controller: _birthdateController,
      label: AppLocalizations.of(context)?.dateOfBirth ?? AppLocalizations.of(context)!.tr('Date of Birth'),
      icon: CupertinoIcons.calendar,
      isLight: isLight,
      hasError: hasError,
      readOnly: true,
      onTap: () => _selectDate(context),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return AppLocalizations.of(context)?.pleaseSelectDateOfBirth ?? AppLocalizations.of(context)!.tr('Please select your date of birth');
        }
        return null;
      },
    );
  }

  // Country Field
  Widget _buildCountryField(bool isLight, {bool hasError = false}) {
    return TradeRepublicTap(
      onTap: () => _showCountryBottomSheet(context, isLight),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 140, // Increased height for better input field size
        decoration: BoxDecoration(
          color: hasError ? Colors.red.withOpacity(0.08) : (isLight ? Colors.white : Colors.black),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clean header with icon and title
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
                      CupertinoIcons.globe,
                      size: 18,
                      color: isLight ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.country ?? AppLocalizations.of(context)!.tr('Country'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Enhanced country selector with gray background
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.05,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedCountryString ?? AppLocalizations.of(context)?.selectCountry ?? AppLocalizations.of(context)!.tr('Select Country'),
                          style: TextStyle(
                            color: _selectedCountryString != null
                                ? (isLight ? Colors.black : Colors.white)
                                : (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_down,
                        size: 16,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Show Country Bottom Sheet
  void _showCountryBottomSheet(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
              children: [
                DragHandle(),

                Row(
                  children: [
                    Icon(CupertinoIcons.globe, size: 22, color: isLight ? Colors.black : Colors.white),
                    const SizedBox(width: 12),
                    Flexible(child: Text(
                      AppLocalizations.of(context)?.selectCountry ?? AppLocalizations.of(context)!.tr('Select Country'),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                    )),
                  ],
                ),

                const SizedBox(height: 20),

                // Scrollable Options
                Expanded(
                  child: ListView(
                    children: _countriesWithCodes.entries.map((entry) {
                      final countryName = entry.key;
                      final countryData = entry.value;
                      final isSelected = _selectedCountryString == countryName;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildCountryBottomSheetOption(
                          countryName,
                          countryData['iso']!,
                          isSelected,
                          () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _selectedCountryString = countryName;
                            });
                            Navigator.pop(context);
                          },
                          isLight,
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 12),

                // Cancel button
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                  isSecondary: true,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
      );
  }

  Widget _buildCountryBottomSheetOption(
    String countryName,
    String isoCode,
    bool isSelected,
    VoidCallback onTap,
    bool isLight,
  ) {
    return TradeRepublicTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : (isLight
                    ? Colors.black.withOpacity(0.04)
                    : const Color(0xFF121212)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text(_isoToFlag(isoCode), style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                countryName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? (isLight ? Colors.white : Colors.black)
                      : (isLight ? Colors.black : Colors.white),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                CupertinoIcons.check_mark_circled,
                color: isLight ? Colors.white : Colors.black,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  // Build Username Field with Live Availability Check
  Widget _buildUsernameFieldWithLiveCheck(bool isLight) {
    Color borderColor;
    Widget? suffixIcon;
    String? helperText;
    Color? helperColor;

    // Determine state
    if (_isCheckingUsername) {
      borderColor = isLight ? Colors.blue : Colors.blue;
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CultiooLoadingIndicator(size: 20),
        ),
      );
      helperText = AppLocalizations.of(context)?.checkingAvailability ?? AppLocalizations.of(context)!.tr('Checking availability...');
      helperColor = Colors.blue;
    } else if (_usernameAvailable == true) {
      borderColor = Colors.green;
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(
          CupertinoIcons.checkmark_circle_fill,
          color: Colors.green,
          size: 20,
        ),
      );
      helperText = AppLocalizations.of(context)?.usernameIsAvailable ?? AppLocalizations.of(context)!.tr('✓ Username is available');
      helperColor = Colors.green;
    } else if (_usernameAvailable == false) {
      borderColor = Colors.red;
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(
          CupertinoIcons.xmark_circle_fill,
          color: Colors.red,
          size: 20,
        ),
      );
      helperText = AppLocalizations.of(context)?.usernameIsAlreadyTaken ?? AppLocalizations.of(context)!.tr('✗ Username is already taken');
      helperColor = Colors.red;
    } else {
      borderColor = _usernameError
          ? Colors.red
          : (isLight ? Colors.black : Colors.white);
      suffixIcon = null;
      helperText = null;
      helperColor = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _usernameError
                ? Colors.red.withOpacity(0.08)
                : (isLight
                    ? Colors.black.withOpacity(0.04)
                    : const Color(0xFF121212)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Icon(
                  CupertinoIcons.person_circle,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.5,
                  ),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TradeRepublicTextField(
                  controller: _usernameController,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                    LowerCaseTextFormatter(),
                  ],
                  hintText: AppLocalizations.of(context)?.username ?? AppLocalizations.of(context)!.tr('Username'),
                ),
              ),
              if (suffixIcon != null) suffixIcon,
              if (suffixIcon == null) const SizedBox(width: 20),
            ],
          ),
        ),
        if (helperText != null)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 8),
            child: Text(
              helperText,
              style: TextStyle(
                color: helperColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  // Build Email Field with Live Availability Check
  Widget _buildEmailFieldWithLiveCheck(bool isLight) {
    Color borderColor;
    Widget? suffixIcon;
    String? helperText;
    Color? helperColor;

    // Determine state
    if (_isCheckingEmail) {
      borderColor = isLight ? Colors.blue : Colors.blue;
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CultiooLoadingIndicator(size: 20),
        ),
      );
      helperText = AppLocalizations.of(context)?.checkingAvailability ?? AppLocalizations.of(context)!.tr('Checking availability...');
      helperColor = Colors.blue;
    } else if (_emailAvailable == true) {
      borderColor = Colors.green;
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(
          CupertinoIcons.checkmark_circle_fill,
          color: Colors.green,
          size: 20,
        ),
      );
      helperText = AppLocalizations.of(context)?.emailIsAvailable ?? AppLocalizations.of(context)!.tr('✓ Email is available');
      helperColor = Colors.green;
    } else if (_emailAvailable == false) {
      borderColor = Colors.red;
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(
          CupertinoIcons.xmark_circle_fill,
          color: Colors.red,
          size: 20,
        ),
      );
      helperText = AppLocalizations.of(context)?.emailIsAlreadyRegistered ?? AppLocalizations.of(context)!.tr('✗ Email is already registered');
      helperColor = Colors.red;
    } else {
      borderColor = _emailError
          ? Colors.red
          : (isLight ? Colors.black : Colors.white);
      suffixIcon = null;
      helperText = null;
      helperColor = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _emailError
                ? Colors.red.withOpacity(0.08)
                : (isLight
                    ? Colors.black.withOpacity(0.04)
                    : const Color(0xFF121212)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Icon(
                  CupertinoIcons.mail,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.5,
                  ),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TradeRepublicTextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  hintText: AppLocalizations.of(context)?.emailAddress ?? AppLocalizations.of(context)!.tr('Email Address'),
                ),
              ),
              if (suffixIcon != null) suffixIcon,
              if (suffixIcon == null) const SizedBox(width: 20),
            ],
          ),
        ),
        if (helperText != null)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 8),
            child: Text(
              helperText,
              style: TextStyle(
                color: helperColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// US Phone Number Formatter Class
class _USPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove all non-digit characters
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Limit to 10 digits for US numbers
    if (digitsOnly.length > 10) {
      return oldValue;
    }

    // Format the number
    String formatted = '';
    if (digitsOnly.isNotEmpty) {
      if (digitsOnly.length <= 3) {
        formatted = '($digitsOnly';
      } else if (digitsOnly.length <= 6) {
        formatted =
            '(${digitsOnly.substring(0, 3)}) ${digitsOnly.substring(3)}';
      } else {
        formatted =
            '(${digitsOnly.substring(0, 3)}) ${digitsOnly.substring(3, 6)}-${digitsOnly.substring(6)}';
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Lowercase Text Formatter Class
class LowerCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toLowerCase(),
      selection: newValue.selection,
    );
  }
}
