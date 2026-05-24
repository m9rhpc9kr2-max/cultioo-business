import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiConfig {
  // FORCE Google Cloud IP - bypassing network detection
  static String? _activeBaseUrl;
  static const String _defaultBaseUrl =
      'https://cultioo-business-app-bgx25dbbma-uc.a.run.app';

  // Get the active base URL - Use initialized URL if available
  static String get baseUrl {
    // If initializeNetworking() found a working URL, use it
    if (_activeBaseUrl != null && _activeBaseUrl!.isNotEmpty) {
      return _activeBaseUrl!;
    }
    // Default fallback: Cloud Run production
    return _defaultBaseUrl;
  }

  // Initialisiere die Netzwerkverbindung (beim App-Start aufrufen)
  static Future<void> initializeNetworking() async {
    print('🚀 Initializing network connectivity...');
    print('🔍 Testing multiple URLs to find working connection...');

    // Release builds must talk to the same DB as buyers (Cloud SQL). If a dev machine
    // on the LAN exposes :3006 with /api/health, we would otherwise pick a local
    // empty DB and driver-requests stays empty forever.
    final localCandidates = <String>[
      'http://192.168.0.118:3006', // Local network (HOST from .env) — real devices
      'http://localhost:3006', // Local development — macOS/simulator
      'http://127.0.0.1:3006', // Local fallback
      'http://10.0.2.2:3006', // Android Emulator
    ];
    final List<String> urlsToTry = kReleaseMode
        ? <String>[
            _defaultBaseUrl,
            'https://cultioo-business-app-78230737866.us-central1.run.app',
            ...localCandidates,
          ]
        : <String>[
            _defaultBaseUrl,
            'https://cultioo-business-app-78230737866.us-central1.run.app',
            ...localCandidates,
          ];

    for (String url in urlsToTry) {
      try {
        print('🧪 Testing connection to $url...');
        final response = await http
            .get(
              Uri.parse('$url/api/health'),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                print('⏱️ Connection to $url timed out after 5 seconds');
                throw Exception('Timeout');
              },
            );

        print('📡 Response from $url: ${response.statusCode}');
        if (response.statusCode == 200) {
          String body = response.body;
          int bodyMaxLength = body.length > 50 ? 50 : body.length;
          print(
            '📡 Response body: ${body.length > 50 ? '${body.substring(0, bodyMaxLength)}...' : body}',
          );
        }

        if (response.statusCode == 200) {
          _activeBaseUrl = url;
          print('✅ Successfully connected to: $url');
          print('🌐 Active backend URL CONFIRMED: $_activeBaseUrl');
          print('==========================================');
          return;
        } else {
          print('❌ Bad response from $url: ${response.statusCode}');
        }
      } catch (e) {
        String errorMsg = e.toString();
        int maxLength = errorMsg.length > 100 ? 100 : errorMsg.length;
        print(
          '❌ Failed to connect to $url: ${errorMsg.length > 100 ? '${errorMsg.substring(0, maxLength)}...' : errorMsg}',
        );
        continue;
      }
    }

    // All attempts failed - use Cloud Run as final fallback
    _activeBaseUrl = _defaultBaseUrl;
    print('⚠️ All health checks failed - using fallback: $_activeBaseUrl');
    print(
      '💡 For local development, ensure business backend runs on localhost:3006',
    );
    print('💡 For Android Emulator, run: adb reverse tcp:3006 tcp:3006');
    print('==========================================');
  }

  // Fallback-URLs
  static List<String> get fallbackUrls => [
    _defaultBaseUrl, // Cloud Run Production
  ];

  // API endpoints
  static String get delviooOrdersUrl => '$baseUrl/api/delvioo/orders';
  static String get delviooProductsUrl => '$baseUrl/api/delvioo/products';

  static String getProductUrl(int productId) =>
      '$baseUrl/api/delvioo/products/$productId';

  // Messages API endpoints
  static String getOrderMessagesUrl(int orderId) =>
      '$baseUrl/api/messages/orders/$orderId/messages';
  static String getUnreadMessagesUrl(String userType, int userId) =>
      '$baseUrl/api/messages/messages/unread/$userType/$userId';
  static String getMarkMessagesReadUrl(int orderId) =>
      '$baseUrl/api/messages/orders/$orderId/messages/read';

  // Authentication API endpoints
  static String get loginEndpoint => '$baseUrl/api/auth/login';
  static String get registerEndpoint => '$baseUrl/api/auth/register';
  static String get logoutEndpoint => '$baseUrl/api/auth/logout';
  static String get updateUserEndpoint => '$baseUrl/api/auth/update-user';
  static String get deleteAccountEndpoint => '$baseUrl/api/auth/account-delete';
  static String get loginHistoryEndpoint => '$baseUrl/api/auth/login-history';

  // Stripe API endpoints
  static String get stripeConfigEndpoint =>
      '$baseUrl/api/stripe/config'; // returns publishable key + mode
  static String get stripeCreateAccountEndpoint =>
      '$baseUrl/api/stripe/create-account';
  static String get stripeConnectEndpoint => '$baseUrl/api/stripe/connect';
  static String get stripeAccountStatusEndpoint =>
      '$baseUrl/api/stripe/account-status';

  // Auction API endpoints (Driver bidding system)
  static String get activeAuctionsUrl => '$baseUrl/api/auctions/active';
  static String getAuctionDetailsUrl(int auctionId) =>
      '$baseUrl/api/auctions/$auctionId';
  static String getAuctionBidUrl(int auctionId) =>
      '$baseUrl/api/auctions/$auctionId/bid';
  static String get myBidsUrl => '$baseUrl/api/auctions/my/bids';

  static List<String> _uniqueUrls(Iterable<String> urls) {
    final seen = <String>{};
    final result = <String>[];

    for (final url in urls) {
      final trimmed = url.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) continue;
      seen.add(trimmed);
      result.add(trimmed);
    }

    return result;
  }

  static List<String> _buildUploadPathCandidates(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final candidates = <String>[];

    for (final host in _uniqueUrls([baseUrl, ...fallbackUrls])) {
      candidates.add('$host$cleanPath');

      if (cleanPath.startsWith('/uploads/')) {
        candidates.add('$host/backend$cleanPath');
      }
    }

    return _uniqueUrls(candidates);
  }

  static List<String> getImageUrlCandidates(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return const [];

    final raw = imageUrl.trim();

    if (raw.startsWith('data:')) {
      return [raw];
    }

    if (raw.startsWith('/cultioo-uploads/')) {
      return ['https://storage.googleapis.com$raw'];
    }

    if (raw.startsWith('/a-/') || raw.startsWith('/a/')) {
      return ['https://lh3.googleusercontent.com$raw'];
    }

    if (raw.contains('/uploads/business-logos/business-logo-')) {
      final fileName = raw.split('/').last;
      return [
        'https://storage.googleapis.com/cultioo-uploads/business-logos/$fileName',
      ];
    }

    if (raw.startsWith('https://storage.googleapis.com/') ||
        raw.startsWith('https://storage.cloud.google.com/')) {
      return [raw];
    }

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      try {
        final uri = Uri.parse(raw);
        if (uri.path.startsWith('/uploads/')) {
          return _uniqueUrls([
            raw,
            ..._buildUploadPathCandidates(uri.path),
            '${uri.scheme}://${uri.authority}/backend${uri.path}',
          ]);
        }
      } catch (_) {}

      return [raw];
    }

    if (raw.startsWith('/uploads/') || raw.startsWith('uploads/')) {
      return _buildUploadPathCandidates(raw);
    }

    if (!raw.contains('/')) {
      if (raw.startsWith('business-logo-')) {
        return [
          'https://storage.googleapis.com/cultioo-uploads/business-logos/$raw',
        ];
      }

      // Driver profile images stored as plain filenames (e.g. 'driver-profile-abc.jpg')
      if (raw.startsWith('driver-profile-') || raw.startsWith('delvioo-profile-')) {
        return [
          'https://storage.googleapis.com/cultioo-uploads/driver-profiles/$raw',
          '$baseUrl/uploads/driver-profiles/$raw',
        ];
      }

      // Generic user profile images
      if (raw.startsWith('profile-') || raw.startsWith('user-profile-')) {
        return _uniqueUrls([
          'https://storage.googleapis.com/cultioo-uploads/profile-images/$raw',
          '$baseUrl/uploads/profile-images/$raw',
          ...fallbackUrls.map((host) => '$host/uploads/profile-images/$raw'),
        ]);
      }

      return _uniqueUrls([
        '$baseUrl/uploads/business-logos/$raw',
        ...fallbackUrls.map((host) => '$host/uploads/business-logos/$raw'),
      ]);
    }

    return [raw];
  }

  // Helper method to convert image URLs to use the active base URL
  static String getImageUrl(String? imageUrl) {
    final candidates = getImageUrlCandidates(imageUrl);
    return candidates.isNotEmpty ? candidates.first : '';
  }
}
