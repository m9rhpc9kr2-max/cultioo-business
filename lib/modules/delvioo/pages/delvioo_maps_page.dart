import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui; // For BackdropFilter and Canvas Path
import 'dart:io'; // For Platform detection
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/services/app_settings.dart';
import '../../../config/api_config.dart';
import '../navigation_modal.dart';
import '../../../shared/widgets/trade_republic_widgets.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/constants/wagon_types.dart';
import '../../../utils/wagon_catalog.dart';

import 'delvioo_main_page.dart'; // For activeOrderNotifier and clearRouteNotifier
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';
// macOS Liquid Glass Support

// Debug mode - set to false to reduce console output
const bool _kDebugMode = true; // TEMPORARY: Enable for emergency debugging

// Free OpenStreetMap Tile Servers - No API Key Required
class MapTileConfig {
  // CartoDB Voyager - Colorful, modern, and completely free
  static String get lightUrl =>
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
  static String get darkUrl =>
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

  // Subdomains for load balancing
  static const List<String> subdomains = ['a', 'b', 'c', 'd'];
}

class DelviooMapsPage extends StatefulWidget {
  const DelviooMapsPage({super.key});

  @override
  State<DelviooMapsPage> createState() => _DelviooMapsPageState();

  // Static method to get accepted orders from anywhere in the app
  static List<Map<String, dynamic>> getAcceptedOrders() {
    return _DelviooMapsPageState._acceptedOrders.toList();
  }
}

// Custom Painter for Apple-style pin pointer
class _PinPointerPainter extends CustomPainter {
  final Color color;
  final bool isLight;

  _PinPointerPainter({required this.color, required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final path = ui.Path();
    // Create teardrop shape
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width / 2 - 4, size.height * 0.6);
    path.lineTo(size.width / 2 + 4, size.height * 0.6);
    path.close();

    // Draw shadow first
    canvas.drawPath(path, shadowPaint);
    // Then draw the pin
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Minimal pin pointer for Uber/Trade Republic style markers
class _MinimalPinPainter extends CustomPainter {
  final Color color;

  _MinimalPinPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = ui.Path();
    // Simple triangle pointing down
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Solid filled upward-pointing triangle for pickup marker
class _SolidTrianglePainter extends CustomPainter {
  final Color color;

  _SolidTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = color.withOpacity(0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const double r = 4.0; // corner radius
    // Three vertices of the upward-pointing triangle
    final top    = Offset(size.width / 2, 0);
    final right  = Offset(size.width,     size.height);
    final left   = Offset(0,              size.height);

    // Helper: move distance r along a direction
    Offset along(Offset from, Offset to, double dist) {
      final d = (to - from);
      return from + d / d.distance * dist;
    }

    final path = ui.Path()
      ..moveTo(along(top, left, r).dx,  along(top, left, r).dy)
      ..quadraticBezierTo(top.dx, top.dy,
          along(top, right, r).dx,  along(top, right, r).dy)
      ..lineTo(along(right, top, r).dx, along(right, top, r).dy)
      ..quadraticBezierTo(right.dx, right.dy,
          along(right, left, r).dx,  along(right, left, r).dy)
      ..lineTo(along(left, right, r).dx, along(left, right, r).dy)
      ..quadraticBezierTo(left.dx, left.dy,
          along(left, top, r).dx,   along(left, top, r).dy)
      ..close();

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DelviooMapsPageState extends State<DelviooMapsPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> orders = [];
  bool isLoading = true;
  bool _isMapLockedByPayout = false;
  String? error;
  String? selectedOrderId;
  final double _zoomLevel = 13.0;
  double _appleMapZoomLevel = 13.0; // mirrors the real Apple Maps zoom so zoomTo() works
  late MapController _mapController;
  mapbox.MapboxMap? _mapboxMap; // MapBox 3D map controller
  apple.AppleMapController?
  _appleMapController; // Apple Maps controller for iOS
  LatLng? currentLocation;
  double _searchRadius =
      75.0; // km - reasonable default for extended delivery areas
  double _displayRadius = 75.0; // km - synchronized with search radius
  bool _isMapExpanded = false; // New state for fullscreen map
  bool _isMapReady = false; // Track if map is ready
  double _lastZoomLevel =
      13.0; // Track last zoom level to prevent unnecessary clustering
  int _lastMarkerCount = 0; // Track marker count to reduce logging

  // Caches to avoid rebuild lag when route is shown
  List<Polyline> _cachedTrafficPolylines = [];
  double? _cachedTrafficAnimationValue;
  List<LatLng> _cachedTrafficRoutePoints = [];

  Set<apple.Polyline> _cachedApplePolylines = {};
  List<LatLng> _cachedAppleRoutePoints = [];

  Set<apple.Annotation> _cachedAppleAnnotations = {};
  String _cachedAppleAnnotationsKey = '';

  // Cache for rendered cluster icon bitmaps (key = '<count>_<em>_<light>')
  final Map<String, apple.BitmapDescriptor> _appleIconCache = {};
  final Set<String> _appleIconPending = {};

  // Shipping filter state
  final bool _isShippingFilterExpanded = false;
  final bool _showFilterContent = false; // Delayed display of filters
  String _selectedShippingFilter = 'all'; // all, standard, cold, express
  Timer? _locationTimer; // Timer for continuous location updates
  Timer? _routeInfoMinimizeTimer; // Timer to auto-minimize route info
  final bool _use3DMap =
      false; // Toggle for 3D MapBox vs 2D Flutter Map - TEMPORARILY DISABLED TO DEBUG

  // Navigation route state
  List<LatLng> _routePoints = [];
  final List<Map<String, dynamic>> _trafficSegments = [];

  // Uber-style route animation
  AnimationController? _routeAnimationController;
  Animation<double>? _routeAnimation;

  // Complete delivery route information
  Map<String, dynamic>? _activeRouteInfo;
  bool _showRouteInfo = false;
  bool _isRouteInfoMinimized = false; // Track if route info modal is minimized

  // Swipe to accept state
  double _swipeProgress = 0.0;
  bool _isAccepting = false;

  // Static list for accepted orders (shared across the app)
  static final List<Map<String, dynamic>> _acceptedOrders = [];

  // Theme tracking for forced rebuilds
  bool _lastThemeWasLight = true;

  // Native theme sync – forces iOS window-level dark/light so MKMapView follows app theme
  static const _nativeThemeChannel = MethodChannel('com.cultioo/native_theme');
  AppSettings? _appSettings; // held to add/remove listener

  // Bottom sheet state for draggable panel
  bool _isBottomSheetExpanded = false;
  bool _isPriceRangeSheetOpen = false;
  bool _isDraggingSheet = false;
  double _bottomSheetHeight = 110.0; // Initial height (collapsed)

  // Auction state (Driver bidding system)
  List<Map<String, dynamic>> _auctions = [];
  bool _isLoadingAuctions = false;
  Timer? _auctionTimer; // Timer for refreshing auction countdown

  // Text controllers for price input
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  // Price filter slider - up to 1,000,000
  double _minPriceFilter = 0.0;
  double _maxPriceFilter = 50000.0;

  // Wagon type filter - null means 'All'
  String? _selectedWagonTypeFilter;

  // Incoterm filter - null means 'All'
  String? _selectedIncotermFilter;

  /// Default `products.wagon_type` id — never use localized UI strings for matching.
  static const String _kDefaultWagonTypeId = 'refrigerated';

  // Price distribution for bar chart (10 buckets matching realistic price ranges)
  List<int> _priceDistribution = List.filled(10, 0);

  // Route selection flow state
  String?
  _selectedVehicleType; // 'car', 'van', 'truck', 'motorcycle', 'bicycle'
  final double _deliveryPrice = 0.0; // Price for delivery
  final double _cleaningCertificatePrice =
      0.0; // Price for cleaning certificate (if required)
  int _rawPriceCents = 0; // Raw cents value for price input
  int _rawCleaningCents = 0; // Raw cents value for cleaning certificate input
  String _priceMode = 'total'; // 'total' or 'per_km' or 'per_mile'
  Map<String, dynamic>? _currentAuctionForBid; // Current auction being bid on
  double _pickupToDeliveryDistance =
      0.0; // Distance from pickup to delivery only

  // Driver's vehicles from database
  List<Map<String, dynamic>> _driverVehicles = [];
  bool _isLoadingVehicles = false;
  int? _selectedVehicleId; // Selected vehicle ID from database

  // Sectional loading for selected vehicle
  final List<Map<String, dynamic>> _selectedVehicleSections = [];
  int? _selectedSectionIndex; // Selected section for this delivery

  // Occupied sections loaded from backend API (same as home_page)
  final Set<int> _occupiedSectionIndices =
      {}; // Track which sections are occupied
  final Map<int, Map<String, dynamic>> _occupiedSectionData =
      {}; // Store load data per section

  // Helper method to safely convert dynamic values to double
  double _toDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  // Helper method to normalize unit names to short forms
  String _normalizeUnit(String unit) {
    final unitLower = unit.toLowerCase().trim();
    // Weight units
    if (unitLower == 'gramm' || unitLower == 'gram' || unitLower == 'grams') {
      return 'g';
    }
    if (unitLower == 'kilogramm' ||
        unitLower == 'kilogram' ||
        unitLower == 'kilograms') {
      return 'kg';
    }
    if (unitLower == 'tonne' ||
        unitLower == 'tonnen' ||
        unitLower == 'ton' ||
        unitLower == 'tons') {
      return 't';
    }
    if (unitLower == 'pound' || unitLower == 'pounds') return 'lb';
    if (unitLower == 'ounce' || unitLower == 'ounces') return 'oz';
    // Volume units
    if (unitLower == 'liter' ||
        unitLower == 'litre' ||
        unitLower == 'liters' ||
        unitLower == 'litres') {
      return 'L';
    }
    if (unitLower == 'milliliter' ||
        unitLower == 'millilitre' ||
        unitLower == 'ml') {
      return 'mL';
    }
    if (unitLower == 'gallon' || unitLower == 'gallons') return 'gal';
    // Quantity units
    if (unitLower == 'piece' ||
        unitLower == 'pieces') {
      return 'pcs';
    }
    // Return original if no match
    return unit;
  }

  // Smart quantity formatting - removes unnecessary decimals
  String _formatQuantity(double value) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    // If it's a whole number, show without decimals
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    // If it has one decimal place significance
    if ((value * 10) == (value * 10).roundToDouble()) {
      return appSettings.formatNumber(value, decimals: 1);
    }
    // Otherwise show 2 decimal places
    return appSettings.formatNumber(value, decimals: 2);
  }

  // Helper function to format cents to price string (right-to-left input)
  String _formatCentsToPrice(int cents) {
    if (cents == 0) return '';
    final dollars = cents ~/ 100;
    final remainingCents = cents % 100;
    return '$dollars.${remainingCents.toString().padLeft(2, '0')}';
  }

  // Calculate price distribution from orders - 10 buckets: 0-50, 50-100, 100-150, 150-200, 200-300, 300-400, 400-600, 600-800, 800-1000, 1000+
  void _calculatePriceDistribution() {
    _priceDistribution = List.filled(10, 0);

    int orderIndex = 0;
    for (var order in orders) {
      // Get total price from order
      double totalPrice = 0.0;

      // DEBUG: Check first order structure - DETAILED PRICE INFO
      if (orderIndex == 0 && _kDebugMode) {
        print('\n🔍 ========== FIRST ORDER DETAILED INFO ==========');
        print('Order keys: ${order.keys.toList()}');
        print(
          'amount: ${order['amount']} (type: ${order['amount']?.runtimeType})');
        print('shipping_cost: ${order['shipping_cost']}');
        print('product_subtotal: ${order['product_subtotal']}');

        if (order['cart'] != null) {
          final cart = order['cart'] as List<dynamic>;
          print('\nCart items count: ${cart.length}');

          for (int i = 0; i < cart.length && i < 3; i++) {
            var item = cart[i];
            print('\n--- Item ${i + 1} ---');
            print('  All keys: ${item.keys.toList()}');
            print(
              '  product name: ${item['name'] ?? item['product_name'] ?? (AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr(''))}');
            print('  Price: \$${item['price']}');
            print('  Quantity: ${item['quantity']}');

            double itemPrice = _toDouble(item['price']);
            double itemQuantity = _toDouble(
              item['quantity'],
              defaultValue: 1.0);

            print('  Subtotal: \$${itemPrice * itemQuantity}');
          }
        }
        print('========================================\n');
      }

      // Use product_subtotal (excludes shipping) for price filter
      if (order['product_subtotal'] != null) {
        totalPrice = _toDouble(order['product_subtotal']);

        if (_kDebugMode && orderIndex < 3) {
          print(
            '📊 Order $orderIndex: Product price = \$$totalPrice (amount: \$${order['amount']}, shipping: \$${order['shipping_cost']})');
        }
      } else if (order['amount'] != null) {
        // Fallback: use total amount
        totalPrice = _toDouble(order['amount']);

        if (_kDebugMode && orderIndex < 3) {
          print('📊 Order $orderIndex: Using amount = \$$totalPrice');
        }
      } else if (order['cart'] != null) {
        // Last resort: Calculate from cart items
        final cart = order['cart'] as List<dynamic>;
        for (var item in cart) {
          double price = _toDouble(item['price']);
          final quantity =
              _toDouble(item['quantity'], defaultValue: 1.0) /
              100.0; // Convert from cents
          totalPrice += price * quantity;
        }
        if (_kDebugMode && orderIndex < 3) {
          print('📊 Order $orderIndex: Calculated from cart = {currencySymbol}$totalPrice');
        }
      }

      // Determine bucket with ranges up to 1000
      int bucketIndex;
      if (totalPrice < 50) {
        bucketIndex = 0; // 0-50{currencySymbol}
      } else if (totalPrice < 100)
        bucketIndex = 1; // 50-100{currencySymbol}
      else if (totalPrice < 150)
        bucketIndex = 2; // 100-150{currencySymbol}
      else if (totalPrice < 200)
        bucketIndex = 3; // 150-200{currencySymbol}
      else if (totalPrice < 300)
        bucketIndex = 4; // 200-300{currencySymbol}
      else if (totalPrice < 400)
        bucketIndex = 5; // 300-400{currencySymbol}
      else if (totalPrice < 600)
        bucketIndex = 6; // 400-600{currencySymbol}
      else if (totalPrice < 800)
        bucketIndex = 7; // 600-800{currencySymbol}
      else if (totalPrice < 1000)
        bucketIndex = 8; // 800-1000{currencySymbol}
      else
        bucketIndex = 9; // 1000+{currencySymbol}

      _priceDistribution[bucketIndex]++;
      orderIndex++;
    }

    if (_kDebugMode) {
      print('📊 Price Distribution: $_priceDistribution');
      print('📊 Total orders processed: ${orders.length}');
    }
  }

  @override
  void initState() {
    super.initState();

    print('\n');
    print('🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀');
    print('🚀 DELVIOO MAPS PAGE INIT STATE');
    print('🚀 Debug mode is: $_kDebugMode');
    print('🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀');
    print('\n');

    _mapController = MapController();
    // Restore locally saved map settings (search radius etc.)
    _loadMapSettings();

    // Set the real collapsed height once the safe-area is known (post-frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bottomPad = MediaQuery.paddingOf(context).bottom;
      final correctH = bottomPad + 110.0;
      if (_bottomSheetHeight < correctH) {
        setState(() => _bottomSheetHeight = correctH);
      }
    });

    // Ensure dock is visible when maps page initializes
    hideDockNotifier.value = false;

    // Listen to clearRouteNotifier from main_page
    clearRouteNotifier.addListener(_onClearRoute);

    _initializeMapsAccess();

  }

  Future<void> _initializeMapsAccess() async {
    // Load orders/auctions/location even when payout is missing so map pins and
    // merged auctions render; payout lock only blocks accepting/bidding actions.
    _getCurrentLocation();
    _loadOrders();
    _loadAcceptedOrders(); // Load accepted orders from database
    _loadAuctions(); // Load active auctions for bidding
    _loadDriverVehicles();

    final hasPayoutAccount = await _hasPayoutAccountConfigured();
    if (!mounted) return;

    if (!hasPayoutAccount) {
      setState(() {
        _isMapLockedByPayout = true;
        error =
            'Map is locked. Please add a payout bank account in Settings first.';
      });
    } else {
      setState(() {
        _isMapLockedByPayout = false;
        error = null;
      });
    }

    // Start continuous location tracking every 30 seconds (reduced from 15s for performance)
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) _getCurrentLocation();
    });

    // Start auction timer refresh every 30 seconds (reduced from 10s for performance)
    _auctionTimer?.cancel();
    _auctionTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) _loadAuctions();
    });
  }

  Future<bool> _hasPayoutAccountConfigured() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localUnlocked =
          prefs.getBool('delvioo_payout_account_verified') ?? false;
      if (localUnlocked) return true;

      final appSettings = Provider.of<AppSettings>(context, listen: false);

      final username =
          prefs.getString('username') ??
          prefs.getString('delvioo_username') ??
          appSettings.userEmail ??
          appSettings.userName;

      if (username == null || username.trim().isEmpty) {
        return false;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/profile/$username'),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode != 200) return false;

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['success'] != true || data['user'] == null) return false;

      final user = (data['user'] as Map).cast<String, dynamic>();

      bool hasValue(dynamic v) {
        if (v == null) return false;
        final s = v.toString().trim().toLowerCase();
        return s.isNotEmpty && s != 'null';
      }

      bool isUsableAccountToken(dynamic v, {int minLength = 4}) {
        if (!hasValue(v)) return false;
        final raw = v.toString().trim();
        if (raw.contains('*') || raw.contains('•')) return false;
        return raw.length >= minLength;
      }

      final hasStripe =
          isUsableAccountToken(user['stripe_bank_account_id']) ||
          isUsableAccountToken(user['stripeBankAccountId']);
      final hasAccountHolder =
          hasValue(user['account_holder_name']) || hasValue(user['accountHolderName']);
      final hasUsBank =
          isUsableAccountToken(user['routing_number'], minLength: 6) &&
          isUsableAccountToken(user['account_number'], minLength: 6) &&
          hasAccountHolder;
      final hasSepa =
          isUsableAccountToken(user['iban'], minLength: 15) &&
          isUsableAccountToken(user['swift_bic'], minLength: 8) &&
          hasAccountHolder;

      final unlocked = (hasStripe && hasAccountHolder) || hasUsBank || hasSepa;
      if (unlocked) {
        await prefs.setBool('delvioo_payout_account_verified', true);
      }
      return unlocked;
    } catch (e) {
      print('⚠️ Failed to validate payout account for maps lock: $e');
      return false;
    }
  }

  void _onClearRoute() {
    if (mounted) {
      setState(() {
        _routePoints.clear();
        _trafficSegments.clear();
        _activeRouteInfo = null;
        _showRouteInfo = false;
        _isRouteInfoMinimized = false;
        _isMapExpanded = false;
      });

      // Show dock again when route is cleared
      hideDockNotifier.value = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newSettings = Provider.of<AppSettings>(context, listen: false);
    if (_appSettings != newSettings) {
      _appSettings?.removeListener(_onAppThemeChanged);
      _appSettings = newSettings;
      _appSettings!.addListener(_onAppThemeChanged);
      _onAppThemeChanged();
    }
  }

  void _onAppThemeChanged() {
    if (!mounted || _appSettings == null) return;
    _syncNativeTheme(isLight: _appSettings!.isLightMode(context));
  }

  void _syncNativeTheme({required bool? isLight}) {
    if (!Platform.isIOS) return;
    // UIUserInterfaceStyle: 0 = unspecified, 1 = light, 2 = dark
    final style = isLight == null ? 0 : (isLight ? 1 : 2);
    _nativeThemeChannel.invokeMethod('setUserInterfaceStyle', style);
  }

  @override
  void dispose() {
    clearRouteNotifier.removeListener(_onClearRoute);
    _locationTimer?.cancel();
    _auctionTimer?.cancel();
    _routeInfoMinimizeTimer?.cancel();
    _routeAnimationController?.dispose();
    // DON'T dispose hideDockNotifier - it's managed by delvioo_main_page
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _appSettings?.removeListener(_onAppThemeChanged);
    super.dispose();
  }

  // Modern top notification system
  // Modern notifications now use TopNotification widget from shared/widgets
  // All notifications converted to TopNotification.success(), TopNotification.error(), TopNotification.info()

  /// API auctions plus orders that carry `active_auction_id` (from `/api/delvioo/orders`)
  /// so map pins still work if `/api/auctions/active` fails on device (wrong host, SSL, etc.).
  List<Map<String, dynamic>> _mergedAuctions() {
    final byOrderId = <String, Map<String, dynamic>>{};
    for (final a in _auctions) {
      final oid = a['order_id']?.toString();
      if (oid != null && oid.isNotEmpty) {
        byOrderId[oid] = Map<String, dynamic>.from(a);
      }
    }
    for (final o in orders) {
      final oid = o['id']?.toString();
      if (oid == null || oid.isEmpty) continue;
      final aid = o['active_auction_id'];
      if (aid == null) continue;
      if (byOrderId.containsKey(oid)) continue;
      byOrderId[oid] = _syntheticAuctionFromOrder(o);
    }
    return byOrderId.values.toList();
  }

  /// Wagon type from order line items (`products.wagon_type` via API on each item).
  String? _wagonTypeFromOrderLineItems(dynamic items) {
    if (items is! List) return null;
    for (final raw in items) {
      if (raw is Map) {
        final w = raw['wagon_type'] ?? raw['product_wagon_type'];
        final s = w?.toString().trim();
        if (s != null && s.isNotEmpty) return normalizeWagonTypeId(s);
      }
    }
    return null;
  }

  Map<String, dynamic> _syntheticAuctionFromOrder(Map<String, dynamic> o) {
    dynamic end = o['auction_end_time'];
    if (end is DateTime) {
      end = end.toUtc().toIso8601String();
    }
    final wagonFromOrder =
        o['wagon_type'] ?? o['product_wagon_type'] ?? _wagonTypeFromOrderLineItems(o['items']);
    return {
      'id': o['active_auction_id'],
      'order_id': o['id'],
      'buyer_username': o['username'],
      'auction_duration_minutes': o['auction_duration_minutes'] ?? 60,
      'end_time': end,
      'status': 'active',
      'pickup_lat': o['pickup_lat'],
      'pickup_lng': o['pickup_lng'],
      'wagon_type': wagonFromOrder,
      'order_total': o['amount'],
      'order_cart': o['items'],
      'total_quantity': o['total_quantity'],
      'quantity_unit': o['quantity_unit'],
      'total_bids': 0,
    };
  }

  // Filter auctions by remaining time, optional wagon/price (not by driver GPS radius).
  List<Map<String, dynamic>> get _filteredAuctions {
    return _mergedAuctions().where((auction) {
      // First check if auction is expired
      final remaining = _getAuctionRemainingTime(auction);
      if (remaining == null || remaining <= Duration.zero) {
        return false; // Don't show expired auctions
      }

      // Filter by wagon/vehicle type
      if (_selectedWagonTypeFilter != null) {
        final auctionWagonType =
            _resolvedWagonTypeForAuction(auction).toLowerCase();
        final filterType = _selectedWagonTypeFilter!.toLowerCase();

        // Match wagon types - first check exact match, then variations
        bool typeMatches = auctionWagonType == filterType;

        if (!typeMatches) {
          // Check for variations/synonyms
          if (filterType == 'grain') {
            typeMatches =
                auctionWagonType.contains('grain') ||
                auctionWagonType.contains('hopper');
          } else if (filterType == 'oil') {
            typeMatches =
                auctionWagonType.contains('oil') ||
                auctionWagonType.contains('tanker');
          } else if (filterType == 'refrigerated') {
            typeMatches =
                auctionWagonType.contains('refrigerat') ||
                auctionWagonType.contains('cold') ||
                auctionWagonType.contains('reefer') ||
                auctionWagonType.contains('food_safe');
          } else if (filterType == 'liquid_food') {
            typeMatches =
                auctionWagonType.contains('liquid') ||
                auctionWagonType.contains('liquid_food');
          } else if (filterType == 'dry_bulk') {
            typeMatches =
                auctionWagonType.contains('dry') ||
                auctionWagonType.contains('bulk');
          } else if (filterType == 'fresh_produce') {
            typeMatches =
                auctionWagonType.contains('fresh') ||
                auctionWagonType.contains('produce');
          } else if (filterType == 'frozen') {
            typeMatches = auctionWagonType.contains('frozen');
          } else if (filterType == 'bakery') {
            typeMatches =
                auctionWagonType.contains('bakery') ||
                auctionWagonType.contains('baked');
          } else if (filterType == 'beverage') {
            typeMatches =
                auctionWagonType.contains('beverage') ||
                auctionWagonType.contains('drink');
          } else if (filterType == 'meat') {
            typeMatches = auctionWagonType.contains('meat');
          } else {
            typeMatches = auctionWagonType.contains(filterType);
          }
        }

        if (!typeMatches) {
          if (_kDebugMode) {
            print(
              '🚛 Filtering out auction ${auction['id']}: wagon type "$auctionWagonType" does not match filter "$filterType"');
          }
          return false;
        }
      }

      // Filter by price range
      final auctionPrice = _getAuctionPrice(auction);
      if (auctionPrice < _minPriceFilter || auctionPrice > _maxPriceFilter) {
        return false;
      }

      // Filter by incoterm
      if (_selectedIncotermFilter != null) {
        final auctionIncoterm = auction['incoterm'] as String?;
        print('🔍 Incoterm filter: selected=$_selectedIncotermFilter, auction=$auctionIncoterm');
        if (auctionIncoterm != _selectedIncotermFilter) {
          return false;
        }
      }

      // Do NOT filter auctions by driver GPS radius. Pickup can be thousands of km
      // away (e.g. US pickup while driver is in EU); the map can still be panned.
      // Order markers still respect radius in _filteredOrders.

      return true;
    }).toList();
  }

  // Helper to get auction price
  double _getAuctionPrice(Map<String, dynamic> auction) {
    // Try different price fields
    if (auction['current_bid'] != null) {
      return _toDouble(auction['current_bid']);
    }
    if (auction['starting_price'] != null) {
      return _toDouble(auction['starting_price']);
    }
    if (auction['price'] != null) {
      return _toDouble(auction['price']);
    }
    if (auction['amount'] != null) {
      return _toDouble(auction['amount']);
    }
    if (auction['order_total'] != null) {
      return _toDouble(auction['order_total']);
    }
    return 0.0;
  }

  // Helper to get order price
  double _getOrderPrice(Map<String, dynamic> order) {
    // Use product_subtotal (excludes shipping) for price filter
    if (order['product_subtotal'] != null) {
      return _toDouble(order['product_subtotal']);
    }
    if (order['amount'] != null) {
      return _toDouble(order['amount']);
    }
    if (order['total'] != null) {
      return _toDouble(order['total']);
    }
    // Calculate from cart items if available
    if (order['cart'] != null) {
      double total = 0.0;
      final cart = order['cart'] as List<dynamic>;
      for (var item in cart) {
        double price = _toDouble(item['price']);
        final quantity =
            _toDouble(item['quantity'], defaultValue: 1.0) /
            100.0; // Convert from cents
        total += price * quantity;
      }
      return total;
    }
    return 0.0;
  }

  // Helper to get required vehicle type from order
  String _getOrderRequiredVehicleType(Map<String, dynamic> order) {
    // Try different fields for required vehicle type
    if (order['wagon_type'] != null &&
        order['wagon_type'].toString().isNotEmpty) {
      print('🚛 Found wagon_type in order: ${order['wagon_type']}');
      return normalizeWagonTypeId(order['wagon_type'].toString());
    }
    if (order['product_wagon_type'] != null &&
        order['product_wagon_type'].toString().isNotEmpty) {
      print(
        '🚛 Found product_wagon_type in order: ${order['product_wagon_type']}');
      return normalizeWagonTypeId(order['product_wagon_type'].toString());
    }
    if (order['vehicle_type'] != null &&
        order['vehicle_type'].toString().isNotEmpty) {
      print('🚛 Found vehicle_type in order: ${order['vehicle_type']}');
      return normalizeWagonTypeId(order['vehicle_type'].toString());
    }
    if (order['required_vehicle_type'] != null &&
        order['required_vehicle_type'].toString().isNotEmpty) {
      print(
        '🚛 Found required_vehicle_type in order: ${order['required_vehicle_type']}');
      return normalizeWagonTypeId(order['required_vehicle_type'].toString());
    }
    // Line items: API uses `items` (processed delvioo orders); raw orders may use `cart`.
    for (final key in ['items', 'cart']) {
      final raw = order[key];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        if (m['wagon_type'] != null &&
            m['wagon_type'].toString().isNotEmpty) {
          print('🚛 Found wagon_type in order line ($key): ${m['wagon_type']}');
          return normalizeWagonTypeId(m['wagon_type'].toString());
        }
        if (m['product_wagon_type'] != null &&
            m['product_wagon_type'].toString().isNotEmpty) {
          print(
            '🚛 Found product_wagon_type in order line ($key): ${m['product_wagon_type']}');
          return normalizeWagonTypeId(m['product_wagon_type'].toString());
        }
        if (m['vehicle_type'] != null &&
            m['vehicle_type'].toString().isNotEmpty) {
          print('🚛 Found vehicle_type in order line ($key): ${m['vehicle_type']}');
          return normalizeWagonTypeId(m['vehicle_type'].toString());
        }
      }
    }
    print('🚛 No wagon_type found in order, using default: refrigerated');
    // Default to refrigerated (same as backend default)
    return normalizeWagonTypeId(_kDefaultWagonTypeId);
  }

  /// Required wagon id for matching: auction payload, then linked row in [orders].
  String _resolvedWagonTypeForAuction(Map<String, dynamic> auction) {
    for (final key in ['wagon_type', 'vehicle_type', 'product_wagon_type']) {
      final v = auction[key];
      final s = v?.toString().trim();
      if (s != null && s.isNotEmpty) return normalizeWagonTypeId(s);
    }
    final oid = auction['order_id']?.toString();
    if (oid != null && oid.isNotEmpty) {
      for (final o in orders) {
        if (o['id']?.toString() == oid) {
          return normalizeWagonTypeId(_getOrderRequiredVehicleType(o));
        }
      }
    }
    return normalizeWagonTypeId(_kDefaultWagonTypeId);
  }

  // Filter orders by distance and enrich with acceptance status
  List<Map<String, dynamic>> get _filteredOrders {
    // Get accepted orders with their status information
    // IMPORTANT: acceptedOrders have numeric order_id (e.g. 2), orders have this as 'id'
    final acceptedOrdersMap = <String, Map<String, dynamic>>{};
    final acceptedOrderIds = <String>{};

    for (var acceptedOrder in _acceptedOrders) {
      final numericOrderId = acceptedOrder['order_id']?.toString() ?? AppLocalizations.of(context)!.tr('');
      if (numericOrderId.isNotEmpty) {
        acceptedOrdersMap[numericOrderId] = acceptedOrder;
        acceptedOrderIds.add(numericOrderId);
        print(
          '🔑 Mapping accepted order: numeric ID $numericOrderId -> status ${acceptedOrder['acceptance_status']}');
      }
    }

    // Process all orders and enrich with status information
    final enrichedOrders = orders.map((order) {
      final orderId = order['id'].toString();
      final acceptedOrder = acceptedOrdersMap[orderId];

      // Create a copy of the order with status information
      final enrichedOrder = Map<String, dynamic>.from(order);

      if (acceptedOrder != null) {
        enrichedOrder['acceptance_status'] =
            acceptedOrder['acceptance_status'] ??
            acceptedOrder['status'] ?? AppLocalizations.of(context)!.tr('accepted');
        enrichedOrder['accepted_at'] =
            acceptedOrder['acceptedAt'] ?? acceptedOrder['accepted_at'];
        enrichedOrder['security_code'] = acceptedOrder['security_code'];
        // Add issue fields for emergency markers
        enrichedOrder['has_issue'] = acceptedOrder['has_issue'];
        enrichedOrder['issue_id'] = acceptedOrder['issue_id'];
        enrichedOrder['issue_latitude'] = acceptedOrder['issue_latitude'];
        enrichedOrder['issue_longitude'] = acceptedOrder['issue_longitude'];
        enrichedOrder['issue_emergency'] = acceptedOrder['issue_emergency'];
        final displayOrderId = order['order_id'] ?? orderId;
        print(
          '✅ Order #$displayOrderId (id: $orderId) found in accepted orders with status: ${enrichedOrder['acceptance_status']}, has_issue: ${enrichedOrder['has_issue']}');
      } else {
        enrichedOrder['acceptance_status'] = 'available';
        final displayOrderId = order['order_id'] ?? orderId;
        print(
          '❌ Order #$displayOrderId (id: $orderId) NOT found in accepted orders - setting as available');
      }

      return enrichedOrder;
    }).toList();

    // Add accepted orders that are NOT in the main orders list (e.g., orders that were accepted and removed from available list)
    for (var acceptedOrder in _acceptedOrders) {
      final orderId = acceptedOrder['order_id']?.toString() ?? AppLocalizations.of(context)!.tr('');
      if (orderId.isNotEmpty &&
          !orders.any((o) => o['id']?.toString() == orderId)) {
        // This accepted order is not in the main orders list, add it directly
        final enrichedOrder = Map<String, dynamic>.from(acceptedOrder);
        // Ensure the order has an 'id' field matching the order_id
        enrichedOrder['id'] = acceptedOrder['order_id'];
        print(
          '➕ Adding accepted order #${acceptedOrder['order_id']} directly to map (not in available orders), has_issue: ${enrichedOrder['has_issue']}');
        enrichedOrders.add(enrichedOrder);
      }
    }

    return enrichedOrders.where((order) {
      // FIRST: Filter out delivered orders - they should not appear on map
      // Keep confirmed, pending, ready_for_pickup, delvioo_accepted, picked_up orders visible
      final orderStatus = order['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');
      if (orderStatus == 'delivered' ||
          orderStatus == 'completed' ||
          orderStatus == 'cancelled') {
        final displayOrderId = order['order_id'] ?? order['id'];
        print(
          '🚫 Filtering out order #$displayOrderId: status is $orderStatus');
        return false;
      }

      // SECOND: Only show orders that have an active auction
      // Orders without an auction are not visible to drivers
      final orderId = order['id'];
      final hasActiveAuction = _mergedAuctions().any((a) =>
          a['order_id']?.toString() == orderId?.toString() &&
          a['status']?.toString() == 'active');
      // Always show accepted orders (already picked up / being delivered)
      final isAccepted = order['acceptance_status'] != null &&
          order['acceptance_status'] != 'available';
      if (!hasActiveAuction && !isAccepted) {
        if (_kDebugMode) {
          final displayOrderId = order['order_id'] ?? orderId;
          print(
            '🔒 Filtering out order #$displayOrderId: no active auction');
        }
        return false;
      }

      // THIRD: Apply shipping type filter
      if (_selectedShippingFilter != 'all') {
        final shippingType =
            order['shipping_type']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');

        if (_selectedShippingFilter == 'standard') {
          // Standard = shipping_type should be 'delvioo'
          if (shippingType != 'delvioo') {
            if (_kDebugMode) {
              final displayOrderId = order['order_id'] ?? order['id'];
              print(
                '🚫 Filtering out order #$displayOrderId: shipping_type is $shippingType (expected delvioo)');
            }
            return false;
          }
        } else if (_selectedShippingFilter == 'cold') {
          // Cold = cold_shipping == 1 or cold_shipping == true
          final coldShipping = order['cold_shipping'];
          final isCold =
              coldShipping == 1 || coldShipping == true || coldShipping == '1';
          if (!isCold) {
            if (_kDebugMode) {
              final displayOrderId = order['order_id'] ?? order['id'];
              print(
                '🚫 Filtering out order #$displayOrderId: cold_shipping is $coldShipping');
            }
            return false;
          }
        }
      }

      // Show all active orders including: confirmed, pending, ready_for_pickup, delvioo_accepted, picked_up
      if (_kDebugMode) {
        final displayOrderId = order['order_id'] ?? order['id'];
        print('✅ Showing order #$displayOrderId with status: $orderStatus');
      }

      // Don't filter by acceptance status - show all orders
      // Orders with acceptance_status != 'available' will be shown with strikethrough

      // Filter by distance to current location
      if (currentLocation != null) {
        final pickupLocation = _getPickupCoordinatesSync(order);
        if (pickupLocation != null) {
          final distance =
              Geolocator.distanceBetween(
                currentLocation!.latitude,
                currentLocation!.longitude,
                pickupLocation.latitude,
                pickupLocation.longitude) /
              1000; // Convert to kilometers

          if (!_searchRadius.isInfinite && distance > _searchRadius) {
            if (_kDebugMode) {
              final displayOrderId = order['order_id'] ?? order['id'];
              print(
                '📏 Filtering out order #$displayOrderId: distance ${distance.toStringAsFixed(1)}km > radius ${_searchRadius}km');
            }
            return false;
          }
        }
      }

      // Filter by price range
      final orderPrice = _getOrderPrice(order);
      if (orderPrice < _minPriceFilter || orderPrice > _maxPriceFilter) {
        if (_kDebugMode) {
          final displayOrderId = order['order_id'] ?? order['id'];
          print(
            '💰 Filtering out order #$displayOrderId: price $orderPrice not in range $_minPriceFilter - $_maxPriceFilter');
        }
        return false;
      }

      // Filter by wagon/vehicle type
      if (_selectedWagonTypeFilter != null) {
        final orderWagonType = _getOrderRequiredVehicleType(
          order).toLowerCase();
        final filterType = _selectedWagonTypeFilter!.toLowerCase();

        // Debug: Always log wagon type info when filter is active
        final displayOrderId = order['order_id'] ?? order['id'];
        print(
          '🔍 Order #$displayOrderId wagon_type check: order["wagon_type"]=${order["wagon_type"]}, extracted="$orderWagonType", filter="$filterType"');

        // Match wagon types - first check exact match, then variations
        bool typeMatches = orderWagonType == filterType;

        if (!typeMatches) {
          // Check for variations/synonyms
          if (filterType == 'grain') {
            typeMatches =
                orderWagonType.contains('grain') ||
                orderWagonType.contains('hopper');
          } else if (filterType == 'oil') {
            typeMatches =
                orderWagonType.contains('oil') ||
                orderWagonType.contains('tanker');
          } else if (filterType == 'refrigerated') {
            typeMatches =
                orderWagonType.contains('refrigerat') ||
                orderWagonType.contains('cold') ||
                orderWagonType.contains('reefer');
          } else if (filterType == 'liquid_food') {
            typeMatches =
                orderWagonType.contains('liquid') ||
                orderWagonType.contains('liquid_food');
          } else if (filterType == 'dry_bulk') {
            typeMatches =
                orderWagonType.contains('dry') ||
                orderWagonType.contains('bulk');
          } else if (filterType == 'fresh_produce') {
            typeMatches =
                orderWagonType.contains('fresh') ||
                orderWagonType.contains('produce');
          } else if (filterType == 'frozen') {
            typeMatches = orderWagonType.contains('frozen');
          } else if (filterType == 'bakery') {
            typeMatches =
                orderWagonType.contains('bakery') ||
                orderWagonType.contains('baked');
          } else if (filterType == 'beverage') {
            typeMatches =
                orderWagonType.contains('beverage') ||
                orderWagonType.contains('drink');
          } else if (filterType == 'meat') {
            typeMatches = orderWagonType.contains('meat');
          } else {
            typeMatches = orderWagonType.contains(filterType);
          }
        }

        if (!typeMatches) {
          if (_kDebugMode) {
            final displayOrderId = order['order_id'] ?? order['id'];
            print(
              '🚛 Filtering out order #$displayOrderId: vehicle type "$orderWagonType" does not match filter "$filterType"');
          }
          return false;
        }
      }

      return true;
    }).toList();
  }

  // Cluster nearby orders for better visualization (optimized for performance)
  List<List<Map<String, dynamic>>> _clusterOrders(
    List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) return [];

    // Reduced for performance: 50 -> 30 Orders max
    List<Map<String, dynamic>> limitedOrders = orders.take(30).toList();

    List<List<Map<String, dynamic>>> clusters = [];
    List<Map<String, dynamic>> unclustered = List.from(limitedOrders);

    // Get current zoom level from map controller (with safety check)
    double currentZoom = 13.0; // Default zoom level
    if (Platform.isIOS) {
      currentZoom = _appleMapZoomLevel;
    } else if (_isMapReady) {
      try {
        currentZoom = _mapController.camera.zoom;
      } catch (e) {
        // Map controller not ready yet, use default zoom
      }
    }

    // Clustering distance based on zoom level - closer zoom = less clustering
    double clusterDistance = _getClusterDistance(currentZoom);

    // Reduced logging for better performance
    if (_kDebugMode) {
      bool shouldLog = (currentZoom - _lastZoomLevel).abs() > 0.5;
      if (shouldLog) {
        print(
          '🗺️ Zoom: $currentZoom, Cluster distance: ${clusterDistance}m, Orders: ${limitedOrders.length}');
        _lastZoomLevel = currentZoom;
      }
    }

    while (unclustered.isNotEmpty) {
      Map<String, dynamic> centerOrder = unclustered.removeAt(0);
      List<Map<String, dynamic>> cluster = [centerOrder];

      LatLng? centerLocation = _getPickupCoordinatesSync(centerOrder);
      if (centerLocation == null) {
        clusters.add(cluster);
        continue;
      }

      // Find nearby orders to cluster together
      List<Map<String, dynamic>> toRemove = [];

      for (Map<String, dynamic> otherOrder in unclustered) {
        LatLng? otherLocation = _getPickupCoordinatesSync(otherOrder);
        if (otherLocation == null) continue;

        // Calculate distance between orders
        double distance = Geolocator.distanceBetween(
          centerLocation.latitude,
          centerLocation.longitude,
          otherLocation.latitude,
          otherLocation.longitude);

        // If within cluster distance, add to cluster
        if (distance <= clusterDistance) {
          cluster.add(otherOrder);
          toRemove.add(otherOrder);
        }
      }

      // Remove clustered orders from unclustered list
      for (var order in toRemove) {
        unclustered.remove(order);
      }

      clusters.add(cluster);
    }

    // Only log clustering results when zoom changes significantly
    if (_kDebugMode && (currentZoom - _lastZoomLevel).abs() > 0.5) {
      print('Created ${clusters.length} clusters from ${orders.length} orders');
    }
    return clusters;
  }

  // Get clustering distance based on zoom level
  double _getClusterDistance(double zoom) {
    // Higher zoom = smaller distance = less aggressive clustering
    // Lower zoom = larger distance = more aggressive clustering
    if (zoom >= 16) return 50; // Very close zoom - 50m clustering
    if (zoom >= 14) return 200; // Close zoom - 200m clustering
    if (zoom >= 12) return 500; // Medium zoom - 500m clustering
    if (zoom >= 10) return 1000; // Far zoom - 1km clustering
    return 2000; // Very far zoom - 2km clustering
  }

  Future<void> _loadOrders() async {
    setState(() {
      isLoading = true;
      if (!_isMapLockedByPayout) {
        error = null;
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('auth_token') ?? prefs.getString('token');

      final response = await http.get(
        Uri.parse(ApiConfig.delviooOrdersUrl),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print(
          '📊 Orders API response: ${responseData.runtimeType}, length: ${responseData is List ? responseData.length : 'N/A'}');

        // Check if response is an array (new format) or has error
        if (responseData is List) {
          List<Map<String, dynamic>> loadedOrders =
              List<Map<String, dynamic>>.from(responseData);
          print('📦 Loaded ${loadedOrders.length} orders from API');

          // DEBUG: Check first order's delivery data
          if (loadedOrders.isNotEmpty) {
            final firstOrder = loadedOrders[0];
            print('🔍 First order delivery check:');
            print('   Order ID: ${firstOrder['id']}');
            print('   Has delivery: ${firstOrder['delivery'] != null}');
            if (firstOrder['delivery'] != null) {
              final del = firstOrder['delivery'] as Map<String, dynamic>;
              print('   Delivery keys: ${del.keys.toList()}');
              print('   street: ${del['street']}');
              print('   house_number: ${del['house_number']}');
              print('   postal_code: ${del['postal_code']}');
              print('   city: ${del['city']}');
              print('   country: ${del['country']}');

              // Deep check for nested or string values
              print('   Delivery object type: ${del.runtimeType}');
              print('   Full delivery JSON: ${json.encode(del)}');
            } else {
              print('   ⚠️ WARNING: delivery is NULL!');
            }
          }

          // Filter out orders without valid items to prevent issues
          loadedOrders = loadedOrders.where((order) {
            final items = order['items'] as List<dynamic>?;
            return items != null && items.isNotEmpty;
          }).toList();

          print('📦 After filtering: ${loadedOrders.length} valid orders');
          final withAuction = loadedOrders
              .where((o) => o['active_auction_id'] != null)
              .length;
          print(
            '🎯 Delvioo map orders: url=${ApiConfig.delviooOrdersUrl} withItems=${loadedOrders.length} activeAuction=$withAuction');

          // Set orders immediately to show them quickly
          if (mounted) {
            setState(() {
              orders = loadedOrders;
              isLoading = false;
              _calculatePriceDistribution(); // Calculate price distribution
            });
          }

          // DEBUG: Test delivery address extraction for first order
          if (loadedOrders.isNotEmpty) {
            final testOrder = loadedOrders.first;
            print('\n🧪 ========== DELIVERY ADDRESS TEST ==========');
            print('🧪 Testing first order: ID ${testOrder['id']}');
            print('🧪 Order keys: ${testOrder.keys.toList()}');
            print('🧪 Has delivery? ${testOrder.containsKey('delivery')}');
            if (testOrder.containsKey('delivery')) {
              final del = testOrder['delivery'];
              print('🧪 delivery type: ${del?.runtimeType}');
              if (del is Map) {
                print('🧪 delivery.address = "${del['address']}"');
              }
            }
            final result = _getDeliveryAddressFromOrder(testOrder);
            print('🧪 RESULT from _getDeliveryAddressFromOrder: "$result"');
            print('🧪 ==========================================\n');
          }

          // Enrich orders with coordinates in background (non-blocking)
          _enrichOrdersInBackground(loadedOrders);
        } else if (responseData is Map && responseData['error'] != null) {
          print('❌ API Error: ${responseData['error']}');
          if (mounted) {
            setState(() {
              error = 'API Error: ${responseData['error']}';
              isLoading = false;
            });
          }
        } else {
          print('⚠️ Unexpected response format: ${responseData.runtimeType}');
          if (mounted) {
            setState(() {
              error = 'Unexpected response format';
              isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            error = '${AppLocalizations.of(context)?.failedToLoadOrders ?? AppLocalizations.of(context)!.tr('Failed to load orders')}: ${response.statusCode}';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Connection error - could not load orders';
          isLoading = false;
        });
      }
    }
  }

  // Load accepted orders from database
  Future<void> _loadAcceptedOrders() async {
    try {
      print('🔄 Loading accepted orders from database...');

      // Fixed driver ID for now - in production this should come from authentication
      const int driverId = 1;

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delvioo/driver-acceptances/$driverId'),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['acceptances'] is List) {
          final acceptances = List<Map<String, dynamic>>.from(
            data['acceptances']);

          // Update the static accepted orders list
          _acceptedOrders.clear();
          _acceptedOrders.addAll(acceptances);

          print('✅ Loaded ${acceptances.length} accepted orders from database');

          // DEBUG: Print all accepted orders with their vehicle and section info
          if (_kDebugMode) {
            print('\n🔍 DETAILED ACCEPTED ORDERS DEBUG:');
            for (var order in acceptances) {
              print('  Order ID: ${order['order_id']}');
              print(
                '    vehicle_id: ${order['vehicle_id']} (type: ${order['vehicle_id']?.runtimeType})');
              print(
                '    section_index: ${order['section_index']} (type: ${order['section_index']?.runtimeType})');
              print('    section_name: ${order['section_name']}');
              print('    status: ${order['acceptance_status']}');
            }
            print('🔍 END DEBUG\n');
          }

          // Refresh UI
          if (mounted) {
            setState(() {});
          }
        }
      } else {
        print('❌ Failed to load accepted orders: ${response.statusCode}');
      }
    } catch (e) {
      print('💥 Error loading accepted orders: $e');
    }
  }

  // Load active auctions for driver bidding
  Future<void> _loadAuctions() async {
    setState(() {
      _isLoadingAuctions = true;
    });

    try {
      final url = ApiConfig.activeAuctionsUrl;
      print('🎯 Loading active auctions from $url');

      // Get auth token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('auth_token') ?? prefs.getString('token');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final ok = data['success'] == true ||
            data['success'] == 1 ||
            data['success'] == 'true';
        final rawList = data['auctions'] ?? data['data'];
        if (ok && rawList is List) {
          final loadedAuctions = List<Map<String, dynamic>>.from(
            rawList);

          if (mounted) {
            setState(() {
              _auctions = loadedAuctions;
              _isLoadingAuctions = false;
            });
          }

          print('✅ Loaded ${loadedAuctions.length} active auctions');

          // Debug: Show auction details including coordinates
          for (var auction in loadedAuctions) {
            print(
              '  📦 Auction #${auction['id']} for Order #${auction['order_id']}');
            print('     Buyer: ${auction['buyer_username']}');
            print('     Ends: ${auction['end_time']}');
            print('     Bids: ${auction['total_bids'] ?? 0}');
            print('     pickup_lat: ${auction['pickup_lat']}');
            print('     pickup_lng: ${auction['pickup_lng']}');
            print('     total_quantity: ${auction['total_quantity']}');
            print('     quantity_unit: ${auction['quantity_unit']}');
            print('     order_cart: ${auction['order_cart']}');
            print('     my_bid: ${auction['my_bid']}');
            print('     All keys: ${auction.keys.toList()}');
          }
        } else {
          print(
            '⚠️ Auctions API unexpected: success=${data['success']} ok=$ok listType=${rawList.runtimeType}');
          if (mounted) {
            setState(() {
              _auctions = [];
              _isLoadingAuctions = false;
            });
          }
        }
      } else {
        print('❌ Failed to load auctions: ${response.statusCode}');
        final b = response.body;
        print(
          '❌ Body (truncated): ${b.length > 400 ? '${b.substring(0, 400)}…' : b}');
        if (mounted) {
          setState(() {
            _auctions = [];
            _isLoadingAuctions = false;
          });
        }
      }
    } catch (e) {
      print('💥 Error loading auctions: $e');
      if (mounted) {
        setState(() {
          _auctions = [];
          _isLoadingAuctions = false;
        });
      }
    }
  }

  // Check if an order has an active auction
  Map<String, dynamic>? _getAuctionForOrder(dynamic orderId) {
    final orderIdStr = orderId?.toString();
    if (orderIdStr == null) return null;

    for (var auction in _mergedAuctions()) {
      if (auction['order_id']?.toString() == orderIdStr) {
        return auction;
      }
    }
    return null;
  }

  // Calculate remaining time for auction
  Duration? _getAuctionRemainingTime(Map<String, dynamic> auction) {
    try {
      final endTimeStr = auction['end_time']?.toString();
      if (endTimeStr == null || endTimeStr.isEmpty) {
        // Keep marker visible when backend omits end_time (older clients / synthetic merge).
        return const Duration(hours: 48);
      }

      final endTime = DateTime.parse(endTimeStr);
      final now = DateTime.now();
      final remaining = endTime.difference(now);

      return remaining.isNegative ? Duration.zero : remaining;
    } catch (e) {
      print('Error parsing auction end time: $e');
      // Treat as still active so the marker is not dropped on odd date formats.
      return const Duration(hours: 24);
    }
  }

  // Format duration as countdown string
  String _formatCountdown(Duration duration) {
    if (duration == Duration.zero) return 'Expired';

    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String _formatRouteDuration(double minutesValue) {
    final totalMinutes = minutesValue.round();
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) {
      return '$hours h';
    }
    return '$hours h $minutes min';
  }

  // Get coordinates for an auction from the pickup location (from products table)
  LatLng? _getAuctionCoordinates(Map<String, dynamic> auction) {
    try {
      // FIRST PRIORITY: Use pickup coordinates from products table
      final pickupLat = auction['pickup_lat'];
      final pickupLng = auction['pickup_lng'];
      if (pickupLat != null && pickupLng != null) {
        final lat = double.tryParse(pickupLat.toString());
        final lng = double.tryParse(pickupLng.toString());
        if (lat != null && lng != null && lat != 0 && lng != 0) {
          print(
            '📍 Using pickup coordinates for auction ${auction['id']}: $lat, $lng');
          return LatLng(lat, lng);
        }
      }

      // SECOND: Try to parse delivery_address JSON
      final deliveryAddressRaw = auction['delivery_address'];
      if (deliveryAddressRaw != null) {
        Map<String, dynamic>? addressData;
        if (deliveryAddressRaw is String) {
          addressData = json.decode(deliveryAddressRaw);
        } else if (deliveryAddressRaw is Map) {
          addressData = Map<String, dynamic>.from(deliveryAddressRaw);
        }

        if (addressData != null) {
          final lat = addressData['lat'];
          final lng = addressData['lng'];
          if (lat != null && lng != null) {
            final latNum = double.tryParse(lat.toString());
            final lngNum = double.tryParse(lng.toString());
            if (latNum != null &&
                lngNum != null &&
                latNum != 0 &&
                lngNum != 0) {
              return LatLng(latNum, lngNum);
            }
          }

          // If no lat/lng, try to use city for approximate coordinates
          final city = addressData['city']?.toString();
          if (city != null && city.toLowerCase().contains('krefeld')) {
            return const LatLng(51.3388, 6.5853);
          }
        }
      }

      // FALLBACK: Use default location with offset based on auction ID
      final auctionId = auction['id'] ?? 0;
      final offset = (auctionId % 10) * 0.005;
      print('⚠️ Using fallback coordinates for auction $auctionId');
      return LatLng(51.3388 + offset, 6.5853 + offset);
    } catch (e) {
      print('💥 Error parsing auction coordinates: $e');
      return const LatLng(51.3388, 6.5853);
    }
  }

  // Get product name from auction cart data
  String _getProductNameFromAuction(Map<String, dynamic> auction) {
    try {
      final cart = auction['order_cart'];
      if (cart == null) return 'Product';

      List<dynamic> cartItems;
      if (cart is String) {
        cartItems = json.decode(cart);
      } else if (cart is List) {
        cartItems = cart;
      } else {
        return 'Product';
      }

      if (cartItems.isNotEmpty) {
        final firstItem = cartItems[0];
        final name =
            firstItem['product_name'] ??
            firstItem['name'] ??
            firstItem['productName'] ?? AppLocalizations.of(context)!.tr('Product');
        // Shorten long names
        if (name.length > 12) {
          return '${name.substring(0, 10)}...';
        }
        return name;
      }
    } catch (e) {
      print('Error parsing auction cart: $e');
    }
    return 'Product';
  }

  // Build auction marker widget - Simple clean white pill
  Widget _buildAuctionMarker(Map<String, dynamic> auction, bool isLight) {
    final remainingTime = _getAuctionRemainingTime(auction);
    final bidCount = auction['total_bids'] ?? 0;
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final orderTotal = _toDouble(auction['order_total']);
    final priceText = appSettings.formatCurrency(orderTotal);
    final countdownText = remainingTime != null
        ? _formatCountdown(remainingTime)
        : '0s';

    // Has the driver already placed a bid on this auction?
    final hasBid = auction['my_bid'] != null;
    final myBidAmount = hasBid
        ? _toDouble(auction['my_bid']['bid_amount'] ?? auction['my_bid']['amount'])
        : 0.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main pill
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            // Green tint when bid placed, white otherwise
            color: hasBid
                ? const Color(0xFFE6F9ED)
                : Colors.white,
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            border: hasBid
                ? Border.all(color: const Color(0xFF34C759), width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: hasBid
                    ? const Color(0xFF34C759).withOpacity(0.25)
                    : Colors.black.withOpacity(0.18),
                blurRadius: 8,
                offset: const Offset(0, 2)),
            ]),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Price
                Text(
                  priceText,
                  style: TextStyle(
                    color: hasBid ? const Color(0xFF1A7A35) : Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
                // Timer + bids (or "My Bid" when bid placed)
                if (hasBid)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        size: 9,
                        color: Color(0xFF34C759)),
                      SizedBox(width: 2),
                      Text(
                        appSettings.formatCurrency(myBidAmount),
                        style: TextStyle(
                          color: Color(0xFF34C759),
                          fontSize: 9,
                          fontWeight: FontWeight.w600)),
                    ])
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        countdownText,
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 9,
                          fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                      Text(
                        ' · ${bidCount}x',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 9,
                          fontWeight: FontWeight.w500)),
                    ]),
              ]))),

        // Green checkmark dot in top-right corner when bid placed
        if (hasBid)
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF34C759).withOpacity(0.4),
                    blurRadius: 4),
                ]),
              child: Icon(
                CupertinoIcons.checkmark,
                size: 8,
                color: Colors.white))),
      ]);
  }

  // Show auction modal with bidding interface
  void _showAuctionModal(Map<String, dynamic> auction, LatLng location) async {
    print('🎯 _showAuctionModal called!');
    print(
      '🚗 Current _driverVehicles count BEFORE load: ${_driverVehicles.length}');

    // Load driver vehicles first to check for matching vehicles
    await _loadDriverVehicles();

    print(
      '🚗 Current _driverVehicles count AFTER load: ${_driverVehicles.length}');

    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final isLight = appSettings.isLightMode(context);

    // Parse order data
    final orderTotal = _toDouble(auction['order_total']);
    final shippingCost = _toDouble(auction['shipping_cost']);

    // Parse delivery address
    Map<String, dynamic>? deliveryAddress;
    try {
      final raw = auction['delivery_address'];
      if (raw is String) {
        deliveryAddress = json.decode(raw);
      } else if (raw is Map) {
        deliveryAddress = Map<String, dynamic>.from(raw);
      }
    } catch (e) {
      print('Error parsing delivery address: $e');
    }

    // Parse cart items
    List<dynamic> cartItems = [];
    try {
      final raw = auction['order_cart'];
      if (raw is String) {
        cartItems = json.decode(raw);
      } else if (raw is List) {
        cartItems = raw;
      }
    } catch (e) {
      print('Error parsing cart: $e');
    }

    // Get pickup address from auction
    final pickupAddress = auction['pickup_address'] ??
      (AppLocalizations.of(context)?.pickupAddressNotAvailable ?? AppLocalizations.of(context)!.tr(''));

    // Calculate distance between pickup and delivery
    double pickupToDeliveryKm = 0.0;
    final pickupLat = _toDouble(auction['pickup_lat']);
    final pickupLng = _toDouble(auction['pickup_lng']);
    // Try to get delivery coordinates from auction or from parsed delivery address
    double deliveryLat = _toDouble(auction['delivery_lat']);
    double deliveryLng = _toDouble(auction['delivery_lng']);

    // If delivery coordinates not in auction directly, try from deliveryAddress
    if ((deliveryLat == 0 || deliveryLng == 0) && deliveryAddress != null) {
      deliveryLat = _toDouble(
        deliveryAddress['lat'] ?? deliveryAddress['latitude']);
      deliveryLng = _toDouble(
        deliveryAddress['lng'] ?? deliveryAddress['longitude']);

      // If still no coordinates, geocode from address components
      if (deliveryLat == 0 || deliveryLng == 0) {
        final street = deliveryAddress['street'] ?? AppLocalizations.of(context)!.tr('');
        final houseNumber = deliveryAddress['house_number'] ?? AppLocalizations.of(context)!.tr('');
        final zipCode = deliveryAddress['zip_code'] ?? AppLocalizations.of(context)!.tr('');
        final city = deliveryAddress['city'] ?? AppLocalizations.of(context)!.tr('');
        final country = deliveryAddress['country'] ?? AppLocalizations.of(context)!.tr('Germany');
        final addressString = '$street $houseNumber, $zipCode $city, $country';

        print('🔍 Geocoding delivery address: $addressString');
        try {
          final encodedAddress = Uri.encodeComponent(addressString);
          final geocodeUrl =
              'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=1';
          final response = await http.get(
            Uri.parse(geocodeUrl),
            headers: {'User-Agent': 'CultiooApp/1.0'});

          if (response.statusCode == 200) {
            final results = json.decode(response.body) as List;
            if (results.isNotEmpty) {
              final result = results[0];
              deliveryLat = double.parse(result['lat']);
              deliveryLng = double.parse(result['lon']);
              print('✅ Geocoded delivery: $deliveryLat, $deliveryLng');
            }
          }
        } catch (e) {
          print('⚠️ Geocoding failed: $e');
        }
      }
    }

    if (pickupLat != 0 &&
        pickupLng != 0 &&
        deliveryLat != 0 &&
        deliveryLng != 0) {
      // Use OSRM to calculate real driving distance
      try {
        final osrmUrl =
            'https://router.project-osrm.org/route/v1/driving/$pickupLng,$pickupLat;$deliveryLng,$deliveryLat?overview=false';
        print('🛣️ Fetching route distance from OSRM...');
        final response = await http.get(
          Uri.parse(osrmUrl),
          headers: {'User-Agent': 'CultiooApp/1.0'});

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['code'] == 'Ok' &&
              data['routes'] != null &&
              data['routes'].isNotEmpty) {
            // Distance is returned in meters, convert to km
            final distanceMeters = data['routes'][0]['distance'] as num;
            pickupToDeliveryKm = distanceMeters / 1000.0;
            print(
              '✅ OSRM route distance: ${pickupToDeliveryKm.toStringAsFixed(1)} km');
          }
        }
      } catch (e) {
        print('⚠️ OSRM routing failed, falling back to straight line: $e');
        // Fallback to straight line distance
        final Distance distance = const Distance();
        pickupToDeliveryKm = distance.as(
          LengthUnit.Kilometer,
          LatLng(pickupLat, pickupLng),
          LatLng(deliveryLat, deliveryLng));
      }
      print('📏 Final distance: ${pickupToDeliveryKm.toStringAsFixed(1)} km');
    }

    // Get quantity and unit directly (stored as real units, not cents)
    final quantity = _toDouble(auction['total_quantity']);
    final quantityUnit = auction['quantity_unit'] ?? AppLocalizations.of(context)!.tr('t');

    // Check cleaning certificate
    final requiresCleaning =
        auction['requires_cleaning_certificate'] == 1 ||
        auction['requires_cleaning_certificate'] == true;

    // Timer control variables (shared between builder and whenComplete)
    Timer? countdownTimer;
    bool isModalMounted = true;

    TradeRepublicBottomSheet.show(
      context: context,
      child: StatefulBuilder(
        builder: (builderContext, setModalState) {
            // Start countdown timer if not already running
            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
              // Check if modal is still mounted before calling setState
              if (isModalMounted) {
                setModalState(() {});
              }
            });

            // Get current remaining time
            final currentRemainingTime = _getAuctionRemainingTime(auction);
            // Check if this is a real auction (has end_time) vs just an order displayed as auction
            final isRealAuction =
                auction['end_time'] != null &&
                auction['end_time'].toString().isNotEmpty;
            final currentIsExpired =
                isRealAuction &&
                (currentRemainingTime == null ||
                    currentRemainingTime == Duration.zero);

            // Cancel timer if expired (only for real auctions)
            if (currentIsExpired) {
              countdownTimer?.cancel();
              isModalMounted = false;
            }

            return SizedBox(
              height: MediaQuery.of(builderContext).size.height,
              child: TradeRepublicTap(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: Column(
                  children: [
                    // Trade Republic Handle bar
                    DragHandle(),
                    // Title Section - Ultra minimalist
                    Padding(
                      padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
                      child: Column(
                        children: [
                          // Live indicator + Title row
                          if (isRealAuction && !currentIsExpired)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.withValues(alpha: 0.5),
                                        blurRadius: 8,
                                        spreadRadius: 2),
                                    ])),
                                SizedBox(width: 10),
                                Text(
                                  AppLocalizations.of(context)?.live ?? AppLocalizations.of(context)!.tr('LIVE'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red,
                                    fontFamily: 'Poppins',
                                    letterSpacing: 2)),
                              ]),
                          if (isRealAuction && !currentIsExpired)
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          Text(
                            currentIsExpired
                                ? (AppLocalizations.of(context)?.ended ?? AppLocalizations.of(context)!.tr('Ended'))
                                : (isRealAuction ? 'Auction' : AppLocalizations.of(context)?.order ?? AppLocalizations.of(context)!.tr('Order')),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                              fontFamily: 'Poppins',
                              letterSpacing: -0.5)),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          // Countdown - minimal pill (only show for real auctions)
                          if (isRealAuction)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12),
                              decoration: BoxDecoration(
                                color: currentIsExpired
                                    ? Colors.red.withValues(alpha: 0.1)
                                    : (isLight
                                          ? const Color(0xFFF2F2F7)
                                          : const Color(0xFF1C1C1E)),
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                              child: Text(
                                currentIsExpired
                                    ? (AppLocalizations.of(context)?.expired ?? AppLocalizations.of(context)!.tr('Expired'))
                                    : _formatCountdown(currentRemainingTime!),
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                  fontWeight: FontWeight.w600,
                                  color: currentIsExpired
                                      ? Colors.red
                                      : (isLight ? Colors.black : Colors.white),
                                  fontFamily: 'Poppins',
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ]))),
                          if (isRealAuction) SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          if ((auction['total_bids'] ?? 0) > 0)
                            Container(
                              margin: EdgeInsets.only(top: 8),
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                              child: Text(
                                '${auction['total_bids']} bids',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.5),
                                  fontFamily: 'Poppins'))),
                        ])),

                    // Key Info Cards - 2×2 Trade Republic grid
                    Padding(
                      padding: EdgeInsets.fromLTRB(0, 20, 0, 0),
                      child: Container(
                        padding: DesktopAppWrapper.getPagePadding(),
                        decoration: BoxDecoration(
                          color: isLight ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                        child: Column(
                          children: [
                            // Row 1: Quantity + Price
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context)?.qty ?? 'Qty',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.4))),
                                      SizedBox(height: 4),
                                      Text(
                                        '${_formatQuantity(quantity)} $quantityUnit',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: isLight ? Colors.black : Colors.white)),
                                    ])),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context)?.valueLabel ?? 'Value',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.4))),
                                      SizedBox(height: 4),
                                      Text(
                                        appSettings.formatCurrency(orderTotal),
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF2E7D32))),
                                    ])),
                              ]),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            Divider(
                              height: 1,
                              color: isLight ? const Color(0xFFE0E0E0) : const Color(0xFF3A3A3A)),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            // Row 2: Distance + Cleaning
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context)?.dist ?? 'Distance',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.4))),
                                      SizedBox(height: 4),
                                      Text(
                                        pickupToDeliveryKm > 0
                                            ? appSettings.formatDistance(pickupToDeliveryKm)
                                            : '--',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: isLight ? Colors.black : Colors.white)),
                                    ])),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context)?.cleaning ?? 'Cleaning',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.4))),
                                      SizedBox(height: 4),
                                      Text(
                                        requiresCleaning
                                            ? (AppLocalizations.of(context)?.yes ?? 'Required')
                                            : 'No',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: requiresCleaning
                                              ? Colors.orange[700]!
                                              : (isLight ? Colors.black : Colors.white))),
                                    ])),
                              ]),
                          ]))),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          // Required Vehicle Row with matching vehicles list
                          Builder(
                            builder: (context) {
                              final requiredWagonType =
                                  _resolvedWagonTypeForAuction(auction);
                              final hasMatchingVehicle = _hasMatchingVehicle(
                                requiredWagonType);

                              // Get all matching vehicles
                              final matchingVehicles = _driverVehicles
                                  .where(
                                    (v) => _vehicleMatchesWagonType(
                                      v,
                                      requiredWagonType))
                                  .toList();

                              return Column(
                                children: [
                                  _buildAuctionDetailRow(
                                    isLight: isLight,
                                    icon: _getWagonTypeIconData(
                                      requiredWagonType),
                                    label: AppLocalizations.of(context)?.requiredVehicle ?? AppLocalizations.of(context)!.tr('Required Vehicle'),
                                    value: _getWagonTypeName(requiredWagonType)),
                                  // Show matching vehicle indicator
                                  hasMatchingVehicle
                                      ? Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(
                                                0.1),
                                              borderRadius:
                                                  BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                            child: Text(
                                              '✓ Match',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.green[600])))
                                        : Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(
                                                0.1),
                                              borderRadius:
                                                  BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                            child: Text(
                                              AppLocalizations.of(context)?.noMatch ?? AppLocalizations.of(context)!.tr('No Match'),
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.orange[700]))),
                                  // Show matching vehicles if any
                                  if (matchingVehicles.isNotEmpty) ...[
                                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                    Container(
                                      width: double.infinity,
                                      margin: EdgeInsets.only(left: 58),
                                      padding: DesktopAppWrapper.getPagePadding(),
                                      decoration: BoxDecoration(
                                        color: isLight
                                            ? Colors.white
                                            : const Color(0xFF111111),
                                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                CupertinoIcons
                                                    .checkmark_circle_fill,
                                                size: 18,
                                                color: Colors.green[600]),
                                              SizedBox(width: 8),
                                              Text(
                                                AppLocalizations.of(context)?.yourMatchingVehicles ?? AppLocalizations.of(context)!.tr('Your matching vehicles'),
                                                style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: isLight
                                                      ? Colors.black87
                                                      : Colors.white,
                                                  letterSpacing: -0.2)),
                                            ]),
                                          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                          ...matchingVehicles.map(
                                            (vehicle) => Padding(
                                              padding: EdgeInsets.only(
                                                bottom: 8),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 36,
                                                    height: 36,
                                                    decoration: BoxDecoration(
                                                      color: isLight
                                                          ? Colors.white
                                                          : Colors.black,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10)),
                                                    child: Icon(
                                                      _getVehicleIcon(vehicle),
                                                      size: 18,
                                                      color: isLight
                                                          ? Colors.black87
                                                          : Colors.white)),
                                                  SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          '${vehicle['vehicle_make'] ?? AppLocalizations.of(context)!.tr('')} ${vehicle['vehicle_model'] ?? AppLocalizations.of(context)!.tr('')}'
                                                              .trim(),
                                                          style: TextStyle(
                                                            fontFamily:
                                                                'Poppins',
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: isLight
                                                                ? Colors.black
                                                                : Colors.white)),
                                                        if (vehicle['license_plate'] !=
                                                            null)
                                                          Text(
                                                            vehicle['license_plate'],
                                                            style: TextStyle(
                                                              fontFamily:
                                                                  'Poppins',
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color: isLight
                                                                  ? Colors
                                                                        .grey[500]
                                                                  : Colors
                                                                        .grey[500])),
                                                      ])),
                                                ]))),
                                        ])),
                                  ],
                                  // Show message if no matching vehicles
                                  if (!hasMatchingVehicle &&
                                      _driverVehicles.isNotEmpty) ...[
                                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                    Container(
                                      width: double.infinity,
                                      margin: EdgeInsets.only(left: 58),
                                      padding: DesktopAppWrapper.getPagePadding(),
                                      decoration: BoxDecoration(
                                        color: isLight
                                            ? Colors.white
                                            : const Color(0xFF111111),
                                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                      child: Row(
                                        children: [
                                          Icon(
                                            CupertinoIcons
                                                .exclamationmark_triangle,
                                            size: 18,
                                            color: Colors.orange[600]),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              '${AppLocalizations.of(context)?.noneOfYourVehiclesMatch ?? AppLocalizations.of(context)!.tr('None of your vehicles match')} (${_driverVehicles.length})',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                                fontWeight: FontWeight.w600,
                                                color: isLight
                                                    ? Colors.black87
                                                    : Colors.white))),
                                        ])),
                                  ],
                                ]);
                            }),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                          // Pickup Address Row
                          _buildAuctionDetailRow(
                            isLight: isLight,
                            icon: CupertinoIcons.building_2_fill,
                            label: AppLocalizations.of(context)?.pickup ?? AppLocalizations.of(context)!.tr('Pickup'),
                            value: pickupAddress),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                          // Delivery Address Row
                          if (deliveryAddress != null)
                            _buildAuctionDetailRow(
                              isLight: isLight,
                              icon: CupertinoIcons.location,
                              label: AppLocalizations.of(context)?.delivery ?? AppLocalizations.of(context)!.tr('Delivery'),
                              value:
                                  deliveryAddress['address'] ??
                                  '${deliveryAddress['street'] ?? AppLocalizations.of(context)!.tr('')} ${deliveryAddress['house_number'] ?? AppLocalizations.of(context)!.tr('')}, ${deliveryAddress['zip_code'] ?? AppLocalizations.of(context)!.tr('')} ${deliveryAddress['city'] ?? AppLocalizations.of(context)!.tr('')}'
                                      .trim()
                                      .replaceAll(RegExp(r'\s+'), ' ')),
                          if (deliveryAddress != null)
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                          // Items Row
                          if (cartItems.isNotEmpty)
                            _buildAuctionDetailRow(
                              isLight: isLight,
                              icon: CupertinoIcons.cube_box,
                              label: AppLocalizations.of(context)?.items ?? AppLocalizations.of(context)!.tr('Items'),
                              value: cartItems.length == 1
                                  ? '${cartItems[0]['product_name'] ?? cartItems[0]['name'] ?? (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr(''))}'
                                  : '${cartItems.length} items'),
                          if (cartItems.isNotEmpty) SizedBox(height: 20),

                          // Your Bid Section - if already placed
                          if (auction['my_bid'] != null)
                            Builder(
                              builder: (context) {
                                final myBid =
                                    auction['my_bid'] as Map<String, dynamic>;
                                final bidAmount = _toDouble(
                                  myBid['bid_amount']);
                                final cleaningPrice = _toDouble(
                                  myBid['cleaning_certificate_price']);
                                final bidStatus = myBid['status'] ?? AppLocalizations.of(context)!.tr('pending');
                                final createdAt = myBid['created_at'];
                                final sectionName = myBid['section_name'];
                                final vehicleId = myBid['vehicle_id'];
                                final estimatedTime =
                                    myBid['estimated_delivery_time'];

                                // Format the date
                                String formattedDate = '';
                                if (createdAt != null) {
                                  try {
                                    final date = DateTime.parse(
                                      createdAt.toString());
                                    final appSettings =
                                        Provider.of<AppSettings>(
                                          context,
                                          listen: false);
                                    formattedDate =
                                        '${appSettings.formatDate(date)} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                                  } catch (e) {
                                    formattedDate = createdAt.toString();
                                  }
                                }

                                // Find vehicle info if available
                                Map<String, dynamic>? selectedVehicle;
                                if (vehicleId != null) {
                                  selectedVehicle = _driverVehicles.firstWhere(
                                    (v) => v['id'] == vehicleId,
                                    orElse: () => {});
                                }

                                return Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: isLight
                                        ? Colors.white
                                        : const Color(0xFF111111),
                                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Header
                                      Container(
                                        width: double.infinity,
                                        padding: EdgeInsets.all(18),
                                        decoration: BoxDecoration(
                                          color: isLight
                                              ? Colors.black
                                              : Colors.white,
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(20),
                                            topRight: Radius.circular(20))),
                                        child: Row(
                                          children: [
                                            Icon(
                                              CupertinoIcons
                                                  .checkmark_circle_fill,
                                              color: isLight
                                                  ? Colors.white
                                                  : Colors.black,
                                              size: 26),
                                            SizedBox(width: 14),
                                            Text(
                                              AppLocalizations.of(context)?.yourBid ?? AppLocalizations.of(context)!.tr('Your Bid'),
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                                                fontWeight: FontWeight.w700,
                                                color: isLight
                                                    ? Colors.white
                                                    : Colors.black)),
                                            const Spacer(),
                                            Container(
                                              padding:
                                                  EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6),
                                              decoration: BoxDecoration(
                                                color:
                                                    (isLight
                                                            ? Colors.white
                                                            : Colors.black)
                                                        .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                              child: Text(
                                                bidStatus
                                                    .toString()
                                                    .toUpperCase(),
                                                style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                  color: isLight
                                                      ? Colors.white
                                                      : Colors.black))),
                                          ])),
                                      // Bid Details - List style like Select Section
                                      Padding(
                                        padding: EdgeInsets.all(18),
                                        child: Column(
                                          children: [
                                            // Bid Amount Row
                                            _buildBidDetailRow(
                                              isLight: isLight,
                                              icon: CupertinoIcons
                                                  .money_dollar_circle,
                                              label: AppLocalizations.of(context)?.bidAmount ?? AppLocalizations.of(context)!.tr('Bid Amount'),
                                              value: appSettings.formatCurrency(
                                                bidAmount)),
                                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                            // Cleaning Certificate Row (if applicable)
                                            if (cleaningPrice > 0) ...[
                                              _buildBidDetailRow(
                                                isLight: isLight,
                                                icon: CupertinoIcons
                                                    .checkmark_shield,
                                                label: AppLocalizations.of(context)?.cleaningCertificate ?? AppLocalizations.of(context)!.tr('Cleaning Certificate'),
                                                value: appSettings
                                                    .formatCurrency(
                                                      cleaningPrice)),
                                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                            ],
                                            // Section Row (if applicable)
                                            if (sectionName != null) ...[
                                              _buildBidDetailRow(
                                                isLight: isLight,
                                                icon: CupertinoIcons
                                                    .square_grid_2x2,
                                                label: AppLocalizations.of(context)?.section ?? AppLocalizations.of(context)!.tr('Section'),
                                                value: sectionName.toString()),
                                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                            ],
                                            // Vehicle Row (if applicable)
                                            if (selectedVehicle != null &&
                                                selectedVehicle.isNotEmpty) ...[
                                              _buildBidDetailRow(
                                                isLight: isLight,
                                                icon: CupertinoIcons.cube_box,
                                                label: AppLocalizations.of(context)?.vehicle ?? AppLocalizations.of(context)!.tr('Vehicle'),
                                                value:
                                                    '${selectedVehicle['vehicle_make'] ?? AppLocalizations.of(context)!.tr('')} ${selectedVehicle['vehicle_model'] ?? AppLocalizations.of(context)!.tr('')}'
                                                        .trim()),
                                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                            ],
                                            // Estimated Time Row (if applicable)
                                            if (estimatedTime != null) ...[
                                              _buildBidDetailRow(
                                                isLight: isLight,
                                                icon: CupertinoIcons.clock,
                                                label: AppLocalizations.of(context)?.estDelivery ?? AppLocalizations.of(context)!.tr('Est. Delivery'),
                                                value: estimatedTime.toString()),
                                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                            ],
                                            // Submission Date Row
                                            if (formattedDate.isNotEmpty)
                                              _buildBidDetailRow(
                                                isLight: isLight,
                                                icon: CupertinoIcons.clock,
                                                label: AppLocalizations.of(context)?.submitted ?? AppLocalizations.of(context)!.tr('Submitted'),
                                                value: formattedDate),
                                          ])),
                                    ]));
                              }),

                          if (auction['my_bid'] != null)
                            SizedBox(height: 20),

                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                          // Hide route action once driver already has a bid on this auction.
                          if (auction['my_bid'] == null) ...[
                            // Show Route button - Trade Republic style
                            TradeRepublicButton(
                              label: AppLocalizations.of(context)?.showRoute ?? AppLocalizations.of(context)!.tr('Show Route'),
                              icon: Icon(CupertinoIcons.map, size: 24),
                              onPressed: () {
                                Navigator.pop(context);
                                _showRouteForAuction(auction, location);
                              }),
                            SizedBox(height: 40),
                          ],
                        ])),
                  ])));
          }));
    
    // Note: Timer cleanup happens automatically when modal is dismissed
    // The isModalMounted flag and timer will be garbage collected
  }

  // Submit a bid for an auction
  Future<bool> _submitBid({
    required int auctionId,
    required double bidAmount,
    String? estimatedDeliveryTime,
    String? vehicleType,
    String? message,
    double? cleaningCertificatePrice,
    int? vehicleId,
    int? sectionIndex,
    String? sectionName,
    String? priceMode,
  }) async {
    try {
      print(
        '💰 Submitting bid for auction #$auctionId: \$$bidAmount (${priceMode ?? AppLocalizations.of(context)!.tr('total')})');
      if (cleaningCertificatePrice != null && cleaningCertificatePrice > 0) {
        print('   + Cleaning certificate: \$$cleaningCertificatePrice');
      }

      // Get auth token and user info from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      // user_id is stored as String, convert to int if needed
      final userIdStr = prefs.getString('user_id');
      final driverId = userIdStr != null ? int.tryParse(userIdStr) ?? 1 : 1;
      final driverUsername = prefs.getString('username') ?? AppLocalizations.of(context)!.tr('driver');

      print(
        '🔑 Token: ${token != null ? "${token.substring(0, 20)}..." : "NULL"}');
      print('👤 Driver ID: $driverId, Username: $driverUsername');
      print('🌐 URL: ${ApiConfig.getAuctionBidUrl(auctionId)}');

      final response = await http.post(
        Uri.parse(ApiConfig.getAuctionBidUrl(auctionId)),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'driver_id': driverId,
          'driver_username': driverUsername,
          'bid_amount': bidAmount,
          'price_mode': priceMode ?? AppLocalizations.of(context)!.tr('total'),
          'estimated_delivery_time': estimatedDeliveryTime,
          'vehicle_type': vehicleType ?? AppLocalizations.of(context)!.tr('truck'),
          'message': message,
          'cleaning_certificate_price': cleaningCertificatePrice,
          'vehicle_id': vehicleId,
          'section_index': sectionIndex,
          'section_name': sectionName,
        }));

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Bid submitted successfully!');
          // Refresh auctions to update bid count
          _loadAuctions();
          return true;
        }
      }

      print('❌ Failed to submit bid: ${response.statusCode}');
      print('❌ Response: ${response.body}');
      return false;
    } catch (e) {
      print('💥 Error submitting bid: $e');
      return false;
    }
  }

  // Build the bidding section widget for auctions
  Widget _buildBiddingSection(Map<String, dynamic> auction, bool isLight) {
    final bidController = TextEditingController();
    final messageController = TextEditingController();

    return StatefulBuilder(
      builder: (context, setModalState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current lowest/highest bid info
            if (auction['lowest_bid'] != null) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.arrow_down,
                      color: Colors.white70,
                      size: 18),
                    SizedBox(width: 8),
                    Text(
                      '${AppLocalizations.of(context)?.lowestBid ?? AppLocalizations.of(context)!.tr('Lowest bid')}: \$${auction['lowest_bid']}',
                      style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                  ])),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            ],

            // Bid amount input
            TradeRepublicTextField(
              controller: bidController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true),
              textInputAction: TextInputAction.done,
              inputFormatters: [_CentsInputFormatter()],
              style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                fontWeight: FontWeight.w700,
                color: Colors.white),
              hintText: AppLocalizations.of(context)?.enterYourBid ?? 'Enter your bid (\$)',
              onChanged: (_) {}, // formatter keeps value in sync
              prefixIcon: Icon(
                CupertinoIcons.money_dollar_circle,
                color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.15)),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Optional message input
            TradeRepublicTextField(
              controller: messageController,
              maxLines: 2,
              style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(), color: Colors.white),
              hintText: AppLocalizations.of(context)?.addAMessageOptional ?? AppLocalizations.of(context)!.tr('Add a message (optional)'),
              prefixIcon: Icon(
                CupertinoIcons.chat_bubble,
                color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1)),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

            // Submit bid button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.placeBid ?? AppLocalizations.of(context)!.tr('Place Bid'),
              icon: Icon(CupertinoIcons.hammer, size: 20),
              onPressed: () async {
                final bidText = bidController.text.trim();
                if (bidText.isEmpty) {
                  TopNotification.error(context, AppLocalizations.of(context)?.pleaseEnterABidAmount ?? AppLocalizations.of(context)!.tr('Please enter a bid amount'));
                  return;
                }

                final bidAmount = double.tryParse(bidText.replaceAll(',', ''));
                if (bidAmount == null || bidAmount <= 0) {
                  TopNotification.error(
                    context,
                    AppLocalizations.of(context)?.pleaseEnterValidBidAmount ?? AppLocalizations.of(context)!.tr('Please enter a valid bid amount'));
                  return;
                }

                HapticFeedback.mediumImpact();

                // Show loading state
                setModalState(() {});

                final success = await _submitBid(
                  auctionId: auction['id'],
                  bidAmount: bidAmount,
                  message: messageController.text.trim().isNotEmpty
                      ? messageController.text.trim()
                      : null);

                if (success) {
                  if (context.mounted) Navigator.pop(context);
                  // Clear route view so the map doesn't stay in the black/route state
                  _onClearRoute();
                  if (context.mounted) {
                    final appSettings = Provider.of<AppSettings>(context, listen: false);
                    TopNotification.success(
                      context,
                      'Bid of ${appSettings.formatCurrency(bidAmount)} submitted!');
                  }
                } else {
                  if (context.mounted) {
                    TopNotification.error(
                    context,
                    AppLocalizations.of(context)?.failedToSubmitBid ?? AppLocalizations.of(context)!.tr('Failed to submit bid. Please try again.'));
                  }
                }
              }),
          ]);
      });
  }

  // Performance caches
  final Map<int, LatLng?> _productCoordinatesCache = {};
  final Set<int> _fetchingProducts =
      {}; // Track which products are being fetched

  // Enrich orders with coordinates in background (non-blocking)
  Future<void> _enrichOrdersInBackground(
    List<Map<String, dynamic>> orderList) async {
    print('🔄 Starting background enrichment for ${orderList.length} orders');

    // Collect unique product IDs to fetch
    Set<int> productIds = {};
    for (var order in orderList) {
      final items = order['items'] as List<dynamic>?;
      if (items != null && items.isNotEmpty) {
        final firstItem = items[0] as Map<String, dynamic>;
        final productIdRaw = firstItem['id'];
        if (productIdRaw != null) {
          int? productId;
          if (productIdRaw is String) {
            productId = int.tryParse(productIdRaw);
          } else if (productIdRaw is int) {
            productId = productIdRaw;
          }

          if (productId != null &&
              productId > 0 &&
              !_productCoordinatesCache.containsKey(productId) &&
              !_fetchingProducts.contains(productId)) {
            productIds.add(productId);
          }
        }
      }
    }

    print(
      '📦 Need to fetch coordinates for ${productIds.length} unique products: $productIds');

    // Fetch coordinates for unique products only
    for (int productId in productIds) {
      if (!mounted) break;

      try {
        _fetchingProducts.add(productId);
        await _fetchProductCoordinatesAsync(productId);

        // Small delay to prevent API spam
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        print('⚠️ Error fetching product $productId: $e');
        _productCoordinatesCache[productId] = null; // Cache the failure
      } finally {
        _fetchingProducts.remove(productId);
      }
    }

    print(
      '✅ Background enrichment completed - cached ${_productCoordinatesCache.length} products');

    if (mounted) {
      setState(() {
        // Final update after all enrichments
      });
    }
  }

  // MapBox 3D Map created callback
  void _onMapboxCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _isMapReady = true;
    print('🗺️ MapBox 3D Map created successfully with pitch: 45°');

    // 3D buildings are automatically enabled in MapboxStyles.STANDARD
    print('✅ 3D Buildings enabled via STANDARD style');
  }

  // Get current GPS location
  Future<void> _getCurrentLocation() async {
    try {
      print('Checking if location service is enabled...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        print('📍 No location will be shown - services disabled');
        if (mounted) {
          setState(() {
            currentLocation = null;
          });
        }
        return;
      }
      print('Location service is enabled');

      print('Checking location permissions...');
      LocationPermission permission = await Geolocator.checkPermission();
      print('Current permission status: $permission');

      if (permission == LocationPermission.denied) {
        print('Location permission denied, requesting...');
        permission = await Geolocator.requestPermission();
        print('Permission after request: $permission');
        if (permission == LocationPermission.denied) {
          print('Location permission still denied after request');
          print('📍 No location will be shown - permission denied');
          if (mounted) {
            setState(() {
              currentLocation = null;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permission denied forever');
        print('📍 No location will be shown - permission permanently denied');
        if (mounted) {
          setState(() {
            currentLocation = null;
          });
        }
        return;
      }

      // Try to request always permission if we only have whileInUse
      if (permission == LocationPermission.whileInUse) {
        print('Have whileInUse permission, trying to get always permission...');
        final alwaysPermission = await Geolocator.requestPermission();
        if (alwaysPermission == LocationPermission.always) {
          print('Successfully got always permission');
          permission = alwaysPermission;
        } else {
          print('Still have whileInUse permission, continuing...');
        }
      }

      print('Getting current position...');
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15), // Increased timeout
      );
      print('Got position: ${position.latitude}, ${position.longitude}');

      if (!mounted) return;

      // ALWAYS use the real GPS position - no fallback to Krefeld
      // Even if outside Europe or in simulator, use actual coordinates for accurate routing
      LatLng locationToUse = LatLng(position.latitude, position.longitude);

      print(
        '✅ Using GPS location: ${locationToUse.latitude}, ${locationToUse.longitude}');
      print('   Accuracy: ${position.accuracy}m');
      print('   Speed: ${position.speed}m/s');

      if (mounted) {
        setState(() {
          currentLocation = locationToUse;
        });
        print('📍 Current location updated successfully');

        // Auf iOS: Kamera zur aktuellen Position bewegen
        if (Platform.isIOS && _appleMapController != null && _isMapReady) {
          try {
            print('🍎 Moving Apple Maps camera to current location');
            _appleMapController!.animateCamera(
              apple.CameraUpdate.newCameraPosition(
                apple.CameraPosition(
                  target: apple.LatLng(
                    locationToUse.latitude,
                    locationToUse.longitude),
                  zoom: _zoomLevel)));
          } catch (e) {
            print('⚠️ Error moving Apple Maps camera: $e');
          }
        } else if (!Platform.isIOS && _isMapReady) {
          // Auf anderen Plattformen: FlutterMap Controller nutzen
          try {
            print('🗺️ Moving FlutterMap camera to current location');
            _mapController.move(locationToUse, _zoomLevel);
          } catch (e) {
            print('⚠️ Error moving FlutterMap camera: $e');
          }
        }
      }
    } catch (e) {
      print('Error getting location: $e');
      print('📍 No location will be shown - GPS error');
      if (mounted) {
        setState(() {
          currentLocation = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);

    // Force complete map rebuild when theme changes
    if (_lastThemeWasLight != isLight) {
      _lastThemeWasLight = isLight;
      // Force a complete state refresh after the current build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            // This will trigger a complete rebuild with new theme
          });
        }
      });
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: _buildUnifiedView(isLight));
  }

  Widget _buildUnifiedView(bool isLight) {
    // Calculate map height based on bottom sheet - smooth transition
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final bottomPadding = mediaQuery.padding.bottom;
    final topPadding = mediaQuery.padding.top;

    // Clamp bottom sheet height to valid range to prevent overflow
    final maxSheetHeight = screenHeight * 0.75; // Never exceed 75% of screen
    final minSheetHeight = bottomPadding + 130.0; // Minimum collapsed height
    final clampedSheetHeight = _bottomSheetHeight.clamp(minSheetHeight, maxSheetHeight);

    // When sheet is expanded (650), map should shrink to leave space
    // When sheet is collapsed (170), map is full screen
    // Map height = screenHeight - bottomSheetHeight + overlap (for smooth look)
    final mapHeight = (screenHeight - clampedSheetHeight + 40).clamp(100.0, screenHeight);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Animated Map Container - shrinks when bottom sheet expands
        // NO ClipRRect to avoid blocking touch events!
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          top: 0,
          left: 0,
          right: 0,
          height: _isBottomSheetExpanded ? mapHeight : screenHeight,
          child: _buildFullScreenMapBase(isLight)),

        // Floating UI elements over the map (route info + swipe) - with hit test behavior
        IgnorePointer(
          ignoring:
              !_showRouteInfo ||
              _routePoints.isEmpty, // Only accept touches when route is shown
          child: _buildFloatingUI(isLight)),

        // Draggable Bottom Sheet - combines Switch and Buttons
        if (!_showRouteInfo || _routePoints.isEmpty)
          _buildDraggableBottomSheet(isLight),

        // Floating action buttons – right side, always visible
        Positioned(
          right: 16,
          bottom: _bottomSheetHeight + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Zoom In
              TradeRepublicTap(
                onTap: () => _zoomMap(1.0),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4)),
                    ]),
                  child: Icon(
                    CupertinoIcons.plus,
                    size: 22,
                    color: isLight ? Colors.black87 : Colors.white))),
              SizedBox(height: 10),
              // Zoom Out
              TradeRepublicTap(
                onTap: () => _zoomMap(-1.0),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4)),
                    ]),
                  child: Icon(
                    CupertinoIcons.minus,
                    size: 22,
                    color: isLight ? Colors.black87 : Colors.white))),
              SizedBox(height: 10),
              // Location
              TradeRepublicTap(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showCurrentLocation();
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4)),
                    ]),
                  child: Icon(
                    CupertinoIcons.location_fill,
                    size: 22,
                    color: const Color(0xFF007AFF)))),
              SizedBox(height: 10),
              // Settings
              TradeRepublicTap(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showSettingsModal();
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4)),
                    ]),
                  child: Icon(
                    CupertinoIcons.settings,
                    size: 22,
                    color: isLight ? Colors.black87 : Colors.white))),
            ])),
      ]);
  }

  // Full screen map base - Platform specific: Apple Maps on iOS, Esri on others
  Widget _buildFullScreenMapBase(bool isLight) {
    final center = currentLocation ?? const LatLng(51.3571486, 6.638026);

    // Use Apple Maps on iOS
    if (Platform.isIOS) {
      // apple_maps_flutter often does not refresh annotations when only the
      // `annotations` set changes after the first frame. Key the map by the
      // loaded auction ids so the first successful /api/auctions/active fetch
      // forces a rebuild with markers (was: 0 auctions on cold start).
      final mergedForKey = _mergedAuctions();
      final appleAuctionKey = mergedForKey.isEmpty
          ? 'none'
          : mergedForKey.map((a) => '${a['id']}').join('_');
      final appleMapKey = '${appleAuctionKey}_o${_filteredOrders.length}_i${_appleIconCache.length}';

      return apple.AppleMap(
        key: ValueKey<String>('apple_map_$appleMapKey'),
        onMapCreated: (apple.AppleMapController controller) {
          _appleMapController = controller;
          _isMapReady = true;
          print('🍎 Apple Maps created successfully');
          print('🍎 Controller type: ${controller.runtimeType}');
        },
        initialCameraPosition: apple.CameraPosition(
          target: apple.LatLng(center.latitude, center.longitude),
          zoom: _zoomLevel),
        mapType: isLight ? apple.MapType.standard : apple.MapType.standard,
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        compassEnabled: true,
        trafficEnabled: false,
        // IMPORTANT: All gestures explicitly enabled
        zoomGesturesEnabled: true,
        scrollGesturesEnabled: true,
        rotateGesturesEnabled: true,
        // Event handlers for debugging
        onTap: (apple.LatLng position) {
          print(
            '🍎 Map tapped at: ${position.latitude}, ${position.longitude}');
          setState(() {
            selectedOrderId = null;
          });
        },
        onCameraMove: (apple.CameraPosition position) {
          _appleMapZoomLevel = position.zoom;
        },
        polylines: _buildAppleMapsPolylines(),
        annotations: _buildAppleMapsAnnotations(isLight));
    }

    // Use native MapBox 3D if enabled (non-iOS)
    if (_use3DMap) {
      return Stack(
        children: [
          mapbox.MapWidget(
            key: ValueKey('mapbox_3d_${isLight ? 'light' : 'dark'}'),
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(center.longitude, center.latitude)),
              zoom: _zoomLevel,
              pitch: 45.0, // 3D viewing angle
              bearing: 0.0),
            styleUri: isLight
                ? mapbox.MapboxStyles.STANDARD
                : mapbox.MapboxStyles.DARK,
            textureView: true,
            onMapCreated: _onMapboxCreated,
            onTapListener: (mapbox.MapContentGestureContext context) {
              setState(() {
                selectedOrderId = null;
              });
            }),
        ]);
    }

    // Use free Esri/OpenStreetMap for other platforms
    return FlutterMap(
      key: ValueKey('fullscreen_map_${isLight ? 'light' : 'dark'}'),
      mapController: _mapController,
      options: MapOptions(
        initialCenter: currentLocation ?? const LatLng(51.3571486, 6.638026),
        initialZoom: _zoomLevel,
        minZoom: 5.0,
        maxZoom: 19.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onTap: (tapPosition, point) {
          setState(() {
            selectedOrderId = null;
          });
        },
        onPositionChanged: (camera, hasGesture) {
          if (!_isMapReady) {
            _isMapReady = true;
          }

          if ((camera.zoom - _lastZoomLevel).abs() > 0.5) {
            _lastZoomLevel = camera.zoom;
          }
        }),
      children: [
        TileLayer(
          urlTemplate: isLight ? MapTileConfig.lightUrl : MapTileConfig.darkUrl,
          subdomains: MapTileConfig.subdomains,
          userAgentPackageName: 'com.cultioo.business',
          maxNativeZoom: 19,
          maxZoom: 19,
          retinaMode: true,
          panBuffer: 2,
          keepBuffer: 4,
          additionalOptions: const {'attribution': '© CartoDB © OpenStreetMap'}),

        if (_routePoints.isNotEmpty)
          PolylineLayer(polylines: _buildTrafficAwarePolylines()),

        MarkerLayer(
          markers: [
            if (_routePoints.isEmpty) ..._buildClusteredMarkers(isLight),

            if (_routePoints.length >= 2) ...[
              // You marker (current location) - blue GPS dot style
              Marker(
                point: _routePoints.first,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF007AFF), Color(0xFF0051D5)]),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF007AFF).withOpacity(0.45),
                        blurRadius: 8,
                        spreadRadius: 2),
                    ]))),

              // Pickup marker - solid yellow triangle
              if (_activeRouteInfo?['pickupLocation'] != null)
                Marker(
                  point: _activeRouteInfo!['pickupLocation'] as LatLng,
                  width: 22,
                  height: 22,
                  child: CustomPaint(
                    painter: _SolidTrianglePainter(color: const Color(0xFFFFC107)),
                    size: const Size(22, 22))),

              // Delivery marker - solid green rectangle
              Marker(
                point: _routePoints.last,
                width: 20,
                height: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                        offset: const Offset(0, 2)),
                    ]))),
            ],

            if (currentLocation != null && _routePoints.isEmpty)
              Marker(
                point: currentLocation!,
                child: _buildAppleLocationIndicator(isLight),
                width: 18,
                height: 18),
          ]),
      ]);
  }

  // Floating UI elements over the map
  Widget _buildFloatingUI(bool isLight) {
    if (_kDebugMode) print('🎨 _buildFloatingUI called - isLight: $isLight');
    return Stack(
      children: [
        // Distance container at the top when route is active
        if (_showRouteInfo &&
            _routePoints.isNotEmpty &&
            _activeRouteInfo != null)
          _buildDistanceContainer(isLight),

        // Close button at the top right - show when route points exist
        if (_routePoints.isNotEmpty) _buildCloseRouteButton(isLight),

        // Select Route button at the bottom when route is displayed
        if (_showRouteInfo &&
            _routePoints.isNotEmpty &&
            _activeRouteInfo != null)
          _buildSelectRouteButton(isLight),

        // Bottom content - dock or swipe interface
        _buildBottomFloatingContent(isLight),
      ]);
  }

  // Distance container at the top of the screen - Trade Republic Style
  Widget _buildDistanceContainer(bool isLight) {
    // Current to Pickup distance
    final currentToPickupDist = _toDouble(
      _activeRouteInfo!['currentToPickupDistance']);
    final currentToPickupDur = _toDouble(
      _activeRouteInfo!['currentToPickupDuration']);
    // Pickup to delivery distance
    final pickupToDeliveryDist = _toDouble(
      _activeRouteInfo!['pickupToDeliveryDistance']);
    final pickupToDeliveryDur = _toDouble(
      _activeRouteInfo!['pickupToDeliveryDuration']);
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final topPadding = MediaQuery.of(context).padding.top;

    // Get pickup and delivery addresses
    final pickupAddress = _activeRouteInfo?['pickupAddress'] ?? AppLocalizations.of(context)?.pickup ?? AppLocalizations.of(context)!.tr('Pickup');
    final deliveryAddressRaw = _activeRouteInfo?['deliveryAddress'] ?? AppLocalizations.of(context)!.tr('');

    // Clean up delivery address
    final deliveryAddress = deliveryAddressRaw.toString().trim();
    final hasValidDeliveryAddress = deliveryAddress.isNotEmpty;

    return Positioned(
      top: topPadding + 12,
      left: 16,
      right: 16,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, -20 * (1 - value)),
            child: Opacity(opacity: value, child: child));
        },
        child: Container(
          padding: DesktopAppWrapper.getPagePadding(),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : Colors.black,
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 8)),
            ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row - Minimal
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.map,
                        color: isLight ? Colors.black : Colors.white,
                        size: 24),
                      SizedBox(width: 10),
                      Text(
                        AppLocalizations.of(context)?.route ?? AppLocalizations.of(context)!.tr('Route'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white,
                          fontFamily: 'Poppins')),
                    ]),
                  // Close button - Trade Republic style
                  TradeRepublicButton.icon(
                    icon: Icon(CupertinoIcons.xmark, size: 18),
                    size: 36,
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _showRouteInfo = false;
                        _activeRouteInfo = null;
                        _routePoints.clear();
                        _trafficSegments.clear();
                        _isRouteInfoMinimized = false;
                      });
                      hideDockNotifier.value = false;
                      activeOrderNotifier.value = null;
                    }),
                ]),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Minimal Timeline
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline dots - color coded: blue=You, gold=Pickup, green=Delivery
                  Column(
                    children: [
                      // You - blue dot
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Color(0xFF007AFF),
                          shape: BoxShape.circle)),
                      Container(
                        width: 1.5,
                        height: 22,
                        color: isLight ? Colors.black12 : Colors.white24),
                      // Pickup - gold dot
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Color(0xFFFFC107),
                          shape: BoxShape.circle)),
                      Container(
                        width: 1.5,
                        height: 22,
                        color: isLight ? Colors.black12 : Colors.white24),
                      // Delivery - green dot
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle)),
                    ]),
                  SizedBox(width: 12),
                  // Addresses and distances - clearer layout
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Your Location
                        Row(
                          children: [
                            Text(
                              AppLocalizations.of(context)?.you ?? AppLocalizations.of(context)!.tr('You'),
                              style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF007AFF))),
                            SizedBox(width: 8),
                            Icon(
                              CupertinoIcons.arrow_right,
                              size: 12,
                              color: isLight ? Colors.black45 : Colors.white54),
                            SizedBox(width: 4),
                            Text(
                              '${appSettings.formatDistance(currentToPickupDist)} • ${_formatRouteDuration(currentToPickupDur)}',
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                color: isLight ? Colors.black54 : Colors.white70)),
                          ]),
                        SizedBox(height: 10),
                        // Pickup address
                        Text(
                          pickupAddress.toString().length > 35
                              ? '${pickupAddress.toString().substring(0, 35)}...'
                              : pickupAddress.toString(),
                          style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFFC107)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                        SizedBox(height: 4),
                        // Arrow to delivery with distance
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.arrow_down,
                              size: 12,
                              color: isLight ? Colors.black45 : Colors.white54),
                            SizedBox(width: 4),
                            Text(
                              '${appSettings.formatDistance(pickupToDeliveryDist)} • ${_formatRouteDuration(pickupToDeliveryDur)}',
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w500,
                                color: isLight ? Colors.black54 : Colors.white70)),
                          ]),
                        SizedBox(height: 4),
                        // Delivery address
                        Text(
                          hasValidDeliveryAddress
                              ? (deliveryAddress.length > 35
                                    ? '${deliveryAddress.substring(0, 35)}...'
                                    : deliveryAddress)
                              : AppLocalizations.of(context)?.deliveryAddressNotAvailable ?? AppLocalizations.of(context)!.tr('Delivery address not available'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: hasValidDeliveryAddress
                                ? const Color(0xFF4CAF50)
                                : (isLight ? Colors.black38 : Colors.white38)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      ])),
                ]),
            ]))));
  }

  // Close button at the top right - Now integrated in the container above
  Widget _buildCloseRouteButton(bool isLight) {
    // Only show standalone close button when distance container is not visible
    if (_showRouteInfo && _activeRouteInfo != null) {
      return const SizedBox.shrink(); // Hide - close button is now in the container
    }

    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 16,
      right: 20,
      child: TradeRepublicButton.icon(
        icon: Icon(CupertinoIcons.xmark, size: 22),
        size: 44,
        onPressed: () {
          HapticFeedback.mediumImpact();
          print('🔴 CLOSE ROUTE BUTTON - Closing route view');
          setState(() {
            _showRouteInfo = false;
            _activeRouteInfo = null;
            _routePoints.clear();
            _trafficSegments.clear();
            _isRouteInfoMinimized = false;
          });
          hideDockNotifier.value = false;
          activeOrderNotifier.value = null;
          print('✅ Route view closed');
        }));
  }

  // Select Route button at the bottom of the screen when route is displayed
  Widget _buildSelectRouteButton(bool isLight) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    // Calculate pickup to delivery distance only
    final pickupToDeliveryDist = _toDouble(
      _activeRouteInfo?['pickupToDeliveryDistance']);

    return Positioned(
      bottom: bottomPadding + 20,
      left: 20,
      right: 20,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isLight
                ? [const Color(0xFF007AFF), const Color(0xFF0051D5)]
                : [const Color(0xFF0A84FF), const Color(0xFF0066CC)]),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          boxShadow: [
            BoxShadow(
              color:
                  (isLight ? const Color(0xFF007AFF) : const Color(0xFF0A84FF))
                      .withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8)),
          ]),
        child: TradeRepublicButton(
          label: AppLocalizations.of(context)?.selectRoute ?? AppLocalizations.of(context)!.tr('Select Route'),
          icon: Icon(
            CupertinoIcons.checkmark_circle_fill,
            size: 20,
            color: Colors.white),
          backgroundColor: isLight
              ? const Color(0xFF007AFF)
              : const Color(0xFF0A84FF),
          foregroundColor: Colors.white,
          onPressed: () {
            HapticFeedback.mediumImpact();
            _showVehicleSelectionModal(isLight);
          })));
  }

  // Load driver's vehicles from database
  Future<void> _loadDriverVehicles() async {
    print('🚗🚗🚗 _loadDriverVehicles() START 🚗🚗🚗');
    print('🚗 _isLoadingVehicles=$_isLoadingVehicles');

    if (_isLoadingVehicles) {
      print('⏳ Already loading vehicles, skipping...');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingVehicles = true;
    });

    try {
      // Get driver username from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final driverUserId = prefs.getString('username') ?? '';
      print('✅ Using driver ID from preferences: "$driverUserId"');

      if (!mounted) return; // Check before async call
      await _loadVehiclesForUser(driverUserId);
    } catch (e) {
      print('❌ Error loading vehicles: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingVehicles = false;
      });
    }
  }

  Future<void> _loadVehiclesForUser(String userId) async {
    print('🚗 Loading vehicles for driver: $userId');

    final url = '${ApiConfig.baseUrl}/api/delvioo/vehicles/$userId';
    print('🌐 API URL: $url');

    final response = await http.get(Uri.parse(url));

    if (!mounted) return;

    print('📡 API Response status: ${response.statusCode}');
    print(
      '📡 API Response body: ${response.body.substring(0, math.min(500, response.body.length))}...');

    if (response.statusCode == 200) {
      final result = json.decode(response.body);

      if (result['success'] && result['vehicles'] != null) {
        if (!mounted) return;
        setState(() {
          _driverVehicles = List<Map<String, dynamic>>.from(result['vehicles']);
          _isLoadingVehicles = false;
        });
        print('✅ Loaded ${_driverVehicles.length} vehicles');

        // Debug: Print vehicle details including payload
        for (var vehicle in _driverVehicles) {
          print(
            '   📦 ${vehicle['vehicle_make']} ${vehicle['vehicle_model']} - type: ${vehicle['vehicle_type']} - payload_capacity: ${vehicle['payload_capacity']} - cargo_capacity: ${vehicle['cargo_capacity']}');
        }
      } else {
        print('⚠️ API returned success=false or no vehicles');
        if (!mounted) return;
        setState(() {
          _isLoadingVehicles = false;
        });
      }
    } else {
      print('❌ Failed to load vehicles: ${response.statusCode}');
      if (!mounted) return;
      setState(() {
        _isLoadingVehicles = false;
      });
    }
  }

  // Get vehicle icon based on type
  IconData _getVehicleIcon(Map<String, dynamic> vehicle) {
    // Try to determine vehicle type from make/model
    final make = (vehicle['vehicle_make'] ?? AppLocalizations.of(context)!.tr('')).toString().toLowerCase();
    final model = (vehicle['vehicle_model'] ?? AppLocalizations.of(context)!.tr('')).toString().toLowerCase();
    final combined = '$make $model';

    if (combined.contains('bike') || combined.contains('bicycle')) {
      return CupertinoIcons.person_crop_circle;
    } else if (combined.contains('moto') ||
        combined.contains('scooter') ||
        combined.contains('vespa')) {
      return CupertinoIcons.car;
    } else if (combined.contains('van') ||
        combined.contains('sprinter') ||
        combined.contains('transit') ||
        combined.contains('transporter')) {
      return CupertinoIcons.bus;
    } else if (combined.contains('truck') ||
        combined.contains('lkw') ||
        combined.contains('lorry')) {
      return CupertinoIcons.cube_box;
    } else {
      return CupertinoIcons.car;
    }
  }

  // Vehicle Selection Modal
  void _showVehicleSelectionModal(bool isLight) async {
    // Load vehicles and accepted orders when modal opens
    await _loadDriverVehicles();
    if (!mounted) return;
    await _loadAcceptedOrders();
    if (!mounted) return;

    // Check if driver has any vehicles at all
    if (_driverVehicles.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.noVehiclesRegistered ?? AppLocalizations.of(context)!.tr('No vehicles registered. Please add a vehicle first.'));
      return;
    }

    // Check if driver has a matching vehicle for the wagon type
    final requiredWagonType = _currentAuctionForBid != null
        ? _resolvedWagonTypeForAuction(_currentAuctionForBid!)
        : _kDefaultWagonTypeId;
    final matchingVehicle = _getMatchingVehicle(requiredWagonType);

    if (matchingVehicle == null) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.noneOfYourVehiclesMatch ?? AppLocalizations.of(context)!.tr('None of your vehicles match the required type for this order.'));
      return;
    }

    // Auto-select matching vehicle and populate sections
    _selectedVehicleId = matchingVehicle['id'];
    _loadVehicleSectionsFromData(matchingVehicle);

    TradeRepublicBottomSheet.show(
      context: context,
      child: _buildVehicleSelectionContent(isLight));
  }

  // Load sections from a vehicle's vehicle_sections JSON field
  void _loadVehicleSectionsFromData(Map<String, dynamic> vehicle) {
    _selectedVehicleSections.clear();

    dynamic sectionsData = vehicle['vehicle_sections'];

    if (sectionsData != null) {
      List<Map<String, dynamic>> parsedSections = [];

      // Parse JSON string if needed
      if (sectionsData is String) {
        try {
          final decoded = json.decode(sectionsData);
          if (decoded is List) {
            parsedSections = List<Map<String, dynamic>>.from(decoded);
          }
        } catch (e) {
          print('❌ Error parsing vehicle_sections JSON string: $e');
        }
      } else if (sectionsData is List) {
        parsedSections = List<Map<String, dynamic>>.from(sectionsData);
      }

      _selectedVehicleSections.addAll(parsedSections);
    }

    // Auto-select first section if available
    if (_selectedVehicleSections.isNotEmpty) {
      _selectedSectionIndex = 0;
    } else {
      _selectedSectionIndex = null;
    }

    print('📦 Loaded ${_selectedVehicleSections.length} sections from vehicle ${vehicle['id']}');
  }

  // Vehicle Selection Content
  Widget _buildVehicleSelectionContent(bool isLight) {
    // Get required wagon type from current auction
    final requiredWagonType = _currentAuctionForBid != null
        ? _resolvedWagonTypeForAuction(_currentAuctionForBid!)
        : _kDefaultWagonTypeId;

    return StatefulBuilder(
      builder: (context, setModalState) {
        // Get section info
        final section = _selectedSectionIndex != null && 
                       _selectedSectionIndex! < _selectedVehicleSections.length
            ? _selectedVehicleSections[_selectedSectionIndex!]
            : null;
        final sectionName =
          section?['name'] ?? (AppLocalizations.of(context)?.section ?? AppLocalizations.of(context)!.tr(''));
        final sectionPercentage = _toDouble(
          section?['percentage'] ?? section?['size_percentage'],
          defaultValue: 100.0).toInt();
        
        // ── CullyAI: Smart capacity matching ──
        // Vehicle has TWO capacity types:
        //   cargo_capacity / cargo_unit → volume (ft³, m³)
        //   payload_capacity / payload_unit → weight (lbs, kg, t)
        // Choose the right one based on whether the order unit is weight or volume
        final selectedVehicle = _driverVehicles.firstWhere(
          (v) => v['id'] == _selectedVehicleId,
          orElse: () => <String, dynamic>{});
        
        // Get order info from current auction
        final rawOrderQuantity = _toDouble(
          _currentAuctionForBid?['total_quantity']);
        final rawOrderUnit = _currentAuctionForBid?['quantity_unit']?.toString() ?? AppLocalizations.of(context)!.tr('t');
        
        // Determine if order unit is weight or volume
        final bool orderIsVolume = _isVolumeUnit(rawOrderUnit);
        
        // ── Get BOTH capacity dimensions from vehicle ──
        final double payloadCapTotal = _toDouble(selectedVehicle['payload_capacity']);
        final String payloadUnit = selectedVehicle['payload_unit']?.toString() ?? AppLocalizations.of(context)!.tr('lbs');
        final double cargoCapTotal = _toDouble(selectedVehicle['cargo_capacity']);
        final String cargoUnit = selectedVehicle['cargo_unit']?.toString() ?? AppLocalizations.of(context)!.tr('ft³');
        
        // Primary dimension: matches the order unit
        final double vehicleCapacityTotal;
        final String rawSectionUnit;
        if (orderIsVolume) {
          vehicleCapacityTotal = cargoCapTotal;
          rawSectionUnit = cargoUnit;
        } else {
          vehicleCapacityTotal = payloadCapTotal;
          rawSectionUnit = payloadUnit;
        }
        final rawSectionCapacity = vehicleCapacityTotal * sectionPercentage / 100.0;
        
        // Secondary dimension: the OTHER capacity (volume if order is weight, weight if order is volume)
        final double secondaryCapTotal;
        final String secondaryRawUnit;
        final String secondaryLabel;
        final IconData secondaryIcon;
        if (orderIsVolume) {
          // Order is volume → secondary is weight (payload)
          secondaryCapTotal = payloadCapTotal;
          secondaryRawUnit = payloadUnit;
          secondaryLabel = 'Weight';
          secondaryIcon = CupertinoIcons.gauge;
        } else {
          // Order is weight → secondary is volume (cargo)
          secondaryCapTotal = cargoCapTotal;
          secondaryRawUnit = cargoUnit;
          secondaryLabel = 'Volume';
          secondaryIcon = CupertinoIcons.cube;
        }
        final double secondarySectionCap = secondaryCapTotal * sectionPercentage / 100.0;
        final convertedSecondary = _convertWeightToUserUnit(secondarySectionCap, secondaryRawUnit);
        final displaySecondaryCap = convertedSecondary['value'] as double;
        final displaySecondaryUnit = convertedSecondary['unit'] as String;
        final bool hasSecondaryCapacity = secondaryCapTotal > 0;

        // ── CullyAI: Convert both to user's preferred unit for display ──
        final convertedOrder = _convertWeightToUserUnit(rawOrderQuantity, rawOrderUnit);
        final convertedSection = _convertWeightToUserUnit(rawSectionCapacity, rawSectionUnit);
        
        final displayOrderQty = convertedOrder['value'] as double;
        final displayOrderUnit = convertedOrder['unit'] as String;
        final displaySectionCap = convertedSection['value'] as double;
        final displaySectionUnit = convertedSection['unit'] as String;

        // ── CullyAI: Normalize both to same base for accurate comparison ──
        // Weight → kg, Volume → m³
        final orderBase = _normalizeToBase(rawOrderQuantity, rawOrderUnit);
        final sectionBase = _normalizeToBase(rawSectionCapacity, rawSectionUnit);
        
        final bool orderFits = orderBase <= sectionBase;
        final double fillPercent = sectionBase > 0 
            ? (orderBase / sectionBase * 100).clamp(0.0, 999.0) 
            : 0.0;
        // Calculate remaining in the section's raw unit
        final double remainingRaw = (rawSectionCapacity - rawOrderQuantity * (sectionBase > 0 ? rawSectionCapacity / sectionBase : 1)).abs();
        final convertedRemaining = _convertWeightToUserUnit(remainingRaw, rawSectionUnit);
        final displayRemainingValFinal = convertedRemaining['value'] as double;
        final displayRemainingUnit = convertedRemaining['unit'] as String;

        // Check if unit conversion happened (units differ between raw sources)
        final bool unitsConverted = rawOrderUnit.toLowerCase().trim() != rawSectionUnit.toLowerCase().trim();

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              DragHandle(),
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.cube_box,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.confirmCapacity ?? AppLocalizations.of(context)!.tr('Confirm Capacity'),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
                ]),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              Text(
                '$sectionName ($sectionPercentage%)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: (isLight ? Colors.black : Colors.white)
                      .withOpacity(0.5))),
                SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                // Capacity comparison cards
                Row(
                    children: [
                      // Order card
                      Expanded(
                        child: Container(
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            color: isLight
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                          child: Column(
                            children: [
                              Icon(
                                CupertinoIcons.cube_box,
                                color: isLight ? Colors.black : Colors.white,
                                size: 28),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                              Text(
                                AppLocalizations.of(context)?.order ?? AppLocalizations.of(context)!.tr('Order'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                                  fontFamily: 'Poppins')),
                              SizedBox(height: 4),
                              Text(
                                _formatQuantity(displayOrderQty),
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                                  fontWeight: FontWeight.w700,
                                  color: isLight ? Colors.black : Colors.white,
                                  fontFamily: 'Poppins')),
                              Text(
                                displayOrderUnit,
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w500,
                                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
                                  fontFamily: 'Poppins')),
                            ]))),
                      SizedBox(width: 12),
                      // Section card
                      Expanded(
                        child: Container(
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            color: isLight
                                ? Colors.white
                                : const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                          child: Column(
                            children: [
                              Icon(
                                CupertinoIcons.square_grid_2x2,
                                color: isLight ? Colors.black : Colors.white,
                                size: 28),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                              Text(
                                AppLocalizations.of(context)?.section ?? AppLocalizations.of(context)!.tr('Section'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                                  fontFamily: 'Poppins')),
                              SizedBox(height: 4),
                              Text(
                                _formatQuantity(displaySectionCap),
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                                  fontWeight: FontWeight.w700,
                                  color: isLight ? Colors.black : Colors.white,
                                  fontFamily: 'Poppins')),
                              Text(
                                displaySectionUnit,
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w500,
                                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
                                  fontFamily: 'Poppins')),
                            ]))),
                    ]),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                // ── CullyAI Analysis Result ──
                Container(
                  width: double.infinity,
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color: orderFits
                        ? Colors.green.withOpacity(isLight ? 0.08 : 0.15)
                        : Colors.red.withOpacity(isLight ? 0.08 : 0.15),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // CullyAI header
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: orderFits
                                    ? [const Color(0xFF34C759), const Color(0xFF30B350)]
                                    : [const Color(0xFFFF3B30), const Color(0xFFE5352B)]),
                              borderRadius: BorderRadius.circular(8)),
                            child: Icon(CupertinoIcons.sparkles, size: 16, color: Colors.white)),
                          SizedBox(width: 10),
                          Text(
                            'CullyAI',
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                              fontFamily: 'Poppins')),
                          const Spacer(),
                          // Fill percentage badge
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: orderFits
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                            child: Text(
                              '${fillPercent.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: orderFits ? Colors.green[700] : Colors.red[700],
                                fontFamily: 'Poppins'))),
                        ]),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                      // Fill bar — custom, no raw LinearProgressIndicator
                      LayoutBuilder(
                        builder: (ctx, constraints) {
                          final barColor = orderFits ? const Color(0xFF34C759) : const Color(0xFFFF3B30);
                          final filled = (fillPercent.clamp(0, 100) / 100 * constraints.maxWidth);
                          return Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(4)),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: filled,
                                decoration: BoxDecoration(
                                  color: barColor,
                                  borderRadius: BorderRadius.circular(4)))));
                        }),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                      // Result text
                      Text(
                        orderFits
                            ? '✓ Order fits in this section'
                            : '✗ Order does not fit in this section',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: orderFits ? Colors.green[700] : Colors.red[700],
                          fontFamily: 'Poppins')),
                      SizedBox(height: 4),
                      // Remaining / overflow info
                      Text(
                        orderFits
                            ? '${_formatQuantity(displayRemainingValFinal)} $displayRemainingUnit remaining capacity'
                            : '${_formatQuantity(displayRemainingValFinal)} $displayRemainingUnit over capacity',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
                          fontFamily: 'Poppins')),
                      // Unit conversion info if units were different
                      if (unitsConverted) ...[
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.arrow_right_arrow_left,
                              size: 12,
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.4)),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Auto-converted: ${_formatQuantity(rawOrderQuantity)} $rawOrderUnit → ${_formatQuantity(displayOrderQty)} $displayOrderUnit  ·  ${_formatQuantity(rawSectionCapacity)} $rawSectionUnit → ${_formatQuantity(displaySectionCap)} $displaySectionUnit',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                                  fontFamily: 'Poppins'))),
                          ]),
                      ],
                    ])),
                // ── Secondary dimension info (the other capacity) ──
                if (hasSecondaryCapacity) ...[                
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.04),
                      borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8)),
                          child: Icon(secondaryIcon, size: 16, color: const Color(0xFF007AFF))),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Truck $secondaryLabel',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
                                      fontFamily: 'Poppins')),
                                  SizedBox(width: 6),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(6)),
                                    child: Text(
                                      'Info',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                                        fontFamily: 'Poppins'))),
                                ]),
                              SizedBox(height: 2),
                              Text(
                                '${_formatQuantity(displaySecondaryCap)} $displaySecondaryUnit in this section',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                                  fontFamily: 'Poppins')),
                              SizedBox(height: 2),
                              Text(
                                'Order unit is $rawOrderUnit — ${orderIsVolume ? 'weight' : 'volume'} not checkable without density',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                                  fontFamily: 'Poppins',
                                  fontStyle: FontStyle.italic)),
                            ])),
                        Icon(
                          CupertinoIcons.info_circle,
                          size: 18,
                          color: (isLight ? Colors.black : Colors.white).withOpacity(0.3)),
                      ])),
                ],
                SizedBox(height: 20),
                      ]))),
                // Buttons
                Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Column(
                    children: [
                      // Primary button
                      TradeRepublicButton(
                        label: orderFits
                            ? (AppLocalizations.of(context)?.yesItFits ?? AppLocalizations.of(context)!.tr('Yes, it fits'))
                            : 'Proceed Anyway',
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(context);
                          _showPriceInputModal(isLight);
                        }),
                      if (!orderFits) ...[
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          AppLocalizations.of(context)?.tr('Split orders are now handled in Orders') ??
                              'Split orders are now handled in Orders',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                            fontFamily: 'Poppins')),
                      ],
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                      // Select different section button - Trade Republic style
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)?.selectDifferentSection ?? AppLocalizations.of(context)!.tr('Select Different Section'),
                        isSecondary: true,
                        onPressed: () {
                          Navigator.pop(context);
                          _showSectionSelectionModal(isLight);
                        }),
                    ])),
              ]));
        });
  }

  // Show modal when order doesn't fit in section - offer to split
  void _showSplitOrderModal(bool isLight, Map<String, dynamic> capacityCheck) {
    final rawOrderQuantity = capacityCheck['orderQuantity'] as double;
    final rawOrderUnit = capacityCheck['orderUnit'] as String;
    final fittingQuantity = capacityCheck['fittingQuantity'] as double;
    final remainingQuantity = capacityCheck['remainingQuantity'] as double;
    final displayOrderQty = capacityCheck['displayOrderQty'] as double;
    final displayOrderUnit = capacityCheck['displayOrderUnit'] as String;
    final displaySectionCap = capacityCheck['displaySectionCap'] as double;
    final displaySectionUnit = capacityCheck['displaySectionUnit'] as String;

    // Get section name
    final section = _selectedSectionIndex != null &&
                    _selectedSectionIndex! < _selectedVehicleSections.length
        ? _selectedVehicleSections[_selectedSectionIndex!]
        : null;
    final sectionName = section?['name'] ?? 'Section ${(_selectedSectionIndex ?? 0) + 1}';

    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            DragHandle(),
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9500), Color(0xFFFF6B00)]),
                    borderRadius: BorderRadius.circular(14)),
                  child: Icon(CupertinoIcons.arrow_branch, size: 22, color: Colors.white)),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.splitOrder ?? AppLocalizations.of(context)!.tr('Split Order'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.4,
                          fontFamily: 'Poppins')),
                      Text(
                        AppLocalizations.of(context)?.youTakeWhatFitsRestGoesToAnotherDriver ?? AppLocalizations.of(context)!.tr('You take what fits — rest goes to another driver'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                          fontFamily: 'Poppins')),
                    ])),
              ]),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            // Split diagram
            Row(
              children: [
                // This driver's part
                Expanded(
                  child: Container(
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(isLight ? 0.08 : 0.15),
                      borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                          child: Icon(CupertinoIcons.person_fill, size: 20, color: Color(0xFF34C759))),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          AppLocalizations.of(context)?.splitOrderYouLabel ?? AppLocalizations.of(context)!.tr('You'),
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                            fontFamily: 'Poppins')),
                        SizedBox(height: 4),
                        Text(
                          _formatQuantity(displaySectionCap),
                          style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700,
                            color: const Color(0xFF34C759),
                            fontFamily: 'Poppins')),
                        Text(
                          displaySectionUnit,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500,
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
                            fontFamily: 'Poppins')),
                        SizedBox(height: 4),
                        Text(
                          sectionName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w400,
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                            fontFamily: 'Poppins')),
                      ]))),
                SizedBox(width: 8),
                // Arrow
                Column(
                  children: [
                    Icon(CupertinoIcons.arrow_right, size: 20,
                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.3)),
                    SizedBox(height: 4),
                    Text(
                      _formatQuantity(displayOrderQty),
                      style: TextStyle(
                        fontSize: 11,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                        fontFamily: 'Poppins')),
                    Text(
                      displayOrderUnit,
                      style: TextStyle(
                        fontSize: 10,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                        fontFamily: 'Poppins')),
                    Text(
                      AppLocalizations.of(context)?.total ?? AppLocalizations.of(context)!.tr('total'),
                      style: TextStyle(
                        fontSize: 9,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.25),
                        fontFamily: 'Poppins')),
                  ]),
                SizedBox(width: 8),
                // Other driver's part
                Expanded(
                  child: Container(
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withOpacity(isLight ? 0.07 : 0.14),
                      borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                          child: Icon(CupertinoIcons.person_2_fill, size: 20, color: Color(0xFF007AFF))),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          AppLocalizations.of(context)?.otherDriver ?? AppLocalizations.of(context)!.tr('Other Driver'),
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                            fontFamily: 'Poppins')),
                        SizedBox(height: 4),
                        Builder(builder: (ctx) {
                          // Convert remaining back to display unit
                          final convRemaining = _convertWeightToUserUnit(remainingQuantity, rawOrderUnit);
                          final remVal = convRemaining['value'] as double;
                          final remUnit = convRemaining['unit'] as String;
                          return Column(
                            children: [
                              Text(
                                _formatQuantity(remVal),
                                style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w700,
                                  color: Color(0xFF007AFF),
                                  fontFamily: 'Poppins')),
                              Text(
                                remUnit,
                                style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500,
                                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
                                  fontFamily: 'Poppins')),
                            ]);
                        }),
                        SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context)?.backToPool ?? AppLocalizations.of(context)!.tr('Back to pool'),
                          style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w400,
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
                            fontFamily: 'Poppins')),
                      ]))),
              ]),
            SizedBox(height: 20),
            // Info note
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.04),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
              child: Row(
                children: [
                  Icon(CupertinoIcons.info_circle, size: 16,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.4)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.splitOrderRemainingInfo(
                        _formatQuantity(_convertWeightToUserUnit(remainingQuantity, rawOrderUnit)["value"] as double),
                        _convertWeightToUserUnit(remainingQuantity, rawOrderUnit)["unit"] as String) ?? 'The remaining ${_formatQuantity(_convertWeightToUserUnit(remainingQuantity, rawOrderUnit)["value"] as double)} ${_convertWeightToUserUnit(remainingQuantity, rawOrderUnit)["unit"]} will be posted back as a new auction. You keep your bid price for your portion.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                        fontFamily: 'Poppins'))),
                ])),
            const Spacer(),
            // Buttons
            Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)?.confirmSplitAndSetPrice ?? AppLocalizations.of(context)!.tr('Confirm Split & Set Price'),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(context);
                      // Mark auction for split on submit
                      if (_currentAuctionForBid != null) {
                        _currentAuctionForBid!['will_split_on_submit'] = true;
                        _currentAuctionForBid!['split_remaining_quantity'] =
                            remainingQuantity;
                        _currentAuctionForBid!['split_fitting_quantity'] =
                            fittingQuantity;
                        _currentAuctionForBid!['split_unit'] = rawOrderUnit;
                        _currentAuctionForBid!['split_section_index'] =
                            _selectedSectionIndex;
                        _currentAuctionForBid!['split_section_capacity'] =
                            capacityCheck['sectionCapacity'];
                      }
                      _showPriceInputModal(isLight);
                    }),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                    isSecondary: true,
                    onPressed: () {
                      Navigator.pop(context);
                      _showVehicleCapacityConfirmation(isLight);
                    }),
                ])),
          ])));
  }

  // Build custom vehicle icon based on type using simple icons
  Widget _buildVehicleIcon(String iconType, bool isSelected, bool isLight) {
    final color = isSelected
        ? (isLight ? Colors.white : Colors.black)
        : (isLight ? Colors.black : Colors.white).withOpacity(0.7);

    // Return icon based on wagon type
    IconData iconData;
    switch (iconType) {
      case 'all':
        iconData = CupertinoIcons.cube_box;
        break;
      case 'grain':
        iconData = CupertinoIcons.leaf_arrow_circlepath;
        break;
      case 'oil':
        iconData = CupertinoIcons.speedometer;
        break;
      case 'refrigerated':
      case 'frozen':
        iconData = CupertinoIcons.snow;
        break;
      case 'liquid':
        iconData = CupertinoIcons.drop;
        break;
      case 'bulk':
        iconData = CupertinoIcons.cube_box;
        break;
      case 'fresh':
        iconData = CupertinoIcons.leaf_arrow_circlepath;
        break;
      case 'bakery':
        iconData = CupertinoIcons.house;
        break;
      case 'beverage':
        iconData = CupertinoIcons.drop;
        break;
      case 'meat':
        iconData = CupertinoIcons.house;
        break;
      default:
        iconData = CupertinoIcons.cube_box;
    }

    return Icon(iconData, size: 20, color: color);
  }

  // Price Filter - Ultra Modern Apple/Linear Style
  Widget _buildPriceFilter(bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    // Format min/max nicely
    String formatPrice(double price) {
      if (price >= 1000) return appSettings.formatCurrency(price);
      return appSettings.formatCurrency(price).replaceAll('.00', '');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Price Display - Tappable for manual input
        Center(
          child: TradeRepublicCard(
            onTap: () {
              HapticFeedback.mediumImpact();
              _showPriceRangeInputModal(isLight);
            },
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
                children: [
                  // Hint text
                  Text(
                    AppLocalizations.of(context)?.tapToSetCustomRange ?? AppLocalizations.of(context)!.tr('Tap to set custom range'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.4))),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  // Min Price - Large
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                      height: 1.0,
                      color: isLight ? Colors.black : Colors.white),
                    child: Text(formatPrice(_minPriceFilter))),
                  SizedBox(height: 4),
                  // Separator
                  Container(
                    width: 24,
                    height: 2,
                    margin: EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.2),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8))),
                  SizedBox(height: 4),
                  // Max Price - Large
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                      height: 1.0,
                      color: isLight ? Colors.black : Colors.white),
                    child: Text(formatPrice(_maxPriceFilter))),
                ]))),

        SizedBox(height: 36),
        _buildModernDualSlider(isLight),

        SizedBox(height: 32),

        // Segmented Quick Filters - iOS Style
        _buildSegmentedPriceFilter(isLight),
      ]);
  }

  // Price Range Input Modal - Modern Bottom Sheet
  void _showPriceRangeInputModal(bool isLight) {
    if (_isPriceRangeSheetOpen) return;
    _isPriceRangeSheetOpen = true;

    TradeRepublicBottomSheet.show<void>(
      context: context,
      showDragHandle: true,
      avoidKeyboard: true,
      child: _PriceRangeBottomSheet(
        isLight: isLight,
        initialMin: _minPriceFilter,
        initialMax: _maxPriceFilter,
        onApply: (min, max) {
          setState(() {
            _minPriceFilter = min;
            _maxPriceFilter = max;
          });
          Navigator.of(context).pop();
        })).whenComplete(() {
      _isPriceRangeSheetOpen = false;
    });
  }

  // Price Input Card Widget - Clean, no border
  Widget _buildPriceInputCard({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    bool autofocus = false,
    required bool isLight,
    required Function(double) onChanged,
  }) {
    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.04),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.4))),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '\$',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.25))),
              SizedBox(width: 4),
              Expanded(
                child: TradeRepublicTextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ThousandSeparatorFormatter()],
                  textInputAction: TextInputAction.next,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    color: isLight ? Colors.black : Colors.white),
                  hintText: AppLocalizations.of(context)!.tr('0') ?? AppLocalizations.of(context)!.tr('0'),
                  hintStyle: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    color: (isLight ? Colors.black : Colors.white)
                        .withOpacity(0.22)),
                  filled: false,
                  onChanged: (text) {
                    final parsed =
                        double.tryParse(text.replaceAll(',', '')) ?? 0;
                    onChanged(parsed.clamp(0, 50000));
                  })),
            ]),
        ]));
  }

  // Quick Select Chip Widget
  Widget _buildQuickSelectChip(
    String label,
    double min,
    double max,
    double currentMin,
    double currentMax,
    bool isLight,
    StateSetter setModalState,
    Function(double, double) onSelect) {
    final isSelected = (currentMin == min && currentMax == max);

    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.selectionClick();
        setModalState(() {
          onSelect(min, max);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : (isLight ? Colors.black : Colors.white).withOpacity(0.05),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Text(
          label,
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w500,
            color: isSelected
                ? (isLight ? Colors.white : Colors.black)
                : (isLight ? Colors.black : Colors.white).withOpacity(0.7)))));
  }

  // Trade Republic Style Price Filter
  Widget _buildModernDualSlider(bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final textColor = isLight ? Colors.black : Colors.white;
    final bgColor = isLight ? Colors.black : Colors.white;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Min Slider
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Min Price',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor)),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: bgColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8)),
              child: Slider(
                value: _minPriceFilter.clamp(0, _maxPriceFilter),
                min: 0,
                max: 50000,
                onChanged: (v) {
                  if (v < _maxPriceFilter) {
                    setState(() => _minPriceFilter = v);
                  }
                })),
          ]),
        SizedBox(height: 20),
        // Max Slider
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Max Price',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor)),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: bgColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8)),
              child: Slider(
                value: _maxPriceFilter.clamp(_minPriceFilter, 50000),
                min: 0,
                max: 50000,
                onChanged: (v) {
                  if (v > _minPriceFilter) {
                    setState(() => _maxPriceFilter = v);
                  }
                })),
          ]),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        // Price Range Display
        Container(
          padding: DesktopAppWrapper.getPagePadding(),
          decoration: BoxDecoration(
            color: bgColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Min',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textColor.withOpacity(0.5))),
                  SizedBox(height: 4),
                  Text(
                    appSettings.formatCurrency(_minPriceFilter).replaceAll('.00', ''),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                      fontWeight: FontWeight.w700,
                      color: textColor)),
                ]),
              Container(
                width: 2,
                height: 40,
                decoration: BoxDecoration(
                  color: textColor.withOpacity(0.1))),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Max',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textColor.withOpacity(0.5))),
                  SizedBox(height: 4),
                  Text(
                    appSettings.formatCurrency(_maxPriceFilter).replaceAll('.00', ''),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                      fontWeight: FontWeight.w700,
                      color: textColor)),
                ]),
            ])),
      ]);
  }

  // Segmented Price Filter - iOS 18 Style
  Widget _buildSegmentedPriceFilter(bool isLight) {
    final filters = [
      {'label': AppLocalizations.of(context)?.allLabel ?? AppLocalizations.of(context)!.tr('All'), 'min': 0.0, 'max': 50000.0},
      {'label': '< 100', 'min': 0.0, 'max': 100.0},
      {'label': '100–1k', 'min': 100.0, 'max': 1000.0},
      {'label': '1k+', 'min': 1000.0, 'max': 50000.0},
    ];

    // Find current selected index
    int selectedIndex = 0;
    for (int i = 0; i < filters.length; i++) {
      if (_minPriceFilter == filters[i]['min'] &&
          _maxPriceFilter == filters[i]['max']) {
        selectedIndex = i;
        break;
      }
    }

    final fg = isLight ? Colors.black : Colors.white;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(filters.length, (i) {
          final isSelected = i == selectedIndex;
          return Padding(
            padding: EdgeInsets.only(right: i < filters.length - 1 ? 8 : 0),
            child: TradeRepublicTap(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _minPriceFilter = filters[i]['min'] as double;
                  _maxPriceFilter = filters[i]['max'] as double;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? fg : fg.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Text(
                  filters[i]['label'] as String,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? (isLight ? Colors.white : Colors.black)
                        : fg.withValues(alpha: 0.65))))));
        })));
  }

  // Legacy method - keeping for compatibility
  Widget _buildApplePriceChip(
    String label,
    double min,
    double max,
    bool isLight) {
    final isSelected = _minPriceFilter == min && _maxPriceFilter == max;

    return TradeRepublicTap(
      onTap: () {
        setState(() {
          _minPriceFilter = min;
          _maxPriceFilter = max;
        });
        HapticFeedback.selectionClick();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Text(
          label,
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w500,
            color: isSelected
                ? (isLight ? Colors.white : Colors.black)
                : (isLight ? Colors.black : Colors.white).withOpacity(0.7)))));
  }

  // Price Distribution Bar Chart - Minimalist Trade Republic Style
  Widget _buildPriceDistributionChart(bool isLight) {
    if (_kDebugMode) {
      print('📊 Building chart - Distribution: $_priceDistribution');
      print(
        '📊 Max count: ${_priceDistribution.isEmpty ? 0 : _priceDistribution.reduce((a, b) => a > b ? a : b)}');
    }

    final maxCount = _priceDistribution.isEmpty
        ? 0
        : _priceDistribution.reduce((a, b) => a > b ? a : b);

    // Price ranges for bucket detection
    final List<double> rangeStarts = [
      0,
      50,
      100,
      150,
      200,
      300,
      400,
      600,
      800,
      1000,
    ];
    final List<double> rangeEnds = [
      50,
      100,
      150,
      200,
      300,
      400,
      600,
      800,
      1000,
      2000,
    ];

    return SizedBox(
      height: 40, // Kompakter
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(10, (index) {
          final count = _priceDistribution[index];
          final heightPercent = maxCount > 0 ? count / maxCount : 0.05;

          // Check if this bar is in the selected price range
          final isInRange =
              (rangeEnds[index] > _minPriceFilter &&
              rangeStarts[index] < _maxPriceFilter);

          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 1.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                height: maxCount == 0 ? 2 : (35 * heightPercent), // Kompakter
                decoration: BoxDecoration(
                  color: isInRange
                      ? (isLight ? Colors.black : Colors.white)
                      : (isLight ? Colors.white : Colors.black),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)))));
        })));
  }

  // Custom Price Dialog - Bottom Sheet for Custom Price Range
  void _showCustomPriceDialog(bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final currencySymbol = appSettings.currencySymbol;
    final currencyName = appSettings.effectiveCurrency;

    final minController = TextEditingController(
      text: _minPriceFilter > 0
          ? _CentsInputFormatter._addCommas(_minPriceFilter.toInt().toString())
          : '');
    final maxController = TextEditingController(
      text: _maxPriceFilter > 0
          ? _CentsInputFormatter._addCommas(_maxPriceFilter.toInt().toString())
          : '');

    TradeRepublicBottomSheet.show(
      context: context,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DragHandle(),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Sheet header: Icon left + Title ──
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.tag,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white),
                    SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.customPriceRange ?? AppLocalizations.of(context)!.tr('Custom Price Range'),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
                  ]),
                SizedBox(height: 20),

                // Min Price Input - Trade Republic Style
                Text(
                  '${AppLocalizations.of(context)?.minimumPrice ?? AppLocalizations.of(context)!.tr('Minimum Price')} ($currencyName)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black54 : Colors.white54)),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                TradeRepublicTextField(
                  controller: minController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [_ThousandSeparatorFormatter()],
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white),
                  hintText: AppLocalizations.of(context)!.tr('0') ?? AppLocalizations.of(context)!.tr('0'),
                  filled: true,
                  fillColor: isLight
                      ? Colors.white
                      : Colors.transparent),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Max Price Input - Trade Republic Style
                Text(
                  '${AppLocalizations.of(context)?.maximumPrice ?? AppLocalizations.of(context)!.tr('Maximum Price')} ($currencyName)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black54 : Colors.white54)),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                TradeRepublicTextField(
                  controller: maxController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [_ThousandSeparatorFormatter()],
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white),
                  hintText: AppLocalizations.of(context)!.tr('1000') ?? AppLocalizations.of(context)!.tr('1000'),
                  filled: true,
                  fillColor: isLight
                      ? Colors.white
                      : Colors.transparent),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Action Buttons - Trade Republic Style
                Row(
                  children: [
                    Expanded(
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                        isSecondary: true,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                        })),
                    SizedBox(width: 12),
                    Expanded(
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)?.apply ?? AppLocalizations.of(context)!.tr('Apply'),
                        onPressed: () {
                          final min = double.tryParse(minController.text.replaceAll(',', '')) ?? 0;
                          final max = double.tryParse(maxController.text.replaceAll(',', '')) ?? 1000;

                          if (min < max) {
                            setState(() {
                              _minPriceFilter = min;
                              _maxPriceFilter = max;
                            });
                            HapticFeedback.lightImpact();
                            Navigator.pop(context);
                          }
                        })),
                  ]),
              ]),
          ])));
  }

  // Bottom Bar - am Rand verbunden wie oben
  Widget _buildBottomBar(bool isLight) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final availableOrders = _filteredOrders
        .where((order) => order['acceptance_status'] == 'available')
        .length;
    final acceptedOrders = _filteredOrders
        .where(
          (order) =>
              order['acceptance_status'] == 'accepted' ||
              order['acceptance_status'] == 'picked_up')
        .length;
    final totalActiveOrders = availableOrders + acceptedOrders;

    return Container(
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: bottomPadding + 12),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20))),
      child: Row(
        children: [
          // Order Badge - nur Text
          Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.cube_box,
                  size: 20,
                  color: isLight ? Colors.black87 : Colors.white),
                SizedBox(width: 8),
                Text(
                  '$totalActiveOrders',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black87 : Colors.white)),
              ])),
          const Spacer(),
          // Settings Button - Trade Republic style
          _buildSimpleFloatingButton(
            icon: CupertinoIcons.settings,
            onTap: _showSettingsModal,
            isLight: isLight),
          SizedBox(width: 12),
          // Location Button - Trade Republic style
          _buildSimpleFloatingButton(
            icon: CupertinoIcons.location,
            onTap: _showCurrentLocation,
            isLight: isLight),
        ]));
  }

  // OLD: Expandable shipping filter badge (nicht mehr genutzt)
  Widget _buildSimpleOrderBadge(bool isLight) {
    final availableOrders = _filteredOrders
        .where((order) => order['acceptance_status'] == 'available')
        .length;
    final acceptedOrders = _filteredOrders
        .where(
          (order) =>
              order['acceptance_status'] == 'accepted' ||
              order['acceptance_status'] == 'picked_up')
        .length;
    final totalActiveOrders = availableOrders + acceptedOrders;

    if (_kDebugMode) {
      print(
        '🎯 Building expandable shipping filter: $totalActiveOrders orders');
    }

    // Screen width for dynamic width
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      height: 56,
      constraints: BoxConstraints(
        minWidth: 80,
        maxWidth: _isShippingFilterExpanded ? screenWidth - 100 : 140),
      padding: EdgeInsets.symmetric(
        horizontal: _isShippingFilterExpanded ? 8 : 16),
      decoration: BoxDecoration(
        // Uber Style: Clean White/Black without Border
        color: isLight ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8), // Uniform 25px radius
        // Uber: Subtle shadows for elevation
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLight ? 0.1 : 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: 0),
        ]),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon und Anzahl - Clean und minimalistisch
          Icon(
            CupertinoIcons.cube_box,
            size: 20,
            color: isLight ? Colors.black87 : Colors.white),
          SizedBox(width: 8),
          Text(
            '$totalActiveOrders',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
              color: isLight ? Colors.black87 : Colors.white)),
        ]));
  }

  // Uber Style Delivery Type Switch - TradeRepublicSlider
  Widget _buildDeliveryTypeSwitch(bool isLight) {
    final topPadding = MediaQuery.of(context).padding.top;

    final currentIndex = _selectedShippingFilter == 'all'
        ? 0
        : _selectedShippingFilter == 'express'
        ? 1
        : 2;

    return Padding(
      padding: EdgeInsets.only(top: topPadding + 12, left: 20, right: 20),
      child: TradeRepublicSliderExpanded(
        labels: [AppLocalizations.of(context)?.delviooLabel ?? AppLocalizations.of(context)!.tr('Delvioo'), 'Express', 'Cold'],
        selectedIndex: currentIndex,
        horizontalPadding: 0,
        onChanged: (index) {
          setState(() {
            _selectedShippingFilter = index == 0
                ? 'all'
                : index == 1
                ? 'express'
                : 'cold';
          });
        }));
  }

  // Filter chips WITHOUT any animations - completely static
  Widget _buildFilterChipsWithSlidingBackground(bool isLight) {
    final filters = [
      {'value': 'all', 'label': AppLocalizations.of(context)?.allLabel ?? AppLocalizations.of(context)!.tr('All'), 'width': 55.0},
      {'value': 'standard', 'label': AppLocalizations.of(context)?.stdLabel ?? AppLocalizations.of(context)!.tr('Std'), 'width': 60.0},
      {'value': 'cold', 'label': AppLocalizations.of(context)?.coldLabel ?? AppLocalizations.of(context)!.tr('Cold'), 'width': 60.0},
    ];

    return Container(
      height: 44,
      padding: EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black12 : Colors.white12),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: filters.map((filter) {
          final isSelected = _selectedShippingFilter == filter['value'];

          return TradeRepublicTap(
            onTap: () {
              setState(() {
                _selectedShippingFilter = filter['value'] as String;
              });
              HapticFeedback.lightImpact();
            },
            child: Container(
              width: filter['width'] as double,
              height: 38,
              alignment: Alignment.center,
              decoration: isSelected
                  ? BoxDecoration(
                      color: isLight ? Colors.black : Colors.white,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8))
                  : null,
              child: Text(
                filter['label'] as String,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? (isLight ? Colors.white : Colors.black)
                      : (isLight ? Colors.black87 : Colors.white70)))));
        }).toList()));
  }

  // OLD: Filter chip for shipping types with staggered animation
  Widget _buildFilterChip(
    String filterValue,
    String label,
    bool isLight,
    int index) {
    final isSelected = _selectedShippingFilter == filterValue;

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 300 + (index * 50)), // Gestaffelt
      curve: Curves.easeOutBack,
      tween: Tween<double>(
        begin: 0.0,
        end: _isShippingFilterExpanded ? 1.0 : 0.0),
      builder: (context, animValue, child) {
        // REMOVED: Transform.scale animation - keep constant size
        return Opacity(
          opacity: animValue.clamp(0.0, 1.0), // Clamp to prevent invalid values
          child: TradeRepublicTap(
            onTap: () {
              setState(() {
                _selectedShippingFilter = filterValue;
              });
              HapticFeedback.lightImpact();
            },
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              tween: Tween<double>(begin: 0.0, end: isSelected ? 1.0 : 0.0),
              builder: (context, bubbleAnim, child) {
                // Back-and-forth animation: sin wave for smooth oscillation
                final oscillation = isSelected
                    ? math.sin(bubbleAnim * math.pi * 4) *
                          2.0 // 4 cycles back and forth
                    : 0.0;

                return Transform.translate(
                  offset: Offset(oscillation, 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isLight ? Colors.black : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? (isLight ? Colors.white : Colors.black)
                            : (isLight ? Colors.black87 : Colors.white70)))));
              })));
      });
  }

  // OLD: iOS Glassmorphism version (not used anymore)
  Widget _buildOldIOSBadge(bool isLight, int totalActiveOrders) {
    return ClipRRect(
      // iOS: Glassmorphism
      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isLight
                ? Colors.white.withOpacity(0.3)
                : Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            boxShadow: [
              BoxShadow(
                color: isLight
                    ? Colors.black.withOpacity(0.03)
                    : Colors.white.withOpacity(0.03),
                offset: const Offset(0, 4),
                blurRadius: 12,
                spreadRadius: 0),
            ]),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.cube_box,
                size: 20,
                color: isLight ? Colors.black87 : Colors.white),
              SizedBox(width: 8),
              Text(
                '$totalActiveOrders',
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: FontWeight.w600,
                  color: isLight ? Colors.black87 : Colors.white)),
            ]))));
  }

  // OLD CODE REMOVED - Horizontal button bar over dock - iOS 26 Dynamic Island Style
  Widget _buildTopRightButtons(bool isLight) {
    // THIS IS NOW REPLACED BY NEW SIMPLE BUTTONS ABOVE
    return const SizedBox.shrink();
  }

  // OLD CODE REMOVED - iOS 26 Dynamic Island Style horizontal controls
  Widget _buildHorizontalControlsIsland(bool isLight) {
    // THIS IS NOW REPLACED BY NEW SIMPLE BUTTONS ABOVE
    return const SizedBox.shrink();
  }

  // Compact product count info for iOS 26 island - NOT USED ANYMORE
  Widget _buildProductCountInfo(bool isLight) {
    // Use filtered orders with proper status enrichment
    final availableOrders = _filteredOrders
        .where((order) => order['acceptance_status'] == 'available')
        .length;
    final acceptedOrders = _filteredOrders
        .where(
          (order) =>
              order['acceptance_status'] == 'accepted' ||
              order['acceptance_status'] == 'picked_up')
        .length;
    final totalActiveOrders = availableOrders + acceptedOrders;

    print(
      '📊 Order counts: available=$availableOrders, accepted=$acceptedOrders, total_active=$totalActiveOrders');
    print(
      '📋 Raw orders count: ${orders.length}, filtered orders count: ${_filteredOrders.length}');

    return Container(
      margin: EdgeInsets.only(left: 20), // Left margin only
      height: 60, // Fixed height for consistency
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8), // 25px border radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLight ? 0.04 : 0.6),
            blurRadius: 40,
            offset: const Offset(0, 10),
            spreadRadius: -5),
        ]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isLight
                    ? [
                        Colors.white.withOpacity(0.15),
                        Colors.white.withOpacity(0.05),
                        Colors.white.withOpacity(0.02),
                      ]
                    : [
                        Colors.white.withOpacity(0.08),
                        Colors.white.withOpacity(0.02),
                        Colors.black.withOpacity(0.05),
                      ]),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.cube_box,
                  size: 16,
                  color: isLight ? Colors.black87 : Colors.white),
                SizedBox(width: 6),
                Text(
                  '$totalActiveOrders',
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black87 : Colors.white,
                    fontFamily: 'Poppins')),
                if (acceptedOrders > 0) ...[
                  SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.checkmark_circle,
                    size: 14,
                    color: Colors.green),
                  SizedBox(width: 2),
                  Text(
                    '$acceptedOrders',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.green,
                      fontFamily: 'Poppins')),
                ],
              ])))));
  }

  // Compact iOS 26 glass button for horizontal layout
  Widget _buildCompactGlassButton({
    required bool isLight,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    EdgeInsets? margin, // Custom margin parameter
  }) {
    return Container(
      margin:
          margin ?? EdgeInsets.all(20), // 20px margin from edge (default)
      height: 60, // Fixed height for consistency
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8), // 25px border radius
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLight ? 0.04 : 0.6),
            blurRadius: 40,
            offset: const Offset(0, 10),
            spreadRadius: -5),
        ]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: TradeRepublicTap(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isLight
                      ? [
                          Colors.white.withOpacity(0.15),
                          Colors.white.withOpacity(0.05),
                          Colors.white.withOpacity(0.02),
                        ]
                      : [
                          Colors.white.withOpacity(0.08),
                          Colors.white.withOpacity(0.02),
                          Colors.black.withOpacity(0.05),
                        ]),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
              child: Icon(icon, color: iconColor, size: 24))))));
  }

  // Bottom floating content (dock only, swipe removed - now only in main_page)
  Widget _buildBottomFloatingContent(bool isLight) {
    return const SizedBox.shrink();
  }

  Widget _buildHeader(bool isLight) {
    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.white.withOpacity(0.8)
            : Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        boxShadow: [
          BoxShadow(
            color: isLight
                ? Colors.black.withOpacity(0.05)
                : Colors.white.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8)),
        ]),
      child: Row(
        children: [
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: isLight
                  ? Colors.black.withOpacity(0.05)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Icon(
              CupertinoIcons.map,
              color: isLight ? Colors.black : Colors.white,
              size: 28)),
          SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.delviooMaps ?? AppLocalizations.of(context)!.tr('Delvioo Maps'),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.5)),
                SizedBox(height: 4),
                Text(
                  isLoading
                      ? AppLocalizations.of(context)?.loadingPickupOrders ?? AppLocalizations.of(context)!.tr('Loading pickup orders...')
                      : error != null
                      ? AppLocalizations.of(context)?.errorLoadingOrders ?? AppLocalizations.of(context)!.tr('Error loading orders')
                      : '${_filteredOrders.length} orders nearby',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.6))),
              ])),
          // Reload Button
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              boxShadow: [
                BoxShadow(
                  color: isLight
                      ? Colors.black.withOpacity(0.08)
                      : Colors.white.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 4)),
              ]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              child: TradeRepublicButton.icon(
                icon: Icon(
                  CupertinoIcons.refresh,
                  color: isLight
                      ? Colors.black.withOpacity(0.7)
                      : Colors.white.withOpacity(0.8),
                  size: 20),
                size: 44,
                isSecondary: true,
                onPressed: _loadOrders))),
        ]));
  }

  Widget _buildBottomActions(bool isLight) {
    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.white.withOpacity(0.9)
            : Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        boxShadow: [
          BoxShadow(
            color: isLight
                ? Colors.black.withOpacity(0.06)
                : Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8)),
        ]),
      child: Row(
        children: [
          Expanded(
            child: TradeRepublicCard(
              onTap: _showCurrentLocation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.location,
                    color: isLight ? Colors.black : Colors.white,
                    size: 24),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Text(
                    AppLocalizations.of(context)?.myLocation ?? AppLocalizations.of(context)!.tr('My Location'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white)),
                ]))),
          SizedBox(width: 16),
          Expanded(
            child: TradeRepublicCard(
              onTap: _showSettingsModal,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.settings,
                    color: isLight ? Colors.black : Colors.white,
                    size: 24),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Text(
                    AppLocalizations.of(context)?.settings ?? AppLocalizations.of(context)!.tr('Settings'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white)),
                ]))),
        ]));
  }

  // Bottom swipe container removed - using only floating swipe container

  Widget _buildMapContainer(bool isLight) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubicEmphasized, // Modern iOS-style curve
      width: double.infinity,
      height: _isMapExpanded
          ? MediaQuery.of(context).size.height
          : MediaQuery.of(context).size.height * 0.62,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_isMapExpanded ? 0 : 20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: _isMapExpanded ? 0 : 10,
            sigmaY: _isMapExpanded ? 0 : 10),
          child: Container(
            decoration: BoxDecoration(
              // Modern gradient background
              gradient: _isMapExpanded
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isLight
                          ? [
                              Colors.white.withOpacity(0.95),
                              Colors.white.withOpacity(0.85),
                            ]
                          : [
                              Colors.transparent.withOpacity(0.95),
                              const Color(0xFF000000).withOpacity(0.90),
                            ]),
              color: _isMapExpanded
                  ? (isLight ? Colors.white : const Color(0xFF000000))
                  : null,
              borderRadius: BorderRadius.circular(_isMapExpanded ? 0 : 20),
              // Premium shadow system
              boxShadow: _isMapExpanded
                  ? [
                      // Deep primary shadow
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 80,
                        spreadRadius: -10,
                        offset: const Offset(0, 40)),
                      // Accent glow
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.08),
                        blurRadius: 100,
                        spreadRadius: -25,
                        offset: const Offset(0, 20)),
                      // Inner highlight
                      BoxShadow(
                        color: isLight
                            ? Colors.white.withOpacity(0.7)
                            : Colors.white.withOpacity(0.05),
                        blurRadius: 2,
                        spreadRadius: -1,
                        offset: const Offset(0, -2)),
                    ]
                  : [
                      // Elevated card shadow
                      BoxShadow(
                        color: isLight
                            ? Colors.black.withOpacity(0.12)
                            : Colors.black.withOpacity(0.7),
                        blurRadius: 50,
                        spreadRadius: -8,
                        offset: const Offset(0, 25)),
                      // Subtle top highlight
                      BoxShadow(
                        color: isLight
                            ? Colors.white.withOpacity(0.95)
                            : Colors.white.withOpacity(0.08),
                        blurRadius: 4,
                        spreadRadius: -2,
                        offset: const Offset(0, -4)),
                      // Blue ambient glow
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.15),
                        blurRadius: 80,
                        spreadRadius: -25,
                        offset: const Offset(0, 12)),
                      // Additional depth shadow
                      BoxShadow(
                        color: isLight
                            ? Colors.black.withOpacity(0.06)
                            : Colors.black.withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: -5,
                        offset: const Offset(0, 15)),
                    ]),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Modern Drag Handle - Always visible for better UX
                    if (!_isMapExpanded)
                      TradeRepublicTap(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _isMapExpanded = true;
                          });
                        },
                        child: const DragHandle()),

                    // Map controls header - animiert sanft ein und aus
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: _isMapExpanded ? 0.0 : 1.0,
                        child: !_isMapExpanded
                            ? Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 12.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.location_solid,
                                      color: isLight
                                          ? Colors.black
                                          : Colors.white,
                                      size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      '${AppLocalizations.of(context)?.order ?? AppLocalizations.of(context)!.tr('Orders')} (${_filteredOrders.length})',
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        fontWeight: FontWeight.w700,
                                        color: isLight
                                            ? Colors.black
                                            : Colors.white)),
                                    const Spacer(),
                                    TradeRepublicButton(
                                      label: AppLocalizations.of(context)?.mapLabel ?? AppLocalizations.of(context)!.tr('Map'),
                                      icon: Icon(CupertinoIcons.map, size: 14, color: Colors.blue),
                                      foregroundColor: Colors.blue,
                                      backgroundColor: Colors.blue.withOpacity(0.12),
                                      height: 30,
                                      padding: EdgeInsets.symmetric(horizontal: 10),
                                      onPressed: () {
                                        setState(() {
                                          selectedOrderId = null;
                                        });
                                      }),
                                    SizedBox(width: 8),
                                    // macOS 26 Fullscreen Button
                                    _buildMacOSFullscreenButton(isLight),
                                  ]))
                            : const SizedBox.shrink())),

                    // Interactive Map Area - immer present
                    Expanded(
                      child: _isMapExpanded
                          ? _buildMapContent(
                              isLight) // No GestureDetector when map is expanded - allow free map interaction
                          : TradeRepublicTap(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                // Expand map when tapped in normal view
                                setState(() {
                                  _isMapExpanded = true;
                                });
                              },
                              child: _buildMapContent(isLight))),
                  ]),

                // Floating Action Buttons - only visible when expanded
                if (_isMapExpanded) _buildFloatingActionButtons(isLight),

                // iOS 26 Dynamic Island with controls and product count
                if (_isMapExpanded) _buildTopRightButtons(isLight),

                // Fullscreen close button (always visible while expanded)
                if (_isMapExpanded) _buildExpandedMapCloseButton(isLight),
              ])))));
  }

  Widget _buildExpandedMapCloseButton(bool isLight) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 12,
      left: 12,
      child: TradeRepublicButton.icon(
        icon: Icon(
          CupertinoIcons.xmark,
          size: 18,
          color: isLight ? Colors.white : Colors.black),
        backgroundColor: isLight
            ? Colors.black.withOpacity(0.85)
            : Colors.white.withOpacity(0.9),
        size: 42,
        onPressed: () {
          HapticFeedback.lightImpact();
          setState(() {
            _isMapExpanded = false;
          });
        }));
  }

  Widget _buildMapContent(bool isLight) {
    if (isLoading) {
      return const Center(child: CultiooLoadingIndicator());
    } else if (error != null) {
      return _buildErrorContent(isLight);
    } else {
      return selectedOrderId != null
          ? _buildOrderDetails(selectedOrderId!, isLight)
          : _buildInteractiveMap(isLight);
    }
  }

  Widget _buildTrafficSummary(bool isLight) {
    // Analyze traffic conditions
    Map<String, int> trafficCounts = {
      'normal': 0,
      'light': 0,
      'moderate': 0,
      'heavy': 0,
    };

    for (var segment in _trafficSegments) {
      String condition = segment['condition'] ?? AppLocalizations.of(context)!.tr('normal');
      trafficCounts[condition] = (trafficCounts[condition] ?? 0) + 1;
    }

    // Determine overall traffic status
    String overallStatus = 'Clear Road';
    Color statusColor = Colors.green;
    IconData statusIcon = CupertinoIcons.speedometer;

    if ((trafficCounts['heavy'] ?? 0) > 0) {
      overallStatus = 'Heavy Traffic Jam';
      statusColor = Colors.red;
      statusIcon = CupertinoIcons.car;
    } else if ((trafficCounts['moderate'] ?? 0) > 2) {
      overallStatus = 'Moderate Traffic';
      statusColor = Colors.orange;
      statusIcon = CupertinoIcons.exclamationmark_triangle;
    } else if ((trafficCounts['light'] ?? 0) > 1) {
      overallStatus = 'Light Traffic';
      statusColor = Colors.yellow.shade700;
      statusIcon = CupertinoIcons.info;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: _isMapExpanded ? 16 : 14),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              overallStatus,
              style: TextStyle(
                fontSize: _isMapExpanded ? 12 : 10,
                fontWeight: FontWeight.w600,
                color: statusColor))),
          // Traffic legend
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((trafficCounts['normal'] ?? 0) > 0)
                _buildTrafficDot(Colors.green, trafficCounts['normal']!),
              if ((trafficCounts['light'] ?? 0) > 0)
                _buildTrafficDot(Colors.yellow, trafficCounts['light']!),
              if ((trafficCounts['moderate'] ?? 0) > 0)
                _buildTrafficDot(Colors.orange, trafficCounts['moderate']!),
              if ((trafficCounts['heavy'] ?? 0) > 0)
                _buildTrafficDot(Colors.red, trafficCounts['heavy']!),
            ]),
        ]));
  }

  Widget _buildTrafficDot(Color color, int count) {
    return Padding(
      padding: EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _isMapExpanded ? 8 : 6,
            height: _isMapExpanded ? 8 : 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          SizedBox(width: 2),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: _isMapExpanded ? 10 : 8,
              color: color,
              fontWeight: FontWeight.w700)),
        ]));
  }

  // Test swipe-to-accept component for debugging

  Widget _buildProductCountBadge(bool isLight) {
    return Positioned(
      left: 16,
      bottom: 80, // Zwischen oberen Controls (140) und unteren Buttons (20)
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        constraints: BoxConstraints(
          maxWidth: _isMapExpanded
              ? MediaQuery.of(context).size.width *
                    0.45 // Kleiner: 60% -> 45%
              : MediaQuery.of(context).size.width * 0.7, // Kleiner: 90% -> 70%
        ),
        padding: EdgeInsets.symmetric(
          horizontal: _isMapExpanded ? 14 : 16, // Kleiner: 20 -> 14/16
          vertical: _isMapExpanded ? 8 : 8, // Kleiner: 12/10 -> 8/8
        ),
        decoration: BoxDecoration(
          // Apple-style liquid glass effect with transparency
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          boxShadow: [
            // Liquid glass shadow
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 8)),
          ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.2),
                    Colors.white.withOpacity(0.05),
                  ])),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(
                      _isMapExpanded ? 4 : 3), // Kleiner: 6/4 -> 4/3
                    decoration: BoxDecoration(
                      gradient: const RadialGradient(
                        colors: [
                          Color(0xFF007AFF), // iOS Blue
                          Color(0xFF0051D5),
                        ]),
                      shape: BoxShape.circle,
                      boxShadow: _isMapExpanded
                          ? [
                              BoxShadow(
                                color: const Color(0xFF007AFF).withOpacity(0.4),
                                blurRadius: 8, // Kleiner: 12 -> 8
                                spreadRadius: 0,
                                offset: const Offset(0, 2), // Kleiner: 4 -> 2
                              ),
                            ]
                          : []),
                    child: Icon(
                      CupertinoIcons.location,
                      color: Colors.white,
                      size: _isMapExpanded ? 14 : 10, // Kleiner: 16/12 -> 14/10
                    )),
                  SizedBox(
                    width: _isMapExpanded ? 12 : 6), // Smaller: 16/8 -> 12/6
                  // Enhanced layout for maximized mode
                  _isMapExpanded
                      ? SizedBox(
                          // Fixed width for optimal size
                          width: 80, // Smaller: 100 -> 80
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _displayRadius.isInfinite
                                    ? 'All'
                                    : Provider.of<AppSettings>(
                                        context).formatDistance(_displayRadius.toDouble()),
                                style: TextStyle(
                                  fontSize: 12, // Kleiner: 14 -> 12
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.95),
                                  letterSpacing: -0.3),
                                overflow: TextOverflow.ellipsis),
                              Row(
                                mainAxisSize: MainAxisSize
                                    .min, // Begrenzt auf minimalen Platz
                                children: [
                                  Text(
                                    '${_filteredOrders.length}',
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize(), // Kleiner: 16 -> 14
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withOpacity(0.9),
                                      letterSpacing: -0.3)),
                                  Flexible(
                                    child: Text(
                                      ' orders',
                                      style: TextStyle(
                                        fontSize: 12, // Kleiner: 14 -> 12
                                        fontWeight: FontWeight.normal,
                                        color: Colors.white.withOpacity(0.8),
                                        letterSpacing: 0),
                                      overflow: TextOverflow.ellipsis)),
                                ]),
                            ]))
                      : Text(
                          _displayRadius.isInfinite
                              ? 'All'
                              : '${Provider.of<AppSettings>(context).formatDistance(_displayRadius.toDouble())} radius',
                          style: TextStyle(
                            fontSize: 11, // Smaller: 12 -> 11
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.87),
                            letterSpacing: 0.2, // Kleiner: 0.3 -> 0.2
                          )),
                ]))))));
  }

  Widget _buildErrorContent(bool isLight) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          CupertinoIcons.xmark_circle,
          size: 80,
          color: Colors.red.withOpacity(0.7)),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
        Text(
          AppLocalizations.of(context)?.errorLoadingOrders ?? AppLocalizations.of(context)!.tr('Error Loading Orders'),
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
            fontWeight: FontWeight.w700,
            color: Colors.red)),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        Text(
          error!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.7))),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
        TradeRepublicButton(
          label: AppLocalizations.of(context)?.retry ?? AppLocalizations.of(context)!.tr('Retry'),
          onPressed: _initializeMapsAccess),
      ]);
  }

  Widget _buildFloatingActionButtons(bool isLight) {
    return Positioned(
      right: 16,
      bottom: Platform.isAndroid ? 100 : 75,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutQuart,
        opacity: _isMapExpanded ? 1.0 : 0.0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuint,
          offset: _isMapExpanded ? const Offset(0, 0) : const Offset(1, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Zoom in
              _buildGlassButton(
                isLight: isLight,
                icon: CupertinoIcons.plus,
                iconColor: isLight ? Colors.black87 : Colors.white,
                onTap: () => _zoomMap(1.0)),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

              // Zoom out
              _buildGlassButton(
                isLight: isLight,
                icon: CupertinoIcons.minus,
                iconColor: isLight ? Colors.black87 : Colors.white,
                onTap: () => _zoomMap(-1.0)),
              SizedBox(height: 10),

              // My Location – frosted glass, blauer Akzent
              _buildGlassButton(
                isLight: isLight,
                icon: CupertinoIcons.location_fill,
                iconColor: const Color(0xFF007AFF),
                bgColor: isLight
                    ? Colors.blue.withOpacity(0.12)
                    : Colors.blue.withOpacity(0.22),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showCurrentLocation();
                }),
              SizedBox(height: 10),

              // Settings – frosted glass, neutral
              _buildGlassButton(
                isLight: isLight,
                icon: CupertinoIcons.settings,
                iconColor: isLight ? Colors.black87 : Colors.white,
                bgColor: isLight
                    ? Colors.white.withOpacity(0.72)
                    : Colors.white.withOpacity(0.14),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showSettingsModal();
                }),

              // Clear Route – nur sichtbar wenn Route aktiv
              if (_routePoints.isNotEmpty) ...[
                SizedBox(height: 10),
                _buildGlassButton(
                  isLight: isLight,
                  icon: CupertinoIcons.xmark,
                  iconColor: const Color(0xFFFF9F0A),
                  bgColor: isLight
                      ? Colors.orange.withOpacity(0.12)
                      : Colors.orange.withOpacity(0.22),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _routePoints.clear();
                      _trafficSegments.clear();
                      _showRouteInfo = false;
                      _activeRouteInfo = null;
                    });
                    hideDockNotifier.value = false;
                    activeOrderNotifier.value = null;
                    TopNotification.info(context, AppLocalizations.of(context)?.routeCleared ?? AppLocalizations.of(context)!.tr('Route cleared'));
                  }),
              ],

              SizedBox(height: 10),

              // Refresh – frosted glass, green accent
              _buildGlassButton(
                isLight: isLight,
                icon: CupertinoIcons.refresh,
                iconColor: isLight
                    ? const Color(0xFF34C759)
                    : const Color(0xFF30D158),
                bgColor: isLight
                    ? Colors.green.withOpacity(0.12)
                    : Colors.green.withOpacity(0.22),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _loadOrders();
                }),
            ]))));
  }

  // ── Zoom helpers ──────────────────────────────────────────────────────────

  void _zoomMap(double delta) {
    HapticFeedback.lightImpact();
    if (Platform.isIOS && _appleMapController != null) {
      final targetZoom = (_appleMapZoomLevel + delta).clamp(1.0, 20.0);
      _appleMapZoomLevel = targetZoom;
      _appleMapController!.animateCamera(apple.CameraUpdate.zoomTo(targetZoom));
    } else if (_use3DMap && _mapboxMap != null) {
      _mapboxMap!.getCameraState().then((state) {
        _mapboxMap!.easeTo(
          mapbox.CameraOptions(zoom: (state.zoom + delta).clamp(1.0, 22.0)),
          mapbox.MapAnimationOptions(duration: 250));
      });
    } else {
      try {
        final cam = _mapController.camera;
        _mapController.move(cam.center, (cam.zoom + delta).clamp(1.0, 22.0));
      } catch (_) {}
    }
  }


  // Close button methods removed - using swipe gestures for dismissal

  // All close button methods removed - using swipe gestures for modal dismissal

  // macOS 26 Fullscreen Button
  Widget _buildMacOSFullscreenButton(bool isLight) {
    return TradeRepublicButton.icon(
      icon: Icon(
        CupertinoIcons.fullscreen,
        size: 18,
        color: isLight ? Colors.white : Colors.white.withOpacity(0.9)),
      backgroundColor: isLight
          ? Colors.black.withOpacity(0.85)
          : Colors.white.withOpacity(0.15),
      size: 40,
      onPressed: () {
        HapticFeedback.mediumImpact();
        setState(() {
          _isMapExpanded = true;
        });
      });
  }

  // Solid glass-style button for floating actions
  Widget _buildGlassButton({
    required bool isLight,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    Color? bgColor,
    double size = 44,
  }) {
    final bg = bgColor ??
        (isLight ? Colors.white.withOpacity(0.72) : Colors.white.withOpacity(0.12));
    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: TradeRepublicTap(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: const Offset(0, 4)),
              ]),
            child: Center(
              child: Icon(icon, size: size * 0.45, color: iconColor))))));
  }

  // Navigation Badge Button - shows when navigation is active
  Widget _buildNavigationBadgeButton(bool isLight) {
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.mediumImpact();
        // Navigation functionality moved to orders page
      },
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 6)),
                BoxShadow(
                  color: Colors.white.withOpacity(isLight ? 0.9 : 0.6),
                  blurRadius: 1,
                  spreadRadius: -1,
                  offset: const Offset(-1, -1)),
              ]),
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                  ]),
                child: Center(
                  child: Text(
                    '1',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w700)))))))));
  }

  Widget _buildInteractiveMap(bool isLight) {
    return _isMapExpanded
        ? _buildFullScreenMap(isLight) // Full screen without any wrappers
        : ClipRRect(
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            child: Stack(
              children: [
                // Background
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: isLight ? Colors.white : Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.map,
                          size: 64,
                          color: isLight
                              ? Colors.black.withOpacity(0.3)
                              : Colors.white.withOpacity(0.3)),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                        Text(
                          AppLocalizations.of(context)?.interactiveMap ?? AppLocalizations.of(context)!.tr('Interactive Map'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                            color: isLight ? Colors.black : Colors.white,
                            fontFamily: 'Poppins')),
                        Text(
                          AppLocalizations.of(context)?.loadingMapTiles ?? AppLocalizations.of(context)!.tr('Loading map tiles...'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            color: isLight ? Colors.black : Colors.white,
                            fontFamily: 'Poppins')),
                      ]))),

                // Actual Map - with gesture detection for route modal
                TradeRepublicTap(
                  // Add tap gesture detection to minimize route info modal
                  onTap: () {
                    if (_showRouteInfo && !_isRouteInfoMinimized) {
                      print(
                        '🗺️ Tap detected on normal map - minimizing route info');
                      setState(() {
                        _isRouteInfoMinimized = true;
                      });
                      HapticFeedback.lightImpact();
                    }
                  },
                  // Add pan gesture detection to minimize route info modal
                  onPanStart: (details) {
                    if (_showRouteInfo && !_isRouteInfoMinimized) {
                      print(
                        '🗺️ Pan gesture started on normal map - minimizing route info');
                      setState(() {
                        _isRouteInfoMinimized = true;
                      });
                      HapticFeedback.lightImpact();
                    }
                  },
                  // Also trigger on any pan movement
                  onPanDown: (details) {
                    if (_showRouteInfo && !_isRouteInfoMinimized) {
                      print(
                        '🗺️ Pan down detected on normal map - minimizing route info');
                      setState(() {
                        _isRouteInfoMinimized = true;
                      });
                      HapticFeedback.lightImpact();
                    }
                  },
                  // Add swipe gesture detection
                  onPanUpdate: (details) {
                    // Detect downward swipe
                    if (details.delta.dy > 8 &&
                        _showRouteInfo &&
                        !_isRouteInfoMinimized) {
                      print(
                        '🗺️ Swipe down detected on normal map - minimizing route info');
                      setState(() {
                        _isRouteInfoMinimized = true;
                      });
                      HapticFeedback.lightImpact();
                    }
                    // Detect upward swipe to expand route info modal
                    else if (details.delta.dy < -8 &&
                        _showRouteInfo &&
                        _isRouteInfoMinimized) {
                      print(
                        '🗺️ Swipe up detected on normal map - expanding route info');
                      setState(() {
                        _isRouteInfoMinimized = false;
                      });
                      HapticFeedback.lightImpact();
                    }
                  },
                  child: FlutterMap(
                    key: ValueKey(
                      'flutter_map_${isLight ? 'light' : 'dark'}'), // Force rebuild on theme change
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          currentLocation ?? const LatLng(51.3571486, 6.638026),
                      initialZoom: _zoomLevel,
                      minZoom: 3.0,
                      maxZoom: 18.0,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                      // Add interaction callbacks to minimize route info when map is interacted with
                      onMapEvent: (MapEvent mapEvent) {
                        print(
                          '🗺️ [NORMAL MAP] Map event: ${mapEvent.runtimeType}');
                        print(
                          '🗺️ [NORMAL MAP] _showRouteInfo: $_showRouteInfo');
                        print(
                          '🗺️ [NORMAL MAP] _isRouteInfoMinimized: $_isRouteInfoMinimized');
                        print(
                          '🗺️ [NORMAL MAP] _activeRouteInfo != null: ${_activeRouteInfo != null}');

                        // Minimize route info on any map interaction
                        if (_showRouteInfo &&
                            !_isRouteInfoMinimized &&
                            _activeRouteInfo != null) {
                          if (mapEvent is MapEventMove ||
                              mapEvent is MapEventRotate ||
                              mapEvent is MapEventFlingAnimation ||
                              mapEvent is MapEventDoubleTapZoom ||
                              mapEvent is MapEventScrollWheelZoom) {
                            print(
                              '🗺️ [NORMAL MAP] ✅ MINIMIZING route info - event: ${mapEvent.runtimeType}');
                            setState(() {
                              _isRouteInfoMinimized = true;
                            });
                            HapticFeedback.lightImpact();
                          } else {
                            print(
                              '🗺️ [NORMAL MAP] ❌ Event type not handled: ${mapEvent.runtimeType}');
                          }
                        } else {
                          print(
                            '🗺️ [NORMAL MAP] ❌ Conditions not met for minimizing');
                        }
                      },
                      onTap: (tapPosition, point) {
                        // Handle map taps - toggle route info minimized state when map is tapped
                        if (_showRouteInfo) {
                          setState(() {
                            _isRouteInfoMinimized = !_isRouteInfoMinimized;
                          });
                        }
                      },
                      onMapReady: () {
                        // Mark map as ready
                        setState(() {
                          _isMapReady = true;
                        });
                      },
                      onPositionChanged: (position, hasGesture) {
                        // Auto-minimize route modal when user starts scrolling/panning/zooming the map
                        if (hasGesture &&
                            mounted &&
                            _isMapReady &&
                            _showRouteInfo &&
                            !_isRouteInfoMinimized) {
                          print(
                            '🗺️ Normal map position changed - auto-minimizing route info');
                          setState(() {
                            _isRouteInfoMinimized = true;
                          });
                          HapticFeedback.selectionClick();
                        }

                        // Only rebuild markers when zoom changes significantly to update clustering
                        if (hasGesture && mounted && _isMapReady) {
                          double currentZoom = position.zoom;

                          // Only update if zoom changed by more than 0.5 levels
                          if ((currentZoom - _lastZoomLevel).abs() > 0.5) {
                            _lastZoomLevel = currentZoom;
                            setState(() {
                              // This will trigger _buildClusteredMarkers() to recalculate
                            });
                          }
                        }
                      }),
                    children: [
                      // Theme-aware tile layer with glass effect when expanded
                      TileLayer(
                        key: ValueKey(
                          'carto_${isLight ? 'light' : 'dark'}'), // Force rebuild on theme change
                        urlTemplate: (() {
                          final url = isLight
                              ? MapTileConfig.lightUrl
                              : MapTileConfig.darkUrl;
                          print(
                            '🗺️ Map URL (${isLight ? 'light' : 'dark'}): $url');
                          return url;
                        })(),
                        subdomains: MapTileConfig.subdomains,
                        userAgentPackageName: 'com.cultioo.business',
                        maxZoom: 20,
                        retinaMode: true,
                        // Modern Apple-style map with glass effect when expanded
                        tileBuilder: (context, tileWidget, tile) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            child: _isMapExpanded
                                ? Opacity(
                                    // Reduced opacity for glass effect when expanded
                                    opacity: 0.85,
                                    child: ColorFiltered(
                                      // Slight desaturation for glass effect when expanded
                                      colorFilter: ColorFilter.matrix([
                                        0.9, 0.05, 0.05, 0, 0, // Red channel
                                        0.05, 0.9, 0.05, 0, 0, // Green channel
                                        0.05, 0.05, 0.9, 0, 0, // Blue channel
                                        0, 0, 0, 1, 0, // Alpha channel
                                      ]),
                                      child: tileWidget))
                                : tileWidget);
                        }),

                      // Search radius circle
                      if (currentLocation != null && !_searchRadius.isInfinite)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: currentLocation!,
                              radius: _searchRadius * 1000,
                              useRadiusInMeter: true,
                              borderStrokeWidth: 2.0,
                              borderColor: Colors.blue.withOpacity(0.6),
                              color: Colors.blue.withOpacity(0.1)),
                          ]),

                      // Search radius circle - only show when map is expanded
                      if (_isMapExpanded && currentLocation != null && !_searchRadius.isInfinite)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: currentLocation!,
                              radius:
                                  _searchRadius * 1000, // Convert km to meters
                              borderColor: Colors.blue.withOpacity(0.6),
                              color: Colors.blue.withOpacity(0.1),
                              borderStrokeWidth: 2.0,
                              useRadiusInMeter: true),
                          ]),

                      // Route polyline layer with traffic coloring
                      // Route polylines - show whenever route points are available
                      if (_routePoints.isNotEmpty)
                        PolylineLayer(polylines: _buildTrafficAwarePolylines()),

                      // Markers
                      MarkerLayer(
                        markers: [
                          // Debug: Print route points info when building markers
                          if (_routePoints.isNotEmpty)
                            ...() {
                              print(
                                '🎨 BUILDING MARKERS: ${_routePoints.length} route points');
                              print(
                                '📍 First point: ${_routePoints.first.latitude}, ${_routePoints.first.longitude}');
                              print(
                                '🎯 Last point: ${_routePoints.last.latitude}, ${_routePoints.last.longitude}');
                              return <Marker>[];
                            }(),

                          // Standard blue location indicator (hide when route is active)
                          if (currentLocation != null && _routePoints.isEmpty)
                            Marker(
                              point: currentLocation!,
                              width: 12,
                              height: 12,
                              child: _buildAppleLocationIndicator(isLight)),

                          // Clustered product markers - only when no route active
                          if (_routePoints.isEmpty) ..._buildClusteredMarkers(isLight),

                          // Route markers: You (blue) → Pickup (gold) → Delivery (green)
                          if (_routePoints.length >= 2) ...[
                            // You marker (current location) - blue GPS dot style
                            Marker(
                              point: _routePoints.first,
                              width: 22,
                              height: 22,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF007AFF), Color(0xFF0051D5)]),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF007AFF).withOpacity(0.45),
                                      blurRadius: 8,
                                      spreadRadius: 2),
                                  ]))),

                            // Pickup marker - solid yellow triangle
                            if (_activeRouteInfo?['pickupLocation'] != null)
                              Marker(
                                point: _activeRouteInfo!['pickupLocation'] as LatLng,
                                width: 22,
                                height: 22,
                                child: CustomPaint(
                                  painter: _SolidTrianglePainter(color: const Color(0xFFFFC107)),
                                  size: const Size(22, 22))),

                            // Delivery marker - solid green rectangle
                            Marker(
                              point: _routePoints.last,
                              width: 20,
                              height: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4CAF50).withOpacity(0.5),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                      offset: const Offset(0, 2)),
                                  ]))),
                          ],
                        ]),
                    ])), // Closing bracket for GestureDetector

                if (isLoading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        // Glass effect for loading overlay when map expanded
                        color: _isMapExpanded
                            ? (isLight ? Colors.white : Colors.black)
                                  .withOpacity(0.15)
                            : (isLight ? Colors.white : Colors.black)
                                  .withOpacity(0.7),
                        backgroundBlendMode: _isMapExpanded
                            ? BlendMode.overlay
                            : null),
                      child: const Center(child: CultiooLoadingIndicator()))),

                // Show "No Orders" overlay when no orders are available
                if (!isLoading && error == null && _filteredOrders.isEmpty)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        // Glass effect for no orders overlay when map expanded
                        color: _isMapExpanded
                            ? (isLight ? Colors.white : Colors.black)
                                  .withOpacity(0.08)
                            : (isLight ? Colors.white : Colors.black)
                                  .withOpacity(0.3),
                        backgroundBlendMode: _isMapExpanded
                            ? BlendMode.overlay
                            : null),
                      child: Center(
                        child: Container(
                          margin: EdgeInsets.all(20),
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            // Enhanced glass effect for the container when map expanded
                            color: _isMapExpanded
                                ? (isLight ? Colors.white : Colors.black)
                                      .withOpacity(0.35)
                                : (isLight ? Colors.white : Colors.black)
                                      .withOpacity(0.95),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  _isMapExpanded ? 0.05 : 0.1),
                                blurRadius: _isMapExpanded ? 15 : 20,
                                spreadRadius: _isMapExpanded ? 1 : 2,
                                offset: const Offset(0, 4)),
                            ]),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.location_slash,
                                size: 60,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.5)),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                              Text(
                                AppLocalizations.of(context)?.noPickupOrders ?? AppLocalizations.of(context)!.tr('No Pickup Orders'),
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                  fontWeight: FontWeight.w700,
                                  color: isLight ? Colors.black : Colors.white,
                                  fontFamily: 'Poppins')),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                              Text(
                                _searchRadius.isInfinite
                                    ? (AppLocalizations.of(context)?.noDelviooOrdersForPickup('All') ?? AppLocalizations.of(context)!.tr('No delvioo orders available for pickup'))
                                    : (AppLocalizations.of(context)?.noDelviooOrdersForPickup(Provider.of<AppSettings>(context).formatDistance(_searchRadius.toDouble())) ?? 'No delvioo orders available for pickup\nwithin ${Provider.of<AppSettings>(context).formatDistance(_searchRadius.toDouble())} of your location'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.7),
                                  fontFamily: 'Poppins')),
                            ]))))),
                // Glass overlay removed - was blocking touch events when map is expanded
              ]));
  }

  // Full screen map without any ClipRRect or decorative wrappers that could block touch events
  Widget _buildFullScreenMap(bool isLight) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        TradeRepublicTap(
          // Add tap gesture detection to minimize route info modal
          onTap: () {
            if (_showRouteInfo && !_isRouteInfoMinimized) {
              print(
                '🗺️ Tap detected on fullscreen map - minimizing route info');
              setState(() {
                _isRouteInfoMinimized = true;
              });
              HapticFeedback.lightImpact();
            }
          },
          // Add pan gesture detection to minimize route info modal
          onPanStart: (details) {
            if (_showRouteInfo && !_isRouteInfoMinimized) {
              print(
                '🗺️ Pan gesture started on fullscreen map - minimizing route info');
              setState(() {
                _isRouteInfoMinimized = true;
              });
              HapticFeedback.lightImpact();
            }
          },
          // Also trigger on any pan movement
          onPanDown: (details) {
            if (_showRouteInfo && !_isRouteInfoMinimized) {
              print(
                '🗺️ Pan down detected on fullscreen map - minimizing route info');
              setState(() {
                _isRouteInfoMinimized = true;
              });
              HapticFeedback.lightImpact();
            }
          },
          // Add swipe down gesture to minimize route info modal
          onPanUpdate: (details) {
            // Detect downward swipe
            if (details.delta.dy > 8 &&
                _showRouteInfo &&
                !_isRouteInfoMinimized) {
              print('🗺️ Swipe down detected - minimizing route info');
              setState(() {
                _isRouteInfoMinimized = true;
              });
              HapticFeedback.lightImpact();
            }
            // Detect upward swipe to expand route info modal
            else if (details.delta.dy < -8 &&
                _showRouteInfo &&
                _isRouteInfoMinimized) {
              print('🗺️ Swipe up detected - expanding route info');
              setState(() {
                _isRouteInfoMinimized = false;
              });
              HapticFeedback.lightImpact();
            }
          },
          child: FlutterMap(
            key: ValueKey(
              'fullscreen_map_${isLight ? 'light' : 'dark'}'), // Force rebuild on theme change
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  currentLocation ?? const LatLng(51.3571486, 6.638026),
              initialZoom: _zoomLevel,
              minZoom: 3.0,
              maxZoom: 18.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              // Add interaction callbacks to minimize route info when map is interacted with
              onMapEvent: (MapEvent mapEvent) {
                print(
                  '🗺️ [FULLSCREEN MAP] Map event: ${mapEvent.runtimeType}');
                print('🗺️ [FULLSCREEN MAP] _showRouteInfo: $_showRouteInfo');
                print(
                  '🗺️ [FULLSCREEN MAP] _isRouteInfoMinimized: $_isRouteInfoMinimized');
                print(
                  '🗺️ [FULLSCREEN MAP] _activeRouteInfo != null: ${_activeRouteInfo != null}');

                // Minimize route info on any map interaction
                if (_showRouteInfo &&
                    !_isRouteInfoMinimized &&
                    _activeRouteInfo != null) {
                  if (mapEvent is MapEventMove ||
                      mapEvent is MapEventRotate ||
                      mapEvent is MapEventFlingAnimation ||
                      mapEvent is MapEventDoubleTapZoom ||
                      mapEvent is MapEventScrollWheelZoom) {
                    print(
                      '🗺️ [FULLSCREEN MAP] ✅ MINIMIZING route info - event: ${mapEvent.runtimeType}');
                    setState(() {
                      _isRouteInfoMinimized = true;
                    });
                    HapticFeedback.lightImpact();
                  } else {
                    print(
                      '🗺️ [FULLSCREEN MAP] ❌ Event type not handled: ${mapEvent.runtimeType}');
                  }
                } else {
                  print(
                    '🗺️ [FULLSCREEN MAP] ❌ Conditions not met for minimizing');
                }
              },
              onTap: (tapPosition, point) {
                // Handle map taps - toggle route info minimized state when map is tapped
                if (_showRouteInfo) {
                  setState(() {
                    _isRouteInfoMinimized = !_isRouteInfoMinimized;
                  });
                  HapticFeedback.lightImpact();
                  return;
                }

                // Check if tap is on any order marker by searching nearby
                LatLng tapLatLng = point;

                // Find if there's an order near the tap location (within 500m)
                for (var order in _filteredOrders) {
                  LatLng? orderLocation = _getPickupCoordinatesSync(order);
                  if (orderLocation != null) {
                    double distance = Geolocator.distanceBetween(
                      tapLatLng.latitude,
                      tapLatLng.longitude,
                      orderLocation.latitude,
                      orderLocation.longitude);

                    // If tap is within 500m of an order, show the modal
                    if (distance <= 500) {
                      // _showOrderModal(order, orderLocation);
                      return;
                    }
                  }
                }
              },
              onMapReady: () {
                // Mark map as ready
                setState(() {
                  _isMapReady = true;
                });
              },
              onPositionChanged: (position, hasGesture) {
                // Auto-minimize route modal when user starts scrolling/panning/zooming the map
                if (hasGesture &&
                    mounted &&
                    _isMapReady &&
                    _showRouteInfo &&
                    !_isRouteInfoMinimized) {
                  print(
                    '🗺️ Full screen map position changed - auto-minimizing route info');
                  setState(() {
                    _isRouteInfoMinimized = true;
                  });
                  HapticFeedback.selectionClick();
                }

                // Only rebuild markers when zoom changes significantly to update clustering
                if (hasGesture && mounted && _isMapReady) {
                  double currentZoom = position.zoom;

                  // Only update if zoom changed by more than 0.5 levels
                  if ((currentZoom - _lastZoomLevel).abs() > 0.5) {
                    _lastZoomLevel = currentZoom;
                    setState(() {
                      // This will trigger _buildClusteredMarkers() to recalculate
                    });
                  }
                }
              }),
            children: [
              // Theme-aware tile layer with glass effect when expanded
              TileLayer(
                key: ValueKey(
                  'carto_fullscreen_${isLight ? 'light' : 'dark'}'), // Force rebuild on theme change
                urlTemplate: (() {
                  final url = isLight
                      ? MapTileConfig.lightUrl
                      : MapTileConfig.darkUrl;
                  print(
                    '🗺️ Fullscreen Map URL (${isLight ? 'light' : 'dark'}): $url');
                  return url;
                })(),
                subdomains: MapTileConfig.subdomains,
                userAgentPackageName: 'com.cultioo.business',
                maxZoom: 20,
                retinaMode: true,
                // Modern Apple-style map with glass effect when expanded
                tileBuilder: (context, tileWidget, tile) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    child: Opacity(
                      // Reduced opacity for glass effect when expanded
                      opacity: 0.85,
                      child: ColorFiltered(
                        // Slight desaturation for glass effect when expanded
                        colorFilter: ColorFilter.matrix([
                          0.9, 0.05, 0.05, 0, 0, // Red channel
                          0.05, 0.9, 0.05, 0, 0, // Green channel
                          0.05, 0.05, 0.9, 0, 0, // Blue channel
                          0, 0, 0, 1, 0, // Alpha channel
                        ]),
                        child: tileWidget)));
                }),

              // Search radius circle - only show in maximized mode
              if (currentLocation != null && !_searchRadius.isInfinite)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: currentLocation!,
                      radius: _searchRadius * 1000, // Convert km to meters
                      useRadiusInMeter: true,
                      color: Colors.blue.withOpacity(0.1),
                      borderColor: Colors.blue.withOpacity(0.6),
                      borderStrokeWidth: 2.0),
                  ]),

              // Route polylines - only show when map is expanded
              if (_routePoints.isNotEmpty)
                PolylineLayer(polylines: _buildTrafficAwarePolylines()),

              // Markers
              MarkerLayer(
                markers: [
                  // Debug: Print route points info when building fullscreen markers
                  if (_routePoints.isNotEmpty)
                    ...() {
                      print(
                        '🎨 FULLSCREEN MARKERS: ${_routePoints.length} route points');
                      print(
                        '📍 Fullscreen First point: ${_routePoints.first.latitude}, ${_routePoints.first.longitude}');
                      print(
                        '🎯 Fullscreen Last point: ${_routePoints.last.latitude}, ${_routePoints.last.longitude}');
                      return <Marker>[];
                    }(),

                  // Simple blue location indicator (hide when route is active)
                  if (currentLocation != null && _routePoints.isEmpty)
                    Marker(
                      point: currentLocation!,
                      width: 12,
                      height: 12,
                      child: _buildAppleLocationIndicator(isLight)),

                  // Clustered product markers - only when no route active
                  if (_routePoints.isEmpty) ..._buildClusteredMarkers(isLight),

                  // Route markers: You (blue) → Pickup (gold) → Delivery (green)
                  // IMPORTANT: Rendered AFTER product markers to ensure they're on top
                  if (_routePoints.length >= 2) ...[
                    // You marker (current location) - blue GPS dot style
                    Marker(
                      point: _routePoints.first,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF007AFF), Color(0xFF0051D5)]),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF007AFF).withOpacity(0.45),
                              blurRadius: 8,
                              spreadRadius: 2),
                          ]))),

                    // Pickup marker - solid yellow triangle
                    if (_activeRouteInfo?['pickupLocation'] != null)
                      Marker(
                        point: _activeRouteInfo!['pickupLocation'] as LatLng,
                        width: 22,
                        height: 22,
                        child: CustomPaint(
                          painter: _SolidTrianglePainter(color: const Color(0xFFFFC107)),
                          size: const Size(22, 22))),

                    // Delivery marker - solid green rectangle
                    Marker(
                      point: _routePoints.last,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4CAF50).withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 1,
                              offset: const Offset(0, 2)),
                          ]))),
                  ],
                ]),
            ])),

        // Close button on top right when route is displayed
        if (_routePoints.isNotEmpty)
          Positioned(
            top: topPadding + 16,
            right: 20,
            child: TradeRepublicButton.icon(
              icon: Icon(
                CupertinoIcons.xmark,
                color: isLight ? Colors.white : Colors.black,
                size: 20),
              backgroundColor: isLight ? Colors.black : Colors.white,
              size: 44,
              onPressed: () {
                HapticFeedback.mediumImpact();
                setState(() {
                  _routePoints.clear();
                  _trafficSegments.clear();
                  _activeRouteInfo = null;
                  _showRouteInfo = false;
                  _isRouteInfoMinimized = false;
                  _isMapExpanded = false;
                });
                hideDockNotifier.value = false;
              })),
      ]);
  }

  Widget _buildOrderDetails(String orderId, bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final order = _filteredOrders.firstWhere(
      (o) => o['id'].toString() == orderId);

    // Parse API transformed format
    final delivery = order['delivery'] as Map<String, dynamic>?;
    final customer = order['customer'] as Map<String, dynamic>?;
    final items = List<Map<String, dynamic>>.from(order['items'] ?? []);

    // DEBUG: Print delivery data
    print('🔍 _buildOrderDetails for order $orderId');
    print('📦 Order keys: ${order.keys.toList()}');
    print('🏠 Delivery object: $delivery');
    print('📍 Delivery fields:');
    print('   street: ${delivery?['street']}');
    print('   house_number: ${delivery?['house_number']}');
    print('   postal_code: ${delivery?['postal_code']}');
    print('   city: ${delivery?['city']}');
    print('   country: ${delivery?['country']}');

    // Get pickup address for display
    final pickupAddress = _getPickupAddressFromOrder(order);
    final deliveryAddress = _getDeliveryAddressFromOrder(order);

    // Safety check for required data - check for items and delivery
    if (items.isEmpty || delivery == null) {
      return Container(
        padding: EdgeInsets.all(0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.xmark_circle,
              size: 60,
              color: Colors.red.withOpacity(0.7)),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            Text(
              AppLocalizations.of(context)?.orderDataIncomplete ?? AppLocalizations.of(context)!.tr('Order Data Incomplete'),
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                fontWeight: FontWeight.w700,
                color: isLight ? Colors.black : Colors.white)),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Text(
              AppLocalizations.of(context)?.missingLocationInfo ?? AppLocalizations.of(context)!.tr('Missing location information for this order.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.7))),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.backToMap ?? AppLocalizations.of(context)!.tr('Back to Map'),
              onPressed: () {
                setState(() {
                  selectedOrderId = null;
                });
              }),
          ]));
    }

    // Get shipping cost (driver's earning)
    final shippingCost = _toDouble(order['shipping_cost']);

    // Get total item quantity from orders table
    final totalQuantity = _toDouble(order['total_quantity']).toInt();

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: Platform.isIOS
            ? ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30)
            : ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Container(
          decoration: BoxDecoration(
            color: Platform.isIOS
                ? (isLight
                      ? Colors.white.withOpacity(0.85)
                      : Colors.black.withOpacity(0.7))
                : (isLight ? Colors.white : Colors.black),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            80), // Added extra bottom padding
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(), // Better scrolling physics
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button and title
                Row(
                  children: [
                    TradeRepublicButton.icon(
                      icon: Icon(
                        CupertinoIcons.chevron_left,
                        size: 18,
                        color: isLight ? Colors.black : Colors.white),
                      backgroundColor: isLight ? Colors.white : Colors.black,
                      size: 40,
                      isSecondary: true,
                      onPressed: () {
                        setState(() {
                          selectedOrderId = null;
                        });
                      }),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}${order["order_id"]}',
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          fontFamily: 'Poppins'))),
                  ]),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Driver Earning Card - Prominent Display
                Container(
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isLight
                          ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                          : [const Color(0xFF388E3C), const Color(0xFF4CAF50)]),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 8)),
                    ]),
                  child: Row(
                    children: [
                      // Money Icon
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle),
                        child: Icon(
                          CupertinoIcons.money_dollar_circle,
                          color: Colors.white,
                          size: 32)),
                      SizedBox(width: 16),
                      // Earning Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'YOUR EARNING • $totalQuantity ${totalQuantity == 1 ? 'ITEM' : 'ITEMS'}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2)),
                            SizedBox(height: 4),
                            Text(
                              appSettings.formatCurrency(shippingCost),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5)),
                          ])),
                      // Arrow Icon
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: Colors.white,
                        size: 20),
                    ])),
                SizedBox(height: 20),

                // Customer info
                Container(
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color:
                        (isLight ? Colors.blue.shade50 : Colors.blue.shade900)
                            .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppLocalizations.of(context)?.customerLabel ?? AppLocalizations.of(context)!.tr('Customer')}: ${customer?['name'] ?? order['username'] ?? AppLocalizations.of(context)!.tr('Unknown')}',
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white)),
                      SizedBox(height: 4),
                      Text(
                        '${AppLocalizations.of(context)?.orderDate ?? AppLocalizations.of(context)!.tr('Order Date')}: ${order['date']?.toString().split('T')[0] ?? AppLocalizations.of(context)!.tr('Unknown')}',
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.7))),
                    ])),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Shipping Type Info - Important for drivers!
                Container(
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color: _getShippingTypeColor(
                      order['shipping_type']).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Row(
                    children: [
                      // Icon for shipping type
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _getShippingTypeColor(order['shipping_type']),
                          shape: BoxShape.circle),
                        child: Icon(
                          _getShippingTypeIcon(order['shipping_type']),
                          color: Colors.white,
                          size: 24)),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)?.shippingType ?? AppLocalizations.of(context)!.tr('Shipping type'),
                              style: TextStyle(
                                fontSize: 12,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6),
                                fontWeight: FontWeight.w500)),
                            SizedBox(height: 4),
                            Text(
                              _getShippingTypeName(order['shipping_type']),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w700,
                                color: isLight ? Colors.black : Colors.white)),
                            SizedBox(height: 2),
                            Text(
                              _getShippingTypeDescription(
                                order['shipping_type']),
                              style: TextStyle(
                                fontSize: 12,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6))),
                          ])),
                    ])),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Locations info
                Text(
                  AppLocalizations.of(context)?.pickupLocation ?? AppLocalizations.of(context)!.tr('Pickup Location:'),
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white)),
                Text(
                  pickupAddress,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7))),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                // Delivery location
                Text(
                  AppLocalizations.of(context)?.deliveryLocation ?? AppLocalizations.of(context)!.tr('Delivery Location:'),
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white)),
                Text(
                  deliveryAddress,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7))),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Items list
                Text(
                  '${AppLocalizations.of(context)?.items ?? AppLocalizations.of(context)!.tr('Items')} (${items.length}):',
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white)),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                // Build each item container
                ...List.generate(items.length, (index) {
                  final item = items[index];
                  return Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: (isLight ? Colors.white : Colors.black)
                          .withOpacity(0.5),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product name and price
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item['name'] ??
                                  (AppLocalizations.of(context)
                                      ?.unknownProduct ?? AppLocalizations.of(context)!.tr('')),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isLight ? Colors.black : Colors.white))),
                            Consumer<AppSettings>(
                              builder: (context, appSettings, _) => Text(
                                appSettings.formatCurrency(
                                  appSettings.convertCurrency(
                                    double.tryParse(
                                          item['price']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                                        0.0)),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green))),
                          ]),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                        // Quantity
                        Text(
                          '${AppLocalizations.of(context)?.quantity ?? AppLocalizations.of(context)!.tr('Quantity')}: ${item['quantity'] ?? 1}x',
                          style: TextStyle(
                            fontSize: 13,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.7))),

                        // Category (if available)
                        if (item['category'] != null &&
                            item['category'].toString().isNotEmpty &&
                            item['category'] != 'General') ...[
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                CupertinoIcons.square_grid_2x2,
                                size: 14,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6)),
                              SizedBox(width: 6),
                              Text(
                                '${AppLocalizations.of(context)?.category ?? AppLocalizations.of(context)!.tr('Category')}: ${item['category']}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.7))),
                            ]),
                        ],
                      ]));
                }),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                // Order-level metadata (batch, production, best before, seller notes)
                if (order['batch_number'] != null &&
                    order['batch_number'].toString().isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          (isLight ? Colors.blue.shade50 : Colors.blue.shade900)
                              .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.qrcode,
                          size: 16,
                          color: isLight
                              ? Colors.blue.shade700
                              : Colors.blue.shade300),
                        SizedBox(width: 8),
                        Text(
                          '${AppLocalizations.of(context)?.batch ?? AppLocalizations.of(context)!.tr('Batch')}: ${order['batch_number']}',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white)),
                      ])),

                if (order['production_date'] != null &&
                    order['production_date'].toString().isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          (isLight
                                  ? Colors.purple.shade50
                                  : Colors.purple.shade900)
                              .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.building_2_fill,
                          size: 16,
                          color: isLight
                              ? Colors.purple.shade700
                              : Colors.purple.shade300),
                        SizedBox(width: 8),
                        Text(
                          '${AppLocalizations.of(context)?.production ?? AppLocalizations.of(context)!.tr('Production')}: ${_formatDate(order['production_date'])}',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white)),
                      ])),

                if (order['best_before_date'] != null &&
                    order['best_before_date'].toString().isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          (isLight
                                  ? Colors.orange.shade50
                                  : Colors.orange.shade900)
                              .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.calendar,
                          size: 16,
                          color: _getExpiryColor(order['best_before_date'])),
                        SizedBox(width: 8),
                        Text(
                          '${AppLocalizations.of(context)?.bestBefore ?? AppLocalizations.of(context)!.tr('Best Before')}: ${_formatDate(order['best_before_date'])}',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: _getExpiryColor(order['best_before_date']))),
                      ])),

                if (order['seller_notes'] != null &&
                    order['seller_notes'].toString().isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          (isLight
                                  ? Colors.amber.shade50
                                  : Colors.amber.shade900)
                              .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          CupertinoIcons.doc_text,
                          size: 16,
                          color: isLight
                              ? Colors.amber.shade700
                              : Colors.amber.shade300),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${AppLocalizations.of(context)?.sellerNotes ?? AppLocalizations.of(context)!.tr('Seller Notes')}: ${order['seller_notes']}',
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black : Colors.white))),
                      ])),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                // Shipping price
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.shippingPrice ?? AppLocalizations.of(context)!.tr('Shipping Price:'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white)),
                      Consumer<AppSettings>(
                        builder: (context, appSettings, _) => Text(
                          appSettings.formatCurrency(
                            appSettings.convertCurrency(
                              _getShippingPriceFromProducts(items))),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w700,
                            color: Colors.green))),
                    ])),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Delivery details
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Consumer<AppSettings>(
                            builder: (context, appSettings, _) => Text(
                              '${AppLocalizations.of(context)?.feeLabel ?? AppLocalizations.of(context)!.tr('Fee')}: ${appSettings.formatCurrency(appSettings.convertCurrency(double.tryParse(order['fee']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ?? 0.0))}',
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w700,
                                color: Colors.green))),
                          Text(
                            '${AppLocalizations.of(context)?.distanceLabel ?? AppLocalizations.of(context)!.tr('Distance')}: ${Provider.of<AppSettings>(context).formatDistance(order['distance']?.toDouble() ?? 0.0)}',
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.7))),
                        ])),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6),
                      decoration: BoxDecoration(
                        color: (order['priority'] ?? AppLocalizations.of(context)!.tr('normal')) == 'high'
                            ? Colors.orange.withOpacity(0.2)
                            : Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                      child: Text(
                        (order['priority'] ?? AppLocalizations.of(context)!.tr('normal'))
                            .toString()
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: (order['priority'] ?? AppLocalizations.of(context)!.tr('normal')) == 'high'
                              ? Colors.orange
                              : Colors.blue))),
                  ]),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Action button - Trade Republic style
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.acceptAndPickup ?? AppLocalizations.of(context)!.tr('Accept & Pickup with Truck'),
                  icon: Icon(CupertinoIcons.cube_box, size: 20, color: Colors.white),
                  onPressed: () => _showAcceptOrderModal(order, isLight)),

                // Extra spacing to ensure content is fully visible
                SizedBox(height: 60),
              ])))));
  }

  // Build modern clustered markers for orders
  List<Marker> _buildClusteredMarkers(bool isLight) {
    List<Marker> markers = [];

    // DEBUG: Log auction count
    print(
      '🗺️ _buildClusteredMarkers: ${_filteredAuctions.length} auctions after filters (merged=${_mergedAuctions().length}, api=${_auctions.length})');

    // FIRST: Add auction markers (these are shown separately from regular orders)
    for (var auction in _filteredAuctions) {
      print('🔍 Processing auction #${auction['id']}...');
      final latLng = _getAuctionCoordinates(auction);
      print('   → Coordinates: $latLng');
      if (latLng != null) {
        markers.add(
          Marker(
            key: Key('auction_${auction['id']}'),
            point: latLng,
            width: 80,
            height: 50,
            child: TradeRepublicTap(
              onTap: () {
                HapticFeedback.mediumImpact();
                _showAuctionModal(auction, latLng);
              },
              child: _buildAuctionMarker(auction, isLight))));
        print(
          '✅ Added auction marker #${auction['id']} at: ${latLng.latitude}, ${latLng.longitude}');
      } else {
        print('⚠️ No coordinates for auction #${auction['id']}');
      }
    }

    // Skip clustering if no orders
    if (_filteredOrders.isEmpty) return markers;

    List<List<Map<String, dynamic>>> clusters = _clusterOrders(_filteredOrders);

    // Reduced logging for performance
    if (_kDebugMode && clusters.length != _lastMarkerCount) {
      print(
        '🎯 Building ${clusters.length} marker clusters from ${_filteredOrders.length} orders');
      _lastMarkerCount = clusters.length;
    }

    for (int clusterIndex = 0; clusterIndex < clusters.length; clusterIndex++) {
      List<Map<String, dynamic>> cluster = clusters[clusterIndex];

      if (cluster.length == 1) {
        // Single order marker
        final order = cluster[0];

        // Skip order marker if there is already an auction marker for this order
        final orderId = (order['id'] ?? order['order_id'])?.toString();
        final hasAuctionMarker = _filteredAuctions.any(
          (a) => a['order_id']?.toString() == orderId);
        if (hasAuctionMarker) continue;

        // Get coordinates for this order using our sync method
        final latLng = _getPickupCoordinatesSync(order);

        if (latLng != null) {
          markers.add(
            Marker(
              key: Key('marker_${order['id']}_${order['acceptance_status']}'),
              point: latLng,
              width: 60,
              height:
                  75, // Adjusted for pin with tail (no separate price badge below)
              child: _AcceptedOrderMarkerWithDenial(
                key: Key(
                  'gesture_${order['id']}_${order['acceptance_status']?.toString() ?? AppLocalizations.of(context)!.tr('available')}'),
                order: order,
                isLight: isLight,
                onTap: () {
                  final acceptanceStatus =
                      (order['acceptance_status']?.toString() ?? AppLocalizations.of(context)!.tr('available'));
                  final hasEmergency =
                      order['has_issue'] == 1 ||
                      order['has_issue'] == true ||
                      order['issue_emergency'] == 1 ||
                      order['issue_emergency'] == true;

                  // Allow other drivers to see emergency orders even if already accepted
                  if (hasEmergency) {
                    HapticFeedback.mediumImpact();
                    // Check if order has auction
                    final orderId = order['id'] ?? order['order_id'];
                    final auction = _getAuctionForOrder(orderId);
                    if (auction != null) {
                      _showAuctionModal(auction, latLng);
                    } else {
                      _showClusterModal([order]);
                    }
                  } else if (acceptanceStatus == 'accepted' ||
                      acceptanceStatus == 'picked_up') {
                    // Do nothing for non-emergency accepted orders - widget handles denial animation
                    print(
                      '🚫 Tap on accepted order - denial animation will be shown');
                  } else {
                    HapticFeedback.mediumImpact();
                    // Check if order has auction
                    final orderId = order['id'] ?? order['order_id'];
                    final auction = _getAuctionForOrder(orderId);
                    if (auction != null) {
                      _showAuctionModal(auction, latLng);
                    } else {
                      _showClusterModal([order]);
                    }
                  }
                })));
        } else {
          if (_kDebugMode) {
            print('Could not get coordinates for order ${order['id']}');
          }
        }
      } else {
        // Clustered marker - modern stacked design
        final firstOrder = cluster[0];

        // Get coordinates for the cluster center
        final latLng = _getPickupCoordinatesSync(firstOrder);

        if (latLng != null) {
          if (_kDebugMode) {
            print(
              'Adding cluster marker with ${cluster.length} orders at: ${latLng.latitude}, ${latLng.longitude}');
          }
          markers.add(
            Marker(
              point: latLng,
              width: 70,
              height: 90, // Increased to prevent overflow
              child: TradeRepublicTap(
                onTap: () {
                  HapticFeedback.mediumImpact(); // Apple-style haptic
                  _showClusterModal(cluster);
                },
                child: _buildAppleStyleClusterMarker(cluster, isLight))));
        } else {
          if (_kDebugMode) print('Could not get coordinates for cluster');
        }
      }
    }

    if (_kDebugMode) print('Built ${markers.length} markers total');
    return markers;
  }

  // Beautiful Apple Maps-Style Order Marker - Clean & Modern with Status Colors
  Widget _buildAppleStyleOrderMarker(Map<String, dynamic> order, bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isExpress = order['priority'] == 'express';
    final items = List<Map<String, dynamic>>.from(order['items'] ?? []);
    final itemCount = items.length;
    final acceptanceStatus =
        (order['acceptance_status']?.toString() ?? AppLocalizations.of(context)!.tr('available'));
    final isEmergency =
        (order['has_issue'] == 1 ||
        order['has_issue'] == true ||
        order['emergency'] == 1 ||
        order['emergency'] == true ||
        order['issue_emergency'] == 1 ||
        order['issue_emergency'] == true);
    final isAccepted =
        acceptanceStatus == 'accepted' || acceptanceStatus == 'picked_up';

    // Get quantity/weight for display in marker - convert to user's preferred unit
    final rawQuantity = _toDouble(order['total_quantity'], defaultValue: 0.0);
    final rawUnit = order['quantity_unit']?.toString() ?? AppLocalizations.of(context)!.tr('t');

    // Smart weight display with unit normalization and automatic conversion
    String weightText;
    if (rawQuantity > 0) {
      final normalizedUnit = _normalizeUnit(rawUnit);
      double displayQuantity = rawQuantity;
      String displayUnit = normalizedUnit;

      // Convert grams to kg if >= 1000g for better readability
      if (normalizedUnit == 'g' && rawQuantity >= 1000) {
        displayQuantity = rawQuantity / 1000;
        displayUnit = 'kg';
      }

      // Format the display value
      final appSettings8 = Provider.of<AppSettings>(context, listen: false);
      if (displayQuantity == displayQuantity.roundToDouble()) {
        weightText = '${displayQuantity.toInt()}$displayUnit';
      } else {
        weightText = '${appSettings8.formatNumber(displayQuantity, decimals: 2)}$displayUnit';
      }
    } else {
      // Fallback: try to get from items
      double itemsWeight = 0;
      String itemsUnit = 'kg';
      for (var item in items) {
        itemsWeight += _toDouble(item['quantity'], defaultValue: 1.0);
        if (item['unit'] != null) {
          itemsUnit = _normalizeUnit(item['unit'].toString());
        }
      }
      if (itemsWeight > 0) {
        // Use raw items weight directly
        final appSettings9 = Provider.of<AppSettings>(context, listen: false);
        weightText = '${appSettings9.formatNumber(itemsWeight, decimals: 2)}$itemsUnit';
      } else {
        weightText = '${items.length}x'; // Fallback to item count
      }
    }

    // Oval background color based on theme (will be overridden for emergency)
    Color ovalColor = isLight ? Colors.black : Colors.white;
    Color textColor = isLight ? Colors.white : Colors.black;

    // Debug logging with correct order ID (only in debug mode)
    if (_kDebugMode) {
      final displayOrderId = order['order_id'] ?? order['id'];
      print(
        '🎯 Building marker for order #$displayOrderId (internal id: ${order['id']}): status=$acceptanceStatus, weight=$weightText');
      print('⚖️ Weight text that will be displayed IN PIN: $weightText');
      print(
        '🎨 Theme: ${isLight ? "LIGHT" : "DARK"}, Oval color: ${isLight ? "BLACK" : "WHITE"}');
      print('📦 Raw order data: ${order.toString().substring(0, 200)}...');
    }

    // Shadow color only
    Color shadowColor;

    // Get display order ID for logging
    final displayOrderId = order['order_id'] ?? order['id'];

    switch (acceptanceStatus) {
      case 'accepted':
      case 'picked_up':
        // Red shadow for accepted/in-progress orders
        if (_kDebugMode) {
          print(
            '🔴 Setting RED shadow for accepted order #$displayOrderId - will show strikethrough');
        }
        shadowColor = const Color(0xFFFF3B30);
        break;
      case 'available':
      default:
        // Shadow color based on express status
        if (_kDebugMode) {
          print('🔵 Setting shadow color for available order #$displayOrderId');
        }
        if (isExpress) {
          shadowColor = const Color(0xFFFF9500);
        } else {
          shadowColor = const Color(0xFF5E5CE6);
        }
        break;
    }
    // EMERGENCY OVERRIDE: Always use emergency red for BOTH shadow AND oval background
    if (isEmergency) {
      if (_kDebugMode) {
        print(
          '🚨 Emergency order detected for #$displayOrderId -> forcing RED marker (shadow + oval)');
      }
      shadowColor = const Color(0xFFFF3B30);
      ovalColor = const Color(0xFFFF3B30); // Make the oval itself RED
      textColor = Colors.white; // White text on red background for visibility
    }

    return SizedBox(
      height: 60, // Fixed height to prevent overflow
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Beautiful Uber-style pin with status-based colors
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow effect
              Container(
                width: 68,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 4),
                  ])),
              // Main marker body with WEIGHT inside (OVAL)
              Container(
                width: 60,
                height: 40,
                decoration: BoxDecoration(
                  color: ovalColor,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4)),
                  ]),
                child: Center(
                  child: Text(
                    weightText,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3)))),

              // Item count badge - modern floating design
              if (itemCount > 1)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.white, Colors.white]),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                      ]),
                    child: Text(
                      '$itemCount',
                      style: TextStyle(
                        color: shadowColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5)))),

              // UBER-STYLE: Bold, minimal strikethrough for accepted orders
              if (acceptanceStatus == 'accepted' ||
                  acceptanceStatus == 'picked_up')
                Center(
                  child: Container(
                    width: 56, // Slightly wider than marker
                    height: 4, // Thick, bold Uber-style line
                    decoration: BoxDecoration(
                      color: Colors.red.shade700, // Bold Uber red
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 3,
                          offset: const Offset(0, 2)),
                      ]))),

              // EMERGENCY INDICATOR: Bold exclamation mark badge for emergency orders
              if (isEmergency)
                Positioned(
                  top: -2,
                  left: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30), // Emergency red
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3B30).withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2),
                      ]),
                    child: const Center(
                      child: Icon(
                        CupertinoIcons.exclamationmark,
                        color: Colors.white,
                        size: 14)))),

              // Express indicator badge (kleines Blitz-Icon) - only if not emergency
              if (isExpress && !isEmergency)
                Positioned(
                  bottom: -2,
                  left: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500),
                      shape: BoxShape.circle),
                    child: Icon(
                      CupertinoIcons.bolt,
                      color: Colors.white,
                      size: 10))),

              // AUCTION INDICATOR: Gavel badge for orders with active auctions
              if (_getAuctionForOrder(order['order_id'] ?? order['id']) != null)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.5),
                          blurRadius: 6,
                          spreadRadius: 1),
                      ]),
                    child: Icon(
                      CupertinoIcons.hammer,
                      color: Colors.white,
                      size: 10))),
            ]),

          // Pin tail
          CustomPaint(
            size: const Size(16, 12),
            painter: _PinPointerPainter(color: ovalColor, isLight: isLight)),
        ]));
  }

  // Beautiful Apple Maps-style cluster marker with status-aware colors
  Widget _buildAppleStyleClusterMarker(
    List<Map<String, dynamic>> cluster,
    bool isLight) {
    final clusterCount = cluster.length;
    final hasExpress = cluster.any((order) => order['priority'] == 'express');
    final hasEmergency = cluster.any(
      (order) =>
          order['has_issue'] == 1 ||
          order['has_issue'] == true ||
          order['emergency'] == 1 ||
          order['emergency'] == true ||
          order['issue_emergency'] == 1 ||
          order['issue_emergency'] == true);

    // Check for accepted orders in cluster
    final hasAccepted = cluster.any((order) {
      final status = (order['acceptance_status']?.toString() ?? AppLocalizations.of(context)!.tr('available'));
      return status == 'accepted' || status == 'picked_up';
    });

    // UBER-STYLE: Pure black/white circles, no gradients
    Color clusterBg = isLight ? Colors.black : Colors.white;
    Color clusterText = isLight ? Colors.white : Colors.black;
    if (hasEmergency) {
      // Emphasize emergency clusters in red
      clusterBg = Colors.red.shade700;
      clusterText = Colors.white;
    }

    return SizedBox(
      height: 60, // Fixed height to prevent overflow
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // UBER-STYLE: Pure minimalist circular cluster
          Stack(
            alignment: Alignment.center,
            children: [
              // Main cluster circle - clean Uber style (solid color, no gradient)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: clusterBg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    // Single bold shadow - Uber style
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                  ]),
                child: Center(
                  child: Text(
                    '$clusterCount',
                    style: TextStyle(
                      color: clusterText,
                      fontSize: clusterCount > 99 ? 13 : 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)))),

              // EMERGENCY INDICATOR: Bold exclamation mark badge for emergency clusters
              if (hasEmergency)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30), // Emergency red
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3B30).withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2),
                      ]),
                    child: const Center(
                      child: Icon(
                        CupertinoIcons.exclamationmark,
                        color: Colors.white,
                        size: 14)))),

              // UBER-STYLE: Simple bold strikethrough for accepted orders
              if (hasAccepted)
                Center(
                  child: Container(
                    width: 52,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 2,
                          offset: const Offset(0, 1)),
                      ]))),
            ]),

          // Pin tail - matching marker color
          SizedBox(height: 2),
          CustomPaint(
            size: const Size(12, 8),
            painter: _PinPointerPainter(color: clusterBg, isLight: isLight)),
        ]));
  }

  // Simple standard blue circle location indicator
  // Modern 3D location indicator with pulsing effect - matching navigation modal
  Widget _buildAppleLocationIndicator(bool isLight) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007AFF), Color(0xFF0051D5)]),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007AFF).withOpacity(0.4),
            blurRadius: 8,
            spreadRadius: 2),
        ]));
  }

  // Calculate route between two LatLng points using OSRM
  Future<Map<String, dynamic>?> _calculateRoutePoints(
    LatLng start,
    LatLng end) async {
    try {
      final url =
          'http://router.project-osrm.org/route/v1/driving/'
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
          '?overview=false&steps=false';

      print('OSRM URL: $url');

      final response = await http.get(Uri.parse(url));

      print('OSRM Response status: ${response.statusCode}');
      print('OSRM Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final result = {
            'distance': route['distance'], // meters
            'duration': route['duration'], // seconds
          };
          print('Route calculation successful: $result');
          return result;
        } else {
          print('No routes found in OSRM response');
        }
      } else {
        print('OSRM API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error calculating route: $e');
    }
    return null;
  }

  // Show order modal with route calculations and Apple glass design (Performance optimized)
  // Accept order and start delivery
  void _acceptOrder(Map<String, dynamic> order) async {
    Navigator.pop(context); // Close modal

    // Show loading indicator with bottom sheet
    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      enableDrag: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          CultiooLoadingIndicator(size: 24),
          SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)?.acceptingOrder ?? AppLocalizations.of(context)!.tr('Accepting Order...'),
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
              fontSize: DesktopOptimizedWidgets.getFontSize())),
        ]));

    try {
      // First, check if driver has a registered vehicle
      final vehicleCheckResponse = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delvioo/vehicles/1'), // TODO: Get actual driver ID from auth
      );

      if (vehicleCheckResponse.statusCode == 200) {
        final vehicleResult = json.decode(vehicleCheckResponse.body);

        print('🚗 Vehicle check response: $vehicleResult');

        if (vehicleResult['success'] && vehicleResult['vehicles'] != null) {
          final vehicles = vehicleResult['vehicles'] as List;
          final activeVehicles = vehicles
              .where(
                (v) =>
                    v['is_active'] == 1 ||
                    v['is_active'] == '1' ||
                    v['is_active'] == true)
              .toList();

          if (activeVehicles.isEmpty) {
            print('⚠️ No active vehicles found. Vehicles: $vehicles');
            // TEMPORARY: Skip validation for testing
            // TODO: Re-enable once vehicle registration is working
            /*
            // No active vehicle found - close loading and show error
            if (mounted) {
              Navigator.pop(context); // Close loading dialog
              TopNotification.error(
                context,
                AppLocalizations.of(context)?.registerVehicleBeforeOrders ?? AppLocalizations.of(context)!.tr('Please register your vehicle before accepting orders'));
            }
            return;
            */
          } else {
            print(
              '✅ Driver has active vehicle: ${activeVehicles[0]['vehicle_make']} ${activeVehicles[0]['vehicle_model']}');
          }
        } else {
          print('⚠️ Vehicle check failed or no vehicles found');
        }
      } else {
        print(
          '⚠️ Vehicle check request failed: ${vehicleCheckResponse.statusCode}');
      }

      // Simulate API call to accept order
      await Future.delayed(const Duration(seconds: 2));

      // Close loading dialog
      if (mounted) Navigator.pop(context);

      // Generiere Sicherheitscode
      final orderId = order['id'] ?? order['order_id'] ?? 0;
      final random = math.Random(orderId.hashCode);
      String securityCode = '';
      for (int i = 0; i < 8; i++) {
        securityCode += random.nextInt(10).toString();
      }

      // Add order to accepted orders list
      final acceptedOrder = Map<String, dynamic>.from(order);
      acceptedOrder['acceptedAt'] = DateTime.now().toIso8601String();
      acceptedOrder['status'] = 'accepted';
      acceptedOrder['security_code'] = securityCode;
      _acceptedOrders.add(acceptedOrder);

      // Show success message
      TopNotification.success(
        context,
        'Order ${order['id']} accepted! Navigate to pickup location.');

      // Reset map view
      setState(() {
        selectedOrderId = null;
        _isMapExpanded = false;
      });

      // Refresh orders
      _loadOrders();
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Show error message
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.failedToAcceptOrder ?? AppLocalizations.of(context)!.tr('Failed to accept order. Please try again.'));
    }
  }

  // Get route with traffic information from routing API
  Future<Map<String, dynamic>> _getRouteWithTrafficFromAPI(
    LatLng start,
    LatLng end) async {
    try {
      // Using OSRM with annotations for traffic data
      final url =
          'http://router.project-osrm.org/route/v1/driving/'
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
          '?overview=full&geometries=geojson&annotations=true&steps=true';

      print('Requesting route with traffic from: $url');

      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'Cultioo Delivery App'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && data['routes'].length > 0) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          final legs = route['legs'] as List?;

          if (geometry != null && geometry['coordinates'] != null) {
            final coordinates = geometry['coordinates'] as List;

            // Convert coordinates to LatLng points
            final routePoints = coordinates.map<LatLng>((coord) {
              return LatLng(coord[1].toDouble(), coord[0].toDouble());
            }).toList();

            // Process traffic data from legs
            List<Map<String, dynamic>> trafficSegments = [];
            if (legs != null && legs.isNotEmpty) {
              for (var leg in legs) {
                final steps = leg['steps'] as List?;
                if (steps != null) {
                  for (var step in steps) {
                    final duration = _toDouble(step['duration']);
                    final distance = _toDouble(step['distance']);
                    final geometry = step['geometry'];

                    // Calculate average speed to determine traffic conditions
                    double speed = distance > 0
                        ? (distance / duration) * 3.6
                        : 0; // Convert m/s to km/h

                    String trafficCondition = 'normal';
                    Color trafficColor = Colors.green;

                    // Determine traffic condition based on speed
                    if (speed < 10) {
                      trafficCondition = 'heavy';
                      trafficColor = Colors.red;
                    } else if (speed < 25) {
                      trafficCondition = 'moderate';
                      trafficColor = Colors.orange;
                    } else if (speed < 40) {
                      trafficCondition = 'light';
                      trafficColor = Colors.yellow;
                    }

                    trafficSegments.add({
                      'geometry': geometry,
                      'condition': trafficCondition,
                      'color': trafficColor,
                      'speed': speed,
                      'duration': duration,
                      'distance': distance,
                    });
                  }
                }
              }
            }

            print(
              'Route found with ${routePoints.length} points and ${trafficSegments.length} traffic segments');
            // OSRM returns distance in meters and duration in seconds
            // Convert to km and minutes respectively
            final distanceMeters = _toDouble(route['distance']);
            final durationSeconds = _toDouble(route['duration']);
            return {
              'routePoints': routePoints,
              'trafficSegments': trafficSegments,
              'distance': distanceMeters / 1000.0, // Convert meters to km
              'duration': durationSeconds / 60.0, // Convert seconds to minutes
            };
          }
        }
      }

      print(
        'No route found in API response or request failed: ${response.statusCode}');
      return {
        'routePoints': <LatLng>[],
        'trafficSegments': <Map<String, dynamic>>[],
        'distance': 0.0,
        'duration': 0.0,
      };
    } catch (e) {
      print('Error getting route with traffic from API: $e');
      return {
        'routePoints': <LatLng>[],
        'trafficSegments': <Map<String, dynamic>>[],
        'distance': 0.0,
        'duration': 0.0,
      };
    }
  }

  // Get route from routing API (using OSRM - free routing service) - Legacy method
  Future<List<LatLng>> _getRouteFromAPI(LatLng start, LatLng end) async {
    final result = await _getRouteWithTrafficFromAPI(start, end);
    return result['routePoints'] as List<LatLng>;
  }

  // Calculate distance along route points
  double _calculateRouteDistance(List<LatLng> points) {
    if (points.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += Geolocator.distanceBetween(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude);
    }

    return totalDistance / 1000; // Convert to kilometers
  }

  // Calculate estimated fuel cost for the route
  double _calculateFuelCost(double distanceKm) {
    // Average fuel consumption: 8 liters per 100km
    const double fuelConsumptionPer100km = 8.0;
    // Base fuel price in USD: 1.50 per liter
    const double baseFuelPricePerLiter = 1.50;

    // Calculate fuel needed in liters
    double fuelNeeded = (distanceKm / 100) * fuelConsumptionPer100km;

    // Calculate total cost in user's currency
    final appSettings = AppSettings();
    final convertedPrice = appSettings.convertCurrency(baseFuelPricePerLiter);
    return fuelNeeded * convertedPrice;
  }

  // Get pickup location coordinates for an order synchronously
  LatLng? _getPickupCoordinatesSync(Map<String, dynamic> order) {
    print('Getting pickup coordinates for order: ${order['id']}');
    // EMERGENCY: Prefer accident GPS when available so the marker shows the crash location
    try {
      final hasIssue = order['has_issue'] == 1 || order['has_issue'] == true;
      final isEmergency =
          hasIssue || order['emergency'] == 1 || order['emergency'] == true;

      if (_kDebugMode && isEmergency) {
        print('🚨 Emergency order ${order['id']} detected!');
        print(
          '   issue_latitude: ${order['issue_latitude']} (type: ${order['issue_latitude']?.runtimeType})');
        print(
          '   issue_longitude: ${order['issue_longitude']} (type: ${order['issue_longitude']?.runtimeType})');
      }

      // 1) Explicit issue coordinates from backend - PRIORITY for emergency orders
      if (isEmergency &&
          order['issue_latitude'] != null &&
          order['issue_longitude'] != null) {
        final lat = _toDouble(order['issue_latitude']);
        final lng = _toDouble(order['issue_longitude']);

        if (_kDebugMode) {
          print('   Converted to: lat=$lat, lng=$lng');
        }

        if (lat != 0.0 && lng != 0.0) {
          print('🚨 Using EMERGENCY accident location for marker: $lat, $lng');
          return LatLng(lat, lng);
        } else {
          print('⚠️ Emergency coords are 0,0 - falling back to normal pickup');
        }
      }

      // 2) Parse from pickup_street like: "Truck Location: 51.23456, 6.98765"
      if (isEmergency && order['pickup_street'] != null) {
        final street = order['pickup_street'].toString();
        final exp = RegExp(
          r'(Truck\s*Location|Accident\s*Location)\s*[:\-]?\s*([+\-]?\d+(?:\.\d+)?)\s*,\s*([+\-]?\d+(?:\.\d+)?)',
          caseSensitive: false);
        final m = exp.firstMatch(street);
        if (m != null) {
          final lat = double.tryParse(m.group(2)!);
          final lng = double.tryParse(m.group(3)!);
          if (lat != null && lng != null) {
            print(
              '🚨 Using EMERGENCY pickup coords parsed from pickup_street: $lat,$lng');
            return LatLng(lat, lng);
          }
        }
      }
    } catch (e) {
      print('⚠️ Emergency pickup coordinate parse failed: $e');
    }

    // FIRST: Try pickup coordinates from database (new fields from enhanced API)
    if (order['pickup_lat'] != null && order['pickup_lng'] != null) {
      final lat = double.tryParse(order['pickup_lat'].toString());
      final lng = double.tryParse(order['pickup_lng'].toString());

      if (lat != null && lng != null) {
        print('✅ Using pickup coordinates from database: $lat, $lng');
        return LatLng(lat, lng);
      }
    }

    // SECOND: Check if order has direct pickup coordinates (old format)
    final pickup = order['pickup'] as Map<String, dynamic>?;
    if (pickup != null && pickup.isNotEmpty) {
      final coordinates = pickup['coordinates'] as Map<String, dynamic>?;
      if (coordinates != null) {
        final lat = coordinates['lat'] as double?;
        final lng = coordinates['lng'] as double?;

        if (lat != null && lng != null) {
          print('✅ Using order pickup coordinates: $lat, $lng');
          return LatLng(lat, lng);
        }
      }
    }

    // SECOND: Try to get pickup coordinates from product data
    final items = order['items'] as List<dynamic>?;
    if (items != null && items.isNotEmpty) {
      final firstItem = items[0] as Map<String, dynamic>;
      print('First item data: $firstItem');

      // Check if we have direct product data with coordinates from the API
      final product = firstItem['product'] as Map<String, dynamic>?;
      if (product != null) {
        final lat = product['lat'] as double?;
        final lng = product['lng'] as double?;

        if (lat != null && lng != null) {
          print('Found product coordinates from API: $lat, $lng');
          return LatLng(lat, lng);
        }
      }

      // If no coordinates in the embedded product data, we need to fetch from products API
      // This should be called asynchronously, but for now we'll trigger the fetch
      final productIdRaw = firstItem['id'];
      if (productIdRaw != null) {
        // Convert to int if it's a string, otherwise use as is
        int productId;
        if (productIdRaw is String) {
          productId = int.tryParse(productIdRaw) ?? 0;
        } else if (productIdRaw is int) {
          productId = productIdRaw;
        } else {
          print('Invalid product ID type: $productIdRaw');
          productId = 0;
        }

        if (productId > 0) {
          // Check cache first
          if (_productCoordinatesCache.containsKey(productId)) {
            final cachedCoords = _productCoordinatesCache[productId];
            if (cachedCoords != null) {
              return cachedCoords;
            }
          }

          print(
            'Product ID found: $productId - will use fallback while coordinates load in background');
        } else {
          print('Invalid product ID: $productIdRaw');
        }
      } else {
        // Product ID is null - try to match by seller or use smart fallback
        final seller = firstItem['seller'] as String?;
        final productName = firstItem['name'] as String?;

        print('⚠️ Product ID is null for item: $productName by $seller');

        // Smart fallback based on seller or order info
        if (seller == 'Arkadiy' || seller?.contains('Arkadiy') == true) {
          // This is likely a product created by Arkadiy - use Krefeld coordinates from Product ID 7
          print('🎯 Using Arkadiy seller fallback coordinates (Krefeld)');
          return const LatLng(51.35714860, 6.63802600);
        }

        // Smart fallback for common products based on name and order
        if (productName != null) {
          // For Order 7 with "Apple" product - this should map to Product ID 7 (Arkadiy, Krefeld)
          final orderId = order['id'] ?? 0;
          if (orderId == 7 && productName.toLowerCase().contains('apple')) {
            print(
              '🍎 Order 7 Apple product -> Using Product ID 7 coordinates (Krefeld)');
            return const LatLng(51.35714860, 6.63802600);
          }

          // General Apple product fallback for Arkadiy's store
          if (productName.toLowerCase().contains('apple') &&
              productName.toLowerCase() != 'apple iphone') {
            print('🍎 Using Apple product fallback coordinates (Krefeld)');
            return const LatLng(51.35714860, 6.63802600);
          }
        }
      }

      print('No coordinates available for product, using fallback location');
    }

    // Fallback: Use a generic location until proper coordinates are loaded
    // This should be replaced once we have async coordinate fetching
    final orderId = order['id'] ?? 0;
    final offset = (orderId % 10) * 0.001; // Small offset to prevent overlap
    final fallbackLocation = LatLng(53.5490 + offset, 9.9900 + offset);
    print(
      'Using fallback location: ${fallbackLocation.latitude}, ${fallbackLocation.longitude}');
    return fallbackLocation;
  }

  // Async method to fetch product coordinates from the API (with caching)
  Future<void> _fetchProductCoordinatesAsync(int productId) async {
    // Skip if already cached or being fetched
    if (_productCoordinatesCache.containsKey(productId) ||
        _fetchingProducts.contains(productId)) {
      return;
    }

    try {
      print('🔍 Fetching coordinates for product ID: $productId');

      final response = await http
          .get(
            Uri.parse(ApiConfig.getProductUrl(productId)),
            headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final productData = json.decode(response.body) as Map<String, dynamic>;

        final lat = productData['lat'] as double?;
        final lng = productData['lng'] as double?;

        if (lat != null && lng != null) {
          final coordinates = LatLng(lat, lng);
          _productCoordinatesCache[productId] = coordinates;
          print('✅ Cached coordinates for product $productId: $lat, $lng');
        } else {
          _productCoordinatesCache[productId] = null;
          print('⚠️ No coordinates in DB for product $productId');
        }
      } else {
        _productCoordinatesCache[productId] = null;
        print('❌ Failed to fetch product $productId: ${response.statusCode}');
      }
    } catch (e) {
      _productCoordinatesCache[productId] = null;
      print('💥 Error fetching product $productId: $e');
    }
  }

  // Get shipping price from product data
  double _getShippingPriceFromProducts(List<Map<String, dynamic>> items) {
    if (items.isNotEmpty) {
      final firstItem = items[0];

      // Try to get shipping price from the enriched product data
      final product = firstItem['product'] as Map<String, dynamic>?;
      if (product != null) {
        final shippingPrice = product['shippingPrice'] as double?;
        return shippingPrice ?? 0.0;
      }
    }

    // Fallback if no shipping price data is available
    return 0.0;
  }

  // Get formatted delivery address description from order
  String _getDeliveryAddressFromOrder(Map<String, dynamic> order) {
    try {
      print('\n🔥 Getting delivery address for order ${order['id']}');

      final delivery = order['delivery'];
      if (delivery == null) {
        print('❌ delivery is null');
        return '';
      }

      if (delivery is! Map) {
        print('❌ delivery is not a Map');
        return '';
      }

      print('✓ delivery keys: ${delivery.keys.toList()}');

      // Get address field
      final address = delivery['address'];
      print('🔍 address value: "$address"');

      if (address != null && address.toString().trim().isNotEmpty) {
        final result = address.toString().trim();
        print('✅ SUCCESS! "$result"');
        return result;
      }

      // Try components
      final street = delivery['street']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
      final city = delivery['city']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');

      if (street.isNotEmpty || city.isNotEmpty) {
        final parts = [
          if (street.isNotEmpty) street,
          if (delivery['house_number'] != null)
            delivery['house_number'].toString(),
          if (delivery['postal_code'] != null)
            delivery['postal_code'].toString(),
          if (city.isNotEmpty) city,
          if (delivery['country'] != null && delivery['country'] != 'Germany')
            delivery['country'].toString(),
        ];

        if (parts.isNotEmpty) {
          final result = parts.join(', ');
          print('✅ Built: "$result"');
          return result;
        }
      }

      print('⚠️ No address found');
      return '';
    } catch (e) {
      print('❌ Error: $e');
      return '';
    }
  }

  // Get pickup address description from order and product info
  String _getPickupAddressFromOrder(Map<String, dynamic> order) {
    print('🏠 Getting pickup address for order: ${order['id']}');
    print('📋 Order data: $order');

    // FIRST: Try pickup address from backend database (new format from API)
    if (order['pickup_street'] != null &&
        order['pickup_street'].toString().isNotEmpty) {
      String pickupAddress = order['pickup_street'].toString();

      // Check if pickup_street already contains a complete address (contains numbers and city)
      final street = pickupAddress.toLowerCase();
      final city = order['pickup_city']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');

      // If pickup_street already contains the city name, use it as is
      if (city.isNotEmpty && street.contains(city)) {
        print(
          '✅ Using complete pickup address from database (street contains city): $pickupAddress');
        return pickupAddress;
      }

      // Otherwise, build the address by combining components
      if (order['pickup_city'] != null &&
          order['pickup_city'].toString().isNotEmpty) {
        pickupAddress += ', ${order['pickup_city']}';
      }
      if (order['pickup_zip'] != null &&
          order['pickup_zip'].toString().isNotEmpty) {
        final cityPart = order['pickup_city']?.toString() ?? AppLocalizations.of(context)!.tr('');
        if (cityPart.isNotEmpty) {
          pickupAddress =
              '${order['pickup_street']}, ${order['pickup_zip']} $cityPart';
        } else {
          pickupAddress += ', ${order['pickup_zip']}';
        }
      }
      print('✅ Using constructed pickup address from database: $pickupAddress');
      return pickupAddress;
    }

    // SECOND: Check if order has pickup address (old format)
    final pickup = order['pickup'] as Map<String, dynamic>?;
    if (pickup != null && pickup.isNotEmpty) {
      final address = pickup['address'] as String?;
      final city = pickup['city'] as String?;
      final zip = pickup['zip'] as String?;

      if (address != null && city != null) {
        final pickupAddr = zip != null && zip.isNotEmpty
            ? '$address, $zip $city'
            : '$address, $city';
        print('✅ Using pickup address from pickup object: $pickupAddr');
        return pickupAddr;
      } else if (address != null) {
        print('✅ Using pickup address (address only): $address');
        return address;
      }
    }

    // THIRD: Try to get address from product data
    final items = order['items'] as List<dynamic>?;
    if (items != null && items.isNotEmpty) {
      final firstItem = items[0] as Map<String, dynamic>;

      final product = firstItem['product'] as Map<String, dynamic>?;
      if (product != null) {
        final locationStreet = product['locationStreet'] as String?;
        final locationCity = product['locationCity'] as String?;
        final locationZip = product['locationZip'] as String?;

        if (locationStreet != null && locationCity != null) {
          final productAddr = locationZip != null
              ? '$locationStreet, $locationZip $locationCity'
              : '$locationStreet, $locationCity';
          print('✅ Using pickup address from product data: $productAddr');
          return productAddr;
        }
      }
    }

    // FOURTH: Order-specific fallbacks based on product seller
    final orderId = order['id'] ?? order['order_id'];
    if (orderId == 2 || order['product_seller'] == 'Arkadiy') {
      final fallbackAddr = 'Main Street 123, 12345 City, Country';
      print('🏪 Using Arkadiy seller fallback address: $fallbackAddr');
      return fallbackAddr;
    }

    // Final fallback if no address data is available
    print('⚠️ Using final fallback message');
    return AppLocalizations.of(context)?.pickupAddressProvidedByStore ?? AppLocalizations.of(context)!.tr('Pickup address will be provided by store');
  }

  // Get delivery location coordinates for an order synchronously
  LatLng? _getDeliveryCoordinatesSync(Map<String, dynamic> order) {
    // Parse delivery address from API transformed format
    final delivery = order['delivery'] as Map<String, dynamic>?;
    if (delivery != null) {
      final coordinates = delivery['coordinates'] as Map<String, dynamic>?;
      if (coordinates != null) {
        // Try to get coordinates from delivery
        final lat = coordinates['lat'] as double?;
        final lng = coordinates['lng'] as double?;

        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }

      // If no coordinates, try to geocode from address
      final address = delivery['address'] as String?;
      final city = delivery['city'] as String?;
      final fullLocation = '${address ?? AppLocalizations.of(context)!.tr('')} ${city ?? AppLocalizations.of(context)!.tr('')}'.toLowerCase();

      if (fullLocation.contains('hamburg')) {
        // Hamburg city center as fallback for Hamburg addresses
        return const LatLng(53.5511, 9.9937);
      }
      if (fullLocation.contains('krefeld')) {
        // Krefeld city center as fallback for Krefeld addresses
        return const LatLng(51.3388, 6.5853);
      }
    }

    // Final fallback to area around Krefeld with order-specific offset
    final orderId = order['id'] ?? 0;
    final baseOffset = (orderId.hashCode % 20) * 0.001; // Small random offset
    return LatLng(51.3571486 + baseOffset, 6.638026 + baseOffset);
  }

  // Calculate complete delivery route based on API transformed data
  Future<Map<String, dynamic>?> _calculateDeliveryRoute(
    List<Map<String, dynamic>> items,
    Map<String, dynamic> delivery) async {
    if (items.isEmpty) return null;

    try {
      // Get pickup location from the first product in the order
      final pickupLocation = await _getPickupLocationFromProducts(items);
      if (pickupLocation == null) {
        // Fallback to Krefeld if no pickup location found
        final pickupLatLng = LatLng(51.3571486, 6.638026);

        // Get delivery coordinates from the API data
        final deliveryCoords = delivery['coordinates'] as Map<String, dynamic>?;
        if (deliveryCoords == null) return null;

        final deliveryLat = deliveryCoords['lat'] as double?;
        final deliveryLng = deliveryCoords['lng'] as double?;

        if (deliveryLat == null || deliveryLng == null) return null;

        final deliveryLatLng = LatLng(deliveryLat, deliveryLng);

        return {
          'distance': 0.0,
          'fuelCost': 0.0,
          'routePoints': <LatLng>[],
          'pickupLocation': pickupLatLng,
          'deliveryLocation': deliveryLatLng,
        };
      }

      final pickupLat = pickupLocation['lat'] as double?;
      final pickupLng = pickupLocation['lng'] as double?;

      if (pickupLat == null || pickupLng == null) return null;

      final pickupLatLng = LatLng(pickupLat, pickupLng);

      // Get delivery coordinates from the API data
      final deliveryCoords = delivery['coordinates'] as Map<String, dynamic>?;
      if (deliveryCoords == null) return null;

      final deliveryLat = deliveryCoords['lat'] as double?;
      final deliveryLng = deliveryCoords['lng'] as double?;

      if (deliveryLat == null || deliveryLng == null) return null;

      final deliveryLatLng = LatLng(deliveryLat, deliveryLng);

      // Calculate route using OSRM
      final routePoints = await _getRouteFromAPI(pickupLatLng, deliveryLatLng);

      if (routePoints.isNotEmpty) {
        final distance = _calculateRouteDistance(routePoints);
        final fuelCost = _calculateFuelCost(distance);

        // DEBUG: Print route points
        print(
          '📍 _calculateDeliveryRoute - START point: ${routePoints.first.latitude}, ${routePoints.first.longitude}');
        print(
          '🎯 _calculateDeliveryRoute - END point: ${routePoints.last.latitude}, ${routePoints.last.longitude}');
        print('📏 Total points in route: ${routePoints.length}');

        // Store route for visualization
        setState(() {
          _routePoints = routePoints;
        });

        return {
          'distance': distance,
          'fuelCost': fuelCost,
          'routePoints': routePoints,
          'pickupLocation': pickupLatLng,
          'deliveryLocation': deliveryLatLng,
        };
      }
    } catch (e) {
      print('Error calculating delivery route: $e');
    }

    return null;
  }

  // Get pickup location from products table based on order items
  Future<Map<String, dynamic>?> _getPickupLocationFromProducts(
    List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return null;

    try {
      // Get the first item's product ID - try multiple possible field names
      final firstItem = items[0];
      print('First item data: $firstItem');

      final productId =
          firstItem['product_id'] ??
          firstItem['productId'] ??
          firstItem['id'] ??
          firstItem['product_id'];

      if (productId == null) {
        print('No product ID found in item: $firstItem');
        print('Available keys: ${firstItem.keys.toList()}');
        return null;
      }

      print('Fetching pickup location for product ID: $productId');

      final response = await http.get(
        Uri.parse(ApiConfig.getProductUrl(productId)),
        headers: {'Content-Type': 'application/json'});

      print('Product API response status: ${response.statusCode}');
      print('Product API response body: ${response.body}');

      if (response.statusCode == 200) {
        final productData = json.decode(response.body) as Map<String, dynamic>;

        // Extract location information from the product
        final locationStreet = productData['locationStreet'];
        final locationCity = productData['locationCity'];
        final locationZip = productData['locationZip'];
        final locationCountry = productData['locationCountry'];
        final lat = productData['lat'] as double?;
        final lng = productData['lng'] as double?;

        print(
          'Product location data: street=$locationStreet, city=$locationCity, lat=$lat, lng=$lng');

        if (lat != null && lng != null) {
          return {
            'lat': lat,
            'lng': lng,
            'address': locationStreet ?? (AppLocalizations.of(context)?.unknownStreet ?? AppLocalizations.of(context)!.tr('Unknown Street')),
            'city': locationCity ?? (AppLocalizations.of(context)?.unknownCity ?? AppLocalizations.of(context)!.tr('Unknown City')),
            'zip': locationZip ?? AppLocalizations.of(context)!.tr(''),
            'country': locationCountry ?? AppLocalizations.of(context)!.tr('Germany'),
          };
        } else {
          print('No coordinates found in product data: $productData');
        }
      } else {
        print(
          'Failed to fetch product data: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error fetching pickup location from products: $e');
    }

    return null;
  }

  // Build pickup button with route information
  Widget _buildPickupButton(
    Map<String, dynamic> order,
    bool isLight,
    Map<String, dynamic>? routeData) {
    return TradeRepublicButton(
      label: AppLocalizations.of(context)?.pickMeUp ?? AppLocalizations.of(context)!.tr('Pick me up!'),
      icon: Icon(CupertinoIcons.cube_box, size: 20),
      onPressed: () => _handlePickupOrder(order, routeData),
      width: double.infinity);
  }

  // Show route for auction on map
  Future<void> _showRouteForAuction(
    Map<String, dynamic> auction,
    LatLng pickupLocation) async {
    if (currentLocation == null) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.tr('Location not available. Please enable GPS.') ?? AppLocalizations.of(context)!.tr('Location not available. Please enable GPS.'));
      return;
    }

    print('🗺️ Starting route calculation for auction...');
    print(
      '📍 Pickup location: ${pickupLocation.latitude}, ${pickupLocation.longitude}');
    print(
      '📍 Current location: ${currentLocation!.latitude}, ${currentLocation!.longitude}');

    // Parse delivery address to get coordinates
    LatLng? deliveryLocation;
    try {
      final raw = auction['delivery_address'];
      Map<String, dynamic>? deliveryAddress;
      if (raw is String) {
        deliveryAddress = json.decode(raw);
      } else if (raw is Map) {
        deliveryAddress = Map<String, dynamic>.from(raw);
      }

      print('📦 Delivery address data: $deliveryAddress');

      if (deliveryAddress != null) {
        final lat = deliveryAddress['lat'];
        final lng = deliveryAddress['lng'];
        print('📍 Delivery lat: $lat, lng: $lng');

        if (lat != null && lng != null && lat != 'null' && lng != 'null') {
          final parsedLat = lat is num
              ? lat.toDouble()
              : double.tryParse(lat.toString());
          final parsedLng = lng is num
              ? lng.toDouble()
              : double.tryParse(lng.toString());

          if (parsedLat != null &&
              parsedLng != null &&
              parsedLat != 0 &&
              parsedLng != 0) {
            deliveryLocation = LatLng(parsedLat, parsedLng);
            print(
              '✅ Using delivery coordinates from address: ${deliveryLocation.latitude}, ${deliveryLocation.longitude}');
          }
        }

        // If no coordinates, try to geocode from address string
        if (deliveryLocation == null) {
          final street = deliveryAddress['street'] ?? AppLocalizations.of(context)!.tr('');
          final houseNumber = deliveryAddress['house_number'] ?? AppLocalizations.of(context)!.tr('');
          final zipCode = deliveryAddress['zip_code'] ?? AppLocalizations.of(context)!.tr('');
          final city = deliveryAddress['city'] ?? AppLocalizations.of(context)!.tr('');
          final country = deliveryAddress['country'] ?? AppLocalizations.of(context)!.tr('Germany');

          final addressString =
              '$street $houseNumber, $zipCode $city, $country';
          print('🔍 Geocoding address: $addressString');

          // Use Nominatim (OpenStreetMap) for geocoding
          try {
            final encodedAddress = Uri.encodeComponent(addressString);
            final geocodeUrl =
                'https://nominatim.openstreetmap.org/search?q=$encodedAddress&format=json&limit=1';
            final response = await http.get(
              Uri.parse(geocodeUrl),
              headers: {'User-Agent': 'CultiooApp/1.0'});

            if (response.statusCode == 200) {
              final results = json.decode(response.body) as List;
              if (results.isNotEmpty) {
                final result = results[0];
                deliveryLocation = LatLng(
                  double.parse(result['lat']),
                  double.parse(result['lon']));
                print(
                  '✅ Geocoded delivery location: ${deliveryLocation.latitude}, ${deliveryLocation.longitude}');
              }
            }
          } catch (e) {
            print('⚠️ Geocoding failed: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Error parsing delivery coordinates: $e');
    }

    // Fallback delivery location - use Krefeld city center if nothing else works
    if (deliveryLocation == null) {
      deliveryLocation = LatLng(51.3388, 6.5853);
      print(
        '⚠️ Using fallback delivery location (Krefeld): ${deliveryLocation.latitude}, ${deliveryLocation.longitude}');
    }

    try {
      List<LatLng> completeRoute = [];
      double totalDistance = 0.0;
      double totalDuration = 0.0;

      // Store current to pickup distance separately
      double currentToPickupDist = 0.0;
      double currentToPickupDur = 0.0;

      _trafficSegments.clear();

      print('🔄 Calculating Route 1: Current → Pickup');
      // Route 1: Current Location -> Pickup
      final routeToPickup = await _getRouteWithTrafficFromAPI(
        currentLocation!,
        pickupLocation);

      final route1Points = routeToPickup['routePoints'] as List<LatLng>? ?? [];
      print('📍 Route 1 points: ${route1Points.length}');

      if (route1Points.isNotEmpty) {
        completeRoute.addAll(route1Points);
        final dist1 = routeToPickup['distance'];
        final dur1 = routeToPickup['duration'];
        currentToPickupDist = (dist1 is num) ? dist1.toDouble() : 0.0;
        currentToPickupDur = (dur1 is num) ? dur1.toDouble() : 0.0;
        totalDistance += currentToPickupDist;
        totalDuration += currentToPickupDur;
        final traffic1 = routeToPickup['trafficSegments'];
        if (traffic1 is List) {
          _trafficSegments.addAll(traffic1.cast<Map<String, dynamic>>());
        }
      }

      print('🔄 Calculating Route 2: Pickup → Delivery');
      // Route 2: Pickup -> Delivery
      final routeToDelivery = await _getRouteWithTrafficFromAPI(
        pickupLocation,
        deliveryLocation);

      final route2Points =
          routeToDelivery['routePoints'] as List<LatLng>? ?? [];
      print('📍 Route 2 points: ${route2Points.length}');

      // Store pickup to delivery distance separately
      double pickupToDeliveryDist = 0.0;
      double pickupToDeliveryDur = 0.0;

      if (route2Points.isNotEmpty) {
        completeRoute.addAll(route2Points);
        final dist2 = routeToDelivery['distance'];
        final dur2 = routeToDelivery['duration'];
        pickupToDeliveryDist = (dist2 is num) ? dist2.toDouble() : 0.0;
        pickupToDeliveryDur = (dur2 is num) ? dur2.toDouble() : 0.0;
        totalDistance += pickupToDeliveryDist;
        totalDuration += pickupToDeliveryDur;
        final traffic2 = routeToDelivery['trafficSegments'];
        if (traffic2 is List) {
          _trafficSegments.addAll(traffic2.cast<Map<String, dynamic>>());
        }
      }

      print(
        '📊 Total route points: ${completeRoute.length}, Distance: ${totalDistance.toStringAsFixed(1)} km');
      print(
        '📊 Pickup to Delivery only: ${pickupToDeliveryDist.toStringAsFixed(2)} km');

      if (completeRoute.isNotEmpty) {
        // Get addresses for display
        String pickupAddressStr =
            auction['pickup_address']?.toString() ?? AppLocalizations.of(context)?.pickup ?? AppLocalizations.of(context)!.tr('Pickup');
        String deliveryAddressStr = '';

        // Parse delivery address - EXACT SAME LOGIC AS MODAL
        try {
          final raw = auction['delivery_address'];
          Map<String, dynamic>? deliveryAddr;
          if (raw is String && raw.isNotEmpty) {
            deliveryAddr = json.decode(raw);
          } else if (raw is Map) {
            deliveryAddr = Map<String, dynamic>.from(raw);
          }

          if (deliveryAddr != null) {
            // Use 'address' field directly - same as modal line 2247
            deliveryAddressStr =
                deliveryAddr['address']?.toString() ??
                '${deliveryAddr['street'] ?? AppLocalizations.of(context)!.tr('')} ${deliveryAddr['house_number'] ?? AppLocalizations.of(context)!.tr('')}, ${deliveryAddr['zip_code'] ?? AppLocalizations.of(context)!.tr('')} ${deliveryAddr['city'] ?? AppLocalizations.of(context)!.tr('')}'
                    .trim()
                    .replaceAll(RegExp(r'\s+'), ' ');
          }
        } catch (e) {
          // ignore
        }

        // Clean up
        deliveryAddressStr = deliveryAddressStr.trim();
        if (deliveryAddressStr.isEmpty ||
            deliveryAddressStr == ',' ||
            deliveryAddressStr == ', ') {
          deliveryAddressStr = AppLocalizations.of(context)?.delivery ?? AppLocalizations.of(context)!.tr('Delivery');
        }

        setState(() {
          _routePoints = completeRoute;
          _showRouteInfo = true;
          final bidAuction = Map<String, dynamic>.from(auction);
          bidAuction['wagon_type'] =
              _resolvedWagonTypeForAuction(bidAuction);
          _currentAuctionForBid = bidAuction; // Store auction for bidding
          _pickupToDeliveryDistance = pickupToDeliveryDist;
          _activeRouteInfo = {
            'totalDistance': totalDistance,
            'totalDuration': totalDuration,
            'pickupLocation': pickupLocation,
            'deliveryLocation': deliveryLocation,
            'routePoints': completeRoute,
            'currentToPickupDistance': currentToPickupDist,
            'currentToPickupDuration': currentToPickupDur,
            'pickupToDeliveryDistance': pickupToDeliveryDist,
            'pickupToDeliveryDuration': pickupToDeliveryDur,
            'pickupAddress': pickupAddressStr,
            'deliveryAddress': deliveryAddressStr,
          };
        });

        _startRouteDrawingAnimation();
        _animateCameraToRoute(completeRoute);

        // Hide dock with animation when route is shown
        hideDockNotifier.value = true;

        TopNotification.success(
          context,
          'Route calculated: ${Provider.of<AppSettings>(context, listen: false).formatDistance(pickupToDeliveryDist)} (Pickup → Delivery)');
      } else {
        print('❌ No route points calculated!');
        TopNotification.error(context, AppLocalizations.of(context)?.couldNotCalculateRoute ?? AppLocalizations.of(context)!.tr('Could not calculate route'));
      }
    } catch (e) {
      print('❌ Error calculating auction route: $e');
      TopNotification.error(context, '${AppLocalizations.of(context)?.failedToCalculateRoute ?? AppLocalizations.of(context)!.tr('Could not calculate route')}: $e');
    }
  }

  // Calculate and show complete delivery route
  Future<void> _calculateAndShowCompleteRoute(
    Map<String, dynamic> order) async {
    if (currentLocation == null) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)!.tr('Location not available. Please enable GPS.') ?? AppLocalizations.of(context)!.tr('Location not available. Please enable GPS.'));
      return;
    }

    // Get pickup location
    final pickupLocation = _getPickupCoordinatesSync(order);
    if (pickupLocation == null) {
      TopNotification.success(
        context,
        AppLocalizations.of(context)!.tr('Pickup location not available.') ?? AppLocalizations.of(context)!.tr('Pickup location not available.'),

        // red error
      );
      return;
    }

    // Get delivery location
    final deliveryLocation = _getDeliveryCoordinatesSync(order);
    if (deliveryLocation == null) {
      TopNotification.success(
        context,
        AppLocalizations.of(context)!.tr('Delivery address not available.') ?? AppLocalizations.of(context)!.tr('Delivery address not available.'),

        // red error
      );
      return;
    }

    try {
      // Calculate route: Current Location -> Pickup -> Delivery
      List<LatLng> completeRoute = [];
      double totalDistance = 0.0;
      double totalDuration = 0.0;

      // Clear previous traffic data
      _trafficSegments.clear();

      print(
        '🗺️ Calculating route for order #${order['order_id'] ?? order['id']}');
      print(
        '   Current location: ${currentLocation!.latitude}, ${currentLocation!.longitude}');
      print(
        '   Pickup location: ${pickupLocation.latitude}, ${pickupLocation.longitude}');
      print(
        '   Delivery location: ${deliveryLocation.latitude}, ${deliveryLocation.longitude}');

      // Route 1: Current location to pickup (with traffic data)
      print('🔄 Route 1: Current → Pickup');
      final route1Result = await _getRouteWithTrafficFromAPI(
        currentLocation!,
        pickupLocation);
      final route1Points = route1Result['routePoints'] as List<LatLng>;
      final route1Traffic =
          route1Result['trafficSegments'] as List<Map<String, dynamic>>;

      if (route1Points.isNotEmpty) {
        completeRoute.addAll(route1Points);
        _trafficSegments.addAll(route1Traffic);
        totalDistance += _toDouble(route1Result['distance']); // Already in km
        totalDuration += _toDouble(
          route1Result['duration']); // Already in minutes
        print(
          '✅ Route 1: ${route1Points.length} points, ${totalDistance.toStringAsFixed(1)}km');
      } else {
        print('❌ Route 1: No points returned');
      }

      // Route 2: Pickup to delivery (with traffic data)
      print('🔄 Route 2: Pickup → Delivery');
      final route2Result = await _getRouteWithTrafficFromAPI(
        pickupLocation,
        deliveryLocation);
      final route2Points = route2Result['routePoints'] as List<LatLng>;
      final route2Traffic =
          route2Result['trafficSegments'] as List<Map<String, dynamic>>;

      if (route2Points.isNotEmpty) {
        completeRoute.addAll(route2Points);
        _trafficSegments.addAll(route2Traffic);
        totalDistance += _toDouble(route2Result['distance']); // Already in km
        totalDuration += _toDouble(
          route2Result['duration']); // Already in minutes
        print(
          '✅ Route 2: ${route2Points.length} points, total now ${totalDistance.toStringAsFixed(1)}km');
      } else {
        print('❌ Route 2: No points returned');
      }

      print(
        '🏁 Complete route: ${completeRoute.length} total points, ${totalDistance.toStringAsFixed(1)}km total distance');

      // DEBUG: Print last point coordinates
      if (completeRoute.isNotEmpty) {
        print(
          '📍 Route START point: ${completeRoute.first.latitude}, ${completeRoute.first.longitude}');
        print(
          '🎯 Route END point: ${completeRoute.last.latitude}, ${completeRoute.last.longitude}');
      }

      // Get addresses for display - DIRECT ACCESS without function
      final pickupAddressStr = _getPickupAddressFromOrder(order);

      // Get delivery address DIRECTLY from order['delivery']['address']
      String deliveryAddressStr = '';
      try {
        final delivery = order['delivery'];
        if (delivery != null &&
            delivery is Map &&
            delivery['address'] != null) {
          deliveryAddressStr = delivery['address'].toString().trim();
        }
        // Fallback: try order['address'] JSON
        if (deliveryAddressStr.isEmpty && order['address'] != null) {
          final addressData = order['address'] is String
              ? json.decode(order['address'])
              : order['address'];
          if (addressData is Map && addressData['address'] != null) {
            deliveryAddressStr = addressData['address'].toString().trim();
          }
        }
      } catch (e) {
        deliveryAddressStr = '';
      }

      print('📍 Pickup address: $pickupAddressStr');
      print('📍 Delivery address: "$deliveryAddressStr"');

      // Extract individual route segments for display
      final route1Distance = _toDouble(route1Result['distance']);
      final route1Duration = _toDouble(route1Result['duration']);
      final route2Distance = _toDouble(route2Result['distance']);
      final route2Duration = _toDouble(route2Result['duration']);

      // Update state with complete route and start Uber-style animation
      setState(() {
        _routePoints = completeRoute;
        _activeRouteInfo = {
          'orderId': order['order_id'] ?? order['id'],
          'totalDistance': totalDistance,
          'totalDuration': totalDuration,
          'currentLocation': currentLocation,
          'pickupLocation': pickupLocation,
          'deliveryLocation': deliveryLocation,
          'pickupAddress': pickupAddressStr,
          'deliveryAddress': deliveryAddressStr,
          'currentToPickupDistance': route1Distance,
          'currentToPickupDuration': route1Duration,
          'pickupToDeliveryDistance': route2Distance,
          'pickupToDeliveryDuration': route2Duration,
        };
        _showRouteInfo = true;
        _isRouteInfoMinimized = false; // Ensure it starts expanded
      });

      // Start Uber-style route drawing animation
      _startRouteDrawingAnimation();

      print(
        '✅ State updated: _routePoints.length = ${_routePoints.length}, _showRouteInfo = $_showRouteInfo');

      // Start timer to auto-minimize route info after 8 seconds
      _routeInfoMinimizeTimer?.cancel(); // Cancel any existing timer
      _routeInfoMinimizeTimer = Timer(const Duration(seconds: 8), () {
        if (mounted && _showRouteInfo && !_isRouteInfoMinimized) {
          print('🗺️ ⏰ Auto-minimizing route info after 8 seconds');
          setState(() {
            _isRouteInfoMinimized = true;
          });
          HapticFeedback.lightImpact();
        }
      });

      // Hide main navigation dock when route is active
      hideDockNotifier.value = true;

      // Pass order with route info to main page for swipe interface
      final orderWithRoute = Map<String, dynamic>.from(order);
      orderWithRoute['routeDistance'] = totalDistance;
      orderWithRoute['routeDuration'] = totalDuration;

      // Add current driver location for database storage
      if (currentLocation != null) {
        orderWithRoute['driverStartLat'] = currentLocation!.latitude;
        orderWithRoute['driverStartLng'] = currentLocation!.longitude;
        print(
          '📍 Driver start location: ${currentLocation!.latitude}, ${currentLocation!.longitude}');
      }

      // Add pickup coordinates
      orderWithRoute['pickupLat'] = pickupLocation.latitude;
      orderWithRoute['pickupLng'] = pickupLocation.longitude;
      print(
        '📍 Pickup location: ${pickupLocation.latitude}, ${pickupLocation.longitude}');

      // Add delivery coordinates
      orderWithRoute['deliveryLat'] = deliveryLocation.latitude;
      orderWithRoute['deliveryLng'] = deliveryLocation.longitude;
      print(
        '📍 Delivery location: ${deliveryLocation.latitude}, ${deliveryLocation.longitude}');

      print('📱 SETTING activeOrderNotifier with route info:');
      print('   Order ID: ${order['order_id'] ?? order['id']}');
      print('   Route Distance: ${totalDistance.toStringAsFixed(1)} km');
      print('   Route Duration: ${totalDuration.round()} min');
      print('   This should trigger bottom sheet in main_page!');

      activeOrderNotifier.value = orderWithRoute;

      print('🚫 DOCK HIDDEN - Route is now active');
      print('   _routePoints.length: ${_routePoints.length}');
      print('   _showRouteInfo: $_showRouteInfo');
      print('   hideDockNotifier.value: ${hideDockNotifier.value}');
      print('   activeOrderNotifier.value: ${activeOrderNotifier.value}');
      print('   📍 Route distance: ${totalDistance.toStringAsFixed(1)} km');
      print('   ⏱️ Route duration: ${totalDuration.round()} min');

      // Smooth camera animation to center on route (Uber-style)
      if (completeRoute.isNotEmpty) {
        _animateCameraToRoute(completeRoute);
      }
    } catch (e) {
      print('Error calculating complete route: $e');
      TopNotification.success(
        context,
        AppLocalizations.of(context)?.errorCalculatingRoute ?? AppLocalizations.of(context)!.tr('Error calculating route.'),

        // red error
      );
    }
  }

  // Center map on the complete route
  void _centerMapOnRoute(List<LatLng> routePoints) {
    if (routePoints.isEmpty) return;

    // Calculate bounds of all points including some padding
    double minLat = routePoints.first.latitude;
    double maxLat = routePoints.first.latitude;
    double minLng = routePoints.first.longitude;
    double maxLng = routePoints.first.longitude;

    for (final point in routePoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    // Add padding to the bounds (10% on each side)
    final latPadding = (maxLat - minLat) * 0.1;
    final lngPadding = (maxLng - minLng) * 0.1;

    minLat -= latPadding;
    maxLat += latPadding;
    minLng -= lngPadding;
    maxLng += lngPadding;

    // Calculate center
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    // Calculate appropriate zoom level to fit bounds
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = math.max(latDiff, lngDiff);

    // Determine zoom level based on the extent
    double zoom = 10.0; // Default zoom
    if (maxDiff > 0.5) {
      zoom = 8.0; // Very wide area
    } else if (maxDiff > 0.2)
      zoom = 9.0; // Wide area
    else if (maxDiff > 0.1)
      zoom = 10.0; // Medium area
    else if (maxDiff > 0.05)
      zoom = 11.0; // Small area
    else
      zoom = 12.0; // Very small area

    print(
      'Route bounds: lat($minLat, $maxLat), lng($minLng, $maxLng), zoom: $zoom');

    // Move map to center with calculated zoom
    try {
      _mapController.move(center, zoom);
    } catch (e) {
      print('Error centering map: $e');
    }
  }

  // Uber-style animated camera movement to route
  void _animateCameraToRoute(List<LatLng> routePoints) async {
    if (routePoints.isEmpty) return;

    print('📸 Animating camera to route with ${routePoints.length} points');
    print(
      '📍 First point (START): ${routePoints.first.latitude}, ${routePoints.first.longitude}');
    print(
      '🎯 Last point (END): ${routePoints.last.latitude}, ${routePoints.last.longitude}');

    // Calculate bounds
    double minLat = routePoints.first.latitude;
    double maxLat = routePoints.first.latitude;
    double minLng = routePoints.first.longitude;
    double maxLng = routePoints.first.longitude;

    for (final point in routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    print('📏 Route bounds: lat($minLat to $maxLat), lng($minLng to $maxLng)');

    // Add MORE padding to ensure markers are fully visible (increased from 0.15 to 0.25)
    final latPadding = (maxLat - minLat) * 0.25;
    final lngPadding = (maxLng - minLng) * 0.25;

    minLat -= latPadding;
    maxLat += latPadding;
    minLng -= lngPadding;
    maxLng += lngPadding;

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    print('🎯 Camera center: ${center.latitude}, ${center.longitude}');

    // Calculate zoom - reduced zoom levels to show more area
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = math.max(latDiff, lngDiff);

    double zoom = 11.0; // Reduced default zoom
    if (maxDiff > 0.5) {
      zoom = 7.0; // Reduced from 8.0
    } else if (maxDiff > 0.2)
      zoom = 8.0; // Reduced from 9.0
    else if (maxDiff > 0.1)
      zoom = 9.0; // Reduced from 10.0
    else if (maxDiff > 0.05)
      zoom = 10.0; // Reduced from 11.0
    else
      zoom = 12.0; // Reduced from 13.0

    print('🔍 Calculated zoom level: $zoom (maxDiff: $maxDiff)');

    // Smooth animated movement (Uber-style)
    try {
      // Animate to target position with easing
      const steps = 30;
      final currentCenter = _mapController.camera.center;
      final currentZoom = _mapController.camera.zoom;

      for (int i = 0; i <= steps; i++) {
        await Future.delayed(const Duration(milliseconds: 16)); // ~60fps

        if (!mounted) break;

        // Easing function (ease-out-cubic)
        final t = i / steps;
        final ease = 1 - math.pow(1 - t, 3);

        final lat =
            currentCenter.latitude +
            (center.latitude - currentCenter.latitude) * ease;
        final lng =
            currentCenter.longitude +
            (center.longitude - currentCenter.longitude) * ease;
        final z = currentZoom + (zoom - currentZoom) * ease;

        _mapController.move(LatLng(lat, lng), z);
      }

      print('✅ Camera animation complete');
      HapticFeedback.lightImpact();
    } catch (e) {
      print('❌ Error animating camera: $e');
    }
  }

  // Start Uber-style route drawing animation
  void _startRouteDrawingAnimation() {
    _routeAnimationController?.dispose();

    _routeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this);

    _routeAnimation = CurvedAnimation(
      parent: _routeAnimationController!,
      curve: Curves.easeInOut);

    _routeAnimation!.addListener(() {
      if (mounted) {
        setState(() {
          // Rebuild to animate route drawing
        });
      }
    });

    _routeAnimationController!.forward();
    HapticFeedback.mediumImpact();
  }

  // Handle pickup order action
  void _handlePickupOrder(
    Map<String, dynamic> order,
    Map<String, dynamic>? routeData) async {
    Navigator.pop(context); // Close modal

    // Calculate complete route: Current location -> Pickup -> Delivery
    await _calculateAndShowCompleteRoute(order);

    // Show success notification
    TopNotification.success(
      context,
      AppLocalizations.of(context)!.tr('Route being calculated and displayed...') ?? AppLocalizations.of(context)!.tr('Route being calculated and displayed...'),

      // blue info
    );

    // Expand map to show full route
    setState(() {
      selectedOrderId = null;
      _isMapExpanded = true;
    });
  }

  // Show cluster modal with list of orders
  void _showClusterModal(List<Map<String, dynamic>> orders) {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final isLight = appSettings.isLightMode(context);

    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            // Drag Handle - Trade Republic Style
            DragHandle(),

            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.group,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.clusteredOrders ?? AppLocalizations.of(context)!.tr('Clustered Orders'),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                          letterSpacing: -0.4, color: isLight ? Colors.black : Colors.white)),
                      Text(
                        '${orders.length} orders in this area',
                        style: TextStyle(
                          fontSize: 13,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          fontWeight: FontWeight.w500)),
                    ])),
              ]),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

            // Orders List
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final delivery = order['delivery'] as Map<String, dynamic>?;
                  final customer = order['customer'] as Map<String, dynamic>?;
                  final items = List<Map<String, dynamic>>.from(
                    order['items'] ?? []);

                  // Check if this order has an active auction
                  final orderId = order['id'] ?? order['order_id'];
                  final auction = _getAuctionForOrder(orderId);
                  final hasAuction = auction != null;

                  // Check if order is already accepted
                  final acceptanceStatus =
                      (order['acceptance_status']?.toString() ?? AppLocalizations.of(context)!.tr('available'));
                  final isAccepted =
                      acceptanceStatus == 'accepted' ||
                      acceptanceStatus == 'picked_up';

                  // Check if this is an emergency order - other drivers should be able to help
                  final isEmergency =
                      order['has_issue'] == 1 ||
                      order['has_issue'] == true ||
                      order['issue_emergency'] == 1 ||
                      order['issue_emergency'] == true ||
                      order['emergency'] == 1 ||
                      order['emergency'] == true ||
                      order['accident_reported'] == 1 ||
                      order['accident_reported'] == true;

                  return TradeRepublicTap(
                    onTap: (isAccepted && !isEmergency)
                        ? null
                        : () {
                            print(
                              '🎯 Cluster item tapped: Order #${order['id']}, index: $index');
                            print('🎯 Order data keys: ${order.keys}');

                            // Check if this order has an auction
                            final orderId = order['id'] ?? order['order_id'];
                            final auction = _getAuctionForOrder(orderId);

                            // Show order modal - now always active in fullscreen design
                            final latLng = _getPickupCoordinatesSync(order);
                            print('🎯 Got pickup coordinates: $latLng');

                            // Close the current modal first
                            Navigator.pop(context);

                            // Use addPostFrameCallback to avoid navigator lock
                            if (latLng != null) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (auction != null) {
                                  print(
                                    '🎯 Order has auction - showing auction modal');
                                  _showAuctionModal(auction, latLng);
                                } else {
                                  print(
                                    '🎯 No auction - creating auction-like data from order');
                                  // Create auction-like data from order for display
                                  final orderAsAuction = {
                                    ...order,
                                    'order_id':
                                        order['id'] ?? order['order_id'],
                                    'order_total':
                                        order['amount'] ?? order['total'],
                                    'order_cart': order['cart'],
                                    'delivery_address':
                                        order['deliveryAddress'] ??
                                        order['address'],
                                    'pickup_address':
                                        order['pickup']?['address'] ??
                                        AppLocalizations.of(context)?.pickupLocation ?? AppLocalizations.of(context)!.tr('Pickup location'),
                                  };
                                  _showAuctionModal(orderAsAuction, latLng);
                                }
                              });
                            } else {
                              print(
                                '❌ No pickup coordinates for order ${order['id']}');
                            }
                          },
                    child: Opacity(
                      opacity: (isAccepted && !isEmergency) ? 0.5 : 1.0,
                      child: Container(
                        key: Key('cluster_order_${order['id']}_$index'),
                        margin: EdgeInsets.only(bottom: 12),
                        padding: DesktopAppWrapper.getPagePadding(),
                        decoration: BoxDecoration(
                          color: isEmergency
                              ? const Color(0xFFFF3B30).withOpacity(0.08)
                              : (isLight
                                  ? Colors.white.withOpacity(0.8)
                                  : Colors.black.withOpacity(0.8)),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          boxShadow: [
                            BoxShadow(
                              color: isEmergency
                                  ? const Color(0xFFFF3B30).withOpacity(0.3)
                                  : Colors.black.withOpacity(0.05),
                              blurRadius: isEmergency ? 12 : 8,
                              spreadRadius: 0,
                              offset: const Offset(0, 2)),
                          ]),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: order['priority'] == 'urgent'
                                          ? [
                                              Colors.red.shade400,
                                              Colors.red.shade600,
                                            ]
                                          : order['priority'] == 'high'
                                          ? [
                                              Colors.orange.shade400,
                                              Colors.orange.shade600,
                                            ]
                                          : [
                                              Colors.green.shade400,
                                              Colors.green.shade600,
                                            ]),
                                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            (order['priority'] == 'urgent'
                                                    ? Colors.red
                                                    : order['priority'] ==
                                                          'high'
                                                    ? Colors.orange
                                                    : Colors.green)
                                                .withOpacity(0.3),
                                        blurRadius: 6,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 2)),
                                    ]),
                                  child: Icon(
                                    CupertinoIcons.cube_box,
                                    color: Colors.white,
                                    size: 16)),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}${order['order_id'] ?? order['id']}',
                                        style: TextStyle(
                                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                                          fontWeight: FontWeight.w700,
                                          // NO strikethrough for emergency orders
                                          decoration:
                                              (order['acceptance_status'] !=
                                                      'available' &&
                                                  !isEmergency)
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                          color: isEmergency
                                              ? const Color(0xFFFF3B30)
                                              : isLight
                                              ? Colors.black87
                                              : Colors.white)),
                                      // Show AUCTION badge if order has an active auction
                                      if (hasAuction) ...[
                                        SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              CupertinoIcons.hammer,
                                              size: 12,
                                              color: Colors.amber.shade600),
                                            SizedBox(width: 4),
                                            Text(
                                              AppLocalizations.of(context)?.auction ?? AppLocalizations.of(context)!.tr('AUCTION'),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.amber.shade600)),
                                          ]),
                                      ],
                                      Text(
                                        '${AppLocalizations.of(context)?.customerLabel ?? AppLocalizations.of(context)!.tr('Customer')}: ${customer?['name'] ?? order['username'] ?? AppLocalizations.of(context)!.tr('Unknown')}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          // NO strikethrough for emergency orders
                                          decoration:
                                              (order['acceptance_status'] !=
                                                      'available' &&
                                                  !isEmergency)
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                          color: isEmergency
                                              ? const Color(0xFFFF3B30)
                                              : (isLight
                                                        ? Colors.black
                                                        : Colors.white)
                                                    .withOpacity(0.7))),
                                    ])),
                              ]),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                            // Items preview
                            if (items.isNotEmpty) ...[
                              Text(
                                '${AppLocalizations.of(context)?.items ?? AppLocalizations.of(context)!.tr('Items')}: ${items.map((item) => '${item['name']} x${item['quantity'] ?? 1}').join(', ')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.6)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            ],

                            // Delivery address
                            if (delivery != null) ...[
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.location_solid,
                                    size: 14,
                                    color: Colors.blue.shade600),
                                  SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${delivery['address'] ?? (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr(''))}, ${delivery['city'] ?? delivery['country'] ?? (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr(''))}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.6)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                                ]),
                            ],
                          ]))));
                })),
          ])));
  }

  // Show accept order modal - Trade Republic style
  void _showAcceptOrderModal(Map<String, dynamic> order, bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.checkmark_seal,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.acceptOrder ?? AppLocalizations.of(context)!.tr('Accept Order'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          // Content
          Text(
            '${AppLocalizations.of(context)?.doYouWantToAccept ?? AppLocalizations.of(context)!.tr('Do you want to accept order')} ${order['order_id'] ?? order['id']}?',
            style: TextStyle(
              fontSize: 15,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
              fontWeight: FontWeight.w500),
            textAlign: TextAlign.center),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                  onPressed: () => Navigator.pop(context),
                  isSecondary: true)),
              SizedBox(width: 12),
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)?.accept ?? AppLocalizations.of(context)!.tr('Accept'),
                  onPressed: () {
                    Navigator.pop(context);
                    _acceptOrder(order);
                  })),
            ]),
        ]));
  }

  void _showCurrentLocation() async {
    // If location is null, try to get current location first
    if (currentLocation == null) {
      // Try to get location
      await _getCurrentLocation();

      // Check if we got location now
      if (currentLocation == null) {
        TopNotification.warning(
          context,
          AppLocalizations.of(context)?.couldNotGetLocation ?? AppLocalizations.of(context)!.tr('Could not get location. Please enable GPS and location permissions.'));
        return;
      }
    }

    // Now we have location, move map to it
    try {
      print(
        '📍 Moving map to current location: ${currentLocation!.latitude}, ${currentLocation!.longitude}');

      // Platform-specific camera movement
      if (Platform.isIOS && _appleMapController != null && _isMapReady) {
        // iOS: Use Apple Maps controller
        print('🍎 Using Apple Maps controller to move camera');
        _appleMapController!.animateCamera(
          apple.CameraUpdate.newCameraPosition(
            apple.CameraPosition(
              target: apple.LatLng(
                currentLocation!.latitude,
                currentLocation!.longitude),
              zoom: 15.0)));

        // Show confirmation message
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.centeredOnYourLocation ?? AppLocalizations.of(context)!.tr('Centered on your location'),

          // green success
        );
      } else {
        // Other platforms: Use FlutterMap controller
        print('🗺️ Using FlutterMap controller to move camera');
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && currentLocation != null) {
            _mapController.move(currentLocation!, 15.0);

            // Show confirmation message
            TopNotification.success(
              context,
              AppLocalizations.of(context)?.centeredOnYourLocation ?? AppLocalizations.of(context)!.tr('Centered on your location'),

              // green success
            );
          }
        });
      }
    } catch (e) {
      print('Error moving map to location: $e');
      TopNotification.success(
        context,
        AppLocalizations.of(context)!.tr('Map not ready yet. Please try again.') ?? AppLocalizations.of(context)!.tr('Map not ready yet. Please try again.'),

        // orange info
      );
    }
  }

  // Silent method to center map on current location (no notifications)
  void _centerMapOnLocation() {
    if (currentLocation == null) return;

    try {
      if (Platform.isIOS && _appleMapController != null && _isMapReady) {
        _appleMapController!.animateCamera(
          apple.CameraUpdate.newCameraPosition(
            apple.CameraPosition(
              target: apple.LatLng(
                currentLocation!.latitude,
                currentLocation!.longitude),
              zoom: 14.0)));
      } else if (mounted) {
        _mapController.move(currentLocation!, 14.0);
      }
    } catch (e) {
      print('Error centering map: $e');
    }
  }

  // Open in Apple Maps (iOS only)
  void _openInAppleMaps() async {
    if (!Platform.isIOS) {
      TopNotification.error(context, AppLocalizations.of(context)?.appleMapsOnlyOnIos ?? AppLocalizations.of(context)!.tr('Apple Maps is only available on iOS'));
      return;
    }

    try {
      LatLng? targetLocation;
      String locationName = 'Current Location';

      // If there's an active route, show the route in Apple Maps
      if (_activeRouteInfo != null && _routePoints.isNotEmpty) {
        final pickupLocation = _getPickupCoordinatesSync(_activeRouteInfo!);
        final deliveryLocation = _getDeliveryCoordinatesSync(_activeRouteInfo!);

        if (pickupLocation != null && deliveryLocation != null) {
          // Open Apple Maps with directions from pickup to delivery
          final url =
              'http://maps.apple.com/?saddr=${pickupLocation.latitude},${pickupLocation.longitude}&daddr=${deliveryLocation.latitude},${deliveryLocation.longitude}&dirflg=d';

          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url));
            TopNotification.success(context, AppLocalizations.of(context)?.openingRouteInAppleMaps ?? AppLocalizations.of(context)!.tr('Opening route in Apple Maps'));
          } else {
            TopNotification.error(context, AppLocalizations.of(context)?.couldNotOpenAppleMaps ?? AppLocalizations.of(context)!.tr('Could not open Apple Maps'));
          }
          return;
        }
      }

      // If no active route, show current location or map center
      if (currentLocation != null) {
        targetLocation = currentLocation!;
        locationName = 'Your Location';
      } else {
        // Fallback to map center
        targetLocation = LatLng(53.5511, 9.9937); // Hamburg center
        locationName = 'Map Location';
      }

      final url =
          'http://maps.apple.com/?ll=${targetLocation.latitude},${targetLocation.longitude}&q=$locationName';

      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
        TopNotification.success(context, AppLocalizations.of(context)?.openingLocationInAppleMaps ?? AppLocalizations.of(context)!.tr('Opening in Apple Maps'));
      } else {
        TopNotification.error(context, AppLocalizations.of(context)?.couldNotOpenAppleMaps ?? AppLocalizations.of(context)!.tr('Could not open Apple Maps'));
      }
    } catch (e) {
      print('Error opening Apple Maps: $e');
      TopNotification.error(context, AppLocalizations.of(context)?.failedToOpenAppleMaps ?? AppLocalizations.of(context)!.tr('Could not open Apple Maps'));
    }
  }

  // ── Persist map settings locally ──

  Future<void> _loadMapSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isAll = prefs.getBool('delvioo_search_radius_all') ?? false;
      final savedRadius = prefs.getDouble('delvioo_search_radius') ?? 75.0;
      if (mounted) {
        setState(() {
          if (isAll) {
            _searchRadius = double.infinity;
            _displayRadius = double.infinity;
          } else {
            _searchRadius = savedRadius;
            _displayRadius = savedRadius;
          }
        });
      }
    } catch (e) {
      print('⚙️ Could not load map settings: $e');
    }
  }

  Future<void> _saveMapSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isAll = _searchRadius.isInfinite;
      await prefs.setBool('delvioo_search_radius_all', isAll);
      if (!isAll) {
        await prefs.setDouble('delvioo_search_radius', _searchRadius);
      }
    } catch (e) {
      print('⚙️ Could not save map settings: $e');
    }
  }

  void _showSettingsModal() {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final isLight = appSettings.isLightMode(context);

    double tempSearchRadius = _searchRadius.isInfinite ? 75.0 : _searchRadius;
    bool tempIsAll = _searchRadius.isInfinite;

    TradeRepublicBottomSheet.show(
      context: context,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          // Helper to build a preset chip
          Widget buildPresetChip({
            required String label,
            required bool isSelected,
            required VoidCallback onTap,
          }) {
            final activeColor = isLight ? Colors.black : Colors.white;
            final inactiveTextColor = (isLight ? Colors.black : Colors.white).withOpacity(0.7);
            return TradeRepublicTap(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? (isLight ? Colors.black : Colors.white)
                      : (isLight ? Colors.black : Colors.white).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? (isLight ? Colors.white : Colors.black)
                        : inactiveTextColor))));
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DragHandle(),

              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.map,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.mapSettings ?? AppLocalizations.of(context)!.tr('Map Settings'),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
                ]),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              // Search Radius Section
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.searchRadius ?? AppLocalizations.of(context)!.tr('Search Radius'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white)),
                      Text(
                        tempIsAll
                            ? 'All'
                            : appSettings.formatDistance(tempSearchRadius),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white)),
                    ]),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Text(
                    AppLocalizations.of(context)?.onlyOrdersWithinRadius ?? AppLocalizations.of(context)!.tr('Only orders within this radius will be shown'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5))),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // ── Quick preset chips ──
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      buildPresetChip(
                        label: appSettings.formatDistance(25.0),
                        isSelected: !tempIsAll && (tempSearchRadius - 25.0).abs() < 0.5,
                        onTap: () => setModalState(() { tempIsAll = false; tempSearchRadius = 25.0; })),
                      buildPresetChip(
                        label: appSettings.formatDistance(75.0),
                        isSelected: !tempIsAll && (tempSearchRadius - 75.0).abs() < 0.5,
                        onTap: () => setModalState(() { tempIsAll = false; tempSearchRadius = 75.0; })),
                      buildPresetChip(
                        label: appSettings.formatDistance(150.0),
                        isSelected: !tempIsAll && (tempSearchRadius - 150.0).abs() < 0.5,
                        onTap: () => setModalState(() { tempIsAll = false; tempSearchRadius = 150.0; })),
                      buildPresetChip(
                        label: AppLocalizations.of(context)!.tr('All') ?? AppLocalizations.of(context)!.tr('All'),
                        isSelected: tempIsAll,
                        onTap: () => setModalState(() { tempIsAll = true; })),
                    ]),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // ── Continuous slider (disabled when "All" is active) ──
                  Opacity(
                    opacity: tempIsAll ? 0.35 : 1.0,
                    child: IgnorePointer(
                      ignoring: tempIsAll,
                      child: TradeRepublicContinuousSlider(
                        value: tempSearchRadius,
                        min: 1.0,
                        max: 200.0,
                        divisions: 199,
                        labelBuilder: (v) => appSettings.formatDistance(v),
                        onChanged: (v) => setModalState(() {
                          tempSearchRadius = v;
                          tempIsAll = false;
                        })))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          appSettings.formatDistance(1.0),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w700,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(tempIsAll ? 0.25 : 0.6))),
                        Text(
                          appSettings.formatDistance(200.0),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w700,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(tempIsAll ? 0.25 : 0.6))),
                      ])),
                ]),

              SizedBox(height: 20),

              // Apply Button
              TradeRepublicButton(
                label: AppLocalizations.of(context)?.apply ?? AppLocalizations.of(context)!.tr('Apply'),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  final newRadius = tempIsAll ? double.infinity : tempSearchRadius;
                  setState(() {
                    _searchRadius = newRadius;
                    _displayRadius = newRadius;
                  });
                  _saveMapSettings(); // persist locally
                  final label = tempIsAll
                      ? 'All'
                      : Provider.of<AppSettings>(context, listen: false).formatDistance(newRadius);
                  Navigator.pop(context);
                  if (mounted) {
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) {
                        TopNotification.success(
                          context,
                          'Search radius updated to $label');
                      }
                    });
                  }
                }),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

              // Cancel button
              TradeRepublicButton(
                label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                isSecondary: true,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                }),
            ]);
        }));
  }

  // Helper to compare LatLng lists for caching
  bool _listEquals(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) return false;
    }
    return true;
  }

  // Build traffic-aware polylines with different colors for different traffic conditions
  // WITH UBER-STYLE DRAWING ANIMATION
  List<Polyline> _buildTrafficAwarePolylines() {
    if (_routePoints.isEmpty) {
      _cachedTrafficPolylines = [];
      _cachedTrafficRoutePoints = [];
      return [];
    }

    final animationValue = _routeAnimation?.value ?? 1.0;
    // Return cached if nothing changed
    if (_cachedTrafficRoutePoints.isNotEmpty &&
        _listEquals(_cachedTrafficRoutePoints, _routePoints) &&
        _cachedTrafficAnimationValue == animationValue) {
      return _cachedTrafficPolylines;
    }

    _cachedTrafficRoutePoints = List.from(_routePoints);
    _cachedTrafficAnimationValue = animationValue;

    final animatedPointCount = (_routePoints.length * animationValue).round();
    final animatedRoutePoints = _routePoints
        .take(animatedPointCount.clamp(2, _routePoints.length))
        .toList();

    if (animatedRoutePoints.length < 2) {
      _cachedTrafficPolylines = [];
      return [];
    }

    _cachedTrafficPolylines = [
      // Shadow/outline layer
      Polyline(
        points: animatedRoutePoints,
        color: Colors.black.withOpacity(0.2),
        strokeWidth: 10.0),
      // White border layer
      Polyline(
        points: animatedRoutePoints,
        color: Colors.white,
        strokeWidth: 7.0),
      // Main route line
      Polyline(
        points: animatedRoutePoints,
        color: const Color(0xFF000000),
        strokeWidth: 5.0),
    ];

    return _cachedTrafficPolylines;
  }


  // Swipe handlers now integrated inline with pan gestures

  // Animation methods removed - now using direct state updates in pan gestures

  // Show success animation when order is accepted
  void _showSuccessAnimation(dynamic orderId) {
    // Strong haptic feedback for success
    HapticFeedback.heavyImpact();

    // Show overlay with success animation
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) =>
          _SuccessAnimationWidget(onComplete: () => overlayEntry.remove()));

    overlay.insert(overlayEntry);
  }

  // Accept order API call
  Future<void> _acceptOrderViaSwipe(dynamic orderId) async {
    if (_isAccepting) return;

    print('🚀 Starting order acceptance for orderId: $orderId');

    setState(() {
      _isAccepting = true;
    });

    try {
      // Find the order by ID - check both internal ID and display ID
      print(
        '🔍 Looking for order with ID: $orderId (type: ${orderId.runtimeType})');
      print(
        '📋 Available orders: ${_filteredOrders.map((o) => 'id:${o['id']}, order_id:${o['order_id']}').toList()}');

      Map<String, dynamic> order;
      try {
        // First try to find by internal ID
        order = _filteredOrders.firstWhere(
          (o) => o['id'].toString() == orderId.toString());
        print('✅ Found order by internal ID: ${order['id']}');
      } catch (e) {
        try {
          // Then try to find by order_id (display ID)
          order = _filteredOrders.firstWhere(
            (o) => o['order_id'].toString() == orderId.toString());
          print('✅ Found order by order_id: ${order['order_id']}');
        } catch (e2) {
          // Finally try to find by formatted display ID (DEL-000001 format)
          final orderIdStr = orderId.toString();
          if (orderIdStr.startsWith('DEL-')) {
            final numericPart = orderIdStr
                .replaceAll('DEL-', '')
                .replaceAll(RegExp(r'^0+'), '');
            if (numericPart.isEmpty) throw Exception('Invalid order ID format');
            order = _filteredOrders.firstWhere(
              (o) =>
                  o['id'].toString() == numericPart ||
                  o['order_id'].toString() == numericPart,
              orElse: () => throw Exception('Order not found'));
            print(
              '✅ Found order by numeric part: $numericPart -> ${order['id']}');
          } else {
            throw Exception('Order not found with ID: $orderId');
          }
        }
      }

      print(
        '📦 Found order: id=${order['id']}, order_id=${order['order_id']}, status: ${order['acceptance_status']}');

      // Get pickup and delivery locations
      final pickupLocation = _getPickupCoordinatesSync(order);
      final deliveryLocation = _getDeliveryCoordinatesSync(order);

      print('📍 Pickup location: $pickupLocation');
      print('🏠 Delivery location: $deliveryLocation');

      // Generiere einen 8-stelligen Sicherheitscode
      final random = math.Random(orderId.hashCode);
      String securityCode = '';
      for (int i = 0; i < 8; i++) {
        securityCode += random.nextInt(10).toString();
      }

      print('🔑 Generated security code: $securityCode');

      // Use the internal numeric order ID for the API call
      final numericOrderId =
          order['id']; // This should be the numeric ID like 1, 2, 3...
      print(
        '🔢 Using numeric order ID for API: $numericOrderId (from order: ${order['id']})');

      final requestBody = {
        'orderId': numericOrderId, // Send numeric ID to backend
        'driverId': 1, // TODO: Get actual driver ID from authentication
        'routeDistance': _activeRouteInfo?['totalDistance'] ?? 0.0,
        'routeDuration': _activeRouteInfo?['totalDuration'] ?? 0.0,
        'pickupLat': pickupLocation?.latitude,
        'pickupLng': pickupLocation?.longitude,
        'deliveryLat': deliveryLocation?.latitude,
        'deliveryLng': deliveryLocation?.longitude,
        'securityCode': securityCode,
      };

      print(
        '📤 Sending request to: ${ApiConfig.baseUrl}/api/delvioo/accept-order');
      print('📤 Request body: $requestBody');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/accept-order'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody));

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Parsed response: $result');

        if (result['success']) {
          // Add order to accepted orders list
          final acceptedOrder = Map<String, dynamic>.from(order);
          acceptedOrder['acceptedAt'] = DateTime.now().toIso8601String();
          acceptedOrder['status'] = 'accepted';
          acceptedOrder['security_code'] = securityCode;
          _acceptedOrders.add(acceptedOrder);

          // Show success message with proper display ID FIRST (at top)
          final displayOrderId =
              order['order_id'] ??
              'DEL-${numericOrderId.toString().padLeft(6, '0')}';
          TopNotification.success(
            context,
            'Order #$displayOrderId accepted successfully! 🎉');

          // Success - show celebration animation
          _showSuccessAnimation(orderId);

          // Wait for animation then hide route
          await Future.delayed(const Duration(milliseconds: 1000));

          // Clear route and hide swipe interface
          setState(() {
            _showRouteInfo = false;
            _activeRouteInfo = null;
            _routePoints.clear();
            _trafficSegments.clear();
            _swipeProgress = 0.0;
          });

          // Show dock again after successful acceptance
          hideDockNotifier.value = false;

          // Clear activeOrderNotifier to hide swipe interface in main page
          activeOrderNotifier.value = null;

          // Show main navigation dock when route is cleared after accepting order
          hideDockNotifier.value = false;

          print('✅ Order accepted - Dock shown, swipe hidden');

          // Check for existing active orders and combine them
          await _checkAndCombineWithActiveOrders(acceptedOrder);

          // Refresh both orders and accepted orders to update UI
          _loadOrders();
          _loadAcceptedOrders();

          // Force map markers to rebuild with new status
          setState(() {
            _lastMarkerCount = 0; // Reset marker count to force rebuild
          });
        } else {
          throw Exception(result['message'] ?? AppLocalizations.of(context)!.tr('Failed to accept order'));
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('💥 Error accepting order: $e');
      print('💥 Stack trace: ${StackTrace.current}');

      // Show user-friendly error message
      String errorMessage = 'Failed to accept order';
      if (e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        errorMessage = 'Network error - check your connection';
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = 'Request timed out - try again';
      } else if (e.toString().contains('Order not found')) {
        errorMessage = 'Order no longer available';
      }

      TopNotification.success(
        context,
        errorMessage,

        // red error
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
          _swipeProgress = 0.0;
        });
      }
    }
  }

  // Message Modal with Apple iOS/macOS 26 Design (Performance optimized)
  void _showMessageModal(
    BuildContext context,
    Map<String, dynamic> order,
    bool isLight) {
    // Extract order ID - handle both int and string formats
    final orderIdRaw = order['order_id'] ?? order['id'];
    final orderId = orderIdRaw is int
        ? orderIdRaw
        : (orderIdRaw is String
              ? (int.tryParse(orderIdRaw.replaceAll(RegExp(r'[^0-9]'), '')) ??
                    0)
              : 0);

    final customer = order['customer'] as Map<String, dynamic>? ?? {};
    final customerName = customer['name'] ??
      order['username'] ??
      (AppLocalizations.of(context)?.customer ?? AppLocalizations.of(context)!.tr(''));

    print('🚀 Opening chat for order $orderId, customer: $customerName');

    TradeRepublicBottomSheet.show(
      context: context,
      enableDrag: true,
      isDismissible: true,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      child: _buildLiquidGlassChatBottomSheet(
        orderId,
        customerName,
        isLight,
        context));
  }

  Widget _buildLiquidGlassChatBottomSheet(
    int orderId,
    String customerName,
    bool isLight,
    BuildContext context) {
    final TextEditingController messageController = TextEditingController();

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          builder: (context, slideValue, child) {
            return Transform.translate(
              offset: Offset(0, 100 * (1 - slideValue)),
              child: Transform.scale(
                scale: 0.95 + (0.05 * slideValue),
                child: Opacity(
                  opacity: slideValue.clamp(0.0, 1.0),
                  child: Container(
                    height: MediaQuery.of(context).size.height * 0.95,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isLight
                            ? [
                                Colors.white.withOpacity(0.98),
                                Colors.white.withOpacity(0.95),
                                Colors.white.withOpacity(0.92),
                              ]
                            : [
                                Colors.black.withOpacity(0.98),
                                Colors.black.withOpacity(0.95),
                                Colors.black.withOpacity(0.92),
                              ]),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: isLight
                              ? Colors.black.withOpacity(0.12 * slideValue)
                              : Colors.black.withOpacity(0.4 * slideValue),
                          blurRadius: 40,
                          spreadRadius: 0,
                          offset: const Offset(0, -8)),
                      ]),
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20)),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isLight
                                  ? [
                                      Colors.white.withOpacity(0.9),
                                      Colors.white.withOpacity(0.85),
                                    ]
                                  : [
                                      Colors.black.withOpacity(0.9),
                                      Colors.black.withOpacity(0.85),
                                    ])),
                          child: Column(
                            children: [
                              // Trade Republic Drag Handle
                              Padding(
                                padding: EdgeInsets.only(top: 18, bottom: 20),
                                child: DragHandle()),

                              // Floating Header Island
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  20),
                                child: SafeArea(
                                  bottom: false,
                                  child: Container(
                                    padding: DesktopAppWrapper.getPagePadding(),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: isLight
                                            ? [
                                                Colors.white.withOpacity(0.95),
                                                Colors.white.withOpacity(0.9),
                                              ]
                                            : [
                                                Colors.black.withOpacity(0.95),
                                                Colors.black.withOpacity(0.9),
                                              ]),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: isLight
                                              ? Colors.black.withOpacity(0.12)
                                              : Colors.black.withOpacity(0.5),
                                          blurRadius: 25,
                                          spreadRadius: -2,
                                          offset: const Offset(0, 8)),
                                      ]),
                                    child: Row(
                                      children: [
                                        TradeRepublicButton.icon(
                                          icon: Icon(
                                            CupertinoIcons.chevron_left,
                                            color: Colors.white,
                                            size: 18),
                                          backgroundColor: Colors.red[600],
                                          size: 40,
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            Navigator.pop(context);
                                          }),
                                        SizedBox(width: 16),
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.blue.withOpacity(0.15),
                                                Colors.blue.withOpacity(0.1),
                                              ]),
                                            borderRadius: BorderRadius.circular(
                                              25)),
                                          child: Icon(
                                            CupertinoIcons.person,
                                            color: Colors.blue,
                                            size: 22)),
                                        SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                customerName,
                                                style: TextStyle(
                                                  fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                                  fontWeight: FontWeight.w700,
                                                  color: isLight
                                                      ? Colors.black
                                                      : Colors.white)),
                                              Text(
                                                '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}$orderId',
                                                style: TextStyle(
                                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                                  fontWeight: FontWeight.w500,
                                                  color:
                                                      (isLight
                                                              ? Colors.black
                                                              : Colors.white)
                                                          .withOpacity(0.6))),
                                            ])),
                                      ])))),

                              // Messages Area
                              Expanded(
                                child: ListView(
                                  padding: DesktopAppWrapper.getPagePadding(),
                                  children: [
                                    Center(
                                      child: Text(
                                        AppLocalizations.of(context)?.noMessagesYet ?? AppLocalizations.of(context)!.tr('No messages yet'),
                                        style: TextStyle(
                                          color:
                                              (isLight
                                                      ? Colors.black
                                                      : Colors.white)
                                                  .withOpacity(0.5),
                                          fontSize: DesktopOptimizedWidgets.getFontSize()))),
                                  ])),

                              // Input Island
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  24),
                                child: SafeArea(
                                  top: false,
                                  child: Container(
                                    padding: DesktopAppWrapper.getPagePadding(),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isLight
                                            ? [
                                                Colors.white.withOpacity(0.95),
                                                Colors.white.withOpacity(0.9),
                                              ]
                                            : [
                                                Colors.black.withOpacity(0.95),
                                                Colors.black.withOpacity(0.9),
                                              ]),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: isLight
                                              ? Colors.black.withOpacity(0.15)
                                              : Colors.black.withOpacity(0.6),
                                          blurRadius: 25,
                                          offset: const Offset(0, 8)),
                                      ]),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: isLight
                                                    ? [
                                                        Colors.white
                                                            .withOpacity(0.9),
                                                        Colors.white
                                                            .withOpacity(0.7),
                                                      ]
                                                    : [
                                                        Colors.black
                                                            .withOpacity(0.9),
                                                        Colors.black
                                                            .withOpacity(0.7),
                                                      ]),
                                              borderRadius:
                                                  BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                            child: TradeRepublicTextField(
                                              controller: messageController,
                                              filled: false,
                                              hintText: AppLocalizations.of(context)?.message ?? AppLocalizations.of(context)!.tr('Message'),
                                              style: TextStyle(
                                                color: isLight
                                                    ? Colors.black
                                                    : Colors.white,
                                                fontSize: DesktopOptimizedWidgets.getFontSize())))),
                                        SizedBox(width: 12),
                                        TradeRepublicButton.icon(
                                          icon: Icon(
                                            CupertinoIcons.arrow_up,
                                            color: Colors.white,
                                            size: 20),
                                          backgroundColor: Colors.blue,
                                          size: 44,
                                          onPressed: () {
                                            if (messageController.text
                                                .trim()
                                                .isNotEmpty) {
                                              HapticFeedback.mediumImpact();
                                              print(
                                                'Sending: ${messageController.text}');
                                              messageController.clear();
                                            }
                                          }),
                                      ])))),
                            ]))))))));
          });
      });
  }

  // Send message to seller
  Future<void> _sendMessage(
    int orderId,
    String messageText,
    Map<String, dynamic> order) async {
    try {
      // Get the first product from the order to identify the seller
      final items = List<Map<String, dynamic>>.from(order['items'] ?? []);
      if (items.isEmpty) {
        throw Exception('No items found in order');
      }

      final firstItem = items[0];
      final productId = firstItem['id'] ?? firstItem['product_id'];

      // For now, assume driver ID = 1 and we need to get seller ID from product
      // In a real app, these would come from authentication/user context
      const int driverId = 1;

      final response = await http.post(
        Uri.parse(ApiConfig.getOrderMessagesUrl(orderId)),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'product_id': productId,
          'sender_type': 'driver',
          'sender_id': driverId,
          'recipient_type': 'seller',
          'recipient_id':
              1, // TODO: Get actual seller ID from product/order data
          'message_text': messageText,
          'message_type': 'text',
        }));

      if (response.statusCode != 201) {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? AppLocalizations.of(context)?.failedToSendMessage ?? AppLocalizations.of(context)!.tr('Failed to send message'));
      }
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  // Fetch messages for an order
  Future<List<Map<String, dynamic>>> _fetchMessages(int orderId) async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.getOrderMessagesUrl(orderId)),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      } else {
        throw Exception('Failed to fetch messages');
      }
    } catch (e) {
      print('Error fetching messages: $e');
      return [];
    }
  }

  // Multi-order combination functionality
  Future<void> _checkAndCombineWithActiveOrders(
    Map<String, dynamic> newOrder) async {
    try {
      print('🔍 Checking for existing active orders to combine...');

      final String url =
          '${ApiConfig.baseUrl}/api/delvioo/driver/1/active-orders'; // Driver ID 1
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['active_orders'] != null) {
          final List activeOrders = data['active_orders'];

          print(
            '📋 Found ${activeOrders.length} active orders (including the new one)');

          if (activeOrders.length > 1) {
            // We have multiple active orders - show combination message
            TopNotification.success(
              context,
              '${activeOrders.length} ${AppLocalizations.of(context)?.ordersAutoCombinedForRoute ?? AppLocalizations.of(context)!.tr('Orders are automatically combined for optimized route')}',

              // blue info
            );

            print(
              '✅ Multi-order combination will be handled in navigation modal');
          }
        }
      }
    } catch (e) {
      print('❌ Error checking for active orders combination: $e');
    }
  }

  void _openMultiOrderNavigation() {
    print('🚀 Opening multi-order navigation...');

    // Find the most recent accepted order for navigation
    if (_acceptedOrders.isNotEmpty) {
      final recentOrder = _acceptedOrders.last;

      // Show navigation modal which will automatically handle multi-order setup
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => NavigationModal(order: recentOrder)));
    }
  }

  // Format expiry date for display
  String _formatExpiryDate(dynamic expiryDate) {
    if (expiryDate == null) return AppLocalizations.of(context)?.notSpecified ?? AppLocalizations.of(context)!.tr('Not specified');

    try {
      DateTime date;
      if (expiryDate is String) {
        date = DateTime.parse(expiryDate);
      } else if (expiryDate is DateTime) {
        date = expiryDate;
      } else {
        return AppLocalizations.of(context)?.invalidDate ?? AppLocalizations.of(context)!.tr('Invalid date');
      }

      final now = DateTime.now();
      final difference = date.difference(now).inDays;

      final appSettings = Provider.of<AppSettings>(context, listen: false);
      final formattedDate = appSettings.formatDate(date);

      if (difference < 0) {
        return '$formattedDate (Expired)';
      } else if (difference == 0) {
        return '$formattedDate (Today)';
      } else if (difference == 1) {
        return '$formattedDate (Tomorrow)';
      } else if (difference <= 7) {
        return '$formattedDate ($difference days)';
      } else {
        return formattedDate;
      }
    } catch (e) {
      return AppLocalizations.of(context)?.invalidDate ?? AppLocalizations.of(context)!.tr('Invalid date');
    }
  }

  // Generate mock expiry date for orders when database doesn't have it yet
  String _getMockExpiryDate(Map<String, dynamic> order) {
    final orderId = order['id'] ?? 0;
    final baseDate = DateTime.now();

    // Generate different expiry dates based on order ID for variety
    final daysToAdd = switch (orderId % 7) {
      0 => 2, // Very urgent - expires in 2 days
      1 => 1, // Critical - expires tomorrow
      2 => 5, // Soon - expires in 5 days
      3 => 7, // Week - expires in a week
      4 => 10, // Medium - 10 days
      5 => 14, // Two weeks
      _ => 21, // Three weeks
    };

    final expiryDate = baseDate.add(Duration(days: daysToAdd));
    return expiryDate.toIso8601String().split(
      'T')[0]; // Return YYYY-MM-DD format
  }

  // Format date from ISO string to readable format
  String _formatDate(dynamic dateInput) {
    if (dateInput == null) return '';

    try {
      DateTime date;
      if (dateInput is String) {
        date = DateTime.parse(dateInput);
      } else if (dateInput is DateTime) {
        date = dateInput;
      } else {
        return dateInput.toString();
      }

      final appSettings = Provider.of<AppSettings>(context, listen: false);
      return appSettings.formatDate(date);
    } catch (e) {
      return dateInput.toString();
    }
  }

  // Helper methods for shipping type display
  String _getShippingTypeName(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'standard':
        return AppLocalizations.of(context)?.standardShippingName ?? AppLocalizations.of(context)!.tr('Standard Shipping');
      case 'cold':
        return AppLocalizations.of(context)?.coldShippingName ?? AppLocalizations.of(context)!.tr('Refrigerated Shipping');
      case 'express':
        return AppLocalizations.of(context)?.expressShippingName ?? AppLocalizations.of(context)!.tr('Express Shipping');
      default:
        return AppLocalizations.of(context)?.standardShippingName ?? AppLocalizations.of(context)!.tr('Standard Shipping'); // Default
    }
  }

  String _getShippingTypeDescription(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'standard':
        return AppLocalizations.of(context)?.normalShippingAtRoomTemp ?? AppLocalizations.of(context)!.tr('Normal shipping at room temperature');
      case 'cold':
        return AppLocalizations.of(context)?.refrigeratedTransportRequired ?? AppLocalizations.of(context)!.tr('Refrigerated transport required');
      case 'express':
        return AppLocalizations.of(context)?.priorityFastestDelivery ?? AppLocalizations.of(context)!.tr('Priority - Fastest possible delivery');
      default:
        return AppLocalizations.of(context)?.normalShippingDefault ?? AppLocalizations.of(context)!.tr('Normal Shipping');
    }
  }

  IconData _getShippingTypeIcon(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'standard':
        return CupertinoIcons.cube_box;
      case 'cold':
        return CupertinoIcons.snow; // Snowflake for cold
      case 'express':
        return CupertinoIcons.bolt; // Lightning bolt for express
      default:
        return CupertinoIcons.cube_box;
    }
  }

  Color _getShippingTypeColor(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'standard':
        return Colors.black; // Standard - black/neutral
      case 'cold':
        return const Color(0xFF2196F3); // Cold - blue
      case 'express':
        return const Color(0xFFFF9800); // Express - orange
      default:
        return Colors.black;
    }
  }

  // Get gradient for shipping type display
  LinearGradient _getShippingTypeGradient(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'cold':
        return const LinearGradient(
          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'express':
        return const LinearGradient(
          colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      default: // standard
        return const LinearGradient(
          colors: [Color(0xFF424242), Color(0xFF212121)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
    }
  }

  // Wagon type helpers - for required vehicle display from products table
  Map<String, String> _getWagonTypeData(String? wagonType) {
    final type = wagonType?.toLowerCase() ?? _kDefaultWagonTypeId;
    return WagonTypesCatalog.localizedById(AppLocalizations.of(context), type);
  }

  String _getWagonTypeName(String? wagonType) {
    return WagonTypesCatalog.englishLabel(normalizeWagonTypeId(wagonType));
  }

  String _getWagonTypeDescription(String? wagonType) {
    return _getWagonTypeData(wagonType)['description'] ??
      (AppLocalizations.of(context)?.generalTransport ?? AppLocalizations.of(context)!.tr(''));
  }

  String _getWagonTypeIcon(String? wagonType) {
    return _getWagonTypeData(wagonType)['icon'] ?? AppLocalizations.of(context)!.tr('🚛');
  }

  IconData _getWagonTypeIconData(String? wagonType) {
    final type = wagonType?.toLowerCase() ?? _kDefaultWagonTypeId;
    switch (type) {
      case 'grain':
        return CupertinoIcons.leaf_arrow_circlepath;
      case 'oil':
        return CupertinoIcons.speedometer;
      case 'refrigerated':
        return CupertinoIcons.snow;
      case 'liquid_food':
        return CupertinoIcons.drop;
      case 'dry_bulk':
        return CupertinoIcons.cube_box;
      case 'temperature_controlled':
        return CupertinoIcons.thermometer;
      case 'fresh_produce':
        return CupertinoIcons.leaf_arrow_circlepath;
      case 'frozen':
        return CupertinoIcons.snow;
      case 'bakery':
        return CupertinoIcons.house;
      case 'beverage':
        return CupertinoIcons.drop;
      case 'meat':
        return CupertinoIcons.house;
      case 'dry_goods':
        return CupertinoIcons.cube_box;
      case 'specialty':
        return CupertinoIcons.star;
      default:
        return CupertinoIcons.cube_box;
    }
  }

  LinearGradient _getWagonTypeGradient(String? wagonType) {
    final type = wagonType?.toLowerCase() ?? _kDefaultWagonTypeId;
    switch (type) {
      case 'grain':
        return const LinearGradient(
          colors: [Color(0xFFFFC107), Color(0xFFFF9800)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'oil':
        return const LinearGradient(
          colors: [Color(0xFF795548), Color(0xFF5D4037)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'refrigerated':
        return const LinearGradient(
          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'liquid_food':
        return const LinearGradient(
          colors: [Color(0xFF03A9F4), Color(0xFF0288D1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'dry_bulk':
        return const LinearGradient(
          colors: [Color(0xFF9E9E9E), Color(0xFF757575)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'temperature_controlled':
        return const LinearGradient(
          colors: [Color(0xFFE91E63), Color(0xFFC2185B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'fresh_produce':
        return const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'frozen':
        return const LinearGradient(
          colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'bakery':
        return const LinearGradient(
          colors: [Color(0xFFFF8A65), Color(0xFFFF5722)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'beverage':
        return const LinearGradient(
          colors: [Color(0xFF7C4DFF), Color(0xFF651FFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'meat':
        return const LinearGradient(
          colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'dry_goods':
        return const LinearGradient(
          colors: [Color(0xFF607D8B), Color(0xFF455A64)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      case 'specialty':
        return const LinearGradient(
          colors: [Color(0xFFFFD54F), Color(0xFFFFC107)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
      default:
        return const LinearGradient(
          colors: [Color(0xFF424242), Color(0xFF212121)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight);
    }
  }

  /// Keyword buckets for matching driver `vehicle_type` / make / model text to
  /// `products.wagon_type` ids (see [WagonTypesCatalog]) and legacy short names.
  List<String> _keywordsForAuctionWagonType(
    String type,
    Map<String, List<String>> wagonTypeKeywords) {
    final t = type.trim().toLowerCase();
    if (t.isEmpty) {
      return List<String>.from(wagonTypeKeywords['refrigerated']!);
    }
    if (wagonTypeKeywords.containsKey(t)) {
      return List<String>.from(wagonTypeKeywords[t]!);
    }
    final first = t.split('_').first;
    if (wagonTypeKeywords.containsKey(first)) {
      return List<String>.from(wagonTypeKeywords[first]!);
    }
    if (first == 'dry' && t.contains('bulk')) {
      return List<String>.from(wagonTypeKeywords['dry_bulk']!);
    }
    if (first == 'dry' && t.contains('good')) {
      return List<String>.from(wagonTypeKeywords['dry_goods']!);
    }
    if (t.contains('frozen')) {
      return List<String>.from(wagonTypeKeywords['frozen']!);
    }
    if (t.contains('fresh') ||
        t.contains('produce') ||
        t.contains('catering')) {
      return List<String>.from(wagonTypeKeywords['fresh_produce']!);
    }
    if (t.contains('temperature') ||
        t.contains('pharma') ||
        t.contains('healthcare')) {
      return List<String>.from(wagonTypeKeywords['temperature_controlled']!);
    }
    if (t.contains('milk') ||
        t.contains('dairy') ||
        t.contains('liquid_food') ||
        (t.contains('food') && t.contains('tank'))) {
      return List<String>.from(wagonTypeKeywords['liquid_food']!);
    }
    if (t.contains('vegetable_oil') ||
        t.contains('fuel_tanker') ||
        t.contains('bitumen') ||
        t.contains('chemical') ||
        t.contains('gas_tanker') ||
        t.contains('powder_tank') ||
        (t.contains('oil') && !t.contains('coil'))) {
      return List<String>.from(wagonTypeKeywords['oil']!);
    }
    if (t.contains('grain') ||
        t.contains('silo') ||
        t.contains('cement_silo') ||
        t.contains('powder')) {
      return List<String>.from(wagonTypeKeywords['grain']!);
    }
    if (t.contains('meat') ||
        t.contains('poultry') ||
        t.contains('fish') ||
        t.contains('seafood') ||
        t.contains('charcuterie') ||
        t.contains('cheese') ||
        t.contains('egg')) {
      return List<String>.from(wagonTypeKeywords['meat']!);
    }
    if (t.contains('bakery') ||
        t.contains('chocolate') ||
        t.contains('honey') ||
        t.contains('jam') ||
        t.contains('coffee') ||
        t.contains('_tea')) {
      return List<String>.from(wagonTypeKeywords['bakery']!);
    }
    if (t.contains('beverage') ||
        t.contains('wine') ||
        t.contains('alcohol')) {
      return List<String>.from(wagonTypeKeywords['beverage']!);
    }
    if (t.contains('refriger') ||
        t.contains('reefer') ||
        t.contains('cold_chain') ||
        t.contains('food_safe')) {
      return List<String>.from(wagonTypeKeywords['refrigerated']!);
    }
    if (t.contains('box_truck') ||
        t.contains('panel_van') ||
        t.contains('curtain') ||
        t.contains('flatbed') ||
        t.contains('container_chassis') ||
        t.contains('swap_body')) {
      return List<String>.from(wagonTypeKeywords['dry_goods']!);
    }
    return List<String>.from(wagonTypeKeywords['specialty']!);
  }

  // Check if a vehicle matches the required wagon type
  bool _vehicleMatchesWagonType(
    Map<String, dynamic> vehicle,
    String? wagonType) {
    final vehicleMake = (vehicle['vehicle_make'] ?? AppLocalizations.of(context)!.tr(''))
        .toString()
        .toLowerCase();
    final vehicleModel = (vehicle['vehicle_model'] ?? AppLocalizations.of(context)!.tr(''))
        .toString()
        .toLowerCase();
    final vehicleType = (vehicle['vehicle_type'] ?? AppLocalizations.of(context)!.tr(''))
        .toString()
        .toLowerCase();
    final vehicleTypeStr = '$vehicleMake $vehicleModel $vehicleType';

    final type = wagonType?.toLowerCase() ?? _kDefaultWagonTypeId;

    print(
      '🔍 Matching: vehicleTypeStr="$vehicleTypeStr" against wagonType="$type"');

    // Driver selected the same catalog id in vehicle registration (exact match).
    final registered = vehicleType.replaceAll('-', '_').trim();
    if (registered.isNotEmpty && registered == type) {
      print('🔍 Match result: true (vehicle_type equals wagon_type id)');
      return true;
    }
    final typeSpaced = type.replaceAll('_', ' ');
    if (typeSpaced.isNotEmpty && vehicleTypeStr.contains(typeSpaced)) {
      print('🔍 Match result: true (vehicle text contains wagon type label)');
      return true;
    }

    // Keywords that match each wagon type
    final Map<String, List<String>> wagonTypeKeywords = {
      'grain': [
        'grain',
        'hopper',
        'bulk',
        'dry bulk',
        'timpte',
        'cornhusker',
        'benson',
        'fruehauf',
      ],
      'oil': [
        'tanker',
        'tank',
        'polar',
        'walker',
        'heil',
        'brenner',
        'tremcar',
        'oil',
      ],
      'refrigerated': [
        'reefer',
        'refriger',
        'thermo',
        'carrier',
        'cold',
        'sprinter',
        'transit',
        'food_safe',
        'food safe',
      ],
      'liquid_food': [
        'tanker',
        'tank',
        'polar',
        'walker',
        'sanitary',
        'food grade',
        'milk',
        'beverage',
      ],
      'dry_bulk': ['hopper', 'bulk', 'timpte', 'cornhusker', 'grain'],
      'dry_goods': ['van', 'transit', 'sprinter', 'delivery', 'box'],
      'temperature_controlled': [
        'thermo',
        'carrier',
        'reefer',
        'refriger',
        'slxi',
        'vector',
      ],
      'fresh_produce': ['reefer', 'refriger', 'sprinter', 'transit', 'cold'],
      'frozen': ['reefer', 'refriger', 'thermo', 'carrier', 'frozen', 'slxi'],
      'bakery': ['transit', 'sprinter', 'van', 'delivery'],
      'beverage': ['tanker', 'tank', 'beverage', 'transit'],
      'meat': ['reefer', 'refriger', 'thermo', 'cold', 'meat'],
      'specialty': ['van', 'transit', 'sprinter', 'insulated'],
    };

    final keywords = _keywordsForAuctionWagonType(type, wagonTypeKeywords);
    print('🔍 Keywords for "$type": $keywords');

    final result = keywords.any((keyword) => vehicleTypeStr.contains(keyword));
    print('🔍 Match result: $result');
    return result;
  }

  // Check if driver has any matching vehicle for the wagon type
  bool _hasMatchingVehicle(String? wagonType) {
    print('🚗 Checking for matching vehicle for wagon type: $wagonType');
    print('🚗 Driver vehicles count: ${_driverVehicles.length}');

    if (_driverVehicles.isEmpty) {
      print('⚠️ No driver vehicles loaded!');
      return false;
    }

    for (var vehicle in _driverVehicles) {
      final matches = _vehicleMatchesWagonType(vehicle, wagonType);
      print(
        '   Vehicle: ${vehicle['vehicle_make']} ${vehicle['vehicle_model']} (type: ${vehicle['vehicle_type']}) - matches: $matches');
    }

    final result = _driverVehicles.any(
      (vehicle) => _vehicleMatchesWagonType(vehicle, wagonType));
    print('🚗 Final result: $result');
    return result;
  }

  // Get the first matching vehicle for the wagon type
  Map<String, dynamic>? _getMatchingVehicle(String? wagonType) {
    if (_driverVehicles.isEmpty) return null;

    try {
      return _driverVehicles.firstWhere(
        (vehicle) => _vehicleMatchesWagonType(vehicle, wagonType));
    } catch (e) {
      return null;
    }
  }

  // Get appropriate color for expiry date based on urgency
  Color _getExpiryColor(dynamic expiryDate) {
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;
    if (expiryDate == null) {
      return (isLight ? Colors.black : Colors.white).withOpacity(0.5);
    }

    try {
      DateTime date;
      if (expiryDate is String) {
        date = DateTime.parse(expiryDate);
      } else if (expiryDate is DateTime) {
        date = expiryDate;
      } else {
        return (isLight ? Colors.black : Colors.white).withOpacity(0.5);
      }

      final now = DateTime.now();
      final difference = date.difference(now).inDays;

      if (difference < 0) {
        return Colors.red; // Expired - red
      } else if (difference <= 1) {
        return Colors.red; // Expires today or tomorrow - red
      } else if (difference <= 3) {
        return Colors.orange; // Expires in 2-3 days - orange
      } else if (difference <= 7) {
        return Colors.yellow.shade700; // Expires in a week - yellow
      } else {
        return Colors.green; // Good expiry date - green
      }
    } catch (e) {
      return (isLight ? Colors.black : Colors.white).withOpacity(0.5);
    }
  }

  // Build Apple Maps polylines from route points
  Set<apple.Polyline> _buildAppleMapsPolylines() {
    if (_routePoints.isEmpty) {
      _cachedApplePolylines = {};
      _cachedAppleRoutePoints = [];
      return {};
    }

    if (_cachedAppleRoutePoints.isNotEmpty &&
        _listEquals(_cachedAppleRoutePoints, _routePoints)) {
      return _cachedApplePolylines;
    }

    _cachedAppleRoutePoints = List.from(_routePoints);
    final applePoints = _routePoints
        .map((p) => apple.LatLng(p.latitude, p.longitude))
        .toList();

    _cachedApplePolylines = {
      apple.Polyline(
        polylineId: apple.PolylineId('route'),
        points: applePoints,
        color: const Color(0xFF007AFF),
        width: 4),
    };

    return _cachedApplePolylines;
  }

  // Renders a circle cluster icon as PNG bytes using Canvas (no widget tree needed).
  Future<void> _ensureAppleClusterIcon(String key, int count, bool isEmergency, bool isLight) async {
    if (_appleIconCache.containsKey(key) || _appleIconPending.contains(key)) return;
    _appleIconPending.add(key);

    const double dp = 48.0;
    const double scale = 3.0; // @3x for retina
    final double px = dp * scale;
    final double r = px / 2 - 2;
    final Offset center = Offset(px / 2, px / 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Shadow
    canvas.drawCircle(
      center.translate(0, 2),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6));

    // Background circle
    final bgColor = isEmergency
        ? const Color(0xFFB71C1C)
        : (isLight ? Colors.black : Colors.white);
    canvas.drawCircle(center, r, Paint()..color = bgColor);

    // Count text
    final textColor = isLight ? Colors.white : Colors.black;
    final tp = TextPainter(
      text: TextSpan(
        text: '$count',
        style: TextStyle(
          color: isEmergency ? Colors.white : textColor,
          fontSize: (count > 99 ? 13.0 : 18.0) * scale,
          fontWeight: FontWeight.w800)),
      textDirection: ui.TextDirection.ltr)..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

    // Emergency badge (red dot with !)
    if (isEmergency) {
      final bCenter = Offset(px * 0.72, px * 0.28);
      canvas.drawCircle(bCenter, 10 * scale / 2, Paint()..color = const Color(0xFFFF3B30));
      final ep = TextPainter(
        text: const TextSpan(
          text: '!',
          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
        textDirection: ui.TextDirection.ltr)..layout();
      ep.paint(canvas, bCenter - Offset(ep.width / 2, ep.height / 2));
    }

    final picture = recorder.endRecording();
    final img = picture.toImageSync(px.toInt(), px.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();

    if (!mounted) return;
    if (byteData != null) {
      _appleIconCache[key] = apple.BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
    }
    _appleIconPending.remove(key);
    // Invalidate annotation cache so next build picks up the new icon
    _cachedAppleAnnotationsKey = '';
    setState(() {});
  }

  apple.BitmapDescriptor _appleClusterIcon(int count, bool isEmergency, bool isLight) {
    final key = '${count}_${isEmergency}_$isLight';
    final cached = _appleIconCache[key];
    if (cached != null) return cached;
    // Trigger async generation; use coloured default pin as placeholder
    _ensureAppleClusterIcon(key, count, isEmergency, isLight);
    if (isEmergency) return apple.BitmapDescriptor.defaultAnnotationWithHue(apple.BitmapDescriptor.hueRed);
    if (count > 1) return apple.BitmapDescriptor.defaultAnnotationWithHue(apple.BitmapDescriptor.hueBlue);
    return isLight
        ? apple.BitmapDescriptor.defaultAnnotation
        : apple.BitmapDescriptor.defaultAnnotationWithHue(apple.BitmapDescriptor.hueAzure);
  }

  // Build Apple Maps annotations (markers) for orders + clusters
  Set<apple.Annotation> _buildAppleMapsAnnotations(bool isLight) {
    // Build cache key from merged auctions + order count + zoom
    final merged = _mergedAuctions();
    final orderIds = _filteredOrders.map((o) => '${o['id']}').join('_');
    final cacheKey = '${merged.map((a) => '${a['id']}').join('_')}|$orderIds|${_appleMapZoomLevel.toStringAsFixed(1)}|$isLight|${_productCoordinatesCache.length}';
    if (_cachedAppleAnnotationsKey == cacheKey && _cachedAppleAnnotations.isNotEmpty) {
      return _cachedAppleAnnotations;
    }
    _cachedAppleAnnotationsKey = cacheKey;

    final Set<apple.Annotation> annotations = {};

    // ── Auction markers ──────────────────────────────────────────────────────
    for (int i = 0; i < _filteredAuctions.length; i++) {
      final auction = _filteredAuctions[i];
      final pickupLocation = _getAuctionCoordinates(auction);
      if (pickupLocation == null) continue;

      final displayOrderId = auction['order_id'] ?? auction['id'];
      annotations.add(
        apple.Annotation(
          annotationId: apple.AnnotationId('auction_$i'),
          position: apple.LatLng(pickupLocation.latitude, pickupLocation.longitude),
          infoWindow: apple.InfoWindow(
            title: auction['businessName'] ??
                '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}$displayOrderId',
            snippet: AppLocalizations.of(context)?.tapToViewDetails ??
                AppLocalizations.of(context)!.tr('Tap to view details')),
          onTap: () {
            HapticFeedback.mediumImpact();
            _showAuctionModal(auction, pickupLocation);
          }));
    }

    // ── Order cluster markers ─────────────────────────────────────────────────
    if (_filteredOrders.isNotEmpty) {
      // Collect order IDs already covered by auction markers
      final auctionOrderIds = _filteredAuctions
          .map((a) => a['order_id']?.toString())
          .whereType<String>()
          .toSet();

      final clusters = _clusterOrders(_filteredOrders);

      for (int ci = 0; ci < clusters.length; ci++) {
        final cluster = clusters[ci];
        final firstOrder = cluster[0];
        final latLng = _getPickupCoordinatesSync(firstOrder);
        if (latLng == null) continue;

        // Skip clusters whose single order is already shown as auction marker
        if (cluster.length == 1) {
          final oid = (firstOrder['id'] ?? firstOrder['order_id'])?.toString();
          if (oid != null && auctionOrderIds.contains(oid)) continue;
        }

        final isEmergency = cluster.any((o) =>
            o['has_issue'] == 1 || o['has_issue'] == true ||
            o['issue_emergency'] == 1 || o['issue_emergency'] == true);
        final count = cluster.length;
        final icon = _appleClusterIcon(count, isEmergency, isLight);

        annotations.add(
          apple.Annotation(
            annotationId: apple.AnnotationId('cluster_$ci'),
            position: apple.LatLng(latLng.latitude, latLng.longitude),
            // Centre the circular icon on the coordinate
            anchor: const Offset(0.5, 0.5),
            icon: icon,
            infoWindow: count > 1
                ? apple.InfoWindow(
                    title: '$count ${AppLocalizations.of(context)?.orders ?? 'Orders'}',
                    snippet: AppLocalizations.of(context)?.tapToViewDetails ??
                        AppLocalizations.of(context)!.tr('Tap to view details'))
                : apple.InfoWindow.noText,
            onTap: () {
              HapticFeedback.mediumImpact();
              if (cluster.length == 1) {
                final orderId = firstOrder['id'] ?? firstOrder['order_id'];
                final auction = _getAuctionForOrder(orderId);
                if (auction != null) {
                  _showAuctionModal(auction, latLng);
                } else {
                  _showClusterModal(cluster);
                }
              } else {
                _showClusterModal(cluster);
              }
            }));
      }
    }

    // ── Route start/end ───────────────────────────────────────────────────────
    if (_routePoints.length >= 2) {
      annotations.add(apple.Annotation(
        annotationId: apple.AnnotationId('route_start'),
        position: apple.LatLng(_routePoints.first.latitude, _routePoints.first.longitude),
        infoWindow: apple.InfoWindow(
            title: AppLocalizations.of(context)?.start ?? AppLocalizations.of(context)!.tr('Start'))));
      annotations.add(apple.Annotation(
        annotationId: apple.AnnotationId('route_end'),
        position: apple.LatLng(_routePoints.last.latitude, _routePoints.last.longitude),
        infoWindow: apple.InfoWindow(
            title: AppLocalizations.of(context)?.destination ??
                AppLocalizations.of(context)!.tr('Destination'))));
    }

    _cachedAppleAnnotations = annotations;
    return annotations;
  }

  // Helper method to build auction detail row
  Widget _buildAuctionDetailRow({
    required bool isLight,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isLight ? Colors.black : Colors.white),
          SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              fontFamily: 'Poppins')),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w600,
                color: isLight ? Colors.black : Colors.white,
                fontFamily: 'Poppins'))),
        ]));
  }

  // Helper method to build bid detail row
  Widget _buildBidDetailRow({
    required bool isLight,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isLight ? Colors.black : Colors.white),
          SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              fontFamily: 'Poppins')),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isLight ? Colors.black : Colors.white,
                fontFamily: 'Poppins'))),
        ]));
  }

  // Calculate section capacity - returns BOTH weight and volume dimensions
  Map<String, dynamic> _calculateSectionCapacity() {
    if (_selectedSectionIndex == null || 
        _selectedSectionIndex! >= _selectedVehicleSections.length) {
      return {
        'capacity': 0.0,
        'unit': 't',
        'payload_capacity': 0.0,
        'payload_unit': 'lbs',
        'cargo_capacity': 0.0,
        'cargo_unit': 'ft³',
      };
    }
    
    final section = _selectedVehicleSections[_selectedSectionIndex!];
    final sectionPercentage = _toDouble(
      section['percentage'] ?? section['size_percentage'],
      defaultValue: 100.0);
    
    final selectedVehicle = _driverVehicles.firstWhere(
      (v) => v['id'] == _selectedVehicleId,
      orElse: () => <String, dynamic>{});
    
    // Get BOTH capacity dimensions
    final double payloadTotal = _toDouble(selectedVehicle['payload_capacity']);
    final String payloadUnit = selectedVehicle['payload_unit']?.toString() ?? AppLocalizations.of(context)!.tr('lbs');
    final double cargoTotal = _toDouble(selectedVehicle['cargo_capacity']);
    final String cargoUnit = selectedVehicle['cargo_unit']?.toString() ?? AppLocalizations.of(context)!.tr('ft³');
    
    // Check order unit to decide primary capacity
    final orderUnit = _currentAuctionForBid?['quantity_unit']?.toString() ?? AppLocalizations.of(context)!.tr('t');
    final bool useVolume = _isVolumeUnit(orderUnit);
    
    final double vehicleCapacity;
    final String capacityUnit;
    if (useVolume) {
      vehicleCapacity = cargoTotal;
      capacityUnit = cargoUnit;
    } else {
      vehicleCapacity = payloadTotal;
      capacityUnit = payloadUnit;
    }
    
    final capacity = vehicleCapacity * sectionPercentage / 100.0;
    
    return {
      'capacity': capacity,
      'unit': capacityUnit,
      'payload_capacity': payloadTotal * sectionPercentage / 100.0,
      'payload_unit': payloadUnit,
      'cargo_capacity': cargoTotal * sectionPercentage / 100.0,
      'cargo_unit': cargoUnit,
    };
  }

  // Build draggable bottom sheet — Trade Republic style, pure black/white
  Widget _buildDraggableBottomSheet(bool isLight) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final fg = isLight ? Colors.black : Colors.white;
    final bg = isLight ? Colors.white : Colors.black;
    final muted = fg.withValues(alpha: 0.38);
    final divider = fg.withValues(alpha: 0.07);

    final availableOrders = _filteredOrders
        .where((o) => o['acceptance_status'] == 'available')
        .length;
    final acceptedOrders = _filteredOrders
        .where((o) =>
            o['acceptance_status'] == 'accepted' ||
            o['acceptance_status'] == 'picked_up')
        .length;

    final loc = AppLocalizations.of(context);
    // collapsedH includes safe-area so the indicator pill sits in the empty
    // bottom section of the sheet without overlapping the stats content.
    final collapsedH = bottomPadding + 130.0;
    final expandedH = (screenHeight * 0.52).clamp(200.0, screenHeight * 0.75);

    // Sync _bottomSheetHeight if it's outside valid range (prevents overflow on page switch)
    if (_bottomSheetHeight < collapsedH || _bottomSheetHeight > expandedH) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _bottomSheetHeight = _bottomSheetHeight.clamp(collapsedH, expandedH);
          });
        }
      });
    }

    final priceFilters = [
      {'label': loc?.allLabel ?? 'All',   'min': 0.0,    'max': 50000.0},
      {'label': '< 100',                  'min': 0.0,    'max': 100.0},
      {'label': '100–1k',                 'min': 100.0,  'max': 1000.0},
      {'label': '1k+',                    'min': 1000.0, 'max': 50000.0},
    ];

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      // Outer detector: absorbs horizontal swipes so parent page-view never
      // navigates when the user interacts with the sheet. Also drives the
      // expand/collapse via vertical drag on the whole collapsed sheet.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        onVerticalDragStart: (_) => setState(() => _isDraggingSheet = true),
        onVerticalDragUpdate: (d) => setState(() {
          _bottomSheetHeight =
              (_bottomSheetHeight - d.delta.dy).clamp(collapsedH, expandedH);
          _isBottomSheetExpanded = _bottomSheetHeight > screenHeight * 0.24;
        }),
        onVerticalDragEnd: (_) => setState(() {
          _isDraggingSheet = false;
          final snap = _bottomSheetHeight > screenHeight * 0.24;
          _bottomSheetHeight = snap ? expandedH : collapsedH;
          _isBottomSheetExpanded = snap;
        }),
        child: AnimatedContainer(
        duration: _isDraggingSheet
            ? Duration.zero
            : const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        height: _bottomSheetHeight,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.09 : 0.35),
              blurRadius: 28,
              offset: const Offset(0, -3)),
          ]),
        clipBehavior: Clip.hardEdge,
        child: ClipRect(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Drag handle (visual only — drag handled by outer detector) ─
            SizedBox(
              width: double.infinity,
              child: DragHandle()),

            // ── Stats row ────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _sheetStatCol('$availableOrders',
                      loc?.available ?? 'Available', fg, muted),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration:
                          BoxDecoration(color: muted, shape: BoxShape.circle))),
                  _sheetStatCol('$acceptedOrders',
                      loc?.active ?? 'Active', fg, muted),
                  const Spacer(),
                  // Filter pill — tap to expand
                  TradeRepublicTap(
                    onTap: () => setState(() {
                      _isBottomSheetExpanded = !_isBottomSheetExpanded;
                      _isDraggingSheet = false;
                      _bottomSheetHeight =
                          _isBottomSheetExpanded ? expandedH : collapsedH;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _isBottomSheetExpanded
                            ? fg
                            : fg.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isBottomSheetExpanded
                                ? CupertinoIcons.xmark
                                : CupertinoIcons.slider_horizontal_3,
                            size: 13,
                            color: _isBottomSheetExpanded
                                ? (isLight ? Colors.white : Colors.black)
                                : muted),
                          SizedBox(width: 6),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _isBottomSheetExpanded
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: _isBottomSheetExpanded
                                  ? (isLight ? Colors.white : Colors.black)
                                  : muted),
                            child: Text(
                              _isBottomSheetExpanded
                                  ? (loc?.tr('Close') ?? 'Close')
                                  : (loc?.tr('Filter') ?? 'Filter'))),
                        ]))),
                ])),

            // ── Expanded filter area ─────────────────────────────────────
            if (_isBottomSheetExpanded) ...[
              Container(height: 0.5, color: divider),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      20, 20, 20, bottomPadding > 0 ? bottomPadding : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Price section
                      Text(
                        (loc?.tr('PRICE') ?? 'PRICE').toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: muted)),
                      SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(priceFilters.length, (i) {
                            final f = priceFilters[i];
                            final sel = _minPriceFilter == f['min'] &&
                                _maxPriceFilter == f['max'];
                            return Padding(
                              padding: EdgeInsets.only(
                                  right: i < priceFilters.length - 1 ? 8 : 0),
                              child: _sheetFilterChip(
                                f['label'] as String,
                                sel,
                                isLight,
                                () => setState(() {
                                  _minPriceFilter = f['min'] as double;
                                  _maxPriceFilter = f['max'] as double;
                                })));
                          }))),

                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                      // Vehicle type section
                      Text(
                        (loc?.vehicleType ?? 'VEHICLE TYPE').toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: muted)),
                      SizedBox(height: 10),
                      _buildWagonTypeChips(isLight),

                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                      // Incoterm section
                      Text(
                        (loc?.tr('INCOTERM') ?? 'INCOTERM').toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: muted)),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['All', 'EXW', 'FOB', 'CIF', 'DDP']
                            .map((t) => _sheetFilterChip(
                                  t,
                                  t == 'All'
                                      ? _selectedIncotermFilter == null
                                      : _selectedIncotermFilter == t,
                                  isLight,
                                  () => setState(() =>
                                      _selectedIncotermFilter =
                                          t == 'All' ? null : t)))
                            .toList()),

                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    ]))),
            ] else
              const Expanded(child: SizedBox()),
          ])), // ClipRect
      )));
  }

  // Stat column for bottom sheet header
  Widget _sheetStatCol(
      String value, String label, Color fg, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
            height: 1.0,
            color: fg)),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
              fontSize: 11, color: muted, fontWeight: FontWeight.w500)),
      ]);
  }

  // Pill chip for bottom sheet filters
  Widget _sheetFilterChip(
      String label, bool isSelected, bool isLight, VoidCallback onTap) {
    final fg = isLight ? Colors.black : Colors.white;
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? fg : fg.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected
                ? (isLight ? Colors.white : Colors.black)
                : fg.withValues(alpha: 0.65)))));
  }

  // Horizontal wagon type chips (chips only, no label)
  Widget _buildWagonTypeChips(bool isLight) {
    final loc = AppLocalizations.of(context);
    final allTypes = WagonTypesCatalog.localized(loc);
    final items = [
      {'id': null, 'name': loc?.allLabel ?? 'All'},
      ...allTypes,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(items.length, (i) {
          final String? id = items[i]['id'];
          final String name = items[i]['name'] ?? '';
          final bool isSelected = _selectedWagonTypeFilter == id;
          return Padding(
            padding: EdgeInsets.only(right: i < items.length - 1 ? 8 : 0),
            child: _sheetFilterChip(name, isSelected, isLight, () {
              setState(() => _selectedWagonTypeFilter = id);
            }));
        })));
  }

  // Show price input modal
  void _showPriceInputModal(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: _PriceInputModal(
        isLight: isLight,
        appSettings: Provider.of<AppSettings>(context, listen: false),
        currentToPickupDist: _toDouble(_activeRouteInfo?['currentToPickupDistance']),
        pickupToDeliveryDist: _pickupToDeliveryDistance,
        requiresCleaningCertificate: _currentAuctionForBid?['requires_cleaning_certificate'] == true,
        initialPriceMode: _priceMode,
        onSubmit: (priceCents, cleaningCents, priceMode) async {
          // Save locally so other widgets can read the values
          setState(() {
            _rawPriceCents = priceCents;
            _rawCleaningCents = cleaningCents;
            _priceMode = priceMode;
          });

          // NOTE: _PriceInputModal already calls Navigator.pop after onSubmit returns.
          // Do NOT call Navigator.pop here — that would produce a double-pop and
          // close the underlying page, leaving a black screen.

          final auction = _currentAuctionForBid;
          final auctionId = auction?['id'] is int
              ? auction!['id'] as int
              : int.tryParse(auction?['id']?.toString() ?? AppLocalizations.of(context)!.tr(''));
          if (auction == null || auctionId == null) return;

          final bidAmount = priceCents / 100.0;
          final cleaningAmount = cleaningCents > 0 ? cleaningCents / 100.0 : null;

          final sectionName = (_selectedSectionIndex != null &&
                  _selectedSectionIndex! < _selectedVehicleSections.length)
              ? _selectedVehicleSections[_selectedSectionIndex!]['name']
                    ?.toString()
              : null;

          final success = await _submitBid(
            auctionId: auctionId,
            bidAmount: bidAmount,
            cleaningCertificatePrice: cleaningAmount,
            vehicleId: _selectedVehicleId,
            sectionIndex: _selectedSectionIndex,
            sectionName: sectionName,
            priceMode: priceMode);

          if (success) {
            _onClearRoute();
            if (mounted) {
              final appSettings =
                  Provider.of<AppSettings>(context, listen: false);
              final overflowAuctionId = auction['overflow_auction_id'];
              final overflowOrderId = auction['overflow_order_id'];
              final overflowQty = _toDouble(auction['overflow_order_qty']);
              final unit = auction['quantity_unit']?.toString() ?? AppLocalizations.of(context)!.tr('');
              if (overflowAuctionId != null) {
                _showSplitBidSuccessSheet(
                  isLight: isLight,
                  bidAmount: bidAmount,
                  overflowAuctionId: overflowAuctionId,
                  overflowOrderId: overflowOrderId,
                  overflowQty: overflowQty,
                  unit: unit,
                  appSettings: appSettings);
              } else {
                TopNotification.success(
                  context,
                  'Bid of ${appSettings.formatCurrency(bidAmount)} submitted!');
              }
            }
          } else {
            if (mounted) {
              TopNotification.error(
                context,
                AppLocalizations.of(context)!.tr('Failed to submit bid. Please try again.') ?? AppLocalizations.of(context)!.tr('Failed to submit bid. Please try again.'));
            }
          }
        }));
  }

  // Show split + bid success sheet — mirrors _showRemainderOrderSheet in cultioo_app
  void _showSplitBidSuccessSheet({
    required bool isLight,
    required double bidAmount,
    required dynamic overflowAuctionId,
    required dynamic overflowOrderId,
    required double overflowQty,
    required String unit,
    required AppSettings appSettings,
  }) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.52,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              const DragHandle(),
              // Success icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF34C759), Color(0xFF30B350)]),
                  borderRadius: BorderRadius.circular(18)),
                child: Icon(CupertinoIcons.checkmark_alt, size: 28, color: Colors.white)),
              SizedBox(height: 14),
              // Title
              Text(
                'Split successful!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                  fontFamily: 'Poppins')),
              SizedBox(height: 6),
              Text(
                '🎯 Bid of ${appSettings.formatCurrency(bidAmount)} submitted for your portion.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.55),
                  fontFamily: 'Poppins')),
              SizedBox(height: 20),
              // Overflow info card
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(isLight ? 0.07 : 0.14),
                  borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                      child: Icon(CupertinoIcons.arrow_branch, size: 20, color: Color(0xFF007AFF))),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            overflowOrderId != null
                                ? 'New split order #$overflowOrderId · Auction #$overflowAuctionId'
                                : 'New auction #$overflowAuctionId',
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                              fontFamily: 'Poppins')),
                          SizedBox(height: 2),
                          Text(
                            '${_formatQuantity(overflowQty)} $unit · Available for other drivers',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                              fontFamily: 'Poppins')),
                        ])),
                  ])),
              const Spacer(),
              Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)!.tr('Close') ?? AppLocalizations.of(context)!.tr('Close'),
                  onPressed: () => Navigator.pop(context))),
            ]))));
  }

  // Show section selection modal
  void _showSectionSelectionModal(bool isLight) {
    if (_selectedVehicleId == null) return;
    
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.square_grid_2x2,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.selectSection ?? AppLocalizations.of(context)!.tr('Select Section'),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
              ]),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            // Section list
            Expanded(
              child: _selectedVehicleSections.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.cube_box,
                            size: 48,
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.3)),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          Text(
                            AppLocalizations.of(context)?.noVehicleSectionsConfigured ?? AppLocalizations.of(context)!.tr('No vehicle sections configured'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
                        ]))
                  : ListView.separated(
                      padding: EdgeInsets.symmetric(horizontal: 0),
                      itemCount: _selectedVehicleSections.length,
                      separatorBuilder: (_, __) => SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final section = _selectedVehicleSections[index];
                        final sectionName = section['name'] ?? 'Section ${index + 1}';
                        final sectionPercentage = _toDouble(section['percentage'], defaultValue: _toDouble(section['size_percentage'], defaultValue: 100.0)).toInt();
                        final isSelected = _selectedSectionIndex == index;

                        return TradeRepublicTap(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _selectedSectionIndex = index;
                            });
                            Navigator.pop(context);
                            // Re-open capacity confirmation with newly selected section
                            _showVehicleCapacityConfirmation(isLight);
                          },
                          child: Container(
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isLight ? const Color(0xFF007AFF).withOpacity(0.1) : const Color(0xFF0A84FF).withOpacity(0.15))
                                  : (isLight ? Colors.white : const Color(0xFF1A1A1A)),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isLight ? const Color(0xFF007AFF) : const Color(0xFF0A84FF))
                                        : (isLight ? Colors.black.withOpacity(0.05) : Colors.white.withOpacity(0.08)),
                                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? Colors.white
                                            : (isLight ? Colors.black : Colors.white))))),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sectionName,
                                        style: TextStyle(
                                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                                          fontWeight: FontWeight.w600,
                                          color: isLight ? Colors.black : Colors.white)),
                                      SizedBox(height: 2),
                                      Text(
                                        '$sectionPercentage% ${AppLocalizations.of(context)?.capacity ?? AppLocalizations.of(context)!.tr('Capacity')}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
                                    ])),
                                if (isSelected)
                                  Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    size: 24,
                                    color: isLight ? const Color(0xFF007AFF) : const Color(0xFF0A84FF)),
                              ])));
                      })),
          ])));
  }

  // Show the capacity confirmation modal (used after selecting a section)
  void _showVehicleCapacityConfirmation(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: _buildVehicleSelectionContent(isLight));
  }

  // Build simple floating button
  Widget _buildSimpleFloatingButton({
    required bool isLight,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return TradeRepublicButton.icon(
      icon: Icon(icon, size: 20, color: isLight ? Colors.black : Colors.white),
      backgroundColor: isLight ? Colors.white : Colors.black,
      size: 44,
      onPressed: onTap);
  }

  // ── CullyAI: Convert weight to user's preferred unit (Metric / Pounds) ──
  Map<String, dynamic> _convertWeightToUserUnit(double value, String unit) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final unitLower = unit.toLowerCase().trim();
    final usePounds = appSettings.effectiveWeightUnit == 'Pounds';

    if (unitLower == 'kg' || unitLower == 'kilogram' || unitLower == 'kilograms' || unitLower == 'kilogramm') {
      if (usePounds) return {'value': value * 2.20462, 'unit': 'lb'};
      return {'value': value, 'unit': 'kg'};
    }
    if (unitLower == 't' || unitLower == 'ton' || unitLower == 'tons' || unitLower == 'tonne' || unitLower == 'tonnes') {
      if (usePounds) return {'value': value * 2204.62, 'unit': 'lb'};
      return {'value': value * 1000, 'unit': 'kg'};
    }
    if (unitLower == 'g' || unitLower == 'gram' || unitLower == 'grams' || unitLower == 'gramm') {
      if (usePounds) {
        final lbValue = value * 0.00220462;
        if (lbValue < 0.1) return {'value': value * 0.035274, 'unit': 'oz'};
        return {'value': lbValue, 'unit': 'lb'};
      }
      if (value < 1000) return {'value': value, 'unit': 'g'};
      return {'value': value / 1000, 'unit': 'kg'};
    }
    if (unitLower == 'lb' || unitLower == 'lbs' || unitLower == 'pound' || unitLower == 'pounds') {
      if (!usePounds) return {'value': value * 0.453592, 'unit': 'kg'};
      return {'value': value, 'unit': 'lb'};
    }
    if (unitLower == 'oz' || unitLower == 'ounce' || unitLower == 'ounces') {
      if (usePounds) {
        if (value < 16) return {'value': value, 'unit': 'oz'};
        return {'value': value / 16, 'unit': 'lb'};
      }
      final grams = value * 28.3495;
      if (grams < 1000) return {'value': grams, 'unit': 'g'};
      return {'value': grams / 1000, 'unit': 'kg'};
    }
    // Volume units: convert between ft³ ↔ m³ based on user preference (Pounds = imperial = ft³)
    if (unitLower == 'ft³' || unitLower == 'ft3' || unitLower == 'cubic feet' || unitLower == 'cu ft') {
      if (!usePounds) return {'value': value * 0.0283168, 'unit': 'm³'};
      return {'value': value, 'unit': 'ft³'};
    }
    if (unitLower == 'm³' || unitLower == 'm3' || unitLower == 'cubic meter' || unitLower == 'cubic meters' || unitLower == 'cbm') {
      if (usePounds) return {'value': value * 35.3147, 'unit': 'ft³'};
      return {'value': value, 'unit': 'm³'};
    }
    if (unitLower == 'l' || unitLower == 'liter' || unitLower == 'liters' || unitLower == 'litre' || unitLower == 'litres') {
      if (usePounds) return {'value': value * 0.264172, 'unit': 'gal'};
      return {'value': value, 'unit': 'L'};
    }
    if (unitLower == 'ml' || unitLower == 'milliliter' || unitLower == 'milliliters' || unitLower == 'millilitre' || unitLower == 'millilitres') {
      // mL → convert up to L or gal for display
      if (usePounds) {
        final flOz = value * 0.033814;
        if (flOz < 32) return {'value': flOz, 'unit': 'fl oz'};
        return {'value': value * 0.000264172, 'unit': 'gal'};
      }
      if (value < 1000) return {'value': value, 'unit': 'mL'};
      return {'value': value / 1000, 'unit': 'L'};
    }
    if (unitLower == 'cl' || unitLower == 'centiliter' || unitLower == 'centiliters' || unitLower == 'centilitre' || unitLower == 'centilitres') {
      if (usePounds) return {'value': value * 0.00338140, 'unit': 'fl oz'};
      return {'value': value / 100, 'unit': 'L'};
    }
    if (unitLower == 'dl' || unitLower == 'deciliter' || unitLower == 'deciliters' || unitLower == 'decilitre' || unitLower == 'decilitres') {
      if (usePounds) return {'value': value * 0.0338140, 'unit': 'fl oz'};
      return {'value': value / 10, 'unit': 'L'};
    }
    if (unitLower == 'gal' || unitLower == 'gallon' || unitLower == 'gallons') {
      if (!usePounds) return {'value': value * 3.78541, 'unit': 'L'};
      return {'value': value, 'unit': 'gal'};
    }
    if (unitLower == 'qt' || unitLower == 'quart' || unitLower == 'quarts') {
      if (!usePounds) return {'value': value * 0.946353, 'unit': 'L'};
      return {'value': value, 'unit': 'qt'};
    }
    if (unitLower == 'pt' || unitLower == 'pint' || unitLower == 'pints') {
      if (!usePounds) return {'value': value * 0.473176, 'unit': 'L'};
      return {'value': value, 'unit': 'pt'};
    }
    if (unitLower == 'fl oz' || unitLower == 'floz' || unitLower == 'fluid oz' || unitLower == 'fluid ounce' || unitLower == 'fluid ounces') {
      if (!usePounds) return {'value': value * 0.0295735, 'unit': 'L'};
      return {'value': value, 'unit': 'fl oz'};
    }
    return {'value': value, 'unit': unit};
  }

  // ── CullyAI: Normalize any weight value to kilograms for comparison ──
  double _convertToKg(double value, String unit) {
    final unitLower = unit.toLowerCase().trim();
    if (unitLower == 'kg' || unitLower == 'kilogram' || unitLower == 'kilograms' || unitLower == 'kilogramm') {
      return value;
    }
    if (unitLower == 't' || unitLower == 'ton' || unitLower == 'tons' || unitLower == 'tonne' || unitLower == 'tonnes') {
      return value * 1000;
    }
    if (unitLower == 'g' || unitLower == 'gram' || unitLower == 'grams' || unitLower == 'gramm') {
      return value / 1000;
    }
    if (unitLower == 'lb' || unitLower == 'lbs' || unitLower == 'pound' || unitLower == 'pounds') {
      return value * 0.453592;
    }
    if (unitLower == 'oz' || unitLower == 'ounce' || unitLower == 'ounces') {
      return value * 0.0283495;
    }
    // Volume units pass through to _normalizeToBase
    return value; // fallback: assume kg
  }

  // ── CullyAI: Check if a unit is a volume unit ──
  bool _isVolumeUnit(String unit) {
    final u = unit.toLowerCase().trim();
    return u == 'ft³' || u == 'ft3' || u == 'cubic feet' || u == 'cu ft' ||
           u == 'm³' || u == 'm3' || u == 'cubic meter' || u == 'cubic meters' || u == 'cbm' ||
           u == 'l' || u == 'liter' || u == 'liters' || u == 'litre' || u == 'litres' ||
           u == 'ml' || u == 'milliliter' || u == 'milliliters' || u == 'millilitre' || u == 'millilitres' ||
           u == 'cl' || u == 'centiliter' || u == 'centiliters' || u == 'centilitre' || u == 'centilitres' ||
           u == 'dl' || u == 'deciliter' || u == 'deciliters' || u == 'decilitre' || u == 'decilitres' ||
           u == 'gal' || u == 'gallon' || u == 'gallons' ||
           u == 'qt' || u == 'quart' || u == 'quarts' ||
           u == 'pt' || u == 'pint' || u == 'pints' ||
           u == 'fl oz' || u == 'floz' || u == 'fluid oz' || u == 'fluid ounce' || u == 'fluid ounces' ||
           u == 'yd³' || u == 'yd3' || u == 'cubic yard' || u == 'cubic yards';
  }

  // ── CullyAI: Normalize any unit to a common base for comparison ──
  // Weight → kilograms, Volume → cubic meters
  double _normalizeToBase(double value, String unit) {
    final u = unit.toLowerCase().trim();
    // Weight units → kg
    if (u == 'kg' || u == 'kilogram' || u == 'kilograms' || u == 'kilogramm') return value;
    if (u == 't' || u == 'ton' || u == 'tons' || u == 'tonne' || u == 'tonnes') return value * 1000;
    if (u == 'g' || u == 'gram' || u == 'grams' || u == 'gramm') return value / 1000;
    if (u == 'lb' || u == 'lbs' || u == 'pound' || u == 'pounds') return value * 0.453592;
    if (u == 'oz' || u == 'ounce' || u == 'ounces') return value * 0.0283495;
    // Volume units → m³
    if (u == 'm³' || u == 'm3' || u == 'cubic meter' || u == 'cubic meters' || u == 'cbm') return value;
    if (u == 'ft³' || u == 'ft3' || u == 'cubic feet' || u == 'cu ft') return value * 0.0283168;
    if (u == 'l' || u == 'liter' || u == 'liters' || u == 'litre' || u == 'litres') return value * 0.001;
    if (u == 'ml' || u == 'milliliter' || u == 'milliliters' || u == 'millilitre' || u == 'millilitres') return value * 0.000001;
    if (u == 'cl' || u == 'centiliter' || u == 'centiliters' || u == 'centilitre' || u == 'centilitres') return value * 0.00001;
    if (u == 'dl' || u == 'deciliter' || u == 'deciliters' || u == 'decilitre' || u == 'decilitres') return value * 0.0001;
    if (u == 'gal' || u == 'gallon' || u == 'gallons') return value * 0.00378541;
    if (u == 'qt' || u == 'quart' || u == 'quarts') return value * 0.000946353;
    if (u == 'pt' || u == 'pint' || u == 'pints') return value * 0.000473176;
    if (u == 'fl oz' || u == 'floz' || u == 'fluid oz' || u == 'fluid ounce' || u == 'fluid ounces') return value * 0.0000295735;
    if (u == 'yd³' || u == 'yd3' || u == 'cubic yard' || u == 'cubic yards') return value * 0.764555;
    return value; // fallback
  }
}

// Accepted Order Marker with Denial Animation
class _AcceptedOrderMarkerWithDenial extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool isLight;
  final VoidCallback onTap;

  const _AcceptedOrderMarkerWithDenial({
    super.key,
    required this.order,
    required this.isLight,
    required this.onTap,
  });

  @override
  State<_AcceptedOrderMarkerWithDenial> createState() =>
      _AcceptedOrderMarkerWithDenialState();
}

class _AcceptedOrderMarkerWithDenialState
    extends State<_AcceptedOrderMarkerWithDenial>
    with TickerProviderStateMixin {
  late AnimationController _shakeController;
  late AnimationController _scaleController;
  late AnimationController _rotationController;
  late AnimationController _breatheController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _breatheAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this);
    _shakeAnimation = Tween<double>(begin: -8.0, end: 8.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack));
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this);
    _rotationAnimation = Tween<double>(begin: 0.0, end: 0.08).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.elasticOut));
    _breatheController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this);
    // Removed .repeat() - breathing animation not needed for performance
    _breatheAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _scaleController.dispose();
    _rotationController.dispose();
    _breatheController.dispose();
    super.dispose();
  }

  void _showDenialAnimation() {
    HapticFeedback.heavyImpact();
    _scaleController.forward().then((_) {
      _scaleController.reverse();
    });
    _shakeController.forward().then((_) {
      _shakeController.reset();
    });
    _rotationController.forward().then((_) {
      _rotationController.reset();
    });
  }

  // Helper method to safely convert dynamic values to double
  double _toDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  @override
  Widget build(BuildContext context) {
    final acceptanceStatus =
        (widget.order['acceptance_status']?.toString() ?? AppLocalizations.of(context)!.tr('available'));
    final isAccepted =
        acceptanceStatus == 'accepted' || acceptanceStatus == 'picked_up';

    // Check if this is an emergency order - other drivers should be able to help
    final isEmergency =
        widget.order['has_issue'] == 1 ||
        widget.order['has_issue'] == true ||
        widget.order['issue_emergency'] == 1 ||
        widget.order['issue_emergency'] == true;

    return TradeRepublicTap(
      onTap: () {
        // Allow emergency orders to be tapped even if already accepted
        if (isEmergency) {
          widget.onTap();
        } else if (isAccepted) {
          _showDenialAnimation();
        } else {
          widget.onTap();
        }
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _shakeAnimation,
          _scaleAnimation,
          _rotationAnimation,
          _breatheAnimation,
        ]),
        builder: (context, child) {
          final breatheScale = 1.0 + (_breatheAnimation.value * 0.006);

          // Calculate shake offset
          double shakeOffset = 0;
          if (_shakeAnimation.value > 0) {
            shakeOffset = math.sin(_shakeAnimation.value * math.pi * 8) * 3;
          }

          // Calculate rotation
          double rotation = 0;
          if (_rotationAnimation.value > 0) {
            rotation = math.sin(_rotationAnimation.value * math.pi * 4) * 0.1;
          }

          final scale = _scaleAnimation.value * breatheScale;

          return Transform.scale(
            scale: scale,
            child: Transform.translate(
              offset: Offset(shakeOffset, 0),
              child: Transform.rotate(
                angle: rotation,
                child: _buildAppleStyleOrderMarker(
                  widget.order,
                  widget.isLight))));
        }));
  }

  // Convert weight to user's preferred unit based on AppSettings
  Map<String, dynamic> _convertWeightToUserUnit(double value, String unit) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final unitLower = unit.toLowerCase().trim();
    final usePounds = appSettings.effectiveWeightUnit == 'Pounds';

    if (unitLower == 'kg' ||
        unitLower == 'kilogram' ||
        unitLower == 'kilograms' ||
        unitLower == 'kilogramm') {
      if (usePounds) return {'value': value * 2.20462, 'unit': 'lb'};
      return {'value': value, 'unit': 'kg'};
    }
    if (unitLower == 't' ||
        unitLower == 'ton' ||
        unitLower == 'tons' ||
        unitLower == 'tonne' ||
        unitLower == 'tonnes') {
      if (usePounds) return {'value': value * 2204.62, 'unit': 'lb'};
      return {'value': value * 1000, 'unit': 'kg'};
    }
    if (unitLower == 'g' ||
        unitLower == 'gram' ||
        unitLower == 'grams' ||
        unitLower == 'gramm') {
      if (usePounds) {
        final lbValue = value * 0.00220462;
        if (lbValue < 0.1) return {'value': value * 0.035274, 'unit': 'oz'};
        return {'value': lbValue, 'unit': 'lb'};
      }
      if (value < 1000) return {'value': value, 'unit': 'g'};
      return {'value': value / 1000, 'unit': 'kg'};
    }
    if (unitLower == 'lb' ||
        unitLower == 'lbs' ||
        unitLower == 'pound' ||
        unitLower == 'pounds') {
      if (!usePounds) return {'value': value * 0.453592, 'unit': 'kg'};
      return {'value': value, 'unit': 'lb'};
    }
    if (unitLower == 'oz' || unitLower == 'ounce' || unitLower == 'ounces') {
      if (usePounds) {
        if (value < 16) return {'value': value, 'unit': 'oz'};
        return {'value': value / 16, 'unit': 'lb'};
      }
      final grams = value * 28.3495;
      if (grams < 1000) return {'value': grams, 'unit': 'g'};
      return {'value': grams / 1000, 'unit': 'kg'};
    }
    return {'value': value, 'unit': unit};
  }

  // Beautiful Apple Maps-Style Order Marker - Clean & Modern with Status Colors
  Widget _buildAppleStyleOrderMarker(Map<String, dynamic> order, bool isLight) {
    final isExpress = order['priority'] == 'express';
    final items = List<Map<String, dynamic>>.from(order['items'] ?? []);
    final itemCount = items.length;
    final acceptanceStatus =
        (order['acceptance_status']?.toString() ?? AppLocalizations.of(context)!.tr('available'));
    final isEmergency =
        (order['has_issue'] == 1 ||
        order['has_issue'] == true ||
        order['emergency'] == 1 ||
        order['emergency'] == true);

    // Get quantity/weight for display in marker - convert to user's preferred unit
    final rawQuantity = _toDouble(order['total_quantity'], defaultValue: 0.0);
    final rawUnit = order['quantity_unit']?.toString() ?? AppLocalizations.of(context)!.tr('t');

    // Format the weight text for the marker using user's preferred unit
    String weightText;
    if (rawQuantity > 0) {
      final converted = _convertWeightToUserUnit(rawQuantity, rawUnit);
      final quantity = converted['value'] as double;
      final unit = converted['unit'] as String;

      if (quantity >= 1000 && (unit == 'kg' || unit == 'lb')) {
        final appSettings = Provider.of<AppSettings>(context, listen: false);
        if (unit == 'kg') {
          weightText = '${appSettings.formatNumber(quantity / 1000, decimals: 1)}t';
        } else {
          weightText = '${appSettings.formatNumber(quantity / 1000, decimals: 1)}k lb';
        }
      } else if (quantity == quantity.roundToDouble()) {
        weightText = '${quantity.toInt()}$unit';
      } else {
        final appSettings = Provider.of<AppSettings>(context, listen: false);
        weightText = '${appSettings.formatNumber(quantity, decimals: 1)}$unit';
      }
    } else {
      double itemsWeight = 0;
      String itemsUnit = 'kg';
      for (var item in items) {
        itemsWeight += _toDouble(item['quantity'], defaultValue: 1.0);
        if (item['unit'] != null) itemsUnit = item['unit'].toString();
      }
      if (itemsWeight > 0) {
        final converted = _convertWeightToUserUnit(itemsWeight, itemsUnit);
        final quantity = converted['value'] as double;
        final unit = converted['unit'] as String;
        final appSettings = Provider.of<AppSettings>(context, listen: false);
        weightText = '${appSettings.formatNumber(quantity, decimals: 0)}$unit';
      } else {
        weightText = '${items.length}x';
      }
    }

    // Oval background color based on theme (will be overridden for emergency)
    Color ovalColor = isLight ? Colors.black : Colors.white;
    Color textColor = isLight ? Colors.white : Colors.black;

    // Debug logging with correct order ID
    final displayOrderId = order['order_id'] ?? order['id'];
    print(
      '🎯 [SECOND FUNCTION] Building marker for order #$displayOrderId: status=$acceptanceStatus, weight=$weightText');
    print('⚖️ [SECOND FUNCTION] Weight IN PIN: $weightText');
    print(
      '🎨 [SECOND FUNCTION] Theme: ${isLight ? "LIGHT" : "DARK"}, Oval color: ${isLight ? "BLACK" : "WHITE"}');
    print(
      '📦 [SECOND FUNCTION] Raw order data: ${order.toString().substring(0, 200)}...');

    // Shadow color only
    Color shadowColor;

    switch (acceptanceStatus) {
      case 'accepted':
      case 'picked_up':
        // Red shadow for accepted/in-progress orders
        print('🔴 Setting RED shadow for accepted order #$displayOrderId');
        shadowColor = const Color(0xFFFF3B30);
        break;
      case 'available':
      default:
        // Shadow color based on express status
        print('🔵 Setting shadow color for available order #$displayOrderId');
        if (isExpress) {
          shadowColor = const Color(0xFFFF9500);
        } else {
          shadowColor = const Color(0xFF5E5CE6);
        }
        break;
    }
    if (isEmergency) {
      print(
        '🚨 Emergency order detected for #$displayOrderId [secondary marker] -> forcing RED marker (shadow + oval)');
      shadowColor = const Color(0xFFFF3B30);
      ovalColor = const Color(0xFFFF3B30); // Make the oval itself RED
      textColor = Colors.white; // White text on red background
    }

    return SizedBox(
      height: 60, // Fixed height to prevent overflow
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Beautiful Uber-style pin with status-based colors
          Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow
              Container(
                width: 68,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 4),
                  ])),
              // Main marker with WEIGHT (OVAL)
              Container(
                width: 60,
                height: 40,
                decoration: BoxDecoration(
                  color: ovalColor,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4)),
                  ]),
                child: Stack(
                  children: [
                    // WEIGHT TEXT instead of price
                    Center(
                      child: Text(
                        weightText,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3))),

                    // Item count badge (top-right)
                    if (itemCount > 1)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            shape: BoxShape.circle),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18),
                          child: Center(
                            child: Text(
                              '$itemCount',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700))))),

                    // UBER-STYLE: Bold, minimal strikethrough for accepted orders
                    if (acceptanceStatus == 'accepted' ||
                        acceptanceStatus == 'picked_up')
                      Center(
                        child: Container(
                          width: 56, // Slightly wider than marker
                          height: 4, // Thick, bold Uber-style line
                          decoration: BoxDecoration(
                            color: Colors.red.shade700, // Bold Uber red
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 3,
                                offset: const Offset(0, 2)),
                            ]))),

                    // Express badge (bottom-left)
                    if (isExpress)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade600,
                            shape: BoxShape.circle),
                          child: Icon(
                            CupertinoIcons.bolt,
                            color: Colors.white,
                            size: 10))),
                  ])),
            ]),

          // Pin tail
          SizedBox(height: 2),
          CustomPaint(
            size: const Size(8, 6),
            painter: _PinPointerPainter(color: ovalColor, isLight: isLight)),
        ]));
  }
}

// Modern notification widget that slides down from top

// Success Animation Widget with celebration effect
class _SuccessAnimationWidget extends StatefulWidget {
  final VoidCallback onComplete;

  const _SuccessAnimationWidget({required this.onComplete});

  @override
  State<_SuccessAnimationWidget> createState() =>
      _SuccessAnimationWidgetState();
}

class _SuccessAnimationWidgetState extends State<_SuccessAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      // Slower iOS timing
      vsync: this);

    _fadeController = AnimationController(
      // Extended iOS fade
      vsync: this);

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: Curves.easeOutQuint, // iOS spring curve
      ));

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeInOutQuart, // iOS smooth fade
      ));

    // Start animations
    _scaleController.forward();

    // Start fade out after scale completes
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _fadeController.forward().then((_) {
          widget.onComplete();
        });
      }
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.4), // Darker iOS backdrop
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_scaleAnimation, _fadeAnimation]),
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _fadeAnimation.value.clamp(0.0, 1.0),
                  child: Container(
                    width: 180, // Larger iOS success indicator
                    height: 180,
                    decoration: BoxDecoration(
                      // iOS 26 Success Glass Effect
                      color: Colors.white.withOpacity(0.95),
                      shape: BoxShape.circle,
                      boxShadow: [
                        // iOS 26 Primary success shadow
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 64,
                          spreadRadius: 0,
                          offset: const Offset(0, 24)),
                        // iOS ambient shadow
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 32,
                          spreadRadius: -8,
                          offset: const Offset(0, 12)),
                        // iOS success glow
                        BoxShadow(
                          color: const Color(0xFF34C759).withOpacity(0.4),
                          blurRadius: 48,
                          spreadRadius: 0,
                          offset: const Offset(0, 0)),
                        // Glass highlight
                        BoxShadow(
                          color: Colors.white.withOpacity(0.95),
                          blurRadius: 0.5,
                          spreadRadius: 0,
                          offset: const Offset(0, -1)),
                      ]),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: Colors
                              .green
                              .shade600, // Green icon on white glass background
                          size: 64),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          AppLocalizations.of(context)?.success ?? AppLocalizations.of(context)!.tr('SUCCESS!'),
                          style: TextStyle(
                            color: Colors
                                .green
                                .shade700, // Green text on white glass background
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                            fontWeight: FontWeight.w700)),
                        Text(
                          '🎉',
                          style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 10, fontFamily: 'Poppins')),
                      ]))));
            }))));
  }
}

// Message Modal Widget with Apple iOS/macOS 26 Design
class _MessageModalWidget extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool isLight;

  const _MessageModalWidget({required this.order, required this.isLight});

  @override
  State<_MessageModalWidget> createState() => _MessageModalWidgetState();
}

class _MessageModalWidgetState extends State<_MessageModalWidget> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final orderId = widget.order['id'] ?? widget.order['order_id'] ?? 0;
      final response = await http.get(
        Uri.parse(ApiConfig.getOrderMessagesUrl(orderId)),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
          _isLoading = false;
        });

        // Scroll to bottom after loading messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
          }
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final orderId = widget.order['id'] ?? widget.order['order_id'] ?? 0;
      final items = List<Map<String, dynamic>>.from(
        widget.order['items'] ?? []);

      if (items.isEmpty) {
        throw Exception('No items found in order');
      }

      final firstItem = items[0];
      final productId = firstItem['id'] ?? firstItem['product_id'];

      final response = await http.post(
        Uri.parse(ApiConfig.getOrderMessagesUrl(orderId)),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'product_id': productId,
          'sender_type': 'driver',
          'sender_id': 1, // TODO: Get actual driver ID
          'recipient_type': 'seller',
          'recipient_id': 1, // TODO: Get actual seller ID
          'message_text': messageText,
          'message_type': 'text',
        }));

      if (response.statusCode == 201) {
        _messageController.clear();
        await _loadMessages(); // Reload messages to show the new one

        // Show success haptic feedback
        HapticFeedback.lightImpact();
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? AppLocalizations.of(context)?.failedToSendMessage ?? AppLocalizations.of(context)!.tr('Failed to send message'));
      }
    } catch (e) {
      print('Error sending message: $e');
      // Show error notification
      TopNotification.error(context, '${AppLocalizations.of(context)?.failedToSendMessage ?? AppLocalizations.of(context)!.tr('Failed to send message')}: ${e.toString()}');
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: BoxDecoration(
            color: widget.isLight
                ? Colors.white.withOpacity(0.85)
                : Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 40,
                offset: const Offset(0, -12)),
            ]),
          child: Column(
            children: [
              const DragHandle(),
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.chat_bubble_text,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.messageSeller ?? AppLocalizations.of(context)!.tr('Message Seller'),
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                            color: widget.isLight ? Colors.black : Colors.white, letterSpacing: -0.4)),
                        SizedBox(height: 4),
                        Text(
                          '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}${widget.order['id'] ?? widget.order['order_id']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.isLight
                                ? Colors.black.withOpacity(0.5)
                                : Colors.white.withOpacity(0.5),
                            fontWeight: FontWeight.w500)),
                      ])),
                  TradeRepublicButton.icon(
                    icon: Icon(
                      CupertinoIcons.xmark,
                      size: 16,
                      color: widget.isLight ? Colors.black : Colors.white),
                    size: 32,
                    isSecondary: true,
                    onPressed: () => Navigator.pop(context)),
                ]),

              // Messages list
              Expanded(
                child: _isLoading
                    ? const Center(child: CultiooLoadingIndicator())
                    : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.chat_bubble,
                              size: 64,
                              color: widget.isLight
                                  ? Colors.black.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.3)),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            Text(
                              AppLocalizations.of(context)?.noMessagesYet ?? AppLocalizations.of(context)!.tr('No messages yet'),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                fontWeight: FontWeight.w500,
                                color: widget.isLight
                                    ? Colors.black.withOpacity(0.6)
                                    : Colors.white.withOpacity(0.6))),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            Text(
                              AppLocalizations.of(context)?.sendMessageToStart ?? AppLocalizations.of(context)!.tr('Send a message to start the conversation'),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                color: widget.isLight
                                    ? Colors.black.withOpacity(0.5)
                                    : Colors.white.withOpacity(0.5))),
                          ]))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.zero,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isFromDriver =
                              message['sender_type'] == 'driver';

                          return Container(
                            margin: EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: isFromDriver
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                if (!isFromDriver) ...[
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                    child: Icon(
                                      CupertinoIcons.bag,
                                      size: 16,
                                      color: Colors.green)),
                                  SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isFromDriver
                                          ? Colors.blue
                                          : widget.isLight
                                          ? Colors.white
                                          : Colors.black,
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          message['message_text'] ?? AppLocalizations.of(context)!.tr(''),
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: isFromDriver
                                                ? Colors.white
                                                : widget.isLight
                                                ? Colors.black
                                                : Colors.white)),
                                        SizedBox(height: 4),
                                        Text(
                                          _formatTime(message['created_at']),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isFromDriver
                                                ? Colors.white.withOpacity(0.7)
                                                : widget.isLight
                                                ? Colors.black.withOpacity(0.5)
                                                : Colors.white.withOpacity(0.5))),
                                      ]))),
                                if (isFromDriver) ...[
                                  SizedBox(width: 8),
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                    child: Icon(
                                      CupertinoIcons.cube_box,
                                      size: 16,
                                      color: Colors.blue)),
                                ],
                              ]));
                        })),

              // Message input
              Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(context).padding.bottom + 16),
                decoration: BoxDecoration(
                  color: widget.isLight
                      ? Colors.white.withOpacity(0.8)
                      : Colors.black.withOpacity(0.8)),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.isLight ? Colors.white : Colors.black,
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                        child: TradeRepublicTextField(
                          controller: _messageController,
                          filled: false,
                          hintText: AppLocalizations.of(context)?.typeAMessage ?? AppLocalizations.of(context)!.tr('Type a message...'),
                          style: TextStyle(
                            color: widget.isLight ? Colors.black : Colors.white,
                            fontSize: DesktopOptimizedWidgets.getFontSize()),
                          maxLines: 3,
                          minLines: 1,
                          onSubmitted: (_) => _sendMessage()))),
                    SizedBox(width: 12),
                    TradeRepublicButton.icon(
                      icon: _isSending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CultiooLoadingIndicator(size: 20))
                          : Icon(
                              CupertinoIcons.paperplane,
                              color: Colors.white,
                              size: 20),
                      backgroundColor:
                          _messageController.text.trim().isNotEmpty && !_isSending
                          ? Colors.blue
                          : widget.isLight ? Colors.grey.shade300 : const Color(0xFF2C2C2E),
                      size: 44,
                      onPressed: _isSending ? null : _sendMessage),
                  ])),
            ]))));
  }

  String _formatTime(dynamic timestamp) {
    try {
      DateTime dateTime;
      if (timestamp is String) {
        dateTime = DateTime.parse(timestamp);
      } else {
        return AppLocalizations.of(context)?.justNow ?? AppLocalizations.of(context)!.tr('Now');
      }

      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return AppLocalizations.of(context)?.justNow ?? AppLocalizations.of(context)!.tr('Just now');
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return AppLocalizations.of(context)?.justNow ?? AppLocalizations.of(context)!.tr('Now');
    }
  }
}

// Price Input Modal Widget with proper state management
class _PriceInputModal extends StatefulWidget {
  final bool isLight;
  final AppSettings appSettings;
  final double currentToPickupDist;
  final double pickupToDeliveryDist;
  final bool requiresCleaningCertificate;
  final String initialPriceMode;
  final Function(int priceCents, int cleaningCents, String priceMode) onSubmit;

  const _PriceInputModal({
    required this.isLight,
    required this.appSettings,
    required this.currentToPickupDist,
    required this.pickupToDeliveryDist,
    required this.requiresCleaningCertificate,
    required this.initialPriceMode,
    required this.onSubmit,
  });

  @override
  State<_PriceInputModal> createState() => _PriceInputModalState();
}

class _PriceInputModalState extends State<_PriceInputModal> {
  int _priceCents = 0;
  int _cleaningCents = 0;
  late String _priceMode;

  @override
  void initState() {
    super.initState();
    _priceMode = widget.initialPriceMode;
    _priceCents = widget.initialPriceMode == 'total' ? 100 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final isValid =
        _priceCents > 0 &&
        (!widget.requiresCleaningCertificate || _cleaningCents > 0);

    return SizedBox(
      height:
          MediaQuery.of(context).size.height *
          (widget.requiresCleaningCertificate ? 0.85 : 0.78),
      child: Column(
        children: [
          // Trade Republic Handle bar
          const DragHandle(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
          // Distance info at top
          Container(
            margin: EdgeInsets.fromLTRB(0, 12, 0, 0),
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: widget.isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle)),
                    SizedBox(width: 10),
                    Text(
                      AppLocalizations.of(context)?.myLocationToPickup ?? AppLocalizations.of(context)!.tr('My Location → Pickup'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w500,
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontFamily: 'Poppins')),
                    const Spacer(),
                    Text(
                      widget.appSettings.formatDistance(
                        widget.currentToPickupDist),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontFamily: 'Poppins')),
                  ]),
                SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Color(0xFF6366F1),
                        shape: BoxShape.circle)),
                    SizedBox(width: 10),
                    Text(
                      AppLocalizations.of(context)?.pickupToDelivery ?? AppLocalizations.of(context)!.tr('Pickup → Delivery'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w500,
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontFamily: 'Poppins')),
                    const Spacer(),
                    Text(
                      widget.appSettings.formatDistance(
                        widget.pickupToDeliveryDist),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6366F1),
                        fontFamily: 'Poppins')),
                  ]),
              ])),
          // Title
          Padding(
            padding: EdgeInsets.only(top: 16, bottom: 12),
            child: Text(
              AppLocalizations.of(context)?.setYourPrice ?? AppLocalizations.of(context)!.tr('Set Your Price'),
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                fontWeight: FontWeight.w700,
                color: widget.isLight ? Colors.black : Colors.white,
                fontFamily: 'Poppins'))),
          // Price mode selection
          Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.totalPrice ?? AppLocalizations.of(context)!.tr('Total Price'),
                    backgroundColor: _priceMode == 'total'
                        ? const Color(0xFF6366F1)
                        : (widget.isLight ? Colors.white : Colors.black),
                    foregroundColor: _priceMode == 'total'
                        ? Colors.white
                        : (widget.isLight ? Colors.black : Colors.white),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _priceMode = 'total');
                    })),
                SizedBox(width: 12),
                Expanded(
                  child: TradeRepublicButton(
                    label: widget.appSettings.effectiveDistanceUnit == 'Miles'
                        ? AppLocalizations.of(context)?.perMile ?? AppLocalizations.of(context)!.tr('Per mile')
                        : AppLocalizations.of(context)?.perKm ?? AppLocalizations.of(context)!.tr('Per km'),
                    backgroundColor: _priceMode != 'total'
                        ? const Color(0xFF6366F1)
                        : (widget.isLight ? Colors.white : Colors.black),
                    foregroundColor: _priceMode != 'total'
                        ? Colors.white
                        : (widget.isLight ? Colors.black : Colors.white),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _priceMode =
                            widget.appSettings.effectiveDistanceUnit == 'Miles'
                            ? 'per_mile'
                            : 'per_km';
                      });
                    })),
              ]),
          SizedBox(height: 20),
          // Price input field
          Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: widget.isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
              child: Row(
                children: [
                  Text(
                    widget.appSettings.currencySymbol,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: widget.isLight ? Colors.black : Colors.white,
                      fontFamily: 'Poppins')),
                  SizedBox(width: 8),
                  Expanded(
                    child: _PriceInputField(
                      initialCents: _priceCents,
                      isLight: widget.isLight,
                      fontSize: 36,
                      onChanged: (cents) {
                        setState(() => _priceCents = cents);
                      })),
                  if (_priceMode != 'total')
                    Text(
                      _priceMode == 'per_km' ? '/km' : '/mi',
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                        fontWeight: FontWeight.w600,
                        color: (widget.isLight ? Colors.black : Colors.white).withOpacity(0.5),
                        fontFamily: 'Poppins')),
                ])),
          // Price slider
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: TradeRepublicValueSlider(
              value: (_priceCents / 100.0).clamp(0.0, _priceMode == 'total' ? 30000.0 : 500.0),
              min: _priceMode == 'total' ? 1.0 : 1.0,
              max: _priceMode == 'total' ? 30000.0 : 500.0,
              divisions: _priceMode == 'total' ? 300 : 500,
              activeColor: const Color(0xFF6366F1),
              inactiveColor: (widget.isLight ? Colors.black : Colors.white).withOpacity(0.08),
              thumbColor: const Color(0xFF6366F1),
              labelBuilder: (v) => widget.appSettings.formatCurrency(v),
              onChanged: (v) {
                final cents = (v * 100).round();
                setState(() => _priceCents = cents);
              })),
          // Slider range labels
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.appSettings.formatCurrency(_priceMode == 'total' ? 1.0 : 1.0),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: (widget.isLight ? Colors.black : Colors.white).withOpacity(0.3),
                    fontFamily: 'Poppins')),
                Text(
                  _priceMode == 'total'
                      ? widget.appSettings.formatCurrency(30000)
                      : widget.appSettings.formatCurrency(500),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: (widget.isLight ? Colors.black : Colors.white).withOpacity(0.3),
                    fontFamily: 'Poppins')),
              ])),
          // Calculated total when per km/mile
          if (_priceMode != 'total' && _priceCents > 0) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            Container(
                padding: DesktopAppWrapper.getPagePadding(),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${AppLocalizations.of(context)?.total ?? AppLocalizations.of(context)!.tr('Total')}: ',
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w500,
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontFamily: 'Poppins')),
                    Text(
                      () {
                        final dist = _priceMode == 'per_mile'
                            ? widget.pickupToDeliveryDist * 0.621371
                            : widget.pickupToDeliveryDist;
                        return widget.appSettings.formatCurrency((_priceCents / 100.0) * dist);
                      }(),
                      style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6366F1),
                        fontFamily: 'Poppins')),
                  ])),
          ],
          // Cleaning Certificate section
          if (widget.requiresCleaningCertificate) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Icon(
                      CupertinoIcons.checkmark_shield,
                      color: Color(0xFFFF9500),
                      size: 20)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.cleaningCertificateRequired ?? AppLocalizations.of(context)!.tr('Cleaning Certificate Required'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: widget.isLight ? Colors.black : Colors.white,
                            fontFamily: 'Poppins')),
                        Text(
                          AppLocalizations.of(context)?.buyerRequestsCleaning ?? AppLocalizations.of(context)!.tr('Buyer requests cleaning certificate'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: widget.isLight ? Colors.black : Colors.white,
                            fontFamily: 'Poppins')),
                      ])),
                ]),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8),
                decoration: BoxDecoration(
                  color: widget.isLight ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Row(
                  children: [
                    Text(
                      widget.appSettings.currencySymbol,
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                        fontWeight: FontWeight.w700,
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontFamily: 'Poppins')),
                    SizedBox(width: 8),
                    Expanded(
                      child: _PriceInputField(
                        initialCents: 0,
                        isLight: widget.isLight,
                        fontSize: 28,
                        onChanged: (cents) {
                          setState(() => _cleaningCents = cents);
                        })),
                    Text(
                      AppLocalizations.of(context)?.certificate ?? AppLocalizations.of(context)!.tr('Certificate'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFFF9500),
                        fontFamily: 'Poppins')),
                  ])),
          ],
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                ]))),
          // Submit button
          Padding(
            padding: EdgeInsets.only(
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 20),
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.submitBid ?? AppLocalizations.of(context)!.tr('Submit Bid'),
              icon: Icon(
                CupertinoIcons.paperplane,
                size: 20,
                color: Colors.white),
              backgroundColor: isValid
                  ? const Color(0xFF34C759)
                  : (widget.isLight
                        ? Colors.grey.shade300
                        : const Color(0xFF2C2C2E)),
              foregroundColor: isValid
                  ? Colors.white
                  : (widget.isLight ? Colors.black54 : Colors.white38),
              onPressed: () {
                debugPrint(
                  '🔴 Submit tapped! _priceCents=$_priceCents, _cleaningCents=$_cleaningCents, isValid=$isValid');
                HapticFeedback.heavyImpact();
                if (isValid) {
                  widget.onSubmit(_priceCents, _cleaningCents, _priceMode);
                  Navigator.pop(context);
                } else {
                  if (_priceCents <= 0) {
                    TopNotification.error(
                      context,
                      AppLocalizations.of(context)?.pleaseEnterDeliveryPrice ?? AppLocalizations.of(context)!.tr('Please enter a delivery price'));
                  } else if (widget.requiresCleaningCertificate &&
                      _cleaningCents <= 0) {
                    TopNotification.error(
                      context,
                      AppLocalizations.of(context)?.pleaseEnterCleaningCertPrice ?? AppLocalizations.of(context)!.tr('Please enter a cleaning certificate price'));
                  }
                }
              })),
        ]));
  }
}

// ─── Price Range Bottom Sheet ───────────────────────────────────────────────
// Completely self-contained: controllers & focus nodes live in initState /
// dispose — guaranteed safe even during the sheet's close animation.
class _PriceRangeBottomSheet extends StatefulWidget {
  final bool isLight;
  final double initialMin;
  final double initialMax;
  final Function(double min, double max) onApply;

  const _PriceRangeBottomSheet({
    required this.isLight,
    required this.initialMin,
    required this.initialMax,
    required this.onApply,
  });

  @override
  State<_PriceRangeBottomSheet> createState() => _PriceRangeBottomSheetState();
}

class _PriceRangeBottomSheetState extends State<_PriceRangeBottomSheet> {
  static const double _kMax = 100000;

  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late final FocusNode _minFocus;
  late final FocusNode _maxFocus;
  late double _tempMin;
  late double _tempMax;

  // Format a whole-dollar value as comma-separated string (empty for 0)
  static String _fmt(double v) {
    if (v <= 0) return '';
    return _CentsInputFormatter._addCommas(v.toInt().toString());
  }

  @override
  void initState() {
    super.initState();
    _tempMin = widget.initialMin > 0 ? widget.initialMin : 1.0;
    _tempMin = _tempMin.clamp(0, _kMax);
    _tempMax = widget.initialMax > 0 ? widget.initialMax : _kMax;
    _tempMax = _tempMax.clamp(_tempMin, _kMax);
    _minCtrl = TextEditingController(text: _fmt(_tempMin));
    _maxCtrl = TextEditingController(text: _fmt(_tempMax));
    _minFocus = FocusNode();
    _maxFocus = FocusNode();
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _minFocus.dispose();
    _maxFocus.dispose();
    super.dispose();
  }

  void _setCtrl(TextEditingController c, String text) {
    if (c.text != text) {
      c.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length));
    }
  }

  void _syncControllers() {
    _setCtrl(_minCtrl, _fmt(_tempMin));
    _setCtrl(_maxCtrl, _fmt(_tempMax));
  }

  void _applyPreset(double min, double max) {
    HapticFeedback.selectionClick();
    setState(() {
      _tempMin = min;
      _tempMax = max;
      _syncControllers();
    });
  }

  String get _rangeSummary {
    final noMin = _tempMin <= 0;
    final noMax = _tempMax >= _kMax;
    if (noMin && noMax) return 'All prices';
    if (noMin) return 'Up to \$${_fmt(_tempMax)}';
    if (noMax) return 'From \$${_fmt(_tempMin)}+';
    return '\$${_fmt(_tempMin)} – \$${_fmt(_tempMax)}';
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.isLight;
    final loc = AppLocalizations.of(context);
    final isDark = !isLight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header row ───────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 0, 0),
          child: TradeRepublicSectionHeader(
            title: loc?.priceRange ?? AppLocalizations.of(context)!.tr('Price Range'),
            subtitle: _rangeSummary,
            trailing: TradeRepublicTap(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _tempMin = 0;
                  _tempMax = _kMax;
                  _syncControllers();
                });
              },
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black)
                      .withOpacity(0.07),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Text(
                  loc?.reset ?? AppLocalizations.of(context)!.tr('Reset'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: (isDark ? Colors.white : Colors.black)
                        .withOpacity(0.65))))))),

        SizedBox(height: 20),

        // ── Scrollable body ──────────────────────────────────────
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(4, 24, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Min / Max input cards
                Row(
                  children: [
                    Expanded(
                      child: _PriceAmountCard(
                        label: loc?.minimum ?? AppLocalizations.of(context)!.tr('Min'),
                        controller: _minCtrl,
                        focusNode: _minFocus,
                        isLight: isLight,
                        onChanged: (v) => setState(() {
                          _tempMin = v;
                          _syncControllers();
                        }))),
                    SizedBox(width: 12),
                    Expanded(
                      child: _PriceAmountCard(
                        label: loc?.maximum ?? AppLocalizations.of(context)!.tr('Max'),
                        controller: _maxCtrl,
                        focusNode: _maxFocus,
                        isLight: isLight,
                        onChanged: (v) => setState(() {
                          _tempMax = v;
                          _syncControllers();
                        }))),
                  ]),

                SizedBox(height: 20),
                const TradeRepublicDivider(),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                TradeRepublicSectionHeader(
                  title: loc?.quickSelect ?? AppLocalizations.of(context)!.tr('Quick Select'),
                  padding: EdgeInsets.only(bottom: 12)),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PricePresetChip(
                      label: '0 – 100{currencySymbol}',
                      isSelected: _tempMin == 0 && _tempMax == 100,
                      isLight: isLight,
                      onTap: () => _applyPreset(0, 100)),
                    _PricePresetChip(
                      label: '100 – 500{currencySymbol}',
                      isSelected: _tempMin == 100 && _tempMax == 500,
                      isLight: isLight,
                      onTap: () => _applyPreset(100, 500)),
                    _PricePresetChip(
                      label: '500 – 1k{currencySymbol}',
                      isSelected: _tempMin == 500 && _tempMax == 1000,
                      isLight: isLight,
                      onTap: () => _applyPreset(500, 1000)),
                    _PricePresetChip(
                      label: '1k – 5k{currencySymbol}',
                      isSelected: _tempMin == 1000 && _tempMax == 5000,
                      isLight: isLight,
                      onTap: () => _applyPreset(1000, 5000)),
                    _PricePresetChip(
                      label: '5k – 10k{currencySymbol}',
                      isSelected: _tempMin == 5000 && _tempMax == 10000,
                      isLight: isLight,
                      onTap: () => _applyPreset(5000, 10000)),
                    _PricePresetChip(
                      label: '10k – 50k{currencySymbol}',
                      isSelected: _tempMin == 10000 && _tempMax == 50000,
                      isLight: isLight,
                      onTap: () => _applyPreset(10000, 50000)),
                  ]),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
              ]))),

        // ── Apply button ─────────────────────────────────────────
        Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: TradeRepublicButton(
            label: loc?.applyFilter ?? AppLocalizations.of(context)!.tr('Apply Filter'),
            width: double.infinity,
            onPressed: () {
              HapticFeedback.mediumImpact();
              final parsedMin =
                  double.tryParse(_minCtrl.text.replaceAll(',', '')) ?? 0;
              final parsedMax =
                  double.tryParse(_maxCtrl.text.replaceAll(',', '')) ?? _kMax;
              widget.onApply(
                math.min(parsedMin, parsedMax).clamp(0, _kMax),
                math.max(parsedMin, parsedMax).clamp(0, _kMax));
            })),
      ]);
  }
}

// ── Amount input card ──────────────────────────────────────────────────────
// Large-number text field with a surface background and currency prefix.
class _PriceAmountCard extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLight;
  final Function(double) onChanged;

  const _PriceAmountCard({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.isLight,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isLight ? Colors.black : Colors.white;
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    return TradeRepublicCard(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: fg.withOpacity(0.38))),
          SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                appSettings.currencySymbol,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  letterSpacing: -0.5,
                  color: fg.withOpacity(0.18))),
              SizedBox(width: 3),
              Expanded(
                child: TradeRepublicTextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ThousandSeparatorFormatter()],
                  textInputAction: TextInputAction.next,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -0.5,
                    color: fg),
                  hintText: AppLocalizations.of(context)!.tr('0') ?? AppLocalizations.of(context)!.tr('0'),
                  hintStyle: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -0.5,
                    color: fg.withOpacity(0.18)),
                  filled: false,
                  onChanged: (text) {
                    final parsed =
                        double.tryParse(text.replaceAll(',', '')) ?? 0;
                    onChanged(parsed.clamp(0, 100000));
                  })),
            ]),
        ]));
  }
}

// ── Preset chip ────────────────────────────────────────────────────────────
class _PricePresetChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isLight;
  final VoidCallback onTap;

  const _PricePresetChip({
    required this.label,
    required this.isSelected,
    required this.isLight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isLight ? Colors.black : Colors.white;
    return TradeRepublicTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? TradeRepublicTheme.selectedColor(context)
              : TradeRepublicTheme.fillColor(context, opacity: 0.06),
          borderRadius: BorderRadius.circular(22),
          border: isSelected
              ? null
              : Border.all(
                  color: fg.withOpacity(0.09),
                  width: 1)),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: isSelected
                ? (isLight ? Colors.white : Colors.black)
                : TradeRepublicTheme.hintColor(context, opacity: 0.72)))));
  }
}

// Right-to-left cents input formatter (1234 -> 12.34)
class _CentsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue) {
    // Remove all non-digits
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Limit to reasonable length (max 9,999,999.99)
    if (digitsOnly.length > 9) {
      digitsOnly = digitsOnly.substring(0, 9);
    }

    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0));
    }

    // Pad with zeros if less than 3 digits
    while (digitsOnly.length < 3) {
      digitsOnly = '0$digitsOnly';
    }

    // Split into integer (dollars) and fractional (cents) parts
    String intPart = digitsOnly.substring(0, digitsOnly.length - 2);
    final decPart = digitsOnly.substring(digitsOnly.length - 2);

    // Remove leading zeros from integer part (but keep at least one)
    while (intPart.length > 1 && intPart.startsWith('0')) {
      intPart = intPart.substring(1);
    }

    final formatted = '${_addCommas(intPart)}.$decPart';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length));
  }

  /// Adds thousand-separator commas to a pure-digit string, e.g. "1234567" → "1,234,567".
  static String _addCommas(String digits) {
    if (digits.length <= 3) return digits;
    final buf = StringBuffer();
    final offset = digits.length % 3;
    if (offset > 0) buf.write(digits.substring(0, offset));
    for (int i = offset; i < digits.length; i += 3) {
      if (buf.isNotEmpty) buf.write(',');
      buf.write(digits.substring(i, i + 3));
    }
    return buf.toString();
  }
}

/// Thousand-separator formatter for whole-dollar filter fields (no decimal part).
/// Typing "1000" shows "1,000"; left-to-right entry.
class _ThousandSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue) {
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0));
    }
    // Remove leading zeros (but keep at least one)
    while (digitsOnly.length > 1 && digitsOnly.startsWith('0')) {
      digitsOnly = digitsOnly.substring(1);
    }
    final formatted = _CentsInputFormatter._addCommas(digitsOnly);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length));
  }
}

// Stateful Price Input Field that maintains its own controller
class _PriceInputField extends StatefulWidget {
  final int initialCents;
  final bool isLight;
  final double fontSize;
  final Function(int cents) onChanged;

  const _PriceInputField({
    required this.initialCents,
    required this.isLight,
    required this.fontSize,
    required this.onChanged,
  });

  @override
  State<_PriceInputField> createState() => _PriceInputFieldState();
}

class _PriceInputFieldState extends State<_PriceInputField> {
  late TextEditingController _controller;
  int _currentCents = 0;

  @override
  void initState() {
    super.initState();
    _currentCents = widget.initialCents;
    _controller = TextEditingController(text: _formatCents(_currentCents));
  }

  @override
  void didUpdateWidget(covariant _PriceInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync text field when parent updates cents (e.g. from slider)
    if (widget.initialCents != _currentCents) {
      _currentCents = widget.initialCents;
      final newText = _formatCents(_currentCents);
      if (_controller.text != newText) {
        _controller.text = newText;
        _controller.selection = TextSelection.collapsed(offset: newText.length);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatCents(int cents) {
    if (cents == 0) return '';
    final dollars = cents ~/ 100;
    final remainingCents = cents % 100;
    return '${_CentsInputFormatter._addCommas(dollars.toString())}.${remainingCents.toString().padLeft(2, '0')}';
  }

  void _handleInput(String value) {
    // Remove all non-digits
    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
    final cents = int.tryParse(digitsOnly) ?? 0;

    debugPrint(
      '🔵 _handleInput: value="$value", digitsOnly="$digitsOnly", cents=$cents, _currentCents=$_currentCents');

    // Always call onChanged to ensure parent gets updated
    _currentCents = cents;
    widget.onChanged(cents);
  }

  @override
  Widget build(BuildContext context) {
    return TradeRepublicTextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true),
      textInputAction: TextInputAction.done,
      inputFormatters: [_CentsInputFormatter()],
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w700,
        color: widget.isLight ? Colors.black : Colors.white,
        fontFamily: 'Poppins'),
      hintText: AppLocalizations.of(context)!.tr('0.00') ?? AppLocalizations.of(context)!.tr('0.00'),
      onChanged: _handleInput);
  }
}
