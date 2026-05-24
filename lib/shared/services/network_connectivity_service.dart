import 'dart:async';
import 'package:http/http.dart' as http;

class NetworkConnectivityService {
  static const List<String> _testUrls = [
    'https://cultioo-business-app-78230737866.us-central1.run.app', // Google Cloud Run
  ];

  static String? _workingUrl;
  static final bool _isTestingUrls = false;

  /// Find a working URL by testing all possibilities
  static Future<String?> findWorkingUrl() async {
    // Always return the Cloud Run URL directly — no dynamic detection needed
    return _testUrls.first;
  }

  /// Teste eine einzelne URL (kept for potential future use)
  static Future<bool> _testUrl(String url) async {
    try {
      print('🧪 Testing URL: $url');
      final response = await http
          .get(
            Uri.parse('$url/api/health'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(
            Duration(seconds: 2),
          ); // Shorter timeout for faster tests

      final isReachable = response.statusCode == 200;
      print(
        isReachable
            ? '✅ $url is reachable'
            : '❌ $url returned ${response.statusCode}',
      );
      return isReachable;
    } catch (e) {
      // Try alternative health check endpoint
      try {
        final response = await http
            .get(
              Uri.parse('$url/api/auth/check-email?email=test@test.com'),
              headers: {'Accept': 'application/json'},
            )
            .timeout(Duration(seconds: 2));

        // A 404 or other HTTP codes also mean the server is reachable
        final isReachable = response.statusCode < 500;
        print(
          isReachable
              ? '✅ $url is reachable (via auth endpoint)'
              : '❌ $url returned ${response.statusCode}',
        );
        return isReachable;
      } catch (e2) {
        print('❌ URL $url not reachable: $e2');
        return false;
      }
    }
  }

  /// Set the URL manually (for tests or manual configuration)
  static void setWorkingUrl(String url) {
    _workingUrl = url;
    print('🔧 Manually set working URL to: $url');
  }

  /// Force a new test of all URLs
  static Future<String?> refreshWorkingUrl() async {
    _workingUrl = null;
    return await findWorkingUrl();
  }

  /// Get the currently working URL (without test)
  static String? get currentWorkingUrl => _workingUrl;

  /// Check if a connection is available
  static Future<bool> isConnected() async {
    final url = await findWorkingUrl();
    return url != null;
  }
}
