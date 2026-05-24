import 'package:flutter/material.dart';
import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_card.dart';
import '../../../shared/widgets/trade_republic_divider.dart';
import '../../../shared/widgets/trade_republic_list_tile.dart';
import '../../../shared/widgets/trade_republic_switch.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import '../../../shared/widgets/trade_republic_value_slider.dart';
import '../../../shared/widgets/drag_handle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'business_account_page.dart';
import 'main_navigation.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import '../../../utils/number_formatters.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

// Currency Input Formatter - Input from right to left like a calculator
// Example: "12300" → "123.00", "500" → "5.00", "12" → "0.12"
class CurrencyInputFormatter extends TextInputFormatter {
  final int decimalDigits;

  CurrencyInputFormatter({this.decimalDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Only allow digits
    String newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (newText.isEmpty) {
      return TextEditingValue(
        text: '0.00',
        selection: TextSelection.collapsed(offset: 4),
      );
    }

    // Interpret as integer (cents)
    int cents = int.parse(newText);

    // Convert to decimal (divide by 100 for 2 decimal places)
    double amount = cents / 100.0;

    // Format with 2 decimal places
    String formatted = formatNumberUS(amount, fractionDigits: decimalDigits);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Number Input Formatter for integers (Stock, etc.)
class IntegerInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Only allow digits
    String newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (newText.isEmpty) {
      return TextEditingValue(
        text: '0',
        selection: TextSelection.collapsed(offset: 1),
      );
    }

    // Remove leading zeros
    int value = int.parse(newText);
    String formatted = value.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Decimal Input Formatter for Nutrition values (max 2 decimal places)
class DecimalInputFormatter extends TextInputFormatter {
  final int decimalDigits;

  DecimalInputFormatter({this.decimalDigits = 2});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Allows digits and one decimal point
    String newText = newValue.text;

    // If empty, return to 0
    if (newText.isEmpty) {
      return TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Regex: Optional digits, optional one point, optional up to 2 digits after
    final regex = RegExp(r'^\d*\.?\d{0,' + decimalDigits.toString() + r'}');
    final match = regex.firstMatch(newText);

    if (match != null) {
      String matched = match.group(0)!;
      return TextEditingValue(
        text: matched,
        selection: TextSelection.collapsed(offset: matched.length),
      );
    }

    return oldValue;
  }
}

/// Top-level helper: returns the translated display name for a category DB key.
String translateProductCategory(String key, BuildContext context) {
  final loc = AppLocalizations.of(context);
  switch (key) {
    case 'Fruits & Vegetables':
      return loc?.categoryFruitsVegetables ?? key;
    case 'Dairy & Eggs':
      return loc?.categoryDairyEggs ?? key;
    case 'Meat & Sausages':
      return loc?.categoryMeatSausages ?? key;
    case 'Bakery Products':
      return loc?.categoryBakeryProducts ?? key;
    case 'Jams & Spreads':
      return loc?.categoryJamsSpreads ?? key;
    case 'Honey':
      return loc?.categoryHoney ?? key;
    case 'Cereal Products':
      return loc?.categoryCerealProducts ?? key;
    case 'Beverages':
      return loc?.categoryBeverages ?? key;
    case 'Spices & Oils':
      return loc?.categorySpicesOils ?? key;
    case 'Fish & Seafood':
      return loc?.categoryFishSeafood ?? key;
    case 'Cheese':
      return loc?.categoryCheese ?? key;
    case 'Snacks & Sweets':
      return loc?.categorySnacksSweets ?? key;
    case 'Ice Cream':
      return loc?.categoryIceCream ?? key;
    case 'Bakery Products (frozen)':
      return loc?.categoryBakeryFrozen ?? key;
    case 'Soups & Ready Meals':
      return loc?.categorySoupsReadyMeals ?? key;
    case 'Salads & Delicacies':
      return loc?.categorySaladsDelicacies ?? key;
    case 'Plants & Herbs':
      return loc?.categoryPlantsHerbs ?? key;
    case 'Non-Food':
      return loc?.categoryNonFood ?? key;
    case 'Canned & Preserved':
      return loc?.categoryCannedPreserved ?? key;
    case 'Pasta & Noodles':
      return loc?.categoryPastaNoodles ?? key;
    case 'Sauces & Dips':
      return loc?.categorySaucesDips ?? key;
    case 'Vegan & Vegetarian':
      return loc?.categoryVeganVegetarian ?? key;
    case 'Organic Products':
      return loc?.categoryOrganicProducts ?? key;
    case 'Regional Specialties':
      return loc?.categoryRegionalSpecialties ?? key;
    case 'Gift Items':
      return loc?.categoryGiftItems ?? key;
    default:
      return key;
  }
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> products = [];
  bool isLoading = true;
  bool _isInitialLoad = true;
  Map<String, dynamic>? userData;
  bool isVerificationLoading = true;
  bool _isModalOpen = false;
  final Set<String> _selectedProductIds = <String>{};

  String _localized(String key) {
    final loc = AppLocalizations.of(context);
    return loc?.tr(key) ?? AppLocalizations(const Locale('en')).tr(key);
  }

  // Modern Animation Controllers - Delvioo Style
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late Animation<double> _headerSlideAnim;
  late Animation<double> _headerFadeAnim;

  @override
  void initState() {
    super.initState();

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

    _loadProducts();
    _loadUserData();
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

  Future<String?> _resolveAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final appSettings = Provider.of<AppSettings>(context, listen: false);

    final candidates = [
      prefs.getString('auth_token'),
      prefs.getString('business_auth_token'),
      prefs.getString('token'),
      appSettings.authToken,
    ];

    for (final candidate in candidates) {
      final normalized = candidate?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }

    return null;
  }

  Future<void> _loadUserData() async {
    print('📡 Loading business user data from users table...');
    if (mounted) {
      setState(() {
        isVerificationLoading = true;
      });
    }

    try {
      // Try to get user profile from backend
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/users/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getStoredToken()}',
        },
      );

      print('📡 User profile response status: ${response.statusCode}');
      print('📡 User profile response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['success'] == true && responseData['user'] != null) {
          final userFromApi = responseData['user'];

          if (mounted) {
            setState(() {
              userData = {
                // Core user fields
                'username': userFromApi['username'],
                'firstname': userFromApi['firstname'],
                'lastname': userFromApi['lastname'],
                'email': userFromApi['email'],
                'phone': userFromApi['phone'],

                // Business information
                'businessName':
                    userFromApi['businessName'] ??
                    userFromApi['business_company'],
                'isBusiness': userFromApi['isBusiness'],

                // Stripe payment fields
                'stripeAccountId': userFromApi['stripeAccountId'],
                'stripeCustomerId': userFromApi['stripeCustomerId'],
                'stripe_customer_id': userFromApi['stripe_customer_id'],

                // Tax forms
                'tax_form_status': userFromApi['tax_form_status'],
                'tax_form_type': userFromApi['tax_form_type'],
              };
              isVerificationLoading = false;
            });
          }

          print(
            '✅ User data loaded: isBusiness=${userData?['isBusiness']}, stripeCustomerId=${userData?['stripeCustomerId']}',
          );
          return;
        }
      }

      // Fallback
      print('⚠️ Using fallback - setting userData to empty');
      if (mounted) {
        setState(() {
          userData = {};
          isVerificationLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading user data: $e');
      if (mounted) {
        setState(() {
          userData = {};
          isVerificationLoading = false;
        });
      }
    }
  }

  Future<void> _loadProducts() async {
    print('📦 Loading user products...');
    if (mounted && _isInitialLoad) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final token = await _getStoredToken();

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/business/products'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📦 Products response status: ${response.statusCode}');
      print('📦 Products response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          products = List<Map<String, dynamic>>.from(data['products'] ?? []);
          isLoading = false;
          _isInitialLoad = false;
        });
        print('✅ Loaded ${products.length} products');
      } else {
        if (mounted) {
          setState(() {
            products = [];
            isLoading = false;
            _isInitialLoad = false;
          });
        }
        print('⚠️ Failed to load products: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error loading products: $e');
      if (mounted) {
        setState(() {
          products = [];
          isLoading = false;
          _isInitialLoad = false;
        });
      }
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
      key: _scaffoldKey,
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
                      CultiooSliverRefreshControl(onRefresh: _loadProducts),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          isDesktop
                              ? 32.0
                              : MediaQuery.of(context).padding.top + 20.0,
                          horizontalPadding,
                          MediaQuery.of(context).padding.bottom + 100.0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Trade Republic Style Header - Simple text, no floating
                              _buildTradeRepublicHeader(isLight),

                              // Products Summary - Large numbers
                              _buildProductsSummary(isLight),

                              // Selection actions (long-press to start selection)
                              if (_selectedProductIds.isNotEmpty)
                                _buildSelectionActionBar(isLight),

                              // Products List - Trade Republic style rows
                              products.isEmpty
                                  ? _buildEmptyState(isLight)
                                  : TradeRepublicCard(
                                      backgroundColor: Colors.transparent,
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                      boxShadow: const [],
                                      padding: EdgeInsets.zero,
                                      child: Column(
                                        children: List.generate(
                                          products.length,
                                          (index) => _buildProductRow(
                                            products[index],
                                            isLight,
                                            index == products.length - 1,
                                          ),
                                        ),
                                      ),
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

  // Trade Republic Style Header - Simple, no glass effects
  Widget _buildTradeRepublicHeader(bool isLight) {
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)?.products ?? AppLocalizations.of(context)!.tr('Products'),
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: isDesktop ? 40 : 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)?.manageYourInventory ?? AppLocalizations.of(context)!.tr('Manage your inventory'),
                style: TextStyle(
                  color: isLight
                      ? Colors.black.withOpacity(0.5)
                      : Colors.white.withOpacity(0.5),
                  fontSize: isDesktop ? 16 : 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          // Add button - Trade Republic minimal
          TradeRepublicButton.icon(
            icon: Icon(CupertinoIcons.add, size: 22),
            onPressed: () => _showAddProductModal(context, isLight),
            backgroundColor: isLight ? Colors.black : Colors.white,
            foregroundColor: isLight ? Colors.white : Colors.black,
            size: 44,
          ),
        ],
      ),
    );
  }

  // Trade Republic Style Summary - Large numbers without containers
  Widget _buildProductsSummary(bool isLight) {
    final totalProducts = products.length;
    final activeProducts = products
        .where(
          (p) =>
              p['status'] == 'active' ||
              p['status'] == 'published' ||
              p['isActive'] == 1,
        )
        .length;
    final draftProducts = products
        .where((p) => p['status'] == 'draft' || p['isActive'] == 0)
        .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total count - large
          Text(
            '$totalProducts',
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
            AppLocalizations.of(context)?.totalProducts ?? AppLocalizations.of(context)!.tr('Total Products'),
            style: TextStyle(
              color: isLight
                  ? Colors.black.withOpacity(0.5)
                  : Colors.white.withOpacity(0.5),
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 20),
          // Status row with dots
          TradeRepublicCard(
            backgroundColor: Colors.transparent,
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            boxShadow: const [],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Active
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34C759),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$activeProducts ${_localized('active')}',
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 24),
                // Draft
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$draftProducts ${_localized('draftLabel')}',
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Icon(
                  CupertinoIcons.chevron_right,
                  color: isLight
                      ? Colors.black.withOpacity(0.3)
                      : Colors.white.withOpacity(0.3),
                  size: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Trade Republic Style Product Row - Minimal list item
  Widget _buildSelectionActionBar(bool isLight) {
    final selectedCount = _selectedProductIds.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TradeRepublicCard(
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        boxShadow: const [],
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  CupertinoIcons.check_mark_circled_solid,
                  size: 18,
                  color: const Color(0xFF34C759),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$selectedCount ${_localized('selected')}',
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: _localized('cancel'),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      if (mounted) setState(() => _selectedProductIds.clear());
                    },
                    isSecondary: true,
                    height: 44,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TradeRepublicButton(
                    label: _localized('delete'),
                    onPressed: () => _showBulkDeleteConfirmation(isLight),
                    isDestructive: true,
                    height: 44,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _productSelectionKey(Map<String, dynamic> product) {
    return product['id']?.toString() ??
        product['product_id']?.toString() ??
        product['title']?.toString() ??
        product.hashCode.toString();
  }

  bool _isProductSelected(Map<String, dynamic> product) {
    return _selectedProductIds.contains(_productSelectionKey(product));
  }

  void _toggleProductSelection(Map<String, dynamic> product) {
    final key = _productSelectionKey(product);
    if (mounted) {
      setState(() {
        if (_selectedProductIds.contains(key)) {
          _selectedProductIds.remove(key);
        } else {
          _selectedProductIds.add(key);
        }
      });
    }
  }

  void _showBulkDeleteConfirmation(bool isLight) {
    if (_selectedProductIds.isEmpty) return;

    final selectedCount = _selectedProductIds.length;

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),
            Row(
              children: [
                Icon(
                  CupertinoIcons.delete,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  _localized('deleteProduct'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '$selectedCount ${_localized('selected')}',
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _localized('deleteProductWarning'),
              style: TextStyle(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                fontSize: DesktopOptimizedWidgets.getFontSize(),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            Row(
              children: [
                Expanded(
                  child: TradeRepublicButton(
                    label: _localized('cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    isSecondary: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TradeRepublicButton(
                    label: _localized('delete'),
                    isDestructive: true,
                    onPressed: () async {
                      Navigator.of(context).pop();

                      final selectedIds = Set<String>.from(_selectedProductIds);
                      int deletedCount = 0;

                      for (final product in List<Map<String, dynamic>>.from(products)) {
                        final key = _productSelectionKey(product);
                        if (!selectedIds.contains(key)) continue;

                        final productId = int.tryParse(product['id']?.toString() ?? AppLocalizations.of(context)!.tr(''));
                        if (productId == null) continue;

                        final success = await _deleteProduct(productId);
                        if (success) deletedCount++;
                      }

                      if (!mounted) return;
                      setState(() => _selectedProductIds.clear());

                      if (deletedCount > 0) {
                        TopNotification.success(
                          context,
                          '${_localized('deleted')}: $deletedCount ${_localized('products')}',
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductRow(
    Map<String, dynamic> product,
    bool isLight,
    bool isLast,
  ) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final stock = product['totalStock'] != null
        ? int.tryParse(product['totalStock'].toString()) ?? 0
        : 0;
    final imageUrl = product['imageUrl'];
    final minPrice =
        double.tryParse(product['minPrice']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ?? 0.0;
    final unitRaw = product['unit'] ?? AppLocalizations.of(context)!.tr('pc');
    final unit = _getUnitAbbreviation(unitRaw);
    final isActive =
        product['status'] == 'active' ||
        product['status'] == 'published' ||
        product['isActive'] == 1;
    final isSelectionMode = _selectedProductIds.isNotEmpty;
    final isSelected = _isProductSelected(product);

    return Column(
      children: [
        TradeRepublicTap(
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _toggleProductSelection(product);
          },
          onTap: () {
            if (_selectedProductIds.isNotEmpty) {
              HapticFeedback.selectionClick();
              _toggleProductSelection(product);
              return;
            }
            _showProductDetailsModal(context, product, isLight);
          },
          child: Container(
            color: isSelected
                ? const Color(0xFF34C759).withOpacity(isLight ? 0.12 : 0.18)
                : Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Row(
                children: [
                // Product Image - Square with rounded corners
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isLight
                        ? Colors.black.withOpacity(0.04)
                        : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    child: imageUrl != null && imageUrl.toString().isNotEmpty
                        ? _buildProductImage(imageUrl, isLight)
                        : Icon(
                            CupertinoIcons.cube_box,
                            color: isLight
                                ? Colors.black.withOpacity(0.3)
                                : Colors.white.withOpacity(0.3),
                            size: 24,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Status dot
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFFFF9500),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              product['title'] ??
                                  (AppLocalizations.of(
                                        context,
                                      )?.unnamedProduct ?? AppLocalizations.of(context)!.tr('Unnamed Product')),
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product['alwaysAvailable'] == 1
                            ? (AppLocalizations.of(context)?.alwaysAvailable ?? AppLocalizations.of(context)!.tr('Always available'))
                            : stock > 0
                            ? '${AppLocalizations.of(context)?.stockCount ?? AppLocalizations.of(context)!.tr('Stock: ')}$stock'
                            : (AppLocalizations.of(context)?.outOfStock ?? AppLocalizations.of(context)!.tr('Out of stock')),
                        style: TextStyle(
                          color: isLight
                              ? Colors.black.withOpacity(0.5)
                              : Colors.white.withOpacity(0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                // Price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      appSettings.formatCurrency(minPrice),
                      style: TextStyle(
                        color: isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${AppLocalizations.of(context)?.perUnit ?? AppLocalizations.of(context)!.tr('per')} $unit',
                      style: TextStyle(
                        color: isLight
                            ? Colors.black.withOpacity(0.4)
                            : Colors.white.withOpacity(0.4),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                if (isSelectionMode)
                  Icon(
                    isSelected
                        ? CupertinoIcons.check_mark_circled_solid
                        : CupertinoIcons.circle,
                    color: isSelected
                        ? const Color(0xFF34C759)
                        : (isLight
                            ? Colors.black.withOpacity(0.25)
                            : Colors.white.withOpacity(0.25)),
                    size: 20,
                  )
                else
                  Icon(
                    CupertinoIcons.chevron_right,
                    color: isLight
                        ? Colors.black.withOpacity(0.3)
                        : Colors.white.withOpacity(0.3),
                    size: 16,
                  ),
                ],
              ),
            ),
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

  Future<bool> _deleteProduct(int productId) async {
    try {
      if (mounted) {
        setState(() => isLoading = true);
      }

      final token = await _resolveAuthToken();

      if (token == null || token.isEmpty) {
        throw Exception('Authentication required');
      }

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/business/products/$productId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      Map<String, dynamic> data = {};
      if (response.body.isNotEmpty) {
        try {
          final parsed = json.decode(response.body);
          if (parsed is Map<String, dynamic>) data = parsed;
        } catch (_) {}
      }

      if (response.statusCode == 200) {

        if (data['success']) {
          HapticFeedback.mediumImpact();

          // Remove product from local list
          if (mounted) {
            setState(() {
              products.removeWhere(
                (p) => p['id']?.toString() == productId.toString(),
              );
            });
          }

          // Show success message
          TopNotification.success(
            context,
            AppLocalizations.of(context)?.productDeletedSuccessfully ?? AppLocalizations.of(context)!.tr('Product deleted successfully'),
          );

          return true;
        } else {
          throw Exception(data['message'] ?? AppLocalizations.of(context)!.tr('Failed to delete product'));
        }
      } else if (response.statusCode == 403) {
        final backendMessage =
            (data['message'] ?? data['error'] ?? AppLocalizations.of(context)!.tr('')).toString();
        throw Exception(
          backendMessage.isNotEmpty
              ? backendMessage
              : 'No permission to delete this product',
        );
      } else if (response.statusCode == 401) {
        final backendMessage =
            (data['message'] ?? data['error'] ?? AppLocalizations.of(context)!.tr('')).toString();
        throw Exception(
          backendMessage.isNotEmpty
              ? backendMessage
              : 'Session expired. Please login again.',
        );
      } else {
        final backendMessage =
            (data['message'] ?? data['error'] ?? AppLocalizations.of(context)!.tr('')).toString();
        throw Exception(
          backendMessage.isNotEmpty
              ? backendMessage
              : 'Server error: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error deleting product: $e');

      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorDeletingProduct ?? AppLocalizations.of(context)!.tr('Error deleting product')}: ${e.toString()}',
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: isLight
                ? Colors.white.withOpacity(0.3)
                : Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.cube_box_fill,
                color: isLight ? Colors.black : Colors.white,
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.products ?? AppLocalizations.of(context)!.tr('Products'),
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TradeRepublicButton.icon(
                icon: Icon(CupertinoIcons.add, size: 24),
                onPressed: () => _showAddProductModal(context, isLight),
                backgroundColor: isLight ? Colors.black : Colors.white,
                foregroundColor: isLight ? Colors.white : Colors.black,
                size: 44,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsHeader(bool isLight) {
    final totalProducts = products.length;
    final publishedProducts = products
        .where(
          (p) =>
              p['status'] == 'active' ||
              p['status'] == 'published' ||
              p['isActive'] == 1,
        )
        .length;
    final draftProducts = products
        .where((p) => p['status'] == 'draft' || p['isActive'] == 0)
        .length;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            AppLocalizations.of(context)?.total ?? AppLocalizations.of(context)!.tr('Total'),
            totalProducts.toString(),
            CupertinoIcons.square_grid_2x2,
            const Color(0xFF007AFF),
            isLight,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            AppLocalizations.of(context)?.active ?? AppLocalizations.of(context)!.tr('Active'),
            publishedProducts.toString(),
            CupertinoIcons.checkmark_circle_fill,
            const Color(0xFF34C759),
            isLight,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            AppLocalizations.of(context)?.draftLabel ?? AppLocalizations.of(context)!.tr('Draft'),
            draftProducts.toString(),
            CupertinoIcons.circle,
            const Color(0xFFFF9500),
            isLight,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isLight,
  ) {
    return TradeRepublicCard(
      padding: (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
          ? const EdgeInsets.all(32)
          : const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Value - large and bold
          Text(
            value,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
              letterSpacing: -1.0,
              height: 1.1,
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          // Title - bold
          Text(
            title,
            style: TextStyle(
              color: isLight
                  ? Colors.black.withOpacity(0.4)
                  : Colors.white.withOpacity(0.4),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(bool isLight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.quickActions ?? AppLocalizations.of(context)!.tr('Quick Actions'),
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionCard(
                AppLocalizations.of(context)?.addProduct ?? AppLocalizations.of(context)!.tr('Add Product'),
                AppLocalizations.of(context)?.createNewProduct ?? AppLocalizations.of(context)!.tr('Create new product'),
                Icons.add_shopping_cart,
                isLight,
                () => _showAddProductModal(context, isLight),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildQuickActionCard(
                AppLocalizations.of(context)?.categoriesLabel ?? AppLocalizations.of(context)!.tr('Categories'),
                AppLocalizations.of(context)?.manageCategories ?? AppLocalizations.of(context)!.tr('Manage categories'),
                Icons.category,
                isLight,
                () => _showCategoriesModal(context, isLight),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(
    String title,
    String subtitle,
    IconData icon,
    bool isLight,
    VoidCallback onTap,
  ) {
    return TradeRepublicCard(
      onTap: onTap,
      padding: DesktopAppWrapper.getPagePadding(),
      child: Column(
        children: [
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: isLight ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Icon(
              icon,
              color: isLight ? Colors.white : Colors.black,
              size: 32,
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Text(
            title,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: isLight ? Colors.black54 : Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFamily: 'Poppins',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getUnitAbbreviation(String? unit) {
    if (unit == null) return 'pc';

    // Convert full unit names to abbreviations
    final abbreviations = {
      'gram': 'g',
      'kilogram': 'kg',
      'tonne': 't',
      'ounce': 'oz',
      'pound': 'lb',
      'piece': 'pc',
      'liter': 'L',
      'milliliter': 'mL',
      'package': 'pk',
    };

    // Return abbreviation if found, otherwise return as-is (might already be abbreviated)
    return abbreviations[unit.toLowerCase()] ?? unit;
  }

  Widget _buildProductCard(Map<String, dynamic> product, bool isLight) {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    final stock = product['totalStock'] != null
        ? int.tryParse(product['totalStock'].toString()) ?? 0
        : 0;
    final imageUrl = product['imageUrl'];

    // Calculate price display based on variants
    final variantCount = product['variantCount'] ?? 1;
    final minPrice =
        double.tryParse(product['minPrice']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ?? 0.0;
    final maxPrice =
        double.tryParse(product['maxPrice']?.toString() ?? AppLocalizations.of(context)!.tr('0.0')) ?? 0.0;
    final unitRaw = product['unit'] ?? AppLocalizations.of(context)!.tr('pc');
    final unit = _getUnitAbbreviation(unitRaw);

    String priceDisplay;
    if (variantCount > 1 && minPrice != maxPrice) {
      // Multiple variants with different prices - show range
      priceDisplay =
          '${appSettings.formatCurrency(minPrice)} - ${appSettings.formatCurrency(maxPrice)}/$unit';
    } else {
      // Single variant or all variants have same price
      priceDisplay = '${appSettings.formatCurrency(minPrice)}/$unit';
    }

    return TradeRepublicTap(
      onTap: () => _showProductDetailsModal(context, product, isLight),
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
          boxShadow:
              (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
              ? [
                  BoxShadow(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.05,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product Image - modern design
            Stack(
              children: [
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isLight
                        ? Colors.black.withOpacity(0.02)
                        : Colors.white.withOpacity(0.02),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    child: imageUrl != null && imageUrl.toString().isNotEmpty
                        ? _buildProductImage(imageUrl, isLight)
                        : _buildImagePlaceholder(isLight),
                  ),
                ),
                // Status badge - minimalist
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isLight ? Colors.black : Colors.white,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                      ),
                    ),
                    child: Text(
                      (product['status'] == 'active' ||
                              product['isActive'] == 1)
                          ? (AppLocalizations.of(context)?.activeLabel ?? AppLocalizations.of(context)!.tr('ACTIVE'))
                          : (AppLocalizations.of(
                                  context,
                                )?.draftLabel.toUpperCase() ?? AppLocalizations.of(context)!.tr('DRAFT')),
                      style: TextStyle(
                        color: isLight ? Colors.white : Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Product Details - minimal design
            Padding(
              padding:
                  (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                  ? const EdgeInsets.all(20)
                  : const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product Name
                  Text(
                    product['title'] ??
                        (AppLocalizations.of(context)?.unnamedProduct ?? AppLocalizations.of(context)!.tr('Unnamed Product')),
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      letterSpacing: 0,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),

                  // Price - minimal
                  Text(
                    priceDisplay,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Stock info - minimal
                  Text(
                    product['alwaysAvailable'] == 1
                        ? (AppLocalizations.of(context)?.alwaysAvailable ?? AppLocalizations.of(context)!.tr('Always available'))
                              .toUpperCase()
                        : stock > 0
                        ? (AppLocalizations.of(
                                context,
                              )?.inStockCount.replaceAll('{0}', '$stock') ??
                              'IN STOCK: $stock')
                        : (AppLocalizations.of(context)?.outOfStock ?? AppLocalizations.of(context)!.tr('Out of stock'))
                              .toUpperCase(),
                    style: TextStyle(
                      color: isLight
                          ? Colors.black.withOpacity(0.3)
                          : Colors.white.withOpacity(0.3),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      letterSpacing: 1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(bool isLight) {
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Center(
        child: Icon(
          CupertinoIcons.photo_fill,
          color: isLight ? Colors.black54 : Colors.white70,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildProductImage(String imageUrl, bool isLight) {
    try {
      // Check if it's a base64 image with data URI
      if (imageUrl.contains(',')) {
        final parts = imageUrl.split(',');
        if (parts.length > 1) {
          return Image.memory(
            base64Decode(parts[1]),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildImagePlaceholder(isLight);
            },
          );
        }
      }

      // Try to decode as pure base64
      return Image.memory(
        base64Decode(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildImagePlaceholder(isLight);
        },
      );
    } catch (e) {
      print('Error decoding image: $e');
      return _buildImagePlaceholder(isLight);
    }
  }

  Widget _buildEmptyState(bool isLight) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.cube_box,
            color: isLight
                ? Colors.black.withOpacity(0.15)
                : Colors.white.withOpacity(0.15),
            size: 48,
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)?.noProducts ?? AppLocalizations.of(context)!.tr('No Products'),
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          Text(
            AppLocalizations.of(context)?.addFirstProductToGetStarted ?? AppLocalizations.of(context)!.tr('Add your first product to get started'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isLight
                  ? Colors.black.withOpacity(0.5)
                  : Colors.white.withOpacity(0.5),
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 32),
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.addProduct ?? AppLocalizations.of(context)!.tr('Add Product'),
            onPressed: () => _showAddProductModal(context, isLight),
          ),
        ],
      ),
    );
  }

  // Delete Product with Confirmation
  void _showDeleteConfirmation(
    BuildContext context,
    Map<String, dynamic> product,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
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
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.deleteProduct ?? AppLocalizations.of(context)!.tr('Delete Product?'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            // Product Name
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Text(
                product['title'] ??
                    (AppLocalizations.of(context)?.thisProduct ?? AppLocalizations.of(context)!.tr('this product')),
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            // Warning Message
            Text(
              AppLocalizations.of(context)?.deleteProductWarning ?? AppLocalizations.of(context)!.tr('This action cannot be undone. All product data, variants, and images will be permanently deleted.'),
              style: TextStyle(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                fontSize: DesktopOptimizedWidgets.getFontSize(),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            // Action Buttons
            Row(
              children: [
                // Cancel Button
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    isSecondary: true,
                  ),
                ),
                const SizedBox(width: 12),
                // Delete Button
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.delete ?? AppLocalizations.of(context)!.tr('Delete'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      final productId = int.tryParse(
                        product['id']?.toString() ?? AppLocalizations.of(context)!.tr(''),
                      );
                      if (productId != null) {
                        _deleteProduct(productId);
                      } else {
                        TopNotification.error(
                          context,
                          AppLocalizations.of(context)?.errorDeletingProduct ?? AppLocalizations.of(context)!.tr('Error deleting product'),
                        );
                      }
                    },
                    isDestructive: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Modal Methods
  void _showAddProductModal(BuildContext context, bool isLight) {
    HapticFeedback.lightImpact();

    // Check verification status first
    if (isVerificationLoading) {
      TopNotification.info(
        context,
        AppLocalizations.of(context)?.loadingVerificationStatus ?? AppLocalizations.of(context)!.tr('Loading verification status...'),
      );
      return;
    }

    if (!BusinessAccountPage.isFullyVerified(userData)) {
      _showVerificationRequiredModal(context, isLight);
      return;
    }

    // Hide navigation to prevent CN component blur effects
    if (mounted) {
      setState(() => _isModalOpen = true);
    }
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      bottomPadding: 20.0,
      enableDrag: true,
      isDismissible: true,
      child: MultiStepProductModal(isLight: isLight),
    ).whenComplete(() {
      // Show navigation again when modal closes
      NavigationVisibility.show();
      if (mounted) {
        setState(() => _isModalOpen = false);
      }
    });
  }

  void _showVerificationRequiredModal(BuildContext context, bool isLight) {
    // Calculate verification score using shared logic
    final verificationScore = BusinessAccountPage.calculateVerificationScore(userData);
    final hasCompleteProfile = BusinessAccountPage.hasCompleteBusinessProfile(userData);
    final hasConnectedBank = BusinessAccountPage.hasConnectedPaymentSetup(userData);

    // Hide navigation
    if (mounted) {
      setState(() => _isModalOpen = true);
    }
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            Row(
              children: [
                Icon(
                  CupertinoIcons.checkmark_shield,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.businessVerificationCenter ?? AppLocalizations.of(context)!.tr('Business Verification Center'),
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

            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Explanation box
                    Container(
                      padding: DesktopAppWrapper.getPagePadding(),
                      decoration: BoxDecoration(
                        color: (isLight ? Colors.black : Colors.white).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.tr('What is Business Verification?'),
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w700,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppLocalizations.of(context)!.tr(
                              'Verification confirms your business on Cultioo. Fully verified accounts receive a Verified badge, more trust from customers, and access to all features including product creation.',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
                              height: 1.45,
                            ),
                          ),
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          Text(
                            AppLocalizations.of(context)!.tr('What is required:'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildVerificationRequirementStep(
                            '1.',
                            AppLocalizations.of(context)!.tr('Complete Business Profile'),
                            AppLocalizations.of(context)!.tr('Business name, email, phone and address must be filled in.'),
                            isLight,
                          ),
                          const SizedBox(height: 4),
                          _buildVerificationRequirementStep(
                            '2.',
                            AppLocalizations.of(context)!.tr('Bank Account / Payment Method'),
                            AppLocalizations.of(context)!.tr('Connect a bank account or payment method in Payment Settings.'),
                            isLight,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Score
                    Text(
                      '$verificationScore% ${AppLocalizations.of(context)!.tr('verified')}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: verificationScore >= 100
                            ? Colors.green
                            : (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Business Profile item
                    _buildVerificationRequirementItem(
                      AppLocalizations.of(context)!.tr('Business Profile'),
                      hasCompleteProfile
                          ? AppLocalizations.of(context)!.tr('Verified')
                          : AppLocalizations.of(context)!.tr('Fill in name, email, phone & address'),
                      CupertinoIcons.person_crop_square_fill,
                      hasCompleteProfile,
                      isLight,
                    ),

                    // Bank Account item
                    _buildVerificationRequirementItem(
                      AppLocalizations.of(context)?.bankAccount ?? AppLocalizations.of(context)!.tr('Bank Account'),
                      hasConnectedBank
                          ? AppLocalizations.of(context)!.tr('Connected')
                          : AppLocalizations.of(context)!.tr('Connect via Payment Settings'),
                      CupertinoIcons.creditcard_fill,
                      hasConnectedBank,
                      isLight,
                    ),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    // Status box
                    Container(
                      width: double.infinity,
                      padding: DesktopAppWrapper.getPagePadding(),
                      decoration: BoxDecoration(
                        color: verificationScore >= 100
                            ? Colors.green.withOpacity(0.08)
                            : Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                      ),
                      child: Text(
                        verificationScore >= 100
                            ? AppLocalizations.of(context)!.tr('Your business is fully verified! You can now create products.')
                            : AppLocalizations.of(context)!.tr('Complete the requirements above to unlock product creation.'),
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w500,
                          color: verificationScore >= 100
                              ? Colors.green
                              : Colors.orange,
                          height: 1.4,
                        ),
                      ),
                    ),

                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

                    // Action Button
                    TradeRepublicButton(
                      label: AppLocalizations.of(context)?.goToBusinessAccount ?? AppLocalizations.of(context)!.tr('Go to Business Account'),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/business_account');
                      },
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      width: double.infinity,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      // Show navigation again when modal closes
      NavigationVisibility.show();
      if (mounted) {
        setState(() => _isModalOpen = false);
      }
    });
  }

  Widget _buildVerificationRequirementItem(
    String title,
    String subtitle,
    IconData icon,
    bool isCompleted,
    bool isLight,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green
                  : (isLight ? Colors.black : Colors.white),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isCompleted
                  ? Colors.white
                  : (isLight ? Colors.white : Colors.black),
            ),
          ),
          const SizedBox(width: 16),
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
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isCompleted
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.clock_fill,
            color: isCompleted
                ? Colors.green
                : (isLight ? Colors.black54 : Colors.white70),
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationRequirementStep(
    String step,
    String title,
    String description,
    bool isLight,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: (isLight ? Colors.black : Colors.white).withOpacity(0.4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$title  ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ),
                TextSpan(
                  text: description,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequirementItem(String text, bool isLight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
          fontSize: DesktopOptimizedWidgets.getFontSize(),
        ),
      ),
    );
  }

  void _showProductDetailsModal(
    BuildContext context,
    Map<String, dynamic> product,
    bool isLight,
  ) {
    // Simply call the edit modal - they are now the same
    _showEditProductModal(context, product, isLight);
  }

  Widget _buildDetailRow(String label, String value, bool isLight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
              fontSize: DesktopOptimizedWidgets.getFontSize(),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProductModal(
    BuildContext context,
    Map<String, dynamic> product,
    bool isLight,
  ) {
    // Hide navigation to prevent CN component blur effects
    if (mounted) {
      setState(() => _isModalOpen = true);
    }
    NavigationVisibility.hide();

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.95,
      bottomPadding: 20.0,
      enableDrag: true,
      isDismissible: true,
      child: MultiStepProductModal(
        isLight: isLight,
        existingVariants: List<Map<String, dynamic>>.from(
          (product['variants'] as List?)?.map((v) => Map<String, dynamic>.from(v)) ?? [],
        ),
        existingPublishStatus: product['publish_status']?.toString(),
        productId: int.tryParse(product['id']?.toString() ?? ''),
      ),
    ).whenComplete(() {
      // Show navigation again when modal closes
      NavigationVisibility.show();
      if (mounted) {
        setState(() => _isModalOpen = false);
      }
    });
  }

  void _showCategoriesModal(BuildContext context, bool isLight) {
    TopNotification.info(
      context,
      AppLocalizations.of(context)?.categoriesComingSoon ?? AppLocalizations.of(context)!.tr('Categories management feature coming soon!'),
    );
  }

  void _showFilterModal(BuildContext context, bool isLight) {
    // Already hidden by CNButton on iOS, hide for Android
    if (mounted) {
      setState(() => _isModalOpen = true);
    }
    if (!Platform.isIOS) {
      NavigationVisibility.hide();
    }

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
                CupertinoIcons.line_horizontal_3_decrease_circle,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.filterProducts ?? AppLocalizations.of(context)!.tr('Filter Products'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Filter Options
          _buildFilterOption(
            AppLocalizations.of(context)?.allProducts ?? AppLocalizations.of(context)!.tr('All Products'),
            CupertinoIcons.cube_box_fill,
            isLight,
            () {
              Navigator.pop(context);
              if (mounted) {
                setState(() {
                  _loadProducts();
                });
              }
            },
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          _buildFilterOption(
            AppLocalizations.of(context)?.publishedLabel ?? AppLocalizations.of(context)!.tr('Published'),
            CupertinoIcons.checkmark_circle_fill,
            isLight,
            () {
              Navigator.pop(context);
              if (mounted) {
                setState(() {
                  products = products
                      .where(
                        (p) =>
                            p['status'] == 'published' ||
                            p['status'] == 'active' ||
                            p['isActive'] == 1,
                      )
                      .toList();
                });
              }
            },
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          _buildFilterOption(
            AppLocalizations.of(context)?.draftLabel ?? AppLocalizations.of(context)!.tr('Draft'),
            Icons.drafts,
            isLight,
            () {
              Navigator.pop(context);
              if (mounted) {
                setState(() {
                  products = products
                      .where(
                        (p) => p['status'] == 'draft' || p['isActive'] == 0,
                      )
                      .toList();
                });
              }
            },
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
          // Cancel Button
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            onPressed: () => Navigator.pop(context),
            isSecondary: true,
            width: double.infinity,
          ),
        ],
      ),
    ).whenComplete(() {
      NavigationVisibility.show();
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  Widget _buildFilterOption(
    String title,
    IconData icon,
    bool isLight,
    VoidCallback onTap,
  ) {
    return TradeRepublicListTile.navigation(
      title: title,
      leading: Icon(icon, size: 22),
      onTap: onTap,
    );
  }

  // Sort Modal
  void _showSortModal(BuildContext context, bool isLight) {
    // Already hidden by CNButton on iOS, hide for Android
    if (mounted) setState(() => _isModalOpen = true);
    if (!Platform.isIOS) {
      NavigationVisibility.hide();
    }

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
                CupertinoIcons.arrow_up_arrow_down,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.sortProducts ?? AppLocalizations.of(context)!.tr('Sort Products'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          // Sort Options
          _buildSortOption(
            AppLocalizations.of(context)?.nameAZ ?? AppLocalizations.of(context)!.tr('Name (A-Z)'),
            Icons.sort_by_alpha,
            isLight,
            () {
              Navigator.pop(context);
              if (mounted) {
                setState(() {
                  products.sort(
                    (a, b) => (a['title'] ?? AppLocalizations.of(context)!.tr('')).toString().compareTo(
                      (b['title'] ?? AppLocalizations.of(context)!.tr('')).toString(),
                    ),
                  );
                });
              }
            },
          ),
          const SizedBox(height: 6),
          _buildSortOption(
            AppLocalizations.of(context)?.priceLowToHigh ?? AppLocalizations.of(context)!.tr('Price (Low to High)'),
            Icons.arrow_upward,
            isLight,
            () {
              Navigator.pop(context);
              setState(() {
                products.sort((a, b) {
                  double priceA =
                      double.tryParse(a['price']?.toString() ?? '0') ?? 0.0;
                  double priceB =
                      double.tryParse(b['price']?.toString() ?? '0') ?? 0.0;
                  return priceA.compareTo(priceB);
                });
              });
            },
          ),
          const SizedBox(height: 6),
          _buildSortOption(
            AppLocalizations.of(context)?.priceHighToLow ?? AppLocalizations.of(context)!.tr('Price (High to Low)'),
            Icons.arrow_downward,
            isLight,
            () {
              Navigator.pop(context);
              setState(() {
                products.sort((a, b) {
                  double priceA =
                      double.tryParse(a['price']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ?? 0;
                  double priceB =
                      double.tryParse(b['price']?.toString() ?? AppLocalizations.of(context)!.tr('0')) ?? 0;
                  return priceB.compareTo(priceA);
                });
              });
            },
          ),
          const SizedBox(height: 6),
          _buildSortOption(
            AppLocalizations.of(context)?.recentlyAdded ?? AppLocalizations.of(context)!.tr('Recently Added'),
            Icons.access_time,
            isLight,
            () {
              Navigator.pop(context);
              setState(() {
                products.sort((a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0));
              });
            },
          ),
          const SizedBox(height: 10),
          // Cancel Button
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            onPressed: () => Navigator.pop(context),
            isSecondary: true,
            width: double.infinity,
          ),
        ],
      ),
    ).whenComplete(() {
      NavigationVisibility.show();
      setState(() => _isModalOpen = false);
    });
  }

  Widget _buildSortOption(
    String title,
    IconData icon,
    bool isLight,
    VoidCallback onTap,
  ) {
    return TradeRepublicListTile(
      title: title,
      leading: Icon(icon, size: 22),
      onTap: onTap,
    );
  }
}

// Separate StatefulWidget for the Multi-Step Modal
class MultiStepProductModal extends StatefulWidget {
  final bool isLight;
  final List<Map<String, dynamic>>? existingVariants;
  final String? existingPublishStatus;
  final bool isEditMode;
  final int? productId;

  const MultiStepProductModal({
    super.key,
    required this.isLight,
    this.existingVariants,
    this.existingPublishStatus,
    this.isEditMode = false,
    this.productId,
  });

  @override
  State<MultiStepProductModal> createState() => _MultiStepProductModalState();
}

class _MultiStepProductModalState extends State<MultiStepProductModal> {
  int currentStep = 1;
  final totalSteps = 6;

  // Controllers for step 1
  final titleController = TextEditingController();
  final subtitleController = TextEditingController();
  final descriptionController = TextEditingController();
  String selectedCategory = 'Fruits & Vegetables';

  // Varianten Liste - starts with one default variant
  List<Map<String, dynamic>> variants = [];

  // Step 6 - Publish status
  String publishStatus = 'draft'; // 'draft' or 'publish'

  // Validation errors - tracks which fields have errors
  Set<String> validationErrors = {};

  // Geocoding state
  final bool _isGeocodingLocation = false;

  // Clear validation error for a specific field
  void _clearValidationError(String fieldKey) {
    if (validationErrors.contains(fieldKey)) {
      setState(() {
        validationErrors.remove(fieldKey);
      });
    }
  }

  @override
  void initState() {
    super.initState();

    // If editing, use existing data, otherwise create new variant
    if (widget.existingVariants != null &&
        widget.existingVariants!.isNotEmpty) {
      variants = List<Map<String, dynamic>>.from(widget.existingVariants!);
      publishStatus = widget.existingPublishStatus ?? AppLocalizations.of(context)!.tr('draft');
    } else {
      // Create the first variant automatically for new products WITH all required structures
      variants.add({
        'title': '',
        'subtitle': '',
        'category': selectedCategory,
        'description': '',
        'name': '',
        'price': 0.0,
        'stock': 0,
        'unit': 'gram',
        'alwaysAvailable': false,
        'dailyProduction': 0.0, // Daily production capacity as double
        'minOrder': 1,
        'images': [],
        'isDefault': true,
        'nutrition': {
          'energy_kj': '',
          'energy_kcal': '',
          'fat': '',
          'fsat': '',
          'carb': '',
          'sugar': '',
          'protein': '',
          'salt': '',
          'servingSize': 'per100g',
        },
        'additionalDetails': {
          'origin': '',
          'bioControlNr': '',
          'features': '',
          'ingredients': '',
          'allergens': '',
          'fillAmount': '',
          'fillUnit': '',
          'organic': false,
          'terpenes': '',
        },
        'shipping': {
          'deliveryTime': '3',
          'tracking_available': true,
          'delivery_instructions': '',
          'special_handling': '',
          'temperature_requirements': '',
          'packaging_type': '',
        },
        'location': {
          'street': '',
          'zip': '',
          'city': '',
          'country': 'Germany',
          'lat': 0.0,
          'lng': 0.0,
          'delivery_area': '',
        },
      });
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    subtitleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  String _getCurrencySymbol() {
    // Get currency from AppSettings
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    return appSettings.currencySymbol;
  }

  String _getStepTitle() {
    switch (currentStep) {
      case 1:
        return AppLocalizations.of(context)?.step1ProductVariants ?? AppLocalizations.of(context)!.tr('Step 1: Product Variants');
      case 2:
        return AppLocalizations.of(context)?.step2ImagesMedia ?? AppLocalizations.of(context)!.tr('Step 2: Images & Media');
      case 3:
        return AppLocalizations.of(context)?.step3PricingStock ?? AppLocalizations.of(context)!.tr('Step 3: Pricing & Stock');
      case 4:
        return AppLocalizations.of(context)?.step4NutritionDetails ?? AppLocalizations.of(context)!.tr('Step 4: Nutrition & Details');
      case 5:
        return AppLocalizations.of(context)?.step5ShippingLocation ?? AppLocalizations.of(context)!.tr('Step 5: Shipping & Location');
      case 6:
        return widget.isEditMode
            ? (AppLocalizations.of(context)?.reviewAndSave ?? AppLocalizations.of(context)!.tr(''))
            : (AppLocalizations.of(context)?.reviewAndPublish ?? AppLocalizations.of(context)!.tr(''));
      default:
        return 'Step $currentStep of $totalSteps';
    }
  }

  bool _isStep3Valid() {
    // Allow proceeding even if fields are not filled
    return true;
  }

  /// Returns the translated display name for a category DB key.
  String _translateCategory(String key) =>
      translateProductCategory(key, context);

  bool _isStep4Valid() {
    // Step 4 is optional, but if nutrition data is entered, validate it
    for (var variant in variants) {
      final nutrition = variant['nutrition'] as Map<String, dynamic>?;
      if (nutrition != null) {
        // Check if any nutrition values are negative
        for (var value in nutrition.values) {
          if (value is String && value.isNotEmpty) {
            final numValue = double.tryParse(value);
            if (numValue != null && numValue < 0) {
              return false; // No negative nutrition values
            }
          }
        }
      }
    }
    return true; // Step 4 is always valid (optional information)
  }

  bool _isStep5Valid() {
    // Clear previous validation errors
    validationErrors.clear();

    // Step 5 validation - ALL FIELDS ARE OPTIONAL
    // User can proceed without filling anything
    // This step is for optional shipping and location information

    return true; // Step 5 is always valid (all fields are optional)
  }

  Future<void> _saveProduct() async {
    // Track whether the loading bottom sheet is currently open so the catch
    // block only pops it when it was actually shown (prevents double-pop).
    bool loadingSheetOpen = false;

    try {
      // Validate step 5 before saving
      if (!_isStep5Valid()) {
        _showValidationBottomSheet(
          context,
          AppLocalizations.of(context)?.missingInformation ?? AppLocalizations.of(context)!.tr('Missing Information'),
          AppLocalizations.of(context)?.pleaseFillShippingFields ?? AppLocalizations.of(context)!.tr('Please fill in all required shipping and location fields.'),
          CupertinoIcons.exclamationmark_circle,
          Colors.orange,
        );
        return;
      }

      // Geocode address before saving
      if (variants.isNotEmpty) {
        final location = variants.first['location'];
        if (location != null) {
          final city = location['city']?.toString().trim() ?? AppLocalizations.of(context)!.tr('');
          if (city.isNotEmpty) {
            print('🗺️ Geocoding address before save...');
            final coordsFound = await _updateCoordinatesFromAddress(location);
            print('🗺️ Coordinates: ${location['lat']}, ${location['lng']}');
            if (!coordsFound) {
              if (mounted) {
                _showValidationBottomSheet(
                  context,
                  'Address Not Found',
                  'Could not find coordinates for the entered address. Please check the street, city and country.',
                  CupertinoIcons.location_slash,
                  Colors.red,
                );
              }
              return;
            }
          }
        }
      }

      if (!mounted) return;

      // Capture everything we need from context BEFORE any Navigator.pop calls.
      // After the modal is popped this widget is unmounted and context is invalid.
      final appSettings = Provider.of<AppSettings>(context, listen: false);
      final String? token = appSettings.authToken;
      final l10n = AppLocalizations.of(context);
      final isEditMode = widget.isEditMode;
      final productId = widget.productId;
      final isLight = widget.isLight;
      final currentPublishStatus = publishStatus;
      final productsPageState = context
          .findAncestorStateOfType<_ProductsPageState>();

      if (token == null || token.isEmpty) {
        print('⚠️ No auth token found in AppSettings');
        _showValidationBottomSheet(
          context,
          l10n?.authenticationError ?? AppLocalizations.of(context)!.tr('Authentication Error'),
          l10n?.needToBeLoggedInToSaveProducts ?? AppLocalizations.of(context)!.tr('You need to be logged in to save products. Please log out and log in again.'),
          Icons.lock_outline,
          Colors.red,
        );
        return;
      }

      print('✅ Using auth token from AppSettings');

      // Prepare payload - map frontend field names to backend expectations
      final variantsForBackend = variants.map((variant) {
        // Create a copy and rename 'description' to 'longDesc'
        final variantCopy = Map<String, dynamic>.from(variant);
        if (variantCopy.containsKey('description')) {
          variantCopy['longDesc'] = variantCopy['description'];
          variantCopy.remove('description');
        }

        return variantCopy;
      }).toList();

      final payload = {
        'publishStatus': publishStatus,
        'variants': variantsForBackend,
      };

      print('💾 Publishing status: $publishStatus');
      print('💾 Number of variants: ${variants.length}');

      // Debug: Log variant data before encoding
      for (int i = 0; i < variantsForBackend.length; i++) {
        final v = variantsForBackend[i];
        print('💾 Variant $i:');
        print('   - title: ${v['title']}');
        print('   - subtitle: ${v['subtitle']}');
        print('   - longDesc: ${v['longDesc']}');
        print('   - category: ${v['category']}');
        print('   - price: ${v['price']}');
        print('   - stock: ${v['stock']}');
        print('   - unit: ${v['unit']}');
        print('   - minOrder: ${v['minOrder']}');
        print('   - alwaysAvailable: ${v['alwaysAvailable']}');
        print('   - images: ${v['images']?.length ?? 0} images');

        // Log shipping details
        final shipping = v['shipping'] as Map<String, dynamic>?;
        if (shipping != null) {
          print('   - shipping:');
          print('     - incoterm: ${shipping['incoterm']}');
          print('     - wagonType: ${shipping['wagonType']}');
          print('     - deliveryTime: ${shipping['deliveryTime']}');
          print(
            '     - cleaning_certificate: ${shipping['cleaning_certificate']}',
          );
        }

        // Log location details
        final location = v['location'] as Map<String, dynamic>?;
        if (location != null) {
          print('   - location:');
          print('     - street: ${location['street']}');
          print('     - city: ${location['city']}');
          print('     - country: ${location['country']}');
        }
      }

      print('💾 Attempting to encode payload...');

      String jsonPayload;
      try {
        jsonPayload = json.encode(payload);
        print('💾 Payload encoded successfully (${jsonPayload.length} bytes)');
      } catch (e) {
        print('❌ Error encoding payload: $e');
        throw Exception('Failed to encode product data: $e');
      }

      // Show loading bottom sheet (AFTER all context captures above)
      loadingSheetOpen = true;
      if (mounted) {
        TradeRepublicBottomSheet.show(
          context: context,
          bottomPadding: 20.0,
          isDismissible: false,
          enableDrag: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DragHandle(),
              CultiooLoadingIndicator(),
              const SizedBox(height: 4),
              Text(
                l10n?.savingProduct ?? AppLocalizations.of(context)!.tr('Saving Product...'),
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      }

      print(
        '💾 Sending ${isEditMode ? "PUT" : "POST"} request to: ${ApiConfig.baseUrl}/api/business/products${isEditMode ? "/$productId" : ""}',
      );

      // Send to API - use PUT for edit, POST for create
      final response = isEditMode
          ? await http
                .put(
                  Uri.parse(
                    '${ApiConfig.baseUrl}/api/business/products/$productId',
                  ),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Content-Type': 'application/json',
                  },
                  body: jsonPayload,
                )
                .timeout(
                  const Duration(seconds: 30),
                  onTimeout: () {
                    throw Exception('Request timed out after 30 seconds');
                  },
                )
          : await http
                .post(
                  Uri.parse('${ApiConfig.baseUrl}/api/business/products'),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Content-Type': 'application/json',
                  },
                  body: jsonPayload,
                )
                .timeout(
                  const Duration(seconds: 30),
                  onTimeout: () {
                    throw Exception('Request timed out after 30 seconds');
                  },
                );

      print('📦 Save response: ${response.statusCode}');
      print('📦 Response body: ${response.body}');

      // Close loading sheet
      loadingSheetOpen = false;
      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Product saved successfully!');

        // Close the product modal
        if (mounted) Navigator.pop(context);

        // Reload products list using the pre-captured parent state reference
        productsPageState?._loadProducts();

        // Show success notification via the parent's context because this
        // widget is now unmounted after the modal was popped above.
        if (productsPageState != null && productsPageState.mounted) {
          final parentCtx = productsPageState.context;
          if (isEditMode) {
            TopNotification.success(
              parentCtx,
              l10n?.productUpdatedSuccessfully ?? AppLocalizations.of(context)!.tr('Product updated successfully!'),
            );
          } else if (currentPublishStatus == 'publish') {
            TopNotification.success(
              parentCtx,
              l10n?.productPublishedSuccessfully ?? AppLocalizations.of(context)!.tr('Product published successfully!'),
            );
          } else {
            TopNotification.info(
              parentCtx,
              l10n?.productSavedAsDraft ?? AppLocalizations.of(context)!.tr('Product saved as draft!'),
            );
          }
        }
      } else {
        print('⚠️ Unexpected response code: ${response.statusCode}');
        String backendMessage = '';
        try {
          final parsed = json.decode(response.body);
          if (parsed is Map<String, dynamic>) {
            backendMessage = (parsed['message'] ?? parsed['error'] ?? AppLocalizations.of(context)!.tr(''))
                .toString()
                .trim();
            if ((parsed['openOrdersCount'] ?? 0) is num &&
                (parsed['openOrdersCount'] as num) > 0) {
              backendMessage =
                  '$backendMessage (${parsed['openOrdersCount']} open orders)';
            }
          }
        } catch (_) {}

        throw Exception(
          backendMessage.isNotEmpty
              ? backendMessage
              : 'Failed to save: ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Error in _saveProduct: $e');
      print('❌ Stack trace: ${StackTrace.current}');

      // Only close the loading sheet if it was actually opened and not yet closed.
      // Without this guard a successful save followed by a post-pop error would
      // pop the ProductsPage and cause a black screen.
      if (loadingSheetOpen && mounted) {
        loadingSheetOpen = false;
        try {
          Navigator.pop(context);
        } catch (_) {}
      }

      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.errorSavingProduct ?? AppLocalizations.of(context)!.tr('Error saving product')}: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Main scrollable content that can go behind floating navigation
        Column(
          children: [
            const DragHandle(),
            // Progress Bar Header
            _buildProgressHeader(),

            // Content basierend auf aktuellem Schritt - kann dahinter scrollen
            Expanded(child: _buildStepContent()),
          ],
        ),

        // Floating Bottom Navigation - positioned over content
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildFloatingBottomNavigation(),
        ),
      ],
    );
  }

  Widget _buildProgressHeader() {
    final progress = currentStep / totalSteps;
    return Container(
      padding: const EdgeInsets.all(0),
      decoration: const BoxDecoration(),
      child: Column(
        children: [
          // Header mit Titel
          Center(
            child: Text(
              widget.isEditMode
                  ? (AppLocalizations.of(context)?.editProduct ?? AppLocalizations.of(context)!.tr('Edit Product'))
                  : (AppLocalizations.of(context)?.addNewProduct ?? AppLocalizations.of(context)!.tr('Add New Product')),
              style: TextStyle(
                color: widget.isLight ? Colors.black : Colors.white,
                fontSize: DesktopOptimizedWidgets.getFontSize() + 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Progress Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getStepTitle(),
                    style: TextStyle(
                      color: widget.isLight ? Colors.black54 : Colors.white54,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(
                      color: widget.isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              ClipRRect(
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: widget.isLight
                      ? Colors.black.withOpacity(0.1)
                      : Colors.white.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.isLight ? Colors.black : Colors.white,
                  ),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (currentStep) {
      case 1:
        return _buildStep1Content();
      case 2:
        return _buildStep2Content();
      case 3:
        return _buildStep3Content();
      case 4:
        return _buildStep4Content();
      case 5:
        return _buildStep5Content();
      case 6:
        return _buildStep6Content();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1Content() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: Platform.isIOS ? 400 : 350,
      ), // Extra space for CNTabBar on iOS
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildVariantsSection()],
      ),
    );
  }

  Widget _buildVariantsSection() {
    return Padding(
      padding: DesktopAppWrapper.getPagePadding(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.isLight
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Icon(
                  CupertinoIcons.cube_box,
                  color: widget.isLight ? Colors.black : Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.productVariants ?? AppLocalizations.of(context)!.tr('Product Variants'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)?.createDifferentVersions ?? AppLocalizations.of(context)!.tr('Create different versions of your product'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black54 : Colors.white54,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Variant 1 is always shown (automatically created in initState)
          _buildVariantCard(variants[0], 0),

          // Weitere Varianten anzeigen (falls vorhanden)
          if (variants.length > 1) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            _buildVariantCard(variants[1], 1),
          ],

          // Add Variant 2 Button (only if we don't have a second variant yet)
          if (variants.length == 1) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            TradeRepublicTap(
              onTap: () {
                setState(() {
                  // Add second variant
                  variants.add({
                    'title': '',
                    'subtitle': '',
                    'category': selectedCategory,
                    'description': '',
                    'name': '',
                    'price': 0.0,
                    'stock': 0,
                    'isDefault': false,
                  });
                });
              },
              child: Container(
                padding: DesktopAppWrapper.getPagePadding(),
                decoration: BoxDecoration(
                  color: widget.isLight ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.add_circled,
                      color: widget.isLight ? Colors.black : Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.addVariant ?? AppLocalizations.of(context)!.tr('Add Variant 2'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Add More Variants Button (ab der 3. Variante)
          if (variants.length >= 2) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            TradeRepublicTap(
              onTap: () {
                setState(() {
                  variants.add({
                    'title': '',
                    'subtitle': '',
                    'category': selectedCategory,
                    'description': '',
                    'name': '',
                    'price': 0.0,
                    'stock': 0,
                    'isDefault': false,
                  });
                });
              },
              child: Container(
                padding: DesktopAppWrapper.getPagePadding(),
                decoration: BoxDecoration(
                  color: widget.isLight ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.add_circled,
                      color: widget.isLight ? Colors.black : Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.addAnotherVariant ?? AppLocalizations.of(context)!.tr('Add Another Variant'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Weitere Varianten anzeigen (ab der 3. Variante)
          ...variants.skip(2).toList().asMap().entries.map((entry) {
            int index = entry.key + 2;
            Map<String, dynamic> variant = entry.value;

            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _buildVariantCard(variant, index),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildVariantCard(Map<String, dynamic> variant, int index) {
    final categories = [
      "Fruits & Vegetables",
      "Dairy & Eggs",
      "Meat & Sausages",
      "Bakery Products",
      "Jams & Spreads",
      "Honey",
      "Cereal Products",
      "Beverages",
      "Spices & Oils",
      "Fish & Seafood",
      "Cheese",
      "Snacks & Sweets",
      "Ice Cream",
      "Bakery Products (frozen)",
      "Soups & Ready Meals",
      "Salads & Delicacies",
      "Plants & Herbs",
      "Non-Food",
      "Canned & Preserved",
      "Pasta & Noodles",
      "Sauces & Dips",
      "Vegan & Vegetarian",
      "Organic Products",
      "Regional Specialties",
      "Gift Items",
    ];

    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  variant['name']?.isEmpty ?? true
                      ? '${AppLocalizations.of(context)?.variantLabel ?? AppLocalizations.of(context)!.tr('Variant')} ${index + 1}'
                      : variant['name'],
                  style: TextStyle(
                    color: widget.isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (variants.length > 1)
                TradeRepublicButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 22),
                  size: 38,
                  isSecondary: true,
                  onPressed: () {
                    setState(() {
                      variants.removeAt(index);
                      // If this was the default variant and others still exist
                      if ((variant['isDefault'] ?? false) &&
                          variants.isNotEmpty) {
                        variants[0]['isDefault'] = true;
                      }
                    });
                  },
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Complete product information for each variant
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titel
              _buildVariantFormField(
                AppLocalizations.of(context)?.productTitle ?? AppLocalizations.of(context)!.tr('Product Title'),
                'e.g. Premium OG Kush',
                variant['title'] ?? AppLocalizations.of(context)!.tr(''),
                (value) => variant['title'] = value,
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Subtitle
              _buildVariantFormField(
                (AppLocalizations.of(context)?.subtitleLabel ?? AppLocalizations.of(context)!.tr('Subtitle')),
                'e.g. Indoor Grown, High THC',
                variant['subtitle'] ?? AppLocalizations.of(context)!.tr(''),
                (value) => variant['subtitle'] = value,
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Kategorie
              _buildVariantCategoryDropdown(variant, categories),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Beschreibung
              _buildVariantFormField(
                AppLocalizations.of(context)?.description ?? AppLocalizations.of(context)!.tr('Description'),
                AppLocalizations.of(context)?.detailedProductDescription ?? AppLocalizations.of(context)!.tr('Detailed product description...'),
                variant['description'] ?? AppLocalizations.of(context)!.tr(''),
                (value) => variant['description'] = value,
                maxLines: 3,
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVariantFormField(
    String label,
    String hint,
    String initialValue,
    Function(String) onChanged, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TradeRepublicTextField(
      key: ValueKey(label),
      useFormField: true,
      initialValue: initialValue,
      hintText: hint,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
    );
  }

  // Modern Apple-style dropdown arrow for all selection boxes
  Widget _buildModernDropdownIcon() {
    return Icon(
      CupertinoIcons.chevron_down,
      size: 20,
      color: widget.isLight ? Colors.black87 : Colors.white70,
    );
  }

  Widget _buildVariantCategoryDropdown(
    Map<String, dynamic> variant,
    List<String> categories,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.categoryLabel ?? AppLocalizations.of(context)!.tr('Category'),
          style: TextStyle(
            color: widget.isLight ? Colors.black : Colors.white,
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        TradeRepublicTap(
          onTap: () => _showCategoryBottomSheet(variant, categories),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: widget.isLight ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _translateCategory(variant['category'] ?? selectedCategory),
                    style: TextStyle(
                      color: widget.isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                    ),
                  ),
                ),
                _buildModernDropdownIcon(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Content() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: Platform.isIOS ? 400 : 350,
      ), // Extra space for CNTabBar on iOS
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildImagesSection()],
      ),
    );
  }

  Widget _buildImagesSection() {
    return Padding(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                CupertinoIcons.photo_fill,
                color: widget.isLight ? Colors.black : Colors.white,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.productImages ?? AppLocalizations.of(context)!.tr('Product Images'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)?.uploadPhotosOfProduct ?? AppLocalizations.of(context)!.tr('Upload photos of your product'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black54 : Colors.white54,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Show images for each variant
          if (variants.isNotEmpty) ...[
            ...variants.asMap().entries.map((entry) {
              int index = entry.key;
              Map<String, dynamic> variant = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index < variants.length - 1 ? 20 : 0,
                ),
                child: _buildVariantImageSection(variant, index),
              );
            }),
          ] else ...[
            // For first variant (if none created yet)
            _buildVariantImageSection({
              'title':
                  AppLocalizations.of(context)?.newProduct ?? AppLocalizations.of(context)!.tr('New Product'),
              'images': [],
            }, 0),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantImageSection(Map<String, dynamic> variant, int index) {
    // Initialize images if not present
    if (variant['images'] == null) {
      variant['images'] = <String>[];
    }

    List<String> images = List<String>.from(variant['images'] ?? []);

    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Variant Header
          Row(
            children: [
              Expanded(
                child: Text(
                  variant['title']?.isNotEmpty == true
                      ? variant['title']
                      : '${AppLocalizations.of(context)?.variantLabel ?? AppLocalizations.of(context)!.tr('Variant')} ${index + 1}',
                  style: TextStyle(
                    color: widget.isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${images.length}/5',
                style: TextStyle(
                  color: (widget.isLight ? Colors.black : Colors.white)
                      .withOpacity(0.4),
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                ),
              ),
            ],
          ),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Image Grid
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: (images.length < 5) ? images.length + 1 : 5,
            itemBuilder: (context, imageIndex) {
              if (imageIndex < images.length) {
                // Vorhandenes Bild anzeigen + Drag & Drop Reordering
                return DragTarget<int>(
                  onWillAcceptWithDetails: (details) =>
                      details.data != imageIndex,
                  onAcceptWithDetails: (details) {
                    setState(() {
                      final fromIndex = details.data;
                      final updatedImages = List<String>.from(images);
                      if (fromIndex < 0 || fromIndex >= updatedImages.length) {
                        return;
                      }

                      final movedImage = updatedImages.removeAt(fromIndex);
                      final targetIndex =
                          fromIndex < imageIndex ? imageIndex - 1 : imageIndex;

                      updatedImages.insert(targetIndex, movedImage);
                      variant['images'] = updatedImages;
                    });
                  },
                  builder: (context, candidateData, rejectedData) {
                    return LongPressDraggable<int>(
                      data: imageIndex,
                      feedback: SizedBox(
                        width: 110,
                        height: 110,
                        child: Opacity(
                          opacity: 0.9,
                          child: _buildImageTile(
                            images[imageIndex],
                            () {},
                            false,
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: _buildImageTile(images[imageIndex], () {
                          setState(() {
                            images.removeAt(imageIndex);
                            variant['images'] = images;
                          });
                        }, false),
                      ),
                      child: _buildImageTile(images[imageIndex], () {
                        setState(() {
                          images.removeAt(imageIndex);
                          variant['images'] = images;
                        });
                      }, false),
                    );
                  },
                );
              } else {
                // Add Image Button (also as drop zone for moving to end)
                return DragTarget<int>(
                  onWillAcceptWithDetails: (details) =>
                      details.data >= 0 && details.data < images.length,
                  onAcceptWithDetails: (details) {
                    setState(() {
                      final fromIndex = details.data;
                      final updatedImages = List<String>.from(images);
                      if (fromIndex < 0 || fromIndex >= updatedImages.length) {
                        return;
                      }
                      final movedImage = updatedImages.removeAt(fromIndex);
                      updatedImages.add(movedImage);
                      variant['images'] = updatedImages;
                    });
                  },
                  builder: (context, candidateData, rejectedData) {
                    return _buildAddImageTile(() {
                      _showImagePicker(variant);
                    });
                  },
                );
              }
            },
          ),

          if (images.isEmpty) ...[
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Container(
              width: double.infinity,
              padding: DesktopAppWrapper.getPagePadding(),
              decoration: BoxDecoration(
                color: widget.isLight ? Colors.white : Colors.black,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.photo_camera,
                    size: 32,
                    color: widget.isLight ? Colors.black54 : Colors.white54,
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Text(
                    AppLocalizations.of(context)?.noImagesAddedYet ?? AppLocalizations.of(context)!.tr('No images added yet'),
                    style: TextStyle(
                      color: widget.isLight ? Colors.black54 : Colors.white54,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
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

  Widget _buildImageTile(
    String imagePath,
    VoidCallback onRemove,
    bool isPlaceholder,
  ) {
    // Check if image is base64, local file, or network URL
    bool isBase64 = imagePath.startsWith('data:image/');
    bool isLocalFile =
        imagePath.startsWith('/') || imagePath.startsWith('file://');

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
              child: isPlaceholder
                  ? Icon(
                      CupertinoIcons.photo_fill,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.4),
                      size: 24,
                    )
                  : isBase64
                  ? _buildBase64Image(imagePath)
                  : isLocalFile
                  ? Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: (widget.isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4),
                          size: 24,
                        );
                      },
                    )
                  : Image.network(
                      imagePath,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: (widget.isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4),
                          size: 24,
                        );
                      },
                    ),
            ),
          ),
          if (!isPlaceholder)
            Positioned(
              top: 4,
              right: 4,
              child: TradeRepublicTap(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBase64Image(String base64String) {
    try {
      // Remove data URI prefix if present
      String base64Data = base64String;
      if (base64String.contains(',')) {
        base64Data = base64String.split(',')[1];
      }

      final bytes = base64Decode(base64Data);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Error displaying base64 image: $error');
          return Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
              0.4,
            ),
            size: 24,
          );
        },
      );
    } catch (e) {
      print('❌ Error decoding base64 image: $e');
      return Icon(
        CupertinoIcons.exclamationmark_triangle,
        color: (widget.isLight ? Colors.black : Colors.white).withOpacity(0.4),
        size: 24,
      );
    }
  }

  Widget _buildAddImageTile(VoidCallback onTap) {
    return TradeRepublicTap(
      onTap: onTap,
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: widget.isLight ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.photo_camera,
              size: 24,
              color: widget.isLight ? Colors.black54 : Colors.white54,
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)?.add ?? AppLocalizations.of(context)!.tr('Add'),
              style: TextStyle(
                color: widget.isLight ? Colors.black54 : Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePicker(Map<String, dynamic> variant) {
    final isLight = Provider.of<AppSettings>(
      context,
      listen: false,
    ).isLightMode(context);
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
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
                  CupertinoIcons.camera,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.addImage ?? AppLocalizations.of(context)!.tr('Add Image'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            Row(
              children: [
                Expanded(
                  child: _buildImagePickerOption(
                    AppLocalizations.of(context)?.camera ?? AppLocalizations.of(context)!.tr('Camera'),
                    CupertinoIcons.camera_fill,
                    () => _pickImageFromCamera(variant),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildImagePickerOption(
                    AppLocalizations.of(context)?.gallery ?? AppLocalizations.of(context)!.tr('Gallery'),
                    Icons.photo_library,
                    () => _pickImageFromGallery(variant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerOption(
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return TradeRepublicTap(
      onTap: onTap, // Execute callback directly without closing modal
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: widget.isLight ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 28,
              color: widget.isLight ? Colors.black : Colors.white,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                color: widget.isLight ? Colors.black : Colors.white,
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickImageFromCamera(Map<String, dynamic> variant) async {
    try {
      // Close image picker modal BEFORE opening camera
      Navigator.pop(context);

      // Small delay to let modal close
      await Future.delayed(const Duration(milliseconds: 100));

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null && mounted) {
        // Convert image to base64
        try {
          final bytes = await File(image.path).readAsBytes();
          final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

          setState(() {
            List<String> images = List<String>.from(variant['images'] ?? []);
            if (images.length < 5) {
              images.add(base64Image);
              variant['images'] = images;
            }
          });
          print('✅ Image converted to base64 (${bytes.length} bytes)');
        } catch (e) {
          print('❌ Error converting image to base64: $e');
          if (mounted) {
            TopNotification.error(
              context,
              '${AppLocalizations.of(context)?.failedToProcessImage ?? AppLocalizations.of(context)!.tr('Failed to process image')}: $e',
            );
          }
        }
      }
    } catch (e) {
      print('Error picking image from camera: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.failedToTakePhoto ?? AppLocalizations.of(context)!.tr('Failed to take photo')}: $e',
        );
      }
    }
  }

  void _pickImageFromGallery(Map<String, dynamic> variant) async {
    try {
      // Close image picker modal BEFORE opening gallery
      Navigator.pop(context);

      // Small delay to let modal close
      await Future.delayed(const Duration(milliseconds: 100));

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null && mounted) {
        // Convert image to base64
        try {
          final bytes = await File(image.path).readAsBytes();
          final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

          setState(() {
            List<String> images = List<String>.from(variant['images'] ?? []);
            if (images.length < 5) {
              images.add(base64Image);
              variant['images'] = images;
            }
          });
          print('✅ Image converted to base64 (${bytes.length} bytes)');
        } catch (e) {
          print('❌ Error converting image to base64: $e');
          if (mounted) {
            TopNotification.error(
              context,
              '${AppLocalizations.of(context)?.failedToProcessImage ?? AppLocalizations.of(context)!.tr('Failed to process image')}: $e',
            );
          }
        }
      }
    } catch (e) {
      print('Error picking image from gallery: $e');
      if (mounted) {
        TopNotification.error(
          context,
          '${AppLocalizations.of(context)?.failedToPickImage ?? AppLocalizations.of(context)!.tr('Failed to pick image')}: $e',
        );
      }
    }
  }

  Widget _buildStep3Content() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: Platform.isIOS ? 400 : 350,
      ), // Extra space for CNTabBar on iOS
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildPricingSection()],
      ),
    );
  }

  Widget _buildStep4Content() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: Platform.isIOS ? 400 : 350,
      ), // Extra space for CNTabBar on iOS
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildNutritionAndDetailsSection()],
      ),
    );
  }

  Widget _buildNutritionAndDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show nutrition and details for each variant
        if (variants.isNotEmpty) ...[
          ...variants.asMap().entries.map((entry) {
            int index = entry.key;
            Map<String, dynamic> variant = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < variants.length - 1 ? 20 : 0,
              ),
              child: _buildVariantNutritionAndDetails(variant, index),
            );
          }),
        ] else ...[
          // For first variant (if not yet created)
          _buildVariantNutritionAndDetails({
            'title': AppLocalizations.of(context)?.newProduct ?? AppLocalizations.of(context)!.tr('New Product'),
            'nutrition': {},
            'additionalDetails': {},
          }, 0),
        ],
      ],
    );
  }

  Widget _buildVariantNutritionAndDetails(
    Map<String, dynamic> variant,
    int index,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.isLight
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Icon(
                  CupertinoIcons.lab_flask,
                  color: widget.isLight ? Colors.black : Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.nutritionAndDetails ?? AppLocalizations.of(context)!.tr('Nutrition & Details'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)?.additionalProductInfo ?? AppLocalizations.of(context)!.tr('Additional product information'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black54 : Colors.white54,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Variant Header
          if (variants.length > 1) ...[
            Container(
              padding: DesktopAppWrapper.getPagePadding(),
              decoration: BoxDecoration(
                color: widget.isLight ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      variant['title']?.isNotEmpty == true
                          ? variant['title']
                          : '${AppLocalizations.of(context)?.variantLabel ?? AppLocalizations.of(context)!.tr('Variant')} ${index + 1}',
                      style: TextStyle(
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Nutrition Information
          _buildNutritionSection(variant),
          const SizedBox(height: 20),

          // Additional Details
          _buildAdditionalDetailsSection(variant),
        ],
      ),
    );
  }

  Widget _buildPricingSection() {
    return Padding(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.isLight
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Icon(
                  CupertinoIcons.money_dollar,
                  color: widget.isLight ? Colors.black : Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.pricingAndStock ?? AppLocalizations.of(context)!.tr('Pricing & Stock'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)?.setPricesAndInventory ?? AppLocalizations.of(context)!.tr('Set prices and inventory levels'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black54 : Colors.white54,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Show pricing for each variant
          if (variants.isNotEmpty) ...[
            ...variants.asMap().entries.map((entry) {
              int index = entry.key;
              Map<String, dynamic> variant = entry.value;
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index < variants.length - 1 ? 20 : 0,
                ),
                child: _buildVariantPricingSection(variant, index),
              );
            }),
          ] else ...[
            // For first variant (if none created yet)
            _buildVariantPricingSection({
              'title':
                  AppLocalizations.of(context)?.newProduct ?? AppLocalizations.of(context)!.tr('New Product'),
              'price': 0.0,
              'stock': 0,
              'unit': 'piece',
              'weight': 0.0,
            }, 0),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantPricingSection(Map<String, dynamic> variant, int index) {
    // Initialize pricing fields if not present
    if (variant['price'] == null) variant['price'] = 0.0;
    if (variant['stock'] == null) variant['stock'] = 0;
    if (variant['unit'] == null) variant['unit'] = 'gram';
    if (variant['alwaysAvailable'] == null) variant['alwaysAvailable'] = false;
    if (variant['dailyProduction'] == null) {
      variant['dailyProduction'] = 0.0; // Changed to double
    }
    if (variant['dailyProductionEnabled'] == null) {
      variant['dailyProductionEnabled'] =
          (variant['dailyProduction'] ?? 0.0) > 0;
    }
    if (variant['minOrder'] == null) variant['minOrder'] = 1;

    final units = ['g', 'kg', 't', 'oz', 'lb', 'pc', 'L', 'mL', 'pk'];

    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Variant Header
          Row(
            children: [
              Expanded(
                child: Text(
                  variant['title']?.isNotEmpty == true
                      ? variant['title']
                      : '${AppLocalizations.of(context)?.variantLabel ?? AppLocalizations.of(context)!.tr('Variant')} ${index + 1}',
                  style: TextStyle(
                    color: widget.isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Pricing Fields
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Price and Unit Row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildPricingFormField(
                      'Unit Price (${_getCurrencySymbol()})',
                      '0.00',
                      variant['price']?.toString() ?? AppLocalizations.of(context)!.tr('0.0'),
                      (value) =>
                          variant['price'] = double.tryParse(value) ?? 0.0,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _buildUnitDropdown(variant, units)),
                ],
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Always Available Toggle
              _buildAlwaysAvailableToggle(variant),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Stock Row (Stock = 0 if always available, disabled if always available)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)?.stockQuantity ?? AppLocalizations.of(context)!.tr('Stock Quantity'),
                    style: TextStyle(
                      color: widget.isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isLight ? Colors.white : Colors.black,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: TradeRepublicTextField(
                      useFormField: true,
                      initialValue: (variant['alwaysAvailable'] ?? false)
                          ? '0'
                          : (variant['stock']?.toString() ?? AppLocalizations.of(context)!.tr('0')),
                      enabled: !(variant['alwaysAvailable'] ?? false),
                      keyboardType: TextInputType.number,
                      inputFormatters: [IntegerInputFormatter()],
                      style: TextStyle(
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                      ),
                      hintText: AppLocalizations.of(context)!.tr('0') ?? AppLocalizations.of(context)!.tr('0'),
                      onChanged: (value) {
                        if (!(variant['alwaysAvailable'] ?? false)) {
                          variant['stock'] = int.tryParse(value) ?? 0;
                        } else {
                          variant['stock'] =
                              0; // Always 0 when always available
                        }
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

              // Daily Production (only shown if Always Available is enabled)
              if (variant['alwaysAvailable'] ?? false) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.building_2_fill,
                          size: 16,
                          color: widget.isLight ? Colors.black : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(
                                  context,
                                )?.dailyProductionCapacity ?? AppLocalizations.of(context)!.tr('Daily Production Capacity'),
                            style: TextStyle(
                              color: widget.isLight
                                  ? Colors.black
                                  : Colors.white,
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TradeRepublicSwitch(
                          value: variant['dailyProductionEnabled'] ?? false,
                          onChanged: (val) {
                            setState(() {
                              variant['dailyProductionEnabled'] = val;
                              if (!val) variant['dailyProduction'] = 0.0;
                            });
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    _buildPricingFormField(
                      AppLocalizations.of(context)?.dailyProduction ?? AppLocalizations.of(context)!.tr('Daily Production'),
                      '0.00',
                      formatNumberUS(
                          (variant['dailyProduction'] as num?)?.toDouble() ?? 0.0,
                          fractionDigits: 2),
                      (value) {
                        if (variant['dailyProductionEnabled'] ?? false) {
                          variant['dailyProduction'] =
                              double.tryParse(value) ?? 0.0;
                        }
                      },
                      keyboardType: TextInputType.number,
                      useCurrencyFormatter: true,
                      enabled: variant['dailyProductionEnabled'] ?? false,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)?.productionCapacity ?? AppLocalizations.of(context)!.tr('How many units can you produce per day? (e.g., 12.34 kg)'),
                      style: TextStyle(
                        color: (widget.isLight ? Colors.black : Colors.white)
                            .withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
              ],

              // Minimum Order Quantity
              _buildPricingFormField(
                AppLocalizations.of(context)?.minimumOrderQuantity ?? AppLocalizations.of(context)!.tr('Minimum Order Quantity'),
                '1',
                variant['minOrder']?.toString() ?? AppLocalizations.of(context)!.tr('1'),
                (value) => variant['minOrder'] = int.tryParse(value) ?? 1,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),

              // Calculated Values Display
              if ((variant['price'] ?? 0.0) > 0) ...[
                Container(
                  width: double.infinity,
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color: widget.isLight ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)?.calculatedValues ?? AppLocalizations.of(context)!.tr('Calculated Values'),
                        style: TextStyle(
                          color: widget.isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppLocalizations.of(context)?.totalValueLabel ?? AppLocalizations.of(context)!.tr('Total Value:'),
                            style: TextStyle(
                              color: widget.isLight
                                  ? Colors.black
                                  : Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            (variant['alwaysAvailable'] ?? false)
                                ? '∞ (Always Available)'
                                : () {
                                    try {
                                      final price =
                                          double.tryParse(
                                            variant['price']?.toString() ?? AppLocalizations.of(context)!.tr('0'),
                                          ) ??
                                          0.0;
                                      final stock =
                                          int.tryParse(
                                            variant['stock']?.toString() ?? AppLocalizations.of(context)!.tr('0'),
                                          ) ??
                                          0;
                                      final appSettings = Provider.of<AppSettings>(context, listen: false);
                                      return appSettings.formatCurrency(price * stock);
                                    } catch (e) {
                                      final appSettings = Provider.of<AppSettings>(context, listen: false);
                                      return appSettings.formatCurrency(0);
                                    }
                                  }(),
                            style: TextStyle(
                              color: widget.isLight
                                  ? Colors.black
                                  : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (variant['alwaysAvailable'] ?? false) ...[
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context)?.alwaysAvailable ?? AppLocalizations.of(context)!.tr('This product is always available and never goes out of stock'),
                          style: TextStyle(
                            color: widget.isLight ? Colors.black : Colors.white,
                            fontSize: 11,
                          ),
                        ),
                        if ((variant['dailyProduction'] ?? 0.0) > 0) ...[
                          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.dailyProductionLabel ?? AppLocalizations.of(context)!.tr('Daily Production:'),
                                style: TextStyle(
                                  color: widget.isLight
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                () {
                                  try {
                                    final daily =
                                        double.tryParse(
                                          variant['dailyProduction']
                                                  ?.toString() ?? AppLocalizations.of(context)!.tr('0'),
                                        ) ??
                                        0.0;
                                    final appSettings = Provider.of<AppSettings>(context, listen: false);
                                    return '${appSettings.formatNumber(daily, decimals: 2)} ${variant['unit'] ?? AppLocalizations.of(context)!.tr('units')}/day';
                                  } catch (e) {
                                    final appSettings = Provider.of<AppSettings>(context, listen: false);
                                    return '${appSettings.formatNumber(0, decimals: 2)} ${variant['unit'] ?? AppLocalizations.of(context)!.tr('units')}/day';
                                  }
                                }(),
                                style: TextStyle(
                                  color: widget.isLight
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.dailyRevenueLabel ?? AppLocalizations.of(context)!.tr('Daily Revenue:'),
                                style: TextStyle(
                                  color: widget.isLight
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                () {
                                  try {
                                    final price =
                                        double.tryParse(
                                          variant['price']?.toString() ?? AppLocalizations.of(context)!.tr('0'),
                                        ) ??
                                        0.0;
                                    final daily =
                                        double.tryParse(
                                          variant['dailyProduction']
                                                  ?.toString() ?? AppLocalizations.of(context)!.tr('0'),
                                        ) ??
                                        0.0;
                                    final appSettings = Provider.of<AppSettings>(context, listen: false);
                                    return appSettings.formatCurrency(price * daily);
                                  } catch (e) {
                                    final appSettings = Provider.of<AppSettings>(context, listen: false);
                                    return appSettings.formatCurrency(0);
                                  }
                                }(),
                                style: TextStyle(
                                  color: const Color(0xFF34C759),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPricingFormField(
    String label,
    String hint,
    String initialValue,
    Function(String) onChanged, {
    TextInputType? keyboardType,
    bool useCurrencyFormatter = false,
    bool enabled = true,
  }) {
    // Determine the correct formatter based on label/hint
    List<TextInputFormatter>? formatters;
    if (useCurrencyFormatter ||
        label.toLowerCase().contains('price') ||
        label.toLowerCase().contains('cost') ||
        label.toLowerCase().contains('price') ||
        label.toLowerCase().contains('production') ||
        label.toLowerCase().contains('capacity') ||
        label.toLowerCase().contains('daily')) {
      formatters = [CurrencyInputFormatter(decimalDigits: 2)];
    } else if (label.toLowerCase().contains('stock') ||
        label.toLowerCase().contains('order')) {
      formatters = [IntegerInputFormatter()];
    }

    return TradeRepublicTextField(
      key: ValueKey('${label}_$initialValue'),
      useFormField: true,
      initialValue: initialValue,
      hintText: hint,
      maxLines: 1,
      keyboardType: keyboardType,
      onChanged: onChanged,
      inputFormatters: formatters,
      enabled: enabled,
    );
  }

  Widget _buildUnitDropdown(Map<String, dynamic> variant, List<String> units) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.unitLabel ?? AppLocalizations.of(context)!.tr('Unit'),
          style: TextStyle(
            color: widget.isLight ? Colors.black : Colors.white,
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        TradeRepublicTap(
          onTap: () => _showUnitBottomSheet(variant, units),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: widget.isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    variant['unit'] ?? AppLocalizations.of(context)!.tr('piece'),
                    style: TextStyle(
                      color: widget.isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                    ),
                  ),
                ),
                _buildModernDropdownIcon(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlwaysAvailableToggle(Map<String, dynamic> variant) {
    final isAlwaysAvailable = variant['alwaysAvailable'] ?? false;

    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        children: [
          Icon(
            isAlwaysAvailable ? Icons.all_inclusive : Icons.inventory,
            color: widget.isLight ? Colors.black : Colors.white,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.alwaysAvailable ?? AppLocalizations.of(context)!.tr('Always Available'),
                  style: TextStyle(
                    color: widget.isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isAlwaysAvailable
                      ? (AppLocalizations.of(context)?.productAlwaysInStock ?? AppLocalizations.of(context)!.tr(''))
                      : AppLocalizations.of(
                              context,
                            )?.trackStockQuantityManually ?? AppLocalizations.of(context)!.tr('Track stock quantity manually'),
                  style: TextStyle(
                    color: widget.isLight ? Colors.black : Colors.white,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TradeRepublicSwitch(
            value: isAlwaysAvailable,
            onChanged: (value) {
              setState(() {
                variant['alwaysAvailable'] = value;
                if (value) {
                  variant['stock'] = 0; // Stock 0 when always available
                  // Keep daily production if already set
                  if (variant['dailyProduction'] == null) {
                    variant['dailyProduction'] = 0.0;
                  }
                } else {
                  variant['stock'] = 0;
                }
              });
            },
          ),
        ],
      ),
    );
  }

  void _showValidationBottomSheet(
    BuildContext context,
    String title,
    String message,
    IconData icon,
    Color color,
  ) {
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
                icon,
                size: 22,
                color: widget.isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          // Message
          Text(
            message,
            style: TextStyle(
              color: widget.isLight ? Colors.black54 : Colors.white70,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          // OK Button
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.ok ?? AppLocalizations.of(context)!.tr('OK'),
              backgroundColor: color,
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildFloatingBottomNavigation() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: DesktopAppWrapper.getPagePadding(),
          decoration: BoxDecoration(
            color: (widget.isLight ? Colors.white : Colors.black).withOpacity(
              0.85,
            ),
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(widget.isLight ? 0.1 : 0.3),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Previous Button
              if (currentStep > 1)
                Expanded(
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)?.previous ?? AppLocalizations.of(context)!.tr('Previous'),
                    isSecondary: true,
                    onPressed: () {
                      setState(() {
                        currentStep--;
                      });
                    },
                  ),
                ),

              if (currentStep > 1) const SizedBox(width: 16),

              // Next/Save Button
              Expanded(
                flex: currentStep == 1 ? 1 : 1,
                child: TradeRepublicButton(
                  label: currentStep == totalSteps
                      ? AppLocalizations.of(context)?.saveProduct ?? AppLocalizations.of(context)!.tr('Save Product')
                      : AppLocalizations.of(context)?.continueAction ?? AppLocalizations.of(context)!.tr('Continue'),
                  onPressed: () {
                    if (currentStep == totalSteps) {
                      // Save product on Step 6
                      if (_isStep5Valid()) {
                        _saveProduct();
                      } else {
                        _showValidationBottomSheet(
                          context,
                          AppLocalizations.of(context)?.missingInformation ?? AppLocalizations.of(context)!.tr('Missing Information'),
                          'Please complete Step 5 before saving.',
                          CupertinoIcons.exclamationmark_circle,
                          Colors.orange,
                        );
                      }
                    } else if (currentStep == 1) {
                      // First variant is already created in initState, just proceed
                      setState(() {
                        currentStep++;
                      });
                    } else if (currentStep == 3) {
                      // Validate step 3 before proceeding to step 4
                      if (_isStep3Valid()) {
                        setState(() {
                          currentStep++;
                        });
                      } else {
                        // No validation needed as fields are optional
                        setState(() {
                          currentStep++;
                        });
                      }
                    } else if (currentStep == 5) {
                      // Validate step 5 before proceeding to step 6
                      if (_isStep5Valid()) {
                        setState(() {
                          currentStep++;
                        });
                      } else {
                        // Trigger rebuild to show error borders
                        setState(() {});
                        _showValidationBottomSheet(
                          context,
                          AppLocalizations.of(context)?.missingInformation ?? AppLocalizations.of(context)!.tr('Missing Information'),
                          'Please fill in all required shipping and location fields (marked in red).',
                          CupertinoIcons.exclamationmark_circle,
                          Colors.red,
                        );
                      }
                    } else {
                      // Other steps (2 to 3, 4 to 5) no special validation
                      setState(() {
                        currentStep++;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNutritionSection(Map<String, dynamic> variant) {
    // Initialize nutrition fields if not present
    if (variant['nutrition'] == null) {
      variant['nutrition'] = {
        'energy_kj': '',
        'energy_kcal': '',
        'fat': '',
        'fsat': '',
        'carb': '',
        'sugar': '',
        'protein': '',
        'salt': '',
        'servingSize': 'per100g', // Default to per 100g
      };
    }

    // Initialize additional fields if not present
    if (variant['additionalDetails'] == null) {
      variant['additionalDetails'] = {
        'origin': '',
        'bioControlNr': '',
        'features': '',
        'ingredients': '',
        'allergens': '',
        'fillAmount': '',
        'fillUnit': '',
        'organic': false,
        'terpenes': '',
      };
    }

    // Create unique key based on nutrition data to force rebuild when data loads
    final nutritionKey =
        '${variant['nutrition']['energy_kj']}_${variant['nutrition']['fat']}_${variant['additionalDetails']['fillAmount']}';
    print('🔑 Building nutrition section with key: $nutritionKey');

    // Ensure organic is a boolean
    if (variant['additionalDetails']['organic'] == null) {
      variant['additionalDetails']['organic'] = false;
    }

    // Ensure servingSize is set
    if (variant['nutrition']['servingSize'] == null) {
      variant['nutrition']['servingSize'] = 'per100g';
    }

    final servingSize = variant['nutrition']['servingSize'] ?? AppLocalizations.of(context)!.tr('per100g');
    final servingSizeLabel = servingSize == 'none'
        ? (AppLocalizations.of(context)?.noneLabel ?? AppLocalizations.of(context)!.tr('None'))
        : (servingSize == 'per100g'
              ? (AppLocalizations.of(context)?.per100g ?? AppLocalizations.of(context)!.tr('per 100g'))
              : (AppLocalizations.of(context)?.perServing ?? AppLocalizations.of(context)!.tr('per serving')));
    final isNutritionDisabled = servingSize == 'none';

    return Container(
      key: ValueKey('nutrition_section_$nutritionKey'),

      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.lab_flask,
                color: widget.isLight ? Colors.black : Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.nutritionInformation ?? AppLocalizations.of(context)!.tr('Nutrition Information'),
                  style: TextStyle(
                    color: widget.isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Serving Size Selector
              TradeRepublicTap(
                onTap: () => _showServingSizeBottomSheet(variant),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isLight ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        servingSizeLabel,
                        style: TextStyle(
                          color: widget.isLight ? Colors.black : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildModernDropdownIcon(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Show message if nutrition is disabled
          if (isNutritionDisabled) ...[
            Container(
              padding: DesktopAppWrapper.getPagePadding(),
              decoration: BoxDecoration(
                color: (widget.isLight ? Colors.black : Colors.white)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.info_circle,
                    color: widget.isLight ? Colors.black54 : Colors.white54,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.nutritionInfoDisabled ?? AppLocalizations.of(context)!.tr('Nutrition information is disabled. Select a format above to add nutrition values.'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black54 : Colors.white54,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Show nutrition fields only if not disabled
          if (!isNutritionDisabled) ...[
            // Energy
            Row(
              children: [
                Expanded(
                  child: _buildNutritionField(
                    '${AppLocalizations.of(context)?.energyLabel ?? AppLocalizations.of(context)!.tr('Energy')} (kJ)',
                    'kJ $servingSizeLabel',
                    variant['nutrition']['energy_kj'] ?? AppLocalizations.of(context)!.tr(''),
                    (value) => variant['nutrition']['energy_kj'] = value,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNutritionField(
                    '${AppLocalizations.of(context)?.energyLabel ?? AppLocalizations.of(context)!.tr('Energy')} (kcal)',
                    'kcal $servingSizeLabel',
                    variant['nutrition']['energy_kcal'] ?? AppLocalizations.of(context)!.tr(''),
                    (value) => variant['nutrition']['energy_kcal'] = value,
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Fat and Saturated Fat
            Row(
              children: [
                Expanded(
                  child: _buildNutritionField(
                    AppLocalizations.of(context)?.fatLabel ?? AppLocalizations.of(context)!.tr('Fat'),
                    'g $servingSizeLabel',
                    variant['nutrition']['fat'] ?? AppLocalizations.of(context)!.tr(''),
                    (value) => variant['nutrition']['fat'] = value,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNutritionField(
                    AppLocalizations.of(context)?.saturatedFat ??
                        AppLocalizations.of(context)?.saturatedFat ?? AppLocalizations.of(context)!.tr('Saturated Fat'),
                    'g $servingSizeLabel',
                    variant['nutrition']['fsat'] ?? AppLocalizations.of(context)!.tr(''),
                    (value) => variant['nutrition']['fsat'] = value,
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Carbs and Sugar
            Row(
              children: [
                Expanded(
                  child: _buildNutritionField(
                    AppLocalizations.of(context)?.carbohydratesLabel ?? AppLocalizations.of(context)!.tr('Carbohydrates'),
                    'g $servingSizeLabel',
                    variant['nutrition']['carb'] ?? AppLocalizations.of(context)!.tr(''),
                    (value) => variant['nutrition']['carb'] = value,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNutritionField(
                    AppLocalizations.of(context)?.sugarLabel ?? AppLocalizations.of(context)!.tr('Sugar'),
                    'g $servingSizeLabel',
                    variant['nutrition']['sugar'] ?? AppLocalizations.of(context)!.tr(''),
                    (value) => variant['nutrition']['sugar'] = value,
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

            // Protein and Salt
            Row(
              children: [
                Expanded(
                  child: _buildNutritionField(
                    AppLocalizations.of(context)?.proteinLabel ?? AppLocalizations.of(context)!.tr('Protein'),
                    'g $servingSizeLabel',
                    variant['nutrition']['protein'] ?? AppLocalizations.of(context)!.tr(''),
                    (value) => variant['nutrition']['protein'] = value,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildNutritionField(
                    AppLocalizations.of(context)?.saltLabel ?? AppLocalizations.of(context)!.tr('Salt'),
                    'g $servingSizeLabel',
                    variant['nutrition']['salt'] ?? AppLocalizations.of(context)!.tr(''),
                    (value) => variant['nutrition']['salt'] = value,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNutritionField(
    String label,
    String hint,
    String initialValue,
    Function(String) onChanged,
  ) {
    // Use a stable key per field + timestamp when loading
    // This forces rebuild when data is loaded
    return TradeRepublicTextField(
      key: ValueKey('nutrition_${label}_${hint.hashCode}_$initialValue'),
      useFormField: true,
      initialValue: initialValue,
      hintText: hint,
      maxLines: 1,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      inputFormatters: [CurrencyInputFormatter(decimalDigits: 2)],
    );
  }

  Widget _buildAdditionalDetailsSection(Map<String, dynamic> variant) {
    return Container(
      padding: DesktopAppWrapper.getPagePadding(),
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.info_circle,
                color: widget.isLight ? Colors.black : Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.additionalDetails ?? AppLocalizations.of(context)!.tr('Additional Details'),
                style: TextStyle(
                  color: widget.isLight ? Colors.black : Colors.white,
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Origin and Bio Control Number
          Row(
            children: [
              Expanded(
                child: _buildAdditionalField(
                  AppLocalizations.of(context)?.originLabel ?? AppLocalizations.of(context)!.tr('Origin'),
                  AppLocalizations.of(context)?.countryOfOrigin ?? AppLocalizations.of(context)!.tr('Country of origin'),
                  variant['additionalDetails']['origin'] ?? AppLocalizations.of(context)!.tr(''),
                  (value) => variant['additionalDetails']['origin'] = value,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAdditionalField(
                  AppLocalizations.of(context)?.bioControlNr ??
                      AppLocalizations.of(context)?.bioControlNr ?? AppLocalizations.of(context)!.tr('Bio Control Nr'),
                  AppLocalizations.of(context)?.bioCertificationNumber ?? AppLocalizations.of(context)!.tr('Bio certification number'),
                  variant['additionalDetails']['bioControlNr'] ?? AppLocalizations.of(context)!.tr(''),
                  (value) =>
                      variant['additionalDetails']['bioControlNr'] = value,
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Features
          _buildAdditionalField(
            AppLocalizations.of(context)?.featuresLabel ?? AppLocalizations.of(context)!.tr('Features'),
            AppLocalizations.of(context)?.productFeaturesAndCharacteristics ?? AppLocalizations.of(context)!.tr('Product features and characteristics'),
            variant['additionalDetails']['features'] ?? AppLocalizations.of(context)!.tr(''),
            (value) => variant['additionalDetails']['features'] = value,
            maxLines: 3,
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Ingredients
          _buildAdditionalField(
            AppLocalizations.of(context)?.ingredientsLabel ?? AppLocalizations.of(context)!.tr('Ingredients'),
            AppLocalizations.of(context)?.listOfIngredients ?? AppLocalizations.of(context)!.tr('List of ingredients'),
            variant['additionalDetails']['ingredients'] ?? AppLocalizations.of(context)!.tr(''),
            (value) => variant['additionalDetails']['ingredients'] = value,
            maxLines: 3,
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          // Allergens
          _buildAdditionalField(
            AppLocalizations.of(context)?.allergensLabel ?? AppLocalizations.of(context)!.tr('Allergens'),
            AppLocalizations.of(context)?.listOfAllergens ?? AppLocalizations.of(context)!.tr('List of allergens'),
            variant['additionalDetails']['allergens'] ?? AppLocalizations.of(context)!.tr(''),
            (value) => variant['additionalDetails']['allergens'] = value,
            maxLines: 2,
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          _buildAdditionalField(
            AppLocalizations.of(context)?.terpenesLabel ?? AppLocalizations.of(context)!.tr('Terpenes'),
            'e.g. Myrcene, Limonene, Pinene',
            variant['additionalDetails']['terpenes'] ?? AppLocalizations.of(context)!.tr(''),
            (value) => variant['additionalDetails']['terpenes'] = value,
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Quality Toggle - Only Organic
          _buildQualityToggle(
            AppLocalizations.of(context)?.organicLabel ?? AppLocalizations.of(context)!.tr('Organic'),
            CupertinoIcons.leaf_arrow_circlepath,
            variant['additionalDetails']['organic'] ?? false,
            (value) => setState(() {
              variant['additionalDetails']['organic'] = value;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalField(
    String label,
    String hint,
    String initialValue,
    Function(String) onChanged, {
    int maxLines = 1,
  }) {
    return TradeRepublicTextField(
      key: ValueKey('${label}_$initialValue'),
      useFormField: true,
      initialValue: initialValue,
      hintText: hint,
      maxLines: maxLines,
      onChanged: onChanged,
    );
  }

  Widget _buildQualityToggle(
    String label,
    IconData icon,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isLight ? Colors.white : Colors.black,
        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: widget.isLight ? Colors.black : Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: widget.isLight ? Colors.black : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TradeRepublicSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  void _showCategoryBottomSheet(
    Map<String, dynamic> variant,
    List<String> categories,
  ) {
    final isLight = Provider.of<AppSettings>(
      context,
      listen: false,
    ).isLightMode(context);
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
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
                    CupertinoIcons.list_bullet,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)?.selectCategory ?? AppLocalizations.of(context)!.tr('Select Category'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: widget.isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Options
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ...categories.map((category) {
                        final isSelected =
                            (variant['category'] ?? selectedCategory) ==
                            category;
                        return TradeRepublicTap(
                          onTap: () {
                            setState(() {
                              variant['category'] = category;
                            });
                            Navigator.pop(context);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: DesktopAppWrapper.getPagePadding(),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (widget.isLight
                                        ? Colors.black
                                        : Colors.white)
                                  : (widget.isLight
                                        ? Colors.white
                                        : Colors.black),
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _translateCategory(category),
                                    style: TextStyle(
                                      color: isSelected
                                          ? (widget.isLight
                                                ? Colors.white
                                                : Colors.black)
                                          : (widget.isLight
                                                ? Colors.black
                                                : Colors.white),
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    color: widget.isLight
                                        ? Colors.white
                                        : Colors.black,
                                    size: 24,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showTemperatureUnitBottomSheet(Map<String, dynamic> shipping) {
    final isLight = Provider.of<AppSettings>(
      context,
      listen: false,
    ).isLightMode(context);
    final units = [
      {
        'id': 'celsius',
        'name': AppLocalizations.of(context)?.celsius ?? AppLocalizations.of(context)!.tr('Celsius (°C)'),
        'description':
            AppLocalizations.of(context)?.metricSystem ?? AppLocalizations.of(context)!.tr('Metric system'),
      },
      {
        'id': 'fahrenheit',
        'name': AppLocalizations.of(context)?.fahrenheit ?? AppLocalizations.of(context)!.tr('Fahrenheit (°F)'),
        'description':
            AppLocalizations.of(context)?.imperialSystem ?? AppLocalizations.of(context)!.tr('Imperial system'),
      },
    ];

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
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
                  CupertinoIcons.thermometer,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.selectTemperatureUnit ?? AppLocalizations.of(context)!.tr('Select Temperature Unit'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: widget.isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Options
            ...units.map((unit) {
              final isSelected =
                  (shipping['temperature_unit'] ?? AppLocalizations.of(context)!.tr('celsius')) == unit['id'];
              return TradeRepublicTap(
                onTap: () {
                  setState(() {
                    shipping['temperature_unit'] = unit['id'];
                  });
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 4,
                  ),
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (widget.isLight ? Colors.black : Colors.white)
                        : (widget.isLight ? Colors.white : Colors.black),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.thermostat,
                        color: isSelected
                            ? (widget.isLight ? Colors.white : Colors.black)
                            : (widget.isLight ? Colors.black : Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              unit['name']!,
                              style: TextStyle(
                                color: isSelected
                                    ? (widget.isLight
                                          ? Colors.white
                                          : Colors.black)
                                    : (widget.isLight
                                          ? Colors.black
                                          : Colors.white),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              unit['description']!,
                              style: TextStyle(
                                color: isSelected
                                    ? (widget.isLight
                                          ? Colors.white
                                          : Colors.black)
                                    : (widget.isLight
                                          ? Colors.black
                                          : Colors.white),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(
                          CupertinoIcons.checkmark_circle_fill,
                          color: Colors.green,
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showCountryBottomSheet(Map<String, dynamic> location) {
    final isLight = Provider.of<AppSettings>(
      context,
      listen: false,
    ).isLightMode(context);
    final countries = [
      // North America
      {'id': 'United States', 'name': 'United States', 'flag': '🇺🇸'},
      {'id': 'Canada', 'name': 'Canada', 'flag': '🇨🇦'},
      {'id': 'Mexico', 'name': 'Mexico', 'flag': '🇲🇽'},
      // EU Countries
      {'id': 'Germany', 'name': 'Germany', 'flag': '🇩🇪'},
      {'id': 'Austria', 'name': 'Austria', 'flag': '🇦🇹'},
      {'id': 'France', 'name': 'France', 'flag': '🇫🇷'},
      {'id': 'Italy', 'name': 'Italy', 'flag': '🇮🇹'},
      {'id': 'Spain', 'name': 'Spain', 'flag': '🇪🇸'},
      {'id': 'Netherlands', 'name': 'Netherlands', 'flag': '🇳🇱'},
      {'id': 'Belgium', 'name': 'Belgium', 'flag': '🇧🇪'},
      {'id': 'Poland', 'name': 'Poland', 'flag': '🇵🇱'},
      {'id': 'Portugal', 'name': 'Portugal', 'flag': '🇵🇹'},
      {'id': 'Greece', 'name': 'Greece', 'flag': '🇬🇷'},
      {'id': 'Ireland', 'name': 'Ireland', 'flag': '🇮🇪'},
      {'id': 'Sweden', 'name': 'Sweden', 'flag': '🇸🇪'},
      {'id': 'Denmark', 'name': 'Denmark', 'flag': '🇩🇰'},
      {'id': 'Finland', 'name': 'Finland', 'flag': '🇫🇮'},
      {'id': 'Czech Republic', 'name': 'Czech Republic', 'flag': '🇨🇿'},
      {'id': 'Hungary', 'name': 'Hungary', 'flag': '🇭🇺'},
      {'id': 'Romania', 'name': 'Romania', 'flag': '🇷🇴'},
      {'id': 'Bulgaria', 'name': 'Bulgaria', 'flag': '🇧🇬'},
      {'id': 'Croatia', 'name': 'Croatia', 'flag': '🇭🇷'},
      {'id': 'Slovakia', 'name': 'Slovakia', 'flag': '🇸🇰'},
      {'id': 'Slovenia', 'name': 'Slovenia', 'flag': '🇸🇮'},
      {'id': 'Estonia', 'name': 'Estonia', 'flag': '🇪🇪'},
      {'id': 'Latvia', 'name': 'Latvia', 'flag': '🇱🇻'},
      {'id': 'Lithuania', 'name': 'Lithuania', 'flag': '🇱🇹'},
      {'id': 'Malta', 'name': 'Malta', 'flag': '🇲🇹'},
      {'id': 'Cyprus', 'name': 'Cyprus', 'flag': '🇨🇾'},
      {'id': 'Luxembourg', 'name': 'Luxembourg', 'flag': '🇱🇺'},
      // Russia
      {'id': 'Russia', 'name': 'Russia', 'flag': '🇷🇺'},
    ];

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
      bottomPadding: 20.0,
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
                  CupertinoIcons.globe,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.selectCountry ?? AppLocalizations.of(context)!.tr('Select Country'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            // Options
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ...countries.map((country) {
                      final isSelected =
                          (location['country'] ?? AppLocalizations.of(context)!.tr('Germany')) == country['id'];
                      return TradeRepublicTap(
                        onTap: () {
                          // Always store the English id, never the localized display name
                          final englishId = country['id']!;
                          setState(() {
                            location['country'] = englishId;
                          });
                          _updateCoordinatesFromAddress(location);
                          Navigator.pop(context);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 4,
                          ),
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.green.withOpacity(0.1)
                                : (widget.isLight
                                      ? Colors.white
                                      : Colors.black),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Row(
                            children: [
                              Text(
                                country['flag']!,
                                style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 10,,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  country['name']!,
                                  style: TextStyle(
                                    color: widget.isLight
                                        ? Colors.black
                                        : Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  CupertinoIcons.checkmark_circle_fill,
                                  color: Colors.green,
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _countryToFlag(String country) {
    const map = {
      'United States': '🇺🇸',
      'Canada': '🇨🇦',
      'Mexico': '🇲🇽',
      'Germany': '🇩🇪',
      'Austria': '🇦🇹',
      'France': '🇫🇷',
      'Italy': '🇮🇹',
      'Spain': '🇪🇸',
      'Netherlands': '🇳🇱',
      'Belgium': '🇧🇪',
      'Poland': '🇵🇱',
      'Portugal': '🇵🇹',
      'Greece': '🇬🇷',
      'Ireland': '🇮🇪',
      'Sweden': '🇸🇪',
      'Denmark': '🇩🇰',
      'Finland': '🇫🇮',
      'Czech Republic': '🇨🇿',
      'Hungary': '🇭🇺',
      'Romania': '🇷🇴',
      'Bulgaria': '🇧🇬',
      'Croatia': '🇭🇷',
      'Slovakia': '🇸🇰',
      'Slovenia': '🇸🇮',
      'Estonia': '🇪🇪',
      'Latvia': '🇱🇻',
      'Lithuania': '🇱🇹',
      'Malta': '🇲🇹',
      'Cyprus': '🇨🇾',
      'Luxembourg': '🇱🇺',
      'Russia': '🇷🇺',
    };
    return map[country] ?? AppLocalizations.of(context)!.tr('🏳️');
  }

  void _showUnitBottomSheet(Map<String, dynamic> variant, List<String> units) {
    final isLight = Provider.of<AppSettings>(
      context,
      listen: false,
    ).isLightMode(context);
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
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
                  CupertinoIcons.tag,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.selectUnit ?? AppLocalizations.of(context)!.tr('Select Unit'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
            // Options
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ...units.map((unit) {
                      final isSelected = (variant['unit'] ?? AppLocalizations.of(context)!.tr('gram')) == unit;
                      return TradeRepublicTap(
                        onTap: () {
                          setState(() {
                            variant['unit'] = unit;
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: DesktopAppWrapper.getPagePadding(),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (widget.isLight ? Colors.black : Colors.white)
                                : (widget.isLight
                                      ? Colors.white
                                      : Colors.black),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  unit,
                                  style: TextStyle(
                                    color: isSelected
                                        ? (widget.isLight
                                              ? Colors.white
                                              : Colors.black)
                                        : (widget.isLight
                                              ? Colors.black
                                              : Colors.white),
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  CupertinoIcons.checkmark_circle_fill,
                                  color: widget.isLight
                                      ? Colors.white
                                      : Colors.black,
                                  size: 24,
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showServingSizeBottomSheet(Map<String, dynamic> variant) {
    final isLight = Provider.of<AppSettings>(
      context,
      listen: false,
    ).isLightMode(context);
    final servingSizes = [
      {
        'id': 'none',
        'name': AppLocalizations.of(context)?.noneLabel ?? AppLocalizations.of(context)!.tr('None'),
        'description':
            AppLocalizations.of(context)?.noNutritionInformation ?? AppLocalizations.of(context)!.tr('No nutrition information'),
      },
      {
        'id': 'per100g',
        'name': AppLocalizations.of(context)?.per100g ?? AppLocalizations.of(context)!.tr('Per 100g'),
        'description':
            AppLocalizations.of(context)?.nutritionValuesPer100g ?? AppLocalizations.of(context)!.tr('Nutrition values per 100 grams'),
      },
      {
        'id': 'perServing',
        'name': AppLocalizations.of(context)?.perServing ?? AppLocalizations.of(context)!.tr('Per Serving'),
        'description':
            AppLocalizations.of(context)?.nutritionValuesPerServing ?? AppLocalizations.of(context)!.tr('Nutrition values per single serving (US style)'),
      },
    ];

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
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
                  CupertinoIcons.doc_text,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.nutritionInfoFormat ?? AppLocalizations.of(context)!.tr('Nutrition Information Format'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: widget.isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Options
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ...servingSizes.map((size) {
                      final isSelected =
                          (variant['nutrition']['servingSize'] ?? AppLocalizations.of(context)!.tr('per100g')) ==
                          size['id'];
                      return TradeRepublicTap(
                        onTap: () {
                          setState(() {
                            variant['nutrition']['servingSize'] = size['id'];
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: DesktopAppWrapper.getPagePadding(),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (widget.isLight ? Colors.black : Colors.white)
                                : (widget.isLight
                                      ? Colors.white
                                      : Colors.black),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      size['name']!,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                        color: isSelected
                                            ? (widget.isLight
                                                  ? Colors.white
                                                  : Colors.black)
                                            : (widget.isLight
                                                  ? Colors.black
                                                  : Colors.white),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      CupertinoIcons.checkmark_circle_fill,
                                      color: widget.isLight
                                          ? Colors.white
                                          : Colors.black,
                                      size: 24,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                size['description']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? Colors.white
                                      : (widget.isLight
                                                ? Colors.black
                                                : Colors.white)
                                            .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showFillAmountBottomSheet(BuildContext context) {
    final isLight = Provider.of<AppSettings>(
      context,
      listen: false,
    ).isLightMode(context);
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
                CupertinoIcons.info_circle_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.fillAmount ??
                      AppLocalizations.of(context)?.fillAmount ?? AppLocalizations.of(context)!.tr('Fill Amount'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Text(
            AppLocalizations.of(context)?.fillAmountHelp ?? AppLocalizations.of(context)!.tr('How much product is in one package. For example:\\\\n\\\\n• 100 (for 100g bag)\\\\n• 1000 (for 1kg bag)\\\\n• 500 (for a 500ml bottle)\\\\n• 24 (for 24 pieces in a box)\\\\n• 50 (for 50 units on a pallet)'),
            style: TextStyle(
              color: widget.isLight ? Colors.black87 : Colors.white70,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              height: 1.5,
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.gotIt ?? AppLocalizations.of(context)!.tr('Got it'),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showFillUnitBottomSheet(BuildContext context) {
    final isLight = Provider.of<AppSettings>(
      context,
      listen: false,
    ).isLightMode(context);
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
                CupertinoIcons.info_circle_fill,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)?.fillUnit ?? AppLocalizations.of(context)!.tr('Fill Unit'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          Text(
            AppLocalizations.of(context)?.fillUnitHelp ?? AppLocalizations.of(context)!.tr('The unit of measurement for the fill amount. For example:\\\\n\\\\n• g (grams)\\\\n• kg (kilograms)\\\\n• ml (milliliters)\\\\n• L (liters)\\\\n• pcs (pieces)\\\\n• bags\\\\n• boxes\\\\n• pallets'),
            style: TextStyle(
              color: widget.isLight ? Colors.black87 : Colors.white70,
              fontSize: DesktopOptimizedWidgets.getFontSize(),
              height: 1.5,
            ),
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
          SizedBox(
            width: double.infinity,
            child: TradeRepublicButton(
              label: AppLocalizations.of(context)?.gotIt ?? AppLocalizations.of(context)!.tr('Got it'),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showFillUnitSelectionBottomSheet(
    BuildContext context,
    Map<String, dynamic> variant,
  ) {
    final isLight = Provider.of<AppSettings>(
      context,
      listen: false,
    ).isLightMode(context);
    final fillUnits = [
      {
        'id': 'g',
        'name': AppLocalizations.of(context)?.gramsUnit ?? AppLocalizations.of(context)!.tr('Grams (g)'),
        'description':
            AppLocalizations.of(context)?.weightMeasurement ?? AppLocalizations.of(context)!.tr('Weight measurement'),
      },
      {
        'id': 'kg',
        'name': AppLocalizations.of(context)?.kilogramsUnit ?? AppLocalizations.of(context)!.tr('Kilograms (kg)'),
        'description':
            AppLocalizations.of(context)?.weightMeasurement ?? AppLocalizations.of(context)!.tr('Weight measurement'),
      },
      {
        'id': 't',
        'name': AppLocalizations.of(context)?.tonnesUnit ?? AppLocalizations.of(context)!.tr('Tonnes (t)'),
        'description':
            AppLocalizations.of(context)?.weightMeasurement ?? AppLocalizations.of(context)!.tr('Weight measurement'),
      },
      {
        'id': 'oz',
        'name': AppLocalizations.of(context)?.ouncesUnit ?? AppLocalizations.of(context)!.tr('Ounces (oz)'),
        'description':
            AppLocalizations.of(context)?.weightMeasurement ?? AppLocalizations.of(context)!.tr('Weight measurement'),
      },
      {
        'id': 'lb',
        'name': AppLocalizations.of(context)?.poundsUnit ?? AppLocalizations.of(context)!.tr('Pounds (lb)'),
        'description':
            AppLocalizations.of(context)?.weightMeasurement ?? AppLocalizations.of(context)!.tr('Weight measurement'),
      },
      {
        'id': 'ml',
        'name':
            AppLocalizations.of(context)?.millilitersUnit ?? AppLocalizations.of(context)!.tr('Milliliters (ml)'),
        'description':
            AppLocalizations.of(context)?.volumeMeasurement ?? AppLocalizations.of(context)!.tr('Volume measurement'),
      },
      {
        'id': 'L',
        'name': AppLocalizations.of(context)?.litersUnit ?? AppLocalizations.of(context)!.tr('Liters (L)'),
        'description':
            AppLocalizations.of(context)?.volumeMeasurement ?? AppLocalizations.of(context)!.tr('Volume measurement'),
      },
      {
        'id': 'pcs',
        'name': AppLocalizations.of(context)?.piecesUnit ?? AppLocalizations.of(context)!.tr('Pieces (pcs)'),
        'description':
            AppLocalizations.of(context)?.countMeasurement ?? AppLocalizations.of(context)!.tr('Count measurement'),
      },
      {
        'id': 'bags',
        'name': AppLocalizations.of(context)?.bagsUnit ?? AppLocalizations.of(context)!.tr('Bags'),
        'description':
            AppLocalizations.of(context)?.packagingUnit ?? AppLocalizations.of(context)!.tr('Packaging unit'),
      },
      {
        'id': 'boxes',
        'name': AppLocalizations.of(context)?.boxesUnit ?? AppLocalizations.of(context)!.tr('Boxes'),
        'description':
            AppLocalizations.of(context)?.packagingUnit ?? AppLocalizations.of(context)!.tr('Packaging unit'),
      },
      {
        'id': 'pallets',
        'name': AppLocalizations.of(context)?.palletsUnit ?? AppLocalizations.of(context)!.tr('Pallets'),
        'description': AppLocalizations.of(context)?.bulkUnit ?? AppLocalizations.of(context)!.tr('Bulk unit'),
      },
    ];

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.cube,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.selectFillUnit ?? AppLocalizations.of(context)!.tr('Select Fill Unit'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Options
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ...fillUnits.map((unit) {
                      final isSelected =
                          (variant['additionalDetails']['fillUnit'] ?? AppLocalizations.of(context)!.tr('')) ==
                          unit['id'];
                      return TradeRepublicTap(
                        onTap: () {
                          setState(() {
                            variant['additionalDetails']['fillUnit'] =
                                unit['id'];
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: DesktopAppWrapper.getPagePadding(),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (widget.isLight ? Colors.black : Colors.white)
                                : (widget.isLight
                                      ? Colors.white
                                      : Colors.black),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      unit['name']!,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                        color: isSelected
                                            ? (widget.isLight
                                                  ? Colors.white
                                                  : Colors.black)
                                            : (widget.isLight
                                                  ? Colors.black
                                                  : Colors.white),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      CupertinoIcons.checkmark_circle_fill,
                                      color: widget.isLight
                                          ? Colors.white
                                          : Colors.black,
                                      size: 24,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                unit['description']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? (widget.isLight
                                            ? Colors.white
                                            : Colors.white.withOpacity(0.6))
                                      : (widget.isLight
                                                ? Colors.black
                                                : Colors.white)
                                            .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Step 5: Shipping & Location
  Widget _buildStep5Content() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: Platform.isIOS ? 400 : 350,
      ), // Extra space for CNTabBar on iOS
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildShippingSection(),
          const SizedBox(height: 20),
          _buildLocationSection(),
        ],
      ),
    );
  }

  // Step 6: Review & Publish
  Widget _buildStep6Content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 300,
      ), // Space for floating navigation
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: widget.isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.isLight ? Colors.white : Colors.black,
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Icon(
                        CupertinoIcons.checkmark_circle,
                        color: widget.isLight ? Colors.black : Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.isEditMode
                            ? AppLocalizations.of(context)?.reviewAndSave ?? AppLocalizations.of(context)!.tr('Review & Save')
                            : 'Review & Publish',
                        style: TextStyle(
                          color: widget.isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                Text(
                  widget.isEditMode
                      ? AppLocalizations.of(context)?.chooseHowToSave ?? AppLocalizations.of(context)!.tr('Choose how to save your changes')
                      : AppLocalizations.of(context)?.chooseHowToSaveProduct ?? AppLocalizations.of(context)!.tr('Choose how to save your product'),
                  style: TextStyle(
                    color: widget.isLight ? Colors.black54 : Colors.white54,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Publish Status Selection
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: widget.isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.publicationStatus ?? AppLocalizations.of(context)!.tr('Publication Status'),
                  style: TextStyle(
                    color: widget.isLight ? Colors.black : Colors.white,
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Publish Option
                TradeRepublicTap(
                  onTap: () {
                    setState(() {
                      publishStatus = 'publish';
                    });
                  },
                  child: Container(
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: publishStatus == 'publish'
                          ? Colors.green.withOpacity(0.1)
                          : (widget.isLight
                                ? Colors.white.withOpacity(0.3)
                                : Colors.black),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: publishStatus == 'publish'
                                ? Colors.green
                                : (widget.isLight
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.1)),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Icon(
                            CupertinoIcons.globe,
                            color: publishStatus == 'publish'
                                ? Colors.white
                                : (widget.isLight
                                      ? Colors.black54
                                      : Colors.white54),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isEditMode
                                    ? AppLocalizations.of(
                                            context,
                                          )?.saveChanges ?? AppLocalizations.of(context)!.tr('Save Changes')
                                    : AppLocalizations.of(
                                            context,
                                          )?.publishNow ?? AppLocalizations.of(context)!.tr('Publish Now'),
                                style: TextStyle(
                                  color: widget.isLight
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.isEditMode
                                    ? (AppLocalizations.of(
                                            context,
                                          )?.makeProductVisibleImmediately ?? AppLocalizations.of(context)!.tr('Make product visible to customers immediately'))
                                    : AppLocalizations.of(
                                            context,
                                          )?.makeProductVisibleImmediately ?? AppLocalizations.of(context)!.tr('Make product visible to customers immediately'),
                                style: TextStyle(
                                  color: widget.isLight
                                      ? Colors.black54
                                      : Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (publishStatus == 'publish')
                          Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: Colors.green,
                            size: 24,
                          ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                // Draft Option
                TradeRepublicTap(
                  onTap: () {
                    setState(() {
                      publishStatus = 'draft';
                    });
                  },
                  child: Container(
                    padding: DesktopAppWrapper.getPagePadding(),
                    decoration: BoxDecoration(
                      color: publishStatus == 'draft'
                          ? Colors.orange.withOpacity(0.1)
                          : (widget.isLight
                                ? Colors.white.withOpacity(0.3)
                                : Colors.black),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: publishStatus == 'draft'
                                ? Colors.orange
                                : (widget.isLight
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.1)),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Icon(
                            Icons.drafts,
                            color: publishStatus == 'draft'
                                ? Colors.white
                                : (widget.isLight
                                      ? Colors.black54
                                      : Colors.white54),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)?.saveAsDraft ?? AppLocalizations.of(context)!.tr('Save as Draft'),
                                style: TextStyle(
                                  color: widget.isLight
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.isEditMode
                                    ? (AppLocalizations.of(
                                            context,
                                          )?.saveProductButKeepHidden ?? AppLocalizations.of(context)!.tr('Save product but keep it hidden from customers'))
                                    : AppLocalizations.of(
                                            context,
                                          )?.saveProductButKeepHidden ?? AppLocalizations.of(context)!.tr('Save product but keep it hidden from customers'),
                                style: TextStyle(
                                  color: widget.isLight
                                      ? Colors.black54
                                      : Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (publishStatus == 'draft')
                          Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: Colors.orange,
                            size: 24,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Summary Info
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: widget.isLight
                  ? Colors.white.withOpacity(0.3)
                  : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.info_circle,
                  color: widget.isLight ? Colors.black54 : Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    publishStatus == 'publish'
                        ? (AppLocalizations.of(
                                context,
                              )?.productWillBePublished ?? AppLocalizations.of(context)!.tr('Product will be published and visible to all customers after saving.'))
                        : (AppLocalizations.of(context)?.productSavedAsDraft ?? AppLocalizations.of(context)!.tr('Product saved as draft!')),
                    style: TextStyle(
                      color: widget.isLight ? Colors.black54 : Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShippingSection() {
    // Initialize shipping fields if not present
    Map<String, dynamic> shipping = variants.first['shipping'] ?? {};
    if (shipping.isEmpty) {
      shipping = {
        'incoterm': 'EXW', // Default Incoterm
        'deliveryTime': '',
        'tracking_available': true,
        'wagonType': 'grain', // Default wagon type
        'cleaning_certificate':
            false, // Cleaning certificate for truck inspection
        'delivery_instructions': '',
        'special_handling': '',
        'temperature_requirements': '',
        'temperature_unit': 'celsius',
        'temperature_min': 2.0,
        'temperature_max': 25.0,
        'packaging_type': '',
      };
      variants.first['shipping'] = shipping;
    }
    // Ensure min/max exist for products loaded without these fields
    shipping['temperature_min'] ??= 2.0;
    shipping['temperature_max'] ??= 25.0;
    shipping['tracking_available'] ??= true;

    return Padding(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.isLight ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Icon(
                  CupertinoIcons.cube_box,
                  color: widget.isLight ? Colors.black : Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.shippingInformation ?? AppLocalizations.of(context)!.tr('Shipping Information'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black : Colors.white,
                        fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)?.configureDeliveryOptions ?? AppLocalizations.of(context)!.tr('Configure delivery options'),
                      style: TextStyle(
                        color: widget.isLight ? Colors.black54 : Colors.white54,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Incoterm Selector
          _buildIncotermSelector(shipping),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),

          // Delivery Time with info button
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    AppLocalizations.of(context)?.deliveryTime ?? AppLocalizations.of(context)!.tr('Delivery Time'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: widget.isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TradeRepublicTap(
                    onTap: () {
                      TopNotification.info(
                        context,
                        'Delivery time: Enter estimated delivery time in days',
                      );
                    },
                    child: Icon(
                      Icons.help_outline,
                      size: 16,
                      color: (widget.isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                    ),
                  ),
                ],
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: validationErrors.contains('deliveryTime')
                            ? Colors.red.withOpacity(0.08)
                            : (widget.isLight ? Colors.white : Colors.black),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: TradeRepublicTextField(
                        useFormField: true,
                        initialValue: shipping['deliveryTime'] ?? AppLocalizations.of(context)!.tr(''),
                        style: TextStyle(
                          color: widget.isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                        ),
                        hintText:
                            AppLocalizations.of(context)?.egTwoToThree ?? AppLocalizations.of(context)!.tr('e.g. 2-3'),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          shipping['deliveryTime'] = value;
                          _clearValidationError('deliveryTime');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isLight ? Colors.white : Colors.black,
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Text(
                      AppLocalizations.of(context)?.days ?? AppLocalizations.of(context)!.tr('days'),
                      style: TextStyle(
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                        color: widget.isLight ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Wagon Type Selector
          // TODO: Implement _buildWagonTypeSelector
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Cleaning Certificate Toggle
          // TODO: Implement _buildCleaningCertificateToggle
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Tracking Toggle + Warning
          // TODO: Implement _buildTrackingAvailabilityToggle
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Delivery Instructions
          TradeRepublicTextField(
            useFormField: true,
            initialValue: shipping['delivery_instructions'] ?? AppLocalizations.of(context)!.tr(''),
            hintText: AppLocalizations.of(context)?.specialDeliveryNotes ?? AppLocalizations.of(context)!.tr('Special delivery notes'),
            maxLines: 3,
            onChanged: (value) => shipping['delivery_instructions'] = value,
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Special Handling Requirements Selector
          // TODO: Implement _buildSpecialHandlingSelector
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

          // Temperature Requirements with Min/Max Sliders
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: label + unit toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context)?.temperatureRequirements ?? AppLocalizations.of(context)!.tr('Temperature Requirements'),
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: widget.isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  TradeRepublicTap(
                    onTap: () => _showTemperatureUnitBottomSheet(shipping),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isLight ? Colors.white : Colors.black,
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (shipping['temperature_unit'] ?? AppLocalizations.of(context)!.tr('celsius')) ==
                                    'celsius'
                                ? '°C'
                                : '°F',
                            style: TextStyle(
                              fontSize: DesktopOptimizedWidgets.getFontSize(),
                              fontWeight: FontWeight.w600,
                              color: widget.isLight
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          _buildModernDropdownIcon(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              // Slider container
              Container(
                padding: DesktopAppWrapper.getPagePadding(),
                decoration: BoxDecoration(
                  color: widget.isLight ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Builder(
                  builder: (context) {
                    final isCelsius =
                        (shipping['temperature_unit'] ?? AppLocalizations.of(context)!.tr('celsius')) ==
                        'celsius';
                    final tempMin = isCelsius ? -30.0 : -22.0;
                    final tempMax = isCelsius ? 60.0 : 140.0;
                    final divisions = isCelsius ? 90 : 162;
                    final minVal =
                        ((shipping['temperature_min'] as num?)?.toDouble() ??
                                2.0)
                            .clamp(tempMin, tempMax);
                    final maxVal =
                        ((shipping['temperature_max'] as num?)?.toDouble() ??
                                25.0)
                            .clamp(tempMin, tempMax);
                    return Column(
                      children: [
                        // Min row
                        Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                'Min',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      (widget.isLight
                                              ? Colors.black
                                              : Colors.white)
                                          .withOpacity(0.5),
                                ),
                              ),
                            ),
                            Expanded(
                              child: TradeRepublicValueSlider(
                                value: minVal,
                                min: tempMin,
                                max: tempMax,
                                divisions: divisions,
                                activeColor: Colors.blue,
                                labelBuilder: (v) => '${v.round()}°',
                                onChanged: (val) {
                                  setState(() {
                                    shipping['temperature_min'] = val;
                                    if (val >
                                        ((shipping['temperature_max'] as num?)
                                                ?.toDouble() ??
                                            25.0)) {
                                      shipping['temperature_max'] = val;
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 48,
                              child: Text(
                                '${minVal.round()}°',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: widget.isLight
                                      ? Colors.black
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TradeRepublicDivider(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          color: (widget.isLight ? Colors.black : Colors.white)
                              .withOpacity(0.08),
                        ),
                        // Max row
                        Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                'Max',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: (widget.isLight ? Colors.black : Colors.white).withOpacity(0.5),
                                ),
                              ),
                            ),
                            Expanded(
                              child: TradeRepublicValueSlider(
                                value: maxVal,
                                min: tempMin,
                                max: tempMax,
                                divisions: divisions,
                                activeColor: Colors.orange,
                                labelBuilder: (v) => '${v.round()}°',
                                onChanged: (val) {
                                  setState(() {
                                    shipping['temperature_max'] = val;
                                    if (val < ((shipping['temperature_min'] as num?)?.toDouble() ?? 2.0)) {
                                      shipping['temperature_min'] = val;
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 48,
                              child: Text(
                                '${maxVal.round()}°',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: widget.isLight ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    if (variants.isEmpty) return const SizedBox.shrink();
    Map<String, dynamic> location = variants.first['location'] ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)?.pickupLocation ?? AppLocalizations.of(context)!.tr('Pickup Location'),
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w700,
            color: widget.isLight ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        TradeRepublicTextField(
          useFormField: true,
          initialValue: location['city'] ?? '',
          hintText: AppLocalizations.of(context)!.tr('City or town'),
          onChanged: (value) {
            location['city'] = value;
            variants.first['location'] = location;
          },
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        TradeRepublicTextField(
          useFormField: true,
          initialValue: location['address'] ?? '',
          hintText: AppLocalizations.of(context)!.tr('Street address'),
          onChanged: (value) {
            location['address'] = value;
            variants.first['location'] = location;
          },
        ),
      ],
    );
  }

  Future<bool> _updateCoordinatesFromAddress(Map<String, dynamic> location) async {
    try {
      final city = location['city']?.toString().trim() ?? '';
      final address = location['address']?.toString().trim() ?? '';
      if (city.isEmpty && address.isEmpty) return false;
      return true;
    } catch (e) {
      print('❌ Error geocoding address: $e');
      return false;
    }
  }

  Widget _buildIncotermSelector(Map<String, dynamic> shipping) {
    final incoterms = ['EXW', 'FCA', 'CPT', 'CIP', 'DAP', 'DPU', 'DDP', 'FAS', 'FOB', 'CFR', 'CIF'];
    final selectedIncoterm = shipping['incoterm'] ?? 'EXW';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.tr('Incoterm'),
          style: TextStyle(
            fontSize: DesktopOptimizedWidgets.getFontSize(),
            fontWeight: FontWeight.w600,
            color: widget.isLight ? Colors.black : Colors.white,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
        TradeRepublicTap(
          onTap: () {
            TradeRepublicBottomSheet.show(
              context: context,
              bottomPadding: 20.0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const DragHandle(),
                    ...incoterms.map((term) => TradeRepublicTap(
                      onTap: () {
                        setState(() => shipping['incoterm'] = term);
                        Navigator.pop(context);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                term,
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: term == selectedIncoterm ? FontWeight.w700 : FontWeight.w400,
                                  color: widget.isLight ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                            if (term == selectedIncoterm)
                              Icon(Icons.check, color: widget.isLight ? Colors.black : Colors.white),
                          ],
                        ),
                      ),
                    )),
                    SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                  ],
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: widget.isLight ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedIncoterm,
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                      color: widget.isLight ? Colors.black : Colors.white,
                    ),
                  ),
                ),
                _buildModernDropdownIcon(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}