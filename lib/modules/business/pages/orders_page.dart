import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../../shared/services/app_settings.dart';
import '../../../config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../shared/widgets/trade_republic_widgets.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import '../../../shared/widgets/trade_republic_bar_chart.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with TickerProviderStateMixin {
  final AppSettings _appSettings = AppSettings();
  final ScrollController _scrollController = ScrollController();
  bool isLoading = true;
  bool _isInitialLoad = true;
  List<Map<String, dynamic>> orders = [];
  double totalRevenue = 0.0;
  int totalOrders = 0;
  Timer? _orderCheckTimer;
  Timer? _liveLocationTimer;
  Map<String, dynamic>? _driverLiveLocation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Pinned orders tracking
  final Set<String> _pinnedOrderIds = {};

  // Track existing order IDs to detect new orders
  final Set<String> _existingOrderIds = {};

  // Locally track orders that have been read this session
  final Set<String> _readOrderIds = {};

  // Active filter for orders list
  // Options: 'needs_info', 'all', 'pending', 'processing', 'completed', 'cancelled'
  String _activeFilter = 'needs_info';

  // Modern Animation Controllers - Delvioo Style
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late Animation<double> _headerSlideAnim;
  late Animation<double> _headerFadeAnim;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadPersistedReadIds().then((_) {
      _loadOrders();
      _startOrderCheckTimer();
    });
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);

    // Modern animation setup - Delvioo Style
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

    // Start header animation immediately
    _headerAnimController.forward();

    // Start content animation shortly after header
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _contentAnimController.forward();
      }
    });
  }

  @override
  void dispose() {
    _orderCheckTimer?.cancel();
    _liveLocationTimer?.cancel();
    _pulseController.dispose();
    _headerAnimController.dispose();
    _contentAnimController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Start timer to check for order updates every 30 seconds
  void _startOrderCheckTimer() {
    _orderCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadOrders();
      }
    });
  }

  Future<String?> _getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('auth_token');

    return token;
  }

  // Helpers
  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  bool _isRevenueStatus(String? status) {
    if (status == null) return false;
    return status.toLowerCase() == 'delivered';
  }

  // Helper to convert value to int safely
  int? _toOrderInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  // Get the base order ID (parent if split, otherwise own ID)
  int? _baseOrderIdFor(Map<String, dynamic> order) {
    final parent = _toOrderInt(order['parent_order_id']);
    final id = _toOrderInt(order['id']);
    return parent ?? id;
  }

  // Display order number with split notation (e.g., "25.1", "25.2")
  String _displayOrderNumberFor(Map<String, dynamic> order) {
    final base = _baseOrderIdFor(order);
    if (base == null) return '';
    final part = _toOrderInt(order['split_order_part']);
    final rawSplit = order['split_order'];
    final isSplit = rawSplit == true ||
        rawSplit == 1 ||
        rawSplit.toString() == '1' ||
        (order['parent_order_id'] != null) ||
        (part != null && part > 0);
    if (isSplit && part != null && part > 0) {
      return '$base.$part';
    }
    return '$base';
  }

  // Find all orders in the same split family (parent + all splits)
  List<Map<String, dynamic>> _findSplitFamily(Map<String, dynamic> order) {
    final orderId = order['id']?.toString();
    final parentId = order['parent_order_id']?.toString();
    
    // If this is a parent order, find all children
    if (parentId == null) {
      final family = [order];
      for (final o in orders) {
        final oParentId = o['parent_order_id']?.toString();
        if (oParentId == orderId) {
          family.add(o);
        }
      }
      // Sort by split_order_part
      family.sort((a, b) {
        final aPart = a['split_order_part'] ?? 0;
        final bPart = b['split_order_part'] ?? 0;
        return aPart.compareTo(bPart);
      });
      return family;
    }
    
    // If this is a child, find parent and all siblings
    final parent = orders.firstWhere(
      (o) => o['id']?.toString() == parentId,
      orElse: () => {},
    );
    
    if (parent.isEmpty) return [order];
    
    final family = [parent];
    for (final o in orders) {
      final oParentId = o['parent_order_id']?.toString();
      if (oParentId == parentId) {
        family.add(o);
      }
    }
    
    // Sort by split_order_part
    family.sort((a, b) {
      final aPart = a['split_order_part'] ?? 0;
      final bPart = b['split_order_part'] ?? 0;
      return aPart.compareTo(bPart);
    });
    
    return family;
  }
  
  // Find current index in split family
  int _findCurrentSplitIndex(Map<String, dynamic> order, List<Map<String, dynamic>> family) {
    final currentId = order['id']?.toString();
    for (int i = 0; i < family.length; i++) {
      if (family[i]['id']?.toString() == currentId) {
        return i;
      }
    }
    return 0;
  }
  
  // Get label for split order slider
  String _getOrderLabel(Map<String, dynamic> order) {
    final base = _baseOrderIdFor(order);
    final part = _toOrderInt(order['split_order_part']);
    if (part != null && part > 0) {
      return '$base.$part';
    }
    return '$base';
  }

  Future<void> _loadOrders() async {
    print('📦 Loading orders from database...');
    if (mounted && _isInitialLoad) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final token = await _getStoredToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/business/orders'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      print('📡 Orders response: ${response.statusCode}');
      print('📡 Orders response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true && responseData['orders'] != null) {
          final newOrders = List<Map<String, dynamic>>.from(
            responseData['orders'],
          );

          // DEBUG: Log split order fields for first few orders
          for (var i = 0; i < newOrders.length && i < 5; i++) {
            final o = newOrders[i];
            print('🔍 ORDER #${o['id']}: split_order=${o['split_order']}, split_order_part=${o['split_order_part']}, parent_order_id=${o['parent_order_id']}');
          }

          // Check for completely new orders (first time seeing them)
          // Skip on initial load — existingOrderIds is empty so every order would trigger a notification
          if (!_isInitialLoad) {
            _checkForNewOrders(newOrders);
            _checkForNewDelviooAcceptedOrders(newOrders);
          } else {
            // Just seed the existing-IDs set silently
            _existingOrderIds.clear();
            for (final o in newOrders) {
              _existingOrderIds.add((o['id'] ?? o['order_id']).toString());
            }
          }

          if (mounted) {
            setState(() {
              orders = newOrders;
              // Prefer API-provided stats if available
              final stats = responseData['stats'];
              if (stats != null) {
                totalOrders = stats['total_orders'] is num
                    ? (stats['total_orders'] as num).toInt()
                    : int.tryParse('${stats['total_orders']}') ?? orders.length;
                // Backend uses 'total_revenue' key; keep 'revenue' as a fallback just in case
                totalRevenue = _asDouble(
                  stats['gross_revenue'] ?? stats['total_revenue'] ?? stats['revenue'],
                );
              } else {
                // Fallbacks if stats are not provided by API
                totalOrders = orders.length;

                // Calculate total revenue only from completed-like statuses
                double revenue = 0.0;
                for (final order in orders) {
                  final status = order['status']?.toString();
                  if (!_isRevenueStatus(status)) continue;

                  final subtotalField =
                      order['amount'] ??
                      order['total_amount'] ??
                      order['seller_subtotal'] ??
                      order['product_subtotal'] ??
                      order['sellerAmount'] ??
                      order['seller_amount'] ??
                      0.0;
                  final subtotal = _asDouble(subtotalField);
                  revenue += subtotal; // full amount, fee deducted on payout
                }
                totalRevenue = revenue;
              }

              isLoading = false;
              _isInitialLoad = false;
            });
          }
          print(
            '✅ Orders loaded successfully: $totalOrders orders, Revenue: \$$totalRevenue',
          );
          return;
        }
      }

      // Fallback with sample data
      print('⚠️ Using fallback order data');
      if (mounted) {
        setState(() {
          orders = [];
          totalRevenue = 0.0;
          totalOrders = 0;
          isLoading = false;
          _isInitialLoad = false;
        });
      }
    } catch (e) {
      print('❌ Error loading orders: $e');
      if (mounted) {
        setState(() {
          orders = [];
          totalRevenue = 0.0;
          totalOrders = 0;
          isLoading = false;
          _isInitialLoad = false;
        });
      }
    }
  }

  // Check for newly accepted orders and show notification
  void _checkForNewDelviooAcceptedOrders(List<Map<String, dynamic>> newOrders) {
    for (var newOrder in newOrders) {
      final newStatus = newOrder['status']?.toString().toLowerCase() ?? '';
      final orderId = newOrder['id'] ?? newOrder['order_id'];

      // Check if this order was previously not delvioo_accepted but now is
      if ((newStatus == 'delvioo_accepted' || newStatus == 'driver_accepted')) {
        // Find existing order to compare
        final existingOrder = orders.firstWhere(
          (order) => (order['id'] ?? order['order_id']) == orderId,
          orElse: () => {},
        );

        final oldStatus =
            existingOrder['status']?.toString().toLowerCase() ?? '';

        // If status changed to delvioo_accepted, show notification
        if (oldStatus != newStatus && oldStatus.isNotEmpty) {
          _showDelviooAcceptedNotification(newOrder);
        }
      }
    }
  }

  // Check for completely new orders and show notification
  void _checkForNewOrders(List<Map<String, dynamic>> newOrders) {
    for (var newOrder in newOrders) {
      final orderId = (newOrder['id'] ?? newOrder['order_id']).toString();

      // If this order ID is not in our existing set, it's a new order
      if (!_existingOrderIds.contains(orderId)) {
        final customerName =
            newOrder['username'] != null
            ? '@${newOrder['username']}'
            : (newOrder['customer_name'] ??
                  newOrder['user_name'] ??
                  AppLocalizations.of(context)?.customer ??
                  'Customer');
        final amount = newOrder['amount'] ?? newOrder['total_amount'] ?? 0.0;
        final totalAmount = (amount is String
            ? double.tryParse(amount) ?? 0.0
            : amount.toDouble());

        _showNewOrderNotification(orderId, customerName, totalAmount, newOrder);
      }
    }

    // Update the existing order IDs set
    _existingOrderIds.clear();
    for (var order in newOrders) {
      final orderId = (order['id'] ?? order['order_id']).toString();
      _existingOrderIds.add(orderId);
    }
  }

  // Show notification for new order
  void _showNewOrderNotification(
    String orderId,
    String customerName,
    double amount,
    Map<String, dynamic> order,
  ) {
    if (mounted) {
      HapticFeedback.heavyImpact();
      TopNotification.success(
        context,
        '🎉 ${AppLocalizations.of(context)?.newOrderFrom ?? 'New Order'} #${_displayOrderNumberFor(order)} from $customerName - ${AppSettings().formatCurrency(amount)}',
      );
    }
  }

  // Show notification when order is accepted by Delvioo driver
  void _showDelviooAcceptedNotification(Map<String, dynamic> order) {
    if (mounted) {
      HapticFeedback.lightImpact();
      TopNotification.info(
        context,
        '🚀 ${AppLocalizations.of(context)?.orderAcceptedByDriver ?? 'Order Accepted! Delvioo driver accepted order'} #${_displayOrderNumberFor(order)}',
      );
    }
  }

  // Load driver acceptance information from accepted_orders table
  Future<Map<String, dynamic>?> _loadDriverAcceptanceInfo(
    dynamic orderId,
  ) async {
    try {
      final token = await _getStoredToken();

      print('🚗 Loading driver acceptance info for order: $orderId');

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/business/orders/$orderId/driver-acceptance',
        ),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      print('🚗 Driver acceptance response: ${response.statusCode}');
      print('🚗 Driver acceptance body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true &&
            responseData['driverAcceptance'] != null) {
          final acceptance = responseData['driverAcceptance'];

          // Transform API response to match UI expectations
          return {
            'driver_name': acceptance['driver']['name'],
            'driverName': acceptance['driver']['name'],
            'driver_phone': acceptance['driver']['phone'],
            'phone': acceptance['driver']['phone'],
            'driver_email': acceptance['driver']['email'],
            'email': acceptance['driver']['email'],
            'vehicle_info': acceptance['vehicle']['info'],
            'vehicle': acceptance['vehicle']['info'],
            'license_plate': acceptance['vehicle']['licensePlate'],
            'licensePlate': acceptance['vehicle']['licensePlate'],
            'license_state': acceptance['vehicle']['licenseState'],
            'licenseState': acceptance['vehicle']['licenseState'],
            'license_country': acceptance['vehicle']['licenseCountry'],
            'licenseCountry': acceptance['vehicle']['licenseCountry'],
            'license_country_code': acceptance['vehicle']['licenseCountryCode'],
            'licenseCountryCode': acceptance['vehicle']['licenseCountryCode'],
            'section_index': acceptance['sectionIndex'],
            'section_name': acceptance['sectionName'],
            'accepted_at': acceptance['acceptedAt'],
            'acceptedAt': acceptance['acceptedAt'],
            'acceptance_date': acceptance['acceptedAt'],
            'rating': acceptance['driver']['rating']?.toString() ?? '',
            'total_deliveries': acceptance['driver']['totalDeliveries'],
            'driver_id': acceptance['driverId'],
            'estimated_delivery': acceptance['estimatedDeliveryTime'],
          };
        }
      }

      print('⚠️ No driver acceptance found for order $orderId');
      return null;
    } catch (e) {
      print('❌ Error loading driver acceptance info: $e');
      return null;
    }
  }

  // Load driver live location for tracking
  Future<Map<String, dynamic>?> _loadDriverLiveLocation(String orderId) async {
    try {
      final token = await _getStoredToken();

      print('📍 Loading driver live location for order: $orderId');

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/business/orders/$orderId/driver-location',
        ),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      print('📍 Driver location response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true &&
            responseData['location'] != null) {
          final location = responseData['location'];

          return {
            'latitude': location['latitude'],
            'longitude': location['longitude'],
            'timestamp': location['timestamp'],
            'speed': location['speed'] ?? 0,
            'heading': location['heading'] ?? 0,
            'accuracy': location['accuracy'] ?? 0,
            'driver_name':
                location['driver_name'] ??
                AppLocalizations.of(context)?.driverLabel ??
                'Driver',
            'estimated_arrival': location['estimated_arrival'],
            'distance_to_pickup': location['distance_to_pickup'],
          };
        }
      }

      print('⚠️ No driver location found for order $orderId');
      return null;
    } catch (e) {
      print('❌ Error loading driver location: $e');
      return null;
    }
  }

  // Start live location tracking for delvioo_accepted orders
  void _startLiveLocationTracking(String orderId) {
    print('🔄 Starting live location tracking for order $orderId');

    _liveLocationTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      if (mounted) {
        final location = await _loadDriverLiveLocation(orderId);
        if (location != null && mounted) {
          setState(() {
            _driverLiveLocation = location;
          });
        }
      } else {
        timer.cancel();
      }
    });

    // Load initial location immediately
    _loadDriverLiveLocation(orderId).then((location) {
      if (location != null && mounted) {
        setState(() {
          _driverLiveLocation = location;
        });
      }
    });
  }

  // Stop live location tracking
  void _stopLiveLocationTracking() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    if (mounted) {
      setState(() {
        _driverLiveLocation = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = _appSettings.isLightMode(context);

    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final horizontalPadding = isDesktop ? 32.0 : 20.0;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 1080 : double.infinity),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: isDesktop,
            thickness: isDesktop ? 6 : null,
            radius: const Radius.circular(4),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
              CultiooSliverRefreshControl(onRefresh: _loadOrders),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  isDesktop ? 32.0 : MediaQuery.of(context).padding.top + 20.0,
                  horizontalPadding,
                  MediaQuery.of(context).padding.bottom + 80.0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Trade Republic Style Header - Simple & Clean
                      _buildAnimatedSection(
                        delay: 0,
                        slideFromBottom: false,
                        child: _buildTradeRepublicHeader(
                          isLight,
                          isDesktop: isDesktop,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Revenue Summary - Trade Republic Style
                      _buildAnimatedSection(
                        delay: 0,
                        slideFromBottom: false,
                        child: _buildRevenueSummary(isLight),
                      ),

                      const SizedBox(height: 24),

                      // Filter chips
                      _buildAnimatedSection(
                        delay: 1,
                        slideFromBottom: false,
                        child: _buildFilterChips(isLight),
                      ),

                      const SizedBox(height: 16),

                      // Orders List
                      _buildAnimatedSection(
                        delay: 2,
                        slideFromBottom: true,
                        child: _buildFilteredOrdersOrEmpty(isLight),
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
    );
  }

  // Trade Republic Style Header - Minimal & Clean
  Widget _buildTradeRepublicHeader(bool isLight, {bool isDesktop = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.orders ?? 'Orders',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: isDesktop ? 40 : 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)?.manageYourIncomingOrders ??
              'Manage your incoming orders',
          style: TextStyle(
            color: isLight
                ? Colors.black.withOpacity(0.5)
                : Colors.white.withOpacity(0.5),
            fontSize: isDesktop ? 16 : 15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // Modern Staggered Animation Widget - Delvioo Style
  Widget _buildAnimatedSection({
    required int delay,
    required Widget child,
    bool slideFromBottom = false,
  }) {
    return AnimatedBuilder(
      animation: _contentAnimController,
      builder: (context, _) {
        final delayFactor = delay * 0.15;
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
            0,
            slideFromBottom ? 30 * (1 - curvedValue) : -30 * (1 - curvedValue),
          ),
          child: Opacity(
            opacity: curvedValue,
            child: Transform.scale(
              scale: 0.95 + (0.05 * curvedValue),
              alignment: slideFromBottom
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }

  void _showRevenueChart(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: SafeArea(
        top: false,
        child: _RevenueChartSheet(
          orders: orders,
          isLight: isLight,
          formatCurrency: (v) => _appSettings.formatCurrency(v),
        ),
      ),
    );
  }

  Widget _buildRevenueSummary(bool isLight) {
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        _showRevenueChart(isLight);
      },
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Revenue - Trade Republic Style: Large number, small label
        Row(
          children: [
            Text(
              AppLocalizations.of(context)?.totalRevenue ?? 'Total Revenue',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isLight
                    ? Colors.black.withOpacity(0.5)
                    : Colors.white.withOpacity(0.5),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chart_bar_alt_fill,
              size: 13,
              color: isLight
                  ? Colors.black.withOpacity(0.3)
                  : Colors.white.withOpacity(0.3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _appSettings.formatCurrency(totalRevenue),
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w700,
            color: isLight ? Colors.black : Colors.white,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 24),
        // Orders count - Trade Republic minimal row
        TradeRepublicCard(
          boxShadow: const [],
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              Text(
                '$totalOrders',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.orders ?? 'Orders',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: isLight
                      ? Colors.black.withOpacity(0.5)
                      : Colors.white.withOpacity(0.5),
                ),
              ),
              const Spacer(),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: isLight
                    ? Colors.black.withOpacity(0.3)
                    : Colors.white.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildEmptyState(bool isLight) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          Icon(
            CupertinoIcons.tray,
            size: 48,
            color: isLight
                ? Colors.black.withOpacity(0.3)
                : Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)?.noOrdersYet ?? 'No Orders Yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isLight ? Colors.black : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)?.yourOrdersWillAppearHere ??
                'Your orders will appear here',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: isLight
                  ? Colors.black.withOpacity(0.5)
                  : Colors.white.withOpacity(0.5),
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// Returns true when the order needs seller information to be filled in.
  bool _orderNeedsInfo(Map<String, dynamic> order) {
    final completed = order['seller_info_completed'];
    final status = (order['status'] ?? '').toString().toLowerCase().trim();
    // Exclude any status that is already "done" or irrelevant
    const excludedStatuses = {
      'closed',    // actual DB value for closed/cancelled orders
      'cancelled',
      'canceled',  // American spelling
      'completed',
      'delivered',
      'confirmed',
      'succeeded',
    };
    if (excludedStatuses.contains(status)) return false;
    return completed != 1 && completed != true;
  }

  /// Filter + sort helper used by both the list and the empty-state check.
  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> source) {
    List<Map<String, dynamic>> filtered;
    switch (_activeFilter) {
      case 'needs_info':
        filtered = source.where(_orderNeedsInfo).toList();
        break;
      case 'pending':
        filtered = source
            .where((o) => (o['status'] ?? '').toString().toLowerCase() == 'pending')
            .toList();
        break;
      case 'processing':
        filtered = source.where((o) {
          final s = (o['status'] ?? '').toString().toLowerCase();
          return s == 'processing' || s == 'preparing';
        }).toList();
        break;
      case 'completed':
        filtered = source.where((o) {
          final s = (o['status'] ?? '').toString().toLowerCase();
          return s == 'completed' || s == 'delivered' || s == 'confirmed';
        }).toList();
        break;
      case 'cancelled':
        filtered = source.where((o) {
          final s = (o['status'] ?? '').toString().toLowerCase();
          return s == 'cancelled' || s == 'canceled' || s == 'closed';
        }).toList();
        break;
      default: // 'all'
        filtered = List<Map<String, dynamic>>.from(source);
    }
    // Pinned first
    filtered.sort((a, b) {
      final aId = (a['id'] ?? a['order_id'] ?? '').toString();
      final bId = (b['id'] ?? b['order_id'] ?? '').toString();
      final aP = _pinnedOrderIds.contains(aId);
      final bP = _pinnedOrderIds.contains(bId);
      if (aP && !bP) return -1;
      if (!aP && bP) return 1;
      return 0;
    });
    return filtered;
  }

  Widget _buildFilteredOrdersOrEmpty(bool isLight) {
    final filtered = _applyFilter(orders);
    if (filtered.isEmpty) return _buildEmptyState(isLight);
    return _buildOrdersList(isLight, filtered);
  }

  Widget _buildFilterChips(bool isLight) {
    const filters = [
      ('needs_info', 'Needs Info'),
      ('all', 'All'),
      ('pending', 'Pending'),
      ('processing', 'Processing'),
      ('completed', 'Completed'),
      ('cancelled', 'Cancelled'),
    ];

    final needsInfoCount = orders.where(_orderNeedsInfo).length;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: TradeRepublicTheme.spacingS),
        itemBuilder: (context, i) {
          final (key, label) = filters[i];
          final isActive = _activeFilter == key;
          final badge =
              key == 'needs_info' && needsInfoCount > 0 ? needsInfoCount : 0;

          return TradeRepublicTap(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _activeFilter = key);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(
                horizontal: TradeRepublicTheme.spacingM,
              ),
              decoration: BoxDecoration(
                color: isActive
                    ? TradeRepublicTheme.textColor(context)
                    : TradeRepublicTheme.fillColor(context, opacity: 0.06),
                borderRadius: TradeRepublicTheme.borderRadiusSmall,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TradeRepublicTheme.titleSmall(context).copyWith(
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive
                          ? TradeRepublicTheme.backgroundColor(context)
                          : TradeRepublicTheme.hintColor(context,
                              opacity: 0.55),
                    ),
                  ),
                  if (badge > 0) ...[
                    const SizedBox(width: TradeRepublicTheme.spacingXS),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isActive
                            ? TradeRepublicTheme.backgroundColor(context)
                                .withOpacity(0.25)
                            : TradeRepublicTheme.textColor(context)
                                .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? TradeRepublicTheme.backgroundColor(context)
                              : TradeRepublicTheme.textColor(context),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrdersList(bool isLight, [List<Map<String, dynamic>>? filteredOrders]) {
    // Sort orders: pinned first, then by date
    final sortedOrders = filteredOrders ?? _applyFilter(orders);
    // Re-sort not needed here – _applyFilter already sorts by pin.
    // Keep the legacy path working if called without argument.
    if (filteredOrders == null) {
      sortedOrders.sort((a, b) {
        final aId = (a['id'] ?? a['order_id'] ?? '').toString();
        final bId = (b['id'] ?? b['order_id'] ?? '').toString();
        final aIsPinned = _pinnedOrderIds.contains(aId);
        final bIsPinned = _pinnedOrderIds.contains(bId);
        if (aIsPinned && !bIsPinned) return -1;
        if (!aIsPinned && bIsPinned) return 1;
        return 0;
      });
    }

    return Column(
      children: sortedOrders.map((order) {
        final orderId = (order['id'] ?? order['order_id'] ?? '').toString();
        final isPinned = _pinnedOrderIds.contains(orderId);

        return TradeRepublicSwipeAction(
          key: ValueKey(orderId),
          leading: TradeRepublicSwipeSpec(
            icon: CupertinoIcons.pin_fill,
            label: 'Pin',
            activeIcon: CupertinoIcons.pin_slash_fill,
            activeLabel: AppLocalizations.of(context)?.unpin ?? 'Unpin',
            isActive: isPinned,
            iconRotation: -0.5,
            onActivate: () {
              setState(() {
                if (isPinned) {
                  _pinnedOrderIds.remove(orderId);
                } else {
                  _pinnedOrderIds.add(orderId);
                }
              });
            },
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            _markOrderRead(orderId, order);
            _showOrderDetails(order, isLight);
          },
          child: _buildOrderCardContent(order, isLight, isPinned),
        );
      }).toList(),
    );
  }

  /// Restore read order IDs from SharedPreferences so the NEW badge
  /// disappears correctly after an app restart.
  Future<void> _loadPersistedReadIds() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('read_order_ids') ?? [];
    if (stored.isNotEmpty) {
      setState(() => _readOrderIds.addAll(stored));
    }
  }

  Future<void> _markOrderRead(String orderId, Map<String, dynamic> order) async {
    final alreadyRead =
        order['is_read'] == 1 || _readOrderIds.contains(orderId);
    if (alreadyRead) return;
    setState(() => _readOrderIds.add(orderId));
    // Persist locally so the NEW badge is gone after restart
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('read_order_ids') ?? [];
    if (!stored.contains(orderId)) {
      stored.add(orderId);
      await prefs.setStringList('read_order_ids', stored);
    }
    // Also update the DB (best-effort)
    try {
      final token = await _getStoredToken();
      await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/api/business/orders/$orderId/read'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      print('⚠️ Could not mark order $orderId as read in DB: $e');
    }
  }

  Widget _buildOrderCardContent(
    Map<String, dynamic> order,
    bool isLight,
    bool isPinned,
  ) {
    final orderId = order['id'] ??
      order['order_id'] ??
      (AppLocalizations.of(context)?.naValue ?? '');
    final status = order['status'] ?? 'pending';
    final amount = order['amount'] ?? order['total_amount'] ?? 0.0;
    final totalAmount = (amount is String
        ? double.tryParse(amount) ?? 0.0
        : amount.toDouble());
    final customerName =
        order['username'] != null
        ? '@${order['username']}'
      : (order['customer_name'] ??
          order['user_name'] ??
          AppLocalizations.of(context)?.customer ??
          'Customer');
    final createdAt =
        order['date'] ?? order['created_at'] ?? order['order_date'];
    final sellerInfoCompleted = order['seller_info_completed'] == 1;
    final isUnread = order['is_read'] != 1 &&
        !_readOrderIds.contains(orderId.toString());

    // Determine status color and icon
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status.toLowerCase()) {
      case 'completed':
      case 'delivered':
        statusColor = Colors.green;
        statusIcon = CupertinoIcons.checkmark_circle_fill;
        statusText =
            AppLocalizations.of(context)?.completedLabel ?? 'Completed';
        break;
      case 'confirmed':
        statusColor = Colors.teal;
        statusIcon = CupertinoIcons.doc_checkmark_fill;
        statusText =
            AppLocalizations.of(context)?.confirmedStatus ?? 'Confirmed';
        break;
      case 'accepted':
        statusColor = Colors.amber;
        statusIcon = CupertinoIcons.checkmark_circle;
        statusText =
            AppLocalizations.of(context)?.acceptedAwaitingDetails ??
            'Accepted - Awaiting Details';
        break;
      case 'picked_up':
        statusColor = Colors.purple;
        statusIcon = CupertinoIcons.cube_box_fill;
        statusText =
            AppLocalizations.of(context)?.pickedUpInTransit ??
            'Picked Up - In Transit';
        break;
      case 'delvioo_accepted':
      case 'driver_accepted':
        statusColor = Colors.blue;
        statusIcon = CupertinoIcons.car_fill;
        statusText =
            AppLocalizations.of(context)?.delviooAcceptedStatus ??
            'Delvioo Accepted';
        break;
      case 'ready_for_pickup':
        statusColor = Colors.teal;
        statusIcon = CupertinoIcons.bag_fill;
        statusText =
            AppLocalizations.of(context)?.readyForPickup ?? 'Ready for Pickup';
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = CupertinoIcons.clock_fill;
        statusText = AppLocalizations.of(context)?.pending ?? 'Pending';
        break;
      case 'processing':
      case 'preparing':
        statusColor = Colors.blue;
        statusIcon = CupertinoIcons.arrow_2_circlepath;
        statusText =
            AppLocalizations.of(context)?.processingStatus ?? 'Processing';
        break;
      case 'shipping':
      case 'out_for_delivery':
        statusColor = Colors.purple;
        statusIcon = CupertinoIcons.cube_box_fill;
        statusText = AppLocalizations.of(context)?.shippingStatus ?? 'Shipping';
        break;
      case 'cancelled':
      case 'canceled':
      case 'closed':
        statusColor = Colors.red;
        statusIcon = CupertinoIcons.xmark_circle_fill;
        statusText = AppLocalizations.of(context)?.cancelled ?? 'Cancelled';
        break;
      default:
        statusColor = Colors.black;
        statusIcon = CupertinoIcons.question_circle;
        statusText = status;
    }

    // Shipping payment state
    final isDelvioo = (order['delvioo'] ?? 0) == 1;
    final shippingPayStatus = (order['shipping_payment_status'] ?? '').toString();
    // Only show Pay Driver banner when backend explicitly set seller_pays
    // (i.e., a driver has been assigned and the incoterm requires seller payment).
    final sellerMustPay = isDelvioo && shippingPayStatus == 'seller_pays';
    final shippingCost = order['shipping_cost'] != null
        ? double.tryParse(order['shipping_cost'].toString())
        : null;

    // Trade Republic Style - Clean list row
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 0),
      child: Row(
        children: [
          // Left: Status dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          // Main content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isPinned)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Transform.rotate(
                          angle: -0.5,
                          child: Icon(
                            CupertinoIcons.pin_fill,
                            size: 12,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        customerName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isUnread
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isUnread)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: TradeRepublicTheme.accentGreen,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    if (!sellerInfoCompleted)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '#${_displayOrderNumberFor(order)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: isLight
                            ? Colors.black.withOpacity(0.5)
                            : Colors.white.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: TextStyle(
                        fontSize: 13,
                        color: isLight
                            ? Colors.black.withOpacity(0.3)
                            : Colors.white.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: statusColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right: Amount + Date
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _appSettings.formatCurrency(totalAmount),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isLight ? Colors.black : Colors.white,
                ),
              ),
              if (createdAt != null)
                Text(
                  _formatDate(createdAt),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: isLight
                        ? Colors.black.withOpacity(0.5)
                        : Colors.white.withOpacity(0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Icon(
            CupertinoIcons.chevron_right,
            size: 14,
            color: isLight
                ? Colors.black.withOpacity(0.3)
                : Colors.white.withOpacity(0.3),
          ),
        ],
      ),
    ),
      // Pay Driver banner — visible only when seller must pay shipping
      if (sellerMustPay)
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            _payDriverShipping(context, order, isLight);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(CupertinoIcons.creditcard_fill, size: 14, color: Color(0xFFFF9500)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shippingCost != null
                        ? 'Pay Driver · ${_appSettings.formatCurrency(shippingCost)}'
                        : 'Pay Driver',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF9500),
                    ),
                  ),
                ),
                const Icon(CupertinoIcons.chevron_right, size: 12, color: Color(0xFFFF9500)),
              ],
            ),
          ),
        ),
    ],
    );
  }

  Future<void> _payDriverShipping(
    BuildContext context,
    Map<String, dynamic> order,
    bool isLight,
  ) async {
    final orderId = (order['id'] ?? order['order_id']).toString();
    double? shippingCost = order['shipping_cost'] != null
        ? double.tryParse(order['shipping_cost'].toString())
        : null;
    
    // If shipping_cost is 0 or null, try to get it from driver-acceptance
    if (shippingCost == null || shippingCost == 0) {
      try {
        final token = await _getStoredToken();
        final response = await http.get(
          Uri.parse(
            '${ApiConfig.baseUrl}/api/business/orders/$orderId/driver-acceptance',
          ),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        );
        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true &&
              responseData['driverAcceptance'] != null) {
            final acceptance = responseData['driverAcceptance'];
            // Check if shipping cost is in driver-acceptance
            if (acceptance['shipping_cost'] != null) {
              shippingCost = double.tryParse(acceptance['shipping_cost'].toString());
            } else if (acceptance['shippingCost'] != null) {
              shippingCost = double.tryParse(acceptance['shippingCost'].toString());
            }
          }
        }
      } catch (e) {
        print('❌ Error loading shipping cost from driver-acceptance: $e');
      }
    }
    
    final isDark = !isLight;

    bool isLoading = false;
    String? error;
    String selectedMethod = 'wallet'; // default to wallet

    List<Map<String, dynamic>> savedMethods = [];
    try {
      final token = await _getStoredToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/business/payment-methods'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['methods'] != null) {
          savedMethods = List<Map<String, dynamic>>.from(data['methods']);
        }
      }
    } catch (e) {
      print('⚠️ Could not load payment methods: $e');
    }

    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: 520,
      child: StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFF9500), Color(0xFFFF6B00)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(CupertinoIcons.creditcard_fill, size: 20, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pay Driver',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black)),
                        Text('Order #${_displayOrderNumberFor(order)}',
                          style: TextStyle(fontSize: 13,
                            color: isDark ? Colors.white54 : Colors.black45)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TradeRepublicCard(
                  boxShadow: const [],
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Shipping cost',
                        style: TextStyle(fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black45)),
                      Text(
                        shippingCost != null ? _appSettings.formatCurrency(shippingCost) : '—',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Saved payment methods
                if (savedMethods.isNotEmpty) ...[
                  Text('Saved payment methods',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white54 : Colors.black45,
                      letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  ...savedMethods.map((method) {
                    final type = method['type'] ?? '';
                    final isSelected = selectedMethod == 'saved_${method['id']}';
                    final label = method['label'] ?? 'Payment method';
                    final detail = method['detail'] ?? '';
                    IconData icon;
                    Color iconColor;
                    if (type == 'card') {
                      icon = CupertinoIcons.creditcard_fill;
                      iconColor = Colors.blue;
                    } else if (type == 'sepa_debit') {
                      icon = CupertinoIcons.building_2_fill;
                      iconColor = Colors.purple;
                    } else if (type == 'us_bank_account') {
                      icon = CupertinoIcons.money_dollar_circle_fill;
                      iconColor = Colors.teal;
                    } else {
                      icon = CupertinoIcons.creditcard;
                      iconColor = Colors.grey;
                    }
                    return GestureDetector(
                      onTap: () => setSheetState(() => selectedMethod = 'saved_${method['id']}'),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(

                       color: isSelected
                              ? (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06))
                              : (isDark ? const Color(0xFF141414) : Colors.black.withOpacity(0.02)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: iconColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: iconColor, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label,
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : Colors.black)),
                                  if (detail.isNotEmpty)
                                    Text(detail,
                                      style: TextStyle(fontSize: 12,
                                        color: isDark ? Colors.white54 : Colors.black45)),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(CupertinoIcons.checkmark_circle_fill,
                                color: isDark ? Colors.white : Colors.black, size: 20),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],

                // Monioo Wallet option
                GestureDetector(
                  onTap: () => setSheetState(() => selectedMethod = 'wallet'),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selectedMethod == 'wallet'
                          ? (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06))
                          : (isDark ? const Color(0xFF141414) : Colors.black.withOpacity(0.02)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9500).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(CupertinoIcons.money_dollar_circle_fill, color: Color(0xFFFF9500), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Monioo Wallet',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black)),
                              Text('Instant payment from your balance',
                                style: TextStyle(fontSize: 12,
                                  color: isDark ? Colors.white54 : Colors.black45)),
                            ],
                          ),
                        ),
                        if (selectedMethod == 'wallet')
                          const Icon(CupertinoIcons.checkmark_circle_fill,
                            color: Color(0xFFFF9500), size: 20),
                      ],
                    ),
                  ),
                ),

                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                TradeRepublicButton(
                  label: selectedMethod == 'wallet'
                      ? 'Pay from Monioo Wallet'
                      : 'Pay with selected method',
                  icon: const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 20),
                  tint: const Color(0xFFFF9500),
                  isLoading: isLoading,
                  onPressed: isLoading ? null : () async {
                    setSheetState(() { isLoading = true; error = null; });
                    final nav = Navigator.of(sheetCtx);
                    final ctx = context;
                    try {
                      final token = await _getStoredToken();
                      final prefs = await SharedPreferences.getInstance();
                      final sellerUsername = prefs.getString('username') ?? prefs.getString('seller_username') ?? '';
                      final paymentType = selectedMethod == 'wallet' ? 'wallet' : 'card';
                      final body = <String, dynamic>{
                        'seller_username': sellerUsername,
                        'payment_type': paymentType,
                      };
                      if (paymentType == 'card' && selectedMethod.startsWith('saved_')) {
                        // Extract payment method ID from saved method
                        final methodId = selectedMethod.replaceFirst('saved_', '');
                        body['payment_method_id'] = methodId;
                      }
                      final response = await http.post(
                        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/orders/$orderId/pay-shipping'),
                        headers: {
                          'Content-Type': 'application/json',
                          if (token != null) 'Authorization': 'Bearer $token',
                        },
                        body: json.encode(body),
                      );
                      final data = json.decode(response.body);
                      if (data['success'] == true || data['already_paid'] == true) {
                        if (mounted) {
                          nav.pop();
                          // ignore: use_build_context_synchronously
                          TopNotification.success(ctx, 'Driver payment confirmed!');
                          _loadOrders();
                        }
                      } else {
                        setSheetState(() {
                          isLoading = false;
                          error = data['message']?.toString() ?? 'Payment failed';
                        });
                      }
                    } catch (e) {
                      setSheetState(() { isLoading = false; error = 'Payment failed: $e'; });
                    }
                  },
                  width: double.infinity,
                ),
                const SizedBox(height: 10),
                TradeRepublicButton(
                  label: 'Cancel',
                  isSecondary: true,
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return _appSettings.formatDate(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatDateTime(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      final formattedDate = _appSettings.formatDate(date);
      return '$formattedDate ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  List<Color> _getStatusColors(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return [const Color(0xFF4CAF50), const Color(0xFF66BB6A)];
      case 'confirmed':
        return [const Color(0xFF00897B), const Color(0xFF26A69A)];
      case 'accepted':
        return [const Color(0xFFFFB300), const Color(0xFFFFD54F)];
      case 'picked_up':
        return [const Color(0xFF7B1FA2), const Color(0xFFAB47BC)];
      case 'delvioo_accepted':
      case 'driver_accepted':
        return [const Color(0xFF1E88E5), const Color(0xFF42A5F5)];
      case 'ready_for_pickup':
        return [const Color(0xFF00ACC1), const Color(0xFF26C6DA)];
      case 'pending':
        return [const Color(0xFFF57C00), const Color(0xFFFFB74D)];
      case 'processing':
      case 'preparing':
        return [const Color(0xFF1976D2), const Color(0xFF64B5F6)];
      case 'shipping':
      case 'out_for_delivery':
        return [const Color(0xFF7B1FA2), const Color(0xFFAB47BC)];
      case 'cancelled':
      case 'canceled':
      case 'closed':
        return [const Color(0xFFD32F2F), const Color(0xFFEF5350)];
      default:
        return [const Color(0xFF616161), const Color(0xFF9E9E9E)];
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return CupertinoIcons.checkmark_circle_fill;
      case 'confirmed':
        return CupertinoIcons.doc_checkmark_fill;
      case 'accepted':
        return CupertinoIcons.checkmark_circle;
      case 'picked_up':
        return CupertinoIcons.cube_box_fill;
      case 'delvioo_accepted':
      case 'driver_accepted':
        return CupertinoIcons.car_fill;
      case 'ready_for_pickup':
        return CupertinoIcons.bag_fill;
      case 'pending':
        return CupertinoIcons.clock_fill;
      case 'processing':
      case 'preparing':
        return CupertinoIcons.arrow_2_circlepath;
      case 'shipping':
      case 'out_for_delivery':
        return CupertinoIcons.cube_box_fill;
      case 'cancelled':
      case 'canceled':
      case 'closed':
        return CupertinoIcons.xmark_circle_fill;
      default:
        return CupertinoIcons.question_circle;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return AppLocalizations.of(context)?.delivered ?? 'Delivered';
      case 'confirmed':
        return AppLocalizations.of(context)?.confirmedStatus ?? 'Confirmed';
      case 'accepted':
        return AppLocalizations.of(context)?.acceptedAwaitingDetails ??
            'Accepted - Awaiting Details';
      case 'picked_up':
        return AppLocalizations.of(context)?.pickedUpInTransit ??
            'Picked Up - In Transit';
      case 'delvioo_accepted':
      case 'driver_accepted':
        return AppLocalizations.of(context)?.delviooAcceptedStatus ??
            'Delvioo Accepted';
      case 'ready_for_pickup':
        return AppLocalizations.of(context)?.readyForPickup ??
            'Ready for Pickup';
      case 'pending':
        return AppLocalizations.of(context)?.pending ?? 'Pending';
      case 'processing':
      case 'preparing':
        return AppLocalizations.of(context)?.processingStatus ?? 'Processing';
      case 'shipping':
      case 'out_for_delivery':
        return AppLocalizations.of(context)?.shippingStatus ?? 'Shipping';
      case 'cancelled':
      case 'canceled':
      case 'closed':
        return AppLocalizations.of(context)?.cancelled ?? 'Cancelled';
      default:
        return status.toUpperCase();
    }
  }

  void _showOrderDetails(Map<String, dynamic> order, bool isLight) {
    final orderId = order['id'] ??
      order['order_id'] ??
      (AppLocalizations.of(context)?.naValue ?? '');
    final status = order['status'] ?? 'pending';
    final amount = order['amount'] ?? order['total_amount'] ?? 0.0;
    final totalAmount = (amount is String
        ? double.tryParse(amount) ?? 0.0
        : amount.toDouble());
    final customerName =
        order['username'] != null
        ? '@${order['username']}'
      : (order['customer_name'] ??
          order['user_name'] ??
          AppLocalizations.of(context)?.customer ??
          'Customer');

    // Parse address if it's JSON
    String deliveryAddress = '';
    String customerEmail = '';
    try {
      final addressData = order['address'];
      if (addressData is String) {
        final addressJson = json.decode(addressData);

        // Try to use the pre-formatted address first
        if (addressJson['address'] != null &&
            addressJson['address'].toString().isNotEmpty) {
          deliveryAddress = addressJson['address'].toString();
        } else {
          // Fallback to building from individual components
          final street = addressJson['street'] ?? '';
          final houseNumber =
              addressJson['houseNumber'] ?? addressJson['house_number'] ?? '';
          final zip = addressJson['zip'] ?? addressJson['zip_code'] ?? '';
          final city = addressJson['city'] ?? '';
          final country = addressJson['country'] ?? '';

          // Build address with house number
          deliveryAddress = street;
          if (houseNumber.isNotEmpty) {
            deliveryAddress += ' $houseNumber';
          }
          if (zip.isNotEmpty || city.isNotEmpty) {
            deliveryAddress += ', $zip $city';
          }
          if (country.isNotEmpty) {
            deliveryAddress += ', $country';
          }
          deliveryAddress = deliveryAddress.trim();
        }

        customerEmail = addressJson['email'] ?? '';
      } else if (addressData is Map) {
        // Try to use the pre-formatted address first
        if (addressData['address'] != null &&
            addressData['address'].toString().isNotEmpty) {
          deliveryAddress = addressData['address'].toString();
        } else {
          // Fallback to building from individual components
          final street = addressData['street'] ?? '';
          final houseNumber =
              addressData['houseNumber'] ?? addressData['house_number'] ?? '';
          final zip = addressData['zip'] ?? addressData['zip_code'] ?? '';
          final city = addressData['city'] ?? '';
          final country = addressData['country'] ?? '';

          // Build address with house number
          deliveryAddress = street;
          if (houseNumber.isNotEmpty) {
            deliveryAddress += ' $houseNumber';
          }
          if (zip.isNotEmpty || city.isNotEmpty) {
            deliveryAddress += ', $zip $city';
          }
          if (country.isNotEmpty) {
            deliveryAddress += ', $country';
          }
          deliveryAddress = deliveryAddress.trim();
        }

        customerEmail = addressData['email'] ?? '';
      }
    } catch (e) {
      deliveryAddress = order['address']?.toString() ?? '';
    }

    // Try to get customer phone from address JSON
    String customerPhone = '';
    try {
      final addressData = order['address'];
      if (addressData is String) {
        final addressJson = json.decode(addressData);
        customerPhone = addressJson['phone'] ?? '';
      } else if (addressData is Map) {
        customerPhone = addressData['phone'] ?? '';
      }
    } catch (e) {
      customerPhone = '';
    }

    // Fallback to order level customer_phone field if exists
    if (customerPhone.isEmpty) {
      customerPhone = order['customer_phone']?.toString() ?? '';
    }
    final createdAt =
        order['date'] ?? order['created_at'] ?? order['order_date'];

    // Parse cart items - prefer 'items' array which has enriched data from backend
    List<dynamic> items = [];
    try {
      // First try to get items from the enriched 'items' array
      if (order['items'] != null && order['items'] is List) {
        items = List<dynamic>.from(order['items']);
      } else {
        // Fallback to parsing cart
        final cartData = order['cart'];
        if (cartData is String) {
          items = json.decode(cartData);
        } else if (cartData is List) {
          items = cartData;
        }
      }
    } catch (e) {
      print('⚠️ Error parsing order items: $e');
      items = [];
    }

    // Initialize controllers ONCE outside the builder
    final sellerInfoCompleted = order['seller_info_completed'] == 1;
    final bestBeforeDate = order['best_before_date'];
    final productionDate = order['production_date'];
    final batchNumber = order['batch_number'];
    final sellerNotes = order['seller_notes'] ?? '';

    String extractDateFromISO(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return '';
      try {
        final date = DateTime.parse(dateStr);
        return _appSettings.formatDate(date);
      } catch (e) {
        return dateStr;
      }
    }

    final bestBeforeDateController = TextEditingController(
      text: extractDateFromISO(bestBeforeDate),
    );
    final productionDateController = TextEditingController(
      text: extractDateFromISO(productionDate),
    );
    final batchNumberController = TextEditingController(
      text: batchNumber ?? '',
    );
    final notesController = TextEditingController(text: sellerNotes);

    // Find split order family
    final splitFamily = _findSplitFamily(order);
    final initialSplitIndex = _findCurrentSplitIndex(order, splitFamily);
    // Track selected split index outside builder to persist between rebuilds
    int selectedSplitIndex = initialSplitIndex;
    
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: StatefulBuilder(
        builder: (modalContext, setModalState) {
          // Get current order based on selection
          Map<String, dynamic> currentOrder = splitFamily.isNotEmpty 
              ? splitFamily[selectedSplitIndex] 
              : order;
          
          // DEBUG: Print all driver-related fields
          print('🔍 ORDER #${currentOrder['id']} - DRIVER FIELDS:');
          print('  driver_id: ${currentOrder['driver_id']} (type: ${currentOrder['driver_id']?.runtimeType})');
          print('  order_driver_id: ${currentOrder['order_driver_id']} (type: ${currentOrder['order_driver_id']?.runtimeType})');
          print('  driverId: ${currentOrder['driverId']} (type: ${currentOrder['driverId']?.runtimeType})');
          print('  assigned_driver_id: ${currentOrder['assigned_driver_id']} (type: ${currentOrder['assigned_driver_id']?.runtimeType})');
          print('  driver_name: ${currentOrder['driver_name']}');
          print('  driver_accepted: ${currentOrder['driver_accepted']}');
          print('  status: ${currentOrder['status']}');
          
          // Build split labels for slider
          final splitLabels = splitFamily.map((o) => _getOrderLabel(o)).toList();
          
          // Recalculate all order-dependent variables based on currentOrder
          final orderId = currentOrder['id'] ??
              currentOrder['order_id'] ??
              (AppLocalizations.of(context)?.naValue ?? '');
          final status = currentOrder['status'] ?? 'pending';
          final amount = currentOrder['amount'] ?? currentOrder['total_amount'] ?? 0.0;
          final totalAmount = (amount is String
              ? double.tryParse(amount) ?? 0.0
              : amount.toDouble());
          final customerName =
              currentOrder['username'] != null
              ? '@${currentOrder['username']}'
            : (currentOrder['customer_name'] ??
                currentOrder['user_name'] ??
                AppLocalizations.of(context)?.customer ??
                'Customer');

          // Parse address if it's JSON
          String deliveryAddress = '';
          String customerEmail = '';
          String customerPhone = '';
          try {
            final addressData = currentOrder['address'];
            if (addressData is String) {
              final addressJson = json.decode(addressData);
              // Try to use the pre-formatted address first
              if (addressJson['address'] != null &&
                  addressJson['address'].toString().isNotEmpty) {
                deliveryAddress = addressJson['address'].toString();
              } else {
                // Fallback to building from individual components
                final street = addressJson['street'] ?? '';
                final houseNumber =
                    addressJson['houseNumber'] ?? addressJson['house_number'] ?? '';
                final zip = addressJson['zip'] ?? addressJson['zip_code'] ?? '';
                final city = addressJson['city'] ?? '';
                final country = addressJson['country'] ?? '';

                // Build address with house number
                deliveryAddress = street;
                if (houseNumber.isNotEmpty) {
                  deliveryAddress += ' $houseNumber';
                }
                if (zip.isNotEmpty || city.isNotEmpty) {
                  deliveryAddress += ', $zip $city';
                }
                if (country.isNotEmpty) {
                  deliveryAddress += ', $country';
                }
                deliveryAddress = deliveryAddress.trim();
              }
              customerEmail = addressJson['email'] ?? '';
              customerPhone = addressJson['phone'] ?? '';
            } else if (addressData is Map) {
              // Try to use the pre-formatted address first
              if (addressData['address'] != null &&
                  addressData['address'].toString().isNotEmpty) {
                deliveryAddress = addressData['address'].toString();
              } else {
                // Fallback to building from individual components
                final street = addressData['street'] ?? '';
                final houseNumber =
                    addressData['houseNumber'] ?? addressData['house_number'] ?? '';
                final zip = addressData['zip'] ?? addressData['zip_code'] ?? '';
                final city = addressData['city'] ?? '';
                final country = addressData['country'] ?? '';

                // Build address with house number
                deliveryAddress = street;
                if (houseNumber.isNotEmpty) {
                  deliveryAddress += ' $houseNumber';
                }
                if (zip.isNotEmpty || city.isNotEmpty) {
                  deliveryAddress += ', $zip $city';
                }
                if (country.isNotEmpty) {
                  deliveryAddress += ', $country';
                }
                deliveryAddress = deliveryAddress.trim();
              }
              customerEmail = addressData['email'] ?? '';
              customerPhone = addressData['phone'] ?? '';
            }
          } catch (e) {
            deliveryAddress = currentOrder['address']?.toString() ?? '';
          }
          
          return SafeArea(
          top: false,
          bottom: false,
          child: SizedBox(
            height: MediaQuery.of(modalContext).size.height * 0.95,
            child: Column(
              children: [
                // Handle Bar - Trade Republic Style
                const DragHandle(),

                // Order Header - Trade Republic Style
                Column(
                  children: [
                    Text(
                      AppLocalizations.of(context)?.orderLabel ?? 'Order',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#${_displayOrderNumberFor(currentOrder)}',
                      style: TextStyle(
                        fontSize: Platform.isMacOS ? 24 : 32,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    
                    // Split Order Slider - only if multiple splits exist
                    if (splitFamily.length > 1) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TradeRepublicSlider(
                          labels: splitLabels,
                          selectedIndex: selectedSplitIndex,
                          onChanged: (index) {
                            HapticFeedback.lightImpact();
                            setModalState(() {
                              selectedSplitIndex = index;
                              currentOrder = splitFamily[index];
                            });
                          },
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 20),
                    // Status Badge - Trade Republic Style
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: _getStatusColors(status).first,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getStatusIcon(status),
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                _getStatusText(status),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // PICKUP ORDER: For delvioo == 0 (self-managed or pickup), show seller info first (if not completed)
                        // After seller info is completed: show waiting-for-buyer card (no QR/security code needed)
                        if ((currentOrder['delvioo'] ?? 0) == 0) ...[
                          if (sellerInfoCompleted == false) ...[
                            _buildSellerInfoSection(
                              currentOrder,
                              isLight,
                              bestBeforeDateController,
                              productionDateController,
                              batchNumberController,
                              notesController,
                            ),
                            const SizedBox(height: 20),
                          ] else if (status.toLowerCase() != 'completed' &&
                              status.toLowerCase() != 'delivered') ...[
                            // Self-managed: seller has done their part — waiting for buyer to confirm receipt
                            _buildSelfShippedWaitingCard(isLight),
                            const SizedBox(height: 20),
                          ],
                        ],
                        // Driver Acceptance Section (for delvioo_accepted orders)
                        if (status == 'delvioo_accepted' ||
                            status == 'driver_accepted') ...[
                          FutureBuilder<Map<String, dynamic>?>(
                            future: _loadDriverAcceptanceInfo(orderId),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return TradeRepublicCard(
                                  backgroundColor: Colors.blue,
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CultiooLoadingIndicator(size: 20),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          'Loading driver information...',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              } else if (snapshot.hasData &&
                                  snapshot.data != null) {
                                // Start live location tracking when driver acceptance is loaded
                                final orderIdForTracking = orderId.toString();
                                if (orderIdForTracking.isNotEmpty) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    _startLiveLocationTracking(
                                      orderIdForTracking,
                                    );
                                  });
                                }
                                return _buildDriverAcceptanceSection(
                                  snapshot.data!,
                                  isLight,
                                );
                              } else {
                                return TradeRepublicCard(
                                  backgroundColor: Colors.blue,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        CupertinoIcons.car_fill,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          AppLocalizations.of(
                                                context,
                                              )?.driverAcceptedThisOrder ??
                                              'Driver accepted this order',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Seller Information Section - show when order is ACCEPTED (before ready_for_pickup)
                        // BUT NOT for pickup orders (delvioo == 0) - they have it at the top
                        if (status.toLowerCase() == 'accepted' &&
                            (order['delvioo'] ?? 0) != 0) ...[
                          _buildSellerInfoSection(
                            order,
                            isLight,
                            bestBeforeDateController,
                            productionDateController,
                            batchNumberController,
                            notesController,
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Progress Bar and Security Code for ready_for_pickup status (after seller info is completed)
                        // BUT NOT for pickup orders (delvioo == 0) - they have QR code at the top
                        if (status == 'ready_for_pickup' &&
                            (order['delvioo'] ?? 0) != 0) ...[
                          _buildOrderProgressBar(status, isLight),
                          const SizedBox(height: 20),
                          _buildSecurityCodeSection(order, isLight),
                          const SizedBox(height: 20),
                        ],

                        // Contact Section
                        if (status == 'delvioo_accepted' ||
                            status == 'driver_accepted') ...[
                          FutureBuilder<Map<String, dynamic>?>(
                            future: _loadDriverAcceptanceInfo(orderId),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null) {
                                return _buildContactSection(
                                  order,
                                  isLight,
                                  driverInfo: snapshot.data!,
                                );
                              } else {
                                return _buildContactSection(order, isLight);
                              }
                            },
                          ),
                        ] else ...[
                          _buildContactSection(order, isLight),
                        ],

                        const SizedBox(height: 20),

                        _buildDetailSection(
                          AppLocalizations.of(context)?.customerInformation ??
                              'Customer Information',
                          isLight,
                          [
                            _buildDetailRow(
                              AppLocalizations.of(context)?.name ?? 'Name',
                              customerName,
                              CupertinoIcons.person_fill,
                              isLight,
                            ),
                            if (customerEmail.isNotEmpty)
                              _buildDetailRow(
                                AppLocalizations.of(context)?.email ?? 'Email',
                                customerEmail,
                                CupertinoIcons.mail_solid,
                                isLight,
                              ),
                            if (customerPhone.isNotEmpty)
                              _buildDetailRow(
                                AppLocalizations.of(context)?.phone ?? 'Phone',
                                customerPhone,
                                CupertinoIcons.phone_fill,
                                isLight,
                              ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        _buildDetailSection(
                          AppLocalizations.of(context)?.deliveryInformation ??
                              'Delivery Information',
                          isLight,
                          [
                            _buildDetailRow(
                              AppLocalizations.of(context)?.address ??
                                  'Address',
                              deliveryAddress.isNotEmpty
                                  ? deliveryAddress
                                  : AppLocalizations.of(context)?.naValue ?? 'N/A',
                              CupertinoIcons.location_solid,
                              isLight,
                            ),
                            if (createdAt != null)
                              _buildDetailRow(
                                AppLocalizations.of(context)?.orderDate ??
                                    'Order Date',
                                _formatDate(createdAt),
                                CupertinoIcons.calendar,
                                isLight,
                              ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Live Location — only for Delvioo orders with an assigned driver
                        if ((currentOrder['delvioo'] ?? 1) == 1 &&
                            (status == 'delvioo_accepted' ||
                             status == 'driver_accepted' ||
                             status == 'picked_up')) ...[  
                          TradeRepublicButton(
                            label: AppLocalizations.of(context)?.liveLocation ?? 'Live Location',
                            icon: const Icon(CupertinoIcons.location_fill, size: 16),
                            onPressed: () {
                              _showLiveLocationModal(
                                context,
                                orderId.toString(),
                                isLight,
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Pickup Information Section
                        if (items.isNotEmpty &&
                            items.any(
                              (item) => (item['pickup_address'] ?? '')
                                  .toString()
                                  .isNotEmpty,
                            )) ...[
                          _buildDetailSection(
                            AppLocalizations.of(context)?.pickupInformation ??
                                'Pickup Information',
                            isLight,
                            items
                                .where(
                                  (item) => (item['pickup_address'] ?? '')
                                      .toString()
                                      .isNotEmpty,
                                )
                                .map<Widget>((item) {
                                  final pickupStreet =
                                      item['pickup_address'] ?? '';
                                  final pickupCity = item['pickup_city'] ?? '';
                                  final pickupZip = item['pickup_zip'] ?? '';
                                  final pickupCountry =
                                      item['pickup_country'] ?? '';
                                  // Read shipping_type and delivery_time from order table, not from items
                                  final shippingType =
                                      order['shipping_type'] ??
                                      order['shippingType'] ??
                                      '';
                                  final deliveryTime =
                                      order['delivery_time'] ?? '';

                                  String pickupFullAddress = pickupStreet;
                                  if (pickupZip.isNotEmpty ||
                                      pickupCity.isNotEmpty) {
                                    pickupFullAddress +=
                                        ', $pickupZip $pickupCity'.trim();
                                  }
                                  if (pickupCountry.isNotEmpty) {
                                    pickupFullAddress += ', $pickupCountry';
                                  }

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TradeRepublicListTile(
                                        title: pickupFullAddress,
                                        subtitle: AppLocalizations.of(context)?.pickupLocation ?? 'Pickup Location',
                                        leading: const Icon(CupertinoIcons.bag_fill),
                                      ),
                                      if (shippingType.isNotEmpty ||
                                          deliveryTime.isNotEmpty) ...[
                                        const TradeRepublicDivider(),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              if (shippingType.isNotEmpty)
                                                DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.local_shipping_outlined, size: 16, color: Colors.white),
                                                        const SizedBox(width: 4),
                                                        Text(shippingType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              if (deliveryTime.isNotEmpty)
                                                DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(CupertinoIcons.clock, size: 16, color: Colors.white),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          '$deliveryTime ${AppLocalizations.of(context)?.daysUnit ?? AppLocalizations.of(context)?.days ?? 'days'}',
                                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                })
                                .toList(),
                          ),

                          const SizedBox(height: 20),
                        ],

                        if (items.isNotEmpty) ...[
                          _buildDetailSection(
                            AppLocalizations.of(context)?.orderItems ??
                                'Order Items',
                            isLight,
                            items.map<Widget>((item) {
                              final itemName =
                                  item['name'] ??
                                  item['product_name'] ??
                                  item['productName'] ??
                                  item['title'] ??
                                  'Item';
                              final quantity = item['quantity'] ?? 1;
                              final itemPrice =
                                  item['price'] ?? item['product_price'] ?? 0.0;
                              final price = (itemPrice is String
                                  ? double.tryParse(itemPrice) ?? 0.0
                                  : itemPrice.toDouble());

                              return _buildDetailRow(
                                itemName,
                                '${quantity}x - ${_appSettings.formatCurrency(price)}',
                                Icons.shopping_bag,
                                isLight,
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 20),
                        ],

                        // Show delvioo toggle only when no driver assigned and status allows
                        if ((currentOrder['delvioo'] ?? 1) == 1 &&
                            !((currentOrder['driver_id'] != null && currentOrder['driver_id'] != 0 && currentOrder['driver_id'] != false && currentOrder['driver_id'] != '') ||
                              (currentOrder['order_driver_id'] != null && currentOrder['order_driver_id'] != 0 && currentOrder['order_driver_id'] != false && currentOrder['order_driver_id'] != '') ||
                              (currentOrder['driverId'] != null && currentOrder['driverId'] != 0 && currentOrder['driverId'] != false && currentOrder['driverId'] != '') ||
                              (currentOrder['assigned_driver_id'] != null && currentOrder['assigned_driver_id'] != 0 && currentOrder['assigned_driver_id'] != false && currentOrder['assigned_driver_id'] != '')) &&
                            !const {
                              'delvioo_accepted', 'driver_accepted',
                              'picked_up', 'delivered', 'completed',
                              'paid', 'bought', 'succeeded', 'cancelled',
                            }.contains(status.toLowerCase())) ...[
                          TradeRepublicCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TradeRepublicListTile(
                                        title: AppLocalizations.of(context)?.shippingMethod ?? 'Shipping Method',
                                        subtitle: (currentOrder['delvioo'] ?? 1) == 1
                                            ? AppLocalizations.of(context)?.usingDelviooDeliveryService ?? 'Using Delvioo delivery service'
                                            : AppLocalizations.of(context)?.selfManagedShipping ?? 'Self-managed shipping',
                                        leading: const Icon(CupertinoIcons.cube_box),
                                      ),
                                    ),
                                    TradeRepublicSwitch(
                                      value: (currentOrder['delvioo'] ?? 1) == 1,
                                      selectedLabel: 'Y',
                                      unselectedLabel: 'N',
                                      onChanged: (currentOrder['driver_id'] != null || currentOrder['assigned_driver_id'] != null)
                                          ? null // Disable when driver is assigned
                                          : (value) async {
                                        // Can only turn OFF — re-enabling is not allowed once disabled
                                        if (value) return;
                                        HapticFeedback.mediumImpact();

                                        // Show detailed self-managed shipping info sheet
                                        final confirm = await TradeRepublicBottomSheet.show<bool>(
                                          context: modalContext,
                                          bottomPadding: 20.0,
                                          child: SafeArea(
                                            top: false,
                                            child: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const DragHandle(),
                                                  // ── Title ──
                                                  Row(
                                                    children: [
                                                      DecoratedBox(
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange,
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: const Padding(
                                                          padding: EdgeInsets.all(10),
                                                          child: Icon(CupertinoIcons.cube_box, color: Colors.white, size: 22),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 14),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              AppLocalizations.of(context)?.selfShipTitle ?? 'Self-Managed Shipping',
                                                              style: TextStyle(
                                                                fontSize: 22,
                                                                fontWeight: FontWeight.w700,
                                                                color: isLight ? Colors.black : Colors.white,
                                                                letterSpacing: -0.4,
                                                              ),
                                                            ),
                                                            Text(
                                                              AppLocalizations.of(context)?.selfShipSubtitle ?? 'Without Delvioo Driver',
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 20),
                                                  // ── Cultioo info card ──
                                                  TradeRepublicCard(
                                                    backgroundColor: Colors.blue,
                                                    child: Row(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Icon(CupertinoIcons.info_circle_fill, color: Colors.white, size: 20),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Text(
                                                            AppLocalizations.of(context)?.selfShipPlatformNote ?? 'Cultioo withdraws from this order. As a SaaS platform, we take no responsibility for shipping or delivery.',
                                                            style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500, height: 1.4),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  // ── Steps ──
                                                  TradeRepublicCard(
                                                    padding: EdgeInsets.zero,
                                                    child: Column(
                                                      children: [
                                                        TradeRepublicListTile(
                                                          leading: DecoratedBox(
                                                            decoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                                                            child: const SizedBox(width: 28, height: 28, child: Center(child: Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)))),
                                                          ),
                                                          title: AppLocalizations.of(context)?.selfShipStep1Title ?? 'You ship the goods',
                                                          subtitle: AppLocalizations.of(context)?.selfShipStep1Desc ?? 'Pack and send the order directly to the buyer – using a shipping provider of your choice.',
                                                        ),
                                                        const TradeRepublicDivider(),
                                                        TradeRepublicListTile(
                                                          leading: DecoratedBox(
                                                            decoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                                                            child: const SizedBox(width: 28, height: 28, child: Center(child: Text('2', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)))),
                                                          ),
                                                          title: AppLocalizations.of(context)?.selfShipStep2Title ?? 'Buyer & seller agree',
                                                          subtitle: AppLocalizations.of(context)?.selfShipStep2Desc ?? 'Coordinate shipping details, tracking number and delivery timeframe directly via the messages feature.',
                                                        ),
                                                        const TradeRepublicDivider(),
                                                        TradeRepublicListTile(
                                                          leading: DecoratedBox(
                                                            decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                                            child: const SizedBox(width: 28, height: 28, child: Center(child: Text('3', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)))),
                                                          ),
                                                          title: AppLocalizations.of(context)?.selfShipStep3Title ?? 'Buyer confirms receipt',
                                                          subtitle: AppLocalizations.of(context)?.selfShipStep3Desc ?? 'Once the goods arrive, the buyer confirms receipt in the app. Only then is the order considered complete.',
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  // ── Warning ──
                                                  TradeRepublicCard(
                                                    backgroundColor: Colors.orange,
                                                    child: Row(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.white, size: 20),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Text(
                                                            AppLocalizations.of(context)?.selfShipWarning ?? 'This action cannot be undone. No Delvioo driver will be notified.',
                                                            style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500, height: 1.4),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 24),
                                                  // ── Confirm Button ──
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 0),
                                                    child: TradeRepublicButton(
                                                      label: AppLocalizations.of(context)?.selfShipConfirmButton ?? "Yes, I'll ship it myself",
                                                      backgroundColor: Colors.orange,
                                                      width: double.infinity,
                                                      icon: const Icon(CupertinoIcons.checkmark, color: Colors.white, size: 18),
                                                      onPressed: () => Navigator.pop(context, true),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Padding(
                                                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                                                    child: TradeRepublicButton(
                                                      label: AppLocalizations.of(context)?.cancel ?? 'Abbrechen',
                                                      isSecondary: true,
                                                      width: double.infinity,
                                                      onPressed: () => Navigator.pop(context, false),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );

                                        if (confirm == true) {
                                          await _toggleDelviooShipping(
                                            orderId,
                                            value,
                                          );
                                          if (!modalContext.mounted) return;
                                          setModalState(() {
                                            currentOrder['delvioo'] = value ? 1 : 0;
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                if ((currentOrder['delvioo'] ?? 1) == 0) ...[
                                  const SizedBox(height: 12),
                                  TradeRepublicCard(
                                    backgroundColor: Colors.orange,
                                    child: Row(
                                      children: [
                                        const Icon(
                                          CupertinoIcons.info_circle,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'You are responsible for shipping this order to the customer.',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        TradeRepublicCard(
                          backgroundColor: Colors.green,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLocalizations.of(context)?.totalAmount ??
                                    'Total Amount',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                _appSettings.formatCurrency(totalAmount),
                                style: TextStyle(
                                  fontSize: Platform.isMacOS ? 18 : 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Waiting Charges Section ──
                        Builder(builder: (context) {
                          final sellerChargesRaw = currentOrder['seller_waiting_charges'] ?? 0;
                          final buyerChargesRaw  = currentOrder['buyer_waiting_charges']  ?? 0;
                          final sellerCharges = sellerChargesRaw is String ? double.tryParse(sellerChargesRaw) ?? 0.0 : (sellerChargesRaw as num).toDouble();
                          final buyerCharges  = buyerChargesRaw  is String ? double.tryParse(buyerChargesRaw)  ?? 0.0 : (buyerChargesRaw  as num).toDouble();
                          final waitingCharges = sellerCharges + buyerCharges;
                          final sellerSeconds = (currentOrder['seller_waiting_seconds'] ?? 0 as num).toInt();
                          final buyerSeconds  = (currentOrder['buyer_waiting_seconds']  ?? 0 as num).toInt();
                          final waitingSeconds = sellerSeconds + buyerSeconds;
                          final waitingPaid = currentOrder['waiting_charges_paid'] == true || currentOrder['waiting_charges_paid'] == 1;
                          if (waitingCharges <= 0) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 20),
                              TradeRepublicCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(CupertinoIcons.timer, color: Colors.orange, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                AppLocalizations.of(context)?.waitingCharges ?? 'Waiting Charges',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: isLight ? Colors.black : Colors.white,
                                                ),
                                              ),
                                              Text(
                                                '${_formatSeconds(waitingSeconds)} ${AppLocalizations.of(context)?.tr('waited') ?? 'waited'}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isLight ? Colors.black45 : Colors.white.withOpacity(0.45),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: waitingPaid ? Colors.green : Colors.orange,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            waitingPaid
                                                ? (AppLocalizations.of(context)?.tr('Paid') ?? 'Paid')
                                                : _appSettings.formatCurrency(waitingCharges),
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (!waitingPaid) ...[
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          // Invoice button
                                          Expanded(
                                            child: TradeRepublicTap(
                                              onTap: () => _showWaitingInvoice(
                                                context, currentOrder, waitingCharges, waitingSeconds, isLight,
                                              ),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                decoration: BoxDecoration(
                                                  color: isLight ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.08),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(CupertinoIcons.doc_text, size: 16, color: isLight ? Colors.black : Colors.white),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      AppLocalizations.of(context)?.invoice ?? 'Invoice',
                                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isLight ? Colors.black : Colors.white),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          // Pay button
                                          Expanded(
                                            flex: 2,
                                            child: TradeRepublicTap(
                                              onTap: () => _transferWaitingCharges(
                                                context, currentOrder, orderId, waitingCharges, setModalState,
                                              ),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(CupertinoIcons.arrow_right_circle_fill, size: 16, color: Colors.white),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      '${AppLocalizations.of(context)?.tr('Pay Driver') ?? 'Pay Driver'} · ${_appSettings.formatCurrency(waitingCharges)}',
                                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          );
                        }),

                        const SizedBox(
                          height: 50,
                        ), // Extra space at end for better scrolling
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
  );
}

  Widget _buildSelfShippedWaitingCard(bool isLight) {
    return TradeRepublicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(CupertinoIcons.cube_box_fill, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.selfShipWaitingTitle ?? 'Your part is done ✓',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)?.selfShipWaitingSubtitle ?? 'Waiting for buyer confirmation',
                      style: TextStyle(
                        fontSize: 13,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const TradeRepublicDivider(),
          // Step 1
          TradeRepublicListTile(
            leading: const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green, size: 20),
            title: AppLocalizations.of(context)?.selfShipStepDoneTitle ?? 'Item packed & shipped',
            subtitle: AppLocalizations.of(context)?.selfShipStepDoneDesc ?? 'You have sent the goods on their way.',
          ),
          const TradeRepublicDivider(),
          // Step 2
          TradeRepublicListTile(
            leading: const Icon(CupertinoIcons.clock, color: Colors.orange, size: 20),
            title: AppLocalizations.of(context)?.selfShipStepPendingTitle ?? 'Buyer confirms receipt',
            subtitle: AppLocalizations.of(context)?.selfShipStepPendingDesc ?? 'Once the buyer confirms receipt in the app, the order is complete.',
          ),
          const SizedBox(height: 12),
          // Cultioo note
          TradeRepublicCard(
            backgroundColor: Colors.blue,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(CupertinoIcons.info_circle_fill, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.selfShipCultiooNote ?? 'Cultioo has stepped back from this order. Buyer and seller have agreed directly.',
                    style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverLiveLocationSection(bool isLight) {
    if (_driverLiveLocation == null) return const SizedBox.shrink();

    final latitude = _driverLiveLocation!['latitude']?.toString() ?? '';
    final longitude = _driverLiveLocation!['longitude']?.toString() ?? '';
    final timestamp = _driverLiveLocation!['timestamp']?.toString() ?? '';
    final speed = _driverLiveLocation!['speed']?.toString() ?? '0';
    final distanceToPickup =
        _driverLiveLocation!['distance_to_pickup']?.toString() ?? '';
    final estimatedArrival =
        _driverLiveLocation!['estimated_arrival']?.toString() ?? '';
    final driverName =
        _driverLiveLocation!['driver_name']?.toString() ??
        AppLocalizations.of(context)?.driverLabel ??
        'Driver';

    return TradeRepublicCard(
      backgroundColor: Colors.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TradeRepublicSectionHeader(
                  title: (AppLocalizations.of(context)
                              ?.tr('driverEnRouteTitle')
                              .replaceAll('{driver}', driverName)) ??
                          '$driverName is en route',
                  subtitle: AppLocalizations.of(context)?.liveTruckLocation ??
                      'Live Truck Location',
                  leading: const Icon(CupertinoIcons.location_fill, color: Colors.white),
                ),
              ),
              // Live indicator with pulse animation
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: const SizedBox(
                      width: 14,
                      height: 14,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.liveLabel ?? 'LIVE',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Location Details Grid
          TradeRepublicCard(
            backgroundColor: Colors.white,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (latitude.isNotEmpty && longitude.isNotEmpty) ...[
                  _buildLocationInfoRow(
                    CupertinoIcons.placemark_fill,
                    AppLocalizations.of(context)?.currentPosition ??
                        'Current Position',
                    '${double.tryParse(latitude)?.toStringAsFixed(4) ?? latitude}, ${double.tryParse(longitude)?.toStringAsFixed(4) ?? longitude}',
                  ),
                  const TradeRepublicDivider(),
                ],
                if (speed != '0') ...[
                  _buildLocationInfoRow(
                    CupertinoIcons.speedometer,
                    AppLocalizations.of(context)?.currentSpeed ??
                        'Current Speed',
                    '$speed km/h',
                  ),
                  const TradeRepublicDivider(),
                ],
                if (distanceToPickup.isNotEmpty) ...[
                  _buildLocationInfoRow(
                    CupertinoIcons.map,
                    AppLocalizations.of(context)?.distanceToPickup ??
                        'Distance to Pickup',
                    distanceToPickup,
                  ),
                  const TradeRepublicDivider(),
                ],
                if (estimatedArrival.isNotEmpty) ...[
                  _buildLocationInfoRow(
                    CupertinoIcons.clock,
                    AppLocalizations.of(context)?.estimatedArrival ??
                        'Estimated Arrival',
                    estimatedArrival,
                  ),
                  const TradeRepublicDivider(),
                ],
                _buildLocationInfoRow(
                  CupertinoIcons.refresh,
                  AppLocalizations.of(context)?.lastUpdated ?? 'Last Updated',
                  _formatLocationTimestamp(timestamp),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // View on Map Button
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.viewOnMap ?? 'View on Map',
              icon: const Icon(CupertinoIcons.map),
              isSecondary: true,
              onPressed: () {
                _openMapView(latitude, longitude, driverName);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInfoRow(IconData icon, String label, String value) {
    return TradeRepublicListTile(
      title: value,
      subtitle: label,
      leading: Icon(icon, color: Colors.green),
    );
  }

  String _formatLocationTimestamp(String timestamp) {
    if (timestamp.isEmpty) return 'Unknown';

    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inSeconds < 30) {
        return AppLocalizations.of(context)?.justNow ?? 'Just now';
      } else if (difference.inMinutes < 1) {
        return '${difference.inSeconds} seconds ago';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
      } else {
        return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
      }
    } catch (e) {
      return timestamp;
    }
  }

  void _showLiveLocationModal(
    BuildContext context,
    String orderId,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
      child: _BusinessLiveLocationModal(
        orderId: orderId,
        isDark: !isLight,
        loadLocation: _loadDriverLiveLocation,
      ),
    );
  }

  void _openMapView(String latitude, String longitude, String driverName) {
    if (latitude.isEmpty || longitude.isEmpty) return;

    // Show a simple map modal with the driver's location
    final isLight = _appSettings.isLightMode(context);
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
                CupertinoIcons.location_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$driverName\'s ${AppLocalizations.of(context)?.liveLocation ?? "Live Location"}',
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
          Container(
            width: double.infinity,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.map, size: 64, color: Colors.black),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)?.interactiveMap ??
                      'Interactive Map',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lat: ${double.tryParse(latitude)?.toStringAsFixed(6) ?? latitude}',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Lng: ${double.tryParse(longitude)?.toStringAsFixed(6) ?? longitude}',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TradeRepublicButton(
                        label:
                            AppLocalizations.of(context)?.openInMapsApp ??
                            'Open in Maps App',
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () {
                          _showMapIntegrationComing();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _showMapIntegrationComing() {
    TopNotification.info(
      context,
      AppLocalizations.of(context)?.fullMapIntegrationComingSoon ??
          'Full map integration coming soon!',
    );
  }

  Widget _buildDriverAcceptanceSection(
    Map<String, dynamic> driverInfo,
    bool isLight,
  ) {
    final driverName =
        driverInfo['driver_name'] ??
        driverInfo['driverName'] ??
        'Unknown Driver';
    final driverPhone = driverInfo['driver_phone'] ?? driverInfo['phone'] ?? '';
    final driverEmail = driverInfo['driver_email'] ?? driverInfo['email'] ?? '';
    final vehicleInfo =
        driverInfo['vehicle_info'] ?? driverInfo['vehicle'] ?? '';
    final licensePlate =
        driverInfo['license_plate'] ?? driverInfo['licensePlate'] ?? '';
    final licenseState =
      (driverInfo['license_state'] ?? driverInfo['licenseState'] ?? '')
        .toString()
        .trim();
    final licenseCountry =
      (driverInfo['license_country'] ?? driverInfo['licenseCountry'] ?? '')
        .toString()
        .trim();
    final licenseCountryCode =
      (driverInfo['license_country_code'] ??
          driverInfo['licenseCountryCode'] ??
          '')
        .toString()
        .trim();
    final plateRegionParts = [
      if (licenseCountryCode.isNotEmpty) licenseCountryCode,
      if (licenseCountryCode.isEmpty && licenseCountry.isNotEmpty)
      licenseCountry,
      if (licenseState.isNotEmpty) licenseState,
    ];
    final displayLicensePlate =
      licensePlate.toString().trim().isEmpty
        ? ''
        : (plateRegionParts.isEmpty
            ? licensePlate.toString()
            : '${licensePlate.toString()} (${plateRegionParts.join(' / ')})');
    final sectionIndex = driverInfo['section_index'];
    final sectionName = driverInfo['section_name'] ?? '';
    final acceptedAt =
        driverInfo['accepted_at'] ??
        driverInfo['acceptedAt'] ??
        driverInfo['acceptance_date'] ??
        '';
    final driverRating = driverInfo['rating'] ?? '';

    return TradeRepublicCard(
      backgroundColor: Colors.green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title: driverName,
            subtitle: AppLocalizations.of(context)?.delviooDriverAccepted ?? 'Delvioo Driver Accepted',
            leading: const Icon(CupertinoIcons.car_fill, color: Colors.white),
          ),

          const SizedBox(height: 20),

          // Live Location Indicator (if available)
          if (_driverLiveLocation != null) ...[
            TradeRepublicCard(
              backgroundColor: Colors.white,
              child: Column(
                children: [
                  Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: const SizedBox(
                              width: 14,
                              height: 14,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
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
                              AppLocalizations.of(context)?.liveTracking ??
                                  'LIVE TRACKING',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.green,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(
                                    context,
                                  )?.driverIsEnRouteToPickup ??
                                  'Driver is en route to pickup',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        CupertinoIcons.location_fill,
                        color: Colors.green,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_driverLiveLocation!['distance_to_pickup'] != null) ...[
                    _buildDriverInfoRow(
                      CupertinoIcons.map,
                      AppLocalizations.of(context)?.distanceToPickup ??
                          'Distance to Pickup',
                      _driverLiveLocation!['distance_to_pickup'].toString(),
                    ),
                    const TradeRepublicDivider(),
                  ],
                  if (_driverLiveLocation!['estimated_arrival'] != null) ...[
                    _buildDriverInfoRow(
                      CupertinoIcons.clock,
                      AppLocalizations.of(context)?.estimatedArrival ??
                          'Estimated Arrival',
                      _driverLiveLocation!['estimated_arrival'].toString(),
                    ),
                    const TradeRepublicDivider(),
                  ],
                  _buildDriverInfoRow(
                    CupertinoIcons.refresh,
                    AppLocalizations.of(context)?.lastUpdated ?? 'Last Updated',
                    _formatLocationTimestamp(
                      _driverLiveLocation!['timestamp']?.toString() ?? '',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Driver Details Grid
          TradeRepublicCard(
            backgroundColor: Colors.white,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (driverPhone.isNotEmpty) ...[
                  _buildDriverInfoRow(
                    CupertinoIcons.phone_fill,
                    AppLocalizations.of(context)?.phone ?? 'Phone',
                    driverPhone,
                  ),
                  const TradeRepublicDivider(),
                ],
                if (driverEmail.isNotEmpty) ...[
                  _buildDriverInfoRow(
                    CupertinoIcons.mail_solid,
                    AppLocalizations.of(context)?.email ?? 'Email',
                    driverEmail,
                  ),
                  const TradeRepublicDivider(),
                ],
                if (vehicleInfo.isNotEmpty) ...[
                  _buildDriverInfoRow(
                    CupertinoIcons.car_fill,
                    AppLocalizations.of(context)?.vehicle ?? 'Vehicle',
                    vehicleInfo,
                  ),
                  const TradeRepublicDivider(),
                ],
                if (sectionName.isNotEmpty) ...[
                  _buildDriverInfoRow(
                    CupertinoIcons.square_grid_2x2,
                    AppLocalizations.of(context)?.vehicleSection ??
                        'Vehicle Section',
                    sectionName,
                  ),
                  const TradeRepublicDivider(),
                ],
                if (displayLicensePlate.isNotEmpty) ...[
                  _buildDriverInfoRow(
                    CupertinoIcons.ticket,
                    AppLocalizations.of(context)?.licensePlate ??
                        'License Plate',
                    displayLicensePlate,
                  ),
                  const TradeRepublicDivider(),
                ],
                if (driverRating.isNotEmpty) ...[
                  _buildDriverInfoRow(
                    CupertinoIcons.star_fill,
                    AppLocalizations.of(context)?.ratingLabel ?? 'Rating',
                    '$driverRating/5',
                  ),
                  const TradeRepublicDivider(),
                ],
                if (acceptedAt.isNotEmpty) ...[
                  _buildDriverInfoRow(
                    CupertinoIcons.clock,
                    AppLocalizations.of(context)?.acceptedAt ?? 'Accepted At',
                    _formatDateTime(acceptedAt),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverInfoRow(IconData icon, String label, String value) {
    return TradeRepublicListTile(
      title: value,
      subtitle: label,
      leading: Icon(icon, color: Colors.green),
    );
  }

  Widget _buildSellerInfoSection(
    Map<String, dynamic> order,
    bool isLight,
    TextEditingController bestBeforeDateController,
    TextEditingController productionDateController,
    TextEditingController batchNumberController,
    TextEditingController notesController,
  ) {
    final sellerInfoCompleted = order['seller_info_completed'] == 1;
    final bestBeforeDate = order['best_before_date'];
    final productionDate = order['production_date'];
    final batchNumber = order['batch_number'];
    final sellerNotes = order['seller_notes'] ?? '';

    return TradeRepublicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - Trade Republic Style
          TradeRepublicSectionHeader(
            title: AppLocalizations.of(context)?.sellerInformation ?? 'Seller Information',
            subtitle: sellerInfoCompleted ? null : (AppLocalizations.of(context)?.completeToProcessOrder ?? 'Complete to process order'),
            leading: Icon(
              sellerInfoCompleted ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.pencil,
              color: sellerInfoCompleted ? Colors.green : Colors.orange,
            ),
            trailing: !sellerInfoCompleted
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text(
                        AppLocalizations.of(context)?.required_ ?? 'Required',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 8),

          if (sellerInfoCompleted) ...[
            // Display mode - show saved information
            TradeRepublicCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildInfoDisplayRow(
                    'Best Before Date (MHD)',
                    _formatDisplayDate(bestBeforeDate),
                    CupertinoIcons.calendar,
                    isLight,
                  ),
                  const TradeRepublicDivider(),
                  _buildInfoDisplayRow(
                    AppLocalizations.of(context)?.productionDate ?? 'Production Date',
                    _formatDisplayDate(productionDate),
                    Icons.factory,
                    isLight,
                  ),
                  const TradeRepublicDivider(),
                  _buildInfoDisplayRow(
                    AppLocalizations.of(context)?.batchNumber ?? 'Batch Number',
                    batchNumber ?? '',
                    CupertinoIcons.cube_box_fill,
                    isLight,
                  ),
                  if (sellerNotes.isNotEmpty) ...[
                    const TradeRepublicDivider(),
                    _buildInfoDisplayRow(
                      AppLocalizations.of(context)?.notes ?? 'Notes',
                      sellerNotes,
                      Icons.note,
                      isLight,
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // Edit mode - show input fields

            // Best Before Date
            _buildDateField(
              AppLocalizations.of(context)?.bestBefore ?? 'Best Before',
              bestBeforeDateController,
              isLight,
              CupertinoIcons.calendar,
            ),
            const SizedBox(height: 16),

            // Production Date
            _buildDateField(
              AppLocalizations.of(context)?.productionDate ?? 'Production Date',
              productionDateController,
              isLight,
              Icons.factory,
            ),
            const SizedBox(height: 16),

            // Batch Number
            _buildTradeRepublicTextField(
              AppLocalizations.of(context)?.batchNumber ?? 'Batch Number',
              batchNumberController,
              isLight,
              CupertinoIcons.cube_box_fill,
            ),
            const SizedBox(height: 16),

            // Notes (Optional)
            _buildTradeRepublicTextField(
              AppLocalizations.of(context)?.notesOptional ?? 'Notes (Optional)',
              notesController,
              isLight,
              Icons.note,
              maxLines: 3,
            ),

            const SizedBox(height: 24),
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.saveAndContinue ?? 'Save & Continue',
              backgroundColor: Colors.green,
              width: double.infinity,
              icon: const Icon(CupertinoIcons.checkmark, color: Colors.white, size: 20),
              onPressed: () => _saveSellerInfo(
                order,
                bestBeforeDateController.text,
                productionDateController.text,
                batchNumberController.text,
                notesController.text,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDisplayDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return _appSettings.formatDate(date);
    } catch (e) {
      return dateStr;
    }
  }

  /// Converts any supported display date format back to YYYY-MM-DD for the API.
  String _displayDateToIso(String displayDate) {
    if (displayDate.isEmpty) return '';
    // Already ISO / parseable by DateTime.parse (yyyy-MM-dd, ISO8601, etc.)
    try {
      final d = DateTime.parse(displayDate);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {}
    // dd.MM.yyyy  (European default)
    final dotParts = displayDate.split('.');
    if (dotParts.length == 3 && dotParts[2].length == 4) {
      final day = int.tryParse(dotParts[0]);
      final month = int.tryParse(dotParts[1]);
      final year = int.tryParse(dotParts[2]);
      if (day != null && month != null && year != null) {
        return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      }
    }
    // MM/dd/yyyy (US)  or  dd/MM/yyyy (UK)
    final slashParts = displayDate.split('/');
    if (slashParts.length == 3) {
      final first = int.tryParse(slashParts[0]) ?? 0;
      final second = int.tryParse(slashParts[1]) ?? 0;
      final third = int.tryParse(slashParts[2]) ?? 0;
      if (slashParts[2].length == 4) {
        // year is last  →  MM/dd/yyyy or dd/MM/yyyy
        final year = third;
        if (first > 12) {
          // first must be day  →  dd/MM/yyyy
          return '$year-${second.toString().padLeft(2, '0')}-${first.toString().padLeft(2, '0')}';
        } else {
          // assume MM/dd/yyyy (US)
          return '$year-${first.toString().padLeft(2, '0')}-${second.toString().padLeft(2, '0')}';
        }
      } else if (slashParts[0].length == 4) {
        // year is first  →  yyyy/MM/dd
        return '$first-${second.toString().padLeft(2, '0')}-${third.toString().padLeft(2, '0')}';
      }
    }
    return displayDate; // unknown format – return as-is and let backend validate
  }

  Widget _buildInfoDisplayRow(
    String label,
    String value,
    IconData icon,
    bool isLight,
  ) {
    return TradeRepublicListTile(
      title: value,
      subtitle: label,
      leading: Icon(icon),
    );
  }

  Widget _buildDateField(
    String label,
    TextEditingController controller,
    bool isLight,
    IconData icon,
  ) {
    return TradeRepublicTap(
      onTap: () async {
        // Parse current date or use today
        DateTime selectedDate = DateTime.now();
        if (controller.text.isNotEmpty) {
          try {
            selectedDate = DateTime.parse(controller.text);
          } catch (e) {
            selectedDate = DateTime.now();
          }
        }

        // Show iOS-style bottom sheet with scrollable date picker wheels
        final DateTime? picked = await TradeRepublicBottomSheet.show<DateTime>(
          context: context,
          bottomPadding: 20.0,
          child: Builder(
            builder: (context) {
              DateTime tempDate = selectedDate;
              return SizedBox(
                height: MediaQuery.of(context).size.height * 0.4,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    children: [
                      // Handle Bar
                      const DragHandle(),

                      // Header
                      Row(
                        children: [
                          Icon(CupertinoIcons.calendar, size: 22, color: isLight ? Colors.black : Colors.white),
                          const SizedBox(width: 12),
                          Flexible(child: Text(
                            label,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                          )),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // iOS-Style Date Picker Wheels
                      Expanded(
                        child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.date,
                          initialDateTime: selectedDate,
                          minimumYear: 2020,
                          maximumYear: 2030,
                          onDateTimeChanged: (DateTime newDate) {
                            tempDate = newDate;
                          },
                          backgroundColor: Colors.transparent,
                        ),
                      ),

                      // Confirm Button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                        child: TradeRepublicButton(
                          label: AppLocalizations.of(context)?.confirm ?? 'Confirm',
                          backgroundColor: isLight ? Colors.black : Colors.white,
                          foregroundColor: isLight ? Colors.white : Colors.black,
                          width: double.infinity,
                          onPressed: () => Navigator.pop(context, tempDate),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );

        if (picked != null) {
          controller.text = _appSettings.formatDate(picked);
        }
      },
      child: AbsorbPointer(
        child: _buildTradeRepublicTextField(label, controller, isLight, icon),
      ),
    );
  }

  Widget _buildTradeRepublicTextField(
    String label,
    TextEditingController controller,
    bool isLight,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isLight
                  ? Colors.black.withOpacity(0.6)
                  : Colors.white.withOpacity(0.6),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isLight ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TradeRepublicTextField(controller: controller, maxLines: maxLines),
      ],
    );
  }

  Future<void> _saveSellerInfo(
    Map<String, dynamic> order,
    String bestBeforeDate,
    String productionDate,
    String batchNumber,
    String notes,
  ) async {
    final orderId = order['id'] as int;
    final delvioo = order['delvioo'] as int? ?? 0;

    // Block if seller waiting charges are unpaid
    final sellerChargesRaw = order['seller_waiting_charges'] ?? 0;
    final sellerCharges = sellerChargesRaw is num ? sellerChargesRaw.toDouble() : double.tryParse(sellerChargesRaw.toString()) ?? 0.0;
    final waitingPaid = order['waiting_charges_paid'] == true || order['waiting_charges_paid'] == 1;
    if (sellerCharges > 0 && !waitingPaid) {
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.waitingCharges ?? "Waiting Charges"} — ${_appSettings.formatCurrency(sellerCharges)} ${AppLocalizations.of(context)?.mustBePaidFirst ?? "must be paid before completing the order"}',
      );
      return;
    }

    // Validate required fields
    if (bestBeforeDate.isEmpty ||
        productionDate.isEmpty ||
        batchNumber.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.pleaseFillInAllRequiredFields ??
            'Please fill in all required fields',
      );
      return;
    }

    try {
      final token = await _getStoredToken();

      print(
        '🔑 Token for seller info update available: ${token != null}',
      );
      print('📝 Sending seller info for order $orderId (delvioo: $delvioo)');

      // For pickup orders (delvioo == 0), set status to 'confirmed'
      // For delivery orders (delvioo == 1), set status to 'ready_for_pickup'
      // (seller entering data marks the order as ready for the driver to pick up)
      final newStatus = delvioo == 0 ? 'confirmed' : 'ready_for_pickup';

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/business/orders/$orderId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'best_before_date': _displayDateToIso(bestBeforeDate),
          'production_date': _displayDateToIso(productionDate),
          'batch_number': batchNumber,
          'seller_notes': notes,
          'status': newStatus,
        }),
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          if (mounted) {
            TopNotification.success(
              context,
              AppLocalizations.of(context)?.sellerInfoSavedSuccessfully ??
                  'Seller information saved successfully',
            );

            // Close modal and reload orders
            Navigator.pop(context);
            _loadOrders();
          }
        } else {
          throw Exception(
            data['message'] ??
                AppLocalizations.of(context)?.failedToSave ??
                'Failed to save',
          );
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error saving seller info: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.error ?? "Error"}: ${e.toString()}',
        );
      }
    }
  }

  Widget _buildDetailSection(
    String title,
    bool isLight,
    List<Widget> children, {
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: title,
          leading: icon != null ? Icon(icon) : null,
        ),
        const SizedBox(height: 8),
        TradeRepublicCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const TradeRepublicDivider(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon,
    bool isLight,
  ) {
    return TradeRepublicListTile(
      title: value,
      subtitle: label,
      leading: Icon(icon),
    );
  }

  Widget _buildOrderProgressBar(String status, bool isLight) {
    final steps = ['Paid', 'Ready', 'Picked Up', 'Delivered'];
    final stepIcons = [
      CupertinoIcons.creditcard,
      CupertinoIcons.bag_fill,
      CupertinoIcons.cube_box_fill,
      CupertinoIcons.checkmark_circle_fill,
    ];
    int currentStep = 0;

    // Map status to progress steps
    if (status == 'pending' || status == 'paid') currentStep = 0;
    if (status == 'ready_for_pickup') currentStep = 1;
    if (status == 'picked_up') currentStep = 2;
    if (status == 'delivered' || status == 'completed') currentStep = 3;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - Trade Republic Style
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    CupertinoIcons.arrow_up_right,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)?.orderProgress ??
                        'Order Progress',
                    style: TextStyle(
                      fontSize: Platform.isMacOS ? 18 : 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${currentStep + 1} of ${steps.length} steps completed',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Progress Line - Trade Republic Style (Large & Minimal)
          SizedBox(
            height: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // Background
                  Container(
                    width: double.infinity,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  // Progress with solid color
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final progress = (currentStep + 1) / steps.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        width: constraints.maxWidth * progress,
                        decoration: const BoxDecoration(color: Colors.green),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Steps - Trade Republic Style (Vertical, Large)
          ...List.generate(steps.length, (index) {
            final isCompleted = index < currentStep;
            final isActive = index == currentStep;
            final isPending = index > currentStep;

            return Padding(
              padding: EdgeInsets.only(
                bottom: index < steps.length - 1 ? 24 : 0,
              ),
              child: Row(
                children: [
                  // Step Circle with Icon
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isCompleted || isActive
                          ? Colors.green
                          : isPending
                          ? (isLight ? Colors.black : Colors.white)
                          : null,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCompleted ? CupertinoIcons.checkmark : stepIcons[index],
                      color: isCompleted || isActive
                          ? Colors.white
                          : (isLight ? Colors.white : Colors.black),
                      size: 28,
                    ),
                  ),

                  const SizedBox(width: 20),

                  // Step Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[index],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context)?.currentStep ??
                                'Current step',
                            style: TextStyle(
                              fontSize: 14,
                              color: const Color(0xFF4CAF50),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (isCompleted) ...[
                          const SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(context)?.completedLabel ??
                                'Completed',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Status indicator
                  if (isCompleted)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Text(
                          '✓',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (isActive)
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          CupertinoIcons.arrow_right,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSecurityCodeSection(Map<String, dynamic> order, bool isLight) {
    final securityCode = order['security_code'] ?? order['securityCode'];

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          // Header - Trade Republic Style
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.pickupCode ?? 'Pickup Code',
                      style: TextStyle(
                        fontSize: Platform.isMacOS ? 18 : 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(
                            context,
                          )?.showToCustomerForVerification ??
                          'Show to customer for verification',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Security Code Display - Trade Republic Style (Large & Bold)
          if (securityCode != null) ...[
            TradeRepublicCard(
              backgroundColor: Colors.green,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
              child: Column(
                children: [
                  Text(
                    AppLocalizations.of(context)?.securityCode ??
                        'Security Code',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    securityCode.toString(),
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // QR Code Display - Trade Republic Style
          if (securityCode != null && securityCode.toString().isNotEmpty) ...[
            TradeRepublicTap(
              onTap: () => _showQRCodeFullScreen(
                context,
                securityCode.toString(),
                isLight,
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: QrImageView(
                          data: securityCode.toString(),
                          version: QrVersions.auto,
                          size: 188.0,
                          backgroundColor: Colors.white,
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.hand_point_right_fill,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context)?.tapToEnlarge ??
                                'Tap to enlarge',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white,
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
          ],
        ],
      ),
    );
  }

  Widget _buildContactSection(
    Map<String, dynamic> order,
    bool isLight, {
    Map<String, dynamic>? driverInfo,
  }) {
    final orderId = order['id'] ??
      order['order_id'] ??
      (AppLocalizations.of(context)?.naValue ?? '');
    final customerName =
        order['username'] != null
        ? '@${order['username']}'
      : (order['customer_name'] ??
          order['user_name'] ??
          AppLocalizations.of(context)?.customer ??
          'Customer');

    // Parse customer contact from address
    String customerEmail = '';
    String customerPhone = '';
    try {
      final addressData = order['address'];
      if (addressData is String) {
        final addressJson = json.decode(addressData);
        customerEmail = addressJson['email'] ?? '';
        customerPhone = addressJson['phone'] ?? '';
      } else if (addressData is Map) {
        customerEmail = addressData['email'] ?? '';
        customerPhone = addressData['phone'] ?? '';
      }
    } catch (e) {
      // Fallback to order level fields
      customerEmail = order['customer_email'] ?? order['email'] ?? '';
      customerPhone = order['customer_phone'] ?? order['phone'] ?? '';
    }

    final driverName =
        driverInfo?['driver_name'] ?? driverInfo?['driverName'] ?? '';
    final driverPhone =
        driverInfo?['driver_phone'] ?? driverInfo?['phone'] ?? '';
    final driverEmail =
        driverInfo?['driver_email'] ?? driverInfo?['email'] ?? '';

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title: AppLocalizations.of(context)?.contact ?? 'Contact',
            leading: const Icon(CupertinoIcons.chat_bubble_fill),
          ),
          const SizedBox(height: 8),
          TradeRepublicCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // Customer Contact
                _buildContactCard(
                  name: customerName,
                  subtitle: AppLocalizations.of(context)?.customer ?? 'Customer',
                  email: customerEmail,
                  phone: customerPhone,
                  icon: CupertinoIcons.person_fill,
                  color: isLight ? Colors.black : Colors.white,
                  onTap: () => _openMessageDialog(
                    customerName,
                    AppLocalizations.of(context)?.customer ?? 'Customer',
                    orderId,
                    isLight,
                    customerEmail,
                    customerPhone,
                  ),
                  isLight: isLight,
                ),
                // Driver Contact (if available)
                if (driverName.isNotEmpty) ...[
                  const TradeRepublicDivider(),
                  _buildContactCard(
                    name: driverName,
                    subtitle: AppLocalizations.of(context)?.delviooDriver ?? 'Delvioo Driver',
                    email: driverEmail,
                    phone: driverPhone,
                    icon: CupertinoIcons.car_fill,
                    color: isLight ? Colors.black : Colors.white,
                    onTap: () => _openMessageDialog(
                      driverName,
                      AppLocalizations.of(context)?.driverLabel ?? 'Driver',
                      orderId,
                      isLight,
                      driverEmail,
                      driverPhone,
                    ),
                    isLight: isLight,
                  ),
                ],
              ],
            ),
          ),
        ],
    );
  }

  Widget _buildContactCard({
    required String name,
    required String subtitle,
    required String email,
    required String phone,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isLight,
  }) {
    final detail = phone.isNotEmpty ? phone : (email.isNotEmpty ? email : subtitle);
    return TradeRepublicListTile.navigation(
      title: name,
      subtitle: detail,
      leading: Icon(icon),
      onTap: onTap,
    );
  }

  void _openMessageDialog(
    String recipientName,
    String recipientType,
    dynamic orderId,
    bool isLight,
    String email,
    String phone,
  ) {
    final messageController = TextEditingController();

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            // Drag indicator - Trade Republic Style
            DragHandle(),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
              child: Row(
                children: [
                  // Back button
                  TradeRepublicButton.icon(
                    icon: Icon(Icons.arrow_back_ios_new, size: 20),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    backgroundColor: isLight ? Colors.black : Colors.white,
                    foregroundColor: isLight ? Colors.white : Colors.black,
                    size: 44,
                  ),
                  const SizedBox(width: 16),
                  // Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.message ?? 'Message',
                          style: TextStyle(
                            fontSize: Platform.isMacOS ? 20 : 28,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$recipientName • $recipientType',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Contact info cards
                    if (email.isNotEmpty) ...[
                      _buildInfoChip(
                        icon: CupertinoIcons.mail_solid,
                        label: AppLocalizations.of(context)?.email ?? 'Email',
                        value: email,
                        isLight: isLight,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (phone.isNotEmpty) ...[
                      _buildInfoChip(
                        icon: CupertinoIcons.phone_fill,
                        label: AppLocalizations.of(context)?.phone ?? 'Phone',
                        value: phone,
                        isLight: isLight,
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Message input
                    Text(
                      AppLocalizations.of(context)?.yourMessage ??
                          'Your Message',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: isLight ? Colors.white : Colors.black,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TradeRepublicTextField(
                        controller: messageController,
                        maxLines: 8,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.2,
                        ),
                        hintText:
                            AppLocalizations.of(context)?.typeYourMessageHere ??
                            'Type your message here...',
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Send button
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
              child: TradeRepublicTap(
                onTap: () {
                  if (messageController.text.trim().isEmpty) {
                    HapticFeedback.lightImpact();
                    TopNotification.warning(
                      context,
                      AppLocalizations.of(context)?.pleaseEnterAMessage ??
                          'Please enter a message',
                    );
                    return;
                  }

                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                  _sendMessage(
                    recipientName,
                    recipientType,
                    orderId,
                    messageController.text.trim(),
                  );
                },
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        CupertinoIcons.paperplane_fill,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        AppLocalizations.of(context)?.sendMessage ??
                            'Send Message',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required bool isLight,
  }) {
    return TradeRepublicListTile(
      title: value,
      subtitle: label,
      leading: Icon(icon),
    );
  }

  Future<void> _toggleDelviooShipping(dynamic orderId, bool enabled) async {
    try {
      final token = await _getStoredToken();

      print(
        '🚚 Toggling Delvioo for order $orderId: ${enabled ? 'enabled' : 'disabled'}',
      );

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/api/business/orders/$orderId/delvioo'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'delvioo_enabled': enabled}),
      );

      print('📡 Toggle Delvioo response: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          if (mounted) {
            HapticFeedback.lightImpact();
            if (enabled) {
              TopNotification.success(
                context,
                AppLocalizations.of(context)?.delviooShippingEnabled ??
                    'Delvioo shipping enabled',
              );
            } else {
              TopNotification.warning(
                context,
                AppLocalizations.of(context)?.delviooDisabledHandleShipping ??
                    'Delvioo disabled - You will handle shipping',
              );
            }
          }

          // Reload orders to reflect change
          _loadOrders();
        } else {
          throw Exception(
            responseData['message'] ??
                AppLocalizations.of(context)?.failedToToggleDelvioo ??
                'Failed to toggle Delvioo',
          );
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error toggling Delvioo: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.failedToToggleDelvioo ?? "Failed to toggle Delvioo"}: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _sendMessage(
    String recipientName,
    String recipientType,
    dynamic orderId,
    String message,
  ) async {
    try {
      final token = await _getStoredToken();

      // Add order reference to the message
      final messageWithOrderRef =
          '${AppLocalizations.of(context)?.regardingOrderMessage ?? "Regarding Order"} #$orderId\n\n$message';

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/business/send-message'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'recipient_name': recipientName,
          'recipient_type': recipientType.toLowerCase(),
          'order_id': orderId,
          'message': messageWithOrderRef,
        }),
      );

      print('📤 Message sent response: ${response.statusCode}');
      print('📤 Message body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          _showMessageSentConfirmation(recipientName, recipientType);
        } else {
          throw Exception(
            responseData['message'] ??
                AppLocalizations.of(context)?.failedToSendMessage ??
                'Failed to send message',
          );
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error sending message: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.failedToSendMessage ?? "Failed to send message"}: ${e.toString()}',
        );
      }
    }
  }

  void _showMessageSentConfirmation(
    String recipientName,
    String recipientType,
  ) {
    if (mounted) {
      HapticFeedback.lightImpact();
      TopNotification.success(
        context,
        '${AppLocalizations.of(context)?.messageSentTo ?? "Message sent to"} $recipientName ($recipientType)',
      );
    }
  }

  void _showQRCodeFullScreen(
    BuildContext context,
    String qrCodeData,
    bool isLight,
  ) {
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
                CupertinoIcons.qrcode,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.pickupSecurityCode ??
                      'Pickup Security Code',
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
          const SizedBox(height: 24),
          Container(
            width: 300,
            height: 300,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: qrCodeData,
              version: QrVersions.auto,
              size: 268.0,
              backgroundColor: Colors.white,
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)?.showThisCodeToDriver ??
                'Show this code to the driver',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isLight ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Waiting Charges helpers ──────────────────────────────────────────────

  String _formatSeconds(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> _transferWaitingCharges(
    BuildContext ctx,
    Map<String, dynamic> order,
    dynamic orderId,
    double amount,
    StateSetter setModalState,
  ) async {
    final isLight = Theme.of(ctx).brightness == Brightness.light;
    final driverName = order['driver_name'] ?? 'Driver';

    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: ctx,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DragHandle(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(CupertinoIcons.timer, color: Colors.orange, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(ctx)?.waitingCharges ?? 'Waiting Charges',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${AppLocalizations.of(ctx)?.tr('Transfer to driver') ?? 'Transfer to driver'} $driverName: ${_appSettings.formatCurrency(amount)}',
                style: TextStyle(fontSize: 15, color: Colors.orange.shade700, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(ctx)?.tr('The driver waited beyond the free waiting time. This charge will be transferred directly from your wallet to the driver.') ?? 'The driver waited beyond the free waiting time. This charge will be transferred directly from your wallet to the driver.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TradeRepublicTap(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isLight ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            AppLocalizations.of(ctx)?.cancel ?? 'Cancel',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isLight ? Colors.black : Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TradeRepublicTap(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            '${AppLocalizations.of(ctx)?.tr('Pay') ?? 'Pay'} ${_appSettings.formatCurrency(amount)}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final token = await _getStoredToken();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/business/orders/$orderId/pay-waiting-charges'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'amount': amount}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setModalState(() => order['waiting_charges_paid'] = true);
          _loadOrders();
          if (mounted) {
            HapticFeedback.heavyImpact();
            TopNotification.success(ctx, '${AppLocalizations.of(ctx)?.tr('Waiting charges paid') ?? 'Waiting charges paid'} · ${_appSettings.formatCurrency(amount)}');
          }
        } else {
          throw Exception(data['error'] ?? data['message'] ?? 'Transfer failed');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) TopNotification.error(ctx, 'Error: ${e.toString()}');
    }
  }

  void _showWaitingInvoice(
    BuildContext ctx,
    Map<String, dynamic> order,
    double waitingCharges,
    int waitingSeconds,
    bool isLight,
  ) {
    final orderId = order['order_id'] ?? order['id'] ?? '';
    final driverName = order['driver_name'] ?? 'Driver';
    final freeMinutes = ((order['waiting_free_minutes'] ?? 15) as num).toInt();
    final ratePerHour = order['waiting_rate_per_hour'] != null
        ? (order['waiting_rate_per_hour'] as num).toDouble()
        : 0.0;
    final sellerSec = ((order['seller_waiting_seconds'] ?? 0) as num).toInt();
    final buyerSec  = ((order['buyer_waiting_seconds']  ?? 0) as num).toInt();
    final chargeableSeconds = (waitingSeconds - freeMinutes * 60).clamp(0, waitingSeconds);
    final invoiceDate = DateTime.now();

    TradeRepublicBottomSheet.show(
      context: ctx,
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(CupertinoIcons.doc_text_fill, color: Colors.orange, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(ctx)?.tr('Waiting Charges Invoice') ?? 'Waiting Charges Invoice',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${AppLocalizations.of(ctx)?.order ?? 'Order'} #$orderId',
                            style: TextStyle(fontSize: 13, color: (isLight ? Colors.black : Colors.white).withOpacity(0.45)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildInvoiceRow(ctx, isLight, AppLocalizations.of(ctx)?.tr('Date') ?? 'Date',
                    '${invoiceDate.day.toString().padLeft(2, '0')}.${invoiceDate.month.toString().padLeft(2, '0')}.${invoiceDate.year}'),
                _buildInvoiceRow(ctx, isLight, AppLocalizations.of(ctx)?.tr('Driver') ?? 'Driver', driverName),
                _buildInvoiceRow(ctx, isLight, AppLocalizations.of(ctx)?.freeWaiting ?? 'Free Waiting', '$freeMinutes min'),
                if (sellerSec > 0)
                  _buildInvoiceRow(ctx, isLight, AppLocalizations.of(ctx)?.tr('Pickup Waiting') ?? 'Pickup Waiting', _formatSeconds(sellerSec)),
                if (buyerSec > 0)
                  _buildInvoiceRow(ctx, isLight, AppLocalizations.of(ctx)?.tr('Delivery Waiting') ?? 'Delivery Waiting', _formatSeconds(buyerSec)),
                _buildInvoiceRow(ctx, isLight, AppLocalizations.of(ctx)?.tr('Total Waited') ?? 'Total Waited', _formatSeconds(waitingSeconds)),
                _buildInvoiceRow(ctx, isLight, AppLocalizations.of(ctx)?.tr('Chargeable Time') ?? 'Chargeable Time', _formatSeconds(chargeableSeconds)),
                if (ratePerHour > 0)
                  _buildInvoiceRow(ctx, isLight, AppLocalizations.of(ctx)?.tr('Rate/hr') ?? 'Rate/hr', _appSettings.formatCurrency(ratePerHour)),
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(AppLocalizations.of(ctx)?.totalAmount ?? 'Total',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(_appSettings.formatCurrency(waitingCharges),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(ctx)?.tr('This amount will be paid directly to the driver.') ?? 'This amount will be paid directly to the driver.',
                  style: TextStyle(fontSize: 12, color: (isLight ? Colors.black : Colors.white).withOpacity(0.38), height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceRow(BuildContext ctx, bool isLight, String label, String value) {
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

}


// ─────────────────────────────────────────
// Revenue Chart Bottom Sheet
// ─────────────────────────────────────────

class _RevenueChartSheet extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final bool isLight;
  final String Function(double) formatCurrency;

  const _RevenueChartSheet({
    required this.orders,
    required this.isLight,
    required this.formatCurrency,
  });

  @override
  State<_RevenueChartSheet> createState() => _RevenueChartSheetState();
}

class _RevenueChartSheetState extends State<_RevenueChartSheet> {
  String _period = '1M';
  static const _periods = ['1W', '1M', '3M', '6M', '1Y', 'ALL'];

  /// Statuses that count as "money has been received". Kept generous so
  /// any backend status that signals a successful sale is captured. Any
  /// order whose status is in this set OR that already carries a payment
  /// timestamp (paid_at / payment_date / completed_at / delivered_at) is
  /// treated as revenue.
  static const _revenueStatuses = {
    'paid',
    'bought',
    'confirmed',
    'accepted',
    'completed',
    'delivered',
    'succeeded',
    'shipped',
    'fulfilled',
    'picked_up',
    'in_transit',
    'ready_for_pickup',
    'driver_accepted',
    'delvioo_accepted',
  };
  static const _excludedStatuses = {
    'cancelled', 'canceled', 'refunded', 'failed', 'rejected', 'pending',
  };

  /// Bucket granularity per period. Keeps every period readable instead of
  /// collapsing sparse data ("ALL = 1 bar"): short ranges bucket by day,
  /// medium ranges by week, long ranges by month.
  String get _granularity {
    switch (_period) {
      case '1W':
      case '1M':
        return 'day';
      case '3M':
      case '6M':
        return 'week';
      case '1Y':
      case 'ALL':
      default:
        return 'month';
    }
  }

  DateTime _bucketStart(DateTime d) {
    switch (_granularity) {
      case 'week':
        // ISO week start: Monday.
        final monday = d.subtract(Duration(days: d.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case 'month':
        return DateTime(d.year, d.month);
      case 'day':
      default:
        return DateTime(d.year, d.month, d.day);
    }
  }

  DateTime _nextBucket(DateTime b) {
    switch (_granularity) {
      case 'week':
        return b.add(const Duration(days: 7));
      case 'month':
        final ny = b.month == 12 ? b.year + 1 : b.year;
        final nm = b.month == 12 ? 1 : b.month + 1;
        return DateTime(ny, nm);
      case 'day':
      default:
        return b.add(const Duration(days: 1));
    }
  }

  List<MapEntry<DateTime, double>> _computeData() {
    final now = DateTime.now();
    DateTime monthsAgo(int m) {
      int y = now.year;
      int mo = now.month - m;
      while (mo <= 0) {
        mo += 12;
        y--;
      }
      final maxDay = DateUtils.getDaysInMonth(y, mo);
      return DateTime(y, mo, math.min(now.day, maxDay));
    }

    // Collect all order dates first so we can find the natural earliest
    // payment for the ALL period instead of starting in year 2000.
    DateTime? earliest;
    final List<MapEntry<DateTime, double>> raw = [];
    for (final order in widget.orders) {
      final status = order['status']?.toString().toLowerCase() ?? '';
      if (_excludedStatuses.contains(status)) continue;

      // Prefer the actual payment timestamp ("when the money arrived").
      // We treat the presence of any payment field as a strong signal that
      // money was received, even when the status string isn't one of the
      // canonical revenue statuses (different backends use very different
      // vocabularies, so being lenient here avoids the chart silently
      // showing 0 even though the home revenue card shows real numbers).
      final paidAt = order['paid_at'] ??
          order['payment_date'] ??
          order['completed_at'] ??
          order['delivered_at'];
      final hasPaymentField = paidAt != null && paidAt.toString().isNotEmpty;
      if (!hasPaymentField && !_revenueStatuses.contains(status)) continue;

      final dateStr = (paidAt ??
              order['date'] ??
              order['created_at'] ??
              order['order_date'] ??
              '')
          .toString();
      if (dateStr.isEmpty) continue;
      DateTime? date;
      try {
        date = DateTime.parse(dateStr).toLocal();
      } catch (_) {
        continue;
      }

      final amountRaw = order['amount'] ??
          order['total_amount'] ??
          order['seller_subtotal'] ??
          order['product_subtotal'] ??
          order['sellerAmount'] ??
          0;
      final value = amountRaw is num
          ? amountRaw.toDouble()
          : double.tryParse(amountRaw.toString()) ?? 0.0;
      if (value <= 0) continue;

      raw.add(MapEntry(date, value));
      if (earliest == null || date.isBefore(earliest)) earliest = date;
    }

    final rawCutoff = switch (_period) {
      '1W' => now.subtract(const Duration(days: 7)),
      '1M' => monthsAgo(1),
      '3M' => monthsAgo(3),
      '6M' => monthsAgo(6),
      '1Y' => DateTime(now.year - 1, now.month, now.day),
      _ => earliest ?? DateTime(now.year, now.month),
    };
    // Align the cutoff to the bucket boundary so we never drop orders that
    // happened earlier on the same day/week/month than `now`. Without this
    // step a 1M cutoff at e.g. 2026-03-28 14:30 silently filters out every
    // order paid before 14:30 on that day.
    final cutoff = _bucketStart(rawCutoff);

    // Aggregate into buckets keyed by their start.
    final Map<DateTime, double> byBucket = {};
    for (final entry in raw) {
      final b = _bucketStart(entry.key);
      if (b.isBefore(cutoff)) continue;
      byBucket[b] = (byBucket[b] ?? 0) + entry.value;
    }

    // Fill gaps so the timeline is continuous — much nicer to read for
    // shops that don't have daily revenue.
    if (byBucket.isEmpty) return const [];
    final start = _bucketStart(cutoff);
    final endBucket = _bucketStart(now);
    final List<MapEntry<DateTime, double>> out = [];
    DateTime cur = start;
    // Hard safety cap so a misconfigured cutoff cannot loop forever.
    int guard = 0;
    while (!cur.isAfter(endBucket) && guard < 600) {
      out.add(MapEntry(cur, byBucket[cur] ?? 0));
      cur = _nextBucket(cur);
      guard++;
    }
    return out;
  }

  String _fmtDate(DateTime d) {
    switch (_granularity) {
      case 'month':
        return '${d.month}/${d.year.toString().substring(2)}';
      case 'week':
      case 'day':
      default:
        return '${d.day}.${d.month}';
    }
  }

  /// Builds a cumulative (running total) version of the daily data.
  List<MapEntry<DateTime, double>> _toCumulative(List<MapEntry<DateTime, double>> daily) {
    double running = 0;
    return daily.map((e) {
      running += e.value;
      return MapEntry(e.key, running);
    }).toList();
  }

  double _computeTrend(List<MapEntry<DateTime, double>> daily) {
    if (daily.length < 2) return 0;
    final half = daily.length ~/ 2;
    final first = daily.take(half).fold(0.0, (s, e) => s + e.value);
    final second = daily.skip(half).fold(0.0, (s, e) => s + e.value);
    if (first == 0) return second > 0 ? 100 : 0;
    return ((second - first) / first) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.isLight;
    final daily = _computeData();
    final cumulative = _toCumulative(daily);
    final total = cumulative.isEmpty ? 0.0 : cumulative.last.value;
    final displayTotal = total;
    final displayLabel = _period == 'ALL'
        ? (AppLocalizations.of(context)?.allTime ?? 'All time')
        : _period;
    // The chart owns its own selection now, so the sheet header never
    // depends on hover state.
    const bool hIdx = false;

    final trend = _computeTrend(daily);
    final trendPositive = trend >= 0;
    final accent = isLight ? Colors.black : Colors.white;
    const positive = Color(0xFF00C896);
    const negative = Color(0xFFFF3B30);
    final dimColor = (isLight ? Colors.black : Colors.white).withOpacity(0.4);

    // ── Stats. Average is computed across non-empty buckets so a quiet
    // last week doesn't drag the per-day average to zero, and the unit
    // label adapts to the bucket granularity.
    final nonEmpty = daily.where((e) => e.value > 0).toList();
    final avgRevenue =
        nonEmpty.isEmpty ? 0.0 : total / nonEmpty.length;
    final peakEntry = daily.isEmpty
        ? null
        : daily.reduce((a, b) => a.value >= b.value ? a : b);
    final granLabel = switch (_granularity) {
      'week' => AppLocalizations.of(context)?.tr('averagePerWeekShort') ??
          'Avg / week',
      'month' => AppLocalizations.of(context)?.tr('averagePerMonthShort') ??
          'Avg / month',
      _ => AppLocalizations.of(context)?.tr('averagePerDayShort') ??
          'Avg / day',
    };
    final countLabel = switch (_granularity) {
      'week' => AppLocalizations.of(context)?.tr('weeksUnit') ?? 'weeks',
      'month' => AppLocalizations.of(context)?.tr('monthsUnit') ?? 'months',
      _ => AppLocalizations.of(context)?.daysUnit ??
          AppLocalizations.of(context)?.days ??
          'days',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DragHandle(),
          // ── Period label + trend badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  displayLabel,
                  key: ValueKey(displayLabel),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: dimColor,
                  ),
                ),
              ),
              if (daily.isNotEmpty && !hIdx) ...[
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trendPositive
                          ? CupertinoIcons.arrow_up_right
                          : CupertinoIcons.arrow_down_right,
                      size: 11,
                      color: trendPositive ? positive : negative,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${trend.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: trendPositive ? positive : negative,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),

          const SizedBox(height: 6),

          // ── Big number
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.08), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: Text(
              widget.formatCurrency(displayTotal),
              key: ValueKey(displayTotal.toStringAsFixed(2)),
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                color: isLight ? Colors.black : Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Chart (pure widgets, monochrome bars).
          SizedBox(
            height: 220,
            child: cumulative.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(CupertinoIcons.chart_bar,
                              size: 28, color: accent.withOpacity(0.4)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context)?.noRevenueInThisPeriod ?? 'No revenue in this period',
                          style: TextStyle(fontSize: 14, color: dimColor),
                        ),
                      ],
                    ),
                  )
                : TradeRepublicBarChart(
                    // Daily values – the running total is reflected in the
                    // big number above the chart, while bars show per-day
                    // revenue so spikes and quiet days remain readable.
                    data: daily.map((e) => e.value).toList(),
                    isLight: isLight,
                    valueFormatter: widget.formatCurrency,
                    highlightLatest: false,
                  ),
          ),

          // ── X-axis dates
          if (cumulative.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmtDate(cumulative.first.key),
                      style: TextStyle(fontSize: 10, color: dimColor)),
                  if (cumulative.length > 2)
                    Text(_fmtDate(cumulative[cumulative.length ~/ 2].key),
                        style: TextStyle(fontSize: 10, color: dimColor)),
                  Text(_fmtDate(cumulative.last.key),
                      style: TextStyle(fontSize: 10, color: dimColor)),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // ── Stats row
          if (daily.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: _StatChip(
                    label: granLabel,
                    value: widget.formatCurrency(avgRevenue),
                    dimColor: dimColor,
                    accent: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatChip(
                    label: AppLocalizations.of(context)?.tr('peakLabel') ??
                        'Peak',
                    value: peakEntry != null ? widget.formatCurrency(peakEntry.value) : '—',
                    dimColor: dimColor,
                    accent: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatChip(
                    label: countLabel,
                    value: '${nonEmpty.length}',
                    dimColor: dimColor,
                    accent: accent,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 16),

          // ── Period selector — shared TR-style monochrome segmented control.
          TradeRepublicPeriodSegmented(
            isLight: isLight,
            selected: _period,
            options: _periods,
            onSelect: (p) => setState(() {
              _period = p;
            }),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────
// Stat chip used inside the revenue sheet
// ─────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color dimColor;
  final Color accent;

  const _StatChip({
    required this.label,
    required this.value,
    required this.dimColor,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: dimColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: accent,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

}


// ─────────────────────────────────────────
// Live Location Modal — Business App
// ─────────────────────────────────────────

class _BusinessLiveLocationModal extends StatefulWidget {
  final String orderId;
  final bool isDark;
  final Future<Map<String, dynamic>?> Function(String) loadLocation;

  const _BusinessLiveLocationModal({
    required this.orderId,
    required this.isDark,
    required this.loadLocation,
  });

  @override
  State<_BusinessLiveLocationModal> createState() =>
      _BusinessLiveLocationModalState();
}

class _BusinessLiveLocationModalState
    extends State<_BusinessLiveLocationModal> {
  late MapController _mapController;
  Timer? _refreshTimer;
  double _latitude = 52.520008;
  double _longitude = 13.404954;
  DateTime? _lastUpdate;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isLoading || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final loc = await widget.loadLocation(widget.orderId);
      if (!mounted) return;
      double? lat;
      double? lng;
      DateTime? ts;
      if (loc != null) {
        lat = double.tryParse(loc['latitude']?.toString() ?? '');
        lng = double.tryParse(loc['longitude']?.toString() ?? '');
        final rawTs = loc['updatedAt'] ?? loc['timestamp'];
        if (rawTs != null) {
          try { ts = DateTime.parse(rawTs.toString()); } catch (_) {}
        }
      }
      if (lat != null && lng != null) {
        setState(() {
          _latitude = lat!;
          _longitude = lng!;
          _lastUpdate = ts ?? DateTime.now();
          _isLoading = false;
        });
        await Future.delayed(const Duration(milliseconds: 100));
        try { _mapController.move(LatLng(_latitude, _longitude), 15.0); } catch (_) {}
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatLastUpdate() {
    if (_lastUpdate == null) return 'Loading...';
    final diff = DateTime.now().difference(_lastUpdate!);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.location_fill,
                  color: widget.isDark ? Colors.white : Colors.black,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.liveLocation ?? 'Live Location',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: widget.isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _isLoading ? Colors.orange : Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isLoading ? 'Updating...' : _formatLastUpdate(),
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                TradeRepublicButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  isSecondary: true,
                  width: 44,
                  height: 44,
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(25),
                  onPressed: _load,
                ),
              ],
            ),
          ),

          // Map — same design as cultioo_app
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
              ),
              clipBehavior: Clip.antiAlias,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(_latitude, _longitude),
                  initialZoom: 15.0,
                  minZoom: 5.0,
                  maxZoom: 18.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: widget.isDark
                        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                        : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                    retinaMode: RetinaMode.isHighDensity(context),
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.cultioo.business',
                    maxZoom: 19,
                  ),
                  if (_isLoading)
                    const ColoredBox(
                      color: Colors.transparent,
                      child: Center(child: CultiooLoadingIndicator()),
                    ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(_latitude, _longitude),
                        width: 50,
                        height: 50,
                        alignment: Alignment.topCenter,
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            // Uber-style pulsing outer circle
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: widget.isDark
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.black.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                            ),
                            // Inner filled circle with dot
                            Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: widget.isDark ? Colors.white : Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: widget.isDark ? Colors.black : Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
}