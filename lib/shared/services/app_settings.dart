import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_localizations.dart';
import '../../utils/number_formatters.dart';

class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  // Keys for SharedPreferences
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyUserType = 'user_type';
  static const String _keyUserId = 'user_id';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyAuthMethod = 'auth_method'; // google, apple, email
  static const String _keyLastApp = 'last_app';
  static const String _keyLastUsedAccount = 'last_used_account';
  static const String _keyStoredAccounts = 'stored_accounts';
  static const String _keyDelviooDistanceUnit = 'delvioo_distance_unit';
  static const String _keyDelviooWeightUnit = 'delvioo_weight_unit';
  static const String _keyDelviooCurrency = 'delvioo_currency';
  static const String _keyDelviooTemperatureUnit = 'delvioo_temperature_unit';
  static const String _keyDelviooNumberFormat = 'delvioo_number_format';
  static const String _keyDelviooTextSize = 'delvioo_text_size';
  static const String _keyMotionDockEnabled = 'motion_dock_enabled';
  static const String _keySelectedTheme = 'selected_theme';
  static const String _keySelectedTextSize = 'selected_text_size';
  static const String _keySelectedLanguage = 'selected_language';
  static const String _keySelectedDateFormat = 'selected_date_format';
  static const String _keyLastMileEnabled = 'last_mile_enabled';
  static const String _keyAiSuggestionRadius = 'ai_suggestion_radius_km';

  bool _motionDockEnabled = true;
  String _selectedTheme = 'System';
  String _selectedTextSize = 'Medium';
  String _selectedLanguage = 'System';
  String _selectedNumberFormat = 'English (1,234.56)';
  String _selectedDateFormat = 'System';
  bool _onboardingCompleted = false;
  bool _dataPermissionGranted = false;
  bool _photosPermissionGranted = false;
  bool _isLoggedIn = false;
  String _userType = 'Business'; // Business or Driver
  bool _autoLoginShown =
      false; // In-memory flag to prevent auto-login modal loops
  String? _userId;
  String? _userName;
  String? _userEmail;
  String? _authToken;
  String? _authMethod; // 'google', 'apple', or 'email'
  String? _lastApp;
  String? _lastUsedAccount;
  List<Map<String, dynamic>> _storedAccounts = [];

  // Delvioo-specific settings
  String _delviooDistanceUnit = 'System';
  String _delviooWeightUnit = 'System';
  String _delviooCurrency = 'System';
  String _delviooTemperatureUnit = 'System';
  String _delviooNumberFormat = 'System';
  String _delviooTextSize = 'Medium';
  bool _lastMileEnabled = true; // Last Mile AI - enabled by default
  double _aiSuggestionRadius = 10.0; // AI order suggestions radius in km

  bool get motionDockEnabled => _motionDockEnabled;
  String get selectedTheme => _selectedTheme;
  String get selectedTextSize => _selectedTextSize;
  String get selectedLanguage => _selectedLanguage;
  String get selectedNumberFormat => _selectedNumberFormat;
  String get selectedDateFormat => _selectedDateFormat;
  bool get onboardingCompleted => _onboardingCompleted;
  bool get dataPermissionGranted => _dataPermissionGranted;
  bool get photosPermissionGranted => _photosPermissionGranted;
  bool get isLoggedIn => _isLoggedIn;
  String get userType => _userType;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  String? get authToken => _authToken;
  String? get authMethod => _authMethod;
  bool get autoLoginShown => _autoLoginShown;

  static String? sanitizeUsername(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.contains(' ')) return null;
    return normalized;
  }

  static String? extractUsernameFromToken(String? token) {
    if (token == null || token.isEmpty) return null;

    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;

      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));

      if (payload is! Map<String, dynamic>) return null;

      return sanitizeUsername(
        payload['username']?.toString() ??
            payload['user']['username']?.toString());
    } catch (_) {
      return null;
    }
  }

  /// Mark that the auto-login modal has been shown this session
  void markAutoLoginShown() {
    _autoLoginShown = true;
    notifyListeners();
  }

  /// Clear the auto-login shown flag (useful on logout or account switch)
  void clearAutoLoginShown() {
    _autoLoginShown = false;
    notifyListeners();
  }

  String? get lastApp => _lastApp;
  String? get lastUsedAccount => _lastUsedAccount;
  List<Map<String, dynamic>> get storedAccounts => List.from(_storedAccounts);

  // Delvioo getters
  String get delviooDistanceUnit => _delviooDistanceUnit;
  String get delviooWeightUnit => _delviooWeightUnit;
  String get delviooCurrency => _delviooCurrency;
  String get delviooTemperatureUnit => _delviooTemperatureUnit;
  String get delviooNumberFormat => _delviooNumberFormat;
  String get delviooTextSize => _delviooTextSize;
  bool get lastMileEnabled => _lastMileEnabled;
  double get aiSuggestionRadius => _aiSuggestionRadius;

  ThemeMode get themeMode {
    switch (_selectedTheme) {
      case 'Light':
        return ThemeMode.light;
      case 'Dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  bool isLightMode(BuildContext context) {
    switch (_selectedTheme) {
      case 'Light':
        return true;
      case 'Dark':
        return false;
      default:
        return Theme.of(context).brightness == Brightness.light;
    }
  }

  Future<void> setMotionDockEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMotionDockEnabled, value);
    _motionDockEnabled = value;
    notifyListeners();
  }

  Future<void> setSelectedTheme(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedTheme, value);
    _selectedTheme = value;
    notifyListeners();
  }

  Future<void> setSelectedTextSize(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedTextSize, value);
    _selectedTextSize = value;
    notifyListeners();
  }

  Future<void> setSelectedLanguage(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedLanguage, value);
    _selectedLanguage = value;
    notifyListeners();
  }

  void setSelectedNumberFormat(String value) {
    _selectedNumberFormat = value;
    notifyListeners();
  }

  Future<void> setSelectedDateFormat(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedDateFormat, value);
    _selectedDateFormat = value;
    notifyListeners();
  }

  void setOnboardingCompleted(bool value) {
    _onboardingCompleted = value;
    notifyListeners();
  }

  void setDataPermissionGranted(bool value) {
    _dataPermissionGranted = value;
    notifyListeners();
  }

  void setPhotosPermissionGranted(bool value) {
    _photosPermissionGranted = value;
    notifyListeners();
  }

  // Delvioo setters
  Future<void> setDelviooDistanceUnit(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDelviooDistanceUnit, value);
    _delviooDistanceUnit = value;
    notifyListeners();
  }

  Future<void> setDelviooWeightUnit(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDelviooWeightUnit, value);
    _delviooWeightUnit = value;
    notifyListeners();
  }

  Future<void> setDelviooCurrency(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDelviooCurrency, value);
    _delviooCurrency = value;
    notifyListeners();
  }

  Future<void> setDelviooTemperatureUnit(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDelviooTemperatureUnit, value);
    _delviooTemperatureUnit = value;
    notifyListeners();
  }

  Future<void> setDelviooNumberFormat(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDelviooNumberFormat, value);
    _delviooNumberFormat = value;
    setNumberFormatStyleIndex(effectiveNumberFormat == '1.234,56' ? 1 : 0);
    notifyListeners();
  }

  Future<void> setDelviooTextSize(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDelviooTextSize, value);
    _delviooTextSize = value;
    notifyListeners();
  }

  Future<void> setLastMileEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLastMileEnabled, value);
    _lastMileEnabled = value;
    notifyListeners();
  }

  Future<void> setAiSuggestionRadius(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyAiSuggestionRadius, value);
    _aiSuggestionRadius = value;
    notifyListeners();
  }

  // Persistent login methods
  Future<void> setIsLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, value);
    _isLoggedIn = value;
    notifyListeners();
  }

  Future<void> setUserType(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserType, value);
    _userType = value;
    notifyListeners();
  }

  Future<void> setUserData({
    required String userId, // Changed from int to String for username
    required String name,
    required String email,
    String? token,
    String? username,
    String? userType, // Add userType parameter
    String? authMethod, // Add authMethod parameter (google, apple, email)
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyUserName, name);
    await prefs.setString(_keyUserEmail, email);

    // Update userType if provided
    if (userType != null) {
      await prefs.setString(_keyUserType, userType);
      _userType = userType;
      print('✅ AppSettings.setUserData() - UserType set to: $userType');
    }

    // Update authMethod if provided
    if (authMethod != null) {
      await prefs.setString(_keyAuthMethod, authMethod);
      _authMethod = authMethod;
      print('✅ AppSettings.setUserData() - AuthMethod set to: $authMethod');
    }

    if (token != null) {
      await prefs.setString(_keyAuthToken, token);
      _authToken = token;
      print(
        '✅ AppSettings.setUserData() - Token saved: ${token.substring(0, 20)}...');
    } else {
      print('⚠️ AppSettings.setUserData() - No token provided!');
    }

    final resolvedUsername =
        sanitizeUsername(username) ??
        extractUsernameFromToken(token) ??
        sanitizeUsername(userId);

    if (resolvedUsername != null) {
      await prefs.setString('username', resolvedUsername);
      print(
        '✅ AppSettings.setUserData() - Username saved: $resolvedUsername');
    } else {
      print('⚠️ AppSettings.setUserData() - No valid username resolved');
    }

    _userId = userId;
    _userName = name;
    _userEmail = email;

    // Save this account as the last used account
    await _saveLastUsedAccount();

    // Mark onboarding as completed when first account is saved
    if (!_onboardingCompleted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);
      _onboardingCompleted = true;
    }

    notifyListeners();
  }

  Future<void> _saveLastUsedAccount() async {
    if (_userId == null || _userName == null || _userEmail == null) return;

    final prefs = await SharedPreferences.getInstance();

    // Create account object
    final accountData = {
      'userId': _userId!,
      'userName': _userName!,
      'userEmail': _userEmail!,
      'userType': _userType,
      'lastApp': _lastApp ?? 'business',
      'lastLoginTime': DateTime.now().toIso8601String(),
    };

    // Set this as the last used account
    final accountKey = '${_userEmail}_$_userType';
    await prefs.setString(_keyLastUsedAccount, accountKey);
    _lastUsedAccount = accountKey;

    // Load existing stored accounts
    await _loadStoredAccounts();

    // Update or add this account to stored accounts
    final existingIndex = _storedAccounts.indexWhere(
      (account) =>
          account['userId'] == _userId && account['userType'] == _userType);

    if (existingIndex != -1) {
      // Update existing account
      _storedAccounts[existingIndex] = accountData;
    } else {
      // Add new account
      _storedAccounts.add(accountData);
    }

    // Keep only the last 5 accounts
    if (_storedAccounts.length > 5) {
      _storedAccounts.sort(
        (a, b) => DateTime.parse(
          b['lastLoginTime']).compareTo(DateTime.parse(a['lastLoginTime'])));
      _storedAccounts = _storedAccounts.take(5).toList();
    }

    // Save updated accounts list
    await _saveStoredAccounts();
  }

  Future<void> _loadStoredAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accountsJson = prefs.getStringList(_keyStoredAccounts) ?? [];

    _storedAccounts = accountsJson
        .map((jsonStr) {
          try {
            return Map<String, dynamic>.from(
              Uri.splitQueryString(
                jsonStr).map((key, value) => MapEntry(key, Uri.decodeComponent(value))));
          } catch (e) {
            return <String, dynamic>{};
          }
        })
        .where((account) => account.isNotEmpty)
        .toList();
  }

  Future<void> _saveStoredAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accountsJson = _storedAccounts.map((account) {
      return account.entries
          .map(
            (entry) =>
                '${entry.key}=${Uri.encodeComponent(entry.value.toString())}')
          .join('&');
    }).toList();

    await prefs.setStringList(_keyStoredAccounts, accountsJson);
  }

  Future<void> setLastApp(String app) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastApp, app);
    _lastApp = app;
    notifyListeners();
  }

  Future<void> loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
    _userType = prefs.getString(_keyUserType) ?? 'Business';
    _userId = prefs.getString(_keyUserId);
    _userName = prefs.getString(_keyUserName);
    _userEmail = prefs.getString(_keyUserEmail);
    _authToken = prefs.getString(_keyAuthToken);
    _authMethod = prefs.getString(_keyAuthMethod); // Load auth method
    _lastApp = prefs.getString(_keyLastApp);
    _lastUsedAccount = prefs.getString(_keyLastUsedAccount);

    final storedUsername = sanitizeUsername(prefs.getString('username'));
    final tokenUsername = extractUsernameFromToken(_authToken);
    if (storedUsername == null && tokenUsername != null) {
      await prefs.setString('username', tokenUsername);
      print('✅ AppSettings.loadUserData() - Restored username from token: $tokenUsername');
    }

    // DEBUG: Log token loading
    print('📱 AppSettings.loadUserData():');
    print('  - isLoggedIn: $_isLoggedIn');
    print('  - userId: $_userId');
    print('  - userName: $_userName');
    print('  - userEmail: $_userEmail');
    print('  - authMethod: $_authMethod');
    print(
      '  - authToken: ${_authToken != null ? "${_authToken!.substring(0, 20)}..." : "NULL"}');

    // Load onboarding status
    _onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

    // Load app settings
    _motionDockEnabled = prefs.getBool(_keyMotionDockEnabled) ?? true;
    _selectedTheme = prefs.getString(_keySelectedTheme) ?? 'System';
    _selectedTextSize = prefs.getString(_keySelectedTextSize) ?? 'Medium';
    _selectedLanguage =
        prefs.getString(_keySelectedLanguage) ?? 'System';
    _selectedDateFormat =
        prefs.getString(_keySelectedDateFormat) ?? 'System';

    // Load Delvioo settings
    _delviooDistanceUnit = prefs.getString(_keyDelviooDistanceUnit) ?? 'System';
    _delviooWeightUnit = prefs.getString(_keyDelviooWeightUnit) ?? 'System';
    _delviooCurrency = prefs.getString(_keyDelviooCurrency) ?? 'System';
    _delviooTemperatureUnit =
        prefs.getString(_keyDelviooTemperatureUnit) ?? 'System';
    _delviooNumberFormat =
        prefs.getString(_keyDelviooNumberFormat) ?? 'System';
    setNumberFormatStyleIndex(effectiveNumberFormat == '1.234,56' ? 1 : 0);
    _delviooTextSize = prefs.getString(_keyDelviooTextSize) ?? 'Medium';
    _lastMileEnabled =
        prefs.getBool(_keyLastMileEnabled) ??
        true; // Last Mile enabled by default
    _aiSuggestionRadius =
        prefs.getDouble(_keyAiSuggestionRadius) ??
        10.0; // Default 10 km

    // Load stored accounts
    await _loadStoredAccounts();

    // If we have stored accounts, onboarding should be completed
    if (_storedAccounts.isNotEmpty && !_onboardingCompleted) {
      await prefs.setBool('onboarding_completed', true);
      _onboardingCompleted = true;
    }

    notifyListeners();
  }

  Future<void> switchToAccount(Map<String, dynamic> accountData) async {
    final prefs = await SharedPreferences.getInstance();

    // Set current session data - ✅ Convert userId to String
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserType, accountData['userType']);
    await prefs.setString(
      _keyUserId,
      accountData['userId'].toString()); // ✅ Convert to String
    await prefs.setString(_keyUserName, accountData['userName']);
    await prefs.setString(_keyUserEmail, accountData['userEmail']);
    await prefs.setString(_keyLastApp, accountData['lastApp'] ?? 'business');

    // Update local variables - ✅ Convert userId to String
    _isLoggedIn = true;
    _userType = accountData['userType'];
    _userId = accountData['userId'].toString(); // ✅ Convert to String
    _userName = accountData['userName'];
    _userEmail = accountData['userEmail'];
    _lastApp = accountData['lastApp'] ?? 'business';

    // Update last used account
    final accountKey = '${accountData['userEmail']}_${accountData['userType']}';
    await prefs.setString(_keyLastUsedAccount, accountKey);
    _lastUsedAccount = accountKey;

    // Update the account's last login time
    final updatedAccount = Map<String, dynamic>.from(accountData);
    updatedAccount['lastLoginTime'] = DateTime.now().toIso8601String();

    final existingIndex = _storedAccounts.indexWhere(
      (account) =>
          account['userId'] == accountData['userId'] &&
          account['userType'] == accountData['userType']);

    if (existingIndex != -1) {
      _storedAccounts[existingIndex] = updatedAccount;
      await _saveStoredAccounts();
    }

    notifyListeners();
  }

  Map<String, dynamic>? getLastUsedAccount() {
    if (_lastUsedAccount == null) return null;

    return _storedAccounts.firstWhere(
      (account) =>
          '${account['userEmail']}_${account['userType']}' == _lastUsedAccount,
      orElse: () => <String, dynamic>{});
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserType);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyAuthToken);
    await prefs.remove(_keyLastApp);
    // Don't remove _keyLastUsedAccount and _keyStoredAccounts - keep them for account switching

    _isLoggedIn = false;
    _userType = 'Business';
    _userId = null;
    _userName = null;
    _userEmail = null;
    _authToken = null;
    _autoLoginShown = false;
    _lastApp = null;
    notifyListeners();
  }

  Future<void> clearAllAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastUsedAccount);
    await prefs.remove(_keyStoredAccounts);

    _lastUsedAccount = null;
    _storedAccounts.clear();

    // Also logout current session
    await logout();
  }

  // ═══════════════════════════════════════════════════════════════════
  // SYSTEM LOCALE RESOLVERS - Detect device settings
  // ═══════════════════════════════════════════════════════════════════

  /// Resolve the effective temperature unit based on device locale
  String get effectiveTemperatureUnit {
    if (_delviooTemperatureUnit != 'System') return _delviooTemperatureUnit;
    // US, Bahamas, Cayman Islands, Liberia, Palau use Fahrenheit
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final fahrenheitCountries = ['US', 'BS', 'KY', 'LR', 'PW'];
    return fahrenheitCountries.contains(locale.countryCode) ? 'Fahrenheit' : 'Celsius';
  }

  /// Resolve the effective distance unit based on device locale
  String get effectiveDistanceUnit {
    if (_delviooDistanceUnit != 'System') return _delviooDistanceUnit;
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final mileCountries = ['US', 'GB', 'MM', 'LR'];
    return mileCountries.contains(locale.countryCode) ? 'Miles' : 'Kilometers';
  }

  /// Resolve the effective weight unit based on device locale
  String get effectiveWeightUnit {
    if (_delviooWeightUnit != 'System') return _delviooWeightUnit;
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final poundCountries = ['US', 'GB', 'MM', 'LR'];
    return poundCountries.contains(locale.countryCode) ? 'Pounds' : 'Kilograms';
  }

  /// Resolve the effective currency based on device locale
  String get effectiveCurrency {
    if (_delviooCurrency != 'System') return _delviooCurrency;
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    switch (locale.countryCode) {
      case 'US': return 'Dollar';
      case 'CA': return 'CanadianDollar';
      case 'MX': return 'MexicanPeso';
      case 'GB': return 'Pound';
      case 'PL': return 'Zloty';
      case 'CZ': return 'Koruna';
      case 'HU': return 'Forint';
      case 'SE': return 'SwedishKrona';
      case 'DK': return 'DanishKrone';
      case 'NO': return 'NorwegianKrone';
      case 'CH': case 'LI': return 'Franc';
      case 'BG': return 'Lev';
      case 'RO': return 'Leu';
      case 'RU': return 'Ruble';
      // Eurozone
      case 'DE': case 'FR': case 'IT': case 'ES': case 'NL': case 'BE':
      case 'AT': case 'PT': case 'IE': case 'FI': case 'GR': case 'LU':
      case 'SK': case 'SI': case 'EE': case 'LV': case 'LT': case 'CY':
      case 'MT': case 'HR': return 'Euro';
      default: return 'Dollar';
    }
  }

  /// Resolve the effective number format based on device locale
  String get effectiveNumberFormat {
    if (_delviooNumberFormat != 'System') return _delviooNumberFormat;
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    // EU countries use comma as decimal separator
    final euCountries = ['DE', 'FR', 'IT', 'ES', 'NL', 'BE', 'AT', 'PT',
      'GR', 'LU', 'SK', 'SI', 'EE', 'LV', 'LT', 'CY', 'MT', 'HR',
      'PL', 'CZ', 'HU', 'RO', 'BG', 'DK', 'SE', 'NO', 'FI', 'CH', 'BR', 'TR'];
    return euCountries.contains(locale.countryCode) ? '1.234,56' : '1,234.56';
  }

  /// Resolve the effective date format based on device locale
  String get effectiveDateFormat {
    if (_selectedDateFormat != 'System') return _selectedDateFormat;
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    if (locale.countryCode == 'US') return 'MM/dd/yyyy';
    if (locale.countryCode == 'JP' || locale.countryCode == 'CN' ||
        locale.countryCode == 'KR') {
      return 'yyyy-MM-dd';
    }
    if (locale.countryCode == 'GB' || locale.countryCode == 'AU' ||
        locale.countryCode == 'NZ') {
      return 'dd/MM/yyyy';
    }
    return 'dd.MM.yyyy'; // European default
  }

  /// Get the Locale object for MaterialApp based on selected language.
  /// Returns null when 'System' is selected so MaterialApp follows the
  /// device locale dynamically instead of using a frozen snapshot.
  Locale? get appLocale {
    if (_selectedLanguage == 'System') {
      return null; // null → MaterialApp uses system locale automatically
    }
    final supported = AppLocales.findByCode(_selectedLanguage);
    if (supported != null) return supported.locale;
    // Fallback: try to parse the code
    final parts = _selectedLanguage.split('_');
    if (parts.length == 2) return Locale(parts[0], parts[1]);
    return const Locale('en', 'US');
  }

  /// Get display name for the selected language
  String get selectedLanguageDisplayName {
    if (_selectedLanguage == 'System') return 'System';
    final supported = AppLocales.findByCode(_selectedLanguage);
    if (supported != null) return '${supported.flag} ${supported.displayName} (${supported.region})';
    return _selectedLanguage;
  }

  /// Resolve the effective language based on device locale
  String get effectiveLanguage {
    if (_selectedLanguage != 'System') {
      final supported = AppLocales.findByCode(_selectedLanguage);
      if (supported != null) return '${supported.displayName} (${supported.region})';
      return _selectedLanguage;
    }
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final match = AppLocales.all.where((l) => 
      l.locale.languageCode == locale.languageCode && 
      l.locale.countryCode == locale.countryCode
    ).toList();
    if (match.isNotEmpty) return '${match.first.displayName} (${match.first.region})';
    // Fallback by language code only
    final langMatch = AppLocales.all.where((l) => 
      l.locale.languageCode == locale.languageCode
    ).toList();
    if (langMatch.isNotEmpty) return '${langMatch.first.displayName} (${langMatch.first.region})';
    return 'English (USA)';
  }

  // Utility methods for unit conversions
  String formatDistance(double kilometers) {
    if (effectiveDistanceUnit == 'Miles') {
      final miles = kilometers * 0.621371;
      if (miles < 1) {
        final feet = miles * 5280;
        return '${formatNumber(feet, decimals: 0)} ft';
      }
      return '${formatNumber(miles, decimals: 1)} mi';
    }

    if (kilometers < 1) {
      final meters = kilometers * 1000;
      return '${formatNumber(meters, decimals: 0)} m';
    }
    return '${formatNumber(kilometers, decimals: 1)} km';
  }

  String formatWeight(double kilograms) {
    if (effectiveWeightUnit == 'Pounds') {
      final pounds = kilograms * 2.20462;
      return '${formatNumber(pounds, decimals: 1)} lb';
    }
    return '${formatNumber(kilograms, decimals: 1)} kg';
  }

  String formatCurrency(double amount) {
    // Convert from Dollar (database base currency) to selected currency
    final convertedAmount = convertCurrency(amount);
    final formattedAmount = formatNumber(convertedAmount, decimals: 2);

    switch (effectiveCurrency) {
      case 'Euro':          return '€$formattedAmount';
      case 'Pound':         return '£$formattedAmount';
      case 'CanadianDollar': return 'CA\$$formattedAmount';
      case 'MexicanPeso':   return 'MX\$$formattedAmount';
      case 'Ruble':         return '₽$formattedAmount';
      case 'Zloty':         return '$formattedAmount zł';
      case 'Koruna':        return '$formattedAmount Kč';
      case 'Forint':        return '$formattedAmount Ft';
      case 'SwedishKrona':  return '${formattedAmount}kr';
      case 'DanishKrone':   return '${formattedAmount}kr';
      case 'NorwegianKrone': return '${formattedAmount}kr';
      case 'Franc':         return 'Fr.$formattedAmount';
      case 'Lev':           return '$formattedAmount лв';
      case 'Leu':           return '$formattedAmount lei';
      case 'Dollar':
      default:              return '\$$formattedAmount';
    }
  }

  // Get currency symbol only
  String get currencySymbol {
    switch (effectiveCurrency) {
      case 'Euro':           return '€';
      case 'Pound':          return '£';
      case 'CanadianDollar': return 'CA\$';
      case 'MexicanPeso':    return 'MX\$';
      case 'Ruble':          return '₽';
      case 'Zloty':          return 'zł';
      case 'Koruna':         return 'Kč';
      case 'Forint':         return 'Ft';
      case 'SwedishKrona':   return 'kr';
      case 'DanishKrone':    return 'kr';
      case 'NorwegianKrone': return 'kr';
      case 'Franc':          return 'Fr.';
      case 'Lev':            return 'лв';
      case 'Leu':            return 'lei';
      case 'Dollar':
      default:               return '\$';
    }
  }

  // Temperature formatting and conversion (base unit: Celsius in database)
  String formatTemperature(double celsius) {
    if (effectiveTemperatureUnit == 'Fahrenheit') {
      final fahrenheit = (celsius * 9 / 5) + 32;
      return '${formatNumber(fahrenheit, decimals: 1)}°F';
    }
    return '${formatNumber(celsius, decimals: 1)}°C';
  }

  // Convert temperature from Celsius to selected unit
  double convertTemperature(double celsius) {
    if (effectiveTemperatureUnit == 'Fahrenheit') {
      return (celsius * 9 / 5) + 32;
    }
    return celsius;
  }

  // Number formatting based on user preference (1,234.56 vs 1.234,56)
  String formatNumber(double number, {int decimals = 2}) {
    if (effectiveNumberFormat == '1.234,56') {
      // European format: 1.234,56
      final parts = number.toStringAsFixed(decimals).split('.');
      final integerPart = parts[0];
      final decimalPart = parts.length > 1 ? parts[1] : '';

      // Add thousand separators (dots)
      String formattedInteger = '';
      int count = 0;
      for (int i = integerPart.length - 1; i >= 0; i--) {
        if (count > 0 && count % 3 == 0) {
          formattedInteger = '.$formattedInteger';
        }
        formattedInteger = integerPart[i] + formattedInteger;
        count++;
      }

      return decimals > 0 ? '$formattedInteger,$decimalPart' : formattedInteger;
    } else {
      // US format: 1,234.56 (default)
      final parts = number.toStringAsFixed(decimals).split('.');
      final integerPart = parts[0];
      final decimalPart = parts.length > 1 ? parts[1] : '';

      // Add thousand separators (commas)
      String formattedInteger = '';
      int count = 0;
      for (int i = integerPart.length - 1; i >= 0; i--) {
        if (count > 0 && count % 3 == 0) {
          formattedInteger = ',$formattedInteger';
        }
        formattedInteger = integerPart[i] + formattedInteger;
        count++;
      }

      return decimals > 0 ? '$formattedInteger.$decimalPart' : formattedInteger;
    }
  }

  // Currency conversion from Dollar (database base currency) to selected currency
  // Simplified rates - in real app would use live exchange rates
  double convertCurrency(double dollarAmount) {
    print(
      '💰 convertCurrency called: input=$dollarAmount, currency=$effectiveCurrency');

    double result;
    switch (effectiveCurrency) {
      case 'Dollar':          result = dollarAmount; break;
      case 'CanadianDollar':  result = dollarAmount * 1.36; break;  // USD→CAD
      case 'MexicanPeso':     result = dollarAmount * 17.15; break; // USD→MXN
      case 'Pound':           result = dollarAmount * 0.79; break;  // USD→GBP
      case 'Euro':            result = dollarAmount * 0.92; break;  // USD→EUR
      case 'Ruble':           result = dollarAmount * 90.0; break;  // USD→RUB
      case 'Zloty':           result = dollarAmount * 4.05; break;  // USD→PLN
      case 'Koruna':          result = dollarAmount * 23.2; break;  // USD→CZK
      case 'Forint':          result = dollarAmount * 360.0; break; // USD→HUF
      case 'SwedishKrona':    result = dollarAmount * 10.5; break;  // USD→SEK
      case 'DanishKrone':     result = dollarAmount * 6.9; break;   // USD→DKK
      case 'NorwegianKrone':  result = dollarAmount * 10.8; break;  // USD→NOK
      case 'Franc':           result = dollarAmount * 0.91; break;  // USD→CHF
      case 'Lev':             result = dollarAmount * 1.80; break;  // USD→BGN
      case 'Leu':             result = dollarAmount * 4.58; break;  // USD→RON
      default:
        print('⚠️ Unknown currency: $_delviooCurrency, using dollar amount as-is');
        result = dollarAmount;
        break;
    }

    print('💰 convertCurrency result: $result');
    return result;
  }

  // Check if user has security features enabled and should show auto-login
  bool get shouldShowAutoLogin {
    return _isLoggedIn && (_userId != null);
  }

  // Get text size multiplier based on selected text size
  double getTextSizeMultiplier() {
    switch (_delviooTextSize) {
      case 'Small':
        return 0.85;
      case 'Medium':
        return 1.0;
      case 'Large':
        return 1.15;
      case 'Extra Large':
        return 1.3;
      default:
        return 1.0;
    }
  }

  // Get scaled font size
  double getScaledFontSize(double baseSize) {
    // When the app is wrapped with a global MediaQuery(textScaleFactor),
    // we should not multiply here to avoid double-scaling.
    // Keep this method to return the base size so existing callers remain
    // compatible and the global textScaleFactor applies app-wide.
    return baseSize;
  }

  // Format date according to user's selected date format
  String formatDate(DateTime date) {
    switch (effectiveDateFormat) {
      case 'MM/dd/yyyy': // US format
        return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
      case 'yyyy-MM-dd': // ISO format
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      case 'dd/MM/yyyy': // UK/Commonwealth format
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      case 'dd.MM.yyyy': // European format (default)
      default:
        return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }
  }

  // Format date string (parses ISO string and formats)
  String formatDateString(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    try {
      final date = DateTime.parse(dateString);
      return formatDate(date);
    } catch (e) {
      return dateString; // Return original if parsing fails
    }
  }
}
