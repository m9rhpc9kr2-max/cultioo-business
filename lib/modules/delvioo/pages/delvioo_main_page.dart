import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../../../shared/services/app_settings.dart';
import '../../../config/api_config.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import 'delvioo_home_page.dart';
import 'delvioo_maps_page.dart';
import 'delvioo_orders_page.dart';
import 'delvioo_messages_page.dart';
import 'delvioo_account_page.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/page_indicator.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/services/driver_location_service.dart';
import '../../../utils/wagon_catalog.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';


// Global ValueNotifier to control dock visibility from maps page
final ValueNotifier<bool> hideDockNotifier = ValueNotifier<bool>(false);

// Global ValueNotifier for bottom sheet state - when any bottom sheet is open, hide dock
final ValueNotifier<bool> bottomSheetOpenNotifier = ValueNotifier<bool>(false);

// Global flag to prevent parent modal from resetting the notifier when opening sub-modal
bool isOpeningVehicleSubModal = false;

// Global ValueNotifier to pass active order from maps page for swipe interface
final ValueNotifier<Map<String, dynamic>?> activeOrderNotifier =
    ValueNotifier<Map<String, dynamic>?>(null);

// Global ValueNotifier to trigger route clearing in maps page
final ValueNotifier<bool> clearRouteNotifier = ValueNotifier<bool>(false);

// Maps bottom container horizontal swipe navigation:
// -1 = previous page, 1 = next page
final ValueNotifier<int> mapsBottomSwipeDirectionNotifier =
    ValueNotifier<int>(0);

// Global ValueNotifier to track navigation modal state - hide CNTabBar when navigation is open
final ValueNotifier<bool> navigationModalOpenNotifier = ValueNotifier<bool>(
  false,
);

// Global ValueNotifier to refresh user profile data across all Delvioo pages
final ValueNotifier<int> refreshUserDataNotifier = ValueNotifier<int>(0);

class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String symbol;
  final String label;

  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.symbol,
    required this.label,
  });
}

class DelviooMainPage extends StatefulWidget {
  const DelviooMainPage({super.key});

  @override
  State<DelviooMainPage> createState() => _DelviooMainPageState();
}

class _DelviooMainPageState extends State<DelviooMainPage> {
  int _currentIndex = 0;
  late PageController _pageController;
  Map<String, dynamic>? _selectedVehicle; // Selected vehicle for current order
  Map<String, dynamic>? userData; // User profile data including image

  // AI Order Suggestion background polling
  Timer? _aiSuggestionTimer;
  final Set<int> _shownAiOrderIds = {}; // Track already-shown orders
  DateTime? _lastAiCheck;
  bool _isCheckingAiOrders = false;
  bool _isAiSheetVisible = false;

  // Sidebar resize state
  static const double _sidebarMinWidth = 72;
  static const double _sidebarMaxWidth = 360;
  static const double _sidebarDefaultWidth = 260;
  double _sidebarWidth = _sidebarDefaultWidth;
  bool _sidebarCollapsed = false;
  double _sidebarWidthBeforeCollapse = _sidebarDefaultWidth;

  final List<Widget> _pages = [
    const DelviooHomePage(),
    const DelviooMapsPage(),
    const DelviooOrdersPage(),
    const DelviooMessagesPage(),
    const DelviooAccountPage(),
  ];

  List<NavItem> get _navItems => [
    NavItem(
      icon: CupertinoIcons.house,
      activeIcon: CupertinoIcons.house_fill,
      symbol: 'house',
      label: AppLocalizations.of(context)?.home ?? AppLocalizations.of(context)!.tr('Home'),
    ),
    NavItem(
      icon: CupertinoIcons.map,
      activeIcon: CupertinoIcons.map_fill,
      symbol: 'map',
      label: AppLocalizations.of(context)?.maps ?? AppLocalizations.of(context)!.tr('Maps'),
    ),
    NavItem(
      icon: CupertinoIcons.cube_box,
      activeIcon: CupertinoIcons.cube_box_fill,
      symbol: 'shippingbox',
      label: AppLocalizations.of(context)?.orders ?? AppLocalizations.of(context)!.tr('Orders'),
    ),
    NavItem(
      icon: CupertinoIcons.chat_bubble,
      activeIcon: CupertinoIcons.chat_bubble_fill,
      symbol: 'message',
      label: AppLocalizations.of(context)?.messages ?? AppLocalizations.of(context)!.tr('Messages'),
    ),
    NavItem(
      icon: CupertinoIcons.person,
      activeIcon: CupertinoIcons.person_fill,
      symbol: 'person',
      label: AppLocalizations.of(context)?.account ?? AppLocalizations.of(context)!.tr('Account'),
    ),
  ];

