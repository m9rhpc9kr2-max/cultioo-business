import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'shared/services/app_settings.dart';
import 'shared/widgets/trade_republic_button.dart';
import 'shared/widgets/page_indicator.dart';
import 'shared/services/app_localizations.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

class OnboardingStep {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final bool isWelcome;
  final bool isInfo;
  final bool isPermission;
  final String? permissionType;

  OnboardingStep({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    this.isWelcome = false,
    this.isInfo = false,
    this.isPermission = false,
    this.permissionType,
  });
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  final Map<int, ScrollController> _scrollControllers = {};
  int _currentPage = 0;

  ScrollController _getScrollController(int index) {
    if (!_scrollControllers.containsKey(index)) {
      _scrollControllers[index] = ScrollController();
    }
    return _scrollControllers[index]!;
  }

  // Animation Controllers
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late AnimationController _permissionController;

  // Animations
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  List<OnboardingStep> get _steps => [
    OnboardingStep(
      title: AppLocalizations.of(context)?.welcome ?? 'Welcome',
      subtitle:
          AppLocalizations.of(context)?.toCultiooBusiness ??
          'to Cultioo Business',
      description:
          AppLocalizations.of(context)?.yourCompleteBusinessManagement ??
          'Your complete business management solution for deliveries and logistics',
      icon: Icons.business,
      isWelcome: true,
    ),
    OnboardingStep(
      title: AppLocalizations.of(context)?.accountInfo ?? 'Account Info',
      subtitle:
          AppLocalizations.of(context)?.chooseYourPath ?? 'Choose Your Path',
      description:
          '''Business Upgrade: Requires a regular Cultioo account from the Cultioo App or Website.

Driver Registration: Free to go! No Cultioo account required - just register as a driver and start working.''',
      icon: Icons.account_circle,
      isInfo: true,
    ),
    OnboardingStep(
      title: AppLocalizations.of(context)?.setupComplete ?? 'Setup Complete',
      subtitle: AppLocalizations.of(context)?.readyToStart ?? 'Ready to Start',
      description:
          AppLocalizations.of(context)?.cameraStoragePermissions ??
          'You can grant camera and storage permissions later in app settings when you need to take photos or access files.',
      icon: Icons.check_circle,
      isWelcome: true,
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _permissionController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Initialize animations
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1), // Smaller movement
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );

    // Start initial animations
    _startAnimations();

