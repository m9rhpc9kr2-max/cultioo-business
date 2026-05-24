import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import '../../../shared/services/app_settings.dart';
import '../../../config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_card.dart';
import '../../../shared/widgets/trade_republic_section_header.dart';
import '../../../shared/widgets/trade_republic_list_tile.dart';
import '../../../shared/widgets/trade_republic_divider.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../shared/widgets/trade_republic_bar_chart.dart' show TradeRepublicBarChart, TradeRepublicPeriodSegmented;
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

class BusinessHomePage extends StatefulWidget {
  const BusinessHomePage({super.key});

  @override
  State<BusinessHomePage> createState() => _BusinessHomePageState();
}

class _BusinessHomePageState extends State<BusinessHomePage>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  bool isLoading = true;
  Map<String, dynamic> businessStats = {};
  List<Map<String, dynamic>> topProducts = [];
  String selectedPeriod = 'all-time';
  bool _isInitialLoad = true;
  String _selectedChartPeriod = '';
  final List<double> _chartData = [];

  // Modern Animation Controllers - Delvioo Style
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late Animation<double> _headerSlideAnim;
  late Animation<double> _headerFadeAnim;

  @override
  void initState() {
    super.initState();
    // Initialize chart period after localization is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _selectedChartPeriod = AppLocalizations.of(context)?.sevenDays ?? AppLocalizations.of(context)!.tr('7 Days');
        });
      }
    });

    // Initialize modern animation controllers
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

    _loadDashboardData();
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    _contentAnimController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<String?> _getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('auth_token');

    return token;
  }

  Future<void> _loadDashboardData() async {
    print('📊 Loading dashboard data for period: $selectedPeriod...');
    if (_isInitialLoad) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final token = await _getStoredToken();

      // Convert selected period to API parameters
      String? startDate;
      String? endDate;
      final now = DateTime.now();

      switch (selectedPeriod) {
        case 'this-month':
          startDate = DateTime(now.year, now.month, 1).toIso8601String();
          endDate = DateTime(
            now.year,
            now.month + 1,
            0,
            23,
            59,
            59,
          ).toIso8601String();
          break;
        case 'last-month':
          final lastMonth = DateTime(now.year, now.month - 1, 1);
          startDate = lastMonth.toIso8601String();
          endDate = DateTime(
            lastMonth.year,
            lastMonth.month + 1,
            0,
            23,
            59,
            59,
          ).toIso8601String();
          break;
        case 'last-3-months':
          startDate = DateTime(now.year, now.month - 3, 1).toIso8601String();
          endDate = now.toIso8601String();
          break;
        case 'this-year':
          startDate = DateTime(now.year, 1, 1).toIso8601String();
          endDate = DateTime(now.year, 12, 31, 23, 59, 59).toIso8601String();
          break;
        case 'last-year':
          startDate = DateTime(now.year - 1, 1, 1).toIso8601String();
          endDate = DateTime(
            now.year - 1,
            12,
            31,
            23,
            59,
            59,
          ).toIso8601String();
          break;
        case 'all-time':
        default:
          // No date filter for "All Time"
          break;
      }

      // Build URL with optional date parameters
      String statsUrl = '${ApiConfig.baseUrl}/api/business/stats';
      if (startDate != null && endDate != null) {
        statsUrl += '?startDate=$startDate&endDate=$endDate';
      }

      // Prepare headers once and reuse
      final Map<String, String> headers = {'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      // Run all 3 requests in parallel for 3x faster loading
      final responses = await Future.wait([
        http.get(Uri.parse(statsUrl), headers: headers),
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/business/followers'),
          headers: headers,
        ),
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/business/products/top'),
          headers: headers,
        ),
      ]);

      final statsResponse = responses[0];
      final followersResponse = responses[1];
      final productsResponse = responses[2];

      // Check for auth errors in any response
      if (statsResponse.statusCode == 401 ||
          statsResponse.statusCode == 403 ||
          followersResponse.statusCode == 401 ||
          followersResponse.statusCode == 403 ||
          productsResponse.statusCode == 401 ||
          productsResponse.statusCode == 403) {
        await _handleUnauthorized();
        setState(() {
          isLoading = false;
          _isInitialLoad = false;
        });
        return;
      }

      // Process stats response
      print('📊 Stats response: ${statsResponse.statusCode}');
      if (statsResponse.statusCode == 200) {
        final statsData = json.decode(statsResponse.body);
        if (statsData['success'] == true) {
          final stats = statsData['stats'] ?? {};
          businessStats = {
            'total_revenue': (stats['totalRevenue'] ?? 0.0).toDouble(),
            'total_orders': stats['totalOrders'] ?? 0,
            'followers_count': stats['followersCount'] ?? 0,
            'total_views': stats['totalViews'] ?? 0,
          };
        }
      }

      // Process followers response
      print('👥 Followers response: ${followersResponse.statusCode}');
      if (followersResponse.statusCode == 200) {
        final followersData = json.decode(followersResponse.body);
        if (followersData['success'] == true &&
            followersData['stats'] != null) {
          final followersCount =
              followersData['stats']['followers_count'] ??
              businessStats['followers_count'] ??
              0;
          businessStats['followers_count'] = followersCount;
          print('👥 Followers count updated: $followersCount');
        }
      }

      // Process top products response
      print('🏆 Top products response: ${productsResponse.statusCode}');
      if (productsResponse.statusCode == 200) {
        final productsData = json.decode(productsResponse.body);
        print('🏆 Top products data: ${productsData['data']}');
        topProducts = List<Map<String, dynamic>>.from(
          productsData['data'] ?? [],
        );
        print('🏆 Loaded ${topProducts.length} top products');
      }

      setState(() {
        isLoading = false;
        _isInitialLoad = false;
      });
    } catch (e) {
      print('❌ Error loading dashboard data: $e');
      setState(() {
        isLoading = false;
        _isInitialLoad = false;
        // Fallback data
        businessStats = {
          'total_revenue': 0.0,
          'total_orders': 0,
          'followers_count': 0,
          'total_views': 0,
        };
      });
    }
  }

  // Handle expired/invalid token: clear stored token and inform user
  Future<void> _handleUnauthorized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    } catch (_) {}

    if (!mounted) return;

    TopNotification.error(
      context,
      AppLocalizations.of(context)?.sessionExpiredPleaseSignInAgain ?? AppLocalizations.of(context)!.tr('Session expired. Please sign in again.'),
    );
  }

  void _showPeriodSelectionModal(bool isLight) {
    final loc = AppLocalizations.of(context);

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle Bar - Trade Republic style
          const DragHandle(),

          Row(
            children: [
              Icon(
                CupertinoIcons.calendar,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  AppLocalizations.of(context)?.timePeriod ?? AppLocalizations.of(context)!.tr('Time Period'),
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

          // Period Options - Trade Republic style
          _buildPeriodOption(
            'all-time',
            loc?.allTime ?? AppLocalizations.of(context)!.tr('All Time'),
            Icons.all_inclusive,
            isLight,
          ),
          _buildPeriodOption(
            'this-month',
            loc?.thisMonth ?? AppLocalizations.of(context)!.tr('This Month'),
            CupertinoIcons.calendar,
            isLight,
          ),
          _buildPeriodOption(
            'last-month',
            loc?.lastMonth ?? AppLocalizations.of(context)!.tr('Last Month'),
            Icons.calendar_month,
            isLight,
          ),
          _buildPeriodOption(
            'last-3-months',
            loc?.lastThreeMonths ?? AppLocalizations.of(context)!.tr('Last 3 Months'),
            Icons.date_range,
            isLight,
          ),
          _buildPeriodOption(
            'this-year',
            loc?.thisYear ?? AppLocalizations.of(context)!.tr('This Year'),
            Icons.event_note,
            isLight,
          ),
          _buildPeriodOption(
            'last-year',
            loc?.lastYear ?? AppLocalizations.of(context)!.tr('Last Year'),
            Icons.history,
            isLight,
          ),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
        ],
      ),
    );
  }

  Widget _buildPeriodOption(
    String periodKey,
    String periodLabel,
    IconData icon,
    bool isLight,
  ) {
    final isSelected = selectedPeriod == periodKey;

    return TradeRepublicListTile(
      title: periodLabel,
      leading: Icon(icon, size: 22, color: isSelected ? Colors.blue : null),
      trailing: isSelected
          ? Icon(CupertinoIcons.checkmark, color: Colors.blue, size: 20)
          : null,
      titleColor: isSelected ? Colors.blue : null,
      onTap: () {
        setState(() {
          selectedPeriod = periodKey;
        });
        Navigator.pop(context);
        _loadDashboardData();
      },
    );
  }

  String _getPeriodLabel(String periodKey) {
    final loc = AppLocalizations.of(context);
    switch (periodKey) {
      case 'this-month':
        return loc?.thisMonth ?? AppLocalizations.of(context)!.tr('This Month');
      case 'last-month':
        return loc?.lastMonth ?? AppLocalizations.of(context)!.tr('Last Month');
      case 'last-3-months':
        return loc?.lastThreeMonths ?? AppLocalizations.of(context)!.tr('Last 3 Months');
      case 'this-year':
        return loc?.thisYear ?? AppLocalizations.of(context)!.tr('This Year');
      case 'last-year':
        return loc?.lastYear ?? AppLocalizations.of(context)!.tr('Last Year');
      case 'all-time':
      default:
        return loc?.allTime ?? AppLocalizations.of(context)!.tr('All Time');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);

    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final horizontalPadding = isDesktop ? 32.0 : 20.0;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: isLoading
          ? const Center(child: CultiooLoadingIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? 1080 : double.infinity,
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: isDesktop,
                  thickness: isDesktop ? 6 : null,
                  radius: const Radius.circular(4),
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      CultiooSliverRefreshControl(
                        onRefresh: _loadDashboardData,
                      ),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Trade Republic Style Header
                            _buildTradeRepublicHeader(
                              isLight,
                              isDesktop: isDesktop,
                            ),

                            // Revenue Summary - Large number
                            _buildRevenueSummary(isLight),

                            // Stats Grid
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                              ),
                              child: _buildStatsGrid(isLight),
                            ),
                            const SizedBox(height: 32),

                            // Top Products Section
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                              ),
                              child: _buildTopProductsSection(isLight),
                            ),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // Trade Republic Style Header - Simple, no glass effects
  Widget _buildTradeRepublicHeader(bool isLight, {bool isDesktop = false}) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final loc = AppLocalizations.of(context);
    final rawName = appSettings.userName ?? appSettings.userId ?? (loc?.businessUser ?? AppLocalizations.of(context)!.tr('Business User'));
    final username = rawName.startsWith('@') ? rawName : '@$rawName';

    final topPadding = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 32 : 20,
        isDesktop ? 28 : topPadding + 20,
        isDesktop ? 32 : 20,
        isDesktop ? 28 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc?.welcomeBack ?? AppLocalizations.of(context)!.tr('Welcome back,'),
            style: TextStyle(
              color: isLight
                  ? Colors.black.withOpacity(0.5)
                  : Colors.white.withOpacity(0.5),
              fontSize: isDesktop ? 16 : 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            username,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: isDesktop ? 40 : 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // Trade Republic Style Revenue Summary - Large number without container
  Widget _buildRevenueSummary(bool isLight) {
    final totalRevenue = businessStats['total_revenue'] ?? 0.0;
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large revenue number
          Text(
            appSettings.formatCurrency(totalRevenue),
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
            AppLocalizations.of(context)?.totalRevenue ?? AppLocalizations.of(context)!.tr('Total Revenue'),
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
            onTap: () => _showPeriodSelectionModal(isLight),
            boxShadow: const [],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.calendar,
                  color: isLight ? Colors.black : Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  _getPeriodLabel(selectedPeriod),
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.chevron_down,
                  color: isLight
                      ? Colors.black.withOpacity(0.4)
                      : Colors.white.withOpacity(0.4),
                  size: 14,
                ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildFloatingAppBar(bool isLight) {
    // BackdropFilter blur app bar
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: isLight
                ? Colors.white.withOpacity(0.3)
                : Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.square_grid_2x2,
                color: isLight ? Colors.black : Colors.white,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.dashboard ?? AppLocalizations.of(context)!.tr('Dashboard'),
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final loc = AppLocalizations.of(context);
    final rawName = appSettings.userName ?? appSettings.userId ?? (loc?.businessUser ?? AppLocalizations.of(context)!.tr('Business User'));
    final username = rawName.startsWith('@') ? rawName : '@$rawName';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc?.welcomeBack ?? AppLocalizations.of(context)!.tr('Welcome back,'),
          style: TextStyle(
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        Text(
          username,
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }

  Widget _buildRevenueCard(bool isLight) {
    final totalRevenue = businessStats['total_revenue'] ?? 0.0;
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    return TradeRepublicTap(
      onTap: () => _showPeriodSelectionModal(isLight),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue, Colors.blue[700]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: const Icon(
                    CupertinoIcons.money_dollar_circle,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _getPeriodLabel(selectedPeriod),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        CupertinoIcons.arrowtriangle_down_fill,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            Text(
              AppLocalizations.of(context)?.totalRevenue ?? AppLocalizations.of(context)!.tr('Total Revenue'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              appSettings.formatCurrency(totalRevenue),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
                letterSpacing: -1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(bool isLight) {
    final totalOrders = (businessStats['total_orders'] is int)
        ? businessStats['total_orders'] as int
        : int.tryParse(businessStats['total_orders']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ?? 0;
    final followersCount = (businessStats['followers_count'] is int)
        ? businessStats['followers_count'] as int
        : int.tryParse(businessStats['followers_count']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ??
              0;
    final totalViews = (businessStats['total_views'] is int)
        ? businessStats['total_views'] as int
        : int.tryParse(businessStats['total_views']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ?? 0;

    return Column(
      children: [
        // Stats in outlined card
        TradeRepublicCard(
          boxShadow: const [],
          padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding()),
          child: Column(
            children: [
              _buildStatRow(
                AppLocalizations.of(context)?.orders ?? AppLocalizations.of(context)!.tr('Orders'),
                totalOrders.toString(),
                CupertinoIcons.bag,
                isLight,
                onTap: () => _showChartModal(
                  AppLocalizations.of(context)?.orders ?? AppLocalizations.of(context)!.tr('Orders'),
                  totalOrders,
                  isLight,
                ),
              ),
              TradeRepublicDivider(
                color: isLight
                    ? Colors.black.withOpacity(0.06)
                    : Colors.white.withOpacity(0.06),
                height: 24,
              ),
              _buildStatRow(
                AppLocalizations.of(context)?.followers ?? AppLocalizations.of(context)!.tr('Followers'),
                followersCount.toString(),
                CupertinoIcons.person_2,
                isLight,
                onTap: () => _showChartModal(
                  AppLocalizations.of(context)?.followers ?? AppLocalizations.of(context)!.tr('Followers'),
                  followersCount,
                  isLight,
                ),
              ),
              TradeRepublicDivider(
                color: isLight
                    ? Colors.black.withOpacity(0.06)
                    : Colors.white.withOpacity(0.06),
                height: 24,
              ),
              _buildStatRow(
                AppLocalizations.of(context)?.productViews ?? AppLocalizations.of(context)!.tr('Product Views'),
                totalViews.toString(),
                CupertinoIcons.eye,
                isLight,
                onTap: () => _showChartModal(
                  AppLocalizations.of(context)?.productViews ?? AppLocalizations.of(context)!.tr('Product Views'),
                  totalViews,
                  isLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(
    String title,
    String value,
    IconData icon,
    bool isLight, {
    VoidCallback? onTap,
  }) {
    return TradeRepublicListTile(
      title: title,
      leading: Icon(icon, size: 20),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 4, fontWeight: FontWeight.w600),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chart_bar,
              size: 16,
              color: isLight
                  ? Colors.black.withOpacity(0.3)
                  : Colors.white.withOpacity(0.3),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  /// Maps localized period label → API period key
  String _periodLabelToApiKey(String label) {
    final loc = AppLocalizations.of(context);
    if (label == (loc?.twentyFourHours ?? '24 Hours')) return '24h';
    if (label == (loc?.sevenDays ?? '7 Days'))        return '7d';
    if (label == (loc?.oneMonth ?? '1 Month'))        return '1m';
    if (label == (loc?.sixMonths ?? '6 Months'))      return '6m';
    if (label == (loc?.oneYear ?? '1 Year'))          return '1y';
    return '7d';
  }

  /// Maps stat title → API metric key
  String _titleToMetric(String title) {
    final loc = AppLocalizations.of(context);
    if (title == (loc?.orders ?? 'Orders'))          return 'orders';
    if (title == (loc?.followers ?? 'Followers'))    return 'followers';
    return 'views';
  }

  Future<List<double>> _fetchChartData(String metric, String period) async {
    try {
      final token = await _getStoredToken();
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/business/analytics/chart?metric=$metric&period=$period',
      );
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == true && body['data'] is List) {
          return (body['data'] as List)
              .map((v) => (v as num).toDouble())
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  void _showChartModal(String title, int currentValue, bool isLight) {
    final metric = _titleToMetric(title);
    TradeRepublicBottomSheet.show(
      context: context,
      child: _ChartModalContent(
        title: title,
        currentValue: currentValue,
        isLight: isLight,
        metric: metric,
        initialPeriod: _selectedChartPeriod,
        fetchChartData: _fetchChartData,
        periodLabelToApiKey: _periodLabelToApiKey,
        onPeriodChanged: (p) => setState(() => _selectedChartPeriod = p),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isLight,
  }) {
    return TradeRepublicCard(
      padding: DesktopAppWrapper.getPagePadding(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
              letterSpacing: -1,
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Text(
            title,
            style: TextStyle(
              color: isLight
                  ? Colors.black.withOpacity(0.4)
                  : Colors.white.withOpacity(0.4),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
              letterSpacing: 0.5,
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
  }) {
    return TradeRepublicCard(
      width: double.infinity,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                    letterSpacing: -1,
                  ),
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                Text(
                  title,
                  style: TextStyle(
                    color: isLight
                        ? Colors.black.withOpacity(0.4)
                        : Colors.white.withOpacity(0.4),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.topProducts ?? AppLocalizations.of(context)!.tr('Top Products'),
          trailing: Text(
            '${topProducts.length} ${AppLocalizations.of(context)?.items ?? AppLocalizations.of(context)!.tr('items')}',
            style: TextStyle(
              color: isLight
                  ? Colors.black.withOpacity(0.4)
                  : Colors.white.withOpacity(0.4),
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        if (topProducts.isEmpty)
          _buildEmptyTopProducts(isLight)
        else
          TradeRepublicCard(
            boxShadow: const [],
            padding: EdgeInsets.zero,
            child: Column(
              children: topProducts.asMap().entries.map((entry) {
                final index = entry.key;
                final product = entry.value;
                return _buildTopProductRow(
                  product,
                  index + 1,
                  isLight,
                  index == topProducts.length - 1,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyTopProducts(bool isLight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: double.infinity),
          Icon(
            CupertinoIcons.cube_box,
            color: isLight
                ? Colors.black.withOpacity(0.15)
                : Colors.white.withOpacity(0.15),
            size: 48,
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Text(
            AppLocalizations.of(context)?.noProductsYet ?? AppLocalizations.of(context)!.tr('No Products Yet'),
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Text(
            AppLocalizations.of(context)?.addFirstProductToGetStarted ?? AppLocalizations.of(context)!.tr('Add your first product to get started'),
            style: TextStyle(
              color: isLight
                  ? Colors.black.withOpacity(0.5)
                  : Colors.white.withOpacity(0.5),
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  /// Safely decodes a base64 image string. Returns null on any error.
  Uint8List? _safeBase64Decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = raw.contains(',') ? raw.split(',')[1] : raw;
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  Widget _buildTopProductRow(
    Map<String, dynamic> product,
    int rank,
    bool isLight,
    bool isLast,
  ) {
    final views = product['views'] ?? 0;
    final imageUrl = product['imageUrl'];
    final title =
        product['title']?.toString() ??
        (AppLocalizations.of(context)?.unknownProduct ?? AppLocalizations.of(context)!.tr('Unknown Product'));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              // Rank number
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: isLight
                        ? Colors.black.withOpacity(0.4)
                        : Colors.white.withOpacity(0.4),
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Product Image - Square with rounded corners
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isLight
                      ? Colors.black.withOpacity(0.04)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  child: () {
                    final bytes = _safeBase64Decode(imageUrl?.toString());
                    if (bytes != null) {
                      return Image.memory(
                        bytes,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          CupertinoIcons.cube_box,
                          color: isLight
                              ? Colors.black.withOpacity(0.3)
                              : Colors.white.withOpacity(0.3),
                          size: 22,
                        ),
                      );
                    }
                    return Icon(
                      CupertinoIcons.cube_box,
                      color: isLight
                          ? Colors.black.withOpacity(0.3)
                          : Colors.white.withOpacity(0.3),
                      size: 22,
                    );
                  }(),
                ),
              ),
              const SizedBox(width: 14),
              // Product Info
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Views count
              Row(
                children: [
                  Icon(
                    CupertinoIcons.eye,
                    color: isLight
                        ? Colors.black.withOpacity(0.4)
                        : Colors.white.withOpacity(0.4),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$views',
                    style: TextStyle(
                      color: isLight
                          ? Colors.black.withOpacity(0.6)
                          : Colors.white.withOpacity(0.6),
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!isLast)
          TradeRepublicDivider(
            color: isLight
                ? Colors.black.withOpacity(0.06)
                : Colors.white.withOpacity(0.06),
            height: 1,
          ),
      ],
    );
  }

  Widget _buildTopProductCard(
    Map<String, dynamic> product,
    int rank,
    bool isLight,
  ) {
    final views = product['views'] ?? 0;
    // Handle price conversion safely - can be num or String from DB
    final dynamic priceValue = product['price'];
    double price = 0.0;
    if (priceValue is num) {
      price = priceValue.toDouble();
    } else if (priceValue is String) {
      price = double.tryParse(priceValue) ?? 0.0;
    }
    final imageUrl = product['imageUrl'];
    final title =
        product['title']?.toString() ??
        (AppLocalizations.of(context)?.unknownProduct ?? AppLocalizations.of(context)!.tr('Unknown Product'));

    // Medal colors for top 3
    Color? rankColor;
    if (rank == 1) rankColor = Colors.amber;
    if (rank == 2) {
      rankColor = (isLight ? Colors.black : Colors.white).withOpacity(0.4);
    }
    if (rank == 3) rankColor = Colors.orange[300];

    return TradeRepublicCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Rank Badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  rankColor?.withOpacity(0.2) ??
                  (isLight ? Colors.black : Colors.white).withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: rankColor ?? (isLight ? Colors.black : Colors.white),
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Product Image
          () {
            final bytes = _safeBase64Decode(imageUrl?.toString());
            if (bytes != null) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                child: Image.memory(
                  bytes,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Icon(
                      CupertinoIcons.photo_fill,
                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                    ),
                  ),
                ),
              );
            }
            return Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Icon(
                CupertinoIcons.photo_fill,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
              ),
            );
          }(),
          const SizedBox(width: 12),

          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  price > 0
                      ? Provider.of<AppSettings>(context, listen: false).formatCurrency(price)
                      : (AppLocalizations.of(context)?.priceNotSet ?? AppLocalizations.of(context)!.tr('Price not set')),
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),

          // Views Count (instead of price)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.eye_fill,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$views',
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)?.viewsLabel ?? AppLocalizations.of(context)!.tr('Views'),
                style: TextStyle(
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.5,
                  ),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartModalContent extends StatefulWidget {
  final String title;
  final int currentValue;
  final bool isLight;
  final String metric;
  final String initialPeriod;
  final Future<List<double>> Function(String metric, String period) fetchChartData;
  final String Function(String label) periodLabelToApiKey;
  final void Function(String period) onPeriodChanged;

  const _ChartModalContent({
    required this.title,
    required this.currentValue,
    required this.isLight,
    required this.metric,
    required this.initialPeriod,
    required this.fetchChartData,
    required this.periodLabelToApiKey,
    required this.onPeriodChanged,
  });

  @override
  State<_ChartModalContent> createState() => _ChartModalContentState();
}

class _ChartModalContentState extends State<_ChartModalContent> {
  late String _period;
  List<double> _data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final key = widget.periodLabelToApiKey(_period);
    final result = await widget.fetchChartData(widget.metric, key);
    if (mounted) setState(() { _data = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final accent = widget.isLight ? Colors.black : Colors.white;
    final dim = accent.withOpacity(0.45);
    const positive = Color(0xFF00C896);
    const negative = Color(0xFFFF3B30);

    double percentChange = 0.0;
    if (_data.length > 1) {
      final first = _data.firstWhere((v) => v > 0, orElse: () => 0);
      if (first > 0) percentChange = ((_data.last - first) / first) * 100;
    }
    final isPositive = percentChange >= 0;
    final trendColor = isPositive ? positive : negative;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DragHandle(),
          Text(
            widget.title.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: dim),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                widget.currentValue.toString(),
                style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.0, color: accent),
              ),
              const SizedBox(width: 10),
              if (!_loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive ? CupertinoIcons.arrow_up_right : CupertinoIcons.arrow_down_right,
                        size: 13, color: trendColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${percentChange.abs().toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: trendColor),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_period, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: dim, letterSpacing: -0.2)),
          const SizedBox(height: 28),
          SizedBox(
            height: 200,
            child: _loading
                ? Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: accent.withOpacity(0.4))))
                : _data.isEmpty
                    ? Center(child: Text('No data', style: TextStyle(color: dim, fontSize: 13)))
                    : TradeRepublicBarChart(data: _data, isLight: widget.isLight),
          ),
          const SizedBox(height: 20),
          TradeRepublicPeriodSegmented(
            isLight: widget.isLight,
            selected: _period,
            options: [
              loc?.twentyFourHours ?? '24 Hours',
              loc?.sevenDays ?? '7 Days',
              loc?.oneMonth ?? '1 Month',
              loc?.sixMonths ?? '6 Months',
              loc?.oneYear ?? '1 Year',
            ],
            onSelect: (p) {
              widget.onPeriodChanged(p);
              setState(() => _period = p);
              _load();
            },
          ),
        ],
      ),
    );
  }
}