  @override
  void initState() {
    super.initState();
    print('🚀 DelviooMainPage initState called');
    _pageController = PageController();

    // Keep driver GPS sync active across all Delvioo tabs (not only Maps tab)
    startDriverLocationService();

    // Listen to dock visibility changes from maps page
    hideDockNotifier.addListener(_onDockVisibilityChanged);

    // Listen to bottom sheet state changes
    bottomSheetOpenNotifier.addListener(_onDockVisibilityChanged);

    // Listen to active order changes to show swipe bottom sheet
    activeOrderNotifier.addListener(_onActiveOrderChanged);

    // Listen to refresh user data notifier (triggered when profile image changes)
    refreshUserDataNotifier.addListener(_onRefreshUserData);
    mapsBottomSwipeDirectionNotifier.addListener(_onMapsBottomSwipeNavigation);

    // Save that user was last in Delvioo
    _saveLastApp();

    // Load user profile data
    print('🔄 About to call _loadUserData()');
    _loadUserData();
    print('✅ _loadUserData() called');

    // Start AI order suggestion background polling (every 2 minutes)
    _aiSuggestionTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _checkAiOrderSuggestions(),
    );
    // Run one initial check after 15 seconds
    Future.delayed(
      const Duration(seconds: 15),
      _checkAiOrderSuggestions,
    );
  }

  void _onActiveOrderChanged() {
    if (mounted && _currentIndex == 1) {
      final activeOrder = activeOrderNotifier.value;
      print('🎯 Active order changed: $activeOrder');
      if (activeOrder != null) {
        print(
          '📱 Bottom sheet will show automatically via ValueListenableBuilder',
        );
        // Set bottom sheet open state to hide dock
        bottomSheetOpenNotifier.value = true;
      } else {
        // Clear bottom sheet open state to show dock again
        bottomSheetOpenNotifier.value = false;
      }
    }
  }

  void _onDockVisibilityChanged() {
    if (mounted) {
      print(
        '🎯 MAIN PAGE: Dock visibility changed - bottomSheetOpen: ${bottomSheetOpenNotifier.value}, hideDock: ${hideDockNotifier.value}',
      );
      setState(() {}); // Rebuild when dock visibility changes
    }
  }

  void _onRefreshUserData() {
    if (mounted) {
      print('🔄 MAIN PAGE: User data refresh triggered - reloading profile...');
      _loadUserData();
    }
  }

  void _onMapsBottomSwipeNavigation() {
    final direction = mapsBottomSwipeDirectionNotifier.value;
    if (!mounted || direction == 0 || _currentIndex != 1) return;

    // Reset the notifier immediately so repeated swipes can retrigger.
    mapsBottomSwipeDirectionNotifier.value = 0;

    if (direction < 0 && _currentIndex > 0) {
      _navigateToPage(_currentIndex - 1, animate: true);
    } else if (direction > 0 && _currentIndex < _pages.length - 1) {
      _navigateToPage(_currentIndex + 1, animate: true);
    }
  }

  void _saveLastApp() async {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    await appSettings.setLastApp('delvioo');
  }

  Future<void> _loadUserData() async {
    print('🎬 _loadUserData() START');
    try {
      print('🔍 Getting appSettings from context...');
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      print('✅ Got appSettings');

      // Get username and email from SharedPreferences (stored during login)
      final prefs = await SharedPreferences.getInstance();
      final username =
          prefs.getString('username') ??
          prefs.getString('delvioo_username') ??
          appSettings.userName;
      final email = prefs.getString('email') ?? prefs.getString('userEmail');

      print('🔍 Username from preferences: $username');
      print('🔍 Email from preferences: $email');

      // Try to load by username first
      if (username != null && username.isNotEmpty) {
        print('📡 Loading user data for username: $username');
        final url = '${ApiConfig.baseUrl}/api/delvioo/profile/$username';
        print('🌐 Full URL: $url');

        final response = await http.get(Uri.parse(url));
        print('📥 Response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true && mounted) {
            print('✅ User data loaded by username: ${data['user']}');
            print('🖼️ Profile image: ${data['user']?['profile_image']}');
            setState(() {
              userData = data['user'];
            });
            print('✅ State updated with userData');
            return;
          }
        }
      }

      // Fallback: Try to find user by email from all-users endpoint
      if (email != null && email.isNotEmpty) {
        print('📡 Trying to find user by email: $email');
        final allUsersUrl = '${ApiConfig.baseUrl}/api/driver/all-users';
        final response = await http.get(Uri.parse(allUsersUrl));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            final users = data['data'] as List? ?? data['users'] as List? ?? [];
            final user = users.firstWhere(
              (u) =>
                  u['email']?.toString().toLowerCase() == email.toLowerCase(),
              orElse: () => null,
            );

            if (user != null && mounted) {
              print('✅ User found by email: ${user['username']}');
              print('🖼️ Profile image: ${user['profile_image']}');
              // Save correct username for future use
              await prefs.setString('username', user['username'] ?? AppLocalizations.of(context)!.tr(''));
              await prefs.setString('delvioo_username', user['username'] ?? AppLocalizations.of(context)!.tr(''));
              setState(() {
                userData = user;
              });
              print('✅ State updated with userData from email search');
              return;
            }
          }
        }
      }

      print('❌ Could not load user data');
    } catch (e, stackTrace) {
      print('❌ Error loading user data: $e');
      print('❌ Stack trace: $stackTrace');
    }
    print('🏁 _loadUserData() END');
  }

  String _getImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      print('⚠️ Image URL is null or empty');
      return '';
    }

    print('🔗 Original image URL: $imageUrl');

    // If already a full URL (GCS or other), return as is
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      print('✅ Full URL detected: $imageUrl');
      return imageUrl;
    }

    // If it's a relative path (like /uploads/...), prepend base URL
    String fullUrl;
    if (imageUrl.startsWith('/')) {
      fullUrl = '${ApiConfig.baseUrl}$imageUrl';
    } else {
      fullUrl = '${ApiConfig.baseUrl}/$imageUrl';
    }

    print('✅ Constructed full URL: $fullUrl');
    return fullUrl;
  }

  @override
  void dispose() {
    // Stop background sync when leaving Delvioo module
    stopDriverLocationService();
    hideDockNotifier.removeListener(_onDockVisibilityChanged);
    bottomSheetOpenNotifier.removeListener(_onDockVisibilityChanged);
    activeOrderNotifier.removeListener(_onActiveOrderChanged);
    refreshUserDataNotifier.removeListener(_onRefreshUserData);
    mapsBottomSwipeDirectionNotifier.removeListener(
      _onMapsBottomSwipeNavigation,
    );
    _aiSuggestionTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);

    // Use native iOS TabBar on iOS, Sidebar on desktop (macOS/Windows/Linux), custom dock on other platforms
    if (Platform.isIOS) {
      return _buildIOSTabBarInterface(isLight);
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return _buildMacOSSidebarInterface(isLight);
    } else {
      return _buildCustomDockInterface(isLight);
    }
  }

  Widget _buildIOSTabBarInterface(bool isLight) {
    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Stack(
        children: [
          // PageView for swiping between pages
          PageView(
            controller: _pageController,
            // Disable swipe on maps page so Apple Maps can receive pan/zoom gestures
            physics: _currentIndex == 1
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            children: _pages,
          ),

          // Zeit/Distanz-Container oben links - only show on maps page when route active
          if (_currentIndex == 1) // Maps page index
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: activeOrderNotifier,
              builder: (context, activeOrder, child) {
                final hasActiveOrder = activeOrder != null;

                if (!hasActiveOrder || activeOrder['routeDistance'] == null) {
                  return const SizedBox.shrink();
                }

                return Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 20,
                  child: _buildRouteTimeContainer(isLight, activeOrder),
                );
              },
            ),

          // Close button top right - only show on maps page when route active
          if (_currentIndex == 1)
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: activeOrderNotifier,
              builder: (context, activeOrder, child) {
                final hasActiveOrder = activeOrder != null;

                if (!hasActiveOrder) {
                  return const SizedBox.shrink();
                }

                return Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  right: 20,
                  child: TradeRepublicButton.icon(
                    icon: Icon(CupertinoIcons.xmark, size: 22),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      clearRouteNotifier.value = !clearRouteNotifier.value;
                      activeOrderNotifier.value = null;
                    },
                    backgroundColor: isLight
                        ? Colors.white.withOpacity(0.95)
                        : Colors.black.withOpacity(0.95),
                    foregroundColor: isLight ? Colors.black : Colors.white,
                    size: 44,
                  ),
                );
              },
            ),

          // Swipe Accept Bottom Sheet - shows when activeOrderNotifier has a value
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: activeOrderNotifier,
            builder: (context, activeOrder, child) {
              if (activeOrder == null) return const SizedBox.shrink();

              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SwipeAcceptBottomSheet(
                  isLight: isLight,
                  order: activeOrder,
                  selectedVehicle: _selectedVehicle,
                  onVehicleSelect: () {
                    _showVehicleSelectionSheet(
                      context,
                      isLight,
                      activeOrder['shipping_type'],
                    );
                  },
                  onVehicleChanged: (vehicle) {
                    setState(() {
                      _selectedVehicle = vehicle;
                    });
                  },
                  onClose: () {
                    clearRouteNotifier.value = !clearRouteNotifier.value;
                    activeOrderNotifier.value = null;
                  },
                ),
              );
            },
          ),

          // PageIndicator at bottom - hide when bottom sheet, navigation modal or dock hidden
          ValueListenableBuilder<bool>(
            valueListenable: bottomSheetOpenNotifier,
            builder: (context, isBottomSheetOpen, child) {
              return ValueListenableBuilder<bool>(
                valueListenable: navigationModalOpenNotifier,
                builder: (context, isNavigationModalOpen, child) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: hideDockNotifier,
                    builder: (context, shouldHideDock, child) {
                      if (isBottomSheetOpen ||
                          isNavigationModalOpen ||
                          shouldHideDock) {
                        return const SizedBox.shrink();
                      }

                      final bp = MediaQuery.of(context).padding.bottom;
                      return Positioned(
                        left: 0,
                        right: 0,
                        bottom: bp > 4 ? bp - 4 : 0,
                        child: Center(
                          child: PageIndicator(
                            currentPage: _currentIndex,
                            pageCount: _navItems.length,
                            pageController: _pageController,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),

          // Edge swipe zones – allow page navigation on maps page where PageView
          // swiping is disabled so Apple Maps can receive pan/zoom gestures.
          ..._buildEdgeSwipeZones(),
        ],
      ),
    );
  }

  Widget _buildCustomDockInterface(bool isLight) {
    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Stack(
        children: [
          // PageView for swiping between pages
          PageView(
            controller: _pageController,
            // Disable swipe on maps page so Apple Maps can receive pan/zoom gestures
            physics: _currentIndex == 1
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            children: _pages,
          ),

          // Zeit/Distanz-Container oben links - only show on maps page when route active
          if (_currentIndex == 1)
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: activeOrderNotifier,
              builder: (context, activeOrder, child) {
                final hasActiveOrder = activeOrder != null;

                if (!hasActiveOrder || activeOrder['routeDistance'] == null) {
                  return const SizedBox.shrink();
                }

                return Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 20,
                  child: _buildRouteTimeContainer(isLight, activeOrder),
                );
              },
            ),

          // Close button top right - only show on maps page when route active
          if (_currentIndex == 1)
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: activeOrderNotifier,
              builder: (context, activeOrder, child) {
                final hasActiveOrder = activeOrder != null;

                if (!hasActiveOrder) {
                  return const SizedBox.shrink();
                }

                return Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  right: 20,
                  child: TradeRepublicButton.icon(
                    icon: Icon(CupertinoIcons.xmark, size: 22),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      clearRouteNotifier.value = !clearRouteNotifier.value;
                      activeOrderNotifier.value = null;
                    },
                    backgroundColor: isLight
                        ? Colors.white.withOpacity(0.95)
                        : Colors.black.withOpacity(0.95),
                    foregroundColor: isLight ? Colors.black : Colors.white,
                    size: 44,
                  ),
                );
              },
            ),

          // Swipe Accept Bottom Sheet - shows when activeOrderNotifier has a value
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: activeOrderNotifier,
            builder: (context, activeOrder, child) {
              if (activeOrder == null) return const SizedBox.shrink();

              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SwipeAcceptBottomSheet(
                  isLight: isLight,
                  order: activeOrder,
                  selectedVehicle: _selectedVehicle,
                  onVehicleSelect: () {
                    _showVehicleSelectionSheet(
                      context,
                      isLight,
                      activeOrder['shipping_type'],
                    );
                  },
                  onVehicleChanged: (vehicle) {
                    setState(() {
                      _selectedVehicle = vehicle;
                    });
                  },
                  onClose: () {
                    clearRouteNotifier.value = !clearRouteNotifier.value;
                    activeOrderNotifier.value = null;
                  },
                ),
              );
            },
          ),

          // PageIndicator on Android/custom dock - hide when bottom sheet,
          // navigation modal, or dock is hidden
          ValueListenableBuilder<bool>(
            valueListenable: bottomSheetOpenNotifier,
            builder: (context, isBottomSheetOpen, child) {
              return ValueListenableBuilder<bool>(
                valueListenable: navigationModalOpenNotifier,
                builder: (context, isNavigationModalOpen, child) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: hideDockNotifier,
                    builder: (context, shouldHideDock, child) {
                      if (isBottomSheetOpen ||
                          isNavigationModalOpen ||
                          shouldHideDock) {
                        return const SizedBox.shrink();
                      }

                      final bp = MediaQuery.of(context).padding.bottom;
                      return Positioned(
                        left: 0,
                        right: 0,
                        bottom: bp > 4 ? bp - 4 : 0,
                        child: Center(
                          child: PageIndicator(
                            currentPage: _currentIndex,
                            pageCount: _navItems.length,
                            pageController: _pageController,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),

          // Edge swipe zones – allow page navigation on maps page where PageView
          // swiping is disabled so Apple Maps can receive pan/zoom gestures.
          ..._buildEdgeSwipeZones(),
        ],
      ),
      extendBody: false,
    );
  }

  Widget _buildCustomDock(bool isLight) {
    return Container(
      height: 60,
      decoration: BoxDecoration(color: isLight ? Colors.white : Colors.black),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(_navItems.length, (index) {
          return _buildDockItem(index, isLight);
        }),
      ),
    );
  }

  Widget _buildDockItem(int index, bool isLight) {
    final navItem = _navItems[index];
    final isSelected = _currentIndex == index;

    return Expanded(
      child: TradeRepublicTap(
        onTap: () {
          HapticFeedback.lightImpact();
          _navigateToPage(index);
        },
        child: Container(
          height: 60,
          color: Colors.transparent,
          child: Center(
            child: Icon(
              isSelected ? navItem.activeIcon : navItem.icon,
              size: 22,
              color: isSelected
                  ? (isLight ? Colors.black : Colors.white)
                  : (isLight ? Colors.white : Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  /// Returns two invisible 30 px-wide Positioned strips on the left and right
  /// screen edges. They are only present on the maps page (index 1) where the
  /// PageView physics are set to NeverScrollable so Apple Maps can receive
  /// pan/zoom touches. A clear horizontal swipe on an edge still navigates
  /// between pages via [_navigateToPage].
  List<Widget> _buildEdgeSwipeZones() {
    if (_currentIndex != 1) return const [];
    return [
      // Left edge → go to previous page
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: 30,
        child: TradeRepublicTap(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 200 && _currentIndex > 0) {
              _navigateToPage(_currentIndex - 1, animate: true);
            }
          },
        ),
      ),
      // Right edge → go to next page
      Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: 30,
        child: TradeRepublicTap(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -200 &&
                _currentIndex < _pages.length - 1) {
              _navigateToPage(_currentIndex + 1, animate: true);
            }
          },
        ),
      ),
    ];
  }

  void _navigateToPage(int index, {bool animate = false}) {
    if (index != _currentIndex) {
      // Clear route and active order when leaving maps page
      if (_currentIndex == 1 && activeOrderNotifier.value != null) {
        clearRouteNotifier.value = !clearRouteNotifier.value;
        activeOrderNotifier.value = null;
      }

      setState(() {
        _currentIndex = index;
      });

      if (animate) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } else {
        // Keep immediate switch for tap-based nav where CNTabBar animates itself.
        _pageController.jumpToPage(index);
      }

      // Haptic Feedback
      _generateHapticFeedback();
    }
  }

  void _generateHapticFeedback() {
    // Light vibration for navigation
    if (Platform.isIOS) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  // Build route time/distance container at top
  Widget _buildRouteTimeContainer(bool isLight, Map<String, dynamic> order) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final distance = (order['routeDistance'] as num?)?.toDouble() ?? 0.0;
    final duration = (order['routeDuration'] as num?)?.toDouble() ?? 0.0;

    // Format distance using AppSettings (km or miles)
    final formattedDistance = appSettings.formatDistance(distance);

    // Format time as hours and minutes
    String formattedTime;
    if (duration >= 60) {
      final hours = (duration / 60).floor();
      final minutes = (duration % 60).round();
      if (minutes > 0) {
        formattedTime = '${hours}h ${minutes}m';
      } else {
        formattedTime = '${hours}h';
      }
    } else {
      formattedTime = '${duration.round()}m';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Distance with icon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.location,
                  color: Color(0xFF007AFF),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  formattedDistance,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Duration with icon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withOpacity(0.1),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.clock,
                  color: Color(0xFF34C759),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  formattedTime,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Show vehicle selection bottom sheet
  void _showVehicleSelectionSheet(
    BuildContext context,
    bool isLight,
    String? shippingType,
  ) async {
    final selectedVehicle = await TradeRepublicBottomSheet.show<Map<String, dynamic>>(
      context: context,
      child: _VehicleSelectionSheet(
        isLight: isLight,
        currentSelectedVehicle: _selectedVehicle,
        requiredShippingType: shippingType,
      ),
    );

    if (selectedVehicle != null) {
      setState(() {
        _selectedVehicle = selectedVehicle;
      });
    }
  }

  // macOS Sidebar Interface - Trade Republic Minimalist Design (same as Business)
  Widget _buildMacOSSidebarInterface(bool isLight) {
    final appSettings = Provider.of<AppSettings>(context);
    final showLabels = _sidebarWidth > 140;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Row(
        children: [
          // Left Sidebar - Trade Republic Style (Flat, No Shadow)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: _sidebarWidth,
            decoration: BoxDecoration(
              color: isLight ? Colors.white : Colors.black,
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo Section - bigger logo
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      showLabels ? 20 : 12, 24, showLabels ? 20 : 12, 16,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      alignment: showLabels ? Alignment.centerLeft : Alignment.center,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: showLabels
                            ? Image.asset(
                                isLight
                                    ? 'assets/images/cultioo_logo_dark.png'
                                    : 'assets/images/cultioo_logo_light.png',
                                key: const ValueKey('full_logo'),
                                height: 110,
                                fit: BoxFit.contain,
                              )
                            : Image.asset(
                                'logo/cultioo_logo.png',
                                key: const ValueKey('leaf_logo'),
                                height: 48,
                                fit: BoxFit.contain,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                      ),
                    ),
                  ),

                  // Navigation Items - Trade Republic Style
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(horizontal: showLabels ? 12 : 8),
                      children: List.generate(
                        _navItems.length,
                        (index) => _buildSidebarItem(index, isLight),
                      ),
                    ),
                  ),

                  // Profile Section - Trade Republic minimal bottom (only when expanded)
                  if (showLabels)
                    Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isLight
                          ? Colors.black.withOpacity(0.04)
                          : Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Row(
                      children: [
                        // Profile Image - Trade Republic square style
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isLight ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Builder(
                            builder: (context) {
                              final fallbackLetter = (appSettings.userName?.isNotEmpty == true)
                                  ? appSettings.userName!.substring(0, 1).toUpperCase()
                                  : 'D';
                              final fallbackWidget = Center(
                                child: Text(
                                  fallbackLetter,
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? Colors.white : Colors.black,
                                  ),
                                ),
                              );
                              final rawUrl = userData?['profile_image']?.toString() ?? AppLocalizations.of(context)!.tr('');
                              if (rawUrl.isEmpty || rawUrl.startsWith('<svg')) {
                                return fallbackWidget;
                              }
                              // base64 data: URL
                              if (rawUrl.startsWith('data:image')) {
                                try {
                                  final bytes = base64Decode(rawUrl.split(',').last);
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                    child: Image.memory(
                                      bytes,
                                      width: 40, height: 40, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => fallbackWidget,
                                    ),
                                  );
                                } catch (_) {
                                  return fallbackWidget;
                                }
                              }
                              // Regular http/https or server-relative URL
                              final fullUrl = _getImageUrl(rawUrl);
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                child: Image.network(
                                  fullUrl,
                                  width: 40, height: 40, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => fallbackWidget,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Name - Trade Republic typography
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                userData?['username'] != null
                                    ? '@${userData!['username']}'
                                    : (appSettings.userName ??
                                    AppLocalizations.of(context)?.driverLabel ?? AppLocalizations.of(context)!.tr('Driver')),
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w600,
                                  color: isLight ? Colors.black : Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppLocalizations.of(context)?.driverLabel ?? AppLocalizations.of(context)!.tr('Driver'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: isLight
                                      ? Colors.black.withOpacity(0.5)
                                      : Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Chevron
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
                ],
              ),
            ),
          ),

          // Draggable Resize Handle
          _buildSidebarResizeHandle(isLight),

          // Main Content Area - Trade Republic clean
          Expanded(
            child: Container(
              color: isLight ? Colors.white : Colors.black,
              child: PageView(
                controller: _pageController,
                // Disable swipe on maps page so Apple Maps can receive pan/zoom gestures
                physics: _currentIndex == 1
                    ? const NeverScrollableScrollPhysics()
                    : const AlwaysScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                children: _pages,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index, bool isLight) {
    final navItem = _navItems[index];
    final isSelected = _currentIndex == index;
    final showLabels = _sidebarWidth > 140;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: TradeRepublicTap(
          onTap: () {
            HapticFeedback.lightImpact();
            _navigateToPage(index);
          },
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          hoverColor: isLight
              ? Colors.black.withOpacity(0.04)
              : Colors.white.withOpacity(0.04),
          splashColor: isLight
              ? Colors.black.withOpacity(0.08)
              : Colors.white.withOpacity(0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: showLabels
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                : const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isLight ? Colors.black : Colors.white)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              mainAxisAlignment: showLabels ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isSelected ? navItem.activeIcon : navItem.icon,
                    key: ValueKey(isSelected),
                    size: 20,
                    color: isSelected
                        ? (isLight ? Colors.white : Colors.black)
                        : (isLight
                              ? Colors.black.withOpacity(0.7)
                              : Colors.white.withOpacity(0.7)),
                  ),
                ),
                if (showLabels) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: showLabels ? 1.0 : 0.0,
                      child: Text(
                        navItem.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? (isLight ? Colors.white : Colors.black)
                              : (isLight ? Colors.black : Colors.white),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isResizeHandleHovered = false;

  // Resize handle between sidebar and content
  Widget _buildSidebarResizeHandle(bool isLight) {
    return TradeRepublicTap(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _sidebarWidth = (_sidebarWidth + details.delta.dx)
              .clamp(_sidebarMinWidth, _sidebarMaxWidth);
          _sidebarCollapsed = _sidebarWidth <= _sidebarMinWidth + 10;
        });
      },
      onHorizontalDragEnd: (details) {
        // Snap to collapsed if near minimum
        if (_sidebarWidth < 110) {
          setState(() {
            _sidebarWidth = _sidebarMinWidth;
            _sidebarCollapsed = true;
          });
        }
      },
      onTap: () {
        setState(() {
          if (_sidebarCollapsed) {
            _sidebarWidth = _sidebarWidthBeforeCollapse;
            _sidebarCollapsed = false;
          } else {
            _sidebarWidthBeforeCollapse = _sidebarWidth;
            _sidebarWidth = _sidebarMinWidth;
            _sidebarCollapsed = true;
          }
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _isResizeHandleHovered = true),
        onExit: (_) => setState(() => _isResizeHandleHovered = false),
        child: Container(
          width: _isResizeHandleHovered ? 8 : 6,
          color: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              width: _isResizeHandleHovered ? 3 : 1,
              decoration: BoxDecoration(
                color: _isResizeHandleHovered
                    ? (isLight ? Colors.black.withOpacity(0.25) : Colors.white.withOpacity(0.4))
                    : (isLight ? Colors.black.withOpacity(0.08) : Colors.white.withOpacity(0.08)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── AI Order Suggestion Background Polling ───────────────────────────────

  /// iOS: kCLErrorDomain code 1 = denied; avoid noisy logs for background checks.
  bool _isExpectedAiLocationFailure(Object e) {
    final s = e.toString();
    return s.contains('kCLErrorDomain') ||
        s.contains('Location service disabled') ||
        s.contains('User denied permissions');
  }

  /// Periodically called to check for nearby open orders matching the driver's
  /// vehicles. Shows a bottom sheet automatically when a good match is found.
  Future<void> _checkAiOrderSuggestions() async {
    if (!mounted) return;
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    // Feature guard: only run when enabled
    if (!appSettings.lastMileEnabled) return;

    // Don't double-run
    if (_isCheckingAiOrders) return;
    _isCheckingAiOrders = true;

    // Don't check more than once every 90 seconds
    if (_lastAiCheck != null &&
        DateTime.now().difference(_lastAiCheck!).inSeconds < 90) {
      _isCheckingAiOrders = false;
      return;
    }

    // Skip when navigation is running or another sheet is open
    if (navigationModalOpenNotifier.value || _isAiSheetVisible) {
      _isCheckingAiOrders = false;
      return;
    }

    _lastAiCheck = DateTime.now();

    try {
      // ── 1. Get current location ──────────────────────────────────────────
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _isCheckingAiOrders = false;
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        _isCheckingAiOrders = false;
        return;
      }

      late final Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 8));
      } catch (e) {
        if (_isExpectedAiLocationFailure(e)) {
          return;
        }
        rethrow;
      }

      // ── 2. Get driver ID ─────────────────────────────────────────────────
      final prefs = await SharedPreferences.getInstance();
      final userIdStr = prefs.getString('user_id');
      final driverId = userIdStr != null ? int.tryParse(userIdStr) ?? 0 : 0;
      if (driverId == 0) {
        _isCheckingAiOrders = false;
        return;
      }

      // ── 3. Fetch driver's vehicles ────────────────────────────────────────
      List<Map<String, dynamic>> driverVehicles = [];
      try {
        final vehiclesResponse = await http
            .get(
              Uri.parse(
                '${ApiConfig.baseUrl}/api/delvioo/vehicles/$driverId',
              ),
            )
            .timeout(const Duration(seconds: 6));
        if (vehiclesResponse.statusCode == 200) {
          final vData = json.decode(vehiclesResponse.body);
          final rawVehicles = (vData['vehicles'] ?? vData['data'] ?? []) as List;
          driverVehicles = rawVehicles.cast<Map<String, dynamic>>();
        }
      } catch (_) {}

      // ── 4. Call last-mile-opportunities API ──────────────────────────────
      final radiusMeters =
          (appSettings.aiSuggestionRadius * 1000).round();
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/api/delvioo/last-mile-opportunities'
              '?driver_id=$driverId'
              '&lat=${position.latitude}'
              '&lng=${position.longitude}'
              '&radius=$radiusMeters',
            ),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        _isCheckingAiOrders = false;
        return;
      }

      final data = json.decode(response.body);
      final opportunities = (data['opportunities'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      if (opportunities.isEmpty) {
        _isCheckingAiOrders = false;
        return;
      }

      // ── 5. Filter already-shown orders ───────────────────────────────────
      final fresh = opportunities.where((o) {
        final id = o['order_id'];
        final orderId = id is int ? id : int.tryParse(id.toString()) ?? -1;
        return !_shownAiOrderIds.contains(orderId);
      }).toList();

      if (fresh.isEmpty) {
        _isCheckingAiOrders = false;
        return;
      }

      // ── 6. Score opportunities ────────────────────────────────────────────
      Map<String, dynamic>? bestMatch;
      Map<String, dynamic>? matchedVehicle;
      double bestScore = -1;

      for (final opp in fresh) {
        try {
          final pickupLat = (opp['pickup_lat'] ?? 0.0) as num;
          final pickupLng = (opp['pickup_lng'] ?? 0.0) as num;
          final deliveryLat = (opp['delivery_lat'] ?? 0.0) as num;
          final deliveryLng = (opp['delivery_lng'] ?? 0.0) as num;

          if (pickupLat == 0 || deliveryLat == 0) continue;

          final distToPickup = _calcDistanceMeters(
            position.latitude, position.longitude,
            pickupLat.toDouble(), pickupLng.toDouble(),
          );
          final pickupToDelivery = _calcDistanceMeters(
            pickupLat.toDouble(), pickupLng.toDouble(),
            deliveryLat.toDouble(), deliveryLng.toDouble(),
          );

          double score = 0;
          if (distToPickup < 2000) {
            score += 100;
          } else if (distToPickup < 5000) score += 50;
          if (pickupToDelivery > 5000) {
            score += 60;
          } else if (pickupToDelivery > 2000) score += 30;
          final orderValue =
              (opp['total_price'] ?? 0) is int
                  ? (opp['total_price'] as int).toDouble()
                  : (opp['total_price'] ?? 0.0) as double;
          if (orderValue > 100) {
            score += 40;
          } else if (orderValue > 50) score += 20;

          // Find a matching vehicle for this opportunity
          Map<String, dynamic>? vehicle;
          if (driverVehicles.isNotEmpty) {
            vehicle = driverVehicles.first; // Default: first vehicle
          }

          if (score > bestScore) {
            bestScore = score;
            bestMatch = {
              ...opp,
              'distanceToPickup': distToPickup,
              'pickupToDelivery': pickupToDelivery,
            };
            matchedVehicle = vehicle;
          }
        } catch (_) {}
      }

      if (bestMatch == null || bestScore < 0) {
        _isCheckingAiOrders = false;
        return;
      }

      // ── 7. Show the suggestion bottom sheet ──────────────────────────────
      if (mounted && !_isAiSheetVisible) {
        HapticFeedback.mediumImpact();
        _isAiSheetVisible = true;

        // Mark as shown
        final oid = bestMatch['order_id'];
        final orderId =
            oid is int ? oid : int.tryParse(oid.toString()) ?? -1;
        if (orderId != -1) {
          _shownAiOrderIds.add(orderId);
          // Clear cache after 30 min so the same order can resurface later
          Future.delayed(const Duration(minutes: 30), () {
            _shownAiOrderIds.remove(orderId);
          });
        }

        await _showAiOrderSuggestionSheet(bestMatch, matchedVehicle);
        _isAiSheetVisible = false;
      }
    } catch (e) {
      if (!_isExpectedAiLocationFailure(e)) {
        print('❌ AI order suggestion error: $e');
      }
    } finally {
      _isCheckingAiOrders = false;
    }
  }

  /// Haversine distance in meters between two lat/lng points.
  double _calcDistanceMeters(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Shows the automatic AI order suggestion as a TradeRepublicBottomSheet.
  Future<void> _showAiOrderSuggestionSheet(
    Map<String, dynamic> order,
    Map<String, dynamic>? vehicle,
  ) async {
    if (!mounted) return;
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final isLight = appSettings.isLightMode(context);

    final distanceToPickup =
        (order['distanceToPickup'] as num? ?? 0).toDouble();
    final pickupToDelivery =
        (order['pickupToDelivery'] as num? ?? 0).toDouble();
    final rawPrice = order['total_price'];
    final orderValue =
        rawPrice is int ? rawPrice.toDouble() : (rawPrice ?? 0.0) as double;
    final orderId = order['order_id'] ?? AppLocalizations.of(context)!.tr('');

    // ── Build address strings ──────────────────────────────────────────────
    final pickupStreet = order['pickup_street']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final pickupCity = order['pickup_city']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final pickupZip = order['pickup_zip']?.toString() ?? AppLocalizations.of(context)!.tr('');
    String pickupAddr = pickupStreet.isNotEmpty
        ? (pickupCity.isNotEmpty ? '$pickupStreet, $pickupCity' : pickupStreet)
        : (pickupCity.isNotEmpty ? '$pickupZip $pickupCity' : '');

    String deliveryAddr = '';
    try {
      final raw = order['deliveryAddress'];
      if (raw != null) {
        final a = raw is String ? json.decode(raw) : raw as Map;
        final street = a['street'] ?? a['address'] ?? AppLocalizations.of(context)!.tr('');
        final city = a['city'] ?? AppLocalizations.of(context)!.tr('');
        deliveryAddr = street.toString().isNotEmpty
            ? (city.toString().isNotEmpty
                ? '$street, $city'
                : street.toString())
            : city.toString();
      }
    } catch (_) {}

    // ── Vehicle info ───────────────────────────────────────────────────────
    final vehicleName = vehicle != null
        ? '${vehicle['make'] ?? AppLocalizations.of(context)!.tr('')} ${vehicle['model'] ?? AppLocalizations.of(context)!.tr('')}'.trim()
        : '';
    final vehicleType = vehicle?['vehicle_type']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final licensePlate = vehicle?['license_plate']?.toString() ?? AppLocalizations.of(context)!.tr('');

    int bidCents = 0;

    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (ctx, setS) {
          final bidAmount = bidCents / 100.0;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Order Suggestion',
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            'Order #$orderId · ${appSettings.formatCurrency(orderValue)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Text(
                        appSettings.formatCurrency(orderValue),
                        style: const TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF34C759),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // ── Route card ───────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isLight
                        ? Colors.grey.withOpacity(0.06)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                  ),
                  child: Column(
                    children: [
                      // Pickup row
                      Row(
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF34C759),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              Container(
                                width: 2,
                                height: 28,
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.12),
                              ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PICKUP',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF34C759),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                Text(
                                  pickupAddr.isNotEmpty
                                      ? pickupAddr
                                      : 'Pickup Address',
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w600,
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.07),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              appSettings
                                  .formatDistance(distanceToPickup / 1000),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Delivery row
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DELIVERY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFFF3B30),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                Text(
                                  deliveryAddr.isNotEmpty
                                      ? deliveryAddr
                                      : 'Delivery Address',
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w600,
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.07),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              appSettings
                                  .formatDistance(pickupToDelivery / 1000),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ── Distance chips ───────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _buildAiInfoChip(
                        icon: Icons.near_me_rounded,
                        label: appSettings
                            .formatDistance(distanceToPickup / 1000),
                        subtitle: AppLocalizations.of(context)?.toPickup ?? AppLocalizations.of(context)!.tr(''),
                        isLight: isLight,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildAiInfoChip(
                        icon: Icons.local_shipping_rounded,
                        label: appSettings
                            .formatDistance(pickupToDelivery / 1000),
                        subtitle:
                          AppLocalizations.of(context)?.tripDistance ?? AppLocalizations.of(context)!.tr(''),
                        isLight: isLight,
                      ),
                    ),
                    if (vehicleName.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildAiInfoChip(
                          icon: _getVehicleIcon(vehicleType),
                          label: vehicleName,
                          subtitle: licensePlate.isNotEmpty
                              ? licensePlate
                              : vehicleType,
                          isLight: isLight,
                          color: const Color(0xFF007AFF),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // ── Bid price input ──────────────────────────────────────────
                TradeRepublicTap(
                  onTap: () {
                    // Show numpad sheet
                    _showAiBidNumpad(
                      ctx,
                      isLight,
                      order,
                      vehicle,
                      pickupAddr,
                      deliveryAddr,
                      distanceToPickup,
                      pickupToDelivery,
                      orderValue,
                      orderId,
                    );
                  },
                  child: Container(
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: isLight
                          ? Colors.grey.withOpacity(0.06)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                      border: Border.all(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tap to enter your bid',
                          style: TextStyle(
                            fontSize: 15,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.45),
                          ),
                        ),
                        Icon(
                          CupertinoIcons.money_dollar_circle,
                          color: const Color(0xFF34C759),
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // ── Action buttons ───────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)?.skip ?? AppLocalizations.of(context)!.tr(''),
                        isSecondary: true,
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)?.placeBid ?? AppLocalizations.of(context)!.tr(''),
                        icon: const Icon(Icons.gavel_rounded, size: 18),
                        tint: const Color(0xFF007AFF),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAiBidNumpad(
                            context,
                            isLight,
                            order,
                            vehicle,
                            pickupAddr,
                            deliveryAddr,
                            distanceToPickup,
                            pickupToDelivery,
                            orderValue,
                            orderId,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 12 + MediaQuery.of(ctx).padding.bottom,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Helper chip widget used in the AI suggestion bottom sheet.
  Widget _buildAiInfoChip({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isLight,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.grey.withOpacity(0.06)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 18,
              color: color ?? (isLight ? Colors.black : Colors.white)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color ?? (isLight ? Colors.black : Colors.white),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color:
                  (isLight ? Colors.black : Colors.white).withOpacity(0.45),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Shows the bid numpad bottom sheet and submits the bid on confirm.
  void _showAiBidNumpad(
    BuildContext sheetCtx,
    bool isLight,
    Map<String, dynamic> order,
    Map<String, dynamic>? vehicle,
    String pickupAddr,
    String deliveryAddr,
    double distanceToPickup,
    double pickupToDelivery,
    double orderValue,
    dynamic orderId,
  ) {
    int bidCents = 0;
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (ctx, setS) {
          final bidAmount = bidCents / 100.0;

          Widget numKey(String label, {VoidCallback? onTap}) {
            return Expanded(
              child: TradeRepublicTap(
                onTap: onTap,
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ),
            );
          }

          void addDigit(int d) {
            if (bidCents > 999999) return; // Max 9999.99
            setS(() => bidCents = bidCents * 10 + d);
          }

          void deleteDigit() {
            setS(() => bidCents = bidCents ~/ 10);
          }

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Route summary compact
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pickupAddr.isNotEmpty ? pickupAddr : 'Pickup',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      appSettings.formatDistance(distanceToPickup / 1000),
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        deliveryAddr.isNotEmpty ? deliveryAddr : 'Delivery',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      appSettings.formatDistance(pickupToDelivery / 1000),
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Big bid display
                Text(
                  appSettings.formatCurrency(bidAmount),
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -2,
                    color: bidCents == 0
                        ? (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.25)
                        : const Color(0xFF34C759),
                  ),
                ),
                Text(
                  'Your Bid  ·  Order value ${appSettings.formatCurrency(orderValue)}',
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.45),
                  ),
                ),
                const SizedBox(height: 20),

                // Numpad
                for (final row in [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['', '0', '⌫'],
                ])
                  Row(
                    children: row.map((k) {
                      if (k.isEmpty) return Expanded(child: SizedBox());
                      if (k == '⌫') {
                        return numKey(k, onTap: deleteDigit);
                      }
                      return numKey(k, onTap: () => addDigit(int.parse(k)));
                    }).toList(),
                  ),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Submit
                TradeRepublicButton(
                  label: bidCents == 0
                      ? (AppLocalizations.of(context)?.enterBidAmount ?? AppLocalizations.of(context)!.tr(''))
                      : '${AppLocalizations.of(context)?.submitBid ?? AppLocalizations.of(context)!.tr('')} ${appSettings.formatCurrency(bidAmount)}',
                  onPressed: bidCents == 0
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _submitAiBid(order, vehicle, bidAmount);
                        },
                  width: double.infinity,
                  tint: bidCents == 0 ? null : const Color(0xFF34C759),
                ),
                SizedBox(height: 12 + MediaQuery.of(ctx).padding.bottom),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Submits a bid or directly accepts the order from the AI suggestion.
  Future<void> _submitAiBid(
    Map<String, dynamic> order,
    Map<String, dynamic>? vehicle,
    double bidAmount,
  ) async {
    final orderId = order['order_id'];
    if (!mounted) return;
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId =
          int.tryParse(prefs.getString('user_id') ?? AppLocalizations.of(context)!.tr('')) ?? 0;
      final driverUsername =
          prefs.getString('username') ?? prefs.getString('delvioo_username') ?? AppLocalizations.of(context)!.tr('');
      final token = prefs.getString('auth_token') ?? prefs.getString('token');

      // Try to find existing auction for this order
      final auctionsResponse = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/delvioo/auctions?status=open'),
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));

      int? auctionId;
      if (auctionsResponse.statusCode == 200) {
        final aData = json.decode(auctionsResponse.body);
        final auctions = (aData is List
                ? aData
                : aData['auctions'] ?? []) as List;
        for (final a in auctions) {
          if (a['order_id'].toString() == orderId.toString()) {
            auctionId = a['id'] is int
                ? a['id']
                : int.tryParse(a['id'].toString());
            break;
          }
        }
      }

      if (auctionId != null) {
        // Submit bid to auction
        final res = await http.post(
          Uri.parse(
              '${ApiConfig.baseUrl}/api/delvioo/auctions/$auctionId/bids'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'driver_id': driverId,
            'driver_username': driverUsername,
            'bid_amount': bidAmount,
            'price_mode': 'total',
            'vehicle_type': vehicle?['vehicle_type'] ?? AppLocalizations.of(context)!.tr('truck'),
            'message': 'AI suggestion',
          }),
        );
        if (res.statusCode == 200 || res.statusCode == 201) {
          if (mounted) {
            HapticFeedback.heavyImpact();
            TopNotification.success(
              context,
              'Bid submitted for Order #$orderId  ${appSettings.formatCurrency(bidAmount)} 🎯',
            );
          }
        } else {
          throw Exception('HTTP ${res.statusCode}');
        }
      } else {
        // Directly accept
        final res = await http.post(
          Uri.parse(
              '${ApiConfig.baseUrl}/api/delvioo/accept-order/$orderId'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'driver_id': driverId,
            'accepted_via': 'ai_suggestion_background',
            'bid_amount': bidAmount,
          }),
        );
        if (res.statusCode == 200) {
          if (mounted) {
            HapticFeedback.heavyImpact();
            TopNotification.success(
              context,
              'Order #$orderId accepted! ${appSettings.formatCurrency(bidAmount)} 🎯',
            );
          }
        } else {
          throw Exception('HTTP ${res.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)!.tr('Bid failed')}: $e',
        );
      }
    }
  }

  // ─── END AI Order Suggestion ───────────────────────────────────────────────

  IconData _getVehicleIcon(String? vehicleType) {
    switch (vehicleType?.toLowerCase()) {
      case 'car':
        return CupertinoIcons.car;
      case 'van':
        return CupertinoIcons.bus;
      case 'truck':
        return CupertinoIcons.cube_box;
      case 'motorcycle':
        return CupertinoIcons.car;
      case 'bicycle':
        return CupertinoIcons.person_crop_circle;
      default:
        return CupertinoIcons.cube_box;
    }
  }
}

// --- EINDEUTIGE, REPARIERTE SWIPE-KOMPONENTE ---
class _SwipeToAcceptSlider extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic> order;
  final bool isEnabled;
  final Map<String, dynamic>? selectedVehicle;
  final Function(bool)? onDragStateChanged; // Callback when drag starts/stops

  const _SwipeToAcceptSlider({
    required this.isLight,
    required this.order,
    required this.isEnabled,
    this.selectedVehicle,
    this.onDragStateChanged,
  });

  @override
  State<_SwipeToAcceptSlider> createState() => _SwipeToAcceptSliderState();
}

class _SwipeToAcceptSliderState extends State<_SwipeToAcceptSlider>
    with TickerProviderStateMixin {
  double _dragPosition = 0.0;
  bool _isAccepting = false;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late AnimationController _successController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    // Don't auto-repeat - only animate when needed
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    // Don't auto-repeat - only animate when needed
    _successController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    _successController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 UBER SWIPE: Building with new animations!');
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth - 72;
        final dragPercentage = (_dragPosition / maxDrag).clamp(0.0, 1.0);
        if (_dragPosition > 0) {
          print(
            '📊 Drag: ${dragPercentage.toStringAsFixed(2)} | BorderRadius: ${(10 + dragPercentage * 15).toStringAsFixed(1)}px',
          );
        }
        return TradeRepublicTap(
          onHorizontalDragStart: (details) {
            // Notify parent that slider is being dragged
            widget.onDragStateChanged?.call(true);
          },
          onHorizontalDragUpdate: (details) {
            // Only allow dragging if enabled (vehicle selected)
            if (!_isAccepting && widget.isEnabled) {
              setState(() {
                _dragPosition = (_dragPosition + details.delta.dx).clamp(
                  0.0,
                  maxDrag,
                );
              });
              if (dragPercentage >= 0.2 && dragPercentage < 0.22) {
                HapticFeedback.selectionClick();
              }
              if (dragPercentage >= 0.4 && dragPercentage < 0.42) {
                HapticFeedback.selectionClick();
              }
              if (dragPercentage >= 0.6 && dragPercentage < 0.62) {
                HapticFeedback.mediumImpact();
              }
              if (dragPercentage >= 0.8 && dragPercentage < 0.82) {
                HapticFeedback.mediumImpact();
              }
              if (dragPercentage >= 0.95 && dragPercentage < 0.97) {
                HapticFeedback.heavyImpact();
              }
            }
          },
          onHorizontalDragEnd: (details) {
            // Notify parent that slider drag ended
            widget.onDragStateChanged?.call(false);

            // Only allow completion if enabled
            if (!_isAccepting && widget.isEnabled) {
              if (dragPercentage >= 0.92) {
                HapticFeedback.heavyImpact();
                _acceptOrder();
              } else {
                HapticFeedback.lightImpact();
                setState(() {
                  _dragPosition = 0.0;
                });
              }
            }
          },
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // MINIMAL: Progress fill (transparent in light mode, no animations behind)
                if (dragPercentage > 0 || _isAccepting)
                  Positioned(
                    left: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      height: 60,
                      width: 32 + dragPercentage * (maxDrag + 32),
                      decoration: BoxDecoration(
                        color: _isAccepting
                            ? const Color(0xFF34C759)
                            : (widget.isLight
                                  ? Colors.transparent
                                  : Colors.black),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                    ),
                  ),

                // UBER-STYLE: Centered bold text
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 80),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _buildUberTextForProgress(
                          dragPercentage,
                          widget.isLight,
                        ),
                      ),
                    ),
                  ),
                ),

                // COOL ANIMATION: Rectangle → Circle with green border
                Positioned(
                  left: 2.0 + _dragPosition,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: dragPercentage > 0.1
                          ? Color.lerp(
                              widget.isLight ? Colors.black : Colors.white,
                              const Color(0xFF34C759).withOpacity(0.15),
                              dragPercentage,
                            )!
                          : (widget.isLight ? Colors.black : Colors.white),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _isAccepting
                              ? CupertinoIcons.checkmark
                              : CupertinoIcons.chevron_right,
                          key: ValueKey(_isAccepting ? 'check' : 'arrow'),
                          color: _isAccepting
                              ? const Color(0xFF34C759)
                              : (dragPercentage > 0.5
                                    ? const Color(0xFF34C759)
                                    : (widget.isLight
                                          ? Colors.white
                                          : Colors.black)),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUberTextForProgress(double progress, bool isLight) {
    // If disabled, show disabled text
    if (!widget.isEnabled) {
      return Text(
        AppLocalizations.of(context)?.selectVehicleFirst ?? AppLocalizations.of(context)!.tr('Select Vehicle First'),
        key: const ValueKey('disabled'),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: isLight ? Colors.white : Colors.black,
          letterSpacing: -0.5,
        ),
      );
    }

    // Text color based on mode and progress
    final textColor = isLight
        ? Colors
              .black87 // Always black in light mode (no background fill)
        : (progress > 0.15
              ? Colors.white
              : Colors.white60); // White on black fill in dark mode

    if (_isAccepting) {
      return Text(
        AppLocalizations.of(context)?.acceptingOrder ?? AppLocalizations.of(context)!.tr('Accepting Order...'),
        key: const ValueKey('accepting'),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textColor,
          letterSpacing: -0.5,
        ),
      );
    } else if (progress >= 0.85) {
      return Text(
        AppLocalizations.of(context)?.releaseToAccept ?? AppLocalizations.of(context)!.tr('Release to Accept'),
        key: const ValueKey('release'),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textColor,
          letterSpacing: -0.5,
        ),
      );
    } else if (progress >= 0.3) {
      return Text(
        AppLocalizations.of(context)?.keepSliding ?? AppLocalizations.of(context)!.tr('Keep Sliding...'),
        key: const ValueKey('almost'),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textColor.withOpacity(0.9),
          letterSpacing: -0.5,
        ),
      );
    } else {
      return Text(
        AppLocalizations.of(context)?.slideToAccept ?? AppLocalizations.of(context)!.tr('Slide to Accept'),
        key: const ValueKey('swipe'),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textColor.withOpacity(0.7),
          letterSpacing: -0.5,
        ),
      );
    }
  }

  void _acceptOrder() async {
    if (_isAccepting) return;

    setState(() {
      _isAccepting = true;
    });

    // Start success animation
    _successController.forward();

    HapticFeedback.heavyImpact();

    // Small delay for visual feedback
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final orderId = widget.order['order_id'] ?? widget.order['id'];

      print('🚀 MAIN PAGE: Accepting order $orderId');
      print('📦 Order data: ${widget.order}');

      // IMPORTANT: Shipping type validation
      final orderShippingType =
          widget.order['shipping_type']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('standard');
      final selectedVehicle = widget.selectedVehicle;

      print('🚚 Checking shipping type compatibility...');
      print('   Order requires: $orderShippingType');
      print(
        '   Selected vehicle: ${selectedVehicle?['vehicle_make']} ${selectedVehicle?['vehicle_model']}',
      );
      print('   Vehicle capabilities:');
      print(
        '     - standard_shipping: ${selectedVehicle?['standard_shipping']}',
      );
      print('     - cold_shipping: ${selectedVehicle?['cold_shipping']}');
      print('     - express_shipping: ${selectedVehicle?['express_shipping']}');

      // Helper function to check if value is truthy (1 or true)
      bool isTruthy(dynamic value) {
        if (value == null) return false;
        if (value is bool) return value;
        if (value is int) return value == 1;
        if (value is String) {
          return value == '1' || value.toLowerCase() == 'true';
        }
        return false;
      }

      // Validate if vehicle supports the required shipping type
      bool isVehicleCompatible = false;
      String errorMessage = '';

      switch (orderShippingType) {
        case 'standard':
          isVehicleCompatible = isTruthy(selectedVehicle?['standard_shipping']);
          if (!isVehicleCompatible) {
            errorMessage =
                AppLocalizations.of(context)?.vehicleNoStandardShipping ?? AppLocalizations.of(context)!.tr('❌ Your vehicle does not support standard shipping.\\\\nPlease select a different vehicle.');
          }
          break;
        case 'cold':
          isVehicleCompatible = isTruthy(selectedVehicle?['cold_shipping']);
          if (!isVehicleCompatible) {
            errorMessage =
                AppLocalizations.of(context)?.vehicleNoColdShipping ?? AppLocalizations.of(context)!.tr('❄️ This order requires refrigerated shipping!\\\\nYour vehicle has no cooling.\\\\n\\\\nProducts like meat must be transported refrigerated, otherwise they spoil.\\\\n\\\\nPlease select a refrigerated vehicle.');
          }
          break;
        case 'express':
          isVehicleCompatible = isTruthy(selectedVehicle?['express_shipping']);
          if (!isVehicleCompatible) {
            errorMessage =
                AppLocalizations.of(context)?.vehicleNoExpressShipping ?? AppLocalizations.of(context)!.tr('⚡ This order is express shipping!\\\\nYour vehicle is not approved for express.\\\\nPlease select an express vehicle.');
          }
          break;
        case 'delvioo':
          // "delvioo" means standard shipping
          isVehicleCompatible = isTruthy(selectedVehicle?['standard_shipping']);
          if (!isVehicleCompatible) {
            errorMessage =
                AppLocalizations.of(context)?.vehicleNoStandardShipping ?? AppLocalizations.of(context)!.tr('❌ Your vehicle does not support standard shipping.\\\\nPlease select a different vehicle.');
          }
          break;
        case 'pickup':
          // Pickup orders don't require vehicle validation
          isVehicleCompatible = true;
          break;
        default:
          // Unknown type -> require standard shipping as fallback
          isVehicleCompatible = isTruthy(selectedVehicle?['standard_shipping']);
          if (!isVehicleCompatible) {
            errorMessage =
                AppLocalizations.of(context)?.vehicleNoStandardShipping ?? AppLocalizations.of(context)!.tr('❌ Your vehicle does not support standard shipping.\\\\nPlease select a different vehicle.');
          }
      }

      if (!isVehicleCompatible) {
        print('❌ VALIDATION FAILED: Vehicle not compatible with shipping type');

        if (mounted) {
          TopNotification.error(context, errorMessage);

          setState(() {
            _isAccepting = false;
            _dragPosition = 0.0;
          });
        }
        return; // Stop here - don't accept the order
      }

      print('✅ Vehicle is compatible with $orderShippingType shipping');
      print(
        '✅ Selected vehicle: ${selectedVehicle?['vehicle_make']} ${selectedVehicle?['vehicle_model']} (ID: ${selectedVehicle?['id']})',
      );

      // Get driver ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final driverId =
          prefs.getInt('driverId') ?? 1; // Driver ID in delvioo_users table

      // We already have a selected vehicle that passed validation - no need to check again
      // The vehicle selection sheet already filtered compatible vehicles

      // Call the accept order API with location data
      final requestBody = {
        'orderId': widget.order['id'], // Use internal numeric ID
        'driverId': driverId, // Use driver ID from delvioo_users
        'routeDistance': widget.order['routeDistance'] ?? 0.0,
        'routeDuration': widget.order['routeDuration'] ?? 0.0,
      };

      // Add driver start location if available
      if (widget.order['driverStartLat'] != null &&
          widget.order['driverStartLng'] != null) {
        requestBody['driverStartLat'] = widget.order['driverStartLat'];
        requestBody['driverStartLng'] = widget.order['driverStartLng'];
        print(
          '📍 Sending driver start location: ${widget.order['driverStartLat']}, ${widget.order['driverStartLng']}',
        );
      }

      // Add pickup location if available
      if (widget.order['pickupLat'] != null &&
          widget.order['pickupLng'] != null) {
        requestBody['pickupLat'] = widget.order['pickupLat'];
        requestBody['pickupLng'] = widget.order['pickupLng'];
        print(
          '📍 Sending pickup location: ${widget.order['pickupLat']}, ${widget.order['pickupLng']}',
        );
      }

      // Add delivery location if available
      if (widget.order['deliveryLat'] != null &&
          widget.order['deliveryLng'] != null) {
        requestBody['deliveryLat'] = widget.order['deliveryLat'];
        requestBody['deliveryLng'] = widget.order['deliveryLng'];
        print(
          '📍 Sending delivery location: ${widget.order['deliveryLat']}, ${widget.order['deliveryLng']}',
        );
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/accept-order'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      print('📥 Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);

        if (result['success']) {
          // Success! Show notification from top
          if (mounted) {
            TopNotification.success(
              context,
              'Order #$orderId accepted successfully!',
            );
          }

          // Wait a moment then clear
          await Future.delayed(const Duration(milliseconds: 1200));

          if (mounted) {
            // Clear active order to hide swipe interface
            activeOrderNotifier.value = null;

            // Reset state
            setState(() {
              _isAccepting = false;
              _dragPosition = 0.0;
            });
          }
        } else {
          throw Exception(result['message'] ?? AppLocalizations.of(context)!.tr('Failed to accept order'));
        }
      } else if (response.statusCode == 400) {
        // Handle specific error codes
        final result = json.decode(response.body);
        if (result['errorCode'] == 'NO_VEHICLE_REGISTERED') {
          if (mounted) {
            TopNotification.error(
              context,
                result['message'] ??
                  (AppLocalizations.of(context)
                      ?.pleaseRegisterYourVehicleFirst ?? AppLocalizations.of(context)!.tr('')),
            );
          }
        } else {
          throw Exception(result['message'] ?? AppLocalizations.of(context)!.tr('Failed to accept order'));
        }

        if (mounted) {
          setState(() {
            _isAccepting = false;
            _dragPosition = 0.0;
          });
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error accepting order: $e');

      if (mounted) {
        TopNotification.error(
          context,
          'Failed to accept order: ${e.toString()}',
        );

        setState(() {
          _isAccepting = false;
          _dragPosition = 0.0;
        });
      }
    }
  }
}

