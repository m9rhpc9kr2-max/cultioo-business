import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../shared/services/biometric_service.dart';
import '../../../shared/services/two_factor_service.dart';
import '../../../config/api_config.dart';
import '../../../shared/widgets/two_factor_setup_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import '../../../shared/widgets/trade_republic_switch.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_divider.dart';
import '../../../shared/widgets/trade_republic_list_tile.dart';
import '../../../shared/widgets/trade_republic_card.dart';
import '../../../shared/widgets/trade_republic_section_header.dart';
import '../../../shared/widgets/trade_republic_swipe_action.dart';
import '../../../shared/widgets/trade_republic_slider.dart';
import '../../../shared/widgets/trade_republic_value_slider.dart';
import '../../../shared/widgets/trade_republic_theme.dart';
import '../../../shared/widgets/payment_input_formatters.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../shared/services/app_localizations.dart';
import 'delvioo_main_page.dart'; // Import for hideDockNotifier
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../utils/wagon_catalog.dart';
import '../../../shared/constants/wagon_types.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import '../../../shared/widgets/credit_card_widget.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

// Smart number formatter for cargo/payload capacity that uses AppSettings
class GermanNumberFormatter extends TextInputFormatter {
  final AppSettings? appSettings;

  GermanNumberFormatter([this.appSettings]);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove all non-digits
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // If empty, return empty
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Convert to double and divide by 100 for decimal places
    double value = double.parse(digitsOnly) / 100;

    // Format using AppSettings if available, otherwise use default European format
    String formatted;
    if (appSettings != null) {
      formatted = appSettings!.formatNumber(value, decimals: 2);
    } else {
      // Fallback to European format if no AppSettings
      formatted = formatGermanNumber(value);
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String formatGermanNumber(double value) {
    // Split into integer and decimal parts
    String valueStr = value.toStringAsFixed(2);
    List<String> parts = valueStr.split('.');
    String integerPart = parts[0];
    String decimalPart = parts[1];

    // Add thousand separators (dots) to integer part
    String formattedInteger = '';
    for (int i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        formattedInteger += '.';
      }
      formattedInteger += integerPart[i];
    }

    // Return with German decimal separator (comma)
    return '$formattedInteger,$decimalPart';
  }

  // Static method to convert formatted number back to double (supports both formats)
  static double parseGermanNumber(String formattedValue) {
    if (formattedValue.isEmpty) return 0.0;

    final lastComma = formattedValue.lastIndexOf(',');
    final lastDot = formattedValue.lastIndexOf('.');

    // No separators → plain number
    if (lastComma == -1 && lastDot == -1) {
      return double.tryParse(formattedValue) ?? 0.0;
    }

    if (lastComma > lastDot) {
      // Comma is the last separator → EU decimal: "2.000,00"
      return double.tryParse(
        formattedValue.replaceAll('.', '').replaceAll(',', '.'),
      ) ?? 0.0;
    } else {
      // Dot is the last separator → US decimal: "2,000.00"
      return double.tryParse(
        formattedValue.replaceAll(',', ''),
      ) ?? 0.0;
    }
  }
}

// Fuel Economy Formatter - formats from right to left (1 -> 0.01, 12 -> 0.12, 123 -> 1.23)
class FuelEconomyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove all non-digits
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // If empty, return empty
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Convert to double and divide by 100 for 2 decimal places
    double value = double.parse(digitsOnly) / 100;

    // Format with 2 decimal places
    String formatted = value.toStringAsFixed(2);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class DelviooAccountPage extends StatefulWidget {
  const DelviooAccountPage({super.key});

  @override
  State<DelviooAccountPage> createState() => _DelviooAccountPageState();

  // Static method to check if biometric login is available and authenticate
  static Future<bool> authenticateWithBiometric() async {
    return await BiometricService.authenticateForLogin();
  }

  // Static method to check if biometric is enabled
  static Future<bool> isBiometricLoginEnabled() async {
    return await BiometricService.isBiometricLoginAvailable();
  }
}

class _DelviooAccountPageState extends State<DelviooAccountPage>
    with TickerProviderStateMixin {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  bool _isRefreshing = false;
  List<Map<String, dynamic>> userGroups = [];
  List<Map<String, dynamic>> availableUsers = [];
  String? selectedUserId;
  List<Map<String, dynamic>> reviews = [];
  bool isLoadingReviews = true;
  double averageRating = 0.0;
  List<Map<String, dynamic>> waitingChargeCredits = [];

  // Animation Controllers
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late Animation<double> _headerSlideAnim;
  late Animation<double> _headerFadeAnim;

  // Header visibility controller for bottom sheets
  AnimationController? _headerVisibilityController;
  bool _isBottomSheetOpen = false;

  // Carbon Footprint / Mileage tracking
  // Key: 'YYYY-MM', value: {startKm, endKm}
  Map<String, Map<String, double>> _mileageEntries = {};

  @override
  void initState() {
    super.initState();
    print('🚀 DelviooAccountPage initState called');

    // Initialize animation controllers
    _headerAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _headerSlideAnim = Tween<double>(begin: -30, end: 0).animate(
      CurvedAnimation(
        parent: _headerAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
    _headerFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut),
    );

    _contentAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Initialize header visibility controller
    _headerVisibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );

    // Start header animation immediately (like in Home page)
    _headerAnimController.forward().then((_) {
      // Lock the header animation at completed state so it doesn't interfere with visibility animation
      if (mounted) {
        setState(() {
          // Header animation done, now only visibility animation will control the header
        });
      }
      print('✅ Header animation complete - locked at final position');
    });

    // Start content animation shortly after header (don't wait for data)
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _contentAnimController.forward();
      }
    });

    _loadUserData();
    _loadUserGroups();
    _loadMileageEntries();
    _loadWaitingChargeCredits();
    print('🔄 About to call _loadReviews()');
    _loadReviews();
    print('✅ _loadReviews() call completed');
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    _contentAnimController.dispose();
    _headerVisibilityController?.dispose();
    super.dispose();
  }

  void _hideHeader() {
    if (!_isBottomSheetOpen && _headerVisibilityController != null) {
      print('🔼 ACCOUNT PAGE: Hiding header');
      setState(() {
        _isBottomSheetOpen = true;
      });
      _headerVisibilityController!.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showHeader() {
    if (_isBottomSheetOpen && _headerVisibilityController != null) {
      print('🔽 ACCOUNT PAGE: Showing header');
      setState(() {
        _isBottomSheetOpen = false;
      });
      _headerVisibilityController!.animateTo(
        1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // Content animation now starts immediately in initState, this is kept for compatibility
  void _startAppearanceAnimations() {
    // Animations now start immediately in initState
    // This method is kept for compatibility but no longer needed
  }

  // Helper method to convert image URLs to use GCS storage
  String _getImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';

    // If it's a full server URL, convert to GCS
    if (imageUrl.contains('/uploads/profile-images/')) {
      final filename = imageUrl.split('/').last;
      final gcsUrl =
          'https://storage.googleapis.com/cultioo-uploads/profile-images/$filename';
      print('🔄 Converted profile URL to GCS: $gcsUrl');
      return gcsUrl;
    }

    // If it's a relative path, use GCS
    if (imageUrl.startsWith('/uploads/')) {
      final filename = imageUrl.split('/').last;
      return 'https://storage.googleapis.com/cultioo-uploads/profile-images/$filename';
    }

    // If it's just a filename, use GCS
    if (!imageUrl.startsWith('http')) {
      return 'https://storage.googleapis.com/cultioo-uploads/profile-images/$imageUrl';
    }

    // Otherwise return as-is
    return imageUrl;
  }

  void _onProfileImageUpdated(String imageUrl) {
    // Update local state immediately for instant UI feedback - use correct database field name
    setState(() {
      userData?['profile_image'] = imageUrl; // Database uses snake_case
      userData?['profileImage'] =
          imageUrl; // Also set camelCase for compatibility
    });

    // Trigger refresh notifier to update sidebar in main page
    refreshUserDataNotifier.value++;
    print(
      '✅ Triggered refreshUserDataNotifier: ${refreshUserDataNotifier.value}',
    );

    // Reload user data from database to ensure consistency across all apps
    // The upload endpoint already saved it to delvioo_users.profile_image
    print('✅ Profile image updated locally: $imageUrl');
    print('🔄 Reloading user data to sync with database...');

    // Reload user data to ensure the image is properly synced
    final userId =
        userData?['userId'] ?? userData?['username'] ?? userData?['email'];
    if (userId != null) {
      _loadSpecificUserData(userId.toString());
    }
  }

  Future<void> _loadUserData() async {
    print('📡 Loading user data from Google Cloud database...');
    setState(() {
      isLoading = true;
    });

    try {
      // Get username from SharedPreferences (stored during login)
      final prefs = await SharedPreferences.getInstance();
      final appSettings = Provider.of<AppSettings>(context, listen: false);

      final username =
          prefs.getString('username') ??
          prefs.getString('delvioo_username') ??
          appSettings.userEmail ??   // email works on backend (WHERE username = ? OR email = ?)
          appSettings.userName;

      print('🔍 Loading profile for logged-in user: $username');

      if (username == null || username.isEmpty) {
        print('❌ No username found in preferences');
        _setFallbackUserData();
        return;
      }

      // Load the logged-in user's profile directly
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/profile/$username'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Profile response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['user'] != null) {
          final user = data['user'];
          print('✅ User profile loaded: ${user['username']}');
          print('📧 Email: ${user['email']}');
          print('🖼️ Profile image: ${user['profile_image']}');
          print('📍 Street: ${user['street']}, City: ${user['city']}');
          print('🎂 DOB: ${user['date_of_birth']}');

          // Persist the resolved delvioo username so vehicle management can find the right vehicles
          final resolvedUsername = user['username'];
          if (resolvedUsername != null && resolvedUsername.toString().isNotEmpty) {
            await prefs.setString('delvioo_username', resolvedUsername.toString());
            print('✅ Persisted delvioo_username: $resolvedUsername');
          }

          setState(() {
            userData = {
              'id': user['id']?.toString() ?? AppLocalizations.of(context)!.tr(''),
              'userId': user['username'] ?? user['email'] ?? user['id']?.toString() ?? AppLocalizations.of(context)!.tr(''),
              'username': user['username'] ?? username,
              'firstName': user['first_name'] ?? user['username'] ?? AppLocalizations.of(context)!.tr('Driver'),
              'lastName': user['last_name'] ?? AppLocalizations.of(context)!.tr(''),
              'email': user['email'] ?? AppLocalizations.of(context)!.tr(''),
              'phone': user['phone'] ?? AppLocalizations.of(context)!.tr(''),
              'dateOfBirth': user['date_of_birth'],
              'profile_image': user['profile_image'],
              'profileImage': user['profile_image'],
              'address': {
                'street': [
                  user['street'] ?? AppLocalizations.of(context)!.tr(''),
                  user['street_number'] ?? AppLocalizations.of(context)!.tr(''),
                ].where((s) => s.isNotEmpty).join(' '),
                'city': user['city'] ?? AppLocalizations.of(context)!.tr(''),
                'zipCode': user['zip_code'] ?? AppLocalizations.of(context)!.tr(''),
                'country': user['country'] ?? AppLocalizations.of(context)!.tr(''),
              },
              'vehicle': user['vehicle'] ?? {},
              'bankDetails': {
                'iban': user['iban'] ?? AppLocalizations.of(context)!.tr(''),
                'swiftBic': user['swift_bic'] ?? AppLocalizations.of(context)!.tr(''),
                'accountHolder': user['account_holder_name'] ?? AppLocalizations.of(context)!.tr(''),
                'routingNumber': user['routing_number'] ?? AppLocalizations.of(context)!.tr(''),
                'accountNumber': user['account_number'] ?? AppLocalizations.of(context)!.tr(''),
                'accountType': user['account_type'] ?? AppLocalizations.of(context)!.tr(''),
                'bankType': user['bank_type'] ?? AppLocalizations.of(context)!.tr(''),
              },
              'verification': {
                'status': user['verification_status'] ?? user['approval_status'] ?? (AppLocalizations.of(context)?.pending ?? AppLocalizations.of(context)!.tr('Pending')),
                'score': 0,
              },
              'stats': user['stats'] ?? {'totalDeliveries': 0, 'rating': 0.0, 'totalEarnings': 0.0},
              'pendingPayout': user['pending_payout'] ?? 0.0,
              'totalEarnings': user['total_earnings'] ?? 0.0,
              'totalDeliveries': user['total_deliveries'] ?? 0,
              'totalAccepted': user['total_accepted'] ?? 0,
              'totalDistance': user['total_distance'] ?? 0.0,
              'created_at': user['created_at'],
            };
            isLoading = false;
          });

          // Start appearance animations after data loads
          _startAppearanceAnimations();

          // 💰 Fetch earnings — profile endpoint doesn't include financial data
          final userId =
              prefs.getString('user_id') ?? prefs.getString('userId');
          if (userId != null && userId.isNotEmpty) {
            try {
              final earningsResp = await http.get(
                Uri.parse(
                  '${ApiConfig.baseUrl}/api/delvioo/driver/$userId/earnings',
                ),
                headers: {'Content-Type': 'application/json'},
              );
              if (earningsResp.statusCode == 200) {
                final earningsData = json.decode(earningsResp.body);
                if (earningsData['success'] == true && mounted) {
                  final summary =
                      earningsData['summary'] as Map<String, dynamic>?;
                  final balance =
                      earningsData['balance'] as Map<String, dynamic>?;
                  setState(() {
                    userData!['pendingPayout'] =
                        ((balance?['available'] ?? 0) as num).toDouble();
                    userData!['totalEarnings'] =
                        ((balance?['total_earned'] ?? 0) as num).toDouble();
                    userData!['totalDeliveries'] =
                        ((summary?['total_deliveries'] ?? 0) as num).toInt();
                    userData!['totalAccepted'] =
                        ((summary?['total_deliveries'] ?? 0) as num).toInt();
                    userData!['totalDistance'] =
                        ((summary?['total_distance_km'] ?? 0) as num)
                            .toDouble();
                  });
                  print(
                    '💰 Earnings loaded: pending=\$${userData!["pendingPayout"]}, '
                    'deliveries=${userData!["totalDeliveries"]}',
                  );
                }
              } else {
                print('⚠️ Earnings API returned ${earningsResp.statusCode}');
              }
            } catch (e) {
              print('⚠️ Could not load earnings data: $e');
            }
          }

          return;
        }
      }

      // Fallback if profile load fails
      print('⚠️ Profile load failed, using fallback');
      _setFallbackUserData();
    } catch (e) {
      print('❌ Error loading user data: $e');
      _setFallbackUserData();
    }
  }

  void _setFallbackUserData() {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final userName = appSettings.userName ?? (AppLocalizations.of(context)?.driverLabel ?? AppLocalizations.of(context)!.tr('Driver'));
    final userEmail = appSettings.userEmail ?? AppLocalizations.of(context)!.tr('');

    setState(() {
      userData = {
        'id': 'temp-user',
        'userId': 'temp-user',
        'username': userName,
        'firstName': userName.split(' ').first,
        'lastName': userName.split(' ').length > 1
            ? userName.split(' ').last
            : '',
        'email': userEmail,
        'phone': '',
        'address': {},
        'vehicle': {},
        'verification': {
          'status': AppLocalizations.of(context)?.pending ?? AppLocalizations.of(context)!.tr('Pending'),
          'score': 0,
        },
        'stats': {'totalDeliveries': 0, 'rating': 0.0, 'totalEarnings': 0.0},
        'profileImage': null,
      };
      isLoading = false;
    });

    _startAppearanceAnimations();
  }

  Future<void> _loadSpecificUserData(String userId) async {
    try {
      print('🔄 Loading specific user data for: $userId');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/user-data/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 User data response status: ${response.statusCode}');
      print('📡 User data response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true && responseData['data'] != null) {
          setState(() {
            userData = responseData['data'];
            selectedUserId = userId;
            isLoading = false;
          });

          // Save username to SharedPreferences for messaging + delvioo vehicle lookup
          final username = responseData['data']['username'];
          if (username != null && username.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('username', username.toString());
            await prefs.setString('delvioo_username', username.toString());
            print('✅ Saved username to SharedPreferences: $username');
          }

          print(
            '✅ Successfully loaded data for: ${responseData['data']['firstName']} ${responseData['data']['lastName']}',
          );
          print(
            '🚗 Vehicles in userData: ${responseData['data']['vehicles']?.length ?? 0}',
          );

          // DEBUG: Print payment/bank data
          print('💳 Payment Info Fields:');
          print('  - paymentInfo: ${responseData['data']['paymentInfo']}');
          print(
            '  - stripeBankAccountId: ${responseData['data']['stripeBankAccountId']}',
          );
          print(
            '  - stripe_bank_account_id: ${responseData['data']['stripe_bank_account_id']}',
          );
          print(
            '  - accountHolderName: ${responseData['data']['accountHolderName']}',
          );
          print(
            '  - account_holder_name: ${responseData['data']['account_holder_name']}',
          );
          print('  - bankType: ${responseData['data']['bankType']}');
          print('  - bank_type: ${responseData['data']['bank_type']}');
          print('  - routingNumber: ${responseData['data']['routingNumber']}');
          print(
            '  - routing_number: ${responseData['data']['routing_number']}',
          );
          print('  - accountNumber: ${responseData['data']['accountNumber']}');
          print(
            '  - account_number: ${responseData['data']['account_number']}',
          );
          print('  - iban: ${responseData['data']['iban']}');
          print('  - swiftBic: ${responseData['data']['swiftBic']}');
          print('  - swift_bic: ${responseData['data']['swift_bic']}');

          // DEBUG: Print profile image field
          print('🖼️ Profile Image Fields:');
          print('  - profileImage: ${responseData['data']['profileImage']}');
          print('  - profile_image: ${responseData['data']['profile_image']}');
          print('  - profilePic: ${responseData['data']['profilePic']}');
          print(
            '  - profilePicture: ${responseData['data']['profilePicture']}',
          );

          // Load delivery stats (earnings, total deliveries, etc.)
          try {
            print('📊 Loading delivery stats for driver: $userId');
            final statsResponse = await http.get(
              Uri.parse(
                '${ApiConfig.baseUrl}/api/delivery-stats?driverId=$userId',
              ),
              headers: {'Content-Type': 'application/json'},
            );

            print('📊 Stats response status: ${statsResponse.statusCode}');
            print('📊 Stats response body: ${statsResponse.body}');

            if (statsResponse.statusCode == 200) {
              final statsData = json.decode(statsResponse.body);

              if (statsData['success'] == true && statsData['data'] != null) {
                final stats = statsData['data'];
                print('✅ Delivery stats loaded:');
                print('  - Total Deliveries: ${stats['totalDeliveries']}');
                print('  - Total Accepted: ${stats['totalAccepted']}');
                print('  - Total Earnings: ${stats['totalEarnings']}');
                print('  - Total Distance: ${stats['totalDistance']} km');
                print('  - Average Rating: ${stats['averageRating']}');

                // Update userData with real stats
                setState(() {
                  userData?['totalDeliveries'] = stats['totalDeliveries'] ?? 0;
                  userData?['totalAccepted'] = stats['totalAccepted'] ?? 0;
                  userData?['pendingPayout'] = stats['totalEarnings'] ?? 0.0;
                  userData?['totalEarnings'] = stats['totalEarnings'] ?? 0.0;
                  userData?['averageRating'] = stats['averageRating'] ?? 0.0;
                  userData?['totalDistance'] = stats['totalDistance'] ?? 0.0;
                  userData?['stats'] = {
                    'totalDeliveries': stats['totalDeliveries'] ?? 0,
                    'totalAccepted': stats['totalAccepted'] ?? 0,
                    'rating': stats['averageRating'] ?? 0.0,
                    'totalEarnings': stats['totalEarnings'] ?? 0.0,
                  };
                  // Save group aggregation info for UI banners
                  userData?['groupAggregation'] = statsData['groupAggregation'];
                  userData?['redirectedToHost'] = statsData['redirectedToHost'];
                });

                print('✅ User data updated with delivery stats');
                print(
                  '✅ userData[pendingPayout] = ${userData?['pendingPayout']}',
                );
                print(
                  '✅ userData[totalEarnings] = ${userData?['totalEarnings']}',
                );
              } else {
                print('⚠️ No stats data in response');
              }
            } else {
              print(
                '⚠️ Failed to load delivery stats: ${statsResponse.statusCode}',
              );
            }
          } catch (statsError) {
            print('⚠️ Error loading delivery stats: $statsError');
            // Continue without stats - not a critical error
          }

          // Also load user groups for this user
          await _loadUserGroups();

          // Start appearance animations after data loads
          _startAppearanceAnimations();

          return;
        }
      }

      // If loading fails, show error
      throw Exception('Failed to load user data for $userId');
    } catch (e) {
      print('❌ Error loading user data for $userId: $e');
      setState(() {
        isLoading = false;
      });

      // Start animations even on error
      _startAppearanceAnimations();
    }
  }

  Future<void> _switchUser(String userId) async {
    setState(() {
      isLoading = true;
    });

    await _loadSpecificUserData(userId);
  }

  Future<List<Map<String, dynamic>>> _loadPayoutHistory() async {
    try {
      final driverUsername = userData?['username'] ?? AppLocalizations.of(context)!.tr('');
      print('📊 Loading payout history for: $driverUsername');

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delvioo/payout-history/$driverUsername',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final payouts = List<Map<String, dynamic>>.from(
            data['data']['payouts'] ?? [],
          );
          print('✅ Loaded ${payouts.length} payouts');
          return payouts;
        }
      }

      print('⚠️ Failed to load payout history: ${response.statusCode}');
      return [];
    } catch (e) {
      print('❌ Error loading payout history: $e');
      return [];
    }
  }

  Widget _buildPayoutHistoryItem(
    Map<String, dynamic> payout,
    bool isLight,
    AppSettings appSettings,
  ) {
    final amount = double.tryParse(payout['amount']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ?? 0.0;
    final status = payout['status'] ?? AppLocalizations.of(context)!.tr('pending');
    final deliveries = payout['total_deliveries'] ?? 0;
    final createdAt = payout['created_at'];
    final payoutId =
        payout['id']?.toString() ?? payout['payout_id']?.toString() ?? AppLocalizations.of(context)!.tr('');

    // Format date
    String formattedMonth = '';
    String formattedDay = '';
    if (createdAt != null) {
      try {
        final date = DateTime.parse(createdAt);
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        formattedMonth = months[date.month - 1].toUpperCase();
        formattedDay = date.day.toString();
      } catch (e) {
        print('Error parsing date: $e');
      }
    }

    // Status color and icon
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'completed':
        statusColor = const Color(0xFF34C759);
        statusIcon = CupertinoIcons.checkmark_circle_fill;
        statusText = 'Completed';
        break;
      case 'pending':
        statusColor = const Color(0xFFFF9500);
        statusIcon = CupertinoIcons.clock;
        statusText = AppLocalizations.of(context)?.pending ?? AppLocalizations.of(context)!.tr('Pending');
        break;
      case 'failed':
        statusColor = const Color(0xFFFF3B30);
        statusIcon = CupertinoIcons.exclamationmark_circle;
        statusText = 'Failed';
        break;
      default:
        statusColor = isLight
            ? Colors.black.withOpacity(0.3)
            : Colors.white.withOpacity(0.3);
        statusIcon = CupertinoIcons.question_circle;
        statusText = status;
    }

    return TradeRepublicSwipeAction(
      key: ValueKey('payout_$payoutId'),
      margin: const EdgeInsets.only(bottom: 12),
      trailing: TradeRepublicSwipeSpec(
        icon: CupertinoIcons.arrow_down_circle_fill,
        label: AppLocalizations.of(context)?.download ?? 'Download',
        onActivate: () => _downloadPayoutInvoice(payout, isLight),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isLight
              ? Colors.transparent
              : Colors.black,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
        ),
        child: Row(
          children: [
            // Status icon in circle
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                statusIcon,
                color: statusColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),

            // Amount and details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appSettings.formatCurrency(
                      appSettings.convertCurrency(amount),
                    ),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$deliveries ${deliveries == 1 ? 'delivery' : 'deliveries'}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),

            // Date and status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formattedMonth.isNotEmpty && formattedDay.isNotEmpty
                      ? '$formattedDay $formattedMonth'
                      : AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.2),
            ),
          ],
        ),
      ),
    );
  }

  // Download payout invoice as PDF
  Future<void> _downloadPayoutInvoice(
    Map<String, dynamic> payout,
    bool isLight,
  ) async {
    final payoutId =
        payout['id']?.toString() ?? payout['payout_id']?.toString();
    if (payoutId == null) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.payoutIdNotFound ?? AppLocalizations.of(context)!.tr('Payout ID not found'),
      );
      return;
    }

    try {
      // Show loading indicator
      TopNotification.info(
        context,
        AppLocalizations.of(context)?.downloadingInvoice ?? AppLocalizations.of(context)!.tr('Downloading invoice...'),
      );

      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/delvioo/payout/$payoutId/invoice',
      );
      print('📥 Downloading invoice from: $url');

      // Download PDF
      final response = await http.get(url);
      print('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        // Save PDF to app documents
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/Payout_$payoutId.pdf';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        print('📥 File saved to: $filePath');

        if (mounted) {
          TopNotification.success(
            context,
            AppLocalizations.of(context)?.invoiceDownloaded ?? AppLocalizations.of(context)!.tr('Invoice downloaded'),
          );
        }

        // Open PDF with system viewer using open_filex
        final result = await OpenFilex.open(filePath);
        print('📥 OpenFilex result: ${result.type} - ${result.message}');

        if (result.type != ResultType.done && mounted) {
          TopNotification.info(
            context,
            '${AppLocalizations.of(context)?.savedTo ?? AppLocalizations.of(context)!.tr('Saved to')}: Payout_$payoutId.pdf',
          );
        }
      } else {
        print('📥 Error response: ${response.body}');
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.failedToDownloadInvoice ?? AppLocalizations.of(context)!.tr('Failed to download invoice'),
          );
        }
      }
    } catch (e) {
      print('📥 Error downloading invoice: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error')}: $e',
        );
      }
    }
  }

  Future<void> _processDriverInstantPayout(bool isLight) async {
    final username = userData?['username']?.toString() ?? '';
    if (username.isEmpty) {
      TopNotification.error(context, AppLocalizations.of(context)?.authRequired ?? AppLocalizations.of(context)!.tr('Authentication required'));
      return;
    }

    final hasBankAccount = (userData?['paymentInfo'] != null &&
            (userData!['paymentInfo']['accountHolder'] != null ||
                userData!['paymentInfo']['iban'] != null)) ||
        userData?['stripeBankAccountId'] != null ||
        userData?['stripe_bank_account_id'] != null ||
        userData?['accountHolderName'] != null ||
        userData?['account_holder_name'] != null;

    if (!hasBankAccount) {
      TopNotification.error(context, AppLocalizations.of(context)?.addBankAccountFirst ?? AppLocalizations.of(context)!.tr('Please add a bank account first before requesting a payout'));
      return;
    }

    final pendingPayout = (userData?['pendingPayout'] is int)
        ? (userData!['pendingPayout'] as int).toDouble()
        : ((userData?['pendingPayout'] ?? 0.0) as num).toDouble();

    if (pendingPayout <= 0) {
      TopNotification.error(context, AppLocalizations.of(context)?.noBalanceAvailable ?? AppLocalizations.of(context)!.tr('No balance available for payout'));
      return;
    }

    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      bottomPadding: 20.0,
      child: Builder(builder: (ctx) {
        final settings = Provider.of<AppSettings>(ctx, listen: false);
        final light = settings.isLightMode(ctx);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const DragHandle(),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(CupertinoIcons.money_dollar_circle_fill, size: 22,
                  color: light ? Colors.black : Colors.white),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(ctx)?.instantPayout ?? 'Instant Payout',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: light ? Colors.black : Colors.white, letterSpacing: -0.4),
              ),
            ]),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Text(
              AppLocalizations.of(ctx)?.confirmPayoutDetailsDesc ?? 'Confirm your payout details',
              style: TextStyle(fontSize: 15,
                  color: (light ? Colors.black : Colors.white).withOpacity(0.5)),
            ),
            const SizedBox(height: 28),
            Container(
              padding: DesktopAppWrapper.getPagePadding(),
              decoration: BoxDecoration(
                color: (light ? Colors.black : Colors.white).withOpacity(0.04),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    AppLocalizations.of(ctx)?.availableBalance ?? 'Available Balance',
                    style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(),
                        color: (light ? Colors.black : Colors.white).withOpacity(0.6)),
                  ),
                  Text('${AppSettings().currencySymbol}${pendingPayout.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(), fontWeight: FontWeight.w600,
                          color: light ? Colors.black : Colors.white)),
                ]),
                const SizedBox(height: 10),
                TradeRepublicDivider(),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(
                    AppLocalizations.of(ctx)?.youWillReceiveLabel ?? 'You will receive',
                    style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(), fontWeight: FontWeight.w700,
                        color: light ? Colors.black : Colors.white),
                  ),
                  Text('${AppSettings().currencySymbol}${pendingPayout.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(), fontWeight: FontWeight.w700,
                          color: Color(0xFF34C759))),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(ctx)?.fundsTransferredImmediately ??
                  'Funds will be transferred to your bank account immediately.',
              style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(),
                  color: (light ? Colors.black : Colors.white).withOpacity(0.5)),
            ),
            const SizedBox(height: 28),
            TradeRepublicButton(
              label: AppLocalizations.of(ctx)?.confirmPayout ?? 'Confirm Payout',
              icon: Icon(CupertinoIcons.bolt_fill, size: 20),
              height: 50,
              onPressed: () { HapticFeedback.lightImpact(); Navigator.of(ctx).pop(true); },
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            TradeRepublicButton(
              label: AppLocalizations.of(ctx)?.cancel ?? 'Cancel',
              isSecondary: true,
              height: 50,
              onPressed: () { HapticFeedback.lightImpact(); Navigator.of(ctx).pop(false); },
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ]),
        ]);
      }),
    );

    if (confirmed != true || !mounted) return;

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      isDismissible: false,
      enableDrag: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const DragHandle(),
        const CultiooLoadingIndicator(size: 20),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        Text(
          AppLocalizations.of(context)?.processingInstantPayoutMsg ?? 'Processing instant payout...',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
      ]),
    );

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/payout/instant'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username}),
      );

      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          TopNotification.success(
            context,
            '✅ ${AppLocalizations.of(context)?.instantPayoutCompleted ?? 'Instant payout completed!'} ${AppSettings().currencySymbol}${pendingPayout.toStringAsFixed(2)} ${AppLocalizations.of(context)?.transferred ?? 'transferred'}.',
          );
          await _refreshAllData();
        }
      } else {
        final data = json.decode(response.body);
        TopNotification.error(
          context,
          data['error'] ?? AppLocalizations.of(context)!.tr('Payout failed. Please try again.'),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error')}: $e',
      );
    }
  }

  Future<void> _handleAddAccount(String email, String password) async {
    try {
      setState(() {
        isLoading = true;
      });

      print('🔐 Attempting login for: $email');

      // Since backend login is not working, search available users by email
      final matchingUser = availableUsers.firstWhere(
        (user) => user['email']?.toLowerCase() == email.toLowerCase(),
        orElse: () => {},
      );

      if (matchingUser.isNotEmpty) {
        final userId = matchingUser['user_id'] ?? matchingUser['id'];

        print(
          '✅ Found matching user: ${matchingUser['first_name']} ${matchingUser['last_name']} ($userId)',
        );

        // Switch to the matching account
        await _switchUser(userId);

        TopNotification.success(
          context,
          '${AppLocalizations.of(context)?.successfullyLoggedInAs ?? AppLocalizations.of(context)!.tr('Successfully logged in as')} ${matchingUser['first_name']} ${matchingUser['last_name']}!',
          title:
              AppLocalizations.of(context)?.accountSwitched ?? AppLocalizations.of(context)!.tr('Account Switched'),
        );
      } else {
        print('❌ No user found with email: $email');
        print(
          '📋 Available emails: ${availableUsers.map((u) => u['email']).join(', ')}',
        );

        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.noAccountFoundWithEmail ?? AppLocalizations.of(context)!.tr('No account found with email')} "$email". ${availableUsers.map((u) => '• ${u['email']}').join('\n')}',
          title:
              AppLocalizations.of(context)?.accountNotFound ?? AppLocalizations.of(context)!.tr('Account Not Found'),
        );
      }
    } catch (e) {
      print('❌ Error during account switch: $e');
      TopNotification.error(
        context,
        'Error switching account: $e',
        title: AppLocalizations.of(context)?.switchError ?? AppLocalizations.of(context)!.tr('Switch Error'),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadUserGroups() async {
    // SILENT FAIL: Groups feature is optional, don't block the app if it fails
    try {
      // Get user ID from loaded user data
      String? userId =
          userData?['userId'] ?? userData?['id'] ?? userData?['user_id'];

      if (userId == null) {
        // No user ID - set empty groups silently
        if (mounted) {
          setState(() {
            userGroups = [];
          });
        }
        return;
      }

      // Try to load groups from API (with timeout to prevent blocking)
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/delvioo-groups/user/$userId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              // Silent timeout - just return empty response
              return http.Response('{"success":false,"error":"timeout"}', 408);
            },
          );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true && responseData['groups'] != null) {
          final groups = responseData['groups'] ?? [];

          if (mounted) {
            setState(() {
              userGroups = List<Map<String, dynamic>>.from(groups);
            });
          }
        } else {
          // API returned success=false - set empty groups silently
          if (mounted) {
            setState(() {
              userGroups = [];
            });
          }
        }
      } else {
        // API error (500, 404, etc.) - set empty groups silently
        if (mounted) {
          setState(() {
            userGroups = [];
          });
        }
      }
    } catch (e) {
      // Any error - set empty groups silently and continue
      if (mounted) {
        setState(() {
          userGroups = [];
        });
      }
    }
  }

  // Load waiting charge credits for driver
  Future<void> _loadWaitingChargeCredits() async {
    try {
      print('⏱️ Loading waiting charge credits...');

      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');

      if (userId == null || userId.isEmpty) {
        print('❌ No userId for waiting charges');
        return;
      }

      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/driver/$userId/waiting-charges'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      print('📡 Waiting charges response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          if (mounted) {
            setState(() {
              waitingChargeCredits = List<Map<String, dynamic>>.from(
                responseData['charges'] ?? [],
              );
            });
          }
          print(
            '✅ Waiting charge credits loaded: ${waitingChargeCredits.length} entries, total: ${AppSettings().currencySymbol}${responseData['totalCredits']?.toStringAsFixed(2) ?? AppLocalizations.of(context)!.tr('0.00')}',
          );
        }
      }
    } catch (e) {
      print('❌ Error loading waiting charge credits: $e');
    }
  }

  Future<void> _loadReviews() async {
    // SILENT FAIL: Reviews are optional, don't block the app
    try {
      final prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');

      if (userId == null || userId.isEmpty) {
        if (mounted) {
          setState(() {
            isLoadingReviews = false;
            reviews = [];
            averageRating = 0.0;
          });
        }
        return;
      }

      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/reviews/driver/$userId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => http.Response('{"success":false}', 408),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && mounted) {
          final reviewsData = data['data'] ?? [];
          final avgRating = data['averageRating'] ?? 0.0;

          setState(() {
            reviews = List<Map<String, dynamic>>.from(reviewsData);
            averageRating = double.tryParse(avgRating.toString()) ?? 0.0;
            isLoadingReviews = false;
          });
        } else {
          if (mounted) {
            setState(() {
              reviews = [];
              averageRating = 0.0;
              isLoadingReviews = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            reviews = [];
            averageRating = 0.0;
            isLoadingReviews = false;
          });
        }
      }
    } catch (e) {
      // Silent fail - reviews are optional
      if (mounted) {
        setState(() {
          reviews = [];
          averageRating = 0.0;
          isLoadingReviews = false;
        });
      }
    }
  }

  Future<void> _refreshAllData() async {
    setState(() { _isRefreshing = true; });
    await Future.wait([
      _loadUserData(),
      _loadUserGroups(),
      _loadMileageEntries(),
      _loadWaitingChargeCredits(),
      _loadReviews(),
    ]);
    if (mounted) setState(() { _isRefreshing = false; });
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);
    final media = MediaQuery.of(context);
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    // Adaptive paddings to avoid overflow in landscape / when keyboard is visible
    final double bottomScrollPadding = 80.0 + media.viewInsets.bottom;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: isLoading && !_isRefreshing
          ? const Center(child: CultiooLoadingIndicator())
          : userData == null
          ? Center(
              child: Text(
                AppLocalizations.of(context)?.unableToLoadAccountData ?? AppLocalizations.of(context)!.tr('Unable to load account data'),
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isDesktop ? 800 : double.infinity),
                child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                CupertinoSliverRefreshControl(
                  onRefresh: _refreshAllData,
                  refreshTriggerPullDistance: 80,
                  refreshIndicatorExtent: 60,
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20.0,
                    isDesktop ? 32.0 : MediaQuery.of(context).padding.top + 20.0,
                    20.0,
                    MediaQuery.of(context).padding.bottom + bottomScrollPadding,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  // 1. Profile Summary Card (with quick actions) - Animated
                  _buildAnimatedSection(
                    delay: 0,
                    slideFromRight: false,
                    child: _buildProfileSummary(isLight),
                  ),

                  // 2. Earnings Dashboard - Animated
                  _buildAnimatedSection(
                    delay: 1,
                    slideFromRight: true,
                    child: _buildEarningsDashboard(isLight),
                  ),

                  // 3. Reviews Section (social proof) - Animated
                  _buildAnimatedSection(
                    delay: 2,
                    slideFromRight: false,
                    child: _buildReviewsSection(isLight, appSettings),
                  ),

                  // 4. Group Management Section - Animated
                  _buildAnimatedSection(
                    delay: 3,
                    slideFromRight: true,
                    child: _buildGroupManagementSection(isLight),
                  ),

                  // 5. Payment Information Section - Animated
                  _buildAnimatedSection(
                    delay: 4,
                    slideFromRight: false,
                    child: _buildBankDetailsSection(isLight),
                  ),

                  // 6. Personal Information Section - Animated
                  _buildAnimatedSection(
                    delay: 5,
                    slideFromRight: true,
                    child: _buildPersonalInfoSection(isLight),
                  ),

                  // 7. Address Information Section - Animated
                  _buildAnimatedSection(
                    delay: 6,
                    slideFromRight: false,
                    child: _buildAddressInfoSection(isLight),
                  ),

                  // 8b. Carbon Footprint Section - Animated
                  _buildAnimatedSection(
                    delay: 8,
                    slideFromRight: false,
                    child: _buildCarbonFootprintSection(isLight),
                  ),

                  // 9. Account Management - Animated
                  _buildAnimatedSection(
                    delay: 9,
                    slideFromRight: false,
                    child: _buildAccountManagementSection(isLight),
                  ),

                  // 10. App Settings Section - Animated
                  _buildAnimatedSection(
                    delay: 10,
                    slideFromRight: true,
                    child: _buildAppSettingsSection(isLight),
                  ),

                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                  // 11. Sign Out Button - at the very bottom
                  _buildAnimatedSection(
                    delay: 11,
                    slideFromRight: false,
                    child: TradeRepublicCard(
                      padding: EdgeInsets.zero,
                      backgroundColor: isLight ? Colors.white : Colors.black,
                      child: TradeRepublicListTile.destructive(
                        title: AppLocalizations.of(context)?.signOut ?? AppLocalizations.of(context)!.tr('Sign Out'),
                        leading: const Icon(CupertinoIcons.square_arrow_left, size: 18, color: Colors.red),
                        onTap: () => _handleSignOut(context, isLight),
                      ),
                    ),
                  ),

                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
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

  // Trade Republic Style Header - Minimal & Clean
  Widget _buildTradeRepublicHeader(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.account ?? AppLocalizations.of(context)!.tr('Account'),
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)?.manageYourDriverProfile ?? AppLocalizations.of(context)!.tr('Manage your driver profile'),
          style: TextStyle(
            color: isLight
                ? Colors.black.withOpacity(0.5)
                : Colors.white.withOpacity(0.5),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // Animated Section Widget with Staggered Animation - From top/bottom
  Widget _buildAnimatedSection({
    required int delay,
    required Widget child,
    bool slideFromRight = false, // Now interpreted as slideFromBottom
  }) {
    return AnimatedBuilder(
      animation: _contentAnimController,
      builder: (context, _) {
        // Calculate staggered delay - use smaller delay factor to ensure all sections animate
        // With 9 sections, use 0.08 delay factor so max delay is 0.72 (< 1.0)
        final delayFactor = delay * 0.08;
        final delayedValue = (_contentAnimController.value - delayFactor).clamp(
          0.0,
          1.0,
        );
        final remainingRange = (1.0 - delayFactor).clamp(0.1, 1.0);
        final curvedValue = Curves.easeOutCubic.transform(
          delayedValue > 0
              ? (delayedValue / remainingRange).clamp(0.0, 1.0)
              : 0.0,
        );

        return Transform.translate(
          offset: Offset(
            0, // No horizontal movement
            // slideFromRight = true means from bottom, false = from top
            slideFromRight ? 30 * (1 - curvedValue) : -30 * (1 - curvedValue),
          ),
          child: Opacity(
            opacity: curvedValue,
            child: Transform.scale(
              scale: 0.95 + (0.05 * curvedValue),
              alignment: slideFromRight
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupManagementSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.groups ?? AppLocalizations.of(context)!.tr('Groups'),
          padding: const EdgeInsets.only(bottom: 12, top: 28, left: 4),
        ),

        // Action Buttons - Trade Republic minimal style (hidden when modal is open)
        ValueListenableBuilder<bool>(
          valueListenable: bottomSheetOpenNotifier,
          builder: (context, isModalOpen, child) {
            if (isModalOpen) {
              return const SizedBox.shrink();
            }
            return Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.createGroup ?? AppLocalizations.of(context)!.tr('Create Group'),
                    onPressed: userGroups.isEmpty
                        ? () {
                            HapticFeedback.lightImpact();
                            _showCreateGroupModal(context, isLight);
                          }
                        : () {
                            HapticFeedback.lightImpact();
                            TopNotification.info(
                              context,
                              AppLocalizations.of(
                                    context,
                                  )?.onlyOneGroupAtATime ?? AppLocalizations.of(context)!.tr('You can only be in one group at a time.'),
                            );
                          },
                    tint: isLight ? CupertinoColors.black : CupertinoColors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.joinGroup ?? AppLocalizations.of(context)!.tr('Join Group'),
                    onPressed: userGroups.isEmpty
                        ? () {
                            HapticFeedback.lightImpact();
                            _showJoinGroupModal(context, isLight);
                          }
                        : () {
                            HapticFeedback.lightImpact();
                            TopNotification.info(
                              context,
                              AppLocalizations.of(
                                    context,
                                  )?.onlyOneGroupAtATime ?? AppLocalizations.of(context)!.tr('You can only be in one group at a time.'),
                            );
                          },
                    isSecondary: true,
                  ),
                ),
              ],
            );
          },
        ),

        // User's Groups List
        if (userGroups.isNotEmpty) ...[
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context)?.yourGroup ?? AppLocalizations.of(context)!.tr('Your Group'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.leave ?? AppLocalizations.of(context)!.tr('Leave'),
                  isDestructive: true,
                  height: 36,
                  padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _showLeaveGroupConfirmation(context, isLight);
                  },
                ),
              ],
            ),
          ),
          ...userGroups.map((group) => _buildGroupCard(group, isLight)),
        ] else ...[
          const SizedBox(height: 32),
          // Empty State - Trade Republic Style
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Column(
              children: [
                Icon(
                  CupertinoIcons.group,
                  size: 48,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.3,
                  ),
                ),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                Text(
                  AppLocalizations.of(context)?.noGroup ?? AppLocalizations.of(context)!.tr('No Group'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)?.createOrJoinGroupToGetStarted ?? AppLocalizations.of(context)!.tr('Create or join a group to get started'),
                  style: TextStyle(
                    fontSize: 15,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
      ],
    );
  }

  // Trade Republic style list tile
  Widget _buildTRListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLight,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return TradeRepublicTap(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: enabled
                    ? (isLight ? Colors.black : Colors.white)
                    : (isLight ? Colors.white : Colors.black),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Icon(
                icon,
                color: enabled
                    ? (isLight ? Colors.white : Colors.black)
                    : (isLight ? Colors.white : Colors.black),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w500,
                      color: enabled
                          ? (isLight ? Colors.black : Colors.white)
                          : (isLight ? Colors.white : Colors.black),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group, bool isLight) {
    final isHost = group['isHost'] ?? false;
    final memberCount = group['memberCount'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Padding(
        padding: DesktopAppWrapper.getPagePadding(),
        child: Row(
          children: [
            // Group Image - minimal
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                child: group['groupImage'] != null
                    ? Image.network(
                        ApiConfig.getImageUrl(group['groupImage']),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            CupertinoIcons.group,
                            color: isLight ? Colors.white : Colors.black,
                            size: 24,
                          );
                        },
                      )
                    : Icon(
                        CupertinoIcons.group,
                        color: isLight ? Colors.white : Colors.black,
                        size: 24,
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Group Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          group['name'] ??
                              AppLocalizations.of(context)?.unknownGroup ?? AppLocalizations.of(context)!.tr('Unknown Group'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isHost) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isLight ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Text(
                            AppLocalizations.of(context)?.hostLabel ?? AppLocalizations.of(context)!.tr('HOST'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.white : Colors.black,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$memberCount members  •  ${group['joinCode'] ?? AppLocalizations.of(context)!.tr('')}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isLight ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ),

            // Action Buttons - minimal style (hidden when modal is open)
            ValueListenableBuilder<bool>(
              valueListenable: bottomSheetOpenNotifier,
              builder: (context, isModalOpen, child) {
                if (isModalOpen) {
                  return const SizedBox.shrink();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Chat Button
                    TradeRepublicButton.icon(
                      icon: Icon(
                        CupertinoIcons.chat_bubble,
                        color: isLight ? Colors.black : Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _showGroupChatModal(context, group, isLight);
                      },
                      isSecondary: true,
                    ),
                    const SizedBox(width: 8),
                    // Settings Button
                    TradeRepublicButton.icon(
                      icon: Icon(
                        CupertinoIcons.settings,
                        color: isLight ? Colors.black : Colors.white,
                        size: 20,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _showGroupSettingsModal(context, group, isLight);
                      },
                      isSecondary: true,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSummary(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Profile Image — circular, centered (like account_page)
        Center(
          child: TradeRepublicTap(
            onTap: () {
              HapticFeedback.lightImpact();
              _showProfileImageModal(context, isLight, _onProfileImageUpdated);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: userData?['profileImage'] != null
                      ? Image.network(
                          ApiConfig.getImageUrl(userData!['profileImage']),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            CupertinoIcons.person_fill,
                            size: 36,
                            color: isLight ? Colors.white : Colors.black,
                          ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: CultiooLoadingIndicator(size: 20),
                            );
                          },
                        )
                      : Icon(
                          CupertinoIcons.person_fill,
                          size: 36,
                          color: isLight ? Colors.white : Colors.black,
                        ),
                ),
                // Camera badge
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white : Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.camera_fill,
                      size: 12,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        // Driver Name
        Text(
          userData?['fullName'] ??
              '${userData?['firstName'] ?? AppLocalizations.of(context)!.tr('Driver')} ${userData?['lastName'] ?? AppLocalizations.of(context)!.tr('')}'.trim(),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: isLight ? Colors.black : Colors.white,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          userData?['email'] ?? AppLocalizations.of(context)!.tr(''),
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w400,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        // Edit Profile + Status row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)?.active ?? AppLocalizations.of(context)!.tr('Active'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Edit Profile button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.editProfile ?? AppLocalizations.of(context)!.tr('Edit Profile'),
              onPressed: () {
                HapticFeedback.lightImpact();
                _showProfileEditModal(context, isLight);
              },
              isSecondary: true,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            ),
          ],
        ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
      ],
    );
  }

  Widget _buildStatusBadge(String text, bool isLight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection(bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.personal ?? AppLocalizations.of(context)!.tr('Personal'),
          padding: const EdgeInsets.only(bottom: 12, top: 28, left: 4),
        ),
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          backgroundColor: isLight ? Colors.white : Colors.black,
          child: Column(
            children: [
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.username ?? AppLocalizations.of(context)!.tr(''),
                subtitle: userData?['username'] != null ? '@${userData!['username']}' : (AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A')),
                leading: const Icon(CupertinoIcons.person_badge_plus, size: 18),
              ),
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.email ?? AppLocalizations.of(context)!.tr('Email'),
                subtitle: userData?['email']?.toString() ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                leading: const Icon(CupertinoIcons.mail, size: 18),
              ),
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.phone ?? AppLocalizations.of(context)!.tr('Phone'),
                subtitle: userData?['phone']?.toString() ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                leading: const Icon(CupertinoIcons.phone, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressInfoSection(bool isLight) {
    final address = userData?['address'] ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.address ?? AppLocalizations.of(context)!.tr('Address'),
          padding: const EdgeInsets.only(bottom: 12, top: 16, left: 4),
        ),
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          backgroundColor: isLight ? Colors.white : Colors.black,
          child: Column(
            children: [
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.street ?? AppLocalizations.of(context)!.tr('Street'),
                subtitle: address['street']?.toString() ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                leading: const Icon(CupertinoIcons.house, size: 18),
              ),
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.city ?? AppLocalizations.of(context)!.tr('City'),
                subtitle: address['city']?.toString() ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                leading: const Icon(CupertinoIcons.building_2_fill, size: 18),
              ),
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.zipCode ?? AppLocalizations.of(context)!.tr('ZIP Code'),
                subtitle: address['zipCode']?.toString() ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                leading: const Icon(CupertinoIcons.mail, size: 18),
              ),
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.country ?? AppLocalizations.of(context)!.tr('Country'),
                subtitle: address['country']?.toString() ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                leading: const Icon(CupertinoIcons.globe, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleInfoSection(bool isLight) {
    final vehicle = userData?['vehicle'] ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.vehicleInformation ?? AppLocalizations.of(context)!.tr('Vehicle Information'),
          padding: const EdgeInsets.only(bottom: 12, top: 16, left: 4),
        ),
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          backgroundColor: isLight ? Colors.white : Colors.black,
          child: Column(
            children: [
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.vehicleType ?? AppLocalizations.of(context)!.tr('Vehicle Type'),
                subtitle: vehicle['fullVehicle']?.toString() ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                leading: const Icon(CupertinoIcons.cube_box, size: 18),
                subtitleMaxLines: 2,
              ),
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.licensePlate ?? AppLocalizations.of(context)!.tr('License Plate'),
                subtitle: vehicle['licensePlate']?.toString() ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                leading: const Icon(CupertinoIcons.doc_text, size: 18),
                subtitleMaxLines: 2,
              ),
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.makeAndModel ?? AppLocalizations.of(context)!.tr('Make & Model'),
                subtitle: '${vehicle['make'] ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A')} ${vehicle['model'] ?? AppLocalizations.of(context)!.tr('')}'.trim(),
                leading: const Icon(CupertinoIcons.car, size: 18),
                subtitleMaxLines: 2,
              ),
              TradeRepublicListTile(
                title: AppLocalizations.of(context)?.year ?? AppLocalizations.of(context)!.tr('Year'),
                subtitle: vehicle['year']?.toString() ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                leading: const Icon(CupertinoIcons.calendar, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildBankDetailsSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.payment ?? AppLocalizations.of(context)!.tr('Payment'),
          padding: const EdgeInsets.only(bottom: 12, top: 28, left: 4),
        ),
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          backgroundColor: isLight ? Colors.white : Colors.black,
          child: TradeRepublicListTile.navigation(
            title: AppLocalizations.of(context)?.paymentSettings ?? AppLocalizations.of(context)!.tr('Payment Settings'),
            subtitle: AppLocalizations.of(context)?.bankDetailsPaymentMethods ?? AppLocalizations.of(context)!.tr('Bank details, payment methods'),
            leading: const Icon(CupertinoIcons.creditcard, size: 18),
            onTap: () => _showPaymentSetupModal(context, isLight),
          ),
        ),
      ],
    );
  }

  Widget _buildEarningsDashboard(bool isLight) {
    final appSettings = Provider.of<AppSettings>(context);

    // Debug: Check userData state
    print('💵 _buildEarningsDashboard called');
    print('💵 userData: $userData');
    print('💵 userData[pendingPayout]: ${userData?['pendingPayout']}');
    print('💵 userData[totalEarnings]: ${userData?['totalEarnings']}');

    // Real data from API - no mock data
    final pendingPayout = (userData?['pendingPayout'] is int)
        ? (userData!['pendingPayout'] as int).toDouble()
        : (userData?['pendingPayout'] ?? 0.0) as double;
    final totalDeliveries = userData?['totalDeliveries'] ?? 0;
    final totalAccepted = userData?['totalAccepted'] ?? 0;
    final totalDistance = (userData?['totalDistance'] is int)
        ? (userData!['totalDistance'] as int).toDouble()
        : (userData?['totalDistance'] ?? 0.0) as double;
    final nextPayoutDate = userData?['nextPayoutDate'] ?? _getNextPayoutDate();

    print('💵 Final pendingPayout value: $pendingPayout');
    print('💵 Final totalDistance value: $totalDistance');
    print('💵 Final totalAccepted value: $totalAccepted');

    final Map<String, dynamic>? groupAgg =
        (userData?['groupAggregation'] is Map)
        ? Map<String, dynamic>.from(userData!['groupAggregation'])
        : null;
    final bool isInGroup = groupAgg?['isInGroup'] == true;
    final bool isHost = groupAgg?['isHost'] == true;
    final String hostName = groupAgg?['hostName']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final String hostUserId = groupAgg?['hostUserId']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final int memberCount =
        int.tryParse(groupAgg?['memberCount']?.toString() ?? AppLocalizations.of(context)!.tr('1')) ?? 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.earnings ?? AppLocalizations.of(context)!.tr('Earnings'),
          padding: const EdgeInsets.only(bottom: 12, top: 28, left: 4),
        ),
        TradeRepublicCard(
          padding: DesktopAppWrapper.getPagePadding(),
          backgroundColor: isLight ? Colors.white : Colors.black,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group earnings banner
              if (isInGroup) ...[
                Container(
                  width: double.infinity,
                  padding: DesktopAppWrapper.getPagePadding(),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isLight ? Colors.black : Colors.white,
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Icon(
                          isHost
                              ? CupertinoIcons.star_fill
                              : CupertinoIcons.info,
                          color: isLight ? Colors.white : Colors.black,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isHost
                                  ? AppLocalizations.of(context)?.groupHost ?? AppLocalizations.of(context)!.tr('Group Host')
                                  : AppLocalizations.of(context)?.groupMember ?? AppLocalizations.of(context)!.tr('Group Member'),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isHost
                                  ? 'You receive all earnings from your group (${memberCount - 1} members).'
                                  : 'Your earnings go to group host: ${hostName.isNotEmpty ? hostName : hostUserId}.',
                              style: TextStyle(
                                fontSize: 13,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Earnings Cards - 3 cards layout
              Row(
                children: [
                  Expanded(
                    child: _buildEarningsCard(
                      AppLocalizations.of(context)?.thisMonth ?? AppLocalizations.of(context)!.tr('This Month'),
                      appSettings.formatCurrency(
                        appSettings.convertCurrency(pendingPayout),
                      ),
                      CupertinoIcons.graph_square,
                      isLight ? Colors.black : Colors.white,
                      AppLocalizations.of(context)?.pendingPayout ?? AppLocalizations.of(context)!.tr('Pending payout'),
                      isLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              Row(
                children: [
                  Expanded(
                    child: _buildEarningsCard(
                      AppLocalizations.of(context)?.distance ?? AppLocalizations.of(context)!.tr('Distance'),
                      appSettings.formatDistance(totalDistance),
                      CupertinoIcons.map,
                      isLight ? Colors.black : Colors.white,
                      AppLocalizations.of(context)?.totalDriven ?? AppLocalizations.of(context)!.tr('Total driven'),
                      isLight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildEarningsCard(
                      AppLocalizations.of(context)?.orders ?? AppLocalizations.of(context)!.tr('Orders'),
                      totalAccepted.toString(),
                      CupertinoIcons.cube_box,
                      isLight ? Colors.black : Colors.white,
                      AppLocalizations.of(context)?.acceptedLabel ?? AppLocalizations.of(context)!.tr('Accepted'),
                      isLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Next Payout Info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.clock,
                      color: isLight ? Colors.black : Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.nextPayout ?? AppLocalizations.of(context)!.tr('Next Payout'),
                            style: TextStyle(
                              fontSize: 13,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            nextPayoutDate,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ═══════════════════════════════════════════
        // WAITING CHARGE CREDITS 
        // ═══════════════════════════════════════════
        if (waitingChargeCredits.isNotEmpty) ...[
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 22,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)?.waitingTimeCompensation ?? AppLocalizations.of(context)!.tr('Waiting Time Compensation'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              AppLocalizations.of(context)?.compensationForSellerWaiting ?? AppLocalizations.of(context)!.tr('Compensation for waiting time at sellers'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: (isLight ? Colors.black : Colors.white)
                    .withOpacity(0.5),
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Total credits summary
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: Colors.green.shade50.withOpacity(isLight ? 1.0 : 0.1),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context)?.totalReceived ?? AppLocalizations.of(context)!.tr('Total received'),
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                    color: isLight ? Colors.black87 : Colors.white70,
                  ),
                ),
                Text(
                  '+${appSettings.formatCurrency(waitingChargeCredits.fold<double>(0.0, (sum, c) => sum + ((c['total_charges'] ?? 0.0) as num).toDouble()))}',
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                    fontWeight: FontWeight.w700,
                    color: Colors.green,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Individual credit entries
          ...waitingChargeCredits.map((charge) {
            final orderId = charge['order_id'] ?? AppLocalizations.of(context)!.tr('');
            final sellerName = charge['seller_name'] ?? charge['seller_username'] ?? (AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown'));
            final totalCharges = ((charge['total_charges'] ?? 0.0) as num).toDouble();
            final sellerSec = ((charge['seller_waiting_seconds'] ?? 0) as num).toInt();
            final buyerSec = ((charge['buyer_waiting_seconds'] ?? 0) as num).toInt();
            final totalSec = sellerSec + buyerSec;
            final totalMin = (totalSec / 60).ceil();
            final orderDate = charge['order_date'] != null
                ? DateTime.tryParse(charge['order_date'].toString())
                : null;
            final dateStr = orderDate != null
                ? '${orderDate.day.toString().padLeft(2, '0')}.${orderDate.month.toString().padLeft(2, '0')}.${orderDate.year}'
                : '';

            return GestureDetector(
              onTap: () => _showWaitingChargeInvoice(charge, isLight, appSettings),
              child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: DesktopAppWrapper.getPagePadding(),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
              ),
              child: Row(
                children: [
                  // Timer icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.green.shade50.withOpacity(isLight ? 1.0 : 0.15),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.timer,
                        size: 22,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}$orderId',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${AppLocalizations.of(context)?.sellerColon ?? AppLocalizations.of(context)!.tr('Seller:')} $sellerName • $totalMin Min',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.5),
                          ),
                        ),
                        if (dateStr.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.35),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+${appSettings.formatCurrency(totalCharges)}',
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                          fontWeight: FontWeight.w700,
                          color: Colors.green,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        CupertinoIcons.doc_text,
                        size: 14,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                      ),
                    ],
                  ),
                ],
              ),
            ));
          }),
        ],
      ],
    );
  }

  void _showWaitingChargeInvoice(
    Map<String, dynamic> charge,
    bool isLight,
    AppSettings appSettings,
  ) {
    final orderId = charge['order_id'] ?? '';
    final sellerName = charge['seller_name'] ?? charge['seller_username'] ?? (AppLocalizations.of(context)?.unknownLabel ?? 'Unknown');
    final totalCharges = ((charge['total_charges'] ?? 0.0) as num).toDouble();
    final sellerSec = ((charge['seller_waiting_seconds'] ?? 0) as num).toInt();
    final buyerSec = ((charge['buyer_waiting_seconds'] ?? 0) as num).toInt();
    final freeMinutes = ((charge['waiting_free_minutes'] ?? 15) as num).toInt();
    final ratePerHour = ((charge['waiting_rate_per_hour'] ?? 0.0) as num).toDouble();
    final totalSec = sellerSec + buyerSec;
    final chargeableSec = (totalSec - freeMinutes * 60).clamp(0, totalSec);
    final orderDate = charge['order_date'] != null ? DateTime.tryParse(charge['order_date'].toString()) : DateTime.now();
    final paid = charge['waiting_charges_paid'] == true || charge['waiting_charges_paid'] == 1;

    String fmtSec(int s) {
      final h = s ~/ 3600; final m = (s % 3600) ~/ 60; final sec = s % 60;
      if (h > 0) return '${h}h ${m}m'; if (m > 0) return '${m}m ${sec}s'; return '${sec}s';
    }

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DragHandle(),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                      ),
                      child: const Icon(CupertinoIcons.doc_text_fill, color: Colors.green, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.tr('Waiting Charges Receipt') ?? 'Waiting Charges Receipt',
                            style: const TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 4, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${AppLocalizations.of(context)?.orderNumber ?? 'Order #'}$orderId',
                            style: TextStyle(fontSize: 13, color: (isLight ? Colors.black : Colors.white).withOpacity(0.45)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: paid ? Colors.green : Colors.orange,
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Text(
                        paid ? (AppLocalizations.of(context)?.tr('Paid') ?? 'Paid') : (AppLocalizations.of(context)?.tr('Pending') ?? 'Pending'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                _buildDriverInvoiceRow(isLight, AppLocalizations.of(context)?.tr('Date') ?? 'Date',
                  orderDate != null ? '${orderDate.day.toString().padLeft(2,'0')}.${orderDate.month.toString().padLeft(2,'0')}.${orderDate.year}' : '—'),
                _buildDriverInvoiceRow(isLight, AppLocalizations.of(context)?.tr('Seller') ?? 'Seller', sellerName),
                _buildDriverInvoiceRow(isLight, AppLocalizations.of(context)?.freeWaiting ?? 'Free Waiting', '$freeMinutes min'),
                _buildDriverInvoiceRow(isLight, AppLocalizations.of(context)?.tr('Total Waited') ?? 'Total Waited', fmtSec(totalSec)),
                if (sellerSec > 0) _buildDriverInvoiceRow(isLight, AppLocalizations.of(context)?.tr('Pickup Waiting') ?? 'Pickup Waiting', fmtSec(sellerSec)),
                if (buyerSec > 0) _buildDriverInvoiceRow(isLight, AppLocalizations.of(context)?.tr('Delivery Waiting') ?? 'Delivery Waiting', fmtSec(buyerSec)),
                _buildDriverInvoiceRow(isLight, AppLocalizations.of(context)?.tr('Chargeable Time') ?? 'Chargeable Time', fmtSec(chargeableSec)),
                if (ratePerHour > 0) _buildDriverInvoiceRow(isLight, AppLocalizations.of(context)?.tr('Rate/hr') ?? 'Rate/hr', appSettings.formatCurrency(ratePerHour)),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppLocalizations.of(context)?.tr('You received') ?? 'You received',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text('+${appSettings.formatCurrency(totalCharges)}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                Text(
                  AppLocalizations.of(context)?.tr('This amount was transferred to you for waiting beyond the free waiting time.') ?? 'This amount was transferred to you for waiting beyond the free waiting time.',
                  style: TextStyle(fontSize: 12, color: (isLight ? Colors.black : Colors.white).withOpacity(0.38), height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDriverInvoiceRow(bool isLight, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: (isLight ? Colors.black : Colors.white).withOpacity(0.54))),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isLight ? Colors.black : Colors.white)),
        ],
      ),
    );
  }

  Widget _buildEarningsCard(
    String title,
    String amount,
    IconData icon,
    Color color,
    String subtitle,
    bool isLight,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isLight ? Colors.black : Colors.white, size: 22),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: isLight ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
              fontWeight: FontWeight.w700,
              color: isLight ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isLight ? Colors.black : Colors.white,
            ),
          ),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.white)),
        ],
      ),
    );
  }

  String _maskAccountNumber(String accountNumber) {
    if (accountNumber == 'N/A' || accountNumber.length < 4) {
      return accountNumber;
    }
    // Show only last 4 digits for US account numbers
    final end = accountNumber.substring(accountNumber.length - 4);
    final masked = '*' * (accountNumber.length - 4);
    return '$masked$end';
  }

  String _getNextPayoutDate() {
    final now = DateTime.now();
    // If we're past the 1st of this month, next payout is 1st of next month
    // If we're before or on the 1st, next payout is 1st of this month
    DateTime nextPayout;
    if (now.day == 1) {
      nextPayout = DateTime(now.year, now.month, 1);
    } else if (now.day > 1) {
      // Next month
      nextPayout = DateTime(now.year, now.month + 1, 1);
    } else {
      nextPayout = DateTime(now.year, now.month, 1);
    }

    // Handle year rollover
    if (nextPayout.month > 12) {
      nextPayout = DateTime(nextPayout.year + 1, 1, 1);
    }

    // Format date
    final months = [
      AppLocalizations.of(context)?.january ?? AppLocalizations.of(context)!.tr('January'),
      AppLocalizations.of(context)?.february ?? AppLocalizations.of(context)!.tr('February'),
      AppLocalizations.of(context)?.march ?? AppLocalizations.of(context)!.tr('March'),
      AppLocalizations.of(context)?.april ?? AppLocalizations.of(context)!.tr('April'),
      'May',
      AppLocalizations.of(context)?.june ?? AppLocalizations.of(context)!.tr('June'),
      AppLocalizations.of(context)?.july ?? AppLocalizations.of(context)!.tr('July'),
      AppLocalizations.of(context)?.august ?? AppLocalizations.of(context)!.tr('August'),
      AppLocalizations.of(context)?.september ?? AppLocalizations.of(context)!.tr('September'),
      AppLocalizations.of(context)?.october ?? AppLocalizations.of(context)!.tr('October'),
      AppLocalizations.of(context)?.november ?? AppLocalizations.of(context)!.tr('November'),
      AppLocalizations.of(context)?.december ?? AppLocalizations.of(context)!.tr('December'),
    ];
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    return appSettings.formatDate(nextPayout);
  }

  void _showCreateGroupModal(BuildContext context, bool isLight) {
    // Hide dock when modal opens
    hideDockNotifier.value = true;
    // Hide buttons when modal opens
    bottomSheetOpenNotifier.value = true;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: _CreateGroupModal(isLight: isLight, userData: userData),
      ),
    ).whenComplete(() {
      // Show dock when modal closes
      hideDockNotifier.value = false;
      // Show buttons when modal closes
      bottomSheetOpenNotifier.value = false;
    });
  }

  void _showJoinGroupModal(BuildContext context, bool isLight) {
    // Hide dock when modal opens
    hideDockNotifier.value = true;
    // Hide buttons when modal opens
    bottomSheetOpenNotifier.value = true;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: _JoinGroupModal(isLight: isLight, userData: userData),
      ),
    ).whenComplete(() {
      // Show dock when modal closes
      hideDockNotifier.value = false;
      // Show buttons when modal closes
      bottomSheetOpenNotifier.value = false;
    });
  }

  void _showGroupSettingsModal(
    BuildContext context,
    Map<String, dynamic> group,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _GroupSettingsModal(
        group: group,
        isLight: isLight,
        userData: userData,
        onGroupUpdated: () {
          _loadUserGroups();
        },
      ),
    );
  }

  // Helper method to check if payment info exists
  bool _hasPaymentInfo() {
    if (userData == null) return false;

    // Check paymentInfo object
    final paymentInfo = userData!['paymentInfo'];
    if (paymentInfo != null && paymentInfo is Map) {
      if (paymentInfo['accountHolder'] != null ||
          paymentInfo['iban'] != null ||
          paymentInfo['accountNumber'] != null) {
        return true;
      }
    }

    // Check direct fields (from registration or database)
    if (userData!['stripeBankAccountId'] != null ||
        userData!['stripe_bank_account_id'] != null ||
        userData!['accountHolderName'] != null ||
        userData!['account_holder_name'] != null ||
        userData!['iban'] != null ||
        userData!['accountNumber'] != null ||
        userData!['account_number'] != null) {
      return true;
    }

    return false;
  }

  void _showPaymentSetupModal(BuildContext context, bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    // Set bottom sheet state to hide dock/tabbar
    bottomSheetOpenNotifier.value = true;

    _hideHeader();
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setModalState) => SizedBox(
          height: MediaQuery.of(context).size.height * 1,
          width: MediaQuery.of(context).size.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ═══════════════════════════════════════════
                      // BALANCE SECTION - Hero Element
                      // ═══════════════════════════════════════════
                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                      // Balance label
                      Center(
                        child: Text(
                          AppLocalizations.of(context)?.available ?? AppLocalizations.of(context)!.tr('Available'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      // Big Balance Number - centered
                      Center(
                        child: Text(
                          appSettings.formatCurrency(
                            appSettings.convertCurrency(
                              userData?['pendingPayout']?.toDouble() ??
                                  userData?['totalEarnings']?.toDouble() ??
                                  0.0,
                            ),
                          ),
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -2.5,
                            height: 1.0,
                          ),
                        ),
                      ),

                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                      // Stats Row - pill style
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.05),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.arrow_up_right,
                                  size: 14,
                                  color: const Color(0xFF34C759),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  appSettings.formatCurrency(
                                    appSettings.convertCurrency(
                                      userData?['totalEarnings']?.toDouble() ?? 0.0,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? Colors.black : Colors.white,
                                  ),
                                ),
                                Text(
                                  ' ${AppLocalizations.of(context)?.totalEarnings ?? AppLocalizations.of(context)!.tr('total')}',
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w400,
                                    color: (isLight ? Colors.black : Colors.white)
                                        .withOpacity(0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.05),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.cube_box,
                                  size: 14,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${userData?['totalDeliveries'] ?? 0}',
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? Colors.black : Colors.white,
                                  ),
                                ),
                                Text(
                                  ' ${AppLocalizations.of(context)?.deliveries ?? AppLocalizations.of(context)!.tr('deliveries')}',
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w400,
                                    color: (isLight ? Colors.black : Colors.white)
                                        .withOpacity(0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 40),

                      // Group Members Earnings (only for hosts)
                      if (userData?['groupAggregation'] != null &&
                          userData!['groupAggregation']['isInGroup'] == true &&
                          userData!['groupAggregation']['isHost'] == true) ...[
                        Text(
                          AppLocalizations.of(context)?.groupMembers ?? AppLocalizations.of(context)!.tr('Group Members'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(userData!['groupAggregation']['memberCount'] ?? 1) - 1} members in your group',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w400,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.4),
                          ),
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Container(
                          width: double.infinity,
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.05),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLocalizations.of(context)?.groupTotal ?? AppLocalizations.of(context)!.tr('Group Total'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.6),
                                ),
                              ),
                              Text(
                                appSettings.formatCurrency(
                                  appSettings.convertCurrency(
                                    userData?['pendingPayout']?.toDouble() ??
                                        userData?['totalEarnings']
                                            ?.toDouble() ??
                                        0.0,
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF34C759),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],

                      // ═══════════════════════════════════════════
                      // PAYOUT SCHEDULE
                      // ═══════════════════════════════════════════
                      Text(
                        AppLocalizations.of(context)?.payoutSchedule ?? AppLocalizations.of(context)!.tr('Payout Schedule'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      // Payout Info Card - clean
                      Container(
                        width: double.infinity,
                        padding: DesktopAppWrapper.getPagePadding(),
                        decoration: BoxDecoration(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.05),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF34C759),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${AppLocalizations.of(context)?.nextPayout ?? AppLocalizations.of(context)!.tr('Next payout')}: ${_getNextPayoutDate()}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            Text(
                              AppLocalizations.of(context)?.automaticMonthlyPayout ?? AppLocalizations.of(context)!.tr('Automatic monthly payout on the 1st'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(context)?.platformFee ?? AppLocalizations.of(context)!.tr('Platform fee: 5% per transaction'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                      // Instant Payout Button
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)?.instantPayout ?? 'Instant Payout',
                        icon: Icon(CupertinoIcons.bolt_fill, size: 18),
                        height: 50,
                        onPressed: () => _processDriverInstantPayout(isLight),
                      ),

                      const SizedBox(height: 40),

                      // ═══════════════════════════════════════════
                      // BANK ACCOUNT SECTION
                      // ═══════════════════════════════════════════
                      Text(
                        AppLocalizations.of(context)?.bankAccount ?? AppLocalizations.of(context)!.tr('Bank Account'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(
                              context,
                            )?.yourConnectedPaymentMethod ?? AppLocalizations.of(context)!.tr('Your connected payment method'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w400,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                      // Existing payment info (if available) - Modern Bank Card Design
                      // Check multiple sources for payment data
                      if (_hasPaymentInfo()) ...[
                        TradeRepublicSwipeAction(
                          margin: const EdgeInsets.only(bottom: 16),
                          trailing: TradeRepublicSwipeSpec(
                            icon: CupertinoIcons.delete_solid,
                            label: AppLocalizations.of(context)?.delete ?? 'Delete',
                            backgroundColor: const Color(0xFFFF3B30),
                            foregroundColor: Colors.white,
                            onActivate: () =>
                                _showDeletePaymentConfirmation(context, isLight),
                          ),
                          child: Builder(
                            builder: (context) {
                              final pi = userData!['paymentInfo'];
                              final isAch = (userData!['bankType'] == 'ACH') ||
                                  (userData!['bank_type'] == 'ACH') ||
                                  (pi?['paymentSystem'] == 'ACH') ||
                                  (pi?['paymentSystem'] == (AppLocalizations.of(context)?.usaLabel ?? 'USA'));
                              final bankType = isAch ? 'ach' : 'sepa';

                              String last4 = '';
                              if (isAch) {
                                last4 = (pi?['accountNumberLast4'])?.toString() ?? '';
                                if (last4.isEmpty) {
                                  final acc = (pi?['accountNumber'] ?? userData!['accountNumber'] ?? userData!['account_number'])?.toString() ?? '';
                                  if (acc.length >= 4) last4 = acc.substring(acc.length - 4);
                                }
                              } else {
                                last4 = (pi?['ibanLast4'])?.toString() ?? '';
                                if (last4.isEmpty) {
                                  final iban = (pi?['iban'] ?? userData!['iban'])?.toString() ?? '';
                                  if (iban.length >= 4) last4 = iban.substring(iban.length - 4);
                                }
                              }

                              final holder = ((pi?['accountHolder']) ??
                                      userData!['accountHolderName'] ??
                                      userData!['account_holder_name'] ??
                                      userData!['swiftAccountHolder'] ??
                                      userData!['swift_account_holder'] ??
                                      '')
                                  .toString();

                              final routing = isAch
                                  ? ((pi?['routingNumber']) ?? userData!['routingNumber'] ?? userData!['routing_number'] ?? '').toString()
                                  : ((pi?['bic']) ?? userData!['swiftBic'] ?? userData!['swift_bic'] ?? '').toString();

                              return BankAccountWidget(
                                type: bankType,
                                maskedNumber: last4,
                                accountHolderName: holder,
                                routingOrSwift: routing,
                                isDefault: false,
                              );
                            },
                          ),
                        ),
                        // Swipe hint
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.arrow_left,
                                size: 16,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.3),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.swipeLeftToDelete ?? AppLocalizations.of(context)!.tr('Swipe left to delete'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.3),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // No payment method - Don't show add button since only one method allowed
                      ],

                      // Add payment method button - Only show when no payment method exists - Trade Republic Style
                      if ((userData?['paymentInfo'] == null ||
                              (userData!['paymentInfo']['accountHolder'] ==
                                      null &&
                                  userData!['paymentInfo']['iban'] == null)) &&
                          userData?['stripeBankAccountId'] == null &&
                          userData?['stripe_bank_account_id'] == null &&
                          userData?['accountHolderName'] == null &&
                          userData?['account_holder_name'] == null) ...[
                        TradeRepublicListTile.navigation(
                          title: AppLocalizations.of(context)?.addPaymentMethod ?? AppLocalizations.of(context)!.tr('Add Payment Method'),
                          subtitle: AppLocalizations.of(context)?.connectYourBankAccount ?? AppLocalizations.of(context)!.tr('Connect your bank account'),
                          leading: Icon(CupertinoIcons.creditcard, size: 20),
                          onTap: () {
                            Navigator.pop(context);
                            _showAddPaymentMethodModal(context, isLight);
                          },
                        ),
                      ],

                      const SizedBox(height: 40),

                      // Payout History Section
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          AppLocalizations.of(context)?.payoutHistory ?? AppLocalizations.of(context)!.tr('Payout History'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          AppLocalizations.of(context)?.yourPastPayouts ?? AppLocalizations.of(context)!.tr('Your past payouts'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w400,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      // Payout History List - Trade Republic Style
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _loadPayoutHistory(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: isLight
                                    ? Colors.transparent
                                    : Colors.black,
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                              ),
                              child: Center(
                                child: CultiooLoadingIndicator(size: 24),
                              ),
                            );
                          }

                          if (snapshot.hasError) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: isLight
                                    ? Colors.transparent
                                    : Colors.black,
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                              ),
                              child: Text(
                                AppLocalizations.of(
                                      context,
                                    )?.failedToLoadPayoutHistory ?? AppLocalizations.of(context)!.tr('Failed to load payout history'),
                                style: TextStyle(
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5),
                                ),
                              ),
                            );
                          }

                          final payouts = snapshot.data ?? [];

                          if (payouts.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      color: (isLight ? Colors.black : Colors.white)
                                          .withOpacity(0.06),
                                    ),
                                    child: Icon(
                                      CupertinoIcons.clock,
                                      size: 24,
                                      color: (isLight ? Colors.black : Colors.white)
                                          .withOpacity(0.25),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    AppLocalizations.of(context)?.noPayoutHistoryYet ?? AppLocalizations.of(context)!.tr('No payout history yet'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                      fontWeight: FontWeight.w600,
                                      color: (isLight ? Colors.black : Colors.white)
                                          .withOpacity(0.7),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    AppLocalizations.of(context)?.yourPayoutsWillAppearHere ?? AppLocalizations.of(context)!.tr('Your payouts will appear here'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                      fontWeight: FontWeight.w400,
                                      color: (isLight ? Colors.black : Colors.white)
                                          .withOpacity(0.4),
                                    ),
                                  ),
                                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                                ],
                              ),
                            );
                          }

                          return Column(
                            children: [
                              ...payouts.map((payout) {
                                return _buildPayoutHistoryItem(
                                  payout,
                                  isLight,
                                  appSettings,
                                );
                              }),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      // Reset bottom sheet state when modal closes
      bottomSheetOpenNotifier.value = false;
      _showHeader();
    });
  }

  void _showAddPaymentMethodModal(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _StripePaymentModal(
        isLight: isLight,
        userData: userData,
        onPaymentInfoUpdated: (paymentInfo) {
          setState(() {
            userData?['paymentInfo'] = paymentInfo;
          });
          _updateStripePaymentInDatabase(paymentInfo);
        },
      ),
    );
  }

  Future<void> _updateStripePaymentInDatabase(
    Map<String, dynamic> paymentInfo,
  ) async {
    try {
      if (userData == null) return;

      // Must be username or email – the backend searches WHERE username = ? OR email = ?
      final userId =
          userData!['username'] ?? userData!['email'] ??
          userData!['user_id'] ?? userData!['userId'] ?? userData!['id'];

      if (userId == null) {
        print('❌ No user ID found in userData');
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.tr('User ID not found. Please reload the page.') ?? AppLocalizations.of(context)!.tr('User ID not found. Please reload the page.'),
          );
        }
        return;
      }

      print('💳 Updating payment info for user: $userId');

      // Prepare stripeData based on payment system
      final Map<String, dynamic> stripeData;

      if (paymentInfo['paymentSystem'] ==
          (AppLocalizations.of(context)?.usaLabel ?? AppLocalizations.of(context)!.tr('USA'))) {
        stripeData = {
          'accountHolder': paymentInfo['accountHolder'],
          'bankName': paymentInfo['bankName'],
          'accountNumber': paymentInfo['accountNumber'],
          'routingNumber': paymentInfo['routingNumber'],
          'accountType': paymentInfo['accountType'],
          'country': 'US',
          'currency': 'usd',
          'paymentSystem': AppLocalizations.of(context)?.usaLabel ?? AppLocalizations.of(context)!.tr('USA'),
        };
      } else {
        // SEPA System
        stripeData = {
          'accountHolder': paymentInfo['accountHolder'],
          'bankName': paymentInfo['bankName'],
          'iban': paymentInfo['iban'],
          'bic': paymentInfo['bic'],
          'country':
              paymentInfo['country'] ?? paymentInfo['iban']?.substring(0, 2),
          'currency': 'eur',
          'paymentSystem': 'SEPA',
        };
      }

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/stripe-payment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'paymentInfo': paymentInfo,
          'stripeData': stripeData,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('✅ Stripe payment info updated successfully');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('delvioo_payout_account_verified', true);

        // Update local data with Stripe account ID if returned
        if (responseData['stripeAccountId'] != null) {
          setState(() {
            userData?['paymentInfo']?['stripeAccountId'] =
                responseData['stripeAccountId'];
            userData?['paymentInfo']?['stripeStatus'] =
                responseData['stripeStatus'] ??
                AppLocalizations.of(context)?.active ?? AppLocalizations.of(context)!.tr('Active');
          });
        }

        TopNotification.success(
          context,
          AppLocalizations.of(context)?.paymentConnectedViaStripe ?? AppLocalizations.of(context)!.tr('Payment information connected via Stripe!'),
        );
      } else {
        print('❌ Failed to update payment info: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.errorConnectingPaymentInfo ?? AppLocalizations.of(context)!.tr('Error connecting payment information'),
          );
        }
      }
    } catch (e) {
      print('❌ Error updating payment info: $e');

      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.errorConnectingToStripe ?? AppLocalizations.of(context)!.tr('Error connecting to Stripe')}: $e',
        );
      }
    }
  }

  void _showAddAccountModal(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _AddAccountModal(
        isLight: isLight,
        availableUsers: availableUsers,
        selectedUserId: selectedUserId,
        onAccountSwitch: _switchUser,
        onAccountAdd: _handleAddAccount,
      ),
    );
  }

  void _handleSignOut(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.square_arrow_left,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.signOut ?? AppLocalizations.of(context)!.tr('Sign Out'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // Description
            Text(
              AppLocalizations.of(context)?.signOutConfirmation ??
                  AppLocalizations.of(context)!.tr(
                    "Are you sure you want to sign out?\\nYou'll need to sign in again to access your account.",
                  ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
                height: 1.4,
              ),
            ),

            const SizedBox(height: 32),

            // Sign Out Button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.signOut ?? AppLocalizations.of(context)!.tr('Sign Out'),
              onPressed: () async {
                HapticFeedback.heavyImpact();
                Navigator.pop(context);

                // Real logout logic
                final appSettings = Provider.of<AppSettings>(
                  context,
                  listen: false,
                );
                await appSettings.logout();

                // Clear SharedPreferences
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();

                // Navigate to login page
                if (context.mounted) {
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              },
              isDestructive: true,
              width: double.infinity,
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel Button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () => Navigator.pop(context),
              isSecondary: true,
              width: double.infinity,
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          ],
        ),
    );
  }

  void _showProfileEditModal(BuildContext context, bool isLight) {
    _hideHeader();
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _ProfileEditModal(
        isLight: isLight,
        userData: userData,
        onProfileUpdated: (updatedData) {
          setState(() {
            // Update only personal info, keep vehicle data separate
            userData?['firstName'] = updatedData['firstName'];
            userData?['lastName'] = updatedData['lastName'];
            userData?['email'] = updatedData['email'];
            userData?['phone'] = updatedData['phone'];
            userData?['dateOfBirth'] = updatedData['dateOfBirth'];
            userData?['address'] = updatedData['address'];
          });
          _updateProfileInDatabase(updatedData);
        },
      ),
    ).whenComplete(_showHeader);
  }

  void _showVehicleManagementModal(BuildContext context, bool isLight) {
    // Set bottom sheet state to hide dock/tabbar
    print('🚗 VEHICLE MODAL: Setting bottomSheetOpenNotifier to TRUE');
    bottomSheetOpenNotifier.value = true;
    isOpeningVehicleSubModal = false; // Reset flag

    _hideHeader();
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _VehicleManagementModal(
        isLight: isLight,
        userData: userData,
        onVehicleUpdated: (vehicleData) {
          // Only update local state - actual database save is handled by _saveVehicleToDatabase in the modal
          setState(() {
            userData?['vehicle'] = vehicleData;
          });
          // Note: Don't call _updateVehicleInDatabase here - it's already saved by _VehicleManagementModal._saveVehicleToDatabase
        },
      ),
    ).whenComplete(() {
      // Only reset if not opening a sub-modal
      if (!isOpeningVehicleSubModal) {
        print(
          '🚗 VEHICLE MODAL: Setting bottomSheetOpenNotifier to FALSE (closing)',
        );
        bottomSheetOpenNotifier.value = false;
        _showHeader();
      } else {
        print(
          '🚗 VEHICLE MODAL: Sub-modal flag detected, keeping notifier TRUE',
        );
      }
    });
  }

  Future<void> _updateProfileInDatabase(
    Map<String, dynamic> profileData,
  ) async {
    try {
      if (userData == null) return;

      // Must be username or email – the backend searches WHERE username = ? OR email = ?
      final userId =
          userData!['username'] ?? userData!['email'] ??
          userData!['user_id'] ?? userData!['userId'] ?? userData!['id'];

      if (userId == null) {
        print('❌ No user ID found for profile update');
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.errorNoUserIdFound ?? AppLocalizations.of(context)!.tr('Error: No user ID found'),
        );
        return;
      }

      print('💾 Updating profile for user: $userId');
      print('📋 Profile data: $profileData');

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/update-profile'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'firstName': profileData['firstName'],
          'lastName': profileData['lastName'],
          'email': profileData['email'],
          'phone': profileData['phone'],
          'dateOfBirth': profileData['dateOfBirth'],
          'address': profileData['address'],
          'front_id_image_url': profileData['front_id_image_url'],
          'back_id_image_url': profileData['back_id_image_url'],
          'license_front_image_url': profileData['license_front_image_url'],
          'license_back_image_url': profileData['license_back_image_url'],
        }),
      );

      print('📡 Profile update response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // Update userData with response data including ID photo URLs
        if (responseData['success'] == true && responseData['data'] != null) {
          setState(() {
            userData = {
              ...?userData,
              'firstName': responseData['data']['firstName'],
              'lastName': responseData['data']['lastName'],
              'email': responseData['data']['email'],
              'phone': responseData['data']['phone'],
              'dateOfBirth': responseData['data']['dateOfBirth'],
              'address': responseData['data']['address'],
              'front_id_image_url': responseData['data']['front_id_image_url'],
              'back_id_image_url': responseData['data']['back_id_image_url'],
              'license_front_image_url':
                  responseData['data']['license_front_image_url'],
              'license_back_image_url':
                  responseData['data']['license_back_image_url'],
            };
          });
          print('📸 Updated userData with ID photos:');
          print('  Front ID: ${userData!['front_id_image_url']}');
          print('  Back ID: ${userData!['back_id_image_url']}');
          print('🪪 Updated userData with License photos:');
          print('  Front License: ${userData!['license_front_image_url']}');
          print('  Back License: ${userData!['license_back_image_url']}');
        }

        print('✅ Profile updated successfully in database');
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.profileUpdatedSuccessfully ?? AppLocalizations.of(context)!.tr('Profile updated successfully!'),
        );
      } else {
        print('❌ Failed to update profile: ${response.statusCode}');
        print('📋 Error response: ${response.body}');
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToUpdateProfile ?? AppLocalizations.of(context)!.tr('Failed to update profile in database'),
        );
      }
    } catch (e) {
      print('❌ Error updating profile: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorUpdatingProfile ?? AppLocalizations.of(context)!.tr('Error updating profile')}: $e',
      );
    }
  }

  Future<void> _updateVehicleInDatabase(
    Map<String, dynamic> vehicleData,
  ) async {
    try {
      if (userData == null) return;

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/vehicle'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userData!['userId'] ?? userData!['id'],
          'vehicleData': vehicleData,
        }),
      );

      if (response.statusCode == 200) {
        print('Vehicle updated successfully in database');
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.vehicleUpdatedSuccessfully ?? AppLocalizations.of(context)!.tr('Vehicle updated successfully!'),
        );
      } else {
        print('Failed to update vehicle: ${response.statusCode}');
        TopNotification.warning(
          context,
          AppLocalizations.of(context)?.vehicleUpdatedLocally ?? AppLocalizations.of(context)!.tr('Vehicle updated locally'),
        );
      }
    } catch (e) {
      print('Error updating vehicle: $e');
      TopNotification.warning(
        context,
        AppLocalizations.of(context)?.vehicleUpdatedLocally ?? AppLocalizations.of(context)!.tr('Vehicle updated locally'),
      );
    }
  }

  void _showSettingsModal(BuildContext context, bool isLight) {
    // Set bottom sheet state to hide dock/tabbar
    bottomSheetOpenNotifier.value = true;

    _hideHeader();
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _AccountSettingsModal(
        isLight: isLight,
        userData: userData,
        onSettingsUpdated: (settings) {
          _updateAccountSettingsInDatabase(settings);
        },
      ),
    ).whenComplete(() {
      // Reset bottom sheet state when modal closes
      bottomSheetOpenNotifier.value = false;
      _showHeader();
    });
  }

  Future<void> _updateAccountSettingsInDatabase(
    Map<String, dynamic> settings,
  ) async {
    try {
      if (userData == null) return;

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/account-settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userData!['id'], 'settings': settings}),
      );

      if (response.statusCode == 200) {
        print('Account settings updated successfully in database');
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.settingsUpdatedSuccessfully ?? AppLocalizations.of(context)!.tr('Settings updated successfully!'),
        );
      } else {
        print('Failed to update settings: ${response.statusCode}');
        TopNotification.warning(
          context,
          AppLocalizations.of(context)?.settingsUpdatedLocally ?? AppLocalizations.of(context)!.tr('Settings updated locally'),
        );
      }
    } catch (e) {
      print('Error updating settings: $e');
      TopNotification.warning(
        context,
        AppLocalizations.of(context)?.settingsUpdatedLocally ?? AppLocalizations.of(context)!.tr('Settings updated locally'),
      );
    }
  }

  void _showProfileImageModal(
    BuildContext context,
    bool isLight,
    Function(String) onImageSelected,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _ProfileImageUploadModal(
        isLight: isLight,
        userData: userData,
        onImageUploaded: (String imageUrl) {
          onImageSelected(imageUrl);
          setState(() {
            userData?['profileImage'] = imageUrl;
          });
        },
      ),
    );
  }

  void _showLeaveGroupConfirmation(BuildContext context, bool isLight) {
    if (userGroups.isEmpty) return;

    final group = userGroups.first; // User can only be in one group
    final isHost = group['isHost'] ?? false;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.trash,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isHost
                      ? (AppLocalizations.of(context)?.deleteGroup ?? AppLocalizations.of(context)!.tr(''))
                      : AppLocalizations.of(context)?.leaveGroup ?? AppLocalizations.of(context)!.tr('Leave Group'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Description
          Text(
            isHost
              ? '${AppLocalizations.of(context)?.deleteGroupDesc ?? AppLocalizations.of(context)!.tr('')} (${group['name']}, ${group['memberCount'] ?? 1})'
              : (AppLocalizations.of(context)?.rejoinGroupLater ?? AppLocalizations.of(context)!.tr('')),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
            ),
          ),

          const SizedBox(height: 32),

          // Primary action button
          TradeRepublicButton(
            label: isHost
              ? (AppLocalizations.of(context)?.deleteGroup ?? AppLocalizations.of(context)!.tr(''))
                : AppLocalizations.of(context)?.leaveGroup ?? AppLocalizations.of(context)!.tr('Leave Group'),
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(context);
              _leaveCurrentGroup();
            },
            isDestructive: true,
            width: double.infinity,
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Secondary cancel button
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            onPressed: () => Navigator.pop(context),
            isSecondary: true,
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  Future<void> _leaveCurrentGroup() async {
    if (userGroups.isEmpty) return;

    try {
      final group = userGroups.first;
      final groupId = group['group_id'] ?? group['groupId'] ?? group['id'];

      if (groupId == null) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.groupIdNotFound ?? AppLocalizations.of(context)!.tr('Group ID not found'),
        );
        return;
      }

      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      print('🚪 Leaving group: $groupId');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo-groups/delvioo/leave'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'groupId': groupId,
          'userId':
              userData?['user_id'] ?? userData?['userId'] ?? userData?['id'],
        }),
      );

      print('📡 Leave group response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        // Refresh groups list
        await _loadUserGroups();

        TopNotification.success(
          context,
          '${AppLocalizations.of(context)?.successfullyLeftGroup ?? AppLocalizations.of(context)!.tr('Successfully left the group')}!',
          title: AppLocalizations.of(context)?.groupLeft ?? AppLocalizations.of(context)!.tr('Group Left'),
        );
      } else {
        final errorData = json.decode(response.body);
        TopNotification.error(
          context,
          errorData['error'] ?? (AppLocalizations.of(context)?.failedToLeaveGroup ?? AppLocalizations.of(context)!.tr('')),
          title: AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error'),
        );
      }
    } catch (e) {
      print('❌ Error leaving group: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorLeavingGroup ?? AppLocalizations.of(context)!.tr('Error leaving group')}: $e',
        title: AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error'),
      );
    }
  }

  void _showGroupChatModal(
    BuildContext context,
    Map<String, dynamic> group,
    bool isLight,
  ) {
    final TextEditingController messageController = TextEditingController();
    final ScrollController scrollController = ScrollController();
    final groupId = group['groupId'] ?? AppLocalizations.of(context)!.tr('');
    final groupName =
        group['name'] ??
        AppLocalizations.of(context)?.unnamedGroup ?? AppLocalizations.of(context)!.tr('Unnamed Group');
    final memberCount = group['memberCount'] ?? group['members']?.length ?? 0;
    final List<Map<String, dynamic>> messages = [];
    bool isLoadingMessages = true;

    // Format timestamp helper
    String formatMessageTime(String? timestamp) {
      if (timestamp == null) return '';
      try {
        final dt = DateTime.parse(timestamp);
        final now = DateTime.now();
        final diff = now.difference(dt);

        if (diff.inMinutes < 1) return 'now';
        if (diff.inMinutes < 60) return '${diff.inMinutes}m';
        if (diff.inHours < 24) return '${diff.inHours}h';
        if (diff.inDays < 7) return '${diff.inDays}d';
        return '${dt.day}.${dt.month}';
      } catch (e) {
        return '';
      }
    }

    // Load messages from database
    Future<void> loadMessages() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');

        final response = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/group-messages/$groupId'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final loadedMessages = List<Map<String, dynamic>>.from(
            data['messages'] ?? [],
          );
          final currentUserId = userData?['userId'] ?? userData?['id'];

          messages.clear();
          for (var msg in loadedMessages) {
            messages.add({
              'text': msg['message_text'],
              'isMe': msg['sender_id'] == currentUserId,
              'sender': msg['sender_name'] ?? (AppLocalizations.of(context)?.userFallback ?? AppLocalizations.of(context)!.tr('')),
              'timestamp': msg['created_at'],
            });
          }

          print('✅ Loaded ${messages.length} messages from database');
        } else {
          print('❌ Failed to load messages: ${response.statusCode}');
        }
      } catch (e) {
        print('❌ Error loading messages: $e');
      }
      isLoadingMessages = false;
    }

    // Hide TradeRepublicButtons when group chat modal opens
    bottomSheetOpenNotifier.value = true;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          // Load messages when modal opens
          if (isLoadingMessages) {
            loadMessages().then((_) {
              if (context.mounted) {
                setModalState(() {});
                // Scroll to bottom after messages load
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (scrollController.hasClients) {
                    scrollController.animateTo(
                      scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.92,
              child: Column(
                children: [
                  // Minimalist Header - Large Title
                  Container(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                    child: Row(
                      children: [
                        // Group avatar - black/white
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isLight ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Center(
                            child: Icon(
                              CupertinoIcons.group,
                              color: isLight ? Colors.white : Colors.black,
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Group info - Large text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                groupName,
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                                  fontWeight: FontWeight.w700,
                                  color: isLight ? Colors.black : Colors.white,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$memberCount members',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isLight
                                      ? Colors.black.withOpacity(0.5)
                                      : Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Settings button - Trade Republic Style
                        TradeRepublicButton.icon(
                          icon: Icon(
                            CupertinoIcons.settings,
                            color: isLight ? Colors.black : Colors.white,
                            size: 22,
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(context);
                            _showGroupSettingsModal(context, group, isLight);
                          },
                          isSecondary: true,
                        ),
                      ],
                    ),
                  ),

                  // Messages Area - Clean background
                  Expanded(
                    child: Container(
                      color: isLight ? Colors.white : Colors.black,
                      child: isLoadingMessages
                          ? Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CultiooLoadingIndicator(size: 20),
                              ),
                            )
                          : messages.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Minimalist icon
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: isLight
                                          ? Colors.black.withOpacity(0.05)
                                          : Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                    ),
                                    child: Icon(
                                      CupertinoIcons.chat_bubble,
                                      size: 36,
                                      color: isLight
                                          ? Colors.black.withOpacity(0.4)
                                          : Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                                  Text(
                                    AppLocalizations.of(
                                          context,
                                        )?.noMessagesYet ?? AppLocalizations.of(context)!.tr('No Messages Yet'),
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                                      fontWeight: FontWeight.w700,
                                      color: isLight
                                          ? Colors.black
                                          : Colors.white,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                  Text(
                                    AppLocalizations.of(
                                          context,
                                        )?.sendFirstMessage ?? AppLocalizations.of(context)!.tr('Send the first message to\\\\nstart the conversation'),
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                      color: isLight
                                          ? Colors.black.withOpacity(0.5)
                                          : Colors.white.withOpacity(0.5),
                                      height: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                16,
                              ),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final message = messages[index];
                                final isMe = message['isMe'] ?? true;
                                final showAvatar =
                                    !isMe &&
                                    (index == 0 ||
                                        messages[index - 1]['isMe'] != isMe ||
                                        messages[index - 1]['sender'] !=
                                            message['sender']);
                                final isLastInGroup =
                                    index == messages.length - 1 ||
                                    messages[index + 1]['isMe'] != isMe ||
                                    messages[index + 1]['sender'] !=
                                        message['sender'];

                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: isLastInGroup ? 12 : 3,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: isMe
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      // Avatar for others
                                      if (!isMe) ...[
                                        SizedBox(
                                          width: 32,
                                          child: showAvatar
                                              ? Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: isLight
                                                        ? Colors.black
                                                        : Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      (message['sender'] ?? AppLocalizations.of(context)!.tr('U'))[0]
                                                          .toUpperCase(),
                                                      style: TextStyle(
                                                        color: isLight
                                                            ? Colors.white
                                                            : Colors.black,
                                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                      ],

                                      // Message bubble
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: isMe
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            // Sender name for group messages
                                            if (!isMe && showAvatar)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 14,
                                                  bottom: 4,
                                                ),
                                                child: Text(
                                                  message['sender'] ??
                                                      (AppLocalizations.of(context)?.userFallback ?? AppLocalizations.of(context)!.tr('')),
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: isLight
                                                        ? Colors.black
                                                              .withOpacity(0.5)
                                                        : Colors.white
                                                              .withOpacity(0.5),
                                                  ),
                                                ),
                                              ),

                                            // Message container - Black/White style
                                            Container(
                                              constraints: BoxConstraints(
                                                maxWidth:
                                                    MediaQuery.of(
                                                      context,
                                                    ).size.width *
                                                    0.72,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isMe
                                                    ? (isLight
                                                          ? Colors.black
                                                          : Colors.white)
                                                    : (isLight
                                                          ? Colors.white
                                                          : Colors.black),
                                                borderRadius:
                                                    BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                              ),
                                              child: Text(
                                                message['text'] ?? AppLocalizations.of(context)!.tr(''),
                                                style: TextStyle(
                                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                                  color: isMe
                                                      ? (isLight
                                                            ? Colors.white
                                                            : Colors.black)
                                                      : (isLight
                                                            ? Colors.black
                                                            : Colors.white),
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),

                                            // Timestamp for last message in group
                                            if (isLastInGroup)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top: 6,
                                                  left: isMe ? 0 : 14,
                                                  right: isMe ? 14 : 0,
                                                ),
                                                child: Text(
                                                  formatMessageTime(
                                                    message['timestamp'],
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: isLight
                                                        ? Colors.black
                                                              .withOpacity(0.4)
                                                        : Colors.white
                                                              .withOpacity(0.4),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),

                                      // Spacer for own messages
                                      if (isMe) const SizedBox(width: 36),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),

                  // Minimalist Input Bar - Send button inside input
                  Container(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(context).padding.bottom + 12,
                    ),
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white : Colors.black,
                    ),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 48,
                        maxHeight: 120,
                      ),
                      padding: DesktopAppWrapper.getPagePadding(),
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.black.withOpacity(0.05)
                            : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Text input
                          Expanded(
                            child: TradeRepublicTextField(
                              controller: messageController,
                              filled: false,
                              hintText:
                                  AppLocalizations.of(context)?.message ?? AppLocalizations.of(context)!.tr('Message'),
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                              ),
                              maxLines: 5,
                              minLines: 1,
                              textCapitalization: TextCapitalization.sentences,
                            ),
                          ),

                          // Send button - Trade Republic Style
                          Padding(
                            padding: const EdgeInsets.only(
                              right: 6,
                              top: 6,
                              bottom: 6,
                            ),
                            child: TradeRepublicTap(
                              onTap: () async {
                                if (messageController.text.trim().isNotEmpty) {
                                  final messageText = messageController.text
                                      .trim();
                                  final userId =
                                      userData?['userId'] ?? userData?['id'];
                                  final senderName =
                                      userData?['firstName'] ??
                                      AppLocalizations.of(context)?.youLabel ?? AppLocalizations.of(context)!.tr('You');

                                  // Optimistically add message to UI
                                  setModalState(() {
                                    messages.add({
                                      'text': messageText,
                                      'isMe': true,
                                      'sender': senderName,
                                      'timestamp': DateTime.now().toString(),
                                    });
                                  });
                                  messageController.clear();

                                  // Scroll to bottom
                                  Future.delayed(
                                    const Duration(milliseconds: 50),
                                    () {
                                      if (scrollController.hasClients) {
                                        scrollController.animateTo(
                                          scrollController
                                              .position
                                              .maxScrollExtent,
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          curve: Curves.easeOut,
                                        );
                                      }
                                    },
                                  );

                                  // Send to backend
                                  try {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    final token = prefs.getString('auth_token');

                                    final response = await http.post(
                                      Uri.parse(
                                        '${ApiConfig.baseUrl}/api/group-messages/send',
                                      ),
                                      headers: {
                                        'Content-Type': 'application/json',
                                        if (token != null)
                                          'Authorization': 'Bearer $token',
                                      },
                                      body: json.encode({
                                        'groupId': groupId,
                                        'userId': userId,
                                        'message': messageText,
                                        'senderName': senderName,
                                      }),
                                    );

                                    if (response.statusCode != 200) {
                                      print(
                                        '❌ Failed to send message: ${response.body}',
                                      );
                                    } else {
                                      print('✅ Message sent successfully');
                                    }
                                  } catch (e) {
                                    print('❌ Error sending message: $e');
                                  }
                                }
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isLight ? Colors.black : Colors.white,
                                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                ),
                                child: Icon(
                                  CupertinoIcons.arrow_up,
                                  color: isLight ? Colors.white : Colors.black,
                                  size: 20,
                                ),
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
        },
      ),
    ).whenComplete(() {
      // Show TradeRepublicButtons again when modal closes
      bottomSheetOpenNotifier.value = false;
    });
  }

  Widget _buildAccountManagementSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.account ?? AppLocalizations.of(context)!.tr('Account'),
          padding: const EdgeInsets.only(bottom: 12, top: 28, left: 4),
        ),
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          backgroundColor: isLight ? Colors.white : Colors.black,
          child: Column(
            children: [
              TradeRepublicListTile.navigation(
                title: AppLocalizations.of(context)?.editProfile ?? AppLocalizations.of(context)!.tr('Edit Profile'),
                subtitle: AppLocalizations.of(context)?.updateYourPersonalInformation ?? AppLocalizations.of(context)!.tr('Update your personal information'),
                leading: const Icon(CupertinoIcons.pen, size: 18),
                onTap: () => _showProfileEditModal(context, isLight),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 56),
                child: TradeRepublicDivider(),
              ),
              TradeRepublicListTile.navigation(
                title: AppLocalizations.of(context)?.vehicleManagement ?? AppLocalizations.of(context)!.tr('Vehicle Management'),
                subtitle: AppLocalizations.of(context)?.manageYourVehiclesAndAddNewOnes ?? AppLocalizations.of(context)!.tr('Manage your vehicles and add new ones'),
                leading: const Icon(CupertinoIcons.car, size: 18),
                onTap: () => _showVehicleManagementModal(context, isLight),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 56),
                child: TradeRepublicDivider(),
              ),
              TradeRepublicListTile.navigation(
                title: AppLocalizations.of(context)?.accountSettings ?? AppLocalizations.of(context)!.tr('Account Settings'),
                subtitle: AppLocalizations.of(context)?.privacyAndSecuritySettings ?? AppLocalizations.of(context)!.tr('Privacy and security settings'),
                leading: const Icon(CupertinoIcons.settings, size: 18),
                onTap: () => _showSettingsModal(context, isLight),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppSettingsSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.settings ?? AppLocalizations.of(context)!.tr('Settings'),
          padding: const EdgeInsets.only(bottom: 12, top: 28, left: 4),
        ),
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          backgroundColor: isLight ? Colors.white : Colors.black,
          child: TradeRepublicListTile.navigation(
            title: AppLocalizations.of(context)?.appSettings ?? AppLocalizations.of(context)?.appSettingsSection ?? AppLocalizations.of(context)!.tr('App Settings'),
            subtitle: AppLocalizations.of(context)?.themeLanguageUnitsPreferences ?? AppLocalizations.of(context)!.tr('Theme, language, units & preferences'),
            leading: const Icon(CupertinoIcons.settings, size: 18),
            onTap: () => _showAppSettingsModal(context, isLight),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewsSection(bool isLight, AppSettings appSettings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.reviews ?? AppLocalizations.of(context)!.tr('Reviews'),
          padding: const EdgeInsets.only(bottom: 12, top: 28, left: 4),
        ),

        // Large Average Rating Display
        if (!isLoadingReviews && reviews.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),

            decoration: BoxDecoration(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              children: [
                Container(
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        averageRating.toStringAsFixed(1),
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (index) {
                          return Icon(
                            index < averageRating.round()
                                ? CupertinoIcons.star_fill
                                : CupertinoIcons.star,
                            color: Colors.amber,
                            size: 20,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.averageRating ?? AppLocalizations.of(context)!.tr('Average Rating'),
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${AppLocalizations.of(context)?.basedOnReviews ?? AppLocalizations.of(context)!.tr('Based on reviews')} (${reviews.length})',
                        style: TextStyle(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.6),
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Reviews Card in App Settings style
        _buildAccountOption(
          icon: CupertinoIcons.star_fill,
          title:
              AppLocalizations.of(context)?.customerReviews ?? AppLocalizations.of(context)!.tr('Customer Reviews'),
          subtitle: isLoadingReviews
              ? AppLocalizations.of(context)?.loading ?? AppLocalizations.of(context)!.tr('Loading...')
              : reviews.isEmpty
              ? AppLocalizations.of(context)?.noReviewsYet ?? AppLocalizations.of(context)!.tr('No reviews yet')
              : '${reviews.length} ${reviews.length == 1 ? 'review' : 'reviews'}',
          isLight: isLight,
          onTap: () {
            // Open reviews modal to show all reviews
            _showReviewsModal(context, isLight, appSettings);
          },
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  void _showReviewsModal(
    BuildContext context,
    bool isLight,
    AppSettings appSettings,
  ) {
    // Hide header when modal opens
    _hideHeader();

    // Set bottom sheet state to hide dock/tabbar
    bottomSheetOpenNotifier.value = true;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 1,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.customerReviews ?? AppLocalizations.of(context)!.tr('Customer Reviews'),
                      style: TextStyle(
                        fontSize: appSettings.getScaledFontSize(28),
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Reviews List
            Expanded(
              child: isLoadingReviews
                  ? const Center(child: CultiooLoadingIndicator())
                  : reviews.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.text_bubble,
                            size: 64,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.3),
                          ),
                          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          Text(
                            AppLocalizations.of(context)?.noReviewsYet ?? AppLocalizations.of(context)!.tr('No reviews yet'),
                            style: TextStyle(
                              fontSize: appSettings.getScaledFontSize(18),
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                          ),
                          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          Text(
                            AppLocalizations.of(
                                  context,
                                )?.customerReviewsWillAppearHere ??
                                AppLocalizations.of(
                                  context,
                                )?.customerReviewsWillAppearHere ?? AppLocalizations.of(context)!.tr('Customer reviews will appear here'),
                            style: TextStyle(
                              fontSize: appSettings.getScaledFontSize(14),
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: reviews.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: TradeRepublicTap(
                            onTap: () => _showReviewDetailModal(
                              context,
                              reviews[index],
                              isLight,
                              appSettings,
                            ),
                            child: _buildReviewCard(
                              reviews[index],
                              isLight,
                              appSettings,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      // Reset bottom sheet state when modal closes
      bottomSheetOpenNotifier.value = false;
      // Show header when modal closes
      _showHeader();
    });
  }

  Widget _buildReviewCard(
    Map<String, dynamic> review,
    bool isLight,
    AppSettings appSettings,
  ) {
    final rating = review['rating'] ?? 0;
    final comment = review['comment'] ?? AppLocalizations.of(context)!.tr('');
    final customerName =
        review['customer_name'] ??
        AppLocalizations.of(context)?.anonymousCustomer ?? AppLocalizations.of(context)!.tr('Anonymous');
    final createdAt = review['created_at'];

    String formattedDate = '';
    if (createdAt != null) {
      try {
        final date = DateTime.parse(createdAt);
        final now = DateTime.now();
        final difference = now.difference(date);

        if (difference.inDays == 0) {
          formattedDate = AppLocalizations.of(context)?.todayLabel ?? AppLocalizations.of(context)!.tr('Today');
        } else if (difference.inDays == 1) {
          formattedDate =
              AppLocalizations.of(context)?.yesterdayLabel ?? AppLocalizations.of(context)!.tr('Yesterday');
        } else if (difference.inDays < 7) {
          formattedDate = '${difference.inDays} days ago';
        } else if (difference.inDays < 30) {
          formattedDate = '${(difference.inDays / 7).floor()} weeks ago';
        } else {
          final appSettings = Provider.of<AppSettings>(context, listen: false);
          formattedDate = appSettings.formatDate(date);
        }
      } catch (e) {
        formattedDate = 'Unknown date';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.05,
                  ),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Icon(
                  CupertinoIcons.person_fill,
                  color: isLight ? Colors.black : Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: appSettings.getScaledFontSize(16),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        fontSize: appSettings.getScaledFontSize(13),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Icon(
                      index < rating
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      color: Colors.amber,
                      size: 20,
                    ),
                  );
                }),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              comment,
              style: TextStyle(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.8),
                fontSize: appSettings.getScaledFontSize(15),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showReviewDetailModal(
    BuildContext context,
    Map<String, dynamic> review,
    bool isLight,
    AppSettings appSettings,
  ) {
    final rating = review['rating'] ?? 0;
    final comment = review['comment'] ?? AppLocalizations.of(context)!.tr('');
    final customerName =
        review['customer_name'] ??
        AppLocalizations.of(context)?.anonymousCustomer ?? AppLocalizations.of(context)!.tr('Anonymous');
    final createdAt = review['created_at'];

    String formattedDate = '';
    if (createdAt != null) {
      try {
        final date = DateTime.parse(createdAt.toString());
        formattedDate = appSettings.formatDate(date);
      } catch (e) {
        formattedDate = '';
      }
    }

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.05),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Icon(
                            CupertinoIcons.text_bubble,
                            color: isLight ? Colors.black : Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)?.customerReview ??
                                    AppLocalizations.of(
                                      context,
                                    )?.customerReview ?? AppLocalizations.of(context)!.tr('Customer Review'),
                                style: TextStyle(
                                  color: isLight ? Colors.black : Colors.white,
                                  fontSize: appSettings.getScaledFontSize(20),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (formattedDate.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  formattedDate,
                                  style: TextStyle(
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.6),
                                    fontSize: appSettings.getScaledFontSize(14),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Rating
                    Container(
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.05),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            rating.toString(),
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Icon(
                                  index < rating
                                      ? CupertinoIcons.star_fill
                                      : CupertinoIcons.star,
                                  color: Colors.amber,
                                  size: 32,
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    // Customer
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Icon(
                            CupertinoIcons.person_fill,
                            color: isLight ? Colors.black : Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          customerName,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: appSettings.getScaledFontSize(16),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                      // Comment
                      Container(
                        padding: DesktopAppWrapper.getPagePadding(),
                        decoration: BoxDecoration(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.05),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.quote_bubble,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.4),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppLocalizations.of(context)?.review ??
                                      AppLocalizations.of(
                                        context,
                                      )?.reviewLabel ?? AppLocalizations.of(context)!.tr('Review'),
                                  style: TextStyle(
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.6),
                                    fontSize: appSettings.getScaledFontSize(13),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            Text(
                              comment,
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontSize: appSettings.getScaledFontSize(15),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAppSettingsModal(BuildContext parentContext, bool isLight) {
    _ensureSettingsLoaded();

    // Set bottom sheet state to hide dock/tabbar
    bottomSheetOpenNotifier.value = true;
    _hideHeader();

    TradeRepublicBottomSheet.show(
      context: parentContext,
      bottomPadding: 20.0,
      showDragHandle: true,
      child: Consumer<AppSettings>(
        builder: (consumerCtx, appSettings, _) {
          return StatefulBuilder(
            builder: (sbCtx, setLocalState) {
              return SizedBox(
                height: MediaQuery.of(context).size.height * 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Sheet header: Icon left + Title ──
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.settings,
                          size: 22,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)?.appSettings ?? AppLocalizations.of(context)!.tr('App Settings'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    Expanded(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Appearance Section
                            _settings_buildAppearanceSection(appSettings, isLight),
                            const TradeRepublicDivider(),

                            // Driver Settings
                            _settings_buildDriverSection(appSettings, isLight, setLocalState),
                            const TradeRepublicDivider(),

                            // Waiting Time Settings
                            _settings_buildWaitingTimeSection(appSettings, isLight, setLocalState),
                            const TradeRepublicDivider(),

                            // Navigation
                            _settings_buildNavigationSection(appSettings, isLight, setLocalState),
                            const TradeRepublicDivider(),

                            // Permissions
                            _settings_buildPermissionsSection(appSettings, isLight, setLocalState),
                            const TradeRepublicDivider(),

                            // Localization & Formats
                            _settings_buildLocalizationSection(appSettings, isLight),
                            const TradeRepublicDivider(),

                            // Units
                            _settings_buildUnitsSection(appSettings, isLight),
                            const TradeRepublicDivider(),

                            // Data Management
                            _settings_buildDataSection(appSettings, isLight),
                            const TradeRepublicDivider(),

                            // Legal & About
                            _settings_buildLegalAboutSection(appSettings, isLight),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ).whenComplete(() {
      // Reset bottom sheet state when modal closes
      bottomSheetOpenNotifier.value = false;
      _showHeader();
    });
  }

  // --- Delvioo Settings section helpers (Trade Republic style) ---

  Widget _settings_buildSectionHeader(String title, bool isLight) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _settings_buildAppearanceSection(
    AppSettings appSettings,
    bool isLight,
  ) {
    // Map internal English keys to localized display names
    final themeOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'Light': AppLocalizations.of(context)?.light ?? AppLocalizations.of(context)!.tr('Light'),
      'Dark': AppLocalizations.of(context)?.dark ?? AppLocalizations.of(context)!.tr('Dark'),
    };
    final textSizeOptions = {
      'Small': AppLocalizations.of(context)?.small ?? AppLocalizations.of(context)!.tr('Small'),
      'Medium': AppLocalizations.of(context)?.medium ?? AppLocalizations.of(context)!.tr('Medium'),
      'Large': AppLocalizations.of(context)?.large ?? AppLocalizations.of(context)!.tr('Large'),
      'Extra Large': AppLocalizations.of(context)?.extraLargeLabel ?? AppLocalizations.of(context)!.tr('Extra Large'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings_buildSectionHeader(
          (AppLocalizations.of(context)?.appearance ?? AppLocalizations.of(context)!.tr('APPEARANCE')).toUpperCase(),
          isLight,
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.theme ?? AppLocalizations.of(context)!.tr('Theme'),
          subtitle: themeOptions[appSettings.selectedTheme] ?? appSettings.selectedTheme,
          leading: Icon(
            CupertinoIcons.paintbrush,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.theme ?? AppLocalizations.of(context)!.tr('Theme'),
            options: themeOptions,
            selectedKey: appSettings.selectedTheme,
            onSelect: (key) => appSettings.setSelectedTheme(key),
            isLight: isLight,
          ),
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.textSize ?? AppLocalizations.of(context)!.tr('Text Size'),
          subtitle: textSizeOptions[appSettings.delviooTextSize] ?? appSettings.delviooTextSize,
          leading: Icon(
            CupertinoIcons.textformat_size,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.textSize ?? AppLocalizations.of(context)!.tr('Text Size'),
            options: textSizeOptions,
            selectedKey: appSettings.delviooTextSize,
            onSelect: (key) => appSettings.setDelviooTextSize(key),
            isLight: isLight,
          ),
        ),
      ],
    );
  }

  Widget _settings_buildDriverSection(
    AppSettings appSettings,
    bool isLight,
    StateSetter setLocalState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings_buildSectionHeader(
          (AppLocalizations.of(context)?.driverSettings ?? AppLocalizations.of(context)!.tr('DRIVER SETTINGS')).toUpperCase(),
          isLight,
        ),
        TradeRepublicListTile.toggle(
          title: AppLocalizations.of(context)?.pushNotifications ?? AppLocalizations.of(context)!.tr('Push Notifications'),
          subtitle: _settingsNotificationsEnabled
              ? (AppLocalizations.of(context)?.enabled ?? AppLocalizations.of(context)!.tr('Enabled'))
              : (AppLocalizations.of(context)?.disabled ?? AppLocalizations.of(context)!.tr('Disabled')),
          leading: Icon(
            CupertinoIcons.bell,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          value: _settingsNotificationsEnabled,
          onChanged: (v) {
            setLocalState(() => _settingsNotificationsEnabled = v);
            _saveSettingPref('notificationsEnabled', v);
          },
        ),
        TradeRepublicListTile.toggle(
          title: AppLocalizations.of(context)?.locationSharing ?? AppLocalizations.of(context)!.tr('Location Sharing'),
          subtitle: _settingsLocationSharing
              ? (AppLocalizations.of(context)?.enabled ?? AppLocalizations.of(context)!.tr('Enabled'))
              : (AppLocalizations.of(context)?.disabled ?? AppLocalizations.of(context)!.tr('Disabled')),
          leading: Icon(
            CupertinoIcons.location_solid,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          value: _settingsLocationSharing,
          onChanged: (v) async {
            if (v) {
              await _settingsRequestLocationPermission();
              if (_settingsLocationPermissionGranted) {
                setLocalState(() => _settingsLocationSharing = v);
                _saveSettingPref('locationSharing', v);
              }
            } else {
              setLocalState(() => _settingsLocationSharing = v);
              _saveSettingPref('locationSharing', v);
            }
          },
        ),
        TradeRepublicListTile.toggle(
          title: AppLocalizations.of(context)?.autoAcceptOrders ?? AppLocalizations.of(context)!.tr('Auto Accept Orders'),
          subtitle: _settingsAutoAcceptOrders
              ? (AppLocalizations.of(context)?.enabled ?? AppLocalizations.of(context)!.tr('Enabled'))
              : (AppLocalizations.of(context)?.disabled ?? AppLocalizations.of(context)!.tr('Disabled')),
          leading: Icon(
            CupertinoIcons.checkmark_circle_fill,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          value: _settingsAutoAcceptOrders,
          onChanged: (v) {
            setLocalState(() => _settingsAutoAcceptOrders = v);
            _saveSettingPref('autoAcceptOrders', v);
          },
        ),
      ],
    );
  }

  Widget _settings_buildWaitingTimeSection(
    AppSettings appSettings,
    bool isLight,
    StateSetter setLocalState,
  ) {
    // Load settings from backend if not loaded
    if (!_waitingSettingsLoaded) {
      _loadWaitingTimeSettings();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings_buildSectionHeader(
          'WARTEZEIT',
          isLight,
        ),
        // Free waiting time
        TradeRepublicListTile(
          title: AppLocalizations.of(context)?.freeWaiting ?? AppLocalizations.of(context)!.tr('Free Waiting Time'),
          subtitle: '$_waitingFreeMinutes ${AppLocalizations.of(context)?.minutes ?? AppLocalizations.of(context)!.tr('minutes')}',
          leading: Icon(
            CupertinoIcons.clock,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          trailing: Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: isLight ? Colors.black38 : Colors.white38,
          ),
          onTap: () {
            _showWaitingTimeEditDialog(
              isLight,
              AppLocalizations.of(context)?.freeWaiting ?? AppLocalizations.of(context)!.tr('Free Waiting Time'),
              _waitingFreeMinutes.toString(),
              'min',
              (value) {
                final parsed = int.tryParse(value);
                if (parsed != null && parsed >= 0 && parsed <= 120) {
                  setLocalState(() => _waitingFreeMinutes = parsed);
                  setState(() {});
                  _saveWaitingTimeSettings();
                }
              },
            );
          },
        ),
        // Rate per hour
        TradeRepublicListTile(
          title: AppLocalizations.of(context)?.waitingCharges ?? AppLocalizations.of(context)!.tr('Hourly Rate'),
          subtitle:
              String.fromCharCode(8364) +
              _waitingRatePerHour.toStringAsFixed(2) +
              String.fromCharCode(47) +
              AppLocalizations.of(context)!.tr('h'),
          leading: Icon(
            CupertinoIcons.money_euro,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          trailing: Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: isLight ? Colors.black38 : Colors.white38,
          ),
          onTap: () {
            _showWaitingTimeEditDialog(
              isLight,
              AppLocalizations.of(context)?.waitingCharges ?? AppLocalizations.of(context)!.tr('Hourly Rate'),
              _waitingRatePerHour.toStringAsFixed(2),
              '${AppSettings().currencySymbol}/h',
              (value) {
                final parsed = double.tryParse(value);
                if (parsed != null && parsed >= 0 && parsed <= 500) {
                  setLocalState(() => _waitingRatePerHour = parsed);
                  setState(() {});
                  _saveWaitingTimeSettings();
                }
              },
            );
          },
        ),
        // Info text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            AppLocalizations.of(context)?.waitingTimeInfoDriver ?? AppLocalizations.of(context)!.tr('After the free waiting time expires, the hourly rate will be charged. The timer starts when you tap "Arrived" and stops when the QR code is scanned.'),
            style: TextStyle(
              fontSize: 12,
              color: isLight ? Colors.black45 : Colors.white.withOpacity(0.45),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  void _showWaitingTimeEditDialog(
    bool isLight,
    String title,
    String currentValue,
    String suffix,
    Function(String) onSave,
  ) {
    final controller = TextEditingController(text: currentValue);

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.pencil,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TradeRepublicTextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -1,
                ),
                  suffixText: suffix,
                  suffixStyle: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                    fontWeight: FontWeight.w500,
                    color: isLight ? Colors.black38 : Colors.white38,
                  ),
                filled: false,
              ),
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TradeRepublicButton(
                label: AppLocalizations.of(context)?.save ?? AppLocalizations.of(context)!.tr('Save'),
                onPressed: () {
                  onSave(controller.text.trim());
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _settings_buildNavigationSection(
    AppSettings appSettings,
    bool isLight,
    StateSetter setLocalState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings_buildSectionHeader(
          (AppLocalizations.of(context)?.navigation ?? AppLocalizations.of(context)!.tr('NAVIGATION')).toUpperCase(),
          isLight,
        ),
        TradeRepublicListTile.toggle(
          title: AppLocalizations.of(context)?.motionDock ?? AppLocalizations.of(context)!.tr('Motion Dock'),
          subtitle: _settingsShowDock
              ? (AppLocalizations.of(context)?.enabled ?? AppLocalizations.of(context)!.tr('Enabled'))
              : (AppLocalizations.of(context)?.disabled ?? AppLocalizations.of(context)!.tr('Disabled')),
          leading: Icon(
            CupertinoIcons.square_grid_2x2,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          value: _settingsShowDock,
          onChanged: (v) {
            setLocalState(() {
              _settingsShowDock = v;
              hideDockNotifier.value = !v;
            });
            _saveSettingPref('showDock', v);
          },
        ),
      ],
    );
  }

  Widget _settings_buildPermissionsSection(
    AppSettings appSettings,
    bool isLight,
    StateSetter setLocalState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings_buildSectionHeader(
          (AppLocalizations.of(context)?.permissionsSection ?? AppLocalizations.of(context)!.tr('PERMISSIONS')).toUpperCase(),
          isLight,
        ),
        _settingsLocationPermissionGranted
          ? TradeRepublicListTile(
              title: AppLocalizations.of(context)?.gpsLocation ?? AppLocalizations.of(context)!.tr('GPS Location'),
              subtitle: AppLocalizations.of(context)?.accessGranted ?? AppLocalizations.of(context)!.tr('Access granted'),
              leading: Icon(
                CupertinoIcons.location_fill,
                size: 20,
                color: isLight ? Colors.black : Colors.white,
              ),
              trailing: Icon(
                CupertinoIcons.checkmark_circle_fill,
                size: 20,
                color: isLight ? Colors.black : Colors.white,
              ),
            )
          : TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)?.gpsLocation ?? AppLocalizations.of(context)!.tr('GPS Location'),
              subtitle: AppLocalizations.of(context)?.tapToEnableLocation ?? AppLocalizations.of(context)!.tr('Tap to enable location access'),
              leading: Icon(
                CupertinoIcons.location_fill,
                size: 20,
                color: isLight ? Colors.black : Colors.white,
              ),
              onTap: () {
                _settingsRequestLocationPermission().then((_) {
                  _settingsCheckLocationPermission();
                  setLocalState(() {});
                });
              },
            ),
      ],
    );
  }

  Widget _settings_buildLocalizationSection(
    AppSettings appSettings,
    bool isLight,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings_buildSectionHeader(
          (AppLocalizations.of(context)?.localization ?? AppLocalizations.of(context)!.tr('LOCALIZATION')).toUpperCase(),
          isLight,
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.language ?? AppLocalizations.of(context)!.tr('Language'),
          subtitle: appSettings.selectedLanguage == 'System'
              ? 'System (${appSettings.effectiveLanguage})'
              : appSettings.selectedLanguageDisplayName,
          leading: Icon(
            CupertinoIcons.globe,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () => _settings_showLanguageOptions(
            appSettings: appSettings,
            isLight: isLight,
          ),
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.numberFormat ?? AppLocalizations.of(context)!.tr('Number Format'),
          subtitle: appSettings.delviooNumberFormat == 'System'
              ? 'System (${appSettings.effectiveNumberFormat == '1,234.56' ? '1,234.56 US' : '1.234,56 EU'})'
              : appSettings.delviooNumberFormat == '1,234.56'
              ? '1,234.56 (US)'
              : '1.234,56 (EU)',
          leading: Icon(
            CupertinoIcons.tag,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.numberFormat ?? AppLocalizations.of(context)!.tr('Number Format'),
            options: {
              'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
              '1,234.56': '1,234.56 (US)',
              '1.234,56': '1.234,56 (EU)',
            },
            selectedKey: appSettings.delviooNumberFormat,
            onSelect: (key) => appSettings.setDelviooNumberFormat(key),
            isLight: isLight,
          ),
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.currency ?? AppLocalizations.of(context)!.tr('Currency'),
          subtitle: appSettings.delviooCurrency == 'System'
              ? 'System (${appSettings.effectiveCurrency})'
              : appSettings.delviooCurrency,
          leading: Icon(
            CupertinoIcons.money_dollar_circle,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.currency ?? AppLocalizations.of(context)!.tr('Currency'),
            options: {
              'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
              'Dollar': 'Dollar ({currencySymbol})',
              'Euro': 'Euro ({currencySymbol})',
              'Pound': 'Pound ({currencySymbol})',
              'Franc': 'Franc (CHF)',
            },
            selectedKey: appSettings.delviooCurrency,
            onSelect: (key) => appSettings.setDelviooCurrency(key),
            isLight: isLight,
          ),
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.dateFormat ?? AppLocalizations.of(context)!.tr('Date Format'),
          subtitle: appSettings.selectedDateFormat,
          leading: Icon(
            CupertinoIcons.calendar,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () => _settings_showOptions(
            parentContext: null,
            title: AppLocalizations.of(context)?.dateFormat ?? AppLocalizations.of(context)!.tr('Date Format'),
            options: [
              'dd.MM.yyyy',
              'dd/MM/yyyy',
              'MM/dd/yyyy',
              'yyyy-MM-dd',
            ],
            selected: appSettings.selectedDateFormat,
            onSelect: (opt) => appSettings.setSelectedDateFormat(opt),
            isLight: isLight,
          ),
        ),
      ],
    );
  }

  Widget _settings_buildUnitsSection(
    AppSettings appSettings,
    bool isLight,
  ) {
    final tempOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'Celsius': 'Celsius (°C)',
      'Fahrenheit': 'Fahrenheit (°F)',
    };
    final distOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'Miles': AppLocalizations.of(context)?.miles ?? AppLocalizations.of(context)!.tr('Miles (mi)'),
      'Kilometers': AppLocalizations.of(context)?.kilometers ?? AppLocalizations.of(context)!.tr('Kilometers (km)'),
    };
    final weightOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'Kilograms': AppLocalizations.of(context)?.kilogramsLabel ?? AppLocalizations.of(context)!.tr('Kilograms'),
      'Pounds': AppLocalizations.of(context)?.poundsLabel ?? AppLocalizations.of(context)!.tr('Pounds'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings_buildSectionHeader(
          (AppLocalizations.of(context)?.units ?? AppLocalizations.of(context)!.tr('UNITS')).toUpperCase(),
          isLight,
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.temperatureUnit ?? AppLocalizations.of(context)!.tr('Temperature'),
          subtitle: appSettings.delviooTemperatureUnit == 'System'
              ? 'System (${appSettings.effectiveTemperatureUnit == 'Celsius' ? 'Celsius' : 'Fahrenheit'})'
              : tempOptions[appSettings.delviooTemperatureUnit] ?? appSettings.delviooTemperatureUnit,
          leading: Icon(
            CupertinoIcons.thermometer,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.temperatureUnit ?? AppLocalizations.of(context)!.tr('Temperature'),
            options: tempOptions,
            selectedKey: appSettings.delviooTemperatureUnit,
            onSelect: (key) => appSettings.setDelviooTemperatureUnit(key),
            isLight: isLight,
          ),
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.distanceUnit ?? AppLocalizations.of(context)!.tr('Distance'),
          subtitle: appSettings.delviooDistanceUnit == 'System'
              ? 'System (${appSettings.effectiveDistanceUnit})'
              : distOptions[appSettings.delviooDistanceUnit] ?? appSettings.delviooDistanceUnit,
          leading: Icon(
            CupertinoIcons.map,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.distanceUnit ?? AppLocalizations.of(context)!.tr('Distance Unit'),
            options: distOptions,
            selectedKey: appSettings.delviooDistanceUnit,
            onSelect: (key) => appSettings.setDelviooDistanceUnit(key),
            isLight: isLight,
          ),
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.weightUnit ?? AppLocalizations.of(context)!.tr('Weight'),
          subtitle: appSettings.delviooWeightUnit == 'System'
              ? 'System (${appSettings.effectiveWeightUnit})'
              : weightOptions[appSettings.delviooWeightUnit] ?? appSettings.delviooWeightUnit,
          leading: Icon(
            CupertinoIcons.speedometer,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.weightUnit ?? AppLocalizations.of(context)!.tr('Weight Unit'),
            options: weightOptions,
            selectedKey: appSettings.delviooWeightUnit,
            onSelect: (key) => appSettings.setDelviooWeightUnit(key),
            isLight: isLight,
          ),
        ),
      ],
    );
  }

  Widget _settings_buildDataSection(
    AppSettings appSettings,
    bool isLight,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings_buildSectionHeader(
          (AppLocalizations.of(context)?.dataManagement ?? AppLocalizations.of(context)!.tr('DATA MANAGEMENT')).toUpperCase(),
          isLight,
        ),
        TradeRepublicListTile.destructive(
          title: AppLocalizations.of(context)?.clearNavigationData ?? AppLocalizations.of(context)!.tr('Clear Navigation Data'),
          subtitle: AppLocalizations.of(context)?.resetAllMultiOrderNavigationSessions ?? AppLocalizations.of(context)!.tr('Reset all multi-order navigation sessions'),
          leading: Icon(CupertinoIcons.trash, size: 20, color: Colors.red),
          onTap: () => _settingsClearNavigationData(context, isLight),
        ),
      ],
    );
  }

  Widget _settings_buildLegalAboutSection(
    AppSettings appSettings,
    bool isLight,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settings_buildSectionHeader(
          (AppLocalizations.of(context)?.legalAbout ?? AppLocalizations.of(context)!.tr('LEGAL & ABOUT')).toUpperCase(),
          isLight,
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.privacyPolicy ?? AppLocalizations.of(context)!.tr('Privacy Policy'),
          subtitle: AppLocalizations.of(context)?.howWeProtectYourData ?? AppLocalizations.of(context)!.tr('How we protect your data'),
          leading: Icon(
            CupertinoIcons.lock_shield,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () async {
            final url = Uri.parse(
              'https://cultioo.com/us/us_legal_app#delvioo_privacy',
            );
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.termsConditions ?? AppLocalizations.of(context)!.tr('Terms & Conditions'),
          subtitle: AppLocalizations.of(context)?.termsOfService ?? AppLocalizations.of(context)!.tr('Terms of service'),
          leading: Icon(
            CupertinoIcons.doc_text,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () async {
            final url = Uri.parse(
              'https://cultioo.com/us/us_legal_app#delvioo_terms',
            );
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
        ),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.generalHelp ?? AppLocalizations.of(context)!.tr('General Help'),
          subtitle: AppLocalizations.of(context)?.helpAndSupportForTheApp ?? AppLocalizations.of(context)!.tr('Help and support for the app'),
          leading: Icon(
            CupertinoIcons.question_circle,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
          onTap: () async {
            final url = Uri.parse('https://cultioo.com/us/us_help');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
        ),
        TradeRepublicListTile(
          title: AppLocalizations.of(context)?.appVersion ?? AppLocalizations.of(context)!.tr('App Version'),
          subtitle: AppLocalizations.of(context)!.tr('1.0.0') ?? AppLocalizations.of(context)!.tr('1.0.0'),
          leading: Icon(
            CupertinoIcons.info_circle,
            size: 20,
            color: isLight ? Colors.black : Colors.white,
          ),
        ),
      ],
    );
  }

  // Options modal that stores internal keys but displays localized names
  void _settings_showMappedOptions({
    required String title,
    required Map<String, String> options, // key (internal) → display name
    required String selectedKey,
    required Function(String) onSelect,
    required bool isLight,
  }) {
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.list_bullet,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          Column(
            children: options.entries.map((entry) {
              final key = entry.key;
              final displayName = entry.value;
              final isSelected = selectedKey == key;
              return TradeRepublicTap(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSelect(key);
                  Navigator.pop(context);
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isLight ? Colors.black : Colors.white)
                        : (isLight ? Colors.black : Colors.white).withOpacity(0.04),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? (isLight ? Colors.white : Colors.black)
                                    : (isLight ? Colors.black : Colors.white),
                              ),
                            ),
                            if (key == 'System')
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  AppLocalizations.of(context)?.followsDeviceSettings ?? AppLocalizations.of(context)!.tr('Follows device settings'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: isSelected
                                        ? (isLight ? Colors.white : Colors.black).withOpacity(0.6)
                                        : (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: isLight ? Colors.white : Colors.black,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            isSecondary: true,
            height: 50,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        ],
      ),
    );
  }

  // Small options modal used by settings rows
  void _settings_showOptions({
    BuildContext? parentContext,
    required String title,
    required List<String> options,
    required String selected,
    required Function(String) onSelect,
    required bool isLight,
  }) {
    final ctx = parentContext ?? context;

    TradeRepublicBottomSheet.show(
      context: ctx,
      bottomPadding: 20.0,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.list_bullet,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          Column(
            children: options.map((opt) {
              final isSelected = selected == opt;
              return TradeRepublicTap(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSelect(opt);
                  Navigator.pop(context);
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isLight ? Colors.black : Colors.white)
                        : (isLight ? Colors.black : Colors.white).withOpacity(0.04),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? (isLight ? Colors.white : Colors.black)
                                    : (isLight ? Colors.black : Colors.white),
                              ),
                            ),
                            if (opt == (AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System')))
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  AppLocalizations.of(context)?.followsDeviceSettings ?? AppLocalizations.of(context)!.tr('Follows device settings'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: isSelected
                                        ? (isLight ? Colors.white : Colors.black).withOpacity(0.6)
                                        : (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: isLight ? Colors.white : Colors.black,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            isSecondary: true,
            height: 50,
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        ],
      ),
    );
  }

  // Language selection modal with flags and regions
  void _settings_showLanguageOptions({
    required AppSettings appSettings,
    required bool isLight,
  }) {
    final northAmerica = AppLocales.all
        .where((l) => l.region == 'USA' || l.region == 'Canada' || l.region == 'México')
        .toList();
    final eu = AppLocales.all
        .where((l) =>
            l.region != 'USA' &&
            l.region != 'Canada' &&
            l.region != 'México' &&
            l.region != 'Россия')
        .toList();
    final russia = AppLocales.all.where((l) => l.region == 'Россия').toList();

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      showDragHandle: true,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.globe,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.language ?? AppLocalizations.of(context)!.tr('Language'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // System option
                    _settings_buildLanguageOptionTile(
                      flag: '🌐',
                      displayName: AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
                      region: appSettings.effectiveLanguage,
                      isSelected: appSettings.selectedLanguage == 'System',
                      isLight: isLight,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        appSettings.setSelectedLanguage('System');
                        Navigator.pop(context);
                      },
                    ),

                    const SizedBox(height: 20),

                    // North America
                    _settings_buildLanguageSectionHeader(
                      AppLocalizations.of(context)?.northAmerica ?? AppLocalizations.of(context)!.tr('NORTH AMERICA'),
                      isLight,
                    ),
                    ...northAmerica.map(
                      (locale) => _settings_buildLanguageOptionTile(
                        flag: locale.flag,
                        displayName: locale.displayName,
                        region: locale.region,
                        isSelected: appSettings.selectedLanguage == locale.code,
                        isLight: isLight,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          appSettings.setSelectedLanguage(locale.code);
                          Navigator.pop(context);
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Europe
                    _settings_buildLanguageSectionHeader(
                      AppLocalizations.of(context)?.europeanUnion ?? AppLocalizations.of(context)!.tr('EUROPEAN UNION'),
                      isLight,
                    ),
                    ...eu.map(
                      (locale) => _settings_buildLanguageOptionTile(
                        flag: locale.flag,
                        displayName: locale.displayName,
                        region: locale.region,
                        isSelected: appSettings.selectedLanguage == locale.code,
                        isLight: isLight,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          appSettings.setSelectedLanguage(locale.code);
                          Navigator.pop(context);
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Russia
                    _settings_buildLanguageSectionHeader(
                      AppLocalizations.of(context)?.russia ?? AppLocalizations.of(context)!.tr('RUSSIA'),
                      isLight,
                    ),
                    ...russia.map(
                      (locale) => _settings_buildLanguageOptionTile(
                        flag: locale.flag,
                        displayName: locale.displayName,
                        region: locale.region,
                        isSelected: appSettings.selectedLanguage == locale.code,
                        isLight: isLight,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          appSettings.setSelectedLanguage(locale.code);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              isSecondary: true,
              height: 50,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          ],
        ),
      ),
    );
  }

  Widget _settings_buildLanguageSectionHeader(String title, bool isLight) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _settings_buildLanguageOptionTile({
    required String flag,
    required String displayName,
    required String region,
    required bool isSelected,
    required bool isLight,
    required VoidCallback onTap,
  }) {
    return TradeRepublicTap(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : (isLight ? Colors.black : Colors.white).withOpacity(0.04),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 10,),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? (isLight ? Colors.white : Colors.black)
                          : (isLight ? Colors.black : Colors.white),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayName == (AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'))
                        ? (AppLocalizations.of(context)?.followsDeviceSettings ?? AppLocalizations.of(context)!.tr('Follows device settings'))
                        : region,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: isSelected
                          ? (isLight ? Colors.white : Colors.black).withOpacity(0.6)
                          : (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: isLight ? Colors.white : Colors.black,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  // Settings state variables & helpers
  bool _settingsNotificationsEnabled = true;
  bool _settingsLocationSharing = true;
  bool _settingsAutoAcceptOrders = false;
  bool _settingsShowDock = true;
  bool _settingsLocationPermissionGranted = false;
  bool _settingsLoaded = false;

  // Waiting time settings
  int _waitingFreeMinutes = 15;
  double _waitingRatePerHour = 25.0;
  bool _waitingSettingsLoaded = false;

  Future<void> _ensureSettingsLoaded() async {
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _settingsNotificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
        _settingsLocationSharing = prefs.getBool('locationSharing') ?? true;
        _settingsAutoAcceptOrders = prefs.getBool('autoAcceptOrders') ?? false;
        _settingsShowDock = prefs.getBool('showDock') ?? true;
        hideDockNotifier.value = !_settingsShowDock;
      });
    }
    _settingsCheckLocationPermission();
  }

  Future<void> _saveSettingPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _settingsCheckLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (mounted) {
        setState(() {
          _settingsLocationPermissionGranted =
              permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse;
        });
      }
    } catch (e) {
      print('❌ Error checking location permission: $e');
    }
  }

  Future<void> _settingsRequestLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => _settingsLocationPermissionGranted = false);
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        try {
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
          );
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _settingsLocationPermissionGranted =
              permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse;
        });
      }
    } catch (e) {
      print('❌ Error requesting location permission: $e');
    }
  }

  // Load waiting time settings from backend
  Future<void> _loadWaitingTimeSettings() async {
    if (_waitingSettingsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? prefs.getString('driverId') ?? prefs.getString('userId') ?? AppLocalizations.of(context)!.tr('');
      if (driverId.isEmpty) return;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/driver/$driverId/waiting-settings'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _waitingFreeMinutes = data['waiting_free_minutes'] ?? 15;
            _waitingRatePerHour = (data['waiting_rate_per_hour'] ?? 25.0).toDouble();
            _waitingSettingsLoaded = true;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading waiting settings: $e');
    }
  }

  // Save waiting time settings to backend
  Future<void> _saveWaitingTimeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? prefs.getString('driverId') ?? prefs.getString('userId') ?? AppLocalizations.of(context)!.tr('');
      if (driverId.isEmpty) return;

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/driver/$driverId/waiting-settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'waiting_free_minutes': _waitingFreeMinutes,
          'waiting_rate_per_hour': _waitingRatePerHour,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Waiting settings saved: $_waitingFreeMinutes min, ${AppSettings().currencySymbol}$_waitingRatePerHour/hr');
      }
    } catch (e) {
      print('❌ Error saving waiting settings: $e');
    }
  }

  Future<void> _settingsClearNavigationData(BuildContext ctx, bool isLight) async {
    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: ctx,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.trash,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.clearNavDataQuestion ?? AppLocalizations.of(context)!.tr('Clear Navigation Data?'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          Text(
            AppLocalizations.of(context)?.deleteNavigationSessionsConfirm ?? AppLocalizations.of(context)!.tr('This will delete all saved multi-order navigation sessions. This action cannot be undone.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.clearNavigationData ?? AppLocalizations.of(context)!.tr('Clear Navigation Data'),
            isDestructive: true,
            width: double.infinity,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            isSecondary: true,
            width: double.infinity,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('multi_order_session_id');
      await prefs.remove('navigation_state');
      await prefs.remove('quick_navigation_state');

      final response = await http
          .delete(
            Uri.parse('${ApiConfig.baseUrl}/api/navigation/clear-all/1'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (ctx.mounted) {
        TopNotification.show(
          ctx,
          message: AppLocalizations.of(context)?.navigationDataClearedSuccessfully ?? AppLocalizations.of(context)!.tr(''),
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        TopNotification.show(
          ctx,
          message: AppLocalizations.of(context)?.errorClearingNavData ?? AppLocalizations.of(context)!.tr('Error clearing navigation data'),
          type: NotificationType.error,
        );
      }
    }
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon,
    bool isLight,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isLight ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isLight ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfoRow(
    String label,
    String value,
    IconData icon,
    bool isLight,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isLight ? Colors.black : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildMinimalInfoRow(String label, String value, bool isLight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              color: isLight ? Colors.black : Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
              color: isLight ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Trade Republic Style Stat Widget for Payment Settings
  Widget _buildMinimalPaymentStat(String label, String value, bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isLight ? Colors.black : Colors.white,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  void _showDeletePaymentConfirmation(BuildContext context, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.creditcard,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.removePaymentMethod ?? AppLocalizations.of(context)!.tr('Remove Payment Method'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            Text(
              AppLocalizations.of(context)?.removePaymentMethodConfirm ?? AppLocalizations.of(context)!.tr('Are you sure you want to remove this payment method? This action cannot be undone.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              ),
            ),

            const SizedBox(height: 32),

            // Remove button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.removePaymentMethod ?? AppLocalizations.of(context)!.tr('Remove Payment Method'),
              onPressed: () {
                Navigator.pop(context);
                _deletePaymentMethod();
              },
              isDestructive: true,
              width: double.infinity,
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () => Navigator.pop(context),
              isSecondary: true,
              width: double.infinity,
            ),
          ],
        ),
    );
  }

  Future<void> _deletePaymentMethod() async {
    try {
      if (userData == null) return;

      final userId =
          userData!['user_id'] ?? userData!['userId'] ?? userData!['id'];

      if (userId == null) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.userIdNotFound ?? AppLocalizations.of(context)!.tr('User ID not found'),
        );
        return;
      }

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/stripe-payment'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId}),
      );

      if (response.statusCode == 200) {
        setState(() {
          userData!['paymentInfo'] = null;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('delvioo_payout_account_verified', false);
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.tr('Payment method removed successfully!') ?? AppLocalizations.of(context)!.tr('Payment method removed successfully!'),
        );
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToRemovePaymentMethod ?? AppLocalizations.of(context)!.tr('Failed to remove payment method'),
        );
      }
    } catch (e) {
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorRemovingPaymentMethod ?? AppLocalizations.of(context)!.tr('Error removing payment method')}: $e',
      );
    }
  }

  // ─── Carbon Footprint / Mileage Tracker ───────────────────────────────────

  String? get _driverIdForMileage =>
      userData?['userId']?.toString() ??
      userData?['id']?.toString() ??
      userData?['username']?.toString();

  Future<void> _loadMileageEntries() async {
    // 1. Load from SharedPreferences immediately (instant UI)
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('delvioo_mileage_entries');
    if (raw != null) {
      try {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        final parsed = decoded.map<String, Map<String, double>>(
          (k, v) => MapEntry(k, {
            'startKm': (v['startKm'] as num).toDouble(),
            'endKm': (v['endKm'] as num).toDouble(),
          }),
        );
        if (mounted) setState(() => _mileageEntries = parsed);
      } catch (_) {}
    }

    // 2. Sync from backend (source of truth)
    final driverId = _driverIdForMileage;
    if (driverId == null || driverId.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/driver/$driverId/mileage'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final entries = (data['entries'] as List).cast<Map<String, dynamic>>();
          final parsed = <String, Map<String, double>>{};
          for (final e in entries) {
            parsed[e['month_key'] as String] = {
              'startKm': double.parse(e['start_km'].toString()),
              'endKm': double.parse(e['end_km'].toString()),
            };
          }
          if (mounted) setState(() => _mileageEntries = parsed);
          // Update local cache
          await prefs.setString('delvioo_mileage_entries', json.encode(
            parsed.map((k, v) => MapEntry(k, {'startKm': v['startKm'], 'endKm': v['endKm']})),
          ));
        }
      }
    } catch (e) {
      print('⚠️ Could not sync mileage from backend (using local cache): $e');
    }
  }

  Future<void> _saveMileageEntry(String monthKey, double startKm, double endKm) async {
    // Optimistic local update first
    setState(() {
      _mileageEntries[monthKey] = {'startKm': startKm, 'endKm': endKm};
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('delvioo_mileage_entries', json.encode(
      _mileageEntries.map((k, v) => MapEntry(k, {'startKm': v['startKm'], 'endKm': v['endKm']})),
    ));

    // Persist to backend
    final driverId = _driverIdForMileage;
    if (driverId == null || driverId.isEmpty) return;
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/driver/$driverId/mileage'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'monthKey': monthKey, 'startKm': startKm, 'endKm': endKm}),
      );
    } catch (e) {
      print('⚠️ Could not save mileage entry to backend: $e');
    }
  }

  Future<void> _deleteMileageEntry(String monthKey) async {
    // Optimistic local remove
    setState(() => _mileageEntries.remove(monthKey));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('delvioo_mileage_entries', json.encode(
      _mileageEntries.map((k, v) => MapEntry(k, {'startKm': v['startKm'], 'endKm': v['endKm']})),
    ));

    final driverId = _driverIdForMileage;
    if (driverId == null || driverId.isEmpty) return;
    try {
      await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/driver/$driverId/mileage/$monthKey'),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('⚠️ Could not delete mileage entry from backend: $e');
    }
  }

  /// CO2 kg for a given distance in km using average 8.5 L/100km, 2.31 kg CO2/L
  double _co2ForKm(double km) => (8.5 / 100) * km * 2.31;

  Widget _buildCarbonFootprintSection(bool isLight) {
    final loc = AppLocalizations.of(context);
    // Summarise all entered months
    double totalCo2Kg = 0;
    for (final entry in _mileageEntries.values) {
      final dist = (entry['endKm'] ?? 0) - (entry['startKm'] ?? 0);
      if (dist > 0) totalCo2Kg += _co2ForKm(dist);
    }
    final hasData = _mileageEntries.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0, top: 8.0, left: 4),
          child: Text(
            'Carbon Footprint',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: isLight ? Colors.black : Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        TradeRepublicListTile.navigation(
          title: hasData
              ? '${totalCo2Kg.toStringAsFixed(1)} kg CO₂'
              : (loc?.enterOdometerReading ?? AppLocalizations.of(context)!.tr('Record Mileage')),
          subtitle: hasData
              ? '${_mileageEntries.length} ${loc?.monthsEnteredCertAvail ?? AppLocalizations.of(context)!.tr('Month(s) entered · Certificate available')}'
              : (loc?.monthlyDataCo2Certificate ?? AppLocalizations.of(context)!.tr('Monthly consumption data & CO₂ certificate')),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
            ),
            child: const Icon(
              CupertinoIcons.leaf_arrow_circlepath,
              color: Color(0xFF10B981),
              size: 24,
            ),
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            _showCarbonFootprintModal(context, isLight);
          },
        ),
      ],
    );
  }

  void _showCarbonFootprintModal(BuildContext context, bool isLight) {
    _hideHeader();
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: _CarbonFootprintModal(
        isLight: isLight,
        mileageEntries: Map.from(_mileageEntries),
        co2ForKm: _co2ForKm,
        onSaveEntry: (monthKey, startKm, endKm) =>
            _saveMileageEntry(monthKey, startKm, endKm),
        onDeleteEntry: (monthKey) => _deleteMileageEntry(monthKey),
      ),
    ).whenComplete(_showHeader);
  }

  // ─── END Carbon Footprint ─────────────────────────────────────────────────

  Widget _buildAccountOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLight,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return TradeRepublicListTile.navigation(
      title: title,
      subtitle: subtitle,
      leading: Icon(
        icon,
        color: iconColor ?? (isLight ? Colors.black : Colors.white),
        size: 22,
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
    );
  }
}

// Verification Center Modal
class _VerificationCenterModal extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final bool isLight;

  const _VerificationCenterModal({
    required this.userData,
    required this.isLight,
  });

  @override
  State<_VerificationCenterModal> createState() =>
      _VerificationCenterModalState();
}

class _VerificationCenterModalState extends State<_VerificationCenterModal> {
  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final verification = widget.userData?['verification'] ?? {};
    final verificationScore = verification['score'] ?? 75;
    final verificationStatus =
        verification['status'] ??
        AppLocalizations.of(context)?.verified ?? AppLocalizations.of(context)!.tr('Verified');

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.shield,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.verificationCenter ?? AppLocalizations.of(context)!.tr('Verification Center'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Main Verification Card
                  Container(
                    width: double.infinity,
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: widget.isLight ? Colors.white : Colors.black,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Verification Score with circular progress
                        Row(
                          children: [
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: Stack(
                                children: [
                                  CultiooLoadingIndicator(size: 32),
                                  Center(
                                    child: Text(
                                      '$verificationScore',
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                                        fontWeight: FontWeight.w700,
                                        color: widget.isLight
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLocalizations.of(
                                          context,
                                        )?.verificationScore ??
                                        AppLocalizations.of(
                                          context,
                                        )?.verificationScore ?? AppLocalizations.of(context)!.tr('Verification Score'),
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                                      fontWeight: FontWeight.w700,
                                      color: widget.isLight
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '$verificationScore/100 Points',
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                      color:
                                          (widget.isLight
                                                  ? Colors.black
                                                  : Colors.white)
                                              .withOpacity(0.7),
                                    ),
                                  ),
                                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: verificationScore >= 80
                                          ? Colors.green.withOpacity(0.2)
                                          : verificationScore >= 60
                                          ? Colors.orange.withOpacity(0.2)
                                          : Colors.red.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                    ),
                                    child: Text(
                                      verificationStatus,
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        fontWeight: FontWeight.w600,
                                        color: verificationScore >= 80
                                            ? Colors.green
                                            : verificationScore >= 60
                                            ? Colors.orange
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                        const TradeRepublicDivider(),
                        const SizedBox(height: 20),

                        // Document Verification Status
                        Text(
                          AppLocalizations.of(context)?.documentVerification ??
                              AppLocalizations.of(
                                context,
                              )?.documentVerification ?? AppLocalizations.of(context)!.tr('Document Verification'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                        _buildVerificationItem(
                          AppLocalizations.of(context)?.identityDocument ?? AppLocalizations.of(context)!.tr('Identity Document'),
                          verification['idDocumentVerified'] == true,
                          AppLocalizations.of(context)?.frontAndBackVerified ?? AppLocalizations.of(context)!.tr('Front and back successfully verified'),
                          CupertinoIcons.creditcard,
                          widget.isLight,
                        ),
                        _buildVerificationItem(
                          'Driver\'s License',
                          verification['driverLicenseVerified'] ?? true,
                          AppLocalizations.of(context)?.validityConfirmed ?? AppLocalizations.of(context)!.tr('Validity and authorization confirmed'),
                          CupertinoIcons.car,
                          widget.isLight,
                        ),
                        _buildVerificationItem(
                          AppLocalizations.of(context)?.insuranceCertificate ?? AppLocalizations.of(context)!.tr('Insurance Certificate'),
                          verification['insuranceVerified'] ?? true,
                          AppLocalizations.of(
                                context,
                              )?.liabilityInsuranceVerified ?? AppLocalizations.of(context)!.tr('Liability insurance verified'),
                          CupertinoIcons.shield,
                          widget.isLight,
                        ),

                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                        const TradeRepublicDivider(),
                        const SizedBox(height: 20),

                        // Background Checks
                        Text(
                          AppLocalizations.of(context)?.backgroundChecks ??
                              AppLocalizations.of(context)?.backgroundChecks ?? AppLocalizations.of(context)!.tr('Background Checks'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                        _buildVerificationItem(
                          AppLocalizations.of(
                                context,
                              )?.criminalBackgroundCheck ?? AppLocalizations.of(context)!.tr('Criminal Background Check'),
                          verification['backgroundCheckPassed'] == true,
                          AppLocalizations.of(context)?.noCriminalRecords ?? AppLocalizations.of(context)!.tr('No criminal records or convictions'),
                          CupertinoIcons.checkmark_shield,
                          widget.isLight,
                        ),
                        _buildVerificationItem(
                          AppLocalizations.of(context)?.creditCheck ?? AppLocalizations.of(context)!.tr('Credit Check'),
                          verification['creditCheckPassed'] ?? true,
                          AppLocalizations.of(context)?.creditScoreVerified ?? AppLocalizations.of(context)!.tr('Credit score verified and approved'),
                          CupertinoIcons.building_2_fill,
                          widget.isLight,
                        ),
                        _buildVerificationItem(
                          AppLocalizations.of(context)?.employmentReferences ?? AppLocalizations.of(context)!.tr('Employment References'),
                          verification['referencesChecked'] ?? false,
                          AppLocalizations.of(context)?.workReferences ?? AppLocalizations.of(context)!.tr('Work references from previous employers'),
                          CupertinoIcons.group,
                          widget.isLight,
                        ),

                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                        const TradeRepublicDivider(),
                        const SizedBox(height: 20),

                        // Platform Compliance
                        Text(
                          AppLocalizations.of(context)?.platformCompliance ??
                              AppLocalizations.of(
                                context,
                              )?.platformCompliance ?? AppLocalizations.of(context)!.tr('Platform Compliance'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                        _buildVerificationItem(
                          AppLocalizations.of(
                                context,
                              )?.twoFactorAuthentication ?? AppLocalizations.of(context)!.tr('Two-Factor Authentication'),
                          verification['twoFactorEnabled'] ?? false,
                          AppLocalizations.of(
                                context,
                              )?.additionalSecurityLayerActivated ?? AppLocalizations.of(context)!.tr('Additional security layer activated'),
                          CupertinoIcons.shield,
                          widget.isLight,
                        ),
                        _buildVerificationItem(
                          AppLocalizations.of(context)?.biometricVerification ?? AppLocalizations.of(context)!.tr('Biometric Verification'),
                          verification['biometricEnabled'] ?? false,
                          AppLocalizations.of(
                                context,
                              )?.fingerprintOrFacialRecognition ?? AppLocalizations.of(context)!.tr('Fingerprint or facial recognition'),
                          CupertinoIcons.person_crop_circle,
                          widget.isLight,
                        ),
                        _buildVerificationItem(
                          AppLocalizations.of(context)?.phoneNumberVerified ?? AppLocalizations.of(context)!.tr('Phone Number Verified'),
                          verification['phoneVerified'] ?? true,
                          AppLocalizations.of(
                                context,
                              )?.smsVerificationSuccessful ?? AppLocalizations.of(context)!.tr('SMS verification successful'),
                          CupertinoIcons.phone,
                          widget.isLight,
                        ),
                        _buildVerificationItem(
                          AppLocalizations.of(context)?.emailVerified ?? AppLocalizations.of(context)!.tr('Email Verified'),
                          verification['emailVerified'] ?? true,
                          AppLocalizations.of(context)?.emailAddressConfirmed ?? AppLocalizations.of(context)!.tr('Email address confirmed'),
                          CupertinoIcons.mail,
                          widget.isLight,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Verification Timeline Card
                  Container(
                    width: double.infinity,
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: widget.isLight ? Colors.white : Colors.black,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.chart_bar,
                              color: widget.isLight
                                  ? Colors.black
                                  : Colors.white,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppLocalizations.of(
                                    context,
                                  )?.verificationTimeline ??
                                  AppLocalizations.of(
                                    context,
                                  )?.verificationTimeline ?? AppLocalizations.of(context)!.tr('Verification Timeline'),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                fontWeight: FontWeight.w700,
                                color: widget.isLight
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildTimelineItem(
                          AppLocalizations.of(context)?.accountCreated ?? AppLocalizations.of(context)!.tr('Account Created'),
                          verification['accountCreated']?.toString().split(
                                'T',
                              )[0] ?? AppLocalizations.of(context)!.tr('2024-01-15'),
                          CupertinoIcons.person_crop_circle,
                          widget.isLight ? Colors.black : Colors.white,
                          widget.isLight,
                        ),
                        _buildTimelineItem(
                          AppLocalizations.of(context)?.documentsUploaded ?? AppLocalizations.of(context)!.tr('Documents Uploaded'),
                          verification['documentsUploaded']?.toString().split(
                                'T',
                              )[0] ?? AppLocalizations.of(context)!.tr('2024-01-16'),
                          CupertinoIcons.arrow_up_doc,
                          widget.isLight ? Colors.black : Colors.white,
                          widget.isLight,
                        ),
                        _buildTimelineItem(
                          AppLocalizations.of(context)?.identityVerified ?? AppLocalizations.of(context)!.tr('Identity Verified'),
                          verification['identityVerified']?.toString().split(
                                'T',
                              )[0] ?? AppLocalizations.of(context)!.tr('2024-01-18'),
                          CupertinoIcons.checkmark_shield,
                          widget.isLight ? Colors.black : Colors.white,
                          widget.isLight,
                        ),
                        _buildTimelineItem(
                          AppLocalizations.of(context)?.licenseVerified ?? AppLocalizations.of(context)!.tr('License Verified'),
                          verification['licenseVerified']?.toString().split(
                                'T',
                              )[0] ?? AppLocalizations.of(context)!.tr('2024-01-19'),
                          CupertinoIcons.car,
                          widget.isLight ? Colors.black : Colors.white,
                          widget.isLight,
                        ),
                        _buildTimelineItem(
                          AppLocalizations.of(context)?.fullyVerified ?? AppLocalizations.of(context)!.tr('Fully Verified'),
                          verification['fullyVerified']?.toString().split(
                                'T',
                              )[0] ?? AppLocalizations.of(context)!.tr('2024-01-20'),
                          CupertinoIcons.checkmark_circle_fill,
                          widget.isLight ? Colors.black : Colors.white,
                          widget.isLight,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: widget.isLight ? Colors.white : Colors.black,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: TradeRepublicButton(
                            label:
                                AppLocalizations.of(context)?.viewDetails ?? AppLocalizations.of(context)!.tr('View Details'),
                            onPressed: () {
                              TopNotification.info(
                                context,
                                AppLocalizations.of(context)!.tr('Loading verification details...') ?? AppLocalizations.of(context)!.tr('Loading verification details...'),
                                title:
                                    AppLocalizations.of(context)?.details ?? AppLocalizations.of(context)!.tr('Details'),
                              );
                            },
                            tint: widget.isLight
                                ? CupertinoColors.black
                                : CupertinoColors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: widget.isLight ? Colors.white : Colors.black,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: TradeRepublicButton(
                            label:
                                AppLocalizations.of(context)?.refresh ?? AppLocalizations.of(context)!.tr('Refresh'),
                            onPressed: () {
                              TopNotification.success(
                                context,
                                AppLocalizations.of(context)!.tr('Verification status updated!') ?? AppLocalizations.of(context)!.tr('Verification status updated!'),
                                title:
                                    AppLocalizations.of(context)?.updated ?? AppLocalizations.of(context)!.tr('Updated'),
                              );
                            },
                            tint: widget.isLight
                                ? CupertinoColors.black
                                : CupertinoColors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationItem(
    String title,
    bool isVerified,
    String subtitle,
    IconData icon,
    bool isLight,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Icon(
              icon,
              color: isLight ? Colors.black : Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isVerified
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.clock,
            color: isLight ? Colors.black : Colors.white,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    String title,
    String date,
    IconData icon,
    Color color,
    bool isLight,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isLight ? Colors.black : Colors.white,
              ),
            ),
          ),
          Text(
            date,
            style: TextStyle(
              fontSize: 13,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// Create Group Modal
class _CreateGroupModal extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? userData;

  const _CreateGroupModal({required this.isLight, required this.userData});

  @override
  State<_CreateGroupModal> createState() => _CreateGroupModalState();
}

class _CreateGroupModalState extends State<_CreateGroupModal> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _joinCodeController = TextEditingController();
  String? _selectedGroupImage;
  File? _groupImageFile;
  bool _isGeneratingCode = false;
  bool _isUploadingImage = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Always generate a new random code when modal opens
    _generateRandomCode();
  }

  Future<void> _generateRandomCode() async {
    // Generate code immediately so UI is never stuck
    String code = DateTime.now().millisecondsSinceEpoch.toString();
    code = code.substring(code.length - 8);

    if (mounted) {
      setState(() {
        _isGeneratingCode = true;
        _joinCodeController.text = code;
      });
    }

    // Then validate uniqueness in background
    bool isUnique = false;
    int attempts = 0;
    const maxAttempts = 10;

    do {
      try {
        final response = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/delvioo-groups/check-code/$code'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          isUnique = responseData['available'] == true;
        } else {
          isUnique = true;
        }
      } catch (e) {
        print('❌ Error checking code uniqueness: $e');
        isUnique = true;
      }

      if (!isUnique) {
        attempts++;
        final newCode = (DateTime.now().millisecondsSinceEpoch + attempts).toString();
        code = newCode.substring(newCode.length - 8);
      }
    } while (!isUnique && attempts < maxAttempts);

    if (mounted) {
      setState(() {
        _isGeneratingCode = false;
        _joinCodeController.text = code;
      });
    }

    print('🎯 Generated unique code: $code (attempts: $attempts)');
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _pickGroupImage() async {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    try {
      // Show option: Camera or Gallery
      final source = await TradeRepublicBottomSheet.show<ImageSource>(
        context: context,
        showDragHandle: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.camera,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.chooseImageSource ?? AppLocalizations.of(context)!.tr('Choose Image Source'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: widget.isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            if (!Platform.isMacOS)
              _buildImageSourceOption(
                icon: CupertinoIcons.camera,
                title: AppLocalizations.of(context)?.camera ?? AppLocalizations.of(context)!.tr('Camera'),
                subtitle:
                    AppLocalizations.of(context)?.takeANewPhoto ?? AppLocalizations.of(context)!.tr('Take a new photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            if (!Platform.isMacOS) const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            _buildImageSourceOption(
              icon: CupertinoIcons.photo,
              title: AppLocalizations.of(context)?.gallery ?? AppLocalizations.of(context)!.tr('Gallery'),
              subtitle:
                  AppLocalizations.of(context)?.chooseFromYourPhotos ?? AppLocalizations.of(context)!.tr('Choose from your photos'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () => Navigator.pop(context),
              tint: widget.isLight
                  ? CupertinoColors.black
                  : CupertinoColors.white,
            ),
          ],
        ),
      );

      if (source == null) return;

      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _groupImageFile = File(pickedFile.path);
          _isUploadingImage = true;
        });

        // Upload to server
        await _uploadGroupImageToServer(File(pickedFile.path));
      }
    } catch (e) {
      print('❌ Error picking group image: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToPickImageTryAgain ?? AppLocalizations.of(context)!.tr('Failed to pick image. Please try again.'),
          title: AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error'),
        );
      }
    }
  }

  Future<void> _uploadGroupImageToServer(File imageFile) async {
    try {
      print('📸 Uploading group image...');

      final prefs = await SharedPreferences.getInstance();
      final userId =
          prefs.getString('user_id') ?? prefs.getString('username') ?? AppLocalizations.of(context)!.tr('');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/group-image'),
      );

      request.fields['userId'] = userId;
      request.files.add(
        await http.MultipartFile.fromPath(
          'groupImage',
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📡 Group image upload response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          setState(() {
            _selectedGroupImage = responseData['imageUrl'];
            _isUploadingImage = false;
          });
          print('✅ Group image uploaded: $_selectedGroupImage');
          if (mounted) {
            TopNotification.success(
              context,
              AppLocalizations.of(context)!.tr('Group image uploaded successfully!') ?? AppLocalizations.of(context)!.tr('Group image uploaded successfully!'),
              title: AppLocalizations.of(context)?.success ?? AppLocalizations.of(context)!.tr('Success'),
            );
          }
        }
      } else {
        setState(() {
          _isUploadingImage = false;
          _groupImageFile = null;
        });
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.failedToUploadGroupImage ?? AppLocalizations.of(context)!.tr('Failed to upload group image'),
            title: AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error'),
          );
        }
      }
    } catch (e) {
      print('❌ Error uploading group image: $e');
      setState(() {
        _isUploadingImage = false;
        _groupImageFile = null;
      });
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.networkErrorUploadingImage ?? AppLocalizations.of(context)!.tr('Network error while uploading image'),
          title: AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error'),
        );
      }
    }
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return TradeRepublicListTile.navigation(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon, size: 22),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14),
    );
  }

  Future<void> _createGroup() async {
    try {
      // Check if user is already in a group
      final accountPageState = context
          .findAncestorStateOfType<_DelviooAccountPageState>();
      if (accountPageState != null && accountPageState.userGroups.isNotEmpty) {
        TopNotification.info(
          context,
          AppLocalizations.of(context)?.onlyOneGroupLeaveFirst ?? AppLocalizations.of(context)!.tr('You can only be in one group at a time. Leave your current group first.'),
        );
        return;
      }

      // Get user ID with fallback logic
      String? currentUserId =
          widget.userData?['userId'] ??
          widget.userData?['id'] ??
          widget.userData?['user_id'];

      final userName =
          widget.userData?['fullName'] ??
          widget.userData?['firstName'] ??
          AppLocalizations.of(context)?.unknownUser ?? AppLocalizations.of(context)!.tr('Unknown User');

      print(
        '🎯 Creating group with userId: $currentUserId, userName: $userName',
      );

      // Create group data
      final groupData = {
        'name': _groupNameController.text.trim(),
        'joinCode': _joinCodeController.text,
        'hostName': userName,
        'hostUserId': currentUserId,
        'createdAt': DateTime.now().toIso8601String(),
        'groupImage': _selectedGroupImage,
        'memberCount': 1,
        'members': [
          {
            'userId': currentUserId,
            'userName': userName,
            'joinedAt': DateTime.now().toIso8601String(),
            'isHost': true,
          },
        ],
      };

      print('🎯 Creating group in Google Cloud: ${groupData['name']}');

      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo-groups/delvioo/create'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(groupData),
      );

      print('📡 Group creation response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final createdGroup = responseData['group'];
        final groupId = createdGroup?['groupId'];

        if (mounted) {
          Navigator.pop(context);

          // Set flag for messages page to open this group automatically
          if (groupId != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('new_group_to_open', groupId);
            print('✅ Set flag to open group: $groupId');
          }

          // Refresh groups list
          final accountPageState = context
              .findAncestorStateOfType<_DelviooAccountPageState>();
          accountPageState?._loadUserGroups();

          TopNotification.success(
            context,
            'Group "${_groupNameController.text}" created successfully! Opening chat...',
            title:
                AppLocalizations.of(context)?.groupCreated ?? AppLocalizations.of(context)!.tr('Group Created'),
          );
        }
      } else if (response.statusCode == 409) {
        // Code conflict - should be rare since we check uniqueness before
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.tr('Code conflict detected. Please generate a new code and try again.') ?? AppLocalizations.of(context)!.tr('Code conflict detected. Please generate a new code and try again.'),
            title:
                AppLocalizations.of(context)?.codeConflict ?? AppLocalizations.of(context)!.tr('Code Conflict'),
          );
          await _generateRandomCode();
        }
      } else {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.failedToCreateGroup ?? AppLocalizations.of(context)!.tr('Failed to create group. Please try again.'),
            title: AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error'),
          );
        }
      }
    } catch (e) {
      print('❌ Error creating group: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.networkErrorCheckConnection ?? AppLocalizations.of(context)!.tr('Network error. Please check your connection.'),
          title:
              AppLocalizations.of(context)?.connectionError ?? AppLocalizations.of(context)!.tr('Connection Error'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.isLight;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        // Group Image - centered, tappable
        TradeRepublicTap(
          onTap: _isUploadingImage ? null : _pickGroupImage,
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: (isLight ? Colors.black : Colors.white)
                  .withOpacity(0.06),
            ),
            child: _isUploadingImage
                ? const Center(child: CultiooLoadingIndicator(size: 24))
                : _groupImageFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.file(
                          _groupImageFile!,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      )
                    : _selectedGroupImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.network(
                              ApiConfig.getImageUrl(_selectedGroupImage!),
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  CupertinoIcons.person_2_fill,
                                  size: 36,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.25),
                                );
                              },
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.camera,
                                size: 28,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.3),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)?.addGroupPhoto ?? AppLocalizations.of(context)!.tr('Photo'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.3),
                                ),
                              ),
                            ],
                          ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Sheet header: Icon left + Title ──
        Row(
          children: [
            Icon(
              CupertinoIcons.person_2,
              size: 22,
              color: isLight ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.of(context)?.createGroup ?? AppLocalizations.of(context)!.tr('Create Group'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isLight ? Colors.black : Colors.white,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          AppLocalizations.of(context)?.createOrJoinGroupToGetStarted ?? AppLocalizations.of(context)!.tr('Create a delivery group with other drivers'),
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w400,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
          ),
        ),

        const SizedBox(height: 32),

        // Group Name Input
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                AppLocalizations.of(context)?.groupName ?? AppLocalizations.of(context)!.tr('Group Name'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: (isLight ? Colors.black : Colors.white)
                      .withOpacity(0.5),
                ),
              ),
            ),
            TradeRepublicTextField(
              controller: _groupNameController,
              hintText: AppLocalizations.of(context)?.enterGroupName ?? AppLocalizations.of(context)!.tr('Enter group name'),
              autofocus: true,
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w500,
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Join Code - read-only display with refresh
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                AppLocalizations.of(context)?.joinCode ?? AppLocalizations.of(context)!.tr('Join Code'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: (isLight ? Colors.black : Colors.white)
                      .withOpacity(0.5),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: (isLight ? Colors.black : Colors.white)
                    .withOpacity(0.05),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _joinCodeController.text.isEmpty
                          ? AppLocalizations.of(context)?.generatingLabel ?? AppLocalizations.of(context)!.tr('Generating...')
                          : _joinCodeController.text,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 22,
                        letterSpacing: 5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                  TradeRepublicButton.icon(
                    icon: _isGeneratingCode
                        ? const SizedBox(width: 18, height: 18, child: CultiooLoadingIndicator(size: 20))
                        : Icon(CupertinoIcons.arrow_clockwise, size: 18, color: (isLight ? Colors.black : Colors.white).withOpacity(0.5)),
                    size: 36,
                    backgroundColor: (isLight ? Colors.black : Colors.white).withOpacity(0.08),
                    onPressed: _isGeneratingCode ? null : () async {
                      HapticFeedback.lightImpact();
                      await _generateRandomCode();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Text(
                AppLocalizations.of(context)?.shareThisCodeWithOthersToJoin ?? AppLocalizations.of(context)!.tr('Share this code with others to join'),
                style: TextStyle(
                  fontSize: 12,
                  color: (isLight ? Colors.black : Colors.white)
                      .withOpacity(0.35),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // Create Button
        TradeRepublicButton(
          label: AppLocalizations.of(context)?.createGroup ?? AppLocalizations.of(context)!.tr('Create Group'),
          onPressed: (_groupNameController.text.trim().isNotEmpty &&
                  _joinCodeController.text.length == 8)
              ? () async {
                  await _createGroup();
                }
              : null,
          width: double.infinity,
        ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

        // Cancel link
        TradeRepublicButton(
          label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
          onPressed: () => Navigator.pop(context),
          isSecondary: true,
          width: double.infinity,
        ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        ],
      ),
    );
  }
}

// Join Group Modal
class _JoinGroupModal extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? userData;

  const _JoinGroupModal({required this.isLight, required this.userData});

  @override
  State<_JoinGroupModal> createState() => _JoinGroupModalState();
}

class _JoinGroupModalState extends State<_JoinGroupModal> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _joinGroup() async {
    try {
      // Check if user is already in a group
      final accountPageState = context
          .findAncestorStateOfType<_DelviooAccountPageState>();
      if (accountPageState != null && accountPageState.userGroups.isNotEmpty) {
        TopNotification.info(
          context,
          AppLocalizations.of(context)?.onlyOneGroupLeaveFirst ?? AppLocalizations.of(context)!.tr('You can only be in one group at a time. Leave your current group first.'),
        );
        return;
      }

      final currentUserId =
          widget.userData?['userId'] ?? widget.userData?['id'];
      final userName =
          widget.userData?['fullName'] ??
          widget.userData?['firstName'] ??
          AppLocalizations.of(context)?.unknownUser ?? AppLocalizations.of(context)!.tr('Unknown User');

      if (currentUserId == null) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.tr('User ID not available. Please reload the page.') ?? AppLocalizations.of(context)!.tr('User ID not available. Please reload the page.'),
          title: AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error'),
        );
        return;
      }

      // Join group data
      final joinData = {
        'joinCode': _searchController.text,
        'userId': currentUserId,
        'userName': userName,
        'joinedAt': DateTime.now().toIso8601String(),
      };

      print('🎯 Joining group with code: ${_searchController.text}');

      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo-groups/delvioo/join'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(joinData),
      );

      print('📡 Join group response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (mounted) {
          Navigator.pop(context);
          // Refresh groups list
          final accountPageState = context
              .findAncestorStateOfType<_DelviooAccountPageState>();
          accountPageState?._loadUserGroups();

          TopNotification.success(
            context,
            '${AppLocalizations.of(context)?.successfullyJoinedGroup ?? AppLocalizations.of(context)!.tr('Successfully joined group')} "${responseData['groupName']}"!',
            title: AppLocalizations.of(context)?.joinedGroup ?? AppLocalizations.of(context)!.tr('Joined Group'),
          );
        }
      } else if (response.statusCode == 404) {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.tr('Group not found. Please check the code.') ?? AppLocalizations.of(context)!.tr('Group not found. Please check the code.'),
            title: AppLocalizations.of(context)?.invalidCode ?? AppLocalizations.of(context)!.tr('Invalid Code'),
          );
        }
      } else if (response.statusCode == 409) {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.tr('You are already a member of this group.') ?? AppLocalizations.of(context)!.tr('You are already a member of this group.'),
            title:
                AppLocalizations.of(context)?.alreadyJoined ?? AppLocalizations.of(context)!.tr('Already Joined'),
          );
        }
      } else {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.failedToJoinGroup ?? AppLocalizations.of(context)!.tr('Failed to join group. Please try again.'),
            title: AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error'),
          );
        }
      }
    } catch (e) {
      print('❌ Error joining group: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.networkErrorCheckConnection ?? AppLocalizations.of(context)!.tr('Network error. Please check your connection.'),
          title:
              AppLocalizations.of(context)?.connectionError ?? AppLocalizations.of(context)!.tr('Connection Error'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        // Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: (widget.isLight ? Colors.black : Colors.white)
                .withOpacity(0.06),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            CupertinoIcons.person_badge_plus,
            size: 32,
            color: (widget.isLight ? Colors.black : Colors.white)
                .withOpacity(0.3),
          ),
        ),

        const SizedBox(height: 20),

        // Title
        Text(
          AppLocalizations.of(context)?.joinAGroup ?? AppLocalizations.of(context)!.tr('Join a Group'),
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
            fontWeight: FontWeight.w700,
            color: widget.isLight ? Colors.black : Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppLocalizations.of(context)?.groupCodeExplanation ?? AppLocalizations.of(context)!.tr('Ask your group admin for the 8-digit code'),
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            color: (widget.isLight ? Colors.black : Colors.white)
                .withOpacity(0.4),
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 28),

        // Code Label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context)?.enterGroupCode ?? AppLocalizations.of(context)!.tr('Group Code'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: (widget.isLight ? Colors.black : Colors.white)
                    .withOpacity(0.5),
              ),
            ),
          ),
        ),

        // Code Input
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: (widget.isLight ? Colors.black : Colors.white)
                .withOpacity(0.05),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
          ),
          child: TradeRepublicTextField(
            controller: _searchController,
            maxLength: 8,
            keyboardType: TextInputType.number,
            filled: false,
            style: TextStyle(
              color: widget.isLight ? Colors.black : Colors.white,
              fontSize: 22,
              letterSpacing: 5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            hintText: AppLocalizations.of(context)!.tr('00000000') ?? AppLocalizations.of(context)!.tr('00000000'),
            counterText: '',
            textAlign: TextAlign.center,
            onChanged: (value) {
              setState(() {});
            },
          ),
        ),

        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context)?.howToGetGroupCode ?? AppLocalizations.of(context)!.tr('Ask your group administrator for the code'),
              style: TextStyle(
                fontSize: 12,
                color: (widget.isLight ? Colors.black : Colors.white)
                    .withOpacity(0.35),
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        // Join Button
        TradeRepublicButton(
          label: _searchController.text.length == 8
              ? AppLocalizations.of(context)?.joinGroup ?? AppLocalizations.of(context)!.tr('Join Group')
              : AppLocalizations.of(context)?.enter8DigitCode ?? AppLocalizations.of(context)!.tr('Enter 8-Digit Code'),
          onPressed: _searchController.text.length == 8
              ? () async {
                  HapticFeedback.mediumImpact();
                  await _joinGroup();
                }
              : null,
          width: double.infinity,
        ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

        // Cancel
        TradeRepublicButton(
          label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
          onPressed: () => Navigator.pop(context),
          isSecondary: true,
          width: double.infinity,
        ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        ],
      ),
    );
  }
}

// Group Settings Modal
class _GroupSettingsModal extends StatefulWidget {
  final Map<String, dynamic> group;
  final bool isLight;
  final Map<String, dynamic>? userData;
  final VoidCallback onGroupUpdated;

  const _GroupSettingsModal({
    required this.group,
    required this.isLight,
    required this.userData,
    required this.onGroupUpdated,
  });

  @override
  State<_GroupSettingsModal> createState() => _GroupSettingsModalState();
}

class _GroupSettingsModalState extends State<_GroupSettingsModal> {
  late List<Map<String, dynamic>> members;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    members = List<Map<String, dynamic>>.from(widget.group['members'] ?? []);
  }

  Future<void> _leaveGroup() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo-groups/delvioo/leave'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'groupId': widget.group['groupId'],
          'userId': widget.userData?['userId'] ?? widget.userData?['id'],
        }),
      );

      print('📡 Leave group response: ${response.statusCode}');

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          widget.onGroupUpdated();

          TopNotification.success(
            context,
            'You have left the group "${widget.group['name']}"',
            title: AppLocalizations.of(context)?.leftGroup ?? AppLocalizations.of(context)!.tr('Left Group'),
          );
        }
      } else {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.failedToLeaveGroup ?? AppLocalizations.of(context)!.tr('Failed to leave group. Please try again.'),
            title: AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error'),
          );
        }
      }
    } catch (e) {
      print('❌ Error leaving group: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.networkErrorCheckConnection ?? AppLocalizations.of(context)!.tr('Network error. Please check your connection.'),
          title:
              AppLocalizations.of(context)?.connectionError ?? AppLocalizations.of(context)!.tr('Connection Error'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showTransferHostModal() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final currentUserId = widget.userData?['userId'] ?? widget.userData?['id'];
    final eligibleMembers = members
        .where(
          (member) =>
              member['userId'] != currentUserId && !(member['isHost'] ?? false),
        )
        .toList();

    if (eligibleMembers.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.tr('No other members available to transfer host role to.') ?? AppLocalizations.of(context)!.tr('No other members available to transfer host role to.'),
        title:
            AppLocalizations.of(context)?.transferNotPossible ?? AppLocalizations.of(context)!.tr('Transfer Not Possible'),
      );
      return;
    }

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.person_2,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.transferHostRole ?? AppLocalizations.of(context)!.tr('Transfer Host Role'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)?.chooseNewHostForGroup ?? AppLocalizations.of(context)!.tr('Choose a new host for the group:'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      color: widget.isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Members List
                  ...eligibleMembers.map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TradeRepublicListTile.navigation(
                        title: member['userName'] ?? (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr('')),
                        subtitle: '${AppLocalizations.of(context)?.joinedDate ?? AppLocalizations.of(context)!.tr('Joined')} ${_formatJoinDate(member['joinedAt'] ?? AppLocalizations.of(context)!.tr(''))}',
                        leading: const Icon(CupertinoIcons.person, size: 22),
                        onTap: () {
                          Navigator.pop(context);
                          _transferHost(member['userId'], member['userName']);
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
    );
  }

  Future<void> _transferHost(String newHostId, String newHostName) async {
    setState(() {
      isLoading = true;
    });

    try {
      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/groups/transfer-host'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token ?? AppLocalizations.of(context)!.tr('')}',
        },
        body: json.encode({
          'groupId': widget.group['groupId'],
          'currentHostId': widget.userData?['userId'] ?? widget.userData?['id'],
          'newHostId': newHostId,
        }),
      );

      print('📡 Transfer host response: ${response.statusCode}');

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          widget.onGroupUpdated();

          TopNotification.success(
            context,
            'Host role transferred to $newHostName successfully!',
            title:
                AppLocalizations.of(context)?.hostTransferred ?? AppLocalizations.of(context)!.tr('Host Transferred'),
          );
        }
      } else {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.failedToTransferHostRole ?? AppLocalizations.of(context)!.tr('Failed to transfer host role. Please try again.'),
            title:
                AppLocalizations.of(context)?.transferFailed ?? AppLocalizations.of(context)!.tr('Transfer Failed'),
          );
        }
      }
    } catch (e) {
      print('❌ Error transferring host: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.networkErrorCheckConnection ?? AppLocalizations.of(context)!.tr('Network error. Please check your connection.'),
          title:
              AppLocalizations.of(context)?.connectionError ?? AppLocalizations.of(context)!.tr('Connection Error'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showDeleteGroupConfirmation() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.trash,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.deleteGroup ?? AppLocalizations.of(context)!.tr('Delete Group'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: widget.isLight ? Colors.black : Colors.white,
                ),
              ),
            ],
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Minimal description
          Text(
            AppLocalizations.of(context)?.deleteGroupConfirm ?? AppLocalizations.of(context)!.tr('This will permanently delete this group and remove all members. This action cannot be undone.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              height: 1.4,
              color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
                0.6,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Primary action button
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label:
                  AppLocalizations.of(context)?.deleteForever ?? AppLocalizations.of(context)!.tr('Delete Forever'),
              tint: Colors.red,
              onPressed: () {
                Navigator.pop(context);
                _deleteGroup();
              },
            ),
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Secondary cancel button
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () => Navigator.pop(context),
              isSecondary: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.delete(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delvioo-groups/${widget.group['groupId']}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'hostId': widget.userData?['userId'] ?? widget.userData?['id'],
        }),
      );

      print('📡 Delete group response: ${response.statusCode}');

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          widget.onGroupUpdated();

          TopNotification.success(
            context,
            'Group "${widget.group['name']}" has been deleted successfully.',
            title:
                AppLocalizations.of(context)?.groupDeleted ?? AppLocalizations.of(context)!.tr('Group Deleted'),
          );
        }
      } else {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.failedToDeleteGroup ?? AppLocalizations.of(context)!.tr('Failed to delete group. Please try again.'),
            title:
                AppLocalizations.of(context)?.deleteFailed ?? AppLocalizations.of(context)!.tr('Delete Failed'),
          );
        }
      }
    } catch (e) {
      print('❌ Error deleting group: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.networkErrorCheckConnection ?? AppLocalizations.of(context)!.tr('Network error. Please check your connection.'),
          title:
              AppLocalizations.of(context)?.connectionError ?? AppLocalizations.of(context)!.tr('Connection Error'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final isHost = widget.group['isHost'] ?? false;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.settings,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.groupSettings ?? AppLocalizations.of(context)!.tr('Group Settings'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group Info Section
                  _buildSectionHeader(
                    AppLocalizations.of(context)?.groupInformation ?? AppLocalizations.of(context)!.tr('Group Information'),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Group Name
                  _buildSettingsTile(
                    icon: CupertinoIcons.group,
                    title:
                        widget.group['name'] ??
                        AppLocalizations.of(context)?.unknownGroup ?? AppLocalizations.of(context)!.tr('Unknown Group'),
                    subtitle:
                        AppLocalizations.of(context)?.groupName ?? AppLocalizations.of(context)!.tr('Group name'),
                    trailing: null,
                    onTap: null,
                  ),

                  // Join Code
                  _buildSettingsTile(
                    icon: CupertinoIcons.qrcode,
                    title: widget.group['joinCode'] ?? AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr('N/A'),
                    subtitle:
                        AppLocalizations.of(context)?.groupCodeTapToCopy ?? AppLocalizations.of(context)!.tr('Group code - Tap to copy'),
                    trailing: Icon(
                      CupertinoIcons.doc_on_doc,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 16,
                    ),
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.group['joinCode'] ?? AppLocalizations.of(context)!.tr('')),
                      );
                      TopNotification.success(
                        context,
                        AppLocalizations.of(context)!.tr('Group code copied to clipboard!') ?? AppLocalizations.of(context)!.tr('Group code copied to clipboard!'),
                        title: AppLocalizations.of(context)?.copied ?? AppLocalizations.of(context)!.tr('Copied'),
                      );
                    },
                  ),

                  // Member Count
                  _buildSettingsTile(
                    icon: CupertinoIcons.group,
                    title:
                        '${members.length} ${members.length == 1 ? 'Member' : 'Members'}',
                    subtitle:
                        AppLocalizations.of(context)?.totalGroupMembers ?? AppLocalizations.of(context)!.tr('Total group members'),
                    trailing: null,
                    onTap: null,
                  ),

                  // Host Status
                  if (isHost)
                    _buildSettingsTile(
                      icon: CupertinoIcons.person_badge_plus,
                      title: AppLocalizations.of(context)?.host ?? AppLocalizations.of(context)!.tr('Host'),
                      subtitle:
                          AppLocalizations.of(context)?.youAreTheGroupHost ?? AppLocalizations.of(context)!.tr('You are the group host'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (widget.isLight ? Colors.black : Colors.white)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.adminLabel ?? AppLocalizations.of(context)!.tr('ADMIN'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                      onTap: null,
                    ),

                  const SizedBox(height: 32),

                  // Members Section
                  _buildSectionHeader(
                    AppLocalizations.of(context)?.groupMembers ?? AppLocalizations.of(context)!.tr('Group Members'),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Members List
                  ...members.map((member) => _buildMemberTile(member)),

                  const SizedBox(height: 32),

                  // Group Actions Section
                  _buildSectionHeader(
                    AppLocalizations.of(context)?.groupActions ?? AppLocalizations.of(context)!.tr('Group Actions'),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Share Group Code
                  _buildSettingsTile(
                    icon: CupertinoIcons.share,
                    title:
                        AppLocalizations.of(context)?.shareGroupCode ?? AppLocalizations.of(context)!.tr('Share Group Code'),
                    subtitle:
                        AppLocalizations.of(
                          context,
                        )?.inviteOtherDriversToJoin ?? AppLocalizations.of(context)!.tr('Invite other drivers to join'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 16,
                    ),
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.group['joinCode'] ?? AppLocalizations.of(context)!.tr('')),
                      );
                      TopNotification.success(
                        context,
                        'Group code ${widget.group['joinCode']} copied to clipboard!',
                        title:
                            AppLocalizations.of(context)?.codeCopied ?? AppLocalizations.of(context)!.tr('Code Copied'),
                      );
                    },
                  ),

                  // Transfer Host (only for host)
                  if (isHost && members.length > 1)
                    _buildSettingsTile(
                      icon: CupertinoIcons.arrow_2_squarepath,
                      title:
                          AppLocalizations.of(context)?.transferHostRole ?? AppLocalizations.of(context)!.tr('Transfer Host Role'),
                      subtitle:
                          AppLocalizations.of(
                            context,
                          )?.makeAnotherMemberTheHost ?? AppLocalizations.of(context)!.tr('Make another member the host'),
                      trailing: Icon(
                        CupertinoIcons.chevron_right,
                        color: (widget.isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        size: 16,
                      ),
                      onTap: _showTransferHostModal,
                    ),

                  const SizedBox(height: 32),

                  // Danger Zone Section
                  _buildSectionHeader(
                    AppLocalizations.of(context)?.dangerZone ?? AppLocalizations.of(context)!.tr('Danger Zone'),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Leave Group
                  _buildSettingsTile(
                    icon: CupertinoIcons.square_arrow_left,
                    title: isHost
                      ? (AppLocalizations.of(context)?.leaveGroup ?? AppLocalizations.of(context)!.tr(''))
                        : AppLocalizations.of(context)?.leaveGroup ?? AppLocalizations.of(context)!.tr('Leave Group'),
                    subtitle: isHost
                        ? AppLocalizations.of(
                                context,
                              )?.transferOwnershipAndLeave ?? AppLocalizations.of(context)!.tr('Transfer ownership and leave')
                        : AppLocalizations.of(
                                context,
                              )?.removeYourselfFromGroup ?? AppLocalizations.of(context)!.tr('Remove yourself from this group'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      color: Colors.red.withOpacity(0.5),
                      size: 16,
                    ),
                    onTap: isLoading
                        ? null
                        : () {
                            TradeRepublicBottomSheet.show(
                              context: context,
                              showDragHandle: true,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                      // ── Sheet header: Icon left + Title ──
                                      Row(
                                        children: [
                                          Icon(
                                            CupertinoIcons.arrow_left_circle,
                                            size: 22,
                                            color: isLight ? Colors.black : Colors.white,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            AppLocalizations.of(context)?.leaveGroup ?? AppLocalizations.of(context)!.tr('Leave Group'),
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.4,
                                              color: widget.isLight ? Colors.black : Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                                      // Minimal description
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Text(
                                          isHost
                                              ? (AppLocalizations.of(context)?.leaveGroupAsHost ?? AppLocalizations.of(context)!.tr(''))
                                              : (AppLocalizations.of(context)?.rejoinGroupLater ?? AppLocalizations.of(context)!.tr('')),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                            height: 1.4,
                                            color:
                                                (widget.isLight
                                                        ? Colors.black
                                                        : Colors.white)
                                                    .withOpacity(0.6),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 32),

                                      // Primary action button - Platform check
                                      SizedBox(
                                        width: double.infinity,
                                        child: TradeRepublicButton(
                                          label:
                                              AppLocalizations.of(
                                                context,
                                              )?.leaveGroup ?? AppLocalizations.of(context)!.tr('Leave Group'),
                                          tint: Colors.red,
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _leaveGroup();
                                          },
                                        ),
                                      ),

                                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                                      // Secondary cancel button - Platform check
                                      SizedBox(
                                        width: double.infinity,
                                        child: TradeRepublicButton(
                                          label:
                                              AppLocalizations.of(
                                                context,
                                              )?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                                          tint: widget.isLight
                                              ? CupertinoColors.black
                                              : CupertinoColors.white,
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          isSecondary: true,
                                        ),
                                      ),
                                    ],
                                ),
                            );
                          },
                    isDestructive: true,
                  ),

                  // Delete Group (only for host)
                  if (isHost)
                    _buildSettingsTile(
                      icon: CupertinoIcons.delete,
                      title:
                          AppLocalizations.of(context)?.deleteGroup ?? AppLocalizations.of(context)!.tr('Delete Group'),
                      subtitle:
                          AppLocalizations.of(
                            context,
                          )?.permanentlyDeleteThisGroup ?? AppLocalizations.of(context)!.tr('Permanently delete this group'),
                      trailing: Icon(
                        CupertinoIcons.chevron_right,
                        color: Colors.red.withOpacity(0.5),
                        size: 16,
                      ),
                      onTap: isLoading ? null : _showDeleteGroupConfirmation,
                      isDestructive: true,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return TradeRepublicSectionHeader(
      title: title,
      padding: const EdgeInsets.only(bottom: 0),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TradeRepublicListTile(
        title: title,
        subtitle: subtitle,
        leading: Icon(icon, size: 20, color: isDestructive ? Colors.red : null),
        trailing: trailing,
        onTap: onTap,
        titleColor: isDestructive ? TradeRepublicTheme.destructiveRed : null,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _buildMemberTile(Map<String, dynamic> member) {
    final isHost = member['isHost'] ?? false;
    final currentUserId = widget.userData?['userId'] ?? widget.userData?['id'];
    final isCurrentUser = member['userId'] == currentUserId;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: (widget.isLight ? Colors.white : Colors.black),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        children: [
          // Member Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              color: (widget.isLight ? Colors.white : Colors.black),
            ),
            child: Icon(
              CupertinoIcons.person,
              color: (widget.isLight ? Colors.black : Colors.white),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Member Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member['userName'] ?? (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr('')),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: widget.isLight ? Colors.black : Colors.white,
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (widget.isLight ? Colors.black : Colors.white)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.youLabel ?? AppLocalizations.of(context)!.tr('You'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ],
                    if (isHost) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (widget.isLight ? Colors.black : Colors.white)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.host ?? AppLocalizations.of(context)!.tr('Host'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppLocalizations.of(context)?.joinedDate ?? AppLocalizations.of(context)!.tr('Joined')} ${_formatJoinDate(member['joinedAt'] ?? AppLocalizations.of(context)!.tr(''))}',
                  style: TextStyle(
                    fontSize: 12,
                    color: (widget.isLight ? Colors.black : Colors.white)
                        .withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberItem(Map<String, dynamic> member) {
    final isHost = member['isHost'] ?? false;
    final currentUserId = widget.userData?['userId'] ?? widget.userData?['id'];
    final isCurrentUser = member['userId'] == currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Member Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              color: (widget.isLight ? Colors.white : Colors.black),
            ),
            child: Icon(
              CupertinoIcons.person,
              color: (widget.isLight ? Colors.black : Colors.white),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Member Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${member['userName'] ?? AppLocalizations.of(context)?.unknownUser ?? AppLocalizations.of(context)!.tr('Unknown User')}${isCurrentUser ? ' (You)' : ''}',
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: widget.isLight ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                    if (isHost)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (widget.isLight ? Colors.black : Colors.white)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.host ?? AppLocalizations.of(context)!.tr('Host'),
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppLocalizations.of(context)?.joinedDate ?? AppLocalizations.of(context)!.tr('Joined')} ${_formatJoinDate(member['joinedAt'] ?? AppLocalizations.of(context)!.tr(''))}',
                  style: TextStyle(
                    fontSize: 12,
                    color: (widget.isLight ? Colors.black : Colors.white)
                        .withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatJoinDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date).inDays;

      if (difference == 0) {
        return 'today';
      } else if (difference == 1) {
        return 'yesterday';
      } else if (difference < 7) {
        return '$difference days ago';
      } else {
        final appSettings = Provider.of<AppSettings>(context, listen: false);
        return appSettings.formatDate(date);
      }
    } catch (e) {
      return 'recently';
    }
  }
}

// Add Account Modal
class _AddAccountModal extends StatefulWidget {
  final bool isLight;
  final List<Map<String, dynamic>> availableUsers;
  final String? selectedUserId;
  final Function(String) onAccountSwitch;
  final Function(String, String) onAccountAdd;

  const _AddAccountModal({
    required this.isLight,
    required this.availableUsers,
    required this.selectedUserId,
    required this.onAccountSwitch,
    required this.onAccountAdd,
  });

  @override
  State<_AddAccountModal> createState() => _AddAccountModalState();
}

class _AddAccountModalState extends State<_AddAccountModal> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.tr('Please fill in both email and password fields.') ?? AppLocalizations.of(context)!.tr('Please fill in both email and password fields.'),
        title:
            AppLocalizations.of(context)?.missingInformation ?? AppLocalizations.of(context)!.tr('Missing Information'),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    await widget.onAccountAdd(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    setState(() {
      _isLoading = false;
    });

    // Close modal after successful login
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showLoginForm(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.person_badge_plus,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.addAccount ?? AppLocalizations.of(context)!.tr('Add Account'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Email Field
                  TradeRepublicTextField(
                    controller: _emailController,
                    hintText: AppLocalizations.of(context)?.email ?? AppLocalizations.of(context)!.tr('Email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Password Field
                  TradeRepublicTextField.password(
                    controller: _passwordController,
                    hintText:
                        AppLocalizations.of(context)?.password ?? AppLocalizations.of(context)!.tr('Password'),
                  ),

                  const Spacer(),

                  // Add Account Button
                  SizedBox(
                    width: double.infinity,
                    child: TradeRepublicButton(
                      label:
                          AppLocalizations.of(context)?.addAccount ?? AppLocalizations.of(context)!.tr('Add Account'),
                      onPressed: _isLoading ? null : _handleLogin,
                      tint: widget.isLight
                          ? CupertinoColors.black
                          : CupertinoColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    // Find current user data
    final currentUser =
        widget.availableUsers.isNotEmpty && widget.selectedUserId != null
        ? widget.availableUsers.firstWhere(
            (user) => user['user_id'] == widget.selectedUserId,
            orElse: () => {},
          )
        : {};

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.person_circle,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.accountManagement ?? AppLocalizations.of(context)!.tr('Account Management'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current Account Section
                Text(
                  AppLocalizations.of(context)?.currentAccount ??
                      AppLocalizations.of(context)?.currentAccount ?? AppLocalizations.of(context)!.tr('Current Account'),
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Current Account Card
                TradeRepublicCard(
                  backgroundColor: widget.isLight ? Colors.white : Colors.black,
                  padding: DesktopAppWrapper.getPagePadding(),
                  child: Row(
                    children: [
                      // Profile Picture
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          color: (widget.isLight ? Colors.white : Colors.black),
                        ),
                        child: Icon(
                          CupertinoIcons.person,
                          color: (widget.isLight ? Colors.black : Colors.white),
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Account Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentUser.isNotEmpty
                                  ? '${currentUser['first_name'] ?? AppLocalizations.of(context)!.tr('Unknown')} ${currentUser['last_name'] ?? AppLocalizations.of(context)!.tr('')}'
                                  : AppLocalizations.of(context)?.currentUser ?? AppLocalizations.of(context)!.tr('Current User'),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w700,
                                color: widget.isLight
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentUser.isNotEmpty
                                  ? currentUser['email'] ?? (AppLocalizations.of(context)?.noEmailAddress ?? AppLocalizations.of(context)!.tr('No email'))
                                  : 'driver@example.com',
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                color:
                                    (widget.isLight
                                            ? Colors.black
                                            : Colors.white)
                                        .withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Active Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: (widget.isLight ? Colors.black : Colors.white)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.active ?? AppLocalizations.of(context)!.tr('Active'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),
                // Close TradeRepublicCard

                // Add Another Account Button - Platform check
                SizedBox(
                  width: double.infinity,
                  child: TradeRepublicButton(
                    label:
                        AppLocalizations.of(context)?.addAnotherAccount ?? AppLocalizations.of(context)!.tr('Add Another Account'),
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.pop(context);
                            _showLoginForm(context);
                          },
                    tint: widget.isLight
                        ? CupertinoColors.black
                        : CupertinoColors.white,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Stripe Payment Modal
class _StripePaymentModal extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? userData;
  final Function(Map<String, dynamic>) onPaymentInfoUpdated;

  const _StripePaymentModal({
    required this.isLight,
    required this.userData,
    required this.onPaymentInfoUpdated,
  });

  @override
  State<_StripePaymentModal> createState() => _StripePaymentModalState();
}

class _StripePaymentModalState extends State<_StripePaymentModal> {
  // USA System Controllers
  final TextEditingController _accountHolderController =
      TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _routingNumberController =
      TextEditingController();
  String _selectedAccountType = 'checking';

  // SEPA/SWIFT System Controllers
  final TextEditingController _ibanController = TextEditingController();
  final TextEditingController _bicController = TextEditingController();

  // Payment system selector
  bool _isUSASystem = true;
  bool _isLoading = false;

  // Track autofill values so we don't overwrite manual edits.
  String _lastAutofilledBankName = '';
  String _lastAutofilledBic = '';

  /// Detects the US bank name from a 9-digit ABA routing number.
  String _detectBankFromRoutingNumber(String routing) {
    if (routing.length < 4) return '';
    final prefixes = {
      '0210': 'Citibank', '0260': 'Bank of America',
      '0719': 'Chase', '3222': 'Wells Fargo',
      '1210': 'Wells Fargo', '2113': 'Citizens Bank',
      '2313': 'Santander', '2550': 'PNC Bank',
      '0711': 'Citibank', '0260': 'TD Bank',
    };
    for (final e in prefixes.entries) {
      if (routing.startsWith(e.key)) return e.value;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing payment info if available
    final paymentInfo = widget.userData?['paymentInfo'] ?? {};

    // Determine which system is being used
    if (paymentInfo['iban'] != null &&
        paymentInfo['iban'].toString().isNotEmpty) {
      _isUSASystem = false;
      _ibanController.text = (paymentInfo['iban'] ?? '').toString();
      _bicController.text = (paymentInfo['bic'] ?? '').toString();
      _bankNameController.text = (paymentInfo['bankName'] ?? '').toString();
      _accountHolderController.text = (paymentInfo['accountHolder'] ?? '').toString();
      _lastAutofilledBankName = _bankNameController.text;
      _lastAutofilledBic = _bicController.text;
    } else {
      _isUSASystem = true;
      _accountHolderController.text = (paymentInfo['accountHolder'] ?? '').toString();
      _bankNameController.text = (paymentInfo['bankName'] ?? '').toString();
      _accountNumberController.text = (paymentInfo['accountNumber'] ?? '').toString();
      _routingNumberController.text = (paymentInfo['routingNumber'] ?? '').toString();
      _selectedAccountType = (paymentInfo['accountType'] ?? 'checking').toString();
      _lastAutofilledBankName = _bankNameController.text;
    }
  }

  @override
  void dispose() {
    _accountHolderController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _routingNumberController.dispose();
    _ibanController.dispose();
    _bicController.dispose();
    super.dispose();
  }

  bool _validateForm() {
    if (_isUSASystem) {
      // USA System Validation
      if (_accountHolderController.text.trim().isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterAccountHolderName ?? AppLocalizations.of(context)!.tr('Please enter account holder name'),
        );
        return false;
      }
      if (_bankNameController.text.trim().isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterBankName ?? AppLocalizations.of(context)!.tr('Please enter bank name'),
        );
        return false;
      }
      if (_accountNumberController.text.trim().isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterAccountNumber ?? AppLocalizations.of(context)!.tr('Please enter account number'),
        );
        return false;
      }
      if (_routingNumberController.text.trim().isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterRoutingNumber ?? AppLocalizations.of(context)!.tr('Please enter routing number'),
        );
        return false;
      }

      // Basic US account number validation (6-17 digits)
      String cleanAccount = _accountNumberController.text.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      if (cleanAccount.length < 6 || cleanAccount.length > 17) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterValidAccountNumber ?? AppLocalizations.of(context)!.tr('Please enter a valid account number (6-17 digits)'),
        );
        return false;
      }

      // Basic US routing number validation (9 digits)
      String cleanRouting = _routingNumberController.text.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      if (cleanRouting.length != 9) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterValidRoutingNumber ?? AppLocalizations.of(context)!.tr('Please enter a valid 9-digit routing number'),
        );
        return false;
      }
    } else {
      // SEPA/SWIFT System Validation
      if (_accountHolderController.text.trim().isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterAccountHolderName ?? AppLocalizations.of(context)!.tr('Please enter account holder name'),
        );
        return false;
      }
      if (_ibanController.text.trim().isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterIban ?? AppLocalizations.of(context)!.tr('Please enter IBAN'),
        );
        return false;
      }
      if (_bicController.text.trim().isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterBicSwiftCode ?? AppLocalizations.of(context)!.tr('Please enter BIC/SWIFT code'),
        );
        return false;
      }

      // Basic IBAN validation (15-34 characters)
      String cleanIban = _ibanController.text.replaceAll(' ', '');
      if (cleanIban.length < 15 || cleanIban.length > 34) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.pleaseEnterValidIban ?? AppLocalizations.of(context)!.tr('Please enter a valid IBAN (15-34 characters)'),
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _savePaymentInfo() async {
    if (!_validateForm()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final paymentInfo = _isUSASystem
          ? {
              'accountHolder': _accountHolderController.text.trim(),
              'bankName': _bankNameController.text.trim(),
              'accountNumber': _accountNumberController.text.trim(),
              'routingNumber': _routingNumberController.text.trim(),
              'accountType': _selectedAccountType,
              'country': 'US',
              'currency': 'USD',
              'paymentSystem': AppLocalizations.of(context)?.usaLabel ?? AppLocalizations.of(context)!.tr('USA'),
              'updatedAt': DateTime.now().toIso8601String(),
            }
          : {
              'accountHolder': _accountHolderController.text.trim(),
              'bankName': _bankNameController.text.trim(),
              'iban': _ibanController.text.trim(),
              'bic': _bicController.text.trim(),
              'country': _ibanController.text.trim().substring(
                0,
                2,
              ), // First 2 chars of IBAN
              'currency': 'EUR',
              'paymentSystem': 'SEPA',
              'updatedAt': DateTime.now().toIso8601String(),
            };

      // Call parent callback to update the state
      widget.onPaymentInfoUpdated(paymentInfo);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.errorSavingPaymentInfo ?? AppLocalizations.of(context)!.tr('Error saving payment information')}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showAccountTypeSelector() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.creditcard,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.accountType ?? AppLocalizations.of(context)!.tr('Account Type'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

            const SizedBox(height: 20),

            // Options
            _buildAccountTypeOption(
              'checking',
              AppLocalizations.of(context)?.checkingAccount ?? AppLocalizations.of(context)!.tr('Checking Account'),
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            _buildAccountTypeOption(
              'savings',
              AppLocalizations.of(context)?.savingsAccount ?? AppLocalizations.of(context)!.tr('Savings Account'),
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () {
                Navigator.pop(context);
              },
              tint: widget.isLight
                  ? CupertinoColors.black
                  : CupertinoColors.white,
              isSecondary: true,
            ),
          ],
        ),
    );
  }

  Widget _buildAccountTypeOption(String type, String label) {
    final isSelected = _selectedAccountType == type;
    return TradeRepublicTap(
      onTap: () {
        setState(() {
          _selectedAccountType = type;
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: isSelected
              ? (widget.isLight ? Colors.black : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? (widget.isLight ? Colors.white : Colors.black)
                      : (widget.isLight ? Colors.black : Colors.white),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: widget.isLight ? Colors.white : Colors.black,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  void _showPasswordConfirmation() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final passwordController = TextEditingController();
    bool isPasswordVisible = false;
    bool isLoading = false;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [

                // ── Sheet header: Icon left + Title ──
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.lock,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.confirmPassword ?? AppLocalizations.of(context)!.tr('Confirm Password'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: widget.isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                Text(
                  AppLocalizations.of(
                        context,
                      )?.pleaseEnterPasswordToConnectBank ?? AppLocalizations.of(context)!.tr('Please enter your password to connect your bank account'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    color: (widget.isLight ? Colors.black : Colors.white)
                        .withOpacity(0.6),
                  ),
                ),

                const SizedBox(height: 32),

                // Password Field
                Container(
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color: widget.isLight
                        ? Colors.transparent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: TradeRepublicTextField(
                    controller: passwordController,
                    filled: false,
                    obscureText: !isPasswordVisible,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: widget.isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.2,
                    ),
                    hintText:
                        AppLocalizations.of(context)?.enterPassword ?? AppLocalizations.of(context)!.tr('Enter password'),
                    prefixIcon: Icon(
                      CupertinoIcons.lock,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.6),
                    ),
                    suffixIcon: TradeRepublicButton.icon(
                      size: 36,
                      isSecondary: true,
                      foregroundColor:
                          (widget.isLight ? Colors.black : Colors.white)
                              .withOpacity(0.6),
                      icon: Icon(
                        isPasswordVisible
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                      ),
                      onPressed: () {
                        setModalState(() {
                          isPasswordVisible = !isPasswordVisible;
                        });
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Confirm button
                TradeRepublicButton(
                  label: isLoading ? '' : (AppLocalizations.of(context)?.confirmPassword ?? AppLocalizations.of(context)!.tr('Confirm Password')),
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (passwordController.text.trim().isEmpty) {
                            TopNotification.error(
                              context,
                              AppLocalizations.of(
                                    context,
                                  )?.pleaseEnterYourPassword ??
                                  AppLocalizations.of(
                                    context,
                                  )?.pleaseEnterYourPassword ?? AppLocalizations.of(context)!.tr('Please enter your password'),
                            );
                            return;
                          }

                          setModalState(() {
                            isLoading = true;
                          });

                          // Simulate password verification
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );

                          if (mounted) {
                            Navigator.pop(context);
                            _savePaymentInfo();
                          }
                        },
                  width: double.infinity,
                ),

                // Cancel button
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  tint: widget.isLight
                      ? CupertinoColors.black
                      : CupertinoColors.white,
                  isSecondary: true,
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedField(
    String label,
    TextEditingController controller,
    IconData icon,
    String hint, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: TradeRepublicTheme.hintColor(context, opacity: 0.6),
            ),
          ),
        ),
        TradeRepublicTextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          hintText: hint,
          filled: true,
          readOnly: readOnly,
          onChanged: onChanged,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: TradeRepublicTheme.textColor(context),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupedTapField(
    String label,
    String value,
    IconData icon,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TradeRepublicTap(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: TradeRepublicTheme.hintColor(context, opacity: 0.6),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: isDark ? Colors.transparent : Colors.white,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: TradeRepublicTheme.textColor(context),
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_down,
                  size: 14,
                  color: TradeRepublicTheme.hintColor(context, opacity: 0.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: TradeRepublicTheme.textColor(context),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                  ),
                  child: Icon(
                    CupertinoIcons.creditcard_fill,
                    color: TradeRepublicTheme.surfaceColor(context),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.bankAccountSetup ?? AppLocalizations.of(context)!.tr('Bank Account Setup'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: TradeRepublicTheme.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        AppLocalizations.of(context)?.automaticPayouts ?? AppLocalizations.of(context)!.tr('Automatic monthly payouts'),
                        style: TextStyle(
                          fontSize: 13,
                          color: TradeRepublicTheme.hintColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.lock_fill,
                          size: 11, color: Color(0xFF34C759)),
                      SizedBox(width: 4),
                      Text(
                        'Stripe',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF34C759),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── System Toggle ────────────────────────────────────────────────
          TradeRepublicSlider(
            labels: const ['🇺🇸  USA', '🇪🇺  SEPA'],
            selectedIndex: _isUSASystem ? 0 : 1,
            onChanged: (i) => setState(() => _isUSASystem = i == 0),
          ),
          const SizedBox(height: 28),

          // ── Scrollable Content ───────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section: Account Details
                  TradeRepublicSectionHeader(
                    title: AppLocalizations.of(context)?.accountHolderName ?? AppLocalizations.of(context)!.tr('Account Details'),
                    padding: const EdgeInsets.only(bottom: 8),
                  ),

                  // Form fields
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGroupedField(
                        AppLocalizations.of(context)?.accountHolderName ?? AppLocalizations.of(context)!.tr('Account Holder Name'),
                        _accountHolderController,
                        CupertinoIcons.person,
                        AppLocalizations.of(context)?.fullNameOnAccount ?? AppLocalizations.of(context)!.tr('Full name on account'),
                      ),
                      if (_isUSASystem) ...[
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        _buildGroupedField(
                          AppLocalizations.of(context)?.bankName ?? AppLocalizations.of(context)!.tr('Bank Name'),
                          _bankNameController,
                          CupertinoIcons.building_2_fill,
                          'Chase, Wells Fargo…',
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        _buildGroupedTapField(
                          AppLocalizations.of(context)?.accountType ?? AppLocalizations.of(context)!.tr('Account Type'),
                          _selectedAccountType == 'checking'
                              ? (AppLocalizations.of(context)
                                      ?.checkingAccount ?? AppLocalizations.of(context)!.tr('Checking Account'))
                              : (AppLocalizations.of(context)
                                      ?.savingsAccount ?? AppLocalizations.of(context)!.tr('Savings Account')),
                          CupertinoIcons.person_crop_rectangle,
                          _showAccountTypeSelector,
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        _buildGroupedField(
                          AppLocalizations.of(context)?.routingNumber ?? AppLocalizations.of(context)!.tr('Routing Number'),
                          _routingNumberController,
                          CupertinoIcons.map,
                          '9-digit routing number',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            RoutingNumberInputFormatter(
                              onBankDetected: (routing) {
                                final detected = _detectBankFromRoutingNumber(routing);
                                if (detected.isNotEmpty) {
                                  if (_bankNameController.text.trim().isEmpty ||
                                      _bankNameController.text.trim() == _lastAutofilledBankName) {
                                    setState(() {
                                      _bankNameController.text = detected;
                                    });
                                    _lastAutofilledBankName = detected;
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        _buildGroupedField(
                          AppLocalizations.of(context)?.accountNumber ?? AppLocalizations.of(context)!.tr('Account Number'),
                          _accountNumberController,
                          CupertinoIcons.creditcard,
                          AppLocalizations.of(context)?.yourAccountNumber ?? AppLocalizations.of(context)!.tr('Account number'),
                          keyboardType: TextInputType.number,
                        ),
                      ] else ...[
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        _buildGroupedField(
                          AppLocalizations.of(context)?.bankName ?? AppLocalizations.of(context)!.tr('Bank Name'),
                          _bankNameController,
                          CupertinoIcons.building_2_fill,
                          AppLocalizations.of(context)
                                  ?.eGDeutscheBankSparkasse ?? AppLocalizations.of(context)!.tr('e.g. Deutsche Bank'),
                          readOnly: true,
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        _buildGroupedField(
                          AppLocalizations.of(context)?.iban ?? AppLocalizations.of(context)!.tr('IBAN'),
                          _ibanController,
                          CupertinoIcons.creditcard,
                          'DE89 3704 0044 0532 0130 00',
                          inputFormatters: [
                            IbanInputFormatter(
                              onBankDetected: (bankName) {
                                if (_bankNameController.text.trim().isEmpty ||
                                    _bankNameController.text.trim() == _lastAutofilledBankName) {
                                  setState(() {
                                    _bankNameController.text = bankName;
                                  });
                                  _lastAutofilledBankName = bankName;
                                }
                              },
                              onBicDetected: (bic) {
                                if (_bicController.text.trim().isEmpty ||
                                    _bicController.text.trim() == _lastAutofilledBic) {
                                  setState(() {
                                    _bicController.text = bic;
                                  });
                                  _lastAutofilledBic = bic;
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        _buildGroupedField(
                          AppLocalizations.of(context)?.bicSwiftCode ?? AppLocalizations.of(context)!.tr('BIC / SWIFT'),
                          _bicController,
                          CupertinoIcons.number,
                          'COBADEFFXXX',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Section: Payout Details
                  TradeRepublicSectionHeader(
                    title: AppLocalizations.of(context)?.payoutSchedule ?? AppLocalizations.of(context)!.tr('Payout Details'),
                    padding: const EdgeInsets.only(bottom: 8),
                  ),

                  TradeRepublicCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        // Row 1 – Security
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.shield,
                                size: 22,
                                color: Color(0xFF34C759),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)
                                              ?.bankLevelSecurity ?? AppLocalizations.of(context)!.tr('Bank-Level Security'),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            TradeRepublicTheme.textColor(context),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppLocalizations.of(context)
                                              ?.poweredByStripe ?? AppLocalizations.of(context)!.tr('Powered by Stripe · Fully encrypted'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: TradeRepublicTheme.hintColor(
                                              context)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        TradeRepublicDivider(
                            margin: const EdgeInsets.only(left: 16)),
                        // Row 2 – Schedule
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.calendar,
                                size: 22,
                                color: TradeRepublicTheme.hintColor(context),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)
                                              ?.payoutSchedule ?? AppLocalizations.of(context)!.tr('Monthly Payout'),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            TradeRepublicTheme.textColor(context),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppLocalizations.of(context)
                                              ?.monthlyPayoutsAtEndOfMonth ?? AppLocalizations.of(context)!.tr('Last day of each month · 1–3 business days'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: TradeRepublicTheme.hintColor(
                                              context)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        TradeRepublicDivider(
                            margin: const EdgeInsets.only(left: 16)),
                        // Row 3 – Earnings
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.arrow_right_circle,
                                size: 22,
                                color: TradeRepublicTheme.hintColor(context),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Instant Earnings',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            TradeRepublicTheme.textColor(context),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppLocalizations.of(context)
                                              ?.earningsExplanation ?? AppLocalizations.of(context)!.tr('Every delivery is accumulated automatically'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: TradeRepublicTheme.hintColor(
                                              context)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // CTA Button
                  SizedBox(
                    width: double.infinity,
                    child: TradeRepublicButton(
                      label: _isLoading
                          ? (AppLocalizations.of(context)?.connectingLabel ?? AppLocalizations.of(context)!.tr('Connecting...'))
                          : (AppLocalizations.of(context)?.connectBankAccount ?? AppLocalizations.of(context)!.tr('Connect Bank Account')),
                      onPressed: _isLoading ? null : _showPasswordConfirmation,
                      tint: widget.isLight
                          ? CupertinoColors.black
                          : CupertinoColors.white,
                    ),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Bank Details Modal (Legacy - keeping for compatibility)
class _BankDetailsModal extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? userData;
  final Function(Map<String, dynamic>) onBankDetailsUpdated;

  const _BankDetailsModal({
    required this.isLight,
    required this.userData,
    required this.onBankDetailsUpdated,
  });

  @override
  State<_BankDetailsModal> createState() => _BankDetailsModalState();
}

class _BankDetailsModalState extends State<_BankDetailsModal> {
  final TextEditingController _accountHolderController =
      TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  final TextEditingController _bicController = TextEditingController();
  bool _isLoading = false;

  String _lastAutofilledBankName = '';
  String _lastAutofilledBic = '';

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing bank details if available
    final bankDetails = widget.userData?['bankDetails'] ?? {};
    _accountHolderController.text = bankDetails['accountHolder'] ?? AppLocalizations.of(context)!.tr('');
    _bankNameController.text = bankDetails['bankName'] ?? AppLocalizations.of(context)!.tr('');
    _ibanController.text = bankDetails['iban'] ?? AppLocalizations.of(context)!.tr('');
    _bicController.text = bankDetails['bic'] ?? AppLocalizations.of(context)!.tr('');
    _lastAutofilledBankName = _bankNameController.text;
    _lastAutofilledBic = _bicController.text;
  }

  @override
  void dispose() {
    _accountHolderController.dispose();
    _bankNameController.dispose();
    _ibanController.dispose();
    _bicController.dispose();
    super.dispose();
  }

  bool _validateForm() {
    if (_accountHolderController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.pleaseEnterAccountHolderName ?? AppLocalizations.of(context)!.tr('Please enter account holder name'),
      );
      return false;
    }
    if (_bankNameController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.pleaseEnterBankName ?? AppLocalizations.of(context)!.tr('Please enter bank name'),
      );
      return false;
    }
    if (_ibanController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.pleaseEnterIban ?? AppLocalizations.of(context)!.tr('Please enter IBAN'),
      );
      return false;
    }
    if (_bicController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.pleaseEnterBicSwiftCode ?? AppLocalizations.of(context)!.tr('Please enter BIC/SWIFT code'),
      );
      return false;
    }

    // Basic IBAN validation (should be 15-34 characters)
    String cleanIban = _ibanController.text.replaceAll(' ', '');
    if (cleanIban.length < 15 || cleanIban.length > 34) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.pleaseEnterValidIban ?? AppLocalizations.of(context)!.tr('Please enter a valid IBAN (15-34 characters)'),
      );
      return false;
    }

    return true;
  }

  Future<void> _saveBankDetails() async {
    if (!_validateForm()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final bankDetails = {
        'accountHolder': _accountHolderController.text.trim(),
        'bankName': _bankNameController.text.trim(),
        'iban': _ibanController.text.replaceAll(' ', '').toUpperCase(),
        'bic': _bicController.text.trim().toUpperCase(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      // Call parent callback to update the state
      widget.onBankDetailsUpdated(bankDetails);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.errorSavingBankDetails ?? AppLocalizations.of(context)!.tr('Error saving bank details')}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.creditcard,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.paymentInformation ?? AppLocalizations.of(context)!.tr('Payment Information'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info Banner
                  Container(
                    width: double.infinity,
                    padding: DesktopAppWrapper.getPagePadding(),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.05),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.info,
                          color: widget.isLight ? Colors.black : Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(
                                  context,
                                )?.paymentProcessingInfo ?? AppLocalizations.of(context)!.tr('This information is used for payment processing. All data is encrypted and secure.'),
                            style: TextStyle(
                              color:
                                  (widget.isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.7),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Account Holder Name
                  Text(
                    AppLocalizations.of(context)?.accountHolderName ?? AppLocalizations.of(context)!.tr('Account Holder Name'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: widget.isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  TradeRepublicTextField(
                    controller: _accountHolderController,
                    hintText:
                        AppLocalizations.of(
                          context,
                        )?.enterFullNameAsOnBankAccount ?? AppLocalizations.of(context)!.tr('Enter full name as on bank account'),
                    prefixIcon: const Icon(CupertinoIcons.person),
                  ),
                  const SizedBox(height: 20),

                  // Bank Name
                  Text(
                    AppLocalizations.of(context)?.bankName ?? AppLocalizations.of(context)!.tr('Bank Name'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: widget.isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  TradeRepublicTextField(
                    controller: _bankNameController,
                    readOnly: true,
                    hintText:
                        AppLocalizations.of(context)?.eGDeutscheBankSparkasse ?? AppLocalizations.of(context)!.tr('e.g., Deutsche Bank, Sparkasse'),
                    prefixIcon: const Icon(CupertinoIcons.building_2_fill),
                  ),
                  const SizedBox(height: 20),

                  // IBAN
                  Text(
                    AppLocalizations.of(context)?.iban ?? AppLocalizations.of(context)!.tr('IBAN'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: widget.isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  TradeRepublicTextField(
                    controller: _ibanController,
                    hintText: AppLocalizations.of(context)!.tr('DE89 3704 0044 0532 0130 00') ?? AppLocalizations.of(context)!.tr('DE89 3704 0044 0532 0130 00'),
                    prefixIcon: const Icon(CupertinoIcons.creditcard),
                    inputFormatters: [
                      IbanInputFormatter(
                        onBankDetected: (bankName) {
                          if (_bankNameController.text.trim().isEmpty ||
                              _bankNameController.text.trim() == _lastAutofilledBankName) {
                            setState(() => _bankNameController.text = bankName);
                            _lastAutofilledBankName = bankName;
                          }
                        },
                        onBicDetected: (bic) {
                          if (_bicController.text.trim().isEmpty ||
                              _bicController.text.trim() == _lastAutofilledBic) {
                            setState(() => _bicController.text = bic);
                            _lastAutofilledBic = bic;
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // BIC/SWIFT
                  Text(
                    AppLocalizations.of(context)?.bicSwiftCode ?? AppLocalizations.of(context)!.tr('BIC/SWIFT Code'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: widget.isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  TradeRepublicTextField(
                    controller: _bicController,
                    hintText: AppLocalizations.of(context)!.tr('COBADEFFXXX') ?? AppLocalizations.of(context)!.tr('COBADEFFXXX'),
                    prefixIcon: const Icon(
                      CupertinoIcons.chevron_left_slash_chevron_right,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: _isLoading
                  ? AppLocalizations.of(context)?.savingLabel ?? AppLocalizations.of(context)!.tr('Saving...')
                  : AppLocalizations.of(context)?.savePaymentInformation ?? AppLocalizations.of(context)!.tr('Save Payment Information'),
              onPressed: _isLoading ? null : _saveBankDetails,
              tint: widget.isLight
                  ? CupertinoColors.black
                  : CupertinoColors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// Profile Edit Modal - Only Personal Information
class _ProfileEditModal extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? userData;
  final Function(Map<String, dynamic>) onProfileUpdated;

  const _ProfileEditModal({
    required this.isLight,
    required this.userData,
    required this.onProfileUpdated,
  });

  @override
  State<_ProfileEditModal> createState() => _ProfileEditModalState();
}

class _ProfileEditModalState extends State<_ProfileEditModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _dateOfBirthController;
  late TextEditingController _streetController;
  late TextEditingController _streetNumberController;
  late TextEditingController _cityController;
  late TextEditingController _zipCodeController;

  String _selectedPhonePrefix = '+1'; // Default to USA
  String _selectedCountry = 'United States'; // Default to USA
  DateTime? _selectedDate;

  // Helper to convert country name to emoji flag
  String _countryToFlag(String country) {
    const map = {
      'United States': '🇺🇸',
      'Canada':        '🇨🇦',
      'Mexico':        '🇲🇽',
      'United Kingdom':'🇬🇧',
      'Austria':       '🇦🇹',
      'Belgium':       '🇧🇪',
      'Bulgaria':      '🇧🇬',
      'Croatia':       '🇭🇷',
      'Cyprus':        '🇨🇾',
      'Czech Republic':'🇨🇿',
      'Denmark':       '🇩🇰',
      'Estonia':       '🇪🇪',
      'Finland':       '🇫🇮',
      'France':        '🇫🇷',
      'Germany':       '🇩🇪',
      'Greece':        '🇬🇷',
      'Hungary':       '🇭🇺',
      'Ireland':       '🇮🇪',
      'Italy':         '🇮🇹',
      'Latvia':        '🇱🇻',
      'Lithuania':     '🇱🇹',
      'Luxembourg':    '🇱🇺',
      'Malta':         '🇲🇹',
      'Netherlands':   '🇳🇱',
      'Norway':        '🇳🇴',
      'Poland':        '🇵🇱',
      'Portugal':      '🇵🇹',
      'Romania':       '🇷🇴',
      'Slovakia':      '🇸🇰',
      'Slovenia':      '🇸🇮',
      'Spain':         '🇪🇸',
      'Sweden':        '🇸🇪',
      'Switzerland':   '🇨🇭',
      'Russia':        '🇷🇺',
    };
    return map[country] ?? '🏳️';
  }

  // Step navigation
  int _currentStep = 1;

  // ID Photo management
  File? _frontIdImage;
  File? _backIdImage;
  String? _frontIdImageUrl;
  String? _backIdImageUrl;

  // Driver's License Photo management
  File? _frontLicenseImage;
  File? _backLicenseImage;
  String? _frontLicenseImageUrl;
  String? _backLicenseImageUrl;

  // Track if critical fields changed (requiring ID verification)
  final bool _criticalFieldsChanged = false;

  // Store original values to detect changes
  late String _originalFirstName;
  late String _originalLastName;
  late String _originalDateOfBirth;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with existing data
    final userData = widget.userData ?? {};
    final address = userData['address'] ?? {};

    _originalFirstName = (userData['firstName'] ?? '').toString();
    _originalLastName = (userData['lastName'] ?? '').toString();

    _firstNameController = TextEditingController(text: _originalFirstName);
    _lastNameController = TextEditingController(text: _originalLastName);
    _emailController = TextEditingController(text: (userData['email'] ?? '').toString());

    // Handle phone number - extract prefix and number
    final fullPhone = (userData['phone'] ?? '').toString();
    if (fullPhone.startsWith('+1')) {
      _selectedPhonePrefix = '+1';
      _phoneController = TextEditingController(text: fullPhone.substring(2));
    } else if (fullPhone.startsWith('+49')) {
      _selectedPhonePrefix = '+49';
      _phoneController = TextEditingController(text: fullPhone.substring(3));
    } else if (fullPhone.isNotEmpty) {
      // If phone exists but no prefix, keep the full number
      _phoneController = TextEditingController(text: fullPhone);
    } else {
      // Empty phone number
      _phoneController = TextEditingController(text: '');
    }

    // Handle date of birth
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final dateOfBirth = (userData['dateOfBirth'] ?? '').toString();
    if (dateOfBirth.isNotEmpty) {
      try {
        DateTime parsedDate;

        if (dateOfBirth.contains('.')) {
          // DD.MM.YYYY format
          final parts = dateOfBirth.split('.');
          if (parts.length == 3) {
            parsedDate = DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
            _selectedDate = parsedDate;
            // Format using selected date format
            _dateOfBirthController = TextEditingController(
              text: appSettings.formatDate(parsedDate),
            );
          } else {
            _dateOfBirthController = TextEditingController(text: dateOfBirth);
          }
        } else if (dateOfBirth.contains('-')) {
          // ISO date format from database (YYYY-MM-DD)
          final parts = dateOfBirth.split('-');
          if (parts.length == 3) {
            parsedDate = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
            _selectedDate = parsedDate;

            // Format using selected date format
            _dateOfBirthController = TextEditingController(
              text: appSettings.formatDate(parsedDate),
            );

            print(
              '📅 Parsed birth date from DB: $dateOfBirth -> ${appSettings.formatDate(parsedDate)}',
            );
          } else {
            // Fallback for other ISO formats
            parsedDate = DateTime.parse(dateOfBirth);
            _selectedDate = parsedDate;

            final appSettings = Provider.of<AppSettings>(
              context,
              listen: false,
            );
            _dateOfBirthController = TextEditingController(
              text: appSettings.formatDate(parsedDate),
            );
          }
        } else if (dateOfBirth.contains('T') || dateOfBirth.contains('Z')) {
          // Legacy ISO timestamp format (should not be used anymore)
          parsedDate = DateTime.parse(dateOfBirth);
          _selectedDate = parsedDate;

          final day = parsedDate.day.toString().padLeft(2, '0');
          final month = parsedDate.month.toString().padLeft(2, '0');
          final year = parsedDate.year.toString();
          _dateOfBirthController = TextEditingController(
            text: '$day.$month.$year',
          );
        } else {
          // Unknown format, use as is
          _dateOfBirthController = TextEditingController(text: dateOfBirth);
        }
      } catch (e) {
        print('❌ Error parsing date of birth "$dateOfBirth": $e');
        _selectedDate = null;
        _dateOfBirthController = TextEditingController(text: dateOfBirth);
      }
    } else {
      _dateOfBirthController = TextEditingController(text: '');
    }

    _streetController = TextEditingController(text: address['street'] ?? '');
    _streetNumberController = TextEditingController(
      text: address['streetNumber'] ?? '',
    );
    _cityController = TextEditingController(text: address['city'] ?? '');
    _zipCodeController = TextEditingController(text: address['zipCode'] ?? '');

    // Set country based on existing data
    final country = address['country'] ?? '';
    if (country.toLowerCase().contains('german') ||
        country.toLowerCase().contains('deutschland')) {
      _selectedCountry = 'Germany';
      _selectedPhonePrefix = '+49'; // Update phone prefix to match country
    } else if (country.toLowerCase().contains('united states') ||
        country.toLowerCase().contains('usa')) {
      _selectedCountry = 'United States';
      _selectedPhonePrefix = '+1'; // Update phone prefix to match country
    } else {
      // Default to USA if no country specified
      _selectedCountry = 'United States';
      _selectedPhonePrefix = '+1';
    }

    // Load ID photo URLs from database
    _frontIdImageUrl = userData['front_id_image_url'];
    _backIdImageUrl = userData['back_id_image_url'];
    print('📸 Loaded ID photos from userData:');
    print('  userData keys: ${userData.keys.toList()}');
    print('  front_id_image_url value: ${userData['front_id_image_url']}');
    print('  back_id_image_url value: ${userData['back_id_image_url']}');
    print('  _frontIdImageUrl: $_frontIdImageUrl');
    print('  _backIdImageUrl: $_backIdImageUrl');

    // Load Driver's License photos
    _frontLicenseImageUrl = userData['license_front_image_url'];
    _backLicenseImageUrl = userData['license_back_image_url'];
    print('🪪 Loaded Driver\'s License photos from userData:');
    print(
      '  license_front_image_url value: ${userData['license_front_image_url']}',
    );
    print(
      '  license_back_image_url value: ${userData['license_back_image_url']}',
    );
    print('  _frontLicenseImageUrl: $_frontLicenseImageUrl');
    print('  _backLicenseImageUrl: $_backLicenseImageUrl');

    // Important: Convert URLs that may contain localhost:8080 to use correct backend URL
    // This handles cases where old data in database has localhost URLs
    if (_frontIdImageUrl != null &&
        _frontIdImageUrl!.contains('localhost:8080')) {
      _frontIdImageUrl = _frontIdImageUrl!.replaceAll(
        'http://localhost:8080',
        '',
      );
      print('  ⚠️ Cleaned front ID URL: $_frontIdImageUrl');
    }
    if (_backIdImageUrl != null &&
        _backIdImageUrl!.contains('localhost:8080')) {
      _backIdImageUrl = _backIdImageUrl!.replaceAll(
        'http://localhost:8080',
        '',
      );
      print('  ⚠️ Cleaned back ID URL: $_backIdImageUrl');
    }
    if (_frontLicenseImageUrl != null &&
        _frontLicenseImageUrl!.contains('localhost:8080')) {
      _frontLicenseImageUrl = _frontLicenseImageUrl!.replaceAll(
        'http://localhost:8080',
        '',
      );
      print('  ⚠️ Cleaned front license URL: $_frontLicenseImageUrl');
    }
    if (_backLicenseImageUrl != null &&
        _backLicenseImageUrl!.contains('localhost:8080')) {
      _backLicenseImageUrl = _backLicenseImageUrl!.replaceAll(
        'http://localhost:8080',
        '',
      );
      print('  ⚠️ Cleaned back license URL: $_backLicenseImageUrl');
    }

    // Additional check: If URLs still have localhost or are from old local server,
    // they won't work on production. Clear them to force re-upload.
    // This catches URLs that were already cleaned but file doesn't exist on server (404)
    if (_frontIdImageUrl != null &&
        _frontIdImageUrl!.contains('arkadiydeiver1')) {
      print(
        '  ⚠️ Front ID appears to be from localhost upload - will need re-upload',
      );
      // Don't clear it yet, let user see the error and re-upload manually
    }
    if (_backIdImageUrl != null &&
        _backIdImageUrl!.contains('arkadiydeiver1')) {
      print(
        '  ⚠️ Back ID appears to be from localhost upload - will need re-upload',
      );
    }
    if (_frontLicenseImageUrl != null &&
        _frontLicenseImageUrl!.contains('arkadiydeiver1')) {
      print(
        '  ⚠️ Front license appears to be from localhost upload - will need re-upload',
      );
    }
    if (_backLicenseImageUrl != null &&
        _backLicenseImageUrl!.contains('arkadiydeiver1')) {
      print(
        '  ⚠️ Back license appears to be from localhost upload - will need re-upload',
      );
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dateOfBirthController.dispose();
    _streetController.dispose();
    _streetNumberController.dispose();
    _cityController.dispose();
    _zipCodeController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    // Manual date validation since we're not using TextFormField anymore
    if (_dateOfBirthController.text.trim().isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.dateOfBirthIsRequired ?? AppLocalizations.of(context)!.tr('Date of Birth is required'),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      // Convert date of birth from MM/DD/YYYY to YYYY-MM-DD for MySQL
      String? convertedDateOfBirth = _dateOfBirthController.text.trim();
      if (convertedDateOfBirth.isNotEmpty &&
          convertedDateOfBirth.contains('/')) {
        // Convert MM/DD/YYYY to YYYY-MM-DD
        final parts = convertedDateOfBirth.split('/');
        if (parts.length == 3) {
          final month = parts[0].padLeft(2, '0');
          final day = parts[1].padLeft(2, '0');
          final year = parts[2];
          convertedDateOfBirth = '$year-$month-$day';
        }
      }

      final updatedData = {
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _selectedPhonePrefix + _phoneController.text.trim(),
        'dateOfBirth': convertedDateOfBirth,
        'address': {
          'street': _streetController.text.trim(),
          'streetNumber': _streetNumberController.text.trim(),
          'city': _cityController.text.trim(),
          'zipCode': _zipCodeController.text.trim(),
          'country': _selectedCountry,
        },
      };

      // Add ID photo URLs if they exist
      if (_frontIdImageUrl != null && _frontIdImageUrl!.isNotEmpty) {
        updatedData['front_id_image_url'] = _frontIdImageUrl!;
      }
      if (_backIdImageUrl != null && _backIdImageUrl!.isNotEmpty) {
        updatedData['back_id_image_url'] = _backIdImageUrl!;
      }

      // Add Driver's License photo URLs if they exist
      if (_frontLicenseImageUrl != null && _frontLicenseImageUrl!.isNotEmpty) {
        updatedData['license_front_image_url'] = _frontLicenseImageUrl!;
      }
      if (_backLicenseImageUrl != null && _backLicenseImageUrl!.isNotEmpty) {
        updatedData['license_back_image_url'] = _backLicenseImageUrl!;
      }

      widget.onProfileUpdated(updatedData);
      Navigator.pop(context);
    }
  }

  // Get step title
  String _getStepTitle() {
    switch (_currentStep) {
      case 1:
        return AppLocalizations.of(context)?.personal ?? AppLocalizations.of(context)!.tr('Personal');
      case 2:
        return AppLocalizations.of(context)?.address ?? AppLocalizations.of(context)!.tr('Address');
      case 3:
        return AppLocalizations.of(context)?.documentsNav ?? AppLocalizations.of(context)!.tr('Documents');
      default:
        return AppLocalizations.of(context)?.editProfile ?? AppLocalizations.of(context)!.tr('Edit Profile');
    }
  }

  // Get step subtitle
  String _getStepSubtitle() {
    switch (_currentStep) {
      case 1:
        return AppLocalizations.of(context)?.basicInformation ?? AppLocalizations.of(context)!.tr('Basic information');
      case 2:
        return AppLocalizations.of(context)?.yourLocationDetails ?? AppLocalizations.of(context)!.tr('Your location details');
      case 3:
        return AppLocalizations.of(context)?.idVerification ?? AppLocalizations.of(context)!.tr('ID verification');
      default:
        return '';
    }
  }

  // Build step content
  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1:
        return _buildPersonalInfoStep();
      case 2:
        return _buildAddressStep();
      case 3:
        return _buildDocumentsStep();
      default:
        return Container();
    }
  }

  // Step 1: Personal Information
  Widget _buildPersonalInfoStep() {
    return Column(
      children: [
        _buildTextField(
          AppLocalizations.of(context)?.firstName ?? AppLocalizations.of(context)!.tr('First Name'),
          _firstNameController,
          CupertinoIcons.person,
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        _buildTextField(
          AppLocalizations.of(context)?.lastName ?? AppLocalizations.of(context)!.tr('Last Name'),
          _lastNameController,
          CupertinoIcons.person,
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        _buildTextField(
          AppLocalizations.of(context)?.email ?? AppLocalizations.of(context)!.tr('Email'),
          _emailController,
          CupertinoIcons.mail,
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        _buildPhoneField(),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        _buildDateField(),
      ],
    );
  }

  // Step 2: Address
  Widget _buildAddressStep() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildTextField(
                AppLocalizations.of(context)?.street ?? AppLocalizations.of(context)!.tr('Street'),
                _streetController,
                CupertinoIcons.house,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: _buildTextField(
                'No.',
                _streetNumberController,
                CupertinoIcons.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: _buildTextField(
                AppLocalizations.of(context)?.zip ?? AppLocalizations.of(context)!.tr('ZIP'),
                _zipCodeController,
                CupertinoIcons.mail,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _buildTextField(
                AppLocalizations.of(context)?.city ?? AppLocalizations.of(context)!.tr('City'),
                _cityController,
                CupertinoIcons.building_2_fill,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        _buildCountryField(),
      ],
    );
  }

  // Step 3: Documents
  Widget _buildDocumentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Government ID Card
        _buildDocumentCard(
          title: AppLocalizations.of(context)?.governmentId ?? AppLocalizations.of(context)!.tr('Government ID'),
          description:
              AppLocalizations.of(context)?.uploadFrontAndBackOfId ?? AppLocalizations.of(context)!.tr('Upload front and back of your ID'),
          documents: [
            {
              'label': AppLocalizations.of(context)?.front ?? AppLocalizations.of(context)!.tr('Front'),
              'image': _frontIdImage,
              'imageUrl': _frontIdImageUrl,
              'onTap': () => _captureIdPhoto('front'),
            },
            {
              'label': AppLocalizations.of(context)?.back ?? AppLocalizations.of(context)!.tr('Back'),
              'image': _backIdImage,
              'imageUrl': _backIdImageUrl,
              'onTap': () => _captureIdPhoto('back'),
            },
          ],
          icon: CupertinoIcons.person_badge_plus,
        ),
        const SizedBox(height: 20),

        // Driver's License Card
        _buildDocumentCard(
          title:
              AppLocalizations.of(context)?.driversLicense ??
              AppLocalizations.of(context)!.tr("Driver's License"),
          description:
              AppLocalizations.of(context)?.uploadFrontAndBackOfLicense ?? AppLocalizations.of(context)!.tr('Upload front and back of your license'),
          documents: [
            {
              'label': AppLocalizations.of(context)?.front ?? AppLocalizations.of(context)!.tr('Front'),
              'image': _frontLicenseImage,
              'imageUrl': _frontLicenseImageUrl,
              'onTap': () => _captureLicensePhoto('front'),
            },
            {
              'label': AppLocalizations.of(context)?.back ?? AppLocalizations.of(context)!.tr('Back'),
              'image': _backLicenseImage,
              'imageUrl': _backLicenseImageUrl,
              'onTap': () => _captureLicensePhoto('back'),
            },
          ],
          icon: CupertinoIcons.creditcard,
        ),
      ],
    );
  }

  // Build modern minimalist document card with animations
  Widget _buildDocumentCard({
    required String title,
    required String description,
    required List<Map<String, dynamic>> documents,
    required IconData icon,
  }) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 15 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: Container(
              padding: DesktopAppWrapper.getPagePadding(),
              decoration: BoxDecoration(
                color: widget.isLight
                    ? Colors.white
                    : Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with icon animation
                  Row(
                    children: [
                      TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 450),
                        tween: Tween(begin: 0.0, end: 1.0),
                        curve: Curves.easeOutBack,
                        builder: (context, scaleValue, child) {
                          return Transform.scale(
                            scale: scaleValue,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: widget.isLight
                                    ? Colors.black
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                              ),
                              child: Icon(
                                icon,
                                color: widget.isLight
                                    ? Colors.white
                                    : Colors.black,
                                size: 20,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: widget.isLight
                                    ? Colors.black
                                    : Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                color:
                                    (widget.isLight
                                            ? Colors.black
                                            : Colors.white)
                                        .withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Document upload buttons
                  Row(
                    children: [
                      for (int i = 0; i < documents.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: _buildMinimalDocumentUpload(
                            label: documents[i]['label'],
                            image: documents[i]['image'],
                            imageUrl: documents[i]['imageUrl'],
                            onTap: documents[i]['onTap'],
                            delay: i * 100,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Minimal document upload button with tap animation
  Widget _buildMinimalDocumentUpload({
    required String label,
    required File? image,
    required String? imageUrl,
    required VoidCallback onTap,
    int delay = 0,
  }) {
    bool hasImage = image != null || (imageUrl != null && imageUrl.isNotEmpty);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 280 + delay),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.85 + (0.15 * value),
          child: Opacity(
            opacity: value,
            child: _AnimatedDocumentButton(
              onTap: onTap,
              hasImage: hasImage,
              isLight: widget.isLight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutQuart,
                height: 140,
                decoration: BoxDecoration(
                  color: widget.isLight ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: hasImage
                    ? Stack(
                        children: [
                          // Image preview with fade-in
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: 1.0,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                              child: SizedBox(
                                width: double.infinity,
                                height: double.infinity,
                                child: image != null
                                    ? Image.file(image, fit: BoxFit.cover)
                                    : (imageUrl != null && imageUrl.isNotEmpty)
                                    ? Image.network(
                                        ApiConfig.getImageUrl(imageUrl),
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            return child;
                                          }
                                          return Center(
                                            child: CultiooLoadingIndicator(),
                                          );
                                        },
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              print(
                                                '❌ Error loading image: $imageUrl',
                                              );
                                              print('❌ Error: $error');
                                              return Center(
                                                child: Icon(
                                                  CupertinoIcons
                                                      .exclamationmark_triangle,
                                                  color: widget.isLight
                                                      ? Colors.white
                                                      : Colors.black,
                                                  size: 32,
                                                ),
                                              );
                                            },
                                      )
                                    : Container(),
                              ),
                            ),
                          ),
                          // Animated check mark
                          Positioned(
                            top: 8,
                            right: 8,
                            child: TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 400),
                              tween: Tween(begin: 0.0, end: 1.0),
                              curve: Curves.easeOutBack,
                              builder: (context, checkValue, child) {
                                return Transform.scale(
                                  scale: checkValue,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: widget.isLight
                                          ? Colors.green
                                          : Colors.green[300],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      CupertinoIcons.checkmark,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // Label with slide-up animation
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 300),
                              tween: Tween(begin: 0.0, end: 1.0),
                              curve: Curves.easeOutQuart,
                              builder: (context, slideValue, child) {
                                return Transform.translate(
                                  offset: Offset(0, 15 * (1 - slideValue)),
                                  child: Opacity(
                                    opacity: slideValue,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withOpacity(0.7),
                                          ],
                                        ),
                                        borderRadius: const BorderRadius.only(
                                          bottomLeft: Radius.circular(20),
                                          bottomRight: Radius.circular(20),
                                        ),
                                      ),
                                      child: Text(
                                        label,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 600),
                            tween: Tween(begin: 0.0, end: 1.0),
                            curve: Curves.easeOutBack,
                            builder: (context, pulseValue, child) {
                              return Transform.scale(
                                scale: 0.92 + (0.08 * pulseValue),
                                child: Icon(
                                  CupertinoIcons.camera,
                                  color:
                                      (widget.isLight
                                              ? Colors.black
                                              : Colors.white)
                                          .withOpacity(0.3),
                                  size: 32,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w600,
                              color:
                                  (widget.isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Next step
  void _nextStep() {
    if (_currentStep == 3) {
      _saveProfile();
    } else {
      setState(() {
        _currentStep++;
      });
    }
  }

  // Previous step
  void _previousStep() {
    if (_currentStep > 1) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _selectedDate ??
          DateTime.now().subtract(const Duration(days: 365 * 25)),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: widget.isLight ? Colors.black : Colors.white,
              onPrimary: widget.isLight ? Colors.white : Colors.black,
              surface: widget.isLight ? Colors.white : Colors.black,
              onSurface: widget.isLight ? Colors.black : Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        // Format as DD.MM.YYYY without time zones
        final day = picked.day.toString().padLeft(2, '0');
        final month = picked.month.toString().padLeft(2, '0');
        final year = picked.year.toString();
        _dateOfBirthController.text = '$day.$month.$year';
      });
    }
  }

  // iOS native date picker with spinning wheels
  Future<void> _selectDateIOS() async {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    DateTime tempDate =
        _selectedDate ??
        DateTime.now().subtract(const Duration(days: 365 * 25));

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.52,
      child: Column(
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.calendar,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.dateOfBirth ?? AppLocalizations.of(context)!.tr('Date of Birth'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _selectedDate != null
                ? '${_selectedDate!.day.toString().padLeft(2, '0')}.${_selectedDate!.month.toString().padLeft(2, '0')}.${_selectedDate!.year}'
                : AppLocalizations.of(context)?.selectDate ?? AppLocalizations.of(context)!.tr('Select your date of birth'),
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w400,
              color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
                0.5,
              ),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 20),

          // Divider
          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
              0.08,
            ),
          ),

          // iOS Date Picker Wheels
          Expanded(
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: widget.isLight ? Brightness.light : Brightness.dark,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                    fontWeight: FontWeight.w500,
                    color: widget.isLight ? Colors.black : Colors.white,
                  ),
                ),
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: tempDate,
                minimumDate: DateTime(1950),
                maximumDate: DateTime.now(),
                backgroundColor: Colors.transparent,
                onDateTimeChanged: (DateTime newDate) {
                  tempDate = newDate;
                },
              ),
            ),
          ),

          // Divider
          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
              0.08,
            ),
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Single confirm button - minimal Trade Republic style
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.confirm ?? AppLocalizations.of(context)!.tr('Confirm'),
            onPressed: () {
              HapticFeedback.mediumImpact();
              setState(() {
                _selectedDate = tempDate;
                final day = tempDate.day.toString().padLeft(2, '0');
                final month = tempDate.month.toString().padLeft(2, '0');
                final year = tempDate.year.toString();
                _dateOfBirthController.text = '$day.$month.$year';
              });
              Navigator.pop(context);
            },
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  void _showPhonePrefixSelector() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.phone,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.phonePrefix ?? AppLocalizations.of(context)!.tr('Phone Prefix'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

            const SizedBox(height: 20),

            // Scrollable options
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in const [
                      ['+1',   'USA',            '🇺🇸'],
                      ['+1',   'Canada',         '🇨🇦'],
                      ['+52',  'Mexico',         '🇲🇽'],
                      ['+44',  'United Kingdom', '🇬🇧'],
                      ['+43',  'Austria',        '🇦🇹'],
                      ['+32',  'Belgium',        '🇧🇪'],
                      ['+359', 'Bulgaria',       '🇧🇬'],
                      ['+385', 'Croatia',        '🇭🇷'],
                      ['+357', 'Cyprus',         '🇨🇾'],
                      ['+420', 'Czech Republic', '🇨🇿'],
                      ['+45',  'Denmark',        '🇩🇰'],
                      ['+372', 'Estonia',        '🇪🇪'],
                      ['+358', 'Finland',        '🇫🇮'],
                      ['+33',  'France',         '🇫🇷'],
                      ['+49',  'Germany',        '🇩🇪'],
                      ['+30',  'Greece',         '🇬🇷'],
                      ['+36',  'Hungary',        '🇭🇺'],
                      ['+353', 'Ireland',        '🇮🇪'],
                      ['+39',  'Italy',          '🇮🇹'],
                      ['+371', 'Latvia',         '🇱🇻'],
                      ['+370', 'Lithuania',      '🇱🇹'],
                      ['+352', 'Luxembourg',     '🇱🇺'],
                      ['+356', 'Malta',          '🇲🇹'],
                      ['+31',  'Netherlands',    '🇳🇱'],
                      ['+47',  'Norway',         '🇳🇴'],
                      ['+48',  'Poland',         '🇵🇱'],
                      ['+351', 'Portugal',       '🇵🇹'],
                      ['+40',  'Romania',        '🇷🇴'],
                      ['+421', 'Slovakia',       '🇸🇰'],
                      ['+386', 'Slovenia',       '🇸🇮'],
                      ['+34',  'Spain',          '🇪🇸'],
                      ['+46',  'Sweden',         '🇸🇪'],
                      ['+41',  'Switzerland',    '🇨🇭'],
                      ['+7',   'Russia',         '🇷🇺'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildPrefixOption(entry[0], entry[1], entry[2]),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              tint: widget.isLight
                  ? CupertinoColors.black
                  : CupertinoColors.white,
              isSecondary: true,
            ),
          ],
        ),
    );
  }

  Widget _buildPrefixOption(String prefix, String country, String flagIcon) {
    final isSelected = _selectedPhonePrefix == prefix;
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _selectedPhonePrefix = prefix;
          // Update country to match phone prefix
          if (prefix == '+1') {
            _selectedCountry = 'United States';
          } else if (prefix == '+49') {
            _selectedCountry = 'Germany';
          }
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: isSelected
              ? (widget.isLight ? Colors.black : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Text(flagIcon, style: const TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 10,),
            const SizedBox(width: 12),
            Text(
              '$prefix $country',
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? (widget.isLight ? Colors.white : Colors.black)
                    : (widget.isLight ? Colors.black : Colors.white),
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: widget.isLight ? Colors.white : Colors.black,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  void _showCountrySelector() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.globe,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.country ?? AppLocalizations.of(context)!.tr('Country'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

            const SizedBox(height: 20),

            // Scrollable options
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in const [
                      ['United States', '🇺🇸'],
                      ['Canada',        '🇨🇦'],
                      ['Mexico',        '🇲🇽'],
                      ['United Kingdom','🇬🇧'],
                      ['Austria',       '🇦🇹'],
                      ['Belgium',       '🇧🇪'],
                      ['Bulgaria',      '🇧🇬'],
                      ['Croatia',       '🇭🇷'],
                      ['Cyprus',        '🇨🇾'],
                      ['Czech Republic','🇨🇿'],
                      ['Denmark',       '🇩🇰'],
                      ['Estonia',       '🇪🇪'],
                      ['Finland',       '🇫🇮'],
                      ['France',        '🇫🇷'],
                      ['Germany',       '🇩🇪'],
                      ['Greece',        '🇬🇷'],
                      ['Hungary',       '🇭🇺'],
                      ['Ireland',       '🇮🇪'],
                      ['Italy',         '🇮🇹'],
                      ['Latvia',        '🇱🇻'],
                      ['Lithuania',     '🇱🇹'],
                      ['Luxembourg',    '🇱🇺'],
                      ['Malta',         '🇲🇹'],
                      ['Netherlands',   '🇳🇱'],
                      ['Norway',        '🇳🇴'],
                      ['Poland',        '🇵🇱'],
                      ['Portugal',      '🇵🇹'],
                      ['Romania',       '🇷🇴'],
                      ['Slovakia',      '🇸🇰'],
                      ['Slovenia',      '🇸🇮'],
                      ['Spain',         '🇪🇸'],
                      ['Sweden',        '🇸🇪'],
                      ['Switzerland',   '🇨🇭'],
                      ['Russia',        '🇷🇺'],
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildCountryOption(entry[0], entry[1]),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              tint: widget.isLight
                  ? CupertinoColors.black
                  : CupertinoColors.white,
              isSecondary: true,
            ),
          ],
        ),
    );
  }

  Widget _buildCountryOption(String country, String flagIcon) {
    final isSelected = _selectedCountry == country;
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _selectedCountry = country;
          // Update phone prefix to match country
          if (country == 'United States') {
            _selectedPhonePrefix = '+1';
          } else if (country == 'Germany') {
            _selectedPhonePrefix = '+49';
          }
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: isSelected
              ? (widget.isLight ? Colors.black : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Text(flagIcon, style: const TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 10,),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                country,
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? (widget.isLight ? Colors.white : Colors.black)
                      : (widget.isLight ? Colors.black : Colors.white),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: widget.isLight ? Colors.white : Colors.black,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Content with padding
            Expanded(
              child: Padding(
                padding: DesktopAppWrapper.getPagePadding(),
                child: Column(
                  children: [
                    // Header with Step Indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getStepTitle(),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        // Step dots
                        Row(
                          children: List.generate(3, (index) {
                            return Container(
                              margin: const EdgeInsets.only(left: 6),
                              width: _currentStep == index + 1 ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _currentStep == index + 1
                                    ? (widget.isLight
                                          ? Colors.black
                                          : Colors.white)
                                    : (widget.isLight
                                          ? Colors.black.withOpacity(0.2)
                                          : Colors.white.withOpacity(0.2)),
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                    // Step Subtitle
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _getStepSubtitle(),
                        style: TextStyle(
                          fontSize: 15,
                          color: widget.isLight
                              ? Colors.black.withOpacity(0.5)
                              : Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Form Content
                    Expanded(
                      child: SingleChildScrollView(child: _buildStepContent()),
                    ),

                    const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    // Navigation Buttons
                    Row(
                      children: [
                        if (_currentStep > 1)
                          Expanded(
                            child: TradeRepublicButton(
                              label:
                                  AppLocalizations.of(context)?.back ?? AppLocalizations.of(context)!.tr('Back'),
                              onPressed: _previousStep,
                              tint: CupertinoColors.systemGrey,
                              isSecondary: true,
                            ),
                          ),
                        if (_currentStep > 1) const SizedBox(width: 12),
                        Expanded(
                          flex: _currentStep == 1 ? 1 : 2,
                          child: TradeRepublicButton(
                            label: _currentStep == 3
                                ? AppLocalizations.of(context)?.saveProfile ?? AppLocalizations.of(context)!.tr('Save Profile')
                                : AppLocalizations.of(
                                        context,
                                      )?.continueAction ?? AppLocalizations.of(context)!.tr('Continue'),
                            onPressed: _nextStep,
                            tint: widget.isLight
                                ? CupertinoColors.black
                                : CupertinoColors.white,
                          ),
                        ),
                      ],
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

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.phoneNumber ?? AppLocalizations.of(context)!.tr('Phone Number'),
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w500,
            color: widget.isLight
                ? Colors.black.withOpacity(0.6)
                : Colors.white.withOpacity(0.6),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        Row(
          children: [
            TradeRepublicTap(
              onTap: _showPhonePrefixSelector,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: widget.isLight ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Row(
                  children: [
                    Text(
                      _selectedPhonePrefix,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: widget.isLight ? Colors.black : Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.chevron_down,
                      color: widget.isLight ? Colors.black : Colors.white,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TradeRepublicTextField(
                useFormField: true,
                controller: _phoneController,
                style: TextStyle(
                  color: widget.isLight ? Colors.black : Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
                keyboardType: TextInputType.phone,
                hintText:
                    AppLocalizations.of(context)?.enterPhoneNumber ?? AppLocalizations.of(context)!.tr('Enter phone number'),
                filled: true,
                fillColor: (widget.isLight ? Colors.white : Colors.black),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppLocalizations.of(context)?.phoneNumberRequired ?? AppLocalizations.of(context)!.tr('Phone number is required');
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return TradeRepublicTap(
      onTap: _selectDateIOS,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: widget.isLight ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.gift,
              color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
                0.7,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _dateOfBirthController.text.isEmpty
                    ? AppLocalizations.of(context)?.dateOfBirth ?? AppLocalizations.of(context)!.tr('Date of Birth')
                    : _dateOfBirthController.text,
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  color: _dateOfBirthController.text.isEmpty
                      ? (widget.isLight ? Colors.black : Colors.white)
                            .withOpacity(0.7)
                      : (widget.isLight ? Colors.black : Colors.white),
                ),
              ),
            ),
            Icon(
              CupertinoIcons.calendar,
              color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
                0.7,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountryField() {
    return TradeRepublicTap(
      onTap: _showCountrySelector,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: widget.isLight ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.globe,
              color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
                0.7,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _countryToFlag(_selectedCountry),
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedCountry,
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  color: widget.isLight ? Colors.black : Colors.white,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_down,
              color: widget.isLight ? Colors.black : Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w500,
            color: widget.isLight
                ? Colors.black.withOpacity(0.6)
                : Colors.white.withOpacity(0.6),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        TradeRepublicTextField(
          useFormField: true,
          controller: controller,
          style: TextStyle(
            color: widget.isLight ? Colors.black : Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
          hintText:
              '${AppLocalizations.of(context)?.enterLabel ?? AppLocalizations.of(context)!.tr('Enter')} $label',
          filled: true,
          fillColor: (widget.isLight ? Colors.white : Colors.black),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '$label is required';
            }
            return null;
          },
        ),
      ],
    );
  }

  // Capture ID photo (Front or Back)
  Future<void> _captureIdPhoto(String position) async {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final ImagePicker picker = ImagePicker();

    // Show option: Camera or Gallery
    final source = await TradeRepublicBottomSheet.show<ImageSource>(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.camera,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.chooseSource ?? AppLocalizations.of(context)!.tr('Choose Source'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          // Camera Option
          if (!Platform.isMacOS)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TradeRepublicListTile.navigation(
                title: AppLocalizations.of(context)?.camera ?? AppLocalizations.of(context)!.tr('Camera'),
                subtitle: AppLocalizations.of(context)?.takeANewPhoto ?? AppLocalizations.of(context)!.tr('Take a new photo'),
                leading: const Icon(CupertinoIcons.camera, size: 22),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ),
          // Gallery Option
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)?.gallery ?? AppLocalizations.of(context)!.tr('Gallery'),
              subtitle: AppLocalizations.of(context)?.chooseFromLibrary ?? AppLocalizations.of(context)!.tr('Choose from library'),
              leading: const Icon(CupertinoIcons.photo, size: 22),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ),
        ],
      ),
    );

    if (source == null) return;

    try {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          if (position == 'front') {
            _frontIdImage = File(pickedFile.path);
          } else {
            _backIdImage = File(pickedFile.path);
          }
        });

        // Upload to server
        await _uploadIdToServer(File(pickedFile.path), position);
      }
    } catch (e) {
      print('❌ Error capturing ID photo: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorCapturingPhoto ?? AppLocalizations.of(context)!.tr('Error capturing photo')}: $e',
      );
    }
  }

  // Upload ID photo to server
  Future<void> _uploadIdToServer(File imageFile, String position) async {
    try {
      print('📤 Uploading $position ID photo...');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/documents/upload-document'),
      );

      // Backend expects 'image' as field name, not 'document'
      request.files.add(
        await http.MultipartFile.fromPath(
          'image', // Changed from 'document' to 'image'
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      request.fields['documentType'] = position == 'front'
          ? 'front_id'
          : 'back_id';
      // Add username for unique filename
      final userData = widget.userData ?? {};
      final userId =
          userData['user_id'] ??
          userData['userId'] ??
          userData['id'] ?? AppLocalizations.of(context)!.tr('unknown');
      request.fields['username'] = userId.toString();

      print('📋 Upload fields: ${request.fields}');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📡 Upload response status: ${response.statusCode}');
      print('📡 Upload response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);

        // Backend returns: { success: true, data: { url: "..." } }
        final imageUrl =
            responseData['data']?['url'] ??
            responseData['url'] ??
            responseData['imageUrl'];

        if (imageUrl == null || imageUrl.isEmpty) {
          throw Exception('No image URL in response');
        }

        setState(() {
          if (position == 'front') {
            _frontIdImageUrl = imageUrl;
          } else {
            _backIdImageUrl = imageUrl;
          }
        });

        print('✅ $position ID photo uploaded: $imageUrl');

        if (mounted) {
          TopNotification.success(
            context,
            '${position == 'front' ? (AppLocalizations.of(context)?.front ?? AppLocalizations.of(context)!.tr('')) : (AppLocalizations.of(context)?.back ?? AppLocalizations.of(context)!.tr(''))} ${AppLocalizations.of(context)?.idUploadedSuccessfully ?? AppLocalizations.of(context)!.tr('')}',
          );
        }
      } else {
        final errorBody = response.body.isNotEmpty
            ? json.decode(response.body)
            : {};
        final errorMessage =
          errorBody['error'] ??
          errorBody['message'] ??
          (AppLocalizations.of(context)?.uploadFailed ?? AppLocalizations.of(context)!.tr(''));
        throw Exception(
          'Upload failed: ${response.statusCode} - $errorMessage',
        );
      }
    } catch (e) {
      print('❌ Error uploading $position ID: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.errorUploadingPhoto ?? AppLocalizations.of(context)!.tr('Error uploading photo')}: $e',
        );
      }
    }
  }

  // Capture Driver's License photo (Front or Back)
  Future<void> _captureLicensePhoto(String position) async {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final ImagePicker picker = ImagePicker();

    // Show option: Camera or Gallery
    final source = await TradeRepublicBottomSheet.show<ImageSource>(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.camera,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.chooseSource ?? AppLocalizations.of(context)!.tr('Choose Source'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          // Camera Option
          if (!Platform.isMacOS)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TradeRepublicListTile.navigation(
                title: AppLocalizations.of(context)?.camera ?? AppLocalizations.of(context)!.tr('Camera'),
                subtitle: AppLocalizations.of(context)?.takeANewPhoto ?? AppLocalizations.of(context)!.tr('Take a new photo'),
                leading: const Icon(CupertinoIcons.camera, size: 22),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ),
          // Gallery Option
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TradeRepublicListTile.navigation(
              title: AppLocalizations.of(context)?.gallery ?? AppLocalizations.of(context)!.tr('Gallery'),
              subtitle: AppLocalizations.of(context)?.chooseFromLibrary ?? AppLocalizations.of(context)!.tr('Choose from library'),
              leading: const Icon(CupertinoIcons.photo, size: 22),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ),
        ],
      ),
    );

    if (source == null) return;

    try {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          if (position == 'front') {
            _frontLicenseImage = File(pickedFile.path);
          } else {
            _backLicenseImage = File(pickedFile.path);
          }
        });

        // Upload to server
        await _uploadLicenseToServer(File(pickedFile.path), position);
      }
    } catch (e) {
      print('❌ Error capturing driver\'s license photo: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorCapturingPhoto ?? AppLocalizations.of(context)!.tr('Error capturing photo')}: $e',
      );
    }
  }

  // Upload Driver's License photo to server
  Future<void> _uploadLicenseToServer(File imageFile, String position) async {
    try {
      print('📤 Uploading $position driver\'s license photo...');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/documents/upload-document'),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      request.fields['documentType'] = position == 'front'
          ? 'front_license'
          : 'back_license';
      final userData = widget.userData ?? {};
      final userId =
          userData['user_id'] ??
          userData['userId'] ??
          userData['id'] ?? AppLocalizations.of(context)!.tr('unknown');
      request.fields['username'] = userId.toString();

      print('📋 Upload fields: ${request.fields}');

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📡 Upload response status: ${response.statusCode}');
      print('📡 Upload response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final imageUrl =
            responseData['data']?['url'] ??
            responseData['url'] ??
            responseData['imageUrl'];

        if (imageUrl == null || imageUrl.isEmpty) {
          throw Exception('No image URL in response');
        }

        setState(() {
          if (position == 'front') {
            _frontLicenseImageUrl = imageUrl;
          } else {
            _backLicenseImageUrl = imageUrl;
          }
        });

        print('✅ $position driver\'s license photo uploaded: $imageUrl');

        if (mounted) {
          TopNotification.success(
            context,
            '${position == 'front' ? (AppLocalizations.of(context)?.front ?? AppLocalizations.of(context)!.tr('')) : (AppLocalizations.of(context)?.back ?? AppLocalizations.of(context)!.tr(''))} ${AppLocalizations.of(context)?.licenseUploadedSuccessfully ?? AppLocalizations.of(context)!.tr('')}',
          );
        }
      } else {
        throw Exception('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error uploading $position driver\'s license: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.errorUploadingPhoto ?? AppLocalizations.of(context)!.tr('Error uploading photo')}: $e',
        );
      }
    }
  }

  // Build ID photo capture widget (similar to vehicle documents)
  Widget _buildIdPhotoCapture({
    required String title,
    required String subtitle,
    required File? image,
    required String? imageUrl,
    required VoidCallback onTap,
    required bool isLight,
  }) {
    bool hasImage = image != null || (imageUrl != null && imageUrl.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Upload/Change Button
        TradeRepublicListTile.navigation(
          title: title,
          subtitle: hasImage
              ? (AppLocalizations.of(context)?.tapToChangePhoto ?? AppLocalizations.of(context)!.tr('Tap to change'))
              : subtitle,
          leading: Icon(
            hasImage ? CupertinoIcons.pen : CupertinoIcons.camera,
            size: 22,
          ),
          onTap: onTap,
        ),

        // Image Preview (if exists)
        if (hasImage) ...[
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          TradeRepublicTap(
            onTap: () =>
                _showFullScreenImage(context, image, imageUrl, isLight),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Stack(
                children: [
                  // Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: image != null
                          ? Image.file(image, fit: BoxFit.cover)
                          : imageUrl != null
                          ? Image.network(
                              ApiConfig.getImageUrl(imageUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                print(
                                  '❌ Error loading image: ${ApiConfig.getImageUrl(imageUrl)}',
                                );
                                print('❌ Error: $error');
                                return Container(
                                  color: isLight ? Colors.white : Colors.black,
                                  child: Center(
                                    child: Icon(
                                      CupertinoIcons.exclamationmark_triangle,
                                      color: isLight
                                          ? Colors.black54
                                          : Colors.white54,
                                      size: 48,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(),
                    ),
                  ),

                  // "Tap to enlarge" badge
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.zoom_in,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            AppLocalizations.of(context)?.tapToEnlarge ?? AppLocalizations.of(context)!.tr('Tap to enlarge'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Show full screen image viewer
  void _showFullScreenImage(
    BuildContext context,
    File? imageFile,
    String? imageUrl,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      backgroundColor: Colors.black,
      enableDrag: true,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Stack(
          children: [
            // Full screen image with zoom
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: imageFile != null
                    ? Image.file(imageFile)
                    : imageUrl != null
                    ? Image.network(
                        ApiConfig.getImageUrl(imageUrl),
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.black,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    CupertinoIcons.exclamationmark_triangle,
                                    color: Colors.white54,
                                    size: 64,
                                  ),
                                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                                  Text(
                                    AppLocalizations.of(
                                          context,
                                        )?.imageCouldNotBeLoaded ?? AppLocalizations.of(context)!.tr('Image could not be loaded'),
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : Container(),
              ),
            ),
            Positioned(top: 30, left: 0, right: 0, child: DragHandle()),
            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: TradeRepublicButton.icon(
                icon: const Icon(CupertinoIcons.xmark, size: 22, color: Colors.white),
                backgroundColor: Colors.black.withOpacity(0.5),
                size: 44,
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Vehicle Management Modal
class _VehicleManagementModal extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? userData;
  final Function(Map<String, dynamic>) onVehicleUpdated;

  const _VehicleManagementModal({
    required this.isLight,
    required this.userData,
    required this.onVehicleUpdated,
  });

  @override
  State<_VehicleManagementModal> createState() =>
      _VehicleManagementModalState();
}

class _VehicleManagementModalState extends State<_VehicleManagementModal> {
  List<Map<String, dynamic>> vehicles = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      // delvioo_vehicles.user_id is a username FK — must use username, not numeric id.
      // Priority: delvioo_username pref (set by delvioo login) → userData username → generic username pref → numeric id as fallback
      final prefs = await SharedPreferences.getInstance();
      final storedDelviooUsername = prefs.getString('delvioo_username');
      final storedGenericUsername  = prefs.getString('username');

      final rawUsername = widget.userData?['username']?.toString() ?? AppLocalizations.of(context)!.tr('');
      final isRealUsername =
          rawUsername.isNotEmpty && !rawUsername.contains(' ');

      final userId = (storedDelviooUsername != null && storedDelviooUsername.isNotEmpty)
          ? storedDelviooUsername
          : isRealUsername
              ? rawUsername
              : (storedGenericUsername != null && storedGenericUsername.isNotEmpty)
                  ? storedGenericUsername
                  : (widget.userData?['user_id'] ??
                        widget.userData?['userId'] ??
                        widget.userData?['id'])
                      ?.toString();

      if (userId == null) {
        print('❌ No user ID found');
        if (mounted) {
          setState(() {
            vehicles = [];
            isLoading = false;
          });
        }
        return;
      }

      print('🚗 Loading vehicles for username: $userId');

      // Fetch vehicles from database
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/vehicles/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Load vehicles response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['vehicles'] != null) {
          if (mounted) {
            setState(() {
              vehicles = List<Map<String, dynamic>>.from(data['vehicles']);
              isLoading = false;
            });
          }
          print('✅ Loaded ${vehicles.length} vehicles from database');
          return;
        }
      }

      // If request failed, vehicles list is empty
      if (mounted) {
        setState(() {
          vehicles = [];
          isLoading = false;
        });
      }
      print('⚠️ No vehicles found or failed to load');
    } catch (e) {
      print('❌ Error loading vehicles: $e');
      if (mounted) {
        setState(() {
          vehicles = [];
          isLoading = false;
        });
      }
    }
  }

  Future<void> _saveVehicleToDatabase(
    Map<String, dynamic> vehicleData, {
    bool isNew = false,
  }) async {
    try {
      // user_id in delvioo_vehicles is FK → delvioo_users.username (varchar)
      // Prefer username from SharedPreferences (set at login) — most reliable source.
      final prefs = await SharedPreferences.getInstance();
      final storedUsername =
          prefs.getString('username') ?? prefs.getString('delvioo_username');

      // Priority: delvioo_username pref → widget.userData username (no spaces) → generic username pref → id fields
      final storedDelviooUsernameForSave = prefs.getString('delvioo_username');
      final rawUsername = widget.userData?['username']?.toString() ?? AppLocalizations.of(context)!.tr('');
      final isRealUsername = rawUsername.isNotEmpty && !rawUsername.contains(' ');
      final widgetUserId =
          (isRealUsername ? rawUsername : null) ??
          widget.userData?['user_id']?.toString() ??
          widget.userData?['userId']?.toString() ??
          widget.userData?['id']?.toString();

      // Use delvioo_username first, then widget userData, then generic username pref
      final userId = (storedDelviooUsernameForSave != null && storedDelviooUsernameForSave.isNotEmpty)
          ? storedDelviooUsernameForSave
          : (widgetUserId != null && widgetUserId != 'temp-user')
              ? widgetUserId
              : (storedUsername != null && storedUsername.isNotEmpty)
                  ? storedUsername
                  : null;
      print('🔑 resolved user_id to send: $userId (storedUsername="$storedUsername", rawUsername="$rawUsername")');

      if (userId == null) {
        throw Exception('No user ID found');
      }

      print('🚗 Saving vehicle to delvioo_vehicles table...');
      print('📋 Vehicle data: $vehicleData');

      // Prepare vehicle data for API (Backend expects mixed case: snake_case for basic fields, camelCase for food transport!)
      final apiData = {
        'user_id': userId.toString(),
        // Basic Vehicle Info (snake_case)
        'vehicle_make':
            vehicleData['vehicleMake'] ?? vehicleData['vehicle_make'],
        'vehicle_model':
            vehicleData['vehicleModel'] ?? vehicleData['vehicle_model'],
        'vehicle_year':
            (int.tryParse(vehicleData['vehicleYear']?.toString() ?? AppLocalizations.of(context)!.tr('')) ??
                    int.tryParse(
                      vehicleData['vehicle_year']?.toString() ?? AppLocalizations.of(context)!.tr(''),
                    ) ??
                    DateTime.now().year)
                .toString(),
        'license_plate':
            vehicleData['licensePlate'] ?? vehicleData['license_plate'] ?? AppLocalizations.of(context)!.tr(''),
        'vin': vehicleData['vin'] ?? AppLocalizations.of(context)!.tr(''),
        // Cargo & Payload Capacity (snake_case)
        'cargo_capacity':
            (double.tryParse(vehicleData['cargoCapacity']?.toString() ?? AppLocalizations.of(context)!.tr('')) ??
                    double.tryParse(
                      vehicleData['cargo_capacity']?.toString() ?? AppLocalizations.of(context)!.tr(''),
                    ))
                ?.toString(),
        'cargo_unit':
            vehicleData['cargoUnit'] ?? vehicleData['cargo_unit'] ?? AppLocalizations.of(context)!.tr('ft³'),
        'payload_capacity':
            (double.tryParse(
                      vehicleData['payloadCapacity']?.toString() ?? AppLocalizations.of(context)!.tr(''),
                    ) ??
                    double.tryParse(
                      vehicleData['payload_capacity']?.toString() ?? AppLocalizations.of(context)!.tr(''),
                    ))
                ?.toString(),
        'payload_unit':
            vehicleData['payloadUnit'] ?? vehicleData['payload_unit'] ?? AppLocalizations.of(context)!.tr('lbs'),
        // Location & Registration (snake_case)
        'license_state':
            vehicleData['usaState'] ?? vehicleData['license_state'] ?? AppLocalizations.of(context)!.tr('CA'),
        'country': vehicleData['country'] ?? (AppLocalizations.of(context)?.unitedStates ?? AppLocalizations.of(context)!.tr('')),
        // Photos (snake_case)
        'front_license_plate_photo':
            vehicleData['frontLicensePlatePhoto'] ??
            vehicleData['front_license_plate_photo'],
        'rear_license_plate_photo':
            vehicleData['rearLicensePlatePhoto'] ??
            vehicleData['rear_license_plate_photo'],
        'vehicle_registration_image_url':
            vehicleData['vehicleRegistrationImageUrl'] ??
            vehicleData['vehicle_registration_image_url'],
        'insurance_proof_image_url':
            vehicleData['insuranceProofImageUrl'] ??
            vehicleData['insurance_proof_image_url'],
        // Food Transport - Dimensions (camelCase for backend access!)
        ...() {
          final cargoLength =
              double.tryParse(vehicleData['cargoLength']?.toString() ?? AppLocalizations.of(context)!.tr('')) ??
              double.tryParse(vehicleData['cargo_length']?.toString() ?? AppLocalizations.of(context)!.tr(''));
          if (cargoLength != null) {
            return {'cargoLength': cargoLength.toString()};
          }
          return <String, dynamic>{};
        }(),
        ...() {
          final cargoWidth =
              double.tryParse(vehicleData['cargoWidth']?.toString() ?? AppLocalizations.of(context)!.tr('')) ??
              double.tryParse(vehicleData['cargo_width']?.toString() ?? AppLocalizations.of(context)!.tr(''));
          if (cargoWidth != null) {
            return {'cargoWidth': cargoWidth.toString()};
          }
          return <String, dynamic>{};
        }(),
        ...() {
          final cargoHeight =
              double.tryParse(vehicleData['cargoHeight']?.toString() ?? AppLocalizations.of(context)!.tr('')) ??
              double.tryParse(vehicleData['cargo_height']?.toString() ?? AppLocalizations.of(context)!.tr(''));
          if (cargoHeight != null) {
            return {'cargoHeight': cargoHeight.toString()};
          }
          return <String, dynamic>{};
        }(),
        'dimensionUnit':
            vehicleData['dimensionUnit'] ??
            vehicleData['dimension_unit'] ?? AppLocalizations.of(context)!.tr('ft'),
        // Food Transport - Temperature (camelCase for backend access!)
        ...() {
          final minTemp =
              double.tryParse(
                vehicleData['minTemperature']?.toString() ?? AppLocalizations.of(context)!.tr(''),
              ) ??
              double.tryParse(vehicleData['min_temperature']?.toString() ?? AppLocalizations.of(context)!.tr(''));
          if (minTemp != null) {
            return {'minTemperature': minTemp.toString()};
          }
          return <String, dynamic>{};
        }(),
        ...() {
          final maxTemp =
              double.tryParse(
                vehicleData['maxTemperature']?.toString() ?? AppLocalizations.of(context)!.tr(''),
              ) ??
              double.tryParse(vehicleData['max_temperature']?.toString() ?? AppLocalizations.of(context)!.tr(''));
          if (maxTemp != null) {
            return {'maxTemperature': maxTemp.toString()};
          }
          return <String, dynamic>{};
        }(),
        'temperatureUnit':
            vehicleData['temperatureUnit'] ??
            vehicleData['temperature_unit'] ?? AppLocalizations.of(context)!.tr('°C'),
        // Food Transport - Certifications (camelCase for backend access!)
        'isFoodSafe':
            vehicleData['isFoodSafe'] ?? vehicleData['is_food_safe'] ?? 0,
        'hasHazmatCertification':
            vehicleData['hasHazmatCertification'] ??
            vehicleData['has_hazmat_certification'] ??
            0,
        'hasCargoInsurance':
            vehicleData['hasCargoInsurance'] ??
            vehicleData['has_cargo_insurance'] ??
            0,
        // Food Transport - Documents (camelCase for backend access!)
        'hazmatCertificateUrl':
            vehicleData['hazmatCertificateUrl'] ??
            vehicleData['hazmat_certificate_url'],
        'cargoInsuranceCertificateUrl':
            vehicleData['cargoInsuranceCertificateUrl'] ??
            vehicleData['cargo_insurance_certificate_url'],
        // Vehicle Type (Grain Hopper, Refrigerated, etc.) - camelCase for backend
        'vehicleType':
            vehicleData['vehicleType'] ?? vehicleData['vehicle_type'],
        // Fuel Consumption (camelCase for backend access!)
        'averageFuelConsumption':
            vehicleData['averageFuelConsumption'] ??
            vehicleData['average_fuel_consumption'],
        'fuelConsumptionUnit':
            vehicleData['fuelConsumptionUnit'] ??
            vehicleData['fuel_consumption_unit'] ?? AppLocalizations.of(context)!.tr('MPG'),
        // Sectional Loading / Partial Fulfillment (camelCase for backend)
        'sectionalLoadingEnabled':
            vehicleData['sectionalLoadingEnabled'] ??
            vehicleData['sectional_loading_enabled'] ??
            0,
        'numberOfSections':
            vehicleData['numberOfSections'] ??
            vehicleData['number_of_sections'] ??
            1,
        'vehicleSections':
            vehicleData['vehicleSections'] ?? vehicleData['vehicle_sections'],
        // Primary vehicle flag (snake_case)
        'is_primary_vehicle': vehicles.isEmpty
            ? 1
            : 0, // First vehicle is primary
      };

      print('🌍 Country being saved to database: "${apiData['country']}"');
      print('📋 Complete API data: $apiData');
      print(
        '📄 Document URLs - Registration: ${apiData['vehicle_registration_image_url']}, Insurance: ${apiData['insurance_proof_image_url']}',
      );
      print(
        '📦 Sectional Loading - Enabled: ${apiData['sectionalLoadingEnabled']}, Sections: ${apiData['numberOfSections']}, Data: ${apiData['vehicleSections']}',
      );

      final response = isNew
          ? await http.post(
              Uri.parse('${ApiConfig.baseUrl}/api/delvioo/vehicle'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(apiData),
            )
          : await http.put(
              Uri.parse(
                '${ApiConfig.baseUrl}/api/delvioo/vehicle/${vehicleData['id']}',
              ),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(apiData),
            );

      print('📡 Save vehicle response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Vehicle saved successfully');

          // Reload vehicles list to show updated data (only if still mounted)
          if (mounted) {
            await _loadVehicles();
          }

          // Show success notification at the top with delay to ensure context is available
          if (mounted) {
            // Small delay to ensure modal animations are complete and context is stable
            await Future.delayed(const Duration(milliseconds: 100));
            if (mounted) {
              TopNotification.success(
                context,
                isNew
                    ? (AppLocalizations.of(context)?.vehicleAddedSuccessfully ?? AppLocalizations.of(context)!.tr('Vehicle added successfully!'))
                    : (AppLocalizations.of(context)?.vehicleUpdatedSuccessfully ?? AppLocalizations.of(context)!.tr('Vehicle updated successfully!')),
              );
            }
          }
        } else {
          throw Exception('API returned error: ${data['message']}');
        }
      } else {
        throw Exception('Failed to save vehicle: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error saving vehicle: $e');
      if (mounted) {
        // Small delay for error notification too
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          TopNotification.error(
            context,
            '${AppLocalizations.of(context)?.errorSavingVehicle ?? AppLocalizations.of(context)!.tr('Error saving vehicle')}: $e',
          );
        }
      }
    }
  }

  void _addNewVehicle() {
    // Set GLOBAL flag to prevent resetting notifier
    isOpeningVehicleSubModal = true;
    print('🚗 ADD VEHICLE: Set global flag to TRUE');

    // IMPORTANT: Keep notifier TRUE before closing parent modal
    print('🚗 ADD VEHICLE: Ensuring bottomSheetOpenNotifier stays TRUE');
    bottomSheetOpenNotifier.value = true;

    // Close Vehicle Management modal
    Navigator.pop(context);

    // Open Add Vehicle modal immediately
    Future.delayed(const Duration(milliseconds: 50), () {
      TradeRepublicBottomSheet.show(
        context: context,
        showDragHandle: true,
        child: _AddVehicleModal(
          isLight: widget.isLight,
          userData: widget.userData,
          onVehicleAdded: (newVehicle) async {
            await _saveVehicleToDatabase(newVehicle, isNew: true);
            _loadVehicles(); // Reload vehicles from database
          },
        ),
      ).whenComplete(() {
        // Show TabBar again when modal closes
        print('🚗 ADD VEHICLE: Setting bottomSheetOpenNotifier to FALSE');
        bottomSheetOpenNotifier.value = false;
        isOpeningVehicleSubModal = false; // Reset flag
      });
    });
  }

  void _editVehicle(int index) {
    final vehicleToEdit = vehicles[index];
    print('📝 Editing vehicle with data: $vehicleToEdit');
    print(
      '📸 Front plate photo: ${vehicleToEdit['front_license_plate_photo']}',
    );
    print('📸 Rear plate photo: ${vehicleToEdit['rear_license_plate_photo']}');
    print(
      '📄 Registration URL: ${vehicleToEdit['vehicle_registration_image_url']}',
    );
    print('📄 Insurance URL: ${vehicleToEdit['insurance_proof_image_url']}');

    // Set GLOBAL flag to prevent resetting notifier
    isOpeningVehicleSubModal = true;
    print('🚗 EDIT VEHICLE: Set global flag to TRUE');

    // IMPORTANT: Keep notifier TRUE before closing parent modal
    print('🚗 EDIT VEHICLE: Ensuring bottomSheetOpenNotifier stays TRUE');
    bottomSheetOpenNotifier.value = true;

    // Close Vehicle Management modal
    Navigator.pop(context);

    // Open Edit Vehicle modal with slight delay
    Future.delayed(const Duration(milliseconds: 50), () {
      TradeRepublicBottomSheet.show(
        context: context,
        showDragHandle: true,
        child: _AddVehicleModal(
          isLight: widget.isLight,
          userData: widget.userData,
          vehicleData: vehicleToEdit,
          onVehicleAdded: (updatedVehicle) async {
            // Add the vehicle ID for updating (convert to string to avoid type error)
            updatedVehicle['id'] = vehicleToEdit['id']?.toString();
            await _saveVehicleToDatabase(updatedVehicle, isNew: false);
            _loadVehicles(); // Reload vehicles from database

            // Update the main vehicle (for now, use the first one)
            if (vehicles.isNotEmpty) {
              widget.onVehicleUpdated(vehicles.first);
            }
          },
        ),
      ).whenComplete(() {
        // Show TabBar again when modal closes
        print('🚗 EDIT VEHICLE: Setting bottomSheetOpenNotifier to FALSE');
        bottomSheetOpenNotifier.value = false;
        isOpeningVehicleSubModal = false; // Reset flag
      });
    });
  }

  void _removeVehicle(int index) {
    // Prevent removing the last vehicle
    if (vehicles.length <= 1) {
      TopNotification.info(
        context,
        AppLocalizations.of(context)!.tr('You must have at least one vehicle registered.') ?? AppLocalizations.of(context)!.tr('You must have at least one vehicle registered.'),
      );
      return;
    }

    // Show confirmation dialog first
    _showDeleteVehicleConfirmation(index);
  }

  void _showDeleteVehicleConfirmation(int index) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final vehicle = vehicles[index];
    final vehicleName =
        '${vehicle['vehicle_year']} ${vehicle['vehicle_make']} ${vehicle['vehicle_model']}';

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.delete,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.deleteVehicleQuestion ?? AppLocalizations.of(context)!.tr('Delete Vehicle?'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // Description
            Text(
              AppLocalizations.of(context)?.deleteVehicleConfirm ?? AppLocalizations.of(context)!.tr('Are you sure you want to delete this vehicle? This action cannot be undone.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: (widget.isLight ? Colors.black : Colors.white)
                    .withOpacity(0.6),
              ),
            ),

            const SizedBox(height: 30),

            // Delete button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.deleteVehicle ?? AppLocalizations.of(context)!.tr('Delete Vehicle'),
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context);
                _deleteVehicleFromDatabase(index);
              },
              isDestructive: true,
              width: double.infinity,
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              isSecondary: true,
            ),
          ],
        ),
    );
  }

  Future<void> _deleteVehicleFromDatabase(int index) async {
    try {
      final vehicle = vehicles[index];
      final vehicleId = vehicle['id'] ?? vehicle['vehicle_id'];

      if (vehicleId == null) {
        throw Exception('No vehicle ID found for deletion');
      }

      print('🗑️ Deleting vehicle from database: ID $vehicleId');

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/vehicle/$vehicleId'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Delete vehicle response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          vehicles.removeAt(index);
        });

        // Update the main vehicle (use the first one)
        if (vehicles.isNotEmpty) {
          widget.onVehicleUpdated(vehicles.first);
        }

        TopNotification.success(
          context,
          AppLocalizations.of(context)?.vehicleDeletedSuccessfully ?? AppLocalizations.of(context)!.tr('Vehicle deleted successfully!'),
        );
        print('✅ Vehicle deleted from database successfully');
      } else {
        throw Exception('Failed to delete vehicle: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error deleting vehicle: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorDeletingVehicle ?? AppLocalizations.of(context)!.tr('Error deleting vehicle')}: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          // ── Sheet header ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.car_detailed,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.vehicleManagement ?? AppLocalizations.of(context)!.tr('Vehicle Management'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              TradeRepublicButton.icon(
                icon: Icon(
                  CupertinoIcons.plus,
                  size: 20,
                  color: isLight ? Colors.white : Colors.black,
                ),
                onPressed: _addNewVehicle,
                tint: isLight ? CupertinoColors.black : CupertinoColors.white,
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Vehicles List
          Expanded(
            child: isLoading
                ? const Center(child: CultiooLoadingIndicator())
                : vehicles.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.car,
                              size: 64,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.2),
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            Text(
                              AppLocalizations.of(context)?.noVehiclesAddedYet ?? AppLocalizations.of(context)!.tr('No vehicles added yet'),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              AppLocalizations.of(context)?.addFirstVehicle ?? AppLocalizations.of(context)!.tr('Tap + to add your first vehicle'),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: vehicles.length,
                        separatorBuilder: (_, __) => const TradeRepublicDivider(),
                        itemBuilder: (context, index) =>
                            _buildVehicleCard(vehicles[index], index, isLight),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _setMainVehicle(int index) async {
    final vehicle = vehicles[index];
    final vehicleId = vehicle['id']?.toString();
    if (vehicleId == null) return;

    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/vehicle/$vehicleId/set-primary'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Reload vehicles so ordering + flag is refreshed from DB
          await _loadVehicles();
          // Notify parent with the newly-primary vehicle
          if (vehicles.isNotEmpty && mounted) {
            final primary = vehicles.firstWhere(
              (v) => v['is_primary_vehicle'] == 1 || v['is_primary_vehicle'] == true,
              orElse: () => vehicles.first,
            );
            widget.onVehicleUpdated(primary);
          }
          if (mounted) {
            TopNotification.success(
              context,
              AppLocalizations.of(context)?.primaryVehicleSet ?? AppLocalizations.of(context)!.tr('Primary vehicle set ⭐'),
            );
          }
        }
      } else {
        throw Exception('Status ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error setting primary vehicle: $e');
      if (mounted) {
        TopNotification.error(context, '${AppLocalizations.of(context)?.errorSettingPrimaryVehicle ?? AppLocalizations.of(context)!.tr('Error setting primary vehicle')}: $e');
      }
    }
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle, int index, bool isLight) {
    final make = vehicle['vehicle_make'] ?? vehicle['make'] ?? (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr(''));
    final model = vehicle['vehicle_model'] ?? vehicle['model'] ?? (AppLocalizations.of(context)?.vehicle ?? AppLocalizations.of(context)!.tr(''));
    final year = vehicle['vehicle_year']?.toString() ??
      vehicle['year']?.toString() ?? (AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr(''));
    final licensePlate =
      vehicle['license_plate'] ?? vehicle['licensePlate'] ?? (AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr(''));
    final vehicleType = vehicle['vehicle_type'] ?? vehicle['vehicleType'] ?? AppLocalizations.of(context)!.tr('');

    final isPrimary = vehicle['is_primary_vehicle'] == 1 ||
        vehicle['is_primary_vehicle'] == true ||
        vehicle['is_primary_vehicle']?.toString() == '1';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TradeRepublicCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPrimary ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  size: 20,
                  color: isPrimary
                      ? const Color(0xFF00C853)
                      : (isLight ? Colors.black : Colors.white).withOpacity(0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [year, make, model].join(' '),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (isPrimary) '⭐ ${AppLocalizations.of(context)?.activeToday ?? AppLocalizations.of(context)!.tr('Active today')}',
                if (vehicleType.isNotEmpty) wagonLabelFromType(vehicleType, AppLocalizations.of(context) ?? AppLocalizations(const Locale('en'))),
                '${AppLocalizations.of(context)?.licensePlateLabel ?? AppLocalizations.of(context)!.tr('')}: $licensePlate',
              ].join(' · '),
              style: TextStyle(
                fontSize: 13,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              ),
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: isPrimary ? 'Primary' : 'Set Primary',
                    onPressed: isPrimary ? null : () => _setMainVehicle(index),
                    isSecondary: true,
                    height: 36,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.edit ?? AppLocalizations.of(context)!.tr('Edit'),
                    onPressed: () => _editVehicle(index),
                    isSecondary: true,
                    height: 36,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.delete ?? AppLocalizations.of(context)!.tr('Delete'),
                    onPressed: () => _showDeleteVehicleConfirmation(index),
                    isDestructive: true,
                    height: 36,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Add/Edit Vehicle Modal - Step 4 Style
class _AddVehicleModal extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? vehicleData;
  final Function(Map<String, dynamic>) onVehicleAdded;
  final Map<String, dynamic>? userData;

  const _AddVehicleModal({
    required this.isLight,
    this.vehicleData,
    required this.onVehicleAdded,
    required this.userData,
  });

  @override
  State<_AddVehicleModal> createState() => _AddVehicleModalState();
}

class _AddVehicleModalState extends State<_AddVehicleModal>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _yearController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _vinController = TextEditingController();
  final _cargoCapacityController = TextEditingController();
  final _payloadCapacityController = TextEditingController();

  // NEW: Food transport specific fields
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _minTemperatureController = TextEditingController();
  final _maxTemperatureController = TextEditingController();
  final _averageFuelConsumptionController = TextEditingController();

  // Animation controllers
  late AnimationController _countrySlideController;

  // Step navigation
  int _currentStep = 1;

  // Selected values for dropdowns
  String? _selectedMake;
  String? _selectedModel;
  String? _selectedVehicleType;
  String _cargoUnit = 'ft³';
  String _payloadUnit = 'lbs';
  String _selectedRegion = 'USA'; // 'USA', 'EU', 'CA', 'MX', 'RU'
  String _selectedUSAState = 'CA';

  // NEW: Food transport units
  String _dimensionUnit = 'ft'; // ft or m
  String _temperatureUnit = '°C'; // °F or °C
  double _minTempValue = -20.0;
  double _maxTempValue = 5.0;
  String _fuelConsumptionUnit = 'MPG'; // MPG or L/100km (default USA)

  // Photo paths for license plate photos
  String? _frontLicensePlatePhoto;
  String? _rearLicensePlatePhoto;

  // Document photos for Step 2
  File? _vehicleRegistrationImage;
  File? _insuranceProofImage;
  String? _vehicleRegistrationImageUrl;
  String? _insuranceProofImageUrl;

  // NEW: Food transport documents
  File? _hazmatCertificateImage;
  File? _cargoInsuranceCertificateImage;
  String? _hazmatCertificateUrl;
  String? _cargoInsuranceCertificateUrl;

  // NEW: Food transport certifications
  bool _isFoodSafe = false; // FDA/USDA Food-safe certified
  bool _hasHazmatCertification =
      false; // Hazmat certification for special food transport
  bool _hasCargoInsurance = false; // Cargo/Freight insurance

  // Legal agreements
  bool _acceptTerms = false; // Accept Terms & Conditions and Privacy Policy
  bool _confirmDataAccuracy = false; // Confirm data accuracy

  // Sectioned Loading - ALWAYS ENABLED (mandatory feature)
  List<Map<String, dynamic>> _vehicleSections = [];
  // Each section: {id: String, name: String, percentage: double, position: int}

  // Track if initial data has been loaded
  bool _hasLoadedInitialData = false;
  // Track if final save is in progress (retry uploads)
  bool _isSaving = false;

  // Vehicle makes and models for food transport vehicles
  final Map<String, List<String>> _vehicleData = {
    // === REFRIGERATION UNIT MANUFACTURERS ===
    'Thermo King': [
      'Super B Series',
      'C Series',
      'V Series',
      'SLXi Series',
      'T-Series',
      'TriPac APU',
      'Precedent S-600',
    ],
    'Carrier Transicold': [
      'Vector 1550',
      'Vector 1850',
      'Vector HE 19',
      'Pulsor 350',
      'Supra 950',
      'X4 7500',
      'neos',
    ],
    'Zanotti': ['Refrigerated Unit', 'Multi-Temperature', 'Frozen Transport'],
    'Eutectic': [
      'Eutectic Plates',
      'Zero Emission Cooling',
      'Silent Refrigeration',
    ],

    // === GRAIN & DRY BULK CARRIERS ===
    'Timpte': [
      'Super Hopper',
      'Grain Hopper',
      'Aluminum Hopper',
      'Steel Hopper',
      'Smooth Side Hopper',
    ],
    'Fruehauf': [
      'Grain Trailer',
      'Bulk Hopper',
      'Ag Hopper',
      'Livestock Trailer',
    ],
    'Cornhusker': ['Grain Hopper', 'Aluminum Hopper', 'Ag Trailer'],
    'Aulick': ['Live Bottom Trailer', 'Grain Trailer', 'Bulk Transport'],
    'Benson': ['Grain Hopper', 'Bulk Carrier', 'Agricultural Trailer'],

    // === LIQUID FOOD TANKERS ===
    'Polar Tank': [
      'Food Grade Tanker',
      'Stainless Steel Tanker',
      'Insulated Tanker',
      'Sanitary Tanker',
      'DOT 407 Tanker',
    ],
    'Walker Stainless': [
      'Sanitary Tanker',
      'Food Transport',
      'Beverage Tanker',
      'Wine Tanker',
      'Milk Tanker',
    ],
    'Heil': ['Food Grade Tank', 'Stainless Tanker', 'Sanitary Transport'],
    'Brenner': ['Food Tanker', 'Liquid Food Transport', 'DOT 407'],
    'Tremcar': ['Food Grade Tank', 'Insulated Tanker', 'Sanitary Tank'],

    // === MAJOR TRUCK MANUFACTURERS (Food Transport Variants) ===
    'Ford': [
      'Transit Refrigerated',
      'F-350 Reefer',
      'F-450 Reefer',
      'F-550 Reefer',
      'E-Series Reefer',
      'Transit Connect Reefer',
    ],
    'Mercedes-Benz': [
      'Sprinter Reefer',
      'Sprinter Food Transport',
      'Actros Reefer',
      'Atego Refrigerated',
      'Vito Reefer',
    ],
    'Isuzu': [
      'NPR Reefer',
      'NQR Reefer',
      'NRR Reefer',
      'FTR Reefer',
      'NPR-HD Reefer',
    ],
    'Freightliner': [
      'M2 Reefer',
      'Cascadia Reefer',
      'Business Class Reefer',
      'Sprinter Reefer',
    ],
    'International': [
      'MV Series Reefer',
      'CV Series Reefer',
      'HV Series Reefer',
      'Durastar Reefer',
    ],
    'Kenworth': ['T680 Reefer', 'T880 Reefer', 'W900 Reefer', 'T270 Reefer'],
    'Peterbilt': ['579 Reefer', '567 Reefer', '389 Reefer', '220 Reefer'],
    'Volvo': ['VNL Reefer', 'VNR Reefer', 'VHD Reefer', 'FL Reefer'],
    'Mack': [
      'Anthem Reefer',
      'Granite Reefer',
      'Pinnacle Reefer',
      'MD Series Reefer',
    ],
    'Hino': ['155 Reefer', '195 Reefer', '268 Reefer', '338 Reefer'],
    'Mitsubishi Fuso': [
      'Canter Reefer',
      'FE Series Reefer',
      'FG Series Reefer',
    ],
    'Chevrolet': ['Express Reefer', 'Silverado 3500 Reefer', 'LCF Reefer'],
    'GMC': ['Savana Reefer', 'Sierra 3500 Reefer', 'W-Series Reefer'],
    'Ram': ['ProMaster Reefer', 'Ram 3500 Reefer', 'Ram 4500 Reefer'],
    'Nissan': ['NV Cargo Reefer', 'Cabstar Reefer', 'UD Trucks Reefer'],

    // === TRAILER MANUFACTURERS (Food Transport) ===
    'Great Dane': [
      'Everest Reefer',
      'Multi-Temp Reefer',
      'Super Freezer',
      'Champion Reefer',
      'Freedom LT Reefer',
    ],
    'Utility Trailer': [
      'Reefer Van',
      'Insulated Van',
      '3000R Reefer',
      '4000D-X Reefer',
      'Multi-Temp Trailer',
    ],
    'Wabash': [
      'DuraPlate Reefer',
      'ArcticLite Reefer',
      'Multi-Temp',
      'Insulated Van',
    ],
    'Hyundai Translead': [
      'Reefer Trailer',
      'Multi-Temperature',
      'Insulated Van',
    ],
    'Strick': ['Reefer Van', 'Insulated Trailer', 'Multi-Temp'],

    // === SPECIALIZED FOOD TRANSPORT BODY MANUFACTURERS ===
    'Morgan Truck Body': [
      'DuraPlate Reefer',
      'Dry Freight',
      'Multi-Temp',
      'Olson Reefer',
      'Morgan Cool',
    ],
    'Supreme Corporation': [
      'Spartan Reefer',
      'Kold King',
      'Iner-City',
      'StarTrans',
      'Signature Series',
    ],
    'Kidron': ['Refrigerated Body', 'Food Service', 'Multi-Temp Body'],
    'Hackney': [
      'Beverage Body',
      'Route Star',
      'Platform',
      'Delivery Body',
      'Food Service',
    ],
    'Mickey': ['Beverage Truck', 'Route Delivery', 'Multi-Door Body'],
    'Marathon': ['Refrigerated Body', 'Food Service', 'Route Delivery'],
    'Maxon': ['Reefer Body', 'Liftgate Reefer', 'Food Transport'],
    'Reading Truck': [
      'Refrigerated Body',
      'Service Body Reefer',
      'Food Service',
    ],

    // === EUROPEAN MANUFACTURERS ===
    'Schmitz Cargobull': [
      'Reefer Trailer',
      'Multi-Temp',
      'FreshService',
      'EcoGeneration',
    ],
    'Krone': ['Cool Liner', 'Dual Temp', 'Multi Temp', 'Thermo Liner'],
    'Chereau': ['Reefer Van', 'Multi-Temperature', 'Pulsar'],
    'Lamberet': ['Refrigerated Body', 'Multi-Temperature', 'SR2'],
    'Gray & Adams': ['Reefer Van', 'Multi-Temp', 'Insulated Body'],
    'Montracon': ['Reefer Trailer', 'Multi-Temperature', 'Insulated Van'],
    'SDC': ['Reefer Trailer', 'Multi-Temp', 'Insulated Van'],

    // === ASIAN MANUFACTURERS ===
    'Dongfeng': ['Reefer Truck', 'Cold Chain', 'Food Transport'],
    'JAC': ['Refrigerated Van', 'Reefer Truck', 'Cold Chain'],
    'Foton': ['Reefer Truck', 'Cold Chain Vehicle', 'Food Transport'],
    'CIMC': ['Reefer Container', 'Cold Chain Trailer', 'Multi-Temp Container'],
  };

  // Countries list with names (EU + CA + MX + RU)
  final Map<String, String> _euCountries = {
    'AT': 'Austria',
    'BE': 'Belgium',
    'BG': 'Bulgaria',
    'HR': 'Croatia',
    'CY': 'Cyprus',
    'CZ': 'Czech Republic',
    'DK': 'Denmark',
    'EE': 'Estonia',
    'FI': 'Finland',
    'FR': 'France',
    'DE': 'Germany',
    'GR': 'Greece',
    'HU': 'Hungary',
    'IE': 'Ireland',
    'IT': 'Italy',
    'LV': 'Latvia',
    'LT': 'Lithuania',
    'LU': 'Luxembourg',
    'MT': 'Malta',
    'NL': 'Netherlands',
    'PL': 'Poland',
    'PT': 'Portugal',
    'RO': 'Romania',
    'SK': 'Slovakia',
    'SI': 'Slovenia',
    'ES': 'Spain',
    'SE': 'Sweden',
  };

  // USA States list
  final List<String> _usaStates = [
    'AL',
    'AK',
    'AZ',
    'AR',
    'CA',
    'CO',
    'CT',
    'DE',
    'FL',
    'GA',
    'HI',
    'ID',
    'IL',
    'IN',
    'IA',
    'KS',
    'KY',
    'LA',
    'ME',
    'MD',
    'MA',
    'MI',
    'MN',
    'MS',
    'MO',
    'MT',
    'NE',
    'NV',
    'NH',
    'NJ',
    'NM',
    'NY',
    'NC',
    'ND',
    'OH',
    'OK',
    'OR',
    'PA',
    'RI',
    'SC',
    'SD',
    'TN',
    'TX',
    'UT',
    'VT',
    'VA',
    'WA',
    'WV',
    'WI',
    'WY',
  ];

  @override
  void initState() {
    super.initState();
    _countrySlideController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoadedInitialData) {
      _hasLoadedInitialData = true;
      // Use setState so all loaded state variables (not just TextControllers) trigger a rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loadInitialData());
      });
    }
  }

  void _loadInitialData() {
    if (widget.vehicleData != null) {
      print(
        '🚗 Loading vehicle data from delvioo_vehicles table: ${widget.vehicleData}',
      );

      // Load vehicle data from new delvioo_vehicles table structure
      _selectedMake = widget.vehicleData!['vehicle_make'];
      _selectedModel = widget.vehicleData!['vehicle_model'];
      _selectedVehicleType = widget.vehicleData!['vehicle_type'];
      _yearController.text =
          widget.vehicleData!['vehicle_year']?.toString() ?? AppLocalizations.of(context)!.tr('');

      // Load license plate first (will be conditionally loaded based on country)
      String savedLicensePlate = widget.vehicleData!['license_plate'] ?? AppLocalizations.of(context)!.tr('');

      // VIN from delvioo_vehicles table
      String vinValue = widget.vehicleData!['vin'] ?? AppLocalizations.of(context)!.tr('');
      _vinController.text = vinValue;
      print('🚗 VIN loaded: "$vinValue"');

      // Get AppSettings for number formatting
      final appSettings = context.read<AppSettings>();

      // Cargo capacity from delvioo_vehicles table - format using AppSettings
      double cargoValue =
          double.tryParse(
            widget.vehicleData!['cargo_capacity']?.toString() ?? AppLocalizations.of(context)!.tr('0'),
          ) ??
          0.0;
      if (cargoValue > 0) {
        _cargoCapacityController.text = appSettings.formatNumber(
          cargoValue,
          decimals: 2,
        );
      }
      print('🚗 Cargo capacity loaded: "$cargoValue"');

      // Payload capacity from delvioo_vehicles table - format using AppSettings
      double payloadValue =
          double.tryParse(
            widget.vehicleData!['payload_capacity']?.toString() ?? AppLocalizations.of(context)!.tr('0'),
          ) ??
          0.0;
      if (payloadValue > 0) {
        _payloadCapacityController.text = appSettings.formatNumber(
          payloadValue,
          decimals: 2,
        );
      }
      print('🚗 Payload capacity loaded: "$payloadValue"');

      // Units from delvioo_vehicles table
      _cargoUnit = widget.vehicleData!['cargo_unit'] ?? AppLocalizations.of(context)!.tr('ft³');
      _payloadUnit = widget.vehicleData!['payload_unit'] ?? AppLocalizations.of(context)!.tr('lbs');
      _selectedUSAState = widget.vehicleData!['license_state'] ?? AppLocalizations.of(context)!.tr('CA');

      print('🚗 Units loaded - Cargo: $_cargoUnit, Payload: $_payloadUnit');

      // Load license plate photos (try both field names for compatibility)
      _frontLicensePlatePhoto =
          widget.vehicleData!['front_license_plate_photo'] ??
          widget.vehicleData!['frontLicensePlatePhoto'];
      _rearLicensePlatePhoto =
          widget.vehicleData!['rear_license_plate_photo'] ??
          widget.vehicleData!['rearLicensePlatePhoto'];

      print(
        '📸 Photos loaded - Front: $_frontLicensePlatePhoto, Rear: $_rearLicensePlatePhoto',
      );

      // Load document URLs (Step 2)
      _vehicleRegistrationImageUrl =
          widget.vehicleData!['vehicle_registration_image_url'] ??
          widget.vehicleData!['vehicleRegistrationImageUrl'];
      _insuranceProofImageUrl =
          widget.vehicleData!['insurance_proof_image_url'] ??
          widget.vehicleData!['insuranceProofImageUrl'];

      print(
        '📄 Documents loaded - Registration: $_vehicleRegistrationImageUrl, Insurance: $_insuranceProofImageUrl',
      );

      // Load Food Transport data (Step 3)
      // Dimensions
      _lengthController.text =
          widget.vehicleData!['cargo_length']?.toString() ?? AppLocalizations.of(context)!.tr('');
      _widthController.text =
          widget.vehicleData!['cargo_width']?.toString() ?? AppLocalizations.of(context)!.tr('');
      _heightController.text =
          widget.vehicleData!['cargo_height']?.toString() ?? AppLocalizations.of(context)!.tr('');
      _dimensionUnit = widget.vehicleData!['dimension_unit'] ?? AppLocalizations.of(context)!.tr('ft');

      // Temperature
      _minTemperatureController.text =
          widget.vehicleData!['min_temperature']?.toString() ?? AppLocalizations.of(context)!.tr('');
      _maxTemperatureController.text =
          widget.vehicleData!['max_temperature']?.toString() ?? AppLocalizations.of(context)!.tr('');
      _temperatureUnit = widget.vehicleData!['temperature_unit'] ?? AppLocalizations.of(context)!.tr('°C');
      _minTempValue = double.tryParse(_minTemperatureController.text) ?? -20.0;
      _maxTempValue = double.tryParse(_maxTemperatureController.text) ?? 5.0;

      // Certifications
      _isFoodSafe =
          (widget.vehicleData!['is_food_safe'] == 1 ||
          widget.vehicleData!['is_food_safe'] == true);
      _hasHazmatCertification =
          (widget.vehicleData!['has_hazmat_certification'] == 1 ||
          widget.vehicleData!['has_hazmat_certification'] == true);
      _hasCargoInsurance =
          (widget.vehicleData!['has_cargo_insurance'] == 1 ||
          widget.vehicleData!['has_cargo_insurance'] == true);

      // Certificate URLs
      _hazmatCertificateUrl = widget.vehicleData!['hazmat_certificate_url'];
      _cargoInsuranceCertificateUrl =
          widget.vehicleData!['cargo_insurance_certificate_url'];

      print(
        '🍔 Food Transport data loaded - isFoodSafe: $_isFoodSafe, hasHazmat: $_hasHazmatCertification, hasInsurance: $_hasCargoInsurance',
      );

      // Average Fuel Consumption
      _averageFuelConsumptionController.text =
          widget.vehicleData!['average_fuel_consumption']?.toString() ?? AppLocalizations.of(context)!.tr('');
      _fuelConsumptionUnit =
          widget.vehicleData!['fuel_consumption_unit'] ?? AppLocalizations.of(context)!.tr('MPG');

      print(
        '⛽ Fuel consumption loaded: ${_averageFuelConsumptionController.text} $_fuelConsumptionUnit',
      );

      // Load Sectional Loading data (always enabled - mandatory feature)
      // Load number of sections
      final numberOfSections = widget.vehicleData!['number_of_sections'];
      if (numberOfSections != null && numberOfSections > 1) {
        // Create sections based on saved number
        _vehicleSections = List.generate(
          numberOfSections,
          (index) => {
            'name': 'Section ${index + 1}',
            'percentage': (100 / numberOfSections).round(),
          },
        );
      }

      if (widget.vehicleData!['vehicle_sections'] != null) {
        try {
          final sectionsData = widget.vehicleData!['vehicle_sections'];
          if (sectionsData is List) {
            _vehicleSections = List<Map<String, dynamic>>.from(
              sectionsData.map((s) => Map<String, dynamic>.from(s)),
            );
          } else if (sectionsData is String && sectionsData.isNotEmpty) {
            // Parse JSON string if stored as string
            final decoded = json.decode(sectionsData);
            if (decoded is List) {
              _vehicleSections = List<Map<String, dynamic>>.from(
                decoded.map((s) => Map<String, dynamic>.from(s)),
              );
            }
          }
          print('📦 Vehicle sections loaded: $_vehicleSections');
        } catch (e) {
          print('⚠️ Error loading vehicle sections: $e');
          _vehicleSections = [];
        }
      }

      // Initialize default sections if none exist
      if (_vehicleSections.isEmpty) {
        _initializeDefaultSections();
      }

      print('📦 Sectional Loading - sections: ${_vehicleSections.length}');

      // Load country/region from vehicle data
      String vehicleCountry = widget.vehicleData!['country'] ?? AppLocalizations.of(context)!.tr('');
      if (vehicleCountry.isNotEmpty) {
        if (vehicleCountry == 'United States') {
          _selectedRegion = 'USA';
        } else if (vehicleCountry == 'Canada') {
          _selectedRegion = 'CA';
        } else if (vehicleCountry == 'Mexico') {
          _selectedRegion = 'MX';
        } else if (vehicleCountry == 'Russia') {
          _selectedRegion = 'RU';
        } else {
          // EU country — find the country code
          _selectedRegion = 'DE'; // Default to Germany
          for (var entry in _euCountries.entries) {
            if (vehicleCountry.contains(entry.value)) {
              _selectedRegion = entry.key;
              break;
            }
          }
        }
      } else {
        // Fallback to user data
        String userCountry = widget.userData?['country'] ??
          (AppLocalizations.of(context)?.unitedStates ?? AppLocalizations.of(context)!.tr(''));
        _selectedRegion = userCountry == (AppLocalizations.of(context)?.unitedStates ?? AppLocalizations.of(context)!.tr('')) ? 'USA' : 'DE';
      }

      // Load license plate
      _licensePlateController.text = savedLicensePlate;
      print(
        '🚗 License plate loaded: "$savedLicensePlate" for region: "$_selectedRegion"',
      );

      print(
        '🌍 Region loaded - Vehicle: "$vehicleCountry", Selected: "$_selectedRegion"',
      );
    } else {
      // Get country from user data for new vehicle
        String country = widget.userData?['country'] ??
          (AppLocalizations.of(context)?.unitedStates ?? AppLocalizations.of(context)!.tr(''));
        _selectedRegion = country == (AppLocalizations.of(context)?.unitedStates ?? AppLocalizations.of(context)!.tr('')) ? 'USA' : 'DE';

      // Initialize default sections for new vehicle (mandatory feature)
      _initializeDefaultSections();

      print(
        '🌍 Region for new vehicle - User: "$country", Selected: "$_selectedRegion"',
      );
    }
  }

  @override
  void dispose() {
    _countrySlideController.dispose();
    _yearController.dispose();
    _licensePlateController.dispose();
    _vinController.dispose();
    _cargoCapacityController.dispose();
    _payloadCapacityController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _minTemperatureController.dispose();
    _maxTemperatureController.dispose();
    _averageFuelConsumptionController.dispose();
    super.dispose();
  }

  // Take License Plate Photo
  Future<void> _takeLicensePlatePhoto(String position) async {
    XFile? photo;

    if (Platform.isMacOS) {
      // macOS: use file picker (no camera)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
      if (result != null && result.files.single.path != null) {
        photo = XFile(result.files.single.path!);
      }
    } else {
      final picker = ImagePicker();
      photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 90,
      );
    }

    if (photo != null) {
      // ✅ Show preview immediately with local file path
      setState(() {
        if (position == 'front') {
          _frontLicensePlatePhoto = photo!.path;
        } else {
          _rearLicensePlatePhoto = photo!.path;
        }
      });
      HapticFeedback.mediumImpact();

      // Try to upload to server in background
      TopNotification.show(
        context,
        message:
            'Uploading ${position == 'front' ? 'front' : 'rear'} license plate photo...',
        type: NotificationType.info,
      );

      final String? uploadedUrl = await _uploadDocumentToServer(
        File(photo.path),
        'license_plate_$position',
      );

      if (uploadedUrl != null) {
        // Replace local path with server URL
        setState(() {
          if (position == 'front') {
            _frontLicensePlatePhoto = uploadedUrl;
          } else {
            _rearLicensePlatePhoto = uploadedUrl;
          }
        });
        TopNotification.success(
          context,
          '${position == 'front' ? (AppLocalizations.of(context)?.front ?? AppLocalizations.of(context)!.tr('')) : (AppLocalizations.of(context)?.rear ?? AppLocalizations.of(context)!.tr(''))} ${AppLocalizations.of(context)?.licensePlatePhotoUploadedSuccessfully ?? AppLocalizations.of(context)!.tr('')}',
        );
        print('📸 License plate photo uploaded: $uploadedUrl');
      } else {
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.photoSavedLocallyServerUnavailable ?? AppLocalizations.of(context)!.tr(''),
          type: NotificationType.info,
        );
      }
    }
  }

  // Upload document image to server (Step 2)
  Future<String?> _uploadDocumentToServer(
    File imageFile,
    String documentType,
  ) async {
    try {
      print('📤 Uploading $documentType document to server...');

      final String baseUrl = ApiConfig.baseUrl;
      final uri = Uri.parse('$baseUrl/api/documents/upload-document');

      final username =
          widget.userData?['username'] ??
          widget.userData?['userId'] ?? AppLocalizations.of(context)!.tr('unknown');

      var request = http.MultipartRequest('POST', uri);
      request.fields['username'] = username;
      request.fields['documentType'] = documentType;

      var fileStream = http.ByteStream(imageFile.openRead());
      var fileLength = await imageFile.length();

      String filename = imageFile.path.split('/').last;
      if (!filename.toLowerCase().endsWith('.jpg') &&
          !filename.toLowerCase().endsWith('.jpeg') &&
          !filename.toLowerCase().endsWith('.png')) {
        filename = '$filename.jpg';
      }

      var multipartFile = http.MultipartFile(
        'image',
        fileStream,
        fileLength,
        filename: filename,
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);

      print('📤 Sending upload request...');

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print('📥 Upload response status: ${response.statusCode}');
      print('📥 Upload response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['success'] == true && responseData['data'] != null) {
          final String imageUrl = responseData['data']['url'];
          print('✅ Document uploaded successfully!');
          print('🌐 Document URL: $imageUrl');

          return imageUrl;
        }
      }

      print('❌ Upload failed: ${response.body}');
      return null;
    } catch (e) {
      print('❌ Upload error: $e');
      return null;
    }
  }

  /// Shows Camera / Gallery picker sheet on mobile (iOS/Android).
  /// Returns null when the user cancels. On macOS, returns null — callers
  /// must use FilePicker directly.
  Future<XFile?> _pickImageMobile({int imageQuality = 85}) async {
    if (Platform.isMacOS) return null;
    final picker = ImagePicker();
    final isLight =
        Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final fg = isLight ? Colors.black : Colors.white;
    final ImageSource? source = await TradeRepublicBottomSheet.show<ImageSource>(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)?.selectImageSource ?? AppLocalizations.of(context)!.tr('Select Image Source'),
            style: TextStyle(
              color: fg,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(CupertinoIcons.camera),
            title: Text(AppLocalizations.of(context)?.camera ?? AppLocalizations.of(context)!.tr('Camera')),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(CupertinoIcons.photo),
            title: Text(AppLocalizations.of(context)?.gallery ?? AppLocalizations.of(context)!.tr('Gallery')),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(CupertinoIcons.xmark_circle),
            title: Text(AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel')),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    if (source == null) return null;
    return picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: imageQuality,
    );
  }

  // Capture vehicle registration document
  Future<void> _captureVehicleRegistration() async {
    XFile? pickedFile;

    if (Platform.isMacOS) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (result != null && result.files.single.path != null) {
        pickedFile = XFile(result.files.single.path!);
      }
    } else {
      pickedFile = await _pickImageMobile(imageQuality: 90);
    }

    if (pickedFile != null) {
      setState(() {
        _vehicleRegistrationImage = File(pickedFile!.path);
      });

      TopNotification.show(
        context,
        message:
            AppLocalizations.of(context)?.uploadingVehicleRegistration ?? AppLocalizations.of(context)!.tr('Uploading vehicle registration...'),
        type: NotificationType.info,
      );

      final String? uploadedUrl = await _uploadDocumentToServer(
        File(pickedFile.path),
        'vehicle_registration',
      );

      if (uploadedUrl != null) {
        setState(() {
          _vehicleRegistrationImageUrl = uploadedUrl;
        });

        TopNotification.show(
          context,
          message:
              AppLocalizations.of(context)?.vehicleRegUploadedSuccess ?? AppLocalizations.of(context)!.tr('Vehicle registration uploaded successfully!'),
          type: NotificationType.success,
        );

        print('✅ Vehicle registration uploaded: $uploadedUrl');
      } else {
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.photoSavedLocallyServerUnavailable ?? AppLocalizations.of(context)!.tr(''),
          type: NotificationType.info,
        );
      }
    }
  }

  // Capture insurance proof document
  Future<void> _captureInsuranceProof() async {
    XFile? pickedFile;

    if (Platform.isMacOS) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (result != null && result.files.single.path != null) {
        pickedFile = XFile(result.files.single.path!);
      }
    } else {
      // Open camera directly — no picker sheet
      final picker = ImagePicker();
      pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 90,
      );
    }

    if (pickedFile != null) {
      setState(() {
        _insuranceProofImage = File(pickedFile!.path);
      });

      TopNotification.show(
        context,
        message:
            AppLocalizations.of(context)?.uploadingInsuranceProof ?? AppLocalizations.of(context)!.tr('Uploading insurance proof...'),
        type: NotificationType.info,
      );

      final String? uploadedUrl = await _uploadDocumentToServer(
        File(pickedFile.path),
        'insurance_proof',
      );

      if (uploadedUrl != null) {
        setState(() {
          _insuranceProofImageUrl = uploadedUrl;
        });

        TopNotification.show(
          context,
          message:
              AppLocalizations.of(context)?.insuranceProofUploadedSuccess ?? AppLocalizations.of(context)!.tr('Insurance proof uploaded successfully!'),
          type: NotificationType.success,
        );

        print('✅ Insurance proof uploaded: $uploadedUrl');
      } else {
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.photoSavedLocallyServerUnavailable ?? AppLocalizations.of(context)!.tr(''),
          type: NotificationType.info,
        );
      }
    }
  }

  // === NEW: Food Transport Document Uploads ===

  // Capture Hazmat Certificate
  Future<void> _captureHazmatCertificate() async {
    XFile? pickedFile;

    if (Platform.isMacOS) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (result != null && result.files.single.path != null) {
        pickedFile = XFile(result.files.single.path!);
      }
    } else {
      pickedFile = await _pickImageMobile();
    }

    if (pickedFile != null) {
      setState(() {
        _hazmatCertificateImage = File(pickedFile!.path);
      });

      TopNotification.show(
        context,
        message:
            AppLocalizations.of(context)?.uploadingHazmatCert ?? AppLocalizations.of(context)!.tr('Uploading hazmat certificate...'),
        type: NotificationType.info,
      );

      final String? uploadedUrl = await _uploadDocumentToServer(
        File(pickedFile.path),
        'hazmat_certificate',
      );

      if (uploadedUrl != null) {
        setState(() {
          _hazmatCertificateUrl = uploadedUrl;
        });

        TopNotification.show(
          context,
          message:
              AppLocalizations.of(context)?.hazmatCertUploaded ?? AppLocalizations.of(context)!.tr('Hazmat certificate uploaded!'),
          type: NotificationType.success,
        );
      } else {
        // Keep local file for preview
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.photoSavedLocallyServerUnavailable ?? AppLocalizations.of(context)!.tr(''),
          type: NotificationType.info,
        );
      }
    }
  }

  // Capture Cargo Insurance Certificate
  Future<void> _captureCargoInsurance() async {
    XFile? pickedFile;

    if (Platform.isMacOS) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (result != null && result.files.single.path != null) {
        pickedFile = XFile(result.files.single.path!);
      }
    } else {
      pickedFile = await _pickImageMobile();
    }

    if (pickedFile != null) {
      setState(() {
        _cargoInsuranceCertificateImage = File(pickedFile!.path);
      });

      TopNotification.show(
        context,
        message:
            AppLocalizations.of(context)?.uploadingCargoInsurance ?? AppLocalizations.of(context)!.tr('Uploading cargo insurance...'),
        type: NotificationType.info,
      );

      final String? uploadedUrl = await _uploadDocumentToServer(
        File(pickedFile.path),
        'cargo_insurance',
      );

      if (uploadedUrl != null) {
        setState(() {
          _cargoInsuranceCertificateUrl = uploadedUrl;
        });

        TopNotification.show(
          context,
          message:
              AppLocalizations.of(context)?.cargoInsuranceUploaded ?? AppLocalizations.of(context)!.tr('Cargo insurance uploaded!'),
          type: NotificationType.success,
        );
      } else {
        // Keep local file for preview
        TopNotification.show(
          context,
          message: AppLocalizations.of(context)?.photoSavedLocallyServerUnavailable ?? AppLocalizations.of(context)!.tr(''),
          type: NotificationType.info,
        );
      }
    }
  }

  // Helper methods to determine which fields to show
  bool _requiresDimensions() {
    if (_selectedVehicleType == null) return false;
    // Show dimensions for box trucks, vans, refrigerated units, dry goods
    final dimensionTypes = [
      'Refrigerated Truck',
      'Fresh Produce Van',
      'Frozen Transport',
      'Bakery Truck',
      'Beverage Carrier',
      'Meat Transport',
      'Dry Goods Van',
      'Specialty Food Transport',
      'Temperature Controlled',
    ];
    return dimensionTypes.contains(_selectedVehicleType);
  }

  bool _requiresTemperature() {
    if (_selectedVehicleType == null) return false;
    // Show temperature for all refrigerated/temperature-controlled vehicles
    final tempTypes = [
      'Refrigerated Truck',
      'Temperature Controlled',
      'Fresh Produce Van',
      'Frozen Transport',
      'Meat Transport',
    ];
    return tempTypes.contains(_selectedVehicleType);
  }

  Future<void> _nextStep() async {
    if (_currentStep == 1) {
      // Validate Step 1 - Basic Info only
      bool makeModelSelected = _selectedMake != null && _selectedModel != null;
      bool vehicleTypeSelected = _selectedVehicleType != null;
      bool yearValid = _yearController.text.isNotEmpty;

      if (!makeModelSelected) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseSelectVehicleMakeAndModel ?? AppLocalizations.of(context)!.tr('Please select vehicle make and model'),
        );
        return;
      }

      if (!yearValid) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseEnterVehicleYear ?? AppLocalizations.of(context)!.tr('Please enter the vehicle year'),
        );
        return;
      }

      if (!vehicleTypeSelected) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseSelectVehicleType ?? AppLocalizations.of(context)!.tr('Please select vehicle type'),
        );
        return;
      }

      // Move to Step 2
      setState(() {
        _currentStep = 2;
      });
    } else if (_currentStep == 2) {
      // Validate Step 2 - License & Details
      bool photosProvided =
          _frontLicensePlatePhoto != null && _rearLicensePlatePhoto != null;

      if (!photosProvided) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseTakePhotosLicensePlates ?? AppLocalizations.of(context)!.tr('Please take photos of the front and rear license plates'),
        );
        return;
      }

      if (_vinController.text.trim().isEmpty) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseEnterVin ?? AppLocalizations.of(context)!.tr('Please enter the VIN'),
        );
        return;
      }

      // Only require fuel consumption for NEW vehicles — editing allows it to be empty
      final isEditing = widget.vehicleData != null;
      if (!isEditing && _averageFuelConsumptionController.text.trim().isEmpty) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseEnterFuelEconomy ?? AppLocalizations.of(context)!.tr('Please enter fuel economy'),
        );
        return;
      }

      // Move to Step 3
      setState(() {
        _currentStep = 3;
      });
    } else if (_currentStep == 3) {
      // Validate Step 3 - Capacity
      if (_cargoCapacityController.text.trim().isEmpty) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseEnterCargoCapacity ?? AppLocalizations.of(context)!.tr('Please enter cargo capacity'),
        );
        return;
      }

      if (_payloadCapacityController.text.trim().isEmpty) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseEnterPayloadCapacity ?? AppLocalizations.of(context)!.tr('Please enter payload capacity'),
        );
        return;
      }

      // Additional validation for dimension fields if required
      if (_requiresDimensions()) {
        if (_lengthController.text.trim().isEmpty ||
            _widthController.text.trim().isEmpty ||
            _heightController.text.trim().isEmpty) {
          _showErrorMessage(
            AppLocalizations.of(context)?.pleaseFillAllCargoDimensions ?? AppLocalizations.of(context)!.tr('Please fill in all cargo dimensions'),
          );
          return;
        }
      }

      // Temperature sliders always carry a value – no isEmpty check needed.

      // Move to Step 4
      setState(() {
        _currentStep = 4;
      });
    } else if (_currentStep == 4) {
      // Validate Step 4 - Documents and save
      // Check if vehicle registration exists (newly uploaded OR already in database)
      final bool hasVehicleRegistration =
          _vehicleRegistrationImage != null ||
          _vehicleRegistrationImageUrl != null ||
          (widget.vehicleData?['vehicle_registration_image_url'] != null &&
              widget.vehicleData!['vehicle_registration_image_url'].isNotEmpty);

      final bool hasInsuranceProof =
          _insuranceProofImage != null ||
          _insuranceProofImageUrl != null ||
          (widget.vehicleData?['insurance_proof_image_url'] != null &&
              widget.vehicleData!['insurance_proof_image_url'].isNotEmpty);

      if (!hasVehicleRegistration) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseCaptureVehicleRegistration ?? AppLocalizations.of(context)!.tr('Please capture your vehicle registration'),
        );
        return;
      }
      if (!hasInsuranceProof) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseCaptureInsuranceProof ?? AppLocalizations.of(context)!.tr('Please capture your insurance proof'),
        );
        return;
      }

      await _validateAndSave();
    }
  }

  void _previousStep() {
    if (_currentStep > 1) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _validateAndSave() async {
    print('🚗 Validating vehicle data...');

    // Validate legal agreements (only for Step 4 - final submission)
    if (_currentStep == 4) {
      if (!_acceptTerms) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseAcceptTermsAndPrivacy ?? AppLocalizations.of(context)!.tr('Please accept the Terms & Conditions and Privacy Policy'),
        );
        return;
      }
      if (!_confirmDataAccuracy) {
        _showErrorMessage(
          AppLocalizations.of(context)?.pleaseConfirmDataAccuracy ?? AppLocalizations.of(context)!.tr('Please confirm the accuracy of the provided data'),
        );
        return;
      }
    }

    print('🚗 ✅ ALL VALIDATIONS PASSED!');

    // ── Retry upload for any local files that failed to reach the server ─────
    // This happens when the background upload after capture failed (network
    // timeout, server error, etc). Without this, the URL stays null and the
    // DB stores NULL even though the user DID add the photo.
    if (mounted) setState(() => _isSaving = true);

    if (_vehicleRegistrationImage != null &&
        (_vehicleRegistrationImageUrl == null ||
            _vehicleRegistrationImageUrl!.isEmpty)) {
      print('🔁 Retrying vehicle registration upload...');
      _vehicleRegistrationImageUrl = await _uploadDocumentToServer(
        _vehicleRegistrationImage!, 'vehicle_registration');
    }
    if (_insuranceProofImage != null &&
        (_insuranceProofImageUrl == null || _insuranceProofImageUrl!.isEmpty)) {
      print('🔁 Retrying insurance proof upload...');
      _insuranceProofImageUrl = await _uploadDocumentToServer(
        _insuranceProofImage!, 'insurance_proof');
    }
    // Retry license plate photos stored as local paths
    if (_frontLicensePlatePhoto != null &&
        !_frontLicensePlatePhoto!.startsWith('http')) {
      print('🔁 Retrying front license plate upload...');
      final url = await _uploadDocumentToServer(
          File(_frontLicensePlatePhoto!), 'license_plate_front');
      if (url != null) _frontLicensePlatePhoto = url;
    }
    if (_rearLicensePlatePhoto != null &&
        !_rearLicensePlatePhoto!.startsWith('http')) {
      print('🔁 Retrying rear license plate upload...');
      final url = await _uploadDocumentToServer(
          File(_rearLicensePlatePhoto!), 'license_plate_rear');
      if (url != null) _rearLicensePlatePhoto = url;
    }

    if (mounted) setState(() => _isSaving = false);

    // DEBUG: Print Step 2 document URLs
    print('📄 Step 2 Document URLs in _validateAndSave():');
    print('   Registration URL: $_vehicleRegistrationImageUrl');
    print('   Insurance URL: $_insuranceProofImageUrl');

    // Save vehicle data
    final vehicleData = {
      'vehicleModel': _selectedModel!,
      'vehicleMake': _selectedMake!,
      'vehicleType': _selectedVehicleType!,
      'vehicleYear': _yearController.text,
      'licensePlate': _licensePlateController.text,
      'vin': _vinController.text,
      'cargoCapacity': GermanNumberFormatter.parseGermanNumber(
        _cargoCapacityController.text,
      ).toString(),
      'payloadCapacity': GermanNumberFormatter.parseGermanNumber(
        _payloadCapacityController.text,
      ).toString(),
      'cargoUnit': _cargoUnit,
      'payloadUnit': _payloadUnit,
      'usaState': _selectedUSAState,
      'country': () {
          switch (_selectedRegion) {
            case 'USA': return 'United States';
            case 'CA': return 'Canada';
            case 'MX': return 'Mexico';
            case 'RU': return 'Russia';
            default: return _euCountries[_selectedRegion] ?? _selectedRegion;
          }
        }(),
      'euCountryCode': _selectedRegion != 'USA' ? _selectedRegion : null,
      'frontLicensePlatePhoto': _frontLicensePlatePhoto,
      'rearLicensePlatePhoto': _rearLicensePlatePhoto,
      'vehicleRegistrationImageUrl': _vehicleRegistrationImageUrl,
      'insuranceProofImageUrl': _insuranceProofImageUrl,
      'fullVehicle': '${_yearController.text} $_selectedMake $_selectedModel',
      // Food Transport - Dimensions
      'cargoLength': _lengthController.text.isNotEmpty
          ? _lengthController.text
          : null,
      'cargoWidth': _widthController.text.isNotEmpty
          ? _widthController.text
          : null,
      'cargoHeight': _heightController.text.isNotEmpty
          ? _heightController.text
          : null,
      'dimensionUnit': _dimensionUnit,
      // Food Transport - Temperature
      'minTemperature': _minTemperatureController.text.isNotEmpty
          ? _minTemperatureController.text
          : null,
      'maxTemperature': _maxTemperatureController.text.isNotEmpty
          ? _maxTemperatureController.text
          : null,
      'temperatureUnit': _temperatureUnit,
      // Food Transport - Certifications
      'isFoodSafe': _isFoodSafe ? 1 : 0,
      'hasHazmatCertification': _hasHazmatCertification ? 1 : 0,
      'hasCargoInsurance': _hasCargoInsurance ? 1 : 0,
      // Food Transport - Documents
      'hazmatCertificateUrl': _hazmatCertificateUrl,
      'cargoInsuranceCertificateUrl': _cargoInsuranceCertificateUrl,
      // Average Fuel Consumption — parse to plain double to avoid locale/formatting issues
      'averageFuelConsumption': () {
        final raw = _averageFuelConsumptionController.text.trim();
        if (raw.isEmpty) return null;
        // Strip any thousand-separator commas (e.g. "1,234.56" → "1234.56")
        final cleaned = raw.replaceAll(',', '');
        final parsed = double.tryParse(cleaned);
        if (parsed == null || parsed <= 0) return null;
        return parsed.toStringAsFixed(2); // always "xxx.xx" for MySQL decimal(5,2)
      }(),
      'fuelConsumptionUnit': _fuelConsumptionUnit,
      // Sectional Loading (MANDATORY - always enabled)
      'sectionalLoadingEnabled': 1,
      'numberOfSections': _vehicleSections.length,
      'vehicleSections': _vehicleSections.isNotEmpty ? _vehicleSections : null,
    };

    // DEBUG: Verify document URLs are in vehicleData
    print('📄 Document URLs in vehicleData object:');
    print(
      '   vehicleRegistrationImageUrl: ${vehicleData['vehicleRegistrationImageUrl']}',
    );
    print(
      '   insuranceProofImageUrl: ${vehicleData['insuranceProofImageUrl']}',
    );

    // Add vehicle ID if editing existing vehicle (convert to string)
    if (widget.vehicleData != null) {
      final vehicleId =
          widget.vehicleData!['id'] ?? widget.vehicleData!['vehicle_id'];
      vehicleData['id'] = vehicleId?.toString();
    }

    print('🚗 Final vehicle data to save: $vehicleData');

    // Close modal first
    Navigator.pop(context);

    // Call save callback - notification will be shown in parent context
    widget.onVehicleAdded(vehicleData);
  }

  void _showErrorMessage(String message) {
    TopNotification.error(context, message);
  }

  // Build document capture widget - Separate containers for button and preview
  Widget _buildDocumentCapture({
    required String title,
    required String subtitle,
    required File? image,
    required String? imageUrl,
    required VoidCallback onTap,
    required bool isLight,
  }) {
    bool hasImage = image != null || (imageUrl != null && imageUrl.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Upload Button - Always visible
        TradeRepublicTap(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: isLight
                  ? (hasImage ? Colors.green.withOpacity(0.15) : Colors.white)
                  : (hasImage ? Colors.green.withOpacity(0.25) : Colors.black),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasImage
                        ? Colors.green.withOpacity(0.2)
                        : (isLight
                              ? Colors.black.withOpacity(0.2)
                              : Colors.black.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Icon(
                    hasImage
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.camera,
                    color: hasImage
                        ? Colors.green
                        : (isLight ? Colors.black : Colors.white),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasImage
                            ? (AppLocalizations.of(context)?.tapToRetakePhoto ?? AppLocalizations.of(context)!.tr(''))
                            : subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  color: isLight ? Colors.white : Colors.black,
                ),
              ],
            ),
          ),
        ),

        // Image Preview Container - Only shown when image exists
        if (hasImage) ...[
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          TradeRepublicTap(
            onTap: () =>
                _showFullScreenImage(context, image, imageUrl, isLight),
            child: Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Display image from File or URL
                    if (image != null)
                      Image.file(image, fit: BoxFit.cover)
                    else if (imageUrl != null && imageUrl.isNotEmpty)
                      Image.network(
                        ApiConfig.getImageUrl(imageUrl),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CultiooLoadingIndicator(),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  CupertinoIcons.xmark_circle,
                                  color: Colors.red,
                                  size: 40,
                                ),
                                const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.failedToLoadImage ?? AppLocalizations.of(context)!.tr('Failed to load image'),
                                  style: TextStyle(
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                    // Tap to enlarge overlay
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.zoom_in,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              AppLocalizations.of(context)?.tapToEnlarge ?? AppLocalizations.of(context)!.tr('Tap to enlarge'),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Show full screen image viewer
  void _showFullScreenImage(
    BuildContext context,
    File? imageFile,
    String? imageUrl,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      backgroundColor: Colors.black,
      enableDrag: true,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Stack(
          children: [
            // Full screen image
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: imageFile != null
                    ? Image.file(imageFile)
                    : (imageUrl != null && imageUrl.isNotEmpty)
                    ? Image.network(
                        ApiConfig.getImageUrl(imageUrl),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CultiooLoadingIndicator(),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  CupertinoIcons.xmark_circle,
                                  color: Colors.white,
                                  size: 48,
                                ),
                                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                                Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.failedToLoadImage ?? AppLocalizations.of(context)!.tr('Failed to load image'),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : Container(),
              ),
            ),

            // Close button
            Positioned(
              top: 40,
              right: 20,
              child: TradeRepublicTap(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.xmark,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),

            // Pinch to zoom hint
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Text(
                    AppLocalizations.of(context)?.pinchToZoomDragToMove ?? AppLocalizations.of(context)!.tr('Pinch to zoom • Drag to move'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.vehicleData != null;
    final isLight = widget.isLight;
    final appSettings = context.watch<AppSettings>();
    final isEuropeanFormat = appSettings.effectiveNumberFormat == '1.234,56';
    final capacityHintText = isEuropeanFormat
        ? 'z.B. 1.234,56'
        : 'e.g., 1,234.56';

    return SizedBox(
      height: MediaQuery.of(context).size.height * 1,
      child: Stack(
        children: [
          Column(
            children: [
              // Main Content
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        0,
                        24,
                        0,
                        140,
                      ), // Extra bottom padding for floating button
                      child: Column(
                        children: [
                          // Header - Compact and Clean
                          Center(
                            child: Column(
                              children: [
                                // Step Number Badge
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: isLight ? Colors.black : Colors.white,
                                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                  ),
                                  child: SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: Center(
                                      child: Text(
                                        '$_currentStep',
                                        style: TextStyle(
                                          color: isLight ? Colors.white : Colors.black,
                                          fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                                // Step Title - Dynamic
                                Text(
                                  _getStepTitle(),
                                  style: TextStyle(
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // Step Subtitle
                                Text(
                                  _getStepSubtitle(),
                                  style: TextStyle(
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.5),
                                    fontSize: 15,
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // Progress Indicator - 4 Steps
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (int i = 1; i <= 4; i++) ...[
                                      _buildStepDot(i, isLight),
                                      if (i < 4)
                                        ColoredBox(
                                          color: _currentStep > i
                                              ? (isLight ? Colors.black : Colors.white)
                                              : (isLight ? Colors.white : Colors.black),
                                          child: const SizedBox(width: 24, height: 2),
                                        ),
                                    ],
                                  ],
                                ),

                                const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                                // Step Labels
                                Text(
                                  '${AppLocalizations.of(context)?.stepXOfY ?? AppLocalizations.of(context)!.tr('Step')} $_currentStep ${AppLocalizations.of(context)?.ofLabel ?? AppLocalizations.of(context)!.tr('of')} 4',
                                  style: TextStyle(
                                    color: isLight
                                        ? Colors.white
                                        : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                          // === STEP 1: BASIC INFO ===
                          if (_currentStep == 1) ...[
                            // Make Selector
                            _buildModernDropdown(
                              label:
                                  AppLocalizations.of(context)?.vehicleMake ?? AppLocalizations.of(context)!.tr('Vehicle Make'),
                              value: _selectedMake,
                              icon: CupertinoIcons.car,
                              isLight: isLight,
                              onTap: () => _showMakeSelector(isLight),
                            ),

                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                            // Model Selector
                            _buildModernDropdown(
                              label:
                                  AppLocalizations.of(context)?.vehicleModel ?? AppLocalizations.of(context)!.tr('Vehicle Model'),
                              value: _selectedModel,
                              icon: CupertinoIcons.car,
                              isLight: isLight,
                              onTap: _selectedMake != null
                                  ? () => _showModelSelector(isLight)
                                  : null,
                            ),

                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                            // Year Field
                            _buildModernTextField(
                              controller: _yearController,
                              label:
                                  AppLocalizations.of(context)?.year ?? AppLocalizations.of(context)!.tr('Year'),
                              icon: CupertinoIcons.calendar,
                              isLight: isLight,
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value?.isEmpty ?? true) return 'Required';
                                final year = int.tryParse(value!);
                                if (year == null ||
                                    year < 1990 ||
                                    year > DateTime.now().year + 1) {
                                  return AppLocalizations.of(
                                        context,
                                      )?.enterValidYear ?? AppLocalizations.of(context)!.tr('Enter valid year');
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                            // Vehicle Type Selector
                            _buildModernDropdown(
                              label:
                                  AppLocalizations.of(context)?.vehicleType ?? AppLocalizations.of(context)!.tr('Vehicle Type'),
                              value: _selectedVehicleType,
                              icon: CupertinoIcons.cube_box,
                              isLight: isLight,
                              onTap: () => _showVehicleTypeSelector(isLight),
                            ),

                            const SizedBox(height: 80),
                          ], // End of Step 1
                          // === STEP 2: LICENSE & DETAILS ===
                          if (_currentStep == 2) ...[
                            // LICENSE PLATE SECTION
                            _buildSectionHeader(
                              AppLocalizations.of(context)?.licensePlate ?? AppLocalizations.of(context)!.tr('License Plate'),
                              isLight,
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                            // License Plate Field with Visual Design
                            _buildModernLicensePlateField(isLight),

                            const SizedBox(height: 32),

                            // VIN Field
                            _buildModernTextField(
                              controller: _vinController,
                              label:
                                  AppLocalizations.of(
                                    context,
                                  )?.vinVehicleIdentificationNumber ?? AppLocalizations.of(context)!.tr('VIN (Vehicle Identification Number)'),
                              icon: CupertinoIcons.ticket,
                              isLight: isLight,
                              textCapitalization: TextCapitalization.characters,
                              maxLength: 17,
                              validator: (value) {
                                if (value?.isEmpty ?? true) {
                                  return AppLocalizations.of(
                                        context,
                                      )?.vinRequired ?? AppLocalizations.of(context)!.tr('VIN is required');
                                }
                                final cleanVin = value!.replaceAll(
                                  RegExp(r'[^A-Z0-9]'),
                                  '',
                                );
                                if (cleanVin.length != 17) {
                                  return AppLocalizations.of(
                                        context,
                                      )?.vinMustBe17Characters ?? AppLocalizations.of(context)!.tr('VIN must be exactly 17 characters');
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 32),

                            // Fuel Economy Field in Step 2
                            _buildSectionHeader(
                              widget.vehicleData != null
                                  ? '${AppLocalizations.of(context)?.fuelEconomy ?? AppLocalizations.of(context)!.tr('Fuel Economy')} (optional)'
                                  : AppLocalizations.of(context)?.fuelEconomy ?? AppLocalizations.of(context)!.tr('Fuel Economy'),
                              isLight,
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: isLight ? Colors.white : Colors.black,
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                              ),
                              child: Padding(
                                padding: DesktopAppWrapper.getPagePadding(),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TradeRepublicTextField(
                                        useFormField: true,
                                        filled: false,
                                        controller: _averageFuelConsumptionController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        inputFormatters: [FuelEconomyFormatter()],
                                        style: TextStyle(
                                          color: isLight ? Colors.black : Colors.white,
                                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        hintText: AppLocalizations.of(context)?.egWeight ?? AppLocalizations.of(context)!.tr('e.g., 25.5'),
                                      ),
                                    ),
                                    _buildUnitChip(
                                      label: _fuelConsumptionUnit,
                                      isLight: isLight,
                                      onTap: () => _showUnitSelector(
                                        title: AppLocalizations.of(context)?.fuelEconomyUnit ?? AppLocalizations.of(context)!.tr('Fuel Economy Unit'),
                                        options: ['MPG', 'L/100km'],
                                        selectedOption: _fuelConsumptionUnit,
                                        onOptionSelected: (unit) => setState(() => _fuelConsumptionUnit = unit),
                                        isLight: isLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 80),
                          ], // End of Step 2
                          // === STEP 3: CAPACITY ===
                          if (_currentStep == 3) ...[
                            // Cargo Capacity Field
                            _buildSectionHeader(
                              AppLocalizations.of(context)?.cargoCapacity ?? AppLocalizations.of(context)!.tr('Cargo Capacity'),
                              isLight,
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: isLight ? Colors.white : Colors.black,
                                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                ),
                                child: Padding(
                                  padding: DesktopAppWrapper.getPagePadding(),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TradeRepublicTextField(
                                          useFormField: true,
                                          filled: false,
                                          controller: _cargoCapacityController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [GermanNumberFormatter(appSettings)],
                                          style: TextStyle(
                                            color: isLight ? Colors.black : Colors.white,
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                            fontWeight: FontWeight.w500,
                                          ),
                                          hintText: capacityHintText,
                                        ),
                                      ),
                                      _buildUnitChip(
                                        label: _cargoUnit,
                                        isLight: isLight,
                                        onTap: () => _showUnitSelector(
                                          title: AppLocalizations.of(context)?.cargoUnit ?? AppLocalizations.of(context)!.tr('Cargo Unit'),
                                          options: ['ft³', 'm³'],
                                          selectedOption: _cargoUnit,
                                          onOptionSelected: (unit) => setState(() => _cargoUnit = unit),
                                          isLight: isLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                            // Payload Capacity Field
                            _buildSectionHeader(
                              AppLocalizations.of(context)?.payloadCapacity ?? AppLocalizations.of(context)!.tr('Payload Capacity'),
                              isLight,
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: isLight ? Colors.white : Colors.black,
                                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                ),
                                child: Padding(
                                  padding: DesktopAppWrapper.getPagePadding(),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TradeRepublicTextField(
                                          useFormField: true,
                                          filled: false,
                                          controller: _payloadCapacityController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [GermanNumberFormatter(appSettings)],
                                          style: TextStyle(
                                            color: isLight ? Colors.black : Colors.white,
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                            fontWeight: FontWeight.w500,
                                          ),
                                          hintText: capacityHintText,
                                        ),
                                      ),
                                      _buildUnitChip(
                                        label: _payloadUnit,
                                        isLight: isLight,
                                        onTap: () => _showUnitSelector(
                                          title: AppLocalizations.of(context)?.payloadUnit ?? AppLocalizations.of(context)!.tr('Payload Unit'),
                                          options: ['lbs', 'kg'],
                                          selectedOption: _payloadUnit,
                                          onOptionSelected: (unit) => setState(() => _payloadUnit = unit),
                                          isLight: isLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                            // Sectioned Loading Header
                            _buildSectionHeader(
                              AppLocalizations.of(context)?.sectionedLoading ?? AppLocalizations.of(context)!.tr('Sectioned Loading'),
                              isLight,
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            Text(
                              AppLocalizations.of(
                                    context,
                                  )?.divideCargAreaIntoSections ?? AppLocalizations.of(context)!.tr('Divide cargo area into sections for partial loads'),
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontSize: 13,
                              ),
                            ),

                            // Sections UI (always shown - mandatory)
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            _buildVehicleSectionsUI(isLight),

                            // Dimensions (if required)
                            if (_requiresDimensions()) ...[
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildSectionHeader(
                                      AppLocalizations.of(context)?.cargoDimensions ?? AppLocalizations.of(context)!.tr('Cargo Dimensions'),
                                      isLight,
                                    ),
                                  ),
                                  // Unit toggle — ft / m
                                  TradeRepublicSlider(
                                    labels: const ['ft', 'm'],
                                    selectedIndex: _dimensionUnit == 'ft' ? 0 : 1,
                                    height: 36,
                                    borderRadius: 12,
                                    onChanged: (i) => setState(() => _dimensionUnit = i == 0 ? 'ft' : 'm'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildModernTextField(
                                      controller: _lengthController,
                                      label: AppLocalizations.of(context)?.length ?? AppLocalizations.of(context)!.tr('Length'),
                                      icon: CupertinoIcons.arrow_left_right,
                                      isLight: isLight,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildModernTextField(
                                      controller: _widthController,
                                      label: AppLocalizations.of(context)?.width ?? AppLocalizations.of(context)!.tr('Width'),
                                      icon: CupertinoIcons.arrow_up_down,
                                      isLight: isLight,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                              _buildModernTextField(
                                controller: _heightController,
                                label: AppLocalizations.of(context)?.height ?? AppLocalizations.of(context)!.tr('Height'),
                                icon: CupertinoIcons.arrow_up_down_circle,
                                isLight: isLight,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ],

                            // Temperature (if required)
                            if (_requiresTemperature()) ...[
                              const SizedBox(height: 32),
                              _buildTemperatureRangeWidget(isLight),
                            ],

                            const SizedBox(height: 80),
                          ], // End of Step 3
                          // === STEP 4: DOCUMENTS ===
                          if (_currentStep == 4) ...[
                            // Vehicle Registration
                            _buildSectionHeader(
                              AppLocalizations.of(
                                    context,
                                  )?.vehicleRegistration ?? AppLocalizations.of(context)!.tr('Vehicle Registration'),
                              isLight,
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            _buildDocumentCapture(
                              title:
                                  AppLocalizations.of(
                                    context,
                                  )?.vehicleRegistration ?? AppLocalizations.of(context)!.tr('Vehicle Registration'),
                              subtitle:
                                  AppLocalizations.of(
                                    context,
                                  )?.captureYourVehicleRegistration ?? AppLocalizations.of(context)!.tr('Capture your vehicle registration'),
                              imageUrl: _vehicleRegistrationImageUrl,
                              image: _vehicleRegistrationImage,
                              isLight: isLight,
                              onTap: _captureVehicleRegistration,
                            ),

                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                            // Insurance Proof
                            _buildSectionHeader(
                              AppLocalizations.of(context)?.insuranceProof ?? AppLocalizations.of(context)!.tr('Insurance Proof'),
                              isLight,
                            ),
                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            _buildDocumentCapture(
                              title:
                                  AppLocalizations.of(
                                    context,
                                  )?.insuranceProof ??
                                  AppLocalizations.of(
                                    context,
                                  )?.insuranceProof ?? AppLocalizations.of(context)!.tr('Insurance Proof'),
                              subtitle:
                                  AppLocalizations.of(
                                    context,
                                  )?.captureYourInsuranceDocument ?? AppLocalizations.of(context)!.tr('Capture your insurance document'),
                              imageUrl: _insuranceProofImageUrl,
                              image: _insuranceProofImage,
                              isLight: isLight,
                              onTap: _captureInsuranceProof,
                            ),

                            const SizedBox(height: 32),

                            // Terms & Conditions
                            TradeRepublicTap(
                              onTap: () {
                                setState(() {
                                  _acceptTerms = !_acceptTerms;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: DesktopAppWrapper.getPagePadding(),
                                decoration: BoxDecoration(
                                  color: _acceptTerms
                                      ? (isLight ? Colors.black : Colors.white).withOpacity(0.05)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                ),
                                child: Row(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: _acceptTerms
                                            ? (isLight
                                                  ? Colors.black
                                                  : Colors.white)
                                            : (isLight ? Colors.black : Colors.white).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                      ),
                                      child: _acceptTerms
                                          ? Icon(
                                              CupertinoIcons.checkmark,
                                              size: 16,
                                              color: isLight
                                                  ? Colors.white
                                                  : Colors.black,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          text: 'I accept the ',
                                          style: TextStyle(
                                            color: isLight
                                                ? Colors.black
                                                : Colors.white,
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                          ),
                                          children: [
                                            TextSpan(
                                              text:
                                                  AppLocalizations.of(
                                                    context,
                                                  )?.termsConditions ?? AppLocalizations.of(context)!.tr('Terms & Conditions'),
                                              style: TextStyle(
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w600,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                              recognizer: TapGestureRecognizer()
                                                ..onTap = () async {
                                                  final url = Uri.parse(
                                                    'https://cultioo.com/us/us_legal_app#delvioo_terms',
                                                  );
                                                  if (await canLaunchUrl(url)) {
                                                    await launchUrl(
                                                      url,
                                                      mode: LaunchMode
                                                          .externalApplication,
                                                    );
                                                  }
                                                },
                                            ),
                                            TextSpan(text: ' and '),
                                            TextSpan(
                                              text:
                                                  AppLocalizations.of(
                                                    context,
                                                  )?.privacyPolicy ?? AppLocalizations.of(context)!.tr('Privacy Policy'),
                                              style: TextStyle(
                                                color: Colors.blue,
                                                fontWeight: FontWeight.w600,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                              recognizer: TapGestureRecognizer()
                                                ..onTap = () async {
                                                  final url = Uri.parse(
                                                    'https://cultioo.com/us/us_legal_app#delvioo_privacy',
                                                  );
                                                  if (await canLaunchUrl(url)) {
                                                    await launchUrl(
                                                      url,
                                                      mode: LaunchMode
                                                          .externalApplication,
                                                    );
                                                  }
                                                },
                                            ),
                                            TextSpan(text: '.'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                            // Data Accuracy Confirmation
                            TradeRepublicTap(
                              onTap: () {
                                setState(() {
                                  _confirmDataAccuracy = !_confirmDataAccuracy;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: DesktopAppWrapper.getPagePadding(),
                                decoration: BoxDecoration(
                                  color: _confirmDataAccuracy
                                      ? (isLight ? Colors.black : Colors.white).withOpacity(0.05)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                ),
                                child: Row(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: _confirmDataAccuracy
                                            ? (isLight
                                                  ? Colors.black
                                                  : Colors.white)
                                            : (isLight ? Colors.black : Colors.white).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                      ),
                                      child: _confirmDataAccuracy
                                          ? Icon(
                                              CupertinoIcons.checkmark,
                                              size: 16,
                                              color: isLight
                                                  ? Colors.white
                                                  : Colors.black,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        AppLocalizations.of(
                                              context,
                                            )?.iConfirmAllInformationIsAccurate ?? AppLocalizations.of(context)!.tr('I confirm all information is accurate'),
                                        style: TextStyle(
                                          color: isLight
                                              ? Colors.black
                                              : Colors.white,
                                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 80),
                          ], // End of Step 4
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Floating Navigation Buttons - Apple Style
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : Colors.black,
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                  children: [
                    // Back Button (only show if step > 1)
                    if (_currentStep > 1) ...[
                      Expanded(
                        child: TradeRepublicButton(
                          label: AppLocalizations.of(context)?.back ?? AppLocalizations.of(context)!.tr('Back'),
                          onPressed: _previousStep,
                          isSecondary: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],

                    // Continue/Save Button
                    Expanded(
                      child: TradeRepublicButton(
                        label: _currentStep < 4
                            ? AppLocalizations.of(context)?.continueAction ?? AppLocalizations.of(context)!.tr('Continue')
                            : (isEditing
                                  ? AppLocalizations.of(context)?.updateVehicle ?? AppLocalizations.of(context)!.tr('Update Vehicle')
                                  : AppLocalizations.of(context)?.addVehicle ?? AppLocalizations.of(context)!.tr('Add Vehicle')),
                        onPressed: _isSaving ? null : _nextStep,
                        isLoading: _isSaving,
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  // Section Header Widget - Apple Style
  Widget _buildSectionHeader(String title, bool isLight) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          color: isLight ? Colors.black : Colors.white,
          fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  // Modern Dropdown Widget
  Widget _buildModernDropdown({
    required String label,
    required String? value,
    required IconData icon,
    required bool isLight,
    required VoidCallback? onTap,
  }) {
    return TradeRepublicTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: value != null
              ? (isLight
                    ? Colors.black.withOpacity(0.05)
                    : Colors.white.withOpacity(0.1))
              : (isLight ? Colors.white : Colors.black),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(
                icon,
                color: value != null
                    ? (isLight ? Colors.black : Colors.white)
                    : ((isLight ? Colors.black : Colors.white).withOpacity(
                        0.5,
                      )),
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  value ??
                      '${AppLocalizations.of(context)?.selectLabel ?? ''} $label',
                  style: TextStyle(
                    color: value != null
                        ? (isLight ? Colors.black : Colors.white)
                        : ((isLight ? Colors.black : Colors.white).withOpacity(
                            0.5,
                          )),
                    fontSize: 17,
                    fontWeight: value != null
                        ? FontWeight.w600
                        : FontWeight.w500,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                color: isLight ? Colors.white : Colors.black,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Modern Text Field Widget
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isLight,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int? maxLength,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: controller.text.isNotEmpty
            ? (isLight
                  ? Colors.black.withOpacity(0.05)
                  : Colors.white.withOpacity(0.1))
            : (isLight ? Colors.white : Colors.black),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: TradeRepublicTextField(
        useFormField: true,
        filled: false,
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        textCapitalization: textCapitalization,
        maxLength: maxLength,
        onChanged: (value) => setState(() {}), // Trigger rebuild for animation
        style: TextStyle(
          color: isLight ? Colors.black : Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        hintText: label,
        prefixIcon: Icon(
          icon,
          color: controller.text.isNotEmpty
              ? (isLight ? Colors.black : Colors.white)
              : ((isLight ? Colors.black : Colors.white).withOpacity(0.5)),
          size: 22,
        ),
        counterText: '',
      ),
    );
  }

  // Last Cleaning Date Field with iOS Date Picker
  // Dimension Field Builder (with inline unit toggle buttons)
  // Compact temperature range widget with two sliders + unit toggle
  Widget _buildTemperatureRangeWidget(bool isLight) {
    final isF = _temperatureUnit == '°F';

    // Ranges scale with the unit
    final double minLow  = isF ? -40.0 : -40.0;
    final double minHigh = isF ?  80.0 :  25.0;   // 80 °F ≈ 27 °C
    final double maxLow  = isF ? -10.0 : -10.0;
    final double maxHigh = isF ? 150.0 :  65.0;   // 150 °F ≈ 66 °C

    final textColor = isLight ? Colors.black : Colors.white;
    final subColor = textColor.withOpacity(0.5);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Padding(
        padding: DesktopAppWrapper.getPagePadding(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: label + unit toggle
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.temperatureRange ?? AppLocalizations.of(context)!.tr('Temperature Range'),
                    style: TextStyle(
                      color: textColor,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                TradeRepublicSlider(
                  labels: const ['°C', '°F'],
                  selectedIndex: isF ? 1 : 0,
                  segmentWidth: 52,
                  height: 36,
                  borderRadius: 12,
                  onChanged: (i) {
                    final newUnit = i == 1 ? '°F' : '°C';
                    if (newUnit == _temperatureUnit) return;
                    setState(() {
                      if (newUnit == '°F') {
                        _minTempValue = ((_minTempValue * 9 / 5) + 32).roundToDouble();
                        _maxTempValue = ((_maxTempValue * 9 / 5) + 32).roundToDouble();
                      } else {
                        _minTempValue = ((_minTempValue - 32) * 5 / 9).roundToDouble();
                        _maxTempValue = ((_maxTempValue - 32) * 5 / 9).roundToDouble();
                      }
                      // Clamp to new unit's ranges
                      final newMinLow  = newUnit == '°F' ? -40.0 : -40.0;
                      final newMinHigh = newUnit == '°F' ?  80.0 :  25.0;
                      final newMaxLow  = newUnit == '°F' ? -10.0 : -10.0;
                      final newMaxHigh = newUnit == '°F' ? 150.0 :  65.0;
                      _minTempValue = _minTempValue.clamp(newMinLow, newMinHigh);
                      _maxTempValue = _maxTempValue.clamp(newMaxLow, newMaxHigh);
                      if (_minTempValue >= _maxTempValue) _maxTempValue = _minTempValue + 1;
                      _temperatureUnit = newUnit;
                      _minTemperatureController.text = _minTempValue.toStringAsFixed(0);
                      _maxTemperatureController.text = _maxTempValue.toStringAsFixed(0);
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // ── Min temp ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(CupertinoIcons.snow, size: 15, color: subColor),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.of(context)?.minTemp ?? AppLocalizations.of(context)!.tr('Min Temp'),
                      style: TextStyle(fontSize: 13, color: subColor, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Text(
                  '${_minTempValue.toStringAsFixed(0)} $_temperatureUnit',
                  style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            TradeRepublicValueSlider(
              value: _minTempValue.clamp(minLow, minHigh),
              min: minLow,
              max: minHigh,
              divisions: (minHigh - minLow).toInt(),
              activeColor: Colors.blue,
              onChanged: (v) {
                setState(() {
                  _minTempValue = v.roundToDouble();
                  if (_minTempValue >= _maxTempValue) _maxTempValue = (_minTempValue + 1).clamp(maxLow, maxHigh);
                  _minTemperatureController.text = _minTempValue.toStringAsFixed(0);
                  _maxTemperatureController.text = _maxTempValue.toStringAsFixed(0);
                });
              },
            ),

            const SizedBox(height: 20),

            // ── Max temp ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(CupertinoIcons.thermometer, size: 15, color: subColor),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.of(context)?.maxTemp ?? AppLocalizations.of(context)!.tr('Max Temp'),
                      style: TextStyle(fontSize: 13, color: subColor, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Text(
                  '${_maxTempValue.toStringAsFixed(0)} $_temperatureUnit',
                  style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            TradeRepublicValueSlider(
              value: _maxTempValue.clamp(maxLow, maxHigh),
              min: maxLow,
              max: maxHigh,
              divisions: (maxHigh - maxLow).toInt(),
              activeColor: Colors.orange,
              onChanged: (v) {
                setState(() {
                  _maxTempValue = v.roundToDouble();
                  if (_maxTempValue <= _minTempValue) _minTempValue = (_maxTempValue - 1).clamp(minLow, minHigh);
                  _minTemperatureController.text = _minTempValue.toStringAsFixed(0);
                  _maxTemperatureController.text = _maxTempValue.toStringAsFixed(0);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  // Get Step Title for current step
  String _getStepTitle() {
    switch (_currentStep) {
      case 1:
        return AppLocalizations.of(context)?.basicInfo ?? AppLocalizations.of(context)!.tr('Basic Info');
      case 2:
        return AppLocalizations.of(context)?.licenseAndDetails ?? AppLocalizations.of(context)!.tr('License & Details');
      case 3:
        return AppLocalizations.of(context)?.capacity ?? AppLocalizations.of(context)!.tr('Capacity');
      case 4:
        return AppLocalizations.of(context)?.documentsNav ?? AppLocalizations.of(context)!.tr('Documents');
      default:
        return AppLocalizations.of(context)?.vehicle ?? AppLocalizations.of(context)!.tr('Vehicle');
    }
  }

  // Get Step Subtitle for current step
  String _getStepSubtitle() {
    switch (_currentStep) {
      case 1:
        return 'Make, model and type';
      case 2:
        return AppLocalizations.of(context)?.licensePlateAndVin ?? AppLocalizations.of(context)!.tr('License plate and VIN');
      case 3:
        return AppLocalizations.of(context)?.cargoAndDimensions ?? AppLocalizations.of(context)!.tr('Cargo and dimensions');
      case 4:
        return AppLocalizations.of(context)?.uploadRequiredDocuments ?? AppLocalizations.of(context)!.tr('Upload required documents');
      default:
        return '';
    }
  }

  // Step Dot Indicator
  Widget _buildStepDot(int step, bool isLight) {
    final isActive = _currentStep >= step;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isActive
            ? (isLight ? Colors.black : Colors.white)
            : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$step',
          style: TextStyle(
            color: isActive
                ? (isLight ? Colors.white : Colors.black)
                : (isLight ? Colors.black : Colors.white),
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // Unit Chip Builder — replaces Container+GestureDetector unit selectors
  Widget _buildUnitChip({
    required String label,
    required bool isLight,
    required VoidCallback onTap,
  }) {
    return TradeRepublicTap(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isLight
                ? Colors.black.withOpacity(0.08)
                : Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  CupertinoIcons.chevron_down,
                  color: isLight ? Colors.black : Colors.white,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Unit Button Builder (reusable for both dimension and temperature)
  Widget _buildUnitButton(
    String unit,
    bool isSelected,
    bool isLight,
    Function(bool) onTap,
  ) {
    return TradeRepublicTap(
      onTap: () => onTap(true),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Text(
          unit,
          style: TextStyle(
            color: isSelected
                ? (isLight ? Colors.white : Colors.black)
                : (isLight ? Colors.black54 : Colors.white54),
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // Modern Capacity Field with Unit Selector
  Widget _buildModernCapacityField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String unit,
    required Function(String) onUnitChanged,
    required bool isLight,
    String? Function(String?)? validator,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 16),
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: controller.text.isNotEmpty
            ? (isLight
                  ? Colors.black.withOpacity(0.05)
                  : Colors.white.withOpacity(0.1))
            : (isLight ? Colors.white : Colors.black),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        children: [
          // Text Field
          Expanded(
            child: TradeRepublicTextField(
              useFormField: true,
              filled: false,
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                GermanNumberFormatter(
                  Provider.of<AppSettings>(context, listen: false),
                ),
              ],
              validator: validator,
              labelText: label,
              prefixIcon: Icon(
                icon,
                color: isLight ? Colors.black : Colors.white,
              ),
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: DesktopOptimizedWidgets.getFontSize(),
              ),
            ),
          ),
          // Unit Selector
          TradeRepublicTap(
            onTap: () => _showUnitSelector(
              title: label,
              selectedOption: unit,
              options: label.contains('Cargo')
                  ? ['ft³', 'm³', 'L']
                  : ['lbs', 'kg', 'tons'],
              onOptionSelected: onUnitChanged,
              isLight: isLight,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: const BoxDecoration(),
              // No border - clean design
              child: Row(
                children: [
                  Text(
                    unit,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.chevron_down,
                    color: isLight ? Colors.black : Colors.white,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // License Plate Field with Visual Design
  Widget _buildModernLicensePlateField(bool isLight) {
    // Region options: code → (flag emoji, label)
    // EU sets _selectedRegion to 'DE' (default), the country selector lets user change it
    const regions = [
      ('USA',    '🇺🇸', 'USA'),
      ('EU',     '🇪🇺', 'EU'),
      ('CA',     '🇨🇦', 'Canada'),
      ('MX',     '🇲🇽', 'Mexico'),
      ('RU',     '🇷🇺', 'Russia'),
    ];

    // Determine which chip is visually selected
    String activeChip;
    if (_selectedRegion == 'USA' || _selectedRegion == 'CA' || _selectedRegion == 'MX' || _selectedRegion == 'RU') {
      activeChip = _selectedRegion;
    } else {
      activeChip = 'EU'; // Any EU country code maps to the EU chip
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(
              CupertinoIcons.creditcard,
              size: 20,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
            ),
            const SizedBox(width: 10),
            Text(
              AppLocalizations.of(context)?.licensePlate ?? AppLocalizations.of(context)!.tr('License Plate'),
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        // Region toggle chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: regions.map((r) {
              final code  = r.$1;
              final flag  = r.$2;
              final label = r.$3;
              final isSelected = activeChip == code;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TradeRepublicTap(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      final oldChip = activeChip;
                      if (oldChip != code) {
                        _licensePlateController.clear();
                      }
                      // EU chip defaults to DE, others map 1:1
                      _selectedRegion = (code == 'EU') ? 'DE' : code;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isLight ? Colors.black : Colors.white)
                          : (isLight ? Colors.black : Colors.white).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(flag, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? (isLight ? Colors.white : Colors.black)
                                : (isLight ? Colors.black : Colors.white).withOpacity(0.55),
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),

        // License Plate Visual
        Center(child: _buildModernLicensePlateVisual(isLight)),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        // Front + Rear photo buttons — directly below the plate
        Row(
          children: [
            Expanded(
              child: _buildPhotoButton(
                label: AppLocalizations.of(context)?.front ?? AppLocalizations.of(context)!.tr('Front'),
                subtitle: AppLocalizations.of(context)?.frontPlate ?? AppLocalizations.of(context)!.tr('Front plate'),
                icon: CupertinoIcons.camera,
                photoPath: _frontLicensePlatePhoto,
                isLight: isLight,
                onTap: () => _takeLicensePlatePhoto('front'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildPhotoButton(
                label: AppLocalizations.of(context)?.rear ?? AppLocalizations.of(context)!.tr('Rear'),
                subtitle: AppLocalizations.of(context)?.rearPlate ?? AppLocalizations.of(context)!.tr('Rear plate'),
                icon: CupertinoIcons.camera,
                photoPath: _rearLicensePlatePhoto,
                isLight: isLight,
                onTap: () => _takeLicensePlatePhoto('rear'),
              ),
            ),
          ],
        ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        // State/Country selector (only USA has states, only EU has sub-countries)
        if (_selectedRegion == 'USA')
          _buildUSAStateSelector(isLight)
        else if (_euCountries.containsKey(_selectedRegion))
          _buildEUCountrySelector(isLight),
      ],
    );
  }

  // License Plate Visual — each region has its own unique plate design
  Widget _buildModernLicensePlateVisual(bool isLight) {
    switch (_selectedRegion) {
      case 'USA':
        return _buildModernUSALicensePlate(isLight);
      case 'CA':
        return _buildModernCALicensePlate(isLight);
      case 'MX':
        return _buildModernMXLicensePlate(isLight);
      case 'RU':
        return _buildModernRULicensePlate(isLight);
      default:
        // All EU country codes (DE, FR, IT, etc.)
        return _buildModernEULicensePlate(isLight);
    }
  }

  // Modern USA License Plate Design
  Widget _buildModernUSALicensePlate(bool isLight) {
    return Container(
      width: 260,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1A1A2E), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.5),
        child: Column(
          children: [
            // Top state banner
            Container(
              height: 14,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1B3A6B), Color(0xFF2A52A0)],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '✦',
                    style: TextStyle(color: Color(0xFFFFD700), fontSize: 6.5),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _selectedUSAState.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    '✦',
                    style: TextStyle(color: Color(0xFFFFD700), fontSize: 6.5),
                  ),
                ],
              ),
            ),
            // Plate number area
            Expanded(
              child: Center(
                child: TradeRepublicTextField(
                  useFormField: true,
                  controller: _licensePlateController,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 8,
                  style: const TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                  hintText: AppLocalizations.of(context)?.licensePlateExampleUs ?? AppLocalizations.of(context)!.tr(''),
                  counterText: '',
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return AppLocalizations.of(
                            context,
                          )?.licensePlateRequired ?? AppLocalizations.of(context)!.tr('License plate required');
                    }
                    return null;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modern EU License Plate Design
  Widget _buildModernEULicensePlate(bool isLight) {
    return Container(
      width: 260,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF111111), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.8),
        child: Row(
          children: [
            // Authentic EU blue band
            Container(
              width: 34,
              color: const Color(0xFF003399),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Stars arc (3×3 circle approximation)
                  const Text(
                    '★★★',
                    style: TextStyle(
                      color: Color(0xFFFFCC00),
                      fontSize: 5,
                      height: 1.2,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Text(
                    '★   ★',
                    style: TextStyle(
                      color: Color(0xFFFFCC00),
                      fontSize: 5,
                      height: 1.2,
                    ),
                  ),
                  const Text(
                    '★★★',
                    style: TextStyle(
                      color: Color(0xFFFFCC00),
                      fontSize: 5,
                      height: 1.2,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _selectedRegion,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            // License Plate Input
            Expanded(
              child: Center(
                child: TradeRepublicTextField(
                  useFormField: true,
                  controller: _licensePlateController,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 12,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                  hintText: _getEULicensePlateHint(),
                  counterText: '',
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return AppLocalizations.of(
                            context,
                          )?.licensePlateRequired ?? AppLocalizations.of(context)!.tr('License plate required');
                    }
                    return null;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🇨🇦 Modern Canadian License Plate Design
  Widget _buildModernCALicensePlate(bool isLight) {
    return Container(
      width: 260,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCC0000), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.5),
        child: Column(
          children: [
            // Red top strip with CANADA
            Container(
              height: 14,
              width: double.infinity,
              color: const Color(0xFFCC0000),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🍁', style: TextStyle(fontSize: 8)),
                  SizedBox(width: 5),
                  Text(
                    'CANADA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(width: 5),
                  Text('🍁', style: TextStyle(fontSize: 8)),
                ],
              ),
            ),
            // Plate number area
            Expanded(
              child: Center(
                child: TradeRepublicTextField(
                  useFormField: true,
                  controller: _licensePlateController,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 8,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                  ),
                  hintText: AppLocalizations.of(context)?.licensePlateExampleDe ?? AppLocalizations.of(context)!.tr(''),
                  counterText: '',
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return AppLocalizations.of(context)?.licensePlateRequired ?? AppLocalizations.of(context)!.tr('License plate required');
                    }
                    return null;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🇲🇽 Modern Mexican License Plate Design
  Widget _buildModernMXLicensePlate(bool isLight) {
    return Container(
      width: 260,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF111111), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.8),
        child: Column(
          children: [
            // Mexican flag tricolor top strip
            SizedBox(
              height: 11,
              child: Row(
                children: [
                  Expanded(child: Container(color: const Color(0xFF006847))),
                  Expanded(child: Container(color: Colors.white)),
                  Expanded(child: Container(color: const Color(0xFFCE1126))),
                ],
              ),
            ),
            // Plate number area
            Expanded(
              child: Center(
                child: TradeRepublicTextField(
                  useFormField: true,
                  controller: _licensePlateController,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 10,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                  hintText: AppLocalizations.of(context)?.licensePlateExampleEu ?? AppLocalizations.of(context)!.tr(''),
                  counterText: '',
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return AppLocalizations.of(context)?.licensePlateRequired ?? AppLocalizations.of(context)!.tr('License plate required');
                    }
                    return null;
                  },
                ),
              ),
            ),
            // MÉXICO bottom label
            Container(
              height: 9,
              width: double.infinity,
              color: const Color(0xFFF0F0F0),
              child: const Center(
                child: Text(
                  'M É X I C O',
                  style: TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 5.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🇷🇺 Modern Russian License Plate Design
  Widget _buildModernRULicensePlate(bool isLight) {
    return Container(
      width: 260,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1A1A1A), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.5),
        child: Row(
          children: [
            // Plate number area
            Expanded(
              child: Center(
                child: TradeRepublicTextField(
                  useFormField: true,
                  controller: _licensePlateController,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 9,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                  ),
                  hintText: _getEULicensePlateHint(),
                  counterText: '',
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return AppLocalizations.of(context)?.licensePlateRequired ?? AppLocalizations.of(context)!.tr('License plate required');
                    }
                    return null;
                  },
                ),
              ),
            ),
            // GOST-style vertical divider
            Container(
              width: 1.5,
              margin: const EdgeInsets.symmetric(vertical: 7),
              color: const Color(0xFF1A1A1A),
            ),
            // Right region band: mini flag + RUS
            SizedBox(
              width: 46,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Mini Russian flag with border
                  Container(
                    width: 28,
                    height: 16,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.black.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(child: Container(color: Colors.white)),
                        Expanded(child: Container(color: const Color(0xFF0039A6))),
                        Expanded(child: Container(color: const Color(0xFFD52B1E))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'RUS',
                    style: TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // USA State Selector
  Widget _buildUSAStateSelector(bool isLight) {
    return TradeRepublicListTile.navigation(
      leading: Icon(
        CupertinoIcons.location_solid,
        size: 18,
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
      ),
      title: '${AppLocalizations.of(context)?.stateLabel ?? AppLocalizations.of(context)!.tr('State')}: $_selectedUSAState',
      onTap: () => _showStateSelector(isLight),
    );
  }

  // EU/International Country Selector
  Widget _buildEUCountrySelector(bool isLight) {
    final countryName = _euCountries[_selectedRegion] ?? _selectedRegion;
    return TradeRepublicListTile.navigation(
      leading: Icon(
        CupertinoIcons.flag,
        size: 18,
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
      ),
      title: '$_selectedRegion — $countryName',
      onTap: () => _showEUCountrySelector(isLight),
    );
  }

  // Get hint text for EU license plate based on country
  String _getEULicensePlateHint() {
    switch (_selectedRegion) {
      case 'DE': // Germany
        return 'B-XX-1234';
      case 'FR': // France
        return 'AB-123-CD';
      case 'IT': // Italy
        return 'AB-123-CD';
      case 'ES': // Spain
        return '1234-ABC';
      case 'NL': // Netherlands
        return 'AB-12-CD';
      case 'BE': // Belgium
        return '1-ABC-123';
      case 'AT': // Austria
        return 'W-12345';
      case 'PL': // Poland
        return 'AB-1234C';
      case 'SE': // Sweden
        return 'ABC-123';
      case 'PT': // Portugal
        return 'AB-12-CD';
      case 'GR': // Greece
        return 'ΑΒΓ-1234';
      case 'CZ': // Czech Republic
        return '1AB-1234';
      case 'HU': // Hungary
        return 'ABC-123';
      case 'RO': // Romania
        return 'AB-12-ABC';
      case 'DK': // Denmark
        return 'AB-12345';
      case 'FI': // Finland
        return 'ABC-123';
      case 'SK': // Slovakia
        return 'AA-123BC';
      case 'IE': // Ireland
        return '12-D-1234';
      case 'HR': // Croatia
        return 'AB-123-CD';
      case 'BG': // Bulgaria
        return 'A-1234-AB';
      case 'LT': // Lithuania
        return 'ABC-123';
      case 'SI': // Slovenia
        return 'AB-123-CD';
      case 'LV': // Latvia
        return 'AB-1234';
      case 'EE': // Estonia
        return '123-ABC';
      case 'CY': // Cyprus
        return 'ABC-123';
      case 'LU': // Luxembourg
        return 'AB-1234';
      case 'MT': // Malta
        return 'ABC-123';
      case 'CA': // Canada
        return 'ABCD 123';
      case 'MX': // Mexico
        return 'ABC-12-34';
      case 'RU': // Russia
        return 'A 123 BC';
      default:
        return 'XX-YY-1234';
    }
  }

  // License Plate Photo Section
  Widget _buildLicensePlatePhotoSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            AppLocalizations.of(context)?.vehiclePhotos ?? AppLocalizations.of(context)!.tr('Vehicle Photos'),
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),

        // Photo Instructions - Simplified
        Container(
          padding: DesktopAppWrapper.getPagePadding(),
          decoration: BoxDecoration(
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.info,
                color: isLight ? Colors.black : Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.photoBothLicensePlatesClearly ?? AppLocalizations.of(context)!.tr('Photo both license plates clearly'),
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Photo Buttons Row
        Row(
          children: [
            // Front License Plate Photo
            Expanded(
              child: _buildPhotoButton(
                label: AppLocalizations.of(context)?.front ?? AppLocalizations.of(context)!.tr('Front'),
                subtitle:
                    AppLocalizations.of(context)?.frontPlate ?? AppLocalizations.of(context)!.tr('Front plate'),
                icon: CupertinoIcons.camera,
                photoPath: _frontLicensePlatePhoto,
                isLight: isLight,
                onTap: () => _takeLicensePlatePhoto('front'),
              ),
            ),

            const SizedBox(width: 16),

            // Rear License Plate Photo
            Expanded(
              child: _buildPhotoButton(
                label: AppLocalizations.of(context)?.rear ?? AppLocalizations.of(context)!.tr('Rear'),
                subtitle:
                    AppLocalizations.of(context)?.rearPlate ?? AppLocalizations.of(context)!.tr('Rear plate'),
                icon: CupertinoIcons.camera,
                photoPath: _rearLicensePlatePhoto,
                isLight: isLight,
                onTap: () => _takeLicensePlatePhoto('rear'),
              ),
            ),
          ],
        ),

        // Show taken photos below buttons
        if (_frontLicensePlatePhoto != null ||
            _rearLicensePlatePhoto != null) ...[
          const SizedBox(height: 20),

          // Photos Preview Section - Simplified
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.photos ?? AppLocalizations.of(context)!.tr('Photos'),
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    // Front Photo Preview
                    if (_frontLicensePlatePhoto != null) ...[
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                color: Colors.green,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)?.frontCheck ?? AppLocalizations.of(context)!.tr('Front ✓'),
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                CupertinoIcons.camera,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)?.front ?? AppLocalizations.of(context)!.tr('Front'),
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(width: 10),

                    // Rear Photo Preview
                    if (_rearLicensePlatePhoto != null) ...[
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                color: Colors.green,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)?.rearCheck ?? AppLocalizations.of(context)!.tr('Rear ✓'),
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                CupertinoIcons.camera,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)?.rear ?? AppLocalizations.of(context)!.tr('Rear'),
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Photo Button Widget - Separate containers for button and preview
  Widget _buildPhotoButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required String? photoPath,
    required bool isLight,
    required VoidCallback onTap,
  }) {
    bool hasPhoto = photoPath != null && photoPath.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Upload Button - Always visible
        TradeRepublicTap(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: isLight
                  ? (hasPhoto ? Colors.green.withOpacity(0.15) : Colors.white)
                  : (hasPhoto ? Colors.green.withOpacity(0.25) : Colors.black),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasPhoto
                        ? Colors.green.withOpacity(0.2)
                        : (isLight
                              ? Colors.black.withOpacity(0.2)
                              : Colors.black.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Icon(
                    hasPhoto ? CupertinoIcons.checkmark_circle_fill : icon,
                    color: hasPhoto
                        ? Colors.green
                        : (isLight ? Colors.black : Colors.white),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasPhoto
                            ? (AppLocalizations.of(context)?.retake ?? AppLocalizations.of(context)!.tr('Retake'))
                            : subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  color: isLight ? Colors.white : Colors.black,
                ),
              ],
            ),
          ),
        ),

        // Image Preview Container - Only shown when photo exists
        if (hasPhoto) ...[
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          TradeRepublicTap(
            onTap: () =>
                _showFullScreenImage(context, null, photoPath, isLight),
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                child: (photoPath.startsWith('/') || photoPath.startsWith('file://'))
                    ? Image.file(
                        File(photoPath),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(CupertinoIcons.xmark_circle, color: Colors.red, size: 40),
                        ),
                      )
                    : Image.network(
                        ApiConfig.getImageUrl(photoPath),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(child: CultiooLoadingIndicator());
                        },
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(CupertinoIcons.xmark_circle, color: Colors.red, size: 40),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Show Unit Selector - Settings Style
  void _showUnitSelector({
    required String title,
    required List<String> options,
    required String selectedOption,
    required Function(String) onOptionSelected,
    required bool isLight,
  }) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.list_bullet,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),

            const SizedBox(height: 20),

            // Options - Settings Style
            ...options.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildSettingsStyleOption(
                  option: option,
                  isSelected: selectedOption == option,
                  onTap: () {
                    onOptionSelected(option);
                    Navigator.pop(context);
                  },
                  isLight: isLight,
                ),
              ),
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button - Settings Style
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              isSecondary: true,
            ),
          ],
        ),
      );
  }

  // === NEW: Dimension Unit Selector ===
  void _showDimensionUnitSelector(bool isLight) {
    _showUnitSelector(
      title: AppLocalizations.of(context)?.dimensionUnit ?? AppLocalizations.of(context)!.tr('Dimension Unit'),
      options: ['ft', 'm'],
      selectedOption: _dimensionUnit,
      onOptionSelected: (unit) {
        setState(() {
          _dimensionUnit = unit;
        });
      },
      isLight: isLight,
    );
  }

  // === NEW: Temperature Unit Selector ===
  void _showTemperatureUnitSelector(bool isLight) {
    _showUnitSelector(
      title:
          AppLocalizations.of(context)?.temperatureUnit ?? AppLocalizations.of(context)!.tr('Temperature Unit'),
      options: ['°F', '°C'],
      selectedOption: _temperatureUnit,
      onOptionSelected: (unit) {
        setState(() {
          _temperatureUnit = unit;
        });
      },
      isLight: isLight,
    );
  }

  // Show Make Selector - Settings Style
  void _showMakeSelector(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.car_detailed,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.vehicleMake ?? AppLocalizations.of(context)!.tr('Vehicle Make'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

            const SizedBox(height: 20),

            // Options - Settings Style
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: _vehicleData.keys.map((make) {
                    final isSelected = _selectedMake == make;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildSettingsStyleOption(
                        option: make,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedMake = make;
                            _selectedModel =
                                null; // Reset model when make changes
                          });
                          Navigator.pop(context);
                        },
                        isLight: isLight,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button - Settings Style
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              isSecondary: true,
            ),
          ],
        ),
      );
  }

  // Settings Style Option Helper Method
  Widget _buildSettingsStyleOption({
    required String option,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isLight,
  }) {
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? (isLight ? Colors.white : Colors.black)
                      : (isLight ? Colors.black : Colors.white),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: isLight ? Colors.white : Colors.black,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  // Show Model Selector - Settings Style
  void _showModelSelector(bool isLight) {
    if (_selectedMake == null) return;

    final models = _vehicleData[_selectedMake!] ?? [];

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.car_detailed,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                '$_selectedMake Model',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

            const SizedBox(height: 20),

            // Options - Settings Style
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: models.map((model) {
                    final isSelected = _selectedModel == model;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildSettingsStyleOption(
                        option: model,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedModel = model;
                          });
                          Navigator.pop(context);
                        },
                        isLight: isLight,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button - Settings Style
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              isSecondary: true,
            ),
          ],
        ),
      );
  }

  // Show Vehicle Type Selector - Settings Style
  void _showVehicleTypeSelector(bool isLight) {
    final vehicleTypes = WagonTypesCatalog.localized(AppLocalizations.of(context));

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.car_detailed,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.vehicleType ?? AppLocalizations.of(context)!.tr('Vehicle Type'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

            const SizedBox(height: 20),

            // Options - Settings Style
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: vehicleTypes.map((type) {
                    final typeName = type['name']!;
                    final typeIcon = type['icon']!;
                    final typeDescription = type['description']!;
                    final isSelected = _selectedVehicleType == type['id'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TradeRepublicTap(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _selectedVehicleType = type['id']!;
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isLight ? Colors.black : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Row(
                            children: [
                              // Icon
                              Text(
                                typeIcon,
                                style: const TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 10,,
                              ),
                              const SizedBox(width: 16),
                              // Name and Description
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      typeName,
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: isSelected
                                            ? (isLight
                                                  ? Colors.white
                                                  : Colors.black)
                                            : (isLight
                                                  ? Colors.black
                                                  : Colors.white),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      typeDescription,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                        color: isSelected
                                            ? (isLight
                                                  ? Colors.white.withOpacity(
                                                      0.8,
                                                    )
                                                  : Colors.black.withOpacity(
                                                      0.6,
                                                    ))
                                            : (isLight
                                                  ? Colors.black.withOpacity(
                                                      0.5,
                                                    )
                                                  : Colors.white.withOpacity(
                                                      0.5,
                                                    )),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Checkmark
                              if (isSelected)
                                Icon(
                                  CupertinoIcons.checkmark_circle_fill,
                                  color: isLight ? Colors.white : Colors.black,
                                  size: 24,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button - Settings Style
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              isSecondary: true,
            ),
          ],
        ),
      );
  }

  // Show State Selector - Settings Style
  void _showStateSelector(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.location,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.usaState ?? AppLocalizations.of(context)!.tr('USA State'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

            const SizedBox(height: 20),

            // Options - Settings Style
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: _usaStates.map((state) {
                    final isSelected = _selectedUSAState == state;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildSettingsStyleOption(
                        option: state,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedUSAState = state;
                          });
                          Navigator.pop(context);
                        },
                        isLight: isLight,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button - Settings Style
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              },
              isSecondary: true,
            ),
          ],
        ),
      );
  }

  // EU Country Selector - Settings Style
  void _showEUCountrySelector(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.globe,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.euCountry ?? AppLocalizations.of(context)!.tr('EU Country'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

            const SizedBox(height: 20),

            // EU Countries List
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: _euCountries.entries.map((entry) {
                    final code = entry.key;
                    final name = entry.value;
                    final isSelected = _selectedRegion == code;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildSettingsStyleOption(
                        option: '$code - $name',
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedRegion = code;
                          });
                          Navigator.pop(context);
                        },
                        isLight: isLight,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      );
  }

  // Build Transport Toggle Widget
  Widget _buildTransportToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    required bool isLight,
    Color? iconColor,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: value
            ? (isLight
                  ? Colors.black.withOpacity(0.05)
                  : Colors.white.withOpacity(0.1))
            : (isLight ? Colors.white : Colors.black),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Padding(
        padding: DesktopAppWrapper.getPagePadding(),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (iconColor ?? (isLight ? Colors.black : Colors.white))
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Icon(
                icon,
                color: iconColor ?? (isLight ? Colors.black : Colors.white),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Text
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
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // Toggle Switch
            TradeRepublicSwitch(
              value: value,
              onChanged: onChanged,
              selectedLabel: 'Y',
              unselectedLabel: 'N',
            ),
          ],
        ),
      ),
    );
  }

  // === SECTIONED LOADING METHODS ===

  // Get the total cargo capacity from the input field
  double _getTotalCargoCapacity() {
    // Use the same parser as the formatter uses (handles "1,234.56" and "1.234,56")
    return GermanNumberFormatter.parseGermanNumber(_cargoCapacityController.text);
  }

  void _initializeDefaultSections() {
    // Create default sections based on vehicle type
    // Sections use PERCENTAGE of total cargo capacity
    final isHopper =
        _selectedVehicleType?.toLowerCase().contains('hopper') ??
        false ||
            (_selectedVehicleType?.toLowerCase().contains('grain') ?? false);
    final isTanker =
        _selectedVehicleType?.toLowerCase().contains('tanker') ??
        false ||
            (_selectedVehicleType?.toLowerCase().contains('liquid') ?? false);

    if (isHopper) {
      // Grain hoppers typically have 2-4 compartments
      // Percentages that add up to 100%
      _vehicleSections = [
        {
          'id': '1',
          'name': 'Front Hopper',
          'percentage': 25.0, // percentage of total
          'position': 0,
        },
        {'id': '2', 'name': 'Middle Hopper', 'percentage': 50.0, 'position': 1},
        {'id': '3', 'name': 'Rear Hopper', 'percentage': 25.0, 'position': 2},
      ];
    } else if (isTanker) {
      // Tankers typically have 2-6 compartments
      _vehicleSections = [
        {'id': '1', 'name': 'Tank 1', 'percentage': 33.33, 'position': 0},
        {'id': '2', 'name': 'Tank 2', 'percentage': 33.33, 'position': 1},
        {'id': '3', 'name': 'Tank 3', 'percentage': 33.34, 'position': 2},
      ];
    } else {
      // Default truck sections
      _vehicleSections = [
        {'id': '1', 'name': 'Front Section', 'percentage': 50.0, 'position': 0},
        {'id': '2', 'name': 'Rear Section', 'percentage': 50.0, 'position': 1},
      ];
    }
  }

  // Get unit label based on vehicle type - uses the cargo unit
  String _getSectionCapacityUnit() {
    return _cargoUnit; // Use same unit as cargo capacity
  }

  // Get total percentage from all sections (should be ~100%)
  double _getTotalSectionPercentage() {
    if (_vehicleSections.isEmpty) return 0.0;
    return _vehicleSections.fold(
      0.0,
      (sum, section) => sum + (section['percentage'] as num).toDouble(),
    );
  }

  // Calculate absolute capacity for a section based on percentage
  double _getSectionAbsoluteCapacity(Map<String, dynamic> section) {
    final percentage = (section['percentage'] as num).toDouble();
    final totalCapacity = _getTotalCargoCapacity();
    return (percentage / 100) * totalCapacity;
  }

  Widget _buildVehicleSectionsUI(bool isLight) {
    final isHopper =
        _selectedVehicleType?.toLowerCase().contains('hopper') ??
        false ||
            (_selectedVehicleType?.toLowerCase().contains('grain') ?? false);
    final isTanker =
        _selectedVehicleType?.toLowerCase().contains('tanker') ??
        false ||
            (_selectedVehicleType?.toLowerCase().contains('liquid') ?? false);

    final unit = _getSectionCapacityUnit();
    final totalCargoCapacity = _getTotalCargoCapacity();
    final totalPercentage = _getTotalSectionPercentage();

    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Padding(
        padding: DesktopAppWrapper.getPagePadding(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  isHopper
                      ? CupertinoIcons.leaf_arrow_circlepath
                      : (isTanker
                            ? CupertinoIcons.drop
                            : CupertinoIcons.cube_box),
                  color: isLight ? Colors.black : Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isHopper
                            ? (AppLocalizations.of(
                                    context,
                                  )?.hopperCompartments ?? AppLocalizations.of(context)!.tr('Hopper Compartments'))
                            : (isTanker
                                  ? AppLocalizations.of(context)?.tankCompartments ?? AppLocalizations.of(context)!.tr('Tank Compartments')
                                  : 'Cargo Sections'),
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (_vehicleSections.isNotEmpty)
                        Text(
                          '${AppLocalizations.of(context)?.totalCapacity ?? AppLocalizations.of(context)!.tr('Total')}: ${totalCargoCapacity.toStringAsFixed(0)} $unit (${totalPercentage.toStringAsFixed(0)}%)',
                          style: TextStyle(
                            color: totalPercentage != 100
                                ? Colors.orange
                                : (isLight ? Colors.black : Colors.white),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                // Add Section Button - Trade Republic style
                TradeRepublicTap(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showAddSectionModal(isLight);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isLight
                          ? Colors.black.withOpacity(0.05)
                          : Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.plus,
                      color: isLight ? Colors.black : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),

            // Warning if percentages don't add up to 100%
            if (_vehicleSections.isNotEmpty &&
                (totalPercentage < 99 || totalPercentage > 101))
              Container(
                margin: const EdgeInsets.only(top: 0, bottom: 20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.05,
                  ),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.exclamationmark,
                        color: isLight ? Colors.black : Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(
                              context,
                            )?.sectionPercentagesWarning ?? AppLocalizations.of(context)!.tr('Section percentages should add up to 100%'),
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Visual Vehicle Representation with sections INSIDE the truck
            _buildTruckWithSections(isLight, isHopper, isTanker),

            if (_vehicleSections.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(0),
                  child: Text(
                    AppLocalizations.of(context)?.tapAddToCreateSections ?? AppLocalizations.of(context)!.tr('Tap "Add" to create sections'),
                    style: TextStyle(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Minimalist Apple/Trade Republic style truck sections
  Widget _buildTruckWithSections(bool isLight, bool isHopper, bool isTanker) {
    final unit = _getSectionCapacityUnit();
    final totalCargoCapacity = _getTotalCargoCapacity();

    if (_vehicleSections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Minimalist truck visualization
        Container(
          height: 80,
          margin: const EdgeInsets.only(bottom: 28),
          child: Row(
            children: [
              // Cab - rounded left, flat right (like real truck)
              Container(
                width: 32,
                height: 48,
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : Colors.black,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Cargo - rounded on both sides
              Expanded(
                child: Container(
                  height: 56,
                  clipBehavior: Clip.antiAlias,
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Row(
                    children: _vehicleSections.asMap().entries.map((entry) {
                      final index = entry.key;
                      final section = entry.value;
                      final percentage = (section['percentage'] as num)
                          .toDouble();
                      final isFirst = index == 0;
                      final isLast = index == _vehicleSections.length - 1;

                      return Expanded(
                        flex: percentage.round().clamp(1, 100),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _getSectionColor(index),
                                _getSectionColor(index).withOpacity(0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.only(
                              topLeft: isFirst
                                  ? const Radius.circular(20)
                                  : Radius.zero,
                              bottomLeft: isFirst
                                  ? const Radius.circular(20)
                                  : Radius.zero,
                              topRight: isLast
                                  ? const Radius.circular(20)
                                  : Radius.zero,
                              bottomRight: isLast
                                  ? const Radius.circular(20)
                                  : Radius.zero,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${percentage.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Section list - pure minimalist, NO containers - swipe left to edit
        ..._vehicleSections.asMap().entries.map((entry) {
          final index = entry.key;
          final section = entry.value;
          final name = section['name'] as String;
          final percentage = (section['percentage'] as num).toDouble();
          final absoluteCapacity = (percentage / 100) * totalCargoCapacity;
          final isLast = index == _vehicleSections.length - 1;

          return TradeRepublicSwipeAction(
            key: ValueKey('section_$index'),
            margin: EdgeInsets.zero,
            borderRadius: 20,
            leading: TradeRepublicSwipeSpec(
              icon: CupertinoIcons.trash,
              label: AppLocalizations.of(context)?.deleteLabel ?? 'Delete',
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              onActivate: () => _confirmDeleteSection(index, isLight),
            ),
            trailing: TradeRepublicSwipeSpec(
              icon: CupertinoIcons.pencil,
              label: AppLocalizations.of(context)?.editLabel ?? 'Edit',
              onActivate: () => _showEditSectionModal(section, index, isLight),
            ),
            child: TradeRepublicTap(
              onTap: () {
                HapticFeedback.selectionClick();
                _editSection(index, isLight);
              },
              onLongPress: () {
                HapticFeedback.heavyImpact();
                _confirmDeleteSection(index, isLight);
              },
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Color dot
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _getSectionColor(index),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Name & capacity
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.toUpperCase(),
                                style: TextStyle(
                                  color: isLight ? Colors.black : Colors.white,
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                '${absoluteCapacity.toStringAsFixed(0)} $unit',
                                style: TextStyle(
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Percentage - solid with gradient
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _getSectionColor(index),
                                _getSectionColor(index).withOpacity(0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Text(
                            '${percentage.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Subtle divider (not on last item)
                  if (!isLast)
                    Container(
                      height: 0.5,
                      color: isLight ? Colors.white : Colors.black,
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildVehicleTopView(bool isLight, bool isHopper, bool isTanker) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight
              ? [Colors.white, Colors.white]
              : [Colors.black, Colors.black],
        ),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Stack(
        children: [
          // Vehicle shape
          Center(
            child: Padding(
              padding: const EdgeInsets.all(0),
              child: isHopper
                  ? _buildHopperTopView(isLight)
                  : (isTanker
                        ? _buildTankerTopView(isLight)
                        : _buildTruckTopView(isLight)),
            ),
          ),

          // Direction indicator
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.chevron_left,
                  size: 12,
                  color: isLight ? Colors.white : Colors.black,
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)?.frontLabel ?? AppLocalizations.of(context)!.tr('FRONT'),
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHopperTopView(bool isLight) {
    final unit = _getSectionCapacityUnit();
    final totalCargoCapacity = _getTotalCargoCapacity();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Cab - sleek design
        Container(
          width: 32,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isLight
                  ? [Colors.white, Colors.black]
                  : [Colors.white, Colors.black],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Hopper Compartments
        ..._vehicleSections.asMap().entries.map((entry) {
          final index = entry.key;
          final section = entry.value;
          final percentage = (section['percentage'] as num).toDouble();
          final absoluteCapacity = (percentage / 100) * totalCargoCapacity;
          final width = (percentage / 100 * 180).clamp(44.0, 100.0);

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: width,
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _getSectionColor(index),
                  _getSectionColor(index).withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${absoluteCapacity.toStringAsFixed(0)} $unit',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTankerTopView(bool isLight) {
    final unit = _getSectionCapacityUnit();
    final totalCargoCapacity = _getTotalCargoCapacity();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Cab - sleek design
        Container(
          width: 32,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isLight
                  ? [Colors.white, Colors.black]
                  : [Colors.white, Colors.black],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Tank Compartments (cylindrical appearance)
        ..._vehicleSections.asMap().entries.map((entry) {
          final index = entry.key;
          final section = entry.value;
          final percentage = (section['percentage'] as num).toDouble();
          final absoluteCapacity = (percentage / 100) * totalCargoCapacity;
          final width = (percentage / 100 * 180).clamp(40.0, 80.0);

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: width,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _getSectionColor(index),
                  _getSectionColor(index).withOpacity(0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${absoluteCapacity.toStringAsFixed(0)} $unit',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTruckTopView(bool isLight) {
    final unit = _getSectionCapacityUnit();
    final totalCargoCapacity = _getTotalCargoCapacity();
    final totalSections = _vehicleSections.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Cab - sleek design
        Container(
          width: 40,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isLight
                  ? [Colors.white, Colors.black]
                  : [Colors.white, Colors.black],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Cargo Area with sections
        Container(
          width: 200,
          height: 75,
          padding: DesktopAppWrapper.getPagePadding(),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: _vehicleSections.asMap().entries.map((entry) {
              final index = entry.key;
              final section = entry.value;
              final percentage = (section['percentage'] as num).toDouble();
              final absoluteCapacity = (percentage / 100) * totalCargoCapacity;
              final isFirst = index == 0;
              final isLast = index == totalSections - 1;

              return Expanded(
                flex: percentage.round().clamp(1, 100),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _getSectionColor(index),
                        _getSectionColor(index).withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.horizontal(
                      left: isFirst ? const Radius.circular(20) : Radius.zero,
                      right: isLast ? const Radius.circular(20) : Radius.zero,
                    ),

                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${percentage.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${absoluteCapacity.toStringAsFixed(0)} $unit',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Color _getSectionColor(int index) {
    final colors = [
      Colors.blue[600]!,
      Colors.green[600]!,
      Colors.orange[600]!,
      Colors.purple[600]!,
      Colors.teal[600]!,
      Colors.pink[600]!,
      Colors.indigo[600]!,
      Colors.amber[700]!,
    ];
    return colors[index % colors.length];
  }

  Widget _buildSectionCard(
    Map<String, dynamic> section,
    int index,
    bool isLight,
  ) {
    final name = section['name'] as String;
    final percentage = (section['percentage'] as num).toDouble();
    final unit = _getSectionCapacityUnit();
    final absoluteCapacity = _getSectionAbsoluteCapacity(section);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Padding(
        padding: DesktopAppWrapper.getPagePadding(),
        child: Row(
          children: [
            // Color indicator
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _getSectionColor(index),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Section Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getSectionColor(index).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: _getSectionColor(index),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '= ${absoluteCapacity.toStringAsFixed(0)} $unit',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Edit Button
            TradeRepublicButton.icon(
              icon: Icon(CupertinoIcons.pencil, size: 18),
              onPressed: () => _showEditSectionModal(section, index, isLight),
              backgroundColor: isLight ? Colors.white : Colors.black,
              foregroundColor: isLight ? Colors.black : Colors.white,
              size: 36,
              isSecondary: true,
            ),
            const SizedBox(width: 8),
            // Delete Button
            TradeRepublicButton.icon(
              icon: Icon(CupertinoIcons.xmark, size: 18),
              onPressed: () => _deleteSection(index),
              backgroundColor: Colors.red.withOpacity(0.1),
              foregroundColor: Colors.red[400]!,
              size: 36,
              isSecondary: true,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSectionModal(bool isLight) {
    final appSettings = context.read<AppSettings>();
    final nameController = TextEditingController();
    final capacityController = TextEditingController();

    // Determine number format from AppSettings
    final isEuropeanFormat = appSettings.effectiveNumberFormat == '1.234,56';
    final hintText = isEuropeanFormat ? '0,00' : '0.00';

    final isHopper =
        _selectedVehicleType?.toLowerCase().contains('hopper') ??
        false ||
            (_selectedVehicleType?.toLowerCase().contains('grain') ?? false);
    final isTanker =
        _selectedVehicleType?.toLowerCase().contains('tanker') ??
        false ||
            (_selectedVehicleType?.toLowerCase().contains('liquid') ?? false);

    final unit = _getSectionCapacityUnit();
    final totalCapacity = _getTotalCargoCapacity();
    final usedPercentage = _getTotalSectionPercentage();
    final remainingPercentage = (100 - usedPercentage).clamp(0.0, 100.0);
    final remainingCapacity = (remainingPercentage / 100) * totalCapacity;

    // Set default values based on vehicle type
    if (isHopper) {
      nameController.text = 'Hopper ${_vehicleSections.length + 1}';
    } else if (isTanker) {
      nameController.text = 'Tank ${_vehicleSections.length + 1}';
    } else {
      nameController.text = 'Section ${_vehicleSections.length + 1}';
    }

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          // Parse capacity using the appropriate number format
          final enteredCapacity = GermanNumberFormatter.parseGermanNumber(
            capacityController.text,
          );
          final calculatedPercentage = totalCapacity > 0
              ? (enteredCapacity / totalCapacity * 100)
              : 0.0;
          final wouldExceed =
              (usedPercentage + calculatedPercentage) >
              100.5; // small tolerance
          final isValid = enteredCapacity > 0 && !wouldExceed;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                // Big title
                      Text(
                        isHopper
                            ? (AppLocalizations.of(context)?.newHopper ?? AppLocalizations.of(context)!.tr('New Hopper'))
                            : (isTanker
                                  ? AppLocalizations.of(context)?.newTank ?? AppLocalizations.of(context)!.tr('New Tank')
                                  : AppLocalizations.of(context)?.newSection ?? AppLocalizations.of(context)!.tr('New Section')),
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),

                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      // Subtitle
                      Text(
                        '${remainingCapacity.toStringAsFixed(0)} $unit available',
                        style: TextStyle(
                          color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w400,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Big capacity input
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: TradeRepublicTextField(
                              controller: capacityController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.right,
                              autofocus: true,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                              ],
                              onChanged: (value) => setModalState(() {}),
                              style: TextStyle(
                                color: wouldExceed
                                    ? Colors.red
                                    : (isLight ? Colors.black : Colors.white),
                                fontSize: 56,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -2,
                              ),
                              hintText: hintText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            unit,
                            style: TextStyle(
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
                              fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      // Percentage indicator
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: wouldExceed
                              ? Colors.red
                              : (isLight ? Colors.blue : Colors.blue[400]!),
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                          fontWeight: FontWeight.w600,
                        ),
                        child: Text(
                          '${calculatedPercentage.toStringAsFixed(1)}%',
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Name input
                      TradeRepublicTextField(
                        controller: nameController,
                        filled: false,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                        hintText:
                            AppLocalizations.of(context)?.nameOptional ?? AppLocalizations.of(context)!.tr('Name (optional)'),
                      ),

                      // Error message
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        child: wouldExceed
                            ? Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.exceedsCapacity ?? AppLocalizations.of(context)!.tr('Exceeds capacity'),
                                  style: TextStyle(
                                    color: Colors.red[400],
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 32),

                      // Add button
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)?.add ?? AppLocalizations.of(context)!.tr('Add'),
                        onPressed: isValid
                            ? () {
                                final name = nameController.text.trim();
                                setState(() {
                                  _vehicleSections.add({
                                    'id': DateTime.now().millisecondsSinceEpoch
                                        .toString(),
                                    'name': name.isEmpty
                                        ? (isHopper
                                              ? 'Hopper ${_vehicleSections.length + 1}'
                                              : (isTanker
                                                    ? 'Tank ${_vehicleSections.length + 1}'
                                                    : 'Section ${_vehicleSections.length + 1}'))
                                        : name,
                                    'percentage': calculatedPercentage.clamp(
                                      0.1,
                                      100.0,
                                    ),
                                    'position': _vehicleSections.length,
                                  });
                                });
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                              }
                            : null,
                        width: double.infinity,
                      ),
                    ],
                  ),
                ),
            ),
          );
        },
      ),
    );
  }

  void _showEditSectionModal(
    Map<String, dynamic> section,
    int index,
    bool isLight,
  ) {
    final appSettings = context.read<AppSettings>();
    final isEuropeanFormat = appSettings.effectiveNumberFormat == '1.234,56';
    final hintText = isEuropeanFormat ? '0,00' : '0.00';

    final nameController = TextEditingController(text: section['name']);
    // Calculate current capacity from percentage and format using AppSettings
    final currentPercentage = (section['percentage'] as num).toDouble();
    final totalCapacity = _getTotalCargoCapacity();
    final currentCapacity = (currentPercentage / 100) * totalCapacity;
    final capacityController = TextEditingController(
      text: appSettings.formatNumber(currentCapacity, decimals: 2),
    );

    final isHopper =
        _selectedVehicleType?.toLowerCase().contains('hopper') ??
        false ||
            (_selectedVehicleType?.toLowerCase().contains('grain') ?? false);
    final isTanker =
        _selectedVehicleType?.toLowerCase().contains('tanker') ??
        false ||
            (_selectedVehicleType?.toLowerCase().contains('liquid') ?? false);

    final unit = _getSectionCapacityUnit();

    // Calculate used percentage excluding current section
    final usedPercentageExcludingCurrent = _vehicleSections
        .asMap()
        .entries
        .where((e) => e.key != index)
        .fold(0.0, (sum, e) => sum + (e.value['percentage'] as num).toDouble());
    final maxAvailablePercentage = (100 - usedPercentageExcludingCurrent).clamp(
      0.0,
      100.0,
    );
    final maxAvailableCapacity = (maxAvailablePercentage / 100) * totalCapacity;

    TradeRepublicBottomSheet.show(
      context: context,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          // Parse capacity using German number format (1.234,56)
          final enteredCapacity = GermanNumberFormatter.parseGermanNumber(
            capacityController.text,
          );
          final calculatedPercentage = totalCapacity > 0
              ? (enteredCapacity / totalCapacity * 100)
              : 0.0;
          final wouldExceed =
              calculatedPercentage >
              maxAvailablePercentage + 0.5; // small tolerance
          final isValid = enteredCapacity > 0 && !wouldExceed;
          final sectionColor = _getSectionColor(index);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Big title with colored dot
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: sectionColor,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 12, height: 12),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isHopper
                              ? (AppLocalizations.of(context)?.editHopper ?? AppLocalizations.of(context)!.tr('Edit Hopper'))
                              : (isTanker
                                    ? AppLocalizations.of(context)?.editTank ?? AppLocalizations.of(context)!.tr('Edit Tank')
                                    : AppLocalizations.of(context)?.editSection ?? AppLocalizations.of(context)!.tr('Edit Section')),
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                    // Subtitle
                    Text(
                      '${AppLocalizations.of(context)?.maxCapacity ?? AppLocalizations.of(context)!.tr('Max')} ${maxAvailableCapacity.toStringAsFixed(0)} $unit',
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w400,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Big capacity input
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: TradeRepublicTextField(
                            controller: capacityController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.right,
                            autofocus: false,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                            ],
                            onChanged: (value) => setModalState(() {}),
                            style: TextStyle(
                              color: wouldExceed
                                  ? Colors.red
                                  : (isLight ? Colors.black : Colors.white),
                              fontSize: 56,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -2,
                            ),
                            hintText: hintText,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          unit,
                          style: TextStyle(
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),

                    // Percentage indicator
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: wouldExceed ? Colors.red : sectionColor,
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                        fontWeight: FontWeight.w600,
                      ),
                      child: Text(
                        '${calculatedPercentage.toStringAsFixed(1)}%',
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Name input
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.black.withOpacity(0.05)
                            : Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                      ),
                      child: TradeRepublicTextField(
                        controller: nameController,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                        hintText:
                            AppLocalizations.of(context)?.name ?? AppLocalizations.of(context)!.tr('Name'),
                      ),
                    ),

                    // Error message
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: wouldExceed
                          ? Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                AppLocalizations.of(
                                      context,
                                    )?.exceedsCapacity ?? AppLocalizations.of(context)!.tr('Exceeds capacity'),
                                style: TextStyle(
                                  color: Colors.red[400],
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 32),

                    // Save button
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)?.save ?? AppLocalizations.of(context)!.tr('Save'),
                      onPressed: isValid
                          ? () {
                              final name = nameController.text.trim();
                              setState(() {
                                _vehicleSections[index] = {
                                  ...section,
                                  'name': name.isEmpty
                                      ? (isHopper
                                            ? 'Hopper ${index + 1}'
                                            : (isTanker
                                                  ? 'Tank ${index + 1}'
                                                  : 'Section ${index + 1}'))
                                      : name,
                                  'percentage': calculatedPercentage.clamp(
                                    0.1,
                                    100.0,
                                  ),
                                };
                              });
                              HapticFeedback.lightImpact();
                              Navigator.pop(context);
                            }
                          : null,
                      width: double.infinity,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Edit section - wrapper for _showEditSectionModal
  void _editSection(int index, bool isLight) {
    if (index >= 0 && index < _vehicleSections.length) {
      _showEditSectionModal(_vehicleSections[index], index, isLight);
    }
  }

  // Confirm delete with bottom sheet - Trade Republic style
  void _confirmDeleteSection(int index, bool isLight) {
    if (index < 0 || index >= _vehicleSections.length) return;

    final section = _vehicleSections[index];
    final sectionName = section['name'] as String;

    HapticFeedback.mediumImpact();

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.trash,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.deleteSection ?? AppLocalizations.of(context)!.tr('Delete Section?'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Description
          Text(
            AppLocalizations.of(context)?.deleteSectionConfirm ?? AppLocalizations.of(context)!.tr('Are you sure you want to delete this section? This action cannot be undone.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),

          // Delete button
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.delete ?? AppLocalizations.of(context)!.tr('Delete'),
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(context);
              _deleteSection(index);
            },
            width: double.infinity,
            isDestructive: true,
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Cancel button
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            isSecondary: true,
          ),
        ],
      ),
    );
  }

  void _deleteSection(int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _vehicleSections.removeAt(index);
      // Update positions
      for (int i = 0; i < _vehicleSections.length; i++) {
        _vehicleSections[i]['position'] = i;
      }
    });
  }
}

// Grid Painter for the vehicle top view
class _GridPainter extends CustomPainter {
  final Color color;

  _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const spacing = 20.0;

    // Vertical lines
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Account Settings Modal
class _AccountSettingsModal extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? userData;
  final Function(Map<String, dynamic>) onSettingsUpdated;

  const _AccountSettingsModal({
    required this.isLight,
    required this.userData,
    required this.onSettingsUpdated,
  });

  @override
  State<_AccountSettingsModal> createState() => _AccountSettingsModalState();
}

class _AccountSettingsModalState extends State<_AccountSettingsModal> {
  bool _isBiometricEnabled = false;
  bool _is2FAEnabled = false;
  String? _generated2FACode;
  List<Map<String, dynamic>> _loginHistory = [];
  bool _isBiometricAvailable = false;

  // Waiting Time Settings
  int _waitingFreeMinutes = 15;
  double _waitingRatePerHour = 25.00;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadLoginHistory();
    _checkBiometricAvailability();
    _loadWaitingTimeSettings();
  }

  Future<void> _loadWaitingTimeSettings() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/driver/1/waiting-settings'),
        headers: {'Content-Type': 'application/json'},
      );

      if (!mounted) return; // Check if still mounted

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _waitingFreeMinutes = data['waiting_free_minutes'] ?? 15;
            _waitingRatePerHour = (data['waiting_rate_per_hour'] ?? 25.00)
                .toDouble();
          });
        }
      }
    } catch (e) {
      print('❌ Error loading waiting time settings: $e');
    }
  }

  Future<void> _saveWaitingTimeSettings() async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/driver/1/waiting-settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'waiting_free_minutes': _waitingFreeMinutes,
          'waiting_rate_per_hour': _waitingRatePerHour,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && mounted) {
          TopNotification.success(
            context,
            AppLocalizations.of(context)?.waitingTimeSettingsSaved ?? AppLocalizations.of(context)!.tr('Waiting time settings saved!'),
          );
        }
      } else {
        throw Exception('Failed to save settings');
      }
    } catch (e) {
      print('❌ Error saving waiting time settings: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToSaveWaitingTimeSettings ?? AppLocalizations.of(context)!.tr('Failed to save waiting time settings'),
        );
      }
    }
  }

  void _showFreeWaitingTimeSelector() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final List<int> waitingOptions = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120];

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.clock,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.freeWaitingTime ?? AppLocalizations.of(context)!.tr('Free Waiting Time'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: widget.isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              Text(
                AppLocalizations.of(context)?.freeWaitingTimeQuestion ?? AppLocalizations.of(context)!.tr('How long will you wait for free at pickup/delivery?'),
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  color: (widget.isLight ? Colors.black : Colors.white)
                      .withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ...waitingOptions.map(
                (minutes) => _buildWaitingOption(
                  minutes == 0
                      ? (AppLocalizations.of(context)?.noFreeWaiting ?? AppLocalizations.of(context)!.tr(''))
                      : '$minutes ${AppLocalizations.of(context)?.minutes ?? AppLocalizations.of(context)!.tr('')}',
                  minutes == _waitingFreeMinutes,
                  () {
                    setState(() {
                      _waitingFreeMinutes = minutes;
                    });
                    Navigator.pop(context);
                    _saveWaitingTimeSettings();
                  },
                ),
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            ],
          ),
        ),
      ),
    );
  }

  void _showWaitingRateSelector() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final List<double> rateOptions = [0, 10, 15, 20, 25, 30, 40, 50, 75, 100];

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.clock,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.hourlyWaitingRate ?? AppLocalizations.of(context)!.tr('Hourly Waiting Rate'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: widget.isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              Text(
                AppLocalizations.of(context)?.waitingRateQuestion ?? AppLocalizations.of(context)!.tr('How much per hour after free waiting time?'),
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  color: (widget.isLight ? Colors.black : Colors.white)
                      .withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ...rateOptions.map(
                (rate) => _buildWaitingOption(
                  rate == 0
                      ? (AppLocalizations.of(context)?.freeNoCharge ?? AppLocalizations.of(context)!.tr(''))
                      : '${Provider.of<AppSettings>(context, listen: false).formatCurrency(rate)}/hour',
                  rate == _waitingRatePerHour,
                  () {
                    setState(() {
                      _waitingRatePerHour = rate;
                    });
                    Navigator.pop(context);
                    _saveWaitingTimeSettings();
                  },
                ),
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingOption(
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TradeRepublicListTile(
        title: label,
        onTap: onTap,
        trailing: isSelected
            ? const Icon(CupertinoIcons.checkmark, size: 16)
            : null,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
  Future<void> _checkBiometricAvailability() async {
    try {
      final bool isDeviceSupported = await BiometricService.isDeviceSupported();

      if (!mounted) return; // Check if still mounted

      setState(() {
        _isBiometricAvailable = isDeviceSupported;
      });
    } catch (e) {
      print('Error checking biometric availability: $e');
      if (!mounted) return; // Check if still mounted
      setState(() {
        _isBiometricAvailable = false;
      });
    }
  }

  void _showAiRadiusSelector() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    // Determine user's unit system
    final useMiles = appSettings.effectiveDistanceUnit == 'Miles';
    const double milesPerKm = 0.621371;
    const double kmPerMile = 1.60934;

    // Work in user's preferred unit (convert stored km → user unit)
    double tempDisplayRadius = useMiles
        ? (appSettings.aiSuggestionRadius * milesPerKm).roundToDouble()
        : appSettings.aiSuggestionRadius;

    // Quick-select values in user's unit
    final List<double> quickSelects = useMiles
        ? [10.0, 25.0, 50.0, 100.0, 150.0]
        : [10.0, 25.0, 50.0, 100.0, 200.0];

    // Format a value in user's unit
    String fmtRadius(double v) =>
        useMiles ? '${v.toStringAsFixed(0)} mi' : '${v.toStringAsFixed(0)} km';

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          final bottomPadding = MediaQuery.of(context).padding.bottom;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.location,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.searchRadius ?? AppLocalizations.of(context)!.tr('Search Radius'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              Text(
                AppLocalizations.of(context)?.howFarSearchOrders ?? AppLocalizations.of(context)!.tr('How far should we search for open orders?'),
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  color: (isLight ? Colors.black : Colors.white)
                      .withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Current value display
              Text(
                fmtRadius(tempDisplayRadius),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 20),

              // Slider (works in user's unit)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                child: TradeRepublicContinuousSlider(
                  value: tempDisplayRadius,
                  min: 1,
                  max: useMiles ? 150 : 200,
                  divisions: useMiles ? 149 : 199,
                  labelBuilder: (v) => fmtRadius(v),
                  onChanged: (val) => setSheetState(() => tempDisplayRadius = val),
                ),
              ),

              // Min/Max labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      fmtRadius(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.4),
                      ),
                    ),
                    Text(
                      fmtRadius(useMiles ? 150 : 200),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Quick select buttons
              Padding(
                padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                child: Row(
                  children: quickSelects.map((radius) {
                    final isSelected = tempDisplayRadius.round() == radius.round();
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: TradeRepublicButton(
                          label: fmtRadius(radius),
                          onPressed: () {
                            setSheetState(() {
                              tempDisplayRadius = radius;
                            });
                          },
                          isSecondary: !isSelected,
                          width: double.infinity,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              // Save button
              Padding(
                padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)?.save ?? AppLocalizations.of(context)!.tr('Save'),
                  onPressed: () {
                    // Convert back to km for storage
                    final kmToSave = useMiles
                        ? tempDisplayRadius * kmPerMile
                        : tempDisplayRadius;
                    appSettings.setAiSuggestionRadius(kmToSave);
                    Navigator.pop(context);
                    if (mounted) {
                      TopNotification.success(
                        context,
                        '${AppLocalizations.of(context)?.radiusSetTo ?? AppLocalizations.of(context)!.tr('Search radius set to')} ${fmtRadius(tempDisplayRadius)}',
                      );
                    }
                  },
                  width: double.infinity,
                ),
              ),
              SizedBox(height: 16 + bottomPadding),
            ],
          );
        },
      ),
    );
  }

  Future<void> _loadSettings() async {
    // Load biometric setting availability
    final biometricEnabled = await BiometricService.isBiometricLoginAvailable();
    if (!mounted) return; // Check if still mounted after first async

    // Load 2FA settings from backend
    final twoFactorStatus = await TwoFactorService.getTwoFactorStatus();

    if (!mounted) return; // Check if still mounted

    setState(() {
      _isBiometricEnabled = biometricEnabled;
      _is2FAEnabled = twoFactorStatus?['twoFactorEnabled'] ?? false;
      _generated2FACode = twoFactorStatus?['twoFactorCode'];
    });
  }

  Future<void> _loadLoginHistory() async {
    try {
      print('📊 Loading login history from Google Cloud...');

      // Get auth token and userId
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final userId =
          widget.userData?['userId'] ??
          widget.userData?['email'] ??
          prefs.getString('user_id');

      if (userId == null) {
        print('❌ No userId found');
        return;
      }

      print('🔑 Loading history for user: $userId');
      print(
        '🌐 API URL: ${ApiConfig.baseUrl}/api/driver/$userId/login-history',
      );

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/$userId/login-history'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('📡 Login history response: ${response.statusCode}');
      print('📡 Login history body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> history = data['data'] ?? [];

        print('✅ Found ${history.length} login history entries');
        print('📋 First entry: ${history.isNotEmpty ? history.first : "none"}');

        if (!mounted) return; // Check if still mounted

        setState(() {
          _loginHistory = history.map((item) {
            // Parse the loginTime string to DateTime
            DateTime? loginTime;
            try {
              loginTime = DateTime.parse(item['loginTime']);
            } catch (e) {
              print('⚠️ Failed to parse loginTime: ${item['loginTime']}');
              loginTime = DateTime.now();
            }

            return {
              'id': item['id'],
              'username': item['username'],
              'loginTime': loginTime,
              'userAgent': item['userAgent'] ?? (AppLocalizations.of(context)?.unknownDevice ?? AppLocalizations.of(context)!.tr('')),
            };
          }).toList();
        });

        print('✅ Login history loaded: ${_loginHistory.length} entries');
      } else {
        print('❌ Failed to load login history: ${response.body}');
        if (!mounted) return; // Check if still mounted
        setState(() {
          _loginHistory = [];
        });
      }
    } catch (e, stackTrace) {
      print('❌ Error loading login history: $e');
      print('📋 Stack trace: $stackTrace');
      if (!mounted) return; // Check if still mounted
      setState(() {
        _loginHistory = [];
      });
    }
  }

  Future<void> _handle2FAToggle() async {
    await TwoFactorSetupBottomSheet.show(
      context,
      isEnabled: _is2FAEnabled,
      onSuccess: () {
        _loadSettings(); // Reload settings after successful change
      },
    );

    // Always reload settings after bottom sheet closes
    _loadSettings();
  }

  Future<void> _toggleBiometric(bool value) async {
    if (!_isBiometricAvailable) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.biometricNotAvailableOnDevice ?? AppLocalizations.of(context)!.tr('Biometric authentication is not available on this device'),
        title: AppLocalizations.of(context)?.notAvailable ?? AppLocalizations.of(context)!.tr('Not Available'),
      );
      return;
    }

    if (value) {
      // Enable biometric authentication
      final bool success = await BiometricService.enableBiometric();

      if (success) {
        setState(() {
          _isBiometricEnabled = true;
        });
        _saveSettings();

        TopNotification.success(
          context,
          AppLocalizations.of(context)?.biometricAuthEnabledSuccessfully ?? AppLocalizations.of(context)!.tr('Biometric authentication enabled successfully!'),
          title: AppLocalizations.of(context)?.success ?? AppLocalizations.of(context)!.tr('Success'),
        );
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.biometricVerificationFailed ?? AppLocalizations.of(context)!.tr('Biometric verification failed. Please try again.'),
          title:
              AppLocalizations.of(context)?.verificationFailed ?? AppLocalizations.of(context)!.tr('Verification Failed'),
        );
      }
    } else {
      // Disable biometric authentication
      final bool success = await BiometricService.disableBiometric();

      if (success) {
        setState(() {
          _isBiometricEnabled = false;
        });
        _saveSettings();

        TopNotification.success(
          context,
          AppLocalizations.of(context)?.biometricAuthDisabledSuccessfully ?? AppLocalizations.of(context)!.tr('Biometric authentication disabled successfully!'),
          title: AppLocalizations.of(context)?.disabled ?? AppLocalizations.of(context)!.tr('Disabled'),
        );
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(
                context,
              )?.biometricVerificationRequiredToDisable ?? AppLocalizations.of(context)!.tr('Biometric verification required to disable this feature'),
          title:
              AppLocalizations.of(context)?.verificationRequired ?? AppLocalizations.of(context)!.tr('Verification Required'),
        );
      }
    }
  }

  void _saveSettings() {
    final settings = {
      'biometricEnabled': _isBiometricEnabled,
      'twoFactorEnabled': _is2FAEnabled,
      'twoFactorCode': _generated2FACode,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    widget.onSettingsUpdated(settings);
  }

  void _showChangePasswordModal() {
    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: true,
      showDragHandle: true,
      child: _ChangePasswordModal(
        isLight: widget.isLight,
        onPasswordChanged: (oldPassword, newPassword) {
          _changePassword(oldPassword, newPassword);
        },
      ),
    );
  }

  Future<void> _changePassword(String oldPassword, String newPassword) async {
    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 2));

      // In real app, would make HTTP request to change password
      TopNotification.success(
        context,
        AppLocalizations.of(context)?.passwordChangedSuccessfully ?? AppLocalizations.of(context)!.tr('Password changed successfully!'),
      );
    } catch (e) {
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorChangingPassword ?? AppLocalizations.of(context)!.tr('Error changing password')}: $e',
      );
    }
  }

  Future<void> _testBiometric() async {
    final bool success = await BiometricService.testBiometric();

    if (success) {
      TopNotification.success(
        context,
        AppLocalizations.of(context)?.biometricTestSuccessful ?? AppLocalizations.of(context)!.tr('Biometric test successful!'),
        title: AppLocalizations.of(context)?.testPassed ?? AppLocalizations.of(context)!.tr('Test Passed'),
      );
    } else {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.biometricTestFailed ?? AppLocalizations.of(context)!.tr('Biometric test failed'),
        title: AppLocalizations.of(context)?.testFailed ?? AppLocalizations.of(context)!.tr('Test Failed'),
      );
    }
  }

  void _show2FAModal() {
    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: true,
      showDragHandle: true,
      child: _TwoFactorModal(
        isLight: widget.isLight,
        currentCode: _generated2FACode,
        onToggle2FA: _handle2FAToggle,
        isEnabled: _is2FAEnabled,
      ),
    );
  }

  void _showLoginHistoryModal() {
    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: true,
      showDragHandle: true,
      child: _LoginHistoryModal(
        isLight: widget.isLight,
        loginHistory: _loginHistory,
      ),
    );
  }

  void _showDeleteAccountConfirmation(BuildContext parentContext) {
    final TextEditingController passwordController = TextEditingController();
    bool isPasswordVisible = false;
    bool isLoading = false;

    TradeRepublicBottomSheet.show(
      context: parentContext,
      enableDrag: true,
      isDismissible: true,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.9,
            child: Column(
              children: [
                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        // Warning Icon
                        Container(
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.exclamationmark_triangle,
                            color: Colors.red,
                            size: 48,
                          ),
                        ),

                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                        // Title
                        Text(
                          AppLocalizations.of(context)?.deleteAccountQuestion ?? AppLocalizations.of(context)!.tr('Delete Account?'),
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),

                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                        // Warning message
                        Text(
                          AppLocalizations.of(
                                context,
                              )?.permanentDeleteWarning ?? AppLocalizations.of(context)!.tr('This action is permanent and cannot be undone. All your data will be deleted from our servers.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color:
                                (widget.isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6),
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Password field
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isLight ? Colors.white : Colors.black,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: TradeRepublicTextField(
                            controller: passwordController,
                            filled: false,
                            obscureText: !isPasswordVisible,
                            enabled: !isLoading,
                            style: TextStyle(
                              color: widget.isLight
                                  ? Colors.black
                                  : Colors.white,
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                            ),
                            hintText:
                                AppLocalizations.of(
                                  context,
                                )?.enterYourPasswordToConfirm ?? AppLocalizations.of(context)!.tr('Enter your password to confirm'),
                            prefixIcon: Icon(
                              CupertinoIcons.lock,
                              color:
                                  (widget.isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.6),
                            ),
                            suffixIcon: TradeRepublicButton.icon(
                              size: 36,
                              isSecondary: true,
                              foregroundColor: (widget.isLight
                                      ? Colors.black
                                      : Colors.white)
                                  .withOpacity(0.6),
                              icon: Icon(
                                isPasswordVisible
                                    ? CupertinoIcons.eye_slash
                                    : CupertinoIcons.eye,
                              ),
                              onPressed: () {
                                setModalState(() {
                                  isPasswordVisible = !isPasswordVisible;
                                });
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                        // Warning checklist
                        Container(
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.whatWillBeDeleted ?? AppLocalizations.of(context)!.tr('What will be deleted:'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: widget.isLight
                                      ? Colors.black
                                      : Colors.white,
                                ),
                              ),
                              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                              _buildDeletedItem(
                                AppLocalizations.of(
                                      context,
                                    )?.allPersonalInformation ?? AppLocalizations.of(context)!.tr('All personal information'),
                              ),
                              _buildDeletedItem(
                                AppLocalizations.of(
                                      context,
                                    )?.deliveryHistoryAndRecords ?? AppLocalizations.of(context)!.tr('Delivery history and records'),
                              ),
                              _buildDeletedItem(
                                AppLocalizations.of(
                                      context,
                                    )?.vehicleAndPaymentInfo ?? AppLocalizations.of(context)!.tr('Vehicle and payment information'),
                              ),
                              _buildDeletedItem(
                                AppLocalizations.of(
                                      context,
                                    )?.groupMemberships ?? AppLocalizations.of(context)!.tr('Group memberships'),
                              ),
                              _buildDeletedItem(
                                AppLocalizations.of(
                                      context,
                                    )?.loginCredentialsAndSettings ?? AppLocalizations.of(context)!.tr('Login credentials and settings'),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                      ],
                    ),
                  ),
                ),

                // Bottom buttons - fixed at bottom
                Padding(
                  padding: DesktopAppWrapper.getPagePadding(),
                  child: Column(
                    children: [
                      // Delete account button
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)?.deleteAccount ?? AppLocalizations.of(context)!.tr('Delete Account'),
                        isDestructive: true,
                        isLoading: isLoading,
                        width: double.infinity,
                        onPressed: isLoading
                            ? null
                            : () async {
                                if (passwordController.text.trim().isEmpty) {
                                  TopNotification.error(
                                    context,
                                    AppLocalizations.of(
                                          context,
                                        )?.pleaseEnterYourPassword ?? AppLocalizations.of(context)!.tr('Please enter your password'),
                                  );
                                  return;
                                }

                                setModalState(() {
                                  isLoading = true;
                                });

                                await _deleteAccount(
                                  passwordController.text.trim(),
                                  context,
                                  parentContext,
                                );

                                setModalState(() {
                                  isLoading = false;
                                });
                              },
                      ),

                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      // Cancel button
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                        onPressed: isLoading
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                Navigator.pop(context);
                              },
                        isSecondary: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeletedItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(CupertinoIcons.xmark, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                color: (widget.isLight ? Colors.black : Colors.white)
                    .withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(
    String password,
    BuildContext modalContext,
    BuildContext parentContext,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        if (modalContext.mounted) {
          TopNotification.error(modalContext, AppLocalizations.of(modalContext)?.authTokenNotFound ?? AppLocalizations.of(context)!.tr('Authentication token not found'));
        }
        return;
      }

      print('🗑️ Attempting to delete account...');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/account-delete'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'password': password}),
      );

      print('🗑️ Delete account response status: ${response.statusCode}');
      print('🗑️ Response body: ${response.body}');

      if (response.statusCode == 200) {
        // Account deleted successfully
        print('✅ Account deleted successfully');

        // Clear all local data
        await prefs.clear();

        // Show success message
        if (modalContext.mounted) {
          TopNotification.success(
            modalContext,
            AppLocalizations.of(context)?.accountDeletedSuccessfully ?? AppLocalizations.of(context)!.tr('Account deleted successfully'),
          );
          Navigator.pop(modalContext); // Close delete confirmation modal
        }

        // Close settings modal and navigate to login
        if (parentContext.mounted) {
          Navigator.of(parentContext).pop(); // Close account settings modal

          // Navigate to login page (assuming you have a named route)
          Navigator.of(
            parentContext,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      } else {
        final errorData = json.decode(response.body);
        final errorMessage =
            errorData['message'] ??
            (AppLocalizations.of(context)?.failedToDeleteAccount ?? AppLocalizations.of(context)!.tr('Failed to delete account'));

        if (modalContext.mounted) {
          TopNotification.error(modalContext, errorMessage);
        }
      }
    } catch (e) {
      print(
        '${AppLocalizations.of(context)?.errorDeletingAccount ?? AppLocalizations.of(context)!.tr('Error deleting account')}: $e',
      );
      if (modalContext.mounted) {
        TopNotification.error(
          modalContext,
          AppLocalizations.of(context)?.failedToDeleteAccountTryAgain ?? AppLocalizations.of(context)!.tr('Failed to delete account. Please try again.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 1,
      child: Column(
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.settings,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.accountSettings ?? AppLocalizations.of(context)!.tr('Account Settings'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Security Section
                  _buildSectionHeader(
                    AppLocalizations.of(context)?.securityAndAuthentication ?? AppLocalizations.of(context)!.tr('Security & Authentication'),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Biometric Authentication
                  _buildSettingsTile(
                    icon: CupertinoIcons.person_crop_circle,
                    title:
                        AppLocalizations.of(context)?.biometricAuthentication ?? AppLocalizations.of(context)!.tr('Biometric Authentication'),
                    subtitle: _isBiometricAvailable
                        ? (_isBiometricEnabled
                          ? (AppLocalizations.of(context)?.enabledTapToTest ?? AppLocalizations.of(context)!.tr(''))
                              : 'Use fingerprint or face ID to unlock')
                        : AppLocalizations.of(
                                context,
                              )?.notAvailableOnThisDevice ?? AppLocalizations.of(context)!.tr('Not available on this device'),
                    trailing: _isBiometricAvailable
                        ? TradeRepublicSwitch(
                            value: _isBiometricEnabled,
                            onChanged: _toggleBiometric,
                            selectedLabel: 'Y',
                            unselectedLabel: 'N',
                          )
                        : Icon(
                            CupertinoIcons.nosign,
                            color: widget.isLight ? Colors.black : Colors.white,
                            size: 20,
                          ),
                    onTap: _isBiometricEnabled && _isBiometricAvailable
                        ? _testBiometric
                        : null,
                  ),

                  // Two Factor Authentication
                  _buildSettingsTile(
                    icon: CupertinoIcons.shield,
                    title:
                        AppLocalizations.of(context)?.twoFactorAuthentication ?? AppLocalizations.of(context)!.tr('Two-Factor Authentication'),
                    subtitle: _is2FAEnabled
                      ? (AppLocalizations.of(context)?.enabled ?? AppLocalizations.of(context)!.tr(''))
                        : AppLocalizations.of(context)?.addExtraSecurityLayer ?? AppLocalizations.of(context)!.tr('Add extra security layer'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 16,
                    ),
                    onTap: _show2FAModal,
                  ),

                  // Change Password
                  _buildSettingsTile(
                    icon: CupertinoIcons.lock,
                    title:
                        AppLocalizations.of(context)?.changePassword ?? AppLocalizations.of(context)!.tr('Change Password'),
                    subtitle:
                        AppLocalizations.of(context)?.updateYourLoginPassword ?? AppLocalizations.of(context)!.tr('Update your login password'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 16,
                    ),
                    onTap: _showChangePasswordModal,
                  ),

                  const SizedBox(height: 32),

                  // Activity Section
                  _buildSectionHeader(
                    AppLocalizations.of(context)?.accountActivity ?? AppLocalizations.of(context)!.tr('Account Activity'),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Login History
                  _buildSettingsTile(
                    icon: CupertinoIcons.clock,
                    title:
                        AppLocalizations.of(context)?.loginHistory ?? AppLocalizations.of(context)!.tr('Login History'),
                    subtitle:
                        AppLocalizations.of(
                          context,
                        )?.viewRecentAccountActivity ?? AppLocalizations.of(context)!.tr('View recent account activity'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 16,
                    ),
                    onTap: _showLoginHistoryModal,
                  ),

                  const SizedBox(height: 32),

                  // Waiting Time Settings Section
                  _buildSectionHeader(
                    AppLocalizations.of(context)?.waitingTimeCharges ?? AppLocalizations.of(context)!.tr('Waiting Time Charges'),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Free Waiting Time
                  _buildSettingsTile(
                    icon: CupertinoIcons.timer,
                    title:
                        AppLocalizations.of(context)?.freeWaitingTime ?? AppLocalizations.of(context)!.tr('Free Waiting Time'),
                    subtitle:
                        '$_waitingFreeMinutes ${AppLocalizations.of(context)?.waitingFreeMinutesLabel ?? AppLocalizations.of(context)!.tr('minutes')}',
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 16,
                    ),
                    onTap: _showFreeWaitingTimeSelector,
                  ),

                  // Hourly Rate After Free Time
                  _buildSettingsTile(
                    icon: CupertinoIcons.money_dollar,
                    title:
                        AppLocalizations.of(context)?.rateAfterFreeTime ?? AppLocalizations.of(context)!.tr('Rate After Free Time'),
                    subtitle:
                        '${Provider.of<AppSettings>(context, listen: false).formatCurrency(_waitingRatePerHour)}/hour',
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 16,
                    ),
                    onTap: _showWaitingRateSelector,
                  ),

                  // Info text
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Text(
                      '${AppLocalizations.of(context)?.freeWaitingTimeQuestion ?? AppLocalizations.of(context)!.tr('Waiting time')}: $_waitingFreeMinutes min',
                      style: TextStyle(
                        fontSize: 13,
                        color: (widget.isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // AI Order Suggestions Section
                  _buildSectionHeader(AppLocalizations.of(context)?.aiOrderSuggestions ?? AppLocalizations.of(context)!.tr('AI Order Suggestions')),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Enable/Disable AI Suggestions
                  Builder(
                    builder: (context) {
                      final appSettings = Provider.of<AppSettings>(context);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TradeRepublicListTile.toggle(
                          title: AppLocalizations.of(context)?.automaticSuggestions ?? AppLocalizations.of(context)!.tr('Automatic Suggestions'),
                          subtitle: appSettings.lastMileEnabled
                              ? AppLocalizations.of(context)?.aiSuggestsNearbyOrders ?? AppLocalizations.of(context)!.tr('AI suggests nearby orders')
                              : AppLocalizations.of(context)?.noAutomaticSuggestions ?? AppLocalizations.of(context)!.tr('No automatic suggestions'),
                          leading: Icon(Icons.auto_awesome_rounded, size: 20),
                          value: appSettings.lastMileEnabled,
                          onChanged: (val) => appSettings.setLastMileEnabled(val),
                        ),
                      );
                    },
                  ),

                  // Radius Selector
                  Builder(
                    builder: (context) {
                      final appSettings = Provider.of<AppSettings>(context);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TradeRepublicListTile.navigation(
                          title: AppLocalizations.of(context)?.searchRadius ?? AppLocalizations.of(context)!.tr('Search Radius'),
                          subtitle: appSettings.formatDistance(appSettings.aiSuggestionRadius),
                          leading: Icon(CupertinoIcons.location_circle, size: 20),
                          onTap: () => _showAiRadiusSelector(),
                        ),
                      );
                    },
                  ),

                  // Info text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text(
                      AppLocalizations.of(context)?.aiSuggestionInfoText ?? AppLocalizations.of(context)!.tr('During navigation, AI automatically suggests nearby open orders. You can place a bid directly.'),
                      style: TextStyle(
                        fontSize: 13,
                        color: (widget.isLight ? Colors.black : Colors.white).withOpacity(0.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Privacy Section
                  _buildSectionHeader(
                    AppLocalizations.of(context)?.privacyAndData ?? AppLocalizations.of(context)!.tr('Privacy & Data'),
                  ),
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Download Data
                  _buildSettingsTile(
                    icon: CupertinoIcons.arrow_down_to_line,
                    title:
                        AppLocalizations.of(context)?.downloadMyData ?? AppLocalizations.of(context)!.tr('Download My Data'),
                    subtitle:
                        AppLocalizations.of(
                          context,
                        )?.exportAllYourAccountData ?? AppLocalizations.of(context)!.tr('Export all your account data'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      size: 16,
                    ),
                    onTap: () {
                      TopNotification.info(
                        context,
                        AppLocalizations.of(context)!.tr('Data export feature coming soon!') ?? AppLocalizations.of(context)!.tr('Data export feature coming soon!'),
                      );
                    },
                  ),

                  // Delete Account
                  _buildSettingsTile(
                    icon: CupertinoIcons.delete,
                    title:
                        AppLocalizations.of(context)?.deleteAccount ?? AppLocalizations.of(context)!.tr('Delete Account'),
                    subtitle:
                        AppLocalizations.of(
                          context,
                        )?.permanentlyDeleteYourAccount ?? AppLocalizations.of(context)!.tr('Permanently delete your account'),
                    trailing: Icon(
                      CupertinoIcons.chevron_right,
                      color: Colors.red.withOpacity(0.7),
                      size: 16,
                    ),
                    isDestructive: true,
                    onTap: () {
                      _showDeleteAccountConfirmation(context);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return TradeRepublicSectionHeader(
      title: title,
      padding: const EdgeInsets.only(bottom: 0),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TradeRepublicListTile(
        title: title,
        subtitle: subtitle,
        leading: Icon(
          icon,
          size: 20,
          color: isDestructive ? Colors.red : null,
        ),
        trailing: trailing,
        onTap: onTap,
        titleColor: isDestructive ? TradeRepublicTheme.destructiveRed : null,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

// Change Password Modal
class _ChangePasswordModal extends StatefulWidget {
  final bool isLight;
  final Function(String, String) onPasswordChanged;

  const _ChangePasswordModal({
    required this.isLight,
    required this.onPasswordChanged,
  });

  @override
  State<_ChangePasswordModal> createState() => _ChangePasswordModalState();
}

class _ChangePasswordModalState extends State<_ChangePasswordModal> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isCurrentPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _changePassword() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      widget.onPasswordChanged(
        _currentPasswordController.text,
        _newPasswordController.text,
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.lock,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.changePassword ?? AppLocalizations.of(context)!.tr('Change Password'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Current Password
                    _buildPasswordField(
                      AppLocalizations.of(context)?.currentPassword ?? AppLocalizations.of(context)!.tr('Current Password'),
                      _currentPasswordController,
                      _isCurrentPasswordVisible,
                      (value) =>
                          setState(() => _isCurrentPasswordVisible = value),
                    ),
                    const SizedBox(height: 20),

                    // New Password
                    _buildPasswordField(
                      AppLocalizations.of(context)?.newPassword ?? AppLocalizations.of(context)!.tr('New Password'),
                      _newPasswordController,
                      _isNewPasswordVisible,
                      (value) => setState(() => _isNewPasswordVisible = value),
                      validator: (value) {
                        if (value == null || value.length < 8) {
                          return AppLocalizations.of(
                                context,
                              )?.passwordAtLeast8Characters ?? AppLocalizations.of(context)!.tr('Password must be at least 8 characters');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Confirm Password
                    _buildPasswordField(
                      AppLocalizations.of(context)?.confirmNewPassword ?? AppLocalizations.of(context)!.tr('Confirm New Password'),
                      _confirmPasswordController,
                      _isConfirmPasswordVisible,
                      (value) =>
                          setState(() => _isConfirmPasswordVisible = value),
                      validator: (value) {
                        if (value != _newPasswordController.text) {
                          return AppLocalizations.of(
                                context,
                              )?.passwordsDoNotMatch ?? AppLocalizations.of(context)!.tr('Passwords do not match');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    // Password Requirements
                    Container(
                      padding: DesktopAppWrapper.getPagePadding(),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(
                                  context,
                                )?.passwordRequirements ?? AppLocalizations.of(context)!.tr('Password Requirements:'),
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w600,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          _buildRequirement('At least 8 characters long'),
                          _buildRequirement(
                            AppLocalizations.of(
                                  context,
                                )?.containsUppercaseLowercase ?? AppLocalizations.of(context)!.tr('Contains uppercase and lowercase letters'),
                          ),
                          _buildRequirement('Contains at least one number'),
                          _buildRequirement(
                            AppLocalizations.of(
                                  context,
                                )?.containsSpecialCharacter ?? AppLocalizations.of(context)!.tr('Contains at least one special character'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: TradeRepublicButton(
                label: _isLoading
                    ? 'Changing...'
                    : AppLocalizations.of(context)?.changePassword ?? AppLocalizations.of(context)!.tr('Change Password'),
                onPressed: _isLoading ? null : _changePassword,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField(
    String label,
    TextEditingController controller,
    bool isVisible,
    Function(bool) onVisibilityToggle, {
    String? Function(String?)? validator,
  }) {
    return TradeRepublicTextField(
      useFormField: true,
      controller: controller,
      obscureText: !isVisible,
      validator:
          validator ??
          (value) {
            if (value == null || value.isEmpty) {
              return '$label is required';
            }
            return null;
          },
      style: TextStyle(color: widget.isLight ? Colors.black : Colors.white),
      hintStyle: TextStyle(
        color: (widget.isLight ? Colors.black : Colors.white).withOpacity(0.5),
      ),
      labelText: label,
      filled: true,
      fillColor: Colors.transparent,
      suffixIcon: TradeRepublicButton.icon(
        size: 36,
        isSecondary: true,
        foregroundColor: (widget.isLight ? Colors.black : Colors.white)
            .withOpacity(0.7),
        onPressed: () => onVisibilityToggle(!isVisible),
        icon: Icon(
          isVisible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
        ),
      ),
    );
  }

  Widget _buildRequirement(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(CupertinoIcons.checkmark_circle, color: Colors.blue, size: 16),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.blue)),
        ],
      ),
    );
  }
}

// Two Factor Authentication Modal
class _TwoFactorModal extends StatefulWidget {
  final bool isLight;
  final String? currentCode;
  final VoidCallback onToggle2FA;
  final bool isEnabled;

  const _TwoFactorModal({
    required this.isLight,
    required this.currentCode,
    required this.onToggle2FA,
    required this.isEnabled,
  });

  @override
  State<_TwoFactorModal> createState() => _TwoFactorModalState();
}

class _TwoFactorModalState extends State<_TwoFactorModal> {
  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        // ── Sheet header: Icon left + Title ──
        Row(
          children: [
            Icon(
              CupertinoIcons.shield,
              size: 22,
              color: isLight ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(context)?.twoFactorAuthentication ?? AppLocalizations.of(context)!.tr('Two-Factor Authentication'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

        // Status
        Container(
          width: double.infinity,
          padding: DesktopAppWrapper.getPagePadding(),
          decoration: BoxDecoration(
            color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
              0.05,
            ),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Row(
            children: [
              Icon(
                widget.isEnabled
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.shield,
                color: widget.isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.isEnabled ? '2FA is enabled' : '2FA is disabled',
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: widget.isLight ? Colors.black : Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

        // Action Button
        SizedBox(
          width: double.infinity,
          child: TradeRepublicButton(
            label: widget.isEnabled ? AppLocalizations.of(context)?.manage2FASettings ?? AppLocalizations.of(context)!.tr('Manage 2FA Settings') : AppLocalizations.of(context)?.enableTwoFactorAuth ?? AppLocalizations.of(context)!.tr('Enable 2FA'),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onToggle2FA();
            },
          ),
        ),
      ],
    );
  }
}

// Login History Modal
class _LoginHistoryModal extends StatefulWidget {
  final bool isLight;
  final List<Map<String, dynamic>> loginHistory;

  const _LoginHistoryModal({required this.isLight, required this.loginHistory});

  @override
  State<_LoginHistoryModal> createState() => _LoginHistoryModalState();
}

class _LoginHistoryModalState extends State<_LoginHistoryModal> {
  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.clock,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.loginHistory ?? AppLocalizations.of(context)!.tr('Login History'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Subtitle
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context)?.recentLoginActivity ?? AppLocalizations.of(context)!.tr('Recent login activity'),
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                color: widget.isLight ? Colors.black : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Login History List
          Expanded(
            child: widget.loginHistory.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.clock,
                          size: 64,
                          color: widget.isLight ? Colors.white : Colors.black,
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                        Text(
                          AppLocalizations.of(context)?.noLoginHistory ?? AppLocalizations.of(context)!.tr('No login history'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: widget.loginHistory.length,
                    itemBuilder: (context, index) {
                      final login = widget.loginHistory[index];
                      return _buildLoginHistoryItem(login);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginHistoryItem(Map<String, dynamic> login) {
    // Safe null handling for loginTime
    final loginTime = login['loginTime'] as DateTime?;
    if (loginTime == null) {
      return const SizedBox.shrink(); // Skip this item if no valid loginTime
    }

    final userAgent =
      (login['userAgent'] as String?) ?? (AppLocalizations.of(context)?.unknownDevice ?? AppLocalizations.of(context)!.tr(''));

    // Parse device info from user agent
    String deviceInfo = _parseDeviceFromUserAgent(userAgent);
    bool isAutoLogin = userAgent.contains('auto-login');

    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        children: [
          // Device Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Icon(
              _getDeviceIcon(userAgent),
              color: widget.isLight ? Colors.black87 : Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),

          // Login Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        deviceInfo,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: widget.isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (isAutoLogin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.autoMode ?? AppLocalizations.of(context)!.tr('Auto'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(loginTime),
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isLight ? Colors.black : Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // Success indicator
          Icon(
            CupertinoIcons.checkmark_circle_fill,
            color: Colors.green,
            size: 20,
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String userAgent) {
    final ua = userAgent.toLowerCase();
    if (ua.contains('iphone') || ua.contains('ipad')) {
      return CupertinoIcons.device_phone_portrait;
    } else if (ua.contains('android')) {
      return CupertinoIcons.device_phone_portrait;
    } else if (ua.contains('dart')) {
      return CupertinoIcons.device_phone_portrait;
    } else if (ua.contains('mac')) {
      return CupertinoIcons.device_laptop;
    } else if (ua.contains('windows')) {
      return CupertinoIcons.device_laptop;
    } else {
      return CupertinoIcons.desktopcomputer;
    }
  }

  String _parseDeviceFromUserAgent(String userAgent) {
    if (userAgent.contains('Dart/')) {
      return AppLocalizations.of(context)?.flutterApp ?? AppLocalizations.of(context)!.tr('Flutter App');
    } else if (userAgent.contains('iPhone')) {
      return 'iPhone';
    } else if (userAgent.contains('iPad')) {
      return 'iPad';
    } else if (userAgent.contains('Android')) {
      return AppLocalizations.of(context)?.androidDevice ?? AppLocalizations.of(context)!.tr('Android Device');
    } else if (userAgent.contains('curl')) {
      return AppLocalizations.of(context)?.apiClient ?? AppLocalizations.of(context)!.tr('API Client');
    } else {
      return AppLocalizations.of(context)?.unknownDevice ?? AppLocalizations.of(context)!.tr('Unknown Device');
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return AppLocalizations.of(context)?.justNow ?? AppLocalizations.of(context)!.tr('Just now');
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} ${AppLocalizations.of(context)?.minutesAgo ?? AppLocalizations.of(context)!.tr('minutes ago')}';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} ${AppLocalizations.of(context)?.hoursAgo ?? AppLocalizations.of(context)!.tr('hours ago')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ${AppLocalizations.of(context)?.daysAgo ?? AppLocalizations.of(context)!.tr('days ago')}';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${AppLocalizations.of(context)?.weeksAgo ?? AppLocalizations.of(context)!.tr('weeks ago')}';
    } else {
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      return appSettings.formatDate(timestamp);
    }
  }
}

// Profile Image Upload Modal - Settings Style
class _ProfileImageUploadModal extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? userData;
  final Function(String) onImageUploaded;

  const _ProfileImageUploadModal({
    required this.isLight,
    required this.userData,
    required this.onImageUploaded,
  });

  @override
  State<_ProfileImageUploadModal> createState() =>
      _ProfileImageUploadModalState();
}

class _ProfileImageUploadModalState extends State<_ProfileImageUploadModal> {
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImageFromCamera() async {
    // Camera not supported on macOS
    if (Platform.isMacOS) {
      if (mounted) {
        TopNotification.info(
          context,
          AppLocalizations.of(context)!.tr('Camera is not available on macOS. Please use Gallery.') ?? AppLocalizations.of(context)!.tr('Camera is not available on macOS. Please use Gallery.'),
        );
      }
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image != null) {
        print('📸 Camera image selected: ${image.path}');
        print('📸 Image name: ${image.name}');
        await _uploadImage(image.path);
      }
    } catch (e) {
      print('❌ Camera error: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.cameraAccessFailed ?? AppLocalizations.of(context)!.tr('Camera access failed')}: $e',
        );
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        print('📸 Gallery image selected: ${image.path}');
        print('📸 Image name: ${image.name}');
        await _uploadImage(image.path);
      }
    } catch (e) {
      print('❌ Gallery error: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.galleryAccessFailed ?? AppLocalizations.of(context)!.tr('Gallery access failed')}: $e',
        );
      }
    }
  }

  Future<void> _uploadImage(String imagePath) async {
    setState(() {
      _isUploading = true;
    });

    try {
      // Get username - backend expects username, not userId
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');

      if (username == null) {
        throw Exception('Username not found. Please log in again.');
      }

      // Get auth token
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('Authentication token not found');
      }

      print('📸 Uploading profile image for username: $username');

      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/profile-image'),
      );

      // Add headers (don't set Content-Type manually for multipart)
      request.headers.addAll({'Authorization': 'Bearer $token'});

      // Add userId field - backend expects field named 'userId' (but value is username string)
      request.fields['userId'] = username;

      // Determine file extension and content type
      String fileExtension = imagePath.toLowerCase().split('.').last;
      String contentType = 'image/jpeg'; // Default

      if (fileExtension == 'png') {
        contentType = 'image/png';
      } else if (fileExtension == 'jpg' || fileExtension == 'jpeg') {
        contentType = 'image/jpeg';
      } else if (fileExtension == 'gif') {
        contentType = 'image/gif';
      } else if (fileExtension == 'webp') {
        contentType = 'image/webp';
      }

      print('📸 Image details: $imagePath');
      print('📸 File extension: $fileExtension');
      print('📸 Content type: $contentType');

      // Add file with proper content type
      final multipartFile = await http.MultipartFile.fromPath(
        'profileImage',
        imagePath,
        filename:
            'profile_${username}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension',
        contentType: MediaType.parse(contentType),
      );

      request.files.add(multipartFile);

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📡 Profile image upload response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true &&
            responseData['imageUrl'] != null) {
          final imageUrl = responseData['imageUrl'];

          if (mounted) {
            TopNotification.success(
              context,
              AppLocalizations.of(context)?.profileImageUpdated ?? AppLocalizations.of(context)!.tr('Profile image updated successfully!'),
            );
            widget.onImageUploaded(imageUrl);
            Navigator.pop(context);
          }
        } else {
          throw Exception(responseData['message'] ?? AppLocalizations.of(context)!.tr('Upload failed'));
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? AppLocalizations.of(context)!.tr('Upload failed'));
      }
    } catch (e) {
      print('❌ Error uploading profile image: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.failedToUploadImage ?? AppLocalizations.of(context)!.tr('Failed to upload image')}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _removeProfileImage() async {
    setState(() {
      _isUploading = true;
    });

    try {
      // Get user ID
      final userId =
          widget.userData?['user_id'] ??
          widget.userData?['userId'] ??
          widget.userData?['id'];

      if (userId == null) {
        throw Exception('User ID not found');
      }

      // Get auth token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        throw Exception('Authentication token not found');
      }

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/profile-image'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'userId': userId}),
      );

      print('📡 Remove profile image response: ${response.statusCode}');

      if (response.statusCode == 200) {
        if (mounted) {
          TopNotification.success(
            context,
            AppLocalizations.of(context)?.profileImageRemoved ?? AppLocalizations.of(context)!.tr('Profile image removed successfully!'),
          );
          widget.onImageUploaded(''); // Empty string means no image
          Navigator.pop(context);
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? AppLocalizations.of(context)!.tr('Remove failed'));
      }
    } catch (e) {
      print('❌ Error removing profile image: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.failedToRemoveImage ?? AppLocalizations.of(context)!.tr('Failed to remove image')}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Sheet header: Icon left + Title ──
        Row(
          children: [
            Icon(
              CupertinoIcons.camera,
              size: 22,
              color: isLight ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.of(context)?.profilePhoto ?? AppLocalizations.of(context)!.tr('Profile Photo'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: widget.isLight ? Colors.black : Colors.white,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        // Scrollable content
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Camera option
                _buildImageOption(
                  icon: CupertinoIcons.camera,
                  title:
                      AppLocalizations.of(context)?.takePhoto ?? AppLocalizations.of(context)!.tr('Take Photo'),
                  subtitle:
                      AppLocalizations.of(context)?.useCameraToTakeANewPhoto ?? AppLocalizations.of(context)!.tr('Use camera to take a new photo'),
                  onTap: _isUploading ? null : _pickImageFromCamera,
                ),

                const SizedBox(height: 6),

                // Gallery option
                _buildImageOption(
                  icon: CupertinoIcons.photo,
                  title:
                      AppLocalizations.of(context)?.chooseFromGallery ?? AppLocalizations.of(context)!.tr('Choose from Gallery'),
                  subtitle:
                      AppLocalizations.of(context)?.selectAnExistingPhoto ?? AppLocalizations.of(context)!.tr('Select an existing photo'),
                  onTap: _isUploading ? null : _pickImageFromGallery,
                ),

                // Remove option (only if user has profile image)
                if (widget.userData?['profileImage'] != null &&
                    widget.userData!['profileImage'].toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildImageOption(
                    icon: CupertinoIcons.delete,
                    title:
                        AppLocalizations.of(context)?.removePhoto ?? AppLocalizations.of(context)!.tr('Remove Photo'),
                    subtitle:
                        AppLocalizations.of(
                          context,
                        )?.removeCurrentProfilePhoto ?? AppLocalizations.of(context)!.tr('Remove current profile photo'),
                    onTap: _isUploading ? null : _removeProfileImage,
                    isDestructive: true,
                  ),
                ],

                // Loading indicator
                if (_isUploading) ...[
                  const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                  Container(
                    padding: DesktopAppWrapper.getPagePadding(),
                    child: Column(
                      children: [
                        CultiooLoadingIndicator(),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          AppLocalizations.of(context)?.uploadingImage ?? AppLocalizations.of(context)!.tr('Uploading image...'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: widget.isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

        // Cancel button - Settings Style
        TradeRepublicButton(
          label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
          onPressed: _isUploading
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                },
          isSecondary: true,
        ),
      ],
    );
  }

  Widget _buildImageOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return TradeRepublicTap(
      onTap: onTap != null
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDestructive
                    ? Colors.red.withOpacity(0.1)
                    : (widget.isLight ? Colors.white : Colors.black),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isDestructive
                    ? Colors.red
                    : (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.8),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: isDestructive
                          ? Colors.red
                          : (widget.isLight ? Colors.black : Colors.white),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
                0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Verification Requirements Modal - Apple Style

// ============================================================================
// ANIMATED DOCUMENT BUTTON - Press Animation with Scale Effect
// ============================================================================
class _AnimatedDocumentButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final bool hasImage;
  final bool isLight;

  const _AnimatedDocumentButton({
    required this.onTap,
    required this.child,
    required this.hasImage,
    required this.isLight,
  });

  @override
  State<_AnimatedDocumentButton> createState() =>
      _AnimatedDocumentButtonState();
}

class _AnimatedDocumentButtonState extends State<_AnimatedDocumentButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _scaleController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
    widget.onTap();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return TradeRepublicTap(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: widget.child,
          );
        },
      ),
    );
  }
}
// ============================================================================
// CARBON FOOTPRINT MODAL - Monthly Odometer Entry & CO₂ Certificate
// ============================================================================
class _CarbonFootprintModal extends StatefulWidget {
  final bool isLight;
  final Map<String, Map<String, double>> mileageEntries;
  final double Function(double km) co2ForKm;
  final void Function(String monthKey, double startKm, double endKm) onSaveEntry;
  final void Function(String monthKey) onDeleteEntry;

  const _CarbonFootprintModal({
    required this.isLight,
    required this.mileageEntries,
    required this.co2ForKm,
    required this.onSaveEntry,
    required this.onDeleteEntry,
  });

  @override
  State<_CarbonFootprintModal> createState() => _CarbonFootprintModalState();
}

class _CarbonFootprintModalState extends State<_CarbonFootprintModal> {
  late Map<String, Map<String, double>> _entries;
  String? _editingMonth; // 'YYYY-MM' of the row currently being edited
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _entries = Map.from(widget.mileageEntries);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatMonth(String key, [AppLocalizations? loc]) {
    // key = 'YYYY-MM'
    final parts = key.split('-');
    if (parts.length != 2) return key;
    final year = parts[0];
    final month = int.tryParse(parts[1]) ?? 0;
    if (month < 1 || month > 12) return key;
    final name = switch (month) {
      1 => loc?.january ?? AppLocalizations.of(context)!.tr('January'),
      2 => loc?.february ?? AppLocalizations.of(context)!.tr('February'),
      3 => loc?.march ?? AppLocalizations.of(context)!.tr('March'),
      4 => loc?.april ?? AppLocalizations.of(context)!.tr('April'),
      5 => loc?.may ?? AppLocalizations.of(context)!.tr('May'),
      6 => loc?.june ?? AppLocalizations.of(context)!.tr('June'),
      7 => loc?.july ?? AppLocalizations.of(context)!.tr('July'),
      8 => loc?.august ?? AppLocalizations.of(context)!.tr('August'),
      9 => loc?.september ?? AppLocalizations.of(context)!.tr('September'),
      10 => loc?.october ?? AppLocalizations.of(context)!.tr('October'),
      11 => loc?.november ?? AppLocalizations.of(context)!.tr('November'),
      12 => loc?.december ?? AppLocalizations.of(context)!.tr('December'),
      _ => '',
    };
    return '$name $year';
  }

  String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  List<String> _last12MonthKeys() {
    final now = DateTime.now();
    final list = <String>[];
    for (int i = 0; i < 12; i++) {
      final dt = DateTime(now.year, now.month - i, 1);
      list.add('${dt.year}-${dt.month.toString().padLeft(2, '0')}');
    }
    return list;
  }

  void _startEditing(String monthKey, {bool useMiles = false}) {
    final existing = _entries[monthKey];
    if (existing != null) {
      final start = useMiles ? existing['startKm']! * 0.621371 : existing['startKm']!;
      final end   = useMiles ? existing['endKm']!   * 0.621371 : existing['endKm']!;
      _startController.text = start.toStringAsFixed(0);
      _endController.text   = end.toStringAsFixed(0);
    } else {
      _startController.text = '';
      _endController.text   = '';
    }
    setState(() => _editingMonth = monthKey);
  }

  void _saveMonth(String monthKey, {bool useMiles = false}) {
    double? start = double.tryParse(_startController.text.replaceAll(',', '.'));
    double? end   = double.tryParse(_endController.text.replaceAll(',', '.'));
    if (start != null && end != null && end >= start) {
      // Always persist in km — convert miles → km if needed
      final startKm = useMiles ? start / 0.621371 : start;
      final endKm   = useMiles ? end   / 0.621371 : end;
      setState(() {
        _entries[monthKey] = {'startKm': startKm, 'endKm': endKm};
        _editingMonth = null;
      });
      widget.onSaveEntry(monthKey, startKm, endKm);
    } else {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.endValueMustBeGreater ?? AppLocalizations.of(context)!.tr('End value must be greater than start value.'),
      );
    }
  }

  void _deleteMonth(String monthKey) {
    setState(() {
      _entries.remove(monthKey);
      if (_editingMonth == monthKey) _editingMonth = null;
    });
    widget.onDeleteEntry(monthKey);
  }

  Future<void> _downloadCertificate() async {
    final loc = AppLocalizations.of(context);
    final months = _last12MonthKeys().reversed.where((k) => _entries.containsKey(k)).toList();
    if (months.isEmpty) {
      TopNotification.warning(
        context,
        AppLocalizations.of(context)?.noCertificateData ?? AppLocalizations.of(context)!.tr('No data available to generate certificate.'),
      );
      return;
    }

    double totalCo2 = 0;
    double totalKm = 0;
    for (final k in months) {
      final e = _entries[k]!;
      final km = (e['endKm']! - e['startKm']!).clamp(0.0, double.infinity);
      totalKm += km;
      totalCo2 += widget.co2ForKm(km);
    }
    final savedCo2 = totalCo2 * 0.3;
    final trees = savedCo2 / 21;
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    // Load logo asset bytes
    final logoBytes = await rootBundle.load('logo/cultioo_word_transparent_darkmode.png');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    // ── Fonts (built-in Helvetica variants – no download needed) ────────────
    final doc = pw.Document();

    // ── Palette: pure black & white ─────────────────────────────────────────
    const black = PdfColors.black;
    const white = PdfColors.white;
    final grey100 = PdfColor.fromHex('F5F5F5');   // very light bg for table header
    final grey300 = PdfColor.fromHex('E0E0E0');   // dividers
    final grey500 = PdfColor.fromHex('9E9E9E');   // secondary text
    final grey700 = PdfColor.fromHex('424242');   // body text

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 44),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [

              // ── TOP BAR: Logo left · document type right ─────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Image(logoImage, height: 22, fit: pw.BoxFit.contain),
                  pw.Text(
                    loc?.co2EmissionCertificate ?? AppLocalizations.of(context)!.tr('CO₂-Emissionszertifikat'),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                      color: grey500,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 32),

              // ── HERO NUMBER ──────────────────────────────────────────────
              pw.Text(
                '${totalKm.toStringAsFixed(0)} km',
                style: pw.TextStyle(
                  fontSize: 52,
                  fontWeight: pw.FontWeight.bold,
                  color: black,
                  letterSpacing: -2,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${loc?.distanceDriven ?? AppLocalizations.of(context)!.tr('Distance Driven')}  ·  ${_formatMonth(months.first, loc)} – ${_formatMonth(months.last, loc)}',
                style: pw.TextStyle(fontSize: 12, color: grey500),
              ),

              pw.SizedBox(height: 28),
              pw.Divider(color: grey300, thickness: 0.5),
              pw.SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              // ── 4 KEY STATS in a row ─────────────────────────────────────
              pw.Row(
                children: [
                  _pdfKpi(loc?.co2Emissions ?? AppLocalizations.of(context)!.tr('CO₂ Emissions'), '${totalCo2.toStringAsFixed(1)} kg', grey700, grey100),
                  _pdfKpiDivider(grey300),
                  _pdfKpi(loc?.co2Saved ?? AppLocalizations.of(context)!.tr('CO₂ Saved*'), '${savedCo2.toStringAsFixed(1)} kg', grey700, grey100),
                  _pdfKpiDivider(grey300),
                  _pdfKpi(loc?.treesPerYear ?? AppLocalizations.of(context)!.tr('Trees/Year*'), trees.toStringAsFixed(1), grey700, grey100),
                  _pdfKpiDivider(grey300),
                  _pdfKpi(loc?.monthsRecorded ?? AppLocalizations.of(context)!.tr('Months Recorded'), '${months.length}', grey700, grey100),
                ],
              ),

              pw.SizedBox(height: 28),
              pw.Divider(color: grey300, thickness: 0.5),
              pw.SizedBox(height: 20),

              // ── SECTION LABEL ────────────────────────────────────────────
              pw.Text(
                loc?.monthlyOverview ?? AppLocalizations.of(context)!.tr('MONTHLY OVERVIEW'),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.4,
                  color: grey500,
                ),
              ),
              pw.SizedBox(height: 10),

              // ── TABLE ────────────────────────────────────────────────────
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.2),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(1.8),
                  4: const pw.FlexColumnWidth(1.8),
                },
                children: [
                  // Header
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: black, width: 1)),
                    ),
                    children: [
                      _pdfTh(loc?.tableHeaderMonth ?? AppLocalizations.of(context)!.tr('Month')),
                      _pdfTh(loc?.tableHeaderStart ?? AppLocalizations.of(context)!.tr('Start (km)')),
                      _pdfTh(loc?.tableHeaderEnd ?? AppLocalizations.of(context)!.tr('End (km)')),
                      _pdfTh(loc?.tableHeaderDistance ?? AppLocalizations.of(context)!.tr('Distance (km)')),
                      _pdfTh(loc?.co2Kg ?? AppLocalizations.of(context)!.tr('CO₂ (kg)')),
                    ],
                  ),
                  // Data rows
                  ...months.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final k = entry.value;
                    final e = _entries[k]!;
                    final km = (e['endKm']! - e['startKm']!).clamp(0.0, double.infinity);
                    final co2 = widget.co2ForKm(km);
                    final rowBg = idx.isOdd ? grey100 : white;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: rowBg),
                      children: [
                        _pdfTd(_formatMonth(k, loc), grey700),
                        _pdfTd(e['startKm']!.toStringAsFixed(0), grey700),
                        _pdfTd(e['endKm']!.toStringAsFixed(0), grey700),
                        _pdfTd(km.toStringAsFixed(0), black, bold: true),
                        _pdfTd(co2.toStringAsFixed(1), black, bold: true),
                      ],
                    );
                  }),
                  // Totals row
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(color: black, width: 0.8)),
                    ),
                    children: [
                      _pdfTd(loc?.total ?? AppLocalizations.of(context)!.tr('Total'), black, bold: true),
                      _pdfTd('', grey500),
                      _pdfTd('', grey500),
                      _pdfTd('${totalKm.toStringAsFixed(0)} km', black, bold: true),
                      _pdfTd('${totalCo2.toStringAsFixed(1)} kg', black, bold: true),
                    ],
                  ),
                ],
              ),

              pw.Spacer(),

              // ── METHODOLOGY NOTE ─────────────────────────────────────────
              pw.Divider(color: grey300, thickness: 0.5),
              pw.SizedBox(height: 10),
              pw.Text(
                loc?.calculationMethod ??
                    AppLocalizations.of(context)!.tr(
                      'Calculation method: Ø 8.5 L/100 km · CO₂ factor 2.31 kg/L Diesel · * 30% estimated empty run savings through Delvioo · * 21 kg CO₂ absorption per tree/year',
                    ),
                style: pw.TextStyle(fontSize: 8, color: grey500),
              ),
              pw.SizedBox(height: 6),

              // ── FOOTER ───────────────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${loc?.issuedOn ?? AppLocalizations.of(context)!.tr('Issued on')} $dateStr · ${loc?.autoGeneratedByApp ?? AppLocalizations.of(context)!.tr('Automatically generated by the Delvioo app')}',
                    style: pw.TextStyle(fontSize: 8, color: grey500),
                  ),
                  pw.Text(
                    '© ${now.year} Delvioo',
                    style: pw.TextStyle(fontSize: 8, color: grey500),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    // ── Share / Save ─────────────────────────────────────────────────────────
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'CO2-Zertifikat_Delvioo_${months.first}_${months.last}.pdf',
    );
  }

  // ── PDF helper widgets ────────────────────────────────────────────────────

  pw.Widget _pdfKpi(String label, String value, PdfColor textColor, PdfColor bg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        color: bg,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
                letterSpacing: -0.5,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8, color: textColor),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfKpiDivider(PdfColor color) {
    return pw.Container(width: 1, height: 52, color: color);
  }

  pw.Widget _pdfTh(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  pw.Widget _pdfTd(String text, PdfColor color, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final isLight = widget.isLight;
    final bg = isLight ? Colors.white : const Color(0xFF111111);
    final fg = isLight ? Colors.black : Colors.white;
    final months = _last12MonthKeys(); // newest first

    final appSettings = Provider.of<AppSettings>(context);
    final useMiles  = appSettings.effectiveDistanceUnit == 'Miles';
    final distUnit  = useMiles ? 'mi' : 'km';
    final loc = AppLocalizations.of(context);

    double totalCo2 = 0;
    for (final k in months) {
      if (_entries.containsKey(k)) {
        final e = _entries[k]!;
        final km = (e['endKm']! - e['startKm']!).clamp(0.0, double.infinity);
        totalCo2 += widget.co2ForKm(km);
      }
    }

    return Column(
      children: [
        const SizedBox(height: 4),

        // Title row
        Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  CupertinoIcons.leaf_arrow_circlepath,
                  color: Color(0xFF10B981),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc?.co2Balance ?? AppLocalizations.of(context)!.tr('CO₂ Balance'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: fg,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      loc?.monthlyOdometerEntry ?? AppLocalizations.of(context)!.tr('Enter Monthly Mileage'),
                      style: TextStyle(fontSize: 13, color: fg.withOpacity(0.5)),
                    ),
                  ],
                ),
              ),
            ],
        ),

        const SizedBox(height: 20),

        // CO2 summary card
        Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.08),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc?.totalCo2_12months ?? AppLocalizations.of(context)!.tr('Total CO₂ (12 Months)'),
                        style: TextStyle(fontSize: 12, color: fg.withOpacity(0.55)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${totalCo2.toStringAsFixed(1)} kg',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ),
                // Download certificate — TR button
                TradeRepublicButton(
                  label: loc?.certificate ?? AppLocalizations.of(context)!.tr('Certificate'),
                  icon: const Icon(CupertinoIcons.doc_text, size: 15),
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  height: 40,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  onPressed: _downloadCertificate,
                ),
              ],
            ),
          ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        Text(
          loc?.last12Months ?? AppLocalizations.of(context)!.tr('Last 12 Months'),
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w600,
            color: fg.withOpacity(0.45),
            letterSpacing: 0.4,
          ),
        ),

        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

        // Monthly list
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(0, 4, 0, MediaQuery.of(context).padding.bottom + 24),
            itemCount: months.length,
            itemBuilder: (_, i) {
              final key = months[i];
              final entry = _entries[key];
              final isEditing = _editingMonth == key;
              final isCurrent = key == _currentMonthKey();
              final km = entry != null
                  ? (entry['endKm']! - entry['startKm']!).clamp(0.0, double.infinity)
                  : 0.0;
              final co2 = widget.co2ForKm(km);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color: isEditing
                        ? const Color(0xFF10B981).withOpacity(0.10)
                        : fg.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Month header row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _formatMonth(key, loc),
                                        style: TextStyle(
                                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                                          fontWeight: FontWeight.w600,
                                          color: fg,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCurrent) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          loc?.current ?? AppLocalizations.of(context)!.tr('Current'),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (entry != null && !isEditing)
                                  Text(
                                    () {
                                      final factor = useMiles ? 0.621371 : 1.0;
                                      final s = (entry['startKm']! * factor).toStringAsFixed(0);
                                      final e = (entry['endKm']!   * factor).toStringAsFixed(0);
                                      final d = (km * factor).toStringAsFixed(1);
                                      return '$s → $e $distUnit  ·  $d $distUnit  ·  ${co2.toStringAsFixed(1)} kg CO₂';
                                    }(),
                                    style: TextStyle(fontSize: 12, color: fg.withOpacity(0.5)),
                                    overflow: TextOverflow.ellipsis,
                                  )
                                else if (entry == null && !isEditing)
                                  Text(
                                    loc?.notEnteredYet ?? AppLocalizations.of(context)!.tr('Not yet recorded'),
                                    style: TextStyle(fontSize: 13, color: fg.withOpacity(0.3)),
                                  ),
                              ],
                            ),
                          ),
                          // Action buttons — TR widgets
                          if (!isEditing) ...[
                            if (entry != null) ...[
                              TradeRepublicButton.icon(
                                icon: const Icon(CupertinoIcons.trash, size: 16, color: Colors.red),
                                onPressed: () => _deleteMonth(key),
                                isSecondary: true,
                                size: 36,
                              ),
                              const SizedBox(width: 6),
                            ],
                            TradeRepublicButton(
                              label: entry != null ? (loc?.edit ?? AppLocalizations.of(context)!.tr('Edit')) : (loc?.enterLabel ?? AppLocalizations.of(context)!.tr('Enter')),
                              height: 36,
                              isSecondary: entry != null,
                              backgroundColor: entry == null
                                  ? const Color(0xFF10B981).withOpacity(0.12)
                                  : null,
                              foregroundColor: entry == null
                                  ? const Color(0xFF10B981)
                                  : null,
                              borderRadius: BorderRadius.circular(10),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              onPressed: () => _startEditing(key, useMiles: useMiles),
                            ),
                          ] else ...[
                            TradeRepublicButton.icon(
                              icon: Icon(CupertinoIcons.xmark, size: 16, color: fg.withOpacity(0.5)),
                              onPressed: () => setState(() => _editingMonth = null),
                              isSecondary: true,
                              size: 36,
                            ),
                          ],
                        ],
                      ),

                      // Inline edit form
                      if (isEditing) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TradeRepublicTextField.withLabel(
                                label: '${loc?.odometerStart ?? AppLocalizations.of(context)!.tr('Start Reading')} ($distUnit)',
                                controller: _startController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                hintText: useMiles ? '${loc?.egAbbr ?? AppLocalizations.of(context)!.tr('e.g.')} 77000' : '${loc?.egAbbr ?? AppLocalizations.of(context)!.tr('e.g.')} 125000',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TradeRepublicTextField.withLabel(
                                label: '${loc?.odometerEnd ?? AppLocalizations.of(context)!.tr('End Reading')} ($distUnit)',
                                controller: _endController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                hintText: useMiles ? '${loc?.egAbbr ?? AppLocalizations.of(context)!.tr('e.g.')} 78100' : '${loc?.egAbbr ?? AppLocalizations.of(context)!.tr('e.g.')} 126800',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        TradeRepublicButton(
                          label: AppLocalizations.of(context)?.save ?? AppLocalizations.of(context)!.tr('Save'),
                          width: double.infinity,
                          height: 48,
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                          onPressed: () => _saveMonth(key, useMiles: useMiles),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
