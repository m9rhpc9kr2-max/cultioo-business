import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';

class TwoFactorService {
  static String get _baseUrl => ApiConfig.baseUrl;

  /// Get current 2FA status and settings
  static Future<Map<String, dynamic>?> getTwoFactorStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? prefs.getString('username');

      if (userId == null) {
        print('No userId found');
        return null;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/user-settings?userId=$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      print('2FA Status Response: ${response.statusCode}');
      print('2FA Status Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final data = responseData['data'] ?? {};
        return {
          'twoFactorEnabled': data['twoFactorEnabled'] ?? false,
          'twoFactorCode': data['twoFactorCode'],
        };
      } else {
        print('Failed to get 2FA status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error getting 2FA status: $e');
      return null;
    }
  }

  /// Enable 2FA with an 8-digit code
  static Future<Map<String, dynamic>> enableTwoFactor(
    String eightDigitCode,
  ) async {
    try {
      // Validate the code format - must be exactly 8 digits
      if (eightDigitCode.length != 8 ||
          !RegExp(r'^\d{8}$').hasMatch(eightDigitCode)) {
        return {
          'success': false,
          'message': 'Code must be exactly 8 digits (numbers only)',
        };
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final userId = prefs.getString('user_id');

      print('🔍 Debug - Token: ${token != null ? "exists" : "null"}');
      print('🔍 Debug - User ID: $userId');

      if (token == null || userId == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      print('📤 Sending to backend - userId: $userId');

      final response = await http.patch(
        Uri.parse('$_baseUrl/api/two-factor'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'userId': userId,
          'twoFactorCode': eightDigitCode,
          'twoFactorEnabled': true,
        }),
      );

      print('Enable 2FA Response: ${response.statusCode}');
      print('Enable 2FA Body: ${response.body}');

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        // Save 2FA status locally
        await prefs.setBool('two_factor_enabled', true);
        await prefs.setString('two_factor_code', eightDigitCode);

        return {
          'success': true,
          'message': 'Two-factor authentication enabled successfully',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Error enabling 2FA',
        };
      }
    } catch (e) {
      print('Error enabling 2FA: $e');
      return {'success': false, 'message': 'Network error while enabling 2FA'};
    }
  }

  /// Disable 2FA
  static Future<Map<String, dynamic>> disableTwoFactor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final userId = prefs.getString('user_id');

      if (token == null || userId == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final response = await http.patch(
        Uri.parse('$_baseUrl/api/two-factor'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'userId': userId,
          'twoFactorCode': '',
          'twoFactorEnabled': false,
        }),
      );

      print('Disable 2FA Response: ${response.statusCode}');
      print('Disable 2FA Body: ${response.body}');

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        // Remove 2FA status locally
        await prefs.setBool('two_factor_enabled', false);
        await prefs.remove('two_factor_code');

        return {
          'success': true,
          'message': 'Two-factor authentication disabled successfully',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Error disabling 2FA',
        };
      }
    } catch (e) {
      print('Error disabling 2FA: $e');
      return {'success': false, 'message': 'Network error while disabling 2FA'};
    }
  }

  /// Update 2FA code (change existing code)
  static Future<Map<String, dynamic>> updateTwoFactorCode(
    String newEightDigitCode,
  ) async {
    try {
      // Validate the code format - must be exactly 8 digits
      if (newEightDigitCode.length != 8 ||
          !RegExp(r'^\d{8}$').hasMatch(newEightDigitCode)) {
        return {
          'success': false,
          'message': 'Code must be exactly 8 digits (numbers only)',
        };
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final userId = prefs.getString('user_id');

      if (token == null || userId == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final response = await http.patch(
        Uri.parse('$_baseUrl/api/two-factor'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'userId': userId,
          'twoFactorCode': newEightDigitCode,
          'twoFactorEnabled': true,
        }),
      );

      print('Update 2FA Code Response: ${response.statusCode}');
      print('Update 2FA Code Body: ${response.body}');

      final responseData = json.decode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        // Update 2FA code locally
        await prefs.setString('two_factor_code', newEightDigitCode);

        return {'success': true, 'message': '2FA code updated successfully'};
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Error updating 2FA code',
        };
      }
    } catch (e) {
      print('Error updating 2FA code: $e');
      return {
        'success': false,
        'message': 'Network error while updating 2FA code',
      };
    }
  }

  /// Check if 2FA is enabled locally
  static Future<bool> isTwoFactorEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('two_factor_enabled') ?? false;
    } catch (e) {
      print('Error checking 2FA status: $e');
      return false;
    }
  }

  /// Get locally stored 2FA code (for verification purposes)
  static Future<String?> getLocalTwoFactorCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('two_factor_code');
    } catch (e) {
      print('Error getting local 2FA code: $e');
      return null;
    }
  }

  /// Validate a 2FA code format - must be exactly 8 digits
  static bool isValidTwoFactorCode(String code) {
    return code.length == 8 && RegExp(r'^\d{8}$').hasMatch(code);
  }

  /// Generate a random 8-digit numeric code
  static String generateRandomCode() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return (random % 100000000).toString().padLeft(8, '0');
  }
}