// Swipe Accept Bottom Sheet with minimize functionality
class _SwipeAcceptBottomSheet extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic> order;
  final Map<String, dynamic>? selectedVehicle;
  final VoidCallback onVehicleSelect;
  final Function(Map<String, dynamic>) onVehicleChanged;
  final VoidCallback onClose;

  const _SwipeAcceptBottomSheet({
    required this.isLight,
    required this.order,
    this.selectedVehicle,
    required this.onVehicleSelect,
    required this.onVehicleChanged,
    required this.onClose,
  });

  @override
  State<_SwipeAcceptBottomSheet> createState() =>
      _SwipeAcceptBottomSheetState();
}

class _SwipeAcceptBottomSheetState extends State<_SwipeAcceptBottomSheet>
    with SingleTickerProviderStateMixin {
  bool _isMinimized = false;
  double _dragOffset = 0.0;
  bool _isSliderActive = false; // Track if slider is being dragged
  bool _isAnimating = false; // Track if expansion/minimize animation is running
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _animateToExpanded() {
    setState(() {
      _isMinimized = false;
      _isAnimating = true;
      _dragOffset = 0.0; // Reset offset immediately
    });
    _slideController.forward().then((_) {
      setState(() {
        _isAnimating = false;
      });
    });
    HapticFeedback.lightImpact();
  }

  void _animateToMinimized() {
    setState(() {
      _isMinimized = true;
      _isAnimating = true;
      _dragOffset = 0.0; // Reset offset immediately
    });
    _slideController.reverse().then((_) {
      setState(() {
        _isAnimating = false;
      });
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    // Direct GestureDetector without Align wrapper
    // Already positioned at bottom via Positioned widget in parent
    return TradeRepublicTap(
      onVerticalDragUpdate: (details) {
        // Block vertical drag if slider is active OR if animation is running
        if (_isSliderActive || _isAnimating) return;

        setState(() {
          if (_isMinimized) {
            // In minimized state: allow upward swipe (negative delta.dy)
            _dragOffset += details.delta.dy;
            _dragOffset = _dragOffset.clamp(-300.0, 0.0);

            // Trigger expansion immediately when dragged up enough
            if (_dragOffset < -50) {
              _animateToExpanded();
            }
          } else {
            // In expanded state: allow downward swipe (positive delta.dy)
            _dragOffset += details.delta.dy;
            _dragOffset = _dragOffset.clamp(0.0, screenHeight);

            // Trigger minimize immediately when dragged down enough
            if (_dragOffset > 80) {
              _animateToMinimized();
            }
          }
        });
      },
      onVerticalDragEnd: (details) {
        // Block if already animating
        if (_isAnimating) return;

        // Check velocity for flick gestures
        final velocity = details.velocity.pixelsPerSecond.dy;

        if (_isMinimized) {
          // If minimized: expand on upward flick
          if (velocity < -500) {
            _animateToExpanded();
          } else {
            // Snap back to minimized position
            setState(() {
              _dragOffset = 0.0;
            });
          }
        } else {
          // If expanded: minimize on downward flick
          if (velocity > 500) {
            _animateToMinimized();
          } else {
            // Snap back to expanded position
            setState(() {
              _dragOffset = 0.0;
            });
          }
        }
      },
      child: AnimatedBuilder(
        animation: _slideAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              color: widget.isLight ? Colors.white : Colors.black,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              bottom: true, // Ensure content respects safe area at bottom
              child: AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                child: _isMinimized
                    ? _buildMinimizedContent()
                    : _buildExpandedContent(),
              ),
            ),
          );
        },
      ),
    );
  }

  // Minimized state - only swipe slider visible
  Widget _buildMinimizedContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Trade Republic Handle bar
        Container(
          width: 30,
          height: 8,
          margin: const EdgeInsets.only(top: 0, bottom: 20),
          decoration: BoxDecoration(
            color: widget.isLight ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
        ),
        // Swipe slider
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _SwipeToAcceptSlider(
            isLight: widget.isLight,
            order: widget.order,
            isEnabled: widget.selectedVehicle != null,
            selectedVehicle: widget.selectedVehicle,
            onDragStateChanged: (isActive) {
              setState(() {
                _isSliderActive = isActive;
              });
            },
          ),
        ),
      ],
    );
  }

  // Expanded state - full content
  Widget _buildExpandedContent() {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Trade Republic Handle bar
        const DragHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.cube_box,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}${widget.order['order_id'] ?? widget.order['id']}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: widget.isLight ? Colors.black : Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Modern Required Shipping Type Card
              Container(
                padding: DesktopAppWrapper.getPagePadding(),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _getShippingTypeColor(
                        widget.order['shipping_type'],
                      ).withOpacity(0.12),
                      _getShippingTypeColor(
                        widget.order['shipping_type'],
                      ).withOpacity(0.05),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Icon container with modern styling
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _getShippingTypeColor(
                          widget.order['shipping_type'],
                        ).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Icon(
                        _getShippingTypeIcon(widget.order['shipping_type']),
                        color: _getShippingTypeColor(
                          widget.order['shipping_type'],
                        ),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.requiredShippingType ?? AppLocalizations.of(context)!.tr('Required Shipping Type'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                              color:
                                  (widget.isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getShippingTypeName(widget.order['shipping_type']),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: widget.isLight
                                  ? Colors.black
                                  : Colors.white,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getShippingTypeDescription(
                              widget.order['shipping_type'],
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color:
                                  (widget.isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Vehicle selection button
              TradeRepublicTap(
                onTap: widget.onVehicleSelect,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isLight
                        ? Colors.transparent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.selectedVehicle == null
                              ? const Color(0xFFFF3B30).withOpacity(0.1)
                              : const Color(0xFF007AFF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Icon(
                          CupertinoIcons.cube_box,
                          color: widget.selectedVehicle == null
                              ? const Color(0xFFFF3B30)
                              : const Color(0xFF007AFF),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.selectedVehicle == null
                                  ? AppLocalizations.of(context)?.selectVehicle ?? AppLocalizations.of(context)!.tr('Select Vehicle')
                                  : '${widget.selectedVehicle!['vehicle_make']} ${widget.selectedVehicle!['vehicle_model']}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: widget.selectedVehicle == null
                                    ? const Color(0xFFFF3B30)
                                    : (widget.isLight
                                          ? Colors.black
                                          : Colors.white),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.selectedVehicle == null
                                  ? AppLocalizations.of(context)?.requiredToAcceptOrder ?? AppLocalizations.of(context)!.tr('Required to accept order')
                                  : '${widget.selectedVehicle!['vehicle_year']} • ${widget.selectedVehicle!['license_plate']}',
                              style: TextStyle(
                                fontSize: 13,
                                color: widget.selectedVehicle == null
                                    ? const Color(0xFFFF3B30).withOpacity(0.7)
                                    : (widget.isLight
                                          ? Colors.black
                                          : Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: widget.isLight ? Colors.white : Colors.black,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Modern swipe slider - only enabled if vehicle is selected
              _SwipeToAcceptSlider(
                isLight: widget.isLight,
                order: widget.order,
                isEnabled: widget.selectedVehicle != null,
                selectedVehicle: widget.selectedVehicle,
                onDragStateChanged: (isActive) {
                  setState(() {
                    _isSliderActive = isActive;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper methods for shipping type display
  String _getShippingTypeName(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'standard':
        return AppLocalizations.of(context)?.standardShippingName ?? AppLocalizations.of(context)!.tr('Standard Shipping');
      case 'cold':
        return AppLocalizations.of(context)?.coldShippingName ?? AppLocalizations.of(context)!.tr('Cold Shipping');
      case 'express':
        return AppLocalizations.of(context)?.expressShippingName ?? AppLocalizations.of(context)!.tr('Express Shipping');
      default:
        return AppLocalizations.of(context)?.standardShippingName ?? AppLocalizations.of(context)!.tr('Standard Shipping');
    }
  }

  IconData _getShippingTypeIcon(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'standard':
        return CupertinoIcons.cube_box;
      case 'cold':
        return CupertinoIcons.snow;
      case 'express':
        return CupertinoIcons.bolt;
      default:
        return CupertinoIcons.cube_box;
    }
  }

  Color _getShippingTypeColor(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'standard':
        return const Color(0xFF34C759); // Green for standard
      case 'cold':
        return const Color(0xFF007AFF); // Blue for cold
      case 'express':
        return const Color(0xFFFF9500); // Orange for express
      default:
        return const Color(0xFF34C759);
    }
  }

  String _getShippingTypeDescription(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'standard':
        return AppLocalizations.of(context)?.regularTemperatureTransport ?? AppLocalizations.of(context)!.tr('Regular temperature transport');
      case 'cold':
        return AppLocalizations.of(context)?.refrigeratedTransportRequired ?? AppLocalizations.of(context)!.tr('Refrigerated transport required');
      case 'express':
        return AppLocalizations.of(context)?.priorityFastestDelivery ?? AppLocalizations.of(context)!.tr('Priority fast delivery');
      default:
        return AppLocalizations.of(context)?.regularTemperatureTransport ?? AppLocalizations.of(context)!.tr('Regular temperature transport');
    }
  }
}

// Vehicle Selection Bottom Sheet
class _VehicleSelectionSheet extends StatefulWidget {
  final bool isLight;
  final Map<String, dynamic>? currentSelectedVehicle;
  final String? requiredShippingType;

  const _VehicleSelectionSheet({
    required this.isLight,
    this.currentSelectedVehicle,
    this.requiredShippingType,
  });

  @override
  State<_VehicleSelectionSheet> createState() => _VehicleSelectionSheetState();
}

class _VehicleSelectionSheetState extends State<_VehicleSelectionSheet> {
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoading = true;
  Map<String, dynamic>? _selectedVehicle;

  @override
  void initState() {
    super.initState();
    _selectedVehicle = widget.currentSelectedVehicle;
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    try {
      // Get driver username from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final driverUsername = prefs.getString('username') ?? AppLocalizations.of(context)!.tr('');

      print('🚗 Loading vehicles from API...');
      print(
        '📍 API URL: ${ApiConfig.baseUrl}/api/delvioo/vehicles/$driverUsername',
      );

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/delvioo/vehicles/$driverUsername'),
      );
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('✅ Parsed response: $result');

        if (result['success'] && result['vehicles'] != null) {
          final vehiclesList = List<Map<String, dynamic>>.from(
            result['vehicles'],
          );
          print('✅ Found ${vehiclesList.length} vehicles total');

          // Filter vehicles based on required shipping type
          List<Map<String, dynamic>> compatibleVehicles = vehiclesList;

          if (widget.requiredShippingType != null) {
            final requiredType = widget.requiredShippingType!.toLowerCase();
            print('🔍 Filtering vehicles for shipping type: $requiredType');

            compatibleVehicles = vehiclesList.where((vehicle) {
              bool isCompatible = false;

              // Helper function to check if value is truthy (1 or true)
              bool isTruthy(dynamic value) {
                if (value == null) return false;
                if (value is bool) return value;
                if (value is int) return value == 1;
                if (value is String) {
                  return value == '1' || value.toLowerCase() == 'true';
                }
                return false;
              }

              switch (requiredType) {
                case 'standard':
                  isCompatible = isTruthy(vehicle['standard_shipping']);
                  break;
                case 'cold':
                  isCompatible = isTruthy(vehicle['cold_shipping']);
                  break;
                case 'express':
                  isCompatible = isTruthy(vehicle['express_shipping']);
                  break;
                case 'delvioo':
                  // "delvioo" means standard shipping
                  isCompatible = isTruthy(vehicle['standard_shipping']);
                  break;
                case 'pickup':
                  // Pickup orders don't need vehicle - show all
                  isCompatible = true;
                  break;
                default:
                  // Unknown type - require standard shipping as fallback
                  isCompatible = isTruthy(vehicle['standard_shipping']);
              }

              print(
                '  🚗 ${vehicle['vehicle_make']} ${vehicle['vehicle_model']}: $isCompatible',
              );
              print(
                '     standard: ${vehicle['standard_shipping']}, cold: ${vehicle['cold_shipping']}, express: ${vehicle['express_shipping']}',
              );

              return isCompatible;
            }).toList();

            print(
              '✅ ${compatibleVehicles.length} compatible vehicles for $requiredType shipping',
            );
          }

          setState(() {
            _vehicles = compatibleVehicles;
            _isLoading = false;
          });
        } else {
          print('⚠️ API returned success=false or no vehicles');
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        print('❌ API returned status ${response.statusCode}');
        if (mounted) {
          TopNotification.error(
            context,
            'Failed to load vehicles: Server returned ${response.statusCode}',
          );
        }
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading vehicles: $e');
      print('❌ Stack trace: ${StackTrace.current}');

      if (mounted) {
        TopNotification.error(
          context,
          'Failed to load vehicles: ${e.toString()}',
        );
      }

      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
      final isLight = Provider.of<AppSettings>(context, listen: false).isLightMode(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.car_detailed,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.selectVehicle ?? AppLocalizations.of(context)!.tr('Select Vehicle'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),

            // Liability Notice - Minimal Design
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                AppLocalizations.of(context)?.youAreLiableForSafeDelivery ?? AppLocalizations.of(context)!.tr('You are liable for safe delivery and maintaining product quality'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isLight
                      ? Colors.black.withOpacity(0.5)
                      : Colors.white.withOpacity(0.5),
                ),
              ),
            ),

            // Content
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CultiooLoadingIndicator()),
              )
            else if (_vehicles.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    // Minimal icon container
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: (widget.isLight ? Colors.black : Colors.white)
                            .withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.requiredShippingType != null
                            ? CupertinoIcons.cube_box
                            : CupertinoIcons.car,
                        size: 72,
                        color: (widget.isLight ? Colors.black : Colors.white)
                            .withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                    Text(
                      widget.requiredShippingType != null
                          ? AppLocalizations.of(context)?.noCompatibleVehicles ?? AppLocalizations.of(context)!.tr('No Compatible Vehicles')
                          : AppLocalizations.of(context)?.noVehiclesRegistered ?? AppLocalizations.of(context)!.tr('No Vehicles Registered'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: widget.isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    Text(
                      widget.requiredShippingType != null
                          ? 'None of your vehicles support\n${_getShippingTypeName(widget.requiredShippingType)} delivery.\nPlease update your vehicle capabilities.'
                          : AppLocalizations.of(context)?.registerFirstVehicleToStart ?? AppLocalizations.of(context)!.tr('Register your first vehicle to start\\\\naccepting delivery orders'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: widget.isLight
                            ? Colors.black.withOpacity(0.6)
                            : Colors.white.withOpacity(0.6),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Minimal button
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)?.registerVehicle ?? AppLocalizations.of(context)!.tr('Register Vehicle'),
                      icon: Icon(CupertinoIcons.add_circled, size: 22),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(context);
                        // TODO: Navigate to vehicle registration
                      },
                      backgroundColor: widget.isLight ? Colors.black : Colors.white,
                      foregroundColor: widget.isLight ? Colors.white : Colors.black,
                      width: double.infinity,
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: _vehicles.length,
                itemBuilder: (context, index) {
                  final vehicle = _vehicles[index];
                  final isSelected =
                      _selectedVehicle != null &&
                      _selectedVehicle!['id'] == vehicle['id'];
                  final isActive = vehicle['is_active'] == 1;

                  // Determine shipping compatibility based on order requirement
                  final shippingType =
                      widget.requiredShippingType?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('standard');
                  String shippingName;
                  switch (shippingType) {
                    case 'cold':
                      shippingName = AppLocalizations.of(context)?.coldShippingName ?? AppLocalizations.of(context)!.tr('Refrigerated Shipping');
                      break;
                    case 'express':
                      shippingName = AppLocalizations.of(context)?.expressShippingName ?? AppLocalizations.of(context)!.tr('Express Shipping');
                      break;
                    default:
                      shippingName = AppLocalizations.of(context)?.standardShippingName ?? AppLocalizations.of(context)!.tr('Standard Shipping');
                  }
                  bool compatible = true;
                  switch (shippingType) {
                    case 'standard':
                      compatible =
                          vehicle['standard_shipping'] == 1 ||
                          vehicle['standard_shipping'] == true;
                      break;
                    case 'cold':
                      compatible =
                          vehicle['cold_shipping'] == 1 ||
                          vehicle['cold_shipping'] == true;
                      break;
                    case 'express':
                      compatible =
                          vehicle['express_shipping'] == 1 ||
                          vehicle['express_shipping'] == true;
                      break;
                    default:
                      compatible = true;
                  }

                  return TradeRepublicTap(
                    onTap: isActive
                        ? (compatible
                              ? () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(context, vehicle);
                                }
                              : () {
                                  HapticFeedback.lightImpact();
                                  TopNotification.error(
                                    context,
                                    'This vehicle does not support the required shipping type: $shippingName',
                                  );
                                })
                        : null,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (widget.isLight ? Colors.black : Colors.white)
                            : (widget.isLight
                                  ? Colors.transparent
                                  : Colors.transparent),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Row(
                        children: [
                          // Minimal vehicle icon
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (widget.isLight
                                        ? Colors.white
                                        : Colors.black)
                                  : (widget.isLight
                                            ? Colors.black
                                            : Colors.white)
                                        .withOpacity(0.08),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            ),
                            child: Icon(
                              _getVehicleIcon(vehicle['vehicle_type']),
                              color: isSelected
                                  ? (widget.isLight
                                        ? Colors.black
                                        : Colors.white)
                                  : (widget.isLight
                                        ? Colors.black.withOpacity(0.7)
                                        : Colors.white.withOpacity(0.7)),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Vehicle info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${vehicle['vehicle_make']} ${vehicle['vehicle_model']}',
                                        style: TextStyle(
                                          fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? (widget.isLight
                                                    ? Colors.white
                                                    : Colors.black)
                                              : (widget.isLight
                                                    ? Colors.black
                                                    : Colors.white),
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: widget.isLight
                                              ? Colors.white
                                              : Colors.black,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          CupertinoIcons.checkmark,
                                          color: widget.isLight
                                              ? Colors.black
                                              : Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      CupertinoIcons.calendar,
                                      size: 13,
                                      color: isSelected
                                          ? (widget.isLight
                                                    ? Colors.white
                                                    : Colors.black)
                                                .withOpacity(0.7)
                                          : (widget.isLight
                                                ? Colors.black.withOpacity(0.5)
                                                : Colors.white.withOpacity(
                                                    0.5,
                                                  )),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      vehicle['vehicle_year'].toString(),
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        fontWeight: FontWeight.w500,
                                        color: isSelected
                                            ? (widget.isLight
                                                      ? Colors.white
                                                      : Colors.black)
                                                  .withOpacity(0.9)
                                            : (widget.isLight
                                                  ? Colors.black.withOpacity(
                                                      0.7,
                                                    )
                                                  : Colors.white.withOpacity(
                                                      0.7,
                                                    )),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      CupertinoIcons.location,
                                      size: 13,
                                      color: isSelected
                                          ? (widget.isLight
                                                    ? Colors.white
                                                    : Colors.black)
                                                .withOpacity(0.7)
                                          : (widget.isLight
                                                ? Colors.black.withOpacity(0.5)
                                                : Colors.white.withOpacity(
                                                    0.5,
                                                  )),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                        vehicle['license_plate'] ??
                                          (AppLocalizations.of(context)
                                              ?.naValue ?? AppLocalizations.of(context)!.tr('')),
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? (widget.isLight
                                                      ? Colors.white
                                                      : Colors.black)
                                                  .withOpacity(0.9)
                                            : (widget.isLight
                                                  ? Colors.black.withOpacity(
                                                      0.7,
                                                    )
                                                  : Colors.white.withOpacity(
                                                      0.7,
                                                    )),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    // Status Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                        gradient: isActive
                                            ? LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  const Color(
                                                    0xFF34C759,
                                                  ).withOpacity(0.2),
                                                  const Color(
                                                    0xFF34C759,
                                                  ).withOpacity(0.1),
                                                ],
                                              )
                                            : null,
                                        color: !isActive
                                            ? Colors.black.withOpacity(0.15)
                                            : null,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: isActive
                                                  ? const Color(0xFF34C759)
                                                  : widget.isLight
                                                  ? Colors.black
                                                  : Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isActive ? AppLocalizations.of(context)?.active ?? AppLocalizations.of(context)!.tr('Active') : 'Inactive',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: isActive
                                                  ? const Color(0xFF34C759)
                                                  : widget.isLight
                                                  ? Colors.black
                                                  : Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Vehicle Type Badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            (widget.isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.08),
                                            (widget.isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.03),
                                          ],
                                        ),
                                      ),
                                      child: Text(
                                        wagonLabelFromType(
                                          vehicle['vehicle_type']?.toString(),
                                          AppLocalizations.of(context) ??
                                              AppLocalizations(
                                                const Locale('en'),
                                              ),
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? (widget.isLight
                                                        ? Colors.white
                                                        : Colors.black)
                                                    .withOpacity(0.8)
                                              : (widget.isLight
                                                    ? Colors.black.withOpacity(
                                                        0.7,
                                                      )
                                                    : Colors.white.withOpacity(
                                                        0.7,
                                                      )),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                // Modern compatibility banner
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                    gradient: compatible
                                        ? LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              const Color(
                                                0xFF34C759,
                                              ).withOpacity(0.15),
                                              const Color(
                                                0xFF34C759,
                                              ).withOpacity(0.05),
                                            ],
                                          )
                                        : LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              const Color(
                                                0xFFFF3B30,
                                              ).withOpacity(0.12),
                                              const Color(
                                                0xFFFF3B30,
                                              ).withOpacity(0.04),
                                            ],
                                          ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: compatible
                                              ? const Color(
                                                  0xFF34C759,
                                                ).withOpacity(0.2)
                                              : const Color(
                                                  0xFFFF3B30,
                                                ).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                        ),
                                        child: Icon(
                                          compatible
                                              ? CupertinoIcons.checkmark_circle
                                              : CupertinoIcons
                                                    .exclamationmark_triangle,
                                          size: 18,
                                          color: compatible
                                              ? const Color(0xFF34C759)
                                              : const Color(0xFFFF3B30),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              compatible
                                                  ? AppLocalizations.of(context)?.compatibleLabel ?? AppLocalizations.of(context)!.tr('Compatible')
                                                  : AppLocalizations.of(context)?.notCompatibleLabel ?? AppLocalizations.of(context)!.tr('Not Compatible'),
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: compatible
                                                    ? const Color(0xFF34C759)
                                                    : const Color(0xFFFF3B30),
                                              ),
                                            ),
                                            if (!compatible) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                '${AppLocalizations.of(context)?.requiresShipping ?? AppLocalizations.of(context)!.tr('Requires')} $shippingName',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: widget.isLight
                                                      ? Colors.black
                                                            .withOpacity(0.6)
                                                      : Colors.white
                                                            .withOpacity(0.6),
                                                ),
                                              ),
                                            ],
                                          ],
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
                  );
                },
              ),
        ],
      ),
    );
  }

  IconData _getVehicleIcon(String? vehicleType) {
    switch (vehicleType?.toLowerCase()) {
      case 'car':
        return CupertinoIcons.car;
      case 'van':
        return CupertinoIcons.bus;
      case 'truck':
        return CupertinoIcons.cube_box;
      case 'motorcycle':
        return CupertinoIcons.car;
      case 'bicycle':
        return CupertinoIcons.person_crop_circle;
      default:
        return CupertinoIcons.cube_box;
    }
  }

  String _getShippingTypeName(String? shippingType) {
    switch (shippingType?.toLowerCase()) {
      case 'standard':
        return AppLocalizations.of(context)?.standardLabel ?? AppLocalizations.of(context)!.tr('Standard');
      case 'cold':
        return 'Cold';
      case 'express':
        return 'Express';
      default:
        return shippingType ?? (AppLocalizations.of(context)?.standardLabel ?? AppLocalizations.of(context)!.tr('Standard'));
    }
  }
}
