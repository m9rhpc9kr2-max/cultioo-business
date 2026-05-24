import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DriverApiService {
  static const String baseUrl = 'http://localhost:3006/api';

  // Get authentication token from SharedPreferences
  static Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_token');
    } catch (e) {
      print('Error getting auth token: $e');
      return null;
    }
  }

  // Get authorization headers
  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await _getAuthToken();

    return {
      'Content-Type': 'application/json',
      'Authorization': token != null ? 'Bearer $token' : '',
    };
  }

  // Save driver registration step data
  static Future<Map<String, dynamic>> saveRegistrationStep({
    required int step,
    required Map<String, dynamic> data,
  }) async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.put(
        Uri.parse('$baseUrl/driver/registration-step'),
        headers: headers,
        body: jsonEncode({'step': step, 'data': data}),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Step saved successfully',
        };
      } else {
        return {
          'success': false,
          'message':
              responseData['message'] ?? 'Failed to save registration step',
        };
      }
    } catch (e) {
      print('Error saving registration step: $e');
      return {
        'success': false,
        'message': 'Network error while saving registration step',
      };
    }
  }

  // Get driver registration data
  static Future<Map<String, dynamic>> getRegistrationData() async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.get(
        Uri.parse('$baseUrl/driver/registration-data'),
        headers: headers,
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'data': responseData['data'] ?? {}};
      } else {
        return {
          'success': false,
          'message':
              responseData['message'] ?? 'Failed to fetch registration data',
          'data': {},
        };
      }
    } catch (e) {
      print('Error getting registration data: $e');
      return {
        'success': false,
        'message': 'Network error while fetching registration data',
        'data': {},
      };
    }
  }

  // Start Stripe W-9 process
  static Future<Map<String, dynamic>> startStripeW9Process({
    required String taxId,
    required String taxIdType,
    Map<String, dynamic>? personalInfo,
  }) async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.post(
        Uri.parse('$baseUrl/driver/stripe-w9/start'),
        headers: headers,
        body: jsonEncode({
          'taxId': taxId,
          'taxIdType': taxIdType,
          'personalInfo': personalInfo ?? {},
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'sessionId': responseData['sessionId'],
          'redirectUrl': responseData['redirectUrl'],
          'message':
              responseData['message'] ?? 'W-9 session created successfully',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to start W-9 process',
        };
      }
    } catch (e) {
      print('Error starting W-9 process: $e');
      return {
        'success': false,
        'message': 'Network error while starting W-9 process',
      };
    }
  }

  // Get W-9 status
  static Future<Map<String, dynamic>> getW9Status() async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.get(
        Uri.parse('$baseUrl/driver/stripe-w9/status'),
        headers: headers,
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'w9Status': responseData['w9Status'] ?? 'not_started',
          'sessionId': responseData['sessionId'],
          'lastUpdated': responseData['lastUpdated'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to get W-9 status',
          'w9Status': 'not_started',
        };
      }
    } catch (e) {
      print('Error getting W-9 status: $e');
      return {
        'success': false,
        'message': 'Network error while checking W-9 status',
        'w9Status': 'not_started',
      };
    }
  }

  // Start verification process
  static Future<Map<String, dynamic>> startVerification({
    required Map<String, dynamic> personalData,
  }) async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.post(
        Uri.parse('$baseUrl/driver/start-verification'),
        headers: headers,
        body: jsonEncode({'personalData': personalData}),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'verificationId': responseData['verificationId'],
          'message':
              responseData['message'] ?? 'Verification started successfully',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to start verification',
        };
      }
    } catch (e) {
      print('Error starting verification: $e');
      return {
        'success': false,
        'message': 'Network error while starting verification',
      };
    }
  }

  // Update verification status
  static Future<Map<String, dynamic>> updateVerificationStatus({
    required String stepId,
    required String status,
    Map<String, dynamic>? result,
  }) async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.put(
        Uri.parse('$baseUrl/driver/verification-status'),
        headers: headers,
        body: jsonEncode({
          'stepId': stepId,
          'status': status,
          'result': result,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Verification status updated',
        };
      } else {
        return {
          'success': false,
          'message':
              responseData['message'] ?? 'Failed to update verification status',
        };
      }
    } catch (e) {
      print('Error updating verification status: $e');
      return {
        'success': false,
        'message': 'Network error while updating verification status',
      };
    }
  }

  // Get verification status
  static Future<Map<String, dynamic>> getVerificationStatus() async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.get(
        Uri.parse('$baseUrl/driver/verification-status'),
        headers: headers,
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'verificationStatus':
              responseData['verificationStatus'] ?? 'not_started',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message':
              responseData['message'] ?? 'Failed to get verification status',
          'verificationStatus': 'not_started',
          'data': null,
        };
      }
    } catch (e) {
      print('Error getting verification status: $e');
      return {
        'success': false,
        'message': 'Network error while checking verification status',
        'verificationStatus': 'not_started',
        'data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> completeRegistration({
    required Map<String, dynamic> finalData,
  }) async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.post(
        Uri.parse('$baseUrl/driver/complete-registration'),
        headers: headers,
        body: jsonEncode({'finalData': finalData}),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message':
              responseData['message'] ??
              'Driver registration completed successfully',
        };
      } else {
        return {
          'success': false,
          'message':
              responseData['message'] ??
              'Failed to complete driver registration',
        };
      }
    } catch (e) {
      print('Error completing registration: $e');
      return {
        'success': false,
        'message': 'Network error while completing registration',
      };
    }
  }

  // Simulate W-9 completion (for testing)
  static Future<Map<String, dynamic>> simulateW9Completion({
    required String sessionId,
  }) async {
    try {
      final headers = await _getAuthHeaders();

      final response = await http.post(
        Uri.parse('$baseUrl/driver/stripe-w9/complete'),
        headers: headers,
        body: jsonEncode({
          'sessionId': sessionId,
          'status': 'completed',
          'stripeData': {
            'w9FormId': 'w9_${DateTime.now().millisecondsSinceEpoch}',
            'completedAt': DateTime.now().toIso8601String(),
            'verified': true,
          },
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message':
              responseData['message'] ?? 'W-9 process completed successfully',
        };
      } else {
        return {
          'success': false,
          'message':
              responseData['message'] ?? 'Failed to complete W-9 process',
        };
      }
    } catch (e) {
      print('Error simulating W-9 completion: $e');
      return {
        'success': false,
        'message': 'Network error while completing W-9 process',
      };
    }
  }

  // 🚀 MODERN: Upload completed verification to delvioo_users database
  static Future<Map<String, dynamic>> uploadToDelvioo({
    required Map<String, dynamic> personalData,
    required Map<String, dynamic> verificationResults,
    required int verificationScore,
    Map<String, dynamic>? documentPaths,
    Map<String, dynamic>? vehicleInfo,
  }) async {
    try {
      print('🚀 Uploading verified data to delvioo_users database...');

      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/driver/upload-to-delvioo'),
        headers: headers,
        body: jsonEncode({
          'personalData': personalData,
          'verificationResults': verificationResults,
          'verificationScore': verificationScore,
          'documentPaths':
              documentPaths ??
              {
                'idFront': personalData['idFrontImagePath'],
                'idBack': personalData['idBackImagePath'],
                'licenseFront': personalData['licenseFrontImagePath'],
                'licenseBack': personalData['licenseBackImagePath'],
                'vehicleRegistration':
                    personalData['vehicleRegistrationImagePath'],
                'insurance': personalData['insuranceProofImagePath'],
              },
          'vehicleInfo':
              vehicleInfo ??
              {
                'make': personalData['vehicleMake'],
                'model': personalData['vehicleModel'],
                'year': personalData['vehicleYear'],
                'vin': personalData['vin'],
                'licensePlate': personalData['licensePlate'],
              },
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Successfully uploaded to delvioo_users!');
        print(
          '📊 Verification Score: ${responseData['data']['verificationScore']}%',
        );
        print('🎯 Status: ${responseData['data']['status']}');

        return {
          'success': true,
          'message':
              responseData['message'] ??
              'Successfully uploaded to Delvioo platform',
          'data': responseData['data'],
        };
      } else {
        print('❌ Upload failed: ${responseData['message']}');
        return {
          'success': false,
          'message':
              responseData['message'] ?? 'Failed to upload to Delvioo platform',
        };
      }
    } catch (e) {
      print('❌ Network error during upload: $e');
      return {
        'success': false,
        'message': 'Network error while uploading to Delvioo platform',
      };
    }
  }
}
