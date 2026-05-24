import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'main_navigation.dart';
import 'dart:async';
import 'dart:convert';
import '../../../shared/services/app_settings.dart';
import 'dart:ui';
import 'dart:io';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/services/biometric_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_card.dart';
import '../../../shared/widgets/trade_republic_section_header.dart';
import '../../../shared/widgets/trade_republic_swipe_action.dart';
import '../../../shared/widgets/trade_republic_slider.dart';
import '../../../shared/widgets/trade_republic_switch.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import '../../../shared/widgets/trade_republic_list_tile.dart';
import '../../../shared/widgets/trade_republic_divider.dart';
import '../../../shared/widgets/trade_republic_theme.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../utils/number_formatters.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import '../../../shared/widgets/payment_input_formatters.dart';
import '../../../shared/widgets/credit_card_widget.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

class BusinessAccountPage extends StatefulWidget {
  const BusinessAccountPage({super.key});

  @override
  State<BusinessAccountPage> createState() => _BusinessAccountPageState();

  // Static method to calculate verification status for use in other pages
  static bool hasCompleteBusinessProfile(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    final name = (userData['businessName'] ?? userData['companyName'] ?? '').toString().trim();
    final email = (userData['businessEmail'] ?? userData['email'] ?? '').toString().trim();
    final phone = (userData['businessPhone'] ?? userData['phone'] ?? '').toString().trim();
    final address = (userData['businessAddress'] ?? '').toString().trim();
    return name.isNotEmpty && email.isNotEmpty && phone.isNotEmpty && address.isNotEmpty;
  }

  static int calculateVerificationScore(Map<String, dynamic>? userData) {
    if (userData == null) return 0;

    int verificationScore = 0;

    // Business Profile complete (50% of score)
    if (hasCompleteBusinessProfile(userData)) {
      verificationScore += 50;
    }

    // Bank Account (50% of score)
    if (hasConnectedPaymentSetup(userData)) {
      verificationScore += 50;
    }

    return verificationScore;
  }

  static bool isFullyVerified(Map<String, dynamic>? userData) {
    return calculateVerificationScore(userData) >= 100;
  }

  static bool hasConnectedPaymentSetup(Map<String, dynamic>? userData) {
    if (userData == null) return false;

    final stripeCustomerId =
        (userData['stripeCustomerId'] ?? userData['stripe_customer_id'] ?? '')
            .toString()
            .trim();
    final stripeAccountId =
        (userData['stripeAccountId'] ?? userData['stripe_account_id'] ?? '')
            .toString()
            .trim();
    final iban = (userData['iban'] ?? '').toString().trim();
    final accountNumber = (userData['account_number'] ?? '').toString().trim();

    return stripeCustomerId.isNotEmpty ||
        stripeAccountId.isNotEmpty ||
        iban.isNotEmpty ||
        accountNumber.isNotEmpty;
  }
}

class _BusinessAccountPageState extends State<BusinessAccountPage>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  Map<String, dynamic>? userData;

  // Helper: true if any modal is open
  bool get _isAnyModalOpen =>
      _isAppSettingsOpen ||
      _isBusinessEditOpen ||
      _isPersonalEditOpen ||
      _isPaymentSettingsOpen ||
      _isSecuritySettingsOpen;

  // Modern Animation Controllers - Delvioo Style
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late Animation<double> _headerSlideAnim;
  late Animation<double> _headerFadeAnim;

  // Safe notification method that doesn't depend on context
  void _showSafeNotification(
    String message, {
    bool isError = false,
    bool isInfo = false,
  }) {
    if (mounted) {
      try {
        if (isError) {
          TopNotification.error(context, message);
        } else if (isInfo) {
          TopNotification.info(context, message);
        } else {
          TopNotification.success(context, message);
        }
      } catch (e) {
        debugPrint(isError ? '❌ $message' : (isInfo ? 'ℹ️ $message' : '✅ $message'));
      }
    } else {
      debugPrint('📱 $message (widget not mounted)');
    }
  }

  void _safePopIfPossible([BuildContext? ctx]) {
    final target = ctx ?? context;
    if (!mounted) return;
    final navigator = Navigator.of(target);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  bool isLoading = true;
  bool _isInitialLoad = true;
  bool _isAppSettingsOpen = false;
  bool _isBusinessEditOpen = false;
  bool _isPersonalEditOpen = false;
  bool _isPaymentSettingsOpen = false;
  bool _isSecuritySettingsOpen = false;
  bool _hasConnectedPaymentMethod = false;

  Map<String, dynamic> businessStats = {};
  List<Map<String, dynamic>> followers = [];
  Map<String, dynamic> socialStats = {
    'followers_count': 0,
    'following_count': 0,
  };
  Map<String, dynamic>? currentGroup;
  Map<String, dynamic> earningsData = {
    'totalEarnings': 0.0,
    'availableBalance': 0.0,
    'totalPayouts': 0.0,
    'totalWaitingCharges': 0.0,
    'lastUpdated': null,
  };
  Map<String, dynamic>? groupEarningsData; // Group earnings for owners
  List<Map<String, dynamic>> recentPayouts = [];
  List<Map<String, dynamic>> earningsHistory = [];
  List<Map<String, dynamic>> waitingChargeDeductions = [];

  // ── Monioo Wallet ──────────────────────────────────────────────────────────
  double _walletBalance = 0.0;
  List<Map<String, dynamic>> _walletTransactions = [];
  List<Map<String, dynamic>> _pendingShippingPayments = [];
  bool _walletLoaded = false;
  bool _pendingShippingLoaded = false;

  // ── Driver Payment Default ────────────────────────────────────────────────
  // 'card' = saved bank account/card, 'wallet' = Monioo Wallet
  String _defaultShippingPayment = 'wallet'; // default: Monioo Wallet
  List<Map<String, dynamic>> _savedPaymentMethodsCache = [];

  // Helper method to format currency with user's number format preference
  String _formatCurrency(double amount) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    return appSettings.formatCurrency(amount);
  }

  /// Tiered seller payout margin on available balance:
  /// below 100k → 1.5%, 100k-150k → 1.25%, above 150k → 1%, enterprise above 500k → 0.5%.
  double _sellerPayoutMarginRate(double availableBalance) {
    if (availableBalance > 500000) return 0.005;
    if (availableBalance >= 150000) return 0.01;
    if (availableBalance >= 100000) return 0.0125;
    return 0.015;
  }

  String _sellerPayoutMarginPercentLabel(double availableBalance) {
    final r = _sellerPayoutMarginRate(availableBalance);
    if (r <= 0.0050001) return '0.5% (enterprise)';
    if (r <= 0.0100001) return '1%';
    if (r <= 0.0125001) return '1.25%';
    return '1.5%';
  }

  // Helper method to format currency in USD
  String _formatUSD(double amount) {
    return formatCurrencyUsd(amount);
  }

  // Helper method to get scaled font size based on user's text size preference
  double _getScaledFontSize(double baseSize) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    return appSettings.getScaledFontSize(baseSize);
  }

  // Download payout invoice as PDF
  Future<void> _downloadPayoutInvoice(
    Map<String, dynamic> payout,
    bool isLight) async {
    final payoutId = payout['id']?.toString();
    if (payoutId == null) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.payoutIdNotFound ?? AppLocalizations.of(context)!.tr('Payout ID not found'));
      return;
    }

    // Get token from SharedPreferences
    final token = await _getStoredToken();
    if (token == null) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.authenticationRequired ?? AppLocalizations.of(context)!.tr('Authentication required'));
      return;
    }

    // Show loading indicator
    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CultiooLoadingIndicator(),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Text(
            AppLocalizations.of(context)?.downloadingInvoice ?? AppLocalizations.of(context)!.tr('Downloading invoice...'),
            style: TextStyle(color: isLight ? Colors.black : Colors.white)),
        ]));

    try {
      // Use Business invoice endpoint
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/business/payout/$payoutId/invoice'),
        headers: {'Authorization': 'Bearer $token'});

      // Close loading dialog
      _safePopIfPossible(context);

      if (response.statusCode == 200) {
        // Save PDF to temporary directory
        final directory = await getTemporaryDirectory();
        final fileName =
            'payout_invoice_${payoutId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final filePath = '${directory.path}/$fileName';

        // Write PDF bytes to file
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        // Open PDF directly
        await OpenFilex.open(filePath);
      } else {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.failedToDownloadInvoice ?? AppLocalizations.of(context)!.tr('Failed to download invoice')}: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      // Close loading dialog if still open
      _safePopIfPossible(context);

      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorDownloadingInvoice ?? AppLocalizations.of(context)!.tr('Error downloading invoice')}: $e');
    }
  }

  Future<void> _downloadWalletTransactionDocument(
    dynamic transactionId,
    bool isLight) async {
    final txId = transactionId?.toString();
    if (txId == null || txId.isEmpty) {
      TopNotification.error(context, AppLocalizations.of(context)!.tr('Transaction ID not found'));
      return;
    }

    final token = await _getStoredToken();
    if (token == null) {
      if (!mounted) return;
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.authenticationRequired ?? AppLocalizations.of(context)!.tr('Authentication required'));
      return;
    }

    if (!mounted) return;
    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CultiooLoadingIndicator(),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Text(
            AppLocalizations.of(context)?.downloadingInvoice ?? AppLocalizations.of(context)!.tr('Downloading document...'),
            style: TextStyle(color: isLight ? Colors.black : Colors.white)),
        ]));

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet/receipt/$txId'),
        headers: {'Authorization': 'Bearer $token'});

      if (!mounted) return;
      _safePopIfPossible(context);

      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath =
            '${directory.path}/wallet_document_${txId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        await OpenFilex.open(filePath);
      } else {
        TopNotification.error(
          context,
          'Failed to download document: ${response.statusCode}');
      }
    } catch (e) {
      _safePopIfPossible(context);
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)!.tr('Error downloading document')}: $e');
    }
  }

  // Helper widget for payout history item
  Widget _buildPayoutHistoryItem(Map<String, dynamic> payout, bool isLight) {
    final amount = payout['amount']?.toDouble() ?? 0.0;
    final status = payout['status']?.toString() ?? AppLocalizations.of(context)!.tr('unknown');
    final payoutDate =
        payout['payout_date']?.toString() ?? payout['created_at']?.toString();
    final errorMessage = payout['error_message']?.toString();
    final netAmount = payout['net_amount']?.toDouble() ?? amount;
    final deliveries = payout['total_deliveries']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final processedDate = payout['processed_date']?.toString();
    final completedDate = payout['completed_date']?.toString();
    final payoutId = payout['payout_id']?.toString() ?? AppLocalizations.of(context)!.tr('');

    // Format date and time
    String dateString = '';
    String timeString = '';
    String dateTimeSource = '';
    if (completedDate != null && completedDate.isNotEmpty) {
      dateTimeSource = completedDate;
    } else if (processedDate != null && processedDate.isNotEmpty) {
      dateTimeSource = processedDate;
    } else if (payoutDate != null && payoutDate.isNotEmpty) {
      dateTimeSource = payoutDate;
    }
    if (dateTimeSource.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateTimeSource);
        final appSettings = Provider.of<AppSettings>(context, listen: false);
        dateString = appSettings.formatDate(dt);
        timeString =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        dateString = dateTimeSource;
        timeString = '';
      }
    }

    // Status colors and gradients
    List<Color> statusGradient;
    IconData statusIcon;

    switch (status.toLowerCase()) {
      case 'completed':
        statusGradient = [Colors.green.shade400, Colors.green.shade600];
        statusIcon = CupertinoIcons.check_mark_circled_solid;
        break;
      case 'pending':
        statusGradient = [Colors.orange.shade400, Colors.orange.shade600];
        statusIcon = CupertinoIcons.clock_fill;
        break;
      case 'failed':
        statusGradient = [Colors.red.shade400, Colors.red.shade600];
        statusIcon = CupertinoIcons.exclamationmark_circle_fill;
        break;
      default:
        statusGradient = isLight
            ? [Colors.black, Colors.black]
            : [Colors.white, Colors.white];
        statusIcon = CupertinoIcons.question_circle;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status icon - KEEP gradient for important visual indicator
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: statusGradient),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Icon(
                  CupertinoIcons.money_dollar_circle,
                  color: Colors.white,
                  size: 24)),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatCurrency(netAmount),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        color: isLight ? Colors.black : Colors.white)),
                    SizedBox(height: 4),
                    if (deliveries.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.cube_box_fill,
                            size: 14,
                            color: isLight ? Colors.black : Colors.white),
                          SizedBox(width: 4),
                          Text(
                            '$deliveries ${AppLocalizations.of(context)?.deliveriesWord ?? AppLocalizations.of(context)!.tr('deliveries')}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isLight ? Colors.black : Colors.white)),
                        ]),
                  ])),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: statusGradient),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      status[0].toUpperCase() + status.substring(1),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.3)),
                  ])),
              // Download Invoice Button
              SizedBox(width: 8),
              TradeRepublicButton.icon(
                icon: Icon(CupertinoIcons.arrow_down_circle, size: 20),
                onPressed: () => _downloadPayoutInvoice(payout, isLight),
                backgroundColor: isLight ? Colors.black : Colors.white,
                foregroundColor: isLight ? Colors.white : Colors.black,
                size: 40),
            ]),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.calendar,
                      size: 16,
                      color: isLight ? Colors.black : Colors.white),
                    SizedBox(width: 8),
                    Text(
                      dateString,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isLight ? Colors.black : Colors.white)),
                    if (timeString.isNotEmpty) ...[
                      SizedBox(width: 12),
                      Icon(
                        CupertinoIcons.clock,
                        size: 16,
                        color: isLight ? Colors.black : Colors.white),
                      SizedBox(width: 6),
                      Text(
                        timeString,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white)),
                    ],
                  ]),
                if (payoutId.isNotEmpty) ...[
                  SizedBox(height: 10),
                  TradeRepublicDivider(
                    color: isLight ? Colors.black : Colors.white,
                    height: 1),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.tag_fill,
                        size: 14,
                        color: isLight ? Colors.black : Colors.white),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'ID: $payoutId',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white,
                            fontFamily: 'monospace'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                    ]),
                ],
              ])),
          if (errorMessage != null && errorMessage.isNotEmpty) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_circle,
                    color: Colors.red.shade700,
                    size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      errorMessage,
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.w600))),
                ])),
          ],
        ]));
  }

  @override
  void initState() {
    super.initState();

    // Initialize modern animation controllers - Delvioo Style
    _headerAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this);
    _headerSlideAnim = Tween<double>(begin: -30, end: 0).animate(
      CurvedAnimation(
        parent: _headerAnimController,
        curve: Curves.easeOutCubic));
    _headerFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut));

    _contentAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this);

    // Start header animation immediately
    _headerAnimController.forward();

    // Start content animation shortly after header
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _contentAnimController.forward();
      }
    });

    _loadUserData();
    _loadBusinessStats();
    _loadFollowers();
    _loadCurrentGroup();
    _loadEarningsData();
    _loadEarningsHistory();
    _loadWaitingChargeDeductions();
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
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    // Prefer the same token source used by Orders page first.
    // Some users still have an old/stale business_auth_token stored.
    String? token = prefs.getString('auth_token');
    token ??= prefs.getString('business_auth_token');
    token ??= prefs.getString('token');
    token ??= appSettings.authToken;

    if (token != null) {
      debugPrint(
        '🔑 Token retrieved: ${token.substring(0, 20)}... (length: ${token.length})');
    } else {
      debugPrint('⚠️ No token found in SharedPreferences');
    }

    return token;
  }

  Future<bool> _loadEarningsFromOrdersFallback(String token) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/business/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

      if (response.statusCode != 200) {
        return false;
      }

      final responseData = json.decode(response.body);
      if (responseData['success'] != true || responseData['orders'] == null) {
        return false;
      }

      final orders = List<Map<String, dynamic>>.from(responseData['orders']);
      final completedStatuses = {
        'paid',
        'bought',
        'confirmed',
        'completed',
        'delivered',
        'succeeded',
      };

      double totalEarnings = 0.0;
      for (final order in orders) {
        final status = (order['status'] ?? AppLocalizations.of(context)!.tr('')).toString().toLowerCase();
        if (!completedStatuses.contains(status)) continue;

        final rawAmount = order['amount'] ?? order['total_amount'] ?? 0;
        final amount = rawAmount is num
            ? rawAmount.toDouble()
            : double.tryParse(rawAmount.toString()) ?? 0.0;

        totalEarnings += amount;
      }

      if (!mounted) return true;

      setState(() {
        earningsData = {
          'totalEarnings': totalEarnings,
          'availableBalance': totalEarnings,
          'totalPayouts': 0.0,
          'totalWaitingCharges': 0.0,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        recentPayouts = [];
      });

      debugPrint(
        '✅ Earnings fallback loaded from orders: ${AppSettings().currencySymbol}${totalEarnings.toStringAsFixed(2)}');
      return true;
    } catch (e) {
      debugPrint('❌ Orders fallback failed: $e');
      return false;
    }
  }

  // Refresh expired token
  Future<String?> _refreshToken() async {
    try {
      debugPrint('🔄 Attempting to refresh token...');

      final prefs = await SharedPreferences.getInstance();
      final oldToken = prefs.getString('auth_token');
      final userId = userData?['username'] ?? prefs.getString('user_id');
      final userEmail = userData?['email'] ?? prefs.getString('user_email');

      if (userId == null && userEmail == null) {
        debugPrint('❌ No user credentials found for token refresh');
        return null;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/refresh-token'),
        headers: {
          'Content-Type': 'application/json',
          if (oldToken != null) 'Authorization': 'Bearer $oldToken',
        },
        body: json.encode({'userId': userId, 'email': userEmail}));

      debugPrint('🔄 Token refresh response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newToken = data['token'];

        if (newToken != null) {
          // Save new token
          await prefs.setString('auth_token', newToken);
          debugPrint('✅ Token refreshed successfully');
          return newToken;
        }
      }

      debugPrint('❌ Token refresh failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ Error refreshing token: $e');
      return null;
    }
  }

  String? _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      final date = DateTime.parse(dateString);
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      return appSettings.formatDate(date);
    } catch (e) {
      return null;
    }
  }

  // Helper method to ensure available balance is never negative
  double _getDisplayableBalance(dynamic balance) {
    double balanceValue = balance is String
        ? double.tryParse(balance) ?? 0.0
        : balance?.toDouble() ?? 0.0;

    // Return 0.0 if balance is negative (shows what can be paid out)
    return balanceValue < 0 ? 0.0 : balanceValue;
  }

  String _buildImageUrl(String imagePath) {
    debugPrint(
      '🖼️ _buildImageUrl called with: ${imagePath.startsWith('data:') ? 'data:...[base64]' : imagePath}');

    // Return data: URLs (base64) as-is – they are handled by _buildProfileImage
    if (imagePath.startsWith('data:')) {
      return imagePath;
    }

    // If imagePath is already a full URL (including GCS URLs), return it directly
    if (imagePath.contains('http://') || imagePath.contains('https://')) {
      debugPrint('🖼️ Using full URL directly: $imagePath');
      return imagePath;
    }

    final result = _buildImageUrlCandidates(imagePath).firstOrNull ??
        ApiConfig.getImageUrl(imagePath);
    debugPrint('🖼️ Final image URL: $result');
    return result;
  }

  List<String> _buildImageUrlCandidates(String imagePath) {
    if (imagePath.isEmpty) return const [];

    if (imagePath.startsWith('data:')) {
      return [imagePath];
    }

    final candidates = ApiConfig.getImageUrlCandidates(imagePath);
    debugPrint('🖼️ Image URL candidates for $imagePath: $candidates');
    return candidates;
  }

  /// Smart profile image widget: handles data:base64, SVG, and HTTP/HTTPS URLs.
  Widget _buildSmartProfileImage(
    String imagePath, {
    double size = 88,
    BoxFit fit = BoxFit.cover,
    bool isLight = true,
  }) {
    final fallbackIcon = Icon(
      CupertinoIcons.person_fill,
      size: size * 0.4,
      color: isLight ? Colors.black : Colors.white);

    if (imagePath.isEmpty) return fallbackIcon;

    // data: URL — decode base64 and render with Image.memory
    if (imagePath.startsWith('data:image')) {
      try {
        final base64Str = imagePath.split(',').last;
        final imageBytes = base64Decode(base64Str);
        return Image.memory(
          imageBytes,
          width: size,
          height: size,
          fit: fit,
          errorBuilder: (_, __, ___) => fallbackIcon);
      } catch (_) {
        return fallbackIcon;
      }
    }

    // SVG string — show fallback
    if (imagePath.startsWith('<svg')) return fallbackIcon;

    return _FallbackNetworkImage(
      imageUrls: _buildImageUrlCandidates(imagePath),
      width: size,
      height: size,
      fit: fit,
      fallback: fallbackIcon,
      loading: const Center(child: CultiooLoadingIndicator(size: 20)));
  }

  // Safe image widget that handles loading errors
  // Sometimes unused in certain build targets; ignore unused_element analyzer warning
  // ignore: unused_element
  Widget _buildSafeNetworkImage(
    String? imagePath, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? fallback,
    bool isLight = true,
  }) {
    if (imagePath == null || imagePath.isEmpty) {
      return fallback ??
          Container(color: isLight ? Colors.white : Colors.black);
    }

    // Check if it's SVG content
    if (imagePath.contains('<svg')) {
      return fallback ??
          Container(
            width: width,
            height: height,
            color: isLight ? Colors.white : Colors.black,
            child: Icon(
              CupertinoIcons.photo,
              color: isLight ? Colors.black : Colors.white));
    }

    // Handle data: base64 URLs
    if (imagePath.startsWith('data:image')) {
      try {
        final base64Str = imagePath.split(',').last;
        final imageBytes = base64Decode(base64Str);
        return Image.memory(
          imageBytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (ctx, err, st) =>
              fallback ??
              Container(color: isLight ? Colors.white : Colors.black));
      } catch (_) {
        return fallback ??
            Container(color: isLight ? Colors.white : Colors.black);
      }
    }

    return _FallbackNetworkImage(
      imageUrls: _buildImageUrlCandidates(imagePath),
      width: width,
      height: height,
      fit: fit,
      fallback: fallback ??
          Container(
            width: width,
            height: height,
            color: isLight ? Colors.white : Colors.black,
            child: Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: isLight ? Colors.black : Colors.white)),
      loading: Container(
        width: width,
        height: height,
        color: isLight ? Colors.white : Colors.black,
        child: Center(child: CultiooLoadingIndicator())));
  }

  String _normalizeGroupRole(dynamic role) {
    final value = role?.toString().trim().toLowerCase() ?? AppLocalizations.of(context)!.tr('member');
    if (value == 'owner' || value == 'admin') return 'admin';
    if (value == 'operator') return 'operator';
    return 'member';
  }

  bool _isGroupAdminRole(dynamic role) {
    return _normalizeGroupRole(role) == 'admin';
  }

  bool get _isCurrentGroupAdmin => _isGroupAdminRole(currentGroup?['role']);

  /// Validates a US ABA routing number using the official checksum algorithm.
  /// 3*(d1+d4+d7) + 7*(d2+d5+d8) + (d3+d6+d9) must be divisible by 10.
  bool _isValidABARoutingNumber(String routing) {
    if (routing.length != 9) return false;
    try {
      final d = routing.split('').map(int.parse).toList();
      final sum = 3 * (d[0] + d[3] + d[6]) +
                  7 * (d[1] + d[4] + d[7]) +
                      (d[2] + d[5] + d[8]);
      return sum != 0 && sum % 10 == 0;
    } catch (_) {
      return false;
    }
  }

  String _formatUsernameHandle(dynamic username) {
    final raw = (username ?? AppLocalizations.of(context)!.tr('')).toString().trim();
    if (raw.isEmpty) return '';
    return raw.startsWith('@') ? raw : '@$raw';
  }

  String _groupRoleHeadline(dynamic role) {
    switch (_normalizeGroupRole(role)) {
      case 'admin':
        return 'Group Admin';
      case 'operator':
        return 'Group Operator';
      default:
        return 'Group Member';
    }
  }

  String _groupRoleBadge(dynamic role) {
    switch (_normalizeGroupRole(role)) {
      case 'admin':
        return 'ADMIN';
      case 'operator':
        return 'OPERATOR';
      default:
        return 'MEMBER';
    }
  }

  Map<String, dynamic> _normalizeGroupPayload(Map<String, dynamic> group) {
    final normalized = Map<String, dynamic>.from(group);
    normalized['role'] = _normalizeGroupRole(normalized['role']);
    return normalized;
  }

  Map<String, dynamic> _normalizeGroupMember(Map<String, dynamic> member) {
    final normalized = Map<String, dynamic>.from(member);
    normalized['role'] = _normalizeGroupRole(normalized['role']);

    final firstName = (normalized['firstname'] ?? AppLocalizations.of(context)!.tr('')).toString().trim();
    final lastName = (normalized['lastname'] ?? AppLocalizations.of(context)!.tr('')).toString().trim();
    final fullName = [
      firstName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ').trim();
    final username = (normalized['username'] ?? normalized['userId'] ?? AppLocalizations.of(context)!.tr(''))
        .toString()
        .trim();

    normalized['name'] = fullName.isNotEmpty
        ? fullName
        : normalized['name']?.toString().trim().isNotEmpty == true
        ? normalized['name']
        : username;
    final resolvedProfileImage =
        (normalized['profilePic'] ?? normalized['profileImage'] ?? AppLocalizations.of(context)!.tr(''))
            .toString();
    normalized['profilePic'] = resolvedProfileImage;
    normalized['profileImage'] = resolvedProfileImage;
    normalized['username'] = username;
    return normalized;
  }

  Widget _buildGroupAvatar(
    String? imagePath, {
    required String label,
    required bool isLight,
    double size = 56,
    bool highlight = false,
  }) {
    final cleanImage = (imagePath ?? AppLocalizations.of(context)!.tr('')).trim();
    final initial = label.trim().isNotEmpty
        ? label.trim()[0].toUpperCase()
        : 'G';

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF111111)
            : (isLight ? const Color(0xFFF2F2F2) : const Color(0xFF1F1F1F)),
        borderRadius: BorderRadius.circular(size * 0.34)),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.32,
          fontWeight: FontWeight.w800,
          color: highlight
              ? Colors.white
              : (isLight ? Colors.black : Colors.white))));

    if (cleanImage.isEmpty || cleanImage.startsWith('<svg')) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.34),
      child: SizedBox(
        width: size,
        height: size,
        child: _buildSmartProfileImage(
          cleanImage,
          size: size,
          fit: BoxFit.cover,
          isLight: isLight)));
  }

  Future<void> _updateUserData(Map<String, dynamic> updatedData) async {
    try {
      debugPrint('📡 Updating user data in users table...');
      final token = await _getStoredToken();

      // Get user ID from AppSettings or userData
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      final userId =
          appSettings.userId ?? userData?['username'] ?? userData?['email'];

      if (userId == null) {
        throw Exception('User ID not found');
      }

      // Include userId in the update data
      final requestData = {'userId': userId, ...updatedData};

      debugPrint('📡 Request data: ${json.encode(requestData)}');

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/business/profile'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode(requestData));

      debugPrint('📡 Update profile response: ${response.statusCode}');
      debugPrint('📡 Update profile response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          // Update local user data with the response
          if (mounted) {
            setState(() {
              userData = {...userData!, ...updatedData};
            });
          }
          debugPrint('✅ User data updated successfully in users table');
          TopNotification.success(
            context,
            AppLocalizations.of(context)?.profileUpdatedSuccess ?? AppLocalizations.of(context)!.tr('Profile updated successfully!'));
        } else {
          debugPrint('❌ Failed to update profile: ${responseData['message']}');
          TopNotification.error(
            context,
            '${AppLocalizations.of(context)?.failedToUpdateProfile ?? AppLocalizations.of(context)!.tr('Failed to update profile')}: ${responseData['message']}');
        }
      } else {
        debugPrint('❌ Update profile failed with status: ${response.statusCode}');
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedUpdateProfile ?? AppLocalizations.of(context)!.tr('Update failed. Please try again.'));
      }
    } catch (e) {
      debugPrint('❌ Error updating user data: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorUpdatingProfile ?? AppLocalizations.of(context)!.tr('Error updating profile')}: $e');
    }
  }

  Future<void> _loadUserData() async {
    debugPrint('📡 Loading business user data from users table...');
    if (mounted && _isInitialLoad) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      // Try to get user profile from backend
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/users/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getStoredToken()}',
        });

      debugPrint('📡 User profile response status: ${response.statusCode}');
      debugPrint('📡 User profile response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true && responseData['user'] != null) {
          final userFromApi = responseData['user'];

          dynamic pickAny(List<String> keys) {
            for (final key in keys) {
              final value = userFromApi[key];
              if (value == null) continue;
              if (value is String && value.trim().isEmpty) continue;
              return value;
            }
            return null;
          }

          debugPrint('🖼️ Business Profile Image from API:');
          debugPrint('  - profilePic: ${userFromApi['profilePic']}');
          debugPrint('  - businessLogo: ${userFromApi['businessLogo']}');

          final fullName =
              (pickAny(['name', 'fullName'])?.toString().trim() ?? AppLocalizations.of(context)!.tr(''));
          final fullNameParts = fullName
              .split(' ')
              .where((p) => p.trim().isNotEmpty)
              .toList();
          final dbFirstName = pickAny(['firstname', 'firstName', 'first_name']);
          final dbLastName = pickAny(['lastname', 'lastName', 'last_name']);

          if (mounted) {
            setState(() {
              userData = {
                // Core user fields
                'username': pickAny(['username', 'userId', 'id']),
                'firstname':
                    dbFirstName ??
                    (fullNameParts.isNotEmpty ? fullNameParts.first : null),
                'lastname':
                    dbLastName ??
                    (fullNameParts.length > 1
                        ? fullNameParts.sublist(1).join(' ')
                        : null),
                'email': pickAny(['email', 'business_email']),
                'phone': pickAny([
                  'phone',
                  'mobile',
                  'phoneNumber',
                  'phone_number',
                ]),
                'birthdate': pickAny([
                  'birthdate',
                  'date_of_birth',
                  'dateOfBirth',
                  'dob',
                ]),
                'timezone': pickAny(['timezone', 'time_zone']),
                'profilePic': pickAny(['profilePic', 'businessLogo']),
                'street': pickAny([
                  'street',
                  'businessAddress',
                  'business_address',
                ]),

                // Business information fields (both variations)
                'businessName': pickAny([
                  'businessName',
                  'business_company',
                  'companyName',
                ]),
                'businessEmail': pickAny([
                  'businessEmail',
                  'business_email',
                  'email',
                ]),
                'businessPhone': pickAny([
                  'businessPhone',
                  'business_phone',
                  'phone',
                ]),
                'businessAddress': pickAny([
                  'businessAddress',
                  'business_address',
                  'address',
                  'street',
                ]),
                'businessDescription': pickAny([
                  'businessDescription',
                  'business_description',
                  'description',
                ]),
                'businessWebsite': pickAny([
                  'businessWebsite',
                  'business_website',
                  'website',
                ]),
                'business_size': pickAny(['business_size', 'businessSize']),
                'business_country': pickAny(['business_country', 'country']),
                'taxVatNumber': pickAny(['taxVatNumber', 'tax_vat_number']),
                'businessInfoCompleted': pickAny([
                  'businessInfoCompleted',
                  'business_info_completed',
                ]),
                'businessInfoCompletedAt': pickAny([
                  'businessInfoCompletedAt',
                  'business_info_completed_at',
                ]),

                // Stripe payment fields
                'stripeAccountId': pickAny([
                  'stripeAccountId',
                  'stripe_account_id',
                ]),
                'stripeCustomerId': pickAny([
                  'stripeCustomerId',
                  'stripe_customer_id',
                ]),
                'stripe_customer_id': pickAny([
                  'stripe_customer_id',
                  'stripeCustomerId',
                ]),

                // Tax form fields
                'tax_form_status': pickAny([
                  'tax_form_status',
                  'taxFormStatus',
                ]),
                'tax_form_type': pickAny(['tax_form_type', 'taxFormType']),

                // Payment method fields
                'payment_system': pickAny(['payment_system', 'paymentSystem']),
                'account_holder_name': pickAny([
                  'account_holder_name',
                  'accountHolderName',
                ]),
                'routing_number': pickAny(['routing_number', 'routingNumber']),
                'account_number': pickAny(['account_number', 'accountNumber']),
                'iban': pickAny(['iban']),
                'bic': pickAny(['bic', 'swift']),
                'bank_name': pickAny(['bank_name', 'bankName']),

                // Security & preferences
                'has_2fa_enabled': pickAny([
                  'has_2fa_enabled',
                  'has2faEnabled',
                ]),
                'biometric_enabled': pickAny([
                  'biometric_enabled',
                  'biometricEnabled',
                ]),
                'twofa': pickAny(['twofa']),
                'notifications_login': pickAny(['notifications_login']),
                'notifications_newsletter': pickAny([
                  'notifications_newsletter',
                ]),
                'supportsVisibilityPrefs': pickAny(['supportsVisibilityPrefs']),
                'supportsNewsletterPrefs': pickAny(['supportsNewsletterPrefs']),
                'remembered_language': pickAny(['remembered_language']),

                // Display preferences
                'showPhone': pickAny(['showPhone']),
                'showBusinessSize': pickAny(['showBusinessSize']),
                'showBusinessCompany': pickAny(['showBusinessCompany']),
                'showBusinessEmail': pickAny(['showBusinessEmail']),
                'showBusinessCountry': pickAny(['showBusinessCountry']),

                // Payment and social
                'paymentMethodsOrder': pickAny(['paymentMethodsOrder']),
                'payout_schedule': pickAny(['payout_schedule']),
                'followers_count': pickAny(['followers_count']) ?? 0,
                'following_count': pickAny(['following_count']) ?? 0,

                // System fields
                'isActive': pickAny(['isActive', 'is_active']) ?? true,
                'isBusiness': pickAny(['isBusiness', 'is_business']),
                'createdAt': pickAny(['createdAt', 'created_at']),
                'lastLogin': pickAny(['lastLogin', 'last_login']),
                'remember_expires': pickAny(['remember_expires']),
                'verification': {
                  'status':
                      (pickAny([
                            'businessInfoCompleted',
                            'business_info_completed',
                          ]) ==
                          true)
                      ? AppLocalizations.of(context)?.verified ?? AppLocalizations.of(context)!.tr('Verified')
                      : AppLocalizations.of(context)?.pending ?? AppLocalizations.of(context)!.tr('Pending'),
                  'score':
                      (pickAny([
                            'businessInfoCompleted',
                            'business_info_completed',
                          ]) ==
                          true)
                      ? 95
                      : 60,
                },
                'stats': {
                  'totalOrders': 45, // Will be loaded from separate endpoint
                  'totalRevenue': 2450.50,
                  'totalProducts': 25,
                  'activeProducts': 22,
                },
                'timestamps': {
                  'accountCreated': pickAny(['createdAt', 'created_at']),
                  'lastLogin': pickAny(['lastLogin', 'last_login']),
                },
              };
              isLoading = false;
              _isInitialLoad = false;
            });
          }

          // Synchronize biometric settings between local storage and database
          await _synchronizeBiometricSettings();

          // Resolve bank verification status also via saved payment methods
          await _refreshPaymentSetupStatus();

          debugPrint('✅ User data loaded successfully from users table');
          return;
        }
      }

      // If database fails, create a basic business profile from app settings
      debugPrint('⚠️ Creating fallback business profile from app settings');
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      final userName =
          appSettings.userName ??
          (AppLocalizations.of(context)?.businessUser ?? AppLocalizations.of(context)!.tr('Business User'));
      final userEmail = appSettings.userEmail ?? AppLocalizations.of(context)!.tr('business@example.com');

      if (mounted) {
        setState(() {
          userData = {
            'username': appSettings.userId ?? AppLocalizations.of(context)!.tr('business_user'),
            'firstname': userName.split(' ').first,
            'lastname': userName.split(' ').length > 1
                ? userName.split(' ').last
                : '',
            'email': userEmail,
            'phone': '',
            'businessName':
                AppLocalizations.of(context)?.myBusiness ?? AppLocalizations.of(context)!.tr('My Business'),
            'businessEmail': userEmail,
            'businessPhone': '',
            'businessAddress': '',
            'businessDescription':
                AppLocalizations.of(context)?.businessDescription ?? AppLocalizations.of(context)!.tr('Business description'),
            'businessWebsite': '',
            'business_size': '',
            'business_country': '',
            'taxVatNumber': '',
            'businessInfoCompleted': false,
            'isActive': true,
            'isBusiness': true,
            'profilePic': null,
            'createdAt': DateTime.now()
                .subtract(const Duration(days: 120))
                .toIso8601String(),
            'lastLogin': DateTime.now().toIso8601String(),
            'verification': {
              'status': AppLocalizations.of(context)?.verified ?? AppLocalizations.of(context)!.tr('Verified'),
              'score': 95,
            },
            'stats': {
              'totalOrders': 45,
              'totalRevenue': 2450.50,
              'totalProducts': 25,
              'activeProducts': 22,
            },
            'timestamps': {
              'accountCreated': DateTime.now()
                  .subtract(const Duration(days: 120))
                  .toIso8601String(),
              'lastLogin': DateTime.now().toIso8601String(),
            },
            // Payment settings (sample data)
            'payment_system': null, // Will default to USA
            'account_holder_name': null,
            'routing_number': null,
            'account_number': null,
            'iban': null,
            'bic': null,
            'bank_name': null,
            'stripe_customer_id': null,
            'stripe_payment_method_id': null,
          };
          isLoading = false;
          _isInitialLoad = false;
        });
      }
      debugPrint('✅ Fallback business profile created successfully');
    } catch (e) {
      debugPrint('❌ Error loading user data: $e');
      // Provide fallback data
      if (mounted) {
        setState(() {
          userData = {
            'username': 'business_user',
            'firstname': AppLocalizations.of(context)?.business ?? AppLocalizations.of(context)!.tr('Business'),
            'lastname': 'User',
            'email': 'business@example.com',
            'businessName':
                AppLocalizations.of(context)?.demoBusiness ?? AppLocalizations.of(context)!.tr('Demo Business'),
            'isActive': true,
            'isBusiness': true,
            // Payment settings
            'payment_system': null,
            'account_holder_name': null,
            'routing_number': null,
            'account_number': null,
            'iban': null,
            'bic': null,
            'bank_name': null,
            'stripe_customer_id': null,
            'stripe_payment_method_id': null,
          };
          isLoading = false;
          _isInitialLoad = false;
          _hasConnectedPaymentMethod = false;
        });
      }
    }
  }

  Future<void> _refreshPaymentSetupStatus() async {
    final byProfile = BusinessAccountPage.hasConnectedPaymentSetup(userData);
    if (byProfile) {
      if (mounted && !_hasConnectedPaymentMethod) {
        setState(() => _hasConnectedPaymentMethod = true);
      }
      return;
    }

    final methods = await _loadSavedPaymentMethods();
    final hasMethod = methods.isNotEmpty;

    if (mounted && _hasConnectedPaymentMethod != hasMethod) {
      setState(() => _hasConnectedPaymentMethod = hasMethod);
    }
  }

  Future<void> _loadBusinessStats() async {
    try {
      debugPrint('📊 Loading business statistics from backend...');

      final token = await _getStoredToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/business/stats'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });

      debugPrint('📡 Business stats response: ${response.statusCode}');
      debugPrint('📡 Business stats response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true && responseData['stats'] != null) {
          if (mounted) {
            setState(() {
              businessStats = responseData['stats'];
            });
          }
          debugPrint('✅ Business stats loaded successfully from backend');
          return;
        }
      }

      // Fallback stats
      if (mounted) {
        setState(() {
          businessStats = {
            'totalOrders': 45,
            'monthlyRevenue': 2450.50,
            'totalProducts': 25,
            'avgOrderValue': 54.50,
          };
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading business stats: $e');
    }
  }

  Future<void> _loadFollowers() async {
    try {
      debugPrint('👥 Loading business followers from backend...');

      final token = await _getStoredToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/business/followers'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });

      debugPrint('📡 Followers response: ${response.statusCode}');
      debugPrint('📡 Followers response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          if (mounted) {
            setState(() {
              followers = List<Map<String, dynamic>>.from(
                responseData['followers'] ?? []);
              socialStats =
                  responseData['stats'] ??
                  {'followers_count': 0, 'following_count': 0};

              // Update userData with follower counts
              if (userData != null) {
                userData!['followers_count'] = socialStats['followers_count'];
                userData!['following_count'] = socialStats['following_count'];
              }
            });
          }
          debugPrint(
            '✅ Followers loaded successfully: ${followers.length} followers');
          return;
        }
      }

      debugPrint('⚠️ Using fallback follower data');
    } catch (e) {
      debugPrint('❌ Error loading followers: $e');
    }
  }

  Future<void> _loadCurrentGroup() async {
    try {
      debugPrint('🎯 Loading current group from backend...');

      final token = await _getStoredToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/business_groups/current'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });

      debugPrint('📡 Current group response: ${response.statusCode}');
      debugPrint('📡 Current group response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true &&
            responseData['currentGroup'] != null) {
          final normalizedGroup = _normalizeGroupPayload(
            Map<String, dynamic>.from(responseData['currentGroup']));
          if (mounted) {
            setState(() {
              currentGroup = normalizedGroup;
            });
          }
          debugPrint(
            '✅ Current group loaded: ${currentGroup?['name']} (Role: ${currentGroup?['role']})');
        } else {
          // User is not in any group
          if (mounted) {
            setState(() {
              currentGroup = null;
            });
          }
          debugPrint('ℹ️ User is not in any group');
        }
      } else if (response.statusCode == 401) {
        debugPrint('❌ Authentication failed - token may be expired');
        if (mounted) {
          setState(() {
            currentGroup = null;
          });
        }
      } else {
        debugPrint('❌ Failed to load current group: ${response.statusCode}');
        if (mounted) {
          setState(() {
            currentGroup = null;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading current group: $e');
      if (mounted) {
        setState(() {
          currentGroup = null;
        });
      }
    }
  }

  Future<void> _loadEarningsData() async {
    try {
      debugPrint('💰 Loading earnings data...');

      final token = await _getStoredToken();

      if (token == null) {
        debugPrint('❌ No auth token available');
        return;
      }

      final username = (userData?['username'] ?? AppLocalizations.of(context)!.tr('')).toString().trim();
      final endpoints = <String>[
        '/api/business/earnings',
        if (username.isNotEmpty)
          '/api/business/earnings?username=${Uri.encodeComponent(username)}',
      ];

      bool loaded = false;

      for (final endpoint in endpoints) {
        final response = await http.get(
          Uri.parse('${ApiConfig.baseUrl}$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          });

        debugPrint('📡 Earnings response ($endpoint): ${response.statusCode}');

        if (response.statusCode == 401) {
          debugPrint('🔄 Token expired, refreshing...');
          await _refreshToken();
          continue;
        }

        if (response.statusCode != 200) {
          continue;
        }

        final responseData = json.decode(response.body);
        if (responseData['success'] != true) {
          continue;
        }

        final earnings = responseData['earnings'] ?? {};
        final payouts = responseData['recentPayouts'] ?? [];
        final groupEarnings = responseData['groupEarnings'];

        if (mounted) {
          setState(() {
            earningsData = {
              'totalEarnings':
                  double.tryParse(earnings['totalEarnings']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ??
                  0.0,
              'availableBalance':
                  double.tryParse(
                    earnings['availableBalance']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ??
                  0.0,
              'totalPayouts':
                  double.tryParse(earnings['totalPaidOut']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ??
                  0.0,
              'totalWaitingCharges':
                  double.tryParse(
                    earnings['totalWaitingCharges']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ??
                  0.0,
              'lastUpdated': earnings['lastUpdated'],
            };

            if (groupEarnings != null) {
              groupEarningsData = {
                'groupId': groupEarnings['groupId'],
                'groupName': groupEarnings['groupName'],
                'totalEarnings':
                    double.tryParse(
                      groupEarnings['totalEarnings']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ??
                    0.0,
                'totalMembers': groupEarnings['totalMembers'] ?? 0,
                'totalDeliveries': groupEarnings['totalDeliveries'] ?? 0,
                'averagePerDelivery':
                    double.tryParse(
                      groupEarnings['averagePerDelivery']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ??
                    0.0,
              };
            } else {
              groupEarningsData = null;
            }

            recentPayouts = List<Map<String, dynamic>>.from(
              payouts.map(
                (payout) => {
                  'id': payout['id'],
                  'amount':
                      double.tryParse(payout['amount']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ??
                      0.0,
                  'payout_date': payout['payout_date'],
                  'created_at': payout['created_at'],
                  'status': payout['status'],
                  'stripe_transfer_id': payout['stripe_transfer_id'],
                  'notes': payout['notes'],
                }));
          });
        }

        loaded = true;
        debugPrint('✅ Earnings loaded successfully');
        debugPrint('💰 Total Earnings: ${AppSettings().currencySymbol}${earningsData['totalEarnings']}');
        debugPrint('💵 Available Balance: ${AppSettings().currencySymbol}${earningsData['availableBalance']}');
        break;
      }

      if (!loaded) {
        debugPrint('⚠️ Earnings endpoint did not return usable data, trying orders fallback...');
        final fallbackLoaded = await _loadEarningsFromOrdersFallback(token);

        if (!fallbackLoaded && mounted) {
          TopNotification.error(
            _scaffoldKey.currentContext ?? context,
            'Earnings could not be loaded. Please refresh.');
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading earnings data: $e');
      if (mounted) {
        setState(() {
          earningsData = {
            'totalEarnings': 0.0,
            'availableBalance': 0.0,
            'totalPayouts': 0.0,
            'lastUpdated': null,
          };
        });
      }
    }
  }

  // Load group member earnings for group owners
  Future<List<Map<String, dynamic>>> _loadGroupMemberEarnings() async {
    if (currentGroup == null || !_isCurrentGroupAdmin) {
      return [];
    }

    try {
      final token = await _getStoredToken();
      if (token == null) return [];

      final groupId = currentGroup?['id'];
      if (groupId == null) return [];

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/business/group/$groupId/member-earnings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['memberEarnings'] != null) {
          return List<Map<String, dynamic>>.from(data['memberEarnings']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error loading group member earnings: $e');
      return [];
    }
  }

  Future<void> _loadEarningsHistory() async {
    try {
      debugPrint('📈 Loading real earnings history from orders...');

      final token = await _getStoredToken();
      final username = (userData?['username'] ?? AppLocalizations.of(context)!.tr('')).toString().trim();
      final endpoints = <String>[
        '/api/business/earnings-history${username.isNotEmpty ? '?username=${Uri.encodeComponent(username)}' : ''}',
        if (username.isNotEmpty)
          '/api/business/account/${Uri.encodeComponent(username)}/earnings-history',
        '/api/business/earnings-history',
        if (username.isNotEmpty)
          '/api/business/account/${Uri.encodeComponent(username)}/earnings-history',
      ];

      bool loaded = false;

      for (final endpoint in endpoints) {
        final response = await http.get(
          Uri.parse('${ApiConfig.baseUrl}$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          });

        debugPrint(
          '📡 Earnings history response ($endpoint): ${response.statusCode}');
        debugPrint('📡 Earnings history response body: ${response.body}');

        if (response.statusCode == 401) {
          await _refreshToken();
          continue;
        }

        if (response.statusCode == 403) {
          // Try compatibility endpoint
          continue;
        }

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {
            final rawItems =
                (responseData['transactions'] ?? responseData['earnings'] ?? [])
                    as List;
            final normalized = rawItems.whereType<Map>().map<Map<String, dynamic>>((
              row) {
              final amountVal = row['amount'];
              final amount = amountVal is num
                  ? amountVal.toDouble()
                  : double.tryParse((amountVal ?? AppLocalizations.of(context)!.tr('0')).toString()) ?? 0.0;

              final createdAt =
                  (row['created_at'] ?? row['date'] ?? row['createdAt'])
                      ?.toString();
              final orderId =
                  (row['orderId'] ?? row['order_id'] ?? row['id'] ?? AppLocalizations.of(context)!.tr(''))
                      .toString();
              final status = (row['status'] ?? AppLocalizations.of(context)!.tr('')).toString();

              return {
                'amount': amount,
                'source': (row['source'] ?? AppLocalizations.of(context)!.tr('sale')).toString(),
                'description':
                    (row['description'] ??
                            'Order #$orderId${status.isNotEmpty ? ' · $status' : ''}')
                        .toString(),
                'created_at': createdAt,
                'customer':
                    (row['customer'] ??
                            row['buyerUsername'] ??
                            row['buyer_username'] ?? AppLocalizations.of(context)!.tr(''))
                        .toString(),
                'order_id': orderId,
              };
            }).toList();

            if (mounted) {
              setState(() {
                earningsHistory = normalized;
              });
            }

            debugPrint(
              '✅ Real earnings history loaded: ${earningsHistory.length} transactions');
            loaded = true;
            break;
          }
        }
      }

      if (!loaded) {
        if (mounted) {
          setState(() {
            earningsHistory = [];
          });
        }
        debugPrint('📊 No real earnings history available, showing empty state');
      }
    } catch (e) {
      debugPrint('❌ Error loading earnings history: $e');
      // Use empty list as fallback
      if (mounted) {
        setState(() {
          earningsHistory = [];
        });
      }
    }
  }

  // Load waiting charge deductions for seller
  Future<void> _loadWaitingChargeDeductions() async {
    try {
      debugPrint('⏱️ Loading waiting charge deductions...');

      final token = await _getStoredToken();
      if (token == null) return;

      final username = (userData?['username'] ?? AppLocalizations.of(context)!.tr('')).toString().trim();
      final endpoints = <String>[
        '/api/business/waiting-charges${username.isNotEmpty ? '?username=${Uri.encodeComponent(username)}' : ''}',
        if (username.isNotEmpty)
          '/api/business/account/${Uri.encodeComponent(username)}/waiting-charges',
        '/api/business/waiting-charges',
        if (username.isNotEmpty)
          '/api/business/account/${Uri.encodeComponent(username)}/waiting-charges',
      ];

      for (final endpoint in endpoints) {
        final response = await http.get(
          Uri.parse('${ApiConfig.baseUrl}$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          });

        debugPrint(
          '📡 Waiting charges response ($endpoint): ${response.statusCode}');

        if (response.statusCode == 401) {
          await _refreshToken();
          continue;
        }

        if (response.statusCode == 403) {
          continue;
        }

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);
          if (responseData['success'] == true) {
            if (mounted) {
              setState(() {
                waitingChargeDeductions = List<Map<String, dynamic>>.from(
                  responseData['charges'] ?? []);
              });
            }
            debugPrint(
              '✅ Waiting charges loaded: ${waitingChargeDeductions.length} deductions');
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading waiting charge deductions: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadGroupMembers(int groupId) async {
    try {
      debugPrint('👥 Loading group members for group ID: $groupId');

      final token = await _getStoredToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/business_groups/$groupId/members'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });

      debugPrint('📡 Group members response: ${response.statusCode}');
      debugPrint('📡 Group members response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true &&
            responseData['members'] != null) {
          return List<Map<String, dynamic>>.from(
            responseData['members']).map(_normalizeGroupMember).toList();
        }
      }

      return [];
    } catch (e) {
      debugPrint('❌ Error loading group members: $e');
      return [];
    }
  }

  // ── Monioo Wallet ─────────────────────────────────────────────────────────

  Future<void> _loadWalletData() async {
    try {
      final token = await _getStoredToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _walletBalance = (data['wallet']?['balance'] ?? 0.0).toDouble();
            _walletTransactions = List<Map<String, dynamic>>.from(
              data['transactions'] ?? []);
            _walletLoaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading wallet: $e');
    }
  }

  Future<void> _loadPendingShippingPayments() async {
    try {
      final token = await _getStoredToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet/pending-shipping'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _pendingShippingPayments = List<Map<String, dynamic>>.from(
              data['pending_payments'] ?? []);
            _pendingShippingLoaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading pending shipping payments: $e');
    }
  }

  Future<void> _loadPaymentDefaults() async {
    try {
      final token = await _getStoredToken();
      if (token == null) return;
      // Load both defaults and saved payment methods in parallel
      final results = await Future.wait([
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/wallet/defaults'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          }),
        _loadSavedPaymentMethods(),
      ]);
      final defaultsResponse = results[0] as http.Response;
      final methods = results[1] as List<Map<String, dynamic>>;
      if (mounted) {
        setState(() {
          if (defaultsResponse.statusCode == 200) {
            final data = json.decode(defaultsResponse.body);
            _defaultShippingPayment =
                data['default_payment_shipping']?.toString() ?? AppLocalizations.of(context)!.tr('wallet');
          }
          _savedPaymentMethodsCache = methods;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading payment defaults: $e');
    }
  }

  Future<void> _saveShippingPaymentDefault(
    String value,
    StateSetter setModalState) async {
    setModalState(() => _defaultShippingPayment = value);
    setState(() => _defaultShippingPayment = value);
    try {
      final token = await _getStoredToken();
      if (token == null) return;
      await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet/defaults'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'default_payment_shipping': value}));
    } catch (e) {
      debugPrint('❌ Error saving shipping payment default: $e');
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _loadUserData(),
      _loadBusinessStats(),
      _loadFollowers(),
      _loadCurrentGroup(),
      _loadEarningsData(),
      _loadEarningsHistory(),
      _loadWaitingChargeDeductions(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);
    final media = MediaQuery.of(context);

    // Global text scale is provided by main.dart MediaQuery now

    // Adaptive paddings to avoid overflow in landscape / when keyboard is visible
    final double topScrollPadding = media.size.height * 0.18; // ~18% of height
    final double bottomScrollPadding =
        80.0 + media.viewInsets.bottom; // increased bottom spacing

    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final horizontalPadding = isDesktop ? 32.0 : 20.0;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: isLoading
          ? const Center(child: CultiooLoadingIndicator())
          : userData == null
          ? Center(
              child: Text(
                AppLocalizations.of(context)?.unableToLoadAccountData ?? AppLocalizations.of(context)!.tr('Unable to load account data'),
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: DesktopOptimizedWidgets.getFontSize())))
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? 1080 : double.infinity),
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    CultiooSliverRefreshControl(onRefresh: _refreshData),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        isDesktop
                            ? 32.0
                            : MediaQuery.of(context).padding.top + 20.0,
                        horizontalPadding,
                        MediaQuery.of(context).padding.bottom +
                            bottomScrollPadding),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Trade Republic Style Header
                            _buildAnimatedSection(
                              delay: 0,
                              slideFromBottom: false,
                              child: _buildTradeRepublicHeader(isLight)),

                            SizedBox(height: 32),

                            // 1. Business Profile Summary Card - Animated
                            if (!_isAnyModalOpen)
                              _buildAnimatedSection(
                                delay: 0,
                                slideFromBottom: false,
                                child: _buildBusinessProfileSummary(isLight)),

                            // 2. Business Statistics Dashboard - Animated
                            _buildAnimatedSection(
                              delay: 1,
                              slideFromBottom: true,
                              child: _buildGroupOverviewDashboard(isLight)),

                            // 3. Business Information Section - Animated
                            _buildAnimatedSection(
                              delay: 2,
                              slideFromBottom: false,
                              child: _buildBusinessInfoSection(isLight)),

                            // 4. Account Settings Section - Animated
                            _buildAnimatedSection(
                              delay: 3,
                              slideFromBottom: false,
                              child: _buildAccountSettingsSection(isLight)),

                            // 5. Verification Status - Animated
                            _buildAnimatedSection(
                              delay: 4,
                              slideFromBottom: true,
                              child: _buildVerificationStatusButton(isLight)),

                            // 6. Security & Privacy Section - Animated
                            _buildAnimatedSection(
                              delay: 6,
                              slideFromBottom: true,
                              child: _buildSecurityPrivacySection(isLight)),

                            // 7. Social & Community Section - Animated
                            _buildAnimatedSection(
                              delay: 7,
                              slideFromBottom: false,
                              child: _buildSocialCommunitySection(isLight)),

                            // 10. Account Management - Animated
                            _buildAnimatedSection(
                              delay: 9,
                              slideFromBottom: true,
                              child: _buildAccountManagementSection(isLight)),
                          ]))),
                  ]))));
  }

  // Trade Republic Style Header - Minimal & Clean
  Widget _buildTradeRepublicHeader(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.account ?? AppLocalizations.of(context)!.tr('Account'),
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5)),
        SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)?.manageBusinessProfile ?? AppLocalizations.of(context)!.tr('Manage your business profile'),
          style: TextStyle(
            color: isLight
                ? Colors.black.withOpacity(0.5)
                : Colors.white.withOpacity(0.5),
            fontSize: 15,
            fontWeight: FontWeight.w400)),
      ]);
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
        // Staggered delay calculation - use smaller delay factor for smooth cascade
        final delayFactor = delay * 0.08;
        final delayedValue = (_contentAnimController.value - delayFactor).clamp(
          0.0,
          1.0);
        final remainingRange = (1.0 - delayFactor).clamp(0.1, 1.0);
        final curvedValue = Curves.easeOutCubic.transform(
          delayedValue > 0
              ? (delayedValue / remainingRange).clamp(0.0, 1.0)
              : 0.0);

        return Transform.translate(
          offset: Offset(
            0, // No horizontal movement
            // slideFromBottom = true means from bottom, false = from top
            slideFromBottom ? 30 * (1 - curvedValue) : -30 * (1 - curvedValue)),
          child: Opacity(
            opacity: curvedValue,
            child: Transform.scale(
              scale: 0.95 + (0.05 * curvedValue),
              alignment: slideFromBottom
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: child)));
      });
  }

  Widget _buildBusinessProfileSummary(bool isLight) {
    final bool hasProfilePic =
        userData?['profilePic'] != null &&
        userData!['profilePic'].toString().trim().isNotEmpty;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Business Profile Photo — circle, centered (matches delvioo_account_page)
          Center(
            child: TradeRepublicTap(
              onTap: () => _showProfilePictureModal(context, isLight),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isLight
                          ? const Color(0xFFF2F2F2)
                          : const Color(0xFF1F1F1F)),
                    clipBehavior: Clip.antiAlias,
                    child: hasProfilePic
                        ? _buildSmartProfileImage(
                            userData!['profilePic'],
                            isLight: isLight)
                        : Icon(
                            CupertinoIcons.person_fill,
                            size: 36,
                            color: isLight ? Colors.black : Colors.white)),
                  // Camera badge
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: isLight ? Colors.white : Colors.black,
                        shape: BoxShape.circle),
                      child: Icon(
                        CupertinoIcons.camera_fill,
                        size: 12,
                        color: isLight ? Colors.black : Colors.white))),
                ]))),

          SizedBox(height: 14),

          // Business Name (only shown when set)
          if ((userData?['businessName'] ?? AppLocalizations.of(context)!.tr('')).toString().trim().isNotEmpty)
            Text(
              userData!['businessName'].toString().trim(),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isLight ? Colors.black : Colors.white,
                letterSpacing: -0.5),
              textAlign: TextAlign.center),
          SizedBox(height: 3),
          // Owner name
          if ((userData?['firstname'] ?? AppLocalizations.of(context)!.tr('')).toString().isNotEmpty ||
              (userData?['lastname'] ?? AppLocalizations.of(context)!.tr('')).toString().isNotEmpty)
            Text(
              '${userData?['firstname'] ?? AppLocalizations.of(context)!.tr('')} ${userData?['lastname'] ?? AppLocalizations.of(context)!.tr('')}'
                  .trim(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5)),
              textAlign: TextAlign.center),
          SizedBox(height: 3),
          // Username / email
          if ((userData?['username'] ?? userData?['email']) != null)
            Text(
              userData?['username'] != null
                  ? '@${userData!['username']}'
                  : userData!['email'],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.4))),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          // Active badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle)),
                SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)?.active ?? AppLocalizations.of(context)!.tr('Active'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.green)),
              ])),

          SizedBox(height: 32),
        ]));
  }

  // -------------------------------
  // App Settings Modal (moved from settings_page.dart)
  // -------------------------------
  void _showAppSettingsModal(BuildContext parentContext, bool isLight) {
    final AppSettings appSettings = Provider.of<AppSettings>(
      parentContext,
      listen: false);

    setState(() => _isAppSettingsOpen = true);
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: parentContext,
      bottomPadding: 20.0,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),

            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.settings,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.appSettings ?? AppLocalizations.of(context)!.tr('App Settings'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Appearance Section
                    _settings_buildAppearanceSection(appSettings, isLight),
                    const TradeRepublicDivider(),

                    // Navigation
                    _settings_buildNavigationSection(appSettings, isLight),
                    const TradeRepublicDivider(),

                    // Localization & Formats
                    _settings_buildLocalizationSection(appSettings, isLight),
                    const TradeRepublicDivider(),

                    // Units
                    _settings_buildUnitsSection(appSettings, isLight),
                    const TradeRepublicDivider(),

                    // Legal & About
                    _settings_buildLegalAboutSection(appSettings, isLight),
                  ]))),
          ]))).whenComplete(() {
      NavigationVisibility.show();
      if (mounted) setState(() => _isAppSettingsOpen = false);
    });
  }

  // --- Settings helpers (simplified versions of the original page) ---
  Widget _settings_buildAppearanceSection(
    AppSettings appSettings,
    bool isLight) {
    final themeOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'Light': AppLocalizations.of(context)?.light ?? AppLocalizations.of(context)!.tr('Light'),
      'Dark': AppLocalizations.of(context)?.dark ?? AppLocalizations.of(context)!.tr('Dark'),
    };
    final textSizeOptions = {
      'Small': AppLocalizations.of(context)?.small ?? AppLocalizations.of(context)!.tr('Small'),
      'Medium': AppLocalizations.of(context)?.medium ?? AppLocalizations.of(context)!.tr('Medium'),
      'Large': AppLocalizations.of(context)?.large ?? AppLocalizations.of(context)!.tr('Large'),
      'Extra Large':
          AppLocalizations.of(context)?.extraLargeLabel ?? AppLocalizations.of(context)!.tr('Extra Large'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(0, 24, 0, 12),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.paintbrush,
                size: 16,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.appearance ?? AppLocalizations.of(context)!.tr('Appearance'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.2)),
            ])),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.theme ?? AppLocalizations.of(context)!.tr('Theme'),
          subtitle:
              themeOptions[appSettings.selectedTheme] ??
              appSettings.selectedTheme,
          leading: Icon(
            CupertinoIcons.paintbrush,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.theme ?? AppLocalizations.of(context)!.tr('Theme'),
            options: themeOptions,
            selectedKey: appSettings.selectedTheme,
            onSelect: (key) => appSettings.setSelectedTheme(key),
            isLight: isLight)),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.textSize ?? AppLocalizations.of(context)!.tr('Text Size'),
          subtitle:
              textSizeOptions[appSettings.selectedTextSize] ??
              appSettings.selectedTextSize,
          leading: Icon(
            CupertinoIcons.textformat_size,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.textSize ?? AppLocalizations.of(context)!.tr('Text Size'),
            options: textSizeOptions,
            selectedKey: appSettings.selectedTextSize,
            onSelect: (key) => appSettings.setSelectedTextSize(key),
            isLight: isLight)),
      ]);
  }

  Widget _settings_buildNavigationSection(
    AppSettings appSettings,
    bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(0, 24, 0, 12),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.square_grid_2x2,
                size: 16,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.navigation ?? AppLocalizations.of(context)!.tr('Navigation'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.2)),
            ])),
        TradeRepublicListTile.toggle(
          title: AppLocalizations.of(context)?.motionDock ?? AppLocalizations.of(context)!.tr('Motion Dock'),
          subtitle: appSettings.motionDockEnabled
              ? (AppLocalizations.of(context)?.enabled ?? AppLocalizations.of(context)!.tr('Enabled'))
              : (AppLocalizations.of(context)?.disabled ?? AppLocalizations.of(context)!.tr('Disabled')),
          leading: Icon(
            CupertinoIcons.square_grid_2x2,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          value: appSettings.motionDockEnabled,
          onChanged: (v) => appSettings.setMotionDockEnabled(v)),
      ]);
  }

  Widget _settings_buildLocalizationSection(
    AppSettings appSettings,
    bool isLight) {
    final numberFormatOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      '1,234.56': '1,234.56 (US)',
      '1.234,56': '1.234,56 (EU)',
    };
    final currencyOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'Dollar': 'Dollar (\$)',
      'CanadianDollar': 'Canadian Dollar (CA\$)',
      'MexicanPeso': 'Mexican Peso (MX\$)',
      'Euro': 'Euro (€)',
      'Pound': 'Pound (£)',
      'Zloty': 'Polish Zloty (zł)',
      'Koruna': 'Czech Koruna (Kč)',
      'Forint': 'Hungarian Forint (Ft)',
      'SwedishKrona': 'Swedish Krona (kr)',
      'DanishKrone': 'Danish Krone (kr)',
      'NorwegianKrone': 'Norwegian Krone (kr)',
      'Franc': 'Swiss Franc (Fr.)',
      'Lev': 'Bulgarian Lev (лв)',
      'Leu': 'Romanian Leu (lei)',
      'Ruble': 'Ruble (₽)',
    };
    final dateFormatOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'dd.MM.yyyy': 'dd.MM.yyyy',
      'dd/MM/yyyy': 'dd/MM/yyyy',
      'MM/dd/yyyy': 'MM/dd/yyyy',
      'yyyy-MM-dd': 'yyyy-MM-dd',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(0, 24, 0, 12),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.globe,
                size: 16,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.localization ?? AppLocalizations.of(context)!.tr('Localization'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.2)),
            ])),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.language ?? AppLocalizations.of(context)!.tr('Language'),
          subtitle: appSettings.selectedLanguage == 'System'
              ? 'System (${appSettings.effectiveLanguage})'
              : appSettings.selectedLanguageDisplayName,
          leading: Icon(
            CupertinoIcons.globe,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () => _settings_showLanguageOptions(
            appSettings: appSettings,
            isLight: isLight)),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.numberFormat ?? AppLocalizations.of(context)!.tr('Number Format'),
          subtitle: appSettings.delviooNumberFormat == 'System'
              ? 'System (${appSettings.effectiveNumberFormat == '1,234.56' ? '1,234.56 US' : '1.234,56 EU'})'
              : appSettings.delviooNumberFormat == '1,234.56'
              ? '1,234.56 (US)'
              : '1.234,56 (EU)',
          leading: Icon(
            CupertinoIcons.tag,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () => _settings_showMappedOptions(
            title:
                AppLocalizations.of(context)?.numberFormat ?? AppLocalizations.of(context)!.tr('Number Format'),
            options: numberFormatOptions,
            selectedKey: appSettings.delviooNumberFormat,
            onSelect: (key) => appSettings.setDelviooNumberFormat(key),
            isLight: isLight)),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.currency ?? AppLocalizations.of(context)!.tr('Currency'),
          subtitle: appSettings.delviooCurrency == 'System'
              ? 'System (${appSettings.effectiveCurrency})'
              : currencyOptions[appSettings.delviooCurrency] ??
                    appSettings.delviooCurrency,
          leading: Icon(
            CupertinoIcons.money_dollar,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.currency ?? AppLocalizations.of(context)!.tr('Currency'),
            options: currencyOptions,
            selectedKey: appSettings.delviooCurrency,
            onSelect: (key) => appSettings.setDelviooCurrency(key),
            isLight: isLight)),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.dateFormat ?? AppLocalizations.of(context)!.tr('Date Format'),
          subtitle: appSettings.selectedDateFormat == 'System'
              ? 'System (${appSettings.effectiveDateFormat})'
              : appSettings.selectedDateFormat,
          leading: Icon(
            CupertinoIcons.calendar,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.dateFormat ?? AppLocalizations.of(context)!.tr('Date Format'),
            options: dateFormatOptions,
            selectedKey: appSettings.selectedDateFormat,
            onSelect: (key) => appSettings.setSelectedDateFormat(key),
            isLight: isLight)),
      ]);
  }

  Widget _settings_buildUnitsSection(AppSettings appSettings, bool isLight) {
    final tempOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'Celsius': 'Celsius (°C)',
      'Fahrenheit': 'Fahrenheit (°F)',
    };
    final distOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'Miles': AppLocalizations.of(context)?.miles ?? AppLocalizations.of(context)!.tr('Miles (mi)'),
      'Kilometers':
          AppLocalizations.of(context)?.kilometers ?? AppLocalizations.of(context)!.tr('Kilometers (km)'),
    };
    final weightOptions = {
      'System': AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
      'Kilograms': AppLocalizations.of(context)?.kilogramsLabel ?? AppLocalizations.of(context)!.tr('Kilograms'),
      'Pounds': AppLocalizations.of(context)?.poundsLabel ?? AppLocalizations.of(context)!.tr('Pounds'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(0, 24, 0, 12),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.thermometer,
                size: 16,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.units ?? AppLocalizations.of(context)!.tr('Units'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.2)),
            ])),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.temperatureUnit ?? AppLocalizations.of(context)!.tr('Temperature'),
          subtitle: appSettings.delviooTemperatureUnit == 'System'
              ? 'System (${appSettings.effectiveTemperatureUnit == 'Celsius' ? 'Celsius' : 'Fahrenheit'})'
              : tempOptions[appSettings.delviooTemperatureUnit] ??
                    appSettings.delviooTemperatureUnit,
          leading: Icon(
            CupertinoIcons.thermometer,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () => _settings_showMappedOptions(
            title:
                AppLocalizations.of(context)?.temperatureUnit ?? AppLocalizations.of(context)!.tr('Temperature'),
            options: tempOptions,
            selectedKey: appSettings.delviooTemperatureUnit,
            onSelect: (key) => appSettings.setDelviooTemperatureUnit(key),
            isLight: isLight)),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.distanceUnit ?? AppLocalizations.of(context)!.tr('Distance'),
          subtitle: appSettings.delviooDistanceUnit == 'System'
              ? 'System (${appSettings.effectiveDistanceUnit})'
              : distOptions[appSettings.delviooDistanceUnit] ??
                    appSettings.delviooDistanceUnit,
          leading: Icon(
            CupertinoIcons.map,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () => _settings_showMappedOptions(
            title:
                AppLocalizations.of(context)?.distanceUnit ?? AppLocalizations.of(context)!.tr('Distance Unit'),
            options: distOptions,
            selectedKey: appSettings.delviooDistanceUnit,
            onSelect: (key) => appSettings.setDelviooDistanceUnit(key),
            isLight: isLight)),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.weightUnit ?? AppLocalizations.of(context)!.tr('Weight'),
          subtitle: appSettings.delviooWeightUnit == 'System'
              ? 'System (${appSettings.effectiveWeightUnit})'
              : weightOptions[appSettings.delviooWeightUnit] ??
                    appSettings.delviooWeightUnit,
          leading: Icon(
            CupertinoIcons.speedometer,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () => _settings_showMappedOptions(
            title: AppLocalizations.of(context)?.weightUnit ?? AppLocalizations.of(context)!.tr('Weight Unit'),
            options: weightOptions,
            selectedKey: appSettings.delviooWeightUnit,
            onSelect: (key) => appSettings.setDelviooWeightUnit(key),
            isLight: isLight)),
      ]);
  }

  Widget _settings_buildLegalAboutSection(
    AppSettings appSettings,
    bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(0, 24, 0, 12),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.info_circle,
                size: 16,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.legalAbout ?? AppLocalizations.of(context)!.tr('Legal & About'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.2)),
            ])),
        TradeRepublicListTile.navigation(
          title:
              AppLocalizations.of(context)?.privacyPolicy ?? AppLocalizations.of(context)!.tr('Privacy Policy'),
          subtitle:
              AppLocalizations.of(context)?.howWeProtectData ??
              AppLocalizations.of(context)?.howWeProtectYourData ?? AppLocalizations.of(context)!.tr('How we protect your data'),
          leading: Icon(
            CupertinoIcons.lock_shield,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () async {
            final url = Uri.parse(
              'https://cultioo.com/us/us_legal_app#business_privacy');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.inAppBrowserView);
            }
          }),
        TradeRepublicListTile.navigation(
          title:
              AppLocalizations.of(context)?.termsConditions ?? AppLocalizations.of(context)!.tr('Terms & Conditions'),
          subtitle:
              AppLocalizations.of(context)?.termsOfService ?? AppLocalizations.of(context)!.tr('Terms of service'),
          leading: Icon(
            CupertinoIcons.doc_text,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () async {
            final url = Uri.parse(
              'https://cultioo.com/us/us_legal_app#business_terms');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.inAppBrowserView);
            }
          }),
        TradeRepublicListTile.navigation(
          title: AppLocalizations.of(context)?.generalHelp ?? AppLocalizations.of(context)!.tr('General Help'),
          subtitle:
              AppLocalizations.of(context)?.helpSupport ??
              AppLocalizations.of(context)?.helpAndSupportForTheApp ?? AppLocalizations.of(context)!.tr('Help and support for the app'),
          leading: Icon(
            CupertinoIcons.question_circle,
            size: 20,
            color: isLight ? Colors.black : Colors.white),
          onTap: () async {
            final url = Uri.parse('https://cultioo.com/us/us_help');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.inAppBrowserView);
            }
          }),
        TradeRepublicListTile(
          title: AppLocalizations.of(context)?.appVersion ?? AppLocalizations.of(context)!.tr('App Version'),
          subtitle: AppLocalizations.of(context)!.tr('1.0.0') ?? AppLocalizations.of(context)!.tr('1.0.0'),
          leading: Icon(
            CupertinoIcons.info_circle,
            size: 20,
            color: isLight ? Colors.black : Colors.white)),
      ]);
  }

  // Helper for time formatting
  String _formatTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  // Language selection modal with flags and regions
  void _settings_showLanguageOptions({
    required AppSettings appSettings,
    required bool isLight,
  }) {
    final ctx = _scaffoldKey.currentContext!;
    void closeLanguageAndSettings() {
      // Close current language sheet first.
      final currentNavigator = Navigator.of(context);
      if (currentNavigator.canPop()) {
        currentNavigator.pop();
      }

      // Close parent settings sheet on next frame to avoid navigator lock re-entry.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final parentNavigator = Navigator.of(ctx);
        if (parentNavigator.canPop()) {
          parentNavigator.pop();
        }
      });
    }
    NavigationVisibility.hide();

    // Group locales by region
    final northAmerica = AppLocales.all
        .where(
          (l) =>
              l.region == 'USA' || l.region == 'Canada' || l.region == 'México')
        .toList();
    final eu = AppLocales.all
        .where(
          (l) =>
              l.region != 'USA' &&
              l.region != 'Canada' &&
              l.region != 'México' &&
              l.region != 'Россия')
        .toList();
    final russia = AppLocales.all.where((l) => l.region == 'Россия').toList();

    TradeRepublicBottomSheet.show(
      context: ctx,
      bottomPadding: 20.0,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),

            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.globe,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.language ?? AppLocalizations.of(context)!.tr('Language'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // System option
                    _buildLanguageOptionTile(
                      flag: '🌐',
                      displayName:
                          AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'),
                      region: appSettings.effectiveLanguage,
                      isSelected: appSettings.selectedLanguage == 'System',
                      isLight: isLight,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        appSettings.setSelectedLanguage('System');
                        closeLanguageAndSettings();
                      }),

                    SizedBox(height: 20),

                    // North America
                    _buildLanguageSectionHeader(
                      AppLocalizations.of(context)?.northAmerica ?? AppLocalizations.of(context)!.tr('NORTH AMERICA'),
                      isLight),
                    ...northAmerica.map(
                      (locale) => _buildLanguageOptionTile(
                        flag: locale.flag,
                        displayName: locale.displayName,
                        region: locale.region,
                        isSelected: appSettings.selectedLanguage == locale.code,
                        isLight: isLight,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          appSettings.setSelectedLanguage(locale.code);
                          closeLanguageAndSettings();
                        })),

                    SizedBox(height: 20),

                    // Europe
                    _buildLanguageSectionHeader(
                      AppLocalizations.of(context)?.europeanUnion ?? AppLocalizations.of(context)!.tr('EUROPEAN UNION'),
                      isLight),
                    ...eu.map(
                      (locale) => _buildLanguageOptionTile(
                        flag: locale.flag,
                        displayName: locale.displayName,
                        region: locale.region,
                        isSelected: appSettings.selectedLanguage == locale.code,
                        isLight: isLight,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          appSettings.setSelectedLanguage(locale.code);
                          closeLanguageAndSettings();
                        })),

                    SizedBox(height: 20),

                    // Russia
                    _buildLanguageSectionHeader(
                      AppLocalizations.of(context)?.russia ?? AppLocalizations.of(context)!.tr('RUSSIA'),
                      isLight),
                    ...russia.map(
                      (locale) => _buildLanguageOptionTile(
                        flag: locale.flag,
                        displayName: locale.displayName,
                        region: locale.region,
                        isSelected: appSettings.selectedLanguage == locale.code,
                        isLight: isLight,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          appSettings.setSelectedLanguage(locale.code);
                          closeLanguageAndSettings();
                        })),
                  ]))),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel Button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              isSecondary: true,
              height: 50,
              onPressed: () {
                closeLanguageAndSettings();
              }),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          ]))).whenComplete(() {
      NavigationVisibility.show();
    });
  }

  Widget _buildLanguageSectionHeader(String title, bool isLight) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
          letterSpacing: 1.2)));
  }

  Widget _buildLanguageOptionTile({
    required String flag,
    required String displayName,
    required String region,
    required bool isSelected,
    required bool isLight,
    required VoidCallback onTap,
  }) {
    return TradeRepublicTap(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : (isLight ? Colors.black : Colors.white).withOpacity(0.04),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Row(
          children: [
            Text(flag, style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 10),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? (isLight ? Colors.white : Colors.black)
                          : (isLight ? Colors.black : Colors.white))),
                  SizedBox(height: 2),
                  Text(
                    displayName ==
                            (AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System'))
                        ? (AppLocalizations.of(
                                context)?.followsDeviceSettings ?? AppLocalizations.of(context)!.tr('Follows device settings'))
                        : region,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: isSelected
                          ? (isLight ? Colors.white : Colors.black).withOpacity(
                              0.6)
                          : (isLight ? Colors.black : Colors.white).withOpacity(
                              0.5))),
                ])),
            if (isSelected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: isLight ? Colors.white : Colors.black,
                size: 20),
          ])));
  }

  // Small options modal used by settings rows
  // Options modal that stores internal keys but displays localized names
  void _settings_showMappedOptions({
    required String title,
    required Map<String, String> options, // key (internal) → display name
    required String selectedKey,
    required Function(String) onSelect,
    required bool isLight,
  }) {
    final ctx = _scaffoldKey.currentContext!;
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: ctx,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),

          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.list_bullet,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4))),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 20),

          Column(
            children: options.entries.map((entry) {
              final key = entry.key;
              final displayName = entry.value;
              final isSelected = selectedKey == key;
              return TradeRepublicTap(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSelect(key);
                  Navigator.pop(context); // Close options modal
                  Navigator.pop(ctx); // Close app settings modal
                },
                child: Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isLight ? Colors.black : Colors.white)
                        : (isLight ? Colors.black : Colors.white).withOpacity(
                            0.04),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? (isLight ? Colors.white : Colors.black)
                                    : (isLight ? Colors.black : Colors.white))),
                            if (key == 'System')
                              Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Text(
                                  AppLocalizations.of(
                                        context)?.followsDeviceSettings ?? AppLocalizations.of(context)!.tr('Follows device settings'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: isSelected
                                        ? (isLight
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withOpacity(0.6)
                                        : (isLight
                                                  ? Colors.black
                                                  : Colors.white)
                                              .withOpacity(0.5)))),
                          ])),
                      if (isSelected)
                        Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: isLight ? Colors.white : Colors.black,
                          size: 20),
                    ])));
            }).toList()),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            isSecondary: true,
            height: 50,
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(ctx);
            }),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        ])).whenComplete(() {
      NavigationVisibility.show();
      if (Navigator.canPop(ctx)) {
        Navigator.pop(ctx);
      }
    });
  }

  void _settings_showOptions({
    BuildContext? parentContext,
    required String title,
    required List<String> options,
    required String selected,
    required Function(String) onSelect,
    required bool isLight,
  }) {
    final ctx = parentContext ?? _scaffoldKey.currentContext!;
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: ctx,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),

          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.list_bullet,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4))),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 20),

          // Options List
          Column(
            children: options.map((opt) {
              final isSelected = selected == opt;
              return TradeRepublicTap(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSelect(opt);
                  Navigator.pop(context); // Close options modal
                  Navigator.pop(ctx); // Close app settings modal
                },
                child: Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isLight ? Colors.black : Colors.white)
                        : (isLight ? Colors.black : Colors.white).withOpacity(
                            0.04),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? (isLight ? Colors.white : Colors.black)
                                    : (isLight ? Colors.black : Colors.white))),
                            if (opt ==
                                (AppLocalizations.of(context)?.system ?? AppLocalizations.of(context)!.tr('System')))
                              Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Text(
                                  AppLocalizations.of(
                                        context)?.followsDeviceSettings ?? AppLocalizations.of(context)!.tr('Follows device settings'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: isSelected
                                        ? (isLight
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withOpacity(0.6)
                                        : (isLight
                                                  ? Colors.black
                                                  : Colors.white)
                                              .withOpacity(0.5)))),
                          ])),
                      if (isSelected)
                        Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: isLight ? Colors.white : Colors.black,
                          size: 20),
                    ])));
            }).toList()),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Cancel Button - Trade Republic Style
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            isSecondary: true,
            height: 50,
            onPressed: () {
              Navigator.pop(context); // Close options modal
              Navigator.pop(ctx); // Close app settings modal
            }),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        ])).whenComplete(() {
      NavigationVisibility.show();
      // Also close app settings modal when options modal is dismissed by swiping down
      if (Navigator.canPop(ctx)) {
        Navigator.pop(ctx);
      }
    });
  }

  Widget _buildStatusBadge(String text, bool isLight) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isLight ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: isLight ? Colors.white : Colors.black,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.5)));
  }

  Widget _buildGroupOverviewDashboard(bool isLight) {
    final isInGroup = currentGroup != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: 20),
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : Colors.black,
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppLocalizations.of(context)?.group ?? AppLocalizations.of(context)!.tr('GROUP'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: isLight ? Colors.black : Colors.white)),
                  const Spacer(),
                  if (isInGroup)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.06),
                        borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        _groupRoleBadge(currentGroup?['role']),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: isLight ? Colors.black : Colors.white)))
                  else if (!_isBusinessEditOpen)
                    TradeRepublicButton.icon(
                      icon: Icon(CupertinoIcons.add, size: 16),
                      onPressed: () => _showCreateGroupModal(context, isLight),
                      size: 32),
                ]),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Current Group Status
              _buildCurrentGroupStatus(isLight),

              SizedBox(height: 14),

              // Group Actions
              Row(
                children: [
                  Expanded(
                    child: _buildGroupActionCard(
                      isInGroup
                          ? 'Members'
                          : (AppLocalizations.of(context)?.join ?? AppLocalizations.of(context)!.tr('Join')),
                      isInGroup
                          ? 'See everyone in your group'
                          : (AppLocalizations.of(context)?.findGroups ?? AppLocalizations.of(context)!.tr('Find Groups')),
                      isInGroup
                          ? CupertinoIcons.person_2_fill
                          : CupertinoIcons.person_add,
                      Colors.black,
                      isLight,
                      () => isInGroup
                          ? _showGroupMembersModal(isLight)
                          : _showJoinGroupModal(context, isLight))),
                  SizedBox(width: 10),
                  Expanded(
                    child: _buildGroupActionCard(
                      isInGroup
                          ? 'Manage'
                          : (AppLocalizations.of(context)?.explore ?? AppLocalizations.of(context)!.tr('Explore')),
                      isInGroup
                          ? 'Open group settings'
                          : (AppLocalizations.of(context)?.browse ?? AppLocalizations.of(context)!.tr('Browse')),
                      isInGroup
                          ? CupertinoIcons.settings_solid
                          : CupertinoIcons.compass,
                      Colors.black,
                      isLight,
                      () => isInGroup
                          ? _showGroupSettingsModal(context, isLight)
                          : _showExploreGroupsModal(context, isLight))),
                ]),
            ]))));
  }

  Widget _buildCurrentGroupStatus(bool isLight) {
    final isInGroup = currentGroup != null;
    final groupName = currentGroup?['name'] ?? AppLocalizations.of(context)!.tr('');
    final groupCode = currentGroup?['code'] ?? AppLocalizations.of(context)!.tr('');
    final roleTitle = _groupRoleHeadline(currentGroup?['role']);
    final isAdmin = _isCurrentGroupAdmin;
    final profileImage = currentGroup?['profileImage']?.toString();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isInGroup
            ? (isAdmin
                  ? const Color(0xFF111111)
                  : (isLight
                        ? Colors.transparent
                        : const Color(0xFF111111)))
            : (isLight ? Colors.white : Colors.black),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGroupAvatar(
                profileImage,
                label: isInGroup ? groupName : 'Group',
                isLight: isLight,
                size: 56,
                highlight: isInGroup && isAdmin),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isInGroup
                          ? groupName
                          : (AppLocalizations.of(context)?.noGroup ?? AppLocalizations.of(context)!.tr('No Group')),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: (isInGroup && isAdmin)
                            ? Colors.white
                            : (isLight ? Colors.black : Colors.white)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                    SizedBox(height: 4),
                    Text(
                      isInGroup
                          ? '$roleTitle • Code: $groupCode'
                          : (AppLocalizations.of(context)?.joinOrCreateGroup ?? AppLocalizations.of(context)!.tr('Join or create a group to collaborate with other businesses')),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: (isInGroup && isAdmin)
                            ? Colors.white.withOpacity(0.72)
                            : (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.6)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                    if (isInGroup) ...[
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7),
                            decoration: BoxDecoration(
                              color: isAdmin
                                  ? Colors.white.withOpacity(0.14)
                                  : (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              _groupRoleBadge(currentGroup?['role']),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: isAdmin
                                    ? Colors.white
                                    : (isLight ? Colors.black : Colors.white)))),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7),
                            decoration: BoxDecoration(
                              color: isAdmin
                                  ? Colors.white.withOpacity(0.14)
                                  : (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              '${currentGroup?['memberCount'] ?? 0} members',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: isAdmin
                                    ? Colors.white
                                    : (isLight ? Colors.black : Colors.white)))),
                        ]),
                    ],
                  ])),
              if (isInGroup && !_isBusinessEditOpen)
                TradeRepublicButton.icon(
                  icon: Icon(CupertinoIcons.settings, size: 18),
                  onPressed: () => _showGroupSettingsModal(context, isLight),
                  size: 36),
            ]),
        ]));
  }

  Widget _buildGroupActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    bool isLight,
    VoidCallback onTap) {
    // Minimalist Trade Republic style - solid black/white
    return TradeRepublicCard(
      onTap: onTap,
      padding: DesktopAppWrapper.getPagePadding(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isLight ? Colors.black : Colors.white, size: 22),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: isLight ? Colors.black : Colors.white)),
          SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isLight ? Colors.black : Colors.white,
              fontWeight: FontWeight.w500)),
        ]));
  }

  Widget _buildBusinessInfoSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header - Trade Republic Style
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)!.tr('Personal Information') ?? AppLocalizations.of(context)!.tr('Personal Information'),
          trailing: !_isBusinessEditOpen
              ? TradeRepublicButton.icon(
                  icon: Icon(Icons.edit, size: 18),
                  onPressed: () => _showPersonalEditModal(context, isLight),
                  size: 36,
                  isSecondary: true)
              : null,
          padding: EdgeInsets.only(bottom: 16, top: 8)),
        TradeRepublicCard(
          padding: DesktopAppWrapper.getPagePadding(),
          child: Column(
            children: [
              _buildInfoRow(
                AppLocalizations.of(context)?.username ?? AppLocalizations.of(context)!.tr('Username'),
                userData?['username']?.toString() ?? AppLocalizations.of(context)!.tr('-'),
                Icons.account_circle,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.firstName ?? AppLocalizations.of(context)!.tr('First Name'),
                userData?['firstname']?.toString() ?? AppLocalizations.of(context)!.tr('-'),
                CupertinoIcons.person_fill,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.lastName ?? AppLocalizations.of(context)!.tr('Last Name'),
                userData?['lastname']?.toString() ?? AppLocalizations.of(context)!.tr('-'),
                CupertinoIcons.person,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.businessName ?? AppLocalizations.of(context)!.tr('Business Name'),
                userData?['businessName'] ??
                    userData?['business_company'] ?? AppLocalizations.of(context)!.tr('-'),
                CupertinoIcons.building_2_fill,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.email ?? AppLocalizations.of(context)!.tr('Email'),
                userData?['email'] ?? AppLocalizations.of(context)!.tr('-'),
                CupertinoIcons.mail,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.phone ?? AppLocalizations.of(context)!.tr('Phone'),
                userData?['phone'] ?? AppLocalizations.of(context)!.tr('-'),
                CupertinoIcons.phone,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.birthdate ?? AppLocalizations.of(context)!.tr('Birthdate'),
                userData?['birthdate']?.toString().substring(0, 10) ?? AppLocalizations.of(context)!.tr('-'),
                Icons.cake,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.businessAddress ?? AppLocalizations.of(context)!.tr('Business Address'),
                userData?['businessAddress'] ?? userData?['street'] ?? AppLocalizations.of(context)!.tr('-'),
                CupertinoIcons.location_solid,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.businessWebsite ?? AppLocalizations.of(context)!.tr('Business Website'),
                userData?['businessWebsite'] ?? AppLocalizations.of(context)!.tr('-'),
                Icons.language,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.businessDescription ?? AppLocalizations.of(context)!.tr('Business Description'),
                userData?['businessDescription'] ?? AppLocalizations.of(context)!.tr('-'),
                Icons.description,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.businessSize ?? AppLocalizations.of(context)!.tr('Business Size'),
                userData?['business_size'] ?? AppLocalizations.of(context)!.tr('-'),
                CupertinoIcons.person_2_fill,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.country ?? AppLocalizations.of(context)!.tr('Country'),
                userData?['business_country'] ?? AppLocalizations.of(context)!.tr('-'),
                CupertinoIcons.globe,
                isLight),
            ])),
        SizedBox(height: 20),
      ]);
  }

  Widget _buildPersonalInfoSection(bool isLight) {
    return const SizedBox.shrink();
  }

  Widget _buildAccountSettingsSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header - Trade Republic Style
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.settings ?? AppLocalizations.of(context)!.tr('Settings'),
          padding: EdgeInsets.only(bottom: 16, top: 8)),
        TradeRepublicCard(
          padding: DesktopAppWrapper.getPagePadding(),
          child: Column(
            children: [
              _buildAccountOption(
                icon: Icons.lock_outline,
                title:
                    AppLocalizations.of(context)?.changePassword ?? AppLocalizations.of(context)!.tr('Change Password'),
                subtitle:
                    AppLocalizations.of(context)?.updateAccountPassword ?? AppLocalizations.of(context)!.tr('Update your account password'),
                isLight: isLight,
                onTap: () => _showChangePasswordModal(context, isLight)),
              _buildAccountOption(
                icon: Icons.security,
                title:
                    AppLocalizations.of(context)?.securitySettings ?? AppLocalizations.of(context)!.tr('Security Settings'),
                subtitle:
                    AppLocalizations.of(context)?.twoFactorBiometrics ?? AppLocalizations.of(context)!.tr('Two-factor authentication, biometrics'),
                isLight: isLight,
                onTap: () => _showSecuritySettingsModal(context, isLight)),
              _buildAccountOption(
                icon: Icons.payment,
                title:
                    AppLocalizations.of(context)?.paymentSettings ?? AppLocalizations.of(context)!.tr('Payment Settings'),
                subtitle:
                    AppLocalizations.of(context)?.bankDetailsPaymentMethods ?? AppLocalizations.of(context)!.tr('Bank details, payment methods'),
                isLight: isLight,
                onTap: () => _showPaymentSettingsModal(context, isLight)),
            ])),
        SizedBox(height: 20),
      ]);
  }

  Widget _buildSecurityPrivacySection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header - Trade Republic Style
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.privacy ?? AppLocalizations.of(context)!.tr('Privacy'),
          padding: EdgeInsets.only(bottom: 16, top: 8)),
        TradeRepublicCard(
          padding: DesktopAppWrapper.getPagePadding(),
          child: Column(
            children: [
              _buildInfoRow(
                AppLocalizations.of(context)?.twoFA ?? AppLocalizations.of(context)!.tr('2FA'),
                (userData?['has_2fa_enabled'] == 1)
                    ? (AppLocalizations.of(context)?.on_ ?? AppLocalizations.of(context)!.tr('On'))
                    : (AppLocalizations.of(context)?.off_ ?? AppLocalizations.of(context)!.tr('Off')),
                Icons.security,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.biometricLogin ?? AppLocalizations.of(context)!.tr('Biometric Login'),
                (userData?['biometric_enabled'] == 1)
                    ? (AppLocalizations.of(context)?.enabled ?? AppLocalizations.of(context)!.tr('Enabled'))
                    : (AppLocalizations.of(context)?.disabled ?? AppLocalizations.of(context)!.tr('Disabled')),
                Icons.fingerprint,
                isLight),
            ])),

        // Interactive toggles for notifications
        TradeRepublicCard(
          margin: EdgeInsets.only(top: 16),
          padding: DesktopAppWrapper.getPagePadding(),
          child: Column(
            children: [
              _buildNotificationToggle(
                AppLocalizations.of(context)?.loginNotifications ?? AppLocalizations.of(context)!.tr('Login Notifications'),
                AppLocalizations.of(context)?.loginNotificationsDesc ?? AppLocalizations.of(context)!.tr('Get notified when someone logs into your account'),
                userData?['notifications_login'] == 1,
                Icons.login,
                isLight,
                (value) => _toggleLoginNotificationsInPrivacy(value)),
              if (userData?['supportsNewsletterPrefs'] == true)
                _buildNotificationToggle(
                  AppLocalizations.of(context)?.newsletterSubscription ?? AppLocalizations.of(context)!.tr('Newsletter Subscription'),
                  AppLocalizations.of(context)?.newsletterDesc ?? AppLocalizations.of(context)!.tr('Receive updates and promotional emails'),
                  userData?['notifications_newsletter'] == 1,
                  Icons.mail_outline,
                  isLight,
                  (value) => _toggleNewsletterSubscription(value)),
            ])),
        SizedBox(height: 20),
      ]);
  }

  Widget _buildSocialCommunitySection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header - Trade Republic Style
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.community ?? AppLocalizations.of(context)!.tr('Community'),
          trailing: (!_isAppSettingsOpen && !_isBusinessEditOpen)
              ? TradeRepublicButton(
                  label: AppLocalizations.of(context)?.viewAll ?? AppLocalizations.of(context)!.tr('View All'),
                  isSecondary: true,
                  height: 50,
                  onPressed: () => _showFollowersModal(context, isLight))
              : null,
          padding: EdgeInsets.only(bottom: 16, top: 8)),
        TradeRepublicCard(
          padding: DesktopAppWrapper.getPagePadding(),
          child: Column(
            children: [
              _buildInfoRow(
                AppLocalizations.of(context)?.followers ?? AppLocalizations.of(context)!.tr('Followers'),
                '${socialStats['followers_count'] ?? userData?['followers_count'] ?? 0}',
                CupertinoIcons.person_2_fill,
                isLight),
              _buildInfoRow(
                AppLocalizations.of(context)?.following ?? AppLocalizations.of(context)!.tr('Following'),
                '${socialStats['following_count'] ?? userData?['following_count'] ?? 0}',
                CupertinoIcons.person_add_solid,
                isLight),
            ])),

        // Show recent followers if any
        if (followers.isNotEmpty) ...[
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          TradeRepublicCard(
            padding: DesktopAppWrapper.getPagePadding(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.recentFollowers ?? AppLocalizations.of(context)!.tr('Recent Followers'),
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7))),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: followers.take(5).length,
                    itemBuilder: (context, index) {
                      final follower = followers[index];
                      return Container(
                        margin: EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.1)),
                              child: Center(
                                child: Text(
                                  (follower['name'] ??
                                          follower['username'] ?? AppLocalizations.of(context)!.tr('U'))
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w700,
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white)))),
                            SizedBox(height: 4),
                            Text(
                              (follower['name'] ??
                                      follower['username'] ?? AppLocalizations.of(context)!.tr('User'))
                                  .split(' ')
                                  .first,
                              style: TextStyle(
                                fontSize: 10,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          ]));
                    })),
              ])),
        ],
        SizedBox(height: 20),
      ]);
  }

  Widget _buildVerificationStatusButton(bool isLight) {
    final hasConnectedBank =
        BusinessAccountPage.hasConnectedPaymentSetup(userData) ||
        _hasConnectedPaymentMethod;

    // Calculate verification score based on actual data
    List<String> verifiedItems = [];
    List<String> pendingItems = [];

    // Business Profile complete
    if (BusinessAccountPage.hasCompleteBusinessProfile(userData)) {
      verifiedItems.add('Profile');
    } else {
      pendingItems.add('Profile');
    }

    // Bank Account
    if (hasConnectedBank) {
      verifiedItems.add('Bank');
    } else {
      pendingItems.add('Bank');
    }

    final isFullyVerified = verifiedItems.length == 2;

    return TradeRepublicCard(
      onTap: () {
        HapticFeedback.lightImpact();
        _showVerificationCenterModal(context, isLight);
      },
      width: double.infinity,
      padding: DesktopAppWrapper.getPagePadding(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isFullyVerified
                  ? Colors.green.withOpacity(0.1)
                  : isLight
                  ? Colors.white
                  : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Icon(
              isFullyVerified
                  ? Icons.verified
                  : CupertinoIcons.checkmark_seal_fill,
              color: isFullyVerified
                  ? Colors.green
                  : (isLight ? Colors.black : Colors.white).withOpacity(0.5),
              size: 22)),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.verificationCenter ?? AppLocalizations.of(context)!.tr('Verification Center'),
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white)),
                SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4),
                  decoration: BoxDecoration(
                    color: isFullyVerified
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Text(
                    isFullyVerified
                        ? (AppLocalizations.of(context)?.fullyVerified ?? AppLocalizations.of(context)!.tr('Fully Verified'))
                        : '${verifiedItems.length}/2 ${AppLocalizations.of(context)?.complete ?? AppLocalizations.of(context)!.tr('complete')}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isFullyVerified ? Colors.green : Colors.orange))),
              ])),
          Icon(
            CupertinoIcons.chevron_right,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
            size: 22),
        ]));
  }

  Widget _buildTaxFormsSection(bool isLight) {
    // Check if user has Stripe account and tax form status
    final hasStripeAccount = BusinessAccountPage.hasConnectedPaymentSetup(
      userData);
    final taxFormStatus =
        userData?['tax_form_status'] ?? AppLocalizations.of(context)!.tr('not_started'); // not_started, pending, completed
    final taxFormType =
        userData?['tax_form_type'] ?? AppLocalizations.of(context)!.tr('unknown'); // w9, w8ben, w8bene

    // Determine status colors and labels
    String statusLabel;
    IconData statusIcon;
    Color badgeColor;

    switch (taxFormStatus) {
      case 'completed':
        badgeColor = Colors.green;
        statusLabel =
            AppLocalizations.of(context)?.taxFormCompleted ?? AppLocalizations.of(context)!.tr('Tax Form Completed');
        statusIcon = CupertinoIcons.check_mark_circled_solid;
        break;
      case 'pending':
        badgeColor = Colors.orange;
        statusLabel =
            AppLocalizations.of(context)?.taxFormPendingReview ?? AppLocalizations.of(context)!.tr('Tax Form Pending Review');
        statusIcon = Icons.pending;
        break;
      default:
        badgeColor = Colors.red;
        statusLabel =
            AppLocalizations.of(context)?.taxFormRequiredLabel ?? AppLocalizations.of(context)!.tr('Tax Form Required');
        statusIcon = Icons.warning;
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Delvioo-style header
          Text(
            AppLocalizations.of(context)?.taxForms ?? AppLocalizations.of(context)!.tr('Tax Forms'),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: isLight ? Colors.black : Colors.white)),
          SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)?.taxFormDesc ?? AppLocalizations.of(context)!.tr('W-9 or W-8 form required for payouts (self-service via Stripe)'),
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Status Badge - Delvioo style
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Row(
              children: [
                Icon(statusIcon, color: badgeColor, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: badgeColor)),
                      if (taxFormStatus == 'completed' &&
                          taxFormType != 'unknown')
                        Text(
                          '${AppLocalizations.of(context)?.formType ?? AppLocalizations.of(context)!.tr('Form Type')}: ${taxFormType.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 12,
                            color: badgeColor.withOpacity(0.8))),
                    ])),
              ])),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Information Box - Delvioo style
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.1),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Icon(
                    CupertinoIcons.info_circle,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.6),
                    size: 18)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasStripeAccount
                        ? (AppLocalizations.of(context)?.completeTaxFormDesc ?? AppLocalizations.of(context)!.tr('Complete your tax form yourself via Stripe to receive payouts'))
                        : (AppLocalizations.of(context)?.connectBankFirstTax ?? AppLocalizations.of(context)!.tr('Connect a bank account first to access tax forms')),
                    style: TextStyle(
                      fontSize: 13,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.7)))),
              ])),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Action Button - Delvioo style
          TradeRepublicButton(
            label: hasStripeAccount
                ? (taxFormStatus == 'completed'
                      ? (AppLocalizations.of(context)?.viewUpdateTaxForm ?? AppLocalizations.of(context)!.tr('View/Update Tax Form'))
                      : (AppLocalizations.of(context)?.completeTaxForm ?? AppLocalizations.of(context)!.tr('Complete Tax Form (Self-Service)')))
                : (AppLocalizations.of(context)?.bankAccountRequired ?? AppLocalizations.of(context)!.tr('Bank Account Required')),
            height: 50,
            onPressed: hasStripeAccount
                ? () {
                    HapticFeedback.lightImpact();
                    _showTaxFormsModal(context, isLight);
                  }
                : () {
                    HapticFeedback.lightImpact();
                    TopNotification.info(
                      context,
                      AppLocalizations.of(context)?.connectBankFirst ?? AppLocalizations.of(context)!.tr('Please connect a bank account first'));
                  }),
        ]));
  }

  Widget _buildAccountManagementSection(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: AppLocalizations.of(context)?.account ?? AppLocalizations.of(context)!.tr('Account'),
          padding: EdgeInsets.only(bottom: 16, top: 8)),
        TradeRepublicCard(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              // App Settings Button
              _buildAccountOption(
                icon: CupertinoIcons.settings,
                title:
                    AppLocalizations.of(context)?.appSettings ?? AppLocalizations.of(context)!.tr('App Settings'),
                subtitle:
                    AppLocalizations.of(context)?.customizeAppSettings ?? AppLocalizations.of(context)!.tr('Customize appearance, language, and preferences'),
                isLight: isLight,
                onTap: () => _showAppSettingsModal(context, isLight)),

              TradeRepublicDivider(),

              // Sign Out Button
              _buildAccountOption(
                icon: CupertinoIcons.square_arrow_right,
                title: AppLocalizations.of(context)?.signOut ?? AppLocalizations.of(context)!.tr('Sign Out'),
                subtitle:
                    AppLocalizations.of(context)?.signOutDesc ?? AppLocalizations.of(context)!.tr('Sign out from your business account'),
                isLight: isLight,
                onTap: () => _showSignOutModal(context, isLight),
                isDestructive: true),
            ])),
        SizedBox(height: 20),
      ]);
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon,
    bool isLight) {
    return TradeRepublicListTile(
      title: label,
      subtitle: value,
      leading: Icon(icon, size: 18),
      padding: EdgeInsets.symmetric(vertical: 12));
  }

  Widget _buildAccountOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLight,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    const tilePadding = EdgeInsets.symmetric(horizontal: 8, vertical: 12);

    if (isDestructive) {
      return TradeRepublicListTile.destructive(
        title: title,
        subtitle: subtitle,
        leading: Icon(icon, size: 20),
        onTap: onTap,
        padding: tilePadding);
    }
    return TradeRepublicListTile.navigation(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon, size: 20),
      onTap: onTap,
      padding: tilePadding);
  }

  // Modal implementations
  void _showProfilePictureModal(BuildContext context, bool isLight) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),

          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.photo_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.businessLogo ?? AppLocalizations.of(context)!.tr('Business Logo'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 32),

          // Current Logo Display - minimalist
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              color: isLight
                  ? const Color(0xFFF2F2F2)
                  : const Color(0xFF1F1F1F)),
            clipBehavior: Clip.antiAlias,
            child:
                userData?['profilePic'] != null &&
                    userData!['profilePic'].toString().trim().isNotEmpty
                ? Image.network(
                    _buildImageUrl(userData!['profilePic']),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        CupertinoIcons.building_2_fill,
                        color: isLight ? Colors.black : Colors.white,
                        size: 40);
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(child: CultiooLoadingIndicator());
                    })
                : Icon(
                    CupertinoIcons.building_2_fill,
                    color: isLight ? Colors.black : Colors.white,
                    size: 40)),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Description
          Text(
            AppLocalizations.of(context)?.imageFormats ?? AppLocalizations.of(context)!.tr('JPG, PNG or GIF • Max 5MB'),
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w500,
              color: isLight ? Colors.black : Colors.white)),

          SizedBox(height: 32),

          // Gallery button - minimalist primary
          TradeRepublicButton(
            label:
                AppLocalizations.of(context)?.chooseFromGallery ?? AppLocalizations.of(context)!.tr('Choose from Gallery'),
            height: 50,
            onPressed: () {
              HapticFeedback.lightImpact();
              _uploadProfilePicture(context, ImageSource.gallery);
            }),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Camera button - minimalist secondary
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.takePhoto ?? AppLocalizations.of(context)!.tr('Take Photo'),
            isSecondary: true,
            height: 50,
            onPressed: () {
              HapticFeedback.lightImpact();
              _uploadProfilePicture(context, ImageSource.camera);
            }),

          if (userData?['profilePic'] != null &&
              userData!['profilePic'].toString().trim().isNotEmpty) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Remove button - minimalist red
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.removeLogo ?? AppLocalizations.of(context)!.tr('Remove Logo'),
              isDestructive: true,
              height: 50,
              onPressed: () {
                HapticFeedback.lightImpact();
                _removeProfilePicture(context);
              }),
          ],
        ])).whenComplete(() => NavigationVisibility.show());
  }

  void _showBusinessEditModal(BuildContext context, bool isLight) {
    // Parse existing address into components
    String existingAddress = userData?['businessAddress'] ?? AppLocalizations.of(context)!.tr('');
    String street = '';
    String houseNumber = '';
    String zipCode = '';
    String city = '';
    String state = '';

    // Try to parse existing address into components robustly.
    // Addresses come in many formats (e.g. "Main Street 123, 40477 Dortmund, Germany"
    // or "123 Main St, Springfield, IL 62704, USA"). We'll look for tokens that
    // contain digits (likely house number or zip) and fall back to simple splits.
    if (existingAddress.isNotEmpty) {
      try {
        final parts = existingAddress
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        // ---- Street & house number ----
        if (parts.isNotEmpty) {
          final streetPart = parts[0];
          final streetTokens = streetPart
              .split(RegExp(r'\s+'))
              .where((t) => t.isNotEmpty)
              .toList();

          // Prefer a token containing a digit as house number. Try last, then first, then any.
          String? foundNumber;
          bool containsDigit(String s) => RegExp(r'\d').hasMatch(s);

          if (streetTokens.isNotEmpty && containsDigit(streetTokens.last)) {
            foundNumber = streetTokens.last;
            street = streetTokens.sublist(0, streetTokens.length - 1).join(' ');
          } else if (streetTokens.isNotEmpty &&
              containsDigit(streetTokens.first)) {
            foundNumber = streetTokens.first;
            street = streetTokens.sublist(1).join(' ');
          } else {
            final anyWithDigit = streetTokens.firstWhere(
              (t) => containsDigit(t),
              orElse: () => '');
            if (anyWithDigit.isNotEmpty) {
              foundNumber = anyWithDigit;
              final idx = streetTokens.indexOf(anyWithDigit);
              final left = streetTokens.sublist(0, idx);
              final right = streetTokens.sublist(idx + 1);
              street = [...left, ...right].join(' ');
            } else {
              // No obvious house number - keep whole as street
              street = streetPart;
            }
          }

          if (foundNumber != null && foundNumber.isNotEmpty) {
            houseNumber = foundNumber;
          }
        }

        // ---- City / State / ZIP ----
        // Join the remaining parts and attempt to find a zip code (sequence of 3-6 digits).
        if (parts.length >= 2) {
          final remainingParts = parts
              .sublist(1)
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          final remaining = remainingParts.join(', ');

          // Helper: known country names to avoid assigning them into `state`
          final knownCountries = [
            'germany',
            'deutschland',
            'united states',
            'usa',
            'austria',
            'switzerland',
            'france',
            'italy',
            'spain',
            'netherlands',
            'uk',
            'united kingdom',
          ];

          // Try to find a zip code anywhere in the remaining text
          final zipMatch = RegExp(r'\b\d{3,6}\b').firstMatch(remaining);
          String working = remaining;
          if (zipMatch != null) {
            zipCode = zipMatch.group(0) ?? AppLocalizations.of(context)!.tr('');
            // Remove the zip from the working string
            working = working
                .replaceFirst(zipMatch.group(0)!, '')
                .replaceAll(',', ' ')
                .trim();
          }

          // Tokenize the remaining (without zip) to determine city/state/country
          final tokens = working
              .split(RegExp(r'[\s,]+'))
              .where((t) => t.isNotEmpty)
              .toList();

          // If the last token is a known country, strip it off before assigning state
          String parsedCountry = '';
          if (tokens.isNotEmpty &&
              knownCountries.contains(tokens.last.toLowerCase())) {
            parsedCountry = tokens.removeLast();
          }

          if (tokens.isEmpty) {
            city = '';
            state = '';
          } else if (tokens.length == 1) {
            city = tokens[0];
            state = '';
          } else {
            // At least two tokens remain - assume last token is state (region) and the rest form the city
            state = tokens.last;
            city = tokens.sublist(0, tokens.length - 1).join(' ');
          }

          // If we stripped a country token and `state` currently equals that country (safety), clear state
          if (parsedCountry.isNotEmpty &&
              state.toLowerCase() == parsedCountry.toLowerCase()) {
            state = '';
          }

          // If city accidentally contains digits (house number), move those tokens to houseNumber.
          if (city.isNotEmpty && RegExp(r'\d').hasMatch(city)) {
            final cityTokens = city
                .split(RegExp(r'\s+'))
                .where((t) => t.isNotEmpty)
                .toList();
            final extractedNumberTokens = cityTokens
                .where((t) => RegExp(r'\d').hasMatch(t))
                .toList();
            if (extractedNumberTokens.isNotEmpty) {
              final extracted = extractedNumberTokens.join(' ');
              cityTokens.removeWhere((t) => RegExp(r'\d').hasMatch(t));
              city = cityTokens.join(' ').trim();
              if (houseNumber.isEmpty) {
                houseNumber = extracted;
              } else if (!houseNumber.contains(extracted)) {
                houseNumber = ('$houseNumber $extracted').trim();
              }
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Could not parse address: $e');
      }
    }

    // Create controllers with current values
    final businessNameController = TextEditingController(
      text: userData?['businessName'] ?? AppLocalizations.of(context)!.tr(''));
    final businessDescriptionController = TextEditingController(
      text: userData?['businessDescription'] ?? AppLocalizations.of(context)!.tr(''));
    final businessWebsiteController = TextEditingController(
      text: userData?['businessWebsite'] ?? AppLocalizations.of(context)!.tr(''));
    final streetController = TextEditingController(text: street);
    final houseNumberController = TextEditingController(text: houseNumber);
    final cityController = TextEditingController(text: city);
    final stateController = TextEditingController(text: state);
    final zipCodeController = TextEditingController(text: zipCode);

    // Get current values from userData (use the keys actually used in _loadUserData)
    String selectedCountry =
        userData?['business_country'] ??
        userData?['country'] ?? AppLocalizations.of(context)!.tr('United States');
    String selectedSize =
        userData?['business_size'] ??
        userData?['businessSize'] ?? AppLocalizations.of(context)!.tr('1-10 employees');

    // Create visibility state variables
    bool showPhone = userData?['showPhone'] == 1;
    bool showBusinessSize = userData?['showBusinessSize'] == 1;
    bool showBusinessCompany = userData?['showBusinessCompany'] == 1;
    bool showBusinessEmail = userData?['showBusinessEmail'] == 1;
    bool showBusinessCountry = userData?['showBusinessCountry'] == 1;

    setState(() => _isBusinessEditOpen = true);
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      enableDrag: true,
      child: StatefulBuilder(
        builder: (context, setModalState) => Material(
          color: Colors.transparent,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DragHandle(),

                // ── Sheet header: Icon left + Title ──
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.briefcase_fill,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white),
                    SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.editPersonalInfo ?? AppLocalizations.of(context)!.tr('Edit Personal Information'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4)),
                  ]),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                SizedBox(height: 32),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.only(bottom: 20),
                    child: Column(
                      children: [
                        // Business Information Section
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(
                                    context)?.businessInformation ?? AppLocalizations.of(context)!.tr('Business Information'),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w700,
                                color: isLight ? Colors.black : Colors.white)),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            _buildEditableBusinessField(
                              AppLocalizations.of(context)?.businessName ??
                                  AppLocalizations.of(context)?.businessName ?? AppLocalizations.of(context)!.tr('Business Name'),
                              businessNameController,
                              CupertinoIcons.building_2_fill,
                              isLight),
                            _buildEditableBusinessField(
                              AppLocalizations.of(
                                    context)?.businessDescription ??
                                  AppLocalizations.of(
                                    context)?.businessDescription ?? AppLocalizations.of(context)!.tr('Business Description'),
                              businessDescriptionController,
                              Icons.description,
                              isLight,
                              maxLines: 3),
                            _buildEditableBusinessField(
                              AppLocalizations.of(context)?.businessWebsite ??
                                  AppLocalizations.of(
                                    context)?.businessWebsite ?? AppLocalizations.of(context)!.tr('Business Website'),
                              businessWebsiteController,
                              Icons.language,
                              isLight),
                          ]),

                        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                        // Business Address Section
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)?.businessAddress ?? AppLocalizations.of(context)!.tr('Business Address'),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w700,
                                color: isLight ? Colors.black : Colors.white)),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                            // Street and House Number
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildEditableBusinessField(
                                    AppLocalizations.of(context)?.street ?? AppLocalizations.of(context)!.tr('Street'),
                                    streetController,
                                    CupertinoIcons.location_solid,
                                    isLight)),
                                SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: _buildEditableBusinessField(
                                    AppLocalizations.of(context)?.numberLabel ?? AppLocalizations.of(context)!.tr('Number'),
                                    houseNumberController,
                                    Icons.home,
                                    isLight)),
                              ]),

                            // City and State
                            Row(
                              children: [
                                Expanded(
                                  child: _buildEditableBusinessField(
                                    AppLocalizations.of(context)?.city ?? AppLocalizations.of(context)!.tr('City'),
                                    cityController,
                                    Icons.location_city,
                                    isLight)),
                                SizedBox(width: 12),
                                Expanded(
                                  child: _buildEditableBusinessField(
                                    AppLocalizations.of(context)?.state ?? AppLocalizations.of(context)!.tr('State'),
                                    stateController,
                                    Icons.map,
                                    isLight)),
                              ]),

                            // ZIP Code and Country
                            Row(
                              children: [
                                Expanded(
                                  child: _buildEditableBusinessField(
                                    AppLocalizations.of(context)?.zipCode ??
                                        AppLocalizations.of(context)?.zipCode ?? AppLocalizations.of(context)!.tr('ZIP Code'),
                                    zipCodeController,
                                    Icons.local_post_office,
                                    isLight)),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(bottom: 16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppLocalizations.of(
                                                context)?.country ?? AppLocalizations.of(context)!.tr('Country'),
                                          style: TextStyle(
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                            fontWeight: FontWeight.w600,
                                            color:
                                                (isLight
                                                        ? Colors.black
                                                        : Colors.white)
                                                    .withOpacity(0.8))),
                                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                        TradeRepublicTap(
                                          onTap: () {
                                            _showCountrySelection(
                                              setModalState,
                                              selectedCountry,
                                              isLight,
                                              (newCountry) {
                                                setModalState(() {
                                                  selectedCountry = newCountry;
                                                });
                                              });
                                          },
                                          child: TradeRepublicCard(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 16),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  CupertinoIcons.globe,
                                                  size: 20,
                                                  color:
                                                      (isLight
                                                              ? Colors.black
                                                              : Colors.white)
                                                          .withOpacity(0.6)),
                                                SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    selectedCountry,
                                                    style: TextStyle(
                                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isLight
                                                          ? Colors.black
                                                          : Colors.white))),
                                                Icon(
                                                  Icons
                                                      .arrow_forward_ios_rounded,
                                                  size: 16,
                                                  color:
                                                      (isLight
                                                              ? Colors.black
                                                              : Colors.white)
                                                          .withOpacity(0.3)),
                                              ]))),
                                      ]))),
                              ]),
                          ]),

                        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                        // Business Size Section
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)?.businessSize ?? AppLocalizations.of(context)!.tr('Business Size'),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w700,
                                color: isLight ? Colors.black : Colors.white)),
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                            TradeRepublicTap(
                              onTap: () {
                                _showBusinessSizeSelection(
                                  setModalState,
                                  selectedSize,
                                  isLight,
                                  (newSize) {
                                    setModalState(() {
                                      selectedSize = newSize;
                                    });
                                  });
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.person_2_fill,
                                    size: 20,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.8)),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      selectedSize,
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        fontWeight: FontWeight.w600,
                                        color: isLight
                                            ? Colors.black
                                            : Colors.white))),
                                  Icon(
                                    CupertinoIcons.forward,
                                    size: 16,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.3)),
                                ])),
                          ]),

                        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                        // Privacy & Visibility Settings Section - Header
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(
                                      context)?.privacyVisibility ?? AppLocalizations.of(context)!.tr('Privacy & Visibility'),
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w700,
                                  color: isLight ? Colors.black : Colors.white)),

                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                              Text(
                                AppLocalizations.of(
                                      context)?.controlVisibleInfo ?? AppLocalizations.of(context)!.tr('Control which business information is publicly visible'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5))),
                            ])),

                        SizedBox(height: 20),

                        RepaintBoundary(
                          child: _buildVisibilityToggle(
                            AppLocalizations.of(context)?.showBusinessPhone ?? AppLocalizations.of(context)!.tr('Show Business Phone'),
                            AppLocalizations.of(context)?.allowSeePhone ?? AppLocalizations.of(context)!.tr('Allow others to see your business phone number'),
                            showPhone,
                            CupertinoIcons.phone,
                            isLight,
                            (value) {
                              setModalState(() {
                                showPhone = value;
                              });
                            })),

                        RepaintBoundary(
                          child: _buildVisibilityToggle(
                            AppLocalizations.of(context)?.showBusinessEmail ?? AppLocalizations.of(context)!.tr('Show Business Email'),
                            AppLocalizations.of(context)?.allowSeeEmail ?? AppLocalizations.of(context)!.tr('Allow others to see your business email address'),
                            showBusinessEmail,
                            CupertinoIcons.mail,
                            isLight,
                            (value) {
                              setModalState(() {
                                showBusinessEmail = value;
                              });
                            })),

                        RepaintBoundary(
                          child: _buildVisibilityToggle(
                            AppLocalizations.of(
                                  context)?.showBusinessCompanyInfo ?? AppLocalizations.of(context)!.tr('Show Business Company Info'),
                            AppLocalizations.of(
                                  context)?.allowSeeCompanyDetails ?? AppLocalizations.of(context)!.tr('Allow others to see your company details'),
                            showBusinessCompany,
                            CupertinoIcons.building_2_fill,
                            isLight,
                            (value) {
                              setModalState(() {
                                showBusinessCompany = value;
                              });
                            })),

                        RepaintBoundary(
                          child: _buildVisibilityToggle(
                            AppLocalizations.of(context)?.showBusinessSize_ ?? AppLocalizations.of(context)!.tr('Show Business Size'),
                            AppLocalizations.of(
                                  context)?.allowSeeBusinessSize ?? AppLocalizations.of(context)!.tr('Allow others to see your business size'),
                            showBusinessSize,
                            CupertinoIcons.person_2_fill,
                            isLight,
                            (value) {
                              setModalState(() {
                                showBusinessSize = value;
                              });
                            })),

                        RepaintBoundary(
                          child: _buildVisibilityToggle(
                            AppLocalizations.of(context)?.showBusinessCountry ?? AppLocalizations.of(context)!.tr('Show Business Country'),
                            AppLocalizations.of(
                                  context)?.allowSeeBusinessCountry ?? AppLocalizations.of(context)!.tr('Allow others to see your business country'),
                            showBusinessCountry,
                            CupertinoIcons.globe,
                            isLight,
                            (value) {
                              setModalState(() {
                                showBusinessCountry = value;
                              });
                            })),

                        SizedBox(height: 32),

                        // Action Buttons - NOW INSIDE ScrollView
                        Row(
                          children: [
                            Expanded(
                              child: TradeRepublicButton(
                                label:
                                    AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                                isSecondary: true,
                                height: 50,
                                onPressed: () => Navigator.pop(context))),

                            SizedBox(width: 16),

                            Expanded(
                              flex: 2,
                              child: TradeRepublicButton(
                                label:
                                    AppLocalizations.of(context)?.saveChanges ?? AppLocalizations.of(context)!.tr('Save Changes'),
                                height: 50,
                                onPressed: () => _saveBusinessData(
                                  context,
                                  businessNameController,
                                  businessDescriptionController,
                                  businessWebsiteController,
                                  streetController,
                                  houseNumberController,
                                  cityController,
                                  stateController,
                                  zipCodeController,
                                  selectedCountry,
                                  selectedSize,
                                  showPhone,
                                  showBusinessEmail,
                                  showBusinessCompany,
                                  showBusinessSize,
                                  showBusinessCountry))),
                          ]),
                      ]))),
              ]))))).whenComplete(() {
      NavigationVisibility.show();
      if (mounted) setState(() => _isBusinessEditOpen = false);
    });
  }

  Widget _buildEditableInfoRow(
    String label,
    String value,
    IconData icon,
    bool isLight) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isLight ? Colors.black : Colors.white),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isLight ? Colors.black : Colors.white)),
                SizedBox(height: 4),
                TradeRepublicTextField(
                  useFormField: true,
                  initialValue: value,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white)),
              ])),
        ]));
  }

  void _showPersonalEditModal(BuildContext context, bool isLight) {
    // Create controllers with current values
    final firstNameController = TextEditingController(
      text: userData?['firstname'] ?? AppLocalizations.of(context)!.tr(''));
    final lastNameController = TextEditingController(
      text: userData?['lastname'] ?? AppLocalizations.of(context)!.tr(''));
    final emailController = TextEditingController(
      text: userData?['email'] ?? AppLocalizations.of(context)!.tr(''));
    final birthdateController = TextEditingController(
      text: userData?['birthdate']?.toString().split('T').first ?? AppLocalizations.of(context)!.tr(''));
    final businessNameController = TextEditingController(
      text: userData?['businessName'] ?? userData?['business_company'] ?? AppLocalizations.of(context)!.tr(''));
    final businessDescriptionController = TextEditingController(
      text: userData?['businessDescription'] ?? AppLocalizations.of(context)!.tr(''));
    final businessWebsiteController = TextEditingController(
      text: userData?['businessWebsite'] ?? AppLocalizations.of(context)!.tr(''));

    String existingAddress = userData?['businessAddress'] ?? AppLocalizations.of(context)!.tr('');
    String street = '';
    String houseNumber = '';
    String zipCode = '';
    String city = '';
    String state = '';
    String parsedCountry = '';

    if (existingAddress.isNotEmpty) {
      try {
        final parts = existingAddress
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        if (parts.isNotEmpty) {
          final streetPart = parts[0];
          final streetTokens = streetPart
              .split(RegExp(r'\s+'))
              .where((t) => t.isNotEmpty)
              .toList();

          String? foundNumber;
          bool containsDigit(String s) => RegExp(r'\d').hasMatch(s);

          if (streetTokens.isNotEmpty && containsDigit(streetTokens.last)) {
            foundNumber = streetTokens.last;
            street = streetTokens.sublist(0, streetTokens.length - 1).join(' ');
          } else if (streetTokens.isNotEmpty &&
              containsDigit(streetTokens.first)) {
            foundNumber = streetTokens.first;
            street = streetTokens.sublist(1).join(' ');
          } else {
            final anyWithDigit = streetTokens.firstWhere(
              (t) => containsDigit(t),
              orElse: () => '');
            if (anyWithDigit.isNotEmpty) {
              foundNumber = anyWithDigit;
              final idx = streetTokens.indexOf(anyWithDigit);
              final left = streetTokens.sublist(0, idx);
              final right = streetTokens.sublist(idx + 1);
              street = [...left, ...right].join(' ');
            } else {
              street = streetPart;
            }
          }

          if (foundNumber != null && foundNumber.isNotEmpty) {
            houseNumber = foundNumber;
          }
        }

        if (parts.length >= 2) {
          final remainingParts = parts
              .sublist(1)
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          final remaining = remainingParts.join(', ');

          final knownCountries = [
            'germany',
            'deutschland',
            'united states',
            'usa',
            'canada',
            'mexico',
            'austria',
            'switzerland',
            'france',
            'italy',
            'spain',
            'netherlands',
            'belgium',
            'poland',
            'portugal',
            'greece',
            'ireland',
            'sweden',
            'denmark',
            'finland',
            'czech republic',
            'hungary',
            'romania',
            'bulgaria',
            'croatia',
            'slovakia',
            'slovenia',
            'estonia',
            'latvia',
            'lithuania',
            'malta',
            'cyprus',
            'luxembourg',
            'russia',
            'uk',
            'united kingdom',
          ];

          final zipMatch = RegExp(r'\b\d{3,6}\b').firstMatch(remaining);
          String working = remaining;
          if (zipMatch != null) {
            zipCode = zipMatch.group(0) ?? AppLocalizations.of(context)!.tr('');
            working = working
                .replaceFirst(zipMatch.group(0)!, '')
                .replaceAll(',', ' ')
                .trim();
          }

          final tokens = working
              .split(RegExp(r'[\s,]+'))
              .where((t) => t.isNotEmpty)
              .toList();

          if (tokens.isNotEmpty &&
              knownCountries.contains(tokens.last.toLowerCase())) {
            parsedCountry = tokens.removeLast();
          }

          if (tokens.isEmpty) {
            city = '';
            state = '';
          } else if (tokens.length == 1) {
            city = tokens[0];
            state = '';
          } else {
            state = tokens.last;
            city = tokens.sublist(0, tokens.length - 1).join(' ');
          }

          if (parsedCountry.isNotEmpty &&
              state.toLowerCase() == parsedCountry.toLowerCase()) {
            state = '';
          }
        }
      } catch (e) {
        debugPrint('⚠️ Could not parse personal edit address: $e');
      }
    }

    final streetController = TextEditingController(text: street);
    final houseNumberController = TextEditingController(text: houseNumber);
    final zipCodeController = TextEditingController(text: zipCode);
    final cityController = TextEditingController(text: city);
    final stateController = TextEditingController(text: state);

    String selectedCountry =
        userData?['business_country'] ??
        userData?['country'] ??
        (parsedCountry.isNotEmpty ? parsedCountry : 'United States');
    String selectedSize =
        userData?['business_size'] ??
        userData?['businessSize'] ?? AppLocalizations.of(context)!.tr('1-10 employees');
    bool showPhone = userData?['showPhone'] == 1;
    bool showBusinessSize = userData?['showBusinessSize'] == 1;
    bool showBusinessCompany = userData?['showBusinessCompany'] == 1;
    bool showBusinessEmail = userData?['showBusinessEmail'] == 1;
    bool showBusinessCountry = userData?['showBusinessCountry'] == 1;
    final bool canEditVisibilityPrefs =
        userData?['supportsVisibilityPrefs'] == true;

    // Parse phone number into country code and number
    String currentPhone = userData?['phone'] ?? AppLocalizations.of(context)!.tr('');
    String selectedCountryCode = '+49'; // Default Germany
    String phoneNumber = '';

    // Country codes: USA, Canada, Mexico, EU and Russia
    final countryCodes = [
      // North America
      {'code': '+1', 'country': 'US', 'flag': '🇺🇸'},
      {'code': '+1', 'country': 'CA', 'flag': '🇨🇦'},
      {'code': '+52', 'country': 'MX', 'flag': '🇲🇽'},
      // EU Countries
      {'code': '+49', 'country': 'DE', 'flag': '🇩🇪'},
      {'code': '+43', 'country': 'AT', 'flag': '🇦🇹'},
      {'code': '+33', 'country': 'FR', 'flag': '🇫🇷'},
      {'code': '+39', 'country': 'IT', 'flag': '🇮🇹'},
      {'code': '+34', 'country': 'ES', 'flag': '🇪🇸'},
      {'code': '+31', 'country': 'NL', 'flag': '🇳🇱'},
      {'code': '+32', 'country': 'BE', 'flag': '🇧🇪'},
      {'code': '+48', 'country': 'PL', 'flag': '🇵🇱'},
      {'code': '+351', 'country': 'PT', 'flag': '🇵🇹'},
      {'code': '+30', 'country': 'GR', 'flag': '🇬🇷'},
      {'code': '+353', 'country': 'IE', 'flag': '🇮🇪'},
      {'code': '+46', 'country': 'SE', 'flag': '🇸🇪'},
      {'code': '+45', 'country': 'DK', 'flag': '🇩🇰'},
      {'code': '+358', 'country': 'FI', 'flag': '🇫🇮'},
      {'code': '+420', 'country': 'CZ', 'flag': '🇨🇿'},
      {'code': '+36', 'country': 'HU', 'flag': '🇭🇺'},
      {'code': '+40', 'country': 'RO', 'flag': '🇷🇴'},
      {'code': '+359', 'country': 'BG', 'flag': '🇧🇬'},
      {'code': '+385', 'country': 'HR', 'flag': '🇭🇷'},
      {'code': '+421', 'country': 'SK', 'flag': '🇸🇰'},
      {'code': '+386', 'country': 'SI', 'flag': '🇸🇮'},
      {'code': '+372', 'country': 'EE', 'flag': '🇪🇪'},
      {'code': '+371', 'country': 'LV', 'flag': '🇱🇻'},
      {'code': '+370', 'country': 'LT', 'flag': '🇱🇹'},
      {'code': '+356', 'country': 'MT', 'flag': '🇲🇹'},
      {'code': '+357', 'country': 'CY', 'flag': '🇨🇾'},
      {'code': '+352', 'country': 'LU', 'flag': '🇱🇺'},
      // Russia
      {'code': '+7', 'country': 'RU', 'flag': '🇷🇺'},
    ];

    // Try to parse existing phone number
    if (currentPhone.isNotEmpty) {
      final normalizedPhone = currentPhone
          .replaceAll(RegExp(r'[()]'), '')
          .trim();
      // Sort by code length (longest first) to match +380 before +38
      final sortedCodes = List<Map<String, String>>.from(countryCodes)
        ..sort((a, b) => b['code']!.length.compareTo(a['code']!.length));

      for (var countryData in sortedCodes) {
        if (normalizedPhone.startsWith(countryData['code']!)) {
          selectedCountryCode = countryData['code']!;
          phoneNumber = normalizedPhone
              .substring(countryData['code']!.length)
              .trim();
          break;
        }
      }
      // If no country code matched, use the whole number
      if (phoneNumber.isEmpty && currentPhone.isNotEmpty) {
        phoneNumber = normalizedPhone.replaceAll(RegExp(r'^\+\d+'), '').trim();
        if (phoneNumber.isEmpty) phoneNumber = currentPhone;
      }
    }

    final phoneController = TextEditingController(text: phoneNumber);
    final editPageController = PageController();
    int currentEditPage = 0;

    setState(() => _isPersonalEditOpen = true);
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.92,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> openBirthdatePicker() async {
            DateTime selectedDate;
            try {
              selectedDate = birthdateController.text.trim().isNotEmpty
                  ? DateTime.parse(birthdateController.text.trim())
                  : DateTime(DateTime.now().year - 25, 1, 1);
            } catch (_) {
              selectedDate = DateTime(DateTime.now().year - 25, 1, 1);
            }

            await TradeRepublicBottomSheet.show(
              context: context,
              maxHeight: 360,
              showDragHandle: true,
              child: StatefulBuilder(
                builder: (context, setDateState) => SizedBox(
                  height: 300,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TradeRepublicButton(
                            label:
                                AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                            isSecondary: true,
                            onPressed: () => Navigator.pop(context)),
                          Text(
                            AppLocalizations.of(context)?.birthdate ?? AppLocalizations.of(context)!.tr('Birthdate'),
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white)),
                          TradeRepublicButton(
                            label: AppLocalizations.of(context)!.tr('Done') ?? AppLocalizations.of(context)!.tr('Done'),
                            onPressed: () {
                              setModalState(() {
                                birthdateController.text =
                                    '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                              });
                              Navigator.pop(context);
                            }),
                        ]),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                      Expanded(
                        child: CupertinoTheme(
                          data: CupertinoThemeData(
                            brightness: isLight
                                ? Brightness.light
                                : Brightness.dark),
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.date,
                            initialDateTime: selectedDate,
                            minimumDate: DateTime(1900, 1, 1),
                            maximumDate: DateTime.now(),
                            onDateTimeChanged: (date) {
                              setDateState(() {
                                selectedDate = date;
                              });
                            }))),
                    ]))));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DragHandle(),
              Row(
                children: [
                  Icon(
                    CupertinoIcons.person_fill,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.editPersonalInfo ?? AppLocalizations.of(context)!.tr('Edit Personal Information'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4))),
                ]),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              Text(
                currentEditPage == 0
                    ? 'Personal details'
                    : currentEditPage == 1
                    ? 'Business details'
                    : 'Privacy & visibility',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.5))),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  final isActive = currentEditPage == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: isActive ? 22 : 8,
                    height: 8,
                    margin: EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? (isLight ? Colors.black : Colors.white)
                          : (isLight ? Colors.black : Colors.white).withOpacity(
                              0.15),
                      borderRadius: BorderRadius.circular(10)));
                })),
              SizedBox(height: 20),
              Expanded(
                child: PageView(
                  controller: editPageController,
                  onPageChanged: (page) {
                    setModalState(() {
                      currentEditPage = page;
                    });
                  },
                  children: [
                    SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        children: [
                          _buildEditableTextField(
                            AppLocalizations.of(context)?.firstName ?? AppLocalizations.of(context)!.tr('First Name'),
                            firstNameController,
                            CupertinoIcons.person_fill,
                            isLight),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          _buildEditableTextField(
                            AppLocalizations.of(context)?.lastName ?? AppLocalizations.of(context)!.tr('Last Name'),
                            lastNameController,
                            CupertinoIcons.person,
                            isLight),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          _buildEditableTextField(
                            AppLocalizations.of(context)?.email ?? AppLocalizations.of(context)!.tr('Email'),
                            emailController,
                            CupertinoIcons.mail,
                            isLight,
                            keyboardType: TextInputType.emailAddress),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          TradeRepublicTap(
                            onTap: openBirthdatePicker,
                            child: AbsorbPointer(
                              child: _buildEditableTextField(
                                AppLocalizations.of(context)?.birthdate ?? AppLocalizations.of(context)!.tr('Birthdate'),
                                birthdateController,
                                CupertinoIcons.calendar,
                                isLight))),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          Container(
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: isLight ? Colors.white : Colors.black,
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(context)?.phone ?? AppLocalizations.of(context)!.tr('Phone'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.5))),
                                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                Row(
                                  children: [
                                    Flexible(
                                      flex: 4,
                                      child: TradeRepublicTap(
                                        onTap: () {
                                          _showCountryCodePicker(
                                            context,
                                            isLight,
                                            countryCodes,
                                            selectedCountryCode,
                                            (newCode) {
                                              setModalState(() {
                                                selectedCountryCode = newCode;
                                              });
                                            });
                                        },
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 14),
                                          decoration: BoxDecoration(
                                            color: isLight
                                                ? Colors.white
                                                : Colors.black,
                                            borderRadius: BorderRadius.circular(
                                              20)),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                countryCodes.firstWhere(
                                                  (c) =>
                                                      c['code'] ==
                                                      selectedCountryCode,
                                                  orElse: () =>
                                                      countryCodes.first)['flag']!,
                                                style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 6)),
                                              SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  selectedCountryCode,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                                    fontWeight: FontWeight.w600,
                                                    color: isLight
                                                        ? Colors.black
                                                        : Colors.white))),
                                              SizedBox(width: 4),
                                              Icon(
                                                CupertinoIcons.chevron_down,
                                                size: 18,
                                                color:
                                                    (isLight
                                                            ? Colors.black
                                                            : Colors.white)
                                                        .withOpacity(0.5)),
                                            ])))),
                                    SizedBox(width: 12),
                                    Expanded(
                                      flex: 6,
                                      child: TradeRepublicTextField(
                                        controller: phoneController,
                                        keyboardType: TextInputType.phone,
                                        hintText: AppLocalizations.of(context)!.tr('123 456 7890') ?? AppLocalizations.of(context)!.tr('123 456 7890'),
                                        filled: true,
                                        fillColor: isLight
                                            ? Colors.white
                                            : Colors.black)),
                                  ]),
                              ])),
                        ])),
                    SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        children: [
                          _buildEditableTextField(
                            AppLocalizations.of(context)?.businessName ?? AppLocalizations.of(context)!.tr('Business Name'),
                            businessNameController,
                            CupertinoIcons.building_2_fill,
                            isLight),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          _buildEditableTextField(
                            AppLocalizations.of(context)?.businessDescription ?? AppLocalizations.of(context)!.tr('Business Description'),
                            businessDescriptionController,
                            Icons.description,
                            isLight),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          _buildEditableTextField(
                            AppLocalizations.of(context)?.businessWebsite ?? AppLocalizations.of(context)!.tr('Business Website'),
                            businessWebsiteController,
                            Icons.language,
                            isLight,
                            keyboardType: TextInputType.url),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildEditableTextField(
                                  AppLocalizations.of(context)?.street ?? AppLocalizations.of(context)!.tr('Street'),
                                  streetController,
                                  CupertinoIcons.location_solid,
                                  isLight)),
                              SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: _buildEditableTextField(
                                  AppLocalizations.of(context)?.numberLabel ?? AppLocalizations.of(context)!.tr('Number'),
                                  houseNumberController,
                                  Icons.home_outlined,
                                  isLight)),
                            ]),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          Row(
                            children: [
                              Expanded(
                                child: _buildEditableTextField(
                                  AppLocalizations.of(context)?.zipCode ?? AppLocalizations.of(context)!.tr('ZIP Code'),
                                  zipCodeController,
                                  Icons.local_post_office,
                                  isLight)),
                              SizedBox(width: 12),
                              Expanded(
                                child: _buildEditableTextField(
                                  AppLocalizations.of(context)?.city ?? AppLocalizations.of(context)!.tr('City'),
                                  cityController,
                                  Icons.location_city,
                                  isLight)),
                            ]),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          _buildEditableTextField(
                            AppLocalizations.of(context)?.state ?? AppLocalizations.of(context)!.tr('State / Region'),
                            stateController,
                            Icons.map_outlined,
                            isLight),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          TradeRepublicTap(
                            onTap: () {
                              _showCountrySelection(
                                setModalState,
                                selectedCountry,
                                isLight,
                                (newCountry) {
                                  setModalState(() {
                                    selectedCountry = newCountry;
                                  });
                                });
                            },
                            child: TradeRepublicCard(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.globe,
                                    size: 20,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.6)),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppLocalizations.of(
                                                context)?.country ?? AppLocalizations.of(context)!.tr('Country'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color:
                                                (isLight
                                                        ? Colors.black
                                                        : Colors.white)
                                                    .withOpacity(0.5))),
                                        SizedBox(height: 4),
                                        Text(
                                          selectedCountry,
                                          style: TextStyle(
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                            fontWeight: FontWeight.w600,
                                            color: isLight
                                                ? Colors.black
                                                : Colors.white)),
                                      ])),
                                  Icon(
                                    CupertinoIcons.forward,
                                    size: 16,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.3)),
                                ]))),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          TradeRepublicTap(
                            onTap: () {
                              _showBusinessSizeSelection(
                                setModalState,
                                selectedSize,
                                isLight,
                                (newSize) {
                                  setModalState(() {
                                    selectedSize = newSize;
                                  });
                                });
                            },
                            child: TradeRepublicCard(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.person_2_fill,
                                    size: 20,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.6)),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppLocalizations.of(
                                                context)?.businessSize ?? AppLocalizations.of(context)!.tr('Business Size'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color:
                                                (isLight
                                                        ? Colors.black
                                                        : Colors.white)
                                                    .withOpacity(0.5))),
                                        SizedBox(height: 4),
                                        Text(
                                          selectedSize,
                                          style: TextStyle(
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                            fontWeight: FontWeight.w600,
                                            color: isLight
                                                ? Colors.black
                                                : Colors.white)),
                                      ])),
                                  Icon(
                                    CupertinoIcons.forward,
                                    size: 16,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.3)),
                                ]))),
                        ])),
                    SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: canEditVisibilityPrefs
                          ? Column(
                              children: [
                                _buildVisibilityToggle(
                                  AppLocalizations.of(
                                        context)?.showBusinessPhone ?? AppLocalizations.of(context)!.tr('Show Business Phone'),
                                  AppLocalizations.of(context)?.allowSeePhone ?? AppLocalizations.of(context)!.tr('Allow others to see your business phone number'),
                                  showPhone,
                                  CupertinoIcons.phone,
                                  isLight,
                                  (value) {
                                    setModalState(() {
                                      showPhone = value;
                                    });
                                  }),
                                _buildVisibilityToggle(
                                  AppLocalizations.of(
                                        context)?.showBusinessEmail ?? AppLocalizations.of(context)!.tr('Show Business Email'),
                                  AppLocalizations.of(context)?.allowSeeEmail ?? AppLocalizations.of(context)!.tr('Allow others to see your business email address'),
                                  showBusinessEmail,
                                  CupertinoIcons.mail,
                                  isLight,
                                  (value) {
                                    setModalState(() {
                                      showBusinessEmail = value;
                                    });
                                  }),
                                _buildVisibilityToggle(
                                  AppLocalizations.of(
                                        context)?.showBusinessCompanyInfo ?? AppLocalizations.of(context)!.tr('Show Business Company Info'),
                                  AppLocalizations.of(
                                        context)?.allowSeeCompanyDetails ?? AppLocalizations.of(context)!.tr('Allow others to see your company details'),
                                  showBusinessCompany,
                                  CupertinoIcons.building_2_fill,
                                  isLight,
                                  (value) {
                                    setModalState(() {
                                      showBusinessCompany = value;
                                    });
                                  }),
                                _buildVisibilityToggle(
                                  AppLocalizations.of(
                                        context)?.showBusinessSize_ ?? AppLocalizations.of(context)!.tr('Show Business Size'),
                                  AppLocalizations.of(
                                        context)?.allowSeeBusinessSize ?? AppLocalizations.of(context)!.tr('Allow others to see your business size'),
                                  showBusinessSize,
                                  CupertinoIcons.person_2_fill,
                                  isLight,
                                  (value) {
                                    setModalState(() {
                                      showBusinessSize = value;
                                    });
                                  }),
                                _buildVisibilityToggle(
                                  AppLocalizations.of(
                                        context)?.showBusinessCountry ?? AppLocalizations.of(context)!.tr('Show Business Country'),
                                  AppLocalizations.of(
                                        context)?.allowSeeBusinessCountry ?? AppLocalizations.of(context)!.tr('Allow others to see your business country'),
                                  showBusinessCountry,
                                  CupertinoIcons.globe,
                                  isLight,
                                  (value) {
                                    setModalState(() {
                                      showBusinessCountry = value;
                                    });
                                  }),
                              ])
                          : const SizedBox.shrink()),
                  ])),
              SizedBox(height: 20),
              Row(
                children: [
                  if (currentEditPage > 0)
                    Expanded(
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)!.tr('Back') ?? AppLocalizations.of(context)!.tr('Back'),
                        isSecondary: true,
                        height: 50,
                        onPressed: () {
                          editPageController.previousPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut);
                        })),
                  if (currentEditPage > 0) SizedBox(width: 12),
                  Expanded(
                    flex: currentEditPage > 0 ? 2 : 1,
                    child: TradeRepublicButton(
                      label: currentEditPage == 2
                          ? (AppLocalizations.of(context)?.saveChanges ?? AppLocalizations.of(context)!.tr('Save Changes'))
                          : 'Next',
                      height: 50,
                      onPressed: () async {
                        if (currentEditPage < 2) {
                          editPageController.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut);
                          return;
                        }

                        final street = streetController.text.trim();
                        final houseNumber = houseNumberController.text.trim();
                        final city = cityController.text.trim();
                        final state = stateController.text.trim();
                        final zipCode = zipCodeController.text.trim();
                        final addressParts = <String>[];
                        if (street.isNotEmpty || houseNumber.isNotEmpty) {
                          addressParts.add(
                            [
                              street,
                              houseNumber,
                            ].where((part) => part.isNotEmpty).join(' '));
                        }
                        if (zipCode.isNotEmpty || city.isNotEmpty) {
                          addressParts.add(
                            [
                              zipCode,
                              city,
                            ].where((part) => part.isNotEmpty).join(' '));
                        }
                        if (state.isNotEmpty) addressParts.add(state);
                        if (selectedCountry.isNotEmpty) {
                          addressParts.add(selectedCountry);
                        }
                        final fullPhone =
                            '$selectedCountryCode${phoneController.text.replaceAll(' ', '')}';

                        final updatedData = <String, dynamic>{
                          'firstname': firstNameController.text.trim(),
                          'lastname': lastNameController.text.trim(),
                          'email': emailController.text.trim(),
                          'phone': fullPhone,
                          'birthdate': birthdateController.text.trim(),
                          'businessName': businessNameController.text.trim(),
                          'businessDescription': businessDescriptionController
                              .text
                              .trim(),
                          'businessWebsite': businessWebsiteController.text
                              .trim(),
                          'businessAddress': addressParts.join(', '),
                          'business_country': selectedCountry,
                          'business_size': selectedSize,
                        };

                        if (canEditVisibilityPrefs) {
                          updatedData.addAll({
                            'showPhone': showPhone ? 1 : 0,
                            'showBusinessEmail': showBusinessEmail ? 1 : 0,
                            'showBusinessCompany': showBusinessCompany ? 1 : 0,
                            'showBusinessSize': showBusinessSize ? 1 : 0,
                            'showBusinessCountry': showBusinessCountry ? 1 : 0,
                          });
                        }

                        await _updateUserData(updatedData);

                        await _loadUserData();
                        if (!mounted) return;
                        Navigator.pop(context);
                        TopNotification.success(
                          context,
                          AppLocalizations.of(context)?.personalInfoUpdated ?? AppLocalizations.of(context)!.tr('Personal information updated!'));
                      })),
                ]),
            ]);
        })).whenComplete(() {
      editPageController.dispose();
      firstNameController.dispose();
      lastNameController.dispose();
      emailController.dispose();
      birthdateController.dispose();
      businessNameController.dispose();
      businessDescriptionController.dispose();
      businessWebsiteController.dispose();
      streetController.dispose();
      houseNumberController.dispose();
      zipCodeController.dispose();
      cityController.dispose();
      stateController.dispose();
      phoneController.dispose();
      NavigationVisibility.show();
      if (mounted) setState(() => _isPersonalEditOpen = false);
    });
  }

  // Helper widget for editable text fields
  Widget _buildEditableTextField(
    String label,
    TextEditingController controller,
    IconData icon,
    bool isLight, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          TradeRepublicTextField(
            controller: controller,
            keyboardType: keyboardType,
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: isLight ? Colors.white : Colors.black,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w500,
              color: isLight ? Colors.black : Colors.white),
            hintText: '${AppLocalizations.of(context)!.tr('Enter')} $label'),
        ]));
  }

  // Country code picker modal
  void _showCountryCodePicker(
    BuildContext context,
    bool isLight,
    List<Map<String, String>> countryCodes,
    String currentCode,
    Function(String) onSelect) {
    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.phone_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.selectCountryCode ?? AppLocalizations.of(context)!.tr('Select Country Code'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 20),

          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: countryCodes.length,
              itemBuilder: (context, index) {
                final country = countryCodes[index];
                final isSelected = country['code'] == currentCode;

                return TradeRepublicTap(
                  onTap: () {
                    onSelect(country['code']!);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14),
                    margin: EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isLight ? Colors.black : Colors.white).withOpacity(
                              0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Row(
                      children: [
                        Text(
                          country['flag']!,
                          style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 10),
                        SizedBox(width: 16),
                        Text(
                          country['country']!,
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white)),
                        const Spacer(),
                        Text(
                          country['code']!,
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w500,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.6))),
                        if (isSelected) ...[
                          SizedBox(width: 12),
                          Icon(
                            CupertinoIcons.check_mark_circled_solid,
                            color: isLight ? Colors.black : Colors.white,
                            size: 20),
                        ],
                      ])));
              })),
        ]));
  }

  void _showSecuritySettingsModal(BuildContext context, bool isLight) {
    // Close any open bottom sheet before opening security settings
    if (_isPaymentSettingsOpen) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (mounted) setState(() => _isPaymentSettingsOpen = false);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    setState(() => _isSecuritySettingsOpen = true);
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 1,
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Sheet header: Icon left + Title ──
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.shield_fill,
                          size: 22,
                          color: isLight ? Colors.black : Colors.white),
                        SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)?.security ?? AppLocalizations.of(context)!.tr('Security'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.4)),
                      ]),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    SizedBox(height: 20),

                    // Authentication Section
                    Text(
                      AppLocalizations.of(context)?.authentication ?? AppLocalizations.of(context)!.tr('Authentication'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    _buildSecurityToggle(
                      AppLocalizations.of(context)?.twoFactorAuthentication ??
                          AppLocalizations.of(
                            context)?.twoFactorAuthentication ?? AppLocalizations.of(context)!.tr('Two-Factor Authentication'),
                      AppLocalizations.of(context)?.extraLayerSecurity ?? AppLocalizations.of(context)!.tr('Extra layer of security'),
                      userData?['has_2fa_enabled'] == 1,
                      CupertinoIcons.lock_shield,
                      isLight,
                      (value) => _toggle2FA(value, setModalState)),

                    _buildSecurityToggle(
                      AppLocalizations.of(context)?.biometricAuthentication ??
                          AppLocalizations.of(
                            context)?.biometricAuthentication ?? AppLocalizations.of(context)!.tr('Biometric Authentication'),
                      AppLocalizations.of(context)?.fingerprintOrFace ?? AppLocalizations.of(context)!.tr('Fingerprint or face recognition'),
                      userData?['biometric_enabled'] == 1,
                      CupertinoIcons.hand_thumbsup,
                      isLight,
                      (value) => _toggleBiometric(value, setModalState)),

                    _buildSecurityToggle(
                      AppLocalizations.of(context)?.loginNotifications ?? AppLocalizations.of(context)!.tr('Login Notifications'),
                      AppLocalizations.of(context)?.getNotifiedNewSignIns ?? AppLocalizations.of(context)!.tr('Get notified on new sign-ins'),
                      userData?['notifications_login'] == 1,
                      CupertinoIcons.bell_solid,
                      isLight,
                      (value) =>
                          _toggleLoginNotifications(value, setModalState)),

                    SizedBox(height: 32),

                    // Account Security Section
                    Text(
                      AppLocalizations.of(context)?.accountSection ??
                          AppLocalizations.of(context)?.account ?? AppLocalizations.of(context)!.tr('Account'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    _buildSecurityActionItem(
                      AppLocalizations.of(context)?.activeSessions ?? AppLocalizations.of(context)!.tr('Active Sessions'),
                      AppLocalizations.of(context)?.manageSignedIn ?? AppLocalizations.of(context)!.tr('Manage logged in devices'),
                      CupertinoIcons.device_laptop,
                      isLight,
                      () => _showActiveSessionsModal(context, isLight)),

                    _buildSecurityActionItem(
                      AppLocalizations.of(context)?.loginHistory ?? AppLocalizations.of(context)!.tr('Login History'),
                      AppLocalizations.of(context)?.viewRecentActivity ?? AppLocalizations.of(context)!.tr('View recent activity'),
                      CupertinoIcons.clock,
                      isLight,
                      () => _showLoginHistoryModal(context, isLight)),

                    SizedBox(height: 32),

                    // Danger Zone
                    Text(
                      AppLocalizations.of(context)?.dangerZone ?? AppLocalizations.of(context)!.tr('Danger Zone'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: Colors.red.withOpacity(0.8))),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    _buildSecurityActionItem(
                      AppLocalizations.of(context)?.deleteAccount ?? AppLocalizations.of(context)!.tr('Delete Account'),
                      AppLocalizations.of(context)?.deleteAccount ?? AppLocalizations.of(context)!.tr('Delete Account'),
                      CupertinoIcons.delete_solid,
                      isLight,
                      () => _showDeleteAccountModal(context, isLight),
                      isDestructive: true),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                  ]))),
          ]))).whenComplete(() {
      if (mounted) setState(() => _isSecuritySettingsOpen = false);
      NavigationVisibility.show();
    });
  }

  void _showPaymentSettingsModal(BuildContext context, bool isLight) async {
    setState(() => _isPaymentSettingsOpen = true);
    // Load current payout schedule from userData, default to 'none' if not set
    String selectedPayoutSchedule =
        userData?['payout_schedule']?.toString() ?? AppLocalizations.of(context)!.tr('none');

    // Tab index for Earnings/Payout History
    int selectedTabIndex = 0;

    // Reload earnings data when opening modal
    NavigationVisibility.hide();

    // Show Loading Bottom Sheet while data is being loaded
    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      enableDrag: false,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          SizedBox(
            width: 24,
            height: 24,
            child: CultiooLoadingIndicator(size: 20)),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Text(
            AppLocalizations.of(context)?.loading ?? AppLocalizations.of(context)!.tr('Loading...'),
            style: TextStyle(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
              fontSize: 15,
              fontWeight: FontWeight.w500)),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        ]));

    // Earnings-Daten laden und warten
    await _loadEarningsData();
    await _loadEarningsHistory();
    // Load wallet data, pending shipping, and payment defaults in parallel
    await Future.wait([
      _loadWalletData(),
      _loadPendingShippingPayments(),
      _loadPaymentDefaults(),
    ]);

    // Close Loading Bottom Sheet
    if (context.mounted) _safePopIfPossible(context);

    if (!context.mounted) return;

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 1,
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ═══════════════════════════════════════════
                    // BALANCE SECTION - Hero Element
                    // ═══════════════════════════════════════════
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.chart_bar_alt_fill,
                          size: 22,
                          color: isLight ? Colors.black : Colors.white),
                        SizedBox(width: 10),
                        Text(
                          AppLocalizations.of(context)?.paymentSettings ?? AppLocalizations.of(context)!.tr('Payment Settings'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.6)),
                      ]),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.06),
                        borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.arrow_clockwise_circle_fill,
                            size: 14,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.75)),
                          SizedBox(width: 8),
                          Text(
                            'Live sync from backend',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.78))),
                        ])),
                    SizedBox(height: 18),

                    Text(
                      AppLocalizations.of(context)?.available ?? AppLocalizations.of(context)!.tr('Available'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w500,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        letterSpacing: -0.3)),
                    SizedBox(height: 4),

                    // Big Balance Number
                    Text(
                      _formatCurrency(
                        _getDisplayableBalance(
                              earningsData['availableBalance']) +
                            (groupEarningsData?['totalEarnings'] ?? 0.0)),
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -2,
                        height: 1.1)),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    // Stats Row - minimalist
                    Row(
                      children: [
                        _buildMinimalStat(
                          AppLocalizations.of(context)?.totalEarningsLabel ?? AppLocalizations.of(context)!.tr('Total Earnings'),
                          _formatCurrency(
                            (earningsData['totalEarnings'] ?? 0.0).toDouble()),
                          isLight),
                        SizedBox(width: 32),
                        _buildMinimalStat(
                          AppLocalizations.of(context)?.paidOut ?? AppLocalizations.of(context)!.tr('Paid Out'),
                          _formatCurrency(
                            earningsData['totalPayouts'] is String
                                ? double.tryParse(
                                        earningsData['totalPayouts']) ??
                                      0.0
                                : earningsData['totalPayouts']?.toDouble() ??
                                      0.0),
                          isLight),
                      ]),

                    // ═══════════════════════════════════════════
                    // WAITING CHARGE DEDUCTIONS
                    // ═══════════════════════════════════════════
                    if ((earningsData['totalWaitingCharges'] ?? 0.0) > 0 ||
                        waitingChargeDeductions.isNotEmpty) ...[
                      SizedBox(height: 40),
                      Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 22,
                            color: Colors.red.shade400),
                          SizedBox(width: 8),
                          Text(
                            'Waiting Costs',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                              letterSpacing: -0.5)),
                        ]),
                      SizedBox(height: 6),
                      Text(
                        'Deductions for waiting time at pickup',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          letterSpacing: -0.2)),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      // Total deductions summary
                      Container(
                        padding: DesktopAppWrapper.getPagePadding(),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50.withOpacity(
                            isLight ? 1.0 : 0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppLocalizations.of(context)?.totalDeducted ?? AppLocalizations.of(context)!.tr('Total deducted'),
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w500,
                                color: isLight
                                    ? Colors.black87
                                    : Colors.white70)),
                            Text(
                              '-${_formatCurrency((earningsData['totalWaitingCharges'] ?? 0.0).toDouble())}',
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                                fontWeight: FontWeight.w700,
                                color: Colors.red.shade400,
                                letterSpacing: -0.5)),
                          ])),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      // Individual deduction entries
                      ...waitingChargeDeductions.map((charge) {
                        final orderId = charge['order_id'] ?? AppLocalizations.of(context)!.tr('');
                        final driverName =
                            charge['driver_name'] ??
                            charge['driver_username'] ??
                            (AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown'));
                        final amount = (charge['amount'] ?? 0.0).toDouble();
                        final waitingSec = (charge['waiting_seconds'] ?? 0);
                        final waitingMin = waitingSec is int
                            ? (waitingSec / 60).ceil()
                            : ((waitingSec as num).toInt() / 60).ceil();
                        final freeMin = charge['free_minutes'] ?? 15;
                        final orderDate = charge['order_date'] != null
                            ? DateTime.tryParse(charge['order_date'].toString())
                            : null;
                        final dateStr = orderDate != null
                            ? '${orderDate.day.toString().padLeft(2, '0')}.${orderDate.month.toString().padLeft(2, '0')}.${orderDate.year}'
                            : '';

                        return TradeRepublicTap(
                          onTap: () => _showWaitingChargeInvoice(
                            context,
                            isLight,
                            charge),
                          child: Container(
                            margin: EdgeInsets.only(bottom: 10),
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: isLight ? Colors.white : Colors.black,
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                            child: Row(
                              children: [
                                // Timer icon
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50.withOpacity(
                                      isLight ? 1.0 : 0.15),
                                    borderRadius: BorderRadius.circular(22)),
                                  child: Center(
                                    child: Icon(
                                      Icons.timer,
                                      size: 22,
                                      color: Colors.red.shade400))),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}$orderId',
                                        style: TextStyle(
                                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                                          fontWeight: FontWeight.w600,
                                          color: isLight
                                              ? Colors.black
                                              : Colors.white,
                                          letterSpacing: -0.3)),
                                      SizedBox(height: 2),
                                      Text(
                                        '${AppLocalizations.of(context)?.driverLabel ?? AppLocalizations.of(context)!.tr('Driver')}: $driverName • $waitingMin Min ($freeMin Min)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                          color:
                                              (isLight
                                                      ? Colors.black
                                                      : Colors.white)
                                                  .withOpacity(0.5))),
                                      if (dateStr.isNotEmpty) ...[
                                        SizedBox(height: 1),
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color:
                                                (isLight
                                                        ? Colors.black
                                                        : Colors.white)
                                                    .withOpacity(0.35))),
                                      ],
                                    ])),
                                // Amount + chevron
                                Text(
                                  '-${_formatCurrency(amount)}',
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade400,
                                    letterSpacing: -0.3)),
                                SizedBox(width: 6),
                                Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.3)),
                              ])));
                      }),
                    ],

                    // ═══════════════════════════════════════════
                    // GROUP MEMBER EARNINGS (for group owners)
                    // ═══════════════════════════════════════════
                    if (currentGroup != null && _isCurrentGroupAdmin) ...[
                      SizedBox(height: 40),
                      Text(
                        AppLocalizations.of(context)?.groupMemberEarnings ?? AppLocalizations.of(context)!.tr('Group Member Earnings'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.5)),
                      SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(
                              context)?.seeHowMuchEachMemberEarned ?? AppLocalizations.of(context)!.tr('See how much each member earned'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          letterSpacing: -0.2)),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _loadGroupMemberEarnings(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Container(
                              padding: DesktopAppWrapper.getPagePadding(),
                              decoration: BoxDecoration(
                                color: isLight ? Colors.white : Colors.black,
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CultiooLoadingIndicator(size: 20))));
                          }

                          final members = snapshot.data ?? [];
                          if (members.isEmpty) {
                            return Container(
                              padding: DesktopAppWrapper.getPagePadding(),
                              decoration: BoxDecoration(
                                color: isLight ? Colors.white : Colors.black,
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                              child: Center(
                                child: Text(
                                  AppLocalizations.of(
                                        context)?.noMemberEarningsYet ?? AppLocalizations.of(context)!.tr('No member earnings yet'),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.5)))));
                          }

                          return Column(
                            children: members.map((member) {
                              final memberName =
                                  member['name'] ??
                                  member['username'] ??
                                  (AppLocalizations.of(context)?.unknown ??
                                      AppLocalizations.of(
                                        context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown'));
                              final memberEarnings =
                                  (member['totalEarnings'] ?? 0.0).toDouble();
                              final deliveries = member['deliveries'] ?? 0;

                              return Container(
                                margin: EdgeInsets.only(bottom: 12),
                                padding: DesktopAppWrapper.getPagePadding(),
                                decoration: BoxDecoration(
                                  color: isLight ? Colors.white : Colors.black,
                                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                child: Row(
                                  children: [
                                    // Avatar
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color:
                                            (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(25)),
                                      child: Center(
                                        child: Text(
                                          memberName.isNotEmpty
                                              ? memberName[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                            fontWeight: FontWeight.w700,
                                            color: isLight
                                                ? Colors.black
                                                : Colors.white)))),
                                    SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            memberName,
                                            style: TextStyle(
                                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                                              fontWeight: FontWeight.w600,
                                              color: isLight
                                                  ? Colors.black
                                                  : Colors.white,
                                              letterSpacing: -0.3)),
                                          SizedBox(height: 2),
                                          Text(
                                            '$deliveries ${AppLocalizations.of(context)?.deliveriesWord ?? AppLocalizations.of(context)!.tr('deliveries')}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              color:
                                                  (isLight
                                                          ? Colors.black
                                                          : Colors.white)
                                                      .withOpacity(0.5))),
                                        ])),
                                    Text(
                                      _formatCurrency(memberEarnings),
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.green,
                                        letterSpacing: -0.3)),
                                  ]));
                            }).toList());
                        }),
                    ],

                    SizedBox(height: 40),

                    // ═══════════════════════════════════════════
                    // MONIOO WALLET SECTION
                    // ═══════════════════════════════════════════
                    _buildMoniooWalletCard(isLight, setModalState),

                    // ═══════════════════════════════════════════
                    // PENDING SHIPPING PAYMENTS (Incoterms-based)
                    // ═══════════════════════════════════════════
                    if (_pendingShippingPayments.isNotEmpty) ...[
                      SizedBox(height: 40),
                      _buildPendingShippingSection(isLight, setModalState),
                    ],

                    SizedBox(height: 40),

                    // ═══════════════════════════════════════════
                    // DRIVER PAYMENT METHOD SECTION
                    // ═══════════════════════════════════════════
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.car_fill,
                          size: 20,
                          color: isLight ? Colors.black : Colors.white),
                        SizedBox(width: 10),
                        Text(
                          AppLocalizations.of(context)?.payDriverWith ?? AppLocalizations.of(context)!.tr('Pay Driver With'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.5)),
                      ]),
                    SizedBox(height: 6),
                    Text(
                      AppLocalizations.of(context)?.chooseDriverPaymentMethod ?? AppLocalizations.of(context)!.tr('Choose how the driver is paid for shipping'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        letterSpacing: -0.2)),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    // Option 1: Saved Bank Account / Card
                    (() {
                      final methods = _savedPaymentMethodsCache;
                      final hasMethod = methods.isNotEmpty;
                      String cardSubtitle;
                      if (hasMethod) {
                        final m = methods.first;
                        final type = (m['type'] ?? AppLocalizations.of(context)!.tr('')).toString().toLowerCase();
                        final typeBadge = (type == 'sepa' || type == 'sepa_debit')
                            ? 'SEPA'
                            : (type == 'us_bank_account' || type == 'ach')
                                ? 'ACH'
                                : (type == 'card')
                                    ? 'Card'
                                    : type.toUpperCase();
                        final bankName = (m['bank_name'] ?? AppLocalizations.of(context)!.tr('')).toString().trim();
                        final last4 = (m['last4'] ?? AppLocalizations.of(context)!.tr('')).toString().trim();
                        final parts = [
                          if (bankName.isNotEmpty) bankName,
                          if (last4.isNotEmpty) '•••• $last4',
                          typeBadge,
                        ];
                        cardSubtitle = parts.join('  ·  ');
                      } else {
                        cardSubtitle = AppLocalizations.of(context)?.noPaymentMethodOnFile ?? AppLocalizations.of(context)!.tr('No payment method on file');
                      }
                      return _buildDriverPaymentOption(
                        value: 'card',
                        title: AppLocalizations.of(context)?.savedBankAccount ?? AppLocalizations.of(context)!.tr('Saved Bank Account'),
                        subtitle: cardSubtitle,
                        icon: CupertinoIcons.creditcard_fill,
                        selected: _defaultShippingPayment == 'card',
                        isLight: isLight,
                        setModalState: setModalState,
                        enabled: hasMethod);
                    })(),
                    SizedBox(height: 10),

                    // Option 2: Monioo Wallet (needs bank fallback)
                    (() {
                      final hasBankFallback = _savedPaymentMethodsCache.isNotEmpty;
                      String walletSubtitle;
                      if (!hasBankFallback) {
                        walletSubtitle = AppLocalizations.of(context)?.bankAccountRequiredAsFallback ?? AppLocalizations.of(context)!.tr('Bank account required as fallback');
                      } else if (_walletLoaded) {
                        walletSubtitle =
                            '${AppLocalizations.of(context)?.walletBalanceLabel ?? AppLocalizations.of(context)!.tr('Balance')}: ${_formatCurrency(_walletBalance)}  ·  ${AppLocalizations.of(context)?.remainderFromBank ?? AppLocalizations.of(context)!.tr('remainder from bank')}';
                      } else {
                        walletSubtitle = AppLocalizations.of(context)?.remainderChargedFromBank ?? AppLocalizations.of(context)!.tr('Remainder charged from bank');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDriverPaymentOption(
                            value: 'wallet',
                            title: AppLocalizations.of(context)!.tr('Monioo Wallet') ?? AppLocalizations.of(context)!.tr('Monioo Wallet'),
                            subtitle: walletSubtitle,
                            icon: CupertinoIcons.rectangle_stack_fill,
                            selected: _defaultShippingPayment == 'wallet',
                            isLight: isLight,
                            setModalState: setModalState,
                            enabled: hasBankFallback),
                          if (!hasBankFallback) ...[
                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.info_circle,
                                    size: 13,
                                    color: (isLight ? Colors.black : Colors.white)
                                        .withOpacity(0.45)),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      AppLocalizations.of(context)?.addBankAccountForWalletHint ?? AppLocalizations.of(context)!.tr('Please add a bank account first. It will be used as fallback if your wallet balance is insufficient.'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.45)))),
                                ])),
                          ],
                        ]);
                    })(),

                    SizedBox(height: 40),

                    // ═══════════════════════════════════════════
                    // SCHEDULE SECTION
                    // ═══════════════════════════════════════════
                    Text(
                      AppLocalizations.of(context)?.payoutSchedule ?? AppLocalizations.of(context)!.tr('Payout Schedule'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.5)),
                    SizedBox(height: 6),
                    Text(
                      AppLocalizations.of(
                            context)?.chooseWhenToReceiveEarnings ?? AppLocalizations.of(context)!.tr('Choose when to receive your earnings'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5),
                        letterSpacing: -0.2)),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    // Payout Schedule - TradeRepublicSlider Style
                    TradeRepublicSliderExpanded(
                      labels: [
                        AppLocalizations.of(context)?.daily ?? AppLocalizations.of(context)!.tr('Daily'),
                        AppLocalizations.of(context)?.weekly ?? AppLocalizations.of(context)!.tr('Weekly'),
                        AppLocalizations.of(context)?.monthly ?? AppLocalizations.of(context)!.tr('Monthly'),
                        AppLocalizations.of(context)?.manual ?? AppLocalizations.of(context)!.tr('Manual'),
                      ],
                      selectedIndex: selectedPayoutSchedule == 'daily'
                          ? 0
                          : selectedPayoutSchedule == 'weekly'
                          ? 1
                          : selectedPayoutSchedule == 'monthly'
                          ? 2
                          : 3,
                      onChanged: (index) {
                        final schedules = [
                          'daily',
                          'weekly',
                          'monthly',
                          'manual',
                        ];
                        final newSchedule = schedules[index];
                        setModalState(
                          () => selectedPayoutSchedule = newSchedule);
                        _savePayoutSchedule(newSchedule);

                        // Show manual payout modal if Manual is selected
                        if (newSchedule == 'manual') {
                          Navigator.pop(context);
                          _showManualPayoutModal(context, isLight);
                        }
                      },
                      horizontalPadding: 0),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                    // Description for selected schedule
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        selectedPayoutSchedule == 'daily'
                            ? (AppLocalizations.of(context)?.autoPayoutsDaily ?? AppLocalizations.of(context)!.tr('Automatic payouts every day at 9:00 AM'))
                            : selectedPayoutSchedule == 'weekly'
                            ? (AppLocalizations.of(
                                    context)?.autoPayoutsWeekly ?? AppLocalizations.of(context)!.tr('Automatic payouts every Monday at 9:00 AM'))
                            : selectedPayoutSchedule == 'monthly'
                            ? (AppLocalizations.of(
                                    context)?.autoPayoutsMonthly ?? AppLocalizations.of(context)!.tr('Automatic payouts on the first Monday of each month'))
                            : (AppLocalizations.of(context)?.withdrawManually ?? AppLocalizations.of(context)!.tr('Withdraw manually anytime (tiered margin: 1.5% / 1.25% / 1% / 0.5% enterprise)')),  
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          letterSpacing: -0.2))),

                    SizedBox(height: 48),

                    // ═══════════════════════════════════════════
                    // HISTORY SECTION
                    // ═══════════════════════════════════════════
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.history ?? AppLocalizations.of(context)!.tr('History'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.5)),
                        // Animated Tab Switcher - TradeRepublicSlider
                        TradeRepublicSlider(
                          labels: [
                            AppLocalizations.of(context)?.earnings ?? AppLocalizations.of(context)!.tr('Earnings'),
                            AppLocalizations.of(context)?.payouts ?? AppLocalizations.of(context)!.tr('Payouts'),
                          ],
                          selectedIndex: selectedTabIndex,
                          segmentWidth: 100,
                          onChanged: (index) {
                            setModalState(() => selectedTabIndex = index);
                          }),
                      ]),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    // Animated content transition
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: selectedTabIndex == 0
                          ? // Earnings
                            KeyedSubtree(
                              key: const ValueKey('earnings'),
                              child: earningsHistory.isEmpty
                                  ? _buildEmptyState(
                                      AppLocalizations.of(
                                            context)?.noEarningsYet ?? AppLocalizations.of(context)!.tr('No earnings yet'),
                                      AppLocalizations.of(
                                            context)?.earningsWillAppearHere ?? AppLocalizations.of(context)!.tr('Your earnings will appear here'),
                                      isLight)
                                  : Column(
                                      children: earningsHistory
                                          .take(5)
                                          .map(
                                            (earning) => _buildHistoryItem(
                                              earning['description'] ??
                                                  AppLocalizations.of(
                                                    context)?.orderLabel ?? AppLocalizations.of(context)!.tr('Order'),
                                              earning['created_at'] ?? AppLocalizations.of(context)!.tr(''),
                                              _formatCurrency(
                                                earning['amount']?.toDouble() ??
                                                    0.0),
                                              true,
                                              isLight,
                                              itemData: earning))
                                          .toList()))
                          : // Payouts
                            KeyedSubtree(
                              key: const ValueKey('payouts'),
                              child: recentPayouts.isEmpty
                                  ? _buildEmptyState(
                                      AppLocalizations.of(
                                            context)?.noPayoutsYet ?? AppLocalizations.of(context)!.tr('No payouts yet'),
                                      AppLocalizations.of(
                                            context)?.payoutsWillAppearHere ?? AppLocalizations.of(context)!.tr('Your payouts will appear here'),
                                      isLight)
                                  : Column(
                                      children: recentPayouts
                                          .take(5)
                                          .map(
                                            (payout) => _buildHistoryItem(
                                              AppLocalizations.of(
                                                    context)?.payoutLabel ?? AppLocalizations.of(context)!.tr('Payout'),
                                              payout['payout_date'] ??
                                                  payout['created_at'] ?? AppLocalizations.of(context)!.tr(''),
                                              _formatCurrency(
                                                payout['amount']?.toDouble() ??
                                                    0.0),
                                              false,
                                              isLight,
                                              itemData: payout))
                                          .toList()))),

                    SizedBox(height: 48),

                    // ═══════════════════════════════════════════
                    // SHIPPING PAYMENT INVOICES
                    // ═══════════════════════════════════════════
                    (() {
                      final shippingPayments = _walletTransactions
                          .where((tx) =>
                              (tx['reference_type']?.toString() ?? '') == 'shipping_payment')
                          .toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.tr('walletShippingInvoicesTitle'),
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: isLight ? Colors.black : Colors.white,
                                  letterSpacing: -0.5)),
                            ]),
                          SizedBox(height: 6),
                          Text(
                                AppLocalizations.of(context)!.tr('walletShippingInvoicesSubtitle'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.5),
                              letterSpacing: -0.2)),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                          if (shippingPayments.isEmpty)
                            Container(
                              padding: DesktopAppWrapper.getPagePadding(),
                              decoration: BoxDecoration(
                                color: isLight ? Colors.white : Colors.black,
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                              child: Center(
                                child: Text(
                                  AppLocalizations.of(context)!.tr('walletNoShippingPaymentsYet'),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: (isLight ? Colors.black : Colors.white)
                                        .withOpacity(0.5)))))
                          else
                            ...shippingPayments.map((tx) {
                              final txId = tx['id'];
                              final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                              final orderId = tx['reference_id']?.toString() ?? '';
                              final description = tx['description']?.toString() ?? '';
                              final createdAt = tx['created_at']?.toString() ?? '';

                              String dateStr = '';
                              if (createdAt.isNotEmpty) {
                                try {
                                  final dt = DateTime.parse(createdAt);
                                  dateStr = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
                                } catch (_) {
                                  dateStr = createdAt;
                                }
                              }

                              return Container(
                                margin: EdgeInsets.only(bottom: 12),
                                padding: DesktopAppWrapper.getPagePadding(),
                                decoration: BoxDecoration(
                                  color: isLight ? Colors.white : Colors.black,
                                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                child: Row(
                                  children: [
                                    // Icon
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50.withOpacity(
                                          isLight ? 1.0 : 0.15),
                                        borderRadius: BorderRadius.circular(22)),
                                      child: Icon(
                                        CupertinoIcons.cube_box_fill,
                                        size: 22,
                                        color: Colors.orange.shade500)),
                                    SizedBox(width: 14),
                                    // Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${AppLocalizations.of(context)!.tr('walletOrderPrefix')} #$orderId',
                                            style: TextStyle(
                                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                                              fontWeight: FontWeight.w600,
                                              color: isLight ? Colors.black : Colors.white,
                                              letterSpacing: -0.3)),
                                          SizedBox(height: 2),
                                          Text(
                                            description,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              color: (isLight ? Colors.black : Colors.white)
                                                  .withOpacity(0.5)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                          if (dateStr.isNotEmpty) ...[
                                            SizedBox(height: 1),
                                            Text(
                                              dateStr,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w400,
                                                color: (isLight ? Colors.black : Colors.white)
                                                    .withOpacity(0.35))),
                                          ],
                                        ])),
                                    // Amount + download
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatCurrency(amount.abs()),
                                          style: TextStyle(
                                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.orange.shade500,
                                            letterSpacing: -0.3)),
                                        SizedBox(height: 6),
                                        TradeRepublicTap(
                                          onTap: () => _downloadWalletTransactionDocument(txId, isLight),
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: (isLight ? Colors.black : Colors.white)
                                                  .withOpacity(0.07),
                                              borderRadius: BorderRadius.circular(10)),
                                            child: Icon(
                                              CupertinoIcons.arrow_down_circle,
                                              size: 18,
                                              color: (isLight ? Colors.black : Colors.white)
                                                  .withOpacity(0.55)))),
                                      ]),
                                  ]));
                            }),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                        ]);
                    })(),

                    SizedBox(height: 48),

                    // ═══════════════════════════════════════════
                    // BANK ACCOUNT SECTION (mandatory, max 1, for payouts)
                    // ═══════════════════════════════════════════
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.building_2_fill,
                              size: 22,
                              color: isLight ? Colors.black : Colors.white),
                            SizedBox(width: 10),
                            Text(
                              AppLocalizations.of(context)?.bankAccount ?? AppLocalizations.of(context)!.tr('Bank Account'),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: isLight ? Colors.black : Colors.white,
                                letterSpacing: -0.5)),
                          ]),
                      ]),
                    SizedBox(height: 4),
                    Text(
                      'Mandatory for payouts · Only one bank account allowed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                        letterSpacing: -0.2)),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    // Bank Account Card (max 1, for payouts)
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadSavedPaymentMethods(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: isLight ? Colors.white : Colors.black,
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CultiooLoadingIndicator(size: 20))));
                        }

                        final allMethods = snapshot.data ?? [];
                        // Filter only bank methods (SEPA, ACH, wire)
                        final bankMethods = allMethods.where((m) {
                          final type = (m['type'] ?? '').toString().toLowerCase();
                          return type == 'sepa' || type == 'sepa_debit' || type == 'ach' || type == 'us_bank_account' || type == 'wire';
                        }).toList();

                        if (bankMethods.isEmpty) {
                          return TradeRepublicTap(
                            onTap: () {
                              Navigator.pop(context);
                              _checkAndShowAddPaymentMethod(context, isLight);
                            },
                            child: Container(
                              padding: DesktopAppWrapper.getPagePadding(),
                              decoration: BoxDecoration(
                                color: isLight ? Colors.white : Colors.black,
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                    child: Icon(
                                      CupertinoIcons.add,
                                      color: Colors.orange,
                                      size: 22)),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppLocalizations.of(context)?.addBankAccount ?? AppLocalizations.of(context)!.tr('Add Bank Account'),
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                            color: isLight ? Colors.black : Colors.white,
                                            letterSpacing: -0.3)),
                                        SizedBox(height: 2),
                                        Text(
                                          AppLocalizations.of(context)?.connectBankForPayouts ?? AppLocalizations.of(context)!.tr('Connect your bank to receive payouts'),
                                          style: TextStyle(
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                            fontWeight: FontWeight.w400,
                                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
                                      ])),
                                  Icon(
                                    CupertinoIcons.chevron_right,
                                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                                    size: 22),
                                ])));
                        }

                        final method = bankMethods.first;
                        final methodType = (method['type'] ?? '').toString().toLowerCase();
                        final isSepa = methodType == 'sepa' || methodType == 'sepa_debit';
                        final bankName = (method['bank_name'] ?? method['bankName'] ?? '').toString().trim().isNotEmpty
                            ? (method['bank_name'] ?? method['bankName']).toString()
                            : (isSepa ? 'SEPA Bank' : 'US Bank');
                        final ibanValue = (method['iban'] ?? '').toString().replaceAll(' ', '');
                        final accountValue = (method['account_number'] ?? method['accountNumber'] ?? '').toString();
                        final last4 = (method['last4'] ?? '').toString();
                        final maskedNumber = isSepa
                            ? '•••• ${(last4.isNotEmpty ? last4 : (ibanValue.length > 4 ? ibanValue.substring(ibanValue.length - 4) : ibanValue))}'
                            : '•••• ${(last4.isNotEmpty ? last4 : (accountValue.length > 4 ? accountValue.substring(accountValue.length - 4) : '****'))}';

                        return TradeRepublicSwipeAction(
                          key: ValueKey('bank_${method['id']?.toString() ?? ''}'),
                          margin: EdgeInsets.only(bottom: 12),
                          trailing: TradeRepublicSwipeSpec(
                            icon: CupertinoIcons.delete_solid,
                            label: AppLocalizations.of(context)?.delete ?? 'Delete',
                            backgroundColor: const Color(0xFFFF3B30),
                            foregroundColor: Colors.white,
                            onActivate: () async {
                              Navigator.pop(context);
                              await _deletePaymentMethod(method['id'], isLight);
                              if (mounted) {
                                _showPaymentSettingsModal(this.context, isLight);
                              }
                            }),
                          child: TradeRepublicTap(
                            onTap: () {
                              Navigator.pop(context);
                              _checkAndShowAddPaymentMethod(context, isLight);
                            },
                            child: Container(
                              height: 180,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isLight
                                      ? [Colors.black, Colors.black.withOpacity(0.85), Colors.black]
                                      : [Colors.white.withOpacity(0.15), Colors.white.withOpacity(0.25), Colors.white.withOpacity(0.1)],
                                  stops: const [0.0, 0.5, 1.0]),
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10)),
                                ]),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                      child: CustomPaint(painter: _CardPatternPainter()))),
                                  Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                              child: Icon(CupertinoIcons.building_2_fill, color: Colors.white, size: 24)),
                                            Container(
                                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                              child: Text(
                                                isSepa ? 'SEPA' : 'ACH',
                                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1.5))),
                                          ]),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              maskedNumber,
                                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 2.5)),
                                            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      AppLocalizations.of(context)?.bank ?? 'BANK',
                                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.5), letterSpacing: 1.2)),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      bankName.toUpperCase(),
                                                      style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(), fontWeight: FontWeight.w600, color: Colors.white, letterSpacing: 0.5)),
                                                  ]),
                                                Row(
                                                  children: [
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: BoxDecoration(
                                                        color: Colors.greenAccent.shade400,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [BoxShadow(color: Colors.greenAccent.withOpacity(0.5), blurRadius: 8)])),
                                                    SizedBox(width: 6),
                                                    Text(
                                                      AppLocalizations.of(context)?.connected ?? 'Connected',
                                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.7))),
                                                  ]),
                                              ]),
                                          ]),
                                      ])),
                                ]))));
                      }),

                    SizedBox(height: 40),

                    // ═══════════════════════════════════════════
                    // CARDS SECTION (unlimited, for shipping payments)
                    // ═══════════════════════════════════════════
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.creditcard_fill,
                              size: 22,
                              color: isLight ? Colors.black : Colors.white),
                            SizedBox(width: 10),
                            Text(
                              'Cards',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: isLight ? Colors.black : Colors.white,
                                letterSpacing: -0.5)),
                          ]),
                        TradeRepublicTap(
                          onTap: () {
                            Navigator.pop(context);
                            _showAddPaymentMethodModal(context, isLight);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.06),
                              borderRadius: BorderRadius.circular(999)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.add,
                                  size: 14,
                                  color: isLight ? Colors.black : Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'Add Card',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? Colors.black : Colors.white)),
                              ]))),
                      ]),
                    SizedBox(height: 4),
                    Text(
                      'For shipping payments · Unlimited cards allowed',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                        letterSpacing: -0.2)),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                    // Cards List
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadSavedPaymentMethods(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: isLight ? Colors.white : Colors.black,
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CultiooLoadingIndicator(size: 20))));
                        }

                        final allMethods = snapshot.data ?? [];
                        // Filter only card methods
                        final cardMethods = allMethods.where((m) {
                          final type = (m['type'] ?? '').toString().toLowerCase();
                          return type == 'card';
                        }).toList();

                        if (cardMethods.isEmpty) {
                          return TradeRepublicTap(
                            onTap: () {
                              Navigator.pop(context);
                              _showAddPaymentMethodModal(context, isLight);
                            },
                            child: Container(
                              padding: DesktopAppWrapper.getPagePadding(),
                              decoration: BoxDecoration(
                                color: isLight ? Colors.white : Colors.black,
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                                    child: Icon(
                                      CupertinoIcons.creditcard,
                                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                                      size: 22)),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Add a Card',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                            color: isLight ? Colors.black : Colors.white,
                                            letterSpacing: -0.3)),
                                        SizedBox(height: 2),
                                        Text(
                                          'Use debit or credit cards for shipping payments',
                                          style: TextStyle(
                                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                                            fontWeight: FontWeight.w400,
                                            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
                                      ])),
                                  Icon(
                                    CupertinoIcons.chevron_right,
                                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                                    size: 22),
                                ])));
                        }

                        return Column(
                          children: cardMethods.map((method) {
                            final brand = (method['brand'] ?? method['card']?['brand'] ?? 'card').toString();
                            final last4 = (method['last4'] ?? method['card']?['last4'] ?? '????').toString();
                            final expM = (method['exp_month'] ?? method['card']?['exp_month'] ?? '').toString();
                            final expY = (method['exp_year'] ?? method['card']?['exp_year'] ?? '').toString();
                            final holder = (method['account_holder_name'] ?? '').toString().trim();
                            final isDefault = method['is_default'] == true || method['isDefault'] == true;

                            return TradeRepublicSwipeAction(
                              key: ValueKey('card_${method['id']?.toString() ?? ''}'),
                              margin: EdgeInsets.only(bottom: 12),
                              trailing: TradeRepublicSwipeSpec(
                                icon: CupertinoIcons.delete_solid,
                                label: AppLocalizations.of(context)?.delete ?? 'Delete',
                                backgroundColor: const Color(0xFFFF3B30),
                                foregroundColor: Colors.white,
                                onActivate: () async {
                                  Navigator.pop(context);
                                  await _deletePaymentMethod(method['id'], isLight);
                                  if (mounted) {
                                    _showPaymentSettingsModal(this.context, isLight);
                                  }
                                }),
                              child: CreditCardWidget(
                                brand: brand,
                                last4: last4,
                                expMonth: expM,
                                expYear: expY,
                                cardholderName: holder,
                                isDefault: isDefault));
                          }).toList());
                      }),

                    SizedBox(height: 60),
                  ]))),
          ]))).whenComplete(() {
      if (mounted) setState(() => _isPaymentSettingsOpen = false);
      NavigationVisibility.show();
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // MONIOO WALLET HELPERS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildMoniooWalletCard(bool isLight, StateSetter setModalState) {
    const green = Color(0xFF22C55E);
    final l10n = AppLocalizations.of(context)!;
    final textColor = isLight ? Colors.black : Colors.white;
    final subtleColor = textColor.withOpacity(0.45);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: l10n.tr('walletMoniooTitle'),
          subtitle: l10n.tr('walletMoniooSubtitle'),
          titleStyle: TradeRepublicTheme.titleLarge(context).copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8),
          padding: EdgeInsets.only(bottom: 16)),
        TradeRepublicCard(
          padding: DesktopAppWrapper.getPagePadding(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14)),
                    child: Icon(
                      CupertinoIcons.creditcard_fill,
                      color: green,
                      size: 22)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.tr('walletBalanceLabel'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: subtleColor)),
                        Text(
                          _formatCurrency(_walletBalance),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                            letterSpacing: -1)),
                      ])),
                  TradeRepublicButton(
                    label: l10n.tr('walletTopUpAction'),
                    onPressed: () =>
                        _showWalletTopUpSheet(isLight, setModalState),
                    backgroundColor: green,
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding())),
                ]),
              // Recent transactions
              if (_walletTransactions.isNotEmpty) ...[
                SizedBox(height: 20),
                TradeRepublicDivider(
                  color: textColor.withOpacity(0.07),
                  margin: EdgeInsets.zero),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                Text(
                  l10n.tr('walletRecentLabel'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: subtleColor,
                    letterSpacing: 0.4)),
                SizedBox(height: 10),
                ..._walletTransactions
                    .take(4)
                    .map((tx) => _buildWalletTxRow(tx, isLight)),
              ] else ...[
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                Center(
                  child: Text(
                    l10n.tr('walletNoTransactionsYet'),
                    style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(), color: subtleColor))),
              ],
            ])),
      ]);
  }

  Widget _buildWalletTxRow(Map<String, dynamic> tx, bool isLight) {
    final textColor = isLight ? Colors.black : Colors.white;
    final txId = tx['id'];
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final type = tx['type']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final isPositive = amount > 0;
    final amountColor = isPositive
        ? const Color(0xFF22C55E)
        : Colors.red.shade400;

    IconData icon;
    switch (type) {
      case 'topup':
        icon = CupertinoIcons.arrow_down_circle_fill;
        break;
      case 'payment':
        icon = CupertinoIcons.arrow_up_circle_fill;
        break;
      case 'refund':
        icon = CupertinoIcons.return_icon;
        break;
      default:
        icon = CupertinoIcons.circle_fill;
    }

    String dateStr = '';
    if (tx['created_at'] != null) {
      try {
        final dt = DateTime.tryParse(tx['created_at'].toString());
        if (dt != null) {
          dateStr =
              '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
        }
      } catch (_) {}
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: amountColor),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx['description'] ?? type.toUpperCase(),
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    letterSpacing: -0.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withOpacity(0.35))),
              ])),
          Text(
            '${isPositive ? '+' : ''}${_formatCurrency(amount.abs())}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: amountColor,
              letterSpacing: -0.3)),
          if (txId != null) ...[
            SizedBox(width: 4),
            Tooltip(
              message: type == 'topup'
                  ? 'Download Invoice'
                  : 'Download Confirmation',
              child: TradeRepublicTap(
                onTap: () => _downloadWalletTransactionDocument(txId, isLight),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.07),
                    borderRadius: BorderRadius.circular(8)),
                  child: Icon(
                    type == 'topup'
                        ? CupertinoIcons.doc_text_fill
                        : CupertinoIcons.doc_plaintext,
                    size: 15,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.55))))),
          ],
        ]));
  }

  Widget _buildPendingShippingSection(bool isLight, StateSetter setModalState) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TradeRepublicSectionHeader(
          title: l10n.tr('walletShippingDueTitle'),
          subtitle: l10n.tr('walletShippingDueSubtitle'),
          leading: Icon(
            CupertinoIcons.exclamationmark_circle_fill,
            size: 22,
            color: Colors.orange.shade500),
          padding: EdgeInsets.only(bottom: 16)),
        ..._pendingShippingPayments.map(
          (order) => _buildPendingShippingItem(order, isLight, setModalState)),
      ]);
  }

  Widget _buildPendingShippingItem(
    Map<String, dynamic> order,
    bool isLight,
    StateSetter setModalState) {
    final textColor = isLight ? Colors.black : Colors.white;
    final orderId = order['order_id']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final productName = order['product_name']?.toString() ?? 'Order #$orderId';
    final shippingCost = (order['shipping_cost'] as num?)?.toDouble() ?? 0.0;
    final incoterm = order['incoterm']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final status = order['status']?.toString() ?? AppLocalizations.of(context)!.tr('');

    String dateStr = '';
    if (order['date'] != null) {
      try {
        final dt = DateTime.tryParse(order['date'].toString());
        if (dt != null) {
          dateStr =
              '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
        }
      } catch (_) {}
    }

    return TradeRepublicCard.outlined(
      margin: EdgeInsets.only(bottom: 12),
      padding: DesktopAppWrapper.getPagePadding(),
      borderColor: Colors.orange.shade400.withOpacity(0.35),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.orange.shade50.withOpacity(isLight ? 1 : 0.12),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
            child: Icon(
              CupertinoIcons.cube_box_fill,
              size: 22,
              color: Colors.orange.shade500)),
          SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    letterSpacing: -0.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
                SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100.withOpacity(
                          isLight ? 1 : 0.15),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        incoterm,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade700))),
                    SizedBox(width: 6),
                    Text(
                      'Order #$orderId',
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withOpacity(0.4))),
                    if (dateStr.isNotEmpty) ...[
                      Text(
                        ' · $dateStr',
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withOpacity(0.4))),
                    ],
                  ]),
              ])),
          SizedBox(width: 10),
          // Amount + Pay button
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatCurrency(shippingCost),
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: -0.3)),
              SizedBox(height: 6),
              TradeRepublicButton(
                label: AppLocalizations.of(
                  context)!.tr('walletAuthorizeAction'),
                onPressed: () => _payShippingFromWallet(
                  orderId,
                  shippingCost,
                  isLight,
                  setModalState),
                backgroundColor: Colors.orange.shade500,
                height: 36,
                padding: EdgeInsets.symmetric(horizontal: 12)),
            ]),
        ]));
  }

  void _showWalletTopUpSheet(bool isLight, StateSetter setModalState) {
    final amountController = TextEditingController();
    bool isFormattingAmount = false;
    // Possible states: 'input' | 'loading' | 'browser_opened'
    String sheetState = 'input';
    String? pendingSessionId;
    bool isPolling = false;
    // Selected payment method ID (null = use default)
    String? selectedPaymentMethodId;
    // Load saved payment methods
    List<Map<String, dynamic>> savedMethods = [];
    bool methodsLoaded = false;

    // Load payment methods asynchronously
    _loadSavedPaymentMethods().then((methods) {
      savedMethods = methods;
      methodsLoaded = true;
      if (mounted) setState(() {});
    });

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          final l10n = AppLocalizations.of(ctx)!;
          final paymentSystem = (userData?['payment_system'] ?? '')
              .toString()
              .toUpperCase();
          final isSepaTopup = paymentSystem == 'SEPA';
          final isAchTopup = paymentSystem == 'USA' || paymentSystem == 'ACH';
          final amountPrefix = AppSettings().currencySymbol;
          final processingMessage = isSepaTopup
              ? 'SEPA top-ups can take a little longer until the bank confirms the payment.'
              : isAchTopup
              ? 'ACH top-ups can take a little longer until the bank confirms the payment.'
              : 'Your payment is being processed. Please check again in a moment.';

          // ── Helper: poll backend for fulfillment ──────────────────────────
          Future<void> pollTopUpStatus() async {
            if (isPolling || pendingSessionId == null) return;
            isPolling = true;
            try {
              final token = await _getStoredToken();
              final resp = await http.get(
                Uri.parse(
                  '${ApiConfig.baseUrl}/api/wallet/topup-status?sessionId=$pendingSessionId'),
                headers: {if (token != null) 'Authorization': 'Bearer $token'});
              final data = json.decode(resp.body);
              if (resp.statusCode == 200 && data['fulfilled'] == true) {
                final newBal = (data['balance'] as num?)?.toDouble() ?? 0.0;
                final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
                setModalState(() => _walletBalance = newBal);
                setState(() => _walletBalance = newBal);
                await _loadWalletData();
                setModalState(() {});
                if (ctx.mounted) Navigator.of(ctx).pop();
                TopNotification.success(
                  context,
                  '${l10n.tr('walletTopupSuccessPrefix')} +${_formatCurrency(amt)} · ${l10n.tr('walletNewBalancePrefix')}: ${_formatCurrency(newBal)}');
              } else if (resp.statusCode == 200 && data['processing'] == true) {
                if (ctx.mounted) {
                  TopNotification.info(ctx, processingMessage);
                }
              }
            } catch (_) {
            } finally {
              isPolling = false;
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              left: 20,
              right: 20,
              top: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14)),
                      child: Icon(
                        CupertinoIcons.creditcard_fill,
                        color: Color(0xFF22C55E),
                        size: 22)),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.tr('walletTopupTitle'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                              letterSpacing: -0.5)),
                          Text(
                            l10n.tr('walletTopupSubtitle'),
                            style: TextStyle(
                              fontSize: 13,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.5))),
                        ])),
                  ]),
                SizedBox(height: 20),

                // ── Balance card ────────────────────────────────────────────
                TradeRepublicCard(
                  backgroundColor: const Color(0xFF22C55E).withOpacity(0.08),
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.tr('walletCurrentBalanceLabel'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.6))),
                      Text(
                        _formatCurrency(_walletBalance),
                        style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF22C55E),
                          letterSpacing: -0.5)),
                    ])),

                if (sheetState == 'browser_opened') ...[
                  // ── State: browser opened, waiting for payment ──────────
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                  TradeRepublicCard(
                    backgroundColor: const Color(0xFF22C55E).withOpacity(0.06),
                    padding: DesktopAppWrapper.getPagePadding(),
                    child: Column(
                      children: [
                        Icon(
                          CupertinoIcons.checkmark_seal_fill,
                          size: 40,
                          color: Color(0xFF22C55E)),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          l10n.tr('walletPaymentOpenedTitle'),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF22C55E)),
                          textAlign: TextAlign.center),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          l10n.tr('walletPaymentOpenedSubtitle'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.5)),
                          textAlign: TextAlign.center),
                      ])),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                  Row(
                    children: [
                      Expanded(
                        child: TradeRepublicButton(
                          label: l10n.tr('walletReopenAction'),
                          isSecondary: true,
                          height: 50,
                          onPressed: () async {
                            return;
                            try {
                              final token = await _getStoredToken();
                              final resp = await http.get(
                                Uri.parse(
                                  '${ApiConfig.baseUrl}/api/wallet/topup-status?sessionId=$pendingSessionId'),
                                headers: {
                                  if (token != null)
                                    'Authorization': 'Bearer $token',
                                });
                              final data = json.decode(resp.body);
                              if (data['sessionUrl'] != null) {
                                launchUrl(
                                  Uri.parse(data['sessionUrl']),
                                  mode: LaunchMode.inAppBrowserView);
                              }
                            } catch (_) {}
                          })),
                      SizedBox(width: 12),
                      Expanded(
                        child: TradeRepublicButton(
                          label: l10n.tr('walletDoneAction'),
                          backgroundColor: const Color(0xFF22C55E),
                          height: 50,
                          onPressed: () => pollTopUpStatus())),
                    ]),
                ] else ...[
                  // ── State: input ─────────────────────────────────────────
                  SizedBox(height: 20),

                  // Amount input
                  TradeRepublicTextField.currency(
                    controller: amountController,
                    hintText: '0.00',
                    onChanged: (raw) {
                      if (isFormattingAmount) return;
                      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
                      if (digits.isEmpty) {
                        isFormattingAmount = true;
                        amountController.clear();
                        isFormattingAmount = false;
                        return;
                      }
                      final cents = int.tryParse(digits) ?? 0;
                      final normalized = cents / 100.0;
                      final formatted = formatNumberUS(
                        normalized,
                        fractionDigits: 2);
                      if (formatted == amountController.text) return;
                      isFormattingAmount = true;
                      amountController.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(
                          offset: formatted.length));
                      isFormattingAmount = false;
                    }),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                  // Quick amounts
                  Row(
                    children: [50.0, 100.0, 250.0, 500.0].map((amt) {
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: TradeRepublicButton(
                            label: '$amountPrefix${formatNumberUS(amt, fractionDigits: 0)}',
                            onPressed: () =>
                                amountController.text = formatNumberUS(amt, fractionDigits: 0),
                            isSecondary: true,
                            height: 40)));
                    }).toList()),
                  SizedBox(height: 20),

                  // ── Payment Method Selector ───────────────────────────────
                  Text(
                    'Pay with',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      letterSpacing: 0.3)),
                  SizedBox(height: 10),

                  if (!methodsLoaded)
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CultiooLoadingIndicator(size: 20))))
                  else if (savedMethods.isEmpty)
                    Container(
                      padding: DesktopAppWrapper.getPagePadding(),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.04),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.exclamationmark_circle,
                            size: 18,
                            color: Colors.orange),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No payment methods saved. Add one in Payment Settings first.',
                              style: TextStyle(
                                fontSize: 13,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6)))),
                        ]))
                  else
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: savedMethods.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final method = savedMethods[i];
                          final mId = method['id']?.toString() ?? '';
                          final type = (method['type'] ?? '').toString().toLowerCase();
                          final isCard = type == 'card';
                          final isSepa = type == 'sepa' || type == 'sepa_debit';
                          final isSelected = selectedPaymentMethodId == mId ||
                              (selectedPaymentMethodId == null && i == 0);

                          String label;
                          String subtitle;
                          IconData icon;
                          Color cardColor;

                          if (isCard) {
                            final brand = (method['brand'] ?? 'Card').toString();
                            final last4 = (method['last4'] ?? '****').toString();
                            label = brand.toUpperCase();
                            subtitle = '•••• $last4';
                            icon = CupertinoIcons.creditcard_fill;
                            cardColor = const Color(0xFF6366F1);
                          } else if (isSepa) {
                            final last4 = (method['last4'] ?? '').isNotEmpty
                                ? '•••• ${method['last4']}'
                                : 'SEPA';
                            label = 'SEPA';
                            subtitle = last4;
                            icon = CupertinoIcons.building_2_fill;
                            cardColor = const Color(0xFF3B82F6);
                          } else {
                            final bankName = (method['bank_name'] ?? 'Bank').toString();
                            final last4 = (method['last4'] ?? '****').toString();
                            label = bankName.length > 12
                                ? '${bankName.substring(0, 10)}…'
                                : bankName;
                            subtitle = '•••• $last4';
                            icon = CupertinoIcons.building_2_fill;
                            cardColor = const Color(0xFF8B5CF6);
                          }

                          return GestureDetector(
                            onTap: () {
                              setSheetState(() {
                                selectedPaymentMethodId = mId;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 160,
                              padding: EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? LinearGradient(
                                        colors: [
                                          cardColor,
                                          cardColor.withOpacity(0.8),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight)
                                    : null,
                                color: isSelected
                                    ? null
                                    : (isLight ? Colors.white : Colors.black),
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                                border: isSelected
                                    ? null
                                    : Border.all(
                                        color: (isLight
                                                ? Colors.black
                                                : Colors.white)
                                            .withOpacity(0.1)),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: cardColor.withOpacity(0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4)),
                                      ]
                                    : []),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        icon,
                                        size: 18,
                                        color: isSelected
                                            ? Colors.white
                                            : (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.6)),
                                      const Spacer(),
                                      if (isSelected)
                                        Icon(
                                          CupertinoIcons
                                              .checkmark_circle_fill,
                                          size: 16,
                                          color: Colors.white),
                                    ]),
                                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                      fontWeight: FontWeight.w700,
                                      color: isSelected
                                          ? Colors.white
                                          : (isLight
                                                  ? Colors.black
                                                  : Colors.white),
                                      letterSpacing: -0.2),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected
                                          ? Colors.white.withOpacity(0.8)
                                          : (isLight
                                                  ? Colors.black
                                                  : Colors.white)
                                              .withOpacity(0.5))),
                                ])));
                        })),

                  SizedBox(height: 20),

                  // ── Pay button ────────────────────────────────────────────
                  TradeRepublicButton(
                    label: l10n.tr('walletPayNowAction'),
                    isLoading: sheetState == 'loading',
                    backgroundColor: const Color(0xFF22C55E),
                    icon: Icon(
                      CupertinoIcons.lock_shield_fill,
                      size: 16,
                      color: Colors.white),
                    onPressed: sheetState == 'loading'
                        ? null
                        : () async {
                            final amt = double.tryParse(
                              amountController.text
                                  .replaceAll(',', '')
                                  .replaceAll(' ', ''));
                            if (amt == null || amt <= 0) {
                              TopNotification.error(
                                ctx,
                                l10n.tr('walletEnterValidAmount'));
                              return;
                            }
                            setSheetState(() => sheetState = 'loading');
                            try {
                              final token = await _getStoredToken();
                              final body = <String, dynamic>{
                                'amount': amt,
                              };
                              // Send selected payment method ID if user picked one
                              if (selectedPaymentMethodId != null &&
                                  selectedPaymentMethodId!.isNotEmpty) {
                                body['payment_method_id'] =
                                    selectedPaymentMethodId;
                              }
                              final resp = await http.post(
                                Uri.parse(
                                  '${ApiConfig.baseUrl}/api/wallet/topup-checkout'),
                                headers: {
                                  'Content-Type': 'application/json',
                                  if (token != null)
                                    'Authorization': 'Bearer $token',
                                },
                                body: json.encode(body));
                              final data = json.decode(resp.body);
                              if (resp.statusCode == 200 &&
                                  data['success'] == true) {
                                final newBalance =
                                    (data['balance'] as num).toDouble();
                                final paidAmount =
                                    (data['amount'] as num).toDouble();
                                // Update wallet balance immediately
                                setModalState(() {
                                  _walletBalance = newBalance;
                                });
                                setState(() {
                                  _walletBalance = newBalance;
                                });
                                // Reload transactions
                                await _loadWalletData();
                                // Close the sheet
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                TopNotification.success(
                                  context,
                                  '+${_formatCurrency(paidAmount)} aufgeladen · Neuer Saldo: ${_formatCurrency(newBalance)}');
                              } else if (resp.statusCode == 402 &&
                                  data['error'] == 'no_payment_method') {
                                setSheetState(() => sheetState = 'input');
                                if (ctx.mounted) {
                                  TopNotification.error(
                                    ctx,
                                    'Please add a card first (Payment Settings → Cards → Add Card)');
                                }
                              } else {
                                setSheetState(() => sheetState = 'input');
                                if (ctx.mounted) {
                                  TopNotification.error(
                                    ctx,
                                    data['message'] ??
                                        data['error'] ??
                                        l10n.tr('walletCreatePaymentError'));
                                }
                              }
                            } catch (e) {
                              setSheetState(() => sheetState = 'input');
                              if (ctx.mounted) {
                                TopNotification.error(
                                    ctx, '${l10n.error}: $e');
                              }
                            }
                          }),
                  SizedBox(height: 10),
                  Center(
                    child: Text(
                      l10n.tr('walletStripeSecurityNote'),
                      style: TextStyle(
                        fontSize: 11,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.3)),
                      textAlign: TextAlign.center)),
                ],
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              ]));
        }));
  }

  Future<void> _payShippingFromWallet(
    String orderId,
    double shippingCost,
    bool isLight,
    StateSetter setModalState) async {
    final l10n = AppLocalizations.of(context)!;
    // Confirm dialog
    bool confirmed = false;
    await TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.cube_box_fill,
              size: 44,
              color: Colors.orange.shade500),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            Text(
              l10n.tr('walletAuthorizeShippingTitle'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isLight ? Colors.black : Colors.white,
                letterSpacing: -0.5),
              textAlign: TextAlign.center),
            SizedBox(height: 10),
            Text(
              '${l10n.tr('walletOrderPrefix')} #$orderId\n${l10n.tr('walletAuthorizeShippingBody')} ${_formatCurrency(shippingCost)}.',
              style: TextStyle(
                fontSize: 15,
                color: (isLight ? Colors.black : Colors.white).withOpacity(
                  0.55)),
              textAlign: TextAlign.center),
            SizedBox(height: 6),
            // Balance info
            Text(
              '${l10n.tr('walletCurrentBalancePrefix')}: ${_formatCurrency(_walletBalance)}',
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w600,
                color: _walletBalance >= shippingCost
                    ? const Color(0xFF22C55E)
                    : Colors.red.shade400)),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: l10n.cancel,
                    isSecondary: true,
                    onPressed: () => Navigator.of(context).pop())),
                SizedBox(width: 12),
                Expanded(
                  child: TradeRepublicButton(
                    label: l10n.tr('walletAuthorizeAction'),
                    backgroundColor: Colors.orange.shade500,
                    onPressed: () {
                      confirmed = true;
                      Navigator.of(context).pop();
                    })),
              ]),
            SizedBox(height: 20),
          ])));

    if (!confirmed) return;

    try {
      final token = await _getStoredToken();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/wallet/pay-shipping/$orderId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        });
      final data = json.decode(resp.body);

      if (resp.statusCode == 200 && data['success'] == true) {
        final newBalance = (data['balance'] as num?)?.toDouble() ?? 0.0;
        setModalState(() {
          _walletBalance = newBalance;
          _pendingShippingPayments.removeWhere(
            (o) => o['order_id']?.toString() == orderId);
        });
        setState(() => _walletBalance = newBalance);
        TopNotification.success(
          context,
          '${l10n.tr('walletShippingAuthorizedPrefix')} #$orderId · ${_formatCurrency(shippingCost)} ${l10n.tr('walletDeductedSuffix')}');
        // Refresh wallet transactions
        await _loadWalletData();
        setModalState(() {});
      } else if (resp.statusCode == 402) {
        // Insufficient balance
        TopNotification.error(
          context,
          l10n.tr('walletInsufficientBalanceTopup'));
        _showWalletTopUpSheet(isLight, setModalState);
      } else {
        TopNotification.error(
          context,
          data['error'] ?? l10n.tr('walletPaymentFailed'));
      }
    } catch (e) {
      TopNotification.error(context, '${l10n.error}: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // DRIVER PAYMENT METHOD OPTION WIDGET
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDriverPaymentOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required bool isLight,
    required StateSetter setModalState,
    bool enabled = true,
  }) {
    final mono = isLight ? Colors.black : Colors.white;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: TradeRepublicTap(
        onTap: enabled ? () => _saveShippingPaymentDefault(value, setModalState) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? mono : mono.withOpacity(0.06),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? (isLight ? Colors.white : Colors.black).withOpacity(0.15)
                    : mono.withOpacity(0.08),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
              child: Icon(
                icon,
                size: 20,
                color: selected
                    ? (isLight ? Colors.white : Colors.black)
                    : mono.withOpacity(0.6))),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? (isLight ? Colors.white : Colors.black)
                          : mono,
                      letterSpacing: -0.3)),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: selected
                          ? (isLight ? Colors.white : Colors.black)
                              .withOpacity(0.65)
                          : mono.withOpacity(0.5))),
                ])),
            if (selected)
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                size: 22,
                color: isLight ? Colors.white : Colors.black)
            else
              Icon(
                CupertinoIcons.circle,
                size: 22,
                color: mono.withOpacity(0.25)),
          ]))));
  }

  // ═══════════════════════════════════════════════════════════════════
  // TRADE REPUBLIC STYLE HELPER WIDGETS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildMinimalStat(String label, String value, bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
            fontWeight: FontWeight.w500)),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
            fontWeight: FontWeight.w700,
            color: isLight ? Colors.black : Colors.white)),
      ]);
  }

  Widget _buildScheduleOption(
    String title,
    String subtitle,
    bool isSelected,
    bool isLight,
    VoidCallback onTap) {
    return TradeRepublicTap(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14),
        margin: EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : (isLight ? Colors.black : Colors.white).withOpacity(0.04),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? (isLight ? Colors.white : Colors.black)
                          : (isLight ? Colors.black : Colors.white))),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected
                          ? (isLight ? Colors.white : Colors.black).withOpacity(
                              0.7)
                          : (isLight ? Colors.black : Colors.white).withOpacity(
                              0.5))),
                ])),
            if (isSelected)
              Icon(
                CupertinoIcons.check_mark_circled_solid,
                color: isLight ? Colors.white : Colors.black,
                size: 22),
          ])));
  }

  Widget _buildHistoryTab(
    String title,
    bool isSelected,
    bool isLight,
    VoidCallback onTap) {
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
                ]
              : []),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isLight ? Colors.white : Colors.black)
                : (isLight ? Colors.black : Colors.white).withOpacity(0.4),
            letterSpacing: -0.3),
          child: Text(title))));
  }

  Widget _buildEmptyState(String title, String subtitle, bool isLight) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.tray,
              size: 40,
              color: isLight ? Colors.black : Colors.white),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w600,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                letterSpacing: -0.3)),
            SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w400,
                color: (isLight ? Colors.black : Colors.white).withOpacity(
                  0.35))),
          ])));
  }

  Widget _buildHistoryItem(
    String title,
    String dateString,
    String amount,
    bool isEarning,
    bool isLight, {
    Map<String, dynamic>? itemData,
  }) {
    // Parse date
    String formattedDate = '';
    try {
      if (dateString.isNotEmpty) {
        final date = DateTime.parse(dateString);
        final appSettings = Provider.of<AppSettings>(context, listen: false);
        formattedDate = appSettings.formatDate(date);
      }
    } catch (e) {
      formattedDate = dateString;
    }

    final itemContent = Container(
      padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isEarning ? Colors.green : Colors.blue).withOpacity(0.1),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Icon(
              isEarning ? CupertinoIcons.arrow_down : CupertinoIcons.arrow_up,
              color: isEarning ? Colors.green : Colors.blue,
              size: 18)),
          SizedBox(width: 14),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.3)),
                if (formattedDate.isNotEmpty) ...[
                  SizedBox(height: 2),
                  Text(
                    formattedDate,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.4))),
                ],
              ])),
          // Amount
          Text(
            '${isEarning ? '+' : '-'}$amount',
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
              color: isEarning
                  ? Colors.green
                  : (isLight ? Colors.black : Colors.white),
              letterSpacing: -0.3)),
        ]));

    // Wrap with swipeable if we have item data
    if (itemData != null) {
      final itemId = itemData['id']?.toString() ?? AppLocalizations.of(context)!.tr('');
      return TradeRepublicSwipeAction(
        key: ValueKey('history_$itemId'),
        margin: EdgeInsets.only(bottom: 12),
        trailing: TradeRepublicSwipeSpec(
          icon: CupertinoIcons.arrow_down_circle_fill,
          label: AppLocalizations.of(context)?.download ?? 'Download',
          onActivate: () => _downloadPayoutInvoice(itemData, isLight)),
        child: itemContent);
    }

    return itemContent;
  }

  // Automatisches Speichern der Payout-Einstellungen
  Future<void> _savePayoutSchedule(String schedule) async {
    try {
      debugPrint('💾 Saving payout schedule: $schedule');

      // If instant payout is selected, trigger immediate payout
      if (schedule == 'instant') {
        await _processInstantPayout();
        return;
      }

      final token = await _getStoredToken();
      if (token == null) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.authRequired ?? AppLocalizations.of(context)!.tr('Authentication required'));
        return;
      }

      // Verwende den neuen Payout-Scheduler Endpoint
      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/business_groups/update-payout-schedule'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'schedule': schedule,
          'minimumAmount': 10.00, // Minimum 10${AppSettings().currencySymbol} for payout
        }));

      debugPrint('📡 Payout schedule response: ${response.statusCode}');
      debugPrint('📡 Payout schedule response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          // Also save in userData for local display
          final updatedData = {'payout_schedule': schedule};
          await _updateUserData(updatedData);

          // Show success notification with schedule details
          String scheduleText;
          String scheduleDetail;

          switch (schedule) {
            case 'instant':
              scheduleText =
                  AppLocalizations.of(context)?.instantPayout ?? AppLocalizations.of(context)!.tr('Instant payout');
              scheduleDetail =
                  AppLocalizations.of(
                    context)?.fundsTransferredImmediatelyFee ?? AppLocalizations.of(context)!.tr('Funds will be transferred immediately (tiered seller margin)');
              break;
            case 'daily':
              scheduleText =
                  AppLocalizations.of(context)?.dailyPayout ?? AppLocalizations.of(context)!.tr('Daily payout');
              scheduleDetail =
                  AppLocalizations.of(context)?.autoTransferDaily ?? AppLocalizations.of(context)!.tr('Automatic transfer every day at 9:00 AM (free)');
              break;
            case 'weekly':
              scheduleText =
                  AppLocalizations.of(context)?.weeklyPayout ?? AppLocalizations.of(context)!.tr('Weekly payout');
              scheduleDetail =
                  AppLocalizations.of(context)?.autoTransferWeekly ?? AppLocalizations.of(context)!.tr('Automatic transfer every Monday at 9:00 AM (free)');
              break;
            default:
              scheduleText =
                  AppLocalizations.of(context)?.payoutSchedule ?? AppLocalizations.of(context)!.tr('Payout schedule');
              scheduleDetail =
                  AppLocalizations.of(context)?.settingsUpdated ?? AppLocalizations.of(context)!.tr('Settings updated');
          }

          TopNotification.success(
            context,
            '$scheduleText ${AppLocalizations.of(context)?.activated ?? AppLocalizations.of(context)!.tr('activated!')}');
        } else {
          TopNotification.error(
            context,
            responseData['error'] ??
                (AppLocalizations.of(context)?.failedPayout ?? AppLocalizations.of(context)!.tr('Failed to update payout schedule')));
        }
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedPayout ?? AppLocalizations.of(context)!.tr('Failed to update payout schedule'));
      }
    } catch (e) {
      debugPrint('❌ Error saving payout schedule: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.failedToSavePayoutSchedule ?? AppLocalizations.of(context)!.tr('Failed to save payout schedule')}: $e');
    }
  }

  // Process instant payout
  Future<void> _processInstantPayout() async {
    try {
      debugPrint('⚡ Processing instant payout...');

      final token = await _getStoredToken();
      if (token == null) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.authRequired ?? AppLocalizations.of(context)!.tr('Authentication required'));
        return;
      }

      // Check if payment method is configured
      if (!BusinessAccountPage.hasConnectedPaymentSetup(userData)) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.addBankAccountFirst ?? AppLocalizations.of(context)!.tr('Please add a bank account first before requesting a payout'));
        return;
      }

      // Check if balance is available
      final availableBalance =
          (earningsData['availableBalance'] as num?)?.toDouble() ?? 0.0;
      if (availableBalance <= 0) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.noBalanceAvailable ?? AppLocalizations.of(context)!.tr('No balance available for payout'));
        return;
      }

      final marginRate = _sellerPayoutMarginRate(availableBalance);
      final instantFee = availableBalance * marginRate;
      final netAmount = availableBalance - instantFee;
      final marginPctLabel = _sellerPayoutMarginPercentLabel(availableBalance);

      // Show confirmation bottom sheet
      NavigationVisibility.hide();

      final confirmed = await TradeRepublicBottomSheet.show<bool>(
        context: context,
        bottomPadding: 20.0,
        child: Builder(
          builder: (context) {
            final AppSettings appSettings = Provider.of<AppSettings>(
              context,
              listen: false);
            final isLight = appSettings.isLightMode(context);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DragHandle(),

                // Content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Sheet header: Icon left + Title ──
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.money_dollar_circle_fill,
                          size: 22,
                          color: isLight ? Colors.black : Colors.white),
                        SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)?.instantPayout ?? AppLocalizations.of(context)!.tr('Instant Payout'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.4)),
                      ]),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    Text(
                      AppLocalizations.of(context)?.confirmPayoutDetailsDesc ?? AppLocalizations.of(context)!.tr('Confirm your payout details'),
                      style: TextStyle(
                        fontSize: 15,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),

                    SizedBox(height: 32),

                    // Payout details
                    Container(
                      padding: DesktopAppWrapper.getPagePadding(),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.04),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                      child: Column(
                        children: [
                          _buildPayoutDetailRow(
                            AppLocalizations.of(context)?.availableBalance ?? AppLocalizations.of(context)!.tr('Available Balance'),
                            _formatCurrency(availableBalance),
                            isLight),
                          SizedBox(height: 14),
                          _buildPayoutDetailRow(
                            AppLocalizations.of(context)?.instantFee ??
                                'Platform service fee ($marginPctLabel)',
                            '-${_formatCurrency(instantFee)}',
                            isLight,
                            isNegative: true),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: TradeRepublicDivider(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.08),
                              height: 1)),
                          _buildPayoutDetailRow(
                            AppLocalizations.of(context)?.youWillReceiveLabel ?? AppLocalizations.of(context)!.tr('You will receive'),
                            _formatCurrency(netAmount),
                            isLight,
                            isBold: true),
                        ])),

                    SizedBox(height: 20),

                    // Info text
                    Text(
                      AppLocalizations.of(
                            context)?.fundsTransferredImmediately ?? AppLocalizations.of(context)!.tr('Funds will be transferred to your bank account immediately.'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),

                    SizedBox(height: 32),

                    // Confirm button
                    TradeRepublicButton(
                      label:
                          AppLocalizations.of(context)?.confirmPayout ?? AppLocalizations.of(context)!.tr('Confirm Payout'),
                      icon: Icon(CupertinoIcons.bolt_fill, size: 20),
                      height: 50,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop(true);
                      }),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                    // Cancel button
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                      isSecondary: true,
                      height: 50,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop(false);
                      }),

                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 16),
                  ]),
              ]);
          })).whenComplete(() => NavigationVisibility.show());

      if (confirmed != true) {
        debugPrint('❌ Instant payout cancelled by user');
        return;
      }

      // Show processing bottom sheet
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      final isLightMode = appSettings.isLightMode(context);

      TradeRepublicBottomSheet.show(
        context: context,
        bottomPadding: 20.0,
        isDismissible: false,
        enableDrag: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),
            SizedBox(
              width: 24,
              height: 24,
              child: CultiooLoadingIndicator(size: 20)),
            SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)?.processingInstantPayoutMsg ?? AppLocalizations.of(context)!.tr('Processing instant payout...'),
              style: TextStyle(
                color: isLightMode ? Colors.black : Colors.white,
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w600)),
            SizedBox(height: 20),
          ]));

      // Call instant payout API
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/business/instant-payout'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

      // Close loading dialog
      if (mounted) _safePopIfPossible(context);

      debugPrint('📡 Instant payout response: ${response.statusCode}');
      debugPrint('📡 Instant payout response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          TopNotification.success(
            context,
            '✅ ${AppLocalizations.of(context)?.instantPayoutCompleted ?? AppLocalizations.of(context)!.tr('Instant payout completed!')} ${_formatCurrency(netAmount)} ${AppLocalizations.of(context)?.transferred ?? AppLocalizations.of(context)!.tr('transferred')}.');

          // Reload earnings data
          await _loadEarningsData();
          await _loadEarningsHistory();

          // Refresh UI
          if (mounted) setState(() {});
        } else {
          TopNotification.error(
            context,
            responseData['message'] ??
                (AppLocalizations.of(context)?.failedInstantPayout ?? AppLocalizations.of(context)!.tr('Failed to process instant payout')));
        }
      } else {
        final responseData = json.decode(response.body);
        TopNotification.error(
          context,
          responseData['message'] ??
              (AppLocalizations.of(context)?.failedInstantPayout ?? AppLocalizations.of(context)!.tr('Failed to process instant payout')));
      }
    } catch (e) {
      debugPrint('❌ Error processing instant payout: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.failedToProcessInstantPayout ?? AppLocalizations.of(context)!.tr('Failed to process instant payout')}: $e');
    }
  }

  // Waiting Charge Invoice / Rechnung
  void _showWaitingChargeInvoice(
    BuildContext context,
    bool isLight,
    Map<String, dynamic> charge) {
    final orderId = charge['order_id'] ?? AppLocalizations.of(context)!.tr('');
    final driverName =
        charge['driver_name'] ??
        charge['driver_username'] ??
        (AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown'));
    final driverUsername = charge['driver_username'] ?? AppLocalizations.of(context)!.tr('');
    final amount = (charge['amount'] ?? 0.0).toDouble();
    final waitingSec = ((charge['waiting_seconds'] ?? 0) as num).toInt();
    final totalMin = waitingSec > 0 ? (waitingSec / 60).ceil() : 0;
    final freeMin = charge['free_minutes'] ?? 15;
    final ratePerHour = (charge['rate_per_hour'] ?? 25.0).toDouble();
    final chargeableMin = (totalMin - freeMin).clamp(0, 999999);
    final checkIn = charge['check_in'] != null
        ? DateTime.tryParse(charge['check_in'].toString())
        : null;
    final checkOut = charge['check_out'] != null
        ? DateTime.tryParse(charge['check_out'].toString())
        : null;
    final waitingStart = charge['waiting_start'] != null
        ? DateTime.tryParse(charge['waiting_start'].toString())
        : null;
    final waitingEnd = charge['waiting_end'] != null
        ? DateTime.tryParse(charge['waiting_end'].toString())
        : null;
    final orderDate = charge['order_date'] != null
        ? DateTime.tryParse(charge['order_date'].toString())
        : null;

    String fmtTime(DateTime? dt) {
      if (dt == null) return '–';
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    String fmtDate(DateTime? dt) {
      if (dt == null) return '–';
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    }

    TradeRepublicBottomSheet.show(
      context: context,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Sheet header: Icon left + Title ──
                    Row(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 22,
                          color: isLight ? Colors.black : Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Wartekosten-Rechnung',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                              letterSpacing: -0.4))),
                      ]),
                    SizedBox(height: 6),
                    Text(
                      '${AppLocalizations.of(context)?.orderNumber ?? AppLocalizations.of(context)!.tr('Order #')}$orderId • ${fmtDate(orderDate)}',
                      style: TextStyle(
                        fontSize: 15,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),

                    SizedBox(height: 28),

                    // Big amount
                    Center(
                      child: Column(
                        children: [
                          Text(
                            '-${_formatCurrency(amount)}',
                            style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w700,
                              color: Colors.red.shade400,
                              letterSpacing: -2,
                              height: 1.1)),
                          SizedBox(height: 4),
                          Text(
                            AppLocalizations.of(
                                  context)?.deductionFromBalance ?? AppLocalizations.of(context)!.tr('Deduction from your balance'),
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.5))),
                        ])),

                    SizedBox(height: 32),

                    // Divider
                    const TradeRepublicDivider(),

                    SizedBox(height: 20),

                    // Driver Info Section
                    Text(
                      AppLocalizations.of(context)?.driverInformation ?? AppLocalizations.of(context)!.tr('Driver Information'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.3)),
                    SizedBox(height: 14),
                    _invoiceRow(
                      AppLocalizations.of(context)?.driverLabel ?? AppLocalizations.of(context)!.tr('Driver'),
                      driverName,
                      isLight),
                    if (driverUsername.isNotEmpty)
                      _invoiceRow(
                        AppLocalizations.of(context)?.usernameLabel ?? AppLocalizations.of(context)!.tr('Username'),
                        '@$driverUsername',
                        isLight),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    // Time Breakdown Section
                    Text(
                      AppLocalizations.of(context)?.timeBreakdown ?? AppLocalizations.of(context)!.tr('Time Breakdown'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.3)),
                    SizedBox(height: 14),
                    _invoiceRow(
                      AppLocalizations.of(context)?.waitingTimeStart ?? AppLocalizations.of(context)!.tr('Waiting Start'),
                      fmtTime(waitingStart),
                      isLight),
                    _invoiceRow(
                      AppLocalizations.of(context)?.waitingTimeEnd ?? AppLocalizations.of(context)!.tr('Waiting End'),
                      fmtTime(waitingEnd),
                      isLight),
                    _invoiceRow(
                      AppLocalizations.of(context)?.totalWaitingTime ?? AppLocalizations.of(context)!.tr('Total Waiting Time'),
                      '$totalMin Min',
                      isLight),
                    _invoiceRow(
                      AppLocalizations.of(context)?.freeMinutes ?? AppLocalizations.of(context)!.tr('Free Minutes'),
                      '$freeMin Min',
                      isLight),
                    _invoiceRow(
                      AppLocalizations.of(context)?.chargeableTime ?? AppLocalizations.of(context)!.tr('Chargeable Time'),
                      '$chargeableMin Min',
                      isLight,
                      highlight: true),

                    if (checkIn != null || checkOut != null) ...[
                      SizedBox(height: 14),
                      _invoiceRow('Check-In', fmtTime(checkIn), isLight),
                      _invoiceRow('Check-Out', fmtTime(checkOut), isLight),
                    ],

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    // Cost Calculation Section
                    Text(
                      AppLocalizations.of(context)?.costCalculation ?? AppLocalizations.of(context)!.tr('Cost Calculation'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.3)),
                    SizedBox(height: 14),
                    _invoiceRow(
                      AppLocalizations.of(context)?.hourlyRate ?? AppLocalizations.of(context)!.tr('Hourly Rate'),
                      '${_formatCurrency(ratePerHour)} ${AppLocalizations.of(context)?.perHourAbbr ?? AppLocalizations.of(context)!.tr('/ hr')}',
                      isLight),
                    _invoiceRow(
                      AppLocalizations.of(context)?.freeMinutes ?? AppLocalizations.of(context)!.tr('Free Minutes'),
                      '$freeMin ${AppLocalizations.of(context)?.minutesFree ?? AppLocalizations.of(context)!.tr('Min (free)')}',
                      isLight),
                    _invoiceRow(
                      AppLocalizations.of(context)?.calculatedTime ?? AppLocalizations.of(context)!.tr('Calculated Time'),
                      '$chargeableMin Min',
                      isLight),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    const TradeRepublicDivider(),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.totalAmount ?? AppLocalizations.of(context)!.tr('Total Amount'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white)),
                        Text(
                          '-${_formatCurrency(amount)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.red.shade400,
                            letterSpacing: -0.5)),
                      ]),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    // Info note
                    Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.04),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.4)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (AppLocalizations.of(
                                        context)?.waitingCostInfoBusiness ?? AppLocalizations.of(context)!.tr('Waiting costs apply when the driver has to wait longer than {0} minutes at pickup. The hourly rate is {1}.'))
                                  .replaceAll('{0}', '$freeMin')
                                  .replaceAll(
                                    '{1}',
                                    _formatCurrency(ratePerHour)),
                              style: TextStyle(
                                fontSize: 13,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.5),
                                height: 1.4))),
                        ])),

                    SizedBox(height: 40),
                  ]))),
          ])));
  }

  // Helper: Invoice row
  Widget _invoiceRow(
    String label,
    String value,
    bool isLight, {
    bool highlight = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6))),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              color: highlight
                  ? Colors.red.shade400
                  : (isLight ? Colors.black : Colors.white))),
        ]));
  }

  // Manual Payout Modal — tiered seller margin (same as instant payout)
  void _showManualPayoutModal(BuildContext context, bool isLight) {
    final availableBalance = _getDisplayableBalance(
      earningsData['availableBalance']);
    final marginPctLabel = _sellerPayoutMarginPercentLabel(availableBalance);
    final fee = availableBalance * _sellerPayoutMarginRate(availableBalance);
    final netAmount = availableBalance - fee;

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          const DragHandle(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Sheet header: Icon left + Title ──
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.money_dollar_circle_fill,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white),
                    SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.manualPayout ?? AppLocalizations.of(context)!.tr('Manual Payout'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4)),
                  ]),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                Text(
                  AppLocalizations.of(context)?.withdrawYourBalance ?? AppLocalizations.of(context)!.tr('Withdraw your available balance now'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5))),

                SizedBox(height: 32),

                // Amount Card
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Column(
                    children: [
                      // Available Balance
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.availableBalance ?? AppLocalizations.of(context)!.tr('Available Balance'),
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w500,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.6))),
                          Text(
                            _formatCurrency(availableBalance),
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white)),
                        ]),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                      TradeRepublicDivider(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.1)),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                      // Fee
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.processingFee ??
                                'Platform service fee ($marginPctLabel)',
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w500,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.6))),
                          Text(
                            '-${_formatCurrency(fee)}',
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w600,
                              color: Colors.red.withOpacity(0.8))),
                        ]),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                      TradeRepublicDivider(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.1)),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                      // Net Amount
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.youWillReceiveLabel ?? AppLocalizations.of(context)!.tr('You will receive'),
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white)),
                          Text(
                            _formatCurrency(netAmount),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.green)),
                        ]),
                    ])),

                const Spacer(),

                // Info Text
                Container(
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.info_circle,
                        color: Colors.blue,
                        size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(
                                context)?.fundsTransferred1to3Days ?? AppLocalizations.of(context)!.tr('Funds will be transferred to your bank account within 1-3 business days.'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.blue))),
                    ])),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Payout Button
                TradeRepublicButton(
                  label: availableBalance >= 10
                      ? 'Withdraw ${_formatCurrency(netAmount)}'
                      : 'Minimum ${_formatCurrency(10.00)} required',
                  height: 50,
                  onPressed: availableBalance >= 10
                      ? () {
                          Navigator.pop(context);
                          _processInstantPayout();
                        }
                      : null),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
              ])),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  Widget _buildPayoutDetailRow(
    String label,
    String value,
    bool isLight, {
    bool isNegative = false,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 18 : 16,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: (isLight ? Colors.black : Colors.white).withOpacity(
              isBold ? 1.0 : 0.7))),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 20 : 16,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            color: isNegative
                ? Colors.red
                : (isBold
                      ? Colors.green
                      : (isLight ? Colors.black : Colors.white)))),
      ]);
  }

  Widget _buildPayoutOption(
    String title,
    String subtitle,
    String fee,
    IconData icon,
    Color color,
    bool isSelected,
    bool isLight,
    VoidCallback onTap) {
    return TradeRepublicTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: isSelected
              ? color
              : isLight
              ? Colors.white
              : Colors.black,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : (isLight ? Colors.black : Colors.white),
                          letterSpacing: -0.3)),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withOpacity(0.25)
                              : (fee == 'Free'
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.orange.withOpacity(0.15)),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                        child: Text(
                          fee,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : (fee == 'Free'
                                      ? Colors.green.shade700
                                      : Colors.orange.shade700),
                            letterSpacing: 0.3))),
                    ]),
                  SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.white.withOpacity(0.9)
                          : (isLight ? Colors.black : Colors.white).withOpacity(
                              0.6))),
                ])),
            SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? Colors.white
                    : (isLight ? Colors.black : Colors.white).withOpacity(0.1)),
              child: isSelected
                  ? Icon(CupertinoIcons.checkmark, size: 16, color: color)
                  : null),
          ])));
  }

  Widget _buildPaymentMethodsList(bool isLight) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadSavedPaymentMethods(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CultiooLoadingIndicator());
        }

        final paymentMethods = snapshot.data ?? [];

        if (paymentMethods.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.05),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Icon(
                    CupertinoIcons.creditcard,
                    size: 40,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.3))),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                Text(
                  AppLocalizations.of(context)?.noBankAccounts ?? AppLocalizations.of(context)!.tr('No Bank Accounts'),
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white)),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                Text(
                  AppLocalizations.of(context)?.addBankAccountDesc ?? AppLocalizations.of(context)!.tr('Add a bank account to receive your earnings'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.6))),
                SizedBox(height: 32),
                TradeRepublicButton(
                  label:
                      AppLocalizations.of(context)?.addBankAccount ?? AppLocalizations.of(context)!.tr('Add Bank Account'),
                  height: 50,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    _checkAndShowAddPaymentMethod(context, isLight);
                  }),
              ]));
        }

        return ListView.builder(
          itemCount: paymentMethods.length,
          itemBuilder: (context, index) {
            final method = paymentMethods[index];
            return TradeRepublicSwipeAction(
              key: ValueKey('paymethod_${method['id']}'),
              margin: EdgeInsets.only(bottom: 12),
              trailing: TradeRepublicSwipeSpec(
                icon: CupertinoIcons.delete_solid,
                label: AppLocalizations.of(context)?.delete ?? 'Delete',
                backgroundColor: const Color(0xFFFF3B30),
                foregroundColor: Colors.white,
                onActivate: () => _deletePaymentMethod(method['id'], isLight)),
              child: _buildPaymentMethodCard(method, isLight));
          });
      });
  }

  Widget _buildPaymentMethodCard(Map<String, dynamic> method, bool isLight) {
    final methodType = (method['type'] ?? '').toString().toLowerCase();
    final isCard = methodType == 'card';
    final isSepa = methodType == 'sepa' || methodType == 'sepa_debit';
    final isWire = methodType == 'wire';
    final holder = (method['account_holder_name'] ?? '').toString().trim();
    final last4 = (method['last4'] ?? '').toString();
    final isDefault = method['is_default'] == true || method['isDefault'] == true;

    if (isCard) {
      final brand = (method['brand'] ?? method['card']?['brand'] ?? 'card').toString();
      final expM = (method['exp_month'] ?? method['card']?['exp_month'] ?? '').toString();
      final expY = (method['exp_year'] ?? method['card']?['exp_year'] ?? '').toString();
      return Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: CreditCardWidget(
          brand: brand,
          last4: last4.isEmpty ? (method['card']?['last4'] ?? '????').toString() : last4,
          expMonth: expM,
          expYear: expY,
          cardholderName: holder,
          isDefault: isDefault));
    }

    final bankLast4 = last4.isNotEmpty
        ? last4
        : (method['iban_last4'] ?? method['account_number_last4'] ?? '????').toString();
    final routing = isWire
        ? (method['swift_bic'] ?? method['routing_number'])?.toString()
        : method['routing_number']?.toString();
    final accountType = isSepa ? 'sepa' : isWire ? 'wire' : 'ach';

    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: BankAccountWidget(
        type: accountType,
        maskedNumber: bankLast4,
        accountHolderName: holder,
        routingOrSwift: routing,
        isDefault: isDefault));
  }

  /// Detects the US bank name from a 9-digit ABA routing number.
  String _detectBankFromRoutingNumber(String routing) {
    if (routing.length < 4) return '';

    // Map of routing number prefixes → bank names (top US banks)
    const Map<String, String> routingMap = {
      // JPMorgan Chase
      '021000021': 'JPMorgan Chase',
      '322271627': 'JPMorgan Chase',
      '021202337': 'JPMorgan Chase',
      // Bank of America
      '026009593': 'Bank of America',
      '121000358': 'Bank of America',
      '081904808': 'Bank of America',
      // Wells Fargo
      '121042882': 'Wells Fargo',
      '091000019': 'Wells Fargo',
      '121000248': 'Wells Fargo',
      // Citibank
      '021000089': 'Citibank',
      '321171184': 'Citibank',
      '031100209': 'Citibank',
      // US Bank
      '091000022': 'U.S. Bank',
      '123000220': 'U.S. Bank',
      '081000210': 'U.S. Bank',
      // Capital One
      '051405515': 'Capital One',
      '056073502': 'Capital One',
      // PNC Bank
      '043000096': 'PNC Bank',
      '031207607': 'PNC Bank',
      '041000124': 'PNC Bank',
      // TD Bank
      '031101266': 'TD Bank',
      '011103093': 'TD Bank',
      // Goldman Sachs (Marcus)
      '124085244': 'Goldman Sachs',
      // Ally Bank
      '124003116': 'Ally Bank',
      // Charles Schwab
      '121202211': 'Charles Schwab',
      // American Express
      '124071889': 'American Express Bank',
      // Discover Bank
      '031100157': 'Discover Bank',
      // USAA
      '314074269': 'USAA',
      // Navy Federal
      '256074974': 'Navy Federal Credit Union',
      // Truist (BB&T/SunTrust)
      '061000104': 'Truist Bank',
      '053101121': 'Truist Bank',
    };

    // Exact match
    if (routingMap.containsKey(routing)) return routingMap[routing]!;

    // Prefix-based detection for major banks
    if (routing.startsWith('0210000') || routing.startsWith('3222716')) {
      return 'JPMorgan Chase';
    }
    if (routing.startsWith('0260095') || routing.startsWith('1210003')) {
      return 'Bank of America';
    }
    if (routing.startsWith('1210428') || routing.startsWith('0910000')) {
      return 'Wells Fargo';
    }
    if (routing.startsWith('0210000') || routing.startsWith('3211711')) {
      return 'Citibank';
    }
    if (routing.startsWith('0430000') || routing.startsWith('0312076')) {
      return 'PNC Bank';
    }
    if (routing.startsWith('0510000') || routing.startsWith('0560735')) {
      return 'Capital One';
    }
    if (routing.startsWith('3140742')) return 'USAA';
    if (routing.startsWith('2560749')) return 'Navy Federal Credit Union';

    return '';
  }

  Future<List<Map<String, dynamic>>> _loadSavedPaymentMethods() async {
    try {
      final token = await _getStoredToken();
      final username = (userData?['username'] ?? AppLocalizations.of(context)!.tr('')).toString().trim();

      if (token != null) {
        final endpoints = <String>[
          '/api/business/payment-methods',
          if (username.isNotEmpty)
            '/api/business/payment-methods?username=${Uri.encodeComponent(username)}',
        ];

        for (final endpoint in endpoints) {
          final response = await http.get(
            Uri.parse('${ApiConfig.baseUrl}$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            });

          if (response.statusCode != 200) continue;

          final data = json.decode(response.body);
          final rawMethods = (data['methods'] as List?) ?? const [];
          final mapped = rawMethods
              .whereType<Map>()
              .map<Map<String, dynamic>>(
                (raw) => {
                  'id': (raw['id'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                  'type': (raw['type'] ?? AppLocalizations.of(context)!.tr('')).toString().toLowerCase(),
                  'bank_name': (raw['bank_name'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                  'account_holder_name': (raw['account_holder_name'] ?? AppLocalizations.of(context)!.tr(''))
                      .toString(),
                  'account_number': (raw['account_number'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                  'iban': (raw['iban'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                  'bic': (raw['bic'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                  'brand': (raw['brand'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                  'last4': (raw['last4'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                  'label': (raw['label'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                  'detail': (raw['detail'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                })
              .where((m) => m['id']!.toString().isNotEmpty)
              .toList();

          if (mapped.isNotEmpty) {
            return mapped;
          }
        }
      }

      // Fallback: legacy local fields (older accounts)
      final List<Map<String, dynamic>> fallbackMethods = [];
      final paymentSystem = userData?['payment_system'] ?? AppLocalizations.of(context)!.tr('');
      final isUSA = paymentSystem == 'USA';
      final hasUsBankData =
          isUSA &&
          (userData?['routing_number'] ?? AppLocalizations.of(context)!.tr('')).toString().trim().isNotEmpty &&
          (userData?['account_number'] ?? AppLocalizations.of(context)!.tr('')).toString().trim().isNotEmpty;
      final hasSepaData =
          !isUSA && (userData?['iban'] ?? AppLocalizations.of(context)!.tr('')).toString().trim().isNotEmpty;

      if (hasUsBankData) {
        fallbackMethods.add({
          'id': 'legacy_ach',
          'type': 'us_bank_account',
          'bank_name':
              userData?['bank_name'] ??
              (AppLocalizations.of(context)?.usBankAccount ?? AppLocalizations.of(context)!.tr('')),
          'routing_number': userData?['routing_number'] ?? AppLocalizations.of(context)!.tr(''),
          'account_number': userData?['account_number'] ?? AppLocalizations.of(context)!.tr(''),
          'last4': (userData?['account_number'] ?? AppLocalizations.of(context)!.tr('')).toString().length > 4
              ? (userData?['account_number'] ?? AppLocalizations.of(context)!.tr('')).toString().substring(
                  (userData?['account_number'] ?? AppLocalizations.of(context)!.tr('')).toString().length - 4)
              : '',
          'account_holder_name':
              userData?['account_holder_name'] ??
              userData?['businessName'] ??
              (AppLocalizations.of(context)?.businessAccount ?? AppLocalizations.of(context)!.tr('Business Account')),
        });
      } else if (hasSepaData) {
        fallbackMethods.add({
          'id': 'legacy_sepa',
          'type': 'sepa_debit',
          'bank_name':
              userData?['bank_name'] ??
              (AppLocalizations.of(context)?.sepaAccount ?? AppLocalizations.of(context)!.tr('')),
          'iban': userData?['iban'] ?? AppLocalizations.of(context)!.tr(''),
          'bic': userData?['bic'] ?? AppLocalizations.of(context)!.tr(''),
          'last4': (userData?['iban'] ?? AppLocalizations.of(context)!.tr('')).toString().length > 4
              ? (userData?['iban'] ?? AppLocalizations.of(context)!.tr('')).toString().substring(
                  (userData?['iban'] ?? AppLocalizations.of(context)!.tr('')).toString().length - 4)
              : '',
          'account_holder_name':
              userData?['account_holder_name'] ??
              userData?['businessName'] ??
              (AppLocalizations.of(context)?.businessAccount ?? AppLocalizations.of(context)!.tr('Business Account')),
        });
      }

      return fallbackMethods;
    } catch (e) {
      debugPrint('Error loading payment methods: $e');
      return [];
    }
  }

  void _showAddPaymentMethodModal(BuildContext context, bool isLight, {bool hasBankMethod = false}) {
    // Payment method type state
    String paymentMethodType = 'bank_account'; // 'bank_account' or 'card'
    
    // Payment system state
    bool isUSASystem =
        userData?['payment_system'] == 'USA' ||
        userData?['payment_system'] == null;

    // USA system controllers
    final accountHolderNameController = TextEditingController(
      text: userData?['account_holder_name'] ?? AppLocalizations.of(context)!.tr(''));
    final routingNumberController = TextEditingController(
      text: userData?['routing_number'] ?? AppLocalizations.of(context)!.tr(''));
    final accountNumberController = TextEditingController(
      text: userData?['account_number'] ?? AppLocalizations.of(context)!.tr(''));

    // SEPA system controllers
    final ibanController = TextEditingController(text: userData?['iban'] ?? AppLocalizations.of(context)!.tr(''));
    final bicController = TextEditingController(text: userData?['bic'] ?? AppLocalizations.of(context)!.tr(''));
    final bankNameController = TextEditingController(
      text: userData?['bank_name'] ?? AppLocalizations.of(context)!.tr(''));
    
    // Card controllers
    final cardNumberController = TextEditingController();
    final cardExpiryController = TextEditingController();
    final cardCvcController = TextEditingController();
    final cardHolderNameController = TextEditingController(
      text: userData?['account_holder_name'] ?? AppLocalizations.of(context)!.tr(''));
    
    // Track values we autofilled so we don't overwrite manual edits.
    String lastAutofilledBankName = bankNameController.text;
    String lastAutofilledBic = bicController.text;
    final pageContext = _scaffoldKey.currentContext ?? this.context;

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.9,
      child: StatefulBuilder(
        builder: (context, setModalState) => Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DragHandle(),
                // Title and subtitle
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Sheet header: Icon left + Title ──
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.creditcard_fill,
                          size: 22,
                          color: isLight ? Colors.black : Colors.white),
                        SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)?.paymentSettings ?? AppLocalizations.of(context)!.tr('Payment Settings'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.4)),
                      ]),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                    Text(
                      AppLocalizations.of(context)?.addBankAccountForPayouts ?? AppLocalizations.of(context)!.tr('Add or update your payout bank account'),
                      style: TextStyle(
                        fontSize: 15,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),
                    SizedBox(height: 10),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.06),
                        borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.lock_shield,
                            size: 14,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.75)),
                          SizedBox(width: 8),
                          Text(
                            'Encrypted via Stripe',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.78))),
                        ])),
                  ]),
                SizedBox(height: 32),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section header: Bank Account (mandatory for payouts) - only if no bank exists yet
                        if (!hasBankMethod) ...[
                          Container(
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.04),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)?.bankingSystem ?? 'Banking System',
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        fontWeight: FontWeight.w600,
                                        color: isLight ? Colors.black : Colors.white)),
                                    SizedBox(width: 8),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6)),
                                      child: Text(
                                        'Required for payouts',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange))),
                                  ]),
                                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                                // ACH/SEPA Toggle
                                TradeRepublicSlider(
                                  labels: const ['ACH', 'SEPA'],
                                  selectedIndex: isUSASystem ? 0 : 1,
                                  segmentWidth: 140,
                                  onChanged: (index) {
                                    setModalState(() {
                                      isUSASystem = (index == 0);
                                    });
                                  }),
                              ])),
                        ],

                        SizedBox(height: 20),

                        // Bank Account Information (only shown if no bank exists - max 1 bank account)
                        Container(
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.04),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(
                                        context)?.bankAccountDetails ?? AppLocalizations.of(context)!.tr('Bank Account Details'),
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? Colors.black : Colors.white)),
                                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                                // USA System Fields
                                if (isUSASystem) ...[
                                  _buildPaymentField(
                                    AppLocalizations.of(
                                          context)?.accountHolderName ?? AppLocalizations.of(context)!.tr('Account Holder Name'),
                                    AppLocalizations.of(
                                          context)?.fullNameOnAccount ?? AppLocalizations.of(context)!.tr('Full name on the account'),
                                    accountHolderNameController,
                                    CupertinoIcons.person_fill,
                                    isLight),
                                  _buildPaymentField(
                                    AppLocalizations.of(context)?.routingNumber ?? AppLocalizations.of(context)!.tr('Routing Number'),
                                    '9-digit routing number',
                                    routingNumberController,
                                    CupertinoIcons.map,
                                    isLight,
                                    keyboardType: TextInputType.number,
                                    onBankDetected: (bankName) {
                                      final current = bankNameController.text.trim();
                                      if (current.isEmpty ||
                                          current == lastAutofilledBankName) {
                                        setModalState(() {
                                          bankNameController.text = bankName;
                                      });
                                      lastAutofilledBankName = bankName;
                                    }
                                  }),
                                _buildPaymentField(
                                  AppLocalizations.of(context)?.accountNumber ?? AppLocalizations.of(context)!.tr('Account Number'),
                                  AppLocalizations.of(context)?.accountNumber ?? AppLocalizations.of(context)!.tr('Bank account number'),
                                  accountNumberController,
                                  CupertinoIcons.creditcard,
                                  isLight,
                                  keyboardType: TextInputType.number),
                              ],

                              // SEPA System Fields
                              if (!isUSASystem) ...[
                                _buildPaymentField(
                                  AppLocalizations.of(
                                        context)?.accountHolderName ?? AppLocalizations.of(context)!.tr('Account Holder Name'),
                                  AppLocalizations.of(
                                        context)?.fullNameOnAccount ?? AppLocalizations.of(context)!.tr('Full name on the account'),
                                  accountHolderNameController,
                                  CupertinoIcons.person_fill,
                                  isLight),
                                _buildPaymentField(
                                  'IBAN',
                                  'DE89 3704 0044 0532 0130 00',
                                  ibanController,
                                  CupertinoIcons.building_2_fill,
                                  isLight,
                                  onBankDetected: (bankName) {
                                    // Only autofill if the field is empty or
                                    // still contains a previously auto-filled
                                    // value — never overwrite manual edits.
                                    final current = bankNameController.text.trim();
                                    if (current.isEmpty ||
                                        current == lastAutofilledBankName) {
                                      setModalState(() {
                                        bankNameController.text = bankName;
                                      });
                                      lastAutofilledBankName = bankName;
                                    }
                                  },
                                  onBicDetected: (bic) {
                                    final current = bicController.text.trim();
                                    if (current.isEmpty ||
                                        current == lastAutofilledBic) {
                                      setModalState(() {
                                        bicController.text = bic;
                                      });
                                      lastAutofilledBic = bic;
                                    }
                                  }),
                                _buildPaymentField(
                                  'BIC/SWIFT Code',
                                  'COBADEFFXXX (8-11 characters)',
                                  bicController,
                                  CupertinoIcons
                                      .chevron_left_slash_chevron_right,
                                  isLight),
                                _buildPaymentField(
                                  AppLocalizations.of(context)?.bankName ?? AppLocalizations.of(context)!.tr('Bank Name'),
                                  AppLocalizations.of(
                                        context)?.nameOfYourBank ?? AppLocalizations.of(context)!.tr('Name of your bank'),
                                  bankNameController,
                                  CupertinoIcons.building_2_fill,
                                  isLight),
                              ],
                            ])),

                        SizedBox(height: 20),

                        // Card Information (also shown - for shipping payments)
                        Container(
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.04),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Card Details',
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    fontWeight: FontWeight.w600,
                                    color: isLight ? Colors.black : Colors.white)),
                                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                                _buildPaymentField(
                                  'Card Number',
                                  '1234 5678 9012 3456',
                                  cardNumberController,
                                  CupertinoIcons.creditcard,
                                  isLight,
                                  keyboardType: TextInputType.number),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildPaymentField(
                                        'Expiry Date',
                                        'MM/YY',
                                        cardExpiryController,
                                        CupertinoIcons.calendar,
                                        isLight,
                                        keyboardType: TextInputType.number)),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: _buildPaymentField(
                                        'CVC',
                                        '123',
                                        cardCvcController,
                                        CupertinoIcons.lock_fill,
                                        isLight,
                                        keyboardType: TextInputType.number)),
                                  ]),
                                _buildPaymentField(
                                  'Cardholder Name',
                                  'Name on card',
                                  cardHolderNameController,
                                  CupertinoIcons.person_fill,
                                  isLight),
                              ])),

                        SizedBox(height: 20),

                        // Stripe Connection Status
                        if (BusinessAccountPage.hasConnectedPaymentSetup(
                          userData)) ...[
                          Container(
                            padding: EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemGreen.withValues(
                                alpha: 0.1),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons.checkmark_circle_fill,
                                  color: CupertinoColors.systemGreen,
                                  size: 20),
                                SizedBox(width: 12),
                                Text(
                                  AppLocalizations.of(
                                        context)?.connectedToStripe ?? AppLocalizations.of(context)!.tr('Connected to Stripe'),
                                  style: TextStyle(
                                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                                    color: CupertinoColors.systemGreen,
                                    fontWeight: FontWeight.w600)),
                              ])),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        ],

                        // Security Notice
                        Text(
                          AppLocalizations.of(context)?.bankInfoEncrypted ?? AppLocalizations.of(context)!.tr('Your banking information is encrypted and securely processed via Stripe.'),
                          style: TextStyle(
                            fontSize: 13,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.4))),

                        SizedBox(height: 120),
                      ]))),
              ]),

            // Save Button
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 24,
              right: 24,
              child: TradeRepublicButton(
                label:
                    AppLocalizations.of(context)?.savePaymentSettings ?? AppLocalizations.of(context)!.tr('Save Payment Settings'),
                height: 50,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _savePaymentSettings(
                    pageContext,
                    paymentMethodType,
                    isUSASystem,
                    accountHolderNameController,
                    routingNumberController,
                    accountNumberController,
                    ibanController,
                    bicController,
                    bankNameController,
                    cardNumberController,
                    cardExpiryController,
                    cardCvcController,
                    cardHolderNameController);
                })),
          ]))).whenComplete(() => NavigationVisibility.show());
  }

  Widget _buildPaymentField(
    String label,
    String hint,
    TextEditingController controller,
    IconData icon,
    bool isLight, {
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onBankDetected,
    Function(String)? onBicDetected,
  }) {
    // Determine input formatters based on the label
    List<TextInputFormatter>? inputFormatters;
    final lowerLabel = label.toLowerCase();
    if (lowerLabel.contains('iban')) {
      inputFormatters = [
        IbanInputFormatter(
          onBankDetected: onBankDetected,
          onBicDetected: onBicDetected),
      ];
    } else if (lowerLabel.contains('bic') ||
        lowerLabel.contains('swift')) {
      inputFormatters = [BicInputFormatter()];
    } else if (lowerLabel.contains('routing')) {
      inputFormatters = [
        RoutingNumberInputFormatter(
          onBankDetected: onBankDetected != null
              ? (routing) {
                  final detected = _detectBankFromRoutingNumber(routing);
                  if (detected.isNotEmpty) onBankDetected(detected);
                }
              : null),
      ];
    } else if (lowerLabel.contains('card number')) {
      inputFormatters = [CardNumberInputFormatter()];
    } else if (lowerLabel.contains('expiry') || lowerLabel.contains('exp')) {
      inputFormatters = [CardExpiryInputFormatter()];
    } else if (lowerLabel.contains('cvc')) {
      inputFormatters = [CardCvcInputFormatter()];
    }

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.7))),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          TradeRepublicTextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              color: isLight ? Colors.black : Colors.white),
            hintText: hint,
            filled: true,
            fillColor: (isLight ? Colors.black : Colors.white).withOpacity(
              0.04)),
        ]));
  }

  Future<void> _savePaymentSettings(
    BuildContext modalContext,
    String paymentMethodType,
    bool isUSASystem,
    TextEditingController accountHolderNameController,
    TextEditingController routingNumberController,
    TextEditingController accountNumberController,
    TextEditingController ibanController,
    TextEditingController bicController,
    TextEditingController bankNameController,
    TextEditingController cardNumberController,
    TextEditingController cardExpiryController,
    TextEditingController cardCvcController,
    TextEditingController cardHolderNameController) async {
    final uiContext = _scaffoldKey.currentContext ?? context;

    // Load ALL localized strings at the very beginning, before ANY async operations
    final loc = AppLocalizations.of(uiContext);
    final accountHolderRequiredMsg =
        loc?.accountHolderRequired ?? AppLocalizations.of(context)!.tr('Account holder name is required');
    final routingNumberRequiredMsg =
        loc?.routingNumberRequired ?? AppLocalizations.of(context)!.tr('Routing number is required');
    final accountNumberRequiredMsg =
        loc?.accountNumberRequired ?? AppLocalizations.of(context)!.tr('Account number is required');
    final routingNumber9DigitsMsg =
        loc?.routingNumber9Digits ?? AppLocalizations.of(context)!.tr('Routing number must be 9 digits');
    final ibanRequiredMsg = loc?.ibanRequired ?? AppLocalizations.of(context)!.tr('IBAN is required');
    final bicRequiredMsg = loc?.bicRequired ?? AppLocalizations.of(context)!.tr('BIC/SWIFT code is required');
    final bankNameRequiredMsg =
        loc?.bankNameRequired ?? AppLocalizations.of(context)!.tr('Bank name is required');
    final invalidIbanFormatMsg =
        loc?.invalidIbanFormat ?? AppLocalizations.of(context)!.tr('Invalid IBAN format');
    final cardNumberRequiredMsg =
        'Card number is required';
    final cardExpiryRequiredMsg =
        'Expiry date is required';
    final cardCvcRequiredMsg =
        'CVC is required';
    final cardHolderRequiredMsg =
        'Cardholder name is required';
    final connectingMsg =
        loc?.connectingStripe ?? AppLocalizations.of(context)!.tr('Connecting to Stripe and saving payment details...');
    final stripeSuccessMsg =
        loc?.stripeSuccess ?? AppLocalizations.of(context)!.tr('Stripe integration successful!');
    final paymentSavedMsg =
        loc?.paymentSettingsSaved ?? AppLocalizations.of(context)!.tr('Payment settings saved to Stripe successfully!');
    final stripeFailedMsg =
        loc?.stripeIntegrationFailed ?? AppLocalizations.of(context)!.tr('Stripe integration failed');
    final failedToSaveMsg =
        loc?.failedToSavePaymentSettings ?? AppLocalizations.of(context)!.tr('Failed to save payment settings');

    try {
      // Check if card data was entered
      final cardNumber = cardNumberController.text.trim().replaceAll(' ', '');
      final cardExpiry = cardExpiryController.text.trim();
      final cardCvc = cardCvcController.text.trim();
      final cardHolderName = cardHolderNameController.text.trim();
      final hasCardData = cardNumber.isNotEmpty || cardExpiry.isNotEmpty || cardCvc.isNotEmpty || cardHolderName.isNotEmpty;

      // If card data is entered, save card AND bank account together
      if (hasCardData) {
        final cardNumber = cardNumberController.text.trim().replaceAll(' ', '');
        final cardExpiry = cardExpiryController.text.trim();
        final cardCvc = cardCvcController.text.trim();
        final cardHolderName = cardHolderNameController.text.trim();

        if (cardNumber.isEmpty) {
          TopNotification.error(uiContext, cardNumberRequiredMsg);
          return;
        }
        if (cardExpiry.isEmpty) {
          TopNotification.error(uiContext, cardExpiryRequiredMsg);
          return;
        }
        if (cardCvc.isEmpty) {
          TopNotification.error(uiContext, cardCvcRequiredMsg);
          return;
        }
        if (cardHolderName.isEmpty) {
          TopNotification.error(uiContext, cardHolderRequiredMsg);
          return;
        }

        // Parse expiry date (MM/YY format)
        final expiryParts = cardExpiry.split('/');
        if (expiryParts.length != 2) {
          TopNotification.error(uiContext, 'Invalid expiry date format. Use MM/YY');
          return;
        }

        final expMonth = int.tryParse(expiryParts[0]);
        final expYear = int.tryParse('20${expiryParts[1]}');

        if (expMonth == null || expYear == null || expMonth < 1 || expMonth > 12) {
          TopNotification.error(uiContext, 'Invalid expiry date');
          return;
        }

        Map<String, dynamic> paymentData = {
          'type': 'card',
          'card_number': cardNumber,
          'exp_month': expMonth,
          'exp_year': expYear,
          'cvc': cardCvc,
          'cardholder_name': cardHolderName,
        };

        // Close modal first
        if (mounted && Navigator.of(modalContext).canPop()) {
          Navigator.pop(modalContext);
        }

        // Show loading
        if (mounted) {
          TopNotification.info(uiContext, connectingMsg);
        }

        // Create Stripe customer and save card payment method
        final stripeResult = await _createStripeCustomerAndPaymentMethod(
          paymentData,
          userData?['email'] ?? AppLocalizations.of(context)!.tr(''),
          userData?['businessName'] ?? AppLocalizations.of(context)!.tr(''));

        if (stripeResult['success'] == true) {
          // Add Stripe customer ID to payment data
          paymentData['stripe_customer_id'] = stripeResult['customer_id'];
          paymentData['stripe_payment_method_id'] = stripeResult['payment_method_id'];

          debugPrint('✅ Stripe customer created: ${stripeResult['customer_id']}');
          debugPrint('✅ $stripeSuccessMsg');

          // Note: payment data already saved to DB by the stripe endpoint - no need to call _updateUserData

          // Update verification status for card
          await _updateVerificationStatus('card', {
            'stripeCustomerId': stripeResult['customer_id'],
          });

          // Reload user data
          await _loadUserData();

          // Refresh payment methods
          await _refreshPaymentSetupStatus();

          // Show success message
          if (mounted) {
            TopNotification.success(uiContext, paymentSavedMsg);
          }
        } else {
          if (mounted) {
            TopNotification.error(uiContext, stripeFailedMsg);
          }
        }

        return;
      }

      // Validate required fields for bank account
      final accountHolderName = accountHolderNameController.text.trim();
      if (accountHolderName.isEmpty) {
        TopNotification.error(uiContext, accountHolderRequiredMsg);
        return;
      }

      Map<String, dynamic> paymentData = {
        'payment_system': isUSASystem ? 'USA' : 'SEPA',
        'account_holder_name': accountHolderName,
      };

      if (isUSASystem) {
        // USA system validation
        final routingNumber = routingNumberController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
        final accountNumber = accountNumberController.text.trim();

        if (routingNumber.isEmpty) {
          TopNotification.error(uiContext, routingNumberRequiredMsg);
          return;
        }
        if (accountNumber.isEmpty) {
          TopNotification.error(uiContext, accountNumberRequiredMsg);
          return;
        }
        if (routingNumber.length != 9) {
          TopNotification.error(uiContext, routingNumber9DigitsMsg);
          return;
        }
        // ABA checksum validation disabled to allow more routing numbers
        // if (!_isValidABARoutingNumber(routingNumber)) {
        //   TopNotification.error(
        //     uiContext,
        //     'Invalid routing number. Please check the 9-digit ABA routing number on your check.',
        //   );
        //   return;
        // }

        debugPrint('📋 Routing number OK, sending to Stripe...');
        paymentData.addAll({
          'routing_number': routingNumber,
          'account_number': accountNumber,
        });
      } else {
        // SEPA system validation
        final iban = ibanController.text.trim().replaceAll(' ', '');
        final bic = bicController.text.trim();
        final bankName = bankNameController.text.trim();

        if (iban.isEmpty) {
          TopNotification.error(uiContext, ibanRequiredMsg);
          return;
        }
        if (bic.isEmpty) {
          TopNotification.error(uiContext, bicRequiredMsg);
          return;
        }
        if (bankName.isEmpty) {
          TopNotification.error(uiContext, bankNameRequiredMsg);
          return;
        }
        if (iban.length < 15 || iban.length > 34) {
          TopNotification.error(uiContext, invalidIbanFormatMsg);
          return;
        }

        paymentData.addAll({
          'iban': iban.toUpperCase(),
          'bic': bic.toUpperCase(),
          'bank_name': bankName,
        });
      }

      // Close modal first
      if (mounted && Navigator.of(modalContext).canPop()) {
        Navigator.pop(modalContext);
      }

      // Show loading
      if (mounted) {
        TopNotification.info(uiContext, connectingMsg);
      }

      // Create Stripe customer and save payment method
      final stripeResult = await _createStripeCustomerAndPaymentMethod(
        paymentData,
        userData?['email'] ?? AppLocalizations.of(context)!.tr(''),
        userData?['businessName'] ?? AppLocalizations.of(context)!.tr(''));

      if (stripeResult['success'] == true) {
        // Add Stripe customer ID to payment data
        paymentData['stripe_customer_id'] = stripeResult['customer_id'];
        paymentData['stripe_payment_method_id'] =
            stripeResult['payment_method_id'];

        debugPrint('✅ Stripe customer created: ${stripeResult['customer_id']}');
        debugPrint('✅ $stripeSuccessMsg');

        // Note: payment data already saved to DB by the stripe endpoint - no need to call _updateUserData

        // Update verification status for bank account
        await _updateVerificationStatus('bank_account', {
          'stripeCustomerId': stripeResult['customer_id'],
        });

        // Reload user data
        await _loadUserData();
        await _refreshPaymentSetupStatus();

        if (mounted) {
          setState(() {});
        }

        debugPrint('✅ $paymentSavedMsg');

        // Show success notification
        if (mounted) {
          TopNotification.success(
            uiContext,
            paymentSavedMsg);
        }
      } else {
        debugPrint('❌ $stripeFailedMsg: ${stripeResult['error']}');
        if (mounted) {
          TopNotification.error(
            uiContext,
            '$stripeFailedMsg: ${stripeResult['error']}');
        }
        return;
      }

      // Dispose controllers
      accountHolderNameController.dispose();
      routingNumberController.dispose();
      accountNumberController.dispose();
      ibanController.dispose();
      bicController.dispose();
      bankNameController.dispose();
    } catch (e) {
      debugPrint('❌ Error saving payment settings: $e');
      debugPrint('❌ $failedToSaveMsg: $e');

      // Dispose controllers even on error
      accountHolderNameController.dispose();
      routingNumberController.dispose();
      accountNumberController.dispose();
      ibanController.dispose();
      bicController.dispose();
      bankNameController.dispose();

      if (mounted) {
        TopNotification.error(uiContext, '$failedToSaveMsg: $e');
      }
    }
  }

  Future<void> _updateVerificationStatus(
    String verificationType,
    Map<String, dynamic> verificationData) async {
    try {
      final token = await _getStoredToken();

      if (token == null) {
        debugPrint('❌ Authentication required for verification update');
        return;
      }

      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/business-groups/update-verification'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'username': userData?['username'],
          'verificationType': verificationType,
          'verificationData': verificationData,
        }));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint(
            '✅ Verification updated: $verificationType - New score: ${data['verificationScore']}%');

          // Show notification for verification update
          if (mounted) {
            TopNotification.success(
              context,
              'Verification updated! New score: ${data['verificationScore']}%');
          }
        } else {
          debugPrint('❌ Verification update failed: ${data['error']}');
        }
      } else {
        debugPrint('❌ Verification update request failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error updating verification: $e');
    }
  }

  Future<Map<String, dynamic>> _createStripeCustomerAndPaymentMethod(
    Map<String, dynamic> paymentData,
    String customerEmail,
    String businessName) async {
    try {
      debugPrint('🔗 Creating Stripe customer and payment method...');

      final token = await _getStoredToken();

      if (token == null) {
        return {
          'success': false,
          'error':
              AppLocalizations.of(context)?.authenticationRequired ?? AppLocalizations.of(context)!.tr('Authentication required'),
        };
      }

        // Resolve required fields for stricter backend validators
        final fallbackUsername =
          (userData?['username'] ?? userData?['userId'] ?? AppLocalizations.of(context)!.tr('business'))
            .toString()
            .trim();
        final resolvedCustomerEmail = customerEmail.trim().isNotEmpty
          ? customerEmail.trim()
          : ((userData?['email'] ?? AppLocalizations.of(context)!.tr('')).toString().trim().isNotEmpty
            ? (userData?['email'] ?? AppLocalizations.of(context)!.tr('')).toString().trim()
            : '$fallbackUsername@cultioo.local');
        final resolvedBusinessName = businessName.trim().isNotEmpty
          ? businessName.trim()
          : ((userData?['businessName'] ?? AppLocalizations.of(context)!.tr('')).toString().trim().isNotEmpty
            ? (userData?['businessName'] ?? AppLocalizations.of(context)!.tr('')).toString().trim()
            : fallbackUsername);

        // Prepare Stripe customer data
      final paymentDataMap = <String, dynamic>{
        'account_holder_name': paymentData['account_holder_name'],
        'payment_system': paymentData['payment_system'],
      };

      // Add system-specific data
      final paymentType = paymentData['type']?.toString();
      if (paymentType == 'card') {
        // Card payment method — send card details directly
        paymentDataMap.addAll({
          'type': 'card',
          'card_number': paymentData['card_number'],
          'exp_month': paymentData['exp_month'],
          'exp_year': paymentData['exp_year'],
          'cvc': paymentData['cvc'],
          'cardholder_name': paymentData['cardholder_name'],
        });
      } else if (paymentData['payment_system'] == 'USA') {
        paymentDataMap.addAll({
          'routing_number': paymentData['routing_number'],
          'account_number': paymentData['account_number'],
        });
      } else {
        paymentDataMap.addAll({
          'iban': paymentData['iban'],
          'bic': paymentData['bic'],
          'bank_name': paymentData['bank_name'],
        });
      }

      final stripeData = {
        // camelCase keys
        'customerEmail': resolvedCustomerEmail,
        'businessName': resolvedBusinessName,
        'paymentData': paymentDataMap,
        // snake_case compatibility keys for older backends
        'customer_email': resolvedCustomerEmail,
        'business_name': resolvedBusinessName,
        'payment_data': paymentDataMap,
      };

      debugPrint('📡 Sending Stripe customer creation request...');
      debugPrint(
        '📡 Stripe request payload summary: email=$resolvedCustomerEmail, business=$resolvedBusinessName, payment_system=${paymentDataMap['payment_system']}');

      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/stripe/create-customer-payment-method'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(stripeData));

      debugPrint('📡 Stripe API response: ${response.statusCode}');
      debugPrint('📡 Stripe API response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          debugPrint('✅ Stripe customer and payment method created successfully');
          return {
            'success': true,
            'customer_id': responseData['customer_id'],
            'payment_method_id': responseData['payment_method_id'],
          };
        } else {
          debugPrint('❌ Stripe API error: ${responseData['error']}');
          return {
            'success': false,
            'error':
                responseData['error'] ??
                (AppLocalizations.of(context)?.unknownStripeError ?? AppLocalizations.of(context)!.tr('Unknown Stripe error')),
          };
        }
      } else {
        String backendError = 'Unknown error';
        try {
          final data = json.decode(response.body);
          backendError = (data['error'] ?? data['message'] ?? response.body)
              .toString();
        } catch (_) {
          backendError = response.body;
        }

        debugPrint(
          '❌ Stripe API request failed with status: ${response.statusCode}');
        debugPrint('❌ Stripe API request details: $backendError');
        return {
          'success': false,
          'error': backendError.isNotEmpty
              ? backendError
              : (AppLocalizations.of(context)?.stripeApiRequestFailed ?? AppLocalizations.of(context)!.tr('Stripe API request failed')),
        };
      }
    } catch (e) {
      debugPrint('❌ Error creating Stripe customer: $e');
      return {
        'success': false,
        'error':
            '${AppLocalizations.of(context)?.networkError ?? AppLocalizations.of(context)!.tr('Network error')}: $e',
      };
    }
  }

  Future<void> _showVerificationCenterModal(
    BuildContext context,
    bool isLight) async {
    await _refreshPaymentSetupStatus();
    final hasConnectedBank =
        BusinessAccountPage.hasConnectedPaymentSetup(userData) ||
        _hasConnectedPaymentMethod;

    // Calculate verification score based on actual data (same logic as button)
    int verificationScore = 0;
    List<String> verifiedItems = [];
    List<String> pendingItems = [];

    final hasCompleteProfile = BusinessAccountPage.hasCompleteBusinessProfile(userData);

    // Business Profile complete (50% of score)
    if (hasCompleteProfile) {
      verificationScore += 50;
      verifiedItems.add(AppLocalizations.of(context)!.tr('Business Profile'));
    } else {
      pendingItems.add(AppLocalizations.of(context)!.tr('Business Profile'));
    }

    // Bank Account (50% of score)
    if (hasConnectedBank) {
      verificationScore += 50;
      verifiedItems.add(
        AppLocalizations.of(context)?.bankAccount ?? AppLocalizations.of(context)!.tr('Bank Account'));
    } else {
      pendingItems.add(
        AppLocalizations.of(context)?.bankAccount ?? AppLocalizations.of(context)!.tr('Bank Account'));
    }

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.75,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.checkmark_shield_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.verification ?? AppLocalizations.of(context)!.tr('Verification'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

            // Explanation
            Container(
              padding: DesktopAppWrapper.getPagePadding(),
              decoration: BoxDecoration(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
                borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.tr('Was ist Business Verification?'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white)),
                  SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context)!.tr(
                      'Verification confirms your business on Cultioo. Fully verified accounts receive a Verified badge, more trust from customers and access to all features.'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
                      height: 1.45)),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Text(
                    AppLocalizations.of(context)!.tr('Was wird benötigt:'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white)),
                  SizedBox(height: 6),
                  _buildVerificationRequirement(
                    '1.',
                    AppLocalizations.of(context)!.tr('Business-Profil vollständig'),
                    AppLocalizations.of(context)!.tr('Name, E-Mail, Telefon und Adresse deines Unternehmens müssen ausgefüllt sein.'),
                    isLight),
                  SizedBox(height: 4),
                  _buildVerificationRequirement(
                    '2.',
                    AppLocalizations.of(context)!.tr('Bankkonto / Zahlungsmethode'),
                    AppLocalizations.of(context)!.tr('Verbinde ein Bankkonto oder eine Zahlungsmethode in den Payment Settings.'),
                    isLight),
                ])),

            SizedBox(height: 20),

            // Score - minimalist
            Text(
              '$verificationScore% ${AppLocalizations.of(context)?.verified ?? AppLocalizations.of(context)!.tr('verified')}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: verificationScore >= 100
                    ? Colors.green
                    : (isLight ? Colors.black : Colors.white).withOpacity(0.5))),

            SizedBox(height: 32),

            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Business Profile
                    _buildVerificationItem(
                      AppLocalizations.of(context)!.tr('Business Profile'),
                      hasCompleteProfile,
                      hasCompleteProfile
                          ? AppLocalizations.of(context)?.verified ?? AppLocalizations.of(context)!.tr('Verified')
                          : AppLocalizations.of(context)!.tr('Name, E-Mail, Telefon & Adresse ausfüllen'),
                      CupertinoIcons.person_crop_square_fill,
                      isLight),

                    // Bank Account
                    _buildVerificationItem(
                      AppLocalizations.of(context)?.bankAccount ?? AppLocalizations.of(context)!.tr('Bank Account'),
                      hasConnectedBank,
                      hasConnectedBank
                          ? AppLocalizations.of(context)?.connected ?? AppLocalizations.of(context)!.tr('Connected')
                          : AppLocalizations.of(
                                  context)?.connectViaPaymentSettings ?? AppLocalizations.of(context)!.tr('Connect via Payment Settings'),
                      CupertinoIcons.creditcard_fill,
                      isLight),
                  ]))),
          ]))).whenComplete(() => NavigationVisibility.show());
  }

  Widget _buildVerificationItem(
    String title,
    bool isVerified,
    String subtitle,
    IconData icon,
    bool isLight) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Row(
        children: [
          // Icon - minimalist
          Icon(
            icon,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
            size: 24),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white)),
                SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isVerified
                        ? Colors.green
                        : (isLight ? Colors.black : Colors.white).withOpacity(
                            0.5))),
              ])),
          // Status icon - minimalist
          Icon(
            isVerified
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.circle,
            color: isVerified
                ? Colors.green
                : (isLight ? Colors.black : Colors.white).withOpacity(0.3),
            size: 24),
        ]));
  }

  Widget _buildVerificationRequirement(
    String step,
    String title,
    String description,
    bool isLight) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.4))),
        SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$title  ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white)),
                TextSpan(
                  text: description,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.55))),
              ]))),
      ]);
  }

  void _showTaxFormsModal(BuildContext context, bool isLight) {
    final taxFormStatus = userData?['tax_form_status'] ?? AppLocalizations.of(context)!.tr('not_started');
    final taxFormType = userData?['tax_form_type'] ?? AppLocalizations.of(context)!.tr('unknown');
    final stripeAccountId =
        userData?['stripeAccountId'] ?? userData?['stripeCustomerId'];

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.doc_text_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.irsTaxForms ?? AppLocalizations.of(context)!.tr('IRS Tax Forms'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 32),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              physics:
                  (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                  ? const ClampingScrollPhysics()
                  : const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Status
                  if (taxFormStatus != 'not_started') ...[
                    Container(
                      padding: DesktopAppWrapper.getPagePadding(),
                      decoration: BoxDecoration(
                        color: taxFormStatus == 'completed'
                            ? CupertinoColors.systemGreen.withValues(alpha: 0.1)
                            : const Color(0xFFFF9500).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                taxFormStatus == 'completed'
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.clock_fill,
                                color: taxFormStatus == 'completed'
                                    ? CupertinoColors.systemGreen
                                    : const Color(0xFFFF9500),
                                size: 22),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      taxFormStatus == 'completed'
                                          ? AppLocalizations.of(
                                                  context)?.taxFormSubmitted ?? AppLocalizations.of(context)!.tr('Tax Form Submitted')
                                          : AppLocalizations.of(
                                                  context)?.taxFormPending ?? AppLocalizations.of(context)!.tr('Tax Form Pending'),
                                      style: TextStyle(
                                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                                        fontWeight: FontWeight.w600,
                                        color: taxFormStatus == 'completed'
                                            ? CupertinoColors.systemGreen
                                            : const Color(0xFFFF9500))),
                                    if (taxFormType != 'unknown') ...[
                                      SizedBox(height: 2),
                                      Text(
                                        '${AppLocalizations.of(context)?.formType ?? AppLocalizations.of(context)!.tr('Form Type')}: ${taxFormType.toUpperCase()}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color:
                                              (isLight
                                                      ? Colors.black
                                                      : Colors.white)
                                                  .withOpacity(0.5))),
                                    ],
                                  ])),
                            ]),
                          // "Continue" button shown only when pending
                          if (taxFormStatus == 'pending') ...[
                            SizedBox(height: 14),
                            TradeRepublicButton(
                              label:
                                  AppLocalizations.of(
                                    context)?.continueFilling ?? AppLocalizations.of(context)!.tr('Continue filling out'),
                              icon: Icon(
                                CupertinoIcons.arrow_up_right_square,
                                size: 18),
                              height: 46,
                              onPressed: () => _completeTaxFormViaStripe(
                                taxFormType != 'unknown' ? taxFormType : 'w9',
                                stripeAccountId)),
                          ],
                        ])),
                    SizedBox(height: 20),
                  ],

                  // W-9 Form
                  _buildTaxFormOption(
                    title: AppLocalizations.of(context)?.formW9 ?? AppLocalizations.of(context)!.tr('Form W-9'),
                    subtitle:
                        AppLocalizations.of(context)?.forUSCitizens ?? AppLocalizations.of(context)!.tr('For U.S. citizens and residents'),
                    description:
                        AppLocalizations.of(context)?.requestForTaxpayerId ?? AppLocalizations.of(context)!.tr('Request for Taxpayer Identification Number'),
                    icon: CupertinoIcons.person_fill,
                    isLight: isLight,
                    isSelected: taxFormType == 'w9',
                    onTap: () =>
                        _completeTaxFormViaStripe('w9', stripeAccountId)),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                  // W-8BEN Form
                  _buildTaxFormOption(
                    title:
                        AppLocalizations.of(context)?.formW8BEN ?? AppLocalizations.of(context)!.tr('Form W-8BEN'),
                    subtitle:
                        AppLocalizations.of(context)?.forNonUSIndividuals ?? AppLocalizations.of(context)!.tr('For non-U.S. individuals'),
                    description:
                        AppLocalizations.of(
                          context)?.certificateOfForeignStatus ?? AppLocalizations.of(context)!.tr('Certificate of Foreign Status of Beneficial Owner'),
                    icon: CupertinoIcons.globe,
                    isLight: isLight,
                    isSelected: taxFormType == 'w8ben',
                    onTap: () =>
                        _completeTaxFormViaStripe('w8ben', stripeAccountId)),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                  // W-8BEN-E Form
                  _buildTaxFormOption(
                    title:
                        AppLocalizations.of(context)?.formW8BENE ?? AppLocalizations.of(context)!.tr('Form W-8BEN-E'),
                    subtitle:
                        AppLocalizations.of(context)?.forNonUSEntities ?? AppLocalizations.of(context)!.tr('For non-U.S. entities/businesses'),
                    description:
                        AppLocalizations.of(
                          context)?.certificateOfStatusForTaxWithholding ?? AppLocalizations.of(context)!.tr('Certificate of Status of Beneficial Owner for Tax Withholding'),
                    icon: CupertinoIcons.building_2_fill,
                    isLight: isLight,
                    isSelected: taxFormType == 'w8bene',
                    onTap: () =>
                        _completeTaxFormViaStripe('w8bene', stripeAccountId)),

                  SizedBox(height: 28),

                  // Information text
                  Text(
                    AppLocalizations.of(context)?.whyDoINeedThis ?? AppLocalizations.of(context)!.tr('Why do I need this?'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white)),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Text(
                    AppLocalizations.of(context)?.irsRequiresTaxInfo ?? AppLocalizations.of(context)!.tr('The IRS requires tax information for all businesses receiving payments. This form helps determine your tax obligations and ensures compliance with U.S. tax laws.\\\\n\\\\n• W-9: For U.S. taxpayers (SSN or EIN)\\\\n• W-8BEN: For foreign individuals\\\\n• W-8BEN-E: For foreign companies'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      height: 1.5,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5))),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                  // Powered by Stripe
                  Center(
                    child: Text(
                      AppLocalizations.of(context)?.securedByStripeConnect ?? AppLocalizations.of(context)!.tr('Secured by Stripe Connect'),
                      style: TextStyle(
                        fontSize: 12,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.3)))),
                ]))),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  Widget _buildTaxFormOption({
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required bool isLight,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLight ? Colors.black : Colors.white)
              : (isLight ? Colors.black : Colors.white).withOpacity(0.04),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected
                  ? (isLight ? Colors.white : Colors.black)
                  : (isLight ? Colors.black : Colors.white).withOpacity(0.5)),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? (isLight ? Colors.white : Colors.black)
                          : (isLight ? Colors.black : Colors.white))),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      color: isSelected
                          ? (isLight ? Colors.white : Colors.black).withOpacity(
                              0.7)
                          : (isLight ? Colors.black : Colors.white).withOpacity(
                              0.5))),
                ])),
            if (isSelected)
              Icon(
                CupertinoIcons.check_mark_circled_solid,
                color: isLight ? Colors.white : Colors.black,
                size: 22)
            else
              Icon(
                CupertinoIcons.chevron_right,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.3),
                size: 20),
          ])));
  }

  Future<void> _completeTaxFormViaStripe(
    String formType,
    String? stripeAccountId) async {
    if (stripeAccountId == null || stripeAccountId.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.noStripeAccount ?? AppLocalizations.of(context)!.tr('No Stripe account found. Please connect a bank account first.'));
      return;
    }

    try {
      Navigator.pop(context); // Close modal
      TopNotification.info(
        context,
        AppLocalizations.of(context)?.openingStripeTaxForm ?? AppLocalizations.of(context)!.tr('Opening Stripe tax form...'));

      debugPrint('📋 Initiating tax form completion via Stripe: $formType');
      debugPrint('📋 Using Stripe Customer ID: $stripeAccountId');

      // Use public endpoint (no token required - validates via Stripe Customer ID)
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/stripe/tax-form-link-public'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'stripeAccountId': stripeAccountId,
          'formType': formType,
        }));

      debugPrint('📡 Tax form link response: ${response.statusCode}');
      debugPrint('📡 Tax form link body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final formUrl = data['url'];
        final needsOnboarding = data['needsOnboarding'] ?? false;

        if (formUrl != null && formUrl.isNotEmpty) {
          // Update local state
          setState(() {
            userData?['tax_form_status'] = 'pending';
            userData?['tax_form_type'] = formType;

            // Save Connect Account ID if provided
            if (data['connectAccountId'] != null) {
              userData?['stripeAccountId'] = data['connectAccountId'];
            }
          });

          if (needsOnboarding) {
            TopNotification.info(
              context,
              AppLocalizations.of(context)?.completeStripeSetupFirst ?? AppLocalizations.of(context)!.tr('Please complete Stripe account setup first'));
          } else {
            TopNotification.success(
              context,
              AppLocalizations.of(context)?.taxFormUrlGenerated ?? AppLocalizations.of(context)!.tr('Tax form URL generated! Opening in browser...'));
          }

          // Show the URL dialog
          debugPrint('🔗 Tax form URL: $formUrl');
          _showTaxFormUrlDialog(
            formUrl,
            isLight: Provider.of<AppSettings>(
              context,
              listen: false).isLightMode(context));
        } else {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.failedToGenerateTaxFormUrl ?? AppLocalizations.of(context)!.tr('Failed to generate tax form URL'));
        }
      } else {
        final error =
            json.decode(response.body)['error'] ??
            (AppLocalizations.of(context)?.unknownError ?? AppLocalizations.of(context)!.tr('Unknown error'));
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error')}: $error');
      }
    } catch (e) {
      debugPrint('❌ Error completing tax form: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.error ?? AppLocalizations.of(context)!.tr('Error')}: $e');
    }
  }

  void _showTaxFormUrlDialog(String url, {required bool isLight}) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.arrow_up_right_square,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.completeTaxFormViaStripe ?? AppLocalizations.of(context)!.tr('Complete Tax Form via Stripe'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4))),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Description
          Text(
            AppLocalizations.of(context)?.redirectedToStripe ?? AppLocalizations.of(context)!.tr('You will be redirected to Stripe\'s secure platform to complete your tax form. This link will open in your browser.'),
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6)),
            textAlign: TextAlign.center),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // URL Container
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Row(
              children: [
                Icon(CupertinoIcons.link, color: Colors.blue, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    url.length > 50 ? '${url.substring(0, 47)}...' : url,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue,
                      fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
              ])),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Action Button - minimalist
          TradeRepublicButton(
            label:
                AppLocalizations.of(context)?.openInBrowser ?? AppLocalizations.of(context)!.tr('Open in Browser'),
            icon: Icon(CupertinoIcons.arrow_up_right_square, size: 20),
            height: 50,
            onPressed: () async {
              HapticFeedback.lightImpact();
              Navigator.pop(context);

              // Open URL in browser
              debugPrint('🌐 Opening URL: $url');
              try {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  TopNotification.success(
                    context,
                    AppLocalizations.of(context)?.openingStripeBrowser ?? AppLocalizations.of(context)!.tr('Opening Stripe in browser...'));

                  // Show dialog that user should return after completing
                  _showReturnAfterStripeDialog(isLight);
                } else {
                  TopNotification.error(
                    context,
                    AppLocalizations.of(context)?.couldNotOpenBrowser ?? AppLocalizations.of(context)!.tr('Could not open browser'));
                }
              } catch (e) {
                debugPrint('❌ Error launching URL: $e');
                TopNotification.error(
                  context,
                  '${AppLocalizations.of(context)?.errorOpeningBrowser ?? AppLocalizations.of(context)!.tr('Error opening browser')}: $e');
              }
            }),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Cancel Button - minimalist
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            isSecondary: true,
            height: 50,
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            }),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  void _showReturnAfterStripeDialog(bool isLight) {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      NavigationVisibility.hide();

      TradeRepublicBottomSheet.show(
        context: context,
        bottomPadding: 20.0,
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            // state: 'waiting' | 'loading' | 'success' | 'incomplete'
            String state = 'waiting';
            bool isVerifying = false;
            List<String> issues = [];
            final loc = AppLocalizations.of(context);

            // Human-readable labels for Stripe requirement keys
            final Map<String, String> issueLabels = {
              'individual.dob.day':
                  loc?.stripeIssueDobDay ?? AppLocalizations.of(context)!.tr('Date of birth (day) missing'),
              'individual.dob.month':
                  loc?.stripeIssueDobMonth ?? AppLocalizations.of(context)!.tr('Date of birth (month) missing'),
              'individual.dob.year':
                  loc?.stripeIssueDobYear ?? AppLocalizations.of(context)!.tr('Date of birth (year) missing'),
              'individual.email':
                  loc?.stripeIssueEmail ?? AppLocalizations.of(context)!.tr('Email address missing or invalid'),
              'individual.first_name':
                  loc?.stripeIssueFirstName ?? AppLocalizations.of(context)!.tr('First name missing'),
              'individual.last_name':
                  loc?.stripeIssueLastName ?? AppLocalizations.of(context)!.tr('Last name missing'),
              'individual.address.line1':
                  loc?.stripeIssueAddress ?? AppLocalizations.of(context)!.tr('Address missing'),
              'individual.address.city': loc?.stripeIssueCity ?? AppLocalizations.of(context)!.tr('City missing'),
              'individual.address.postal_code':
                  loc?.stripeIssuePostalCode ?? AppLocalizations.of(context)!.tr('Postal code missing'),
              'individual.address.country':
                  loc?.stripeIssueCountry ?? AppLocalizations.of(context)!.tr('Country missing'),
              'individual.id_number':
                  loc?.stripeIssueIdNumber ?? AppLocalizations.of(context)!.tr('Tax ID (SSN/EIN) missing'),
              'individual.ssn_last_4':
                  loc?.stripeIssueSsnLast4 ?? AppLocalizations.of(context)!.tr('Last 4 digits of SSN missing'),
              'individual.phone':
                  loc?.stripeIssuePhone ?? AppLocalizations.of(context)!.tr('Phone number missing'),
              'individual.verification.document':
                  loc?.stripeIssueVerificationDoc ?? AppLocalizations.of(context)!.tr('Identity document missing'),
              'external_account':
                  loc?.stripeIssueExternalAccount ?? AppLocalizations.of(context)!.tr('Bank account missing'),
              'tos_acceptance.date':
                  loc?.stripeIssueTos ?? AppLocalizations.of(context)!.tr('Terms of service not accepted'),
              'tos_acceptance.ip':
                  loc?.stripeIssueTos ?? AppLocalizations.of(context)!.tr('Terms of service not accepted'),
              'business_profile.url':
                  loc?.stripeIssueProfileUrl ?? AppLocalizations.of(context)!.tr('Website / profile URL missing'),
            };

            Future<void> verify() async {
              setSheetState(() {
                state = 'loading';
                isVerifying = true;
              });

              final stripeAccountId = userData?['stripeAccountId']?.toString();
              bool confirmed = false;
              List<String> foundIssues = [];

              if (stripeAccountId != null &&
                  stripeAccountId.startsWith('acct_')) {
                try {
                  final resp = await http.post(
                    Uri.parse(
                      '${ApiConfig.baseUrl}/api/stripe/check-account-complete'),
                    headers: {'Content-Type': 'application/json'},
                    body: json.encode({'stripeAccountId': stripeAccountId}));
                  if (resp.statusCode == 200) {
                    final d = json.decode(resp.body);
                    confirmed = d['isComplete'] == true;
                    final due = <String>{
                      ...List<String>.from(d['currentlyDue'] ?? []),
                      ...List<String>.from(d['pastDue'] ?? []),
                    }.toList();
                    foundIssues = due.map((k) => issueLabels[k] ?? k).toList();
                  }
                } catch (e) {
                  debugPrint('⚠️ Stripe verify error: $e');
                }
              }

              if (confirmed) {
                await _updateTaxFormStatus('completed');
                await _loadUserData();
                setSheetState(() {
                  state = 'success';
                  isVerifying = false;
                });
              } else {
                setSheetState(() {
                  state = 'incomplete';
                  issues = foundIssues;
                  isVerifying = false;
                });
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DragHandle(),

                // ── Icon + headline ──────────────────────────────────────
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: state == 'success'
                        ? const Color(0xFF34C759).withOpacity(0.12)
                        : state == 'incomplete'
                        ? const Color(0xFFFF3B30).withOpacity(0.10)
                        : (isLight ? Colors.black : Colors.white).withOpacity(
                            0.06),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: state == 'loading'
                      ? const Center(child: CultiooLoadingIndicator(size: 28))
                      : Icon(
                          state == 'success'
                              ? CupertinoIcons.checkmark_circle_fill
                              : state == 'incomplete'
                              ? CupertinoIcons.xmark_circle_fill
                              : CupertinoIcons.doc_text_search,
                          size: 30,
                          color: state == 'success'
                              ? const Color(0xFF34C759)
                              : state == 'incomplete'
                              ? const Color(0xFFFF3B30)
                              : (isLight ? Colors.black : Colors.white))),
                SizedBox(height: 20),

                Text(
                  state == 'success'
                      ? (loc?.stripeVerificationCompleted ?? AppLocalizations.of(context)!.tr('Verification complete'))
                      : state == 'incomplete'
                      ? (loc?.stripeVerificationFailed ?? AppLocalizations.of(context)!.tr('Verification failed'))
                      : state == 'loading'
                      ? (loc?.stripeCheckingStatus ?? AppLocalizations.of(context)!.tr('Checking…'))
                      : (loc?.stripeFormFilled ?? AppLocalizations.of(context)!.tr('Form filled out?')),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: isLight ? Colors.black : Colors.white),
                  textAlign: TextAlign.center),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                Text(
                  state == 'success'
                      ? (loc?.stripeVerifiedSub ?? AppLocalizations.of(context)!.tr('Your Stripe account has been verified. You can now receive payouts.'))
                      : state == 'incomplete'
                      ? issues.isEmpty
                            ? (loc?.stripeIncompleteSub ?? AppLocalizations.of(context)!.tr('Your details could not be confirmed. Please complete the form in Stripe.'))
                            : (loc?.stripeMissingFieldsSub ?? AppLocalizations.of(context)!.tr('The following details are missing or invalid:'))
                      : state == 'loading'
                      ? (loc?.stripeCheckingSub ?? AppLocalizations.of(context)!.tr('We are checking your status with Stripe…'))
                      : (loc?.stripeWaitingSub ?? AppLocalizations.of(context)!.tr('Tap "Check now" once you have completed the form.')),
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5),
                    height: 1.5),
                  textAlign: TextAlign.center),

                // ── Issues list ──────────────────────────────────────────
                if (state == 'incomplete' && issues.isNotEmpty) ...[
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                  Container(
                    width: double.infinity,
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withOpacity(0.07),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_circle,
                              size: 15,
                              color: Color(0xFFFF3B30)),
                            SizedBox(width: 6),
                            Text(
                              loc?.stripeMissingInvalidFields ?? AppLocalizations.of(context)!.tr('Missing / invalid details'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFF3B30))),
                          ]),
                        SizedBox(height: 10),
                        ...issues.map(
                          (issue) => Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(top: 3),
                                  child: Icon(
                                    CupertinoIcons.circle_fill,
                                    size: 5,
                                    color: Color(0xFFFF3B30))),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    issue,
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                      color:
                                          (isLight
                                                  ? Colors.black
                                                  : Colors.white)
                                              .withOpacity(0.75)))),
                              ]))),
                      ])),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Text(
                    loc?.stripeEmailSentHint ?? AppLocalizations.of(context)!.tr('An email with these details was sent to your address.'),
                    style: TextStyle(
                      fontSize: 12,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.35)),
                    textAlign: TextAlign.center),
                ],

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // ── Buttons ──────────────────────────────────────────────
                if (state == 'success') ...[
                  TradeRepublicButton(
                    label: loc?.done ?? AppLocalizations.of(context)!.tr('Done'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }),
                ] else if (state == 'incomplete') ...[
                  TradeRepublicButton(
                    label: loc?.stripeRetryFill ?? AppLocalizations.of(context)!.tr('Fill out again'),
                    icon: Icon(
                      CupertinoIcons.arrow_up_right_square,
                      size: 18),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      final formType = userData?['tax_form_type'] ?? AppLocalizations.of(context)!.tr('w9');
                      final acctId = userData?['stripeCustomerId'];
                      _completeTaxFormViaStripe(formType, acctId);
                    }),
                  SizedBox(height: 10),
                  TradeRepublicButton(
                    label: loc?.close ?? AppLocalizations.of(context)!.tr('Close'),
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }),
                ] else if (state != 'loading') ...[
                  TradeRepublicButton(
                    label: loc?.stripeVerifyNow ?? AppLocalizations.of(context)!.tr('Check now'),
                    icon: Icon(CupertinoIcons.checkmark_shield, size: 18),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      verify();
                    }),
                  SizedBox(height: 10),
                  TradeRepublicButton(
                    label: loc?.stripeNotYetDone ?? AppLocalizations.of(context)!.tr('Not done yet'),
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }),
                ] else ...[
                  // loading state – no buttons
                  SizedBox(height: 40),
                ],
              ]);
          })).whenComplete(() => NavigationVisibility.show());
    });
  }

  Future<void> _updateTaxFormStatus(String status) async {
    try {
      debugPrint('💾 Updating tax form status to: $status');

      final token = await _getStoredToken();
      if (token == null) {
        debugPrint('❌ No auth token found');
        return;
      }

      // Get user ID
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      final userId =
          appSettings.userId ?? userData?['username'] ?? userData?['email'];

      if (userId == null) {
        debugPrint('❌ No user ID found');
        return;
      }

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/business/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'userId': userId, 'tax_form_status': status}));

      debugPrint('📡 Tax form status update response: ${response.statusCode}');
      debugPrint('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ Tax form status updated successfully');
      } else {
        debugPrint('❌ Failed to update tax form status: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error updating tax form status: $e');
    }
  }

  void _showFollowersModal(BuildContext context, bool isLight) {
    // Create a local copy of followers for this modal
    List<Map<String, dynamic>> modalFollowers = List.from(followers);

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.8,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DragHandle(),
                // ── Sheet header: Icon left + Title ──
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.person_2_fill,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white),
                    SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.followers ?? AppLocalizations.of(context)!.tr('Followers'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4)),
                  ]),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Stats Row
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: isLight ? Colors.white : Colors.black,
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                        child: Column(
                          children: [
                            Text(
                              '${modalFollowers.length}',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: isLight ? Colors.black : Colors.white)),
                            SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(context)?.followers ?? AppLocalizations.of(context)!.tr('Followers'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.5))),
                          ]))),
                    SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: isLight ? Colors.white : Colors.black,
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                        child: Column(
                          children: [
                            Text(
                              '${socialStats['following_count']}',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: isLight ? Colors.black : Colors.white)),
                            SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(context)?.following ?? AppLocalizations.of(context)!.tr('Following'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.5))),
                          ]))),
                  ]),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Followers List with swipe-to-remove
                Expanded(
                  child: modalFollowers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.person_2_fill,
                                size: 64,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.2)),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                              Text(
                                AppLocalizations.of(context)?.noFollowersYet ?? AppLocalizations.of(context)!.tr('No followers yet'),
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5))),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                              Text(
                                AppLocalizations.of(
                                      context)?.shareProfileToGetFollowers ?? AppLocalizations.of(context)!.tr('Share your profile to get followers'),
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w500,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.4))),
                            ]))
                      : ListView.builder(
                          itemCount: modalFollowers.length,
                          itemBuilder: (context, index) {
                            final follower = modalFollowers[index];
                            final followerId =
                                follower['id']?.toString() ??
                                follower['userId']?.toString() ??
                                follower['username']?.toString() ??
                                index.toString();

                            return TradeRepublicSwipeAction(
                              key: ValueKey('follower_$followerId'),
                              margin: EdgeInsets.only(bottom: 8),
                              trailing: TradeRepublicSwipeSpec(
                                icon: CupertinoIcons.person_badge_minus,
                                label: 'Remove',
                                backgroundColor: const Color(0xFFFF3B30),
                                foregroundColor: Colors.white,
                                onActivate: () async {
                                  setModalState(() {
                                    modalFollowers.removeAt(index);
                                  });
                                  setState(() {
                                    followers.removeWhere(
                                      (f) =>
                                          (f['id']?.toString() ??
                                              f['userId']?.toString() ??
                                              f['username']?.toString()) ==
                                          followerId);
                                    if (socialStats['followers_count'] != null) {
                                      socialStats['followers_count'] =
                                          (socialStats['followers_count']
                                              as int) -
                                          1;
                                    }
                                  });
                                  await _removeFollower(followerId);
                                }),
                              child: _buildFollowerItem(follower, isLight));
                          })),
              ]));
        })).whenComplete(() => NavigationVisibility.show());
  }

  // Remove a follower (they will no longer follow you)
  Future<void> _removeFollower(String followerId) async {
    try {
      final token = await _getStoredToken();
      if (token == null) return;

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/business/followers/$followerId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

      if (response.statusCode == 200) {
        debugPrint('✅ Follower removed successfully');
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.followerRemoved ?? AppLocalizations.of(context)!.tr('Follower removed'));
      } else {
        debugPrint('❌ Failed to remove follower: ${response.body}');
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedRemoveFollower ?? AppLocalizations.of(context)!.tr('Failed to remove follower'));
      }
    } catch (e) {
      debugPrint('❌ Error removing follower: $e');
    }
  }

  // Build avatar widget for follower - handles profile pictures and fallback
  Widget _buildFollowerAvatar(Map<String, dynamic> follower, bool isLight) {
    final profilePic = follower['profilePic']?.toString() ?? AppLocalizations.of(context)!.tr('');
    final name =
        follower['name']?.toString() ?? follower['username']?.toString() ?? AppLocalizations.of(context)!.tr('U');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    // Check if profilePic is empty or SVG (not supported)
    if (profilePic.isEmpty || profilePic.startsWith('<svg')) {
      // Show initial letter avatar with gradient
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade400, Colors.purple.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
              fontWeight: FontWeight.w700,
              color: Colors.white))));
    }

    // Load network image
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      child: Image.network(
        _buildImageUrl(profilePic),
        fit: BoxFit.cover,
        width: 50,
        height: 50,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CultiooLoadingIndicator(size: 20)));
        },
        errorBuilder: (context, error, stackTrace) {
          // Fallback to initial letter on error
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.purple.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                  fontWeight: FontWeight.w700,
                  color: Colors.white))));
        }));
  }

  Widget _buildFollowerItem(Map<String, dynamic> follower, bool isLight) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        // Use solid color to prevent red swipe background from showing through
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Row(
        children: [
          // Profile Picture or Avatar - Modern style
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              color: isLight ? Colors.white : Colors.black),
            child: _buildFollowerAvatar(follower, isLight)),

          SizedBox(width: 16),

          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        follower['name'] ??
                            follower['username'] ??
                            (AppLocalizations.of(context)?.unknownUser ?? AppLocalizations.of(context)!.tr('Unknown User')),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                    if (follower['isBusiness'] == true)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                        child: Text(
                          AppLocalizations.of(context)?.business ?? AppLocalizations.of(context)!.tr('Business'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue))),
                  ]),

                SizedBox(height: 4),

                Text(
                  '@${follower['username']}',
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.6))),

                SizedBox(height: 4),

                Row(
                  children: [
                    Icon(
                      CupertinoIcons.calendar,
                      size: 12,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.4)),
                    SizedBox(width: 4),
                    Text(
                      '${AppLocalizations.of(context)?.followingSince ?? AppLocalizations.of(context)!.tr('Following since')} ${_formatDate(follower['followedDate'])}',
                      style: TextStyle(
                        fontSize: 12,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.4))),
                  ]),
              ])),

          // Stats
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${follower['stats']['followers']}',
                style: TextStyle(
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: FontWeight.w600,
                  color: Colors.green)),
              Text(
                (AppLocalizations.of(context)?.followers ?? AppLocalizations.of(context)!.tr('followers'))
                    .toLowerCase(),
                style: TextStyle(
                  fontSize: 10,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.4))),
            ]),
        ]));
  }

  void _showSignOutModal(BuildContext context, bool isLight) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Builder(
        builder: (BuildContext context) {
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DragHandle(),
                // ── Sheet header: Icon left + Title ──
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.power,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white),
                    SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.signOut ?? AppLocalizations.of(context)!.tr('Sign Out'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4)),
                  ]),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                SizedBox(height: 32),

                // Icon - minimalist
                Icon(
                  CupertinoIcons.square_arrow_right,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.6),
                  size: 64),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Description
                Text(
                  AppLocalizations.of(context)?.signOutConfirm ?? AppLocalizations.of(context)!.tr('Are you sure you want to sign out?\\\\nYou can always sign back in anytime.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.6))),

                SizedBox(height: 40),

                // Sign Out button - minimalist red
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.signOut ?? AppLocalizations.of(context)!.tr('Sign Out'),
                  isDestructive: true,
                  height: 50,
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    _performSignOut();
                  }),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                // Cancel button - minimalist
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                  isSecondary: true,
                  height: 50,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  }),
              ]));
        })).whenComplete(() => NavigationVisibility.show());
  }

  Future<void> _saveBusinessData(
    BuildContext context,
    TextEditingController businessNameController,
    TextEditingController businessDescriptionController,
    TextEditingController businessWebsiteController,
    TextEditingController streetController,
    TextEditingController houseNumberController,
    TextEditingController cityController,
    TextEditingController stateController,
    TextEditingController zipCodeController,
    String selectedCountry,
    String selectedSize,
    bool showPhone,
    bool showBusinessEmail,
    bool showBusinessCompany,
    bool showBusinessSize,
    bool showBusinessCountry) async {
    try {
      // Validate required fields
      if (businessNameController.text.trim().isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.businessNameRequired ?? AppLocalizations.of(context)!.tr('Business name is required'));
        return;
      }

      // Merge address fields into single string: "Street HouseNumber, City, State, ZIP, Country"
      final street = streetController.text.trim();
      final houseNumber = houseNumberController.text.trim();
      final city = cityController.text.trim();
      final state = stateController.text.trim();
      final zipCode = zipCodeController.text.trim();

      // Build full address string
      final addressParts = <String>[];
      if (street.isNotEmpty || houseNumber.isNotEmpty) {
        addressParts.add('$street $houseNumber'.trim());
      }
      if (city.isNotEmpty) addressParts.add(city);
      if (state.isNotEmpty) addressParts.add(state);
      if (zipCode.isNotEmpty) addressParts.add(zipCode);
      if (selectedCountry.isNotEmpty) addressParts.add(selectedCountry);

      final businessAddress = addressParts.join(', ');

      // Note: Email and phone are now taken from users table, not business fields

      // Collect updated data including visibility settings
      final updatedData = {
        'businessName': businessNameController.text.trim(),
        'businessDescription':
            businessDescriptionController.text.trim().isNotEmpty
            ? businessDescriptionController.text.trim()
            : null,
        'businessWebsite': businessWebsiteController.text.trim().isNotEmpty
            ? businessWebsiteController.text.trim()
            : null,
        'businessAddress': businessAddress,
        'country': selectedCountry,
        'businessSize': selectedSize,

        // Privacy & visibility settings
        'showPhone': showPhone ? 1 : 0,
        'showBusinessEmail': showBusinessEmail ? 1 : 0,
        'showBusinessCompany': showBusinessCompany ? 1 : 0,
        'showBusinessSize': showBusinessSize ? 1 : 0,
        'showBusinessCountry': showBusinessCountry ? 1 : 0,
      };

      // Close modal first
      Navigator.pop(context);

      // Dispose controllers
      businessNameController.dispose();
      businessDescriptionController.dispose();
      businessWebsiteController.dispose();
      streetController.dispose();
      houseNumberController.dispose();
      cityController.dispose();
      stateController.dispose();
      zipCodeController.dispose();

      // Show loading indicator
      TopNotification.info(
        context,
        AppLocalizations.of(context)?.updatingBusinessInfo ?? AppLocalizations.of(context)!.tr('Updating business information...'));

      // Update user data via API
      await _updateUserData(updatedData);

      // Reload user data to reflect changes
      await _loadUserData();
    } catch (e) {
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.failedToUpdateBusinessInfo ?? AppLocalizations.of(context)!.tr('Failed to update business information')}: $e');
    }
  }

  Widget _buildEditableBusinessField(
    String label,
    TextEditingController controller,
    IconData icon,
    bool isLight, {
    int maxLines = 1,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.8))),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          TradeRepublicTextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
              color: isLight ? Colors.black : Colors.white),
            prefixIcon: Icon(
              icon,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              size: 20),
            filled: false),
        ]));
  }

  Widget _buildVisibilityToggle(
    String title,
    String subtitle,
    bool currentValue,
    IconData icon,
    bool isLight,
    Function(bool) onChanged) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: DesktopAppWrapper.getPagePadding(),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : Colors.black,
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: currentValue
                      ? Colors.green.withOpacity(0.2)
                      : (isLight ? Colors.black : Colors.white).withOpacity(
                          0.1),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Icon(
                  icon,
                  size: 20,
                  color: currentValue
                      ? Colors.green
                      : (isLight ? Colors.black : Colors.white).withOpacity(
                          0.6))),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: isLight ? Colors.black : Colors.white)),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.6)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  ])),
              SizedBox(width: 12),
              TradeRepublicSwitch(value: currentValue, onChanged: onChanged),
            ]))));
  }

  void _showCountrySelection(
    StateSetter setModalState,
    String currentCountry,
    bool isLight,
    Function(String) onCountrySelected) {
    final countries = [
      // North America
      {'name': 'United States', 'code': 'US', 'flag': '🇺🇸'},
      {'name': 'Canada', 'code': 'CA', 'flag': '🇨🇦'},
      {'name': 'Mexico', 'code': 'MX', 'flag': '🇲🇽'},
      // EU Countries
      {'name': 'Germany', 'code': 'DE', 'flag': '🇩🇪'},
      {'name': 'Austria', 'code': 'AT', 'flag': '🇦🇹'},
      {'name': 'France', 'code': 'FR', 'flag': '🇫🇷'},
      {'name': 'Italy', 'code': 'IT', 'flag': '🇮🇹'},
      {'name': 'Spain', 'code': 'ES', 'flag': '🇪🇸'},
      {'name': 'Netherlands', 'code': 'NL', 'flag': '🇳🇱'},
      {'name': 'Belgium', 'code': 'BE', 'flag': '🇧🇪'},
      {'name': 'Poland', 'code': 'PL', 'flag': '🇵🇱'},
      {'name': 'Portugal', 'code': 'PT', 'flag': '🇵🇹'},
      {'name': 'Greece', 'code': 'GR', 'flag': '🇬🇷'},
      {'name': 'Ireland', 'code': 'IE', 'flag': '🇮🇪'},
      {'name': 'Sweden', 'code': 'SE', 'flag': '🇸🇪'},
      {'name': 'Denmark', 'code': 'DK', 'flag': '🇩🇰'},
      {'name': 'Finland', 'code': 'FI', 'flag': '🇫🇮'},
      {'name': 'Czech Republic', 'code': 'CZ', 'flag': '🇨🇿'},
      {'name': 'Hungary', 'code': 'HU', 'flag': '🇭🇺'},
      {'name': 'Romania', 'code': 'RO', 'flag': '🇷🇴'},
      {'name': 'Bulgaria', 'code': 'BG', 'flag': '🇧🇬'},
      {'name': 'Croatia', 'code': 'HR', 'flag': '🇭🇷'},
      {'name': 'Slovakia', 'code': 'SK', 'flag': '🇸🇰'},
      {'name': 'Slovenia', 'code': 'SI', 'flag': '🇸🇮'},
      {'name': 'Estonia', 'code': 'EE', 'flag': '🇪🇪'},
      {'name': 'Latvia', 'code': 'LV', 'flag': '🇱🇻'},
      {'name': 'Lithuania', 'code': 'LT', 'flag': '🇱🇹'},
      {'name': 'Malta', 'code': 'MT', 'flag': '🇲🇹'},
      {'name': 'Cyprus', 'code': 'CY', 'flag': '🇨🇾'},
      {'name': 'Luxembourg', 'code': 'LU', 'flag': '🇱🇺'},
      // Russia
      {'name': 'Russia', 'code': 'RU', 'flag': '🇷🇺'},
    ];

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.4,
      child: Column(
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.globe,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.selectCountry ?? AppLocalizations.of(context)!.tr('Select Country'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: countries.length,
              itemBuilder: (context, index) {
                final country = countries[index];
                final isSelected = country['name'] == currentCountry;

                return TradeRepublicTap(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onCountrySelected(country['name']!);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isLight ? Colors.black : Colors.white)
                          : isLight
                          ? Colors.white
                          : Colors.black,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Row(
                      children: [
                        Text(
                          country['flag']!,
                          style: TextStyle(fontSize: 28)),
                        SizedBox(width: 16),
                        Text(
                          country['name']!,
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? (isLight ? Colors.white : Colors.black)
                                : (isLight ? Colors.black : Colors.white))),
                        if (isSelected) ...[
                          const Spacer(),
                          Icon(
                            CupertinoIcons.check_mark_circled_solid,
                            color: isLight ? Colors.white : Colors.black),
                        ],
                      ])));
              })),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  void _showBusinessSizeSelection(
    StateSetter setModalState,
    String currentSize,
    bool isLight,
    Function(String) onSizeSelected) {
    final sizeOptions = [
      {'size': '1-10 employees', 'icon': Icons.store},
      {'size': '11-50 employees', 'icon': CupertinoIcons.building_2_fill},
      {'size': '51-100 employees', 'icon': Icons.domain},
      {'size': '101-500 employees', 'icon': Icons.corporate_fare},
      {'size': '500+ employees', 'icon': CupertinoIcons.building_2_fill},
    ];

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.5,
      child: Column(
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.building_2_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.selectBusinessSize ?? AppLocalizations.of(context)!.tr('Select Business Size'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Expanded(
            child: ListView.builder(
              itemCount: sizeOptions.length,
              itemBuilder: (context, index) {
                final option = sizeOptions[index];
                final isSelected = option['size'] == currentSize;

                return TradeRepublicTap(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSizeSelected(option['size'] as String);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: EdgeInsets.only(bottom: 12),
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isLight ? Colors.black : Colors.white)
                          : isLight
                          ? Colors.white
                          : Colors.black,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                    child: Row(
                      children: [
                        Icon(
                          option['icon'] as IconData,
                          color: isSelected
                              ? (isLight ? Colors.white : Colors.black)
                                    .withOpacity(0.6)
                              : (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.6)),
                        SizedBox(width: 16),
                        Text(
                          option['size'] as String,
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? (isLight ? Colors.white : Colors.black)
                                : (isLight ? Colors.black : Colors.white))),
                        if (isSelected) ...[
                          const Spacer(),
                          Icon(
                            CupertinoIcons.check_mark_circled_solid,
                            color: isLight ? Colors.white : Colors.black),
                        ],
                      ])));
              })),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  Widget _buildSecurityToggle(
    String title,
    String subtitle,
    bool currentValue,
    IconData icon,
    bool isLight,
    Function(bool) onChanged) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: (isLight ? Colors.black : Colors.white).withOpacity(0.04),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: currentValue
                ? CupertinoColors.systemGreen
                : (isLight ? Colors.black : Colors.white).withOpacity(0.5)),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white)),
                SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5))),
              ])),
          Builder(
            builder: (ctx) {
              final isProcessing =
                  userData != null && userData!['biometric_processing'] == true;
              if (isProcessing) {
                return SizedBox(
                  width: 48,
                  height: 28,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CultiooLoadingIndicator(size: 20))));
              }

              return TradeRepublicSwitch(
                value: currentValue,
                onChanged: onChanged);
            }),
        ]));
  }

  Widget _buildSecurityActionItem(
    String title,
    String subtitle,
    IconData icon,
    bool isLight,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.red.withOpacity(0.08)
              : (isLight ? Colors.black : Colors.white).withOpacity(0.04),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isDestructive
                  ? Colors.red
                  : (isLight ? Colors.black : Colors.white).withOpacity(0.5)),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: isDestructive
                          ? Colors.red
                          : (isLight ? Colors.black : Colors.white))),
                  SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5))),
                ])),
            Icon(
              CupertinoIcons.chevron_right,
              size: 20,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.3)),
          ])));
  }

  // Security Toggle Methods
  Future<void> _toggle2FA(bool enabled, StateSetter setModalState) async {
    if (enabled) {
      // Show 2FA setup modal when enabling
      _show2FASetupModal(context, setModalState);
    } else {
      // Disable 2FA directly
      try {
        final updatedData = {'has_2fa_enabled': 0, 'twofa': null};

        await _updateUserData(updatedData);

        setModalState(() {
          userData!['has_2fa_enabled'] = 0;
          userData!['twofa'] = null;
        });

        TopNotification.success(
          context,
          AppLocalizations.of(context)?.twoFADisabledSuccess ?? AppLocalizations.of(context)!.tr('2FA disabled successfully!'));
      } catch (e) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedDisable2FA ?? AppLocalizations.of(context)!.tr('Failed to disable 2FA settings'));
      }
    }
  }

  Future<void> _toggleBiometric(bool enabled, StateSetter setModalState) async {
    try {
      if (enabled) {
        // When enabling biometric, first check if device supports it
        final bool isDeviceSupported =
            await BiometricService.isDeviceSupported();
        if (!isDeviceSupported) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.biometricNotSupported ?? AppLocalizations.of(context)!.tr('Biometric authentication not supported on this device'));
          return;
        }

        // Test biometric authentication to verify it works
        TopNotification.info(
          context,
          AppLocalizations.of(context)?.authenticateBiometricEnable ?? AppLocalizations.of(context)!.tr('Please authenticate with your biometric to enable this feature'));

        // mark processing to update UI (show spinner)
        setModalState(() {
          userData!['biometric_processing'] = true;
        });

        // Use testBiometric instead of enableBiometric to avoid double saving
        // Add timeout to avoid hangs on iOS and catch exceptions
        bool biometricTest = false;
        bool processingSet = true;
        try {
          try {
            biometricTest = await BiometricService.testBiometric().timeout(
              const Duration(seconds: 12));
          } catch (e) {
            debugPrint('⚠️ Biometric test timeout or error: $e');
            biometricTest = false;
          }

          if (!biometricTest) {
            TopNotification.error(
              context,
              AppLocalizations.of(context)?.biometricAuthFailed ?? AppLocalizations.of(context)!.tr('Biometric authentication failed. Please try again.'));
            return;
          }

          // If test successful, save both locally and to database
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('biometric_enabled', true);

          final updatedData = {'biometric_enabled': 1};

          await _updateUserData(updatedData);

          setModalState(() {
            userData!['biometric_enabled'] = 1;
          });

          TopNotification.success(
            context,
            AppLocalizations.of(context)?.biometricEnabledSuccess ?? AppLocalizations.of(context)!.tr('Biometric authentication enabled and tested successfully!'));
        } finally {
          if (processingSet) {
            setModalState(() {
              userData!['biometric_processing'] = false;
            });
          }
        }
      } else {
        // When disabling biometric, verify with biometric first
        TopNotification.info(
          context,
          AppLocalizations.of(context)?.authenticateBiometricDisable ?? AppLocalizations.of(context)!.tr('Please authenticate with your biometric to disable this feature'));

        // mark processing
        setModalState(() {
          userData!['biometric_processing'] = true;
        });

        bool biometricTest = false;
        bool processingSet = true;
        try {
          try {
            biometricTest = await BiometricService.testBiometric().timeout(
              const Duration(seconds: 12));
          } catch (e) {
            debugPrint('⚠️ Biometric test timeout or error: $e');
            biometricTest = false;
          }

          if (!biometricTest) {
            TopNotification.error(
              context,
              AppLocalizations.of(context)?.biometricRequiredDisable ?? AppLocalizations.of(context)!.tr('Biometric authentication required to disable this feature'));
            return;
          }

          // If verification successful, disable both locally and in database
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('biometric_enabled', false);

          final updatedData = {'biometric_enabled': 0};

          await _updateUserData(updatedData);

          setModalState(() {
            userData!['biometric_enabled'] = 0;
          });

          TopNotification.success(
            context,
            AppLocalizations.of(context)?.biometricDisabledSuccess ?? AppLocalizations.of(context)!.tr('Biometric authentication disabled successfully!'));
        } finally {
          if (processingSet) {
            setModalState(() {
              userData!['biometric_processing'] = false;
            });
          }
        }
      }
    } catch (e) {
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.failedUpdateBiometric ?? AppLocalizations.of(context)!.tr('Failed to update biometric settings')}: $e');
      debugPrint('❌ Error in _toggleBiometric: $e');
    }
  }

  /// Synchronize biometric settings between local SharedPreferences and database
  Future<void> _synchronizeBiometricSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localBiometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      final dbBiometricEnabled = userData?['biometric_enabled'] == 1;

      debugPrint(
        '🔄 Synchronizing biometric settings: local=$localBiometricEnabled, db=$dbBiometricEnabled');

      // If settings don't match, prioritize database value (server as source of truth)
      if (localBiometricEnabled != dbBiometricEnabled) {
        debugPrint(
          '⚠️ Biometric settings mismatch - updating local storage to match database');
        await prefs.setBool('biometric_enabled', dbBiometricEnabled);
      }
    } catch (e) {
      debugPrint('❌ Error synchronizing biometric settings: $e');
    }
  }

  Future<void> _toggleLoginNotifications(
    bool enabled,
    StateSetter setModalState) async {
    try {
      final updatedData = {'notifications_login': enabled ? 1 : 0};

      await _updateUserData(updatedData);

      setModalState(() {
        userData!['notifications_login'] = enabled ? 1 : 0;
      });

      TopNotification.success(
        context,
        enabled
            ? AppLocalizations.of(context)?.loginNotifEnabled ?? AppLocalizations.of(context)!.tr('Login notifications enabled!')
            : AppLocalizations.of(context)?.loginNotifDisabled ?? AppLocalizations.of(context)!.tr('Login notifications disabled!'));
    } catch (e) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.failedUpdateNotifSettings ?? AppLocalizations.of(context)!.tr('Failed to update notification settings'));
    }
  }

  // Notification Toggle Methods for Security & Privacy Section
  Future<void> _toggleNewsletterSubscription(bool enabled) async {
    try {
      debugPrint('📧 Toggling newsletter subscription via Google Cloud: $enabled');

      final token = await _getStoredToken();

      if (token == null) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.authenticationRequired ?? AppLocalizations.of(context)!.tr('Authentication required'));
        return;
      }

      final updatedData = {'notifications_newsletter': enabled ? 1 : 0};

      // Save to Google Cloud database
      await _updateUserData(updatedData);

      // Update local state
      if (mounted) {
        setState(() {
          userData!['notifications_newsletter'] = enabled ? 1 : 0;
        });
      }

      debugPrint(
        '✅ Newsletter subscription ${enabled ? 'enabled' : 'disabled'} successfully');
      TopNotification.success(
        context,
        enabled
            ? AppLocalizations.of(context)?.newsletterEnabled ?? AppLocalizations.of(context)!.tr('Newsletter subscription enabled and synced to Google Cloud!')
            : AppLocalizations.of(context)?.newsletterDisabled ?? AppLocalizations.of(context)!.tr('Newsletter subscription disabled and synced to Google Cloud!'));
    } catch (e) {
      debugPrint('❌ Error updating newsletter subscription: $e');
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.failedSyncNewsletter ?? AppLocalizations.of(context)!.tr('Failed to sync newsletter subscription to Google Cloud'));
    }
  }

  Future<void> _toggleLoginNotificationsInPrivacy(bool enabled) async {
    try {
      debugPrint('🔔 Toggling login notifications in privacy section: $enabled');

      final token = await _getStoredToken();

      if (token == null) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.authenticationRequired ?? AppLocalizations.of(context)!.tr('Authentication required'));
        return;
      }

      final updatedData = {'notifications_login': enabled ? 1 : 0};

      // Save to Google Cloud database
      await _updateUserData(updatedData);

      // Update local state
      if (mounted) {
        setState(() {
          userData!['notifications_login'] = enabled ? 1 : 0;
        });
      }

      debugPrint(
        '✅ Login notifications ${enabled ? 'enabled' : 'disabled'} successfully');
      TopNotification.success(
        context,
        enabled
            ? AppLocalizations.of(context)?.loginNotifEnabledSync ?? AppLocalizations.of(context)!.tr('Login notifications enabled')
            : AppLocalizations.of(context)?.loginNotifDisabledSync ?? AppLocalizations.of(context)!.tr('Login notifications disabled'));
    } catch (e) {
      debugPrint('❌ Error updating login notifications: $e');
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.failedSyncLoginNotif ?? AppLocalizations.of(context)!.tr('Failed to sync login notifications'));
    }
  }

  Widget _buildNotificationToggle(
    String title,
    String subtitle,
    bool currentValue,
    IconData icon,
    bool isLight,
    Function(bool) onChanged) {
    return TradeRepublicListTile.toggle(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon, size: 18),
      value: currentValue,
      onChanged: (v) => onChanged(v));
  }

  // Security Modal Methods
  void _showChangePasswordModal(BuildContext context, bool isLight) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrentPassword = true;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.lock_fill,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.changePassword ?? AppLocalizations.of(context)!.tr('Change Password'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4)),
                ]),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              Flexible(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Current Password
                      _buildPasswordField(
                        AppLocalizations.of(context)?.currentPassword ?? AppLocalizations.of(context)!.tr('Current Password'),
                        AppLocalizations.of(context)?.currentPasswordHint ?? AppLocalizations.of(context)!.tr('Current password'),
                        currentPasswordController,
                        obscureCurrentPassword,
                        isLight,
                        () => setModalState(
                          () =>
                              obscureCurrentPassword = !obscureCurrentPassword)),

                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                      // New Password
                      _buildPasswordField(
                        AppLocalizations.of(context)?.newPassword ?? AppLocalizations.of(context)!.tr('New Password'),
                        AppLocalizations.of(context)?.newPasswordHint ?? AppLocalizations.of(context)!.tr('New password'),
                        newPasswordController,
                        obscureNewPassword,
                        isLight,
                        () => setModalState(
                          () => obscureNewPassword = !obscureNewPassword)),

                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                      // Confirm Password
                      _buildPasswordField(
                        AppLocalizations.of(context)?.confirmPassword ?? AppLocalizations.of(context)!.tr('Confirm Password'),
                        AppLocalizations.of(context)?.confirmNewPasswordHint ?? AppLocalizations.of(context)!.tr('Confirm new password'),
                        confirmPasswordController,
                        obscureConfirmPassword,
                        isLight,
                        () => setModalState(
                          () =>
                              obscureConfirmPassword = !obscureConfirmPassword)),

                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                      // Requirements - minimalist
                      Text(
                        AppLocalizations.of(context)?.atLeastEightCharacters ?? AppLocalizations.of(context)!.tr('At least 8 characters with uppercase, lowercase, number and special character'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4))),
                    ]))),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              // Change button - minimalist
              TradeRepublicButton(
                label:
                    AppLocalizations.of(context)?.changePassword ?? AppLocalizations.of(context)!.tr('Change Password'),
                height: 50,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _changePassword(
                    currentPasswordController.text,
                    newPasswordController.text,
                    confirmPasswordController.text);
                }),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

              // Cancel button - minimalist
              TradeRepublicButton(
                label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                isSecondary: true,
                height: 50,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  currentPasswordController.dispose();
                  newPasswordController.dispose();
                  confirmPasswordController.dispose();
                  Navigator.pop(context);
                }),
            ]))).whenComplete(() => NavigationVisibility.show());
  }

  Widget _buildPasswordField(
    String label,
    String hint,
    TextEditingController controller,
    bool obscureText,
    bool isLight,
    VoidCallback toggleVisibility) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w600,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        TradeRepublicTextField(
          controller: controller,
          obscureText: obscureText,
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w500,
            color: isLight ? Colors.black : Colors.white),
          hintText: hint,
          suffixIcon: TradeRepublicButton.icon(
            size: 36,
            isSecondary: true,
            foregroundColor:
                (isLight ? Colors.black : Colors.white).withOpacity(0.4),
            icon: Icon(
              obscureText ? CupertinoIcons.eye_slash : CupertinoIcons.eye_fill,
              size: 20),
            onPressed: toggleVisibility),
          filled: true,
          fillColor: (isLight ? Colors.black : Colors.white).withOpacity(0.05)),
      ]);
  }

  Future<void> _changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword) async {
    debugPrint('🔐 _changePassword called');

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.fillAllFields ?? AppLocalizations.of(context)!.tr('Please fill in all fields'));
      return;
    }

    if (newPassword != confirmPassword) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.passwordsDoNotMatch ?? AppLocalizations.of(context)!.tr('New passwords do not match'));
      return;
    }

    if (newPassword.length < 8) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.passwordMinLength ??
            AppLocalizations.of(context)?.passwordAtLeast8Characters ?? AppLocalizations.of(context)!.tr('Password must be at least 8 characters'));
      return;
    }

    debugPrint('✅ Password validation passed');

    try {
      final token = await _getStoredToken();
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      final userId =
          appSettings.userId ?? userData?['username'] ?? userData?['email'];

      debugPrint('📡 Debug info:');
      debugPrint(
        '  - Token: ${token != null ? "Present (${token.length} chars)" : "NULL"}');
      debugPrint('  - UserId: $userId');
      debugPrint('  - AppSettings userId: ${appSettings.userId}');
      debugPrint('  - UserData username: ${userData?['username']}');

      if (userId == null) {
        throw Exception('User ID not found');
      }

      if (token == null || token.isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.authRequiredLogin ?? AppLocalizations.of(context)!.tr('Authentication required. Please logout and login again to change your password.'));
        return;
      }

      final requestData = {
        'userId': userId,
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      };

      debugPrint(
        '📡 Sending password change request: ${json.encode({'userId': userId, 'currentPassword': '***', 'newPassword': '***'})}');

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(requestData));

      debugPrint('📡 Password change response: ${response.statusCode}');
      debugPrint('📡 Password change response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          Navigator.pop(context);
          TopNotification.success(
            context,
            AppLocalizations.of(context)?.passwordChangedSuccess ?? AppLocalizations.of(context)!.tr('Password changed successfully!'));
          debugPrint('✅ Password changed successfully in database');
        } else {
          TopNotification.error(
            context,
            responseData['message'] ??
                (AppLocalizations.of(context)?.failedToChangePassword ?? AppLocalizations.of(context)!.tr('Failed to change password')));
          debugPrint('❌ Password change failed: ${responseData['message']}');
        }
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToChangePasswordRetry ?? AppLocalizations.of(context)!.tr('Failed to change password. Please try again.'));
        debugPrint('❌ Password change failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error changing password: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorChangingPassword ?? AppLocalizations.of(context)!.tr('Error changing password')}: $e');
    }
  }

  void _showActiveSessionsModal(BuildContext context, bool isLight) async {
    // Load real active sessions from API
    List<Map<String, dynamic>> sessions = [];
    bool isLoading = true;
    String? errorMessage;

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.8,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          // Load sessions when modal opens
          if (isLoading) {
            _loadActiveSessions()
                .then((loadedSessions) {
                  setModalState(() {
                    sessions = loadedSessions;
                    isLoading = false;
                  });
                })
                .catchError((error) {
                  setModalState(() {
                    errorMessage = error.toString();
                    isLoading = false;
                  });
                });
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DragHandle(),
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.desktopcomputer,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.activeSessions ?? AppLocalizations.of(context)!.tr('Active Sessions'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4)),
                ]),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              SizedBox(height: 6),

              Text(
                AppLocalizations.of(context)?.manageSignedIn ??
                    AppLocalizations.of(context)!.tr("Manage where you're signed in"),
                style: TextStyle(
                  fontSize: 15,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.5))),

              SizedBox(height: 32),

              Expanded(
                child: isLoading
                    ? Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CultiooLoadingIndicator(size: 20)))
                    : errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.exclamationmark_circle,
                                size: 40,
                                color: Colors.red),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                              Text(
                                AppLocalizations.of(
                                      context)?.failedToLoadSessions ?? AppLocalizations.of(context)!.tr('Failed to load sessions'),
                                style: TextStyle(
                                  color: isLight ? Colors.black : Colors.white,
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w600)),
                            ])))
                    : sessions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.device_laptop,
                                size: 40,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.3)),
                              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                              Text(
                                AppLocalizations.of(
                                      context)?.noActiveSessions ?? AppLocalizations.of(context)!.tr('No active sessions'),
                                style: TextStyle(
                                  color: isLight ? Colors.black : Colors.white,
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(
                                      context)?.noOtherActiveSessions ?? AppLocalizations.of(context)!.tr('You have no other active sessions'),
                                style: TextStyle(
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5),
                                  fontSize: DesktopOptimizedWidgets.getFontSize())),
                            ])))
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          return _buildActiveSessionItem(
                            session,
                            isLight,
                            setModalState);
                        })),
            ]);
        }));
  }

  Future<List<Map<String, dynamic>>> _loadLoginHistory() async {
    try {
      final token = await _getStoredToken();

      if (token == null) {
        debugPrint('❌ No auth token found for login history');
        return [];
      }

      debugPrint('📊 Loading login history from API...');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/login-history'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

      debugPrint('📡 Login history response: ${response.statusCode}');
      debugPrint('📡 Login history response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true &&
            responseData['loginHistory'] != null) {
          final List<dynamic> activities = responseData['loginHistory'];

          debugPrint('📊 Processing ${activities.length} login history entries');

          return activities
              .map((activity) {
                final loginData = {
                  'date': _formatLoginDate(activity['loginTime']),
                  'time': _formatLoginTime(activity['loginTime']),
                  'device': _extractDeviceFromUserAgent(
                    activity['userAgent'] ??
                        (AppLocalizations.of(context)?.unknown ??
                            AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown'))),
                  'location':
                      AppLocalizations.of(context)?.unknownLocation ??
                      AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown'), // Default location since not in login_history table
                  'ip':
                      AppLocalizations.of(context)?.hidden ?? AppLocalizations.of(context)!.tr('Hidden'), // IP not stored in login_history table
                  'method': _extractLoginMethodFromUserAgent(
                    activity['userAgent'] ?? AppLocalizations.of(context)!.tr('')),
                  'status':
                      'success', // login_history only stores successful logins
                  'failureReason': null,
                };

                debugPrint('📊 Mapped login entry: $loginData');
                return loginData;
              })
              .cast<Map<String, dynamic>>()
              .toList();
        }
      }

      return [];
    } catch (e) {
      debugPrint('❌ Error loading login history: $e');
      return [];
    }
  }

  String _formatLoginDate(String? dateTimeString) {
    if (dateTimeString == null) {
      return AppLocalizations.of(context)?.unknownDate ?? AppLocalizations.of(context)!.tr('Unknown Date');
    }
    try {
      final dateTime = DateTime.parse(dateTimeString);
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      return appSettings.formatDate(dateTime);
    } catch (e) {
      return AppLocalizations.of(context)?.unknownDate ?? AppLocalizations.of(context)!.tr('Unknown Date');
    }
  }

  String _formatLoginTime(String? dateTimeString) {
    if (dateTimeString == null) {
      return AppLocalizations.of(context)?.unknownTime ?? AppLocalizations.of(context)!.tr('Unknown Time');
    }
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return AppLocalizations.of(context)?.unknownTime ?? AppLocalizations.of(context)!.tr('Unknown Time');
    }
  }

  String _getMonthName(int month) {
    if (month < 1 || month > 12) {
      return AppLocalizations.of(context)?.unknownTime ??
          AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown');
    }
    try {
      final locale = Localizations.localeOf(context).languageCode;
      final date = DateTime(2024, month, 1);
      return DateFormat.MMMM(locale).format(date);
    } catch (e) {
      const months = [
        '',
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return months[month];
    }
  }

  String _extractDeviceFromUserAgent(String userAgent) {
    if (userAgent.isEmpty) {
      return AppLocalizations.of(context)?.unknownDevice ?? AppLocalizations.of(context)!.tr('Unknown Device');
    }

    final ua = userAgent.toLowerCase();

    // iPhone models
    if (ua.contains('iphone')) {
      if (ua.contains('iphone 15')) return 'iPhone 15';
      if (ua.contains('iphone 14')) return 'iPhone 14';
      if (ua.contains('iphone 13')) return 'iPhone 13';
      if (ua.contains('iphone 12')) return 'iPhone 12';
      if (ua.contains('iphone 11')) return 'iPhone 11';
      return 'iPhone';
    }

    // iPad models
    if (ua.contains('ipad')) {
      if (ua.contains('ipad pro')) return 'iPad Pro';
      if (ua.contains('ipad air')) return 'iPad Air';
      if (ua.contains('ipad mini')) return 'iPad Mini';
      return 'iPad';
    }

    // Android devices
    if (ua.contains('android')) {
      return AppLocalizations.of(context)?.androidDevice ?? AppLocalizations.of(context)!.tr('Android Device');
    }

    // Mac detection
    if (ua.contains('macintosh') ||
        ua.contains('mac os x') ||
        ua.contains('macos')) {
      if (ua.contains('macbook pro')) return 'MacBook Pro';
      if (ua.contains('macbook air')) return 'MacBook Air';
      if (ua.contains('imac')) return 'iMac';
      if (ua.contains('mac mini')) return 'Mac mini';
      return AppLocalizations.of(context)?.macBookiMac ?? AppLocalizations.of(context)!.tr('MacBook/iMac');
    }

    // Windows PC
    if (ua.contains('windows') ||
        ua.contains('win32') ||
        ua.contains('win64')) {
      return AppLocalizations.of(context)?.windowsPC ?? AppLocalizations.of(context)!.tr('Windows PC');
    }

    // Linux
    if (ua.contains('linux') || ua.contains('x11')) {
      return AppLocalizations.of(context)?.linuxSystem ?? AppLocalizations.of(context)!.tr('Linux System');
    }

    // Browsers
    if (ua.contains('chrome')) {
      return AppLocalizations.of(context)?.chromeBrowser ?? AppLocalizations.of(context)!.tr('Chrome Browser');
    }
    if (ua.contains('firefox')) {
      return AppLocalizations.of(context)?.firefoxBrowser ?? AppLocalizations.of(context)!.tr('Firefox Browser');
    }
    if (ua.contains('safari')) {
      return AppLocalizations.of(context)?.safariBrowser ?? AppLocalizations.of(context)!.tr('Safari Browser');
    }
    if (ua.contains('edge')) {
      return 'Edge Browser';
    }

    // API Client
    if (ua.contains('curl')) {
      return AppLocalizations.of(context)?.apiClient ?? AppLocalizations.of(context)!.tr('API Client');
    }

    return AppLocalizations.of(context)?.unknownDevice ?? AppLocalizations.of(context)!.tr('Unknown Device');
  }

  String _extractLoginMethodFromUserAgent(String userAgent) {
    if (userAgent.contains('(auto-login)')) {
      return 'auto-login';
    } else if (userAgent.contains('2fa')) {
      return '2fa';
    } else if (userAgent.contains('biometric')) {
      return 'biometric';
    } else {
      return 'password';
    }
  }

  Future<List<Map<String, dynamic>>> _loadActiveSessions() async {
    try {
      final token = await _getStoredToken();

      if (token == null) {
        debugPrint('❌ No auth token found for active sessions');
        throw Exception('Authentication required');
      }

      debugPrint('📊 Loading active sessions from login history API...');

      // Use login history as active sessions for now
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/login-history'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

      debugPrint('📡 Login history response: ${response.statusCode}');
      debugPrint('📡 Login history response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true &&
            responseData['loginHistory'] != null) {
          final List<dynamic> loginHistory = responseData['loginHistory'];

          debugPrint(
            '📊 Processing ${loginHistory.length} login entries as active sessions');

          // Convert recent login history to session-like data
          return loginHistory.take(5).map<Map<String, dynamic>>((login) {
            final userAgent =
                login['userAgent'] ??
                AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown');
            final device = _extractDeviceFromUserAgent(userAgent);
            final browser = _extractBrowserFromUserAgent(userAgent);
            final os = _extractOSFromUserAgent(userAgent);
            final isMobile =
                userAgent.contains('Mobile') ||
                userAgent.contains('Android') ||
                userAgent.contains('iPhone');

            return {
              'id': login['id'],
              'device': '$device - $browser',
              'browser': browser,
              'os': os,
              'location':
                  AppLocalizations.of(context)?.unknownLocation ?? AppLocalizations.of(context)!.tr('Unknown Location'), // We don't have location data
              'ip': userAgent.contains('curl')
                  ? (AppLocalizations.of(context)?.apiClient ?? AppLocalizations.of(context)!.tr('API Client'))
                  : (AppLocalizations.of(context)?.unknownIP ?? AppLocalizations.of(context)!.tr('Unknown IP')),
              'lastActive': _formatSessionTime(login['loginTime']),
              'current':
                  loginHistory.indexOf(login) ==
                  0, // Mark most recent as current
              'isMobile': isMobile,
              'createdAt': login['loginTime'],
              'lastActivity': login['loginTime'],
            };
          }).toList();
        }
      }

      throw Exception('Failed to load active sessions');
    } catch (e) {
      debugPrint('❌ Error loading active sessions: $e');
      rethrow;
    }
  }

  String _extractBrowserFromUserAgent(String userAgent) {
    if (userAgent.contains('Chrome')) return 'Chrome';
    if (userAgent.contains('Firefox')) return 'Firefox';
    if (userAgent.contains('Safari') && !userAgent.contains('Chrome')) {
      return 'Safari';
    }
    if (userAgent.contains('Edge')) return 'Edge';
    if (userAgent.contains('curl')) {
      return AppLocalizations.of(context)?.apiClient ?? AppLocalizations.of(context)!.tr('API Client');
    }
    return AppLocalizations.of(context)?.unknownBrowser ?? AppLocalizations.of(context)!.tr('Unknown Browser');
  }

  String _extractOSFromUserAgent(String userAgent) {
    if (userAgent.isEmpty) {
      return AppLocalizations.of(context)?.unknownOS ?? AppLocalizations.of(context)!.tr('Unknown OS');
    }

    final ua = userAgent.toLowerCase();

    // iOS detection (iPhone, iPad, iPod)
    if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
      return 'iOS';
    }

    // Android detection
    if (ua.contains('android')) {
      return 'Android';
    }

    // macOS detection (multiple patterns)
    if (ua.contains('macintosh') ||
        ua.contains('mac os x') ||
        ua.contains('macos')) {
      return 'macOS';
    }

    // Windows detection (multiple patterns)
    if (ua.contains('windows') ||
        ua.contains('win32') ||
        ua.contains('win64')) {
      return 'Windows';
    }

    // Linux detection (multiple patterns)
    if (ua.contains('linux') || ua.contains('x11')) {
      return 'Linux';
    }

    // Chrome OS
    if (ua.contains('cros')) {
      return 'Chrome OS';
    }

    // Web browser without OS info - try to detect from browser
    if (ua.contains('curl')) {
      return AppLocalizations.of(context)?.apiClient ?? AppLocalizations.of(context)!.tr('API Client');
    }

    return AppLocalizations.of(context)?.unknownOS ?? AppLocalizations.of(context)!.tr('Unknown OS');
  }

  String _formatSessionTime(String? dateTimeString) {
    if (dateTimeString == null) {
      return AppLocalizations.of(context)?.unknownTime ?? AppLocalizations.of(context)!.tr('Unknown time');
    }
    try {
      final dateTime = DateTime.parse(dateTimeString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return AppLocalizations.of(context)?.justNow ?? AppLocalizations.of(context)!.tr('Just now');
      }
      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} ${AppLocalizations.of(context)?.minutesAgo ?? AppLocalizations.of(context)!.tr('minutes ago')}';
      }
      if (difference.inHours < 24) {
        return '${difference.inHours} ${AppLocalizations.of(context)?.hoursAgo ?? AppLocalizations.of(context)!.tr('hours ago')}';
      }
      return '${difference.inDays} ${AppLocalizations.of(context)?.daysAgo ?? AppLocalizations.of(context)!.tr('days ago')}';
    } catch (e) {
      return AppLocalizations.of(context)?.unknownTime ?? AppLocalizations.of(context)!.tr('Unknown time');
    }
  }

  Widget _buildActiveSessionItem(
    Map<String, dynamic> session,
    bool isLight,
    StateSetter setModalState) {
    final isCurrent = session['current'] == true;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCurrent
            ? CupertinoColors.systemGreen.withValues(alpha: 0.1)
            : (isLight ? Colors.black : Colors.white).withOpacity(0.04),
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Row(
        children: [
          Icon(
            session['isMobile'] == true
                ? CupertinoIcons.device_phone_portrait
                : CupertinoIcons.desktopcomputer,
            color: isCurrent
                ? CupertinoColors.systemGreen
                : (isLight ? Colors.black : Colors.white).withOpacity(0.5),
            size: 22),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session['device'] ??
                            (AppLocalizations.of(context)?.unknownDevice ?? AppLocalizations.of(context)!.tr('Unknown Device')),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white))),
                    if (isCurrent)
                      Text(
                        AppLocalizations.of(context)?.current ?? AppLocalizations.of(context)!.tr('Current'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemGreen)),
                  ]),
                SizedBox(height: 2),
                Text(
                  '${session['device']} • ${session['os']}',
                  style: TextStyle(
                    fontSize: 13,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.6))),
                Text(
                  '${AppLocalizations.of(context)?.lastActive ?? AppLocalizations.of(context)!.tr('Last active')}: ${session['lastActive']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.4))),
              ])),
          if (!isCurrent)
            TradeRepublicTap(
              onTap: () {
                HapticFeedback.lightImpact();
                _terminateSession(session['id'], setModalState);
              },
              child: Icon(
                CupertinoIcons.square_arrow_right,
                color: Colors.red,
                size: 20)),
        ]));
  }

  Future<void> _terminateSession(
    int sessionId,
    StateSetter setModalState) async {
    try {
      final token = await _getStoredToken();

      if (token == null) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.authRequired ?? AppLocalizations.of(context)!.tr('Authentication required'));
        return;
      }

      debugPrint('🔒 Terminating session: $sessionId');

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/active-sessions/$sessionId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

      debugPrint('📡 Terminate session response: ${response.statusCode}');

      if (response.statusCode == 200) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.sessionTerminated ?? AppLocalizations.of(context)!.tr('Session terminated successfully'));

        // Reload sessions
        _loadActiveSessions().then((loadedSessions) {
          setModalState(() {
            // This will trigger a rebuild with updated sessions
          });
        });
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedTerminateSession ?? AppLocalizations.of(context)!.tr('Failed to terminate session'));
      }
    } catch (e) {
      debugPrint('❌ Error terminating session: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorTerminatingSession ?? AppLocalizations.of(context)!.tr('Error terminating session')}: $e');
    }
  }

  void _showLoginHistoryModal(BuildContext context, bool isLight) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.clock_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.loginHistory ?? AppLocalizations.of(context)!.tr('Login History'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 6),

          Text(
            AppLocalizations.of(context)?.recentLoginActivity ?? AppLocalizations.of(context)!.tr('Recent login activity on your account'),
            style: TextStyle(
              fontSize: 15,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),

          SizedBox(height: 32),

          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadLoginHistory(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CultiooLoadingIndicator(size: 20)));
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context)?.errorLoadingLoginHistory ?? AppLocalizations.of(context)!.tr('Error loading login history'),
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))));
                }

                final loginHistory = snapshot.data ?? [];

                if (loginHistory.isEmpty) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context)?.noLoginHistoryAvailable ?? AppLocalizations.of(context)!.tr('No login history available'),
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))));
                }

                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: loginHistory.length,
                  itemBuilder: (context, index) {
                    final login = loginHistory[index];
                    final isSuccess = login['status'] == 'success';

                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSuccess
                            ? (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.04)
                            : Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                      child: Row(
                        children: [
                          Icon(
                            isSuccess ? Icons.check_circle : Icons.error,
                            size: 22,
                            color: isSuccess ? Colors.green : Colors.red),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        login['device'].toString(),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: isLight
                                              ? Colors.black
                                              : Colors.white),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                                    Text(
                                      '${login['date']} ${login['time']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.4))),
                                  ]),
                                SizedBox(height: 2),
                                Text(
                                  '${login['location']} • ${isSuccess ? (AppLocalizations.of(context)?.successful ?? AppLocalizations.of(context)!.tr('Successful')) : (AppLocalizations.of(context)?.failed ?? AppLocalizations.of(context)!.tr('Failed'))}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.5))),
                              ])),
                        ]));
                  });
              })),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  void _showDeleteAccountModal(BuildContext context, bool isLight) {
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.65,
      child: StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DragHandle(),
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.trash_fill,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.deleteAccount ?? AppLocalizations.of(context)!.tr('Delete Account'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4)),
                ]),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Subtitle
              Text(
                AppLocalizations.of(context)?.thisActionCannotBeUndone ?? AppLocalizations.of(context)!.tr('This action cannot be undone'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.5))),

              SizedBox(height: 32),

              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Warning text - minimalist
                      Text(
                        AppLocalizations.of(context)?.allDataWillBeDeleted ?? AppLocalizations.of(context)!.tr('All your data, orders, and documents will be permanently deleted.'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.6))),

                      SizedBox(height: 32),

                      // Password field - minimalist
                      Text(
                        AppLocalizations.of(
                              context)?.confirmPasswordHintDelete ?? AppLocalizations.of(context)!.tr('Confirm password'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5))),

                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      TradeRepublicTextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w500,
                          color: isLight ? Colors.black : Colors.white),
                        hintText:
                            AppLocalizations.of(context)?.password ?? AppLocalizations.of(context)!.tr('Password'),
                        suffixIcon: TradeRepublicButton.icon(
                          size: 36,
                          isSecondary: true,
                          foregroundColor: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4),
                          icon: Icon(
                            obscurePassword
                                ? CupertinoIcons.eye_slash
                                : CupertinoIcons.eye_fill,
                            size: 20),
                          onPressed: () => setModalState(
                            () => obscurePassword = !obscurePassword)),
                        filled: true,
                        fillColor: isLight ? Colors.white : Colors.black),
                    ]))),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              // Delete button - minimalist red
              TradeRepublicButton(
                label:
                    AppLocalizations.of(context)?.deleteAccount ?? AppLocalizations.of(context)!.tr('Delete Account'),
                isDestructive: true,
                height: 50,
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  _deleteAccount(passwordController.text);
                }),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

              // Cancel button - minimalist
              TradeRepublicButton(
                label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                isSecondary: true,
                height: 50,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  passwordController.dispose();
                  Navigator.pop(context);
                }),
            ])))).whenComplete(() => NavigationVisibility.show());
  }

  Future<void> _deleteAccount(String password) async {
    if (password.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.enterPassword ?? AppLocalizations.of(context)!.tr('Please enter your password'));
      return;
    }

    debugPrint('🗑️ Starting account deletion process...');

    try {
      final token = await _getStoredToken();

      if (token == null || token.isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.authRequiredLoginAgain ?? AppLocalizations.of(context)!.tr('Authentication required. Please login again.'));
        return;
      }

      // Show loading notification
      Navigator.pop(context); // Close modal first
      TopNotification.info(
        context,
        AppLocalizations.of(context)?.verifyingPassword ?? AppLocalizations.of(context)!.tr('Verifying password and deleting account...'));

      final requestData = {'password': password};

      debugPrint('📡 Sending account deletion request');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/account-delete'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(requestData));

      debugPrint('📡 Account deletion response: ${response.statusCode}');
      debugPrint('📡 Account deletion response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          debugPrint(
            '✅ Account deleted successfully: ${responseData['deletedUser']}');

          // Clear all stored data
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();

          debugPrint('✅ All user data cleared from device');

          TopNotification.success(
            context,
            AppLocalizations.of(context)?.accountDeletedSuccess ?? AppLocalizations.of(context)!.tr('Account deleted successfully. Goodbye!'));

          // Navigate to login or home screen
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        } else {
          debugPrint('❌ Account deletion failed: ${responseData['message']}');
          TopNotification.error(
            context,
            responseData['message'] ??
                (AppLocalizations.of(context)?.failedToDeleteAccount ?? AppLocalizations.of(context)!.tr('Failed to delete account')));
        }
      } else if (response.statusCode == 401) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.incorrectPassword ?? AppLocalizations.of(context)!.tr('Incorrect password. Please try again.'));
      } else if (response.statusCode == 404) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.userNotFound ?? AppLocalizations.of(context)!.tr('User not found. Please contact support.'));
      } else {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedDeleteAccount ?? AppLocalizations.of(context)!.tr('Failed to delete account. Please try again.'));
        debugPrint('❌ Account deletion failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error during account deletion: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorDeletingAccount ?? AppLocalizations.of(context)!.tr('Error deleting account')}: $e');
    }
  }

  void _show2FASetupModal(
    BuildContext context,
    StateSetter parentSetModalState) {
    final twoFACodeController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    NavigationVisibility.hide();

    final AppSettings appSettings = AppSettings();
    final isLight = appSettings.isLightMode(context);

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Sheet header: Icon left + Title ──
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.shield_fill,
                        size: 22,
                        color: isLight ? Colors.black : Colors.white),
                      SizedBox(width: 12),
                      Text(
                        AppLocalizations.of(context)?.enable2FA ?? AppLocalizations.of(context)!.tr('Two-Factor Authentication'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.4)),
                    ]),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                  Text(
                    AppLocalizations.of(context)?.addExtraLayerSecurity ?? AppLocalizations.of(context)!.tr('Add an extra layer of security to your account.'),
                    style: TextStyle(
                      fontSize: 15,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5))),

                  SizedBox(height: 32),

                  // 2FA Code Input
                  Text(
                    AppLocalizations.of(context)?.twoFACode ?? AppLocalizations.of(context)!.tr('2FA Code (8 digits)'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.7))),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  TradeRepublicTextField(
                    controller: twoFACodeController,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w600),
                    hintText: AppLocalizations.of(context)!.tr('12345678') ?? AppLocalizations.of(context)!.tr('12345678'),
                    filled: true,
                    fillColor: (isLight ? Colors.black : Colors.white)
                        .withOpacity(0.04),
                    counterText: ''),

                  SizedBox(height: 20),

                  // Password Confirmation
                  Text(
                    AppLocalizations.of(context)?.confirmPassword ?? AppLocalizations.of(context)!.tr('Confirm Password'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.7))),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  TradeRepublicTextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      color: isLight ? Colors.black : Colors.white),
                    hintText:
                        AppLocalizations.of(context)?.enterPassword ?? AppLocalizations.of(context)!.tr('Enter your password'),
                    suffixIcon: TradeRepublicButton.icon(
                      size: 36,
                      isSecondary: true,
                      foregroundColor: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      onPressed: () {
                        setModalState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                      icon: Icon(
                        obscurePassword
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        size: 20)),
                    filled: true,
                    fillColor: (isLight ? Colors.black : Colors.white)
                        .withOpacity(0.04)),

                  const Spacer(),

                  // Enable button
                  TradeRepublicButton(
                    label:
                        AppLocalizations.of(context)?.enable2FA ?? AppLocalizations.of(context)!.tr('Enable 2FA'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _enable2FA(
                        twoFACodeController.text,
                        passwordController.text,
                        parentSetModalState,
                        twoFACodeController,
                        passwordController);
                    }),

                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                  // Cancel button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        try {
                          twoFACodeController.dispose();
                          passwordController.dispose();
                        } catch (e) {}
                      });
                    }),

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ])),
          ]))).whenComplete(() => NavigationVisibility.show());
  }

  Future<void> _enable2FA(
    String code,
    String password,
    StateSetter parentSetModalState,
    TextEditingController codeController,
    TextEditingController passwordController) async {
    debugPrint(
      '🔐 _enable2FA called with code: "$code", password length: ${password.length}');

    // Validate inputs
    if (code.isEmpty || code.length != 8) {
      debugPrint('❌ Invalid code: empty=${code.isEmpty}, length=${code.length}');
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.enter2FACode ?? AppLocalizations.of(context)!.tr('Please enter a valid 8-digit 2FA code'));
      return;
    }

    if (password.isEmpty) {
      debugPrint('❌ Password is empty');
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.pleaseEnterYourPassword ?? AppLocalizations.of(context)!.tr('Please enter your password'));
      return;
    }

    // Check if code contains only numbers
    if (!RegExp(r'^[0-9]+$').hasMatch(code)) {
      debugPrint('❌ Code contains non-numeric characters: "$code"');
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.enter2FACodeNumbers ?? AppLocalizations.of(context)!.tr('2FA code must contain only numbers'));
      return;
    }

    debugPrint('✅ Validation passed, sending update request...');

    try {
      final updatedData = {'has_2fa_enabled': 1, 'twofa': code};

      debugPrint('📡 Calling _updateUserData with: $updatedData');
      await _updateUserData(updatedData);

      debugPrint('✅ _updateUserData completed successfully');

      parentSetModalState(() {
        userData!['has_2fa_enabled'] = 1;
        userData!['twofa'] = code;
      });

      debugPrint(
        '✅ Local userData updated: has_2fa_enabled=${userData!['has_2fa_enabled']}, twofa=${userData!['twofa']}');

      // Close modal first, then cleanup
      Navigator.pop(context);

      // Cleanup controllers after modal is closed
      Future.delayed(Duration(milliseconds: 100), () {
        try {
          codeController.dispose();
          passwordController.dispose();
        } catch (e) {
          debugPrint('⚠️ Controller disposal error (safe to ignore): $e');
        }
      });

      TopNotification.success(
        context,
        AppLocalizations.of(context)?.twoFAEnabledSuccess ?? AppLocalizations.of(context)!.tr('2FA enabled successfully!'));
    } catch (e) {
      debugPrint('❌ Error in _enable2FA: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.failedEnable2FA ?? AppLocalizations.of(context)!.tr('Failed to enable 2FA settings')}: $e');
    }
  }

  Future<void> _performSignOut() async {
    try {
      debugPrint('🔓 Starting sign out process...');

      // Close the modal first
      Navigator.pop(context);

      // Show loading notification
      TopNotification.info(
        context,
        AppLocalizations.of(context)?.signingOut ?? AppLocalizations.of(context)!.tr('Signing out...'));

      final token = await _getStoredToken();

      if (token != null) {
        // Call logout API to invalidate session on server
        try {
          debugPrint('📡 Calling logout API to invalidate server session...');

          final response = await http.post(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            });

          debugPrint('📡 Logout API response: ${response.statusCode}');
          debugPrint('📡 Logout API response body: ${response.body}');

          if (response.statusCode == 200) {
            final responseData = json.decode(response.body);
            if (responseData['success'] == true) {
              debugPrint('✅ Server session invalidated successfully');
            } else {
              debugPrint('⚠️ Server logout response: ${responseData['message']}');
            }
          } else {
            debugPrint(
              '⚠️ Server logout failed with status: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint(
            '⚠️ Error calling logout API (continuing with local logout): $e');
        }
      }

      // Clear all local data
      debugPrint('🗑️ Clearing local user data...');

      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('✅ SharedPreferences cleared');

      // Clear app settings if available
      try {
        // Reset app settings to default values (if methods exist)
        debugPrint('✅ App settings reset attempted');
      } catch (e) {
        debugPrint('⚠️ Could not reset app settings: $e');
      }

      // Clear local state
      if (mounted) {
        setState(() {
          userData = null;
          businessStats = {};
          isLoading = false;
        });
      }

      debugPrint('✅ Local data cleared successfully');

      // Navigate to login page and clear navigation stack immediately
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      debugPrint('❌ Error during sign out: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorSigningOut ?? AppLocalizations.of(context)!.tr('Error signing out')}: $e');
    }
  }

  // Business Logo Upload Methods
  Future<void> _uploadProfilePicture(
    BuildContext context,
    ImageSource source) async {
    debugPrint('📸 Starting business logo upload from source: $source');

    // Close modal immediately and work with stored context
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85);

      debugPrint('📸 Image picker result: ${image?.path ?? AppLocalizations.of(context)!.tr('null')}');

      if (image == null) {
        debugPrint('⚠️ Image selection cancelled by user');
        return;
      }

      // Validate file size (5MB limit)
      final file = File(image.path);
      final fileSizeInBytes = await file.length();
      final fileSizeInMB = fileSizeInBytes / (1024 * 1024);

      debugPrint('📊 Image file size: ${fileSizeInMB.toStringAsFixed(2)} MB');

      if (fileSizeInMB > 5) {
        debugPrint('❌ Image file too large: ${fileSizeInMB.toStringAsFixed(2)} MB');
        _showSafeNotification(
          'Image size must be less than 5MB',
          isError: true);
        return;
      }

      // Show uploading notification
      debugPrint('📤 Starting image upload to server...');
      _showSafeNotification(
        AppLocalizations.of(context)?.uploadingLogo ?? AppLocalizations.of(context)!.tr('Uploading business logo...'),
        isInfo: true);

      // Upload to server
      final uploadResult = await _uploadImageToServer(file);

      debugPrint('📡 Upload result: $uploadResult');

      if (uploadResult['success'] == true) {
        final logoUrl = uploadResult['imageUrl'];
        debugPrint('✅ Logo uploaded successfully: $logoUrl');

        // The upload endpoint already updated the database, so just reload user data
        await _loadUserData();

        _showSafeNotification(
          AppLocalizations.of(context)?.logoUploadedSuccess ?? AppLocalizations.of(context)!.tr('Business logo uploaded successfully!'));
      } else {
        final errorMsg =
            uploadResult['error'] ??
            (AppLocalizations.of(context)?.unknownError ?? AppLocalizations.of(context)!.tr('Unknown error'));
        debugPrint('❌ Logo upload failed: $errorMsg');

        // Check if authentication is the issue
        if (uploadResult['needsLogin'] == true) {
          // Clear stored token since it's invalid
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('auth_token');
          debugPrint('🗑️ Cleared invalid token from storage');

          // Show session expired dialog
          if (mounted) {
            _showSessionExpiredDialog();
          }
        } else {
          _showSafeNotification(
            '${AppLocalizations.of(context)?.failedToUploadLogo ?? AppLocalizations.of(context)!.tr('Failed to upload logo')}: $errorMsg',
            isError: true);
        }
      }
    } catch (e) {
      debugPrint('❌ Error uploading business logo: $e');
      _showSafeNotification(
        '${AppLocalizations.of(context)?.errorUploadingLogo ?? AppLocalizations.of(context)!.tr('Error uploading logo')}: $e',
        isError: true);
    }
  }

  Future<Map<String, dynamic>> _uploadImageToServer(File imageFile) async {
    try {
      final token = await _getStoredToken();

      if (token == null || token.isEmpty) {
        debugPrint('❌ No authentication token available');
        return {
          'success': false,
          'error':
              AppLocalizations.of(context)?.authRequiredPleaseLogin ?? AppLocalizations.of(context)!.tr('Authentication required - please log in again'),
        };
      }

      debugPrint('📤 Uploading image to server: ${imageFile.path}');
      final tokenPreviewLength = token.length < 20 ? token.length : 20;
      debugPrint('🔑 Using token: ${token.substring(0, tokenPreviewLength)}...');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/business/upload-logo'));

      request.headers.addAll({'Authorization': 'Bearer $token'});

      final imageBytes = await imageFile.readAsBytes();

      request.files.add(
        http.MultipartFile.fromBytes(
          'businessLogo',
          imageBytes,
          filename: imageFile.path.split('/').last,
          contentType: MediaType('image', _getImageExtension(imageFile.path))));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('📡 Upload response: ${response.statusCode}');
      debugPrint('📡 Upload response body: ${response.body}');

      if (response.statusCode == 401 || response.statusCode == 403) {
        // Token expired or invalid - show specific error
        return {
          'success': false,
          'error':
              AppLocalizations.of(context)?.sessionExpiredPleaseLogin ?? AppLocalizations.of(context)!.tr('Session expired - please log in again'),
          'needsLogin': true,
        };
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true) {
          return {'success': true, 'imageUrl': responseData['imageUrl']};
        } else {
          return {
            'success': false,
            'error':
                responseData['message'] ??
                (AppLocalizations.of(context)?.uploadFailed ?? AppLocalizations.of(context)!.tr('Upload failed')),
          };
        }
      } else {
        return {
          'success': false,
          'error':
              '${AppLocalizations.of(context)?.serverError ?? AppLocalizations.of(context)!.tr('Server error')}: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ Error uploading to server: $e');
      return {
        'success': false,
        'error':
            '${AppLocalizations.of(context)?.networkError ?? AppLocalizations.of(context)!.tr('Network error')}: $e',
      };
    }
  }

  Future<void> _removeProfilePicture(BuildContext context) async {
    debugPrint('🗑️ Starting business logo removal...');

    // Close modal immediately
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    try {
      // Update user data to remove logo
      final updatedData = {'profilePic': null};

      debugPrint('📡 Updating user data to remove logo...');
      _showSafeNotification(
        AppLocalizations.of(context)?.removingLogo ?? AppLocalizations.of(context)!.tr('Removing business logo...'),
        isInfo: true);

      await _updateUserData(updatedData);

      // Reload user data to reflect changes
      await _loadUserData();

      debugPrint('✅ Business logo removed successfully');
      _showSafeNotification(
        AppLocalizations.of(context)?.logoRemovedSuccess ?? AppLocalizations.of(context)!.tr('Business logo removed successfully!'));
    } catch (e) {
      debugPrint('❌ Error removing business logo: $e');
      _showSafeNotification(
        '${AppLocalizations.of(context)?.errorRemovingLogo ?? AppLocalizations.of(context)!.tr('Error removing logo')}: $e',
        isError: true);
    }
  }

  // Helper method to get image extension from file path
  String _getImageExtension(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'jpeg';
      case 'png':
        return 'png';
      case 'gif':
        return 'gif';
      case 'webp':
        return 'webp';
      default:
        return 'jpeg'; // Default fallback
    }
  }

  // Group Management Methods
  void _showGroupSettingsModal(BuildContext context, bool isLight) {
    if (currentGroup == null) return;

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.gear,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.groupSettings ?? AppLocalizations.of(context)!.tr('Group Settings'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 20),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  // Group Header with info
                  _buildGroupSettingsHeader(isLight),

                  SizedBox(height: 20),

                  // Group Details Section
                  _buildGroupSettingsSection(
                    AppLocalizations.of(context)?.groupDetails ?? AppLocalizations.of(context)!.tr('Group Details'),
                    [
                      if (currentGroup?['description'] != null &&
                          currentGroup!['description'].toString().isNotEmpty)
                        _buildGroupSettingsOption(
                          icon: CupertinoIcons.doc_text,
                          title:
                              AppLocalizations.of(context)?.description ?? AppLocalizations.of(context)!.tr('Description'),
                          subtitle: currentGroup!['description'].toString(),
                          isLight: isLight,
                          onTap: () {}),
                      if (currentGroup?['website'] != null &&
                          currentGroup!['website'].toString().isNotEmpty)
                        _buildGroupSettingsOption(
                          icon: CupertinoIcons.globe,
                          title:
                              AppLocalizations.of(context)?.website ?? AppLocalizations.of(context)!.tr('Website'),
                          subtitle: currentGroup!['website'].toString(),
                          isLight: isLight,
                          onTap: () {}),
                      _buildGroupSettingsOption(
                        icon: CupertinoIcons.calendar,
                        title:
                            AppLocalizations.of(context)?.created ?? AppLocalizations.of(context)!.tr('Created'),
                        subtitle:
                            _formatDate(
                              currentGroup?['createdAt']?.toString()) ??
                            AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown'),
                        isLight: isLight,
                        onTap: () {}),
                    ],
                    isLight),

                  SizedBox(height: 20),

                  // Members Section
                  _buildGroupSettingsSection(
                    AppLocalizations.of(context)?.members ?? AppLocalizations.of(context)!.tr('Members'),
                    [_buildGroupMembersOption(isLight)],
                    isLight),

                  SizedBox(height: 20),

                  // Admin Actions
                  if (_isCurrentGroupAdmin) ...[
                    _buildGroupSettingsSection(
                      AppLocalizations.of(context)?.ownerActions ?? AppLocalizations.of(context)!.tr('Admin Actions'),
                      [
                        _buildGroupSettingsOption(
                          icon: CupertinoIcons.photo_fill_on_rectangle_fill,
                          title: AppLocalizations.of(context)!.tr('Update Group Image') ?? AppLocalizations.of(context)!.tr('Update Group Image'),
                          subtitle: AppLocalizations.of(context)!.tr('Upload a new profile image for this group') ?? AppLocalizations.of(context)!.tr('Upload a new profile image for this group'),
                          isLight: isLight,
                          onTap: () => _showGroupProfileImageOptions(
                            context,
                            isLight,
                            (_) {},
                            (path) {
                              if (path != null && path.isNotEmpty) {
                                _uploadGroupProfileImage(path);
                              }
                            }),
                          color: Colors.blue),
                        _buildGroupSettingsOption(
                          icon: CupertinoIcons.arrow_right_arrow_left,
                          title:
                              AppLocalizations.of(context)?.transferOwnership ?? AppLocalizations.of(context)!.tr('Transfer Admin Role'),
                          subtitle:
                              AppLocalizations.of(
                                context)?.transferOwnershipDesc ?? AppLocalizations.of(context)!.tr('Make another member the group admin'),
                          isLight: isLight,
                          onTap: () => _showTransferOwnershipDialog(isLight),
                          color: Colors.orange),
                        _buildGroupSettingsOption(
                          icon: CupertinoIcons.delete,
                          title:
                              AppLocalizations.of(context)?.deleteGroup ?? AppLocalizations.of(context)!.tr('Delete Group'),
                          subtitle:
                              AppLocalizations.of(context)?.deleteGroupDesc ??
                              AppLocalizations.of(
                                context)?.permanentlyDeleteThisGroup ?? AppLocalizations.of(context)!.tr('Permanently delete this group'),
                          isLight: isLight,
                          onTap: () => _showDeleteGroupDialog(isLight),
                          color: Colors.red),
                      ],
                      isLight),
                    SizedBox(height: 20),
                  ],

                  if (!_isCurrentGroupAdmin) ...[
                    // Leave Group Action
                    _buildGroupSettingsSection(
                      AppLocalizations.of(context)?.actions ?? AppLocalizations.of(context)!.tr('Actions'),
                      [
                        _buildGroupSettingsOption(
                          icon: CupertinoIcons.square_arrow_right,
                          title:
                              AppLocalizations.of(context)?.leaveGroup ?? AppLocalizations.of(context)!.tr('Leave Group'),
                          subtitle:
                              AppLocalizations.of(context)?.leaveThisGroup ?? AppLocalizations.of(context)!.tr('Leave this group'),
                          isLight: isLight,
                          onTap: () => _showLeaveGroupDialog(context, isLight),
                          color: Colors.red),
                      ],
                      isLight),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  ],

                  // Cancel button (like in settings)
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)?.close ?? AppLocalizations.of(context)!.tr('Close'),
                    isSecondary: true,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    }),
                ]))),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  Widget _buildGroupSettingsHeader(bool isLight) {
    final groupName =
        currentGroup?['name'] ??
        (AppLocalizations.of(context)?.unknownGroup ?? AppLocalizations.of(context)!.tr('Unknown Group'));
    final groupCode = currentGroup?['code'] ?? AppLocalizations.of(context)!.tr('');
    final userRole = currentGroup?['role'] ?? AppLocalizations.of(context)!.tr('');
    final isOwner = _isGroupAdminRole(userRole);
    final memberCount = currentGroup?['memberCount'] ?? 0;
    final profileImage = currentGroup?['profileImage']?.toString();

    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Column(
        children: [
          // Group Profile Image or Icon
          _buildGroupAvatar(
            profileImage,
            label: groupName,
            isLight: isLight,
            size: 70,
            highlight: isOwner),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Group Name with Role
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  groupName,
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white),
                  textAlign: TextAlign.center)),
              if (isOwner) ...[
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                  child: Text(
                    _groupRoleBadge(userRole),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.orange,
                      letterSpacing: 0.5))),
              ],
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Group Code and Member Count
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${AppLocalizations.of(context)?.codeLabel ?? AppLocalizations.of(context)!.tr('Code')}: $groupCode',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.6))),
              Text(
                ' • ',
                style: TextStyle(
                  fontSize: 13,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.6))),
              Text(
                '$memberCount ${memberCount == 1 ? AppLocalizations.of(context)?.memberWord ?? AppLocalizations.of(context)!.tr('Member') : AppLocalizations.of(context)?.membersWord ?? AppLocalizations.of(context)!.tr('Members')}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.6))),
            ]),
        ]));
  }

  Widget _buildGroupSettingsSection(
    String title,
    List<Widget> options,
    bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.7)))),
        ...options,
      ]);
  }

  Widget _buildGroupSettingsOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLight,
    required VoidCallback onTap,
    Color? color,
  }) {
    final optionColor = color ?? (isLight ? Colors.black : Colors.white);

    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: TradeRepublicTap(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: DesktopAppWrapper.getPagePadding(),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : Colors.black,
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.05),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                child: Icon(
                  icon,
                  size: 20,
                  color: optionColor.withOpacity(0.8))),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: color ?? (isLight ? Colors.black : Colors.white),
                        letterSpacing: -0.2)),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),
                  ])),
              if (color == null)
                Icon(
                  CupertinoIcons.forward,
                  size: 16,
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.3)),
            ]))));
  }

  Widget _buildGroupMembersOption(bool isLight) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadGroupMembers(currentGroup?['id'] ?? 0),
      builder: (context, snapshot) {
        String subtitle =
            AppLocalizations.of(context)?.loadingMembers ?? AppLocalizations.of(context)!.tr('Loading members...');

        if (snapshot.hasData && snapshot.data != null) {
          final members = snapshot.data!;
          final memberNames = members
              .take(3)
              .map((m) {
                final handle = _formatUsernameHandle(
                  m['username'] ?? m['userId']);
                if (handle.isNotEmpty) return handle;
                return (m['name'] ?? m['userId'] ?? AppLocalizations.of(context)!.tr('')).toString().trim();
              })
              .where((label) => label.isNotEmpty)
              .toList();

          if (memberNames.isNotEmpty) {
            subtitle = memberNames.join(', ');
            if (members.length > 3) {
              subtitle += ' and ${members.length - 3} more';
            }
          } else {
            subtitle =
                AppLocalizations.of(context)?.noMembersFound ?? AppLocalizations.of(context)!.tr('No members found');
          }
        } else if (snapshot.hasError) {
          subtitle =
              AppLocalizations.of(context)?.failedToLoadMembers ?? AppLocalizations.of(context)!.tr('Failed to load members');
        }

        return _buildGroupSettingsOption(
          icon: CupertinoIcons.person_2_fill,
          title:
              AppLocalizations.of(context)?.viewAllMembers ?? AppLocalizations.of(context)!.tr('View All Members'),
          subtitle: subtitle,
          isLight: isLight,
          onTap: () => _showGroupMembersModal(isLight));
      });
  }

  void _showGroupMembersModal(bool isLight) {
    Navigator.pop(context); // Close group settings first

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.person_2_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.groupMembers ?? AppLocalizations.of(context)!.tr('Group Members'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 20),

          // Members list
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadGroupMembers(currentGroup?['id'] ?? 0),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CultiooLoadingIndicator());
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context)?.failedToLoadMembers ?? AppLocalizations.of(context)!.tr('Failed to load members'),
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.6))));
                }

                final members = snapshot.data!;

                return ListView(
                  children: members
                      .map((member) => _buildMemberListItem(member, isLight))
                      .toList());
              })),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  Widget _buildMemberListItem(Map<String, dynamic> member, bool isLight) {
    final isOwner = _isGroupAdminRole(member['role']);
    final memberUserId = (member['userId'] ?? member['username'] ?? AppLocalizations.of(context)!.tr(''))
        .toString();
    final isCurrentUser = memberUserId == userData?['username'];
    final canManage = _isCurrentGroupAdmin && !isCurrentUser;
    final displayName = (member['name'] ?? memberUserId).toString();
    final usernameHandle = _formatUsernameHandle(
      member['username'] ?? memberUserId);
    final profilePic = member['profilePic']?.toString();

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Row(
        children: [
          // Profile Icon
          _buildGroupAvatar(
            profilePic,
            label: displayName,
            isLight: isLight,
            size: 44,
            highlight: isOwner),

          SizedBox(width: 12),

          // Member Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Ensure the name can shrink and ellipsize to avoid horizontal overflow
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.2))),
                    if (isCurrentUser) ...[
                      SizedBox(width: 8),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          AppLocalizations.of(context)?.youLabel ?? AppLocalizations.of(context)!.tr('(You)'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.blue))),
                    ],
                    if (isOwner) ...[
                      SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 80),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                          child: Text(
                            _groupRoleBadge(member['role']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange)))),
                    ],
                  ]),
                if (usernameHandle.isNotEmpty || member['email'] != null) ...[
                  SizedBox(height: 4),
                  Text(
                    [
                      if (usernameHandle.isNotEmpty) usernameHandle,
                      _groupRoleHeadline(member['role']),
                      if (member['email'] != null &&
                          member['email'].toString().trim().isNotEmpty)
                        member['email'].toString().trim(),
                    ].join(' • '),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5))),
                ],
              ])),

          // Action Button (for owner only)
          if (canManage)
            TradeRepublicTap(
              onTap: () => _showMemberActionsDialog(member, isLight),
              child: Icon(
                CupertinoIcons.ellipsis_vertical,
                size: 20,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
        ]));
  }

  void _showMemberActionsDialog(Map<String, dynamic> member, bool isLight) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.55,
      child: Column(
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.ellipsis_circle_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.memberActions ?? AppLocalizations.of(context)!.tr('Member Actions'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 20),

          // Action options
          Column(
            children: [
              TradeRepublicListTile.destructive(
                title:
                    AppLocalizations.of(context)?.removeFromGroup ?? AppLocalizations.of(context)!.tr('Remove from Group'),
                leading: Icon(
                  CupertinoIcons.person_badge_minus,
                  color: Colors.red),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement remove member functionality
                }),
            ]),
        ]));
  }

  void _showTransferOwnershipDialog(bool isLight) {
    Navigator.pop(context); // Close settings modal first

    // Load members and show selection dialog
    _loadGroupMembers(currentGroup?['id'] ?? 0).then((members) {
      if (members.isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.noMembersTransfer ?? AppLocalizations.of(context)!.tr('No members found to transfer ownership to'));
        return;
      }

      // Filter out current user (owner)
      final eligibleMembers = members
          .where((member) => member['userId'] != userData?['username'])
          .toList();

      if (eligibleMembers.isEmpty) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.noEligibleMembers ?? AppLocalizations.of(context)!.tr('No eligible members to transfer ownership to'));
        return;
      }

      NavigationVisibility.hide();

      TradeRepublicBottomSheet.show(
        context: context,
        maxHeight: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.arrow_right_arrow_left_circle_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.transferOwnership ?? AppLocalizations.of(context)!.tr('Transfer Ownership'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            SizedBox(height: 32),

            // Member list
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: [
                    Text(
                      AppLocalizations.of(context)?.selectMemberToTransfer ?? AppLocalizations.of(context)!.tr('Select a member to transfer group ownership to:'),
                      style: TextStyle(
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.7))),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                    ...eligibleMembers.map((member) {
                      final usernameHandle = _formatUsernameHandle(
                        member['username'] ?? member['userId']);

                      return Container(
                        margin: EdgeInsets.only(bottom: 12),
                        child: TradeRepublicTap(
                          onTap: () {
                            Navigator.pop(context);
                            _transferOwnership(member['userId']);
                          },
                          child: Container(
                            padding: DesktopAppWrapper.getPagePadding(),
                            decoration: BoxDecoration(
                              color: isLight ? Colors.white : Colors.black,
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                            child: Row(
                              children: [
                                _buildGroupAvatar(
                                  member['profilePic']?.toString(),
                                  label: (member['name'] ?? member['userId'])
                                      .toString(),
                                  isLight: isLight,
                                  size: 42),
                                SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        member['name'] ?? member['userId'],
                                        style: TextStyle(
                                          color: isLight
                                              ? Colors.black
                                              : Colors.white,
                                          fontWeight: FontWeight.w600)),
                                      if (usernameHandle.isNotEmpty) ...[
                                        SizedBox(height: 4),
                                        Text(
                                          usernameHandle,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color:
                                                (isLight
                                                        ? Colors.black
                                                        : Colors.white)
                                                    .withOpacity(0.5))),
                                      ],
                                    ])),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.3)),
                              ]))));
                    }),
                  ]))),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              isSecondary: true,
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              }),
          ])).whenComplete(() => NavigationVisibility.show());
    });
  }

  void _showDeleteGroupDialog(bool isLight) {
    Navigator.pop(context); // Close settings modal first

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.trash_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.deleteGroup ?? AppLocalizations.of(context)!.tr('Delete Group'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

            // Subtitle
            Text(
              AppLocalizations.of(context)?.thisActionCannotBeUndone ?? AppLocalizations.of(context)!.tr('This action cannot be undone'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5))),

            SizedBox(height: 32),

            // Warning icon - minimalist
            Icon(
              CupertinoIcons.delete_solid,
              color: Colors.red.withOpacity(0.8),
              size: 64),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // Description
            Text(
              AppLocalizations.of(context)?.allMembersWillBeRemoved ?? AppLocalizations.of(context)!.tr('All members will be removed and group data will be permanently deleted.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.5,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.6))),

            SizedBox(height: 40),

            // Delete button - minimalist
            TradeRepublicButton(
              label:
                  AppLocalizations.of(context)?.deleteGroup ?? AppLocalizations.of(context)!.tr('Delete Group'),
              isDestructive: true,
              onPressed: () {
                HapticFeedback.heavyImpact();
                Navigator.pop(context);
                _deleteGroup();
              }),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button - minimalist
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              isSecondary: true,
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              }),
          ]))).whenComplete(() => NavigationVisibility.show());
  }

  Future<void> _transferOwnership(String newOwnerId) async {
    try {
      debugPrint('🔄 Transferring ownership to: $newOwnerId');

      final token = await _getStoredToken();
      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/business_groups/${currentGroup?['id']}/transfer-admin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'targetUserId': newOwnerId}));

      debugPrint('📡 Transfer ownership response: ${response.statusCode}');
      debugPrint('📡 Transfer ownership response body: ${response.body}');

      if (response.statusCode == 200) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.ownershipTransferredSuccessfully ?? AppLocalizations.of(context)!.tr('Admin role transferred successfully'));
        // Reload group data
        await _loadCurrentGroup();
      } else {
        final errorData = json.decode(response.body);
        TopNotification.error(
          context,
          errorData['error'] ??
              errorData['message'] ??
              (AppLocalizations.of(context)?.failedToTransferOwnership ?? AppLocalizations.of(context)!.tr('Failed to transfer admin role')));
      }
    } catch (e) {
      debugPrint('❌ Error transferring ownership: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorTransferringOwnership ?? AppLocalizations.of(context)!.tr('Error transferring ownership')}: $e');
    }
  }

  Future<void> _deleteGroup() async {
    try {
      debugPrint('🗑️ Deleting group: ${currentGroup?['id']}');

      final token = await _getStoredToken();
      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/business_groups/${currentGroup?['id']}/delete'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });

      debugPrint('📡 Delete group response: ${response.statusCode}');
      debugPrint('📡 Delete group response body: ${response.body}');

      if (response.statusCode == 200) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.groupDeletedSuccessfully ?? AppLocalizations.of(context)!.tr('Group deleted successfully'));
        // Clear current group and reload
        setState(() {
          currentGroup = null;
        });
        await _loadCurrentGroup();
      } else {
        final errorData = json.decode(response.body);
        TopNotification.error(
          context,
          errorData['error'] ??
              errorData['message'] ??
              (AppLocalizations.of(context)?.failedToDeleteGroup ?? AppLocalizations.of(context)!.tr('Failed to delete group')));
      }
    } catch (e) {
      debugPrint('❌ Error deleting group: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorDeletingGroup ?? AppLocalizations.of(context)!.tr('Error deleting group')}: $e');
    }
  }

  void _showCreateGroupModal(BuildContext context, bool isLight) {
    final groupNameController = TextEditingController();
    final groupDescriptionController = TextEditingController();
    final groupWebsiteController = TextEditingController();
    String? groupProfileImagePath;

    // Validation state variables
    bool groupNameError = false;
    bool groupDescriptionError = false;

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 8,
      child: StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          top: false,
          child: Column(
            children: [
              const DragHandle(),
              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.person_badge_plus_fill,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.createGroup ?? AppLocalizations.of(context)!.tr('Create Group'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4)),
                ]),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              SizedBox(height: 32),

              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    children: [
                      // Profile Image Selection
                      _buildGroupModalOption(
                        icon: CupertinoIcons.camera_fill,
                        title:
                            AppLocalizations.of(context)?.groupImage ?? AppLocalizations.of(context)!.tr('Group Image'),
                        subtitle: groupProfileImagePath != null
                            ? AppLocalizations.of(context)?.selected ?? AppLocalizations.of(context)!.tr('Selected')
                            : AppLocalizations.of(context)?.optional ?? AppLocalizations.of(context)!.tr('Optional'),
                        isLight: isLight,
                        onTap: () => _showGroupProfileImageOptions(
                          context,
                          isLight,
                          setModalState,
                          (path) {
                            groupProfileImagePath = path;
                            setModalState(() {});
                          }),
                        trailing: groupProfileImagePath != null
                            ? Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                color: Colors.green,
                                size: 20)
                            : null),

                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                      _buildGroupInputField(
                        controller: groupNameController,
                        title:
                            AppLocalizations.of(context)?.groupName ?? AppLocalizations.of(context)!.tr('Group Name'),
                        subtitle:
                            AppLocalizations.of(context)?.requiredField ?? AppLocalizations.of(context)!.tr('Required'),
                        icon: CupertinoIcons.person_2_fill,
                        isLight: isLight,
                        hasError: groupNameError),

                      _buildGroupInputField(
                        controller: groupDescriptionController,
                        title:
                            AppLocalizations.of(context)?.description ?? AppLocalizations.of(context)!.tr('Description'),
                        subtitle:
                            AppLocalizations.of(context)?.optional ?? AppLocalizations.of(context)!.tr('Optional'),
                        icon: CupertinoIcons.doc_text,
                        isLight: isLight,
                        maxLines: 3,
                        hasError: groupDescriptionError),

                      _buildGroupInputField(
                        controller: groupWebsiteController,
                        title:
                            AppLocalizations.of(context)?.website ?? AppLocalizations.of(context)!.tr('Website'),
                        subtitle:
                            AppLocalizations.of(context)?.optional ?? AppLocalizations.of(context)!.tr('Optional'),
                        icon: CupertinoIcons.globe,
                        isLight: isLight),

                      SizedBox(height: 32),

                      // Create Button - minimalist
                      TradeRepublicButton(
                        label:
                            AppLocalizations.of(context)?.createGroup ?? AppLocalizations.of(context)!.tr('Create Group'),
                        onPressed: () {
                          HapticFeedback.lightImpact();

                          setModalState(() {
                            groupNameError = false;
                            groupDescriptionError = false;
                          });

                          bool hasErrors = false;
                          if (groupNameController.text.trim().isEmpty) {
                            setModalState(() {
                              groupNameError = true;
                            });
                            hasErrors = true;
                          }

                          if (hasErrors) {
                            TopNotification.error(
                              context,
                              AppLocalizations.of(
                                    context)?.pleaseEnterGroupName ?? AppLocalizations.of(context)!.tr('Please enter a group name'));
                            return;
                          }

                          Navigator.pop(context);
                          _createGroup(
                            groupNameController.text.trim(),
                            groupDescriptionController.text.trim(),
                            groupWebsiteController.text.trim(),
                            groupProfileImagePath);
                        }),

                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

                      // Cancel button - minimalist
                      TradeRepublicButton(
                        label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                        isSecondary: true,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                        }),
                    ]))),
            ])))).whenComplete(() => NavigationVisibility.show());
  }

  void _showJoinGroupModal(BuildContext context, bool isLight) {
    final groupCodeController = TextEditingController();

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.arrow_right_circle_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.joinGroup ?? AppLocalizations.of(context)!.tr('Join Group'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            SizedBox(height: 20),

            // Group Code Input
            _buildGroupInputField(
              controller: groupCodeController,
              title: AppLocalizations.of(context)?.groupCode ?? AppLocalizations.of(context)!.tr('Group Code'),
              subtitle:
                  AppLocalizations.of(context)?.eightDigitCode ?? AppLocalizations.of(context)!.tr('8-digit code'),
              icon: CupertinoIcons.tag_fill,
              isLight: isLight),

            SizedBox(height: 32),

            // Join Button - minimalist
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.joinGroup ?? AppLocalizations.of(context)!.tr('Join Group'),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                _joinGroup(groupCodeController.text.trim());
              }),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button - minimalist
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              isSecondary: true,
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              }),
          ]))).whenComplete(() => NavigationVisibility.show());
  }

  void _showExploreGroupsModal(BuildContext context, bool isLight) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          const DragHandle(),
          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.search_circle_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.exploreGroups ?? AppLocalizations.of(context)!.tr('Explore Groups'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4)),
            ]),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          SizedBox(height: 20),

          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.compass,
                    size: 64,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.3)),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                  Text(
                    AppLocalizations.of(context)?.comingSoon ?? AppLocalizations.of(context)!.tr('Coming Soon!'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white)),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Text(
                    AppLocalizations.of(context)?.groupDiscoveryComingSoon ?? AppLocalizations.of(context)!.tr('Group discovery feature will be available soon.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.6))),
                ]))),

          // Cancel button
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.close ?? AppLocalizations.of(context)!.tr('Close'),
            isSecondary: true,
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            }),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  void _showLeaveGroupDialog(BuildContext context, bool isLight) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.arrow_uturn_left_circle_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.leaveGroup ?? AppLocalizations.of(context)!.tr('Leave Group'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

            // Group name
            Text(
              '"${currentGroup?['name'] ?? AppLocalizations.of(context)?.thisGroup ?? AppLocalizations.of(context)!.tr('this group')}"',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isLight ? Colors.black : Colors.white)),

            SizedBox(height: 32),

            // Warning icon - minimalist
            Icon(
              CupertinoIcons.square_arrow_right,
              color: Colors.red.withOpacity(0.8),
              size: 64),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            // Description
            Text(
              AppLocalizations.of(context)?.loseAccessGroupContent ?? AppLocalizations.of(context)!.tr('You will lose access to all group content and will need to be invited again to rejoin.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.5,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.6))),

            SizedBox(height: 40),

            // Leave button - minimalist
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.leaveGroup ?? AppLocalizations.of(context)!.tr('Leave Group'),
              isDestructive: true,
              onPressed: () {
                HapticFeedback.heavyImpact();
                Navigator.pop(context);
                _leaveGroup();
              }),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button - minimalist
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              isSecondary: true,
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              }),
          ]))).whenComplete(() => NavigationVisibility.show());
  }

  void _showGroupProfileImageOptions(
    BuildContext context,
    bool isLight,
    StateSetter setModalState,
    Function(String?) onImageSelected) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.photo_fill_on_rectangle_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.groupProfileImage ?? AppLocalizations.of(context)!.tr('Group Profile Image'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            SizedBox(height: 32),

            // Camera Option
            _buildGroupModalOption(
              icon: CupertinoIcons.camera_fill,
              title: AppLocalizations.of(context)?.takePhoto ?? AppLocalizations.of(context)!.tr('Take Photo'),
              subtitle:
                  AppLocalizations.of(context)?.useCamera ??
                  AppLocalizations.of(context)?.useCameraToTakeANewPhoto ?? AppLocalizations.of(context)!.tr('Use camera to take a new photo'),
              isLight: isLight,
              onTap: () {
                Navigator.pop(context);
                _selectGroupImage(ImageSource.camera, onImageSelected);
              }),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Gallery Option
            _buildGroupModalOption(
              icon: CupertinoIcons.photo_on_rectangle,
              title:
                  AppLocalizations.of(context)?.chooseFromGallery ?? AppLocalizations.of(context)!.tr('Choose from Gallery'),
              subtitle:
                  AppLocalizations.of(context)?.selectExistingPhoto ??
                  AppLocalizations.of(context)?.selectAnExistingPhoto ?? AppLocalizations.of(context)!.tr('Select an existing photo'),
              isLight: isLight,
              onTap: () {
                Navigator.pop(context);
                _selectGroupImage(ImageSource.gallery, onImageSelected);
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
          ]))).whenComplete(() => NavigationVisibility.show());
  }

  Future<void> _selectGroupImage(
    ImageSource source,
    Function(String?) onImageSelected) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85);

      if (image != null) {
        onImageSelected(image.path);
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.imageSelectedSuccess ?? AppLocalizations.of(context)!.tr('Image selected successfully'));
      }
    } catch (e) {
      debugPrint('❌ Error selecting group image: $e');
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.failedSelectImage ?? AppLocalizations.of(context)!.tr('Failed to select image'));
    }
  }

  Future<void> _createGroup(
    String groupName,
    String description,
    String website,
    String? profileImagePath) async {
    try {
      debugPrint('🎯 Creating new group: $groupName');

      // Check if user is already in a group
      if (currentGroup != null) {
        if (_isCurrentGroupAdmin) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.tr('Admins cannot leave the group. Transfer admin role first or delete the group.') ?? AppLocalizations.of(context)!.tr('Admins cannot leave the group. Transfer admin role first or delete the group.'));
          return;
        }
        debugPrint(
          '⚠️ User is already in a group, showing confirmation bottom sheet...');

        // Show confirmation bottom sheet
        final isLight = Provider.of<AppSettings>(
          context,
          listen: false).isLightMode(context);
        final shouldLeave = await TradeRepublicBottomSheet.show<bool>(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DragHandle(),

              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_circle_fill,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.alreadyInGroupLeaveFirst ?? AppLocalizations.of(context)!.tr('Already in a Group'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4)),
                ]),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Content
              Text(
                AppLocalizations.of(context)?.leaveCurrentGroupAndCreate ?? AppLocalizations.of(context)!.tr('You are currently in a group. You can only be in one group at a time. Do you want to leave your current group and create a new one?'),
                style: TextStyle(
                  color: Theme.of(
                    context).textTheme.bodyLarge?.color?.withOpacity(0.7),
                  fontSize: 15),
                textAlign: TextAlign.center),

              SizedBox(height: 32),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                      isSecondary: true,
                      onPressed: () => Navigator.of(context).pop(false))),
                  SizedBox(width: 12),
                  Expanded(
                    child: TradeRepublicButton(
                      label:
                          AppLocalizations.of(context)?.leaveAndCreate ?? AppLocalizations.of(context)!.tr('Leave & Create'),
                      onPressed: () => Navigator.of(context).pop(true))),
                ]),
            ]));

        if (shouldLeave != true) {
          debugPrint('🚫 User cancelled group creation');
          return;
        }

        // Leave current group first
        final leaveSucceeded = await _leaveGroup();
        if (!leaveSucceeded) {
          return;
        }
      }

      final token = await _getStoredToken();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/business_groups/create'));

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['groupName'] = groupName;

      if (description.isNotEmpty) {
        request.fields['description'] = description;
      }

      if (website.isNotEmpty) {
        request.fields['website'] = website;
      }

      if (profileImagePath != null) {
        final extension = _getImageExtension(profileImagePath);
        request.files.add(
          await http.MultipartFile.fromPath(
            'profileImage',
            profileImagePath,
            contentType: MediaType('image', extension)));
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      debugPrint('📡 Create group response: ${response.statusCode}');
      debugPrint('📡 Create group response body: $responseBody');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final responseData = json.decode(responseBody);
        final groupData = responseData['group'];
        final groupCode =
            groupData['code'] ??
            AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown');
        final actualGroupName = groupData['name'] ?? groupName;

        TopNotification.success(
          context,
          AppLocalizations.of(context)?.groupCreatedSuccessfully ?? AppLocalizations.of(context)!.tr('Group created successfully!'));

        // Show success modal with group code
        _showGroupCreatedSuccessModal(context, actualGroupName, groupCode);

        // Reload current group
        await _loadCurrentGroup();
      } else {
        // Parse error response
        try {
          final errorData = json.decode(responseBody);
          String errorMessage =
              errorData['error'] ??
              (AppLocalizations.of(context)?.failedToCreateGroup ?? AppLocalizations.of(context)!.tr('Failed to create group'));

          // Simplify technical database errors for users
          if (errorMessage.contains('TLS') ||
              errorMessage.contains('servername')) {
            errorMessage =
                AppLocalizations.of(context)?.databaseConnectionError ?? AppLocalizations.of(context)!.tr('Database connection error. Please try again or contact support.');
          }

          // If user is already in a group (409), reload current group to show which one
          if (response.statusCode == 409) {
            await _loadCurrentGroup();

            // Show error with current group name if available
            if (currentGroup != null) {
              final currentGroupName =
                  currentGroup!['name'] ??
                  (AppLocalizations.of(context)?.unknownGroup ?? AppLocalizations.of(context)!.tr('Unknown Group'));
              errorMessage =
                  AppLocalizations.of(context)?.alreadyInGroupPleaseLeave ?? AppLocalizations.of(context)!.tr('Please leave first to create a new group.');
            }
          }

          TopNotification.error(context, errorMessage);
        } catch (e) {
          // If JSON parsing fails (HTML error), show generic message
          TopNotification.error(
            context,
            AppLocalizations.of(context)?.serverError ?? AppLocalizations.of(context)!.tr('Server error. Please try again later.'));
        }
      }
    } catch (e) {
      debugPrint('❌ Error creating group: $e');

      // Show user-friendly error message
      String errorMessage =
          AppLocalizations.of(context)?.networkError ?? AppLocalizations.of(context)!.tr('Network error. Please check your connection and try again.');
      if (e.toString().contains('TLS') || e.toString().contains('servername')) {
        errorMessage =
            AppLocalizations.of(context)?.databaseContactSupport ?? AppLocalizations.of(context)!.tr('Database connection error. Please contact support.');
      }

      TopNotification.error(context, errorMessage);
    }
  }

  Future<void> _joinGroup(String groupCode) async {
    if (groupCode.isEmpty) {
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.pleaseEnterGroupCode ?? AppLocalizations.of(context)!.tr('Please enter a group code'));
      return;
    }

    try {
      debugPrint('🤝 Joining group with code: $groupCode');

      // Check if user is already in a group
      if (currentGroup != null) {
        if (_isCurrentGroupAdmin) {
          TopNotification.error(
            context,
            AppLocalizations.of(context)!.tr('Admins cannot leave the group. Transfer admin role first or delete the group.') ?? AppLocalizations.of(context)!.tr('Admins cannot leave the group. Transfer admin role first or delete the group.'));
          return;
        }
        debugPrint('⚠️ User is already in a group, leaving current group first...');

        // Show confirmation dialog
        final isLight = Provider.of<AppSettings>(
          context,
          listen: false).isLightMode(context);
        final shouldLeave = await TradeRepublicBottomSheet.show<bool>(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DragHandle(),

              // ── Sheet header: Icon left + Title ──
              Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_circle_fill,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white),
                  SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.alreadyInGroupLeaveFirst ?? AppLocalizations.of(context)!.tr('Already in a Group'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4)),
                ]),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Content
              Text(
                AppLocalizations.of(context)?.leaveCurrentGroupAndJoin ?? AppLocalizations.of(context)!.tr('You are currently in a group. You can only be in one group at a time. Do you want to leave your current group and join the new one?'),
                style: TextStyle(
                  color: Theme.of(
                    context).textTheme.bodyLarge?.color?.withOpacity(0.7),
                  fontSize: 15),
                textAlign: TextAlign.center),

              SizedBox(height: 32),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: TradeRepublicButton(
                      label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                      isSecondary: true,
                      onPressed: () => Navigator.of(context).pop(false))),
                  SizedBox(width: 12),
                  Expanded(
                    child: TradeRepublicButton(
                      label:
                          AppLocalizations.of(context)?.leaveAndJoin ?? AppLocalizations.of(context)!.tr('Leave & Join'),
                      onPressed: () => Navigator.of(context).pop(true))),
                ]),
            ]));

        if (shouldLeave != true) {
          debugPrint('🚫 User cancelled group switch');
          return;
        }

        // Leave current group first
        final leaveSucceeded = await _leaveGroup();
        if (!leaveSucceeded) {
          return;
        }
      }

      final token = await _getStoredToken();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/business_groups/join'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'code': groupCode, 'forceLeave': false}));

      debugPrint('📡 Join group response: ${response.statusCode}');
      debugPrint('📡 Join group response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        TopNotification.success(
          context,
          'Successfully joined group "${responseData['groupName']}"!');

        // Reload current group
        await _loadCurrentGroup();
      } else {
        final errorData = json.decode(response.body);
        TopNotification.error(
          context,
          errorData['error'] ??
              (AppLocalizations.of(context)?.failedToJoinGroup ?? AppLocalizations.of(context)!.tr('Failed to join group')));
      }
    } catch (e) {
      debugPrint('❌ Error joining group: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorJoiningGroup ?? AppLocalizations.of(context)!.tr('Error joining group')}: $e');
    }
  }

  Future<bool> _leaveGroup() async {
    try {
      debugPrint('👋 Leaving current group...');

      if (_isCurrentGroupAdmin) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.tr('Admins cannot leave the group. Transfer admin role first or delete the group.') ?? AppLocalizations.of(context)!.tr('Admins cannot leave the group. Transfer admin role first or delete the group.'));
        return false;
      }

      final token = await _getStoredToken();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/business_groups/leave'),
        headers: {'Authorization': 'Bearer $token'});

      debugPrint('📡 Leave group response: ${response.statusCode}');
      debugPrint('📡 Leave group response body: ${response.body}');

      if (response.statusCode == 200) {
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.successfullyLeftGroup ?? AppLocalizations.of(context)!.tr('Successfully left the group'));

        // Clear current group and reload
        setState(() {
          currentGroup = null;
        });
        await _loadCurrentGroup();
        return true;
      } else {
        final errorData = json.decode(response.body);
        TopNotification.error(
          context,
          errorData['error'] ??
              errorData['message'] ??
              (AppLocalizations.of(context)?.failedToLeaveGroup ?? AppLocalizations.of(context)!.tr('Failed to leave group')));
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error leaving group: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorLeavingGroup ?? AppLocalizations.of(context)!.tr('Error leaving group')}: $e');
      return false;
    }
  }

  Future<void> _uploadGroupProfileImage(String imagePath) async {
    try {
      if (!_isCurrentGroupAdmin) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)!.tr('Only admins can update the group image.') ?? AppLocalizations.of(context)!.tr('Only admins can update the group image.'));
        return;
      }
      if (currentGroup?['id'] == null || imagePath.isEmpty) {
        TopNotification.error(context, AppLocalizations.of(context)!.tr('No group image selected.') ?? AppLocalizations.of(context)!.tr('No group image selected.'));
        return;
      }

      final token = await _getStoredToken();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${ApiConfig.baseUrl}/business_groups/${currentGroup?['id']}/profile-image'));

      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        await http.MultipartFile.fromPath(
          'profileImage',
          imagePath,
          contentType: MediaType('image', _getImageExtension(imagePath))));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = responseBody.isNotEmpty
          ? json.decode(responseBody)
          : {};

      if (response.statusCode == 200) {
        TopNotification.success(context, AppLocalizations.of(context)!.tr('Group image updated successfully') ?? AppLocalizations.of(context)!.tr('Group image updated successfully'));
        await _loadCurrentGroup();
      } else {
        TopNotification.error(
          context,
          responseData['error'] ??
              responseData['message'] ?? AppLocalizations.of(context)!.tr('Failed to update group image'));
      }
    } catch (e) {
      debugPrint('❌ Error uploading group profile image: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)!.tr('Error updating group image')}: $e');
    }
  }

  void _showGroupCreatedSuccessModal(
    BuildContext context,
    String groupName,
    String groupCode) {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final isLight = appSettings.isLightMode(context);

    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      enableDrag: false,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DragHandle(),

                // ── Sheet header: Icon left + Title ──
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white),
                    SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.groupCreatedMessage ?? AppLocalizations.of(context)!.tr('Group Created!'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4)),
                  ]),

                SizedBox(height: 10),

                Text(
                  AppLocalizations.of(context)?.groupCreatedDesc ?? AppLocalizations.of(context)!.tr('Your group has been created successfully.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7))),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Group Code Display
                Column(
                  children: [
                    Text(
                      AppLocalizations.of(context)?.groupCode ?? AppLocalizations.of(context)!.tr('Group Code'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),
                    SizedBox(height: 4),
                    Text(
                      groupCode,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.green,
                        letterSpacing: 2)),
                    SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)?.shareCodeToInvite ?? AppLocalizations.of(context)!.tr('Share this code with others to invite them'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),
                  ]),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                // Action Button - minimalist
                TradeRepublicButton(
                  label: AppLocalizations.of(context)?.gotIt ?? AppLocalizations.of(context)!.tr('Got it!'),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    NavigationVisibility.show();
                  }),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
              ]))))).whenComplete(() => NavigationVisibility.show());
  }

  Widget _buildGroupModalOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLight,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6)),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white)),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5))),
                ])),
            if (trailing != null)
              trailing
            else
              Icon(
                CupertinoIcons.chevron_right,
                size: 24,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.3)),
          ])));
  }

  Widget _buildGroupInputField({
    required TextEditingController controller,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isLight,
    int maxLines = 1,
    bool hasError = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
              color: hasError
                  ? Colors.red
                  : (isLight ? Colors.black : Colors.white).withOpacity(0.5))),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          TradeRepublicTextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w500),
            hintText: subtitle,
            filled: true,
            fillColor: hasError
                ? Colors.red.withOpacity(0.1)
                : isLight
                ? Colors.white
                : Colors.black),
        ]));
  }

  void _checkAndShowAddPaymentMethod(BuildContext context, bool isLight) {
    if (!mounted) return;
    final safeContext = this.context;

    // Check if a BANK method already exists (cards should not block adding bank)
    _loadSavedPaymentMethods().then((methods) {
      final hasBankMethod = methods.any((m) {
        final t = (m['type'] ?? AppLocalizations.of(context)!.tr('')).toString().toLowerCase();
        return t == 'ach' ||
            t == 'us_bank_account' ||
            t == 'sepa' ||
            t == 'sepa_debit';
      });

      // Always show the modal - bank fields are shown only if no bank exists,
      // card fields are always shown (unlimited cards allowed)
      _showAddPaymentMethodModal(safeContext, isLight, hasBankMethod: hasBankMethod);
    });
  }

  void _showDeletePaymentMethodDialog(String methodId, bool isLight) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),

            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.creditcard_fill,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.deleteBankAccount ?? AppLocalizations.of(context)!.tr('Delete Bank Account'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            SizedBox(height: 32),

            // Warning icon - minimalist
            Icon(
              CupertinoIcons.delete_solid,
              size: 64,
              color: Colors.red.withOpacity(0.8)),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

            Text(
              AppLocalizations.of(context)?.deleteBankAccountConfirm ?? AppLocalizations.of(context)!.tr('Are you sure you want to delete this bank account?\\\\nThis action cannot be undone.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.5,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.6))),

            SizedBox(height: 40),

            // Delete button - minimalist red
            TradeRepublicButton(
              label:
                  AppLocalizations.of(context)?.deleteAccount ??
                  AppLocalizations.of(context)?.delete ?? AppLocalizations.of(context)!.tr('Delete'),
              isDestructive: true,
              onPressed: () {
                HapticFeedback.heavyImpact();
                Navigator.pop(context);
                _deletePaymentMethodConfirmed(methodId);
              }),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Cancel button - minimalist
            TradeRepublicButton(
              label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
              isSecondary: true,
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              }),
          ]))).whenComplete(() => NavigationVisibility.show());
  }

  Future<void> _deletePaymentMethod(dynamic methodId, bool isLight) async {
    NavigationVisibility.hide();

    final confirmed = await TradeRepublicBottomSheet.show<bool>(
      context: context,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),

            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.delete,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white),
                SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.deleteBankAccount ?? AppLocalizations.of(context)!.tr('Delete Bank Account'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4)),
              ]),

            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Description
            Text(
              AppLocalizations.of(context)?.deleteBankAccountConfirmAlt ?? AppLocalizations.of(context)!.tr('Are you sure you want to delete this bank account? This action cannot be undone.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Theme.of(
                  context).textTheme.bodyLarge?.color?.withOpacity(0.6),
                height: 1.4)),

            SizedBox(height: 28),

            // Buttons
            Row(
              children: [
                // Cancel button
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                    isSecondary: true,
                    onPressed: () => Navigator.pop(context, false))),

                SizedBox(width: 12),

                // Delete button
                Expanded(
                  child: TradeRepublicButton(
                    label:
                        AppLocalizations.of(context)?.deleteAccount ??
                        AppLocalizations.of(context)?.delete ?? AppLocalizations.of(context)!.tr('Delete'),
                    isDestructive: true,
                    onPressed: () => Navigator.pop(context, true))),
              ]),
          ])));

    NavigationVisibility.show();

    if (confirmed != true) return;

    try {
      // Delete from Stripe via backend
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/stripe/bank-account/$methodId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getStoredToken()}',
        });

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to delete from Stripe: ${response.body}');
      }

      // Update local data
      await _loadUserData();

      TopNotification.success(
        context,
        AppLocalizations.of(context)?.bankAccountDeletedSuccessfully ?? AppLocalizations.of(context)!.tr('Bank account deleted successfully!'));
    } catch (e) {
      debugPrint('❌ Error deleting payment method: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorDeletingBankAccount ?? AppLocalizations.of(context)!.tr('Error deleting bank account')}: $e');
    }
  }

  Future<void> _deletePaymentMethodConfirmed(String methodId) async {
    try {
      // TODO: Call backend API to delete payment method
      await Future.delayed(Duration(seconds: 1)); // Simulate API call

      // Update user data to remove payment method info
      final updatedData = {'stripeCustomerId': null};

      await _updateUserData(updatedData);
      await _loadUserData();

      TopNotification.success(
        context,
        AppLocalizations.of(context)?.bankAccountDeletedSuccessfully ?? AppLocalizations.of(context)!.tr('Bank account deleted successfully!'));
    } catch (e) {
      debugPrint('❌ Error deleting payment method: $e');
      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorDeletingBankAccount ?? AppLocalizations.of(context)!.tr('Error deleting bank account')}: $e');
    }
  }

  Widget _buildEarningHistoryItem(Map<String, dynamic> earning, bool isLight) {
    final amount = earning['amount']?.toDouble() ?? 0.0;
    final source = earning['source']?.toString() ?? AppLocalizations.of(context)!.tr('unknown');
    final description =
        earning['description']?.toString() ??
        (AppLocalizations.of(context)?.noDescription ?? AppLocalizations.of(context)!.tr('No description'));
    final createdAt = earning['created_at']?.toString();
    final customer = earning['customer']?.toString();

    // Parse date
    DateTime? dateTime;
    try {
      if (createdAt != null) {
        dateTime = DateTime.parse(createdAt);
      }
    } catch (e) {
      dateTime = DateTime.now();
    }

    // Format time
    final timeString = dateTime != null
        ? '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}'
        : '--:--';

    // Format date
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final dateString = dateTime != null
        ? appSettings.formatDate(dateTime)
        : AppLocalizations.of(context)?.unknownLabel ?? AppLocalizations.of(context)!.tr('Unknown');

    // Get source icon, color and gradient
    IconData sourceIcon;
    String sourceLabel;
    List<Color> gradientColors;

    switch (source.toLowerCase()) {
      case 'delivery':
        sourceIcon = CupertinoIcons.car_fill;
        sourceLabel = AppLocalizations.of(context)?.delivery ?? AppLocalizations.of(context)!.tr('Delivery');
        gradientColors = [Colors.blue.shade400, Colors.blue.shade600];
        break;
      case 'sale':
        sourceIcon = CupertinoIcons.bag;
        sourceLabel = 'Sale';
        gradientColors = [Colors.green.shade400, Colors.green.shade600];
        break;
      default:
        sourceIcon = CupertinoIcons.money_dollar_circle;
        sourceLabel = 'Earning';
        gradientColors = [Colors.amber.shade400, Colors.orange.shade500];
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
      child: Row(
        children: [
          // Icon with gradient - KEEP for category indication
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Icon(sourceIcon, size: 24, color: Colors.white)),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      sourceLabel,
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.3)),
                    // Amount badge - KEEP gradient for positive value
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.green.shade400,
                            Colors.green.shade600,
                          ]),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
                      child: Text(
                        '+${_formatCurrency(amount)}',
                        style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3))),
                  ]),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.7)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
                if (customer != null && customer.isNotEmpty) ...[
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.person,
                        size: 14,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5)),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          customer,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.6)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                    ]),
                ],
                SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.clock,
                      size: 13,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.4)),
                    SizedBox(width: 4),
                    Text(
                      '$dateString • $timeString',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: (isLight ? Colors.black : Colors.white)
                            .withOpacity(0.5))),
                  ]),
              ])),
        ]));
  }

  void _showFullEarningsHistoryModal(BuildContext context, bool isLight) {
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.9,
      child: Column(
        children: [
          const DragHandle(),

          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.chart_bar_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)?.earningsHistory ?? AppLocalizations.of(context)!.tr('Earnings History'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4)),
                  Text(
                    AppLocalizations.of(context)?.completeEarningsHistory ?? AppLocalizations.of(context)!.tr('Complete history of your earnings'),
                    style: TextStyle(
                      fontSize: 13,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5))),
                ]),
            ]),

          SizedBox(height: 32),

          // Total earnings summary - minimalist
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: isLight ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.totalEarningsLabel ?? AppLocalizations.of(context)!.tr('Total Earnings'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w500,
                        color: (isLight ? Colors.white : Colors.black)
                            .withOpacity(0.7))),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    Text(
                      _formatCurrency(
                        earningsData['totalEarnings'] is String
                            ? double.tryParse(earningsData['totalEarnings']) ??
                                  0.0
                            : earningsData['totalEarnings']?.toDouble() ?? 0.0),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.white : Colors.black)),
                  ]),
                Icon(
                  Icons.trending_up,
                  color: isLight ? Colors.white : Colors.black,
                  size: 32),
              ])),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Earnings list
          Expanded(
            child: earningsHistory.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.3)),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                        Text(
                          AppLocalizations.of(context)?.noEarningsYet ?? AppLocalizations.of(context)!.tr('No earnings yet'),
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                            fontWeight: FontWeight.w600,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.5))),
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          '${AppLocalizations.of(context)?.earningsWillAppearHere ?? AppLocalizations.of(context)!.tr('Your earnings will appear here')}\n${AppLocalizations.of(context)?.onceYouStartDeliveries ?? AppLocalizations.of(context)!.tr('once you start making deliveries')}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.4))),
                      ]))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: earningsHistory.length,
                    itemBuilder: (context, index) {
                      final earning = earningsHistory[index];
                      return _buildEarningHistoryItem(earning, isLight);
                    })),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
        ])).whenComplete(() => NavigationVisibility.show());
  }

  // Session Expired Dialog
  void _showSessionExpiredDialog() {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false);
    final isLight = appSettings.isLightMode(context);

    TradeRepublicBottomSheet.show(
      context: context,
      isDismissible: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8)),
            child: Icon(CupertinoIcons.lock, size: 48, color: Colors.orange)),
          SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)?.sessionExpired ?? AppLocalizations.of(context)!.tr('Session Expired'),
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
              fontWeight: FontWeight.w700,
              color: isLight ? Colors.black : Colors.white)),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Text(
            AppLocalizations.of(context)?.sessionExpiredDesc ?? AppLocalizations.of(context)!.tr('Your session has expired for security reasons. Please log in again to continue.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6))),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.logInAgain ?? AppLocalizations.of(context)!.tr('Log In Again'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(
                  context).pushNamedAndRemoveUntil('/login', (route) => false);
              })),
        ]));
  }
}

// Custom painter for bank card subtle pattern
class _CardPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw subtle curved lines
    final path1 = Path();
    path1.moveTo(size.width * 0.7, 0);
    path1.quadraticBezierTo(
      size.width * 0.5,
      size.height * 0.3,
      size.width * 0.8,
      size.height * 0.5);
    path1.quadraticBezierTo(
      size.width * 1.1,
      size.height * 0.7,
      size.width * 0.9,
      size.height);
    canvas.drawPath(path1, paint);

    final path2 = Path();
    path2.moveTo(size.width * 0.9, 0);
    path2.quadraticBezierTo(
      size.width * 0.7,
      size.height * 0.4,
      size.width,
      size.height * 0.6);
    canvas.drawPath(path2, paint);

    // Draw subtle circles
    final circlePaint = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.2),
      size.width * 0.15,
      circlePaint);

    canvas.drawCircle(
      Offset(size.width * 0.1, size.height * 0.8),
      size.width * 0.2,
      circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tries a list of image URLs sequentially and shows [fallback] when all fail.
class _FallbackNetworkImage extends StatefulWidget {
  final List<String> imageUrls;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallback;
  final Widget? loading;

  const _FallbackNetworkImage({
    required this.imageUrls,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
    this.loading,
  });

  @override
  State<_FallbackNetworkImage> createState() => _FallbackNetworkImageState();
}

class _FallbackNetworkImageState extends State<_FallbackNetworkImage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty || _currentIndex >= widget.imageUrls.length) {
      return widget.fallback ?? const SizedBox.shrink();
    }
    return Image.network(
      widget.imageUrls[_currentIndex],
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return widget.loading ?? const SizedBox.shrink();
      },
      errorBuilder: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _currentIndex < widget.imageUrls.length - 1) {
            setState(() => _currentIndex++);
          }
        });
        return widget.fallback ?? const SizedBox.shrink();
      });
  }
}
