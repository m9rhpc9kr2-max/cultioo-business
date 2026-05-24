import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';

class ApiService {
  // Dynamic base URL based on platform using ApiConfig
  static String get baseUrl {
    return '${ApiConfig.baseUrl}/api';
  }

  // Login endpoint
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? twoFACode,
    bool isDelviooMode = false,
  }) async {
    print('═══════════════════════════════════════');
    print('🌐 API SERVICE LOGIN CALL');
    print('═══════════════════════════════════════');

    try {
      print('🔗 Base URL: $baseUrl');
      print('🔗 Full URL: $baseUrl/auth/login');
      print('📧 Email: $email');
      print('🔑 Has 2FA Code: ${twoFACode != null}');
      print('🚗 Delvioo Mode: $isDelviooMode');

      final body = {
        'email': email,
        'password': password,
        'isDelviooMode': isDelviooMode,
      };

      if (twoFACode != null) {
        body['twoFACode'] = twoFACode;
        print('🔑 2FA Code: $twoFACode');
      }

      print('📤 Request body: $body');
      print('───────────────────────────────────────');
      print('📡 Sending HTTP POST request...');

      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              print('❌ REQUEST TIMEOUT after 30 seconds');
              throw Exception('Request timeout');
            },
          );

      print('───────────────────────────────────────');
      print('📥 Response received!');
      print('📥 Status code: ${response.statusCode}');
      print(
        '📥 Response body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...',
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Login successful');
        return {
          'success': true,
          'user': data['user'],
          'token': data['token'],
          'message': data['message'],
        };
      } else if (response.statusCode == 202) {
        print('🔐 2FA required');
        // 2FA required
        return {
          'success': false,
          'requiresTwoFA': data['requiresTwoFA'] ?? false,
          'step': data['step'], // ✅ Include step information!
          'userId': data['userId'],
          'message': data['message'] ?? '2FA required',
        };
      } else if (response.statusCode == 403 &&
          data['requiresEmailVerification'] == true) {
        print('📧 Email verification required');
        return {
          'success': false,
          'requiresEmailVerification': true,
          'userId': data['userId'],
          'message':
              data['message'] ?? 'Please verify your email address first',
        };
      } else {
        print('❌ Login failed: ${data['message']}');
        return {'success': false, 'message': data['message'] ?? 'Login failed'};
      }
    } catch (e) {
      print('═══════════════════════════════════════');
      print('💥 API SERVICE LOGIN ERROR');
      print('═══════════════════════════════════════');
      print('💥 Error Type: ${e.runtimeType}');
      print('💥 Error Message: $e');
      print('💥 Error Details: ${e.toString()}');
      print('🌐 Was trying: $baseUrl/auth/login');
      print('═══════════════════════════════════════');

      return {'success': false, 'message': 'Connection error: ${e.toString()}'};
    }
  }

  // Register endpoint
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String userType = 'Business',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'user_type': userType,
          'isBusiness': userType == 'Business' ? 1 : 0,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'user': data['user'], 'token': data['token']};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Registration failed',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: ${e.toString()}'};
    }
  }

  // Verify 2FA code
  static Future<Map<String, dynamic>> verify2FA({
    required String userId,
    required String code,
    bool isDelviooMode = false,
  }) async {
    try {
      print('🔐 Verifying 2FA code for user: $userId');

      final body = {
        'userId': userId,
        'twoFACode': code,
        'isDelviooMode': isDelviooMode,
      };

      print('📤 2FA Request body: $body');

      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/verify-2fa'), // ✅ Correct endpoint
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      print('📥 2FA Response status: ${response.statusCode}');
      print('📥 2FA Response body: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ 2FA verification successful');
        return {
          'success': true,
          'user': data['user'],
          'token': data['token'],
          'message': data['message'] ?? '2FA verified successfully',
        };
      } else if (response.statusCode == 202 && data['requiresTwoFA'] == true) {
        // Static code was correct, now requires email code
        print('🔐 Static code verified, now requiring email code');
        return {
          'success': false,
          'requiresTwoFA': true,
          'step': data['step'], // Should be 'email_code'
          'userId': data['userId'],
          'message': data['message'] ?? 'Email code required',
        };
      } else {
        print('❌ 2FA verification failed: ${data['message']}');
        return {
          'success': false,
          'message': data['message'] ?? '2FA verification failed',
        };
      }
    } catch (e) {
      print('💥 2FA verification error: $e');
      return {'success': false, 'message': 'Connection error: ${e.toString()}'};
    }
  }

  // Verify token endpoint
  static Future<Map<String, dynamic>> verifyToken(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/verify'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'user': data['user']};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Token verification failed',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: ${e.toString()}'};
    }
  }

  // Update business information endpoint
  static Future<Map<String, dynamic>> updateBusinessInfo({
    required String token,
    required String businessName,
    required String businessEmail,
    required String businessSize,
    required String businessCountry,
    required String businessPhone,
    required String businessAddress,
    required String taxVatNumber,
    String? businessDescription,
    String? businessWebsite,
    String? businessLogoPath,
  }) async {
    try {
      print('🔗 Updating business info at: $baseUrl/business/complete-info');

      final body = {
        'businessName': businessName,
        'businessEmail': businessEmail,
        'business_size': businessSize,
        'business_country': businessCountry,
        'businessPhone': businessPhone,
        'businessAddress': businessAddress,
        'taxVatNumber': taxVatNumber,
      };

      // Add optional fields if provided
      if (businessDescription != null && businessDescription.isNotEmpty) {
        body['businessDescription'] = businessDescription;
      }
      if (businessWebsite != null && businessWebsite.isNotEmpty) {
        body['businessWebsite'] = businessWebsite;
      }
      if (businessLogoPath != null && businessLogoPath.isNotEmpty) {
        body['businessLogo'] = businessLogoPath;
      }

      print('📤 Request body: $body');

      final response = await http
          .put(
            Uri.parse('$baseUrl/business/complete-info'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Business info updated successfully');
        return {
          'success': true,
          'user': data['user'],
          'message':
              data['message'] ?? 'Business information updated successfully',
        };
      } else {
        print('❌ Update failed: ${data['message']}');
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to update business information',
        };
      }
    } catch (e) {
      print('💥 Update business info error: $e');
      return {'success': false, 'message': 'Connection error: ${e.toString()}'};
    }
  }

  // Check if email exists
  static Future<Map<String, dynamic>> checkEmailExists(String email) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/auth/check-email?email=${Uri.encodeComponent(email)}',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'exists': data['exists'] ?? false,
          'message': data['message'] ?? '',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to check email',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: ${e.toString()}'};
    }
  }

  // Check if username exists
  static Future<Map<String, dynamic>> checkUsernameExists(
    String username,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/auth/check-username?username=${Uri.encodeComponent(username)}',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'exists': data['exists'] ?? false,
          'message': data['message'] ?? '',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to check username',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: ${e.toString()}'};
    }
  }
}
