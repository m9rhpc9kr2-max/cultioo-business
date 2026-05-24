import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/drag_handle.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../config/api_config.dart';
import '../../../shared/widgets/top_notification.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_card.dart';
import '../../../shared/widgets/trade_republic_divider.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../utils/wagon_catalog.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import '../../../shared/widgets/trade_republic_bar_chart.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

class DelviooHomePage extends StatefulWidget {
  const DelviooHomePage({super.key});

  @override
  State<DelviooHomePage> createState() => _DelviooHomePageState();
}

class _DelviooHomePageState extends State<DelviooHomePage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _statsData;
  bool _isLoadingStats = true;
  bool _isRefreshing = false;
  List<Map<String, dynamic>> _monthlyData = [];
  String _selectedPeriod = 'all-time'; // 'all-time' or 'YYYY-MM'
  String? _username; // delvioo username (login id)

  // Chart state
  String _selectedChartPeriod = '';
  List<double> _chartData = [];

  // Vehicle and sections data
  List<Map<String, dynamic>> _driverVehicles = [];
  Map<String, dynamic>? _selectedVehicle;
  List<Map<String, dynamic>> _vehicleSections = [];
  Set<int> _occupiedSectionIndices = {}; // Track which sections are occupied
  Map<int, Map<String, dynamic>> _occupiedSectionData =
      {}; // Store load data per section
  bool _isLoadingVehicles = false;

  // Animation Controllers
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late Animation<double> _headerSlideAnim;
  late Animation<double> _headerFadeAnim;

  // Header visibility controller for bottom sheets
  AnimationController? _headerVisibilityController;
  bool _isBottomSheetOpen = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Initialize chart period after localization is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _selectedChartPeriod = AppLocalizations.of(context)?.sevenDays ?? '7 Days';
        });
      }
    });

    // Load username from SharedPreferences (skip empty strings — ?? won't skip '')
    SharedPreferences.getInstance().then((prefs) {
      final u = [
        prefs.getString('username'),
        prefs.getString('delvioo_username'),
        prefs.getString('userId'),
      ].firstWhere((s) => s != null && s.isNotEmpty, orElse: () => null);
      if (mounted && u != null) setState(() => _username = u);
    });

    // Header animation (App Bar)
    _headerAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _headerSlideAnim = Tween<double>(begin: -50, end: 0).animate(
      CurvedAnimation(
        parent: _headerAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
    _headerFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut),
    );

    // Content animation
    _contentAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _loadDeliveryStats();
    _loadMonthlyData();
    _loadDriverVehicles(); // Load vehicle data

    // Start header animation immediately
    _headerAnimController.forward();

    // Initialize header visibility controller
    _headerVisibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
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

  Future<void> _loadDeliveryStats() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStats = true;
    });

    try {
      print('📊 Loading delivery statistics from Google Cloud database...');

      // Get driverId from SharedPreferences (try multiple keys)
      final prefs = await SharedPreferences.getInstance();
      final driverId =
          prefs.getString('driverId') ??
          prefs.getString('userId') ??
          prefs.getString('username') ??
          '';

      print('📊 Using driverId for stats: $driverId');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delivery-stats?driverId=$driverId'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📈 Stats API Response status: ${response.statusCode}');
      print('📈 Stats API Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('📊 Received stats data: $responseData');

        if (responseData['success'] == true && responseData['data'] != null) {
          final stats = responseData['data'];

          print('🔍 Raw stats object: $stats');
          print('🔍 Total Deliveries: ${stats['totalDeliveries']}');
          print('🔍 Total Distance: ${stats['totalDistance']}');
          print('🔍 Total Earnings: ${stats['totalEarnings']}');

          final today = stats['today'] ?? {};
          final thisWeek = stats['thisWeek'] ?? {};
          final thisMonth = stats['thisMonth'] ?? {};

          print('🔍 Today data: $today');
          print('🔍 This week data: $thisWeek');
          print('🔍 This month data: $thisMonth');

          final processedStats = {
            'totalDeliveries':
                int.tryParse(stats['totalDeliveries']?.toString() ?? '0') ?? 0,
            'totalDistance':
                double.tryParse(stats['totalDistance']?.toString() ?? '0') ??
                0.0,
            'totalEarnings':
                double.tryParse(stats['totalEarnings']?.toString() ?? '0') ??
                0.0,
            'todayDeliveries':
                int.tryParse(today['deliveries']?.toString() ?? '0') ?? 0,
            'todayDistance':
                double.tryParse(today['distance']?.toString() ?? '0') ?? 0.0,
            'todayEarnings':
                double.tryParse(today['earnings']?.toString() ?? '0') ?? 0.0,
            'weekDeliveries':
                int.tryParse(thisWeek['deliveries']?.toString() ?? '0') ?? 0,
            'weekDistance':
                double.tryParse(thisWeek['distance']?.toString() ?? '0') ?? 0.0,
            'weekEarnings':
                double.tryParse(thisWeek['earnings']?.toString() ?? '0') ?? 0.0,
            'monthDeliveries':
                int.tryParse(thisMonth['deliveries']?.toString() ?? '0') ?? 0,
            'monthDistance':
                double.tryParse(thisMonth['distance']?.toString() ?? '0') ??
                0.0,
            'monthEarnings':
                double.tryParse(thisMonth['earnings']?.toString() ?? '0') ??
                0.0,
            'averageRating':
                double.tryParse(stats['averageRating']?.toString() ?? '0') ??
                0.0,
            'completionRate':
                double.tryParse(stats['completionRate']?.toString() ?? '0') ??
                0.0,
            'onTimeRate':
                double.tryParse(stats['onTimeRate']?.toString() ?? '0') ?? 0.0,
          };

          if (!mounted) return;
          setState(() {
            _statsData = processedStats;
            _isLoadingStats = false;
          });

          // Start content animations after data loads
          if (mounted) _contentAnimController.forward();

          print('✅ Successfully loaded delivery statistics');
        } else {
          throw Exception('Invalid stats response format');
        }
      } else {
        throw Exception('Failed to load stats: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading delivery stats: $e');

      if (!mounted) return;

      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToLoadDeliveryStatistics ??
              'Failed to load delivery statistics',
        );
      }

      if (mounted) {
        setState(() {
          _statsData = {
            'totalDeliveries': 0,
            'totalDistance': 0.0,
            'totalEarnings': 0.0,
            'todayDeliveries': 0,
            'todayDistance': 0.0,
            'todayEarnings': 0.0,
            'weekDeliveries': 0,
            'weekDistance': 0.0,
            'weekEarnings': 0.0,
            'monthDeliveries': 0,
            'monthDistance': 0.0,
            'monthEarnings': 0.0,
            'averageRating': 0.0,
            'completionRate': 0.0,
            'onTimeRate': 0.0,
          };
          _isLoadingStats = false;
        });
      }

      // Still start animations even on error
      if (mounted) _contentAnimController.forward();
    }
  }

  Future<void> _loadMonthlyData() async {
    try {
      print('📅 Loading monthly earnings data...');

      // Get driverId from SharedPreferences (same as stats)
      final prefs = await SharedPreferences.getInstance();
      final driverId =
          prefs.getString('driverId') ??
          prefs.getString('userId') ??
          prefs.getString('username') ??
          '';

      print('📅 Using driverId for monthly data: $driverId');

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delivery-stats/monthly?driverId=$driverId',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true && responseData['data'] != null) {
          final monthlyList = List<Map<String, dynamic>>.from(
            responseData['data'],
          );

          if (!mounted) return;
          setState(() {
            _monthlyData = monthlyList;
          });

          print('✅ Loaded ${monthlyList.length} months of data');
        }
      }
    } catch (e) {
      print('❌ Error loading monthly data: $e');
    }
  }

  // Helper to safely parse double from database (can be String or num)
  double _parseDouble(dynamic value, [double defaultValue = 0.0]) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }

  // Load driver's vehicles and their sections
  Future<void> _loadDriverVehicles() async {
    if (!mounted) return;
    setState(() {
      _isLoadingVehicles = true;
    });

    try {
      print('🚛 Loading driver vehicles...');

      final prefs = await SharedPreferences.getInstance();

      // Debug: Show all stored keys
      print('🔑 SharedPreferences keys: ${prefs.getKeys()}');
      print('🔑 userId: ${prefs.getString('userId')}');
      print('🔑 driverId: ${prefs.getString('driverId')}');
      print('🔑 username: ${prefs.getString('username')}');

      final userId =
          prefs.getString('userId') ??
          prefs.getString('driverId') ??
          prefs.getString('username') ??
          '';

      print('🚛 Using userId for vehicles: $userId');

      // Korrigierte URL: userId als Pfad-Parameter
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/vehicles/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      print('🚛 Vehicles API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('🚛 Vehicles data: $data');

        if (data['success'] == true && data['vehicles'] != null) {
          final vehicles = List<Map<String, dynamic>>.from(data['vehicles']);

          // Prefer the primary vehicle; backend already orders by is_primary_vehicle DESC
          final primaryVehicle = vehicles.firstWhere(
            (v) =>
                v['is_primary_vehicle'] == 1 ||
                v['is_primary_vehicle'] == true ||
                v['is_primary_vehicle']?.toString() == '1',
            orElse: () => vehicles.first,
          );

          if (!mounted) return;
          setState(() {
            _driverVehicles = vehicles;
            _selectedVehicle = primaryVehicle;
            _isLoadingVehicles = false;
          });

          // Load sections directly from vehicle data (vehicle_sections JSON column)
          if (vehicles.isNotEmpty) {
            await _loadVehicleSectionsFromVehicle(primaryVehicle);
          }

          print('✅ Loaded ${vehicles.length} vehicles');
        } else {
          if (!mounted) return;
          setState(() {
            _isLoadingVehicles = false;
          });
        }
      } else {
        print('❌ Failed to load vehicles: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        if (!mounted) return;
        setState(() {
          _isLoadingVehicles = false;
        });
      }
    } catch (e) {
      print('❌ Error loading vehicles: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingVehicles = false;
      });
    }
  }

  // Load sections from vehicle data (vehicle_sections JSON column)
  Future<void> _loadVehicleSectionsFromVehicle(
    Map<String, dynamic> vehicle,
  ) async {
    try {
      print('📦 Loading sections from vehicle data...');
      print('📦 Vehicle data keys: ${vehicle.keys.toList()}');

      // Check for vehicle_sections in vehicle data
      dynamic sectionsData = vehicle['vehicle_sections'];

      print('📦 Raw vehicle_sections: $sectionsData');
      print('📦 Type: ${sectionsData.runtimeType}');

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

        print('📦 Parsed ${parsedSections.length} sections');

        if (!mounted) return;
        setState(() {
          _vehicleSections = parsedSections;
        });
      } else {
        print('📦 No vehicle_sections found in vehicle data');
        if (!mounted) return;
        setState(() {
          _vehicleSections = [];
        });
      }

      // Load occupied sections for this vehicle
      await _loadOccupiedSections(vehicle['id']);
    } catch (e) {
      print('❌ Error loading sections from vehicle: $e');
      if (!mounted) return;
      setState(() {
        _vehicleSections = [];
      });
    }
  }

  // Load occupied sections from backend
  Future<void> _loadOccupiedSections(dynamic vehicleId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      print('🔍 Loading occupied sections for vehicle ID: $vehicleId');

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delvioo/vehicles/$vehicleId/occupied-sections',
        ),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      print('🔍 Response status: ${response.statusCode}');
      print('🔍 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final occupiedSections =
              data['occupied_sections'] as List<dynamic>? ?? [];

          print('🔍 Parsing ${occupiedSections.length} occupied sections');

          // Build maps for indices and load data
          final indices = <int>{};
          final loadData = <int, Map<String, dynamic>>{};

          for (final section in occupiedSections) {
            final index = section['section_index'] as int;
            indices.add(index);
            loadData[index] = {
              'quantity': section['load_quantity'] ?? 0,
              'product': section['load_product'] ?? '',
              'unit': section['load_unit'] ?? 'kg',
              'order_id': section['order_id'],
              'auction_status': section['auction_status'],
            };
            print('🔍 Added section $index with data: ${loadData[index]}');
          }

          print(
            '🔍 Before setState - indices: $indices, loadData keys: ${loadData.keys.toList()}',
          );

          if (!mounted) return;
          if (mounted) {
            setState(() {
              _occupiedSectionIndices = indices;
              _occupiedSectionData = loadData;
            });
          }

          print(
            '🔍 After setState - _occupiedSectionIndices: $_occupiedSectionIndices',
          );
          print(
            '🔍 After setState - _occupiedSectionData keys: ${_occupiedSectionData.keys.toList()}',
          );
          print(
            '🔍 After setState - _occupiedSectionData: $_occupiedSectionData',
          );

          // Note: Load distribution analysis removed from auto-start
          // Can be triggered manually if needed
        }
      } else {
        print('❌ Failed to load occupied sections: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading occupied sections: $e');
    }
  }

  // Check if load distribution has a warning (only rear sections loaded)
  bool _hasLoadWarning() {
    if (_vehicleSections.isEmpty || _occupiedSectionIndices.isEmpty) {
      return false;
    }

    final totalSections = _vehicleSections.length;
    if (totalSections < 2) return false;

    final frontSection = 0;
    final backSection = totalSections - 1;

    // Warning if back is loaded but front is empty
    return _occupiedSectionIndices.contains(backSection) &&
        !_occupiedSectionIndices.contains(frontSection);
  }

  // Get section fill color based on actual occupation status from database
  Color _getSectionColor(int sectionIndex, bool isLight) {
    final isOccupied = _occupiedSectionIndices.contains(sectionIndex);

    // If there's a load warning, ALL sections become red/warning colored
    if (_hasLoadWarning()) {
      if (isOccupied) {
        return const Color(
          0xFFEF4444,
        ); // Red for occupied sections with warning
      } else {
        return const Color(
          0xFFEF4444,
        ).withOpacity(0.2); // Light red for empty sections with warning
      }
    }

    // Normal coloring (no warning) - Trade Republic style
    if (isOccupied) {
      return isLight ? Colors.black : Colors.white; // Black/white for occupied
    }

    return (isLight ? Colors.black : Colors.white).withOpacity(
      0.05,
    ); // Light background for empty
  }

  // Get text color based on warning state
  Color _getSectionTextColor(int sectionIndex, bool isLight, bool isOccupied) {
    if (_hasLoadWarning()) {
      if (isOccupied) {
        return Colors.white; // White text on red background
      } else {
        return const Color(0xFFEF4444); // Red text on light red background
      }
    }

    // Normal coloring — text must contrast the section background.
    // Occupied background = isLight ? black : white  →  text = inverse
    if (isOccupied) {
      return isLight ? Colors.white : Colors.black;
    }
    return (isLight ? Colors.black : Colors.white).withOpacity(0.3);
  }

  // Get color for section index (for visual variety)
  Color _getSectionAccentColor(int index) {
    final colors = [
      Colors.black, // Black
      const Color(0xFF10B981), // Green
      const Color(0xFFF59E0B), // Orange
      const Color(0xFFEF4444), // Red
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFEC4899), // Pink
    ];
    return colors[index % colors.length];
  }

  Future<void> _setVehicleAsPrimary(Map<String, dynamic> vehicle) async {
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
          // Reload full list so is_primary_vehicle flags are up to date
          await _loadDriverVehicles();
        }
      }
    } catch (e) {
      print('❌ Error setting primary vehicle from home: $e');
    }
  }

  Widget _buildActiveVehicleCard(bool isLight) {
    if (_isLoadingVehicles) {
      return const SizedBox(
        height: 76,
        child: Center(child: CultiooLoadingIndicator()),
      );
    }

    if (_selectedVehicle == null) {
      return TradeRepublicCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                CupertinoIcons.car_detailed,
                size: 22,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.35),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                AppLocalizations.of(context)?.noVehicleSelected ?? 'No vehicle selected',
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: FontWeight.w600,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.45),
                ),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.25),
            ),
          ],
        ),
      );
    }

    final make = _selectedVehicle!['vehicle_make']?.toString() ?? '';
    final model = _selectedVehicle!['vehicle_model']?.toString() ?? '';
    final year = _selectedVehicle!['vehicle_year']?.toString() ?? '';
    final licensePlate = _selectedVehicle!['license_plate']?.toString() ?? '';
    final vehicleType = _selectedVehicle!['vehicle_type']?.toString() ?? '';
    final isPrimary =
        _selectedVehicle!['is_primary_vehicle'] == 1 ||
        _selectedVehicle!['is_primary_vehicle'] == true ||
        _selectedVehicle!['is_primary_vehicle']?.toString() == '1';
    final vehicleName =
        [year, make, model].where((s) => s.isNotEmpty).join(' ');

    return TradeRepublicCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          // Icon with primary star badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? const Color(0xFF00C853).withOpacity(0.12)
                      : (isLight ? Colors.black : Colors.white).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                ),
                child: Icon(
                  _getVehicleIcon(_selectedVehicle!),
                  size: 24,
                  color: isPrimary
                      ? const Color(0xFF00C853)
                      : (isLight ? Colors.black : Colors.white),
                ),
              ),
              if (isPrimary)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00C853),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.star_fill,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Vehicle name + plate + badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicleName.isNotEmpty ? vehicleName : (AppLocalizations.of(context)?.vehicle ?? 'Vehicle'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (licensePlate.isNotEmpty) licensePlate,
                    if (vehicleType.isNotEmpty) wagonLabelFromType(vehicleType, AppLocalizations.of(context) ?? AppLocalizations(const Locale('en'))),
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 13,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isPrimary) ...[  
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          size: 11,
                          color: Color(0xFF00C853),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context)?.activeToday ?? 'Active today',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF00C853),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Arrow only when multiple vehicles
          if (_driverVehicles.length > 1)
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
            ),
        ],
      ),
    );
  }

  Future<void> _refreshAllData() async {
    setState(() { _isRefreshing = true; });
    await Future.wait([
      _loadDeliveryStats(),
      _loadMonthlyData(),
      _loadDriverVehicles(),
    ]);
    if (mounted) setState(() { _isRefreshing = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);

    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: _isLoadingStats && !_isRefreshing
          ? const Center(child: CultiooLoadingIndicator())
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
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Welcome Header - Trade Republic Style
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      isDesktop ? 32 : MediaQuery.of(context).padding.top + 16,
                      20,
                      24,
                    ),
                    child: _buildAnimatedContainer(
                      delay: 0,
                      child: _buildWelcomeHeader(isLight, appSettings),
                    ),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                  // Active Vehicle Card + inline switcher
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              AppLocalizations.of(context)?.myVehicle ?? 'My Vehicle',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.45),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        _buildActiveVehicleCard(isLight),
                        // Inline vehicle switcher pills (only when 2+ vehicles)
                        if (_driverVehicles.length > 1) ...[  
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.zero,
                              itemCount: _driverVehicles.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final v = _driverVehicles[index];
                                final isSelected =
                                    v['id'] == _selectedVehicle?['id'];
                                final plate =
                                    v['license_plate']?.toString() ?? '';
                                final make =
                                    v['vehicle_make']?.toString() ?? '';
                                final label = plate.isNotEmpty ? plate : make;
                                return TradeRepublicTap(
                                  onTap: isSelected
                                      ? null
                                      : () async {
                                          HapticFeedback.lightImpact();
                                          setState(() {
                                            _selectedVehicle = v;
                                            _occupiedSectionIndices = {};
                                          });
                                          await _setVehicleAsPrimary(v);
                                          await _loadVehicleSectionsFromVehicle(v);
                                        },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 0),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? (isLight ? Colors.black : Colors.white)
                                          : (isLight ? Colors.black : Colors.white)
                                              .withOpacity(0.07),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _getVehicleIcon(v),
                                          size: 14,
                                          color: isSelected
                                              ? (isLight ? Colors.white : Colors.black)
                                              : (isLight ? Colors.black : Colors.white)
                                                  .withOpacity(0.5),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          label.isNotEmpty ? label : '#${index + 1}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? (isLight ? Colors.white : Colors.black)
                                                : (isLight ? Colors.black : Colors.white)
                                                    .withOpacity(0.55),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Total Earnings Card - Animated
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                    child: _buildAnimatedContainer(
                      delay: 1,
                      slideFromRight: false,
                      child: _buildEarningsCard(isLight, appSettings),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Stats Grid - Animated
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                    child: _buildAnimatedContainer(
                      delay: 2,
                      child: _buildStatsGrid(isLight, appSettings),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Truck Visualization - Animated
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                    child: _buildAnimatedContainer(
                      delay: 3,
                      child: _buildTruckVisualization(isLight, appSettings),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Fuel & Emissions Section - Animated
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                    child: _buildAnimatedContainer(
                      delay: 4,
                      slideFromRight: true,
                      child: _buildFuelEmissionsSection(isLight, appSettings),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Period Statistics - Animated
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                    child: _buildAnimatedContainer(
                      delay: 5,
                      slideFromRight: true,
                      child: _buildPeriodStatistics(isLight, appSettings),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
                ],
              ),
            ),
            ],
            ),
              ),
            ),
    );
  }

  // Animated Container Widget with Staggered Animation - From top/bottom
  Widget _buildAnimatedContainer({
    required int delay,
    required Widget child,
    bool slideFromRight = false, // Now interpreted as slideFromBottom
  }) {
    return AnimatedBuilder(
      animation: _contentAnimController,
      builder: (context, _) {
        // Calculate staggered delay
        final delayedValue = (_contentAnimController.value - (delay * 0.15))
            .clamp(0.0, 1.0);
        final curvedValue = Curves.easeOutCubic.transform(
          delayedValue > 0
              ? (delayedValue / (1 - delay * 0.15)).clamp(0.0, 1.0)
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

  Widget _buildWelcomeHeader(bool isLight, AppSettings appSettings) {
    // Prefer the login username; fall back to first name only (not full name)
    final displayName = (_username != null && _username!.isNotEmpty)
        ? '@$_username'
        : (appSettings.userName?.split(' ').first ?? 'Driver');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.welcomeBack ?? 'Welcome back,',
          style: TextStyle(
            color: isLight
                ? Colors.black.withOpacity(0.5)
                : Colors.white.withOpacity(0.5),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          displayName,
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildEarningsCard(bool isLight, AppSettings appSettings) {
    // Calculate earnings based on selected period
    double displayEarnings = 0.0;
    String periodLabel = AppLocalizations.of(context)?.allTime ?? 'All-Time';

    if (_selectedPeriod == 'all-time') {
      final totalEarningsRaw = _statsData?['totalEarnings'];
      displayEarnings =
          double.tryParse(totalEarningsRaw?.toString() ?? '0') ?? 0.0;
      periodLabel = AppLocalizations.of(context)?.allTime ?? 'All-Time';
    } else {
      // Find the selected month's data
      final monthData = _monthlyData.firstWhere(
        (m) => m['month'] == _selectedPeriod,
        orElse: () => {'earnings': '0'},
      );
      final earningsRaw = monthData['earnings'];
      displayEarnings = double.tryParse(earningsRaw?.toString() ?? '0') ?? 0.0;

      // Format month label (e.g., "2025-11" -> "November 2025")
      try {
        final parts = _selectedPeriod.split('-');
        final year = parts[0];
        final monthNum = int.parse(parts[1]);
        final monthNames = [
          '',
          AppLocalizations.of(context)?.january ?? 'January',
          AppLocalizations.of(context)?.february ?? 'February',
          AppLocalizations.of(context)?.march ?? 'March',
          AppLocalizations.of(context)?.april ?? 'April',
          AppLocalizations.of(context)?.may ?? 'May',
          AppLocalizations.of(context)?.june ?? 'June',
          AppLocalizations.of(context)?.july ?? 'July',
          AppLocalizations.of(context)?.august ?? 'August',
          AppLocalizations.of(context)?.september ?? 'September',
          AppLocalizations.of(context)?.october ?? 'October',
          AppLocalizations.of(context)?.november ?? 'November',
          AppLocalizations.of(context)?.december ?? 'December',
        ];
        periodLabel = '${monthNames[monthNum]} $year';
      } catch (e) {
        periodLabel = _selectedPeriod;
      }
    }

    final convertedEarnings = appSettings.convertCurrency(displayEarnings);

    // Trade Republic Style - Large number without container
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Large earnings number
        Text(
          appSettings.formatCurrency(convertedEarnings),
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)?.totalEarnings ?? 'Total Earnings',
          style: TextStyle(
            color: isLight
                ? Colors.black.withOpacity(0.5)
                : Colors.white.withOpacity(0.5),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
        // Period selector row
        TradeRepublicCard(
          onTap: () {
            HapticFeedback.lightImpact();
            _showPeriodSelector(isLight, appSettings);
          },
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.calendar,
                color: isLight ? Colors.black : Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                periodLabel,
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                CupertinoIcons.chevron_down,
                color: (isLight ? Colors.black : Colors.white).withOpacity(
                  0.5,
                ),
                size: 16,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPeriodSelector(bool isLight, AppSettings appSettings) {
    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: true,
      enableDrag: true,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trade Republic Handle bar
            DragHandle(),

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
                  AppLocalizations.of(context)?.selectPeriod ?? 'Select Period',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // Period list
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // All-Time option
                  _buildPeriodOption(
                    isLight: isLight,
                    icon: CupertinoIcons.infinite,
                    title: AppLocalizations.of(context)?.allTime ?? 'All-Time',
                    subtitle:
                        AppLocalizations.of(context)?.sinceCompanyFounding ??
                        'Since company founding',
                    earnings: appSettings.formatCurrency(
                      appSettings.convertCurrency(
                        _parseDouble(_statsData?['totalEarnings']),
                      ),
                    ),
                    isSelected: _selectedPeriod == 'all-time',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedPeriod = 'all-time';
                      });
                      Navigator.pop(context);
                    },
                  ),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                  // Divider with label
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TradeRepublicDivider(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.1),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
                          child: Text(
                            AppLocalizations.of(context)?.monthlyPeriods ??
                                'MONTHLY PERIODS',
                            style: TextStyle(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TradeRepublicDivider(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.1),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Monthly options
                  ..._monthlyData.map((monthData) {
                    final month = monthData['month'];
                    final earningsRaw = monthData['earnings'];
                    final earnings =
                        double.tryParse(earningsRaw?.toString() ?? '0') ?? 0.0;
                    final deliveries =
                        int.tryParse(
                          monthData['deliveries']?.toString() ?? '0',
                        ) ??
                        0;
                    final convertedEarnings = appSettings.convertCurrency(
                      earnings,
                    );

                    // Format month label
                    String monthLabel = month;
                    try {
                      final parts = month.split('-');
                      final year = parts[0];
                      final monthNum = int.parse(parts[1]);
                      final monthNames = [
                        '',
                        AppLocalizations.of(context)?.january ?? 'January',
                        AppLocalizations.of(context)?.february ?? 'February',
                        AppLocalizations.of(context)?.march ?? 'March',
                        AppLocalizations.of(context)?.april ?? 'April',
                        AppLocalizations.of(context)?.may ?? 'May',
                        AppLocalizations.of(context)?.june ?? 'June',
                        AppLocalizations.of(context)?.july ?? 'July',
                        AppLocalizations.of(context)?.august ?? 'August',
                        AppLocalizations.of(context)?.september ?? 'September',
                        AppLocalizations.of(context)?.october ?? 'October',
                        AppLocalizations.of(context)?.november ?? 'November',
                        AppLocalizations.of(context)?.december ?? 'December',
                      ];
                      monthLabel = '${monthNames[monthNum]} $year';
                    } catch (e) {
                      // Use raw month string if parsing fails
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildPeriodOption(
                        isLight: isLight,
                        icon: CupertinoIcons.calendar,
                        title: monthLabel,
                        subtitle:
                            '$deliveries ${deliveries == 1 ? 'delivery' : 'deliveries'}',
                        earnings: appSettings.formatCurrency(convertedEarnings),
                        isSelected: _selectedPeriod == month,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _selectedPeriod = month;
                          });
                          Navigator.pop(context);
                        },
                      ),
                    );
                  }),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodOption({
    required bool isLight,
    required IconData icon,
    required String title,
    required String subtitle,
    required String earnings,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final periodCard = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isSelected
            ? (isLight ? Colors.black : Colors.white).withOpacity(0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: (isLight ? Colors.black : Colors.white).withOpacity(
              isSelected ? 1.0 : 0.5,
            ),
            size: 22,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Text(
            earnings,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 12),
            Icon(
              CupertinoIcons.checkmark,
              color: isLight ? Colors.black : Colors.white,
              size: 18,
            ),
          ],
        ],
      ),
    );

    return TradeRepublicTap(onTap: onTap, child: periodCard);
  }

  Widget _buildStatsGrid(bool isLight, AppSettings appSettings) {
    final totalDeliveries = (_statsData?['totalDeliveries'] is int)
        ? (_statsData?['totalDeliveries'] as int).toDouble()
        : (int.tryParse(_statsData?['totalDeliveries']?.toString() ?? '0') ?? 0)
            .toDouble();
    final totalDistance = _parseDouble(_statsData?['totalDistance']);
    final averageRating = _parseDouble(_statsData?['averageRating']);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildAnimatedStatCard(
                delay: 0,
                child: TradeRepublicTap(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showChartModal(
                      AppLocalizations.of(context)?.deliveries ?? 'Deliveries',
                      'deliveries',
                      isLight,
                    );
                  },
                  child: _buildStatCard(
                    title:
                        AppLocalizations.of(context)?.deliveries ?? 'Deliveries',
                    value:
                        appSettings.formatNumber(totalDeliveries, decimals: 0),
                    icon: CupertinoIcons.cube_box,
                    color: isLight ? Colors.black : Colors.white,
                    isLight: isLight,
                    showChartIcon: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildAnimatedStatCard(
                delay: 1,
                child: TradeRepublicTap(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showChartModal(
                      AppLocalizations.of(context)?.distance ?? 'Distance',
                      'distance',
                      isLight,
                    );
                  },
                  child: _buildStatCard(
                    title: AppLocalizations.of(context)?.distance ?? 'Distance',
                    value: appSettings.formatDistance(totalDistance),
                    icon: CupertinoIcons.location,
                    color: isLight ? Colors.black : Colors.white,
                    isLight: isLight,
                    showChartIcon: true,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
        _buildAnimatedStatCard(
          delay: 2,
          child: TradeRepublicTap(
            onTap: () {
              HapticFeedback.lightImpact();
              _showChartModal(
                AppLocalizations.of(context)?.averageRating ?? 'Average Rating',
                'earnings',
                isLight,
              );
            },
            child: _buildWideStatCard(
              title:
                  AppLocalizations.of(context)?.averageRating ?? 'Average Rating',
              value: appSettings.formatNumber(averageRating, decimals: 1),
              icon: CupertinoIcons.star,
              color: isLight ? Colors.black : Colors.white,
              isLight: isLight,
              showChartIcon: true,
            ),
          ),
        ),
      ],
    );
  }

  // Truck Visualization with Sections
  Widget _buildTruckVisualization(bool isLight, AppSettings appSettings) {
    // Count occupied and empty sections based on actual database data
    final occupiedCount = _occupiedSectionIndices.length;
    final emptyCount = _vehicleSections.length - occupiedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title with Vehicle Selector
        Row(
          children: [
            Text(
              AppLocalizations.of(context)?.vehicleCapacity ??
                  'Vehicle Capacity',
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            // Vehicle Selector Button
            if (_driverVehicles.length > 1)
              Flexible(
                child: TradeRepublicTap(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showVehicleSelector(isLight);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.05),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${_selectedVehicle?['vehicle_make'] ?? ''} ${_selectedVehicle?['vehicle_model'] ?? ''}'
                                .trim(),
                            style: TextStyle(
                              color: isLight ? Colors.black : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins',
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          CupertinoIcons.chevron_down,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        // Truck Container
        Container(
          width: double.infinity,
          padding: DesktopAppWrapper.getPagePadding(),
          decoration: BoxDecoration(
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.03),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Column(
            children: [
              // Truck Visualization
              if (_isLoadingVehicles)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CultiooLoadingIndicator(),
                  ),
                )
              else if (_vehicleSections.isEmpty)
                _buildEmptyTruckState(isLight)
              else
                _buildTruckWithSections(isLight),
            ],
          ),
        ),
      ],
    );
  }

  // Empty truck state when no sections configured
  Widget _buildEmptyTruckState(bool isLight) {
    return SizedBox(
      height: 120,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.cube_box,
            size: 48,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Text(
            AppLocalizations.of(context)?.noVehicleSectionsConfigured ??
                'No vehicle sections configured',
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)?.addSectionsInMaps ??
                'Add sections in Maps → Vehicle Settings',
            style: TextStyle(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Build truck with sections visualization - Minimal Style like Maps
  Widget _buildTruckWithSections(bool isLight) {
    final totalSections = _vehicleSections.length;

    // Get cargo capacity and unit from vehicle data
    double totalCargoCapacity = 0.0;
    String cargoUnit = 'm³';

    if (_selectedVehicle != null) {
      // Safely parse cargo_capacity (can be String or num from database)
      final capacityRaw = _selectedVehicle!['cargo_capacity'];
      if (capacityRaw != null) {
        if (capacityRaw is num) {
          totalCargoCapacity = capacityRaw.toDouble();
        } else {
          totalCargoCapacity = double.tryParse(capacityRaw.toString()) ?? 0.0;
        }
      }
      cargoUnit = _selectedVehicle!['cargo_unit']?.toString() ?? 'm³';
    }

    // Truck Visualization - Minimal Style like Maps
    return Container(
      height: 120,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            // Cabin - minimal (also red if warning)
            Container(
              width: 50,
              decoration: BoxDecoration(
                color: _hasLoadWarning()
                    ? const Color(0xFFEF4444).withOpacity(0.3)
                    : (isLight ? Colors.black : Colors.white).withOpacity(0.05),
              ),
              child: Center(
                child: Icon(
                  CupertinoIcons.cube_box,
                  color: _hasLoadWarning()
                      ? const Color(0xFFEF4444)
                      : (isLight ? Colors.black : Colors.white).withOpacity(
                          0.3,
                        ),
                  size: 24,
                ),
              ),
            ),
            // Sections
            Expanded(
              child: Row(
                children: _vehicleSections.asMap().entries.map((entry) {
                  final index = entry.key;
                  final section = entry.value;

                  // Safely parse percentage
                  final percentageRaw = section['percentage'];
                  int percentage;
                  if (percentageRaw is num) {
                    percentage = percentageRaw.toInt();
                  } else if (percentageRaw != null) {
                    percentage =
                        double.tryParse(percentageRaw.toString())?.toInt() ??
                        (100 ~/ totalSections);
                  } else {
                    percentage = 100 ~/ totalSections;
                  }

                  final sectionCapacity =
                      totalCargoCapacity * (percentage / 100);
                  // Use actual occupied sections from database
                  final isOccupied = _occupiedSectionIndices.contains(index);

                  // Get text colors based on warning state
                  final mainTextColor = _getSectionTextColor(
                    index,
                    isLight,
                    isOccupied,
                  );
                  final subTextColor = _hasLoadWarning()
                      ? mainTextColor.withOpacity(0.7)
                      : (isOccupied
                            // Occupied background = isLight?black:white → subtitle is inverse
                            ? (isLight ? Colors.white : Colors.black).withOpacity(0.7)
                            : (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.4));

                  return Expanded(
                    flex: percentage > 0 ? percentage : 1,
                    child: TradeRepublicTap(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showSectionDetails(section, index, isLight);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: _getSectionColor(index, isLight),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Section number - large
                              Text(
                                '${index + 1}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                                  fontWeight: FontWeight.w800,
                                  color: mainTextColor,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Capacity with original unit
                              Text(
                                totalCargoCapacity > 0
                                    ? '${AppSettings().formatNumber(sectionCapacity, decimals: 1)} $cargoUnit'
                                    : '$percentage%',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: subTextColor,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build a wheel
  Widget _buildWheel(bool isLight) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: isLight ? Colors.black : Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }

  // Build legend item
  Widget _buildLegendItem({
    required Color color,
    required String label,
    required bool isLight,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // Show vehicle selector bottom sheet - Modern Design like Maps
  void _showVehicleSelector(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            // Trade Republic Handle bar
            DragHandle(),
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
                  AppLocalizations.of(context)?.selectVehicle ?? 'Select Vehicle',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white, letterSpacing: -0.4),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            // Vehicle List
            Expanded(
              child: _driverVehicles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.car,
                            size: 64,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.3),
                          ),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          Text(
                            AppLocalizations.of(
                                  context,
                                )?.noVehiclesRegistered ??
                                'No vehicles registered',
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black : Colors.white,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _driverVehicles.length,
                      itemBuilder: (context, index) {
                        final vehicle = _driverVehicles[index];
                        final isSelected =
                            vehicle['id'] == _selectedVehicle?['id'];

                        // Build vehicle display info
                        final make = vehicle['vehicle_make']?.toString() ?? '';
                        final model =
                            vehicle['vehicle_model']?.toString() ?? '';
                        final year = vehicle['vehicle_year']?.toString() ?? '';
                        final licensePlate =
                            vehicle['license_plate']?.toString() ?? '';
                        final vehicleType =
                            vehicle['vehicle_type']?.toString() ?? '';
                        final hasSections =
                            (vehicle['sectional_loading_enabled'] == 1 ||
                            vehicle['sectional_loading_enabled'] == true);
                        final numSections = vehicle['number_of_sections'] ?? 1;

                        final vehicleName = '$make $model'.trim();
                        final vehicleTypeLabel = vehicleType.isNotEmpty
                            ? wagonLabelFromType(vehicleType, AppLocalizations.of(context) ?? AppLocalizations(const Locale('en')))
                            : '';
                        final vehicleDescription = [
                          if (year.isNotEmpty) year,
                          if (licensePlate.isNotEmpty) licensePlate,
                          if (vehicleTypeLabel.isNotEmpty) vehicleTypeLabel,
                        ].where((s) => s.isNotEmpty).join(' • ');

                        // Get cargo capacity
                        final cargoCapacity = _parseDouble(
                          vehicle['cargo_capacity'],
                        );
                        final cargoUnit =
                            vehicle['cargo_unit']?.toString() ?? 'm³';

                        return TradeRepublicTap(
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _selectedVehicle = vehicle;
                              _occupiedSectionIndices =
                                  {}; // Reset while loading
                            });
                            Navigator.pop(context);
                            // Persist selection as primary vehicle in DB
                            await _setVehicleAsPrimary(vehicle);
                            await _loadVehicleSectionsFromVehicle(vehicle);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isLight ? Colors.black : Colors.white)
                                        .withOpacity(0.05)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            ),
                            child: Row(
                              children: [
                                // Vehicle Icon
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                  ),
                                  child: Icon(
                                    _getVehicleIcon(vehicle),
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Vehicle Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        vehicleName.isNotEmpty
                                            ? vehicleName
                                            : AppLocalizations.of(
                                                    context,
                                                  )?.vehicle ??
                                                  'Vehicle',
                                        style: TextStyle(
                                          fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                          fontWeight: FontWeight.w600,
                                          color: isLight
                                              ? Colors.black
                                              : Colors.white,
                                          fontFamily: 'Poppins',
                                        ),
                                      ),
                                      if (vehicleDescription.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          vehicleDescription,
                                          style: TextStyle(
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                            color: isLight
                                                ? Colors.black
                                                : Colors.white,
                                            fontFamily: 'Poppins',
                                          ),
                                        ),
                                      ],
                                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                      // Capacity & Sections info
                                      Row(
                                        children: [
                                          if (cargoCapacity > 0)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    (isLight
                                                            ? Colors.black
                                                            : Colors.white)
                                                        .withOpacity(0.05),
                                                borderRadius:
                                                    BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                              ),
                                              child: Text(
                                                '📦 ${AppSettings().formatNumber(cargoCapacity, decimals: 1)} $cargoUnit',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color:
                                                      (isLight
                                                              ? Colors.black
                                                              : Colors.white)
                                                          .withOpacity(0.6),
                                                  fontFamily: 'Poppins',
                                                ),
                                              ),
                                            ),
                                          if (hasSections) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isLight
                                                    ? Colors.green.withOpacity(
                                                        0.1,
                                                      )
                                                    : Colors.green.withOpacity(
                                                        0.2,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                              ),
                                              child: Text(
                                                '🚛 $numSections sections',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: isLight
                                                      ? Colors.green[800]
                                                      : Colors.green[300],
                                                  fontFamily: 'Poppins',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Selection indicator
                                if (isSelected)
                                  Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                    size: 28,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Safe area padding
            SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
          ],
        ),
      ),
    );
  }

  // Get vehicle icon based on type
  IconData _getVehicleIcon(Map<String, dynamic> vehicle) {
    final type = (vehicle['vehicle_type'] ?? '').toString().toLowerCase();
    if (type.contains('truck') || type.contains('hopper')) {
      return CupertinoIcons.cube_box;
    } else if (type.contains('van') || type.contains('transporter')) {
      return CupertinoIcons.bus;
    } else if (type.contains('car')) {
      return CupertinoIcons.car;
    } else if (type.contains('trailer')) {
      return CupertinoIcons.car;
    }
    return CupertinoIcons.cube_box;
  }

  // Show section details
  void _showSectionDetails(
    Map<String, dynamic> section,
    int sectionIndex,
    bool isLight,
  ) {
    // Use the actual occupied status from database
    final isOccupied = _occupiedSectionIndices.contains(sectionIndex);
    // Get load data for this section
    final loadData = _occupiedSectionData[sectionIndex];
    final rawQuantity = loadData?['quantity'];
    final loadQuantity = rawQuantity is num
        ? rawQuantity.toDouble()
        : (double.tryParse(rawQuantity?.toString() ?? '') ?? 0.0);
    final loadProduct = loadData?['product']?.toString() ?? '';
    final loadUnit = loadData?['unit']?.toString() ?? 'kg';

    print('📦 _showSectionDetails called:');
    print('   - sectionIndex: $sectionIndex');
    print('   - isOccupied: $isOccupied');
    print('   - _occupiedSectionIndices: $_occupiedSectionIndices');
    print(
      '   - _occupiedSectionData keys: ${_occupiedSectionData.keys.toList()}',
    );
    print('   - loadData for index $sectionIndex: $loadData');
    print('   - loadQuantity: $loadQuantity, loadUnit: $loadUnit');

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trade Republic Handle bar
          DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.square_grid_2x2,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                section['name'] ?? '${AppLocalizations.of(context)?.section ?? 'Section'} ${sectionIndex + 1}',
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Text(
            isOccupied
                ? AppLocalizations.of(context)?.currentlyOccupied ??
                      'Currently occupied'
                : AppLocalizations.of(context)?.availableForLoading ??
                      'Available for loading',
            style: TextStyle(
              color: isOccupied
                  ? (isLight ? Colors.black : Colors.white).withOpacity(0.5)
                  : const Color(0xFF10B981),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Capacity Info
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${AppSettings().formatNumber(_parseDouble(section['percentage'], 100 / _vehicleSections.length), decimals: 0)}%',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)?.capacity ?? 'Capacity',
                        style: TextStyle(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          fontSize: 13,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.1,
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        isOccupied ? '1' : '0',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)?.orders ?? 'Orders',
                        style: TextStyle(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          fontSize: 13,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Load Info if occupied
          if (isOccupied) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            Container(
              padding: DesktopAppWrapper.getPagePadding(),
              decoration: BoxDecoration(
                color: (isLight ? Colors.black : Colors.white).withOpacity(
                  0.03,
                ),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.cube_box,
                        color: isLight ? Colors.black : Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)?.currentLoad ??
                            'Current Load',
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  // Load quantity - big display
                  Row(
                    children: [
                      Text(
                        AppSettings().formatNumber(loadQuantity, decimals: 2),
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        loadUnit,
                        style: TextStyle(
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.6),
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ],
                  ),
                  if (loadProduct.isNotEmpty) ...[
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    Text(
                      loadProduct,
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.7),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Available message if not occupied
          if (!isOccupied) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            Container(
              padding: DesktopAppWrapper.getPagePadding(),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: Color(0xFF10B981),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.sectionEmptyReadyForCargo ??
                          'This section is empty and ready for new cargo.',
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.7),
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        ],
      ),
    );
  }

  // Animated Stat Card mit Pop-In Effekt
  Widget _buildAnimatedStatCard({required int delay, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (delay * 100)),
      curve: Curves.easeOutBack,
      builder: (context, value, _) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isLight,
    bool showChartIcon = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.03),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: isLight ? Colors.black : Colors.white, size: 22),
              if (showChartIcon)
                Icon(
                  CupertinoIcons.chart_bar_alt_fill,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                  size: 18,
                ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Text(
            value,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isLight,
    bool showChartIcon = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.03),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        children: [
          Icon(icon, color: isLight ? Colors.black : Colors.white, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (showChartIcon)
            Icon(
              CupertinoIcons.chart_bar_alt_fill,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
              size: 20,
            ),
        ],
      ),
    );
  }

  // Chart Modal
  void _showChartModal(String title, String metric, bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    setState(() {
      _chartData = _buildRealChartData(metric, _selectedChartPeriod);
    });

    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: true,
      enableDrag: true,
      child: StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          // Percent change: this month vs. previous month from real monthly data
          final percentChange = _calcPercentChange(metric);
          final isPositive = percentChange >= 0;

          // Display value from _statsData (all-time totals)
          String displayValue;
          switch (metric) {
            case 'deliveries':
              displayValue = appSettings.formatNumber(
                _parseDouble(_statsData?['totalDeliveries']), decimals: 0);
              break;
            case 'distance':
              displayValue = appSettings.formatDistance(
                _parseDouble(_statsData?['totalDistance']));
              break;
            case 'earnings':
              displayValue = appSettings.formatCurrency(
                _parseDouble(_statsData?['totalEarnings']));
              break;
            default:
              displayValue = appSettings.formatNumber(
                _parseDouble(_statsData?['averageRating']), decimals: 1);
          }

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DragHandle(),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.chart_bar_circle,
                      color: isLight ? Colors.black : Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      displayValue,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (percentChange != 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              isPositive
                                  ? CupertinoIcons.arrow_up_right
                                  : CupertinoIcons.arrow_down_right,
                              color: isPositive
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${appSettings.formatNumber(percentChange.abs(), decimals: 1)}%',
                              style: TextStyle(
                                color: isPositive
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444),
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                Text(
                  _selectedChartPeriod,
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 260,
                  child: _chartData.length < 2
                      ? Center(
                          child: Text(
                            'No data available',
                            style: TextStyle(
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                            ),
                          ),
                        )
                      : TradeRepublicBarChart(
                          data: _chartData,
                          isLight: isLight,
                          valueFormatter: (v) {
                            switch (metric) {
                              case 'earnings':
                                return appSettings.formatCurrency(v);
                              case 'distance':
                                return appSettings.formatDistance(v);
                              default:
                                return appSettings.formatNumber(v, decimals: 0);
                            }
                          },
                        ),
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                TradeRepublicPeriodSegmented(
                  isLight: isLight,
                  selected: _selectedChartPeriod,
                  options: [
                    AppLocalizations.of(context)?.twentyFourHours ?? '24 Hours',
                    AppLocalizations.of(context)?.sevenDays ?? '7 Days',
                    AppLocalizations.of(context)?.oneMonth ?? '1 Month',
                    AppLocalizations.of(context)?.sixMonths ?? '6 Months',
                    AppLocalizations.of(context)?.oneYear ?? '1 Year',
                  ],
                  onSelect: (period) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedChartPeriod = period;
                      _chartData = _buildRealChartData(metric, period);
                    });
                    setModalState(() {});
                  },
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Build chart data from real monthly stats. Maps period label → number of months.
  List<double> _buildRealChartData(String metric, String period) {
    if (_monthlyData.isEmpty) return [];

    final loc = AppLocalizations.of(context);
    int numMonths;
    if (period == (loc?.oneYear ?? '1 Year')) {
      numMonths = 12;
    } else if (period == (loc?.sixMonths ?? '6 Months')) {
      numMonths = 6;
    } else {
      numMonths = 3; // 24h / 7 days / 1 month — show 3 months for context
    }

    // Sort by 'YYYY-MM' string (lexicographic = chronological)
    final sorted = List<Map<String, dynamic>>.from(_monthlyData)
      ..sort((a, b) =>
          (a['month']?.toString() ?? '').compareTo(b['month']?.toString() ?? ''));

    final slice = sorted.length > numMonths
        ? sorted.sublist(sorted.length - numMonths)
        : sorted;

    return slice.map((m) {
      final raw = m[metric];
      if (raw == null) return 0.0;
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw.toString()) ?? 0.0;
    }).toList();
  }

  /// Percent change between the two most recent months.
  double _calcPercentChange(String metric) {
    if (_monthlyData.length < 2) return 0.0;
    final sorted = List<Map<String, dynamic>>.from(_monthlyData)
      ..sort((a, b) =>
          (a['month']?.toString() ?? '').compareTo(b['month']?.toString() ?? ''));
    final prevVal = _parseDouble(sorted[sorted.length - 2][metric]);
    final currVal = _parseDouble(sorted[sorted.length - 1][metric]);
    if (prevVal == 0) return 0.0;
    return ((currVal - prevVal) / prevVal) * 100;
  }

  Widget _buildPeriodStatistics(bool isLight, AppSettings appSettings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.timePeriodStats ?? 'Time Period Stats',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
        _buildAnimatedPeriodCard(
          delay: 0,
          child: _buildPeriodCard(
            title: AppLocalizations.of(context)?.today ?? 'Today',
            deliveries: appSettings.formatNumber(
              _parseDouble(_statsData?['todayDeliveries']),
              decimals: 0,
            ),
            distance: appSettings.formatDistance(
              _parseDouble(_statsData?['todayDistance']),
            ),
            earnings: appSettings.formatCurrency(
              appSettings.convertCurrency(
                _parseDouble(_statsData?['todayEarnings']),
              ),
            ),
            isLight: isLight,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        _buildAnimatedPeriodCard(
          delay: 1,
          child: _buildPeriodCard(
            title: AppLocalizations.of(context)?.thisWeek ?? 'This Week',
            deliveries: appSettings.formatNumber(
              _parseDouble(_statsData?['weekDeliveries']),
              decimals: 0,
            ),
            distance: appSettings.formatDistance(
              _parseDouble(_statsData?['weekDistance']),
            ),
            earnings: appSettings.formatCurrency(
              appSettings.convertCurrency(
                _parseDouble(_statsData?['weekEarnings']),
              ),
            ),
            isLight: isLight,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        _buildAnimatedPeriodCard(
          delay: 2,
          child: _buildPeriodCard(
            title: AppLocalizations.of(context)?.thisMonth ?? 'This Month',
            deliveries: appSettings.formatNumber(
              _parseDouble(_statsData?['monthDeliveries']),
              decimals: 0,
            ),
            distance: appSettings.formatDistance(
              _parseDouble(_statsData?['monthDistance']),
            ),
            earnings: appSettings.formatCurrency(
              appSettings.convertCurrency(
                _parseDouble(_statsData?['monthEarnings']),
              ),
            ),
            isLight: isLight,
          ),
        ),
      ],
    );
  }

  // Animated Period Card mit Slide-Up Effekt
  Widget _buildAnimatedPeriodCard({required int delay, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 500 + (delay * 150)),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
    );
  }

  Widget _buildPeriodCard({
    required String title,
    required String deliveries,
    required String distance,
    required String earnings,
    required bool isLight,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.03),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Row(
            children: [
              Expanded(
                child: _buildPeriodStat(
                  deliveries,
                  AppLocalizations.of(context)?.deliveries ?? 'Deliveries',
                  CupertinoIcons.cube_box,
                  isLight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPeriodStat(
                  distance,
                  AppLocalizations.of(context)?.distance ?? 'Distance',
                  CupertinoIcons.map,
                  isLight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPeriodStat(
                  earnings,
                  AppLocalizations.of(context)?.earnings ?? 'Earnings',
                  CupertinoIcons.creditcard,
                  isLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodStat(
    String value,
    String label,
    IconData icon,
    bool isLight,
  ) {
    return Column(
      children: [
        Icon(icon, color: isLight ? Colors.black : Colors.white, size: 20),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        Text(
          value,
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // Fuel & Emissions Section - Shows fuel usage, costs, CO2 and savings
  Widget _buildFuelEmissionsSection(bool isLight, AppSettings appSettings) {
    // Get total distance from stats (in km) - safely parse
    final distanceRaw = _statsData?['totalDistance'];
    double totalDistanceKm = 0.0;
    if (distanceRaw is num) {
      totalDistanceKm = distanceRaw.toDouble();
    } else if (distanceRaw != null) {
      totalDistanceKm = double.tryParse(distanceRaw.toString()) ?? 0.0;
    }

    // Calculate weighted average fuel consumption across ALL vehicles
    // Normalized to L/100km for consistent calculations
    double avgFuelConsumption = 8.5; // Default 8.5 L/100km
    int vehicleCount = 0;

    if (_driverVehicles.isNotEmpty) {
      double totalConsumption = 0.0;

      for (var vehicle in _driverVehicles) {
        // Safely parse fuel consumption (can be String or num from database)
        final consumptionRaw = vehicle['average_fuel_consumption'];
        double? consumption;
        if (consumptionRaw is num) {
          consumption = consumptionRaw.toDouble();
        } else if (consumptionRaw != null) {
          consumption = double.tryParse(consumptionRaw.toString());
        }
        final unit = vehicle['fuel_consumption_unit']?.toString() ??
          (AppLocalizations.of(context)?.fuelUnitLPer100km ?? '');

        if (consumption != null && consumption > 0) {
          vehicleCount++;
          if (unit == 'MPG') {
            // Convert MPG to L/100km for averaging: L/100km = 235.215 / MPG
            totalConsumption += 235.215 / consumption;
          } else {
            totalConsumption += consumption;
          }
        }
      }

      if (vehicleCount > 0) {
        avgFuelConsumption = totalConsumption / vehicleCount;
      }
    }

    // Check user's preferred units from AppSettings
    final usesMiles = appSettings.effectiveDistanceUnit == 'Miles';
    final usesLbs = appSettings.effectiveWeightUnit == 'Pounds';

    // US Average fuel prices (December 2025)
    const double avgGasPricePerGallon = 3.10; // USD
    const double avgGasPricePerLiter = 0.82; // ~3.10/gal ÷ 3.785

    // CO2 emissions: ~2.31 kg CO2 per liter of gasoline
    const double co2PerLiter = 2.31; // kg CO2

    // Calculate fuel used using average consumption (in L/100km)
    // avgFuelConsumption is already normalized to L/100km
    double totalFuelUsedLiters = (avgFuelConsumption / 100) * totalDistanceKm;
    double totalFuelCost = totalFuelUsedLiters * avgGasPricePerLiter;
    double totalCO2EmissionsKg = totalFuelUsedLiters * co2PerLiter;

    // Format fuel based on user's distance preference (miles = gallons, km = liters)
    String fuelUsedText;
    if (usesMiles) {
      final gallons = totalFuelUsedLiters / 3.785;
      fuelUsedText = '${appSettings.formatNumber(gallons, decimals: 2)} gal';
      totalFuelCost = gallons * avgGasPricePerGallon; // Recalculate in gallons
    } else {
      fuelUsedText = '${appSettings.formatNumber(totalFuelUsedLiters, decimals: 2)} L';
    }

    // Format CO2 based on user's weight preference
    String co2EmissionsText;
    if (usesLbs) {
      final lbs = totalCO2EmissionsKg * 2.20462;
      co2EmissionsText = '${appSettings.formatNumber(lbs, decimals: 2)} lb';
    } else {
      co2EmissionsText = '${appSettings.formatNumber(totalCO2EmissionsKg, decimals: 2)} kg';
    }

    // Format consumption display based on user preference
    // avgFuelConsumption is in L/100km, convert if user prefers MPG
    String consumptionText;
    if (usesMiles) {
      // Convert L/100km to MPG: MPG = 235.215 / (L/100km)
      final mpg = avgFuelConsumption > 0 ? 235.215 / avgFuelConsumption : 0.0;
      consumptionText = '${appSettings.formatNumber(mpg, decimals: 1)} MPG';
    } else {
      consumptionText = '${appSettings.formatNumber(avgFuelConsumption, decimals: 1)} L/100km';
    }

    // Calculate CO2 savings from filled empty runs
    final totalDeliveries = _statsData?['totalDeliveries'] ?? 0;
    // Estimate: ~30% of deliveries filled what would have been empty runs
    final filledEmptyRuns = (totalDeliveries * 0.30).round();
    // Average distance per delivery
    final avgDistancePerDelivery = totalDeliveries > 0
        ? totalDistanceKm / totalDeliveries
        : 0.0;
    // Saved distance = filled empty runs * avg distance
    final savedDistanceKm = filledEmptyRuns * avgDistancePerDelivery;

    // Calculate saved fuel and CO2 using average consumption (L/100km)
    double savedFuelLiters = (avgFuelConsumption / 100) * savedDistanceKm;
    double savedCO2Kg = savedFuelLiters * co2PerLiter;

    // Format saved values based on user preferences
    String savedFuelText;
    if (usesMiles) {
      final gallons = savedFuelLiters / 3.785;
      savedFuelText = '${appSettings.formatNumber(gallons, decimals: 2)} gal';
    } else {
      savedFuelText = '${appSettings.formatNumber(savedFuelLiters, decimals: 2)} L';
    }

    String savedCO2Text;
    double savedCO2ForDisplay;
    if (usesLbs) {
      savedCO2ForDisplay = savedCO2Kg * 2.20462;
      savedCO2Text = '${appSettings.formatNumber(savedCO2ForDisplay, decimals: 2)} lb';
    } else {
      savedCO2ForDisplay = savedCO2Kg;
      savedCO2Text = '${appSettings.formatNumber(savedCO2Kg, decimals: 2)} kg';
    }

    // Format saved distance using AppSettings
    final savedDistanceText = appSettings.formatDistance(savedDistanceKm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Text(
          AppLocalizations.of(context)?.fuelEmissions ?? 'Fuel & Emissions',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        // Main Stats Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.03),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Column(
            children: [
              // Fuel Usage Row
              Row(
                children: [
                  Expanded(
                    child: _buildFuelStatItem(
                      icon: CupertinoIcons.speedometer,
                      iconColor: const Color(0xFFF59E0B),
                      title:
                          AppLocalizations.of(context)?.fuelUsed ?? 'Fuel Used',
                      value: fuelUsedText,
                      isLight: isLight,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.1,
                    ),
                  ),
                  Expanded(
                    child: _buildFuelStatItem(
                      icon: CupertinoIcons.money_dollar_circle,
                      iconColor: isLight ? Colors.black : Colors.white,
                      title:
                          AppLocalizations.of(context)?.fuelCost ?? 'Fuel Cost',
                      value: appSettings.formatCurrency(totalFuelCost),
                      isLight: isLight,
                    ),
                  ),
                ],
              ),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
              TradeRepublicDivider(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.1),
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // CO2 Emissions Row
              Row(
                children: [
                  Expanded(
                    child: _buildFuelStatItem(
                      icon: CupertinoIcons.cloud,
                      iconColor: isLight ? Colors.black : Colors.white,
                      title:
                          AppLocalizations.of(context)?.co2Emissions ??
                          'CO₂ Emissions',
                      value: co2EmissionsText,
                      isLight: isLight,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.1,
                    ),
                  ),
                  Expanded(
                    child: _buildFuelStatItem(
                      icon: CupertinoIcons.speedometer,
                      iconColor: const Color(0xFF8B5CF6),
                      title: vehicleCount > 1
                          ? (AppLocalizations.of(context)?.fleetAvg ??
                                'Fleet Avg.')
                          : (AppLocalizations.of(context)?.avgConsumption ??
                                'Avg. Consumption'),
                      value: consumptionText,
                      isLight: isLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

        // CO2 Savings Card - Modern Minimal
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.03),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Column(
            children: [
              // Hero: CO2 Saved - centered big number
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        CupertinoIcons.leaf_arrow_circlepath,
                        color: Color(0xFF10B981),
                        size: 24,
                      ),
                    ),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    Text(
                      AppLocalizations.of(context)?.co2Saved ?? 'CO₂ Saved',
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w500,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      savedCO2Text,
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🌳', style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(),),
                        const SizedBox(width: 4),
                        Text(
                          '≈ ${appSettings.formatNumber(savedCO2Kg / 21, decimals: 1)} ${AppLocalizations.of(context)?.treesYear ?? 'trees/year'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Savings breakdown - 3 stats in a row
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildFuelStatItem(
                        icon: CupertinoIcons.cube_box,
                        iconColor: const Color(0xFF10B981),
                        title: AppLocalizations.of(context)?.filledEmptyRuns ??
                            'Filled Runs',
                        value: '$filledEmptyRuns',
                        isLight: isLight,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 60,
                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.1),
                    ),
                    Expanded(
                      child: _buildFuelStatItem(
                        icon: CupertinoIcons.map,
                        iconColor: const Color(0xFF10B981),
                        title: AppLocalizations.of(context)?.distanceSaved ??
                            'Dist. Saved',
                        value: savedDistanceText,
                        isLight: isLight,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 60,
                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.1),
                    ),
                    Expanded(
                      child: _buildFuelStatItem(
                        icon: CupertinoIcons.speedometer,
                        iconColor: const Color(0xFF10B981),
                        title: AppLocalizations.of(context)?.fuelSaved ??
                            'Fuel Saved',
                        value: savedFuelText,
                        isLight: isLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Info text
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.info_circle,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.25),
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.fillingEmptyTripsHelpsReduce ??
                      'By filling empty return trips, you help reduce unnecessary emissions.',
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper widget for fuel stat items
  Widget _buildFuelStatItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required bool isLight,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // Helper widget for savings breakdown rows
  Widget _buildSavingsRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: DesktopOptimizedWidgets.getFontSize(),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
