import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as dartui; // used for Path in painters to avoid latlong2.Path conflict
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import '../../config/api_config.dart';
import '../../shared/services/app_settings.dart';
import '../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../shared/widgets/trade_republic_button.dart';
import '../../shared/widgets/trade_republic_list_tile.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../shared/widgets/trade_republic_card.dart';
import '../../shared/services/app_localizations.dart';
import '../../shared/services/live_activity_service.dart';
import '../../shared/widgets/cultioo_spinner.dart';
import '../../shared/widgets/qr_scanner_sheet.dart';
import '../../shared/widgets/trade_republic_tap.dart';


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

enum NavigationPhase {
  toPickup,
  atPickup,
  toDelivery,
  completed,
  multiOrderPickups, // Phase for collecting multiple pickups
  multiOrderDeliveries, // Phase for delivering multiple orders
}

enum NavigationMode { online, offline }

// Custom painter for animated checkmark
class CheckmarkPainter extends CustomPainter {
  final double progress;

  CheckmarkPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Draw circle background
    final circlePaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, circlePaint);

    // Draw checkmark using individual lines instead of Path to avoid conflict
    const double checkStart = 0.3;
    const double checkMiddle = 0.5;
    const double checkEnd = 0.8;

    final startPoint = Offset(size.width * checkStart, size.height * 0.5);
    final middlePoint = Offset(size.width * checkMiddle, size.height * 0.65);
    final endPoint = Offset(size.width * checkEnd, size.height * 0.35);

    if (progress > 0) {
      if (progress <= 0.5) {
        // First half: draw from start to middle
        final currentPoint = Offset.lerp(startPoint, middlePoint, progress * 2);
        canvas.drawLine(startPoint, currentPoint!, paint);
      } else {
        // Draw complete first half
        canvas.drawLine(startPoint, middlePoint, paint);
        // Second half: draw from middle to end
        final currentPoint = Offset.lerp(
          middlePoint,
          endPoint,
          (progress - 0.5) * 2);
        canvas.drawLine(middlePoint, currentPoint!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CheckmarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// Solid filled upward-pointing triangle for pickup marker (same as maps page)
class _NavSolidTrianglePainter extends CustomPainter {
  final Color color;

  _NavSolidTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()
      ..color = color.withOpacity(0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const double r = 4.0;
    final top   = Offset(size.width / 2, 0);
    final right = Offset(size.width,     size.height);
    final left  = Offset(0,              size.height);

    Offset along(Offset from, Offset to, double dist) {
      final d = to - from;
      return from + d / d.distance * dist;
    }

    final path = dartui.Path()
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
  bool shouldRepaint(_NavSolidTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

class NavigationModal extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback? onNavigationStarted;
  final VoidCallback? onNavigationCompleted;

  const NavigationModal({
    super.key,
    required this.order,
    this.onNavigationStarted,
    this.onNavigationCompleted,
  });

  @override
  State<NavigationModal> createState() => _NavigationModalState();
}

class _NavigationModalState extends State<NavigationModal>
    with TickerProviderStateMixin {
  NavigationPhase _currentPhase = NavigationPhase.toPickup;
  NavigationMode _navigationMode = NavigationMode.online;

  late MapController _mapController;
  apple.AppleMapController?
  _appleMapController; // Apple Maps controller for iOS
  LatLng?
  _currentLocation; // Will be set from real GPS only, null if permission denied
  LatLng _pickupLocation = const LatLng(
    0.0,
    0.0); // Will be set from order data
  LatLng _deliveryLocation = const LatLng(
    0.0,
    0.0); // Will be loaded from API or order data
  List<LatLng> _routePoints = [];
  List<String> _routeInstructions = [];
  List<Color> _routeColors = [];
  int _closestRoutePointIndex =
      0; // Track current position on route for gray coloring
  double _currentBearing =
      0.0; // Track direction/rotation of movement (0-360 degrees)

  // Multi-Order Navigation State
  List<Map<String, dynamic>> _allOrders = [];
  final List<LatLng> _allPickupLocations = [];
  final List<LatLng> _allDeliveryLocations = [];
  int _currentPickupIndex = 0;
  int _currentDeliveryIndex = 0;
  bool _isMultiOrderMode = false;
  final List<Map<String, dynamic>> _completedDeliveries = [];
  String?
  _multiOrderSessionId; // Persistent session ID for multi-order navigation
  bool _navigationStateRestoredFromDB =
      false; // Flag to prevent overriding restored state
  bool _isClosingNavigation =
      false; // Flag to prevent multiple simultaneous close operations
  bool _restoreSheetShown = false; // Guard: prevent pickup/free-time sheet from showing twice on double load
    bool _restoreScanSheetScheduled = false; // Guard: schedule scan sheet restore only once per modal instance

  // Native theme sync – forces iOS window-level dark/light so MKMapView follows app theme
  // ...existing code...
  /// Called whenever inherited dependencies change (e.g. Provider / AppSettings).
  /// We register a listener on AppSettings so that changing the in-app theme
  /// immediately updates the iOS-level overrideUserInterfaceStyle, which
  /// propagates to native views like MKMapView (Apple Maps).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newSettings = Provider.of<AppSettings>(context, listen: false);
    if (_appSettings != newSettings) {
      _appSettings?.removeListener(_onAppThemeChanged);
      _appSettings = newSettings;
      _appSettings!.addListener(_onAppThemeChanged);
      _onAppThemeChanged(); // sync immediately with current theme
    }
  }

  void _onAppThemeChanged() {
    if (!mounted || _appSettings == null) return;
    _syncNativeTheme(isLight: _appSettings!.isLightMode(context));
  }

  /// Sends the desired iOS user-interface style to the native layer via
  /// MethodChannel.  [isLight] == null resets to "follow system" (unspecified).
  void _syncNativeTheme({required bool? isLight}) {
    if (!Platform.isIOS) return;
    // UIUserInterfaceStyle: 0 = unspecified, 1 = light, 2 = dark
    final style = isLight == null ? 0 : (isLight ? 1 : 2);
    _nativeThemeChannel.invokeMethod('setUserInterfaceStyle', style);
  }

  // Native theme sync – forces iOS window-level dark/light so MKMapView follows app theme
  static const _nativeThemeChannel = MethodChannel('com.cultioo/native_theme');
  AppSettings? _appSettings; // held to add/remove listener

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Modern Completion Animations
  late AnimationController _completionController;
  late Animation<double> _completionScaleAnimation;
  late Animation<double> _completionFadeAnimation;
  late Animation<double> _checkmarkAnimation;
  late Animation<double> _confettiAnimation;

  // Security Code Panel Animation
  late AnimationController _securityCodePanelController;
  late Animation<double> _securityCodeScaleAnimation;
  late Animation<double> _securityCodeFadeAnimation;

  // QR Scan Success Animation
  late AnimationController _scanSuccessController;
  late Animation<double> _scanSuccessScaleAnimation;
  late Animation<double> _scanSuccessFadeAnimation;
  MobileScannerController? _qrScannerController;

  Timer? _locationTimer;
  bool _isLoadingRoute = false;
  bool _navigationStarted = false;
  bool _showArrivedButton = false;
  bool _showSecurityCode = false;
  final int _securityCodeCountdown = 3;
  Timer? _securityCodeTimer;

  // QR Code Scanner State
  bool _showQRScanner = false;
  bool _isQRScannerLoading = false;
  String _qrScanResult = "";
  final ValueNotifier<bool>   _qrLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<String> _qrResultNotifier  = ValueNotifier('');

  // QR Code Display State (for delivery to show QR to customer)
  bool _showQRDisplay = false;

  // QR Scanner bottom sheet state
  StateSetter? _scannerSheetSetter;
  VoidCallback? _closeScannerSheet;

  // Guard flags to prevent duplicate bottom sheet opens
  bool _isPickupSheetOpen = false;
  bool _isDeliverySheetOpen = false;

  // Current order for multi-order delivery workflow
  Map<String, dynamic>? _currentOrder;

  // Last Mile AI State
  final List<Map<String, dynamic>> _nearbyOrders = [];
  bool _showLastMileOrder = false;
  Map<String, dynamic>? _suggestedOrder;
  Timer? _lastMileCheckTimer;
  DateTime? _lastLastMileCheck;

  String _estimatedArrival = "Loading...";
  String _totalDistance = "Loading...";

  // Full route distance/time (Pickup → Delivery) - shown BEFORE navigation starts
  String _fullRouteDistance = "Loading...";
  String _fullRouteTime = "Loading...";

  // Flag to prevent multiple total route calculations
  bool _isFetchingTotalRoute = false;
  bool _totalRouteCalculated = false;

  int _currentInstructionIndex = 0;
  String _securityCode = "";

  // Waiting Time Charges State
  Timer? _waitingTimer;
  int _waitingFreeMinutes = 15; // Default: 15 minutes free waiting
  double _waitingRatePerHour = 25.00; // Default: 25/hour after free time
  DateTime? _waitingStartTime; // When driver arrived at pickup
  int _waitingElapsedSeconds = 0; // Total seconds waited
  bool _freeTimeWarningShown = false; // 5-min warning notification shown
  bool _freeTimeExpiredShown = false; // Free time expired notification shown
  double _totalWaitingCharges = 0.0; // Calculated charges
  bool _isLoadingWaitingSettings = false;

  // Loading Timer State (starts on 1st QR scan / check-in, stops on 2nd QR scan / check-out)
  Timer? _loadingTimer;
  DateTime? _loadingStartTime;
  int _loadingElapsedSeconds = 0;

  // Scan phase per stop: 'waiting' → 1st scan → 'loading' → 2nd scan → 'done'
  // 'waiting' = waiting timer running, 'loading' = loading timer running
  String _scanPhase = 'waiting'; // reset on each new stop

  // External map app preference: 'none' | 'google' | 'waze' | 'apple'
  String _externalMapApp = 'none';

  // Check-in / Check-out timestamps → saved to orders table
  DateTime? _sellerCheckInAt;   // Arrived at pickup  (seller_check_in_at)
  DateTime? _sellerCheckOutAt;  // Left pickup / QR scanned  (seller_check_out_at)
  DateTime? _buyerCheckInAt;    // Arrived at delivery  (buyer_check_in_at)
  DateTime? _buyerCheckOutAt;   // Delivery completed / QR scanned  (buyer_check_out_at)

  // Delivery Polling — driver app polls every 3s to detect when buyer scanned the QR URL
  Timer? _deliveryPollTimer;
  bool _buyerScannedCheckIn = false;   // true after 1st buyer scan  (buyer_check_in_at set)
  bool _buyerScannedCheckOut = false;  // true after 2nd buyer scan  (buyer_check_out_at set)
  bool _isCompletingDelivery = false;  // guard against duplicate completion calls

  int _parseDriverId(dynamic raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    return int.tryParse(raw.toString()) ?? 0;
  }

  String? _normalizedDepartmentValue(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (value == '0' || lower == 'null' || lower == 'undefined') {
      return null;
    }
    return value;
  }

  Future<int> _getDriverId() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final candidates = <dynamic>[
        prefs.getInt('driver_id'),
        prefs.getInt('user_id'),
        prefs.getInt('driverId'),
        prefs.getInt('userId'),
        prefs.getString('driver_id'),
        prefs.getString('user_id'),
        prefs.getString('driverId'),
        prefs.getString('userId'),
      ];

      for (final c in candidates) {
        final parsed = _parseDriverId(c);
        if (parsed > 0) return parsed;
      }

      final token = prefs.getString('auth_token') ?? prefs.getString('token');
      if (token != null && token.isNotEmpty) {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = json.decode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));

          final tokenCandidates = <dynamic>[
            payload['driver_id'],
            payload['driverId'],
            payload['user_id'],
            payload['userId'],
            payload['id'],
          ];

          for (final c in tokenCandidates) {
            final parsed = _parseDriverId(c);
            if (parsed > 0) return parsed;
          }
        }
      }
    } catch (_) {}

    return 1;
  }


  @override
  void initState() {
    super.initState();

    // Reset total route calculation flags for fresh start
    _isFetchingTotalRoute = false;
    _totalRouteCalculated = false;

    _setupAnimations();
    _mapController = MapController();

    // Initialize current order first
    _currentOrder = widget.order;

    // Get order ID for checks
    final orderId = widget.order['order_id'] ?? widget.order['id'];

    // Only clear sessions if no active navigation is running
    // This allows modal to be reopened with preserved state
    _checkAndClearSessionsIfNeeded(orderId);

    // Reset navigation states to prevent accumulation
    _resetNavigationState();

    // CRITICAL FIX: Check if navigation state was pre-loaded from API
    _checkPreLoadedNavigationState();

    // Initialize multi-order mode BEFORE other setup
    _initializeMultiOrderModeSync();

    // DON'T extract order locations here - will be done after coordinate loading
    // _extractOrderLocations();

    // Schedule all async operations for after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCoordinatesAndInitialize();
    });
  }

  Future<void> _loadCoordinatesAndInitialize() async {
    final orderId = widget.order['order_id'] ?? widget.order['id'];

    // CRITICAL: Load driver's waiting time settings
    await _loadWaitingTimeSettings();

    // CRITICAL: Load delivery coordinates FIRST, before any navigation state loading

    // Check if this is multi-order batch
    final isBatchOrder =
        widget.order.containsKey('batch_orders') ||
        orderId.toString().startsWith('multi_');
    print(
      '   widget.order.containsKey(batch_orders): ${widget.order.containsKey('batch_orders')}');
    print(
      '   widget.order[batch_orders] type: ${widget.order['batch_orders']?.runtimeType}');
    print(
      '   widget.order[batch_orders] value: ${widget.order['batch_orders']}');

    // CRITICAL: Always try to load navigation state from database first
    // This allows resuming navigation for both single and multi-order modes
    await _loadNavigationState();

    // Initialize _allOrders IMMEDIATELY if batch order, before API call
    if (isBatchOrder &&
        widget.order.containsKey('batch_orders') &&
        widget.order['batch_orders'] != null) {
      _allOrders = List<Map<String, dynamic>>.from(
        widget.order['batch_orders']);
    }

    http
        .get(
          Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders'),
          headers: {'Content-Type': 'application/json'})
        .then((response) {
          if (response.statusCode == 200) {
            final List<dynamic> allOrdersFromAPI = jsonDecode(response.body);

            if (isBatchOrder &&
                widget.order.containsKey('batch_orders') &&
                widget.order['batch_orders'] != null) {
              // Multi-order batch: Load coordinates for ALL orders in the batch
              for (var batchOrder in _allOrders) {
                final batchOrderId = batchOrder['order_id'] ?? batchOrder['id'];
                if (batchOrderId.toString().startsWith('multi_')) continue;

                // Find this order in API response
                final freshOrder = allOrdersFromAPI.firstWhere(
                  (o) => (o['id'] ?? o['order_id']) == batchOrderId,
                  orElse: () => null);

                if (freshOrder != null) {
                  // Update ALL coordinate fields
                  batchOrder['pickup_lat'] = freshOrder['pickup_lat'];
                  batchOrder['pickup_lng'] = freshOrder['pickup_lng'];
                  batchOrder['pickup_street'] = freshOrder['pickup_street'];
                  batchOrder['pickup_city'] = freshOrder['pickup_city'];
                  batchOrder['pickup_zip'] = freshOrder['pickup_zip'];
                  batchOrder['product_seller'] = freshOrder['product_seller'];
                  batchOrder['seller_department'] = freshOrder['seller_department'];
                    batchOrder['department'] =
                      _normalizedDepartmentValue(freshOrder['department']) ??
                      _normalizedDepartmentValue(freshOrder['seller_department']);
                  batchOrder['loading_instruction'] = freshOrder['loading_instruction'];

                  // Update delivery coordinates from nested structure
                  if (freshOrder['delivery'] != null &&
                      freshOrder['delivery']['coordinates'] != null) {
                    final coords = freshOrder['delivery']['coordinates'];
                    batchOrder['delivery_lat'] = coords['lat'];
                    batchOrder['delivery_lng'] = coords['lng'];
                  }

                  // Also update status to keep navigation state in sync
                  batchOrder['status'] = freshOrder['status'];
                }
              }

              // Now extract all locations from updated batch orders
              _extractAllLocations();

              // Set multi-order mode flag AFTER successful extraction
              if ((_allOrders.isNotEmpty && isBatchOrder) ||
                  _allPickupLocations.length > 1 ||
                  _allDeliveryLocations.length > 1) {
                setState(() {
                  _isMultiOrderMode = true;
                  _currentPhase = NavigationPhase.multiOrderPickups;
                });
              }

              // Re-extract locations AFTER coordinates are loaded from API
              _extractAllLocations();
              if (!_navigationStarted &&
                  _currentPhase != NavigationPhase.completed) {
                print(
                  '🗺️ Scheduling preview route generation for multi-order');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted &&
                      !_navigationStarted &&
                      _currentPhase != NavigationPhase.completed) {
                    _generateRoute();
                  }
                });
              }
            } else {
              // Single order: Load coordinates for just this order
              // CRITICAL: Convert to string for comparison to handle int vs string type mismatch
              final orderIdStr = orderId.toString();
              final freshOrder = allOrdersFromAPI.firstWhere(
                (o) => (o['id'] ?? o['order_id']).toString() == orderIdStr,
                orElse: () => null);

              print(
                '🔍 Looking for order $orderIdStr in ${allOrdersFromAPI.length} orders from API');

              if (freshOrder != null) {
                print(
                  '🔄 ✅ Found and updating single order $orderId with fresh API data...');
                print(
                  '   Fresh order pickup_street: ${freshOrder['pickup_street']}');
                print(
                  '   Fresh order pickup_city: ${freshOrder['pickup_city']}');
                print('   Fresh order pickup_lat: ${freshOrder['pickup_lat']}');
                print('   Fresh order pickup_lng: ${freshOrder['pickup_lng']}');

                // CRITICAL: Update pickup coordinates from fresh API data
                if (freshOrder['pickup_lat'] != null &&
                    freshOrder['pickup_lng'] != null) {
                  widget.order['pickup_lat'] = freshOrder['pickup_lat'];
                  widget.order['pickup_lng'] = freshOrder['pickup_lng'];
                  widget.order['pickup_street'] = freshOrder['pickup_street'];
                  widget.order['pickup_city'] = freshOrder['pickup_city'];
                  widget.order['pickup_zip'] = freshOrder['pickup_zip'];
                  widget.order['product_seller'] = freshOrder['product_seller'];
                  widget.order['seller_department'] = freshOrder['seller_department'];
                    widget.order['department'] =
                      _normalizedDepartmentValue(freshOrder['department']) ??
                      _normalizedDepartmentValue(freshOrder['seller_department']);
                  widget.order['loading_instruction'] = freshOrder['loading_instruction'];

                  final pickupLat =
                      double.tryParse(freshOrder['pickup_lat'].toString()) ??
                      0.0;
                  final pickupLng =
                      double.tryParse(freshOrder['pickup_lng'].toString()) ??
                      0.0;
                  print('   📍 Pickup: ($pickupLat, $pickupLng)');
                }

                // Update delivery coordinates from nested structure
                if (freshOrder['delivery'] != null &&
                    freshOrder['delivery']['coordinates'] != null) {
                  final coords = freshOrder['delivery']['coordinates'];
                  final lat =
                      double.tryParse(coords['lat']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                      0.0;
                  final lng =
                      double.tryParse(coords['lng']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                      0.0;

                  if (lat != 0.0 && lng != 0.0) {
                    _deliveryLocation = LatLng(lat, lng);
                  }
                }

                // Update order status
                widget.order['status'] = freshOrder['status'];
              }

              // Extract order locations AFTER coordinates are loaded from API
              _extractOrderLocations();

              // Generate preview route if navigation hasn't started yet
              if (!_navigationStarted &&
                  _currentPhase != NavigationPhase.completed) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted &&
                      !_navigationStarted &&
                      _currentPhase != NavigationPhase.completed) {
                    _generateRoute();
                  }
                });
              }
            }
          }

          // NOW continue with navigation state loading
          return _checkAndLoadActiveNavigation();
        })
        .catchError((e) {
          print('⚠️ Could not pre-load delivery coordinates: $e');
          return _checkAndLoadActiveNavigation();
        })
        .then((_) {
          return _loadNavigationState();
        })
        .then((_) async {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_navigationStateRestoredFromDB) {
              _initializeMultiOrderMode();
            } else {
              print(
                '🔄 Skipping multi-order initialization - state was restored from DB');
            }

            if (mounted) {
              setState(() {
                print(
                  '🔄 Force UI update after navigation restoration - Phase: $_currentPhase, RestoredFromDB: $_navigationStateRestoredFromDB');
              });
            }
          });

          final orderStatus =
              widget.order['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');
          print(
            '🔍 Order $orderId status check: $orderStatus, current phase: $_currentPhase, restored from DB: $_navigationStateRestoredFromDB');

          // Schedule status-based phase changes for after build completes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;

            // If no navigation state was restored from DB, check order status to set correct phase
            if (!_navigationStateRestoredFromDB) {
              if (orderStatus == 'picked_up') {
                print(
                  '🚚 Order already picked up - starting delivery phase immediately');
                setState(() {
                  _currentPhase = NavigationPhase.toDelivery;
                  _navigationStarted =
                      true; // Auto-start navigation for delivery phase
                });
              } else if (orderStatus == 'delivered') {
                print(
                  '✅ Order already delivered - marking as completed and showing success UI');
                setState(() {
                  _currentPhase = NavigationPhase.completed;
                  _navigationStarted = false;
                  _showArrivedButton = false;
                  _showSecurityCode = false;
                  _showQRScanner = false;
                });

                // Schedule animation for after the state is set
                Timer(const Duration(milliseconds: 100), () {
                  if (mounted) {
                    _triggerCompletionAnimation();

                    // Show completion animation again for delivered orders
                    Timer(const Duration(milliseconds: 500), () {
                      if (mounted) {
                        _triggerCompletionAnimation();
                      }
                    });
                  }
                });
              } else if (orderStatus == 'accepted') {
                print(
                  '📦 Order accepted but not picked up - starting pickup phase');
                setState(() {
                  _currentPhase = NavigationPhase.toPickup;
                  _navigationStarted = false;
                });
              }
            } else {
              print(
                '✅ Navigation state restored from database - keeping current phase: $_currentPhase');
            }
          });

          // CRITICAL: For multi-order mode, ensure all locations are extracted BEFORE generating route
          // But DON'T generate route here - it was already generated in the API callback above
          if (_isMultiOrderMode && _allOrders.isNotEmpty) {
            print(
              '   Orders: ${_allOrders.length}, Pickups: ${_allPickupLocations.length}, Deliveries: ${_allDeliveryLocations.length}');

            if (_allPickupLocations.isEmpty || _allDeliveryLocations.isEmpty) {
              _extractAllLocations();
              print(
                '✅ Locations extracted: ${_allPickupLocations.length} pickups, ${_allDeliveryLocations.length} deliveries');
            }
          }

          // CRITICAL: Get real GPS location FIRST
          await _getCurrentLocation();
          print(
            '📍 GPS location ready: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');

          // CRITICAL: Always regenerate route after DB restoration to use correct indices
          // This overrides the preview route generated earlier with the correct destination
          if (_navigationStateRestoredFromDB &&
              _currentPhase != NavigationPhase.completed) {
            print(
              '🗺️ Navigation state restored from DB - regenerating route with restored state');
            print('   Navigation started: $_navigationStarted');
            print('   Current phase: $_currentPhase');
            if (_isMultiOrderMode) {
              print(
                '   Multi-order indices: pickup $_currentPickupIndex/${_allPickupLocations.length}, delivery $_currentDeliveryIndex/${_allDeliveryLocations.length}');
            }
            _generateRoute(); // Call without await since it's async but returns void
          }

          _updateCurrentDistanceAndTime();
          _startLocationTracking();
        });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _completionController.dispose();
    _securityCodePanelController.dispose();
    _scanSuccessController.dispose();
    _qrLoadingNotifier.dispose();
    _qrResultNotifier.dispose();
    // Grab the controller reference before clearing state, then dispose safely.
    final ctrl = _qrScannerController;
    _qrScannerController = null;
    ctrl?.dispose();
    _locationTimer?.cancel();
    _securityCodeTimer?.cancel();
    _lastMileCheckTimer?.cancel(); // Cancel Last Mile timer
    _waitingTimer?.cancel(); // Cancel waiting time timer
    _loadingTimer?.cancel(); // Cancel loading time timer
    _deliveryPollTimer?.cancel(); // Cancel delivery polling timer
    _appSettings?.removeListener(_onAppThemeChanged); // Remove theme listener
    super.dispose();
  }

  // Load driver's waiting time settings from database
  Future<void> _loadWaitingTimeSettings() async {
    if (_isLoadingWaitingSettings) return;

    setState(() {
      _isLoadingWaitingSettings = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getInt('driver_id') ?? prefs.getInt('userId');

      if (driverId == null) {
        print('⚠️ No driver ID found, using default waiting settings');
        return;
      }

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delvioo/driver/$driverId/waiting-settings'),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _waitingFreeMinutes = data['waiting_free_minutes'] ?? 15;
            _waitingRatePerHour = (data['waiting_rate_per_hour'] ?? 25.0)
                .toDouble();
          });
          print(
            '✅ Loaded waiting settings: $_waitingFreeMinutes min free, \$$_waitingRatePerHour/hr');
        }
      }
    } catch (e) {
      print('❌ Error loading waiting settings: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingWaitingSettings = false;
        });
      }
    }
  }

  // Start waiting timer when driver arrives at pickup
  void _startWaitingTimer() {
    _waitingStartTime = DateTime.now();
    _waitingElapsedSeconds = 0;
    _freeTimeWarningShown = false;
    _freeTimeExpiredShown = false;
    _totalWaitingCharges = 0.0;

    print(
      '⏱️ Starting waiting timer - Free time: $_waitingFreeMinutes minutes');

    _waitingTimer?.cancel();
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _waitingElapsedSeconds++;
        _calculateWaitingCharges();
      });

      // Live Activity update: every 5 s during waiting (service handles throttle),
      // force=true on each new minute so Dynamic Island / Android notification
      // reflects the countdown immediately.
      final bool forceOnMinute = _waitingElapsedSeconds % 60 == 0;
      _updateLiveActivity(force: forceOnMinute);

      final freeTimeSeconds = _waitingFreeMinutes * 60;
      final warningTimeSeconds = freeTimeSeconds - (5 * 60); // 5 minutes before

      // Show 5-minute warning
      if (!_freeTimeWarningShown &&
          _waitingElapsedSeconds >= warningTimeSeconds &&
          _waitingElapsedSeconds < freeTimeSeconds) {
        _freeTimeWarningShown = true;
        _showWaitingTimeWarning();
      }

      // Show free time expired notification
      if (!_freeTimeExpiredShown && _waitingElapsedSeconds >= freeTimeSeconds) {
        _freeTimeExpiredShown = true;
        _showFreeTimeExpiredNotification();
      }
    });
  }

  // Stop waiting timer and calculate final charges
  void _stopWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingTimer = null;
    _calculateWaitingCharges();
    print(
      '⏱️ Waiting timer stopped - Total time: ${_formatWaitingTime(_waitingElapsedSeconds)}, Charges: \$${_totalWaitingCharges.toStringAsFixed(2)}');
  }

  // Start loading timer (begins after 1st QR scan = check-in)
  void _startLoadingTimer() {
    _loadingStartTime = DateTime.now();
    _loadingElapsedSeconds = 0;
    _loadingTimer?.cancel();
    _loadingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() { _loadingElapsedSeconds++; });

      final bool forceOnMinute = _loadingElapsedSeconds % 60 == 0;
      _updateLiveActivity(force: forceOnMinute);
    });
    print('📦 Loading timer started');
  }

  // Stop loading timer
  void _stopLoadingTimer() {
    _loadingTimer?.cancel();
    _loadingTimer = null;
    print('📦 Loading timer stopped - Total: ${_formatWaitingTime(_loadingElapsedSeconds)}');
  }

  // ─── Delivery Polling ────────────────────────────────────────────────────────
  // Generate the QR URL that the buyer opens in their phone camera
  String _generateDeliveryQRData() {
    final orderId = (_currentOrder != null)
        ? (_currentOrder!['order_id'] ?? _currentOrder!['id'] ?? 0)
        : (widget.order['order_id'] ?? widget.order['id'] ?? 0);
    return '${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/buyer-scan/$_securityCode';
  }

  // Start polling for buyer QR scans while delivery bottom sheet is open
  void _startDeliveryPolling() {
    _deliveryPollTimer?.cancel();
    _buyerScannedCheckIn = false;
    _buyerScannedCheckOut = false;
    _deliveryPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) { _stopDeliveryPolling(); return; }
      await _checkDeliveryBuyerScanStatus();
    });
    print('🔄 Delivery polling started');
  }

  // Stop polling
  void _stopDeliveryPolling() {
    _deliveryPollTimer?.cancel();
    _deliveryPollTimer = null;
    print('🔄 Delivery polling stopped');
  }

  // Poll backend for buyer scan status
  Future<void> _checkDeliveryBuyerScanStatus() async {
    try {
      final orderId = (_currentOrder != null)
          ? (_currentOrder!['order_id'] ?? _currentOrder!['id'] ?? 0)
          : (widget.order['order_id'] ?? widget.order['id'] ?? 0);

      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/delivery-scan-status'),
              headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return;
      final data = json.decode(response.body);
      if (data['success'] != true) return;

      final checkInSet  = data['buyer_check_in_at']  != null;
      final checkOutSet = data['buyer_check_out_at'] != null;

      // ── Check-In detected ──
      if (checkInSet && !_buyerScannedCheckIn) {
        _buyerScannedCheckIn = true;
        print('✅ Buyer scanned check-IN — stop waiting, start loading');
        if (mounted) {
          _stopWaitingTimer();
          _saveWaitingTimeToOrder(phase: 'buyer');
          _startLoadingTimer();
          setState(() { _scanPhase = 'loading'; });
          HapticFeedback.heavyImpact();
        }
      }

      // ── Check-Out detected ──
      if (checkOutSet && !_buyerScannedCheckOut) {
        _buyerScannedCheckOut = true;
        print('✅ Buyer scanned check-OUT — stop loading, complete delivery');
        _stopDeliveryPolling();
        if (mounted) {
          _stopLoadingTimer();
          _saveLoadingTimeToOrder(phase: 'buyer');
          HapticFeedback.heavyImpact();
          // Keep delivery sheet open until backend confirmation succeeds.
          _completeCurrentDeliveryAsync();
        }
      }
    } catch (e) {
      // Silently ignore poll errors (network issues etc.)
    }
  }

  // Calculate waiting charges based on elapsed time
  void _calculateWaitingCharges() {
    final freeTimeSeconds = _waitingFreeMinutes * 60;

    if (_waitingElapsedSeconds <= freeTimeSeconds) {
      _totalWaitingCharges = 0.0;
    } else {
      final chargeableSeconds = _waitingElapsedSeconds - freeTimeSeconds;
      final chargeableHours = chargeableSeconds / 3600.0;
      _totalWaitingCharges = chargeableHours * _waitingRatePerHour;
    }
  }

  // Format waiting time for display
  String _formatWaitingTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String _formatClock(DateTime? dt) {
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildScanPhaseStatusCard(bool isLight, {required bool isDelivery}) {
    final isCheckInDone = _scanPhase == 'loading';
    final stepTitle = isCheckInDone
      ? 'Next step: Scan check-out'
      : 'Next step: Scan check-in';
    final stepSubtitle = isCheckInDone
      ? 'Timer is running.'
      : 'The timer starts after this.';

    final checkInTime = isDelivery ? _buyerCheckInAt : _sellerCheckInAt;
    final checkOutTime = isDelivery ? _buyerCheckOutAt : _sellerCheckOutAt;

    return TradeRepublicCard(
      padding: EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(14),
      backgroundColor: isCheckInDone
          ? Colors.green.withOpacity(0.10)
          : Colors.orange.withOpacity(0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCheckInDone
                    ? CupertinoIcons.checkmark_seal_fill
                    : CupertinoIcons.clock_fill,
                size: 18,
                color: isCheckInDone ? Colors.green : Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  stepTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white))),
            ]),
          SizedBox(height: 6),
          Text(
            stepSubtitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.72))),
          SizedBox(height: 10),
          Divider(
            height: 1,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.12)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Check-in ${_formatClock(checkInTime)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black87 : Colors.white70))),
              Expanded(
                child: Text(
                  'Check-out ${_formatClock(checkOutTime)}',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black87 : Colors.white70))),
            ]),
        ]));
  }

  // Get remaining free time
  String _getRemainingFreeTime() {
    final freeTimeSeconds = _waitingFreeMinutes * 60;
    final remainingSeconds = freeTimeSeconds - _waitingElapsedSeconds;

    if (remainingSeconds <= 0) {
      return AppLocalizations.of(context)?.chargingStarted ?? AppLocalizations.of(context)!.tr('Charging started');
    }

    return _formatWaitingTime(remainingSeconds);
  }

  // Check if free time has expired
  bool _isFreeTimeExpired() {
    return _waitingElapsedSeconds >= (_waitingFreeMinutes * 60);
  }

  // Show 5-minute warning notification
  void _showWaitingTimeWarning() {
    HapticFeedback.heavyImpact();

    if (!mounted) return;

    TopNotification.warning(
      context,
      AppLocalizations.of(context)?.freeWaitingTimeExpiresIn5Min ?? 'Free waiting time expires in 5 minutes. After that, ${_waitingRatePerHour.toStringAsFixed(0)}{currencySymbol}/hr will be charged.',
      title: AppLocalizations.of(context)?.fiveMinutesRemaining ?? AppLocalizations.of(context)!.tr('5 Minutes Remaining'));

    print('⚠️ 5-minute warning shown');
  }

  // Show free time expired notification
  void _showFreeTimeExpiredNotification() {
    HapticFeedback.heavyImpact();

    // Double haptic for urgency
    Future.delayed(const Duration(milliseconds: 200), () {
      HapticFeedback.heavyImpact();
    });

    if (!mounted) return;

    TopNotification.error(
      context,
      AppLocalizations.of(context)?.chargingPerHourStartingNow ?? 'Charging ${_waitingRatePerHour.toStringAsFixed(0)}{currencySymbol}/hr starting now.',
      title: AppLocalizations.of(context)?.freeWaitingTimeExpired ?? AppLocalizations.of(context)!.tr('Free Waiting Time Expired'));

    print('🔴 Free time expired - charging started');
  }

  // Save ONLY the waiting start time to orders when driver clicks Arrived
  // This persists immediately so the timer survives app restart
  Future<void> _saveWaitingStartToOrder({required String phase}) async {
    if (_waitingStartTime == null) return;
    try {
      final orderId = (_currentOrder != null)
          ? (_currentOrder!['order_id'] ?? _currentOrder!['id'])
          : (widget.order['order_id'] ?? widget.order['id']);

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/waiting-time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phase': phase,
          'waiting_start_time': _waitingStartTime!.toIso8601String(),
          'waiting_seconds': _waitingElapsedSeconds,
          'in_progress': true, // Signal that waiting is ongoing, no end time yet
        }));
      if (response.statusCode == 200) {
        print('✅ [$phase] Waiting START saved to orders (timer still running)');
      } else {
        print('⚠️ Failed to save waiting start: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error saving waiting start: $e');
    }
  }

  // Save waiting time to order — phase: 'seller' (pickup) or 'buyer' (delivery)
  Future<void> _saveWaitingTimeToOrder({required String phase}) async {
    if (_waitingStartTime == null) return;

    try {
      final orderId = (_currentOrder != null)
          ? (_currentOrder!['order_id'] ?? _currentOrder!['id'])
          : (widget.order['order_id'] ?? widget.order['id']);

      final response = await http.put(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/waiting-time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phase': phase,
          'waiting_start_time': _waitingStartTime!.toIso8601String(),
          'waiting_end_time': DateTime.now().toIso8601String(),
          'waiting_seconds': _waitingElapsedSeconds,
          // settings come from delvioo_users on the backend — no need to send them
        }));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final backendCharges =
            (responseData['waiting_charges'] as num?)?.toDouble();
        if (backendCharges != null && mounted) {
          setState(() {
            _totalWaitingCharges = backendCharges;
          });
        }
        print(
          '✅ [$phase] Waiting time saved: ${_formatWaitingTime(_waitingElapsedSeconds)}, charges: ${_totalWaitingCharges.toStringAsFixed(2)}{currencySymbol}');
      } else {
        print('⚠️ Failed to save waiting time: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error saving waiting time: $e');
    }
  }

  // Save loading/unloading time to orders table (phase: 'seller' or 'buyer')
  Future<void> _saveLoadingTimeToOrder({required String phase}) async {
    if (_loadingStartTime == null) return;
    try {
      final orderId = (_currentOrder != null)
          ? (_currentOrder!['order_id'] ?? _currentOrder!['id'])
          : (widget.order['order_id'] ?? widget.order['id']);
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/loading-time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phase': phase,
          'loading_start_time': _loadingStartTime!.toIso8601String(),
          'loading_end_time': DateTime.now().toIso8601String(),
          'loading_seconds': _loadingElapsedSeconds,
        }));
      if (response.statusCode == 200) {
        print('✅ [$phase] Loading time saved: ${_formatWaitingTime(_loadingElapsedSeconds)}');
      } else {
        print('⚠️ Failed to save loading time: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error saving loading time: $e');
    }
  }

  // Save loading timer PROGRESS to orders table (timer still running, no end time)
  // Used when modal is closed but loading isn't done yet
  Future<void> _saveLoadingProgressToOrder({required String phase}) async {
    if (_loadingStartTime == null) return;
    try {
      final orderId = (_currentOrder != null)
          ? (_currentOrder!['order_id'] ?? _currentOrder!['id'])
          : (widget.order['order_id'] ?? widget.order['id']);
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/loading-time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phase': phase,
          'loading_start_time': _loadingStartTime!.toIso8601String(),
          'loading_seconds': _loadingElapsedSeconds,
          // NO loading_end_time — timer still running
        }));
      if (response.statusCode == 200) {
        print('✅ [$phase] Loading progress saved (timer still running)');
      } else {
        print('⚠️ Failed to save loading progress: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error saving loading progress: $e');
    }
  }

  /// Saves check-in / check-out timestamps to the existing columns in the orders table.
  /// Only the provided (non-null) fields are sent.
  Future<void> _saveCheckinCheckout({
    DateTime? sellerCheckIn,
    DateTime? sellerCheckOut,
    DateTime? buyerCheckIn,
    DateTime? buyerCheckOut,
  }) async {
    try {
      final orderId = (_currentOrder != null)
          ? (_currentOrder!['order_id'] ?? _currentOrder!['id'])
          : (widget.order['order_id'] ?? widget.order['id']);

      final Map<String, dynamic> body = {};
      if (sellerCheckIn != null)  body['seller_check_in_at']  = sellerCheckIn.toIso8601String();
      if (sellerCheckOut != null) body['seller_check_out_at'] = sellerCheckOut.toIso8601String();
      if (buyerCheckIn != null)   body['buyer_check_in_at']   = buyerCheckIn.toIso8601String();
      if (buyerCheckOut != null)  body['buyer_check_out_at']  = buyerCheckOut.toIso8601String();

      if (body.isEmpty) return;

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/checkin-checkout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body));

      if (response.statusCode == 200) {
        print('✅ Check-in/out saved for order $orderId: $body');
      } else {
        print('⚠️ Failed to save check-in/out: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('❌ Error saving check-in/out: $e');
    }
  }



  Future<void> _clearAllMultiOrderSessions() async {
    try {
      // Clear SharedPreferences immediately and synchronously
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('multi_order_session_id');
      await prefs.remove('navigation_state');
      await prefs.remove('quick_navigation_state');

      // Reset all navigation state immediately
      _resetNavigationState();

      // Try to clear database sessions (non-blocking - continue even if it fails)
      _clearDatabaseSessionsAsync();
    } catch (e) {
      print('❌ Error clearing multi-order sessions: $e');
    }
  }

  // Separate async method for database cleanup that doesn't block the main flow
  void _clearDatabaseSessionsAsync() async {
    try {
      final driverId = await _getDriverId();

      // Try multiple API endpoints to ensure cleanup
      final endpoints = [
        '${ApiConfig.baseUrl}/api/navigation/clear-all-sessions/$driverId',
        '${ApiConfig.baseUrl}/api/navigation/clear-all/$driverId',
        '${ApiConfig.baseUrl}/api/delvioo/clear-navigation/$driverId',
      ];

      for (String endpoint in endpoints) {
        try {
          final response = await http
              .delete(
                Uri.parse(endpoint),
                headers: {'Content-Type': 'application/json'})
              .timeout(Duration(seconds: 3));

          if (response.statusCode == 200) {
            return; // Success, no need to try other endpoints
          }
        } catch (e) {
          print('⚠️ Failed to clear via $endpoint: $e');
        }
      }

      print(
        '⚠️ All database cleanup attempts failed, but local data is cleared');
    } catch (e) {
      print('⚠️ Database cleanup error: $e');
    }
  }

  Future<void> _checkAndClearSessionsIfNeeded(dynamic orderId) async {
    try {
      // Check if there's an existing active navigation session in LOCAL storage
      final prefs = await SharedPreferences.getInstance();
      final existingState = prefs.getString('navigation_state');
      final hasActiveLocalSession =
          existingState != null &&
          existingState.isNotEmpty &&
          existingState != '{}';

      // If there's an active local session, DON'T clear - allow resumption
      if (hasActiveLocalSession) {
        print(
          '🔄 Active local navigation session found - preserving state for resumption');
        return;
      }

      // No local session — but this might be a DIFFERENT DEVICE (logout + login elsewhere).
      // Before wiping the DB, check if the cloud DB has an active session for this order.
      // If it does, we MUST preserve it so _loadNavigationState() can restore the full state.
      try {
        final driverId = await _getDriverId();
        final response = await http
            .get(
              Uri.parse('${ApiConfig.baseUrl}/api/navigation/active/$driverId'),
              headers: {'Content-Type': 'application/json'})
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true &&
              responseData['navigation'] != null) {
            final navData = responseData['navigation'];
            final navOrderId = navData['order_id'];
            final currentOrderId = orderId.toString();

            // Check if DB session belongs to this order (direct or via all_orders)
            bool dbSessionMatchesOrder =
                navOrderId.toString() == currentOrderId;
            if (!dbSessionMatchesOrder && navData['all_orders'] != null) {
              final allOrders = navData['all_orders'] as List? ?? [];
              dbSessionMatchesOrder = allOrders.any(
                (o) =>
                    (o['order_id'] ?? o['id'])?.toString() == currentOrderId);
            }

            if (dbSessionMatchesOrder) {
              print(
                '🔄 Active DB session found for order $currentOrderId on different device — preserving for cross-device resumption');
              // Don't clear anything; _loadNavigationState() will restore from DB
              return;
            }
          }
        }
      } catch (e) {
        // Network error or timeout — be safe: don't wipe the DB session
        print(
          '⚠️ Could not verify DB session before clear (network issue) — skipping clear to be safe: $e');
        return;
      }

      // Confirmed: no active session anywhere — proceed with clearing for fresh start
      print('🆕 No active session found locally or in DB — clearing old data for fresh start');

      if (orderId.toString().startsWith('multi_')) {
        print(
          '🆕 Multi-order detected - clearing ALL old multi-order sessions');
        _clearAllMultiOrderSessions();

        // Re-initialize _allOrders after clearing (for multi-orders)
        if (widget.order.containsKey('batch_orders') &&
            widget.order['batch_orders'] != null) {
          _allOrders = List<Map<String, dynamic>>.from(
            widget.order['batch_orders']);
          print(
            '🔄 Re-initialized _allOrders with ${_allOrders.length} batch orders AFTER clearing old sessions');
        }
      }

      // Check if this is a single new order (not a multi-order continuation)
      final isNewSingleOrder =
          !widget.order.containsKey('batch_orders') &&
          !widget.order.containsKey('additional_orders') &&
          widget.order['status']?.toString().toLowerCase() != 'picked_up';

      if (isNewSingleOrder) {
        print(
          '🆕 New single order detected - clearing all old multi-order sessions');
        _clearAllMultiOrderSessions();
      }
    } catch (e) {
      print('⚠️ Error checking sessions: $e');
    }
  }

  Future<void> _completeResetNavigation() async {
    try {
      // Clear all sessions
      await _clearAllMultiOrderSessions();

      // Reset UI state
      setState(() {
        _currentPhase = NavigationPhase.toPickup;
        _navigationStarted = false;
        _routePoints.clear();
        _routeInstructions.clear();
        _routeColors.clear();
        _currentInstructionIndex = 0;
      });
    } catch (e) {
      print('❌ Error during complete reset: $e');
    }
  }

  void _resetNavigationState() {
    // Store batch orders before clearing if they exist
    final hasBatchOrders =
        widget.order.containsKey('batch_orders') &&
        widget.order['batch_orders'] != null;
    final batchOrders = hasBatchOrders
        ? List<Map<String, dynamic>>.from(widget.order['batch_orders'])
        : null;

    _allOrders.clear();
    _allPickupLocations.clear();
    _allDeliveryLocations.clear();
    // DON'T reset pickup/delivery indices here - they should be restored from database
    // _currentPickupIndex = 0;
    // _currentDeliveryIndex = 0;
    _isMultiOrderMode = false;
    _completedDeliveries.clear();
    _routePoints.clear();
    _routeInstructions.clear();
    _routeColors.clear();

    // Reset map rotation to north (0 degrees)
    _currentBearing = 0.0;
    // Only reset rotation if map is already rendered (avoid controller error)
    if (mounted) {
      try {
        // Check if map controller is ready before using it
        if (_mapController.camera.zoom > 0) {
          _mapController.rotate(0.0);
        }
      } catch (e) {
        // Map not rendered yet, rotation will be set on first render
        print(
          'ℹ️ Map controller not ready yet, rotation will be reset on render');
      }
    }

    // CRITICAL: Reset total route calculation flags for new navigation session
    _isFetchingTotalRoute = false;
    _totalRouteCalculated = false;

    // Restore batch orders immediately if they existed
    if (batchOrders != null && batchOrders.isNotEmpty) {
      _allOrders = batchOrders;
    }
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _pulseController.repeat(reverse: true);

    // Modern Completion Animations
    _completionController = AnimationController(
      duration: const Duration(
        milliseconds: 2000), // 2 seconds for full completion animation
      vsync: this);

    // Scale animation for the completion container (bouncy entrance)
    _completionScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _completionController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)));

    // Fade animation for smooth appearance
    _completionFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _completionController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut)));

    // Checkmark drawing animation
    _checkmarkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _completionController,
        curve: const Interval(0.4, 0.8, curve: Curves.easeInOut)));

    // Confetti/celebration animation
    _confettiAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _completionController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut)));

    // Security Code Panel Animation (smooth slide up from bottom)
    _securityCodePanelController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this);

    _securityCodeScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _securityCodePanelController,
        curve: Curves.easeOutCubic));

    _securityCodeFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _securityCodePanelController,
        curve: Curves.easeOut));

    // QR Scan Success Animation (beautiful checkmark and scale)
    _scanSuccessController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this);

    _scanSuccessScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanSuccessController, curve: Curves.elasticOut));

    _scanSuccessFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanSuccessController, curve: Curves.easeOut));
  }

  String _formatDuration(int totalMinutes) {
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    } else {
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (minutes == 0) {
        return '$hours h';
      } else {
        return '$hours h $minutes min';
      }
    }
  }

  void _initializeMultiOrderModeSync() {
    // DON'T initialize indices to 0 here - they will be loaded from database if navigation exists
    // OR will be set to 0 later in _initializeMultiOrderMode() if it's a new navigation
    // _currentPickupIndex = 0; // REMOVED - will be restored from DB or set later
    // _currentDeliveryIndex = 0; // REMOVED - will be restored from DB or set later

    // Check if order data contains multiple orders or is part of a batch
    if (widget.order.containsKey('batch_orders') &&
        widget.order['batch_orders'] != null) {
      // Multiple orders in batch format
      _allOrders = List<Map<String, dynamic>>.from(
        widget.order['batch_orders']);
      _isMultiOrderMode = true;
      _extractAllLocations();
      _currentPhase = NavigationPhase.multiOrderPickups;
    } else if (widget.order.containsKey('additional_orders') &&
        widget.order['additional_orders'] != null) {
      // Main order + additional orders
      _allOrders = [widget.order];
      _allOrders.addAll(
        List<Map<String, dynamic>>.from(widget.order['additional_orders']));
      _isMultiOrderMode = true;
      _extractAllLocations();
      _currentPhase = NavigationPhase.multiOrderPickups;
    } else {
      // Single order mode - check if already picked up
      _allOrders = [widget.order];
      _isMultiOrderMode = false;

      // Determine initial phase based on order status
      final orderStatus =
          widget.order['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');
      if (orderStatus == 'picked_up') {
        // Product already picked up, start with delivery phase
        _currentPhase = NavigationPhase.toDelivery;
        debugPrint(
          '📦 Order already picked up, starting navigation at delivery phase');
      } else {
        // Normal flow - start with pickup
        _currentPhase = NavigationPhase.toPickup;
      }
    }

    // Generate or retrieve multi-order session ID if in multi-order mode (async initialization)
    if (_isMultiOrderMode) {
      _getOrCreateMultiOrderSessionId().then((sessionId) {
        _multiOrderSessionId = sessionId;
      });
    }

    // Save initial state for multi-order persistence
    if (_isMultiOrderMode && _allOrders.length > 1) {
      _saveNavigationState();
    }
  }

  Future<String> _getOrCreateMultiOrderSessionId() async {
    // Try to find existing session in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final existingSessionId = prefs.getString('multi_order_session_id');

    if (existingSessionId != null && existingSessionId.isNotEmpty) {
      return existingSessionId;
    }

    // Generate new session ID based on current navigation context
    final driverId = await _getDriverId();
    String sessionId;

    // Always create timestamp-based session ID for consistency
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    sessionId = 'multi_${timestamp}_$driverId';

    // Save to SharedPreferences for persistence across modal opens/closes
    await prefs.setString('multi_order_session_id', sessionId);

    return sessionId;
  }

  Future<String> _getSessionId() async {
    // For multi-order mode, use persistent session ID
    if (_isMultiOrderMode) {
      if (_multiOrderSessionId != null) {
        return _multiOrderSessionId!;
      }
      // If session ID is not yet initialized, create it
      _multiOrderSessionId = await _getOrCreateMultiOrderSessionId();
      return _multiOrderSessionId!;
    }

    // For single order mode, use individual order ID
    final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;
    return orderId.toString();
  }

  Future<void> _initializeMultiOrderMode() async {
    // Check if this is a new single order - if so, don't look for existing sessions
    final isNewSingleOrder =
        !widget.order.containsKey('batch_orders') &&
        !widget.order.containsKey('additional_orders') &&
        widget.order['status']?.toString().toLowerCase() != 'picked_up';

    // Check if this order is already part of a multi-order batch
    final isMultiOrderBatch =
        widget.order.containsKey('batch_orders') ||
        widget.order.containsKey('additional_orders') ||
        widget.order['order_id']?.toString().startsWith('multi_') == true;

    if (!isNewSingleOrder) {
      // Only check for existing navigation if this is NOT a new single order
      await _checkForExistingNavigation();

      // Early check: If navigation state was restored from DB, skip ALL multi-order setup
      if (_navigationStateRestoredFromDB) {
        return;
      }

      // CRITICAL FIX: Only combine active orders if:
      // 1. This is ALREADY a multi-order batch (has batch_orders or multi_ ID)
      // 2. OR navigation state was restored and we're continuing multi-order navigation
      if (isMultiOrderBatch) {
        print(
          '🔄 Multi-order batch detected - checking for additional active orders to combine');
        await _checkAndCombineActiveOrders();
      } else {
        print(
          '📦 Single order in picked_up status - NOT auto-combining with other active orders');
      }
    } else {
      print(
        '🆕 New single order (ready_for_pickup) - skipping existing navigation checks and auto-combining');
    }

    // If we didn't already set up multi-order mode synchronously, check again
    if (!_isMultiOrderMode) {
      // Check if order data contains multiple orders or is part of a batch
      if (widget.order.containsKey('batch_orders') &&
          widget.order['batch_orders'] != null) {
        // Multiple orders in batch format
        _allOrders = List<Map<String, dynamic>>.from(
          widget.order['batch_orders']);
        _isMultiOrderMode = true;
      } else if (widget.order.containsKey('additional_orders') &&
          widget.order['additional_orders'] != null) {
        // Main order + additional orders
        _allOrders = [widget.order];
        _allOrders.addAll(
          List<Map<String, dynamic>>.from(widget.order['additional_orders']));
        _isMultiOrderMode = true;
      } else {
        // Single order mode (default) - but we may have found other active orders above
        if (!_isMultiOrderMode) {
          _allOrders = [widget.order];
          _isMultiOrderMode = false;
          _currentPhase = NavigationPhase.toPickup;
        }
      }

      // Extract all pickup and delivery locations
      _extractAllLocations();
    }

    // CRITICAL: Initialize indices to 0 ONLY if navigation state was NOT restored from DB
    if (!_navigationStateRestoredFromDB && _isMultiOrderMode) {
      _currentPickupIndex = 0;
      _currentDeliveryIndex = 0;
    } else if (_navigationStateRestoredFromDB) {
      print(
        '✅ Keeping restored multi-order indices: pickup=$_currentPickupIndex, delivery=$_currentDeliveryIndex');
    }

    // Determine optimal phase based on current state - but only if not restored from DB
    if (_isMultiOrderMode &&
        _allOrders.length > 1 &&
        !_navigationStateRestoredFromDB) {
      _determineOptimalNextPhase();
    } else if (_navigationStateRestoredFromDB) {}
  }

  Future<void> _checkForExistingNavigation() async {
    try {
      final driverId = await _getDriverId();
      // Use the SAME session ID that _getOrCreateMultiOrderSessionId() would create/return
      final currentSessionId = await _getOrCreateMultiOrderSessionId();

      if (currentSessionId.isNotEmpty) {
        // Try to load navigation state for this specific multi-order session
        try {
          final String url =
              '${ApiConfig.baseUrl}/api/navigation/active/$driverId?session_id=$currentSessionId';

          final response = await http.get(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'});

          if (response.statusCode == 200) {
            final data = json.decode(response.body);

            if (data['hasActiveNavigation'] == true &&
                data['navigation'] != null) {
              final existingNavigation = data['navigation'];
              final existingOrderId = existingNavigation['order_id'];

              // Check if this is a multi-order session
              if (existingOrderId.toString().startsWith('multi_')) {
                // Always resume the multi-order session, don't create a new one
                _multiOrderSessionId = currentSessionId;
                _isMultiOrderMode = true;

                await _loadExistingNavigationState(existingNavigation);
                return; // Exit early - we're resuming existing session
              }
            }
          }
        } catch (e) {}
      }

      // Regular single-order navigation check (no specific session ID)
      final String url =
          '${ApiConfig.baseUrl}/api/navigation/active/$driverId';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['hasActiveNavigation'] == true && data['navigation'] != null) {
          final existingNavigation = data['navigation'];

          // Check if this is a different order than the current one
          final currentOrderId = widget.order['id'] ?? widget.order['order_id'];
          final existingOrderId = existingNavigation['order_id'];

          if (currentOrderId != existingOrderId) {
            // We have a different active order - merge them!
            await _mergeWithExistingNavigation(existingNavigation);
          } else {
            // Same order - load existing navigation state
            await _loadExistingNavigationState(existingNavigation);
          }
        }
      }
    } catch (e) {}
  }

  Future<void> _checkAndCombineActiveOrders() async {
    try {
      final driverId = await _getDriverId();
      final String url =
          '${ApiConfig.baseUrl}/api/delvioo/driver/$driverId/active-orders';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['active_orders'] != null) {
          List activeOrders = List.from(data['active_orders']);

          // IMPORTANT: Limit to max 5 orders to prevent UI overload and pickup display issues
          if (activeOrders.length > 5) {
            activeOrders = activeOrders.take(5).toList();
          }

          if (activeOrders.isNotEmpty) {
            // Check if current order is already in the active orders
            final currentOrderId =
                widget.order['id'] ?? widget.order['order_id'];
            final bool isAlreadyActive = activeOrders.any(
              (order) => order['id'].toString() == currentOrderId.toString());

            print(
              '📦 [DEBUG] Current order ID: $currentOrderId, Already active: $isAlreadyActive');

            if (!isAlreadyActive && activeOrders.isNotEmpty) {
              print(
                '✅ [DEBUG] Combining current order with ${activeOrders.length} active orders');
              // Combine current order with existing active orders
              await _combineWithActiveOrders(activeOrders);
            } else if (activeOrders.length > 1) {
              print(
                '✅ [DEBUG] Setting up multi-order mode for ${activeOrders.length} orders');
              // Even if current order is already active, set up multi-order mode if we have multiple orders
              await _combineWithActiveOrders(activeOrders);
            }
          }
        }
      }
    } catch (e) {
      print('❌ [DEBUG] Error in _checkAndCombineActiveOrders: $e');
    }
  }

  Future<void> _combineWithActiveOrders(List activeOrders) async {
    try {
      print(
        '🔄 [DEBUG] Combining ${activeOrders.length} active orders into multi-order mode');

      // Convert active orders to proper format with coordinates
      List<Map<String, dynamic>> formattedOrders = [];

      for (var activeOrder in activeOrders) {
        print(
          '📦 [DEBUG] Processing order ${activeOrder['order_id']} - ${activeOrder['pickup_address']}');
        formattedOrders.add({
          'id': activeOrder['id'],
          'order_id': activeOrder['order_id'],
          'pickup_address': activeOrder['pickup_address'],
          'delivery_address': activeOrder['delivery_address'],
          'pickup_lat': activeOrder['pickup_lat'],
          'pickup_lng': activeOrder['pickup_lng'],
          'delivery_lat': activeOrder['delivery_lat'],
          'delivery_lng': activeOrder['delivery_lng'],
          'status': activeOrder['status'],
          'current_phase': activeOrder['current_phase'],
          'pickup_completed': activeOrder['pickup_completed'],
          'delivery_completed': activeOrder['delivery_completed'],
        });
      }

      // Add current order to the list
      formattedOrders.add(widget.order);

      // Set up multi-order mode
      _allOrders = formattedOrders;
      _isMultiOrderMode = true;

      print(
        '✅ [DEBUG] Multi-order mode activated with ${_allOrders.length} orders');

      // Only set initial phase if not restored from DB
      if (!_navigationStateRestoredFromDB) {
        _currentPhase = NavigationPhase.multiOrderPickups;
      } else {
        print('📖 [DEBUG] Keeping restored phase: $_currentPhase');
      }

      // Extract all locations after setting up orders
      _extractAllLocations();

      print(
        '📍 [DEBUG] Extracted ${_allPickupLocations.length} pickup locations and ${_allDeliveryLocations.length} delivery locations');

      // Force UI rebuild
      if (mounted) {
        setState(() {});
      }

      // Show notification to user
      TopNotification.success(
        context,
        'Multi-Order Navigation: ${formattedOrders.length} orders combined');
    } catch (e) {}
  }

  Future<void> _mergeWithExistingNavigation(
    Map<String, dynamic> existingNav) async {
    try {
      // Get the existing order data
      final existingOrderId = existingNav['order_id'];
      final existingOrder = await _getOrderData(existingOrderId);

      if (existingOrder != null) {
        // Create multi-order setup
        _allOrders = [existingOrder, widget.order];
        _isMultiOrderMode = true;

        // Determine current phase based on existing navigation state
        final currentPhase = existingNav['current_phase'] ?? AppLocalizations.of(context)!.tr('toPickup');
        if (currentPhase == 'toPickup' || currentPhase == 'multiOrderPickups') {
          _currentPhase = NavigationPhase.multiOrderPickups;
          // Only reset to 0 if no state was restored from DB
          if (!_navigationStateRestoredFromDB) {
            _currentPickupIndex = 0; // Start from first pickup
          } else {}
        } else if (currentPhase == 'toDelivery' ||
            currentPhase == 'multiOrderDeliveries') {
          _currentPhase = NavigationPhase.multiOrderDeliveries;
          // Only reset to 0 if no state was restored from DB
          if (!_navigationStateRestoredFromDB) {
            _currentDeliveryIndex = 0; // Start from first delivery
          } else {}
        }

        // Show success notification to user
        if (mounted) {
          TopNotification.success(
            context,
            '🚚 Orders combined! ${_allOrders.length} orders in route');
        }
      }
    } catch (e) {}
  }

  Future<void> _loadExistingNavigationState(
    Map<String, dynamic> navigation) async {
    try {
      // Extract navigation state
      final currentPhase = navigation['current_phase'] ?? AppLocalizations.of(context)!.tr('toPickup');
      final navigationStarted = navigation['navigation_started'] ?? false;
      final driverStartedDriving =
          navigation['driver_started_driving'] ?? false;

      print(
        '   Raw navigation_started from DB: ${navigation['navigation_started']}');
      print(
        '   Raw driver_started_driving from DB: ${navigation['driver_started_driving']}');
      print('   Parsed navigationStarted: $navigationStarted');
      print('   Parsed driverStartedDriving: $driverStartedDriving');
      print(
        '   Will set _navigationStarted to: ${navigationStarted || driverStartedDriving}');

      setState(() {
        _navigationStarted = navigationStarted || driverStartedDriving;

        // Set phase based on existing navigation
        if (currentPhase.contains('toPickup') ||
            currentPhase.contains('multiOrderPickups')) {
          _currentPhase = NavigationPhase.multiOrderPickups;
          // Reset to ensure we start from the beginning of pickups if needed
          if (_currentPickupIndex >= _allPickupLocations.length) {
            _currentPickupIndex = 0;
          }
        } else if (currentPhase.contains('toDelivery') ||
            currentPhase.contains('multiOrderDeliveries')) {
          _currentPhase = NavigationPhase.multiOrderDeliveries;
          // If we're in delivery phase, all pickups should be completed
          _currentPickupIndex = _allPickupLocations.length;
          // Reset delivery index if it's out of bounds
          if (_currentDeliveryIndex >= _allDeliveryLocations.length) {
            _currentDeliveryIndex = 0;
          }
        } else if (currentPhase.contains('completed')) {
          _currentPhase = NavigationPhase.completed;
          _currentPickupIndex = _allPickupLocations.length;
          _currentDeliveryIndex = _allDeliveryLocations.length;
          _triggerCompletionAnimation();
        } else {
          _currentPhase = NavigationPhase.toPickup;
          _currentPickupIndex = 0;
          _currentDeliveryIndex = 0;
        }

        // Load route points if available
        if (navigation['route_points'] != null) {
          final routeData = navigation['route_points'] as List;
          _routePoints = routeData
              .map(
                (point) =>
                    LatLng(point['lat'].toDouble(), point['lng'].toDouble()))
              .toList();
        }

        // Load other navigation data
        _totalDistance = navigation['total_distance'] ?? AppLocalizations.of(context)!.tr('Loading...');
        _estimatedArrival = navigation['estimated_arrival'] ?? AppLocalizations.of(context)!.tr('Loading...');
        _securityCode =
            navigation['security_code'] ?? _extractSecurityCodeFromOrder();
      });
    } catch (e) {}
  }

  Future<Map<String, dynamic>?> _getOrderData(dynamic orderId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders/$orderId'),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['order'] != null) {
          return data['order'];
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  void _determineOptimalNextPhase() {
    // If navigation state was restored from DB, don't override the phase
    if (_navigationStateRestoredFromDB) {
      return;
    }

    // Check order statuses to determine which orders are already picked up
    int alreadyPickedUpCount = 0;
    for (var order in _allOrders) {
      final status = order['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');
      if (status == 'picked_up' || status == 'delivered') {
        alreadyPickedUpCount++;
      }
    }

    // Adjust pickup index based on already picked up orders
    if (alreadyPickedUpCount > 0) {
      _currentPickupIndex = alreadyPickedUpCount;
      debugPrint(
        '📦 Found $alreadyPickedUpCount already picked up orders, adjusting pickup index to $_currentPickupIndex');
    }

    // Simple sequential logic: Complete all pickups first, then all deliveries

    // Check if there are remaining pickups
    if (_currentPickupIndex < _allPickupLocations.length) {
      _currentPhase = NavigationPhase.multiOrderPickups;
      return;
    }

    // All pickups done, check deliveries
    if (_currentDeliveryIndex < _allDeliveryLocations.length) {
      _currentPhase = NavigationPhase.multiOrderDeliveries;
      return;
    }

    // All done
    _currentPhase = NavigationPhase.completed;
    _triggerCompletionAnimation();
  }

  void _extractAllLocations() {
    _allPickupLocations.clear();
    _allDeliveryLocations.clear();

    // Prevent duplicate orders by tracking IDs we've already processed
    Set<dynamic> processedOrderIds = {};

    for (var order in _allOrders) {
      final orderId = order['order_id'] ?? order['id'];

      // Skip multi-order container IDs (they are not actual deliverable orders)
      if (orderId.toString().startsWith('multi_')) {
        continue;
      }

      // Skip if we've already processed this order ID
      if (processedOrderIds.contains(orderId)) {
        continue;
      }
      processedOrderIds.add(orderId);

      // Extract pickup location for this order with coordinate validation
      double pickupLat = 0.0; // Will be set from order data
      double pickupLng = 0.0;

      if (order.containsKey('pickup_lat') && order['pickup_lat'] != null) {
        pickupLat =
            double.tryParse(order['pickup_lat'].toString()) ?? pickupLat;
      }
      if (order.containsKey('pickup_lng') && order['pickup_lng'] != null) {
        pickupLng =
            double.tryParse(order['pickup_lng'].toString()) ?? pickupLng;
      }

      // Validate coordinates
      if (pickupLat == 0.0 || pickupLng == 0.0) {
        debugPrint(
          '⚠️ Multi-order: Order $orderId has invalid pickup coordinates ($pickupLat, $pickupLng)');
      }

      debugPrint(
        '📍 Multi-order: Order $orderId pickup coordinates: $pickupLat, $pickupLng');
      _allPickupLocations.add(LatLng(pickupLat, pickupLng));

      // Extract delivery location for this order
      double deliveryLat = 0.0; // Will be set from order data
      double deliveryLng = 0.0;

      // Try multiple possible delivery coordinate field names
      if (order.containsKey('delivery_lat') && order['delivery_lat'] != null) {
        deliveryLat =
            double.tryParse(order['delivery_lat'].toString()) ?? deliveryLat;
      }
      if (order.containsKey('delivery_lng') && order['delivery_lng'] != null) {
        deliveryLng =
            double.tryParse(order['delivery_lng'].toString()) ?? deliveryLng;
      }

      // Check deliveryAddress object for coordinates (same logic as single order)
      if ((deliveryLat == 0.0 || deliveryLng == 0.0) &&
          order.containsKey('deliveryAddress')) {
        final deliveryAddress = order['deliveryAddress'];
        if (deliveryAddress is Map) {
          if (deliveryAddress.containsKey('lat') &&
              deliveryAddress['lat'] != null) {
            deliveryLat =
                double.tryParse(deliveryAddress['lat'].toString()) ??
                deliveryLat;
          }
          if (deliveryAddress.containsKey('lng') &&
              deliveryAddress['lng'] != null) {
            deliveryLng =
                double.tryParse(deliveryAddress['lng'].toString()) ??
                deliveryLng;
          }
        } else if (deliveryAddress is String) {
          // Parse JSON string
          try {
            final parsed = json.decode(deliveryAddress);
            if (parsed is Map) {
              deliveryLat =
                  double.tryParse(parsed['lat']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                  deliveryLat;
              deliveryLng =
                  double.tryParse(parsed['lng']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                  deliveryLng;
            }
          } catch (e) {
            debugPrint(
              '⚠️ Multi-order: Error parsing deliveryAddress JSON for order $orderId: $e');
          }
        }
      }

      // CRITICAL: Also check delivery.coordinates (Backend format) - same as in _extractOrderLocations
      if ((deliveryLat == 0.0 || deliveryLng == 0.0) &&
          order.containsKey('delivery')) {
        final delivery = order['delivery'];
        if (delivery is Map && delivery.containsKey('coordinates')) {
          final coords = delivery['coordinates'];
          if (coords is Map) {
            deliveryLat =
                double.tryParse(coords['lat']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                deliveryLat;
            deliveryLng =
                double.tryParse(coords['lng']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                deliveryLng;
            debugPrint(
              '📍 Multi-order: Order $orderId delivery coords from delivery.coordinates: $deliveryLat, $deliveryLng');
          }
        }
      }

      // If still no coordinates, log warning
      if (deliveryLat == 0.0 || deliveryLng == 0.0) {
        debugPrint(
          '⚠️ Multi-order: No delivery coordinates available for order $orderId');
      }

      debugPrint(
        '📍 Multi-order: Order $orderId delivery coordinates: $deliveryLat, $deliveryLng');
      _allDeliveryLocations.add(LatLng(deliveryLat, deliveryLng));
    }
  }

  void _extractOrderLocations() {
    // DEBUG: Print all order keys and pickup-related values
    final orderId = widget.order['order_id'] ?? widget.order['id'];
    print('🔍 _extractOrderLocations for order $orderId');
    print('   pickup_lat from order: ${widget.order['pickup_lat']}');
    print('   pickup_lng from order: ${widget.order['pickup_lng']}');
    print('   pickup_street from order: ${widget.order['pickup_street']}');
    print('   pickup_city from order: ${widget.order['pickup_city']}');

    // Extract pickup location with coordinate validation
    double pickupLat = 0.0; // Will be set from order data
    double pickupLng = 0.0;

    if (widget.order.containsKey('pickup_lat') &&
        widget.order['pickup_lat'] != null) {
      pickupLat =
          double.tryParse(widget.order['pickup_lat'].toString()) ?? pickupLat;
    }
    if (widget.order.containsKey('pickup_lng') &&
        widget.order['pickup_lng'] != null) {
      pickupLng =
          double.tryParse(widget.order['pickup_lng'].toString()) ?? pickupLng;
    }

    // Fix coordinates for known orders with wrong data
    final seller =
        widget.order['product_seller'] ??
        widget.order['sellerName'] ??
        widget.order['username'] ?? AppLocalizations.of(context)!.tr('');

    // Validate final pickup coordinates
    if (pickupLat == 0.0 || pickupLng == 0.0) {
      print(
        '⚠️ Invalid pickup coordinates for order $orderId: $pickupLat, $pickupLng');
    }

    _pickupLocation = LatLng(pickupLat, pickupLng);
    print(
      '📍 Final pickup location set: ${_pickupLocation.latitude}, ${_pickupLocation.longitude}');

    // Extract delivery location
    double deliveryLat = 0.0; // Will be set from order data
    double deliveryLng = 0.0;

    // DEBUG: Print all order keys to see what's available

    // Try multiple possible delivery coordinate field names
    if (widget.order.containsKey('delivery_lat') &&
        widget.order['delivery_lat'] != null) {
      deliveryLat =
          double.tryParse(widget.order['delivery_lat'].toString()) ??
          deliveryLat;
    }
    if (widget.order.containsKey('delivery_lng') &&
        widget.order['delivery_lng'] != null) {
      deliveryLng =
          double.tryParse(widget.order['delivery_lng'].toString()) ??
          deliveryLng;
    }

    // Also check for latitude/longitude (without delivery_ prefix)
    if (deliveryLat == 0.0 &&
        widget.order.containsKey('latitude') &&
        widget.order['latitude'] != null) {
      deliveryLat =
          double.tryParse(widget.order['latitude'].toString()) ?? deliveryLat;
    }
    if (deliveryLng == 0.0 &&
        widget.order.containsKey('longitude') &&
        widget.order['longitude'] != null) {
      deliveryLng =
          double.tryParse(widget.order['longitude'].toString()) ?? deliveryLng;
    }

    // Check deliveryAddress object for coordinates
    if ((deliveryLat == 0.0 || deliveryLng == 0.0) &&
        widget.order.containsKey('deliveryAddress')) {
      final deliveryAddress = widget.order['deliveryAddress'];
      if (deliveryAddress is Map) {
        if (deliveryAddress.containsKey('lat') &&
            deliveryAddress['lat'] != null) {
          deliveryLat =
              double.tryParse(deliveryAddress['lat'].toString()) ?? deliveryLat;
        }
        if (deliveryAddress.containsKey('lng') &&
            deliveryAddress['lng'] != null) {
          deliveryLng =
              double.tryParse(deliveryAddress['lng'].toString()) ?? deliveryLng;
        }
      } else if (deliveryAddress is String) {
        // Parse JSON string
        try {
          final parsed = json.decode(deliveryAddress);
          if (parsed is Map) {
            deliveryLat =
                double.tryParse(parsed['lat']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                deliveryLat;
            deliveryLng =
                double.tryParse(parsed['lng']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                deliveryLng;
          }
        } catch (e) {
          debugPrint('⚠️ Error parsing deliveryAddress JSON: $e');
        }
      }
    }

    // Check nested delivery.coordinates (Backend format) - MOST IMPORTANT
    if ((deliveryLat == 0.0 || deliveryLng == 0.0) &&
        widget.order.containsKey('delivery')) {
      final delivery = widget.order['delivery'];

      if (delivery is Map && delivery.containsKey('coordinates')) {
        final coords = delivery['coordinates'];

        if (coords is Map) {
          if (coords.containsKey('lat') && coords['lat'] != null) {
            deliveryLat =
                double.tryParse(coords['lat'].toString()) ?? deliveryLat;
          }
          if (coords.containsKey('lng') && coords['lng'] != null) {
            deliveryLng =
                double.tryParse(coords['lng'].toString()) ?? deliveryLng;
          }
        }
      } else {
        print('❌ delivery object does not contain coordinates');
      }
    }

    // Validate final delivery coordinates
    if (deliveryLat == 0.0 || deliveryLng == 0.0) {
      // Check if delivery location was pre-loaded from API
      if (_deliveryLocation.latitude != 0.0 &&
          _deliveryLocation.longitude != 0.0) {
        // Keep the API-loaded coordinates, don't overwrite
        deliveryLat = _deliveryLocation.latitude;
        deliveryLng = _deliveryLocation.longitude;
      }
    }

    _deliveryLocation = LatLng(deliveryLat, deliveryLng);

    // Extract security code from database first
    _securityCode = _extractSecurityCodeFromOrder();

    // Load security code from database asynchronously
    _loadSecurityCodeFromDatabase();
  }

  void _generateRoute() async {
    print(
      '🗺️ _generateRoute() called - _navigationStarted: $_navigationStarted, Phase: $_currentPhase, GPS Available: ${_currentLocation != null}');

    // CRITICAL: If GPS not available yet, generate preview route without current location
    if (_currentLocation == null) {
      print(
        '🗺️ GPS not available yet - generating preview route from pickup to delivery');
      await _generateRouteWithoutGPS();
      return;
    }

    // Check current order status to determine route type
    final currentOrderStatus = (_currentOrder != null)
        ? (_currentOrder!['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr(''))
        : (widget.order['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr(''));

    // WICHTIG: If order is picked_up, show ONLY current location → delivery route
    if (currentOrderStatus == 'picked_up') {
      print(
        '🚚 Order already picked up - showing direct route to delivery only');

      LatLng deliveryDestination;

      if (_isMultiOrderMode) {
        // Multi-order: Get current delivery location
        if (_currentDeliveryIndex < _allDeliveryLocations.length) {
          deliveryDestination = _allDeliveryLocations[_currentDeliveryIndex];
        } else {
          print('⚠️ Invalid delivery index in multi-order mode');
          return;
        }
      } else {
        // Single order: Use delivery location
        deliveryDestination = _deliveryLocation;
      }

      setState(() {
        _isLoadingRoute = true;
        _routePoints = [];
        _routeInstructions = [];
      });

      try {
        await _fetchRealRoute(_currentLocation!, deliveryDestination);
        _navigationMode = NavigationMode.online;
      } catch (e) {
        print('❌ Error fetching picked_up route: $e');
        setState(() {
          _routePoints = _generateSimpleRoute(
            _currentLocation!,
            deliveryDestination);
        });
        _navigationMode = NavigationMode.offline;
      }

      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
        });
        _updateCurrentDistanceAndTime();
        _centerMapOnRoute();
      }

      return; // Exit early - no pickup route needed
    }

    // IMPORTANT: If navigation is already running, ALWAYS only show current position → destination
    // If navigation hasn't started yet, show full route
    if (!_navigationStarted) {
      if (_isMultiOrderMode) {
        // Multi-order: Show complete route with ALL pickups and ALL deliveries
        print(
          '🗺️ Generating COMPLETE multi-order preview route (Current → All Pickups → All Deliveries)');
        await _generateMultiOrderFullRoute();
      } else {
        // Single order: Show current → pickup → delivery
        print(
          '🗺️ Generating full preview route (Current → Pickup → Delivery)');
        print(
          '   Current: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
        print(
          '   Pickup: ${_pickupLocation.latitude}, ${_pickupLocation.longitude}');
        print(
          '   Delivery: ${_deliveryLocation.latitude}, ${_deliveryLocation.longitude}');
        await _generateFullPreviewRoute();
      }
      return;
    }

    // CRITICAL: Navigation already running - show ONLY remaining route (current position → destination)
    print(
      '🗺️ Navigation active - generating route from CURRENT position to destination');

    LatLng destination;

    // Determine destination based on current phase and multi-order mode
    if (_isMultiOrderMode) {
      if (_currentPhase == NavigationPhase.multiOrderPickups) {
        // CRITICAL: Multi-order pickup phase should navigate to pickup locations, not delivery!
        if (_currentPickupIndex < _allPickupLocations.length) {
          destination = _allPickupLocations[_currentPickupIndex];
          print(
            '🎯 Multi-order PICKUP route: Index $_currentPickupIndex, Destination: ${destination.latitude}, ${destination.longitude}');
        } else {
          // All pickups completed, start deliveries
          _currentPhase = NavigationPhase.multiOrderDeliveries;
          // CRITICAL: Use existing _currentDeliveryIndex - don't reset to 0!
          // The index was either restored from DB or set by completed delivery logic
          if (_currentDeliveryIndex < _allDeliveryLocations.length) {
            destination = _allDeliveryLocations[_currentDeliveryIndex];
            print(
              '🎯 Multi-order switching to DELIVERY route: Index $_currentDeliveryIndex, Destination: ${destination.latitude}, ${destination.longitude}');
          } else {
            // All deliveries completed
            _currentPhase = NavigationPhase.completed;
            _triggerCompletionAnimation();
            return;
          }
        }
      } else if (_currentPhase == NavigationPhase.multiOrderDeliveries) {
        // Navigate to next delivery location
        if (_currentDeliveryIndex < _allDeliveryLocations.length) {
          destination = _allDeliveryLocations[_currentDeliveryIndex];
          print(
            '🎯 Multi-order DELIVERY route: Index $_currentDeliveryIndex, Destination: ${destination.latitude}, ${destination.longitude}');
        } else {
          // All deliveries completed
          _currentPhase = NavigationPhase.completed;
          _triggerCompletionAnimation();
          return;
        }
      } else {
        // CRITICAL: Fallback should be pickup for new multi-order navigation
        destination = _pickupLocation;
        print(
          '🎯 Multi-order fallback to PICKUP: ${destination.latitude}, ${destination.longitude}');
      }
    } else {
      // Single order mode (existing logic)
      destination = _currentPhase == NavigationPhase.toPickup
          ? _pickupLocation
          : _deliveryLocation;

      // CRITICAL FIX: For all pickup phases, navigate to pickup location
      if (_currentPhase == NavigationPhase.toPickup ||
          _currentPhase == NavigationPhase.multiOrderPickups) {
        destination = _pickupLocation;
        print(
          '🎯 PICKUP destination: ${_pickupLocation.latitude}, ${_pickupLocation.longitude}');
      } else {
        destination = _deliveryLocation;
        print(
          '🎯 DELIVERY destination: ${_deliveryLocation.latitude}, ${_deliveryLocation.longitude}');
      }
    }

    // Debug: Print current phase and destination
    if (_isMultiOrderMode) {
      // Safe display of current progress - handle out-of-bounds indices
      int currentPickupDisplay =
          _currentPickupIndex >= _allPickupLocations.length
          ? _allPickupLocations.length
          : _currentPickupIndex + 1;
      int currentDeliveryDisplay =
          _currentDeliveryIndex >= _allDeliveryLocations.length
          ? _allDeliveryLocations.length
          : _currentDeliveryIndex + 1;
    }

    setState(() {
      _isLoadingRoute = true;
      _estimatedArrival = "Loading...";
      _totalDistance = "Loading...";
      // Clear old route points to ensure fresh route generation
      _routePoints = [];
      _routeColors = [];
      _routeInstructions = [];
    });

    // Validate coordinates before making API call
    if (_currentLocation != null) {
      print(
        '   Current location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
    } else {
      print('   Current location: GPS not available');
    }
    print('   Destination: ${destination.latitude}, ${destination.longitude}');

    // Check for invalid coordinates
    if (destination.latitude == 0.0 && destination.longitude == 0.0) {
      print('❌ Invalid destination coordinates (0.0, 0.0)');
      setState(() {
        _isLoadingRoute = false;
      });
      return;
    }

    try {
      // For multi-order mode, we might need to generate routes to multiple destinations
      if (_isMultiOrderMode) {
        await _fetchRealRoute(_currentLocation!, destination);
      } else {
        await _fetchRealRoute(_currentLocation!, destination);
      }

      // If we get here, the API call was successful, ensure we're in online mode
      _navigationMode = NavigationMode.online;
    } catch (e) {
      // Switch to offline mode
      _navigationMode = NavigationMode.offline;

      // Fallback to simple route if API fails
      _routePoints = _generateSimpleRoute(_currentLocation!, destination);
      _generateTrafficColors();

      double distance = _calculateDistance(_currentLocation!, destination);
      String modeLabel = _isMultiOrderMode
          ? " (multi-order offline)"
          : " (offline)";
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      _totalDistance =
          "${appSettings.formatDistance((distance / 1000).toDouble())}$modeLabel";
      _estimatedArrival =
          "${_formatDuration((distance / 1000 * 2).round())} (est.)";

      // Set offline instructions with distance-appropriate guidance
      String distanceInfo = distance > 100000
          ? appSettings.formatDistance((distance / 1000).toDouble())
          : appSettings.formatDistance((distance / 1000).toDouble());

      if (_isMultiOrderMode) {
        String currentTask = _currentPhase == NavigationPhase.multiOrderPickups
            ? 'pickup ${_currentPickupIndex + 1} of ${_allPickupLocations.length}'
            : 'delivery ${_currentDeliveryIndex + 1} of ${_allDeliveryLocations.length}';

        if (distance > 100000) {
          // Long distance instructions (>100km)
          _routeInstructions = [
            'Head towards $currentTask ($distanceInfo away)',
            'Take highway/Autobahn for long-distance travel',
            'Continue for approximately ${(distance / 1000 / 100).round()} hours',
            AppLocalizations.of(context)?.followSignsTowardsDestination ?? AppLocalizations.of(context)!.tr('Follow signs towards destination city'),
            AppLocalizations.of(context)?.exitHighwayNearDestination ?? AppLocalizations.of(context)!.tr('Exit highway near destination area'),
            AppLocalizations.of(context)?.navigateToFinalDestination ?? AppLocalizations.of(context)!.tr('Navigate to final destination'),
          ];
        } else {
          // Medium/short distance instructions
          _routeInstructions = [
            'Head towards your $currentTask ($distanceInfo away)',
            AppLocalizations.of(context)?.followMainRoadsTowardsDestination ?? AppLocalizations.of(context)!.tr('Follow the main roads towards destination'),
            AppLocalizations.of(context)?.navigateUsingBestJudgment ?? AppLocalizations.of(context)!.tr('Navigate using your best judgment'),
            'Complete $currentTask, then continue to next destination',
          ];
        }
      } else {
        if (distance > 100000) {
          // Long distance instructions (>100km)
          _routeInstructions = [
            'Head towards destination ($distanceInfo away)',
            'Take highway/Autobahn for long-distance travel',
            'Continue for approximately ${(distance / 1000 / 100).round()} hours',
            AppLocalizations.of(context)?.followSignsTowardsDestination ?? AppLocalizations.of(context)!.tr('Follow signs towards destination city'),
            AppLocalizations.of(context)?.exitHighwayNearDestination ?? AppLocalizations.of(context)!.tr('Exit highway near destination area'),
            AppLocalizations.of(context)?.navigateToFinalDestination ?? AppLocalizations.of(context)!.tr('Navigate to final destination'),
          ];
        } else {
          // Medium/short distance instructions
          _routeInstructions = [
            'Head towards your destination ($distanceInfo away)',
            AppLocalizations.of(context)?.followMainRoads ?? AppLocalizations.of(context)!.tr('Follow the main roads'),
            AppLocalizations.of(context)?.navigateUsingBestJudgment ?? AppLocalizations.of(context)!.tr('Navigate using your best judgment'),
            AppLocalizations.of(context)?.youWillArriveAtDestination ?? AppLocalizations.of(context)!.tr('You will arrive at your destination'),
          ];
        }
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingRoute = false;
      });

      // Calculate initial bearing if navigation is active and route exists
      if (_navigationStarted &&
          _routePoints.length >= 2 &&
          _currentLocation != null) {
        _currentBearing = _calculateBearing(_currentLocation!, _routePoints[1]);
        print('🧭 Initial bearing calculated: $_currentBearing°');

        // Apply initial rotation to map - map will rebuild with new rotation
        _mapController.move(_currentLocation!, _mapController.camera.zoom);
      }

      // Update distance and time with the new route
      _updateCurrentDistanceAndTime();

      // Center map on route after generating it
      Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _centerMapOnRoute();
        }
      });

      // Save the route points after generating them
      if (_navigationStarted) {
        _saveNavigationState();
      }
    }
  }

  // Generate route preview WITHOUT GPS location (Pickup → Delivery only)
  Future<void> _generateRouteWithoutGPS() async {
    print('🗺️ _generateRouteWithoutGPS called');
    print(
      '   _pickupLocation: ${_pickupLocation.latitude}, ${_pickupLocation.longitude}');
    print(
      '   _deliveryLocation: ${_deliveryLocation.latitude}, ${_deliveryLocation.longitude}');
    print('   widget.order pickup_street: ${widget.order['pickup_street']}');
    print('   widget.order pickup_lat: ${widget.order['pickup_lat']}');
    print('   widget.order pickup_lng: ${widget.order['pickup_lng']}');

    // Check if this is multi-order mode
    if (_isMultiOrderMode) {
      print(
        '🗺️ Multi-order mode detected - generating FULL multi-order preview without GPS');
      await _generateMultiOrderRouteWithoutGPS();
      return;
    }

    // Single order route without GPS
    setState(() {
      _isLoadingRoute = true;
      _routeInstructions = [];
    });

    try {
      // Validate coordinates
      if (_pickupLocation.latitude == 0.0 && _pickupLocation.longitude == 0.0) {
        print('❌ Invalid pickup coordinates');
        return;
      }
      if (_deliveryLocation.latitude == 0.0 &&
          _deliveryLocation.longitude == 0.0) {
        print('❌ Invalid delivery coordinates');
        return;
      }

      print(
        '   From: ${_pickupLocation.latitude}, ${_pickupLocation.longitude}');
      print(
        '   To: ${_deliveryLocation.latitude}, ${_deliveryLocation.longitude}');

      // Generate route from Pickup to Delivery
      List<LatLng> routePoints = await _fetchRoutePoints(
        _pickupLocation,
        _deliveryLocation);

      double distance = _calculateDistance(_pickupLocation, _deliveryLocation);

      final appSettings = Provider.of<AppSettings>(context, listen: false);
      setState(() {
        _routePoints = routePoints;
        _routeInstructions = [
          "📍 Route preview (GPS loading...)",
          "📦 Start at pickup location",
          "🚚 Drive ${appSettings.formatDistance((distance / 1000).toDouble())} to delivery",
          "✅ Complete delivery at destination",
        ];
        _totalDistance = appSettings.formatDistance(
          (distance / 1000).toDouble());
        _estimatedArrival =
            "${_formatDuration((distance / 1000 * 2).round())} (estimate)";
      });

      _navigationMode = NavigationMode.online;
    } catch (e) {
      print('❌ Route generation without GPS failed: $e');

      // Fallback to simple route
      List<LatLng> realisticRoute = _generateSimpleRoute(
        _pickupLocation,
        _deliveryLocation);
      double distance = _calculateDistance(_pickupLocation, _deliveryLocation);

      final appSettings = Provider.of<AppSettings>(context, listen: false);
      setState(() {
        _routePoints = realisticRoute;
        _routeInstructions = [
          "📍 Route preview (GPS loading...)",
          "📦 Start at pickup location",
          "🚚 Navigate to delivery location",
        ];
        _totalDistance = appSettings.formatDistance(
          (distance / 1000).toDouble());
        _estimatedArrival =
            "${_formatDuration((distance / 1000 * 2).round())} (est.)";
      });
      _navigationMode = NavigationMode.offline;
    }

    if (mounted) {
      setState(() {
        _isLoadingRoute = false;
      });

      _generateTrafficColors();

      // Center map to show the route
      _centerMapOnRoute();

      // When GPS becomes available, regenerate route with current location
      Timer.periodic(const Duration(seconds: 2), (timer) {
        if (_currentLocation != null) {
          timer.cancel();
          _generateRoute();
        } else if (!mounted) {
          timer.cancel();
        }
      });
    }
  }

  // Generate MULTI-ORDER route preview WITHOUT GPS (All Pickups → All Deliveries)
  Future<void> _generateMultiOrderRouteWithoutGPS() async {
    print(
      '🗺️ _generateMultiOrderRouteWithoutGPS() - Showing ALL pickups → ALL deliveries');
    print(
      '   Pickups: ${_allPickupLocations.length}, Deliveries: ${_allDeliveryLocations.length}');

    setState(() {
      _isLoadingRoute = true;
      _routeInstructions = [];
    });

    try {
      // Validate we have locations
      if (_allPickupLocations.isEmpty || _allDeliveryLocations.isEmpty) {
        print('❌ No pickup/delivery locations available');
        return;
      }

      List<LatLng> fullRoutePoints = [];
      List<String> fullInstructions = [
        "📍 Multi-order route preview (GPS loading...)",
      ];
      double totalDistance = 0;

      // Phase 1: Connect all pickups (Pickup1 → Pickup2 → Pickup3...)
      print(
        '🗺️ Phase 1: Connecting ${_allPickupLocations.length} pickup locations');
      for (int i = 0; i < _allPickupLocations.length; i++) {
        if (i == 0) {
          fullInstructions.add("📦 Start at Pickup ${i + 1}");
        } else {
          LatLng from = _allPickupLocations[i - 1];
          LatLng to = _allPickupLocations[i];

          print('🔗 Fetching route: Pickup $i → Pickup ${i + 1}');
          List<LatLng> segment = await _fetchRoutePoints(from, to);

          // Remove duplicate start point
          if (segment.isNotEmpty && fullRoutePoints.isNotEmpty) {
            segment.removeAt(0);
          }

          fullRoutePoints.addAll(segment);

          double segmentDistance = _calculateDistance(from, to);
          totalDistance += segmentDistance;

          final appSettings = Provider.of<AppSettings>(context, listen: false);
          fullInstructions.add(
            "🚗 Drive ${appSettings.formatDistance((segmentDistance / 1000).toDouble())} to Pickup ${i + 1}");
        }
      }

      // Phase 2: Connect last pickup to first delivery
      LatLng lastPickup = _allPickupLocations.last;
      LatLng firstDelivery = _allDeliveryLocations.first;

      List<LatLng> transitionSegment = await _fetchRoutePoints(
        lastPickup,
        firstDelivery);
      if (transitionSegment.isNotEmpty && fullRoutePoints.isNotEmpty) {
        transitionSegment.removeAt(0);
      }
      fullRoutePoints.addAll(transitionSegment);

      double transitionDistance = _calculateDistance(lastPickup, firstDelivery);
      totalDistance += transitionDistance;

      final appSettings = Provider.of<AppSettings>(context, listen: false);
      fullInstructions.add("📦 All pickups collected!");
      fullInstructions.add(
        "🚚 Drive ${appSettings.formatDistance((transitionDistance / 1000).toDouble())} to first delivery");

      // Phase 3: Connect all deliveries (Delivery1 → Delivery2 → Delivery3...)
      print(
        '🗺️ Phase 3: Connecting ${_allDeliveryLocations.length} delivery locations');
      for (int i = 0; i < _allDeliveryLocations.length; i++) {
        if (i > 0) {
          LatLng from = _allDeliveryLocations[i - 1];
          LatLng to = _allDeliveryLocations[i];

          print('🔗 Fetching route: Delivery $i → Delivery ${i + 1}');
          List<LatLng> segment = await _fetchRoutePoints(from, to);

          // Remove duplicate start point
          if (segment.isNotEmpty && fullRoutePoints.isNotEmpty) {
            segment.removeAt(0);
          }

          fullRoutePoints.addAll(segment);

          double segmentDistance = _calculateDistance(from, to);
          totalDistance += segmentDistance;

          fullInstructions.add(
            "🚚 Drive ${appSettings.formatDistance((segmentDistance / 1000).toDouble())} to Delivery ${i + 1}");
        } else {
          fullInstructions.add("🏠 Complete Delivery 1");
        }
      }

      fullInstructions.add("✅ All ${_allOrders.length} orders completed!");

      setState(() {
        _routePoints = fullRoutePoints;
        _routeInstructions = fullInstructions;
        _totalDistance = appSettings.formatDistance(
          (totalDistance / 1000).toDouble());
        _estimatedArrival =
            "${_formatDuration((totalDistance / 1000 * 2).round())} (estimate)";
      });

      _navigationMode = NavigationMode.online;
      print(
        '✅ Multi-order route generated: ${fullRoutePoints.length} points, ${(totalDistance / 1000).toStringAsFixed(1)}km total');
    } catch (e) {
      print('❌ Multi-order route generation without GPS failed: $e');

      // Fallback: Generate simple route connecting all locations
      List<LatLng> fallbackRoute = [];
      double totalDistance = 0;

      // Connect all pickups
      for (int i = 0; i < _allPickupLocations.length; i++) {
        if (i == 0) {
          fallbackRoute.add(_allPickupLocations[i]);
        } else {
          List<LatLng> segment = _generateSimpleRoute(
            _allPickupLocations[i - 1],
            _allPickupLocations[i]);
          segment.removeAt(0); // Remove duplicate
          fallbackRoute.addAll(segment);
          totalDistance += _calculateDistance(
            _allPickupLocations[i - 1],
            _allPickupLocations[i]);
        }
      }

      // Connect to deliveries
      List<LatLng> transitionSegment = _generateSimpleRoute(
        _allPickupLocations.last,
        _allDeliveryLocations.first);
      transitionSegment.removeAt(0);
      fallbackRoute.addAll(transitionSegment);
      totalDistance += _calculateDistance(
        _allPickupLocations.last,
        _allDeliveryLocations.first);

      // Connect all deliveries
      for (int i = 0; i < _allDeliveryLocations.length; i++) {
        if (i > 0) {
          List<LatLng> segment = _generateSimpleRoute(
            _allDeliveryLocations[i - 1],
            _allDeliveryLocations[i]);
          segment.removeAt(0);
          fallbackRoute.addAll(segment);
          totalDistance += _calculateDistance(
            _allDeliveryLocations[i - 1],
            _allDeliveryLocations[i]);
        }
      }

      final appSettings = Provider.of<AppSettings>(context, listen: false);
      setState(() {
        _routePoints = fallbackRoute;
        _routeInstructions = [
          "📍 Multi-order route preview (GPS loading...)",
          "📦 Collect ${_allPickupLocations.length} pickups",
          "🚚 Deliver to ${_allDeliveryLocations.length} locations",
          "✅ Complete all ${_allOrders.length} orders",
        ];
        _totalDistance = appSettings.formatDistance(
          (totalDistance / 1000).toDouble());
        _estimatedArrival =
            "${_formatDuration((totalDistance / 1000 * 2).round())} (est.)";
      });
      _navigationMode = NavigationMode.offline;
    }

    if (mounted) {
      setState(() {
        _isLoadingRoute = false;
      });

      _generateTrafficColors();

      // Center map to show the entire multi-order route
      _centerMapOnMultiOrderRoute();

      // When GPS becomes available, regenerate route with current location
      Timer.periodic(const Duration(seconds: 2), (timer) {
        if (_currentLocation != null) {
          print(
            '✅ GPS now available - regenerating FULL multi-order route with current location');
          timer.cancel();
          _generateRoute();
        } else if (!mounted) {
          timer.cancel();
        }
      });
    }
  }

  // Center map to show entire multi-order route
  void _centerMapOnMultiOrderRoute() {
    if (!mounted) return;

    List<LatLng> allPoints = [];

    // Add all route points
    if (_routePoints.isNotEmpty) {
      allPoints.addAll(_routePoints);
    } else {
      // Fallback: Add pickup and delivery locations
      allPoints.addAll(_allPickupLocations);
      allPoints.addAll(_allDeliveryLocations);
    }

    // Validate all points
    allPoints = allPoints
        .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
        .toList();

    if (allPoints.isEmpty) {
      print('⚠️ No valid points to center map on');
      return;
    }

    print(
      '🗺️ Centering map on multi-order route with ${allPoints.length} points');

    double minLat = allPoints.map((p) => p.latitude).reduce(math.min);
    double maxLat = allPoints.map((p) => p.latitude).reduce(math.max);
    double minLng = allPoints.map((p) => p.longitude).reduce(math.min);
    double maxLng = allPoints.map((p) => p.longitude).reduce(math.max);

    // Add padding
    LatLng southwest = LatLng(minLat - 0.01, minLng - 0.01);
    LatLng northeast = LatLng(maxLat + 0.01, maxLng + 0.01);

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(southwest, northeast),
          padding: EdgeInsets.all(50)));
    } catch (e) {
      print('⚠️ Could not center map: $e');
    }
  }

  // Generate full preview route: current location → pickup → delivery
  Future<void> _generateFullPreviewRoute() async {
    print(
      '🗺️🗺️🗺️ _generateFullPreviewRoute() started - FULL ROUTE CALCULATION');
    setState(() {
      _isLoadingRoute = true;
      _routeInstructions = [];
    });

    try {
      List<LatLng> fullRoutePoints = [];
      List<String> fullInstructions = [];

      print(
        '   From: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
      print('   To: ${_pickupLocation.latitude}, ${_pickupLocation.longitude}');

      // Route segment 1: Current location → Pickup (with metrics)
      final toPickupData = await _fetchRouteWithMetrics(
        _currentLocation!,
        _pickupLocation);
      final List<LatLng> toPickupPoints = toPickupData['points'];
      final double pickupDistance = toPickupData['distance']; // meters
      final double pickupDuration = toPickupData['duration']; // seconds

      print(
        '✅ Received ${toPickupPoints.length} points for Current → Pickup: ${pickupDistance}m, ${pickupDuration}s');
      fullRoutePoints.addAll(toPickupPoints);

      double deliveryDistance = 0.0;
      double deliveryDuration = 0.0;

      // Route segment 2: Pickup → Delivery (only if delivery coords are valid)
      if (_deliveryLocation.latitude != 0.0 ||
          _deliveryLocation.longitude != 0.0) {
        print(
          '   From: ${_pickupLocation.latitude}, ${_pickupLocation.longitude}');
        print(
          '   To: ${_deliveryLocation.latitude}, ${_deliveryLocation.longitude}');

        final toDeliveryData = await _fetchRouteWithMetrics(
          _pickupLocation,
          _deliveryLocation);
        final List<LatLng> toDeliveryPoints = toDeliveryData['points'];
        deliveryDistance = toDeliveryData['distance']; // meters
        deliveryDuration = toDeliveryData['duration']; // seconds

        print(
          '✅ Received ${toDeliveryPoints.length} points for Pickup → Delivery: ${deliveryDistance}m, ${deliveryDuration}s');
        fullRoutePoints.addAll(toDeliveryPoints);
      } else {
        print(
          '⚠️ Skipping Pickup → Delivery segment (invalid delivery coords)');
      }

      // Calculate TOTAL distance and duration from API data
      double totalDistance = pickupDistance + deliveryDistance; // meters
      double totalDuration = pickupDuration + deliveryDuration; // seconds

      final appSettings = Provider.of<AppSettings>(context, listen: false);
      fullInstructions = [
        "📍 Full route preview",
        "🚗 Drive ${appSettings.formatDistance((pickupDistance / 1000).toDouble())} to pickup location",
        "📦 Collect items at pickup",
        "🚚 Drive ${appSettings.formatDistance((deliveryDistance / 1000).toDouble())} to delivery",
        "✅ Complete delivery at destination",
      ];

      setState(() {
        _routePoints = fullRoutePoints;
        _routeInstructions = fullInstructions;
        // Use ACTUAL distance and duration from OSRM API
        _totalDistance = appSettings.formatDistance(
          (totalDistance / 1000).toDouble());
        _estimatedArrival = _formatDuration(
          (totalDuration / 60).round()); // convert seconds to minutes

        print('   📏 Total distance: $_totalDistance (${totalDistance}m)');
        print('   ⏱️ Total time: $_estimatedArrival (${totalDuration}s)');
        print('   🗺️ Total points: ${fullRoutePoints.length}');
        print(
          '   📍 Pickup distance: ${appSettings.formatDistance((pickupDistance / 1000).toDouble())}');
        print(
          '   📍 Delivery distance: ${appSettings.formatDistance((deliveryDistance / 1000).toDouble())}');
      });

      _navigationMode = NavigationMode.online;
    } catch (e) {
      print('❌ Full preview route generation failed: $e');

      // Fallback to realistic combined route (not straight lines)
      List<LatLng> realisticRoute = [];
      realisticRoute.addAll(
        _generateSimpleRoute(_currentLocation!, _pickupLocation));

      // Remove duplicate point between pickup and delivery segments
      List<LatLng> deliverySegment = _generateSimpleRoute(
        _pickupLocation,
        _deliveryLocation);
      if (deliverySegment.isNotEmpty) {
        deliverySegment.removeAt(0); // Remove duplicate pickup point
        realisticRoute.addAll(deliverySegment);
      }

      double pickupDistance = _calculateDistance(
        _currentLocation!,
        _pickupLocation);
      double deliveryDistance = _calculateDistance(
        _pickupLocation,
        _deliveryLocation);
      double totalDistance = pickupDistance + deliveryDistance;

      final appSettings = Provider.of<AppSettings>(context, listen: false);
      setState(() {
        _routePoints = realisticRoute;
        _routeInstructions = [
          "📍 Route preview (offline)",
          "🚗 Navigate to pickup location first",
          "🚚 Then proceed to delivery location",
          "📱 Tap ${AppLocalizations.of(context)?.goExclamation ?? AppLocalizations.of(context)!.tr('Go!')} to start navigation",
        ];
        _totalDistance =
            "${appSettings.formatDistance((totalDistance / 1000).toDouble())} total";
        _estimatedArrival =
            "${_formatDuration((totalDistance / 1000 * 2).round())} (est.)";
      });
      _navigationMode = NavigationMode.offline;
    }

    if (mounted) {
      setState(() {
        _isLoadingRoute = false;
      });

      _generateTrafficColors();
      _centerMapOnRoute();
      _updateCurrentDistanceAndTime();
    }
  }

  // Generate complete multi-order route: current → pickup1 → pickup2 → ... → delivery1 → delivery2 → ...
  Future<void> _generateMultiOrderFullRoute() async {
    print(
      '🗺️ _generateMultiOrderFullRoute() started - ${_allPickupLocations.length} pickups, ${_allDeliveryLocations.length} deliveries');

    // Validate we have locations to work with
    if (_allPickupLocations.isEmpty && _allDeliveryLocations.isEmpty) {
      print(
        '❌ No pickup or delivery locations available - cannot generate multi-order route');
      return;
    }

    final appSettings = Provider.of<AppSettings>(context, listen: false);

    setState(() {
      _isLoadingRoute = true;
      _routeInstructions = [];
    });

    try {
      List<LatLng> fullRoutePoints = [];
      List<String> fullInstructions = [];
      double totalDistance = 0.0;

      // Start from current location
      LatLng currentPoint = _currentLocation!;
      print(
        '🗺️ Starting from current location: ${currentPoint.latitude}, ${currentPoint.longitude}');

      // Step 1: Route through ALL pickup locations
      for (int i = 0; i < _allPickupLocations.length; i++) {
        final pickup = _allPickupLocations[i];
        print('   From: ${currentPoint.latitude}, ${currentPoint.longitude}');
        print('   To: ${pickup.latitude}, ${pickup.longitude}');

        List<LatLng> segmentPoints = await _fetchRoutePoints(
          currentPoint,
          pickup);
        print(
          '✅ Received ${segmentPoints.length} points for segment to Pickup ${i + 1}');

        if (segmentPoints.isNotEmpty) {
          // Remove first point if it duplicates the last point of previous segment
          if (fullRoutePoints.isNotEmpty &&
              segmentPoints.first == fullRoutePoints.last) {
            segmentPoints.removeAt(0);
          }
          fullRoutePoints.addAll(segmentPoints);

          double segmentDistance = _calculateDistance(currentPoint, pickup);
          totalDistance += segmentDistance;
          fullInstructions.add(
            '📦 Pickup ${i + 1}: ${appSettings.formatDistance((segmentDistance / 1000).toDouble())}');
        }

        currentPoint = pickup; // Move to next starting point
      }

      print(
        '✅ All pickup segments complete. Total pickups: ${_allPickupLocations.length}');

      // Step 2: Route through ALL delivery locations
      for (int i = 0; i < _allDeliveryLocations.length; i++) {
        final delivery = _allDeliveryLocations[i];
        print('   From: ${currentPoint.latitude}, ${currentPoint.longitude}');
        print('   To: ${delivery.latitude}, ${delivery.longitude}');

        List<LatLng> segmentPoints = await _fetchRoutePoints(
          currentPoint,
          delivery);
        print(
          '✅ Received ${segmentPoints.length} points for segment to Delivery ${i + 1}');

        if (segmentPoints.isNotEmpty) {
          // Remove first point if it duplicates the last point of previous segment
          if (fullRoutePoints.isNotEmpty &&
              segmentPoints.first == fullRoutePoints.last) {
            segmentPoints.removeAt(0);
          }
          fullRoutePoints.addAll(segmentPoints);

          double segmentDistance = _calculateDistance(currentPoint, delivery);
          totalDistance += segmentDistance;
          fullInstructions.add(
            '🏠 Delivery ${i + 1}: ${appSettings.formatDistance((segmentDistance / 1000).toDouble())}');
        }

        currentPoint = delivery; // Move to next starting point
      }

      print(
        '✅ All delivery segments complete. Total deliveries: ${_allDeliveryLocations.length}');
      print(
        '✅ Complete multi-order route: ${fullRoutePoints.length} points, ${(totalDistance / 1000).toStringAsFixed(1)} km total');

      setState(() {
        _routePoints = fullRoutePoints;
        _routeInstructions = [
          "📍 Complete multi-order route preview",
          "📦 Step 1: Pick up from ${_allPickupLocations.length} location(s)",
          ...fullInstructions.where((i) => i.contains(AppLocalizations.of(context)?.pickup ?? AppLocalizations.of(context)!.tr('Pickup'))),
          "🚚 Step 2: Deliver to ${_allDeliveryLocations.length} location(s)",
          ...fullInstructions.where((i) => i.contains(AppLocalizations.of(context)?.delivery ?? AppLocalizations.of(context)!.tr('Delivery'))),
          "📱 Tap ${AppLocalizations.of(context)?.goExclamation ?? AppLocalizations.of(context)!.tr('Go!')} to start navigation",
        ];
        _totalDistance =
            "${appSettings.formatDistance((totalDistance / 1000).toDouble())} total";
        int totalMinutes = (totalDistance / 1000 * 2)
            .round(); // ~2 min per km estimate
        _estimatedArrival = "${_formatDuration(totalMinutes)} (est.)";
      });
    } catch (e) {
      print('❌ Error generating multi-order full route: $e');

      // Fallback to realistic combined route
      List<LatLng> realisticRoute = [];
      double totalDistance = 0.0;
      LatLng currentPoint = _currentLocation!;

      // Generate route through all pickups
      for (int i = 0; i < _allPickupLocations.length; i++) {
        List<LatLng> segment = _generateSimpleRoute(
          currentPoint,
          _allPickupLocations[i]);
        if (realisticRoute.isNotEmpty && segment.isNotEmpty) {
          segment.removeAt(0); // Remove duplicate point
        }
        realisticRoute.addAll(segment);
        totalDistance += _calculateDistance(
          currentPoint,
          _allPickupLocations[i]);
        currentPoint = _allPickupLocations[i];
      }

      // Generate route through all deliveries
      for (int i = 0; i < _allDeliveryLocations.length; i++) {
        List<LatLng> segment = _generateSimpleRoute(
          currentPoint,
          _allDeliveryLocations[i]);
        if (realisticRoute.isNotEmpty && segment.isNotEmpty) {
          segment.removeAt(0); // Remove duplicate point
        }
        realisticRoute.addAll(segment);
        totalDistance += _calculateDistance(
          currentPoint,
          _allDeliveryLocations[i]);
        currentPoint = _allDeliveryLocations[i];
      }

      setState(() {
        _routePoints = realisticRoute;
        _routeInstructions = [
          "📍 Multi-order route preview (offline)",
          "📦 Collect ${_allPickupLocations.length} pickup(s)",
          "🚚 Deliver to ${_allDeliveryLocations.length} location(s)",
          "📱 Tap ${AppLocalizations.of(context)?.goExclamation ?? AppLocalizations.of(context)!.tr('Go!')} to start navigation",
        ];
        _totalDistance =
            "${appSettings.formatDistance((totalDistance / 1000).toDouble())} total";
        _estimatedArrival =
            "${_formatDuration((totalDistance / 1000 * 2).round())} (est.)";
      });
      _navigationMode = NavigationMode.offline;
    }

    if (mounted) {
      setState(() {
        _isLoadingRoute = false;
      });

      _generateTrafficColors();
      _centerMapOnRoute();
      _updateCurrentDistanceAndTime();
    }
  }

  // Helper method to fetch route points between two locations
  Future<List<LatLng>> _fetchRoutePoints(LatLng start, LatLng end) async {
    // Validate coordinates before making API call
    if (start.latitude == 0.0 && start.longitude == 0.0) {
      print('❌ Invalid start coordinates (0.0, 0.0) - using fallback route');
      return _generateSimpleRoute(start, end);
    }
    if (end.latitude == 0.0 && end.longitude == 0.0) {
      print('❌ Invalid end coordinates (0.0, 0.0) - using fallback route');
      return _generateSimpleRoute(start, end);
    }

    // Additional coordinate validation
    if (start.latitude.abs() > 90 ||
        start.longitude.abs() > 180 ||
        end.latitude.abs() > 90 ||
        end.longitude.abs() > 180) {
      print('❌ Coordinates out of valid range - using fallback route');
      return _generateSimpleRoute(start, end);
    }

    print(
      '🔗 Fetching route segment: ${start.latitude.toStringAsFixed(4)}, ${start.longitude.toStringAsFixed(4)} → ${end.latitude.toStringAsFixed(4)}, ${end.longitude.toStringAsFixed(4)}');

    final String url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&alternatives=false';

    print('🌐 OSRM segment URL: $url');

    try {
      print('🌐 Making OSRM segment API request...');
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'CultiooBusinessApp/1.0',
              'Accept': 'application/json',
            })
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              print('❌ OSRM segment API timeout after 30 seconds on Android');
              throw Exception('Segment timeout');
            });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];

          if (geometry != null && geometry['coordinates'] != null) {
            final coordinates = geometry['coordinates'] as List;
            List<LatLng> points = [];

            for (var coord in coordinates) {
              if (coord is List && coord.length >= 2) {
                double lat = coord[1].toDouble();
                double lng = coord[0].toDouble();

                // Validate coordinates
                if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
                  points.add(LatLng(lat, lng));
                }
              }
            }

            if (points.isNotEmpty) {
              return points;
            }
          }
        } else {
          print(
            '❌ OSRM error for segment: ${data['code']} - ${data['message'] ?? AppLocalizations.of(context)!.tr('Unknown')}');
        }
      } else {
        print('❌ OSRM HTTP error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error fetching route segment: $e');
    }

    // Fallback to realistic route (not straight line)
    print('🛣️ Using fallback realistic route for segment');
    return _generateSimpleRoute(start, end);
  }

  /// Fetches route with distance and duration information
  Future<Map<String, dynamic>> _fetchRouteWithMetrics(
    LatLng start,
    LatLng end) async {
    // Validate coordinates before making API call
    if (start.latitude == 0.0 && start.longitude == 0.0) {
      print('❌ Invalid start coordinates (0.0, 0.0) - using fallback');
      return {
        'points': _generateSimpleRoute(start, end),
        'distance': 0.0,
        'duration': 0.0,
      };
    }
    if (end.latitude == 0.0 && end.longitude == 0.0) {
      print('❌ Invalid end coordinates (0.0, 0.0) - using fallback');
      return {
        'points': _generateSimpleRoute(start, end),
        'distance': 0.0,
        'duration': 0.0,
      };
    }

    final String url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&alternatives=false';

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Segment timeout'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];

          // Extract distance (meters) and duration (seconds)
          final double distance = (route['distance']?.toDouble() ?? 0.0);
          final double duration = (route['duration']?.toDouble() ?? 0.0);

          if (geometry != null && geometry['coordinates'] != null) {
            final coordinates = geometry['coordinates'] as List;
            List<LatLng> points = [];

            for (var coord in coordinates) {
              if (coord is List && coord.length >= 2) {
                double lat = coord[1].toDouble();
                double lng = coord[0].toDouble();

                if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
                  points.add(LatLng(lat, lng));
                }
              }
            }

            if (points.isNotEmpty) {
              print(
                '✅ Fetched route segment: ${points.length} points, ${distance}m, ${duration}s');
              return {
                'points': points,
                'distance': distance,
                'duration': duration,
              };
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error fetching route metrics: $e');
    }

    // Fallback - use realistic driving time estimate
    final fallbackDistance = _calculateDistance(start, end);
    // Average city driving: ~50 km/h = ~1.2 min per km
    // Highway driving: ~80 km/h = ~0.75 min per km
    // Use 1 min per km as reasonable average
    final estimatedDuration =
        (fallbackDistance / 1000 * 60); // 1 minute per km = 60 km/h average

    print(
      '⚠️ Using fallback route calculation: ${(fallbackDistance / 1000).toStringAsFixed(2)}km, ${(estimatedDuration / 60).toStringAsFixed(1)}min');

    return {
      'points': _generateSimpleRoute(start, end),
      'distance': fallbackDistance,
      'duration': estimatedDuration,
    };
  }

  Future<void> _fetchRealRoute(LatLng start, LatLng end) async {
    // Validate coordinates before making API call
    if (start.latitude == 0.0 && start.longitude == 0.0) {
      print('❌ Invalid start coordinates (0.0, 0.0) - cannot fetch route');
      throw Exception('Invalid start coordinates');
    }
    if (end.latitude == 0.0 && end.longitude == 0.0) {
      print('❌ Invalid end coordinates (0.0, 0.0) - cannot fetch route');
      throw Exception('Invalid end coordinates');
    }

    // Additional coordinate validation
    if (start.latitude.abs() > 90 ||
        start.longitude.abs() > 180 ||
        end.latitude.abs() > 90 ||
        end.longitude.abs() > 180) {
      print('❌ Coordinates out of valid range - cannot fetch route');
      throw Exception('Invalid coordinate range');
    }

    print(
      '🛣️ Fetching real route from ${start.latitude.toStringAsFixed(4)}, ${start.longitude.toStringAsFixed(4)} to ${end.latitude.toStringAsFixed(4)}, ${end.longitude.toStringAsFixed(4)}');

    // Using OSRM (Open Source Routing Machine) - Free, no API key required
    final String url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true&alternatives=false';

    print('🌐 OSRM API URL: $url');

    try {
      print('🌐 Making OSRM API request...');
      // Add timeout and better error handling
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': 'CultiooBusinessApp/1.0',
              'Accept': 'application/json',
            })
          .timeout(
            const Duration(seconds: 30), // Increased timeout for Android
            onTimeout: () {
              print('❌ OSRM API timeout after 30 seconds on Android');
              throw Exception(
                'Network timeout after 30 seconds - using offline route');
            });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('📊 OSRM Response code: ${data['code']}');

        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            data['routes'].isNotEmpty) {
          final route = data['routes'][0];

          // Check if geometry exists and is valid
          if (route['geometry'] != null &&
              route['geometry']['coordinates'] != null) {
            final coordinates = route['geometry']['coordinates'] as List;

            // Convert coordinates to LatLng with validation
            List<LatLng> routePoints = [];
            for (var coord in coordinates) {
              if (coord is List && coord.length >= 2) {
                double lat = coord[1].toDouble();
                double lng = coord[0].toDouble();

                // Validate coordinates are within reasonable bounds
                if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
                  routePoints.add(LatLng(lat, lng));
                }
              }
            }

            if (routePoints.isNotEmpty) {
              _routePoints = routePoints;
              print(
                '✅ Successfully parsed ${routePoints.length} valid route points');

              // Generate traffic-aware colors for route segments
              _generateTrafficColors();

              // Extract route info
              final distance =
                  (route['distance']?.toDouble() ?? 0.0) /
                  1000.0; // Convert to km
              final duration =
                  (route['duration']?.toDouble() ?? 0.0) /
                  60.0; // Convert to minutes

              final appSettings = Provider.of<AppSettings>(
                context,
                listen: false);
              _totalDistance = appSettings.formatDistance(distance.toDouble());
              _estimatedArrival = _formatDuration(duration.round());

              // CRITICAL: Save full route distance BEFORE navigation starts
              // This is the complete pickup → delivery distance
              if (!_navigationStarted) {
                _fullRouteDistance = _totalDistance;
                _fullRouteTime = _estimatedArrival;
                print(
                  '📏 Full route saved: $_fullRouteDistance, Time: $_fullRouteTime');
              }

              // Extract turn-by-turn instructions
              _routeInstructions = [];
              if (route['legs'] != null) {
                final legs = route['legs'] as List;

                for (var leg in legs) {
                  if (leg['steps'] != null) {
                    final steps = leg['steps'] as List;
                    for (var step in steps) {
                      if (step['maneuver'] != null) {
                        final maneuver = step['maneuver'];
                        final instruction =
                            maneuver['instruction']?.toString() ?? AppLocalizations.of(context)!.tr('');
                        final type = maneuver['type']?.toString() ?? AppLocalizations.of(context)!.tr('');
                        final modifier = maneuver['modifier']?.toString() ?? AppLocalizations.of(context)!.tr('');

                        // Enhanced instruction processing
                        String enhancedInstruction = instruction;
                        if (type == 'turn' && modifier.isNotEmpty) {
                          if (modifier.contains('left')) {
                            enhancedInstruction = AppLocalizations.of(context)?.turnLeft ?? AppLocalizations.of(context)!.tr('Turn left');
                          } else if (modifier.contains('right')) {
                            enhancedInstruction = AppLocalizations.of(context)?.turnRight ?? AppLocalizations.of(context)!.tr('Turn right');
                          } else if (modifier == 'straight') {
                            enhancedInstruction = AppLocalizations.of(context)?.continueStraight ?? AppLocalizations.of(context)!.tr('Continue straight');
                          }
                        }

                        String friendlyInstruction = _convertOSRMInstruction(
                          type,
                          enhancedInstruction);
                        if (friendlyInstruction.isNotEmpty &&
                            friendlyInstruction != 'Follow route' &&
                            friendlyInstruction != (AppLocalizations.of(context)?.startYourJourney ?? AppLocalizations.of(context)!.tr('Start your journey'))) {
                          _routeInstructions.add(friendlyInstruction);
                        }
                      }
                    }
                  }
                }
              }

              print(
                '✅ Parsed ${_routeInstructions.length} navigation instructions');
            } else {
              print('❌ No valid route points found after parsing');
              throw Exception('No valid route coordinates found');
            }
          } else {
            print('❌ No geometry data in OSRM response');
            throw Exception('No route geometry found in response');
          }
        } else {
          print(
            '❌ OSRM returned error: ${data['code']} - ${data['message'] ?? AppLocalizations.of(context)!.tr('Unknown error')}');
          throw Exception(
            'No route found: ${data['code']} - ${data['message'] ?? AppLocalizations.of(context)!.tr('Unknown error')}');
        }
      } else {
        print('❌ OSRM API failed with status: ${response.statusCode}');
        print('Response body: ${response.body}');
        throw Exception('OSRM API failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Route fetching failed: $e');

      // Create offline fallback instructions
      _routeInstructions = [
        AppLocalizations.of(context)?.headTowardsDestination ?? AppLocalizations.of(context)!.tr('Head towards your destination'),
        AppLocalizations.of(context)?.followMainRoads ?? AppLocalizations.of(context)!.tr('Follow the main roads'),
        AppLocalizations.of(context)?.turnWhenNecessary ?? AppLocalizations.of(context)!.tr('Turn when necessary based on GPS'),
        AppLocalizations.of(context)?.youWillArriveAtDestination ?? AppLocalizations.of(context)!.tr('You will arrive at your destination'),
      ];

      rethrow; // Still throw to trigger fallback in generateRoute
    }
  }

  String _convertOSRMInstruction(String type, String instruction) {
    switch (type) {
      case 'depart':
        return AppLocalizations.of(context)?.startYourJourney ?? AppLocalizations.of(context)!.tr('Start your journey');
      case 'turn':
        if (instruction.toLowerCase().contains('left')) {
          return AppLocalizations.of(context)?.turnLeft ?? AppLocalizations.of(context)!.tr('Turn left');
        } else if (instruction.toLowerCase().contains('right')) {
          return AppLocalizations.of(context)?.turnRight ?? AppLocalizations.of(context)!.tr('Turn right');
        }
        return instruction.isEmpty ? AppLocalizations.of(context)?.turnInstruction ?? AppLocalizations.of(context)!.tr('Turn') : instruction;
      case 'new name':
        return AppLocalizations.of(context)?.continueOnRoad ?? AppLocalizations.of(context)!.tr('Continue on the road');
      case 'continue':
        return AppLocalizations.of(context)?.continueStraight ?? AppLocalizations.of(context)!.tr('Continue straight');
      case 'arrive':
        return AppLocalizations.of(context)?.arrivedAtDestination ?? AppLocalizations.of(context)!.tr('You have arrived at your destination');
      case 'merge':
        return AppLocalizations.of(context)?.mergeOntoMainRoad ?? AppLocalizations.of(context)!.tr('Merge onto the main road');
      case 'on ramp':
        return AppLocalizations.of(context)?.takeOnRamp ?? AppLocalizations.of(context)!.tr('Take the on-ramp');
      case 'off ramp':
        return AppLocalizations.of(context)?.takeExit ?? AppLocalizations.of(context)!.tr('Take the exit');
      case 'fork':
        return AppLocalizations.of(context)?.atForkKeepRight ?? AppLocalizations.of(context)!.tr('At the fork, keep right');
      case 'end of road':
        return AppLocalizations.of(context)?.atEndOfRoadTurn ?? AppLocalizations.of(context)!.tr('At the end of the road, turn');
      case 'roundabout':
        return AppLocalizations.of(context)?.enterRoundabout ?? AppLocalizations.of(context)!.tr('Enter the roundabout');
      case 'rotary':
        return AppLocalizations.of(context)?.enterRoundabout ?? AppLocalizations.of(context)!.tr('Enter the roundabout');
      case 'roundabout turn':
        if (instruction.toLowerCase().contains('1st')) {
          return AppLocalizations.of(context)?.takeFirstExitRoundabout ?? AppLocalizations.of(context)!.tr('Take the 1st exit at the roundabout');
        } else if (instruction.toLowerCase().contains('2nd')) {
          return AppLocalizations.of(context)?.takeSecondExitRoundabout ?? AppLocalizations.of(context)!.tr('Take the 2nd exit at the roundabout');
        } else if (instruction.toLowerCase().contains('3rd')) {
          return AppLocalizations.of(context)?.takeThirdExitRoundabout ?? AppLocalizations.of(context)!.tr('Take the 3rd exit at the roundabout');
        }
        return AppLocalizations.of(context)?.takeExitAtRoundabout ?? AppLocalizations.of(context)!.tr('Take the exit at the roundabout');
      case 'notification':
        return AppLocalizations.of(context)?.roadNameChanges ?? AppLocalizations.of(context)!.tr('Road name changes');
      default:
        return instruction.isEmpty ? AppLocalizations.of(context)?.followRoute ?? AppLocalizations.of(context)!.tr('Follow the route') : instruction;
    }
  }

  void _generateTrafficColors() {
    _routeColors = [];

    if (_routePoints.isEmpty) return;

    // Apple Maps style traffic colors
    const Color normalTraffic = Color(0xFF007AFF); // Apple Blue
    const Color lightTraffic = Color(0xFFFF9500); // Apple Orange
    const Color heavyTraffic = Color(0xFFFF3B30); // Apple Red
    const Color slowTraffic = Color(0xFFFFCC02); // Apple Yellow

    // Simulate realistic traffic patterns
    for (int i = 0; i < _routePoints.length - 1; i++) {
      double progress = i / (_routePoints.length - 1);

      // Simulate traffic conditions based on route progress and randomization
      double trafficSeed = math.sin(progress * math.pi * 4) * 0.5 + 0.5;
      trafficSeed += (math.Random().nextDouble() - 0.5) * 0.3;

      // More traffic in middle sections (city centers)
      if (progress > 0.2 && progress < 0.8) {
        trafficSeed += 0.2;
      }

      // Determine traffic color based on conditions
      Color segmentColor;
      if (trafficSeed > 0.8) {
        segmentColor = heavyTraffic; // Heavy traffic - Red
      } else if (trafficSeed > 0.6) {
        segmentColor = lightTraffic; // Moderate traffic - Orange
      } else if (trafficSeed > 0.4) {
        segmentColor = slowTraffic; // Slow traffic - Yellow
      } else {
        segmentColor = normalTraffic; // Normal traffic - Blue
      }

      _routeColors.add(segmentColor);
    }
  }

  List<Polyline> _buildTrafficAwarePolylines() {
    List<Polyline> polylines = [];

    if (_routePoints.isEmpty || _routeColors.isEmpty) {
      // Fallback to simple blue line if no traffic data
      if (_routePoints.isNotEmpty) {
        polylines.add(
          Polyline(
            points: _routePoints,
            color: const Color(0xFF007AFF), // Apple Blue
            strokeWidth: 6));
      }
      return polylines;
    }

    // WICHTIG: Am Anfang (Navigation nicht gestartet) eine durchgehende schwarze Linie zeigen
    if (!_navigationStarted) {
      return [
        // White border (outer layer) for better visibility
        Polyline(
          points: _routePoints,
          color: Colors.white,
          strokeWidth: 10,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round),
        // Black route line (inner layer)
        Polyline(
          points: _routePoints,
          color: Colors.black,
          strokeWidth: 5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round),
      ];
    }

    // During navigation: Show traffic-aware segments
    // Driven sections (before current position) in green, remaining in traffic colors

    // Guard against stale progress index when a new/shorter route is loaded.
    final int safeClosestRoutePointIndex = _routePoints.isEmpty
      ? 0
      : _closestRoutePointIndex.clamp(0, _routePoints.length - 1);

    // First, draw the driven section (green)
    if (safeClosestRoutePointIndex > 0) {
      List<LatLng> drivenPoints = _routePoints.sublist(
        0,
        safeClosestRoutePointIndex + 1);

      // White border for driven section
      polylines.add(
        Polyline(
          points: drivenPoints,
          color: Colors.white.withOpacity(0.5),
          strokeWidth: 10,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round));

      // Green line for driven section
      polylines.add(
        Polyline(
          points: drivenPoints,
          color: const Color(0xFF34C759), // Apple Green
          strokeWidth: 5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round));
    }

    // Then, draw the remaining route with traffic colors
    for (
      int i = safeClosestRoutePointIndex;
      i < _routePoints.length - 1 && i < _routeColors.length;
      i++
    ) {
      // Group consecutive segments with same color for smoother appearance
      Color currentColor = _routeColors[i];
      List<LatLng> segmentPoints = [_routePoints[i]];

      // Look ahead for same color segments
      int j = i + 1;
      while (j < _routePoints.length - 1 &&
          j < _routeColors.length &&
          _routeColors[j] == currentColor &&
          j - i < 5) {
        // Limit segment length
        segmentPoints.add(_routePoints[j]);
        j++;
      }
      segmentPoints.add(_routePoints[j.clamp(0, _routePoints.length - 1)]);

      // Create white border (outer layer) for better visibility
      polylines.add(
        Polyline(
          points: segmentPoints,
          color: Colors.white,
          strokeWidth: 10,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round));

      // Create colored traffic segment (inner layer)
      polylines.add(
        Polyline(
          points: segmentPoints,
          color: currentColor,
          strokeWidth: 5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round));

      i = j - 1; // Move to next different color segment
    }

    return polylines;
  }

  List<LatLng> _generateSimpleRoute(LatLng start, LatLng end) {
    print('🛣️ Generating realistic fallback route (not straight line)');

    List<LatLng> route = [start];

    double latDiff = end.latitude - start.latitude;
    double lngDiff = end.longitude - start.longitude;
    double totalDistance = _calculateDistance(start, end);

    // Create a more realistic route that follows road-like patterns
    // Instead of straight line, create waypoints that simulate real road curves
    int numWaypoints = math.max(
      8,
      (totalDistance / 5000).round()); // More waypoints for longer routes

    for (int i = 1; i < numWaypoints; i++) {
      double progress = i / numWaypoints;

      // Add some curve variation to simulate real roads
      double curveOffset = 0.0;

      // Add realistic road-like curves based on distance and direction
      if (totalDistance > 1000) {
        // Only add curves for routes longer than 1km
        // Simulate road curves with sine wave pattern
        curveOffset =
            math.sin(progress * math.pi * 2) *
            0.002; // Small offset for realism

        // Add some randomness but keep it consistent
        math.Random seedRandom = math.Random((start.latitude * 1000).round());
        curveOffset += (seedRandom.nextDouble() - 0.5) * 0.001;
      }

      // Calculate intermediate point with curve
      double intermediateLat = start.latitude + (latDiff * progress);
      double intermediateLng = start.longitude + (lngDiff * progress);

      // Apply curve offset perpendicular to the main direction
      if (latDiff.abs() > lngDiff.abs()) {
        // Mostly north-south route, offset east-west
        intermediateLng += curveOffset;
      } else {
        // Mostly east-west route, offset north-south
        intermediateLat += curveOffset;
      }

      route.add(LatLng(intermediateLat, intermediateLng));
    }

    route.add(end);

    print(
      '✅ Generated realistic fallback route with ${route.length} waypoints (${(totalDistance / 1000).toStringAsFixed(1)}km)');
    return route;
  }

  // Simplify route for API to avoid payload size issues
  List<LatLng> _simplifyRouteForAPI(List<LatLng> route) {
    if (route.isEmpty) return [];
    if (route.length <= 50) return route; // No need to simplify small routes

    List<LatLng> simplified = [];

    // Always include start point
    simplified.add(route.first);

    // Take every nth point to reduce size, ensuring we get key waypoints
    int step = (route.length / 40).ceil(); // Target ~40 points max

    for (int i = step; i < route.length - step; i += step) {
      simplified.add(route[i]);
    }

    // Always include end point
    if (route.length > 1) {
      simplified.add(route.last);
    }

    return simplified;
  }

  void _startLocationTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        _getCurrentLocation();

        _locationTimer = Timer.periodic(const Duration(seconds: 2), (
          timer) async {
          if (mounted) {
            _getCurrentLocation();

            // During active navigation, update progress every tick for smooth route coloring
            if (_navigationStarted) {
              _updateNavigationProgress();
            } else {
              _updateCurrentDistanceAndTime();
            }

            // Save location to orders table every 30 seconds during navigation
            if (timer.tick % 15 == 0) {
              // Every 30 seconds (15 * 2 seconds)
              _updateOrderLocation(
                widget.order['order_id'] ?? widget.order['id']);
            }

            // ENABLED: Automatic order status checking every 30 seconds to keep UI synchronized
            if (timer.tick % 15 == 0) {
              // Every 30 seconds (15 * 2 seconds)
              final orderId = widget.order['order_id'] ?? widget.order['id'];
              _checkOrderStatus(orderId)
                  .then((currentStatus) {
                    if (currentStatus != null && mounted) {
                      print(
                        '🔄 Auto-check: Order $orderId status is "$currentStatus", UI phase: $_currentPhase');
                      _synchronizeUIWithDatabaseStatus(currentStatus);
                    }
                  })
                  .catchError((error) {
                    print('❌ Periodic status check failed: $error');
                  });
            }

            // Last Mile AI: Check for nearby orders every 45 seconds during navigation
            if (_navigationStarted && timer.tick % 22 == 0) {
              // Every 44 seconds (22 * 2 seconds)
              _checkLastMileOpportunities();
            }
          }
        });
      }
    } catch (e) {}
  }

  // Save current location to database for multi-order navigation tracking
  Future<void> _saveLocationToDatabase() async {
    try {
      // Get session ID (order ID or multi-order session ID)
      final sessionId = await _getSessionId();

      print(
        '📍 Saving location to database: ${_currentLocation!.latitude}, ${_currentLocation!.longitude} for session $sessionId');

      // Save to navigation_sessions table
      final navResponse = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/navigation/progress/$sessionId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'current_location': {
            'lat': _currentLocation!.latitude,
            'lng': _currentLocation!.longitude,
          },
          'current_phase': _currentPhase.toString(),
          'current_instruction_index': _currentInstructionIndex,
        }));

      if (navResponse.statusCode == 200) {
      } else {
        print(
          '⚠️ Failed to save location to navigation_sessions: ${navResponse.statusCode}');
      }

      // Also save to orders table (driver_latitude, driver_longitude)
      // If multi-order mode, update all active orders
      if (_isMultiOrderMode && _allOrders.isNotEmpty) {
        for (var order in _allOrders) {
          final orderId = order['order_id'] ?? order['id'];
          if (orderId != null) {
            await _updateOrderLocation(orderId);
          }
        }
      } else {
        // Single order mode - update current order
        final orderId = widget.order['order_id'] ?? widget.order['id'];
        if (orderId != null) {
          await _updateOrderLocation(orderId);
        }
      }
    } catch (e) {
      print('❌ Error saving location to database: $e');
    }
  }

  // Update driver location in orders table
  Future<void> _updateOrderLocation(dynamic orderId) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/orders/$orderId/driver-location'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'driver_latitude': _currentLocation!.latitude,
          'driver_longitude': _currentLocation!.longitude,
        }));

      if (response.statusCode == 200) {
      } else {
        print(
          '⚠️ Failed to save driver location to orders table: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error updating order location: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check and request permissions first
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          print('❌ Location permission denied by user');
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions are permanently denied');
        throw Exception('Location permissions are permanently denied');
      }

      // Use real GPS location with longer timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(
          seconds: 30), // Increased from 10 to 30 seconds
      );

      LatLng newLocation = LatLng(position.latitude, position.longitude);

      if (mounted) {
        // KRITISCHER FIX: Check if _currentLocation is null before calculating distance
        bool locationChanged =
            _currentLocation == null ||
            _calculateDistance(_currentLocation!, newLocation) >
                10; // 10m threshold

        setState(() {
          _currentLocation = newLocation;
        });

        if (locationChanged) {
          // Keep navigation zoom level when navigating
          double zoomLevel = _navigationStarted ? 17.0 : 12.0;
          if (_currentLocation != null) {
            // During navigation, apply rotation to keep route pointing up
            // Rotation happens via setState + ValueKey forcing map rebuild
            _mapController.move(_currentLocation!, zoomLevel);
          }
          _updateNavigationProgress();
        }

        // Always update distance and time based on current location
        _updateCurrentDistanceAndTime();
      }
    } catch (e) {
      print('❌ GPS error: $e');

      // CRITICAL: DON'T set location to null if we already have a location
      // Only set to null if we've never had a GPS fix
      if (_currentLocation == null) {
        print(
          '📍 No GPS data available yet - route will be shown without current location');
      } else {
        print(
          '📍 GPS timeout, but using last known location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
      }

      // Don't remove existing location on temporary GPS errors
      // This allows the app to continue working with last known position
    }
  }

  // Last Mile AI: Check for nearby orders that match current route
  Future<void> _checkLastMileOpportunities() async {
    // Get app settings to check if Last Mile is enabled
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    if (!appSettings.lastMileEnabled) {
      return;
    }

    if (_currentLocation == null) {
      return;
    }

    // Don't check too frequently (minimum 2 minutes between checks)
    if (_lastLastMileCheck != null) {
      final timeSinceLastCheck = DateTime.now().difference(_lastLastMileCheck!);
      if (timeSinceLastCheck.inSeconds < 120) {
        return;
      }
    }

    _lastLastMileCheck = DateTime.now();

    try {
      print('🤖 AI suggestions: Searching within radius ${appSettings.aiSuggestionRadius} km...');

      // Get driver ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userIdStr = prefs.getString('user_id');
      final driverId = userIdStr != null ? int.tryParse(userIdStr) ?? 1 : 1;

      // Use configurable radius from AppSettings (convert km to meters)
      final radiusMeters = (appSettings.aiSuggestionRadius * 1000).round();

      // Call backend API to find nearby orders
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delvioo/last-mile-opportunities?driver_id=$driverId&lat=${_currentLocation!.latitude}&lng=${_currentLocation!.longitude}&radius=$radiusMeters'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final opportunities = data['opportunities'] as List? ?? [];

        if (opportunities.isEmpty) {
          print('✅ AI: No open orders nearby');
          return;
        }

        // Filter for best match based on route compatibility
        final bestMatch = _findBestLastMileMatch(opportunities);

        if (bestMatch != null && mounted) {
          setState(() {
            _suggestedOrder = bestMatch;
            _showLastMileOrder = true;
          });

          print('🎯 AI: Order #${bestMatch['order_id']} found — ${(bestMatch['distanceToPickup'] as double? ?? 0).round()}m away');
          HapticFeedback.mediumImpact();
        }
      }
    } catch (e) {
      print('❌ AI suggestions error: $e');
    }
  }

  // Find best matching order based on route compatibility
  Map<String, dynamic>? _findBestLastMileMatch(List opportunities) {
    if (opportunities.isEmpty || _currentLocation == null) return null;

    // Calculate score for each opportunity
    List<Map<String, dynamic>> scoredOpportunities = [];

    for (var opportunity in opportunities) {
      try {
        final pickupLat = opportunity['pickup_lat'] ?? 0.0;
        final pickupLng = opportunity['pickup_lng'] ?? 0.0;
        final deliveryLat = opportunity['delivery_lat'] ?? 0.0;
        final deliveryLng = opportunity['delivery_lng'] ?? 0.0;

        if (pickupLat == 0.0 || deliveryLat == 0.0) continue;

        final pickupLocation = LatLng(pickupLat, pickupLng);
        final deliveryLocation = LatLng(deliveryLat, deliveryLng);

        // Calculate distances
        final distanceToPickup = _calculateDistance(
          _currentLocation!,
          pickupLocation);
        final pickupToDelivery = _calculateDistance(
          pickupLocation,
          deliveryLocation);

        // Calculate detour from current route
        LatLng currentDestination;
        if (_currentPhase == NavigationPhase.toPickup ||
            _currentPhase == NavigationPhase.multiOrderPickups) {
          currentDestination = _pickupLocation;
        } else {
          currentDestination = _deliveryLocation;
        }

        final directDistance = _calculateDistance(
          _currentLocation!,
          currentDestination);
        final detourDistance =
            distanceToPickup +
            _calculateDistance(pickupLocation, currentDestination);
        final detourPercentage =
            ((detourDistance - directDistance) / directDistance) * 100;

        // Scoring: Lower is better
        // - Favor nearby pickups (< 2km)
        // - Favor minimal detour (< 20% extra distance)
        // - Favor profitable deliveries (longer delivery distance = better)
        double score = 0.0;

        if (distanceToPickup < 2000) {
          score += 100; // Very close pickup
        } else if (distanceToPickup < 5000)
          score += 50; // Reasonable distance

        if (detourPercentage < 10) {
          score += 80; // Minimal detour
        } else if (detourPercentage < 20)
          score += 40; // Acceptable detour
        else
          score -= 50; // Too much detour

        if (pickupToDelivery > 5000) {
          score += 60; // Good delivery distance
        } else if (pickupToDelivery > 2000)
          score += 30; // Okay delivery distance

        // Add order value bonus if available
        final orderValue = opportunity['total_price'] ?? 0.0;
        if (orderValue > 50) score += 20;
        if (orderValue > 100) score += 40;

        scoredOpportunities.add({
          ...opportunity,
          'score': score,
          'distanceToPickup': distanceToPickup,
          'pickupToDelivery': pickupToDelivery,
          'detourPercentage': detourPercentage,
        });
      } catch (e) {
        print('Error scoring opportunity: $e');
      }
    }

    // Sort by score (highest first)
    scoredOpportunities.sort(
      (a, b) => (b['score'] as double).compareTo(a['score'] as double));

    // Return best match if score is positive
    if (scoredOpportunities.isNotEmpty &&
        scoredOpportunities.first['score'] > 50) {
      return scoredOpportunities.first;
    }

    return null;
  }


  // Show bid placement bottom sheet for the suggested order
  void _showBidBottomSheet() {
    if (_suggestedOrder == null) return;
    
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);
    final orderValue = (_suggestedOrder!['total_price'] ?? 0.0) is int
        ? (_suggestedOrder!['total_price'] as int).toDouble()
        : (_suggestedOrder!['total_price'] ?? 0.0) as double;
    final orderId = _suggestedOrder!['order_id'] ??
      (AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr(''));
    final distanceToPickup = _suggestedOrder!['distanceToPickup'] as double? ?? 0.0;
    final pickupToDelivery = _suggestedOrder!['pickupToDelivery'] as double? ?? 0.0;
    int bidCents = 0; // Right-to-left price input in cents

    // Extract addresses
    final pickupStreet = _suggestedOrder!['pickup_street'] ?? AppLocalizations.of(context)!.tr('');
    final pickupCity = _suggestedOrder!['pickup_city'] ?? AppLocalizations.of(context)!.tr('');
    final pickupZip = _suggestedOrder!['pickup_zip'] ?? AppLocalizations.of(context)!.tr('');
    final pickupCountry = _suggestedOrder!['pickup_country'] ?? AppLocalizations.of(context)!.tr('');
    String pickupAddressText = '';
    if (pickupStreet.toString().isNotEmpty) {
      pickupAddressText = pickupStreet.toString();
      if (pickupCity.toString().isNotEmpty) {
        pickupAddressText += ', $pickupCity';
      }
      if (pickupCountry.toString().isNotEmpty) {
        pickupAddressText += ', $pickupCountry';
      }
    } else if (pickupCity.toString().isNotEmpty) {
      pickupAddressText = '$pickupZip $pickupCity';
      if (pickupCountry.toString().isNotEmpty) {
        pickupAddressText += ', $pickupCountry';
      }
    }

    String deliveryAddressText = '';
    try {
      final deliveryAddr = _suggestedOrder!['deliveryAddress'];
      if (deliveryAddr != null) {
        final addr = deliveryAddr is String ? json.decode(deliveryAddr) : deliveryAddr;
        final street = addr['street'] ?? addr['address'] ?? AppLocalizations.of(context)!.tr('');
        final city = addr['city'] ?? AppLocalizations.of(context)!.tr('');
        final country = addr['country'] ?? AppLocalizations.of(context)!.tr('');
        if (street.toString().isNotEmpty) {
          deliveryAddressText = street.toString();
          if (city.toString().isNotEmpty) {
            deliveryAddressText += ', $city';
          }
          if (country.toString().isNotEmpty) {
            deliveryAddressText += ', $country';
          }
        } else if (city.toString().isNotEmpty) {
          deliveryAddressText = city.toString();
          if (country.toString().isNotEmpty) {
            deliveryAddressText += ', $country';
          }
        }
      }
    } catch (_) {}

    HapticFeedback.mediumImpact();

    TradeRepublicBottomSheet.show(
      context: context,
      child: SafeArea(
        top: false,
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final bidAmount = bidCents / 100.0;

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DragHandle(),

                  // ── Sheet header: Icon left + Title ──
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.money_dollar_circle,
                        size: 22,
                        color: isLight ? Colors.black : Colors.white),
                      SizedBox(width: 12),
                      Text(
                        '${AppLocalizations.of(context)?.placeBid ?? AppLocalizations.of(context)!.tr('Place Bid')}?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.4)),
                    ]),
                  SizedBox(height: 12),

                  // Maps-style route summary (compact)
                  TradeRepublicCard(
                    padding: EdgeInsets.all(14),
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        // Pickup row
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759),
                                borderRadius: BorderRadius.circular(5))),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                pickupAddressText.isNotEmpty 
                                    ? pickupAddressText 
                                    : (AppLocalizations.of(context)?.pickupAddress ?? AppLocalizations.of(context)!.tr('Pickup Address')),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isLight ? Colors.black : Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                            Text(
                              appSettings.formatDistance(distanceToPickup / 1000),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
                          ]),
                        Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 2,
                              height: 16,
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.12)))),
                        // Delivery row
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF3B30),
                                borderRadius: BorderRadius.circular(5))),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                deliveryAddressText.isNotEmpty 
                                    ? deliveryAddressText 
                                    : (AppLocalizations.of(context)?.deliveryAddress ?? AppLocalizations.of(context)!.tr('Delivery Address')),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isLight ? Colors.black : Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                            Text(
                              appSettings.formatDistance(pickupToDelivery / 1000),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
                          ]),
                      ])),
                  SizedBox(height: 12),

                  // Order value row
                  TradeRepublicCard(
                    padding: EdgeInsets.all(14),
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.orderValue ?? AppLocalizations.of(context)!.tr('Order Value'),
                          style: TextStyle(
                            fontSize: 15,
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.7))),
                        Text(
                          appSettings.formatCurrency(orderValue),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white)),
                      ])),
                  SizedBox(height: 16),

                  // Big price display
                  Text(
                    bidCents == 0
                        ? '0.00{currencySymbol}'
                        : '${bidAmount.toStringAsFixed(2)}{currencySymbol}',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      color: bidCents == 0
                          ? (isLight ? Colors.black : Colors.white).withOpacity(0.3)
                          : const Color(0xFF34C759),
                      letterSpacing: -2)),
                  Text(
                    AppLocalizations.of(context)?.yourBid ?? AppLocalizations.of(context)!.tr('Your Bid'),
                    style: TextStyle(
                      fontSize: 14,
                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
                  SizedBox(height: 20),

                  // Numpad
                  _buildBidNumpad(
                    isLight: isLight,
                    currentCents: bidCents,
                    onChanged: (newCents) {
                      setSheetState(() {
                        bidCents = newCents;
                      });
                    }),
                  SizedBox(height: 20),

                  // Submit button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)?.submitBid ?? AppLocalizations.of(context)!.tr('Submit Bid'),
                    icon: Icon(CupertinoIcons.hammer),
                    onPressed: bidCents > 0
                        ? () async {
                            Navigator.pop(context);
                            await _submitAiBid(bidAmount);
                          }
                        : null,
                    width: double.infinity),
                  SizedBox(height: 16),
                ]));
          })));
  }

  // Numpad widget for bid input (right-to-left cents input)
  Widget _buildBidNumpad({
    required bool isLight,
    required int currentCents,
    required ValueChanged<int> onChanged,
  }) {
    Widget buildKey(String label, {VoidCallback? onTap, bool isWide = false}) {
      return Expanded(
        flex: isWide ? 2 : 1,
        child: TradeRepublicTap(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap?.call();
          },
          child: Container(
            height: 52,
            margin: EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: (isLight ? Colors.black : Colors.white).withOpacity(label == '⌫' ? 0.04 : 0.08),
              borderRadius: BorderRadius.circular(16)),
            child: Center(
              child: label == '⌫'
                  ? Icon(
                      CupertinoIcons.delete_left,
                      color: isLight ? Colors.black : Colors.white,
                      size: 22)
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: isLight ? Colors.black : Colors.white))))));
    }

    return Column(
      children: [
        Row(children: [
          buildKey('1', onTap: () => onChanged(currentCents * 10 + 1)),
          buildKey('2', onTap: () => onChanged(currentCents * 10 + 2)),
          buildKey('3', onTap: () => onChanged(currentCents * 10 + 3)),
        ]),
        Row(children: [
          buildKey('4', onTap: () => onChanged(currentCents * 10 + 4)),
          buildKey('5', onTap: () => onChanged(currentCents * 10 + 5)),
          buildKey('6', onTap: () => onChanged(currentCents * 10 + 6)),
        ]),
        Row(children: [
          buildKey('7', onTap: () => onChanged(currentCents * 10 + 7)),
          buildKey('8', onTap: () => onChanged(currentCents * 10 + 8)),
          buildKey('9', onTap: () => onChanged(currentCents * 10 + 9)),
        ]),
        Row(children: [
          buildKey('00', onTap: () => onChanged(currentCents * 100)),
          buildKey('0', onTap: () => onChanged(currentCents * 10)),
          buildKey('⌫', onTap: () => onChanged(currentCents ~/ 10)),
        ]),
      ]);
  }

  // Submit bid for AI-suggested order
  Future<void> _submitAiBid(double bidAmount) async {
    if (_suggestedOrder == null) return;

    final orderId = _suggestedOrder!['order_id'];

    try {
      print('💰 AI Bid: Offer \$$bidAmount for Order #$orderId');

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final userIdStr = prefs.getString('user_id');
      final driverId = userIdStr != null ? int.tryParse(userIdStr) ?? 1 : 1;
      final driverUsername = prefs.getString('username') ?? AppLocalizations.of(context)!.tr('driver');

      // First check if there's an active auction for this order
      final auctionsResponse = await http.get(
        Uri.parse('${ApiConfig.activeAuctionsUrl}?driver_id=$driverId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });

      int? auctionId;
      if (auctionsResponse.statusCode == 200) {
        final auctionsData = json.decode(auctionsResponse.body);
        final auctions = (auctionsData is List ? auctionsData : auctionsData['auctions'] ?? []) as List;
        for (var auction in auctions) {
          if (auction['order_id'].toString() == orderId.toString()) {
            auctionId = auction['id'] is int ? auction['id'] : int.tryParse(auction['id'].toString());
            break;
          }
        }
      }

      if (auctionId != null) {
        // Submit bid to existing auction
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
            'price_mode': 'total',
            'vehicle_type': 'truck',
            'message': AppLocalizations.of(context)?.aiSuggestionDuringNav ?? AppLocalizations.of(context)!.tr('AI suggestion during navigation'),
          }));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            print('✅ AI bid submitted successfully!');
            if (mounted) {
              HapticFeedback.heavyImpact();
              TopNotification.success(
                context,
                '${AppLocalizations.of(context)?.bidSubmittedForOrder ?? AppLocalizations.of(context)!.tr('Bid submitted for Order')} #$orderId \$${bidAmount.toStringAsFixed(2)} 🎯');
            }
          } else {
            throw Exception(data['error'] ?? AppLocalizations.of(context)!.tr('Bid failed'));
          }
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } else {
        // No auction found, directly accept the order
        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/api/delvioo/accept-order/$orderId'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'driver_id': driverId,
            'accepted_via': 'ai_suggestion',
            'bid_amount': bidAmount,
          }));

        if (response.statusCode == 200) {
          print('✅ Order direkt angenommen (keine Auktion)');
          if (mounted) {
            HapticFeedback.heavyImpact();
            TopNotification.success(
              context,
              '${AppLocalizations.of(context)?.orderAccepted ?? AppLocalizations.of(context)!.tr('Order accepted')} #$orderId \$${bidAmount.toStringAsFixed(2)} 🎯');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      }

      // Dismiss the suggestion card
      setState(() {
        _showLastMileOrder = false;
        _suggestedOrder = null;
      });
    } catch (e) {
      print('❌ AI bid error: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.bidFailed ?? AppLocalizations.of(context)!.tr('Bid failed. Please try again.'));
      }
    }
  }

  // Decline Last Mile suggestion
  void _declineLastMileOrder() {
    setState(() {
      _showLastMileOrder = false;
      _suggestedOrder = null;
    });

    HapticFeedback.lightImpact();
  }

  double _calculateDistance(LatLng start, LatLng end) {
    const double radiusEarth = 6371.0;
    double lat1Rad = start.latitude * math.pi / 180.0;
    double lat2Rad = end.latitude * math.pi / 180.0;
    double deltaLatRad = (end.latitude - start.latitude) * math.pi / 180.0;
    double deltaLngRad = (end.longitude - start.longitude) * math.pi / 180.0;

    double a =
        math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLngRad / 2) *
            math.sin(deltaLngRad / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radiusEarth * c * 1000;
  }

  // Calculate bearing (direction) between two points in degrees (0-360)
  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * math.pi / 180.0;
    double lat2 = end.latitude * math.pi / 180.0;
    double dLng = (end.longitude - start.longitude) * math.pi / 180.0;

    double y = math.sin(dLng) * math.cos(lat2);
    double x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    double bearing = math.atan2(y, x);

    // Convert from radians to degrees and normalize to 0-360
    bearing = (bearing * 180.0 / math.pi + 360) % 360;

    return bearing;
  }

  void _updateCurrentDistanceAndTime() {
    if (!mounted || _currentLocation == null) return;

    // CRITICAL: If navigation NOT started, show TOTAL route (Current → Pickup → Delivery)
    if (!_navigationStarted && _currentPhase == NavigationPhase.toPickup) {
      // Prevent multiple simultaneous calculations
      if (_isFetchingTotalRoute || _totalRouteCalculated) {
        print(
          '⏭️ Skipping total route calculation (already done or in progress)');
        return; // Already calculating or already calculated
      }

      _isFetchingTotalRoute = true;
      print(
        '📊 Navigation NOT started - fetching REAL TOTAL route data from API');

      // Fetch real route data from OSRM API asynchronously
      _fetchRouteWithMetrics(_currentLocation!, _pickupLocation)
          .then((toPickupData) {
            final double pickupDistance = toPickupData['distance']; // meters
            final double pickupDuration = toPickupData['duration']; // seconds

            return _fetchRouteWithMetrics(
              _pickupLocation,
              _deliveryLocation).then((toDeliveryData) {
              final double deliveryDistance =
                  toDeliveryData['distance']; // meters
              final double deliveryDuration =
                  toDeliveryData['duration']; // seconds

              // Calculate totals
              final double totalDistance =
                  pickupDistance + deliveryDistance; // meters
              final double totalDuration =
                  pickupDuration + deliveryDuration; // seconds

              final appSettings = Provider.of<AppSettings>(
                context,
                listen: false);

              if (mounted) {
                setState(() {
                  _totalDistance = appSettings.formatDistance(
                    (totalDistance / 1000).toDouble());
                  _estimatedArrival = _formatDuration(
                    (totalDuration / 60).round()); // seconds to minutes
                  _totalRouteCalculated = true; // Mark as calculated
                  _isFetchingTotalRoute = false;
                });

                print(
                  '   📍 Current → Pickup: ${(pickupDistance / 1000).toStringAsFixed(2)} km, ${(pickupDuration / 60).toStringAsFixed(1)} min');
                print(
                  '   📍 Pickup → Delivery: ${(deliveryDistance / 1000).toStringAsFixed(2)} km, ${(deliveryDuration / 60).toStringAsFixed(1)} min');
                print('   📏 TOTAL Distance: $_totalDistance');
                print('   ⏱️ TOTAL Time: $_estimatedArrival');
              }
            });
          })
          .catchError((error) {
            print(
              '⚠️ Failed to fetch real route data, using GPS estimate: $error');

            // Fallback to GPS distance calculation
            double distanceToPickup = _calculateDistance(
              _currentLocation!,
              _pickupLocation);
            double distanceToDelivery = _calculateDistance(
              _pickupLocation,
              _deliveryLocation);
            double totalDistance = distanceToPickup + distanceToDelivery;
            double estimatedMinutes = (totalDistance / 1000) * 2;

            final appSettings = Provider.of<AppSettings>(
              context,
              listen: false);

            if (mounted) {
              setState(() {
                _totalDistance = appSettings.formatDistance(
                  (totalDistance / 1000).toDouble());
                _estimatedArrival = _formatDuration(estimatedMinutes.round());
                _totalRouteCalculated = true;
                _isFetchingTotalRoute = false;
              });
            }
          });

      return; // Don't calculate individual segment
    }

    // Determine destination based on current phase and multi-order mode
    LatLng destination;

    // WICHTIG: Check order status first - if picked_up, ALWAYS navigate to delivery
    final currentOrderStatus = (_currentOrder != null)
        ? (_currentOrder!['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr(''))
        : (widget.order['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr(''));

    if (currentOrderStatus == 'picked_up') {
      // Order is already picked up - navigate directly to delivery
      if (_isMultiOrderMode &&
          _currentDeliveryIndex < _allDeliveryLocations.length) {
        destination = _allDeliveryLocations[_currentDeliveryIndex];
        print(
          '🎯 [PICKED_UP] Multi-order DELIVERY destination: Index $_currentDeliveryIndex, Coords: ${destination.latitude}, ${destination.longitude}');
        if (destination.latitude == 0.0 && destination.longitude == 0.0) {
          print(
            '❌ Invalid multi-order delivery coordinates (0.0, 0.0) - using single order delivery');
          destination = _deliveryLocation;
        }
      } else {
        destination = _deliveryLocation;
        print(
          '🎯 [PICKED_UP] Single-order DELIVERY destination: ${destination.latitude}, ${destination.longitude}');
      }
    }
    // CRITICAL: Always prioritize pickup locations for pickup phases
    else if (_currentPhase == NavigationPhase.toPickup ||
        _currentPhase == NavigationPhase.multiOrderPickups) {
      // For pickup phases, ALWAYS navigate to pickup location
      if (_isMultiOrderMode &&
          _currentPickupIndex < _allPickupLocations.length) {
        destination = _allPickupLocations[_currentPickupIndex];
        print(
          '🎯 Multi-order PICKUP destination: Index $_currentPickupIndex, Coords: ${destination.latitude}, ${destination.longitude}');
        // CRITICAL FIX: Check if destination coordinates are valid
        if (destination.latitude == 0.0 && destination.longitude == 0.0) {
          print(
            '❌ Invalid multi-order pickup coordinates (0.0, 0.0) - using single order pickup');
          destination = _pickupLocation;
        }
      } else {
        destination = _pickupLocation;
      }
    } else if (_currentPhase == NavigationPhase.toDelivery ||
        _currentPhase == NavigationPhase.multiOrderDeliveries) {
      // For delivery phases, navigate to delivery location
      if (_isMultiOrderMode &&
          _currentDeliveryIndex < _allDeliveryLocations.length) {
        destination = _allDeliveryLocations[_currentDeliveryIndex];
        // Check if destination coordinates are valid
        if (destination.latitude == 0.0 && destination.longitude == 0.0) {
          destination = _deliveryLocation;
        }
      } else {
        destination = _deliveryLocation;
      }
    } else {
      // Fallback - default to pickup
      destination = _pickupLocation;
      print(
        '🎯 FALLBACK to pickup destination: ${destination.latitude}, ${destination.longitude}');
    }

    // Calculate current GPS distance to destination
    double distanceToDestination = _calculateDistance(
      _currentLocation!,
      destination);

    // Get app settings for unit system
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final bool useMetric = appSettings.effectiveDistanceUnit == 'Kilometers';

    // Always use real GPS distance for nearby locations (< 5km)
    // For longer distances, prefer OSRM route data if available and reasonable
    bool useGPSDistance =
        distanceToDestination < 5000 ||
        _totalDistance == "Loading..." ||
        _estimatedArrival == "Loading..." ||
        _totalDistance.contains("offline") ||
        _navigationMode == NavigationMode.offline;

    if (useGPSDistance) {
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      setState(() {
        if (distanceToDestination > 0) {
          _totalDistance = appSettings.formatDistance(
            (distanceToDestination / 1000).toDouble());
        }

        // Realistic time estimation based on distance and travel type
        double estimatedTimeMinutes;
        if (distanceToDestination < 500) {
          // Walking distance - 1-2 minutes max
          estimatedTimeMinutes = math.max(
            1,
            (distanceToDestination / 100)); // ~1 min per 100m walking
        } else if (distanceToDestination < 2000) {
          // Short driving distance - city speed ~25 km/h
          estimatedTimeMinutes =
              (distanceToDestination / 1000) * 2.4; // 25 km/h = 2.4 min/km
        } else {
          // Longer driving distance - assume 30 km/h average
          estimatedTimeMinutes =
              (distanceToDestination / 1000) * 2; // 30 km/h = 2 min/km
        }

        if (estimatedTimeMinutes < 1) {
          _estimatedArrival = "< 1 min";
        } else {
          _estimatedArrival = _formatDuration(estimatedTimeMinutes.round());
        }
      });

      String destinationType;
      if (_isMultiOrderMode) {
        if (_currentPhase == NavigationPhase.multiOrderPickups) {
          destinationType =
              "pickup ${_currentPickupIndex + 1}/${_allPickupLocations.length}";
        } else if (_currentPhase == NavigationPhase.multiOrderDeliveries) {
          destinationType =
              "delivery ${_currentDeliveryIndex + 1}/${_allDeliveryLocations.length}";
        } else {
          destinationType = _currentPhase == NavigationPhase.toPickup
              ? "pickup"
              : "delivery";
        }
      } else {
        destinationType = _currentPhase == NavigationPhase.toPickup
            ? "pickup"
            : "delivery";
      }

      // CRITICAL: Trigger UI update to check for arrived button after distance update
      if (mounted && _navigationStarted) {
        // Force a getCurrentInstruction call to trigger arrived button logic
        Timer(const Duration(milliseconds: 100), () {
          if (mounted) {
            _getCurrentInstruction(); // This will trigger arrived button check
          }
        });
        // Throttled Live Activity update with fresh distance/ETA
        _updateLiveActivity();
      }
    } else {
      // Not using GPS distance, but still check for arrived button
      if (mounted && _navigationStarted) {
        Timer(const Duration(milliseconds: 100), () {
          if (mounted) {
            _getCurrentInstruction(); // This will trigger arrived button check
          }
        });
      }
    }
  }

  void _centerMapOnRoute() {
    if (!mounted || _currentLocation == null) return;

    List<LatLng> allPoints = [];

    // Add current location
    allPoints.add(_currentLocation!);

    // Add route points if available
    if (_routePoints.isNotEmpty) {
      allPoints.addAll(_routePoints);
    } else {
      // No route yet - add destination based on current phase
      if (_isMultiOrderMode) {
        if (_currentPhase == NavigationPhase.multiOrderPickups &&
            _currentPickupIndex < _allPickupLocations.length) {
          allPoints.add(_allPickupLocations[_currentPickupIndex]);
        } else if (_currentPhase == NavigationPhase.multiOrderDeliveries &&
            _currentDeliveryIndex < _allDeliveryLocations.length) {
          allPoints.add(_allDeliveryLocations[_currentDeliveryIndex]);
        }
      } else {
        if (_currentPhase == NavigationPhase.toPickup) {
          allPoints.add(_pickupLocation);
        } else if (_currentPhase == NavigationPhase.toDelivery) {
          allPoints.add(_deliveryLocation);
        }
      }
    }

    // Validate all points have non-zero coordinates
    allPoints = allPoints
        .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
        .toList();

    if (allPoints.isEmpty) {
      print('⚠️ No valid points to center map on');
      return;
    }

    for (var point in allPoints) {
      print(
        '   Point: ${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}');
    }

    double minLat = allPoints.map((p) => p.latitude).reduce(math.min);
    double maxLat = allPoints.map((p) => p.latitude).reduce(math.max);
    double minLng = allPoints.map((p) => p.longitude).reduce(math.min);
    double maxLng = allPoints.map((p) => p.longitude).reduce(math.max);

    LatLng southwest = LatLng(minLat - 0.01, minLng - 0.01);
    LatLng northeast = LatLng(maxLat + 0.01, maxLng + 0.01);

    print(
      '🗺️ Map bounds: SW(${southwest.latitude}, ${southwest.longitude}) - NE(${northeast.latitude}, ${northeast.longitude})');

    try {
      // During active navigation, don't use fitCamera (it resets rotation)
      // Instead, just center on current location - rotation via setState
      if (_navigationStarted && _currentBearing != 0.0) {
        _mapController.move(_currentLocation!, 17.0);
      } else {
        // Before navigation starts, fit the whole route in view
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(southwest, northeast),
            padding: EdgeInsets.all(80)));
      }
    } catch (e) {}
  }

  /// Updates (or creates) the iOS Live Activity with the current navigation state.
  /// Pass [force] = true for phase changes and arrival events to bypass the 30-second throttle.
  void _updateLiveActivity({bool force = false}) {
    if (!mounted) return;
    final order = _currentOrder ?? widget.order;
    final orderNumber =
        '${order['order_id'] ?? order['id'] ?? AppLocalizations.of(context)!.tr('–')}';

    // Determine delivery phase
    final bool isDeliveryPhase =
        _currentPhase == NavigationPhase.toDelivery ||
        (_isMultiOrderMode &&
            _currentPhase == NavigationPhase.multiOrderDeliveries) ||
        (_currentPhase == NavigationPhase.atPickup &&
            (order['status']?.toString().toLowerCase() == 'picked_up'));

    String phase;
    if (_showQRScanner) {
      // QR scanner bottom sheet is open — driver is actively scanning
      phase = 'scanning';
    } else if (_scanPhase == 'loading') {
      // Between 1st and 2nd QR scan — goods being loaded / unloaded
      phase = isDeliveryPhase ? 'unloadingGoods' : 'loadingGoods';
    } else if (_waitingStartTime != null) {
      phase = isDeliveryPhase ? 'atDelivery' : 'atPickup';
    } else if (_currentPhase == NavigationPhase.toDelivery ||
        (_isMultiOrderMode &&
            _currentPhase == NavigationPhase.multiOrderDeliveries)) {
      phase = 'toDelivery';
    } else {
      phase = 'toPickup';
    }

    // Build destination address string
    String destAddr;
    if (isDeliveryPhase) {
      // Try to parse deliveryAddress object for proper city + country
      try {
        final raw = order['deliveryAddress'];
        final addr = raw is String ? json.decode(raw) : (raw is Map ? raw : null);
        if (addr != null) {
          final street = addr['street']?.toString().trim() ?? addr['address']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
          final city   = addr['city']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
          final country = addr['country']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
          final parts = [if (street.isNotEmpty) street, if (city.isNotEmpty) city, if (country.isNotEmpty) country];
          destAddr = parts.isNotEmpty ? parts.join(', ') : (order['delivery_address']?.toString() ?? AppLocalizations.of(context)!.tr('Lieferadresse'));
        } else {
          destAddr = order['delivery_address']?.toString() ?? AppLocalizations.of(context)!.tr('Lieferadresse');
        }
      } catch (_) {
        destAddr = order['delivery_address']?.toString() ?? AppLocalizations.of(context)!.tr('Lieferadresse');
      }
    } else {
      final street  = order['pickup_street']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
      final city    = order['pickup_city']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
      final country = order['pickup_country']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
      final parts   = [if (street.isNotEmpty) street, if (city.isNotEmpty) city, if (country.isNotEmpty) country];
      destAddr = parts.join(' ').trim();
    }

    final bool isActiveTimerPhase =
        _waitingStartTime != null || _scanPhase == 'loading';
    final int activeTimerSeconds =
        _scanPhase == 'loading' ? _loadingElapsedSeconds : _waitingElapsedSeconds;

    DelviooLiveActivityService.update(
      orderNumber: orderNumber,
      phase: phase,
      distanceText: _totalDistance,
      etaText: _estimatedArrival,
      destinationAddress: destAddr,
      isWaitingTimerActive: isActiveTimerPhase,
      waitingElapsedSeconds: activeTimerSeconds,
      force: force);
  }

  void _startNavigation() async {
    // CRITICAL: Save driver start location when navigation begins
    await _saveDriverStartLocation();

    setState(() {
      _navigationStarted = true;
      _currentInstructionIndex = 0;
    });

    // Update Live Activity when navigation starts
    _updateLiveActivity(force: true);

    // Generate route to show the path in modal (in-app navigation)
    _generateRoute();

    // Also open external map app if the user selected one
    if (_externalMapApp != 'none' && _currentLocation != null) {
      final dest = _getDestinationForCurrentPhase();
      await _launchExternalMapApp(
        origin: _currentLocation!,
        destination: dest,
        app: _externalMapApp);
    }

    // CRITICAL: Calculate initial bearing AFTER route is generated
    // Wait for route generation to complete
    await Future.delayed(const Duration(milliseconds: 500));

    if (_currentLocation != null && _routePoints.length >= 2) {
      // Calculate bearing to second point (first point is usually current location)
      _currentBearing = _calculateBearing(_currentLocation!, _routePoints[1]);
      print(
        '🧭 🔥 Navigation started - initial bearing: $_currentBearing° - ROTATING MAP NOW');

      // Apply rotation by forcing map rebuild with new rotation value
      try {
        print('🧭 🔥 Setting initial bearing: $_currentBearing°');

        // Center on current location
        _mapController.move(_currentLocation!, 17.0);

        // Force complete rebuild with new rotation via setState
        // The ValueKey on FlutterMap will force a complete rebuild
        if (mounted) {
          setState(() {
            // This triggers rebuild with new initialRotation value
          });
        }

        print(
          '✅ Map rebuilt with rotation: $_currentBearing° - route now points UP');
      } catch (e) {
        print('❌ Failed to rotate map: $e');
      }
    } else {
      print(
        '⚠️ Cannot calculate bearing: location=${_currentLocation != null}, points=${_routePoints.length}');
    }

    // CRITICAL: Save navigation state to database WITH await
    await _saveNavigationState();

    // Notify parent widget that navigation started
    if (widget.onNavigationStarted != null) {
      widget.onNavigationStarted!();
    }

    // Start haptic feedback for navigation start
    HapticFeedback.heavyImpact();

    // Auto-zoom to navigation view with rotation
    _zoomToNavigationView();
  }

  // Save driver start location when navigation begins
  Future<void> _saveDriverStartLocation() async {
    if (_currentLocation == null) {
      print('⚠️ Cannot save driver start location - GPS not available');
      return;
    }

    try {
      print(
        '📍 Saving driver start location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');

      final orderId = widget.order['order_id'] ?? widget.order['id'];

      // Calculate distance from driver start to pickup
      double distanceToPickup = 0.0;
      if (_isMultiOrderMode &&
          _currentPickupIndex < _allPickupLocations.length) {
        final pickupLocation = _allPickupLocations[_currentPickupIndex];
        distanceToPickup = _calculateDistance(
          _currentLocation!,
          pickupLocation);
      } else {
        distanceToPickup = _calculateDistance(
          _currentLocation!,
          _pickupLocation);
      }

      print(
        '📏 Distance from driver start to pickup: ${distanceToPickup.toStringAsFixed(1)} km');

      // Save to database
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/save-start-location'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'order_id': orderId,
          'driver_start_latitude': _currentLocation!.latitude,
          'driver_start_longitude': _currentLocation!.longitude,
          'distance_to_pickup': distanceToPickup,
          'timestamp': DateTime.now().toIso8601String(),
        }));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print(
            '   Distance to pickup: ${distanceToPickup.toStringAsFixed(1)} km');
        } else {
          print('⚠️ Failed to save driver start location: ${data['message']}');
        }
      } else {
        print('❌ Error saving driver start location: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Exception saving driver start location: $e');
    }
  }

  /// Returns the navigation destination LatLng based on the current phase.
  LatLng _getDestinationForCurrentPhase() {
    if (_isMultiOrderMode) {
      if (_currentPhase == NavigationPhase.multiOrderPickups &&
          _currentPickupIndex < _allPickupLocations.length) {
        return _allPickupLocations[_currentPickupIndex];
      }
      if (_currentPhase == NavigationPhase.multiOrderDeliveries &&
          _currentDeliveryIndex < _allDeliveryLocations.length) {
        return _allDeliveryLocations[_currentDeliveryIndex];
      }
    }
    return _currentPhase == NavigationPhase.toDelivery
        ? _deliveryLocation
        : _pickupLocation;
  }

  /// Opens the selected external map app for voice-guided navigation.
  Future<void> _launchExternalMapApp({
    required LatLng origin,
    required LatLng destination,
    required String app,
  }) async {
    try {
      Uri uri;
      final lat = destination.latitude;
      final lng = destination.longitude;

      // Use native deep-link schemes without an explicit origin so each map app
      // uses the device's own live GPS location as the starting point.
      switch (app) {
        case 'google':
          // Native Google Maps scheme → falls back to web URL if not installed
          final native = Uri.parse(
            'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
          if (await canLaunchUrl(native)) {
            await launchUrl(native, mode: LaunchMode.externalApplication);
            return;
          }
          uri = Uri.parse(
            'https://www.google.com/maps/dir/?api=1'
            '&destination=$lat,$lng'
            '&travelmode=driving');
          break;
        case 'waze':
          // Waze always navigates from current location
          uri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
          break;
        case 'apple':
          // Native Apple Maps scheme – no saddr = uses current GPS location
          uri = Uri.parse('maps://?daddr=$lat,$lng&dirflg=d');
          break;
        default:
          return;
      }

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.noNavigationAppAvailable ?? AppLocalizations.of(context)!.tr('App not available on this device'));
        }
      }
    } catch (e) {
      print('❌ Error launching external map app ($app): $e');
    }
  }

  /// Compact horizontal row of map-app selector chips shown in the bottom panel.
  /// Small pill button that shows the currently selected map app and opens the
  /// bottom sheet selector when tapped.
  Widget _buildMapAppButton(bool isLight) {
    const appLabels = {
      'none': 'In-App',
      'google': 'Google Maps',
      'waze': 'Waze',
      'apple': 'Apple Maps',
    };
    const appIcons = {
      'none': CupertinoIcons.map,
      'google': CupertinoIcons.map,
      'waze': CupertinoIcons.car_fill,
      'apple': CupertinoIcons.map, // replaced at runtime for iOS
    };
    final label = appLabels[_externalMapApp] ?? AppLocalizations.of(context)!.tr('In-App');
    final icon = _externalMapApp == 'apple'
        ? CupertinoIcons.map_fill
        : (appIcons[_externalMapApp] ?? CupertinoIcons.map);
    final color = isLight ? Colors.black54 : Colors.white70;

    return Align(
      alignment: Alignment.centerRight,
      child: TradeRepublicTap(
        onTap: _showMapAppSheet,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isLight
                ? Colors.black.withOpacity(0.08)
                : Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
              SizedBox(width: 3),
              Icon(CupertinoIcons.chevron_down, size: 14, color: color),
            ]))));
  }

  /// Checks which map apps are installed and shows a bottom sheet so the user
  /// can pick where the route should be opened.
  Future<void> _showMapAppSheet() async {
    final List<({String id, IconData icon, String label, Color color})> available = [
      (id: 'none', icon: CupertinoIcons.map, label: AppLocalizations.of(context)!.tr('In-App Navigation') ?? AppLocalizations.of(context)!.tr('In-App Navigation'), color: Colors.blue),
    ];

    // On iOS/macOS: canLaunchUrl requires LSApplicationQueriesSchemes in Info.plist.
    // Apple Maps is always present on Apple platforms – no check needed.
    if (Platform.isIOS || Platform.isMacOS) {
      available.add((
        id: 'apple',
        icon: CupertinoIcons.map_fill,
        label: AppLocalizations.of(context)!.tr('Apple Maps') ?? AppLocalizations.of(context)!.tr('Apple Maps'),
        color: Colors.grey.shade700));
    }
    if (await canLaunchUrl(Uri.parse('comgooglemaps://'))) {
      available.add((
        id: 'google',
        icon: CupertinoIcons.map,
        label: AppLocalizations.of(context)!.tr('Google Maps') ?? AppLocalizations.of(context)!.tr('Google Maps'),
        color: const Color(0xFF4285F4)));
    }
    if (await canLaunchUrl(Uri.parse('waze://'))) {
      available.add((
        id: 'waze',
        icon: CupertinoIcons.car_fill,
        label: AppLocalizations.of(context)!.tr('Waze') ?? AppLocalizations.of(context)!.tr('Waze'),
        color: const Color(0xFF33CCFF)));
    }

    if (!mounted) return;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Open route in...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87)),
          SizedBox(height: 8),
          ...available.map((app) {
            final selected = _externalMapApp == app.id;
            return TradeRepublicListTile(
              title: app.label,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: app.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
                child: Icon(app.icon, color: app.color, size: 22)),
              trailing: selected
                  ? Icon(CupertinoIcons.checkmark_circle_fill, color: app.color, size: 22)
                  : null,
              onTap: () async {
                setState(() => _externalMapApp = app.id);
                Navigator.pop(context);
                // Immediately open the chosen app with the current destination
                if (app.id != 'none' && _currentLocation != null) {
                  final dest = _getDestinationForCurrentPhase();
                  await _launchExternalMapApp(
                    origin: _currentLocation!,
                    destination: dest,
                    app: app.id);
                }
              });
          }),
          SizedBox(height: 8),
        ]));
  }

  // Launch native MapBox Navigation
  Future<void> _launchMapBoxNavigation({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      // Try Google Maps first (most reliable and shows route between buildings)
      final googleMapsUrl = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&travelmode=driving');

      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: Try Apple Maps
        final appleMapsUrl = Uri.parse(
          'https://maps.apple.com/?'
          'saddr=${origin.latitude},${origin.longitude}&'
          'daddr=${destination.latitude},${destination.longitude}&'
          'dirflg=d');

        print('⚠️ Google Maps not available, trying Apple Maps');

        if (await canLaunchUrl(appleMapsUrl)) {
          await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
        } else {
          print('❌ Cannot launch any navigation app');
          if (mounted) {
            TopNotification.error(context, AppLocalizations.of(context)?.noNavigationAppAvailable ?? AppLocalizations.of(context)!.tr('No navigation app available'));
          }
        }
      }
    } catch (e) {
      print('❌ Error launching Navigation: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.errorStartingNavigation ?? AppLocalizations.of(context)!.tr('Error starting navigation')}: $e');
      }
    }
  }

  Future<void> _saveNavigationState() async {
    try {
      final bool hasRecoverableState =
          _navigationStarted ||
          _waitingStartTime != null ||
          _loadingStartTime != null ||
          _showQRScanner ||
          _showQRDisplay ||
          _showSecurityCode ||
          _showArrivedButton ||
          _currentPhase != NavigationPhase.toPickup;

      // Skip only true pre-start preview states.
      if (!hasRecoverableState) {
        print('⏸️ No active navigation state - skipping database save');
        return;
      }

      final bool persistedNavigationStarted =
          _navigationStarted ||
          _waitingStartTime != null ||
          _loadingStartTime != null ||
          _currentPhase != NavigationPhase.toPickup;

      final sessionId = await _getSessionId();
        final driverId = await _getDriverId();
        final fallbackLocation =
          _currentPhase == NavigationPhase.toDelivery ||
            _currentPhase == NavigationPhase.multiOrderDeliveries
          ? _deliveryLocation
          : _pickupLocation;
        final saveLocation = _currentLocation ?? fallbackLocation;

      // Reduce route points to avoid payload size issues (max 100 points)
      List<LatLng> simplifiedRoute = _simplifyRouteForAPI(_routePoints);

      // API endpoint to save navigation state
      final String url = '${ApiConfig.baseUrl}/api/navigation/start';

      print(
        '☁️ ${_isMultiOrderMode ? (AppLocalizations.of(context)?.multiOrderLabel ?? AppLocalizations.of(context)!.tr('')) : (AppLocalizations.of(context)?.singleOrderLabel ?? AppLocalizations.of(context)!.tr(''))} navigation: saving to cloud database');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'order_id': sessionId,
          'driver_id': driverId,
          'current_phase': _currentPhase.toString(),
            'navigation_started': persistedNavigationStarted,
            'driver_started_driving': persistedNavigationStarted,
          'started_at': DateTime.now().toIso8601String(),
          'current_location': {
            'lat': saveLocation.latitude,
            'lng': saveLocation.longitude,
          },
          'pickup_location': {
            'lat': _pickupLocation.latitude,
            'lng': _pickupLocation.longitude,
          },
          'delivery_location': {
            'lat': _deliveryLocation.latitude,
            'lng': _deliveryLocation.longitude,
          },
          'current_instruction_index': _currentInstructionIndex,
          'route_points': simplifiedRoute
              .map((point) => {'lat': point.latitude, 'lng': point.longitude})
              .toList(),
          'route_instructions': _routeInstructions.length > 20
              ? _routeInstructions.take(20).toList()
              : _routeInstructions,
          'total_distance': _totalDistance,
          'estimated_arrival': _estimatedArrival,
          'navigation_mode': _navigationMode.toString(),
          'security_code': _securityCode,
          // Multi-order specific data (CRITICAL for progress persistence)
          'is_multi_order_mode': _isMultiOrderMode,
          'current_pickup_index': _currentPickupIndex,
          'current_delivery_index': _currentDeliveryIndex,
          'all_orders': _isMultiOrderMode ? _allOrders : [],
          'multi_order_session_id': _multiOrderSessionId,
          'show_security_code': _showSecurityCode,
          'show_arrived_button': _showArrivedButton,
          'current_order': _currentOrder,
          // Additional multi-order progress tracking
          'completed_deliveries': _completedDeliveries,
          // Timer / scan phase state for resumption
          'scan_phase': _scanPhase,
          'waiting_start_time': _waitingStartTime?.toIso8601String(),
          'waiting_elapsed_seconds': _waitingElapsedSeconds,
          'waiting_free_minutes': _waitingFreeMinutes,
          'waiting_rate_per_hour': _waitingRatePerHour,
          'total_waiting_charges': _totalWaitingCharges,
          'free_time_warning_shown': _freeTimeWarningShown,
          'free_time_expired_shown': _freeTimeExpiredShown,
          'loading_start_time': _loadingStartTime?.toIso8601String(),
          'loading_elapsed_seconds': _loadingElapsedSeconds,
          'seller_check_in_at': _sellerCheckInAt?.toIso8601String(),
          'seller_check_out_at': _sellerCheckOutAt?.toIso8601String(),
          'buyer_check_in_at': _buyerCheckInAt?.toIso8601String(),
          'buyer_check_out_at': _buyerCheckOutAt?.toIso8601String(),
        }));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          print(
            '✅ ${_isMultiOrderMode ? (AppLocalizations.of(context)?.multiOrderLabel ?? AppLocalizations.of(context)!.tr('')) : (AppLocalizations.of(context)?.singleOrderLabel ?? AppLocalizations.of(context)!.tr(''))} navigation saved to cloud database');
        }
      } else {
        print('⚠️ Failed to save navigation to cloud: ${response.statusCode}');
      }

      // Also save to local storage for immediate restoration
      await _saveNavigationStateToSharedPreferences();
    } catch (e) {
      print('❌ Error saving navigation to cloud: $e');
      // Fallback: Still save to local storage
      await _saveNavigationStateToSharedPreferences();
    }
  }

  Future<void> _checkAndLoadActiveNavigation() async {
    try {
      final driverId = await _getDriverId();
      print(
        '🔍 CRITICAL: Checking for active navigation to restore state immediately...');

      final String url = '${ApiConfig.baseUrl}/api/navigation/active/$driverId';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true &&
            responseData['navigation'] != null) {
          final navData = responseData['navigation'];
          final navOrderId = navData['order_id'];
          final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;

          print(
            '🔍 Active navigation found: order $navOrderId, current order: $orderId');

          // Check if this navigation is for our current order (exact match only)
          // Ignore old multi-order sessions that don't match the current single order
          if (navOrderId.toString() == orderId.toString()) {
            print(
              '✅ CRITICAL: Restoring navigation state immediately for matching order!');
          } else if (navOrderId.toString().contains('multi_order')) {
            // For multi-order sessions, check if current order is actually part of it
            final allOrders = navData['all_orders'] as List<dynamic>? ?? [];
            final hasCurrentOrder = allOrders.any(
              (order) =>
                  order['order_id'].toString() == orderId.toString() ||
                  order['id'].toString() == orderId.toString());

            if (hasCurrentOrder) {
              print(
                '✅ CRITICAL: Restoring valid multi-order navigation containing current order!');
            } else {
              print(
                '❌ Multi-order session does not contain current order $orderId - ignoring old session');
              return; // Exit early to avoid restoring invalid state
            }
          } else {
            print(
              '❌ Navigation order mismatch - not restoring (nav: $navOrderId, current: $orderId)');
            return; // Exit early to avoid restoring invalid state
          }

          // Only restore if we reach this point (valid navigation found)
          if (navOrderId.toString() == orderId.toString() ||
              (navOrderId.toString().contains('multi_order') &&
                  (navData['all_orders'] as List<dynamic>? ?? []).any(
                    (order) =>
                        order['order_id'].toString() == orderId.toString() ||
                        order['id'].toString() == orderId.toString()))) {
            setState(() {
              // Restore phase first
              final phaseString =
                  navData['current_phase'] ?? AppLocalizations.of(context)!.tr('NavigationPhase.toPickup');
              if (phaseString.contains('toDelivery')) {
                _currentPhase = NavigationPhase.toDelivery;
              } else if (phaseString.contains('atPickup')) {
                _currentPhase = NavigationPhase.atPickup;
              } else if (phaseString.contains('completed')) {
                _currentPhase = NavigationPhase.completed;
              } else if (phaseString.contains('multiOrderPickups')) {
                _currentPhase = NavigationPhase.multiOrderPickups;
              } else if (phaseString.contains('multiOrderDeliveries')) {
                _currentPhase = NavigationPhase.multiOrderDeliveries;
              } else {
                _currentPhase = NavigationPhase.toPickup;
              }

              // Restore navigation state
              _navigationStarted = navData['navigation_started'] ?? false;
              _navigationStateRestoredFromDB = true;

              print(
                '🔄 IMMEDIATE STATE RESTORATION: Phase=$_currentPhase, Started=$_navigationStarted');
            });
          }
        }
      }
    } catch (e) {
      print('❌ Error in immediate navigation check: $e');
    }
  }

  void _checkPreLoadedNavigationState() {
    // Check if navigation state was pre-loaded from parent component
    if (widget.order.containsKey('navigation_phase')) {
      final preLoadedPhase = widget.order['navigation_phase'];

      if (preLoadedPhase == 'NavigationPhase.toDelivery') {
        setState(() {
          _currentPhase = NavigationPhase.toDelivery;
          _navigationStarted = true;
          _navigationStateRestoredFromDB = true;
        });
        _updateLiveActivity(force: true);
      }
    }
  }

  Future<void> _loadNavigationState() async {
    try {
      final driverId = await _getDriverId();
      final sessionId = await _getSessionId();
      final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;

      // First try to load from local storage for immediate restoration
      await _loadQuickNavigationState();

      // Check for active navigation for this driver

      String url = '${ApiConfig.baseUrl}/api/navigation/active/$driverId';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print(
          '🔍 Navigation API response data: success=${responseData['success']}, hasNavigation=${responseData['navigation'] != null}');

        if (responseData['success'] == true &&
            responseData['navigation'] != null) {
          final navData = responseData['navigation'];
          final navOrderId = navData['order_id'];

          // Check if the order in navigation is still valid (not cancelled)
          final orderStatus = await _checkOrderStatus(navOrderId);
          if (orderStatus == 'cancelled') {
            // DISABLED: await _removeFromNavigation(navOrderId);
            // DISABLED: return;
          }

          // Check if multi-order data exists in navigation
          bool hasMultiOrderData =
              navData.containsKey('is_multi_order_mode') ||
              navData.containsKey('all_orders') ||
              navData.containsKey('current_pickup_index');

          // For multi-order navigation, check if the navigation order is in our batch OR restore multi-order state
          bool shouldRestoreNavigation = false;

          // CRITICAL: Check hasMultiOrderData FIRST before checking _isMultiOrderMode
          // because _isMultiOrderMode might not be set yet if batch_orders was missing
          if (hasMultiOrderData && navData['all_orders'] != null) {
            // Found existing multi-order navigation - check if our current order is part of it
            final navAllOrders = navData['all_orders'] as List? ?? [];

            // For multi-order, check if current order ID matches navigation order ID OR is part of all_orders
            if (navOrderId.toString() == orderId.toString()) {
              // Direct match - this IS the multi-order navigation
              shouldRestoreNavigation = true;
            } else {
              // Check if current order is one of the orders in the batch
              shouldRestoreNavigation = navAllOrders.any(
                (navOrder) =>
                    (navOrder['order_id'] ?? navOrder['id']) == orderId);
              print(
                '🔍 Checking if order $orderId is in batch: $shouldRestoreNavigation');
            }

            // If we should restore, update our local multi-order state NOW
            if (shouldRestoreNavigation) {
              _isMultiOrderMode = navData['is_multi_order_mode'] ?? true;
              _allOrders = List<Map<String, dynamic>>.from(navAllOrders);
              _extractAllLocations();
              print(
                '✅ Multi-order state pre-loaded: ${_allOrders.length} orders, ${_allPickupLocations.length} pickups, ${_allDeliveryLocations.length} deliveries');
            }
          } else if (_isMultiOrderMode && _allOrders.isNotEmpty) {
            // Check if any order in our batch matches the navigation order
            shouldRestoreNavigation = _allOrders.any(
              (order) => (order['order_id'] ?? order['id']) == navOrderId);
            print(
              '🔍 Checking if navOrderId $navOrderId is in our batch: $shouldRestoreNavigation');
          } else {
            // Single order mode - direct match (ensure both are strings for comparison)
            shouldRestoreNavigation =
                navOrderId.toString() == orderId.toString();
            print(
              '🔍 Single order comparison: navOrderId="$navOrderId" vs orderId="$orderId" -> $shouldRestoreNavigation');
          }

          print(
            '🔍 Navigation restoration check: navOrderId=$navOrderId, orderId=$orderId, shouldRestore=$shouldRestoreNavigation, isMultiOrder=$_isMultiOrderMode, hasMultiOrderData=$hasMultiOrderData');

          // Only restore state if this navigation belongs to our order(s)
          if (shouldRestoreNavigation) {
            print(
              '🔄 Restoring navigation state from Google Cloud database...');

            // CRITICAL: Determine phase BEFORE loading coordinates
            final phaseString =
                navData['current_phase'] ?? AppLocalizations.of(context)!.tr('NavigationPhase.toPickup');
            NavigationPhase restoredPhase = NavigationPhase.toPickup;
            if (phaseString.contains('toDelivery')) {
              restoredPhase = NavigationPhase.toDelivery;
            } else if (phaseString.contains('atPickup')) {
              restoredPhase = NavigationPhase.atPickup;
            } else if (phaseString.contains('completed')) {
              restoredPhase = NavigationPhase.completed;
            } else if (phaseString.contains('multiOrderPickups')) {
              restoredPhase = NavigationPhase.multiOrderPickups;
            } else if (phaseString.contains('multiOrderDeliveries')) {
              restoredPhase = NavigationPhase.multiOrderDeliveries;
            }

            // CRITICAL: ALWAYS reload fresh order data from Delvioo API to get delivery coordinates
            // This is needed for ALL phases, not just delivery phase
            print(
              '🔄 Reloading fresh order data from API to get delivery coordinates...');
            try {
              final response = await http.get(
                Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders'),
                headers: {'Content-Type': 'application/json'});

              if (response.statusCode == 200) {
                final List<dynamic> orders = jsonDecode(response.body);
                final freshOrder = orders.firstWhere(
                  (o) => (o['id'] ?? o['order_id']) == orderId,
                  orElse: () => null);

                if (freshOrder != null && freshOrder['delivery'] != null) {
                  final delivery = freshOrder['delivery'];
                  if (delivery['coordinates'] != null) {
                    final coords = delivery['coordinates'];
                    final lat =
                        double.tryParse(coords['lat']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                        0.0;
                    final lng =
                        double.tryParse(coords['lng']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                        0.0;

                    if (lat != 0.0 && lng != 0.0) {
                      _deliveryLocation = LatLng(lat, lng);
                      print(
                        '✅ Reloaded delivery coordinates from API: $lat, $lng');
                    } else {
                      print('⚠️ API returned 0.0 coordinates for delivery');
                    }
                  } else {
                    print('⚠️ API response missing delivery.coordinates');
                  }
                } else {
                  print('⚠️ Order $orderId not found in API response');
                }
              } else {
                print('⚠️ API returned status ${response.statusCode}');
              }
            } catch (e) {
              print('⚠️ Could not reload order data from API: $e');
            }

            if (mounted) {
              setState(() {
                // CRITICAL: If navigation was started before, keep it started when resuming
                // This prevents the "back to start" bug when closing and reopening navigation
                final wasNavigationStarted =
                    navData['navigation_started'] ?? false;
                final driverStartedDriving =
                    navData['driver_started_driving'] ?? false;

                // If driver already started driving OR navigation was previously started,
                // automatically resume navigation
                _navigationStarted =
                    wasNavigationStarted || driverStartedDriving;

                print('🚗 Navigation resume check:');
                print(
                  '   - Previous navigation_started: $wasNavigationStarted');
                print('   - Driver started driving: $driverStartedDriving');
                print('   - Resuming navigation: $_navigationStarted');

                _currentInstructionIndex =
                    navData['current_instruction_index'] ?? 0;
                _totalDistance = navData['total_distance'] ?? AppLocalizations.of(context)!.tr('Loading...');
                _estimatedArrival =
                    navData['estimated_arrival'] ?? AppLocalizations.of(context)!.tr('Loading...');

                // CRITICAL: First restore multi-order state before phase
                if (navData['is_multi_order_mode'] == true) {
                  _isMultiOrderMode = true;

                  // Restore multi-order progress indices
                  if (navData['current_pickup_index'] != null) {
                    final rawPickupIndex = navData['current_pickup_index'];
                    _currentPickupIndex = (rawPickupIndex is String)
                        ? int.parse(rawPickupIndex)
                        : (rawPickupIndex ?? 0);
                  }
                  if (navData['current_delivery_index'] != null) {
                    final rawDeliveryIndex = navData['current_delivery_index'];
                    _currentDeliveryIndex = (rawDeliveryIndex is String)
                        ? int.parse(rawDeliveryIndex)
                        : (rawDeliveryIndex ?? 0);
                  }

                  // Restore all orders
                  if (navData['all_orders'] != null) {
                    _allOrders = List<Map<String, dynamic>>.from(
                      navData['all_orders']);
                    _extractAllLocations(); // Rebuild location arrays
                  }

                  // Restore current order
                  if (navData['current_order'] != null) {
                    _currentOrder = Map<String, dynamic>.from(
                      navData['current_order']);
                  }

                  // Restore multi-order session ID
                  if (navData['multi_order_session_id'] != null) {
                    _multiOrderSessionId = navData['multi_order_session_id']
                        .toString();
                  }

                  print(
                    '✅ Multi-order state restored: pickup $_currentPickupIndex/${_allPickupLocations.length}, delivery $_currentDeliveryIndex/${_allDeliveryLocations.length}');
                }

                // Restore current phase - including multi-order phases
                final phaseString =
                    navData['current_phase'] ?? AppLocalizations.of(context)!.tr('NavigationPhase.toPickup');
                if (phaseString.contains('toDelivery')) {
                  _currentPhase = NavigationPhase.toDelivery;
                } else if (phaseString.contains('atPickup')) {
                  _currentPhase = NavigationPhase.atPickup;
                } else if (phaseString.contains('completed')) {
                  _currentPhase = NavigationPhase.completed;
                } else if (phaseString.contains('multiOrderPickups')) {
                  _currentPhase = NavigationPhase.multiOrderPickups;
                } else if (phaseString.contains('multiOrderDeliveries')) {
                  _currentPhase = NavigationPhase.multiOrderDeliveries;
                } else {
                  _currentPhase = NavigationPhase.toPickup;
                }

                // Mark that navigation state was successfully restored from database
                _navigationStateRestoredFromDB = true;

                // Restore navigation mode
                final modeString =
                    navData['navigation_mode'] ?? AppLocalizations.of(context)!.tr('NavigationMode.online');
                _navigationMode = modeString.contains('offline')
                    ? NavigationMode.offline
                    : NavigationMode.online;

                // Restore current location
                if (navData['current_location'] != null) {
                  final location = navData['current_location'];
                  final lat =
                      double.tryParse(location['lat']?.toString() ?? AppLocalizations.of(context)!.tr('')) ??
                      0.0;
                  final lng =
                      double.tryParse(location['lng']?.toString() ?? AppLocalizations.of(context)!.tr('')) ??
                      0.0;
                  if (lat != 0.0 || lng != 0.0) {
                    _currentLocation = LatLng(lat, lng);
                  }
                }

                // Restore route points
                if (navData['route_points'] != null &&
                    navData['route_points'] is List) {
                  _routePoints = (navData['route_points'] as List)
                      .map(
                        (point) => LatLng(
                          double.tryParse(point['lat'].toString()) ?? 0.0,
                          double.tryParse(point['lng'].toString()) ?? 0.0))
                      .toList();
                  if (_routePoints.isNotEmpty) {
                    _generateTrafficColors();
                  }
                }

                // Restore security code
                if (navData['security_code'] != null) {
                  _securityCode = navData['security_code'].toString();
                }

                // Restore multi-order state from backend response

                if (navData['is_multi_order_mode'] != null) {
                  _isMultiOrderMode = navData['is_multi_order_mode'] ?? false;
                }
                if (navData['current_pickup_index'] != null) {
                  final oldPickupIndex = _currentPickupIndex;
                  final rawPickupIndex = navData['current_pickup_index'];
                  _currentPickupIndex = (rawPickupIndex is String)
                      ? int.parse(rawPickupIndex)
                      : (rawPickupIndex ?? 0);
                } else {}
                if (navData['current_delivery_index'] != null) {
                  final oldDeliveryIndex = _currentDeliveryIndex;
                  final rawDeliveryIndex = navData['current_delivery_index'];
                  _currentDeliveryIndex = (rawDeliveryIndex is String)
                      ? int.parse(rawDeliveryIndex)
                      : (rawDeliveryIndex ?? 0);
                } else {}
                if (navData['all_orders'] != null) {
                  _allOrders = List<Map<String, dynamic>>.from(
                    navData['all_orders']);
                  _extractAllLocations(); // Rebuild location arrays
                }
                if (navData['current_order'] != null) {
                  _currentOrder = Map<String, dynamic>.from(
                    navData['current_order']);
                }

                // If multi-order data not found directly, check if it's nested
                if (!_isMultiOrderMode &&
                    navData.containsKey('multi_order_data')) {
                  // Check if multi_order_data is a string (JSON) or already parsed
                  dynamic multiOrderData = navData['multi_order_data'];
                  if (multiOrderData is String) {
                    try {
                      multiOrderData = jsonDecode(multiOrderData);
                    } catch (e) {
                      multiOrderData = null;
                    }
                  }

                  if (multiOrderData != null && multiOrderData is Map) {
                    _isMultiOrderMode =
                        multiOrderData['is_multi_order_mode'] ?? false;
                    final rawPickupIndex =
                        multiOrderData['current_pickup_index'];
                    _currentPickupIndex = (rawPickupIndex is String)
                        ? int.parse(rawPickupIndex)
                        : (rawPickupIndex ?? 0);
                    final rawDeliveryIndex =
                        multiOrderData['current_delivery_index'];
                    _currentDeliveryIndex = (rawDeliveryIndex is String)
                        ? int.parse(rawDeliveryIndex)
                        : (rawDeliveryIndex ?? 0);

                    if (multiOrderData['all_orders'] != null) {
                      _allOrders = List<Map<String, dynamic>>.from(
                        multiOrderData['all_orders']);
                      _extractAllLocations();
                    }

                    if (multiOrderData['current_order'] != null) {
                      _currentOrder = Map<String, dynamic>.from(
                        multiOrderData['current_order']);
                    }
                  }
                }

                // Restore UI states for resumed navigation
                if (navData['show_security_code'] != null) {
                  _showSecurityCode = navData['show_security_code'] ?? false;
                }
                if (navData['show_arrived_button'] != null) {
                  _showArrivedButton = navData['show_arrived_button'] ?? false;
                }

                // Determine appropriate UI state based on phase
                if (_currentPhase == NavigationPhase.atPickup ||
                    (_isMultiOrderMode &&
                        _currentPhase == NavigationPhase.multiOrderPickups &&
                        _showSecurityCode)) {
                  _showSecurityCode = true;
                  _showArrivedButton = false;
                } else if (_currentPhase == NavigationPhase.toPickup ||
                    (_isMultiOrderMode &&
                        _currentPhase == NavigationPhase.multiOrderPickups)) {
                  // Check if we should show arrived button based on proximity
                  if (_isMultiOrderMode &&
                      _currentPickupIndex < _allPickupLocations.length) {
                    final destination =
                        _allPickupLocations[_currentPickupIndex];
                    final distance = _calculateDistance(
                      _currentLocation!,
                      destination);
                    if (distance < 5000) {
                      // Within 5km
                      _showArrivedButton = true;
                      _showSecurityCode = false;
                    }
                  }
                }

                // Restore the delivery phase states
                if (navData['show_arrived_button'] != null) {
                  _showArrivedButton = navData['show_arrived_button'] ?? false;
                }
                if (navData['show_security_code'] != null) {
                  _showSecurityCode = navData['show_security_code'] ?? false;
                }

                // Restore scan phase, timers, and check-in/out timestamps
                _restoreTimerState(navData);
                _restoreActiveScanSheetIfNeeded();

                // CRITICAL FIX: Update _pickupLocation and _deliveryLocation from restored _currentOrder
                // This prevents the bug where delivery location is shown as pickup after modal reopen
                if (_currentOrder != null) {
                  print('🔄 Updating coordinates from restored _currentOrder');

                  // Extract pickup coordinates from current order
                  if (_currentOrder!.containsKey('pickup_lat') &&
                      _currentOrder!['pickup_lat'] != null &&
                      _currentOrder!.containsKey('pickup_lng') &&
                      _currentOrder!['pickup_lng'] != null) {
                    final pickupLat =
                        double.tryParse(
                          _currentOrder!['pickup_lat'].toString()) ??
                        0.0;
                    final pickupLng =
                        double.tryParse(
                          _currentOrder!['pickup_lng'].toString()) ??
                        0.0;
                    if (pickupLat != 0.0 && pickupLng != 0.0) {
                      _pickupLocation = LatLng(pickupLat, pickupLng);
                      print('   📍 Restored pickup: $pickupLat, $pickupLng');
                    }
                  }

                  // Extract delivery coordinates from current order
                  double deliveryLat = 0.0;
                  double deliveryLng = 0.0;

                  // Try delivery_lat/delivery_lng first
                  if (_currentOrder!.containsKey('delivery_lat') &&
                      _currentOrder!['delivery_lat'] != null) {
                    deliveryLat =
                        double.tryParse(
                          _currentOrder!['delivery_lat'].toString()) ??
                        0.0;
                  }
                  if (_currentOrder!.containsKey('delivery_lng') &&
                      _currentOrder!['delivery_lng'] != null) {
                    deliveryLng =
                        double.tryParse(
                          _currentOrder!['delivery_lng'].toString()) ??
                        0.0;
                  }

                  // Try delivery.coordinates if not found
                  if ((deliveryLat == 0.0 || deliveryLng == 0.0) &&
                      _currentOrder!.containsKey('delivery')) {
                    final delivery = _currentOrder!['delivery'];
                    if (delivery is Map &&
                        delivery.containsKey('coordinates')) {
                      final coords = delivery['coordinates'];
                      if (coords is Map) {
                        deliveryLat =
                            double.tryParse(
                              coords['lat']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                            0.0;
                        deliveryLng =
                            double.tryParse(
                              coords['lng']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                            0.0;
                      }
                    }
                  }

                  // Try deliveryAddress if still not found
                  if ((deliveryLat == 0.0 || deliveryLng == 0.0) &&
                      _currentOrder!.containsKey('deliveryAddress')) {
                    final deliveryAddress = _currentOrder!['deliveryAddress'];
                    if (deliveryAddress is Map) {
                      deliveryLat =
                          double.tryParse(
                            deliveryAddress['lat']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                          0.0;
                      deliveryLng =
                          double.tryParse(
                            deliveryAddress['lng']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                          0.0;
                    } else if (deliveryAddress is String) {
                      try {
                        final parsed = json.decode(deliveryAddress);
                        if (parsed is Map) {
                          deliveryLat =
                              double.tryParse(
                                parsed['lat']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                              0.0;
                          deliveryLng =
                              double.tryParse(
                                parsed['lng']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                              0.0;
                        }
                      } catch (e) {
                        print('⚠️ Error parsing deliveryAddress: $e');
                      }
                    }
                  }

                  if (deliveryLat != 0.0 && deliveryLng != 0.0) {
                    _deliveryLocation = LatLng(deliveryLat, deliveryLng);
                    print(
                      '   📍 Restored delivery: $deliveryLat, $deliveryLng');
                  }
                }

                // CRITICAL: For multi-order mode, also update from _allDeliveryLocations array
                if (_isMultiOrderMode &&
                    _currentDeliveryIndex < _allDeliveryLocations.length) {
                  _deliveryLocation =
                      _allDeliveryLocations[_currentDeliveryIndex];
                  print(
                    '   📍 Multi-order delivery from array: ${_deliveryLocation.latitude}, ${_deliveryLocation.longitude}');
                }
                if (_isMultiOrderMode &&
                    _currentPickupIndex < _allPickupLocations.length) {
                  _pickupLocation = _allPickupLocations[_currentPickupIndex];
                  print(
                    '   📍 Multi-order pickup from array: ${_pickupLocation.latitude}, ${_pickupLocation.longitude}');
                }
              });

              // CRITICAL: Force UI update after restoring navigation state
              print(
                '🔄 Force updating UI components after navigation state restoration...');

              // CRITICAL: Mark that navigation state was successfully restored for ANY navigation phase
              _navigationStateRestoredFromDB = true;
              print(
                '✅ Navigation state restored from database - Phase: $_currentPhase, Started: $_navigationStarted');

              // Restore active scan sheet for pickup/delivery if a scan flow is in progress.
              _restoreActiveScanSheetIfNeeded();

              // Force update distance and time displays for correct UI
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    // Force complete UI rebuild to show correct phase text and navigation state
                    _updateCurrentDistanceAndTime();
                    print(
                      '✅ UI components fully updated after navigation restoration - Phase: $_currentPhase, NavigationStarted: $_navigationStarted');
                  });
                  // Update Live Activity if navigation was restored as active
                  if (_navigationStarted) _updateLiveActivity(force: true);
                }
              });

              // CRITICAL: Reload fresh order data from Delvioo API BEFORE updating UI
              final orderId = widget.order['order_id'] ?? widget.order['id'];
              if (orderId != null &&
                  _currentPhase == NavigationPhase.toDelivery) {
                print(
                  '🔄 Reloading fresh order data from API to get delivery coordinates...');
                try {
                  final response = await http.get(
                    Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders'),
                    headers: {'Content-Type': 'application/json'});

                  if (response.statusCode == 200) {
                    final List<dynamic> orders = jsonDecode(response.body);
                    final freshOrder = orders.firstWhere(
                      (o) => (o['id'] ?? o['order_id']) == orderId,
                      orElse: () => null);

                    if (freshOrder != null && freshOrder['delivery'] != null) {
                      final delivery = freshOrder['delivery'];
                      if (delivery['coordinates'] != null) {
                        final coords = delivery['coordinates'];
                        final lat =
                            double.tryParse(
                              coords['lat']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                            0.0;
                        final lng =
                            double.tryParse(
                              coords['lng']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ??
                            0.0;

                        if (lat != 0.0 && lng != 0.0) {
                          _deliveryLocation = LatLng(lat, lng);
                          print(
                            '✅ Reloaded delivery coordinates from API: $lat, $lng');
                        } else {
                          print('⚠️ API returned 0.0 coordinates');
                        }
                      }
                    }
                  }
                } catch (e) {
                  print('⚠️ Could not reload order data from API: $e');
                }
              }

              // If navigation was started or completed, restore the route and zoom appropriately
              // CRITICAL: Also regenerate route for toPickup phase to show correct preview
              if (_navigationStarted ||
                  _currentPhase == NavigationPhase.completed ||
                  _currentPhase == NavigationPhase.toPickup ||
                  _currentPhase == NavigationPhase.toDelivery) {
                // IMPORTANT: Always regenerate route based on current phase and position
                // Use addPostFrameCallback to ensure coordinates are fully restored before route generation
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    print(
                      '🗺️ Regenerating route after state restoration - Phase: $_currentPhase');
                    print(
                      '   Pickup: ${_pickupLocation.latitude}, ${_pickupLocation.longitude}');
                    print(
                      '   Delivery: ${_deliveryLocation.latitude}, ${_deliveryLocation.longitude}');
                    _generateRoute();
                  }
                });

                // For completed navigation, show the full route; for active navigation, zoom to current location
                Timer(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    if (_currentPhase == NavigationPhase.completed) {
                      // Show the full completed route
                      if (_routePoints.isNotEmpty) {
                        _centerMapOnRoute();
                      }
                    } else {
                      // Active navigation - zoom to current location
                      if (_currentLocation != null) {
                        _mapController.move(_currentLocation!, 17.0);
                      }
                    }
                  }
                });
              }
            }
          } else {
            print(
              '❌ Navigation NOT restored - order mismatch or condition not met');
          }
        } else {
          print('❌ No navigation data found in response');
        }
      } else {}
    } catch (e) {}

    // CRITICAL: Force final UI update after all navigation loading is complete
    if (mounted) {
      setState(() {
        print(
          '🎯 Final UI update after _loadNavigationState - Phase: $_currentPhase, Started: $_navigationStarted, RestoredFromDB: $_navigationStateRestoredFromDB');
      });
    }

    // IMPORTANT: Load security code for the current order after state restoration
    print('🔐 Loading security code after navigation state restoration...');
    await _loadSecurityCodeFromDatabase();

    // Note: Do NOT reset _navigationStateRestoredFromDB flag here
    // It needs to stay active to protect against phase overrides
  }

  Future<void> _loadQuickNavigationState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateJson = prefs.getString('quick_navigation_state');

      if (stateJson != null) {
        final stateData = jsonDecode(stateJson) as Map<String, dynamic>;
        final currentOrderId =
            widget.order['order_id'] ?? widget.order['id'] ?? 0;

        // Check if this quick state is for our current order or multi-order batch
        final stateOrderId = stateData['current_order_id'];
        final isMultiOrder = stateData['is_multi_order_mode'] ?? false;

        bool isRelevantState = false;

        if (isMultiOrder && stateData['all_orders'] != null) {
          final allOrders = List<Map<String, dynamic>>.from(
            stateData['all_orders']);
          isRelevantState = allOrders.any(
            (order) => (order['order_id'] ?? order['id']) == currentOrderId);
        } else {
          isRelevantState = stateOrderId == currentOrderId;
        }

        if (isRelevantState) {
          setState(() {
            // CRITICAL: Restore _navigationStarted immediately so "Tap Go" never
            // flashes on screen when resuming an already-started navigation.
            _navigationStarted = stateData['navigation_active'] ?? false;
            _showSecurityCode = stateData['show_security_code'] ?? false;
            _showArrivedButton = stateData['show_arrived_button'] ?? false;
            _securityCode = stateData['security_code'] ?? AppLocalizations.of(context)!.tr('');

            if (isMultiOrder) {
              _isMultiOrderMode = true;
              final rawPickupIndex = stateData['current_pickup_index'];
              _currentPickupIndex = (rawPickupIndex is String)
                  ? int.parse(rawPickupIndex)
                  : (rawPickupIndex ?? 0);
              final rawDeliveryIndex = stateData['current_delivery_index'];
              _currentDeliveryIndex = (rawDeliveryIndex is String)
                  ? int.parse(rawDeliveryIndex)
                  : (rawDeliveryIndex ?? 0);

              if (stateData['all_orders'] != null) {
                _allOrders = List<Map<String, dynamic>>.from(
                  stateData['all_orders']);
                _extractAllLocations();
              }

              if (stateData['current_order'] != null) {
                _currentOrder = Map<String, dynamic>.from(
                  stateData['current_order']);
              }
            }

            // Restore scan phase and timer state
            _restoreTimerState(stateData);
            _restoreActiveScanSheetIfNeeded();
          });
          // Update Live Activity if navigation was restored as active
          if (_navigationStarted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _updateLiveActivity(force: true);
            });
          }
        }
      }
    } catch (e) {}
  }

  /// Restores scan phase, waiting/loading timers, and check-in/out timestamps
  /// from a saved state map, then resumes the active timer.
  void _restoreTimerState(Map<String, dynamic> data) {
    // Restore scan phase
    final savedPhase = data['scan_phase'];
    if (savedPhase != null && savedPhase is String && savedPhase.isNotEmpty) {
      _scanPhase = savedPhase;
    }

    // Restore check-in / check-out timestamps
    if (data['seller_check_in_at'] != null) {
      _sellerCheckInAt = DateTime.tryParse(data['seller_check_in_at'].toString());
    }
    if (data['seller_check_out_at'] != null) {
      _sellerCheckOutAt = DateTime.tryParse(data['seller_check_out_at'].toString());
    }
    if (data['buyer_check_in_at'] != null) {
      _buyerCheckInAt = DateTime.tryParse(data['buyer_check_in_at'].toString());
    }
    if (data['buyer_check_out_at'] != null) {
      _buyerCheckOutAt = DateTime.tryParse(data['buyer_check_out_at'].toString());
    }

    // Restore waiting settings
    if (data['waiting_free_minutes'] != null) {
      _waitingFreeMinutes = (data['waiting_free_minutes'] as num).toInt();
    }
    if (data['waiting_rate_per_hour'] != null) {
      _waitingRatePerHour = (data['waiting_rate_per_hour'] as num).toDouble();
    }
    _freeTimeWarningShown = data['free_time_warning_shown'] ?? false;
    _freeTimeExpiredShown = data['free_time_expired_shown'] ?? false;
    _totalWaitingCharges = (data['total_waiting_charges'] as num?)?.toDouble() ?? 0.0;

    // Restore waiting timer state and resume if active
    if (data['waiting_start_time'] != null) {
      _waitingStartTime = DateTime.tryParse(data['waiting_start_time'].toString());
    }
    final savedWaitingSec = (data['waiting_elapsed_seconds'] as num?)?.toInt() ?? 0;

    // Restore loading timer state
    if (data['loading_start_time'] != null) {
      _loadingStartTime = DateTime.tryParse(data['loading_start_time'].toString());
    }
    final savedLoadingSec = (data['loading_elapsed_seconds'] as num?)?.toInt() ?? 0;

    // Resume the correct timer based on scan phase
    if (_scanPhase == 'waiting' && _waitingStartTime != null) {
      // Waiting timer was active — recalculate elapsed from real time
      final elapsed = DateTime.now().difference(_waitingStartTime!).inSeconds;
      _waitingElapsedSeconds = elapsed;
      _calculateWaitingCharges();
      // Restart the periodic timer
      _waitingTimer?.cancel();
      _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        setState(() {
          _waitingElapsedSeconds++;
          _calculateWaitingCharges();
          // Free time warnings
          final freeTimeSec = _waitingFreeMinutes * 60;
          if (!_freeTimeWarningShown && _waitingElapsedSeconds >= freeTimeSec - 300 && _waitingElapsedSeconds < freeTimeSec) {
            _freeTimeWarningShown = true;
            _showWaitingTimeWarning();
          }
          if (!_freeTimeExpiredShown && _waitingElapsedSeconds >= freeTimeSec) {
            _freeTimeExpiredShown = true;
            if (!_restoreSheetShown) {
              _restoreSheetShown = true;
              _showFreeTimeExpiredNotification();
            }
          }
        });

        final bool forceOnMinute = _waitingElapsedSeconds % 60 == 0;
        _updateLiveActivity(force: forceOnMinute);
      });
      print('🔄 Waiting timer resumed — elapsed: ${_formatWaitingTime(_waitingElapsedSeconds)}');
    } else if (_scanPhase == 'loading' && _loadingStartTime != null) {
      // Loading timer was active — recalculate elapsed from real time
      final elapsed = DateTime.now().difference(_loadingStartTime!).inSeconds;
      _loadingElapsedSeconds = elapsed;
      // Also restore final waiting data (waiting is done at this point)
      _waitingElapsedSeconds = savedWaitingSec;
      _calculateWaitingCharges();
      // Restart the periodic timer
      _loadingTimer?.cancel();
      _loadingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        setState(() { _loadingElapsedSeconds++; });

        final bool forceOnMinute = _loadingElapsedSeconds % 60 == 0;
        _updateLiveActivity(force: forceOnMinute);
      });
      print('🔄 Loading timer resumed — elapsed: ${_formatWaitingTime(_loadingElapsedSeconds)}');
    } else if (_scanPhase == 'done') {
      // Both phases complete — just restore the final values
      _waitingElapsedSeconds = savedWaitingSec;
      _loadingElapsedSeconds = savedLoadingSec;
      _calculateWaitingCharges();
      print('🔄 Timers restored (both complete) — waiting: ${_formatWaitingTime(_waitingElapsedSeconds)}, loading: ${_formatWaitingTime(_loadingElapsedSeconds)}');
    }
  }

  // Restore pickup/delivery scan sheet when reopening navigation during active scan flow.
  // This covers states like "Buyer must scan QR code" where timers are active
  // but the bottom sheet might not be visible after modal reopen.
  void _restoreActiveScanSheetIfNeeded() {
    if (!mounted) return;
    if (_restoreScanSheetScheduled) return;

    final bool hasActiveScanFlow =
        (_scanPhase == 'waiting' || _scanPhase == 'loading') &&
        (_waitingStartTime != null || _loadingStartTime != null);

    if (!hasActiveScanFlow) return;
    if (_showQRScanner || _isPickupSheetOpen || _isDeliverySheetOpen) return;

    final bool isDeliveryPhase =
        _currentPhase == NavigationPhase.toDelivery ||
        (_isMultiOrderMode && _currentPhase == NavigationPhase.multiOrderDeliveries);

    final bool isPickupPhase =
        _currentPhase == NavigationPhase.atPickup ||
        _currentPhase == NavigationPhase.toPickup ||
        (_isMultiOrderMode && _currentPhase == NavigationPhase.multiOrderPickups);

    if (!isDeliveryPhase && !isPickupPhase) return;

    _restoreScanSheetScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      print(
        '🔁 Restoring active scan sheet: ${isDeliveryPhase ? "delivery" : "pickup"} (phase=$_currentPhase, scanPhase=$_scanPhase)');

      if (isDeliveryPhase) {
        _showDeliveryBottomSheet();
      } else {
        _showPickupBottomSheet();
      }
    });
  }

  Future<String?> _checkOrderStatus(dynamic orderId) async {
    try {
      final String url =
          '${ApiConfig.baseUrl}/api/delvioo/driver-acceptances/1'; // Driver ID 1

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['acceptances'] != null) {
          final acceptances = List<Map<String, dynamic>>.from(
            data['acceptances']);

          for (var acceptance in acceptances) {
            final acceptanceOrderId =
                acceptance['order_id'] ?? acceptance['id'];
            if (acceptanceOrderId.toString() == orderId.toString()) {
              final status =
                  acceptance['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('unknown');

              // CRITICAL: Synchronize UI with database status
              _synchronizeUIWithDatabaseStatus(status);

              return status;
            }
          }

          // Order not found in accepted orders - DON'T assume cancelled
          return null; // Changed from 'cancelled' to null
        } else {}
      } else {}

      return null;
    } catch (e) {
      return null;
    }
  }

  void _synchronizeUIWithDatabaseStatus(String status) {
    print(
      '🔄 Synchronizing UI with database status: $status, current phase: $_currentPhase');

    if (status == 'picked_up' &&
        (_currentPhase == NavigationPhase.toPickup ||
            _currentPhase == NavigationPhase.atPickup)) {
      print(
        '🔄 Status is picked_up but UI shows pickup phase - switching to delivery');
      setState(() {
        _currentPhase = NavigationPhase.toDelivery;
        _navigationStarted = true;
        _showArrivedButton = false;
        _showSecurityCode = false;
        _showQRScanner = false;
      });

      // Update Live Activity to reflect the new delivery phase
      _updateLiveActivity(force: true);

      // Force UI refresh
      Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          _updateCurrentDistanceAndTime();
          _getCurrentInstruction();
        }
      });
    } else if (status == 'delivered' &&
        _currentPhase != NavigationPhase.completed) {
      print(
        '✅ Status is DELIVERED - checking if more deliveries in multi-order mode');

      // CRITICAL: Check if we're in multi-order mode and have more deliveries
      if (_isMultiOrderMode &&
          _currentDeliveryIndex + 1 < _allDeliveryLocations.length) {
        print(
          '🚚 Multi-order mode: Proceeding to next delivery (${_currentDeliveryIndex + 1} of ${_allDeliveryLocations.length})');

        // Save multi-order delivery completion to backend BEFORE advancing index
        _saveMultiOrderDeliveryCompletion();

        // Track completed delivery
        if (_currentDeliveryIndex < _allOrders.length) {
          _completedDeliveries.add(Map<String, dynamic>.from(_allOrders[_currentDeliveryIndex]));
        }

        // Use _proceedToNextDelivery which properly resets timer/check-in state
        _proceedToNextDelivery();

        // Show success message
        if (mounted) {
          TopNotification.success(
            context,
            AppLocalizations.of(context)!.tr('✅ Delivery completed! Proceeding to next delivery...') ?? AppLocalizations.of(context)!.tr('✅ Delivery completed! Proceeding to next delivery...'));
        }

        return; // Don't complete navigation yet
      }

      // All deliveries completed - end navigation
      setState(() {
        _currentPhase = NavigationPhase.completed;
        _navigationStarted = false;
        _showArrivedButton = false;
        _showSecurityCode = false;
        _showQRScanner = false;
        _showQRDisplay = false;
      });

      // Trigger beautiful completion animation
      _triggerCompletionAnimation();

      // Notify parent that navigation is completed
      if (widget.onNavigationCompleted != null) {
        widget.onNavigationCompleted!();
      }

      // Auto-close navigation after 2 seconds
      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          print('🚪 Auto-closing navigation - all deliveries completed');
          Navigator.pop(context);
        }
      });
    }
  }

  void _closeNavigation(BuildContext context) {
    // Prevent multiple simultaneous close operations
    if (_isClosingNavigation) {
      print(
        '⚠️ Close navigation already in progress - ignoring duplicate call');
      return;
    }

    _isClosingNavigation = true;
    print('🚪 Closing navigation - saving current state for later resumption');
    print('   Current Phase: $_currentPhase');
    print('   Navigation Started: $_navigationStarted');
    print(
      '   Pickup Index: $_currentPickupIndex/${_allPickupLocations.length}');
    print(
      '   Delivery Index: $_currentDeliveryIndex/${_allDeliveryLocations.length}');

    // CRITICAL: Save running timer progress to orders table
    // so even if the app is killed, the orders table has the latest elapsed time
    final closePhase = (_currentPhase == NavigationPhase.toDelivery ||
        _currentPhase == NavigationPhase.multiOrderDeliveries) ? 'buyer' : 'seller';
    if (_scanPhase == 'waiting' && _waitingStartTime != null) {
      _saveWaitingStartToOrder(phase: closePhase);
    } else if (_scanPhase == 'loading' && _loadingStartTime != null) {
      // Save progress only (no end time) — loading is still in progress
      _saveLoadingProgressToOrder(phase: closePhase);
    }

    // Save navigation state FIRST before closing
    _saveNavigationState()
        .then((_) {
          return _saveNavigationStateToSharedPreferences();
        })
        .then((_) {
          // Now close the modal if context is still valid and mounted
          if (mounted && context.mounted) {
            Navigator.of(context).pop();
          }

          // Reset flag after successful close
          _isClosingNavigation = false;
        })
        .catchError((error) {
          print('⚠️ Could not save navigation state: $error');

          // Still try to close even if save failed
          if (mounted && context.mounted) {
            Navigator.of(context).pop();
          }

          // Reset flag even on error
          _isClosingNavigation = false;
        });
  }

  Future<void> _completeNavigationAndCleanup() async {
    try {
      print(
        '🧹 Starting complete navigation cleanup for new multi-order preparation...');

      // 1. Mark all orders in this navigation as delivered
      await _markOrdersAsDelivered();

      // 2. Clear ALL navigation sessions from backend (not just current)
      await _clearAllNavigationSessions();

      // 3. Reset ALL local navigation data completely
      await _resetAllNavigationDataForNewMultiOrder();

      // 4. Clear database navigation sessions for ALL drivers to prevent conflicts
      await _clearAllDriverNavigationSessions();

      // 5. Reset internal state completely for new multi-order capability
      _performCompleteStateReset();

      // 6. End Live Activity — navigation is fully complete
      await DelviooLiveActivityService.end();

      // 7. Notify parent widget that navigation is completed
      if (widget.onNavigationCompleted != null) {
        widget.onNavigationCompleted!();
      }

      print(
        '✅ Complete navigation cleanup finished - ready for new multi-orders');
    } catch (e) {}
  }

  Future<void> _markOrdersAsDelivered() async {
    try {
      // Collect all order IDs from this navigation
      List<dynamic> orderIds = [];

      if (_isMultiOrderMode) {
        // Multi-order: get all order IDs
        for (var order in _allOrders) {
          final orderId = order['order_id'] ?? order['id'];
          if (orderId != null) {
            orderIds.add(orderId);
          }
        }
      } else {
        // Single order: get current order ID
        final orderId = widget.order['order_id'] ?? widget.order['id'];
        if (orderId != null) {
          orderIds.add(orderId);
        }
      }

      // Mark each order as delivered in the backend
      for (var orderId in orderIds) {
        try {
          final response = await http.post(
            Uri.parse(
              '${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/mark-delivered'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'driver_id': 1,
              'delivered_at': DateTime.now().toIso8601String(),
              'delivery_notes': 'Completed via navigation system',
            }));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success'] == true) {}
          }
        } catch (e) {}
      }
    } catch (e) {}
  }

  Future<void> _clearNavigationSession() async {
    try {
      final sessionId = await _getSessionId();

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/navigation/clear/$sessionId'),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {}
    } catch (e) {}
  }

  Future<void> _clearLocalNavigationData() async {
    try {
      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('multi_order_session_id');
      await prefs.remove('navigation_state');

      // Reset local state
      if (mounted) {
        setState(() {
          _navigationStarted = false;
          _showArrivedButton = false;
          _showSecurityCode = false;
          _showQRScanner = false;
          _showQRDisplay = false;
        });
      }
    } catch (e) {}
  }

  void _zoomToNavigationView() {
    // Zoom to current location for navigation
    Timer(const Duration(milliseconds: 500), () {
      if (mounted && _currentLocation != null) {
        // Apply rotation for heading-up mode when navigation starts
        // Rotation happens via setState in _startNavigation
        _mapController.move(_currentLocation!, 17.0);
      }
    });
  }

  double _calculateDistanceToNextManeuver() {
    if (_routePoints.isEmpty || _currentLocation == null) {
      return 0.0;
    }

    // Find the next route point from current location
    LatLng? nextPoint;

    // If we have route points, find the closest one ahead of us
    if (_routePoints.isNotEmpty) {
      double minDistance = double.infinity;
      for (int i = 0; i < _routePoints.length; i++) {
        double distance = _calculateDistance(
          _currentLocation!,
          _routePoints[i]);
        if (distance < minDistance && distance > 5) {
          // Only points more than 5m away
          minDistance = distance;
          nextPoint = _routePoints[i];
        }
      }
    }

    // Fallback to correct destination based on current phase and multi-order mode
    if (nextPoint == null) {
      if (_isMultiOrderMode) {
        if (_currentPhase == NavigationPhase.multiOrderPickups) {
          nextPoint = _currentPickupIndex < _allPickupLocations.length
              ? _allPickupLocations[_currentPickupIndex]
              : _pickupLocation;
        } else if (_currentPhase == NavigationPhase.multiOrderDeliveries) {
          nextPoint = _currentDeliveryIndex < _allDeliveryLocations.length
              ? _allDeliveryLocations[_currentDeliveryIndex]
              : _deliveryLocation;
        } else {
          nextPoint = _currentPhase == NavigationPhase.toPickup
              ? _pickupLocation
              : _deliveryLocation;
        }
      } else {
        nextPoint = _currentPhase == NavigationPhase.toPickup
            ? _pickupLocation
            : _deliveryLocation;
      }
    }

    double distance = _calculateDistance(_currentLocation!, nextPoint);

    // For long distances (>50km), don't limit to 2km - show realistic long distance instructions
    double finalDistance;
    if (distance > 50000) {
      // Over 50km
      finalDistance = distance; // Show full distance for long routes
    } else {
      finalDistance = math.max(
        10.0,
        math.min(20000.0, distance)); // Up to 20km for medium distances
    }

    return finalDistance;
  }

  String _extractSecurityCodeFromOrder() {
    // Priority 1: Check securityCode (new camelCase format)
    if (widget.order.containsKey('securityCode') &&
        widget.order['securityCode'] != null &&
        widget.order['securityCode'].toString().isNotEmpty) {
      String securityCode = widget.order['securityCode'].toString();
      if (!securityCode.startsWith('data:image')) {
        debugPrint('✅ Security code found (securityCode): $securityCode');
        return securityCode;
      }
    }

    // Priority 2: Check security_code (old snake_case format)
    if (widget.order.containsKey('security_code') &&
        widget.order['security_code'] != null &&
        widget.order['security_code'].toString().isNotEmpty) {
      String securityCode = widget.order['security_code'].toString();
      if (!securityCode.startsWith('data:image')) {
        debugPrint('✅ Security code found (security_code): $securityCode');
        return securityCode;
      }
    }

    // Priority 3: Check qrCode (new camelCase format)
    if (widget.order.containsKey('qrCode') &&
        widget.order['qrCode'] != null &&
        widget.order['qrCode'].toString().isNotEmpty) {
      String qrCode = widget.order['qrCode'].toString();
      if (!qrCode.startsWith('data:image')) {
        debugPrint('✅ Security code found (qrCode): $qrCode');
        return qrCode;
      }
    }

    // Priority 4: Check qr_code (old snake_case format)
    if (widget.order.containsKey('qr_code') &&
        widget.order['qr_code'] != null &&
        widget.order['qr_code'].toString().isNotEmpty) {
      String qrCode = widget.order['qr_code'].toString();
      if (!qrCode.startsWith('data:image')) {
        debugPrint('✅ Security code found (qr_code): $qrCode');
        return qrCode;
      }
    }

    // Priority 5: Check nested order.securityCode
    if (widget.order.containsKey('order') && widget.order['order'] != null) {
      final orderData = widget.order['order'];
      if (orderData is Map &&
          orderData.containsKey('securityCode') &&
          orderData['securityCode'] != null &&
          orderData['securityCode'].toString().isNotEmpty) {
        String nestedCode = orderData['securityCode'].toString();
        if (!nestedCode.startsWith('data:image')) {
          debugPrint(
            '✅ Security code found (nested securityCode): $nestedCode');
          return nestedCode;
        }
      }
      // Also check old format
      if (orderData is Map &&
          orderData.containsKey('security_code') &&
          orderData['security_code'] != null &&
          orderData['security_code'].toString().isNotEmpty) {
        String nestedCode = orderData['security_code'].toString();
        if (!nestedCode.startsWith('data:image')) {
          debugPrint(
            '✅ Security code found (nested security_code): $nestedCode');
          return nestedCode;
        }
      }
    }

    // Load from database asynchronously
    _loadSecurityCodeFromDatabase();

    // Fallback: Show loading state
    return "Loading...";
  }

  Future<void> _loadSecurityCodeFromDatabase() async {
    try {
      // CRITICAL: In multi-order mode, use the current pickup order ID
      dynamic orderId;

      if (_isMultiOrderMode && _allOrders.isNotEmpty) {
        // Multi-order mode: Get ID from current pickup order
        if (_currentPhase == NavigationPhase.multiOrderPickups &&
            _currentPickupIndex < _allOrders.length) {
          orderId =
              _allOrders[_currentPickupIndex]['order_id'] ??
              _allOrders[_currentPickupIndex]['id'];
          print(
            '🔐 Multi-order pickup mode: Loading security code for order $orderId (index $_currentPickupIndex/${_allOrders.length})');
        } else if (_currentPhase == NavigationPhase.multiOrderDeliveries &&
            _currentDeliveryIndex < _allOrders.length) {
          orderId =
              _allOrders[_currentDeliveryIndex]['order_id'] ??
              _allOrders[_currentDeliveryIndex]['id'];
          print(
            '🔐 Multi-order delivery mode: Loading security code for order $orderId (index $_currentDeliveryIndex/${_allOrders.length})');
        } else {
          orderId = widget.order['order_id'] ?? widget.order['id'];
          print(
            '🔐 Multi-order fallback: Loading security code for widget order $orderId');
        }
      } else {
        // Single order mode: Use widget order ID
        orderId =
            widget.order['order_id'] ??
            widget.order['id'] ??
            widget.order['orderId'];
        print('🔐 Single-order mode: Loading security code for order $orderId');
      }

      if (orderId == null || orderId == 0) {
        print('⚠️ Cannot load security code: orderId is null or 0');
        return;
      }

      print('🔐 Fetching security code from API for order $orderId...');
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders/$orderId'),
            headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['order'] != null) {
          final orderData = data['order'];
          String? loadedSecurityCode;

          // Try both camelCase and snake_case formats
          if (orderData['securityCode'] != null &&
              orderData['securityCode'].toString().isNotEmpty) {
            loadedSecurityCode = orderData['securityCode'].toString();
          } else if (orderData['security_code'] != null &&
              orderData['security_code'].toString().isNotEmpty) {
            loadedSecurityCode = orderData['security_code'].toString();
          } else if (orderData['qrCode'] != null &&
              orderData['qrCode'].toString().isNotEmpty) {
            loadedSecurityCode = orderData['qrCode'].toString();
          } else if (orderData['qr_code'] != null &&
              orderData['qr_code'].toString().isNotEmpty) {
            loadedSecurityCode = orderData['qr_code'].toString();
          }

          // Filter out base64 image data - we only want numeric codes
          if (loadedSecurityCode != null &&
              !loadedSecurityCode.startsWith('data:image')) {
            print(
              '✅ Security code loaded successfully from database: $loadedSecurityCode');

            if (mounted) {
              setState(() {
                _securityCode = loadedSecurityCode!;
              });
            }

            // Update current order security code if available
            if (_currentOrder != null) {
              _currentOrder!['securityCode'] = loadedSecurityCode;
              _currentOrder!['security_code'] = loadedSecurityCode;
            }

            // Also update the order in _allOrders if multi-order mode
            if (_isMultiOrderMode && _allOrders.isNotEmpty) {
              if (_currentPhase == NavigationPhase.multiOrderPickups &&
                  _currentPickupIndex < _allOrders.length) {
                _allOrders[_currentPickupIndex]['securityCode'] =
                    loadedSecurityCode;
                _allOrders[_currentPickupIndex]['security_code'] =
                    loadedSecurityCode;
              } else if (_currentPhase ==
                      NavigationPhase.multiOrderDeliveries &&
                  _currentDeliveryIndex < _allOrders.length) {
                _allOrders[_currentDeliveryIndex]['securityCode'] =
                    loadedSecurityCode;
                _allOrders[_currentDeliveryIndex]['security_code'] =
                    loadedSecurityCode;
              }
            }
          } else {
            print('⚠️ Invalid or missing security code');
            if (mounted) {
              setState(() {
                _securityCode = "Code not found";
              });
            }
          }
        } else {
          print('⚠️ API response missing order data');
          if (mounted) {
            setState(() {
              _securityCode = "Code not found";
            });
          }
        }
      } else {
        print('⚠️ API returned status ${response.statusCode}');
        if (mounted) {
          setState(() {
            _securityCode = "Code not found";
          });
        }
      }
    } catch (e) {}
  }

  String _extractSecurityCodeFromCurrentOrder() {
    if (_currentOrder == null) {
      return _extractSecurityCodeFromOrder(); // Fallback to main order
    }

    // Priority 1: Check securityCode (new camelCase format)
    if (_currentOrder!.containsKey('securityCode') &&
        _currentOrder!['securityCode'] != null &&
        _currentOrder!['securityCode'].toString().isNotEmpty) {
      String securityCode = _currentOrder!['securityCode'].toString();
      if (!securityCode.startsWith('data:image')) {
        debugPrint(
          '✅ Security code found in current order (securityCode): $securityCode');
        return securityCode;
      }
    }

    // Priority 2: Check security_code (old snake_case format)
    if (_currentOrder!.containsKey('security_code') &&
        _currentOrder!['security_code'] != null &&
        _currentOrder!['security_code'].toString().isNotEmpty) {
      String securityCode = _currentOrder!['security_code'].toString();
      if (!securityCode.startsWith('data:image')) {
        debugPrint(
          '✅ Security code found in current order (security_code): $securityCode');
        return securityCode;
      }
    }

    // Priority 3: Check qrCode (new camelCase format)
    if (_currentOrder!.containsKey('qrCode') &&
        _currentOrder!['qrCode'] != null &&
        _currentOrder!['qrCode'].toString().isNotEmpty) {
      String qrCode = _currentOrder!['qrCode'].toString();
      if (!qrCode.startsWith('data:image')) {
        debugPrint('✅ Security code found in current order (qrCode): $qrCode');
        return qrCode;
      }
    }

    // Priority 4: Check qr_code (old snake_case format)
    if (_currentOrder!.containsKey('qr_code') &&
        _currentOrder!['qr_code'] != null &&
        _currentOrder!['qr_code'].toString().isNotEmpty) {
      String qrCode = _currentOrder!['qr_code'].toString();
      if (!qrCode.startsWith('data:image')) {
        debugPrint('✅ Security code found in current order (qr_code): $qrCode');
        return qrCode;
      }
    }

    // Load from database for current order
    final orderId = _currentOrder!['order_id'] ?? _currentOrder!['id'] ?? 0;
    if (orderId != 0) {
      _loadSecurityCodeFromDatabaseForCurrentOrder(orderId);
    }

    // Fallback: Show loading state
    return "Loading...";
  }

  Future<bool> _loadSecurityCodeFromDatabaseForCurrentOrder(
    dynamic orderId) async {
    try {
      print('🔐 Loading security code for Order $orderId...');

      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders/$orderId'),
            headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Check if order data exists
        if (data['order'] != null) {
          final orderData = data['order'];
          String? loadedSecurityCode;

          // Try new camelCase format first
          if (orderData['securityCode'] != null &&
              orderData['securityCode'].toString().isNotEmpty) {
            loadedSecurityCode = orderData['securityCode'].toString();
          }
          // Fallback to old snake_case format
          else if (orderData['security_code'] != null &&
              orderData['security_code'].toString().isNotEmpty) {
            loadedSecurityCode = orderData['security_code'].toString();
          }
          // Try qrCode
          else if (orderData['qrCode'] != null &&
              orderData['qrCode'].toString().isNotEmpty) {
            loadedSecurityCode = orderData['qrCode'].toString();
          }
          // Try qr_code
          else if (orderData['qr_code'] != null &&
              orderData['qr_code'].toString().isNotEmpty) {
            loadedSecurityCode = orderData['qr_code'].toString();
          }

          // Validate and set the code
          if (loadedSecurityCode != null &&
              !loadedSecurityCode.startsWith('data:image')) {
            setState(() {
              _securityCode = loadedSecurityCode!;

              // Update current order with both formats for compatibility
              if (_currentOrder != null) {
                _currentOrder!['securityCode'] = loadedSecurityCode;
                _currentOrder!['security_code'] = loadedSecurityCode;
              }
            });

            // Success haptic feedback
            HapticFeedback.mediumImpact();
            return true;
          } else {
            print('⚠️ Invalid security code format (base64 image or null)');
          }
        } else {
          print('⚠️ No order data in response');
        }
      } else {
        print('⚠️ Order API returned status ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading security code: $e');
    }

    return false; // Code not loaded successfully
  }

  String _generateQRCodeData() {
    // CRITICAL FIX: Return ONLY the security code, not JSON
    // This way the scanned code will match the database security_code field
    return _securityCode;
  }

  void _markAsArrived() async {
    // ── Reopen guard ──────────────────────────────────────────────────────────
    // If the timer is already running (driver previously tapped Arrived and
    // closed the sheet without finishing), just reopen the sheet so the timer
    // continues from where it left off — do NOT reinitialise anything.
    if (_waitingStartTime != null) {
      setState(() { _showArrivedButton = false; });
      _showPickupBottomSheet();
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    // Update state
    setState(() {
      _showArrivedButton = false;
      _navigationStarted = true;

      // Update current order for the current pickup
      if (_isMultiOrderMode && _currentPickupIndex < _allOrders.length) {
        _currentOrder = _allOrders[_currentPickupIndex];
        _currentPhase = NavigationPhase.atPickup;
      } else {
        _currentOrder = widget.order;
        _currentPhase = NavigationPhase.atPickup;
      }
    });

    // Haptic feedback for arrival confirmation
    HapticFeedback.heavyImpact();

    // CRITICAL: Start waiting timer when driver arrives at pickup
    _scanPhase = 'waiting'; // reset: waiting for first scan (check-in)
    _startWaitingTimer();

    // Update Live Activity to show arrival / scan-waiting phase
    _updateLiveActivity(force: true);

    // NOTE: _sellerCheckInAt is set later, when the 1st QR scan (check-in) succeeds

    // CRITICAL: Save waiting start time to orders table immediately
    // so the timer start persists even if app is killed
    _saveWaitingStartToOrder(phase: 'seller');

    // Load fresh security code from database for current order
    final orderId = (_currentOrder != null)
        ? (_currentOrder!['order_id'] ?? _currentOrder!['id'] ?? 0)
        : (widget.order['order_id'] ?? widget.order['id'] ?? 0);

    if (orderId != 0) {
      await _loadSecurityCodeFromDatabaseForCurrentOrder(orderId);
    } else {
      // Generate a fallback code
      setState(() {
        final random = math.Random();
        _securityCode = (1000 + random.nextInt(9000)).toString();
      });
    }

    // Save arrival status to database
    await _saveArrivalStatus();

    // CRITICAL: Save updated navigation state AFTER arrival status
    // This ensures the phase and arrived button state are persisted
    await _saveNavigationState();

    // Also save to local storage for immediate restoration
    await _saveNavigationStateToSharedPreferences();

    // Show pickup bottom sheet
    _showPickupBottomSheet();
  }

  // Build Loading Timer Card - shown after 1st QR scan (check-in) until 2nd scan (check-out)
  Widget _buildLoadingTimerCard(bool isLight) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final h = _loadingElapsedSeconds ~/ 3600;
        final m = (_loadingElapsedSeconds % 3600) ~/ 60;
        final s = _loadingElapsedSeconds % 60;
        final timeStr = h > 0
            ? '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}'
            : '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
        return Container(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12)),
                child: Icon(CupertinoIcons.cube_box, color: Colors.white, size: 24)),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loading timer running',
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                    Text(
                      timeStr,
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 2)),
                  ])),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20)),
                    child: Text(AppLocalizations.of(context)?.checkoutScan ?? AppLocalizations.of(context)!.tr('Scan Check-out'), style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                ]),
            ]));
      });
  }

  // Build Waiting Time Card with live timer - Trade Republic Style
  Widget _buildWaitingTimeCard(bool isLight) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        // Recompute every tick from the live state values
        final freeTimeSeconds = _waitingFreeMinutes * 60;
        final remainingFreeSeconds = freeTimeSeconds - _waitingElapsedSeconds;
        final isCharging = remainingFreeSeconds <= 0;
        final progress = freeTimeSeconds > 0
            ? (_waitingElapsedSeconds / freeTimeSeconds)
            : 0.0;
        return Container(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isCharging
                  ? [
                      Colors.red.withOpacity(0.15),
                      Colors.orange.withOpacity(0.1),
                    ]
                  : [
                      Colors.green.withOpacity(0.15),
                      Colors.blue.withOpacity(0.1),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isCharging
                              ? Colors.red.withOpacity(0.2)
                              : Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20)),
                        child: Icon(
                          isCharging
                              ? CupertinoIcons.timer
                              : CupertinoIcons.timer,
                          color: isCharging ? Colors.red : Colors.green,
                          size: 20)),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCharging ? (AppLocalizations.of(context)?.waitingCharges ?? AppLocalizations.of(context)!.tr('Waiting Charges')) : (AppLocalizations.of(context)?.freeWaiting ?? AppLocalizations.of(context)!.tr('Free Waiting')),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black87 : Colors.white)),
                          Text(
                            isCharging
                                ? '${Provider.of<AppSettings>(context, listen: false).formatCurrency(_waitingRatePerHour)} / hr'
                                : '$_waitingFreeMinutes min free',
                            style: TextStyle(
                              fontSize: 12,
                              color: isLight ? Colors.black54 : Colors.white70)),
                        ]),
                    ]),
                  // Charges Badge (only show when charging)
                  if (isCharging && _totalWaitingCharges > 0)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        '+${Provider.of<AppSettings>(context, listen: false).formatCurrency(_totalWaitingCharges)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white))),
                ]),

              SizedBox(height: 16),

              // Timer Display
              Row(
                children: [
                  // Elapsed Time
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _formatWaitingTime(_waitingElapsedSeconds),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: isCharging
                                ? Colors.red
                                : (isLight ? Colors.black : Colors.white),
                            fontFeatures: const [FontFeature.tabularFigures()])),
                        Text(
                          AppLocalizations.of(context)?.timeElapsed ?? AppLocalizations.of(context)!.tr('Time Elapsed'),
                          style: TextStyle(
                            fontSize: 12,
                            color: isLight ? Colors.black54 : Colors.white70)),
                      ])),

                  // Divider
                  Container(
                    height: 40,
                    width: 1,
                    color: isLight ? Colors.black12 : Colors.white24),

                  // Remaining/Overage
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          isCharging
                              ? '+${_formatWaitingTime(_waitingElapsedSeconds - freeTimeSeconds)}'
                              : _formatWaitingTime(remainingFreeSeconds),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: isCharging ? Colors.red : Colors.green,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                        Text(
                          isCharging
                              ? (AppLocalizations.of(context)?.chargeable ?? AppLocalizations.of(context)!.tr('Chargeable'))
                              : (AppLocalizations.of(context)?.freeRemaining ?? AppLocalizations.of(context)!.tr('Free Remaining')),
                          style: TextStyle(
                            fontSize: 12,
                            color: isLight ? Colors.black54 : Colors.white70)),
                      ])),
                ]),

              SizedBox(height: 16),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: isLight ? Colors.black12 : Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isCharging ? Colors.red : Colors.green),
                  minHeight: 6)),

              // Warning text when close to expiring
              if (!isCharging &&
                  remainingFreeSeconds <= 300 &&
                  remainingFreeSeconds > 0)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_triangle_fill,
                        color: Colors.orange,
                        size: 16),
                      SizedBox(width: 6),
                      Text(
                        AppLocalizations.of(context)?.freeTimeExpiringSoon ?? AppLocalizations.of(context)!.tr('Free time expiring soon!'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange)),
                    ])),
            ]));
      });
  }

  Future<void> _showPickupBottomSheet() async {
    if (_isPickupSheetOpen) return;
    _isPickupSheetOpen = true;
    // Get current order info for multi-order mode
    final currentOrderForPickup =
        _isMultiOrderMode && _currentPickupIndex < _allOrders.length
        ? _allOrders[_currentPickupIndex]
        : widget.order;

    final orderId =
        currentOrderForPickup['order_id'] ??
        currentOrderForPickup['id'] ?? AppLocalizations.of(context)!.tr('N/A');

    // CRITICAL: Load security code for current pickup order
    final currentSecurityCode = _extractSecurityCodeFromOrder();

    // Also load from database asynchronously
    if (_isMultiOrderMode && orderId != 'N/A') {
      _loadSecurityCodeFromDatabaseForCurrentOrder(orderId).then((success) {
        if (success && mounted) {
          setState(() {});
        }
      });
    }

    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final isLight = appSettings.isLightMode(context);

    void startPickupScanFlow() {
      _showQRCodeScanner();
    }

    final loadingInstruction = (currentOrderForPickup['loadingInstruction'] ?? AppLocalizations.of(context)!.tr('')).toString();
    final pickupDepartment =
      _normalizedDepartmentValue(currentOrderForPickup['department']) ??
      _normalizedDepartmentValue(currentOrderForPickup['seller_department']) ??
      _normalizedDepartmentValue(currentOrderForPickup['sellerDepartment']) ?? AppLocalizations.of(context)!.tr('');

    await TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.94,
        child: Column(
          children: [
            const DragHandle(),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.pickupConfirmation ?? AppLocalizations.of(context)!.tr('Pickup Confirmation'),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.45)),
                      SizedBox(height: 4),
                      Text(
                        _scanPhase == 'waiting'
                            ? 'Ready for check-in'
                            : 'Ready for check-out',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isLight ? Colors.black54 : Colors.white70)),
                    ])),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}$orderId',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.green))),
              ]),

            SizedBox(height: 14),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (loadingInstruction.isNotEmpty)
                      Container(
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_triangle_fill,
                              color: Colors.orange,
                              size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Operator Instructions',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isLight ? Colors.black87 : Colors.white)),
                                  SizedBox(height: 4),
                                  Text(
                                    loadingInstruction,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                      color: isLight ? Colors.black87 : Colors.white70)),
                                ])),
                          ])),

                    if (loadingInstruction.isNotEmpty) SizedBox(height: 12),

                    if (pickupDepartment.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pickup department',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade700)),
                            SizedBox(height: 6),
                            Text(
                              pickupDepartment.toUpperCase(),
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                                letterSpacing: 0.3)),
                          ])),

                    if (pickupDepartment.isNotEmpty) SizedBox(height: 12),

                    Text(
                      AppLocalizations.of(context)?.scanBusinessQrCode ?? AppLocalizations.of(context)!.tr('Scan business QR code'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isLight ? Colors.black87 : Colors.white70,
                        letterSpacing: 0.2)),

                    SizedBox(height: 12),

                    _buildScanPhaseStatusCard(isLight, isDelivery: false),

                    SizedBox(height: 12),

                    if (_scanPhase == 'waiting') _buildWaitingTimeCard(isLight),
                    if (_scanPhase == 'loading') _buildLoadingTimerCard(isLight),

                    SizedBox(height: 16),

                    // Security code
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.black.withValues(alpha: 0.03)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                AppLocalizations.of(context)?.securityCode ?? AppLocalizations.of(context)!.tr('Security Code'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isLight ? Colors.black54 : Colors.white60)),
                              const Spacer(),
                              if (_securityCode.isNotEmpty && _securityCode != 'Loading...')
                                TradeRepublicTap(
                                  onTap: () {
                                    Clipboard.setData(ClipboardData(text: _securityCode));
                                    TopNotification.success(
                                      context,
                                      AppLocalizations.of(context)!.tr('Sicherheitscode kopiert') ?? AppLocalizations.of(context)!.tr('Sicherheitscode kopiert'));
                                  },
                                  child: Icon(
                                    CupertinoIcons.doc_on_doc,
                                    size: 16,
                                    color: isLight ? Colors.black54 : Colors.white70)),
                            ]),
                          SizedBox(height: 12),
                          Center(
                            child: _securityCode.isNotEmpty && _securityCode != 'Loading...'
                                ? Text(
                                    _securityCode,
                                    style: TextStyle(
                                      fontSize: 42,
                                      fontWeight: FontWeight.w800,
                                      color: isLight ? Colors.black : Colors.white,
                                      letterSpacing: 5.5))
                                : SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: CultiooLoadingIndicator(size: 24))),
                          SizedBox(height: 10),
                          Text(
                            AppLocalizations.of(context)?.matchCodeWithBusiness ?? AppLocalizations.of(context)!.tr('Match this code with business'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isLight ? Colors.black87 : Colors.white70)),
                        ])),

                    SizedBox(height: 16),

                    _buildVehicleSectionCard(currentOrderForPickup, isLight),

                    SizedBox(height: 16),

                    Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.green.withValues(alpha: 0.06)
                            : Colors.green.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18)),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.qrcode_viewfinder,
                            color: Colors.green,
                            size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _scanPhase == 'waiting'
                                      ? 'Scan check-in'
                                      : 'Scan check-out',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isLight ? Colors.black : Colors.white)),
                                SizedBox(height: 2),
                                Text(
                                  _scanPhase == 'waiting'
                                      ? 'Scan business QR code now'
                                      : 'Scan business QR code again',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: (isLight ? Colors.black : Colors.white)
                                        .withValues(alpha: 0.6))),
                              ])),
                        ])),

                    SizedBox(height: 8),
                  ]))),

            SizedBox(height: 12),

            // Bottom actions
            Column(
              children: [
                TradeRepublicButton(
                  label: _scanPhase == 'waiting'
                      ? 'Scan check-in'
                      : 'Scan check-out',
                  icon: Icon(CupertinoIcons.qrcode_viewfinder),
                  onPressed: startPickupScanFlow),
                SizedBox(height: 10),
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.close ?? AppLocalizations.of(context)!.tr('Close'),
                  onPressed: () => Navigator.pop(context),
                  isSecondary: true),
              ]),
          ])));

    // Sheet was dismissed – persist timer/scan-phase so it survives a re-open
    _isPickupSheetOpen = false;
    if (mounted) {
      _saveNavigationState();
      _saveNavigationStateToSharedPreferences();
    }
  }

  // Build Vehicle Section Card - Shows truck visualization with selected section
  Widget _buildVehicleSectionCard(Map<String, dynamic> order, bool isLight) {
    // Extract section information from order
    final sectionIndex = order['section_index'];
    final sectionName = order['section_name'] ?? AppLocalizations.of(context)!.tr('');
    final vehicleId = order['vehicle_id'];
    final vehicleSections = order['vehicle_sections'];

    // If no section info, don't show the card
    if (sectionIndex == null && vehicleSections == null) {
      return const SizedBox.shrink();
    }

    // Parse sections data
    List<Map<String, dynamic>> sections = [];
    if (vehicleSections != null) {
      if (vehicleSections is List) {
        sections = vehicleSections
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
      } else if (vehicleSections is String) {
        try {
          final parsed = json.decode(vehicleSections);
          if (parsed is List) {
            sections = parsed.map((s) => Map<String, dynamic>.from(s)).toList();
          }
        } catch (e) {
          print('Error parsing vehicle_sections: $e');
        }
      }
    }

    // Default to 3 sections if no data but section_index exists
    if (sections.isEmpty && sectionIndex != null) {
      sections = [
        {'name': 'Front', 'percentage': 33},
        {'name': 'Middle', 'percentage': 34},
        {'name': AppLocalizations.of(context)?.back ?? AppLocalizations.of(context)!.tr('Back'), 'percentage': 33},
      ];
    }

    final totalSections = sections.length;
    final selectedIdx = sectionIndex is int
        ? sectionIndex
        : (int.tryParse(sectionIndex?.toString() ?? AppLocalizations.of(context)!.tr('')) ?? 0);

    // Get section name
    String displaySectionName = sectionName.isNotEmpty
        ? sectionName
        : (selectedIdx < sections.length
              ? (sections[selectedIdx]['name'] ?? 'Section ${selectedIdx + 1}')
              : 'Section ${selectedIdx + 1}');

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4)),
        ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
                child: Icon(
                  CupertinoIcons.cube_box,
                  color: Colors.blue,
                  size: 24)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.loadInSection ?? AppLocalizations.of(context)!.tr('Load in Section'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                        letterSpacing: 0.2)),
                    SizedBox(height: 2),
                    Text(
                      displaySectionName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                        letterSpacing: -0.3)),
                  ])),
              // Section number badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20)),
                child: Center(
                  child: Text(
                    '${selectedIdx + 1}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)))),
            ]),

          SizedBox(height: 20),

          // Truck Visualization
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Row(
                children: [
                  // Cabin
                  Container(
                    width: 40,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white : const Color(0xFF252525)),
                    child: Center(
                      child: Icon(
                        CupertinoIcons.cube_box,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.3),
                        size: 20))),
                  // Sections
                  Expanded(
                    child: Row(
                      children: List.generate(totalSections, (index) {
                        final section = index < sections.length
                            ? sections[index]
                            : {'percentage': 100 ~/ totalSections};
                        final isSelected = selectedIdx == index;
                        final percentage =
                            (section['percentage'] ?? (100 ~/ totalSections))
                                as int;

                        return Expanded(
                          flex: percentage > 0 ? percentage : 1,
                          child: Container(
                            margin: EdgeInsets.only(left: index == 0 ? 0 : 1),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.green
                                  : (isLight
                                        ? Colors.white
                                        : const Color(0xFF1A1A1A))),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Section number
                                Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? Colors.white
                                        : (isLight
                                                  ? Colors.black
                                                  : Colors.white)
                                              .withOpacity(0.3))),
                                if (isSelected) ...[
                                  SizedBox(height: 2),
                                  Icon(
                                    CupertinoIcons.arrow_down,
                                    color: Colors.white,
                                    size: 16),
                                ],
                              ])));
                      }))),
                ]))),

          SizedBox(height: 12),

          // Instruction text
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.info,
                  color: Colors.green[700],
                  size: 16),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    AppLocalizations.of(context)?.openSectionLoad ?? AppLocalizations.of(context)!.tr('Open section and load the goods'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700]))),
              ])),
        ]));
  }

  // Build Vehicle Section Card for Delivery - Shows which section to unload from
  Widget _buildVehicleSectionCardForDelivery(
    Map<String, dynamic> order,
    bool isLight) {
    // Extract section information from order
    final sectionIndex = order['section_index'];
    final sectionName = order['section_name'] ?? AppLocalizations.of(context)!.tr('');
    final vehicleSections = order['vehicle_sections'];

    // If no section info, don't show the card
    if (sectionIndex == null && vehicleSections == null) {
      return const SizedBox.shrink();
    }

    // Parse sections data
    List<Map<String, dynamic>> sections = [];
    if (vehicleSections != null) {
      if (vehicleSections is List) {
        sections = vehicleSections
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
      } else if (vehicleSections is String) {
        try {
          final parsed = json.decode(vehicleSections);
          if (parsed is List) {
            sections = parsed.map((s) => Map<String, dynamic>.from(s)).toList();
          }
        } catch (e) {
          print('Error parsing vehicle_sections: $e');
        }
      }
    }

    // Default to 3 sections if no data but section_index exists
    if (sections.isEmpty && sectionIndex != null) {
      sections = [
        {'name': 'Front', 'percentage': 33},
        {'name': 'Middle', 'percentage': 34},
        {'name': AppLocalizations.of(context)?.back ?? AppLocalizations.of(context)!.tr('Back'), 'percentage': 33},
      ];
    }

    final totalSections = sections.length;
    final selectedIdx = sectionIndex is int
        ? sectionIndex
        : (int.tryParse(sectionIndex?.toString() ?? AppLocalizations.of(context)!.tr('')) ?? 0);

    // Get section name
    String displaySectionName = sectionName.isNotEmpty
        ? sectionName
        : (selectedIdx < sections.length
              ? (sections[selectedIdx]['name'] ?? 'Section ${selectedIdx + 1}')
              : 'Section ${selectedIdx + 1}');

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4)),
        ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20)),
                child: Icon(
                  CupertinoIcons.cube_box,
                  color: Colors.orange,
                  size: 24)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.unloadFromSection ?? AppLocalizations.of(context)!.tr('Unload from Section'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                        letterSpacing: 0.2)),
                    SizedBox(height: 2),
                    Text(
                      displaySectionName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                        letterSpacing: -0.3)),
                  ])),
              // Section number badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(20)),
                child: Center(
                  child: Text(
                    '${selectedIdx + 1}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)))),
            ]),

          SizedBox(height: 20),

          // Truck Visualization
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(20)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Row(
                children: [
                  // Cabin
                  Container(
                    width: 40,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white : const Color(0xFF252525)),
                    child: Center(
                      child: Icon(
                        CupertinoIcons.cube_box,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.3),
                        size: 20))),
                  // Sections
                  Expanded(
                    child: Row(
                      children: List.generate(totalSections, (index) {
                        final section = index < sections.length
                            ? sections[index]
                            : {'percentage': 100 ~/ totalSections};
                        final isSelected = selectedIdx == index;
                        final percentage =
                            (section['percentage'] ?? (100 ~/ totalSections))
                                as int;

                        return Expanded(
                          flex: percentage > 0 ? percentage : 1,
                          child: Container(
                            margin: EdgeInsets.only(left: index == 0 ? 0 : 1),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.orange
                                  : (isLight
                                        ? Colors.white
                                        : const Color(0xFF1A1A1A))),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Section number
                                Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? Colors.white
                                        : (isLight
                                                  ? Colors.black
                                                  : Colors.white)
                                              .withOpacity(0.3))),
                                if (isSelected) ...[
                                  SizedBox(height: 2),
                                  Icon(
                                    CupertinoIcons.arrow_up,
                                    color: Colors.white,
                                    size: 16),
                                ],
                              ])));
                      }))),
                ]))),

          SizedBox(height: 12),

          // Instruction text
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.info,
                  color: Colors.orange[700],
                  size: 16),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    AppLocalizations.of(context)?.openSectionUnload ?? AppLocalizations.of(context)!.tr('Open section and unload the goods'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700]))),
              ])),
        ]));
  }

  Future<void> _saveNavigationStateToSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Enhanced state data for immediate restoration
      final stateData = {
        'navigation_active': _navigationStarted,
        'current_order_id':
            (_currentOrder ?? widget.order)['order_id'] ??
            (_currentOrder ?? widget.order)['id'],
        'current_phase': _currentPhase.toString(),
        'show_security_code': _showSecurityCode,
        'show_arrived_button': _showArrivedButton,
        'is_multi_order_mode': _isMultiOrderMode,
        'current_pickup_index': _currentPickupIndex,
        'current_delivery_index': _currentDeliveryIndex,
        'all_orders': _allOrders,
        'current_order': _currentOrder,
        'security_code': _securityCode,
        'updated_at': DateTime.now().toIso8601String(),
        // Timer / scan phase state for resumption
        'scan_phase': _scanPhase,
        'waiting_start_time': _waitingStartTime?.toIso8601String(),
        'waiting_elapsed_seconds': _waitingElapsedSeconds,
        'waiting_free_minutes': _waitingFreeMinutes,
        'waiting_rate_per_hour': _waitingRatePerHour,
        'total_waiting_charges': _totalWaitingCharges,
        'free_time_warning_shown': _freeTimeWarningShown,
        'free_time_expired_shown': _freeTimeExpiredShown,
        'loading_start_time': _loadingStartTime?.toIso8601String(),
        'loading_elapsed_seconds': _loadingElapsedSeconds,
        'seller_check_in_at': _sellerCheckInAt?.toIso8601String(),
        'seller_check_out_at': _sellerCheckOutAt?.toIso8601String(),
        'buyer_check_in_at': _buyerCheckInAt?.toIso8601String(),
        'buyer_check_out_at': _buyerCheckOutAt?.toIso8601String(),
      };

      await prefs.setString('quick_navigation_state', jsonEncode(stateData));
    } catch (e) {}
  }

  void _showQRCodeScanner() async {
    try {
      print('🎥 Opening QR Scanner as bottom sheet...');

      // Dispose any old controller safely
      if (_qrScannerController != null) {
        final old = _qrScannerController;
        _qrScannerController = null;
        await Future.delayed(const Duration(milliseconds: 30));
        try { await old?.stop(); } catch (_) {}
        try { await old?.dispose(); } catch (_) {}
      }
      if (!mounted) return;

      _scanSuccessController.reset();
      _qrScannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        autoStart: true);
      _qrScanResult = '';
      _isQRScannerLoading = false;
      _qrLoadingNotifier.value = false;
      _qrResultNotifier.value  = '';

      setState(() {
        _showSecurityCode = false;
        _showQRScanner = true;   // hides Go/Navigating buttons
      });
      _updateLiveActivity(force: true); // Dynamic Island → scanning
      HapticFeedback.mediumImpact();

      await showQRScannerSheet(
        context: context,
        controller: _qrScannerController!,
        onDetect: _onQRCodeDetected,
        scanSuccessController: _scanSuccessController,
        scanSuccessScaleAnimation: _scanSuccessScaleAnimation,
        scanSuccessFadeAnimation: _scanSuccessFadeAnimation,
        isLoadingNotifier: _qrLoadingNotifier,
        resultNotifier: _qrResultNotifier,
        onSheetReady: ({required setter, required close}) {
          _scannerSheetSetter  = setter;
          _closeScannerSheet   = close;
        });

      // Sheet dismissed (user dragged down or we called pop)
      _scannerSheetSetter = null;
      _closeScannerSheet = null;
      final ctrl = _qrScannerController;
      _qrScannerController = null;
      _qrLoadingNotifier.value = false;
      _qrResultNotifier.value  = '';
      setState(() {
        _showQRScanner = false;
        _qrScanResult = '';
        _isQRScannerLoading = false;
        if (_waitingStartTime != null) _showArrivedButton = true;
      });
      _updateLiveActivity(force: true); // Dynamic Island → restore prior phase
      try { await ctrl?.stop(); } catch (_) {}
      try { await ctrl?.dispose(); } catch (_) {}
    } catch (e) {
      print('❌ Error opening QR Scanner: $e');

      // Show error message to user
      if (mounted) {
        setState(() {
          _showQRScanner = false;
          _isQRScannerLoading = false;
          if (_waitingStartTime != null) {
            _showArrivedButton = true;
          }
        });

        // Show error bottom sheet
        final appSettings = Provider.of<AppSettings>(context, listen: false);
        final isLight = appSettings.isLightMode(context);
        TradeRepublicBottomSheet.show(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DragHandle(),
                Row(
                  children: [
                    Icon(CupertinoIcons.camera, size: 22),
                    SizedBox(width: 12),
                    Flexible(child: Text(
                      AppLocalizations.of(context)?.cameraError ?? AppLocalizations.of(context)!.tr('Camera Error'),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4))),
                  ]),
                SizedBox(height: 4),
                Text(
                  '${AppLocalizations.of(context)?.failedToOpenCameraCheckPermissions ?? AppLocalizations.of(context)!.tr('Failed to open camera. Please check camera permissions in Settings.')}\n\n${e.toString()}',
                  textAlign: TextAlign.center),
                SizedBox(height: 24),
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.ok ?? AppLocalizations.of(context)!.tr('OK'),
                  onPressed: () => Navigator.pop(context)),
            ]));
      }
    }
  }

  void _triggerCompletionAnimation() {
    // Start the beautiful completion animation sequence
    _completionController.forward();

    // Heavy haptic feedback for completion celebration
    HapticFeedback.heavyImpact();

    // Additional haptic feedback for confetti effect
    Timer(const Duration(milliseconds: 600), () {
      HapticFeedback.mediumImpact();
    });
    Timer(const Duration(milliseconds: 800), () {
      HapticFeedback.lightImpact();
    });
  }

  Future<void> _handleDeliveryCompletionAsync() async {
    // Call the existing delivery completion logic with proper async handling
    await _completeCurrentDeliveryAsync();
  }

  void _onQRCodeDetected(BarcodeCapture barcodeCapture) {
    final List<Barcode> barcodes = barcodeCapture.barcodes;

    if (barcodes.isEmpty || _isQRScannerLoading) return;

    final String? scannedCode = barcodes.first.rawValue;

    if (scannedCode == null || scannedCode.isEmpty) return;

    // Prevent multiple scans
    _isQRScannerLoading = true;
    _qrScanResult = scannedCode;
    _qrLoadingNotifier.value = true;
    _qrResultNotifier.value  = scannedCode;

    // Stop camera
    _qrScannerController?.stop();

    // Trigger success animation
    _scanSuccessController.forward();
    HapticFeedback.heavyImpact();

    // Wait for animation then validate
    Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        _validateQRCodeWithDatabase();
      }
    });
  }

  Future<void> _validateQRCodeWithDatabase() async {
    try {
      final orderId = (_currentOrder != null)
          ? (_currentOrder!['order_id'] ?? _currentOrder!['id'] ?? 0)
          : (widget.order['order_id'] ?? widget.order['id'] ?? 0);

      print('   Scanned code: $_qrScanResult');

      // Determine validation type based on current phase
      String validationType = 'pickup';
      if (_currentPhase == NavigationPhase.toDelivery ||
          (_isMultiOrderMode &&
              _currentPhase == NavigationPhase.multiOrderDeliveries)) {
        validationType = 'delivery';
      }

      print('   Validation type: $validationType');

      // Fetch order data to get stored QR code
      final String url = '${ApiConfig.baseUrl}/api/delvioo/orders/$orderId';

      final response = await http
          .get(Uri.parse(url), headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true && responseData['order'] != null) {
          final orderData = responseData['order'];

          // Get stored QR code - check both formats
          String? storedQRCode = orderData['qrCode'] ?? orderData['qr_code'];
          String? storedSecurityCode =
              orderData['securityCode'] ?? orderData['security_code'];

          print('   Stored QR code: $storedQRCode');
          print('   Stored security code: $storedSecurityCode');

          // Validate: Check if scanned code matches either QR code or security code
          bool isValid = false;

          if (storedQRCode != null && storedQRCode.isNotEmpty) {
            isValid = _qrScanResult == storedQRCode;
          }

          // Also allow security code as valid QR code
          if (!isValid &&
              storedSecurityCode != null &&
              storedSecurityCode.isNotEmpty) {
            isValid = _qrScanResult == storedSecurityCode;
          }

          print('   Validation result: $isValid');

          if (isValid) {
            if (validationType == 'delivery') {
              await _onDeliveryQRCodeValidationSuccess();
            } else {
              await _onQRCodeValidationSuccess();
            }
          } else {
            print('❌ QR Code validation failed - code does not match');
            _onQRCodeValidationFailure('QR Code does not match order');
          }
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ QR Code validation error: $e');
      _onQRCodeValidationFailure('Validation failed: ${e.toString()}');
    }
  }

  Future<void> _onQRCodeValidationSuccess() async {
    HapticFeedback.heavyImpact();

    if (_scanPhase == 'waiting') {
      // ── 1st SCAN: Check-in ──
      // Waiting timer stops, loading timer starts
      _stopWaitingTimer();
      await _saveWaitingTimeToOrder(phase: 'seller');
      _startLoadingTimer();
      _scanPhase = 'loading';

      // ✅ Check-in time = moment of QR scan (not arrival)
      _sellerCheckInAt = DateTime.now();
      _saveCheckinCheckout(sellerCheckIn: _sellerCheckInAt);

      _qrScanResult = '✅ Check-in OK · Jetzt Check-out scannen';
      _isQRScannerLoading = false;
      _qrLoadingNotifier.value = false;
      _qrResultNotifier.value  = '✅ Check-in OK · Jetzt Check-out scannen';
      _scanSuccessController.reset();
      // IMPORTANT: Do NOT auto-start the 2nd scan.
      // Close scanner and return to pickup confirmation so checkout appears explicitly.
      Timer(const Duration(milliseconds: 350), () {
        if (mounted) {
          _closeScannerSheet?.call();
        }
      });
      if (mounted) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.tr('Check-in successful. Now start check-out in pickup confirmation.') ?? AppLocalizations.of(context)!.tr('Check-in successful. Now start check-out in pickup confirmation.'));
      }
      print('✅ Pickup check-in: waiting stopped, loading started, check-in time saved');
    } else {
      // ── 2nd SCAN: Check-out ──
      // Loading timer stops, proceed to delivery phase
      _stopLoadingTimer();
      await _saveLoadingTimeToOrder(phase: 'seller');
      _qrScanResult = '✅ QR Code Verified!';
      _qrResultNotifier.value = '✅ QR Code Verified!';
      if (mounted) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.tr('Check-out successful. Proceeding to delivery.') ?? AppLocalizations.of(context)!.tr('Check-out successful. Proceeding to delivery.'));
      }
      _updateOrderStatusToPickedUp();
      Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          _closeScannerSheet?.call();
          _scanPhase = 'waiting';
          _startDeliveryPhase();
        }
      });
      print('✅ Pickup check-out: loading stopped, proceeding to delivery');
    }
  }

  Future<void> _updateOrderStatusToPickedUp() async {
    try {
      final orderId = (_currentOrder != null)
          ? (_currentOrder!['order_id'] ?? _currentOrder!['id'] ?? 0)
          : (widget.order['order_id'] ?? widget.order['id'] ?? 0);

      final String url =
          '${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/status';

      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'status': 'picked_up',
          'picked_up_at': DateTime.now().toIso8601String(),
          'driver_id': 1, // TODO: Get from authentication
        }));

      if (response.statusCode == 200) {
      } else {
        print('⚠️ Failed to update order status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error updating order status to picked_up: $e');
    }
  }

  Future<void> _onDeliveryQRCodeValidationSuccess() async {
    HapticFeedback.heavyImpact();

    if (_scanPhase == 'waiting') {
      // ── 1st SCAN: Check-in ──
      // Waiting timer stops, loading/unloading timer starts
      _stopWaitingTimer();
      await _saveWaitingTimeToOrder(phase: 'buyer');
      _startLoadingTimer();
      _scanPhase = 'loading';

      // ✅ Check-in time = moment of QR scan (not arrival)
      _buyerCheckInAt = DateTime.now();
      _saveCheckinCheckout(buyerCheckIn: _buyerCheckInAt);

      _qrScanResult = '✅ Check-in OK · Jetzt Check-out scannen';
      _isQRScannerLoading = false;
      _qrLoadingNotifier.value = false;
      _qrResultNotifier.value  = '✅ Check-in OK · Jetzt Check-out scannen';
      _scanSuccessController.reset();
      // Reopen scanner for the 2nd scan (small delay so user sees state change)
      Timer(const Duration(milliseconds: 900), () {
        _qrScannerController?.start();
      });
      if (mounted) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.tr('Delivery check-in successful. Timer running – please complete check-out.') ?? AppLocalizations.of(context)!.tr('Delivery check-in successful. Timer running – please complete check-out.'));
      }
      print('✅ Delivery check-in: waiting stopped, unloading timer started, check-in time saved');
    } else {
      // ── 2nd SCAN: Check-out ──
      // Loading/unloading timer stops, complete delivery
      _stopLoadingTimer();
      await _saveLoadingTimeToOrder(phase: 'buyer');
      _qrScanResult = '✅ Delivery QR Code Verified!';
      _qrResultNotifier.value = '✅ Delivery QR Code Verified!';
      if (mounted) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)!.tr('Delivery Check-out erfolgreich. Lieferung wird abgeschlossen.') ?? AppLocalizations.of(context)!.tr('Delivery Check-out erfolgreich. Lieferung wird abgeschlossen.'));
      }
      Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          _closeScannerSheet?.call();
          _scanPhase = 'waiting';
          _completeCurrentDeliveryAsync();
        }
      });
      print('✅ Delivery check-out: unloading stopped, completing delivery');
    }
  }

  void _onQRCodeValidationFailure(String errorMessage) {
    HapticFeedback.mediumImpact();

    // Stop scan success animation if running
    _scanSuccessController.reset();

    _qrScanResult = '❌ $errorMessage';
    _isQRScannerLoading = false;
    _qrLoadingNotifier.value = false;
    _qrResultNotifier.value  = '❌ $errorMessage';

    // Restart camera for retry
    Timer(const Duration(seconds: 2), () {
      if (mounted && _showQRScanner) {
        _qrScanResult = '';
        _qrResultNotifier.value = '';
        // Restart scanner controller
        _qrScannerController?.start();
      }
    });
  }

  Future<void> _saveArrivalStatus() async {
    try {
      final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;

      String url;
      Map<String, dynamic> requestBody;

      if (_isMultiOrderMode &&
          _currentPhase == NavigationPhase.multiOrderPickups) {
        // Use multi-order pickup arrival endpoint
        url = '${ApiConfig.baseUrl}/api/navigation/multi-order/arrived-pickup';

        final currentPickupOrderId = _currentPickupIndex < _allOrders.length
            ? (_allOrders[_currentPickupIndex]['order_id'] ??
                  _allOrders[_currentPickupIndex]['id'] ??
                  0)
            : orderId;

        requestBody = {
          'order_id': orderId, // Main navigation session ID
          'driver_id': 1,
          'pickup_index': _currentPickupIndex,
          'current_pickup_order_id': currentPickupOrderId,
          'arrived_at_pickup': DateTime.now().toIso8601String(),
          'current_phase': 'multiOrderPickups',
          'security_code_shown': _showSecurityCode,
          'pickup_location': {
            'lat': _currentPickupIndex < _allPickupLocations.length
                ? _allPickupLocations[_currentPickupIndex].latitude
                : _pickupLocation.latitude,
            'lng': _currentPickupIndex < _allPickupLocations.length
                ? _allPickupLocations[_currentPickupIndex].longitude
                : _pickupLocation.longitude,
          },
          'driver_location': {
            'lat': _currentLocation!.latitude,
            'lng': _currentLocation!.longitude,
          },
        };
      } else {
        // Use single order arrival endpoint
        url = '${ApiConfig.baseUrl}/api/navigation/arrived';

        requestBody = {
          'order_id': orderId,
          'driver_id': 1, // TODO: Get from authentication
          'arrived_at_pickup': true,
          'arrived_at': DateTime.now().toIso8601String(),
          'current_phase': 'atPickup',
          'security_code_shown': true,
          'pickup_location': {
            'lat': _pickupLocation.latitude,
            'lng': _pickupLocation.longitude,
          },
          'driver_location': {
            'lat': _currentLocation!.latitude,
            'lng': _currentLocation!.longitude,
          },
        };
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {}
      } else {}
    } catch (e) {}
  }

  Future<void> _saveArrivalAtDeliveryStatus() async {
    try {
      final orderId = (_currentOrder != null)
          ? (_currentOrder!['order_id'] ?? _currentOrder!['id'] ?? 0)
          : (widget.order['order_id'] ?? widget.order['id'] ?? 0);

      if (_isMultiOrderMode &&
          _currentPhase == NavigationPhase.multiOrderDeliveries) {
        // Use multi-order delivery arrival
        await _saveMultiOrderDeliveryArrival();
      } else {
        // Use single order delivery arrival
        final String url =
            '${ApiConfig.baseUrl}/api/navigation/arrived-delivery';

        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'order_id': orderId,
            'driver_id': 1,
            'arrived_at_delivery': true,
            'arrived_at': DateTime.now().toIso8601String(),
            'current_phase': 'atDelivery',
            'security_code_shown': true,
            'delivery_location': {
              'lat': _deliveryLocation.latitude,
              'lng': _deliveryLocation.longitude,
            },
            'driver_location': {
              'lat': _currentLocation!.latitude,
              'lng': _currentLocation!.longitude,
            },
          }));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {}
        } else {}
      }
    } catch (e) {}
  }

  void _startDeliveryPhase() {
    // Waiting timer/saving is handled at 1st QR scan (check-in); just ensure it's stopped
    _stopWaitingTimer();
    _stopLoadingTimer();

    // CRITICAL: Reset pickup timing state so delivery starts with a clean timer context
    // This prevents pickup waiting time from continuing into delivery.
    _waitingStartTime = null;
    _waitingElapsedSeconds = 0;
    _loadingStartTime = null;
    _loadingElapsedSeconds = 0;
    _totalWaitingCharges = 0.0;
    _freeTimeWarningShown = false;
    _freeTimeExpiredShown = false;
    _scanPhase = 'waiting';

    // PICKUP CHECK-OUT: save departure timestamp to orders.seller_check_out_at
    _sellerCheckOutAt = DateTime.now();
    _saveCheckinCheckout(sellerCheckOut: _sellerCheckOutAt);

    // Handle multi-order pickup flow differently
    if (_isMultiOrderMode &&
        _currentPhase == NavigationPhase.multiOrderPickups) {
      _saveMultiOrderPickupCompletion().then((_) {
        _proceedToNextPickup();
      });
      return;
    }

    // Single-order pickup completion - save to Google Cloud
    final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;
    _markOrderAsPickedUp(orderId).then((_) {}).catchError((error) {
      print(
        '⚠️ Could not save single-order pickup to cloud, but continuing: $error');
    });

    setState(() {
      _currentPhase = NavigationPhase.toDelivery;
      // DON'T change _currentLocation - use actual GPS position for delivery routing
      _navigationStarted = true; // Automatically start navigation to delivery
      _showSecurityCode = false;
      _showArrivedButton = false;
      _showQRScanner = false;
      _showQRDisplay = false;
      _currentInstructionIndex = 0;
    });

    // Update Live Activity for delivery phase start
    _updateLiveActivity(force: true);

    print(
      '🚚 Starting delivery phase: Navigation automatically started to delivery location');
    print(
      '📍 Current GPS position: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');

    // CRITICAL: Get fresh GPS position before generating route
    _getCurrentLocation()
        .then((_) {
          print(
            '✅ GPS position updated for delivery phase: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');

          // Generate new route to delivery location from CURRENT GPS position
          _generateRoute();

          // Update distance and time for new destination
          _updateCurrentDistanceAndTime();

          // Center map and zoom after route is generated
          Timer(const Duration(milliseconds: 500), () {
            if (mounted) {
              _centerMapOnRoute();
              _zoomToNavigationView();
            }
          });
        })
        .catchError((error) {
          print(
            '⚠️ Could not get GPS position, using last known location: $error');
          // Fallback: Generate route anyway with last known position
          _generateRoute();
          _updateCurrentDistanceAndTime();
        });

    // WICHTIG: Save navigation state with new delivery phase immediately
    _saveNavigationState()
        .then((_) {
          print(
            '✅ Delivery phase saved to database - will persist on modal reopen');
        })
        .catchError((error) {
          print('⚠️ Could not save delivery phase to database: $error');
        });

    // Save delivery phase start to database
    _saveDeliveryPhaseStart();

    // Haptic feedback for phase transition
    HapticFeedback.mediumImpact();
  }

  void _proceedToNextPickup() {
    // Increment pickup index
    _currentPickupIndex++;

    // CRITICAL: Reset timer & check-in state for the new pickup stop
    // so data from the previous stop doesn't carry over
    _stopWaitingTimer();
    _stopLoadingTimer();
    _waitingElapsedSeconds = 0;
    _loadingElapsedSeconds = 0;
    _waitingStartTime = null;
    _loadingStartTime = null;
    _sellerCheckInAt = null;
    _sellerCheckOutAt = null;
    _totalWaitingCharges = 0.0;
    _freeTimeWarningShown = false;
    _freeTimeExpiredShown = false;
    _scanPhase = 'waiting';

    if (_currentPickupIndex < _allPickupLocations.length) {
      // Move to next pickup location

      setState(() {
        _showSecurityCode = false;
        _showQRScanner = false;
        _showArrivedButton = false;
        _navigationStarted = true;
        _currentInstructionIndex = 0;
        // Stay in multiOrderPickups phase
      });

      // Update Live Activity for next multi-order pickup
      _updateLiveActivity(force: true);

      // Generate route to next pickup
      _generateRoute();
      _centerMapOnRoute();
      _zoomToNavigationView();

      // Update distance and time
      _updateCurrentDistanceAndTime();
    } else {
      // All pickups completed, start deliveries

      setState(() {
        _currentPhase = NavigationPhase.multiOrderDeliveries;
        _currentDeliveryIndex = 0;
        _showSecurityCode = false;
        _showQRScanner = false;
        _showArrivedButton = false;
        _navigationStarted = true;
        _currentInstructionIndex = 0;
      });

      // Update Live Activity for multi-order delivery start
      _updateLiveActivity(force: true);

      // Generate route to first delivery location
      _generateRoute();
      _centerMapOnRoute();
      _zoomToNavigationView();

      // Update distance and time
      _updateCurrentDistanceAndTime();
    }

    // Save updated navigation state for multi-order persistence
    _saveNavigationState();

    // Haptic feedback
    HapticFeedback.mediumImpact();
  }

  void _proceedToNextDelivery() {
    // Increment delivery index
    _currentDeliveryIndex++;

    // CRITICAL: Reset timer & check-in state for the new delivery stop
    // so data from the previous delivery doesn't carry over
    _stopWaitingTimer();
    _stopLoadingTimer();
    _stopDeliveryPolling();
    _waitingElapsedSeconds = 0;
    _loadingElapsedSeconds = 0;
    _waitingStartTime = null;
    _loadingStartTime = null;
    _buyerCheckInAt = null;
    _buyerCheckOutAt = null;
    _totalWaitingCharges = 0.0;
    _freeTimeWarningShown = false;
    _freeTimeExpiredShown = false;
    _scanPhase = 'waiting';

    if (_currentDeliveryIndex < _allDeliveryLocations.length) {
      // Move to next delivery location

      setState(() {
        _showSecurityCode = false;
        _showQRScanner = false;
        _showQRDisplay = false;
        _showArrivedButton = false;
        _navigationStarted = true;
        _currentInstructionIndex = 0;
        // Stay in multiOrderDeliveries phase

        // Update current order for the next delivery
        if (_currentDeliveryIndex < _allOrders.length) {
          _currentOrder = _allOrders[_currentDeliveryIndex];
        }
      });

      // Update Live Activity for next multi-order delivery
      _updateLiveActivity(force: true);

      // Generate route to next delivery
      _generateRoute();
      _centerMapOnRoute();
      _zoomToNavigationView();

      // Update distance and time
      _updateCurrentDistanceAndTime();
    } else {
      // All deliveries completed
      print(
        '🎉 All multi-order deliveries completed! Starting complete cleanup...');

      setState(() {
        _currentPhase = NavigationPhase.completed;
        _navigationStarted = false;
      });

      // Trigger beautiful completion animation for multi-order
      _triggerCompletionAnimation();

      // Start complete cleanup after animation to reset everything for new multi-orders
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          _completeNavigationAndCleanup();
        }
      });
    }

    // Save updated navigation state for multi-order persistence
    _saveNavigationState();

    // Also save to local storage for immediate restoration
    _saveNavigationStateToSharedPreferences();

    // Haptic feedback
    HapticFeedback.mediumImpact();
  }

  Widget _buildMultiOrderProgressIndicator() {
    if (!_isMultiOrderMode) return const SizedBox.shrink();

    final totalOrders = _allOrders.length;
    int completedSteps = 0;

    // Calculate progress based on current phase
    if (_currentPhase == NavigationPhase.multiOrderPickups) {
      completedSteps = _currentPickupIndex;
    } else if (_currentPhase == NavigationPhase.multiOrderDeliveries) {
      completedSteps = _allPickupLocations.length + _currentDeliveryIndex;
    } else if (_currentPhase == NavigationPhase.completed) {
      completedSteps = totalOrders * 2; // All pickups + deliveries
    }

    final totalSteps = totalOrders * 2; // Pickup + Delivery for each order
    final progress = totalSteps > 0 ? completedSteps / totalSteps : 0.0;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 24, vertical: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Modern Apple-style progress bar
          Container(
            height: 3,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _currentPhase == NavigationPhase.completed
                      ? Colors.green
                      : const Color(0xFF007AFF), // Apple Blue
                )))),
        ]));
  }

  void _markArrivedAtDelivery() async {
    // ── Reopen guard ──────────────────────────────────────────────────────────
    // If the timer is already running (driver previously tapped Arrived and
    // closed the sheet without finishing), just reopen the sheet so the timer
    // continues from where it left off — do NOT reinitialise anything.
    if (_waitingStartTime != null &&
      (_currentPhase == NavigationPhase.toDelivery ||
        _currentPhase == NavigationPhase.multiOrderDeliveries) &&
      _scanPhase == 'waiting') {
      setState(() { _showArrivedButton = false; });
      _showDeliveryBottomSheet();
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    // IMPORTANT: Cancel any existing pickup timer to prevent conflicts
    _securityCodeTimer?.cancel();

    setState(() {
      _showArrivedButton = false;
      _navigationStarted = true;

      // Update current order for delivery workflow
      if (_isMultiOrderMode && _currentDeliveryIndex < _allOrders.length) {
        _currentOrder = _allOrders[_currentDeliveryIndex];
        _currentPhase = NavigationPhase.multiOrderDeliveries;
      } else {
        _currentOrder = widget.order;
        _currentPhase = NavigationPhase.toDelivery;
      }

      // Ensure delivery waiting timer always starts fresh and isolated
      _waitingStartTime = null;
      _waitingElapsedSeconds = 0;
      _loadingStartTime = null;
      _loadingElapsedSeconds = 0;
      _totalWaitingCharges = 0.0;
      _freeTimeWarningShown = false;
      _freeTimeExpiredShown = false;
    });

    // Haptic feedback for arrival confirmation
    HapticFeedback.heavyImpact();

    // CRITICAL: Start waiting timer when driver arrives at delivery
    _scanPhase = 'waiting'; // reset: waiting for first scan (check-in)
    _startWaitingTimer();

    // Update Live Activity to show delivery arrival / scan-waiting phase
    _updateLiveActivity(force: true);

    // DELIVERY CHECK-IN: timestamp is saved when buyer QR scan succeeds (1st scan)
    // NOTE: _buyerCheckInAt is set later, when the 1st QR scan (check-in) succeeds

    // CRITICAL: Save waiting start time to orders table immediately
    // so the timer start persists even if app is killed
    _saveWaitingStartToOrder(phase: 'buyer');

    // Load fresh security code from database for current delivery order
    final orderId = (_currentOrder != null)
        ? (_currentOrder!['order_id'] ?? _currentOrder!['id'] ?? 0)
        : (widget.order['order_id'] ?? widget.order['id'] ?? 0);

    if (orderId != 0) {
      await _loadSecurityCodeFromDatabaseForCurrentOrder(orderId);
    } else {
      // Fallback to extraction method
      setState(() {
        _securityCode = _extractSecurityCodeFromCurrentOrder();
      });
    }

    // Save arrival at delivery status to database
    await _saveArrivalAtDeliveryStatus();

    // CRITICAL: Save updated navigation state AFTER arrival status
    await _saveNavigationState();

    // Also save to local storage for immediate restoration
    await _saveNavigationStateToSharedPreferences();

    // Show delivery QR code and security code in bottom sheet
    _showDeliveryBottomSheet();
  }

  Future<void> _showDeliveryBottomSheet() async {
    if (_isDeliverySheetOpen) return;
    _isDeliverySheetOpen = true;
    // Get current order information
    final currentOrderForDelivery =
        _isMultiOrderMode && _currentDeliveryIndex < _allOrders.length
        ? _allOrders[_currentDeliveryIndex]
        : _currentOrder ?? widget.order;

    final orderId =
        currentOrderForDelivery['order_id'] ??
        currentOrderForDelivery['id'] ?? AppLocalizations.of(context)!.tr('N/A');
    final customerName =
        currentOrderForDelivery['customer_name'] ??
        currentOrderForDelivery['username'] ?? AppLocalizations.of(context)!.tr('Customer');

    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final isLight = appSettings.isLightMode(context);

    // Start polling so driver app auto-detects when buyer scans the QR URL
    _startDeliveryPolling();

    await TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            const DragHandle(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(0, 0, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)?.deliveryConfirmation ?? AppLocalizations.of(context)!.tr('Delivery Confirmation'),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: isLight ? Colors.black : Colors.white,
                                  letterSpacing: -0.45)),
                              SizedBox(height: 4),
                              Text(
                                '${AppLocalizations.of(context)?.showQrCodeTo ?? AppLocalizations.of(context)!.tr('Show QR code to')} $customerName',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isLight ? Colors.black54 : Colors.white70)),
                            ])),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}$orderId',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue))),
                      ]),

                    SizedBox(height: 12),
                    _buildScanPhaseStatusCard(isLight, isDelivery: true),
                    SizedBox(height: 12),

                    if (_scanPhase == 'waiting') ...[
                      _buildWaitingTimeCard(isLight),
                      SizedBox(height: 12),
                    ],

                    if (_scanPhase == 'loading') ...[
                      _buildLoadingTimerCard(isLight),
                      SizedBox(height: 12),
                    ],

                    Center(
                      child: Container(
                        width: 252,
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8)),
                          ]),
                        child: _securityCode.isNotEmpty && _securityCode != 'Loading...'
                            ? QrImageView(
                                data: _generateDeliveryQRData(),
                                version: QrVersions.auto,
                                size: 220,
                                backgroundColor: Colors.white,
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Colors.black),
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Colors.black))
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CultiooLoadingIndicator(size: 24)),
                                  SizedBox(height: 16),
                                  Text(
                                    AppLocalizations.of(context)?.loading ?? AppLocalizations.of(context)!.tr('Loading...'),
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500)),
                                ]))),
                    SizedBox(height: 14),
                    Text(
                      _scanPhase == 'loading'
                          ? (AppLocalizations.of(context)?.buyerScanAgainCheckout ?? AppLocalizations.of(context)!.tr('Buyer: scan again for check-out'))
                          : (AppLocalizations.of(context)?.customerScansThisCode ?? AppLocalizations.of(context)!.tr('Customer scans this code (Check-in)')),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _scanPhase == 'loading'
                            ? Colors.green
                            : (isLight ? Colors.black87 : Colors.white))),

                    if (_securityCode.isNotEmpty && _securityCode != 'Loading...') ...[
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isLight ? Colors.black.withOpacity(0.03) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.lock_fill,
                              color: Colors.blue,
                              size: 18),
                            SizedBox(width: 10),
                            Text(
                              AppLocalizations.of(context)?.securityCode ?? AppLocalizations.of(context)!.tr('Security Code'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isLight ? Colors.black54 : Colors.white60)),
                            const Spacer(),
                            Text(
                              _securityCode,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: isLight ? Colors.black : Colors.white,
                                letterSpacing: 2)),
                          ])),
                    ],

                    SizedBox(height: 12),
                    _buildVehicleSectionCardForDelivery(
                      currentOrderForDelivery,
                      isLight),

                    SizedBox(height: 12),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        AppLocalizations.of(context)?.deliveryCompleteAuto ?? AppLocalizations.of(context)!.tr('Delivery will complete automatically when customer scans the QR code'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isLight ? Colors.black54 : Colors.white70,
                          height: 1.35))),

                    SizedBox(height: 12),
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)?.close ?? AppLocalizations.of(context)!.tr('Close'),
                      onPressed: () {
                        _stopDeliveryPolling();
                        Navigator.pop(context);
                        setState(() {
                          _showArrivedButton = true;
                        });
                      },
                      isSecondary: true),
                  ]))),
          ])));

    // Sheet was dismissed – persist timer/scan-phase
    _isDeliverySheetOpen = false;
    if (mounted) {
      _saveNavigationState();
      _saveNavigationStateToSharedPreferences();
    }
  }

  bool _isDeliveryScanPhase() {
    return _currentPhase == NavigationPhase.toDelivery ||
        (_isMultiOrderMode &&
            _currentPhase == NavigationPhase.multiOrderDeliveries);
  }

  void _reopenActiveScanBottomSheet() {
    if (!mounted) return;
    if (_scanPhase != 'loading') return;
    if (_showQRScanner || _showQRDisplay) return;

    if (_isDeliveryScanPhase()) {
      if (_isDeliverySheetOpen) return;
      _showDeliveryBottomSheet();
      return;
    }

    if (_isPickupSheetOpen) return;
    _showPickupBottomSheet();
  }

  // Delivery completion logic (called after buyer scans check-out QR, or manually)
  Future<void> _completeCurrentDeliveryAsync() async {
    if (_isCompletingDelivery) {
      print('⏳ Delivery completion already in progress - skipping duplicate call');
      return;
    }
    _isCompletingDelivery = true;

    // Ensure waiting/loading timers are stopped (may already be stopped by polling handler)
    _stopWaitingTimer();
    _stopLoadingTimer();
    _stopDeliveryPolling();

    // DELIVERY CHECK-OUT: save completion timestamp to orders.buyer_check_out_at (if not set by backend yet)
    _buyerCheckOutAt = DateTime.now();
    _saveCheckinCheckout(buyerCheckOut: _buyerCheckOutAt);

    // Track this delivery as completed
    final completedOrder = _currentOrder ?? widget.order;
    _completedDeliveries.add(Map<String, dynamic>.from(completedOrder));

    final orderId = (_currentOrder != null)
        ? (_currentOrder!['order_id'] ?? _currentOrder!['id'] ?? 0)
        : (widget.order['order_id'] ?? widget.order['id'] ?? 0);

    try {
      bool markDeliveredCallFailed = false;

      // FIRST: Mark order as delivered in backend
      try {
        await _markOrderAsDelivered(orderId);
        // IMMEDIATELY update local order status to prevent stale UI
        if (_currentOrder != null) {
          _currentOrder!['status'] = 'delivered';
        }
        if (widget.order['order_id'] == orderId || widget.order['id'] == orderId) {
          widget.order['status'] = 'delivered';
        }
      } catch (e) {
        markDeliveredCallFailed = true;
        print('⚠️ mark-delivered call failed, verifying status anyway: $e');
      }

      // THEN: Verify the status was updated
      final String checkUrl =
          '${ApiConfig.baseUrl}/api/delvioo/orders/$orderId';
      final checkResponse = await http
          .get(
            Uri.parse(checkUrl),
            headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (checkResponse.statusCode == 200) {
        final responseData = json.decode(checkResponse.body);

        if (responseData['success'] == true && responseData['order'] != null) {
          final orderData = responseData['order'];
          final String currentStatus =
              orderData['status']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');

          print('📋 Verified order status: $currentStatus');

          if (currentStatus == 'delivered') {
            // CRITICAL: Only clear navigation if ALL deliveries are completed
            bool shouldClearNavigation = true;

            if (_isMultiOrderMode) {
              // Check if there are more deliveries pending
              if (_currentDeliveryIndex + 1 < _allDeliveryLocations.length) {
                print(
                  '🚚 Multi-order mode: More deliveries pending (${_currentDeliveryIndex + 1}/${_allDeliveryLocations.length}) - NOT clearing navigation');
                shouldClearNavigation = false;
              } else {
                print(
                  '✅ Multi-order mode: Last delivery completed - WILL clear navigation');
              }
            } else {}

            // Only delete navigation if this is the final delivery
            if (shouldClearNavigation) {
              try {
                final deleteNavResponse = await http
                    .delete(
                      Uri.parse(
                        '${ApiConfig.baseUrl}/api/navigation/clear/$orderId'),
                      headers: {'Content-Type': 'application/json'})
                    .timeout(const Duration(seconds: 5));

                if (deleteNavResponse.statusCode == 200) {
                  final deleteData = json.decode(deleteNavResponse.body);
                  if (deleteData['success'] == true) {
                    print(
                      '✅ Navigation cleared from backend for order $orderId');
                  } else {
                    print(
                      '⚠️ Backend returned success: false when clearing navigation');
                  }
                } else {
                  print(
                    '⚠️ Failed to clear navigation: HTTP ${deleteNavResponse.statusCode}');
                }
              } catch (e) {
                print('⚠️ Error clearing navigation from backend: $e');
              }
            } else {
              print('📌 Keeping navigation active for remaining deliveries');
              // Save updated navigation state with current delivery marked as completed
              await _saveNavigationState();
            }

            // THEN trigger UI completion
            _synchronizeUIWithDatabaseStatus('delivered');
            return;
          } else {
            print(
              '⚠️ Status not yet updated to delivered (still: $currentStatus)');

            if (markDeliveredCallFailed) {
              throw Exception('Failed to mark order as delivered');
            }

            // CRITICAL: Only clear navigation if ALL deliveries are completed
            bool shouldClearNavigation = true;

            if (_isMultiOrderMode) {
              // Check if there are more deliveries pending
              if (_currentDeliveryIndex + 1 < _allDeliveryLocations.length) {
                print(
                  '🚚 Multi-order mode: More deliveries pending - NOT clearing navigation (fallback)');
                shouldClearNavigation = false;
              } else {
                print(
                  '✅ Multi-order mode: Last delivery completed - WILL clear navigation (fallback)');
              }
            }

            // Continue anyway since we just marked it - also clear navigation if appropriate
            if (shouldClearNavigation) {
              try {
                final deleteNavResponse = await http
                    .delete(
                      Uri.parse(
                        '${ApiConfig.baseUrl}/api/navigation/clear/$orderId'),
                      headers: {'Content-Type': 'application/json'})
                    .timeout(const Duration(seconds: 5));

                if (deleteNavResponse.statusCode == 200) {}
              } catch (e) {
                print('⚠️ Error clearing navigation (fallback): $e');
              }
            } else {
              print(
                '📌 Keeping navigation active for remaining deliveries (fallback)');
              await _saveNavigationState();
            }

            _synchronizeUIWithDatabaseStatus('delivered');
            return;
          }
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception(
          'Failed to check order status: ${checkResponse.statusCode}');
      }
    } catch (e) {
      print('❌ Error completing delivery for order $orderId: $e');

      if (mounted) {
        TopNotification.error(context, '${AppLocalizations.of(context)?.errorCompletingDelivery ?? AppLocalizations.of(context)!.tr('Error completing delivery')}: $e');
      }

      return;
    } finally {
      _isCompletingDelivery = false;
    }
  }

  Future<void> _saveDeliveryCompletion() async {
    try {
      final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;

      // First, mark navigation as complete
      final String navUrl = '${ApiConfig.baseUrl}/api/navigation/complete';

      final navResponse = await http.post(
        Uri.parse(navUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'order_id': orderId,
          'driver_id': 1, // TODO: Get from authentication
          'completed_at': DateTime.now().toIso8601String(),
          'delivery_location': {
            'lat': _deliveryLocation.latitude,
            'lng': _deliveryLocation.longitude,
          },
          'driver_location': {
            'lat': _currentLocation!.latitude,
            'lng': _currentLocation!.longitude,
          },
          'delivery_notes': 'Delivered successfully',
        }));

      if (navResponse.statusCode == 200 || navResponse.statusCode == 201) {
      } else {}

      // Second, mark order as delivered in the orders system
      final String orderUrl =
          '${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/mark-delivered';

      final orderResponse = await http.post(
        Uri.parse(orderUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'driver_id': 1, // TODO: Get from authentication
          'delivered_at': DateTime.now().toIso8601String(),
          'delivery_notes': 'Delivered successfully via navigation system',
        }));

      if (orderResponse.statusCode == 200 || orderResponse.statusCode == 201) {
        final responseData = json.decode(orderResponse.body);
      } else {
        print(
          '❌ Failed to mark order as delivered: ${orderResponse.statusCode}');
      }
    } catch (e) {}
  }

  Future<void> _saveDeliveryPhaseStart() async {
    try {
      final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;

      final String url = '${ApiConfig.baseUrl}/api/navigation/delivery-start';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'order_id': orderId,
          'driver_id': 1, // TODO: Get from authentication
          'current_phase': 'toDelivery',
          'navigation_started': true,
          'delivery_started_at': DateTime.now().toIso8601String(),
          'pickup_completed_at': DateTime.now().toIso8601String(),
          'current_location': {
            'lat': _currentLocation!.latitude,
            'lng': _currentLocation!.longitude,
          },
          'pickup_location': {
            'lat': _pickupLocation.latitude,
            'lng': _pickupLocation.longitude,
          },
          'delivery_location': {
            'lat': _deliveryLocation.latitude,
            'lng': _deliveryLocation.longitude,
          },
          'security_code': _securityCode,
        }));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {}
      } else {}
    } catch (e) {}
  }

  // Multi-Order Save Methods

  Future<void> _saveMultiOrderPickupCompletion() async {
    try {
      final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;

      final currentPickupOrderId = _currentPickupIndex < _allOrders.length
          ? (_allOrders[_currentPickupIndex]['order_id'] ??
                _allOrders[_currentPickupIndex]['id'] ??
                0)
          : orderId;

      // CRITICAL: Save pickup success to Google Cloud database immediately
      await _markOrderAsPickedUp(currentPickupOrderId);

      String nextPhase;
      if (_currentPickupIndex + 1 < _allPickupLocations.length) {
        nextPhase = 'multiOrderPickups'; // More pickups remaining
      } else {
        nextPhase =
            'multiOrderDeliveries'; // All pickups done, start deliveries
      }

      // Local multi-order navigation state can be saved to local storage only
      try {
        final String url =
            '${ApiConfig.baseUrl}/api/navigation/multi-order/pickup-completed';

        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'order_id': orderId, // Main navigation session ID
            'driver_id': 1,
            'pickup_index': _currentPickupIndex,
            'current_pickup_order_id': currentPickupOrderId,
            'pickup_completed_at': DateTime.now().toIso8601String(),
            'current_phase': 'multiOrderPickups',
            'next_phase': nextPhase,
            'pickup_location': {
              'lat': _currentPickupIndex < _allPickupLocations.length
                  ? _allPickupLocations[_currentPickupIndex].latitude
                  : _pickupLocation.latitude,
              'lng': _currentPickupIndex < _allPickupLocations.length
                  ? _allPickupLocations[_currentPickupIndex].longitude
                  : _pickupLocation.longitude,
            },
            'driver_location': {
              'lat': _currentLocation!.latitude,
              'lng': _currentLocation!.longitude,
            },
          }));

        if (response.statusCode == 200 || response.statusCode == 201) {
        } else {
          print(
            '⚠️ Multi-order navigation not saved locally (using memory): ${response.body}');
        }
      } catch (navError) {
        print(
          '⚠️ Multi-order navigation save error (order pickup still recorded): $navError');
      }
    } catch (e) {
      print('❌ Error saving multi-order pickup completion: $e');
    }
  }

  // Mark order as picked up in Google Cloud database
  Future<void> _markOrderAsPickedUp(dynamic orderId) async {
    try {
      print(
        '📦 Marking order $orderId as picked up in Google Cloud database...');

      final String url =
          '${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/mark-picked-up';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'driver_id': 1, // TODO: Get from authentication
          'picked_up_at': DateTime.now().toIso8601String(),
          'pickup_notes':
              AppLocalizations.of(context)?.pickedUpSuccessfullyViaNav ?? AppLocalizations.of(context)!.tr('Product picked up successfully via navigation system'),
          'pickup_location': {
            'lat': _currentLocation!.latitude,
            'lng': _currentLocation!.longitude,
          },
        }));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        print(
          '✅ Order $orderId marked as picked up in Google Cloud: ${responseData['message']}');
      } else {
        print('❌ Failed to mark order $orderId as picked up: ${response.body}');
        throw Exception(
          'Failed to mark order as picked up: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error marking order $orderId as picked up: $e');
      rethrow; // Re-throw to allow error handling in calling function
    }
  }

  Future<void> _saveMultiOrderDeliveryArrival() async {
    try {
      final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;

      final currentDeliveryOrderId = _currentDeliveryIndex < _allOrders.length
          ? (_allOrders[_currentDeliveryIndex]['order_id'] ??
                _allOrders[_currentDeliveryIndex]['id'] ??
                0)
          : orderId;

      final String url =
          '${ApiConfig.baseUrl}/api/navigation/multi-order/arrived-delivery';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'order_id': orderId, // Main navigation session ID
          'driver_id': 1,
          'delivery_index': _currentDeliveryIndex,
          'current_delivery_order_id': currentDeliveryOrderId,
          'arrived_at_delivery': DateTime.now().toIso8601String(),
          'current_phase': 'multiOrderDeliveries',
          'security_code_shown': _showSecurityCode,
          'delivery_location': {
            'lat': _currentDeliveryIndex < _allDeliveryLocations.length
                ? _allDeliveryLocations[_currentDeliveryIndex].latitude
                : _deliveryLocation.latitude,
            'lng': _currentDeliveryIndex < _allDeliveryLocations.length
                ? _allDeliveryLocations[_currentDeliveryIndex].longitude
                : _deliveryLocation.longitude,
          },
          'driver_location': {
            'lat': _currentLocation!.latitude,
            'lng': _currentLocation!.longitude,
          },
        }));

      if (response.statusCode == 200 || response.statusCode == 201) {
      } else {}
    } catch (e) {}
  }

  Future<void> _saveMultiOrderDeliveryCompletion() async {
    try {
      final orderId = widget.order['order_id'] ?? widget.order['id'] ?? 0;

      final currentDeliveryOrderId = _currentDeliveryIndex < _allOrders.length
          ? (_allOrders[_currentDeliveryIndex]['order_id'] ??
                _allOrders[_currentDeliveryIndex]['id'] ??
                0)
          : orderId;

      // Check if this is the final delivery
      bool isFinalDelivery =
          (_currentDeliveryIndex + 1) >= _allDeliveryLocations.length;

      // CRITICAL: Save delivery success to Google Cloud database immediately
      await _markOrderAsDelivered(currentDeliveryOrderId);

      String nextPhase = isFinalDelivery ? 'completed' : 'multiOrderDeliveries';

      // Local multi-order navigation state can be saved to local storage only
      try {
        final String navUrl =
            '${ApiConfig.baseUrl}/api/navigation/multi-order/delivery-completed';

        final navResponse = await http.post(
          Uri.parse(navUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'order_id': orderId, // Main navigation session ID
            'driver_id': 1,
            'delivery_index': _currentDeliveryIndex,
            'current_delivery_order_id': currentDeliveryOrderId,
            'delivery_completed_at': DateTime.now().toIso8601String(),
            'current_phase': 'multiOrderDeliveries',
            'next_phase': nextPhase,
            'is_final_delivery': isFinalDelivery,
            'delivery_location': {
              'lat': _currentDeliveryIndex < _allDeliveryLocations.length
                  ? _allDeliveryLocations[_currentDeliveryIndex].latitude
                  : _deliveryLocation.latitude,
              'lng': _currentDeliveryIndex < _allDeliveryLocations.length
                  ? _allDeliveryLocations[_currentDeliveryIndex].longitude
                  : _deliveryLocation.longitude,
            },
            'driver_location': {
              'lat': _currentLocation!.latitude,
              'lng': _currentLocation!.longitude,
            },
          }));

        if (navResponse.statusCode == 200 || navResponse.statusCode == 201) {
        } else {
          print(
            '⚠️ Multi-order navigation not saved locally (using memory): ${navResponse.body}');
        }
      } catch (navError) {
        print(
          '⚠️ Multi-order navigation save error (order delivery still recorded): $navError');
      }
    } catch (e) {
      print('❌ Error saving multi-order delivery completion: $e');
    }
  }

  // Mark order as delivered in Google Cloud database
  Future<void> _markOrderAsDelivered(dynamic orderId) async {
    try {
      print(
        '📦 Marking order $orderId as delivered in Google Cloud database...');

      final String url =
          '${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/mark-delivered';

      final Map<String, dynamic> requestBody = {
        'driver_id': 1, // TODO: Get from authentication
        'delivered_at': DateTime.now().toIso8601String(),
        'delivery_notes':
            AppLocalizations.of(context)?.deliveredSuccessfullyViaNav ?? AppLocalizations.of(context)!.tr('Order delivered successfully via navigation system'),
      };
      if (_currentLocation != null) {
        requestBody['delivery_location'] = {
          'lat': _currentLocation!.latitude,
          'lng': _currentLocation!.longitude,
        };
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        print(
          '✅ Order $orderId marked as delivered in Google Cloud: ${responseData['message']}');
      } else {
        final responseBody = response.body;
        print('❌ Failed to mark order $orderId as delivered: HTTP ${response.statusCode} - $responseBody');
        throw Exception(
          'Failed to mark order as delivered: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error marking order $orderId as delivered: $e');
      rethrow; // Re-throw to allow error handling in calling function
    }
  }

  String _getCurrentInstruction() {
    if (_currentLocation == null) {
      return AppLocalizations.of(context)?.waitingForGpsLocation ?? AppLocalizations.of(context)!.tr('Waiting for GPS location...');
    }

    // Determine destination based on current phase and multi-order mode
    // CRITICAL: Use SAME logic as _updateCurrentDistanceAndTime() for consistency
    LatLng destination;

    // CRITICAL: Always prioritize pickup locations for pickup phases
    if (_currentPhase == NavigationPhase.toPickup ||
        _currentPhase == NavigationPhase.multiOrderPickups ||
        _currentPhase == NavigationPhase.atPickup) {
      // ADDED atPickup phase!
      // For pickup phases, ALWAYS navigate to pickup location
      if (_isMultiOrderMode &&
          _currentPickupIndex < _allPickupLocations.length) {
        destination = _allPickupLocations[_currentPickupIndex];
        // CRITICAL FIX: Check if destination coordinates are valid
        if (destination.latitude == 0.0 && destination.longitude == 0.0) {
          destination = _pickupLocation;
        }
      } else {
        destination = _pickupLocation;
      }
    } else if (_currentPhase == NavigationPhase.toDelivery ||
        _currentPhase == NavigationPhase.multiOrderDeliveries) {
      // For delivery phases, navigate to delivery location
      if (_isMultiOrderMode &&
          _currentDeliveryIndex < _allDeliveryLocations.length) {
        destination = _allDeliveryLocations[_currentDeliveryIndex];
        // CRITICAL FIX: Check if destination coordinates are valid
        if (destination.latitude == 0.0 && destination.longitude == 0.0) {
          destination = _deliveryLocation;
        }
      } else {
        destination = _deliveryLocation;
      }
    } else {
      // Fallback - default to pickup for all other phases
      destination = _pickupLocation;
    }

    double distance = _calculateDistance(_currentLocation!, destination);

    // DEBUG: Log destination consistency check
    print(
      '🎯 _getCurrentInstruction DESTINATION: Phase=$_currentPhase, Coords=${destination.latitude.toStringAsFixed(6)}, ${destination.longitude.toStringAsFixed(6)}, Distance=${(distance / 1000).toStringAsFixed(3)}km');

    if (_isLoadingRoute) {
      return AppLocalizations.of(context)?.calculatingRoute ?? AppLocalizations.of(context)!.tr('Calculating route...');
    }

    if (!_navigationStarted) {
      return 'Tap "Go!" to start navigation';
    }

    // ── Scan-phase overrides ──────────────────────────────────────────────────
    // Once the driver tapped "Arrived", stop showing distance/directions and
    // instead show a contextual scan instruction.
    if (_waitingStartTime != null) {
      final isDeliveryPhase =
          _currentPhase == NavigationPhase.toDelivery ||
          (_isMultiOrderMode &&
              _currentPhase == NavigationPhase.multiOrderDeliveries);
      if (_scanPhase == 'loading') {
        // After 1st QR scan – waiting for 2nd (loading/unloading in progress)
        return isDeliveryPhase
            ? (AppLocalizations.of(context)?.waitingForBuyerScan ?? AppLocalizations.of(context)!.tr('Waiting for buyer scan to complete'))
            : (AppLocalizations.of(context)?.loadingUnloadingQrPending ?? AppLocalizations.of(context)!.tr('Loading/unloading in progress – 2nd QR scan pending'));
      }
      // 'waiting' phase – no scan yet
      return isDeliveryPhase
          ? (AppLocalizations.of(context)?.buyerMustScanQr ?? AppLocalizations.of(context)!.tr('Buyer must scan QR code'))
          : (AppLocalizations.of(context)?.operatorMustScanQr ?? AppLocalizations.of(context)!.tr('Operator must scan QR code'));
    }
    // ─────────────────────────────────────────────────────────────────────────

    if (_showQRScanner) {
      return _qrScanResult.isEmpty
          ? (AppLocalizations.of(context)?.waitingForQrCodeScan ?? AppLocalizations.of(context)!.tr(''))
          : _qrScanResult;
    }

    if (_showQRDisplay) {
      return AppLocalizations.of(context)?.showQrCodeToCustomer ?? AppLocalizations.of(context)!.tr('Show QR Code to customer for delivery verification');
    }

    // DEBUG: Check current state for arrived button logic
    print(
      '🔍 Arrived button check: navigationStarted=$_navigationStarted, phase=$_currentPhase, distance=${(distance / 1000).toStringAsFixed(1)}km');
    print(
      '🔍 Current UI state: showArrived=$_showArrivedButton, showSecurity=$_showSecurityCode, showQR=$_showQRScanner');

    // Show arrived button when navigation is active.
    // For delivery phases, do not enforce a distance radius.
    // For pickup phases, keep the 5km safeguard.
    bool shouldShowArrivedButton = false;

    if (_navigationStarted &&
        (_currentPhase == NavigationPhase.toPickup ||
            _currentPhase == NavigationPhase.atPickup ||
            _currentPhase == NavigationPhase.multiOrderPickups ||
            _currentPhase == NavigationPhase.toDelivery ||
            _currentPhase == NavigationPhase.multiOrderDeliveries)) {
      final isDeliveryPhase =
          _currentPhase == NavigationPhase.toDelivery ||
          _currentPhase == NavigationPhase.multiOrderDeliveries;

      // Delivery: always allow arrival/check flow (no radius lock).
      // Pickup: still require <= 5 km.
      if (isDeliveryPhase || distance <= 5000) {
        shouldShowArrivedButton = true;
        print(
          isDeliveryPhase
              ? '🔘 Delivery phase active - showing arrived button without radius lock'
              : '🔘 Within 5km radius (${(distance / 1000).toStringAsFixed(1)}km) - showing arrived button');
      } else {
        print(
          '🔘 Too far from destination (${(distance / 1000).toStringAsFixed(1)}km > 5km) - hiding arrived button');
      }
    }

    if (shouldShowArrivedButton &&
        !_showArrivedButton &&
        !_showSecurityCode &&
        !_showQRScanner &&
        !_showQRDisplay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _showArrivedButton = true;
          });
        }
      });
    } else if (!shouldShowArrivedButton && _showArrivedButton) {
      // Hide arrived button if conditions no longer met
      print('❌ Hiding arrived button - conditions not met');
    }

    if (distance < 100) {
      if (_currentPhase == NavigationPhase.toPickup ||
          _currentPhase == NavigationPhase.atPickup ||
          (_isMultiOrderMode &&
              _currentPhase == NavigationPhase.multiOrderPickups)) {
        return _isMultiOrderMode
            ? '${AppLocalizations.of(context)?.arrivedAtPickupLocation ?? AppLocalizations.of(context)!.tr('Arrived at pickup location')} ${_currentPickupIndex + 1}/${_allPickupLocations.length}'
            : (AppLocalizations.of(context)?.arrivedAtPickupLocation ?? AppLocalizations.of(context)!.tr('Arrived at pickup location'));
      } else if (_currentPhase == NavigationPhase.toDelivery ||
          (_isMultiOrderMode &&
              _currentPhase == NavigationPhase.multiOrderDeliveries)) {
        return _isMultiOrderMode
            ? '${AppLocalizations.of(context)?.arrivedAtDeliveryLocation ?? AppLocalizations.of(context)!.tr('Arrived at delivery location')} ${_currentDeliveryIndex + 1}/${_allDeliveryLocations.length}'
            : (AppLocalizations.of(context)?.arrivedAtDeliveryLocation ?? AppLocalizations.of(context)!.tr('Arrived at delivery location'));
      } else {
        return AppLocalizations.of(context)?.arrivedAtDestination ?? AppLocalizations.of(context)!.tr('Arrived at destination');
      }
    }

    // Show real turn-by-turn instruction if available
    if (_routeInstructions.isNotEmpty &&
        _currentInstructionIndex < _routeInstructions.length) {
      String instruction = _routeInstructions[_currentInstructionIndex];

      // Always calculate real distance to next maneuver based on current GPS position
      double realDistance = _calculateDistanceToNextManeuver();

      // Clean instruction of any existing distance info
      String cleanInstruction = instruction;
      if (instruction.contains('In ') &&
          (instruction.contains('km:') || instruction.contains('m:'))) {
        // Extract just the instruction part after the colon
        int colonIndex = instruction.indexOf(':');
        if (colonIndex != -1 && colonIndex < instruction.length - 1) {
          cleanInstruction = instruction.substring(colonIndex + 1).trim();
        }
      }

      // Get app settings for unit system
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      final bool useMetric = appSettings.effectiveDistanceUnit == 'Kilometers';

      // For very long distances (>100km), show highway-style instructions
      if (realDistance > 100000) {
        String distanceStr;
        if (useMetric) {
          distanceStr = "${(realDistance / 1000).round()} km";
        } else {
          distanceStr = "${(realDistance / 1609.34).round()} mi";
        }
        return 'Continue for $distanceStr: $cleanInstruction';
      } else if (realDistance > 1000) {
        if (useMetric) {
          return 'In ${(realDistance / 1000).toStringAsFixed(1)} km: $cleanInstruction';
        } else {
          return 'In ${(realDistance / 1609.34).toStringAsFixed(1)} mi: $cleanInstruction';
        }
      } else {
        if (useMetric) {
          return 'In ${realDistance.round()}m: $cleanInstruction';
        } else {
          return 'In ${(realDistance * 3.28084).round()}ft: $cleanInstruction';
        }
      }
    }

    // Fallback to distance info with better long distance handling and phase-specific messages
    int meters = distance.round();

    // Determine destination type for better user feedback
    String destinationType = 'destination';
    if (_currentPhase == NavigationPhase.toPickup ||
        _currentPhase == NavigationPhase.atPickup ||
        (_isMultiOrderMode &&
            _currentPhase == NavigationPhase.multiOrderPickups)) {
      destinationType = AppLocalizations.of(context)?.pickupLocation ?? AppLocalizations.of(context)!.tr('pickup location');
    } else if (_currentPhase == NavigationPhase.toDelivery ||
        (_isMultiOrderMode &&
            _currentPhase == NavigationPhase.multiOrderDeliveries)) {
      destinationType = AppLocalizations.of(context)?.deliveryLocation ?? AppLocalizations.of(context)!.tr('delivery location');
    }

    // Get app settings for unit system
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final bool useMetric = appSettings.effectiveDistanceUnit == 'Kilometers';

    if (meters > 100000) {
      if (useMetric) {
        int km = (meters / 1000).round();
        return 'Continue towards $destinationType for $km km';
      } else {
        int mi = (meters / 1609.34).round();
        return 'Continue towards $destinationType for $mi mi';
      }
    } else if (meters > 1000) {
      if (useMetric) {
        return 'Continue towards $destinationType for ${(meters / 1000).toStringAsFixed(1)} km';
      } else {
        return 'Continue towards $destinationType for ${(meters / 1609.34).toStringAsFixed(1)} mi';
      }
    } else {
      if (useMetric) {
        return 'Continue towards $destinationType for ${meters}m';
      } else {
        return 'Continue towards $destinationType for ${(meters * 3.28084).round()} ft';
      }
    }
  }

  void _updateNavigationProgress() {
    if (!_navigationStarted ||
        _routeInstructions.isEmpty ||
        _routePoints.isEmpty ||
        _currentLocation == null) {
      return;
    }

    // Find closest point on route to current location
    double minDistanceToRoute = double.infinity;
    int closestRouteIndex = 0;

    for (int i = 0; i < _routePoints.length; i++) {
      double distanceToPoint = _calculateDistance(
        _currentLocation!,
        _routePoints[i]);
      if (distanceToPoint < minDistanceToRoute) {
        minDistanceToRoute = distanceToPoint;
        closestRouteIndex = i;
      }
    }

    // IMPORTANT: If user is more than 200m off route, recalculate route automatically (wrong turn detection)
    if (minDistanceToRoute > 200) {
      print(
        '⚠️ User is ${minDistanceToRoute.toInt()}m off route - recalculating route automatically');
      _generateRoute(); // Automatically recalculate route from current position
      HapticFeedback.heavyImpact(); // Strong feedback for route recalculation
      return;
    }

    // Only update if user is actually following the route (within 200m of route)
    if (minDistanceToRoute < 200) {
      // Update closest route point index for gray coloring of driven sections
      bool needsUpdate = false;

      if (closestRouteIndex != _closestRoutePointIndex) {
        _closestRoutePointIndex = closestRouteIndex;
        needsUpdate = true;
        print(
          '📍 Route progress updated: $_closestRoutePointIndex/${_routePoints.length} points');
      }

      // Calculate bearing (direction) to next route point for map rotation (heading-up mode)
      if (closestRouteIndex < _routePoints.length - 1) {
        double newBearing = _calculateBearing(
          _currentLocation!,
          _routePoints[closestRouteIndex + 1]);

        // Update bearing if changed (more responsive rotation, 2° threshold)
        if ((_currentBearing - newBearing).abs() > 2) {
          setState(() {
            _currentBearing = newBearing;
          });
          needsUpdate = true;

          print(
            '🧭 Rotating map to bearing: $_currentBearing° (route points up) - TRIGGERING UI REBUILD');

          // CRITICAL: Rotate map so route ALWAYS points straight up (heading-up mode)
          // The blue marker stays pointing up, the map rotates around it
          // Rotation happens via setState above which triggers map rebuild with new initialRotation
          try {
            _mapController.move(_currentLocation!, _mapController.camera.zoom);
          } catch (e) {
            print('⚠️ Map move failed: $e');
          }
        }
      }

      // Calculate progress based on position on route
      double routeProgress = closestRouteIndex / (_routePoints.length - 1);
      int newInstructionIndex = (routeProgress * _routeInstructions.length)
          .floor();
      newInstructionIndex = math.min(
        newInstructionIndex,
        _routeInstructions.length - 1);

      // Only update instruction if user has made significant progress along route
      if (newInstructionIndex > _currentInstructionIndex) {
        _currentInstructionIndex = newInstructionIndex;
        needsUpdate = true;

        // Haptic feedback for new instruction
        HapticFeedback.lightImpact();
      }

      // Update UI if route progress changed
      if (needsUpdate) {
        setState(() {
          // Force UI rebuild to show gray route and updated instructions
        });
      }

      // CRITICAL: Update distance and time display while driving
      _updateCurrentDistanceAndTime();
    }
  }

  void _centerOnMyLocation() {
    if (!mounted) return;

    if (_currentLocation == null) {
      print('⚠️ Cannot center on location - GPS not available');
      return;
    }

    try {
      // Center on iOS Apple Maps
      if (Platform.isIOS && _appleMapController != null) {
        print(
          '📍 Centering Apple Maps on current location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
        _appleMapController!.animateCamera(
          apple.CameraUpdate.newCameraPosition(
            apple.CameraPosition(
              target: apple.LatLng(
                _currentLocation!.latitude,
                _currentLocation!.longitude),
              zoom: 16.0)));
        HapticFeedback.mediumImpact();
      } else {
        // Center on Android/other platforms with FlutterMap
        // ALWAYS apply rotation if navigation is active (heading-up mode)
        if (_navigationStarted) {
          // Recalculate bearing if we have route points
          if (_routePoints.length >= 2) {
            // Find next route point
            int closestIndex = 0;
            double minDistance = double.infinity;
            for (int i = 0; i < _routePoints.length; i++) {
              double distance = _calculateDistance(
                _currentLocation!,
                _routePoints[i]);
              if (distance < minDistance) {
                minDistance = distance;
                closestIndex = i;
              }
            }

            // Calculate bearing to next point
            if (closestIndex < _routePoints.length - 1) {
              double newBearing = _calculateBearing(
                _currentLocation!,
                _routePoints[closestIndex + 1]);

              setState(() {
                _currentBearing = newBearing;
              });

              print(
                '🧭 My Location clicked - rotating to bearing: $_currentBearing°');

              // Wait for rebuild with new rotation, then center the map
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted && _currentLocation != null) {
                  _mapController.move(_currentLocation!, 16.0);
                  print('✅ Map centered with rotation: $_currentBearing°');
                }
              });
              return; // Exit early, map will be centered after rebuild
            }
          }

          // No bearing update needed, just center the map
          _mapController.move(_currentLocation!, 16.0);
        } else {
          _mapController.move(_currentLocation!, 16.0);
        }

        HapticFeedback.mediumImpact();
        print(
          '📍 Map centered on current location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
      }
    } catch (e) {
      print('❌ Error centering on location: $e');
    }
  }

  // Custom animated checkmark widget
  Widget _buildAnimatedCheckmark() {
    return AnimatedBuilder(
      animation: _checkmarkAnimation,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(100, 100),
          painter: CheckmarkPainter(_checkmarkAnimation.value));
      });
  }

  // Modern completion celebration widget with confetti effect
  Widget _buildCompletionCelebration(bool isLight) {
    return AnimatedBuilder(
      animation: _confettiAnimation,
      builder: (context, child) {
        return Stack(
          children: [
            // Floating confetti particles
            ...List.generate(12, (index) {
              final angle =
                  (index * 30.0) * (3.14159 / 180); // Convert to radians
              final distance = _confettiAnimation.value * 100;
              final x = math.cos(angle) * distance;
              final y =
                  math.sin(angle) * distance - _confettiAnimation.value * 20;

              return Positioned(
                left: 120 + x,
                top: 120 + y,
                child: Opacity(
                  opacity: (1.0 - _confettiAnimation.value).clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: _confettiAnimation.value * 4 + angle,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: [
                          Colors.yellow,
                          Colors.orange,
                          Colors.pink,
                          Colors.purple,
                          Colors.blue,
                          Colors.green,
                        ][index % 6],
                        borderRadius: BorderRadius.circular(20))))));
            }),
          ]);
      });
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final isLight = appSettings.isLightMode(context);

    print(
      '🔍 Building UI - _navigationStarted: $_navigationStarted'); // Debug log

    return Scaffold(
      backgroundColor: isLight
          ? const Color(0xFFF2F2F7)
          : const Color(0xFF0B0B0D),
      body: SafeArea(
        bottom: false,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top Controls Bar ─────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _NavCloseButton(onTap: () => _closeNavigation(context)),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getNavigationPhaseText(),
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                          letterSpacing: -0.3,
                          height: 1.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                      SizedBox(height: 1),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _getPhaseAccentColor(),
                              shape: BoxShape.circle)),
                          SizedBox(width: 5),
                          Text(
                            '#${widget.order['order_id'] ?? widget.order['id'] ?? AppLocalizations.of(context)!.tr('–')}',
                            style: TextStyle(
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.38),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2)),
                        ]),
                    ])),
                if (!_showQRScanner && !_showQRDisplay) ...[
                  SizedBox(width: 8),
                  _TopNavButton(
                    icon: _navigationStarted
                        ? CupertinoIcons.location_north_fill
                        : CupertinoIcons.location,
                    onTap: _centerOnMyLocation,
                    isLight: isLight),
                ],
                if (_navigationStarted &&
                    _currentPhase != NavigationPhase.completed) ...[
                  SizedBox(width: 8),
                  _TopNavButton(
                    icon: _externalMapApp == 'apple'
                        ? CupertinoIcons.map_fill
                        : CupertinoIcons.map,
                    onTap: _showMapAppSheet,
                    isLight: isLight),
                ],
              ])),
          Divider(
            height: 1,
            thickness: 0.5,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.08)),
          // ── Map + overlays ────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                // Map Layer
                Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
                child: Platform.isIOS
                  ? apple.AppleMap(
                      onMapCreated: (apple.AppleMapController controller) {
                        _appleMapController = controller;
                        print('🍎 Apple Maps created in Navigation Modal');
                        print(
                          '🍎 Initial position: ${(_currentLocation ?? _pickupLocation).latitude}, ${(_currentLocation ?? _pickupLocation).longitude}');

                        // Move camera to show route after map is created
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_routePoints.isNotEmpty) {
                            _centerAppleMapOnRoute();
                          } else if (_currentLocation != null ||
                              (_pickupLocation.latitude != 0.0 &&
                                  _pickupLocation.longitude != 0.0)) {
                            // Center on current location or pickup if no route yet
                            final center = _currentLocation ?? _pickupLocation;
                            controller.animateCamera(
                              apple.CameraUpdate.newCameraPosition(
                                apple.CameraPosition(
                                  target: apple.LatLng(
                                    center.latitude,
                                    center.longitude),
                                  zoom: 14.0)));
                          }
                        });
                      },
                      initialCameraPosition: apple.CameraPosition(
                        target: apple.LatLng(
                          _pickupLocation.latitude != 0.0
                              ? _pickupLocation.latitude
                              : 50.8503, // Fallback to Frankfurt
                          _pickupLocation.longitude != 0.0
                              ? _pickupLocation.longitude
                              : 4.3517),
                        zoom: 14.0),
                      mapType: apple.MapType.standard,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      compassEnabled: true,
                      trafficEnabled: false,
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      rotateGesturesEnabled: true,
                      pitchGesturesEnabled: true,
                      polylines: _buildAppleMapsPolylines(),
                      annotations: _buildAppleMapsAnnotations(isLight),
                      onTap: (apple.LatLng position) {
                        print(
                          '🍎 Navigation Map tapped at: ${position.latitude}, ${position.longitude}');
                      },
                      onCameraMove: (apple.CameraPosition position) {
                        print(
                          '🍎 Navigation Camera: zoom=${position.zoom}, lat=${position.target.latitude}');
                      })
                  : FlutterMap(
                      key: ValueKey(
                        'flutter_map_rotation_${_currentBearing.toStringAsFixed(0)}'),
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentLocation ?? _pickupLocation,
                        initialZoom: 12,
                        initialRotation: _navigationStarted
                            ? -_currentBearing
                            : 0.0,
                        minZoom: 8,
                        maxZoom: 18,
                        // Better interaction settings for mobile
                        // CRITICAL: Allow rotation during navigation so we can programmatically rotate
                        interactionOptions: InteractionOptions(
                          flags: _navigationStarted
                              ? (InteractiveFlag.drag |
                                    InteractiveFlag.pinchZoom |
                                    InteractiveFlag.rotate)
                              : InteractiveFlag.all),
                        onMapEvent: (event) {
                          // Log map events for debugging network issues
                          if (event is MapEventMoveEnd ||
                              event is MapEventFlingAnimationEnd) {}
                        }),
                      children: [
                        TileLayer(
                          key: ValueKey(
                            'navigation_map_${isLight ? 'light' : 'dark'}'),
                          // CartoDB Voyager - Same as delvioo_maps_page
                          urlTemplate: isLight
                              ? MapTileConfig.lightUrl
                              : MapTileConfig.darkUrl,
                          subdomains: MapTileConfig.subdomains,
                          userAgentPackageName: 'com.cultioo.business',
                          maxNativeZoom: 19,
                          maxZoom: 19,
                          retinaMode: true,
                          panBuffer: 2,
                          keepBuffer: 4,
                          additionalOptions: const {
                            'attribution':
                                '© CartoDB © OpenStreetMap contributors',
                          }),
                        PolylineLayer(polylines: _buildTrafficAwarePolylines()),
                        MarkerLayer(
                          markers: [
                            // Current Location - only show if GPS is available
                            if (_currentLocation != null)
                              Marker(
                                point: _currentLocation!,
                                child: _navigationStarted
                                    ? Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF007AFF),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(
                                                0xFF007AFF).withOpacity(0.5),
                                              blurRadius: 12,
                                              spreadRadius: 3),
                                          ]),
                                        child: Icon(
                                          CupertinoIcons.location_north_fill,
                                          color: Colors.white,
                                          size: 24))
                                    : AnimatedBuilder(
                                        animation: _pulseAnimation,
                                        builder: (context, child) =>
                                            Transform.scale(
                                              scale: _pulseAnimation.value,
                                              child: Container(
                                                width: 16,
                                                height: 16,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      const Color(0xFF007AFF),
                                                      const Color(0xFF0051D5),
                                                    ]),
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(
                                                        0xFF007AFF).withOpacity(0.4),
                                                      blurRadius: 8,
                                                      spreadRadius: 2),
                                                  ]))))),

                            // Multi-Order Mode: Show ALL pickup and delivery locations with numbers
                            if (_isMultiOrderMode) ...[
                              // All Pickup Locations with numbers
                              ...() {
                                // Group pickups by location to count duplicates
                                Map<String, List<int>> pickupGroups = {};
                                for (
                                  int i = 0;
                                  i < _allPickupLocations.length;
                                  i++
                                ) {
                                  String key =
                                      '${_allPickupLocations[i].latitude.toStringAsFixed(5)},${_allPickupLocations[i].longitude.toStringAsFixed(5)}';
                                  pickupGroups.putIfAbsent(key, () => []);
                                  pickupGroups[key]!.add(i);
                                }

                                List<Marker> markers = [];
                                for (var entry in pickupGroups.entries) {
                                  int firstIndex = entry.value.first;
                                  LatLng location =
                                      _allPickupLocations[firstIndex];
                                  int count = entry.value.length;

                                  // Yellow triangle pickup marker + optional count badge
                                  final double sz = count > 1 ? 32.0 : 26.0;
                                  markers.add(
                                    Marker(
                                      point: location,
                                      width: sz,
                                      height: sz,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CustomPaint(
                                            painter: _NavSolidTrianglePainter(
                                              color: firstIndex <= _currentPickupIndex
                                                  ? Colors.green
                                                  : const Color(0xFFFFC107)),
                                            size: Size(sz, sz)),
                                          if (count > 1)
                                            Positioned(
                                              top: 2,
                                              right: 2,
                                              child: Container(
                                                width: 16,
                                                height: 16,
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.75),
                                                  shape: BoxShape.circle),
                                                child: Center(
                                                  child: Text(
                                                    '$count',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700))))),
                                        ])));
                                }
                                return markers;
                              }(),

                              // All Delivery Locations with numbers
                              ...() {
                                // Group deliveries by location to count duplicates
                                Map<String, List<int>> deliveryGroups = {};
                                for (
                                  int i = 0;
                                  i < _allDeliveryLocations.length;
                                  i++
                                ) {
                                  String key =
                                      '${_allDeliveryLocations[i].latitude.toStringAsFixed(5)},${_allDeliveryLocations[i].longitude.toStringAsFixed(5)}';
                                  deliveryGroups.putIfAbsent(key, () => []);
                                  deliveryGroups[key]!.add(i);
                                }

                                List<Marker> markers = [];
                                for (var entry in deliveryGroups.entries) {
                                  int firstIndex = entry.value.first;
                                  LatLng location =
                                      _allDeliveryLocations[firstIndex];
                                  int count = entry.value.length;

                                  // Green rectangle delivery marker + optional count badge
                                  final double dsz = count > 1 ? 32.0 : 22.0;
                                  final deliveryColor = firstIndex <= _currentDeliveryIndex
                                      ? const Color(0xFF66BB6A)
                                      : const Color(0xFF4CAF50);
                                  markers.add(
                                    Marker(
                                      point: location,
                                      width: dsz,
                                      height: dsz,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            width: dsz,
                                            height: dsz,
                                            decoration: BoxDecoration(
                                              color: deliveryColor,
                                              borderRadius: BorderRadius.circular(4),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: deliveryColor.withOpacity(0.5),
                                                  blurRadius: 8,
                                                  spreadRadius: 1,
                                                  offset: const Offset(0, 2)),
                                              ])),
                                          if (count > 1)
                                            Text(
                                              '$count',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700)),
                                        ])));
                                }
                                return markers;
                              }(),
                            ],

                            // Single Order Mode: Show single pickup and delivery
                            if (!_isMultiOrderMode) ...[
                              // Pickup Location - gelbes Dreieck (wie maps page)
                              Marker(
                                point: _pickupLocation,
                                width: 26,
                                height: 26,
                                child: CustomPaint(
                                  painter: _NavSolidTrianglePainter(
                                    color: const Color(0xFFFFC107)),
                                  size: const Size(26, 26))),
                              // Delivery Location - green rectangle (like maps page)
                              Marker(
                                point: _deliveryLocation,
                                width: 22,
                                height: 22,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF4CAF50).withOpacity(0.5),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                        offset: const Offset(0, 2)),
                                    ]))),
                            ],
                          ]),
                      ]))),

          // Bottom Instructions
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                decoration: BoxDecoration(
                  color: isLight
                      ? Colors.white
                      : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isLight ? 0.06 : 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, -4)),
                  ]),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Simplified driver-first panel ──────────────────────
                    Builder(
                      builder: (context) {
                        final rawInstruction = _getCurrentInstruction();
                        final parts = _parseInstructionDistance(rawInstruction);
                        final distPart = parts[0];
                        final textPart = parts[1];

                        String nextActionTitle;
                        String nextActionHint;

                        if (_showQRDisplay) {
                          nextActionTitle = 'Show QR to customer';
                          nextActionHint = 'Wait until customer scan is completed';
                        } else if (_showQRScanner) {
                          nextActionTitle = 'Scan business QR now';
                          nextActionHint = 'Confirm current stop in one scan';
                        } else if (!_navigationStarted) {
                          nextActionTitle = 'Start navigation';
                          nextActionHint = 'Drive to the next stop';
                        } else if (_scanPhase == 'waiting') {
                          nextActionTitle = 'Scan check-in at stop';
                          nextActionHint = 'Then loading timer starts';
                        } else if (_scanPhase == 'loading') {
                          nextActionTitle = 'Scan check-out at stop';
                          nextActionHint = 'Then continue to the next stop';
                        } else {
                          nextActionTitle = 'Follow next instruction';
                          nextActionHint = 'Stay on route';
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TradeRepublicCard.elevated(
                              padding: EdgeInsets.all(14),
                              borderRadius: BorderRadius.circular(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: _getPhaseAccentColor().withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(14)),
                                        child: _isLoadingRoute
                                            ? Center(
                                                child: CultiooLoadingIndicator(size: 22))
                                            : Icon(
                                                _getNavigationIcon(),
                                                size: 24,
                                                color: _getPhaseAccentColor())),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'NEXT',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.7,
                                                color: (isLight ? Colors.black : Colors.white)
                                                    .withValues(alpha: 0.55))),
                                            SizedBox(height: 2),
                                            Text(
                                              nextActionTitle,
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                                height: 1.15,
                                                color: isLight ? Colors.black : Colors.white,
                                                letterSpacing: -0.5),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis),
                                          ])),
                                      if (distPart.isNotEmpty)
                                        Text(
                                          distPart,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            color: _getPhaseAccentColor(),
                                            letterSpacing: -0.8)),
                                    ]),
                                  SizedBox(height: 10),
                                  Text(
                                    nextActionHint,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: (isLight ? Colors.black : Colors.white)
                                          .withValues(alpha: 0.62))),
                                  if (textPart.isNotEmpty) ...[
                                    SizedBox(height: 6),
                                    Text(
                                      textPart,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: (isLight ? Colors.black : Colors.white)
                                            .withValues(alpha: 0.78)),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  ],
                                ])),
                            SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_totalDistance.isNotEmpty && _totalDistance != 'Loading...')
                                  _MetricPill(
                                    label: _totalDistance,
                                    color: _getPhaseAccentColor(),
                                    isLight: isLight),
                                if (_estimatedArrival.isNotEmpty && _estimatedArrival != 'Loading...')
                                  _MetricPill(
                                    label: _estimatedArrival,
                                    color: isLight ? Colors.black : Colors.white,
                                    isLight: isLight,
                                    dimmed: true),
                                if (_waitingStartTime != null)
                                  _MetricPill(
                                    icon: CupertinoIcons.timer,
                                    label: _formatWaitingTime(_waitingElapsedSeconds),
                                    color: const Color(0xFFFFB300),
                                    isLight: isLight),
                              ]),
                          ]);
                      }),

                    SizedBox(height: 10),

                        // Security Code Display with Beautiful Animations
                        if (_showSecurityCode)
                          AnimatedBuilder(
                            animation: _securityCodePanelController,
                            builder: (context, child) {
                              return FadeTransition(
                                opacity: _securityCodeFadeAnimation,
                                child: ScaleTransition(
                                  scale: _securityCodeScaleAnimation,
                                  child: Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                    decoration: BoxDecoration(
                                      color: isLight
                                          ? Colors.white
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(20)),
                                    child: Column(
                                      children: [
                                        // Hero security code
                                        Text(
                                          _securityCode,
                                          style: TextStyle(
                                            color: isLight ? Colors.black : Colors.white,
                                            fontSize: 48,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 8,
                                            fontFamily: 'Poppins',
                                            fontFeatures: const [FontFeature.tabularFigures()]),
                                          textAlign: TextAlign.center),
                                        SizedBox(height: 4),
                                        // Countdown only while pending
                                        if (_securityCodeCountdown > 0)
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              CultiooLoadingIndicator(size: 14),
                                              SizedBox(width: 6),
                                              Text(
                                                '${AppLocalizations.of(context)?.scannerOpensIn ?? AppLocalizations.of(context)!.tr('Opens in')} $_securityCodeCountdown',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.45))),
                                            ]),
                                        SizedBox(height: 14),
                                        // QR Scanner Button
                                        TradeRepublicButton(
                                          label: AppLocalizations.of(context)?.openQrScanner ?? AppLocalizations.of(context)!.tr('Open QR Scanner'),
                                          icon: Icon(CupertinoIcons.qrcode_viewfinder, size: 22),
                                          onPressed: _showQRCodeScanner),
                                      ]))));
                            }),

                        // QR Code Display for Delivery (Customer scans from driver's phone) - Apple Style Minimalistic
                        if (_showQRDisplay)
                          Container(
                            width: double.infinity,
                            margin: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16),
                            child: Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isLight
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10)),
                                ]),
                              child: Column(
                                children: [
                                  // Header
                                  Container(
                                    width: double.infinity,

                                    decoration: BoxDecoration(
                                      color: isLight
                                          ? const Color(0xFFF2F2F7)
                                          : const Color(0xFF2C2C2E),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(20),
                                        topRight: Radius.circular(20))),
                                    child: Column(
                                      children: [
                                        Text(
                                          AppLocalizations.of(context)?.deliveryQrCode ?? AppLocalizations.of(context)!.tr('Delivery QR Code'),
                                          style: TextStyle(
                                            color: isLight
                                                ? Colors.black
                                                : Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -0.4)),
                                        SizedBox(height: 8),
                                        Text(
                                          AppLocalizations.of(context)?.showThisToCustomer ?? AppLocalizations.of(context)!.tr('Show this to the customer'),
                                          style: TextStyle(
                                            color: isLight
                                                ? Colors.black54
                                                : Colors.white70,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w400)),
                                      ])),

                                  // QR Code
                                  Container(
                                    padding: EdgeInsets.all(32),
                                    child:
                                        _securityCode.isNotEmpty &&
                                            _securityCode != "Loading..."
                                        ? Container(
                                            width: 220,
                                            height: 220,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.05),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4)),
                                              ]),
                                            padding: EdgeInsets.all(16),
                                            child: QrImageView(
                                              data: _generateQRCodeData(),
                                              version: QrVersions.auto,
                                              size: 188.0,
                                              backgroundColor: Colors.white,
                                              dataModuleStyle:
                                                  const QrDataModuleStyle(
                                                    dataModuleShape:
                                                        QrDataModuleShape
                                                            .square,
                                                    color: Colors.black),
                                              eyeStyle: const QrEyeStyle(
                                                eyeShape: QrEyeShape.square,
                                                color: Colors.black)))
                                        : Container(
                                            width: 220,
                                            height: 220,
                                            decoration: BoxDecoration(
                                              color: isLight
                                                  ? const Color(0xFFF2F2F7)
                                                  : const Color(0xFF2C2C2E),
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child:
                                                      CultiooLoadingIndicator(size: 20)),
                                                SizedBox(height: 16),
                                                Text(
                                                  AppLocalizations.of(context)?.loading ?? AppLocalizations.of(context)!.tr('Loading...'),
                                                  style: TextStyle(
                                                    color: isLight
                                                        ? Colors.black54
                                                        : Colors.white70,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500)),
                                              ]))),

                                  // Security Code Display
                                  if (_securityCode.isNotEmpty &&
                                      _securityCode != "Loading...")
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 32,
                                        vertical: 16),
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12),
                                        decoration: BoxDecoration(
                                          color: isLight
                                              ? const Color(0xFFF2F2F7)
                                              : const Color(0xFF2C2C2E),
                                          borderRadius: BorderRadius.circular(
                                            25)),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '${AppLocalizations.of(context)?.codeLabel ?? AppLocalizations.of(context)!.tr('Code')}: ',
                                              style: TextStyle(
                                                color: isLight
                                                    ? Colors.black54
                                                    : Colors.white70,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500)),
                                            Flexible(
                                              child: Text(
                                                _securityCode,
                                                style: TextStyle(
                                                  color: isLight
                                                      ? Colors.black
                                                      : Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 1.0),
                                                overflow: TextOverflow.ellipsis)),
                                          ]))),

                                  // Action Buttons
                                  Container(
                                    child: Column(
                                      children: [
                                        // Complete Delivery Button
                                        SizedBox(width: double.infinity),

                                        SizedBox(height: 12),

                                        // Cancel Button
                                        SizedBox(width: double.infinity),
                                      ])),
                                ]))),

                        // Arrived Button – modern full-width card
                        // Shows "Resume scan" once arrival was already confirmed
                        // (waiting timer already running), otherwise shows the
                        // normal "You have arrived" confirmation button.
                        if (_showArrivedButton)
                          TradeRepublicButton(
                            label: _waitingStartTime != null
                                  ? (AppLocalizations.of(context)?.resumeScan ?? AppLocalizations.of(context)!.tr('Resume Scan'))
                                  : (AppLocalizations.of(context)?.arrivedAtDestination ?? AppLocalizations.of(context)!.tr('You have arrived!')),
                              icon: Icon(
                                _waitingStartTime != null
                                    ? CupertinoIcons.qrcode_viewfinder
                                    : CupertinoIcons.location_fill,
                                size: 22),
                              backgroundColor: _waitingStartTime != null
                                  ? const Color(0xFF007AFF)
                                  : const Color(0xFF22C55E),
                              foregroundColor: Colors.white,
                              width: double.infinity,
                              onPressed: () {
                                if (_currentPhase == NavigationPhase.toDelivery ||
                                    (_isMultiOrderMode &&
                                        _currentPhase == NavigationPhase.multiOrderDeliveries)) {
                                  _markArrivedAtDelivery();
                                } else {
                                  _markAsArrived();
                                }
                              }),

                        // Resume checkout/unloading flow if 2nd QR is still pending
                        // and the scan bottom sheet was closed by mistake.
                        if (_scanPhase == 'loading' &&
                            !_showQRScanner &&
                            !_showQRDisplay &&
                            !_showSecurityCode &&
                            !_isPickupSheetOpen &&
                            !_isDeliverySheetOpen)
                          TradeRepublicButton(
                            label: AppLocalizations.of(context)?.resumeScan ?? AppLocalizations.of(context)!.tr('Resume Scan'),
                            icon: Icon(CupertinoIcons.square_arrow_up_on_square),
                            width: double.infinity,
                            onPressed: _reopenActiveScanBottomSheet),

                        // Delivery sheet quick access (instead of manual delivered action)
                        if ((_currentPhase == NavigationPhase.toDelivery ||
                                (_isMultiOrderMode &&
                                    _currentPhase == NavigationPhase.multiOrderDeliveries)) &&
                            (_waitingStartTime != null || _scanPhase == 'loading') &&
                            !_showArrivedButton &&
                            !_showQRScanner &&
                            !_showQRDisplay &&
                            !_showSecurityCode &&
                            !_isDeliverySheetOpen)
                          TradeRepublicButton(
                            label: AppLocalizations.of(context)!.tr('Open delivery sheet') ?? AppLocalizations.of(context)!.tr('Open delivery sheet'),
                            icon: Icon(CupertinoIcons.rectangle_stack_badge_person_crop),
                            onPressed: _showDeliveryBottomSheet,
                            isSecondary: true),

                        // Go Button - nur wenn Navigation nicht gestartet und nicht abgeschlossen
                        if (!_navigationStarted &&
                            !_showArrivedButton &&
                            !_showSecurityCode &&
                            !_showQRScanner &&
                            !_showQRDisplay &&
                            _currentPhase != NavigationPhase.completed)
                          TradeRepublicButton(
                            label: AppLocalizations.of(context)?.goExclamation ?? AppLocalizations.of(context)!.tr('Go!'),
                            icon: Icon(CupertinoIcons.location_north_fill, size: 22, color: Colors.white),
                            onPressed: _startNavigation),

                        // Navigating Button - darker, non-interactive when navigation has started
                        if (_navigationStarted &&
                            !_showArrivedButton &&
                            !_showSecurityCode &&
                            !_showQRScanner &&
                            !_showQRDisplay &&
                            _currentPhase != NavigationPhase.completed)
                          TradeRepublicButton(
                            label: AppLocalizations.of(context)?.navigating ?? AppLocalizations.of(context)!.tr('Navigating...'),
                            icon: Icon(
                              CupertinoIcons.location_north_fill,
                              size: 20,
                              color: isLight ? Colors.black.withOpacity(0.45) : Colors.white.withOpacity(0.45)),
                            onPressed: null,
                            isSecondary: true),

                        // Modern Animated Completion Message
                        if (_currentPhase == NavigationPhase.completed)
                          AnimatedBuilder(
                            animation: _completionController,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _completionScaleAnimation.value,
                                child: Opacity(
                                  opacity: _completionFadeAnimation.value,
                                  child: Container(
                                    width: double.infinity,
                                    margin: EdgeInsets.symmetric(
                                      horizontal: 8),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Confetti animation overlay
                                        _buildCompletionCelebration(isLight),

                                        // Main completion card
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            25),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                              sigmaX: 20,
                                              sigmaY: 20),
                                            child: Container(
                                              padding: EdgeInsets.all(48),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Colors.green.withOpacity(
                                                      0.3),
                                                    Colors.blue.withOpacity(
                                                      0.2),
                                                  ]),
                                                borderRadius:
                                                    BorderRadius.circular(28),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.green
                                                        .withOpacity(0.3),
                                                    blurRadius: 24,
                                                    spreadRadius: 8),
                                                ]),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Animated checkmark
                                                  _buildAnimatedCheckmark(),

                                                  SizedBox(height: 32),

                                                  // Success text
                                                  Text(
                                                    '🎉 Delivery Completed!',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 32,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: -0.5,
                                                      fontFamily: 'Poppins',
                                                      shadows: [
                                                        Shadow(
                                                          color: Colors.black
                                                              .withOpacity(0.3),
                                                          blurRadius: 10,
                                                          offset: const Offset(
                                                            0,
                                                            3)),
                                                      ])),

                                                  SizedBox(height: 18),

                                                  // Subtitle
                                                  Text(
                                                    AppLocalizations.of(context)?.thankYouForUsingCultioo ?? AppLocalizations.of(context)!.tr('Thank you for using Cultioo Business'),
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      letterSpacing: -0.3,
                                                      fontFamily: 'Poppins')),
                                                ])))),
                                      ]))));
                            }),
                      ]))),

          // Multi-Order Progress Indicator - positioned at the very top
          if (_isMultiOrderMode)
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: _buildMultiOrderProgressIndicator()),

          // Last Mile AI Order Suggestion - Center of screen
          if (_showLastMileOrder && _suggestedOrder != null)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.35,
              left: 20,
              right: 20,
              child: _buildLastMileOrderCard(isLight)),
              ])),
        ])));
  }

  // Build Last Mile order suggestion card
  Widget _buildLastMileOrderCard(bool isLight) {
    if (_suggestedOrder == null) return const SizedBox.shrink();

    final distanceToPickup =
        _suggestedOrder!['distanceToPickup'] as double? ?? 0.0;
    final pickupToDelivery =
        _suggestedOrder!['pickupToDelivery'] as double? ?? 0.0;
    final detourPercentage =
        _suggestedOrder!['detourPercentage'] as double? ?? 0.0;
    final rawOrderValue = _suggestedOrder!['total_price'];
    final orderValue = rawOrderValue is int ? rawOrderValue.toDouble() : (rawOrderValue ?? 0.0) as double;
    final orderId = _suggestedOrder!['order_id'] ??
      (AppLocalizations.of(context)?.naValue ?? AppLocalizations.of(context)!.tr(''));

    // Extract addresses
    final pickupStreet = _suggestedOrder!['pickup_street'] ?? AppLocalizations.of(context)!.tr('');
    final pickupCity = _suggestedOrder!['pickup_city'] ?? AppLocalizations.of(context)!.tr('');
    final pickupZip = _suggestedOrder!['pickup_zip'] ?? AppLocalizations.of(context)!.tr('');
    String pickupAddressText = '';
    if (pickupStreet.toString().isNotEmpty) {
      pickupAddressText = pickupStreet.toString();
      if (pickupCity.toString().isNotEmpty) {
        pickupAddressText += ', $pickupCity';
      }
    } else if (pickupCity.toString().isNotEmpty) {
      pickupAddressText = '$pickupZip $pickupCity';
    }

    // Parse delivery address from JSON
    String deliveryAddressText = '';
    try {
      final deliveryAddr = _suggestedOrder!['deliveryAddress'];
      if (deliveryAddr != null) {
        final addr = deliveryAddr is String ? json.decode(deliveryAddr) : deliveryAddr;
        final street = addr['street'] ?? addr['address'] ?? AppLocalizations.of(context)!.tr('');
        final city = addr['city'] ?? AppLocalizations.of(context)!.tr('');
        if (street.toString().isNotEmpty) {
          deliveryAddressText = street.toString();
          if (city.toString().isNotEmpty) {
            deliveryAddressText += ', $city';
          }
        } else if (city.toString().isNotEmpty) {
          deliveryAddressText = city.toString();
        }
      }
    } catch (_) {}

    // Get app settings for currency
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isLight
                  ? [
                      Colors.white.withOpacity(0.95),
                      Colors.white.withOpacity(0.85),
                    ]
                  : [
                      const Color(0xFF2C2C2E).withOpacity(0.95),
                      Colors.transparent.withOpacity(0.85),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 24,
                offset: const Offset(0, 8),
                spreadRadius: 0),
            ]),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with AI icon and order info
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(20)),
                    child: Icon(
                      CupertinoIcons.sparkles,
                      color: Colors.white,
                      size: 24)),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.aiSuggestion ?? AppLocalizations.of(context)!.tr('AI Suggestion'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white)),
                        SizedBox(height: 2),
                        Text(
                          '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}$orderId',
                          style: TextStyle(
                            fontSize: 13,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.6))),
                      ])),
                  // Order value badge
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      appSettings.formatCurrency(orderValue),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF34C759)))),
                ]),
              SizedBox(height: 16),

              // Maps-style route card with from → to addresses
              TradeRepublicCard(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Pickup row (from)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Green dot (pickup)
                        Column(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF34C759).withOpacity(0.3),
                                    blurRadius: 4),
                                ])),
                            // Dotted line connector
                            Container(
                              width: 2,
                              height: 30,
                              margin: EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: (isLight ? Colors.black : Colors.white).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(1))),
                          ]),
                        SizedBox(width: 12),
                        // Pickup address info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)?.pickup ?? AppLocalizations.of(context)!.tr('Pickup'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF34C759),
                                  letterSpacing: 0.5)),
                              SizedBox(height: 2),
                              Text(
                                pickupAddressText.isNotEmpty 
                                    ? pickupAddressText 
                                    : (AppLocalizations.of(context)?.pickupAddress ?? AppLocalizations.of(context)!.tr('Pickup Address')),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isLight ? Colors.black : Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            ])),
                        // Distance to pickup
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            appSettings.formatDistance(distanceToPickup / 1000),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.7)))),
                      ]),

                    // Delivery row (to)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Red dot (delivery)
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF3B30).withOpacity(0.3),
                                blurRadius: 4),
                            ])),
                        SizedBox(width: 12),
                        // Delivery address info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)?.delivery ?? AppLocalizations.of(context)!.tr('Delivery'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFFF3B30),
                                  letterSpacing: 0.5)),
                              SizedBox(height: 2),
                              Text(
                                deliveryAddressText.isNotEmpty 
                                    ? deliveryAddressText 
                                    : (AppLocalizations.of(context)?.deliveryAddress ?? AppLocalizations.of(context)!.tr('Delivery Address')),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isLight ? Colors.black : Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            ])),
                        // Pickup to delivery distance
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            appSettings.formatDistance(pickupToDelivery / 1000),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.7)))),
                      ]),
                  ])),
              SizedBox(height: 12),

              // Distance chips row
              Row(
                children: [
                  Expanded(
                    child: _buildInfoChip(
                      icon: CupertinoIcons.location_fill,
                      label: appSettings.formatDistance(
                        distanceToPickup / 1000),
                      subtitle: AppLocalizations.of(context)?.toPickup ?? AppLocalizations.of(context)!.tr('to pickup'),
                      isLight: isLight)),
                  SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      icon: CupertinoIcons.cube_box,
                      label: appSettings.formatDistance(
                        pickupToDelivery / 1000),
                      subtitle: AppLocalizations.of(context)?.pickupToDelivery ?? AppLocalizations.of(context)!.tr('Pickup → Delivery'),
                      isLight: isLight)),
                  SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      icon: CupertinoIcons.map,
                      label:
                          '+${detourPercentage.toStringAsFixed(0)}${String.fromCharCode(37)}',
                      subtitle: AppLocalizations.of(context)?.detour ?? AppLocalizations.of(context)!.tr('detour'),
                      isLight: isLight,
                      color: detourPercentage < 15
                          ? const Color(0xFF34C759)
                          : detourPercentage < 25
                          ? const Color(0xFFFF9500)
                          : const Color(0xFFFF3B30))),
                ]),
              SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  // Decline Button
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.skip ?? AppLocalizations.of(context)!.tr('Skip'),
                      isSecondary: true,
                      onPressed: _declineLastMileOrder)),
                  SizedBox(width: 12),
                  // Bid Button
                  Expanded(
                    flex: 2,
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.placeBid ?? AppLocalizations.of(context)!.tr('Place Bid'),
                      icon: Icon(CupertinoIcons.hammer),
                      tint: const Color(0xFF007AFF),
                      onPressed: _showBidBottomSheet)),
                ]),
            ]))));
  }

  // Helper widget for info chips in Last Mile card
  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isLight,
    Color? color,
  }) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.white.withOpacity(0.6)
            : Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Icon(
            icon,
            color: color ?? (isLight ? Colors.black : Colors.white),
            size: 20),
          SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color ?? (isLight ? Colors.black : Colors.white))),
          SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
        ]));
  }

  /// Splits a navigation instruction string into [distancePart, actionText].
  /// e.g. "In 1.2 km: Turn right onto Main St" → ["1.2 km", "Turn right onto Main St"]
  /// Returns ['', fullInstruction] if no distance prefix found.
  List<String> _parseInstructionDistance(String instruction) {
    // "In 1.2 km: Turn right" / "In 300 m: Continue" / "In 500ft: Turn left"
    final inPattern = RegExp(r'^In (.+?): (.+)$');
    final inMatch = inPattern.firstMatch(instruction);
    if (inMatch != null) {
      return [inMatch.group(1)!.trim(), inMatch.group(2)!.trim()];
    }
    // "Continue for 5 km: Head straight"
    final contForPattern = RegExp(r'^Continue for (.+?): (.+)$');
    final contForMatch = contForPattern.firstMatch(instruction);
    if (contForMatch != null) {
      return [contForMatch.group(1)!.trim(), contForMatch.group(2)!.trim()];
    }
    // "Continue towards pickup location for 1.2 km"
    final contTowardsPattern = RegExp(r'^(Continue towards .+?) for (.+)$');
    final contTowardsMatch = contTowardsPattern.firstMatch(instruction);
    if (contTowardsMatch != null) {
      return [contTowardsMatch.group(2)!.trim(), contTowardsMatch.group(1)!.trim()];
    }
    return ['', instruction];
  }

  // Get accent color based on current navigation phase
  Color _getPhaseAccentColor() {
    switch (_currentPhase) {
      case NavigationPhase.toPickup:
      case NavigationPhase.multiOrderPickups:
        return const Color(0xFF2B8CFF); // blue — to pickup
      case NavigationPhase.atPickup:
        return const Color(0xFFFFB300); // amber — at pickup (waiting)
      case NavigationPhase.toDelivery:
      case NavigationPhase.multiOrderDeliveries:
        return const Color(0xFF19C95C); // green — to delivery
      case NavigationPhase.completed:
        return const Color(0xFF19C95C); // green — done
    }
  }

  // Get navigation icon based on current instruction
  IconData _getNavigationIcon() {
    String instruction = _getCurrentInstruction().toLowerCase();

    // Check for specific navigation instructions
    if (instruction.contains('turn left') || instruction.contains('links')) {
      return CupertinoIcons.arrow_turn_up_left;
    } else if (instruction.contains('turn right') ||
        instruction.contains('rechts')) {
      return CupertinoIcons.arrow_turn_up_right;
    } else if (instruction.contains('straight') ||
        instruction.contains('continue') ||
        instruction.contains('geradeaus')) {
      return CupertinoIcons.arrow_up;
    } else if (instruction.contains('roundabout') ||
        instruction.contains('kreisverkehr')) {
      return CupertinoIcons.arrow_counterclockwise;
    } else if (instruction.contains('merge') ||
        instruction.contains('einfahren')) {
      return CupertinoIcons.arrow_up;
    } else if (instruction.contains('exit') ||
        instruction.contains('ausfahrt')) {
      return CupertinoIcons.arrow_right_square;
    } else if (instruction.contains('arrived') ||
        instruction.contains('angekommen')) {
      return CupertinoIcons.location_fill;
    } else if (_currentPhase == NavigationPhase.toPickup ||
        _currentPhase == NavigationPhase.multiOrderPickups) {
      return CupertinoIcons.bag_fill;
    } else if (_currentPhase == NavigationPhase.toDelivery ||
        _currentPhase == NavigationPhase.multiOrderDeliveries) {
      return CupertinoIcons.house_fill;
    } else {
      return CupertinoIcons.location_north_fill;
    }
  }

  // Get navigation phase text with multi-order support
  String _getNavigationPhaseText() {
    switch (_currentPhase) {
      case NavigationPhase.completed:
        return '✅ Delivery Completed';

      case NavigationPhase.toPickup:
        return '🧭 Navigate to Pickup';

      case NavigationPhase.atPickup:
        return '📦 At Pickup Location';

      case NavigationPhase.toDelivery:
        return '🚛 Navigate to Delivery';

      case NavigationPhase.multiOrderPickups:
        if (_isMultiOrderMode && _allPickupLocations.isNotEmpty) {
          return '📦 Pickup ${_currentPickupIndex + 1} of ${_allPickupLocations.length}';
        }
        return '📦 Navigate to Pickup';

      case NavigationPhase.multiOrderDeliveries:
        if (_isMultiOrderMode && _allDeliveryLocations.isNotEmpty) {
          return '🚛 Delivery ${_currentDeliveryIndex + 1} of ${_allDeliveryLocations.length}';
        }
        return '🚛 Navigate to Delivery';
    }
  }

  // Get pickup address text - same logic as in delvioo_orders_page.dart
  String _getPickupAddress() {
    final orderId = widget.order['order_id'] ?? widget.order['id'] ?? AppLocalizations.of(context)!.tr('unknown');

    debugPrint('🏠 [NavigationModal Order $orderId] Getting pickup address...');

    // For multi-order mode, get address from first order in batch
    if (_isMultiOrderMode && _allOrders.isNotEmpty) {
      final firstOrder = _allOrders[0];
      debugPrint(
        '   Multi-order: Using first order (${firstOrder['order_id'] ?? firstOrder['id']}) for pickup address');
      debugPrint('   pickup_street: ${firstOrder['pickup_street']}');
      debugPrint('   pickup_city: ${firstOrder['pickup_city']}');
      debugPrint('   pickup_zip: ${firstOrder['pickup_zip']}');

      if (firstOrder['pickup_street'] != null &&
          firstOrder['pickup_street'].toString().trim().isNotEmpty) {
        String pickupAddress = firstOrder['pickup_street'].toString().trim();

        if (firstOrder['pickup_city'] != null &&
            firstOrder['pickup_city'].toString().trim().isNotEmpty) {
          pickupAddress += ', ${firstOrder['pickup_city']}';
        }
        if (firstOrder['pickup_zip'] != null &&
            firstOrder['pickup_zip'].toString().trim().isNotEmpty) {
          final cityPart = firstOrder['pickup_city']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
          if (cityPart.isNotEmpty) {
            pickupAddress =
                '${firstOrder['pickup_street']}, ${firstOrder['pickup_zip']} $cityPart';
          } else {
            pickupAddress += ', ${firstOrder['pickup_zip']}';
          }
        }
        final firstCountry = firstOrder['pickup_country']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
        if (firstCountry.isNotEmpty) pickupAddress += ', $firstCountry';
        debugPrint(
          '✅ [NavigationModal Multi-Order] Using pickup address from first order: $pickupAddress');
        return pickupAddress;
      }
    }

    debugPrint('   pickup_street: ${widget.order['pickup_street']}');
    debugPrint('   pickup_city: ${widget.order['pickup_city']}');
    debugPrint('   pickup_zip: ${widget.order['pickup_zip']}');
    debugPrint('   product_seller: ${widget.order['product_seller']}');

    // Priority 1: Use pickup_street + pickup_city from backend database (FIRST PRIORITY - like orders_page!)
    if (widget.order['pickup_street'] != null &&
        widget.order['pickup_street'].toString().trim().isNotEmpty) {
      String pickupAddress = widget.order['pickup_street'].toString().trim();

      // Check if pickup_street already contains a complete address (contains numbers and city)
      final street = pickupAddress.toLowerCase();
      final city = widget.order['pickup_city']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');

      // If pickup_street already contains the city name, use it as is
      if (city.isNotEmpty && street.contains(city)) {
        debugPrint(
          '✅ [NavigationModal Order $orderId] Using complete pickup address from database (street contains city): $pickupAddress');
        return pickupAddress;
      }

      // Otherwise, build the address by combining components
      if (widget.order['pickup_city'] != null &&
          widget.order['pickup_city'].toString().trim().isNotEmpty) {
        pickupAddress += ', ${widget.order['pickup_city']}';
      }
      if (widget.order['pickup_zip'] != null &&
          widget.order['pickup_zip'].toString().trim().isNotEmpty) {
        final cityPart = widget.order['pickup_city']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
        if (cityPart.isNotEmpty) {
          pickupAddress =
              '${widget.order['pickup_street']}, ${widget.order['pickup_zip']} $cityPart';
        } else {
          pickupAddress += ', ${widget.order['pickup_zip']}';
        }
      }
      final pickupCountry = widget.order['pickup_country']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
      if (pickupCountry.isNotEmpty) pickupAddress += ', $pickupCountry';
      debugPrint(
        '✅ [NavigationModal Order $orderId] Using constructed pickup address from database: $pickupAddress');
      return pickupAddress;
    }

    // Priority 2: Check for Apple products (use Apple Store for demo purposes)
    final cartItems = widget.order['cart'] as List<dynamic>? ?? [];
    final hasAppleProduct = cartItems.any(
      (item) =>
          (item['name'] ?? AppLocalizations.of(context)!.tr('')).toString().toLowerCase().contains('apple') ||
          (item['title'] ?? AppLocalizations.of(context)!.tr('')).toString().toLowerCase().contains('apple'));

    if (hasAppleProduct) {
      const appleAddress = 'Jungfernstieg 12, 20354 Hamburg';
      debugPrint(
        '✅ [NavigationModal Order $orderId] Apple product - using Apple Store: $appleAddress');
      return appleAddress;
    }

    // Priority 3: Use business address from seller info
    if (widget.order['businessAddress'] != null &&
        widget.order['businessAddress'].toString().trim().isNotEmpty) {
      final address = widget.order['businessAddress'].toString().trim();
      debugPrint(
        '✅ [NavigationModal Order $orderId] Using businessAddress: $address');
      return address;
    }

    // Priority 4: Generic fallback - no hardcoded addresses
    debugPrint(
      '⚠️ [NavigationModal Order $orderId] No pickup address found - using generic fallback');
    return AppLocalizations.of(context)?.storeLocationContactSeller ?? AppLocalizations.of(context)!.tr('Store Location - Contact Seller');
  }

  // NEW: Complete navigation cleanup methods for multi-order reset

  Future<void> _clearAllNavigationSessions() async {
    try {
      // Clear current session
      await _clearNavigationSession();

      // Clear all multi-order sessions for this driver
      final response = await http.delete(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/navigation/clear-all/1'), // Driver ID 1
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
      } else {
        print(
          '⚠️ Could not clear all navigation sessions: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error clearing all navigation sessions: $e');
    }
  }

  Future<void> _resetAllNavigationDataForNewMultiOrder() async {
    try {
      print(
        '🔄 Resetting ALL navigation data for new multi-order capability...');

      // Clear SharedPreferences completely
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('multi_order_session_id');
      await prefs.remove('navigation_state');
      await prefs.remove('quick_navigation_state');

      // Clear any cached navigation data
      final allKeys = prefs.getKeys();
      for (String key in allKeys) {
        if (key.startsWith('navigation_') || key.startsWith('multi_order_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      print('❌ Error resetting navigation data: $e');
    }
  }

  Future<void> _clearAllDriverNavigationSessions() async {
    try {
      // Delete all navigation records for this driver
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/navigation/driver/1/clear-all'),
        headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
      } else {
        print('⚠️ Could not clear driver sessions: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error clearing driver navigation sessions: $e');
    }
  }

  void _performCompleteStateReset() {
    // Reset ALL navigation variables to initial state
    _currentPhase = NavigationPhase.toPickup;
    _navigationStarted = false;
    _showArrivedButton = false;
    _showSecurityCode = false;
    _showQRScanner = false;
    _showQRDisplay = false;
    _currentInstructionIndex = 0;

    // Reset multi-order state
    _isMultiOrderMode = false;
    _currentPickupIndex = 0;
    _currentDeliveryIndex = 0;
    _multiOrderSessionId = null;
  }

  // Center Apple Maps camera to show entire route
  void _centerAppleMapOnRoute() {
    if (_appleMapController == null || _routePoints.isEmpty) return;

    print(
      '🍎 Centering Apple Maps on route with ${_routePoints.length} points');

    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;

    for (var point in _routePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    // Calculate appropriate zoom level
    final latDiff = (maxLat - minLat).abs();
    final lngDiff = (maxLng - minLng).abs();
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    double zoom = 14.0;
    if (maxDiff > 0.1) {
      zoom = 11.0;
    } else if (maxDiff > 0.05)
      zoom = 12.0;
    else if (maxDiff > 0.02)
      zoom = 13.0;

    print('🍎 Moving camera to: $centerLat, $centerLng, zoom: $zoom');

    _appleMapController!.animateCamera(
      apple.CameraUpdate.newCameraPosition(
        apple.CameraPosition(
          target: apple.LatLng(centerLat, centerLng),
          zoom: zoom)));
  }

  // Build Apple Maps polylines from route points
  Set<apple.Polyline> _buildAppleMapsPolylines() {
    if (_routePoints.isEmpty) return {};

    return {
      apple.Polyline(
        polylineId: apple.PolylineId('route'),
        points: _routePoints
            .map((point) => apple.LatLng(point.latitude, point.longitude))
            .toList(),
        color: const Color(0xFF007AFF), // Apple Blue
        width: 5),
    };
  }

  // Build Apple Maps annotations (markers) for navigation
  Set<apple.Annotation> _buildAppleMapsAnnotations(bool isLight) {
    Set<apple.Annotation> annotations = {};

    // Pickup location marker
    if (_pickupLocation.latitude != 0.0 && _pickupLocation.longitude != 0.0) {
      annotations.add(
        apple.Annotation(
          annotationId: apple.AnnotationId('pickup'),
          position: apple.LatLng(
            _pickupLocation.latitude,
            _pickupLocation.longitude),
          infoWindow: apple.InfoWindow(title: AppLocalizations.of(context)?.pickupLocation ?? AppLocalizations.of(context)!.tr('Pickup Location'))));
    }

    // Delivery location marker
    if (_deliveryLocation.latitude != 0.0 &&
        _deliveryLocation.longitude != 0.0) {
      annotations.add(
        apple.Annotation(
          annotationId: apple.AnnotationId('delivery'),
          position: apple.LatLng(
            _deliveryLocation.latitude,
            _deliveryLocation.longitude),
          infoWindow: apple.InfoWindow(title: AppLocalizations.of(context)?.deliveryLocation ?? AppLocalizations.of(context)!.tr('Delivery Location'))));
    }

    // Multi-order pickup markers
    if (_isMultiOrderMode) {
      for (int i = 0; i < _allPickupLocations.length; i++) {
        annotations.add(
          apple.Annotation(
            annotationId: apple.AnnotationId('pickup_$i'),
            position: apple.LatLng(
              _allPickupLocations[i].latitude,
              _allPickupLocations[i].longitude),
            infoWindow: apple.InfoWindow(title: '${AppLocalizations.of(context)?.pickup ?? AppLocalizations.of(context)!.tr('Pickup')} ${i + 1}')));
      }

      // Multi-order delivery markers
      for (int i = 0; i < _allDeliveryLocations.length; i++) {
        annotations.add(
          apple.Annotation(
            annotationId: apple.AnnotationId('delivery_$i'),
            position: apple.LatLng(
              _allDeliveryLocations[i].latitude,
              _allDeliveryLocations[i].longitude),
            infoWindow: apple.InfoWindow(title: '${AppLocalizations.of(context)?.delivery ?? AppLocalizations.of(context)!.tr('Delivery')} ${i + 1}')));
      }
    }

    return annotations;
  }
}

// ── Metric pill widget ──────────────────────────────────────────────────────
class _MetricPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool isLight;
  final bool dimmed;
  final IconData? icon;

  const _MetricPill({
    required this.label,
    required this.color,
    required this.isLight,
    this.dimmed = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = dimmed ? color.withOpacity(0.45) : color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: effectiveColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: effectiveColor), SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: effectiveColor,
              letterSpacing: -0.1)),
        ]));
  }
}

// ── macOS-style nav close button ────────────────────────────────────────────

class _NavCloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _NavCloseButton({required this.onTap});

  @override
  State<_NavCloseButton> createState() => _NavCloseButtonState();
}

class _NavCloseButtonState extends State<_NavCloseButton>
    with SingleTickerProviderStateMixin {
  final bool _isHovered = false;
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.76).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TradeRepublicTap(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF5F57)),
          child: const Center(
            child: Icon(
              CupertinoIcons.xmark,
              size: 16,
              color: Colors.white)))));
  }
}

// ── Small frosted icon button used in top nav row ────────────────────────────

class _TopNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isLight;
  const _TopNavButton({
    required this.icon,
    required this.onTap,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return TradeRepublicTap(
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.45)))));
  }
}
