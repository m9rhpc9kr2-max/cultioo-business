import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/services/app_settings.dart';
import 'modules/business/pages/main_navigation.dart';
import 'modules/delvioo/pages/delvioo_home_page.dart';

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);

    // Route based on user type
    switch (appSettings.userType) {
      case 'Business':
        return const MainNavigationPage(); // Business navigation with tabs
      case 'Driver':
        return const DelviooHomePage(); // Delvioo driver interface
      default:
        return const MainNavigationPage(); // Default to business
    }
  }
}
