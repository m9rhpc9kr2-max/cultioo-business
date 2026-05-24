import 'dart:io';
import 'package:flutter/material.dart';
import 'widgets/glass_effect.dart';
import 'services/app_settings.dart';
import 'services/app_localizations.dart';

class MyAccountPage extends StatelessWidget {
  const MyAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = AppSettings();
    final isLight = appSettings.isLightMode(context);
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          AppLocalizations.of(context)?.myAccount ?? 'My Account',
          style: TextStyle(
            color: isLight ? Colors.black : Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 800 : double.infinity),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
            // Profile Section
            GlassContainer(
              width: double.infinity,
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: isLight
                          ? Colors.black.withOpacity(0.1)
                          : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.person,
                      size: 40,
                      color: isLight ? Colors.black54 : Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.unknownUser ?? 'User',
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'john.doe@cultioo.com',
                          style: TextStyle(
                            color: isLight ? Colors.black54 : Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            AppLocalizations.of(context)?.premiumMember ?? 'Premium Member',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.edit,
                    color: isLight ? Colors.black54 : Colors.white70,
                    size: 20,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Account Options
            Column(
                children: [
                  // Account Type Info
                  GlassContainer(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context)?.accountInformation ?? 'Account Information',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context)?.upgradeToBusinessInfo ?? 'To upgrade to Business features, you need a regular Cultioo account from the Cultioo App or Website. Drivers can register directly without a Cultioo account.',
                          style: TextStyle(
                            color: isLight ? Colors.black54 : Colors.white70,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Options Grid
                  GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: isDesktop ? 3 : 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      children: [
                        _buildAccountOption(
                          icon: Icons.credit_card,
                          title: AppLocalizations.of(context)?.payment ?? 'Payment',
                          subtitle: AppLocalizations.of(context)?.methods ?? 'Methods',
                          color: Colors.blue,
                          isLight: isLight,
                        ),
                        _buildAccountOption(
                          icon: Icons.security,
                          title: AppLocalizations.of(context)?.security ?? 'Security',
                          subtitle: AppLocalizations.of(context)?.privacy ?? 'Privacy',
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          isLight: isLight,
                        ),
                        _buildAccountOption(
                          icon: Icons.notifications,
                          title: AppLocalizations.of(context)?.notifications ?? 'Notifications',
                          subtitle: AppLocalizations.of(context)?.preferences ?? 'Preferences',
                          color: Colors.blue,
                          isLight: isLight,
                        ),
                        _buildAccountOption(
                          icon: Icons.help_outline,
                          title: AppLocalizations.of(context)?.help ?? 'Help',
                          subtitle: AppLocalizations.of(context)?.support ?? 'Support',
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          isLight: isLight,
                        ),
                        _buildAccountOption(
                          icon: Icons.star_outline,
                          title: AppLocalizations.of(context)?.subscription ?? 'Subscription',
                          subtitle: AppLocalizations.of(context)?.premium ?? 'Premium',
                          color: Colors.blue,
                          isLight: isLight,
                        ),
                        _buildAccountOption(
                          icon: Icons.logout,
                          title: AppLocalizations.of(context)?.signOut ?? 'Sign Out',
                          subtitle: AppLocalizations.of(context)?.logout ?? 'Logout',
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                          isLight: isLight,
                        ),
                      ],
                    ),
                ],
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isLight,
  }) {
    return GlassContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: isLight ? Colors.black54 : Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
