import 'package:shared_preferences/shared_preferences.dart';

/// Utility script to clear all navigation data from SharedPreferences
/// Run this from Flutter DevTools or add a button in the app to call it
Future<void> clearAllNavigationData() async {
  print('🗑️ Clearing all navigation data from SharedPreferences...');

  final prefs = await SharedPreferences.getInstance();

  // Clear multi-order session data
  await prefs.remove('multi_order_session_id');
  print('✅ Removed: multi_order_session_id');

  // Clear navigation state
  await prefs.remove('navigation_state');
  print('✅ Removed: navigation_state');

  // Clear quick navigation state
  await prefs.remove('quick_navigation_state');
  print('✅ Removed: quick_navigation_state');

  // List all remaining keys for verification
  final allKeys = prefs.getKeys();
  print('\n📋 Remaining SharedPreferences keys:');
  for (var key in allKeys) {
    print('   - $key');
  }

  print('\n🎉 All navigation data cleared!');
  print('💡 Tip: Restart the app to ensure clean state');
}
