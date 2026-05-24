import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'business_home_page.dart';
import 'products_page.dart';
import 'orders_page.dart';
import 'messenger_page.dart';
import 'business_account_page.dart';
// settings_page removed - settings are now accessible from the Account page
import '../../../shared/services/app_settings.dart';
import '../../../config/api_config.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/page_indicator.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_list_tile.dart';
import '../../../shared/widgets/desktop_sheet_navigator.dart';
import '../../../shared/widgets/cultioo_desktop_layout.dart';
import '../../../shared/widgets/trade_republic_theme.dart';
import '../../../shared/widgets/trade_republic_tap.dart';

// Global notifier to hide navigation when bottom sheets are open
class NavigationVisibility {
  static final ValueNotifier<bool> isVisible = ValueNotifier<bool>(true);

  static void hide() => isVisible.value = false;
  static void show() => isVisible.value = true;
}

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  PageController? _pageController;
  int _activeDesktopTab = 0;
  final List<int> _desktopTabPages = [0];
  bool _isDesktopSplitView = false;
  int _desktopSplitLeftTab = 0;
  int _desktopSplitRightTab = 0;
  double _desktopSplitRatio = 0.5;
  final AppSettings _appSettings = AppSettings();
  Map<String, dynamic>? userData; // User profile data including image
  // Sidebar resize state
  static const double _sidebarMinWidth = 72;
  static const double _sidebarMaxWidth = 360;
  static const double _sidebarDefaultWidth = 260;
  double _sidebarWidth = _sidebarDefaultWidth;
  bool _sidebarCollapsed = false;
  double _sidebarWidthBeforeCollapse = _sidebarDefaultWidth;

  // Animation controllers for sidebar (nullable to avoid late init errors)
  AnimationController? _logoAnimationController;
  AnimationController? _sidebarItemsController;
  Animation<double>? _logoScaleAnimation;
  Animation<double>? _logoFadeAnimation;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _appSettings.addListener(_onSettingsChanged);

    // Initialize logo animation
    _logoAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800));
    _logoScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoAnimationController!,
        curve: Curves.easeOutBack));
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoAnimationController!, curve: Curves.easeOut));

    // Initialize sidebar items stagger animation
    _sidebarItemsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600));

    // Start animations after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logoAnimationController?.forward();
      _sidebarItemsController?.forward();
    });

    print(
      '🚀 MainNavigation initState - Platform.isMacOS: ${Platform.isMacOS}');

    // Load user profile data for desktop sidebar
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      print('🚀 Calling _loadUserData for desktop');
      _loadUserData();
    } else {
      print('🚀 Mobile platform, skipping _loadUserData');
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _appSettings.removeListener(_onSettingsChanged);
    _logoAnimationController?.dispose();
    _sidebarItemsController?.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    setState(() {});
  }

  void _onBottomNavTapped(int index) {
    setState(() {
      _currentIndex = index;
      if (_activeDesktopTab >= 0 && _activeDesktopTab < _desktopTabPages.length) {
        _desktopTabPages[_activeDesktopTab] = index;
      }
    });
    _pageController?.jumpToPage(index);
  }

  Widget _buildDesktopPageByIndex(int index) {
    switch (index.clamp(0, 4)) {
      case 0:
        return const BusinessHomePage();
      case 1:
        return const ProductsPage();
      case 2:
        return const OrdersPage();
      case 3:
        return const MessengerPage();
      case 4:
      default:
        return const BusinessAccountPage();
    }
  }

  String _getDesktopTabLabel(int pageIndex) {
    final loc = AppLocalizations.of(context);
    switch (pageIndex.clamp(0, 4)) {
      case 0:
        return loc?.home ?? AppLocalizations.of(context)!.tr('Home');
      case 1:
        return loc?.products ?? AppLocalizations.of(context)!.tr('Products');
      case 2:
        return loc?.orders ?? AppLocalizations.of(context)!.tr('Orders');
      case 3:
        return loc?.messages ?? AppLocalizations.of(context)!.tr('Messages');
      case 4:
      default:
        return loc?.account ?? AppLocalizations.of(context)!.tr('Account');
    }
  }

  IconData _getDesktopTabIcon(int pageIndex) {
    switch (pageIndex.clamp(0, 4)) {
      case 0:
        return CupertinoIcons.house_fill;
      case 1:
        return CupertinoIcons.cube_box_fill;
      case 2:
        return CupertinoIcons.doc_text_fill;
      case 3:
        return CupertinoIcons.chat_bubble_fill;
      case 4:
      default:
        return CupertinoIcons.person_fill;
    }
  }

  void _openDesktopTab(int tabIndex) {
    final page = _desktopTabPages[tabIndex].clamp(0, 4);
    setState(() {
      _activeDesktopTab = tabIndex;
      _currentIndex = page;
    });
    _pageController?.jumpToPage(page);
  }

  int _firstOtherDesktopTabIndex(int tabIndex) {
    for (var i = 0; i < _desktopTabPages.length; i++) {
      if (i != tabIndex) return i;
    }
    return -1;
  }

  void _startDesktopSplit(int sourceTab, int targetTab) {
    if (_desktopTabPages.length < 2) return;
    if (sourceTab == targetTab) {
      final partner = _firstOtherDesktopTabIndex(targetTab);
      if (partner == -1) return;
      sourceTab = partner;
    }

    setState(() {
      _isDesktopSplitView = true;
      _desktopSplitLeftTab = targetTab;
      _desktopSplitRightTab = sourceTab;
      _activeDesktopTab = sourceTab;
      _desktopSplitRatio = 0.5;
    });
  }

  void _closeDesktopTab(int tabIndex) {
    if (_desktopTabPages.length <= 1) return;

    setState(() {
      _desktopTabPages.removeAt(tabIndex);

      if (_activeDesktopTab >= _desktopTabPages.length) {
        _activeDesktopTab = _desktopTabPages.length - 1;
      }

      if (_isDesktopSplitView) {
        if (_desktopSplitLeftTab == tabIndex || _desktopSplitRightTab == tabIndex) {
          _isDesktopSplitView = false;
        } else {
          if (_desktopSplitLeftTab > tabIndex) _desktopSplitLeftTab -= 1;
          if (_desktopSplitRightTab > tabIndex) _desktopSplitRightTab -= 1;
        }
      }

      _currentIndex = _desktopTabPages[_activeDesktopTab].clamp(0, 4);
    });

    _pageController?.jumpToPage(_currentIndex);
  }

  void _showDesktopTabActions(int tabIndex, bool isLight) {
    final page = _desktopTabPages[tabIndex].clamp(0, 4);

    TradeRepublicBottomSheet.show<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: isLight ? Colors.white : const Color(0xFF000000),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(top: 4, bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TradeRepublicListTile(
                  leading: Icon(CupertinoIcons.arrow_right_circle_fill),
                  title: AppLocalizations.of(context)!.tr('Open Tab') ?? AppLocalizations.of(context)!.tr('Open Tab'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _activeDesktopTab = tabIndex;
                      _currentIndex = page;
                    });
                    _pageController?.jumpToPage(page);
                  }),
                TradeRepublicListTile(
                  leading: Icon(CupertinoIcons.rectangle_split_3x1),
                  title: AppLocalizations.of(context)!.tr('Split Left') ?? AppLocalizations.of(context)!.tr('Split Left'),
                  onTap: () {
                    Navigator.pop(context);
                    final partner = _firstOtherDesktopTabIndex(tabIndex);
                    if (partner == -1) return;
                    setState(() {
                      _isDesktopSplitView = true;
                      _desktopSplitLeftTab = tabIndex;
                      _desktopSplitRightTab = partner;
                      _desktopSplitRatio = 0.5;
                    });
                  }),
                TradeRepublicListTile(
                  leading: Icon(CupertinoIcons.rectangle_split_3x1_fill),
                  title: AppLocalizations.of(context)!.tr('Split Right') ?? AppLocalizations.of(context)!.tr('Split Right'),
                  onTap: () {
                    Navigator.pop(context);
                    final partner = _firstOtherDesktopTabIndex(tabIndex);
                    if (partner == -1) return;
                    setState(() {
                      _isDesktopSplitView = true;
                      _desktopSplitLeftTab = partner;
                      _desktopSplitRightTab = tabIndex;
                      _desktopSplitRatio = 0.5;
                    });
                  }),
                if (_isDesktopSplitView)
                  TradeRepublicListTile(
                    leading: Icon(CupertinoIcons.rectangle),
                    title: AppLocalizations.of(context)!.tr('Exit Split Screen') ?? AppLocalizations.of(context)!.tr('Exit Split Screen'),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _isDesktopSplitView = false);
                    }),
                if (_desktopTabPages.length > 1)
                  TradeRepublicListTile.destructive(
                    leading: Icon(CupertinoIcons.xmark_circle_fill),
                    title: AppLocalizations.of(context)!.tr('Close Tab') ?? AppLocalizations.of(context)!.tr('Close Tab'),
                    onTap: () {
                      Navigator.pop(context);
                      _closeDesktopTab(tabIndex);
                    }),
              ])))));
  }

  Widget _buildDesktopTabChip({
    required int tabIndex,
    required bool isLight,
    required bool isSelected,
    required bool isInSplit,
    required bool highlightDrop,
  }) {
    final pageIndex = _desktopTabPages[tabIndex].clamp(0, 4);
    final tabLabel = _getDesktopTabLabel(pageIndex);
    final tabIcon = _getDesktopTabIcon(pageIndex);

    final fg = isSelected
        ? (isLight ? Colors.white : Colors.black)
        : (isLight ? Colors.black.withOpacity(0.75) : Colors.white.withOpacity(0.75));

    return TradeRepublicTap(
      onTap: () {
        _openDesktopTab(tabIndex);
      },
      onDoubleTap: () {
        _openDesktopTab(tabIndex);
        _showDesktopTabActions(tabIndex, isLight);
      },
      onSecondaryTapDown: (_) {
        _openDesktopTab(tabIndex);
        _showDesktopTabActions(tabIndex, isLight);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: highlightDrop
              ? (isLight ? Colors.black : Colors.white).withOpacity(0.18)
              : isSelected
                  ? (isLight ? Colors.black : Colors.white)
                  : (isLight ? Colors.black : Colors.white).withOpacity(0.05),
          borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isInSplit ? CupertinoIcons.rectangle_split_3x1_fill : tabIcon,
              size: 14,
              color: fg),
            SizedBox(width: 8),
            Text(
              tabLabel,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
            if (_desktopTabPages.length > 1) ...[
              SizedBox(width: 8),
              TradeRepublicTap(
                onTap: () => _closeDesktopTab(tabIndex),
                child: Icon(CupertinoIcons.xmark, size: 12, color: fg)),
            ],
          ])));
  }

  Widget _buildDesktopTopTabBar(bool isLight) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_desktopTabPages.length, (i) {
                  final isSelected = _activeDesktopTab == i;
                  final isInSplit = _isDesktopSplitView &&
                      (i == _desktopSplitLeftTab || i == _desktopSplitRightTab);

                  return Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: DragTarget<int>(
                      onWillAcceptWithDetails: (details) => details.data != i,
                      onAcceptWithDetails: (details) => _startDesktopSplit(details.data, i),
                      builder: (context, candidateData, rejectedData) {
                        return LongPressDraggable<int>(
                          data: i,
                          feedback: Material(
                            color: Colors.transparent,
                            child: _buildDesktopTabChip(
                              tabIndex: i,
                              isLight: isLight,
                              isSelected: true,
                              isInSplit: isInSplit,
                              highlightDrop: false)),
                          childWhenDragging: Opacity(
                            opacity: 0.45,
                            child: _buildDesktopTabChip(
                              tabIndex: i,
                              isLight: isLight,
                              isSelected: isSelected,
                              isInSplit: isInSplit,
                              highlightDrop: false)),
                          child: _buildDesktopTabChip(
                            tabIndex: i,
                            isLight: isLight,
                            isSelected: isSelected,
                            isInSplit: isInSplit,
                            highlightDrop: candidateData.isNotEmpty));
                      }));
                })))),
          if (_isDesktopSplitView)
            Container(
              margin: EdgeInsets.only(right: 10),
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10)),
              child: Text(
                'Split',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white))),
          TradeRepublicButton.icon(
            icon: Icon(
              CupertinoIcons.add,
              size: 18,
              color: isLight ? Colors.black : Colors.white),
            size: 38,
            isSecondary: true,
            onPressed: () {
              setState(() {
                _desktopTabPages.add(_currentIndex);
                _activeDesktopTab = _desktopTabPages.length - 1;
              });
            }),
        ]));
  }

  Widget _buildDesktopSplitView(bool isLight) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 12.0;
        final availableWidth = constraints.maxWidth - dividerWidth;
        final leftWidth = availableWidth * _desktopSplitRatio;
        final rightWidth = availableWidth - leftWidth;

        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: _buildDesktopPageByIndex(_desktopTabPages[_desktopSplitLeftTab])),
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: TradeRepublicTap(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final ratio = (_desktopSplitRatio + (details.delta.dx / constraints.maxWidth))
                      .clamp(0.25, 0.75);
                  setState(() => _desktopSplitRatio = ratio);
                },
                child: Container(
                  width: dividerWidth,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 72,
                      decoration: BoxDecoration(
                        color: isLight
                            ? Colors.black.withOpacity(0.16)
                            : Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999))))))),
            SizedBox(
              width: rightWidth,
              child: _buildDesktopPageByIndex(_desktopTabPages[_desktopSplitRightTab])),
          ]);
      });
  }

  Future<void> _loadUserData() async {
    print('🎬 _loadUserData() START');
    try {
      // Get auth token and username from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      // ✅ Use 'auth_token' (snake_case) — matches AppSettings._keyAuthToken
      final token = prefs.getString('auth_token');

      print('🔍 SharedPreferences keys: ${prefs.getKeys()}');
      print(
        '🔑 auth_token: ${token != null ? "Found (${token.length} chars)" : "NULL"}');

      final tokenUsername = AppSettings.extractUsernameFromToken(token);
      if (tokenUsername != null) {
        print('✅ Username decoded from token: $tokenUsername');
        await prefs.setString('username', tokenUsername);
      }

      // Always prefer business token username, then stored username, then safe fallbacks
      var username =
          tokenUsername ??
          AppSettings.sanitizeUsername(prefs.getString('username'));
      print('👤 username from SharedPreferences: $username');

      if (username == null || username.isEmpty) {
        print('⚠️ Username is null/empty, checking AppSettings...');
        // Fallback to AppSettings
        final appSettings = Provider.of<AppSettings>(context, listen: false);
        username =
            AppSettings.sanitizeUsername(appSettings.userName) ??
            AppSettings.sanitizeUsername(appSettings.userId);
        print('⚠️ Using AppSettings username as fallback: $username');
      } else {
        print('✅ Using stored username from SharedPreferences: $username');
      }

      if (username == null || username.isEmpty) {
        print(
          '❌ CRITICAL: No username found in SharedPreferences or AppSettings');
        print('❌ Cannot load profile without username!');
        return;
      }

      print('📡 Loading business user data for: $username');

      print(
        '🔑 Auth token found: ${token != null ? 'YES (${token.length} chars)' : 'NO'}');

      if (token == null || token.isEmpty) {
        print('⚠️ No auth token found - trying without token');
        // Try without token for debugging
      }

      // Load user data with username parameter and auth token
      final url =
          '${ApiConfig.baseUrl}/api/business/profile?username=$username';

      print('🌐 Making request to: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: token != null
            ? {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              }
            : {'Content-Type': 'application/json'});

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        print('✅ Parsed response data: $data');

        if (mounted) {
          setState(() {
            userData = data;
          });
          print('✅ Business user data loaded: ${data['profilePic']}');
          print('🔄 setState called - userData updated');
        } else {
          print('⚠️ Widget not mounted - skipping setState');
        }
      } else {
        print('❌ HTTP error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
    }
  }

  String _getImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';

    // Replace localhost with actual IP address
    if (imageUrl.contains('localhost')) {
      imageUrl = imageUrl.replaceAll('localhost', '192.168.0.118');
    }

    if (imageUrl.startsWith('http')) {
      return imageUrl;
    }

    return '${ApiConfig.baseUrl}$imageUrl';
  }

  Widget _buildCustomDock(bool isLight) {
    return Container(
      height: 60,
      decoration: BoxDecoration(color: isLight ? Colors.white : Colors.black),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildDockItem(0, isLight, CupertinoIcons.home, Icons.home, AppLocalizations.of(context)?.homeNav ?? AppLocalizations.of(context)!.tr('Home')),
          _buildDockItem(
            1,
            isLight,
            CupertinoIcons.cube_box,
            CupertinoIcons.cube_box_fill,
            AppLocalizations.of(context)?.products ?? AppLocalizations.of(context)!.tr('Products')),
          _buildDockItem(
            2,
            isLight,
            CupertinoIcons.doc_text,
            Icons.receipt_long,
            AppLocalizations.of(context)?.orders ?? AppLocalizations.of(context)!.tr('Orders')),
          _buildDockItem(
            3,
            isLight,
            CupertinoIcons.chat_bubble_fill,
            Icons.message,
            AppLocalizations.of(context)?.messages ?? AppLocalizations.of(context)!.tr('Messages')),
          _buildDockItem(
            4,
            isLight,
            CupertinoIcons.person,
            CupertinoIcons.person_fill,
            AppLocalizations.of(context)?.account ?? AppLocalizations.of(context)!.tr('Account')),
        ]));
  }

  Widget _buildDockItem(
    int index,
    bool isLight,
    IconData inactiveIcon,
    IconData activeIcon,
    String label) {
    final isSelected = _currentIndex == index;

    return Expanded(
      child: TradeRepublicTap(
        onTap: () => _onBottomNavTapped(index),
        child: Container(
          height: 60,
          color: Colors.transparent,
          child: Center(
            child: Icon(
              isSelected ? activeIcon : inactiveIcon,
              size: 22,
              color: isSelected
                  ? (isLight ? Colors.black : Colors.white)
                  : (isLight ? Colors.black : Colors.white).withOpacity(0.4))))));
  }

  @override
  Widget build(BuildContext context) {
    final isLight = _appSettings.isLightMode(context);

    // Use Sidebar on macOS and Windows, Bottom Navigation on mobile platforms
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return _buildMacOSSidebarInterface(isLight);
    }

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Stack(
        children: [
          // Full-screen page view
          PageView(
            controller: _pageController,
            physics: const AlwaysScrollableScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            children: const [
              BusinessHomePage(),
              ProductsPage(),
              OrdersPage(),
              MessengerPage(),
              BusinessAccountPage(),
            ]),

          // Floating page indicator - centered at the bottom
          ValueListenableBuilder<bool>(
            valueListenable: NavigationVisibility.isVisible,
            builder: (context, isNavigationVisible, _) {
              final bottomInset = MediaQuery.of(context).padding.bottom;
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                bottom: isNavigationVisible
                    ? bottomInset - 4
                    : -(64 + bottomInset),
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: isNavigationVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeInOut,
                  child: Center(
                    child: _pageController != null
                        ? PageIndicator(
                            currentPage: _currentIndex,
                            pageCount: 5,
                            pageController: _pageController!)
                        : const SizedBox.shrink())));
            }),
        ]));
  }

  // macOS/Windows Sidebar Interface - Trade Republic Minimalist Design
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
              color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
              border: Border(
                right: BorderSide(
                  color: CultiooDesktopLayout.hairlineColor(context),
                  width: CultiooDesktopLayout.hairlineWidth))),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo Section - Animated with scale and fade
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      showLabels ? 22 : 14, 24, showLabels ? 22 : 14, 20),
                    child: _logoAnimationController != null
                        ? AnimatedBuilder(
                            animation: _logoAnimationController!,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _logoScaleAnimation?.value ?? 1.0,
                                child: Opacity(
                                  opacity: _logoFadeAnimation?.value ?? 1.0,
                                  child: child));
                            },
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
                                        fit: BoxFit.contain)
                                    : Image.asset(
                                        'logo/cultioo_logo.png',
                                        key: const ValueKey('leaf_logo'),
                                        height: 48,
                                        fit: BoxFit.contain,
                                        color: isLight ? Colors.black : Colors.white))))
                        : AnimatedContainer(
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
                                      fit: BoxFit.contain)
                                  : Image.asset(
                                      'logo/cultioo_logo.png',
                                      key: const ValueKey('leaf_logo'),
                                      height: 48,
                                      fit: BoxFit.contain,
                                      color: isLight ? Colors.black : Colors.white)))),

                  // Navigation Items - Trade Republic Style with stagger animation
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        showLabels ? 14 : 10,
                        8,
                        showLabels ? 14 : 10,
                        16),
                      children: [
                        _buildAnimatedSidebarItem(
                          0,
                          isLight,
                          CupertinoIcons.home,
                          CupertinoIcons.house_fill,
                          AppLocalizations.of(context)?.home ?? AppLocalizations.of(context)!.tr('Home'),
                          0),
                        _buildAnimatedSidebarItem(
                          1,
                          isLight,
                          CupertinoIcons.cube_box,
                          CupertinoIcons.cube_box_fill,
                          AppLocalizations.of(context)?.products ?? AppLocalizations.of(context)!.tr('Products'),
                          1),
                        _buildAnimatedSidebarItem(
                          2,
                          isLight,
                          CupertinoIcons.doc_text,
                          CupertinoIcons.doc_text_fill,
                          AppLocalizations.of(context)?.orders ?? AppLocalizations.of(context)!.tr('Orders'),
                          2),
                        _buildAnimatedSidebarItem(
                          3,
                          isLight,
                          CupertinoIcons.chat_bubble,
                          CupertinoIcons.chat_bubble_fill,
                          AppLocalizations.of(context)?.messages ?? AppLocalizations.of(context)!.tr('Messages'),
                          3),
                        _buildAnimatedSidebarItem(
                          4,
                          isLight,
                          CupertinoIcons.person,
                          CupertinoIcons.person_fill,
                          AppLocalizations.of(context)?.account ?? AppLocalizations.of(context)!.tr('Account'),
                          4),
                      ])),

                  // Profile Section - Trade Republic minimal bottom
                  if (showLabels)
                    Container(
                      margin: EdgeInsets.all(12),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isLight ? Colors.white : const Color(0xFF000000),
                        border: Border.all(
                          color: isLight
                              ? Colors.black.withOpacity(0.06)
                              : Colors.white.withOpacity(0.08)),
                        borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          // Profile Image
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: isLight ? Colors.black : Colors.white,
                              borderRadius: BorderRadius.circular(17)),
                            child: Builder(
                              builder: (context) {
                                final fallbackLetter = (appSettings.userName?.isNotEmpty == true)
                                    ? appSettings.userName!.substring(0, 1).toUpperCase()
                                    : 'B';
                                final fallbackWidget = Center(
                                  child: Text(
                                    fallbackLetter,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isLight ? Colors.white : Colors.black)));
                                final rawUrl = userData?['profilePic']?.toString() ?? AppLocalizations.of(context)!.tr('');
                                if (rawUrl.isEmpty || rawUrl.startsWith('<svg')) {
                                  return fallbackWidget;
                                }
                                // base64 data: URL (uploaded via web)
                                if (rawUrl.startsWith('data:image')) {
                                  try {
                                    final bytes = base64Decode(rawUrl.split(',').last);
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: Image.memory(
                                        bytes,
                                        width: 40, height: 40, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => fallbackWidget));
                                  } catch (_) {
                                    return fallbackWidget;
                                  }
                                }
                                // Regular http/https or server-relative URL
                                final fullUrl = _getImageUrl(rawUrl);
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Image.network(
                                    fullUrl,
                                    width: 40, height: 40, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => fallbackWidget));
                              })),
                          SizedBox(width: 12),
                          // Name
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '@${userData?['userName'] ?? appSettings.userName ?? AppLocalizations.of(context)!.tr('Business')}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? Colors.black : Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                                SizedBox(height: 2),
                                Text(
                                  (userData?['businessName'] as String?)?.isNotEmpty == true
                                      ? userData!['businessName'] as String
                                      : AppLocalizations.of(context)?.business ?? AppLocalizations.of(context)!.tr('Business'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: isLight
                                        ? Colors.black.withOpacity(0.5)
                                        : Colors.white.withOpacity(0.5)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              ])),
                          Icon(
                            CupertinoIcons.chevron_right,
                            size: 14,
                            color: isLight
                                ? Colors.black.withOpacity(0.3)
                                : Colors.white.withOpacity(0.3)),
                        ])),
                ]))),

          // Draggable Resize Handle
          _buildSidebarResizeHandle(isLight),

          // Main Content Area - Trade Republic clean
          Expanded(
            child: Container(
              color: isLight ? Colors.white : Colors.black,
              child: Column(
                children: [
                  _buildDesktopTopTabBar(isLight),
                  Expanded(
                    child: _isDesktopSplitView &&
                            _desktopSplitLeftTab < _desktopTabPages.length &&
                            _desktopSplitRightTab < _desktopTabPages.length &&
                            _desktopSplitLeftTab != _desktopSplitRightTab
                        ? _buildDesktopSplitView(isLight)
                        : PageView(
                            controller: _pageController,
                            physics: const NeverScrollableScrollPhysics(),
                            onPageChanged: (index) {
                              setState(() {
                                _currentIndex = index;
                                if (_activeDesktopTab >= 0 &&
                                    _activeDesktopTab < _desktopTabPages.length) {
                                  _desktopTabPages[_activeDesktopTab] = index;
                                }
                              });
                            },
                            children: const [
                              BusinessHomePage(),
                              ProductsPage(),
                              OrdersPage(),
                              MessengerPage(),
                              BusinessAccountPage(),
                            ])),
                ]))),
          // Right desktop panel host for stacked bottom sheets.
          Padding(
            padding: EdgeInsets.only(
              right: MediaQuery.paddingOf(context).right),
            child: CultiooDesktopSheetNavigator.buildPanelHost(
              width: _desktopRightPanelWidth(context),
              isDark: !isLight)),
        ]));
  }

  double _desktopRightPanelWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return (w * 0.40).clamp(520.0, 680.0);
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
                borderRadius: BorderRadius.circular(2)))))));
  }

  Widget _buildAnimatedSidebarItem(
    int index,
    bool isLight,
    IconData inactiveIcon,
    IconData activeIcon,
    String label,
    int animationIndex) {
    // Calculate stagger delay based on index
    final double startInterval = animationIndex * 0.1;
    final double endInterval = startInterval + 0.4;

    // If animation controller not ready, return static item
    if (_sidebarItemsController == null) {
      return _buildSidebarItem(index, isLight, inactiveIcon, activeIcon, label);
    }

    return AnimatedBuilder(
      animation: _sidebarItemsController!,
      builder: (context, child) {
        final curvedValue = Curves.easeOutCubic.transform(
          (((_sidebarItemsController!.value - startInterval) /
                  (endInterval - startInterval))
              .clamp(0.0, 1.0)));
        return Transform.translate(
          offset: Offset(-20 * (1 - curvedValue), 0),
          child: Opacity(opacity: curvedValue, child: child));
      },
      child: _buildSidebarItem(index, isLight, inactiveIcon, activeIcon, label));
  }

  Widget _buildSidebarItem(
    int index,
    bool isLight,
    IconData inactiveIcon,
    IconData activeIcon,
    String label) {
    final isSelected = _currentIndex == index;
    final showLabels = _sidebarWidth > 140;
    final selBg = TradeRepublicTheme.selectionContainerBackground(context);
    final selFg = TradeRepublicTheme.selectionContainerForeground(context);
    final muted = isLight
        ? Colors.black.withOpacity(0.62)
        : Colors.white.withOpacity(0.72);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: TradeRepublicTap(
          onTap: () {
            _onBottomNavTapped(index);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: showLabels
                ? EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                : EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? selBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment:
                  showLabels ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isSelected ? activeIcon : inactiveIcon,
                    key: ValueKey(isSelected),
                    size: 20,
                    color: isSelected ? selFg : muted)),
                if (showLabels) ...[
                  SizedBox(width: 8),
                  Flexible(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: showLabels ? 1.0 : 0.0,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? selFg : muted),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1))),
                ],
              ])))));
  }
}