    // Check already granted permissions on startup
    _checkExistingPermissions();
  }

  void _checkExistingPermissions() async {
    // No more permissions required - simple onboarding
  }

  void _startAnimations() async {
    _slideController.forward();
    await Future.delayed(const Duration(milliseconds: 80));
    _scaleController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _scaleController.dispose();
    _permissionController.dispose();
    _pageController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      setState(() {
        _currentPage++;
      });
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _completeOnboarding() {
    final appSettings = Provider.of<AppSettings>(context, listen: false);
    appSettings.setOnboardingCompleted(true);

    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = Provider.of<AppSettings>(context, listen: true);
    final isLight = appSettings.isLightMode(context);
    final isMacOS = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: AnimatedBuilder(
        animation: Listenable.merge([_slideController, _scaleController]),
        builder: (context, child) {
          return Column(
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top),
              Expanded(
                child: Center(
                  child: PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      pageSnapping: true,
                      onPageChanged: (index) {
                        setState(() {
                          _currentPage = index;
                        });
                        _slideController.reset();
                        _scaleController.reset();
                        _startAnimations();
                      },
                      itemCount: _steps.length,
                      itemBuilder: (context, index) {
                        return _buildOnboardingStep(
                          _steps[index],
                          isLight,
                          isMacOS,
                          index,
                        );
                      },
                  ),
                ),
              ),
              _buildBottomSection(isLight, isMacOS),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOnboardingStep(
    OnboardingStep step,
    bool isLight,
    bool isMacOS,
    int index,
  ) {
    final scrollController = _getScrollController(index);

    if (isMacOS) {
      // Desktop Layout - Two Column Design (compact, screen-appropriate)
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left Side - Icon/Logo
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: step.isWelcome
                      ? Image.asset(
                          isLight
                              ? 'assets/cultioo_logo_black.png'
                              : 'assets/cultioo_logo_white.png',
                          width: 160,
                          height: 160,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                color: isLight ? Colors.black : Colors.white,
                                borderRadius: BorderRadius.circular(36),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.10),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Icon(
                                step.icon,
                                size: 72,
                                color: isLight ? Colors.white : Colors.black,
                              ),
                            );
                          },
                        )
                      : Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: isLight ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            step.icon,
                            size: 64,
                            color: isLight ? Colors.white : Colors.black,
                          ),
                        ),
                ),
                const SizedBox(width: 48),
                // Right Side - Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeTransition(
                        opacity: _scaleAnimation,
                        child: Text(
                          step.title,
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.0,
                            height: 1.1,
                          ),
                        ),
                      ),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                      Text(
                        step.subtitle,
                        style: TextStyle(
                          color: isLight
                              ? Colors.black.withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.6),
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                      SlideTransition(
                        position: _slideAnimation,
                        child: Container(
                          padding: DesktopAppWrapper.getPagePadding(),
                          decoration: BoxDecoration(
                            color: isLight
                                ? Colors.black.withValues(alpha: 0.03)
                                : Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.description,
                                style: TextStyle(
                                  color: isLight
                                      ? Colors.black.withValues(alpha: 0.80)
                                      : Colors.white.withValues(alpha: 0.80),
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  height: 1.55,
                                  letterSpacing: 0.1,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              if (step.isInfo) ...[
                                const SizedBox(height: 20),
                                _buildAccountOptionsDesktop(isLight),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Mobile Layout
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 50),
        // Animated Icon with Cultioo logo
        ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: isLight ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              step.icon,
              size: 60,
              color: isLight ? Colors.white : Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 50),
        // Animated Title
        FadeTransition(
          opacity: _scaleAnimation,
          child: Text(
            step.title,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
        Text(
          step.subtitle,
          style: TextStyle(
            color: isLight ? Colors.black54 : Colors.white70,
            fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        // Animated Content
        SlideTransition(
          position: _slideAnimation,
          child: Container(
                  padding: DesktopAppWrapper.getPagePadding(),
                  decoration: BoxDecoration(
                    color: isLight
                        ? Colors.black.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        step.description,
                        style: TextStyle(
                          color: isLight ? Colors.black : Colors.white,
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (step.isInfo) _buildAccountOptions(isLight),
                    ],
                  ),
                ),
        ),
      ],
    );

    return SingleChildScrollView(
      padding: DesktopAppWrapper.getPagePadding(),
      child: content,
    );
  }

  Widget _buildAccountOptionsDesktop(bool isLight) {
    return Column(
      children: [
        _buildAccountOptionDesktop(
          AppLocalizations.of(context)?.businessAccount ??
              'Business Account',
          AppLocalizations.of(context)?.upgradeFromExistingCultioo ??
              'Upgrade from existing Cultioo account',
          Icons.business_center,
          isLight,
        ),
        const SizedBox(height: 10),
        _buildAccountOptionDesktop(
          AppLocalizations.of(context)?.driverAccount ??
              'Driver Account',
          AppLocalizations.of(context)?.registerDirectlyAsDriver ??
              'Register directly as a driver',
          Icons.delivery_dining,
          isLight,
        ),
      ],
    );
  }

  Widget _buildAccountOptionDesktop(
    String title,
    String description,
    IconData icon,
    bool isLight,
  ) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isLight
              ? Colors.black.withValues(alpha: 0.025)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isLight ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: isLight ? Colors.white : Colors.black,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      color: isLight
                          ? Colors.black.withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountOptions(bool isLight) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          _buildAccountOption(
            AppLocalizations.of(context)?.businessAccount ?? 'Business Account',
            AppLocalizations.of(context)?.upgradeFromExistingCultioo ??
                'Upgrade from existing Cultioo account',
            Icons.business_center,
            isLight,
          ),
          SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
          _buildAccountOption(
            AppLocalizations.of(context)?.driverAccount ?? 'Driver Account',
            AppLocalizations.of(context)?.registerDirectlyAsDriver ??
                'Register directly as a driver',
            Icons.delivery_dining,
            isLight,
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildAccountOption(
    String title,
    String description,
    IconData icon,
    bool isLight,
  ) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: DesktopAppWrapper.getPagePadding(),
        decoration: BoxDecoration(
          color: isLight
              ? Colors.black.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isLight ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Icon(
                icon,
                color: isLight ? Colors.white : Colors.black,
                size: 24,
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
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: isLight ? Colors.black54 : Colors.white70,
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection(bool isLight, bool isMacOS) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMacOS ? 48 : 24,
        vertical: isMacOS ? 20 : 24,
      ),
      child: Center(
        child: Container(
          constraints: isMacOS ? const BoxConstraints(maxWidth: 860) : null,
          child: Column(
            children:
            [
              // Page Indicators with Animation
              ScaleTransition(
                scale: _scaleAnimation,
                child: PageIndicator(
                  currentPage: _currentPage,
                  pageCount: _steps.length,
                  pageController: _pageController,
                ),
              ),
              SizedBox(height: isMacOS ? 20 : 32),
              // Action Buttons with Animation
              ScaleTransition(
                scale: _scaleAnimation,
                child: Row(
                  children: [
                    // Back button for macOS
                    if (isMacOS && _currentPage > 0) ...[
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: TradeRepublicButton.icon(
                          icon: Icon(
                            CupertinoIcons.chevron_left,
                            size: 20,
                            color: isLight ? Colors.white : Colors.black,
                          ),
                          onPressed: () {
                            if (_currentPage > 0) {
                              setState(() {
                                _currentPage--;
                              });
                              _pageController.animateToPage(
                                _currentPage,
                                duration: const Duration(milliseconds: 500),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                          isSecondary: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    // Next/Get Started button
                    Expanded(
                      child: SizedBox(
                        height: isMacOS ? 60 : 56,
                        child: TradeRepublicButton(
                          label: _getButtonText(),
                          onPressed: _nextPage,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getButtonText() {
    return _currentPage == _steps.length - 1
        ? AppLocalizations.of(context)?.getStarted ?? 'Get Started'
        : 'Continue';
  }
}
