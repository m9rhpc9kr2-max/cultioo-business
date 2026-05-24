import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/api_config.dart';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/top_notification.dart';

import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_list_tile.dart';
import '../../../shared/widgets/trade_republic_card.dart';
import '../../../shared/widgets/trade_republic_divider.dart';
import '../../../shared/widgets/trade_republic_section_header.dart';
import '../../../shared/widgets/trade_republic_swipe_action.dart';
import '../../../shared/widgets/trade_republic_theme.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

class DelviooMessagesPage extends StatefulWidget {
  const DelviooMessagesPage({super.key});

  @override
  _DelviooMessagesPageState createState() => _DelviooMessagesPageState();
}

class _DelviooMessagesPageState extends State<DelviooMessagesPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> orders = [];
  List<Map<String, dynamic>> userGroups = [];
  bool isLoading = true;
  bool isDarkMode = false;
  final Map<int, List<Map<String, dynamic>>> messagesCache = {};
  final Map<String, List<Map<String, dynamic>>> groupMessagesCache = {};
  late AnimationController _floatingController;
  String currentUserId = ''; // Dynamic user ID, loaded from SharedPreferences
  String? _myUsername; // Username from SharedPreferences for message comparison

  // Animation Controllers
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late Animation<double> _headerFadeAnim;

  // Animation trigger key - increment to re-trigger animations
  int _listAnimationKey = 0;
  int _groupChatAnimationKey = 0;
  int _orderChatAnimationKey = 0;

  // Swipe functionality for pinning chats
  Set<String> _pinnedChats = <String>{};

  // Deleted chats (persisted locally)
  Set<String> _deletedChats = <String>{};

  // Blocked users (persisted on server)
  Set<String> _blockedUsers = <String>{};

  // Profile data cache for message senders
  final Map<String, Map<String, dynamic>> _profileCache = {};
  // Cache for profile loading futures to avoid re-creating FutureBuilder futures
  final Map<String, Future<Map<String, dynamic>?>> _profileFutureCache = {};
  // Track which profiles are currently being loaded to avoid duplicate requests
  final Set<String> _profileLoadingSet = {};

  // Track if chat modal is open to hide app bar buttons
  bool _isChatOpen = false;

  // Keep selected chat attachment stable across keyboard/layout rebuilds.
  File? _chatSelectedFile;
  String? _chatSelectedFileType; // 'image' or 'pdf'

  // Header visibility controller for bottom sheets
  AnimationController? _headerVisibilityController;
  bool _isBottomSheetOpen = false;

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers
    _headerAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _headerFadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut),
    );

    _contentAnimController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Initialize header visibility controller
    _headerVisibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );

    // Start header animation immediately
    _headerAnimController.forward();

    // Start content animation shortly after header
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _contentAnimController.forward();
      }
    });

    // Initialize floating animation - only start when needed
    _floatingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _loadThemePreference();
    _loadPinnedChats();
    _loadDeletedChats();
    _loadBlockedUsers();
    _fetchOrders();
    _loadUserGroups();
    _checkAndOpenNewGroup();
    _cleanupSharedPreferences(); // Remove email from cache
    _debugLogUserIdentity();
    _loadMyUsername(); // Load username for message comparison
  }

  // Load username from SharedPreferences
  Future<void> _loadMyUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myUsername = prefs.getString('username') ?? currentUserId;
    });
    print('🆔 Loaded myUsername for comparison: $_myUsername');
  }

  // Cleanup SharedPreferences - remove email and only keep username
  Future<void> _cleanupSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // Remove email if it exists
    final email = prefs.getString('email');
    if (email != null) {
      await prefs.remove('email');
      print('🧹 Removed email from SharedPreferences: $email');

      // If no username exists, try to fetch it from backend
      final username = prefs.getString('username');
      if (username == null || username.isEmpty) {
        print('⚠️ No username found, fetching from backend...');
        // TODO: Fetch username from backend using email
      } else {
        print('✅ Username exists: $username');
      }
    }

    // Also remove user_id if it's an email
    final userId = prefs.getString('user_id');
    if (userId != null && userId.contains('@')) {
      await prefs.remove('user_id');
      print('🧹 Removed email-based user_id from SharedPreferences: $userId');
    }
  }

  // Debug: Log user identity to understand which ID is being used
  Future<void> _debugLogUserIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    print('🆔 DEBUG User Identity:');
    print('  - username: ${prefs.getString('username')}');
    print('  - currentUserId: $currentUserId');
    print(
      '  - Will use for messages: ${prefs.getString('username') ?? currentUserId}',
    );
  }

  // Check if a new group was just created and open it automatically
  Future<void> _checkAndOpenNewGroup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newGroupId = prefs.getString('new_group_to_open');

      if (newGroupId != null) {
        // Clear the flag
        await prefs.remove('new_group_to_open');

        // Wait for groups to load
        await Future.delayed(const Duration(milliseconds: 1000));

        // Find and open the group
        final group = userGroups.firstWhere(
          (g) => g['groupId'] == newGroupId,
          orElse: () => {},
        );

        if (group.isNotEmpty && mounted) {
          final appSettings = Provider.of<AppSettings>(context, listen: false);
          final isLight = appSettings.isLightMode(context);
          _showGroupChatBottomSheet(context, group, isLight);
        }
      }
    } catch (e) {
      print('⚠️ Error checking for new group: $e');
    }
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    _contentAnimController.dispose();
    _floatingController.dispose();
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
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
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
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  void _loadThemePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        isDarkMode = prefs.getBool('isDarkMode') ?? false;
      });
    }
  }

  // Load pinned chats from local storage
  Future<void> _loadPinnedChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pinnedList = prefs.getStringList('delvioo_pinned_chats') ?? [];
      if (!mounted) return;
      setState(() {
        _pinnedChats = Set<String>.from(pinnedList);
      });
      print('📌 Loaded pinned chats: $_pinnedChats');
    } catch (e) {
      print('❌ Error loading pinned chats: $e');
    }
  }

  // Save pinned chats to local storage
  Future<void> _savePinnedChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('delvioo_pinned_chats', _pinnedChats.toList());
      print('💾 Saved pinned chats: $_pinnedChats');
    } catch (e) {
      print('❌ Error saving pinned chats: $e');
    }
  }

  // Load deleted chats from local storage
  Future<void> _loadDeletedChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deletedList = prefs.getStringList('delvioo_deleted_chats') ?? [];
      if (!mounted) return;
      setState(() {
        _deletedChats = Set<String>.from(deletedList);
      });
      print('🗑️ Loaded deleted chats: $_deletedChats');
    } catch (e) {
      print('❌ Error loading deleted chats: $e');
    }
  }

  // Save deleted chats to local storage
  Future<void> _saveDeletedChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'delvioo_deleted_chats',
        _deletedChats.toList(),
      );
      print('💾 Saved deleted chats: $_deletedChats');
    } catch (e) {
      print('❌ Error saving deleted chats: $e');
    }
  }

  // Load blocked users from server
  Future<void> _loadBlockedUsers() async {
    try {
      print('🚫 Loading blocked users for: $currentUserId');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/blocked-users/$currentUserId'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Blocked users response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final blockedList = List<String>.from(data['blocked_users'] ?? []);
          if (!mounted) return;
          setState(() {
            _blockedUsers = Set<String>.from(blockedList);
          });
          print('✅ Loaded ${_blockedUsers.length} blocked users');
        }
      }
    } catch (e) {
      print('❌ Error loading blocked users: $e');
    }
  }

  // Block a user
  Future<void> _blockUser(String userId, String userName) async {
    try {
      print('🚫 Blocking user: $userId');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/blocked-users/block'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'blocker_id': currentUserId, 'blocked_id': userId}),
      );

      print('📡 Block user response: ${response.statusCode}');
      print('📡 Block user body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        setState(() {
          _blockedUsers.add(userId);
        });
        print('✅ User blocked successfully');
        if (mounted) {
          TopNotification.success(
            context,
            '$userName ${AppLocalizations.of(context)?.userHasBeenBlocked ?? "has been blocked"}',
          );
        }
        HapticFeedback.mediumImpact();
      } else {
        throw Exception('Failed to block user: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error blocking user: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToBlockUser ??
              'Failed to block user',
        );
      }
    }
  }

  // Unblock a user
  Future<void> _unblockUser(String userId, String userName) async {
    try {
      print('✅ Unblocking user: $userId');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/blocked-users/unblock'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'blocker_id': currentUserId, 'blocked_id': userId}),
      );

      print('📡 Unblock user response: ${response.statusCode}');
      print('📡 Unblock user body: ${response.body}');

      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _blockedUsers.remove(userId);
        });
        print('✅ User unblocked successfully');
        if (mounted) {
          TopNotification.success(
            context,
            '$userName ${AppLocalizations.of(context)?.userHasBeenUnblocked ?? "has been unblocked"}',
          );
        }
        HapticFeedback.mediumImpact();
      } else {
        throw Exception('Failed to unblock user: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error unblocking user: $e');
      if (mounted) {
        TopNotification.error(
          context,
          AppLocalizations.of(context)?.failedToUnblockUser ??
              'Failed to unblock user',
        );
      }
    }
  }

  // Check if a user is blocked
  bool _isUserBlocked(String userId) {
    return _blockedUsers.contains(userId);
  }

  // Toggle pin status for a chat
  void _togglePinChat(String chatId) {
    setState(() {
      if (_pinnedChats.contains(chatId)) {
        _pinnedChats.remove(chatId);
        TopNotification.info(
          context,
          AppLocalizations.of(context)?.chatUnpinned ?? 'Chat unpinned',
        );
      } else {
        _pinnedChats.add(chatId);
        TopNotification.success(
          context,
          AppLocalizations.of(context)?.chatPinned ?? 'Chat pinned',
        );
      }
    });
    _savePinnedChats();
    HapticFeedback.mediumImpact();
  }

  // Delete a chat completely
  Future<void> _deleteChat(String chatId) async {
    try {
      setState(() {
        // Add to deleted chats set (persistent)
        _deletedChats.add(chatId);

        // Remove from pinned if it was pinned
        _pinnedChats.remove(chatId);

        // Remove from lists based on type
        if (chatId.startsWith('order_')) {
          // Extract order ID and remove from orders list
          final orderId = int.tryParse(chatId.replaceFirst('order_', ''));
          if (orderId != null) {
            orders.removeWhere((order) => order['order_id'] == orderId);
            // Also clear from cache
            messagesCache.remove(orderId);
            print('🗑️ Deleted order chat: $orderId');
          }
        } else {
          // Remove from groups list
          userGroups.removeWhere((group) => group['groupId'] == chatId);
          // Also clear from cache
          groupMessagesCache.remove(chatId);
          print('🗑️ Deleted group chat: $chatId');
        }
      });

      // Save deleted chats list (persistent storage)
      await _saveDeletedChats();

      // Save updated pinned list
      await _savePinnedChats();

      // Show confirmation
      TopNotification.success(
        context,
        AppLocalizations.of(context)?.chatDeleted ?? 'Chat deleted',
      );
      HapticFeedback.mediumImpact();

      print('✅ Chat deleted successfully and saved to storage: $chatId');
    } catch (e) {
      print(
        '${AppLocalizations.of(context)?.errorDeletingChat ?? 'Error deleting chat'}: $e',
      );
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.failedToDeleteChat ??
            'Failed to delete chat',
      );
    }
  }

  // Show delete confirmation dialog
  Future<bool> _showDeleteConfirmation(
    BuildContext context,
    bool isLight,
  ) async {
    return await TradeRepublicBottomSheet.show<bool>(
          context: context,
          showDragHandle: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    CupertinoIcons.trash,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      AppLocalizations.of(context)?.deleteChat ?? 'Delete Chat',
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

              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

              // Subtitle
              Text(
                AppLocalizations.of(context)?.deleteConversationConfirm ??
                    'Are you sure you want to delete this conversation? This action cannot be undone.',
                textAlign: TextAlign.start,
                style: TradeRepublicTheme.bodySmall(context),
              ),

              const SizedBox(height: 28),

              TradeRepublicButton(
                label: AppLocalizations.of(context)?.delete ?? 'Delete',
                onPressed: () => Navigator.pop(context, true),
                backgroundColor: const Color(0xFFFF3B30),
                foregroundColor: Colors.white,
                width: double.infinity,
              ),

              const SizedBox(height: 10),

              TradeRepublicButton(
                label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                onPressed: () => Navigator.pop(context, false),
                isSecondary: true,
                width: double.infinity,
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _fetchOrders() async {
    try {
      print('🔗 Fetching messages from Google Cloud SQL...');

      // Get current logged-in user from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final loggedInUsername = prefs.getString('username');

      if (loggedInUsername == null || loggedInUsername.isEmpty) {
        print(
          '⚠️ No username found in SharedPreferences, cannot fetch messages',
        );
        if (mounted) {
          setState(() {
            orders = [];
            isLoading = false;
          });
        }
        return;
      }

      print('👤 Fetching messages for logged-in user: $loggedInUsername');

      // Ensure _myUsername and currentUserId are set early
      if (_myUsername == null || _myUsername!.isEmpty) {
        _myUsername = loggedInUsername;
      }
      if (currentUserId.isEmpty) {
        currentUserId = loggedInUsername;
      }

      // Clear caches when fetching for new user
      messagesCache.clear();
      _profileCache.clear();
      _profileFutureCache.clear(); // Also clear future cache to avoid stale futures
      _profileLoadingSet.clear();

      final String url =
          '${ApiConfig.baseUrl}/api/messages/user/$loggedInUsername';
      final response = await http
          .get(Uri.parse(url), headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));

      print('📡 API Response Status: ${response.statusCode}');
      print('📡 API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        if (responseBody['success'] == true &&
            responseBody['messages'] != null) {
          final messagesList = List<Map<String, dynamic>>.from(
            responseBody['messages'],
          );

          // Filter out deleted chats
          final filteredMessages = messagesList.where((order) {
            final chatId = 'order_${order['order_id']}';
            final isDeleted = _deletedChats.contains(chatId);
            if (isDeleted) {
              print('🚫 Filtering out deleted chat: $chatId');
            }
            return !isDeleted;
          }).toList();

          if (mounted) {
            setState(() {
              orders = filteredMessages;
              isLoading = false;
              _listAnimationKey++; // Trigger animation on data load
            });
          }
          print(
            '✅ Real messages loaded from database for $loggedInUsername: ${filteredMessages.length} (filtered ${messagesList.length - filteredMessages.length} deleted)',
          );
        } else {
          throw Exception(
            'Invalid API response structure: ${responseBody['error'] ?? 'Unknown error'}',
          );
        }
      } else {
        throw Exception('Failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching messages: $e');
      if (mounted) {
        setState(() {
          orders = []; // Keine Mock-Daten verwenden, zeige leere Liste
          isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserGroups() async {
    try {
      print('🎯 Loading user groups for messenger...');

      // Get current user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final username =
          prefs.getString('username') ??
          prefs.getString('delvioo_username') ??
          '';

      if (username.isNotEmpty) {
        if (mounted) {
          setState(() {
            currentUserId = username;
          });
        }
        print('✅ Using username from SharedPreferences: $currentUserId');
      }

      print('🌐 Loading groups for user: $currentUserId');

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/delvioo-groups/user/$currentUserId',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Groups response: ${response.statusCode}');
      print('📡 Groups body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          final groupsList = List<Map<String, dynamic>>.from(
            responseData['groups'] ?? [],
          );

          // Filter out deleted chats
          final filteredGroups = groupsList.where((group) {
            final chatId = group['groupId'] ?? '';
            final isDeleted = _deletedChats.contains(chatId);
            if (isDeleted) {
              print('� Filtering out deleted group: $chatId');
            }
            return !isDeleted;
          }).toList();

          if (mounted) {
            setState(() {
              userGroups = filteredGroups;
              _listAnimationKey++; // Trigger animation on groups load
            });
            print(
              '✅ Loaded ${filteredGroups.length} groups for messenger (filtered ${groupsList.length - filteredGroups.length} deleted)',
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error loading user groups: $e');
      if (mounted) {
        setState(() {
          userGroups = [];
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchGroupMessages(String groupId) async {
    try {
      print('📱 Fetching messages for group: $groupId');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/groups/$groupId/messages'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Group messages response: ${response.statusCode}');
      print('📡 Group messages body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['messages'] ?? []);
        }
      }
    } catch (e) {
      print('❌ Error fetching group messages: $e');
    }
    return [];
  }

  Future<void> _sendGroupMessage(String groupId, String messageText) async {
    try {
      print('📨 Sending group message to: $groupId');
      print('📨 Message: $messageText');

      // Get sender name from SharedPreferences or use fallback
      final prefs = await SharedPreferences.getInstance();
      String senderName = 'Unknown User';

      // Try to get full name or construct it from first/last name
      final fullName = prefs.getString('full_name');
      final firstName = prefs.getString('first_name');
      final lastName = prefs.getString('last_name');

      if (fullName != null && fullName.isNotEmpty) {
        senderName = fullName;
      } else if (firstName != null && firstName.isNotEmpty) {
        senderName = lastName != null && lastName.isNotEmpty
            ? '$firstName $lastName'
            : firstName;
      } else {
        // Fallback to username
        senderName = prefs.getString('username') ?? currentUserId;
      }

      print('📨 Sender name: $senderName');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/groups/$groupId/messages'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'sender_id': currentUserId,
          'sender_type':
              'delvioo', // Changed from 'driver' to 'delvioo' for Delvioo drivers
          'sender_name': senderName,
          'message_text': messageText,
        }),
      );

      print('📡 Send message response: ${response.statusCode}');
      print('📡 Send message body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ Group message sent successfully');
      } else {
        print('❌ Failed to send group message: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error sending group message: $e');
    }
  }

  // Load profile data for message sender - with proper caching to avoid duplicate requests
  Future<Map<String, dynamic>?> _loadProfileData(
    String senderId,
    String senderType,
  ) async {
    try {
      // Check cache first
      final cacheKey = '${senderType}_$senderId';
      if (_profileCache.containsKey(cacheKey)) {
        return _profileCache[cacheKey];
      }
      
      // Check if already loading to avoid duplicate requests
      if (_profileLoadingSet.contains(cacheKey)) {
        // Return existing future if available
        if (_profileFutureCache.containsKey(cacheKey)) {
          return _profileFutureCache[cacheKey];
        }
      }
      
      // Mark as loading and create future
      _profileLoadingSet.add(cacheKey);
      
      final future = _fetchProfileData(senderId, senderType, cacheKey);
      _profileFutureCache[cacheKey] = future;
      
      return future;
    } catch (e) {
      print('❌ Error loading profile for $senderId: $e');
    }
    return null;
  }
  
  // Actual profile data fetching logic (extracted for caching)
  Future<Map<String, dynamic>?> _fetchProfileData(
    String senderId,
    String senderType,
    String cacheKey,
  ) async {
    try {
      // Check cache again (might have been populated while waiting)
      if (_profileCache.containsKey(cacheKey)) {
        return _profileCache[cacheKey];
      }
      
      print('🔍 Loading profile for: $senderId (type: $senderType)');

      // Determine which endpoint to use
      // Support both numeric IDs and email addresses
      final bool isEmail = senderId.contains('@');

      // Track which table we're querying: true = users/business, false = driver
      bool isDriverTable = false;

      String endpoint;
      if (isEmail) {
        // For email addresses, try users table first (business users)
        endpoint = '${ApiConfig.baseUrl}/api/users/profile-by-email/$senderId';
        isDriverTable = false;
        print('📧 Email detected, trying users table first');
      } else {
        // For usernames, use the provided sender type
        // 'delvioo' is the driver user type used in messages — map it to 'driver'
        final normalizedType = (senderType == 'delvioo') ? 'driver' : senderType;
        if (normalizedType == 'driver') {
          endpoint = '${ApiConfig.baseUrl}/api/driver/user-data/$senderId';
          isDriverTable = true;
        } else {
          endpoint = '${ApiConfig.baseUrl}/api/users/profile/$senderId';
          isDriverTable = false;
        }
      }

      var response = await http.get(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Profile response for $senderId: ${response.statusCode}');

      // If email didn't work with users table, try driver table
      if (response.statusCode != 200 && isEmail && !isDriverTable) {
        print('⚠️ Not found in users table, trying driver table');
        endpoint =
            '${ApiConfig.baseUrl}/api/driver/user-data-by-email/$senderId';
        isDriverTable = true;
        response = await http.get(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
        );
        print('📡 Driver table response: ${response.statusCode}');
      }

      // If username/ID didn't work with users table, try driver table
      if (response.statusCode != 200 && !isEmail && !isDriverTable) {
        print('⚠️ Not found in users table, trying driver table with username');
        endpoint = '${ApiConfig.baseUrl}/api/driver/user-data/$senderId';
        isDriverTable = true;
        response = await http.get(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
        );
        print('📡 Driver table response: ${response.statusCode}');
      }

      // If driver table didn't work, try users table (reverse fallback)
      if (response.statusCode != 200 && !isEmail && isDriverTable) {
        print('⚠️ Not found in driver table, trying users table with username');
        endpoint = '${ApiConfig.baseUrl}/api/users/profile/$senderId';
        isDriverTable = false;
        response = await http.get(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
        );
        print('📡 Users table response: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final profileData = data['data'] ?? data['user'];

          // Debug: Print the actual field names received
          print('🔍 Profile data fields: ${profileData.keys.toList()}');
          print('🔍 Raw profile data: $profileData');

          // Determine actual user type based on which table we loaded from
          final bool isBusiness =
              profileData['isBusiness'] == 1 ||
              profileData['isBusiness'] == true;

          // Build profile picture URL with comprehensive field mapping
          // For driver table (delvioo_users): profileImage, profile_image
          // For users table (business): businessLogo, profilePic, profilePicture, profile_image, profileImage
          // For profile-by-email endpoint: profilePicture
          String? profilePicture;
          if (isDriverTable) {
            // Driver table fields
            profilePicture = (profileData['profileImage'] ??
                profileData['profile_image'] ??
                profileData['profilePicture'] ??
                profileData['profilePic'] ??
                '') as String?;
          } else {
            // Business/users table fields
            // profile_image may contain a raw base64 string (buyers stored in cultioo_users)
            // profilePic may be incorrectly prefixed with server host if it was base64 — prefer profile_image
            final rawProfilePic = profileData['profilePic']?.toString() ?? '';
            final rawProfileImage = profileData['profile_image']?.toString() ?? '';
            // If profilePic looks like a broken URL (http://server/data:...), use profile_image instead
            final profilePicIsBroken = rawProfilePic.contains('/data:image/');
            profilePicture = (profileData['businessLogo'] ??
                (profilePicIsBroken ? null : (rawProfilePic.isNotEmpty ? rawProfilePic : null)) ??
                profileData['profilePicture'] ??
                (rawProfileImage.isNotEmpty ? rawProfileImage : null) ??
                profileData['profileImage'] ??
                '') as String?;
          }
          
          // Clean up empty strings
          if (profilePicture != null && profilePicture.isEmpty) {
            profilePicture = null;
          }

          final Map<String, dynamic> profile = {
            'profilePicture': profilePicture,
            'firstName':
                profileData['first_name'] ??
                profileData['firstName'] ??
                profileData['firstname'] ??
                '',
            'lastName':
                profileData['last_name'] ??
                profileData['lastName'] ??
                profileData['lastname'] ??
                '',
            'username':
                profileData['username'] ??
                profileData['user_id'] ??
                profileData['userId'] ??
                '',
            'businessName':
                profileData['businessName'] ??
                profileData['business_name'] ??
                profileData['business_company'] ??
                '',
            'userType': isDriverTable
                ? AppLocalizations.of(context)?.driverLabel ?? 'Driver'
                : AppLocalizations.of(context)?.business ?? 'Business',
            'isBusiness': isBusiness,
          };

          print('🖼️ Profile picture URL: ${profile['profilePicture']}');
          print(
            '👤 User type: ${profile['userType']}, Is Business: ${profile['isBusiness']}',
          );

          // Cache the profile data
          if (mounted) {
            setState(() {
              _profileCache[cacheKey] = profile;
            });
          }

          print(
            '✅ Profile loaded: ${profile['firstName']} ${profile['lastName']} (${profile['userType']})',
          );
          return profile;
        }
      }
    } catch (e) {
      print('❌ Error loading profile for $senderId: $e');
    } finally {
      _profileLoadingSet.remove(cacheKey);
    }
    return null;
  }
  
  // Build a profile avatar image widget that supports both HTTP URLs and base64 data URIs.
  // Returns null if profilePicture is null/empty so callers can show initials instead.
  Widget? _buildAvatarImage(String? profilePicture, double size, double borderRadius) {
    if (profilePicture == null || profilePicture.isEmpty) return null;

    final isBase64 = profilePicture.startsWith('data:image/');
    final isHttp = profilePicture.startsWith('http://') || profilePicture.startsWith('https://');

    if (!isBase64 && !isHttp) return null;

    Widget imageWidget;
    if (isBase64) {
      try {
        // Strip the data URI prefix: "data:image/jpeg;base64,"
        final commaIndex = profilePicture.indexOf(',');
        if (commaIndex == -1) return null;
        final base64Str = profilePicture.substring(commaIndex + 1);
        final bytes = base64Decode(base64Str);
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      } catch (_) {
        return null;
      }
    } else {
      imageWidget = Image.network(
        profilePicture,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageWidget,
    );
  }

  // Get a stable future for profile loading (prevents FutureBuilder from re-fetching)
  Future<Map<String, dynamic>?> _getProfileFuture(String senderId, String senderType) {
    final cacheKey = '${senderType}_$senderId';
    if (_profileFutureCache.containsKey(cacheKey)) {
      return _profileFutureCache[cacheKey]!;
    }
    final future = _loadProfileData(senderId, senderType);
    _profileFutureCache[cacheKey] = future;
    return future;
  }

  // Select image from gallery or camera (show preview only)
  Future<File?> _selectImage() async {
    try {
      final ImagePicker picker = ImagePicker();

      // On macOS, skip camera/gallery dialog and go straight to gallery
      ImageSource source;
      if (Platform.isMacOS) {
        source = ImageSource.gallery;
      } else {
        // Show options for camera or gallery on mobile
        final ImageSource? selectedSource = await _showImageSourceDialog();
        if (selectedSource == null) return null;
        source = selectedSource;
      }

      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image != null) {
        print('📷 Image selected: ${image.path}');
        print('📏 Image size: ${await image.length()} bytes');
        print('🏷️ Image name: ${image.name}');

        // Validate file size (max 10MB)
        final fileSize = await image.length();
        if (fileSize > 10 * 1024 * 1024) {
          _showError(
            AppLocalizations.of(context)?.imageTooLargeMax10mb ??
                'Image too large. Maximum size is 10MB.',
          );
          return null;
        }

        // Ensure file has correct extension
        String fileName = image.name.toLowerCase();
        if (!fileName.endsWith('.jpg') &&
            !fileName.endsWith('.jpeg') &&
            !fileName.endsWith('.png') &&
            !fileName.endsWith('.webp')) {
          // Add .jpg extension if missing
          fileName = '$fileName.jpg';
          print('🔄 Added .jpg extension: $fileName');
        }

        return File(image.path);
      }
    } catch (e) {
      print('❌ Error selecting image: $e');
      _showError(
        '${AppLocalizations.of(context)?.failedToSelectImage ?? "Failed to select image"}: ${e.toString()}',
      );
    }
    return null;
  }

  // Select PDF file (show preview only)
  Future<File?> _selectPDF() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
        withData: false, // Don't load file data into memory
        withReadStream: false,
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        final fileName = result.files.single.name;
        final fileSize = result.files.single.size;

        print('📄 PDF selected: ${file.path}');
        print('📏 PDF size: $fileSize bytes');
        print('🏷️ PDF name: $fileName');

        // Validate file size (max 10MB)
        if (fileSize > 10 * 1024 * 1024) {
          _showError(
            AppLocalizations.of(context)?.pdfTooLargeMax10mb ??
                'PDF too large. Maximum size is 10MB.',
          );
          return null;
        }

        // Validate file extension
        if (!fileName.toLowerCase().endsWith('.pdf')) {
          _showError('Invalid file format. Only PDF files are allowed.');
          return null;
        }

        return file;
      }
    } catch (e) {
      print('❌ Error selecting PDF: $e');
      _showError(
        '${AppLocalizations.of(context)?.failedToSelectPdf ?? "Failed to select PDF"}: ${e.toString()}',
      );
    }
    return null;
  }

  // Upload file to server
  Future<void> _uploadFileToServer(
    File file,
    int orderId,
    String fileType,
  ) async {
    try {
      print('📤 Uploading $fileType to server...');
      print('📁 File path: ${file.path}');

      // Get sender username from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final sender = prefs.getString('username') ?? currentUserId;

      // Get receiver from order data
      String receiver = ''; // Will be resolved from order
      String receiverType = 'business'; // Default
      try {
        final order = orders.firstWhere((order) {
          if (orderId == 0) {
            return order['order_id'] == null || order['order_id'] == 0;
          }
          return order['order_id'] == orderId;
        });
        receiver = order['other_username'] ??
          (AppLocalizations.of(context)?.unknownUser ?? '');
        receiverType = order['other_user_type'] ?? 'business';
      } catch (e) {
        print('⚠️ Could not find receiver for order $orderId, using default');
      }

      print('📨 Upload sender: $sender');
      print('📨 Upload receiver: $receiver');
      print('📨 Upload receiver_type: $receiverType');

      // Determine correct MIME type
      String mimeType;
      String fileName = file.path.split('/').last.toLowerCase();

      if (fileType == 'image') {
        if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')) {
          mimeType = 'image/jpeg';
        } else if (fileName.endsWith('.png')) {
          mimeType = 'image/png';
        } else if (fileName.endsWith('.webp')) {
          mimeType = 'image/webp';
        } else {
          // Default to JPEG for images
          mimeType = 'image/jpeg';
          print('🔄 Unknown image format, defaulting to image/jpeg');
        }
      } else {
        mimeType = 'application/pdf';
      }

      print('🏷️ MIME type: $mimeType');
      print('📝 File name: $fileName');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/messages/orders/$orderId/upload'),
      );

      request.fields['sender'] = sender;
      request.fields['receiver'] = receiver;
      request.fields['message_type'] = fileType;
      request.fields['sender_type'] =
          'delvioo'; // Current user is delvioo driver
      request.fields['receiver_type'] =
          receiverType; // Use type from order data
      request.fields['file_name'] = fileName;

      // Add file with correct MIME type
      var multipartFile = await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(mimeType),
      );

      request.files.add(multipartFile);

      print('📦 Request fields: ${request.fields}');
      print(
        '📎 File info: ${multipartFile.filename}, ${multipartFile.contentType}',
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      print('📡 Upload response: ${response.statusCode}');
      print('📡 Upload body: $responseBody');

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ File uploaded successfully');
        TopNotification.success(
          context,
          '${fileType == 'image' ? AppLocalizations.of(context)?.image ?? 'Image' : 'PDF'} uploaded successfully',
        );
      } else {
        throw Exception(
          'Upload failed with status: ${response.statusCode}. Response: $responseBody',
        );
      }
    } catch (e) {
      print('❌ Error uploading file to server: $e');
      rethrow;
    }
  }

  // Show image source bottom sheet
  Future<ImageSource?> _showImageSourceDialog() async {
    final AppSettings appSettings = Provider.of<AppSettings>(
      context,
      listen: false,
    );
    final isLight = appSettings.isLightMode(context);

    return TradeRepublicBottomSheet.show<ImageSource>(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title:
                AppLocalizations.of(context)?.selectImageSource ??
                'Select Image Source',
            leading: Icon(
              CupertinoIcons.photo_on_rectangle,
              size: 20,
              color: TradeRepublicTheme.textColor(context),
            ),
          ),

          TradeRepublicCard(
            backgroundColor: isLight ? null : Colors.transparent,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                TradeRepublicListTile.navigation(
                  title: AppLocalizations.of(context)?.camera ?? 'Camera',
                  subtitle:
                      AppLocalizations.of(context)?.takeAPhoto ??
                      'Take a photo',
                  leading: Icon(
                    CupertinoIcons.camera,
                    size: 20,
                    color: TradeRepublicTheme.textColor(context),
                  ),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context, ImageSource.camera);
                  },
                ),
                const TradeRepublicDivider(),
                TradeRepublicListTile.navigation(
                  title: AppLocalizations.of(context)?.gallery ?? 'Gallery',
                  subtitle:
                      AppLocalizations.of(context)?.chooseFromGallery ??
                      'Choose from gallery',
                  leading: Icon(
                    CupertinoIcons.photo,
                    size: 20,
                    color: TradeRepublicTheme.textColor(context),
                  ),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context, ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            isSecondary: true,
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  // Show error message
  void _showError(String message) {
    TopNotification.error(context, message);
  }

  // Show full-screen image viewer with download option
  void _showFullScreenImage(
    BuildContext context,
    List<String> imageCandidates,
    bool isLight,
  ) {
    if (imageCandidates.isEmpty) return;
    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height,
      child: _buildFullScreenImageViewer(imageCandidates, isLight, context),
    );
  }

  // Build full-screen image viewer widget
  Widget _buildFullScreenImageViewer(
    List<String> imageCandidates,
    bool isLight,
    BuildContext context,
  ) {
    Widget buildFullscreenImage(int index) {
      if (index >= imageCandidates.length) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.photo_on_rectangle,
                color: Colors.white,
                size: 64,
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
              Text(
                AppLocalizations.of(context)?.imageNotAvailable ??
                    'Image not available',
                style: const TextStyle(color: Colors.white, fontSize: DesktopOptimizedWidgets.getFontSize(),,
              ),
            ],
          ),
        );
      }
      final url = imageCandidates[index];
      return Image.network(
        url,
        fit: BoxFit.contain,
        headers: const {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'image/*',
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(child: CultiooLoadingIndicator());
        },
        errorBuilder: (context, error, stackTrace) {
          if (index + 1 < imageCandidates.length) {
            return buildFullscreenImage(index + 1);
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.photo_on_rectangle,
                  color: Colors.white,
                  size: 64,
                ),
                const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                Text(
                  AppLocalizations.of(context)?.imageNotAvailable ??
                      'Image not available',
                  style: const TextStyle(color: Colors.white, fontSize: DesktopOptimizedWidgets.getFontSize(),,
                ),
              ],
            ),
          );
        },
      );
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Stack(
        children: [
          // Background
          Container(color: Colors.black),

          // Image
          Center(
            child: InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: buildFullscreenImage(0),
            ),
          ),

          // iOS-style Header with close and download buttons
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TradeRepublicButton.icon(
                      icon: const Icon(
                        CupertinoIcons.xmark,
                        color: Colors.white,
                        size: 22,
                      ),
                      size: 44,
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                      foregroundColor: Colors.white,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                    ),
                    TradeRepublicButton.icon(
                      icon: const Icon(
                        CupertinoIcons.arrow_down_to_line,
                        color: Colors.white,
                        size: 22,
                      ),
                      size: 44,
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                      foregroundColor: Colors.white,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _downloadImage(imageCandidates);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Download image functionality with permission handling
  Future<void> _downloadImage(List<String> imageUrls) async {
    try {
      if (imageUrls.isEmpty) return;
      print('📥 Starting image download, candidates: $imageUrls');

      // Check and request storage permission
      // Android 13+ (API 33+): no permission needed to write to Downloads/Pictures
      // under scoped storage — READ_MEDIA_IMAGES is for reading gallery, not saving.
      if (Platform.isAndroid) {
        final androidVersion = await _getAndroidVersion();
        if (androidVersion < 33) {
          PermissionStatus permission;
          if (androidVersion >= 30) {
            // Android 11–12: MANAGE_EXTERNAL_STORAGE for Downloads folder
            permission = await Permission.manageExternalStorage.request();
          } else {
            // Android ≤10: legacy storage permission
            permission = await Permission.storage.request();
          }
          if (!permission.isGranted) {
            TopNotification.warning(
              context,
              AppLocalizations.of(context)?.storagePermissionRequiredImages ??
                  'Storage permission is required to download images',
            );
            return;
          }
        }
      } else {
        final permission = await Permission.storage.request();
        if (!permission.isGranted) {
          TopNotification.warning(
            context,
            AppLocalizations.of(context)?.storagePermissionRequiredImages ??
                'Storage permission is required to download images',
          );
          return;
        }
      }

      // Show loading indicator
      TopNotification.info(
        context,
        AppLocalizations.of(context)?.downloadingImage ??
            'Downloading image...',
      );

      // Download the image — try each URL until one succeeds
      http.Response? response;
      for (final imageUrl in imageUrls) {
        try {
          final r = await http.get(Uri.parse(imageUrl));
          if (r.statusCode == 200) {
            response = r;
            break;
          }
        } catch (_) {
          continue;
        }
      }

      if (response != null && response.statusCode == 200) {
        // Create a unique filename
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'Cultioo_Image_$timestamp.jpg';

        String? savedPath;

        if (Platform.isAndroid) {
          // Try multiple Android storage locations
          final possiblePaths = [
            '/storage/emulated/0/Download',
            '/storage/emulated/0/Pictures',
            '/storage/emulated/0/DCIM',
          ];

          for (String path in possiblePaths) {
            try {
              final directory = Directory(path);
              if (await directory.exists()) {
                final filePath = '$path/$fileName';
                final file = File(filePath);
                await file.writeAsBytes(response.bodyBytes);
                savedPath = filePath;
                print('✅ Image saved to: $savedPath');
                break;
              }
            } catch (e) {
              print('⚠️ Failed to save to $path: $e');
              continue;
            }
          }

          // If all public directories failed, use app external storage
          if (savedPath == null) {
            final directory = await getExternalStorageDirectory();
            if (directory != null) {
              final downloadsPath = '${directory.path}/Downloads';
              final downloadsDir = Directory(downloadsPath);
              if (!await downloadsDir.exists()) {
                await downloadsDir.create(recursive: true);
              }
              final filePath = '$downloadsPath/$fileName';
              final file = File(filePath);
              await file.writeAsBytes(response.bodyBytes);
              savedPath = filePath;
              print('✅ Image saved to app directory: $savedPath');
            }
          }
        } else {
          // For other platforms
          final directory = await getExternalStorageDirectory();
          if (directory != null) {
            final filePath = '${directory.path}/$fileName';
            final file = File(filePath);
            await file.writeAsBytes(response.bodyBytes);
            savedPath = filePath;
            print('✅ Image saved to: $savedPath');
          }
        }

        if (savedPath != null) {
          // Show success message
          TopNotification.success(
            context,
            AppLocalizations.of(context)?.imageSaved ??
                'Image saved successfully',
          );
        } else {
          throw Exception('Could not find suitable storage location');
        }
      } else {
        throw Exception(
          response == null
              ? 'Failed to download image from all URLs'
              : 'Failed to download image: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Error downloading image: $e');

      TopNotification.error(context, 'Download failed: ${e.toString()}');
    }
  }

  // Helper method to get Android API level (simplified)
  Future<int> _getAndroidVersion() async {
    // For simplicity, assume modern Android
    // In production, use device_info_plus to get actual API level
    return 30;
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _fetchOrders(),
      _loadUserGroups(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings appSettings = Provider.of<AppSettings>(context);
    final isLight = appSettings.isLightMode(context);
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    // Filter out blocked users from orders
    final filteredOrders = orders.where((order) {
      final otherUsername = order['other_username'] ?? '';
      return !_isUserBlocked(otherUsername);
    }).toList();

    // Count total conversations and messages (excluding blocked users)
    final totalConversations = (filteredOrders.length + userGroups.length);
    int unreadMessagesCount = 0;

    // Count messages from filtered orders only
    for (var order in filteredOrders) {
      final messageCount = order['message_count'] ?? 0;
      if (messageCount > 0) {
        unreadMessagesCount += (messageCount as num).toInt();
      }
    }

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 800 : double.infinity,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section - Trade Republic Style (like Account Page)
              AnimatedBuilder(
                animation: _headerVisibilityController != null
                    ? Listenable.merge([
                        _headerAnimController,
                        _headerVisibilityController!,
                      ])
                    : _headerAnimController,
                builder: (context, child) {
                  final visibilityValue =
                      _headerVisibilityController?.value ?? 1.0;
                  return Opacity(
                    opacity: _headerFadeAnim.value * visibilityValue,
                    child: child,
                  );
                },
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    isDesktop ? 32 : MediaQuery.of(context).padding.top + 20,
                    20,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title Row with action buttons
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title - Trade Republic Style
                                Text(
                                  AppLocalizations.of(context)?.messages ??
                                      'Messages',
                                  style: TextStyle(
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppLocalizations.of(
                                        context,
                                      )?.chatWithCustomers ??
                                      'Chat with customers',
                                  style: TextStyle(
                                    color: isLight
                                        ? Colors.black.withOpacity(0.5)
                                        : Colors.white.withOpacity(0.5),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Unread Badge
                          if (unreadMessagesCount > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF3B30),
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                              ),
                              child: Text(
                                '$unreadMessagesCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],

                          // Action Buttons (hide when chat is open)
                          if (!_isChatOpen) ...[
                            // New Chat Button
                            TradeRepublicButton.icon(
                              icon: const Icon(CupertinoIcons.plus, size: 20),
                              size: 40,
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                _showNewChatModal(context, isLight);
                              },
                            ),
                            const SizedBox(width: 8),
                            // Settings Button
                            TradeRepublicButton.icon(
                              icon: const Icon(
                                CupertinoIcons.ellipsis,
                                size: 20,
                              ),
                              size: 40,
                              isSecondary: true,
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                _showSettingsBottomSheet(isLight);
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // Messages List - Expanded to fill remaining space
              // CullyAI always shown first regardless of orders/groups
              Expanded(
                child: isLoading
                    ? const Center(child: CultiooLoadingIndicator())
                    : _buildMessagesList(isLight),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingAppBar(
    bool isLight,
    int conversationsCount,
    int unreadCount,
  ) {
    // Standard layout for all platforms
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Icon + Title section
        Row(
          children: [
            Icon(
              CupertinoIcons.chat_bubble,
              color: isLight ? Colors.black : Colors.white,
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              AppLocalizations.of(context)?.messages ?? 'Messages',
              style: TextStyle(
                color: isLight ? Colors.black : Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),

        // Right side buttons - Fallback for non-iOS
        if (!_isChatOpen)
          Row(
            children: [
              TradeRepublicButton.icon(
                icon: const Icon(CupertinoIcons.plus_circle, size: 22),
                size: 36,
                isSecondary: true,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _showNewChatModal(context, isLight);
                },
              ),
              const SizedBox(width: 8),
              TradeRepublicButton.icon(
                icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 22),
                size: 36,
                isSecondary: true,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _showUserManagementModal(isLight);
                },
              ),
            ],
          ),
      ],
    );
  }

  // Modern empty state with animation - Trade Republic Style
  Widget _buildEmptyState(bool isLight) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.chat_bubble_2,
              size: 56,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.2),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)?.noMessagesYet ?? 'No Messages Yet',
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                fontWeight: FontWeight.w700,
                color: isLight ? Colors.black : Colors.white,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            Text(
              AppLocalizations.of(context)?.startConversation ??
                  'Start a conversation with customers and group members',
              style: TextStyle(
                fontSize: DesktopOptimizedWidgets.getFontSize(),
                color: (isLight ? Colors.black : Colors.white).withOpacity(
                  0.45,
                ),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Messages list
  Widget _buildMessagesList(bool isLight) {
    // Filter out blocked users from orders
    final filteredOrders = orders.where((order) {
      final otherUsername = order['other_username'] ?? '';
      final isBlocked = _isUserBlocked(otherUsername);
      if (isBlocked) {
        print('🚫 Hiding chat with blocked user: $otherUsername');
      }
      return !isBlocked;
    }).toList();

    // Create combined list of all chats with type info for sorting
    List<Map<String, dynamic>> allChats = [];

    // Add groups
    for (var group in userGroups) {
      final groupId = group['groupId'] ?? '';
      allChats.add({
        'type': 'group',
        'data': group,
        'isPinned': _pinnedChats.contains(groupId),
        'id': groupId,
      });
    }

    // Add orders
    for (var order in filteredOrders) {
      final orderId = order['order_id'];
      allChats.add({
        'type': 'order',
        'data': order,
        'isPinned': _pinnedChats.contains('order_$orderId'),
        'id': 'order_$orderId',
      });
    }

    // Sort: pinned first, then by original order
    allChats.sort((a, b) {
      final aPinned = a['isPinned'] as bool;
      final bPinned = b['isPinned'] as bool;
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return 0; // Keep original order within same pin status
    });

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: _refreshData,
          refreshTriggerPullDistance: 80,
          refreshIndicatorExtent: 60,
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // ── CullyAI always first ──────────────────────────────
                if (index == 0) {
                  return _buildAnimatedChatCard(
                    child: _buildCullyAiCard(isLight),
                    index: 0,
                  );
                }

                final chat = allChats[index - 1];
                final chatType = chat['type'] as String;

                if (chatType == 'group') {
                  final group = chat['data'] as Map<String, dynamic>;
                  return _buildAnimatedChatCard(
                    child: _buildGroupChatCard(group, isLight),
                    index: index,
                  );
                } else {
                  final order = chat['data'] as Map<String, dynamic>;
                  final orderId = order['order_id'] as int?;
                  return _buildAnimatedChatCard(
                    child: _buildOrderChatCard(order, orderId ?? 0, isLight),
                    index: index,
                  );
                }
              },
              childCount: allChats.length + 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCullyAiCard(bool isLight) {
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        _openCullyAiChat(isLight);
      },
      child: TradeRepublicCard(
        backgroundColor: isLight ? null : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            // CullyAI Avatar
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Image.asset(
                isLight ? 'logo/cully_light.png' : 'logo/cully_dark.png',
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'CullyAI',
                        style: TextStyle(
                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your intelligent assistant — tap to chat',
                    style: TextStyle(
                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                      fontWeight: FontWeight.w400,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.2),
            ),
          ],
        ),
      ),
    );
  }

  void _openCullyAiChat(bool isLight) {
    setState(() {
      _isChatOpen = true;
    });
    _hideHeader();
    Navigator.of(context)
        .push(
          CupertinoPageRoute(
            builder: (context) => _CullyAiChatPage(isLight: isLight),
          ),
        )
        .then((_) {
          setState(() {
            _isChatOpen = false;
          });
          _showHeader();
        });
  }

  // Animated wrapper for chat cards with staggered slide-in effect
  Widget _buildAnimatedChatCard({required Widget child, required int index}) {
    // Use a key that changes when data is reloaded to re-trigger animation
    return TweenAnimationBuilder<double>(
      key: ValueKey('chat_anim_${_listAnimationKey}_$index'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 80).clamp(0, 400)),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final clampedValue = value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 30 * (1 - clampedValue)),
          child: Opacity(
            opacity: clampedValue,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupChatCard(Map<String, dynamic> group, bool isLight) {
    final memberCount = group['memberCount'] ?? 0;
    final isHost = group['isHost'] ?? false;
    final groupId = group['groupId'] ?? '';
    final isPinned = _pinnedChats.contains(groupId);
    final lastMessage =
        group['lastMessage'] ??
        AppLocalizations.of(context)?.tapToOpenChat ??
        'Tap to open chat';
    final lastMessageTime = group['lastMessageTime'] ?? group['updated_at'];

    return TradeRepublicSwipeAction(
      key: ValueKey('group_$groupId'),
      leading: TradeRepublicSwipeSpec(
        icon: CupertinoIcons.pin_fill,
        label: 'Pin',
        activeIcon: CupertinoIcons.pin_slash_fill,
        activeLabel: AppLocalizations.of(context)?.unpin ?? 'Unpin',
        isActive: isPinned,
        iconRotation: -0.5,
        onActivate: () => _togglePinChat(groupId),
      ),
      trailing: TradeRepublicSwipeSpec(
        icon: CupertinoIcons.delete_solid,
        label: AppLocalizations.of(context)?.delete ?? 'Delete',
        backgroundColor: const Color(0xFFFF3B30),
        foregroundColor: Colors.white,
        onActivate: () async {
          final confirmed = await _showDeleteConfirmation(context, isLight);
          if (confirmed) {
            await _deleteChat(groupId);
          }
        },
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        _showGroupChatBottomSheet(context, group, isLight);
      },
      child: TradeRepublicCard(
        backgroundColor: isLight ? null : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            // Group Avatar - Trade Republic style
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isLight ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      CupertinoIcons.person_2,
                      color: isLight ? Colors.white : Colors.black,
                      size: 24,
                    ),
                  ),
                  if (isPinned)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: isLight ? Colors.black : Colors.white,
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Icon(
                          CupertinoIcons.pin_fill,
                          size: 10,
                          color: isLight ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 14),

            // Group Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group['name'] ??
                              AppLocalizations.of(context)?.groupChat ??
                              'Group Chat',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            fontWeight: FontWeight.w600,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastMessageTime != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _formatMessageTime(lastMessageTime),
                          style: TextStyle(
                            fontSize: 13,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (isHost)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Text(
                            AppLocalizations.of(context)?.host ?? 'Host',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          '$memberCount members • $lastMessage',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Chevron
            Icon(
              CupertinoIcons.chevron_right,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.2),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderChatCard(
    Map<String, dynamic> order,
    int orderId,
    bool isLight,
  ) {
    // Use 'direct_username' for null order_id (direct messages)
    final conversationId = orderId == 0
        ? 'direct_${order['other_username'] ?? 'unknown'}'
        : 'order_$orderId';
    final isPinned = _pinnedChats.contains(conversationId);
    final messageCount = order['message_count'] ?? 0;
    final lastMessage =
        order['last_message'] ??
        AppLocalizations.of(context)?.tapToOpenChat ??
        'Tap to open chat';
    final lastMessageTime = order['last_message_time'] ?? order['updated_at'];

    return TradeRepublicSwipeAction(
      key: ValueKey('conv_$conversationId'),
      leading: TradeRepublicSwipeSpec(
        icon: CupertinoIcons.pin_fill,
        label: 'Pin',
        activeIcon: CupertinoIcons.pin_slash_fill,
        activeLabel: AppLocalizations.of(context)?.unpin ?? 'Unpin',
        isActive: isPinned,
        iconRotation: -0.5,
        onActivate: () => _togglePinChat(conversationId),
      ),
      trailing: TradeRepublicSwipeSpec(
        icon: CupertinoIcons.delete_solid,
        label: AppLocalizations.of(context)?.delete ?? 'Delete',
        backgroundColor: const Color(0xFFFF3B30),
        foregroundColor: Colors.white,
        onActivate: () async {
          final confirmed = await _showDeleteConfirmation(context, isLight);
          if (confirmed) {
            await _deleteChat(conversationId);
          }
        },
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        _showLiquidGlassBottomSheet(context, orderId, isLight);
      },
      child: TradeRepublicCard(
        backgroundColor: isLight ? null : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            // Avatar - Trade Republic style with profile picture
            FutureBuilder<Map<String, dynamic>?>(
              future: _getProfileFuture(
                order['other_username']?.toString() ?? '',
                order['other_user_type']?.toString() ?? 'customer',
              ),
              builder: (context, snapshot) {
                final profileData = snapshot.data;
                final profilePictureRaw = profileData?['profilePicture'];

                // Use ApiConfig.getImageUrl to properly handle Google Cloud Storage URLs
                String? profilePicture;
                if (profilePictureRaw != null &&
                    profilePictureRaw.toString().isNotEmpty) {
                  profilePicture = ApiConfig.getImageUrl(
                    profilePictureRaw.toString(),
                  );
                }

                // Get other_user_type from order for accurate type determination
                final otherUserType =
                    order['other_user_type']?.toString() ?? '';
                final firstName = profileData?['firstName'] ?? '';
                final lastName = profileData?['lastName'] ?? '';
                final initials = firstName.isNotEmpty
                    ? '${firstName[0]}${lastName.isNotEmpty ? lastName[0] : ''}'
                          .toUpperCase()
                    : (order['customer_name'] ?? 'U')[0].toUpperCase();

                // Badge icon and color based on other_user_type - Trade Republic style
                IconData badgeIcon;
                Color badgeColor;

                if (otherUserType == 'business') {
                  badgeIcon = CupertinoIcons.building_2_fill;
                  badgeColor = isLight ? Colors.black : Colors.white;
                } else if (otherUserType == 'delvioo') {
                  badgeIcon = CupertinoIcons.cube_box;
                  badgeColor = isLight ? Colors.black : Colors.white;
                } else {
                  badgeIcon = CupertinoIcons.person_fill;
                  badgeColor = isLight ? Colors.black : Colors.white;
                }

                return Stack(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isLight ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: _buildAvatarImage(profilePicture, 52, 20) ??
                          Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                fontWeight: FontWeight.w600,
                                color: isLight ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                    ),
                    // Pin indicator
                    if (isPinned)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isLight ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Icon(
                            CupertinoIcons.pin_fill,
                            size: 10,
                            color: isLight ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    // User type badge based on sender_type
                    if (!isPinned)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Center(
                            child: Icon(
                              badgeIcon,
                              size: 8,
                              color: isLight ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),

            const SizedBox(width: 14),

            // Chat Info
            Expanded(
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _getProfileFuture(
                  order['other_username']?.toString() ??
                      order['sender_id']?.toString() ??
                      '',
                  order['other_user_type']?.toString() ?? 'customer',
                ),
                builder: (context, snapshot) {
                    String displayName = order['other_username'] ??
                      (AppLocalizations.of(context)?.userFallback ?? '');

                  if (snapshot.hasData && snapshot.data != null) {
                    final profile = snapshot.data!;
                    final businessName = profile['businessName'] ?? '';
                    final username = profile['username'] ?? '';
                    final firstName = profile['firstName'] ?? '';
                    final lastName = profile['lastName'] ?? '';
                    final otherUserType =
                        order['other_user_type']?.toString() ?? '';

                    // Show name based on other_user_type:
                    // - If other_user_type='business': Show business name
                    // - If other_user_type='user': Show username (not business name!)
                    // - If other_user_type='delvioo': Show username
                    if (otherUserType == 'business' &&
                        businessName.isNotEmpty) {
                      displayName = businessName;
                    } else if (username.isNotEmpty) {
                      displayName = '@$username';
                    } else if (firstName.isNotEmpty || lastName.isNotEmpty) {
                      displayName = '$firstName $lastName'.trim();
                    }
                  }

                  // Get role label based on other_user_type
                  final otherUserType =
                      order['other_user_type']?.toString() ?? '';
                  String roleLabel = '';
                  Color roleColor = (isLight ? Colors.black : Colors.white)
                      .withOpacity(0.5);
                  bool showBorder = true;
                  double borderRadius = 4;

                  if (otherUserType == 'business') {
                    roleLabel =
                        AppLocalizations.of(context)?.sellerLabel ?? 'Seller';
                    roleColor = const Color(0xFF007AFF); // Blue
                  } else if (otherUserType == 'delvioo') {
                    roleLabel =
                        AppLocalizations.of(context)?.driverLabel ?? 'Driver';
                    roleColor = Colors.green;
                  } else if (otherUserType == 'user') {
                    roleLabel =
                        AppLocalizations.of(context)?.buyerLabel ?? 'Buyer';
                    roleColor = (isLight ? Colors.black : Colors.white)
                        .withOpacity(0.5);
                    showBorder = false;
                    borderRadius = 25;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                      fontWeight: messageCount > 0
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isLight
                                          ? Colors.black
                                          : Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (roleLabel.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: roleColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                    ),
                                    child: Text(
                                      roleLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: roleColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (lastMessageTime != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatMessageTime(lastMessageTime),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: messageCount > 0
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                                color: messageCount > 0
                                    ? const Color(0xFF007AFF)
                                    : (isLight ? Colors.black : Colors.white)
                                          .withOpacity(0.4),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastMessage,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: messageCount > 0
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                                color: messageCount > 0
                                    ? (isLight
                                          ? Colors.black87
                                          : Colors.white70)
                                    : (isLight ? Colors.black : Colors.white)
                                          .withOpacity(0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (messageCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF),
                                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                boxShadow: [], // Kein Schatten
                              ),
                              child: Text(
                                '$messageCount',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupChatBottomSheet(
    BuildContext context,
    Map<String, dynamic> group,
    bool isLight,
  ) {
    print('🚀 Opening group chat for group: ${group['name']}');

    // Increment animation key to trigger fresh animations
    _groupChatAnimationKey++;

    // Hide app bar buttons when chat is open
    setState(() {
      _isChatOpen = true;
    });

    // Hide header
    _hideHeader();

    Navigator.of(context)
        .push(
          CupertinoPageRoute(
            builder: (ctx) => Scaffold(
              backgroundColor: isLight ? Colors.white : Colors.black,
              body: _buildIOSGroupChatModal(group, isLight, ctx),
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            setState(() {
              _isChatOpen = false;
            });
            _showHeader();
            _fetchOrders();
          }
        });
  }

  Widget _buildIOSGroupChatModal(
    Map<String, dynamic> group,
    bool isLight,
    BuildContext context,
  ) {
    final TextEditingController messageController = TextEditingController();
    final groupId = group['groupId'] ?? '';
    final groupName =
        group['name'] ??
        AppLocalizations.of(context)?.unnamedGroup ??
        'Unnamed Group';
    final chatId = groupId;
    int refreshKey = 0; // Key to force FutureBuilder refresh

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height,
            child: Column(
              children: [
                // Header - Trade Republic Style
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    MediaQuery.of(context).padding.top + 16,
                    20,
                    14,
                  ),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                  ),
                  child: Row(
                    children: [
                      // Back button
                      TradeRepublicButton.icon(
                        icon: Icon(
                          CupertinoIcons.back,
                          size: 20,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                        size: 36,
                        isSecondary: true,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isLight ? Colors.black : Colors.white,
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Icon(
                          CupertinoIcons.person_2,
                          color: isLight ? Colors.white : Colors.black,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              groupName,
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize() + 4,
                                fontWeight: FontWeight.w600,
                                color: isLight ? Colors.black : Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppLocalizations.of(context)?.groupChat ??
                                  'Group Chat',
                              style: TextStyle(
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // More options menu
                      TradeRepublicButton.icon(
                        icon: Icon(
                          CupertinoIcons.ellipsis,
                          size: 20,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                        size: 36,
                        isSecondary: true,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _showChatOptionsMenu(
                            context,
                            chatId,
                            groupName,
                            isLight,
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Messages Area
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey('group_messages_$refreshKey'),
                    future: _fetchGroupMessages(groupId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CultiooLoadingIndicator());
                      }

                      final messages = snapshot.data ?? [];

                      if (messages.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: isLight ? Colors.black : Colors.white,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Icon(
                                  CupertinoIcons.chat_bubble,
                                  size: 40,
                                  color: isLight ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
                              Text(
                                AppLocalizations.of(context)?.groupChat ??
                                    'Group Chat',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: isLight ? Colors.black : Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.startChattingWithGroup ??
                                    'Start chatting with your group members',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: DesktopAppWrapper.getPagePadding(),
                        reverse: true,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          final senderId =
                              message['sender_id']?.toString() ?? '';
                          final senderType =
                              message['sender_type']?.toString() ?? '';
                          final isMe =
                              senderType == 'delvioo' ||
                              senderId == currentUserId ||
                              senderId.toLowerCase() ==
                                  (_myUsername ?? '').toLowerCase();

                          return TweenAnimationBuilder<double>(
                            key: ValueKey(
                              'grp_msg_${_groupChatAnimationKey}_${message['id'] ?? index}',
                            ),
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(
                              milliseconds: 300 + (index * 50).clamp(0, 200),
                            ),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(
                                  isMe ? 30 * (1 - value) : -30 * (1 - value),
                                  0,
                                ),
                                child: Opacity(
                                  opacity: value,
                                  child: _buildGroupMessageBubble(
                                    message,
                                    isMe,
                                    isLight,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),

                // Input Section - Trade Republic Style
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(context).padding.bottom + 12,
                  ),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TradeRepublicTextField(
                          controller: messageController,
                          hintText:
                              AppLocalizations.of(context)?.message ??
                              'Message',
                          style: TextStyle(
                            color: isLight ? Colors.black : Colors.white,
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                          ),
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Send button - Group chat
                      TradeRepublicButton.icon(
                        icon: const Icon(CupertinoIcons.arrow_up, size: 18),
                        size: 40,
                        onPressed: () async {
                          final text = messageController.text.trim();
                          if (text.isNotEmpty) {
                            messageController.clear();
                            await _sendGroupMessage(groupId, text);
                            setModalState(() {
                              refreshKey++;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLiquidGlassBottomSheet(
    BuildContext context,
    int orderId,
    bool isLight,
  ) {
    print('🚀 Opening conversation for order $orderId');

    // Increment animation key to trigger fresh animations
    _orderChatAnimationKey++;

    // Mark messages as read when chat is opened
    _markMessagesAsRead(orderId);

    // Hide app bar buttons when chat is open
    setState(() {
      _isChatOpen = true;
    });

    // Hide header
    _hideHeader();

    Navigator.of(context)
        .push(
          CupertinoPageRoute(
            builder: (ctx) => Scaffold(
              backgroundColor: isLight ? Colors.white : Colors.black,
              body: _buildIOSChatModal(orderId, isLight, ctx),
            ),
          ),
        )
        .then((_) {
          if (mounted) {
            setState(() {
              _isChatOpen = false;
            });
            _showHeader();
            _fetchOrders();
          }
        });
  }

  Widget _buildIOSChatModal(int orderId, bool isLight, BuildContext context) {
    final TextEditingController messageController = TextEditingController();

    // Get customer name - for orderId=0, get from order data
    String customerName;
    if (orderId == 0) {
      try {
        final order = orders.firstWhere(
          (order) => order['order_id'] == null || order['order_id'] == 0,
        );
        customerName = order['customer_name'] ??
          order['other_username'] ??
          (AppLocalizations.of(context)?.userFallback ?? '');
      } catch (e) {
        customerName = 'User';
      }
    } else {
      customerName = _getCustomerNameForOrder(orderId);
    }

    final chatId = orderId == 0 ? 'direct_chat' : 'order_$orderId';

    // Get other user's ID and type for blocking functionality and profile loading
    String? otherUserId;
    String otherUserType = 'customer';
    try {
      final order = orders.firstWhere((order) {
        if (orderId == 0) {
          return order['order_id'] == null || order['order_id'] == 0;
        }
        return order['order_id'] == orderId;
      });
      otherUserId = order['other_username'];

      // For direct messages: get the OTHER user's type
      // If I'm the sender, use receiver_type; if I'm the receiver, use sender_type
      final sender = order['sender']?.toString() ?? '';
      final receiver = order['receiver']?.toString() ?? '';
      final senderType = order['sender_type']?.toString() ?? '';
      final receiverType = order['receiver_type']?.toString() ?? '';

      // Normalize 'delvioo' → 'driver' so _fetchProfileData hits the correct endpoint
      String normalizeUserType(String t) => t == 'delvioo' ? 'driver' : t;

      if (sender == currentUserId || sender == _myUsername) {
        // I'm the sender, so the other user is the receiver
        otherUserType = normalizeUserType(receiverType.isNotEmpty ? receiverType : 'customer');
      } else {
        // I'm the receiver, so the other user is the sender
        otherUserType = normalizeUserType(senderType.isNotEmpty ? senderType : 'customer');
      }

      print('🔍 Loaded chat for $otherUserId (type: $otherUserType)');
    } catch (e) {
      print('⚠️ Could not find other_username for order $orderId: $e');
    }

    List<Map<String, dynamic>> sharedOrders = [];
    bool showOrderSuggestions = false;
    int? selectedOrderId;
    int refreshKey = 0; // Key to force FutureBuilder refresh
    Future<List<Map<String, dynamic>>> messagesFuture =
        _fetchMessagesForConversation(orderId);

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height,
            child: Column(
              children: [
                // Header - Trade Republic Style
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    MediaQuery.of(context).padding.top + 16,
                    20,
                    14,
                  ),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                  ),
                  child: Row(
                    children: [
                      // Back button
                      TradeRepublicButton.icon(
                        icon: Icon(
                          CupertinoIcons.back,
                          size: 20,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                        size: 36,
                        isSecondary: true,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      // Avatar
                      FutureBuilder<Map<String, dynamic>?>(
                        future: otherUserId != null
                            ? _getProfileFuture(otherUserId, otherUserType)
                            : null,
                        builder: (context, snapshot) {
                          final profileData = snapshot.data;
                          final profilePictureRaw =
                              profileData?['profilePicture'];

                          // Use ApiConfig.getImageUrl to properly handle Google Cloud Storage URLs
                          String? profilePicture;
                          if (profilePictureRaw != null &&
                              profilePictureRaw.toString().isNotEmpty) {
                            profilePicture = ApiConfig.getImageUrl(
                              profilePictureRaw.toString(),
                            );
                          }

                          final userType =
                              profileData?['userType'] ??
                              AppLocalizations.of(context)?.businessLabel ??
                              'Business';
                          final firstName = profileData?['firstName'] ?? '';

                          return Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isLight ? Colors.black : Colors.white,
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            ),
                            child: _buildAvatarImage(profilePicture, 40, 20) ??
                                Center(
                                  child: Text(
                                    (firstName.isNotEmpty
                                            ? firstName[0]
                                            : customerName[0])
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: isLight
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: DesktopOptimizedWidgets.getFontSize(),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),

                      // Customer info
                      Expanded(
                        child: FutureBuilder<Map<String, dynamic>?>(
                          future: otherUserId != null
                              ? _getProfileFuture(otherUserId, otherUserType)
                              : null,
                          builder: (context, snapshot) {
                            String displayName = customerName;

                            // Load from profile data if available
                            if (snapshot.hasData && snapshot.data != null) {
                              final profile = snapshot.data!;
                              final businessName =
                                  profile['businessName'] ?? '';
                              final username = profile['username'] ?? '';
                              final firstName = profile['firstName'] ?? '';
                              final lastName = profile['lastName'] ?? '';

                              // Check sender_type to decide which name to show
                              // If sender_type='business': Show business name
                              // If sender_type='user': Show username (not business name!)
                              // If sender_type='delvioo': Show username
                              if (otherUserType == 'business' &&
                                  businessName.isNotEmpty) {
                                displayName = businessName;
                              } else if (username.isNotEmpty) {
                                displayName = '@$username';
                              } else if (firstName.isNotEmpty ||
                                  lastName.isNotEmpty) {
                                displayName = '$firstName $lastName'.trim();
                              }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        displayName,
                                        style: TextStyle(
                                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                                          fontWeight: FontWeight.w600,
                                          color: isLight
                                              ? Colors.black
                                              : Colors.white,
                                          letterSpacing: -0.3,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Role badge
                                    Builder(
                                      builder: (context) {
                                        String roleLabel;
                                        Color roleColor;

                                        if (otherUserType == 'business') {
                                          roleLabel =
                                              AppLocalizations.of(
                                                context,
                                              )?.sellerLabel ??
                                              'Seller';
                                          roleColor = const Color(0xFF007AFF);
                                        } else if (otherUserType == 'delvioo') {
                                          roleLabel =
                                              AppLocalizations.of(
                                                context,
                                              )?.driverLabel ??
                                              'Driver';
                                          roleColor = Colors.green;
                                        } else {
                                          roleLabel =
                                              AppLocalizations.of(
                                                context,
                                              )?.buyerLabel ??
                                              'Buyer';
                                          roleColor =
                                              (isLight
                                                      ? Colors.black
                                                      : Colors.white)
                                                  .withOpacity(0.5);
                                        }

                                        return Container(
                                          margin: const EdgeInsets.only(
                                            left: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: roleColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            roleLabel,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: roleColor,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  orderId == 0
                                      ? (AppLocalizations.of(
                                              context,
                                            )?.directMessage ??
                                            'Direct Message')
                                      : '${AppLocalizations.of(context)?.order ?? 'Order'} #$orderId',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.5),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      // Menu Button - macOS compatible
                      if (otherUserId != null && otherUserId.isNotEmpty)
                        TradeRepublicButton.icon(
                          icon: Icon(
                            CupertinoIcons.ellipsis,
                            size: 20,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                          size: 36,
                          isSecondary: true,
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _showChatOptionsBottomSheet(
                              isLight,
                              otherUserId!,
                              customerName,
                              chatId,
                            );
                          },
                        ),
                    ],
                  ),
                ),

                // Messages area - Telegram style
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey('messages_$refreshKey'),
                    future: messagesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CultiooLoadingIndicator());
                      }

                      final messages = snapshot.data ?? [];

                      if (messages.isEmpty) {
                        return Center(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutBack,
                            builder: (context, value, child) {
                              final clampedValue = value.clamp(0.0, 1.0);
                              return Transform.scale(
                                scale: clampedValue,
                                child: Opacity(
                                  opacity: clampedValue,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _PulsingIcon(
                                        icon: CupertinoIcons.chat_bubble,
                                        size: 56,
                                        color:
                                            (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.15),
                                      ),
                                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                                      Text(
                                        AppLocalizations.of(
                                              context,
                                            )?.noMessagesYet ??
                                            'No messages yet',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color:
                                              (isLight
                                                      ? Colors.black
                                                      : Colors.white)
                                                  .withOpacity(0.4),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        AppLocalizations.of(
                                              context,
                                            )?.startTheConversation ??
                                            'Start the conversation',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color:
                                              (isLight
                                                      ? Colors.black
                                                      : Colors.white)
                                                  .withOpacity(0.3),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: messages.length,
                        physics: const BouncingScrollPhysics(),
                        reverse: false,
                        itemBuilder: (context, index) {
                          final message = messages[index];

                          // Compare sender username with my username from SharedPreferences
                          final myUsername = _myUsername ?? currentUserId;
                          final messageSender =
                              message['sender']?.toString() ?? '';
                          final senderType =
                              message['sender_type']?.toString() ?? '';
                          final isMe =
                              senderType == 'delvioo' ||
                              messageSender.toLowerCase() ==
                                  myUsername.toLowerCase() ||
                              messageSender.toLowerCase() ==
                                  currentUserId.toLowerCase();

                          return _buildAnimatedMessageBubble(
                            message,
                            isMe,
                            isLight,
                            index,
                          );
                        },
                      );
                    },
                  ),
                ),

                // Input bar - Trade Republic Style
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(context).padding.bottom + 12,
                  ),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Order suggestions
                      if (showOrderSuggestions && sharedOrders.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          constraints: const BoxConstraints(maxHeight: 150),
                          decoration: BoxDecoration(
                            color: isLight ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: sharedOrders.length,
                            itemBuilder: (context, index) {
                              final order = sharedOrders[index];
                              final orderNum = order['order_id'];

                              return TradeRepublicTap(
                                onTap: () {
                                  String currentText = messageController.text;
                                  if (currentText.endsWith('#')) {
                                    messageController.text = currentText
                                        .substring(0, currentText.length - 1);
                                  }
                                  setModalState(() {
                                    selectedOrderId = orderNum;
                                    showOrderSuggestions = false;
                                  });
                                  HapticFeedback.lightImpact();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.tag,
                                        size: 18,
                                        color: const Color(0xFF007AFF),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${AppLocalizations.of(context)?.order ?? 'Order'} #$orderNum',
                                        style: TextStyle(
                                          fontSize: DesktopOptimizedWidgets.getFontSize(),
                                          fontWeight: FontWeight.w500,
                                          color: isLight
                                              ? Colors.black
                                              : Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      // Selected order badge
                      if (selectedOrderId != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.tag,
                                size: 14,
                                color: const Color(0xFF007AFF),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${AppLocalizations.of(context)?.orderNumber ?? "Order #"}$selectedOrderId',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF007AFF),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TradeRepublicButton.icon(
                                icon: const Icon(
                                  CupertinoIcons.xmark,
                                  size: 14,
                                  color: Color(0xFF007AFF),
                                ),
                                size: 26,
                                backgroundColor: const Color(
                                  0xFF007AFF,
                                ).withOpacity(0.1),
                                onPressed: () {
                                  setModalState(() {
                                    selectedOrderId = null;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                      // File preview (Image or PDF)
                      if (_chatSelectedFile != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isLight
                                ? Colors.black.withOpacity(0.05)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                          ),
                          child: Row(
                            children: [
                              // Preview thumbnail
                              if (_chatSelectedFileType == 'image')
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                  child: Image.file(
                                    _chatSelectedFile!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else if (_chatSelectedFileType == 'pdf')
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF007AFF,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.doc_fill,
                                    size: 32,
                                    color: const Color(0xFF007AFF),
                                  ),
                                ),
                              const SizedBox(width: 12),

                              // File info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _chatSelectedFileType == 'image'
                                          ? (AppLocalizations.of(
                                                  context,
                                                )?.imageLabel ??
                                                'Image')
                                          : (AppLocalizations.of(
                                                  context,
                                                )?.pdfDocument ??
                                                'PDF Document'),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isLight
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _chatSelectedFile!.path.split('/').last,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color:
                                            (isLight
                                                    ? Colors.black
                                                    : Colors.white)
                                                .withOpacity(0.5),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),

                              // Remove button
                              TradeRepublicButton.icon(
                                icon: const Icon(
                                  CupertinoIcons.xmark,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                size: 36,
                                backgroundColor: Colors.red.withOpacity(0.1),
                                onPressed: () {
                                  setModalState(() {
                                    _chatSelectedFile = null;
                                    _chatSelectedFileType = null;
                                  });
                                  HapticFeedback.lightImpact();
                                },
                              ),
                            ],
                          ),
                        ),

                      // Input row - matching business messenger style
                      Row(
                        children: [
                          // Attachment button
                          TradeRepublicButton.icon(
                            icon: const Icon(CupertinoIcons.plus, size: 20),
                            size: 40,
                            isSecondary: true,
                            onPressed: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              _showAttachmentOptions(
                                context,
                                orderId,
                                isLight,
                                (file, fileType) {
                                  setModalState(() {
                                    _chatSelectedFile = file;
                                    _chatSelectedFileType = fileType;
                                  });
                                },
                              );
                            },
                          ),
                          const SizedBox(width: 10),

                          // Input field
                          Expanded(
                            child: TradeRepublicTextField(
                              controller: messageController,
                              hintText:
                                  AppLocalizations.of(context)?.message ??
                                  'Message',
                              maxLines: null,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (text) async {
                                if (text.endsWith('#') &&
                                    !showOrderSuggestions) {
                                  try {
                                    final order = orders.firstWhere(
                                      (o) => o['order_id'] == orderId,
                                    );
                                    final otherUsername =
                                        order['other_username'] ?? '';

                                    if (otherUsername.isNotEmpty) {
                                      final fetchedOrders =
                                          await _getSharedOrders(otherUsername);
                                      setModalState(() {
                                        sharedOrders = fetchedOrders;
                                        showOrderSuggestions = true;
                                      });
                                    }
                                  } catch (e) {
                                    print('Error fetching shared orders: $e');
                                  }
                                } else if (!text.contains('#')) {
                                  setModalState(() {
                                    showOrderSuggestions = false;
                                  });
                                }
                              },
                            ),
                          ),

                          const SizedBox(width: 10),

                          // Send button
                          TradeRepublicButton.icon(
                            icon: const Icon(CupertinoIcons.arrow_up, size: 18),
                            size: 40,
                            onPressed: () async {
                              final hasText = messageController.text
                                  .trim()
                                  .isNotEmpty;
                              final hasFile = _chatSelectedFile != null;

                              if (hasText || hasFile) {
                                HapticFeedback.lightImpact();

                                // Send file if selected
                                if (hasFile &&
                                    _chatSelectedFile != null &&
                                    _chatSelectedFileType != null) {
                                  await _uploadFileToServer(
                                    _chatSelectedFile!,
                                    orderId,
                                    _chatSelectedFileType!,
                                  );
                                  await Future.delayed(
                                    const Duration(milliseconds: 500),
                                  );
                                }

                                // Send text message if present
                                if (hasText) {
                                  if (orderId == 0 && otherUserId != null) {
                                    await _sendDirectMessage(
                                      otherUserId,
                                      messageController.text.trim(),
                                      otherUserType,
                                    );
                                  } else {
                                    await _sendMessage(
                                      orderId,
                                      messageController.text.trim(),
                                      customOrderId: selectedOrderId,
                                    );
                                  }
                                  await Future.delayed(
                                    const Duration(milliseconds: 500),
                                  );
                                }

                                messageController.clear();
                                setModalState(() {
                                  selectedOrderId = null;
                                  showOrderSuggestions = false;
                                  _chatSelectedFile = null;
                                  _chatSelectedFileType = null;
                                  refreshKey++;
                                  messagesFuture =
                                      _fetchMessagesForConversation(orderId);
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method for block confirmation
  void _showBlockConfirmation(
    BuildContext context,
    String userId,
    String userName,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.nosign,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  '${AppLocalizations.of(context)?.blockUser ?? "Block"} $userName?',
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

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          Text(
            AppLocalizations.of(context)?.theyWontBeAbleToSend ??
                'They won\'t be able to send you messages anymore.',
            textAlign: TextAlign.start,
            style: TradeRepublicTheme.bodySmall(context),
          ),

          const SizedBox(height: 28),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.block ?? 'Block',
            onPressed: () {
              Navigator.pop(context);
              _blockUser(userId, userName);
            },
            backgroundColor: const Color(0xFFFF3B30),
            foregroundColor: Colors.white,
            width: double.infinity,
          ),

          const SizedBox(height: 10),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
            onPressed: () => Navigator.pop(context),
            isSecondary: true,
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  // Show chat options menu (Delete, etc.)
  void _showChatOptionsMenu(
    BuildContext context,
    String chatId,
    String chatName,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title: chatName,
            subtitle:
                AppLocalizations.of(context)?.chatOptions ?? 'Chat Options',
            leading: Icon(
              CupertinoIcons.chat_bubble_2,
              size: 20,
              color: TradeRepublicTheme.textColor(context),
            ),
          ),

          TradeRepublicCard(
            backgroundColor: isLight ? null : Colors.transparent,
            padding: EdgeInsets.zero,
            child: TradeRepublicListTile.destructive(
              title:
                  AppLocalizations.of(context)?.deleteChatLocal ??
                  'Delete Chat',
              subtitle:
                  AppLocalizations.of(context)?.removeConversation ??
                  'Remove this conversation',
              leading: const Icon(
                CupertinoIcons.trash,
                size: 20,
                color: Color(0xFFFF3B30),
              ),
              onTap: () async {
                Navigator.pop(context);
                HapticFeedback.mediumImpact();
                final confirmed = await _showDeleteConfirmation(
                  context,
                  isLight,
                );
                if (confirmed == true) {
                  await _deleteChat(chatId);
                  if (mounted) Navigator.of(context).pop();
                }
              },
            ),
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
            onPressed: () => Navigator.pop(context),
            isSecondary: true,
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  void _markMessagesAsRead(int orderId) {
    setState(() {
      // Find the order and set message_count to 0
      for (int i = 0; i < orders.length; i++) {
        if (orders[i]['order_id'] == orderId) {
          orders[i]['message_count'] = 0;
          break;
        }
      }
    });
    print('✅ Messages marked as read locally for order $orderId');

    // Also send to server to mark as read permanently
    _markMessagesAsReadOnServer(orderId);
  }

  Future<void> _markMessagesAsReadOnServer(int orderId) async {
    try {
      // Get current user's username
      final prefs = await SharedPreferences.getInstance();
      final myUsername = prefs.getString('username') ?? currentUserId;

      // For direct messages (orderId=0), use different endpoint
      if (orderId == 0) {
        // Find the other user from orders
        String? otherUsername;
        try {
          final order = orders.firstWhere(
            (o) => o['order_id'] == null || o['order_id'] == 0,
            orElse: () => {},
          );
          otherUsername = order['other_username'];
        } catch (e) {
          print('⚠️ Could not find other_username for direct messages');
          return;
        }

        if (otherUsername == null || otherUsername.isEmpty) {
          print('⏭️ No other_username found, skipping mark as read');
          return;
        }

        print('📤 Marking direct messages as read with $otherUsername');

        final String url =
            '${ApiConfig.baseUrl}/api/messages/direct/$myUsername/$otherUsername/mark-read';
        final response = await http
            .post(Uri.parse(url), headers: {'Content-Type': 'application/json'})
            .timeout(const Duration(seconds: 5));

        print(
          '📡 Mark direct messages as read response: ${response.statusCode}',
        );

        if (response.statusCode == 200) {
          print('✅ Direct messages marked as read on server');
        }
        return;
      }

      // For order-based messages
      print('📤 Marking messages as read on server for order $orderId');

      final String url =
          '${ApiConfig.baseUrl}/api/messages/orders/$orderId/mark-read';
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'reader': 'driver_system',
              'read_at': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      print('📡 Mark as read response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        if (responseBody['success'] == true) {
          print('✅ Messages marked as read on server');
        } else {
          print('⚠️ Server returned success: false');
        }
      } else {
        print('⚠️ Failed to mark as read on server: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error marking messages as read on server: $e');
      // Don't show error to user, local marking is sufficient
    }
  }

  // Helper method to get customer name from order
  String _getCustomerNameForOrder(int orderId) {
    try {
      final order = orders.firstWhere((order) => order['order_id'] == orderId);

      // Get the username directly from other_username
      final otherUsername = order['other_username'];
      if (otherUsername != null && otherUsername.isNotEmpty) {
        // Return the username directly (not the full name)
        return otherUsername;
      }

      // Final fallback
      return 'User';
    } catch (e) {
      return 'Customer';
    }
  }

  // Fetch messages for a specific conversation
  Future<List<Map<String, dynamic>>> _fetchMessagesForConversation(
    int orderId,
  ) async {
    try {
      print('📱 Fetching messages for order: $orderId');

      // First, try to get the other_username from the order data
      String? otherUsername;
      try {
        final order = orders.firstWhere((order) {
          // For orderId=0 (direct messages), match both null and 0
          if (orderId == 0) {
            return order['order_id'] == null || order['order_id'] == 0;
          }
          return order['order_id'] == orderId;
        });
        otherUsername = order['other_username'];
        print('📝 Found other_username: $otherUsername');
      } catch (e) {
        print('⚠️ Could not find other_username for order $orderId');
      }

      // Special case: If orderId is 0 and we have otherUsername, use direct messages API
      if (orderId == 0 && otherUsername != null && otherUsername.isNotEmpty) {
        print('📱 Order ID is 0 with username, fetching direct messages');
        final directMessages = await _fetchDirectMessages(otherUsername);
        print('📨 Fetched ${directMessages.length} direct messages');
        for (var msg in directMessages) {
          print(
            '   - Message ${msg['id']}: type=${msg['message_type']}, text=${msg['message_text']}, fileUrl=${msg['fileUrl']}',
          );
        }
        return directMessages;
      }

      // If we have other_username, fetch ALL messages with that user (including direct messages)
      if (otherUsername != null && otherUsername.isNotEmpty && orderId != 0) {
        print(
          '🔄 Fetching ALL messages with user: $otherUsername (including order $orderId)',
        );
        final response = await http.get(
          Uri.parse(
            '${ApiConfig.baseUrl}/api/messages/user/$currentUserId/$otherUsername?order_id=$orderId',
          ),
          headers: {'Content-Type': 'application/json'},
        );

        print('📡 User messages response: ${response.statusCode}');
        print('📡 User messages body: ${response.body}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            final messages = List<Map<String, dynamic>>.from(
              data['messages'] ?? [],
            );
            print(
              '✅ Loaded ${messages.length} total messages with $otherUsername (direct + order)',
            );
            return messages;
          }
        }
      }

      // Only try order-specific endpoint if orderId > 0
      if (orderId > 0) {
        print('⚠️ Falling back to order-specific messages');
        final response = await http.get(
          Uri.parse(
            '${ApiConfig.baseUrl}/api/messages/orders/$orderId/messages',
          ),
          headers: {'Content-Type': 'application/json'},
        );

        print('📡 Messages response: ${response.statusCode}');
        print('📡 Messages body: ${response.body}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            return List<Map<String, dynamic>>.from(data['messages'] ?? []);
          }
        }
      }
    } catch (e) {
      print('❌ Error fetching messages: $e');
    }

    // Return empty list if no messages found
    return [];
  }

  // Send message to customer
  Future<void> _sendMessage(
    int orderId,
    String messageText, {
    int? customOrderId,
  }) async {
    try {
      print('📨 Sending message to order: $orderId');
      print('📨 Message: $messageText');
      if (customOrderId != null) {
        print('📦 Custom order reference: $customOrderId');
      }

      // Get sender username from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final sender = prefs.getString('username') ?? currentUserId;

      print('📨 Sender: $sender');

      // For orderId = 0 (direct messages), use a default order ID or the first available order
      int actualOrderId = orderId;
      if (orderId == 0) {
        if (customOrderId != null) {
          actualOrderId = customOrderId;
        } else if (orders.isNotEmpty) {
          // Use the first available order ID
          actualOrderId = orders.first['order_id'] ?? 0;
        } else {
          // No order available — cannot send
          return;
        }
      }

      print('📦 Using order ID: $actualOrderId');

      final response = await http.post(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/messages/orders/$actualOrderId/messages',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'sender': sender,
          'receiver': orders.isNotEmpty
              ? (orders.firstWhere(
                  (o) => (o['order_id'] ?? o['id']) == actualOrderId,
                  orElse: () => orders.first,
                )['other_username'] ?? '')
              : '',
          'message_text': messageText,
          'message_type': 'text',
          'sender_type': 'delvioo',
          'receiver_type': 'business',
          'order_id': actualOrderId,
        }),
      );

      print('📡 Send message response: ${response.statusCode}');
      print('📡 Send message body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ Message sent successfully');
      } else {
        print('❌ Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error sending message: $e');
    }
  }

  // Get shared orders between current user and another user
  Future<List<Map<String, dynamic>>> _getSharedOrders(
    String otherUsername,
  ) async {
    try {
      print('🔍 Fetching shared orders with: $otherUsername');

      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/api/messages/shared-orders/$currentUserId/$otherUsername',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Shared orders response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final sharedOrders = List<Map<String, dynamic>>.from(
            data['orders'] ?? [],
          );
          print('✅ Found ${sharedOrders.length} shared orders');
          return sharedOrders;
        }
      }
    } catch (e) {
      print('❌ Error fetching shared orders: $e');
    }

    return [];
  }

  // Animated message bubble wrapper with slide and fade animation
  Widget _buildAnimatedMessageBubble(
    Map<String, dynamic> message,
    bool isMe,
    bool isLight,
    int index,
  ) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(
        'order_msg_${_orderChatAnimationKey}_${message['id'] ?? message['message_id'] ?? index}',
      ),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50).clamp(0, 200)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        // Clamp value to ensure it's within valid range
        final clampedValue = value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(
            isMe ? 30 * (1 - clampedValue) : -30 * (1 - clampedValue),
            0,
          ),
          child: Opacity(opacity: clampedValue, child: child),
        );
      },
      child: _buildMessageBubble(message, isMe, isLight),
    );
  }

  // Build message bubble for regular conversations - Telegram Style with Gradient
  Widget _buildMessageBubble(
    Map<String, dynamic> message,
    bool isMe,
    bool isLight,
  ) {
    final messageType = message['message_type'] ?? 'text';
    final orderId = message['order_id'];
    final hasOrderId = orderId != null && orderId != 0;
    final timestamp = message['created_at'] ?? message['timestamp'];

    // Format time
    String timeString = '';
    if (timestamp != null) {
      try {
        final dateTime = DateTime.parse(timestamp.toString());
        timeString =
            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        timeString = '';
      }
    }

    return Container(
      margin: EdgeInsets.only(
        bottom: 4,
        left: isMe ? 60 : 0,
        right: isMe ? 0 : 60,
      ),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Message Bubble - Minimalist Trade Republic Style
          Container(
            clipBehavior: Clip.antiAlias,
            padding: messageType == 'image'
                ? EdgeInsets.zero
                : (messageType == 'pdf'
                      ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                      : const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        )),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              color: isMe
                  ? (isLight ? Colors.black : Colors.white)
                  : Colors.transparent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order reference badge
                if (hasOrderId)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? (isLight
                                ? Colors.white.withOpacity(0.2)
                                : Colors.black.withOpacity(0.1))
                          : Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.tag,
                          size: 12,
                          color: isMe
                              ? (isLight ? Colors.white : Colors.black)
                              : isLight
                              ? Colors.black
                              : Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '#$orderId',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isMe
                                ? (isLight ? Colors.white : Colors.black)
                                : isLight
                                ? Colors.black
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Message content
                if (messageType == 'image')
                  _buildImageMessage(message, isMe, isLight)
                else if (messageType == 'pdf')
                  _buildPDFMessage(message, isMe, isLight)
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          message['message_text'] ?? '',
                          style: TextStyle(
                            fontSize: DesktopOptimizedWidgets.getFontSize(),
                            // High contrast text
                            color: isMe
                                ? (isLight ? Colors.white : Colors.black)
                                : (isLight ? Colors.black : Colors.white),
                            height: 1.3,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      if (timeString.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          timeString,
                          style: TextStyle(
                            fontSize: 10, // Minimalist small time
                            color: isMe
                                ? (isLight ? Colors.white : Colors.black)
                                      .withOpacity(0.5)
                                : (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// DB may store `/uploads/<file>` while the file is under `uploads/chat-attachments/`.
  String _normalizeLegacyChatFileUrl(String url) {
    var u = url;
    if (u.startsWith('/uploads/') &&
        !u.startsWith('/uploads/chat-attachments/') &&
        !u.startsWith('/uploads/chat-images/') &&
        !u.startsWith('/uploads/files/')) {
      final rest = u.substring('/uploads/'.length);
      if (rest.isNotEmpty && !rest.contains('/')) {
        u = '/uploads/chat-attachments/$rest';
      }
    }
    try {
      final uri = Uri.parse(u);
      final segs = uri.pathSegments;
      if (segs.length == 2 &&
          segs[0] == 'uploads' &&
          segs[1] != 'chat-attachments' &&
          segs[1] != 'chat-images' &&
          segs[1] != 'files') {
        return uri
            .replace(path: '/uploads/chat-attachments/${segs[1]}')
            .toString();
      }
    } catch (_) {
      /* ignore */
    }
    return u;
  }

  List<String> _chatImageUrlCandidates(String rawUrl) {
    final normalized = _normalizeLegacyChatFileUrl(rawUrl);
    final candidates = <String>[];

    String? chatAttachmentFileName;
    try {
      final uri = Uri.parse(normalized);
      if (uri.path.contains('/uploads/chat-attachments/')) {
        chatAttachmentFileName = uri.pathSegments.isNotEmpty
            ? uri.pathSegments.last
            : null;
      }
    } catch (_) {
      if (normalized.contains('/uploads/chat-attachments/')) {
        chatAttachmentFileName = normalized.split('/').last;
      }
    }

    // Prefer persistent object storage for chat attachments first.
    if (chatAttachmentFileName != null && chatAttachmentFileName.isNotEmpty) {
      candidates.add(
        'https://storage.googleapis.com/cultioo-uploads/chat-attachments/$chatAttachmentFileName',
      );
      candidates.add(
        'https://storage.googleapis.com/cultioo-business-uploads/chat-attachments/$chatAttachmentFileName',
      );
    }

    // Some environments expose uploads at /uploads/*, others at /backend/uploads/*.
    // Try both path styles explicitly before generic API candidates.
    try {
      final uri = Uri.parse(normalized);
      final path = uri.path;
      if (path.contains('/backend/uploads/')) {
        final nonBackendPath = path.replaceFirst('/backend/uploads/', '/uploads/');
        final nonBackendUrl = uri.replace(path: nonBackendPath).toString();
        candidates.add(nonBackendUrl);
      } else if (path.contains('/uploads/')) {
        final backendPath = path.replaceFirst('/uploads/', '/backend/uploads/');
        final backendUrl = uri.replace(path: backendPath).toString();
        candidates.add(backendUrl);
      }
    } catch (_) {
      // Ignore malformed URLs; generic fallback candidates below still apply.
    }

    candidates.addAll(ApiConfig.getImageUrlCandidates(normalized));

    final deduped = <String>[];
    final seen = <String>{};
    for (final url in candidates) {
      final clean = url.trim();
      if (clean.isEmpty || seen.contains(clean)) continue;
      seen.add(clean);
      deduped.add(clean);
    }
    return deduped;
  }

  // Build image message widget
  Widget _buildImageMessage(
    Map<String, dynamic> message,
    bool isMe,
    bool isLight,
  ) {
    // Extract URL from message data
    String? imageUrl;

    // Try different possible URL fields
    if (message['file_url'] != null &&
        message['file_url'].toString().isNotEmpty) {
      imageUrl = message['file_url'].toString();
      print('🖼️ Found file_url: $imageUrl');
    } else if (message['fileUrl'] != null &&
        message['fileUrl'].toString().isNotEmpty) {
      imageUrl = message['fileUrl'].toString();
      print('🖼️ Found fileUrl: $imageUrl');
    } else {
      // Parse from message text if URL is embedded
      final messageText = message['message_text'] ?? '';
      final urlMatch = RegExp(r'http[s]?://[^\s]+').firstMatch(messageText);
      imageUrl = urlMatch?.group(0);
      print('🖼️ Extracted URL from text: $imageUrl');
    }

    final imageCandidates = <String>[];

    // Clean and fix the URL
    if (imageUrl != null) {
      print('🔍 Original URL: $imageUrl');

      // Remove emoji and "Image:" prefix if present
      imageUrl = imageUrl.replaceAll(RegExp(r'📷\s*Image:\s*'), '');
      imageUrl = imageUrl.replaceAll(RegExp(r'🖼️\s*Image:\s*'), '');

      // Check if URL already starts with the correct Cloud Run base URL
      if (imageUrl.startsWith(ApiConfig.baseUrl)) {
        print('✅ URL already has correct base URL: $imageUrl');
      }
      // Replace old base URLs (localhost, old IPs) with current Cloud Run URL
      else if (imageUrl.contains('localhost') ||
          imageUrl.contains('127.0.0.1') ||
          imageUrl.contains('192.168.') ||
          imageUrl.contains('10.0.2.2') ||
          imageUrl.contains('95.111.237.12') ||
          imageUrl.contains('35.241.195.202')) {
        // Extract just the path part (everything after /uploads or /api)
        final uploadsMatch = RegExp(r'/uploads/.*').firstMatch(imageUrl);
        if (uploadsMatch != null) {
          final path = uploadsMatch.group(0);
          imageUrl = '${ApiConfig.baseUrl}$path';
          print('🔄 Replaced old URL with Cloud Run URL + path: $imageUrl');
        } else {
          // If no /uploads found, try to extract the path after the host
          final uri = Uri.tryParse(imageUrl);
          if (uri != null && uri.path.isNotEmpty) {
            imageUrl = '${ApiConfig.baseUrl}${uri.path}';
            print('🔄 Replaced old URL with Cloud Run URL: $imageUrl');
          }
        }
      }
      // If URL doesn't start with http at all, add base URL
      else if (!imageUrl.startsWith('http')) {
        imageUrl = '${ApiConfig.baseUrl}$imageUrl';
        print('🔗 Added base URL: $imageUrl');
      }

      final candidates = _chatImageUrlCandidates(imageUrl);
      if (candidates.isNotEmpty) {
        imageCandidates.addAll(candidates);
        imageUrl = candidates.first;
        print('🖼️ Image URL candidates: $candidates');
      } else {
        imageUrl = _normalizeLegacyChatFileUrl(imageUrl);
        imageCandidates.add(imageUrl);
      }
      print('✅ Final cleaned URL: $imageUrl');
    }

    Widget buildImageCandidate(int index) {
      final sourceList = imageCandidates.isNotEmpty ? imageCandidates : [imageUrl!];
      final candidateUrl = sourceList[index];

      return TradeRepublicTap(
        onTap: () => _showFullScreenImage(
          context,
          List<String>.from(sourceList),
          isLight,
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
          child: Image.network(
            candidateUrl,
            fit: BoxFit.cover,
            width: 240,
            height: 240,
            headers: const {
              'User-Agent': 'Mozilla/5.0',
              'Accept': 'image/*',
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                return child;
              }
              final progress = loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null;
              return Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  color: isLight
                      ? Colors.black.withOpacity(0.05)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CultiooLoadingIndicator(size: 24),
                      ),
                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                      Text(
                        progress != null
                            ? '${(progress * 100).toStringAsFixed(0)}%'
                            : AppLocalizations.of(context)?.loading ?? 'Loading...',
                        style: TextStyle(
                          color: isLight
                              ? Colors.black.withOpacity(0.5)
                              : Colors.white.withOpacity(0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              final hasNext = index + 1 < sourceList.length;
              if (hasNext) {
                final nextUrl = sourceList[index + 1];
                print('❌ Image load error on candidate $candidateUrl: $error');
                print('🔁 Trying next image candidate: $nextUrl');
                return buildImageCandidate(index + 1);
              }

              print('❌ Image load error: $error');
              print('🖼️ Failed URL: $candidateUrl');
              return Container(
                width: 240,
                height: 240,
                padding: DesktopAppWrapper.getPagePadding(),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.photo_on_rectangle,
                      size: 48,
                      color: Colors.red.withOpacity(0.7),
                    ),
                    const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    Text(
                      AppLocalizations.of(context)?.imageUnavailable ??
                          'Image unavailable',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: DesktopOptimizedWidgets.getFontSize(),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                    Text(
                      error.toString().contains('SocketException')
                          ? 'Network error'
                          : error.toString().contains('404')
                          ? 'Image not found'
                          : AppLocalizations.of(context)?.failedToLoad ??
                                'Failed to load',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageUrl != null)
          buildImageCandidate(0)
        else
          Container(
            padding: DesktopAppWrapper.getPagePadding(),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.photo_on_rectangle,
                  size: 24,
                  color: isMe
                      ? Colors.white
                      : (isLight ? Colors.black : Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.imageNotAvailable ??
                      'Image not available',
                  style: TextStyle(
                    color: isMe
                        ? Colors.white
                        : (isLight ? Colors.black : Colors.white),
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Build PDF message widget
  Widget _buildPDFMessage(
    Map<String, dynamic> message,
    bool isMe,
    bool isLight,
  ) {
    final fileName = message['file_name'] ?? 'Document.pdf';

    // Extract PDF URL from message
    String? pdfUrl;
    if (message['file_url'] != null &&
        message['file_url'].toString().isNotEmpty) {
      pdfUrl = message['file_url'].toString();
    } else if (message['fileUrl'] != null &&
        message['fileUrl'].toString().isNotEmpty) {
      pdfUrl = message['fileUrl'].toString();
    } else {
      // Parse from message text if URL is embedded
      final messageText = message['message_text'] ?? '';
      final urlMatch = RegExp(r'http[s]?://[^\s]+').firstMatch(messageText);
      pdfUrl = urlMatch?.group(0);
    }

    // Clean and fix the URL
    if (pdfUrl != null) {
      pdfUrl = pdfUrl.replaceAll(RegExp(r'📄\s*PDF:\s*'), '');
      if (pdfUrl.startsWith(ApiConfig.baseUrl)) {
        // URL is already correct
      } else if (pdfUrl.contains('localhost') ||
          pdfUrl.contains('192.168') ||
          pdfUrl.contains('10.0.2.2')) {
        final path = pdfUrl.split('/uploads/').last;
        pdfUrl = '${ApiConfig.baseUrl}/uploads/$path';
      } else if (!pdfUrl.startsWith('http')) {
        pdfUrl = '${ApiConfig.baseUrl}$pdfUrl';
      }
    }

    // Trade Republic style: Clean row, icon in circle, minimal text
    return TradeRepublicTap(
      onTap: pdfUrl != null ? () => _openPDF(pdfUrl!) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8), // Smaller icon container
            decoration: BoxDecoration(
              color: isMe
                  ? (isLight
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.1))
                  : Colors.black.withOpacity(0.2), // Subtle background
              shape: BoxShape.circle, // Circular icon background
            ),
            child: Icon(
              CupertinoIcons.doc_fill,
              color: isMe
                  ? (isLight ? Colors.white : Colors.black)
                  : (isLight ? Colors.black : Colors.white),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isMe
                        ? (isLight ? Colors.white : Colors.black)
                        : (isLight ? Colors.black : Colors.white),
                    fontSize: 15,
                    fontWeight: FontWeight.w500, // Medium weight
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context)?.tapToOpenPdf ??
                      'Tap to open PDF',
                  style: TextStyle(
                    color:
                        (isMe
                                ? (isLight ? Colors.white : Colors.black)
                                : (isLight ? Colors.black : Colors.white))
                            .withOpacity(0.6), // Subtle subtitle
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            CupertinoIcons.chevron_right,
            size: 14,
            color:
                (isMe
                        ? (isLight ? Colors.white : Colors.black)
                        : (isLight ? Colors.black : Colors.white))
                    .withOpacity(0.4),
          ),
        ],
      ),
    );
  }

  // Open PDF in browser or external viewer
  Future<void> _openPDF(String pdfUrl) async {
    try {
      print('📄 Opening PDF: $pdfUrl');

      final Uri url = Uri.parse(pdfUrl);

      // Try to launch the URL
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        HapticFeedback.lightImpact();
      } else {
        throw Exception('Could not launch URL');
      }
    } catch (e) {
      print('❌ Error opening PDF: $e');
      TopNotification.error(
        context,
        AppLocalizations.of(context)?.failedToOpenPdf ?? 'Failed to open PDF',
      );
    }
  }

  // Build text message widget
  Widget _buildTextMessage(
    Map<String, dynamic> message,
    bool isMe,
    bool isLight,
  ) {
    return Text(
      message['message_text'] ?? '',
      style: TextStyle(
        fontSize: DesktopOptimizedWidgets.getFontSize(),
        color: isMe
            ? (isLight ? Colors.white : Colors.black)
            : (isLight ? Colors.black : Colors.white),
      ),
    );
  }

  // Build message bubble for group conversations
  // Build message bubble for group conversations
  Widget _buildGroupMessageBubble(
    Map<String, dynamic> message,
    bool isMe,
    bool isLight,
  ) {
    final messageType = message['message_type'] ?? 'text';
    final senderId = message['sender_id'] ?? '';
    final senderType = message['sender_type'] ?? 'customer';
    final orderId = message['order_id'];
    final hasOrderId = orderId != null && orderId != 0;

    return FutureBuilder<Map<String, dynamic>?>(
      future: !isMe ? _getProfileFuture(senderId, senderType) : null,
      builder: (context, snapshot) {
        final profileData = snapshot.data;
        // Use ApiConfig.getImageUrl to properly handle Google Cloud Storage URLs
        final profilePictureRaw = profileData?['profilePicture'];
        final profilePicture = profilePictureRaw != null
            ? ApiConfig.getImageUrl(profilePictureRaw.toString())
            : null;
        final userType =
            profileData?['userType'] ??
            AppLocalizations.of(context)?.businessLabel ??
            'Business';
        final firstName = profileData?['firstName'] ?? '';
        final lastName = profileData?['lastName'] ?? '';

        // Build display name from profile data (NOT from message sender_name)
        final displayName = (firstName.isNotEmpty && lastName.isNotEmpty)
            ? '$firstName $lastName'
            : (firstName.isNotEmpty
                  ? firstName
                  : (message['sender_name'] ?? 'Member'));

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar for received messages with profile picture
              if (!isMe)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 12, bottom: 4),
                      decoration: BoxDecoration(
                        color: isLight ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                      ),
                      child: _buildAvatarImage(profilePicture, 40, 20) ??
                          Center(
                            child: Text(
                              displayName[0].toUpperCase(),
                              style: TextStyle(
                                color: isLight ? Colors.white : Colors.black,
                                fontSize: DesktopOptimizedWidgets.getFontSize(),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                    ),

                    // User type badge
                    Positioned(
                      bottom: 0,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isLight ? Colors.black : Colors.white,
                          borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              userType == 'Driver'
                                  ? CupertinoIcons.cube_box
                                  : CupertinoIcons.building_2_fill,
                              size: 8,
                              color: isLight ? Colors.white : Colors.black,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              userType == 'Driver' ? 'D' : 'B',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: isLight ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

              // Message Island
              Flexible(
                child: Column(
                  crossAxisAlignment: isMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    // Sender name (only for received messages)
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 4),
                        child: Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isLight
                                ? Colors.black.withOpacity(0.5)
                                : Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ),

                    // Message Bubble
                    Container(
                      padding: messageType == 'image' || messageType == 'pdf'
                          ? const EdgeInsets.all(8)
                          : const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                      decoration: isMe
                          ? BoxDecoration(
                              color: isLight ? Colors.black : Colors.white,
                              borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Order reference badge (inside the bubble, modern style)
                          if (hasOrderId)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.bag,
                                    size: 12,
                                    color: const Color(0xFF6C757D),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${AppLocalizations.of(context)?.orderNumber ?? "Order #"}$orderId',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF6C757D),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Message content
                          if (messageType == 'image')
                            _buildImageMessage(message, isMe, isLight)
                          else if (messageType == 'pdf')
                            _buildPDFMessage(message, isMe, isLight)
                          else
                            _buildTextMessage(message, isMe, isLight),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Show attachment options with iOS-style design
  void _showAttachmentOptions(
    BuildContext context,
    int orderId,
    bool isLight,
    Function(File file, String fileType) onFileSelected,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title:
                AppLocalizations.of(context)?.sendAttachment ??
                'Send Attachment',
            leading: Icon(
              CupertinoIcons.paperclip,
              size: 20,
              color: TradeRepublicTheme.textColor(context),
            ),
          ),

          TradeRepublicCard(
            backgroundColor: isLight ? null : Colors.transparent,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                TradeRepublicListTile.navigation(
                  title: AppLocalizations.of(context)?.photo ?? 'Photo',
                  subtitle:
                      AppLocalizations.of(context)?.takeOrUploadPhoto ??
                      'Take or upload a photo',
                  leading: Icon(
                    CupertinoIcons.camera,
                    size: 20,
                    color: TradeRepublicTheme.textColor(context),
                  ),
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    FocusManager.instance.primaryFocus?.unfocus();
                    final file = await _selectImage();
                    if (file != null) onFileSelected(file, 'image');
                  },
                ),
                const TradeRepublicDivider(),
                TradeRepublicListTile.navigation(
                  title: AppLocalizations.of(context)?.document ?? 'Document',
                  subtitle:
                      AppLocalizations.of(context)?.uploadPdfFile ??
                      'Upload a PDF file',
                  leading: Icon(
                    CupertinoIcons.doc,
                    size: 20,
                    color: TradeRepublicTheme.textColor(context),
                  ),
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    FocusManager.instance.primaryFocus?.unfocus();
                    final file = await _selectPDF();
                    if (file != null) onFileSelected(file, 'pdf');
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            isSecondary: true,
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  // Show settings bottom sheet (chat modal style) - Trade Republic Style
  void _showSettingsBottomSheet(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.75,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Sheet header: Icon left + Title ──
            Row(
              children: [
                Icon(
                  CupertinoIcons.settings,
                  size: 22,
                  color: isLight ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)?.settings ?? 'Settings',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: isLight ? Colors.black : Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)?.manageChatPreferences ??
                  'Manage your chat preferences',
              style: TextStyle(
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.5),
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
            // Tiles — no card wrapper, no extra background
            TradeRepublicListTile.navigation(
              title:
                  AppLocalizations.of(context)?.pinnedChats ?? 'Pinned Chats',
              subtitle:
                  '${_pinnedChats.length} ${AppLocalizations.of(context)?.pinned ?? 'pinned'}',
              leading: const Icon(
                CupertinoIcons.pin_fill,
                size: 18,
                color: Color(0xFFFF9500),
              ),
              onTap: () {
                Navigator.pop(context);
                _showPinnedUsersModal(isLight);
              },
            ),
            const TradeRepublicDivider(),
            TradeRepublicListTile.navigation(
              title:
                  AppLocalizations.of(context)?.blockedUsers ?? 'Blocked Users',
              subtitle:
                  '${_blockedUsers.length} ${AppLocalizations.of(context)?.blocked ?? 'blocked'}',
              leading: const Icon(
                CupertinoIcons.person_crop_circle_badge_minus,
                size: 18,
                color: Color(0xFFFF3B30),
              ),
              onTap: () {
                Navigator.pop(context);
                _showBlockedUsersModal(isLight);
              },
            ),
            const TradeRepublicDivider(),
            TradeRepublicListTile.navigation(
              title:
                  AppLocalizations.of(context)?.deletedChats ?? 'Deleted Chats',
              subtitle:
                  '${_deletedChats.length} ${AppLocalizations.of(context)?.deleted ?? 'deleted'}',
              leading: Icon(
                CupertinoIcons.trash,
                size: 18,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.6),
              ),
              onTap: () {
                Navigator.pop(context);
                _showDeletedChatsModal(isLight);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Show chat options bottom sheet (in chat modal)
  void _showChatOptionsBottomSheet(
    bool isLight,
    String userId,
    String userName,
    String chatId,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title: userName,
            subtitle:
                AppLocalizations.of(context)?.chatOptions ?? 'Chat Options',
            leading: Icon(
              CupertinoIcons.person_circle,
              size: 20,
              color: TradeRepublicTheme.textColor(context),
            ),
          ),

          TradeRepublicCard(
            backgroundColor: isLight ? null : Colors.transparent,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                TradeRepublicListTile.navigation(
                  title: _isUserBlocked(userId)
                      ? (AppLocalizations.of(context)?.unblock ??
                            'Unblock User')
                      : (AppLocalizations.of(context)?.blockUser ??
                            'Block User'),
                  subtitle: _isUserBlocked(userId)
                      ? 'Receive messages from $userName'
                      : 'Stop receiving messages from $userName',
                  leading: Icon(
                    _isUserBlocked(userId)
                        ? CupertinoIcons.checkmark_shield
                        : CupertinoIcons.nosign,
                    size: 20,
                    color: const Color(0xFF007AFF),
                  ),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    if (_isUserBlocked(userId)) {
                      _unblockUser(userId, userName);
                    } else {
                      _blockUser(userId, userName);
                    }
                  },
                ),
                const TradeRepublicDivider(),
                TradeRepublicListTile.destructive(
                  title:
                      AppLocalizations.of(context)?.deleteChat ?? 'Delete Chat',
                  subtitle:
                      AppLocalizations.of(context)?.removeConversation ??
                      'Remove this conversation',
                  leading: const Icon(
                    CupertinoIcons.trash,
                    size: 20,
                    color: Color(0xFFFF3B30),
                  ),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    _deleteChat(chatId);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            isSecondary: true,
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  // Show user management modal (pinned/blocked/deleted chats)
  void _showUserManagementModal(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TradeRepublicSectionHeader(
            title:
                AppLocalizations.of(context)?.userManagement ??
                'User Management',
            leading: Icon(
              CupertinoIcons.person_2,
              size: 20,
              color: TradeRepublicTheme.textColor(context),
            ),
          ),

          TradeRepublicCard(
            backgroundColor: isLight ? null : Colors.transparent,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                TradeRepublicListTile.navigation(
                  title:
                      AppLocalizations.of(context)?.pinnedChats ??
                      'Pinned Chats',
                  subtitle:
                      '${_pinnedChats.length} ${AppLocalizations.of(context)?.pinned ?? 'pinned'}',
                  leading: const Icon(
                    CupertinoIcons.pin_fill,
                    size: 20,
                    color: Color(0xFFFF9500),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showPinnedUsersModal(isLight);
                  },
                ),
                const TradeRepublicDivider(),
                TradeRepublicListTile.navigation(
                  title:
                      AppLocalizations.of(context)?.blockedUsers ??
                      'Blocked Users',
                  subtitle:
                      '${_blockedUsers.length} ${AppLocalizations.of(context)?.blocked ?? 'blocked'}',
                  leading: const Icon(
                    CupertinoIcons.nosign,
                    size: 20,
                    color: Color(0xFFFF3B30),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showBlockedUsersModal(isLight);
                  },
                ),
                const TradeRepublicDivider(),
                TradeRepublicListTile.navigation(
                  title:
                      AppLocalizations.of(context)?.deletedChats ??
                      'Deleted Chats',
                  subtitle:
                      '${_deletedChats.length} ${AppLocalizations.of(context)?.deleted ?? 'deleted'}',
                  leading: Icon(
                    CupertinoIcons.trash,
                    size: 20,
                    color: TradeRepublicTheme.textColor(context),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeletedChatsModal(isLight);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Show pinned users modal
  void _showPinnedUsersModal(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sheet header: Icon left + Title ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.pin,
                      size: 22,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.pinnedChats ??
                          'Pinned Chats',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_pinnedChats.length} ${AppLocalizations.of(context)?.pinned ?? 'pinned'}',
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _pinnedChats.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.pin,
                          size: 56,
                          color: TradeRepublicTheme.hintColor(context),
                        ),
                        const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          AppLocalizations.of(context)?.noPinnedChats ??
                              'No pinned chats',
                          style: TradeRepublicTheme.bodyMedium(context),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    itemCount: _pinnedChats.length,
                    itemBuilder: (context, index) {
                      final chatId = _pinnedChats.elementAt(index);
                      String chatName = chatId;

                      if (chatId.startsWith('order_')) {
                        final orderId = int.tryParse(
                          chatId.replaceFirst('order_', ''),
                        );
                        if (orderId != null) {
                          try {
                            final order = orders.firstWhere(
                              (o) => o['order_id'] == orderId,
                            );
                            chatName = order['customer_name'] ?? chatId;
                          } catch (_) {}
                        }
                      } else {
                        try {
                          final group = userGroups.firstWhere(
                            (g) => g['groupId'] == chatId,
                          );
                          chatName = group['name'] ?? chatId;
                        } catch (_) {}
                      }

                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index < _pinnedChats.length - 1 ? 0 : 0,
                        ),
                        child: TradeRepublicCard(
                          padding: EdgeInsets.zero,
                          backgroundColor: isLight
                              ? Colors.white
                              : Colors.transparent,
                          child: TradeRepublicListTile(
                            title: chatName,
                            leading: const Icon(
                              CupertinoIcons.pin_fill,
                              size: 18,
                              color: Color(0xFFFF9500),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Show blocked users modal
  void _showBlockedUsersModal(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Sheet header: Icon left + Title ──
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.nosign,
                        size: 22,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        AppLocalizations.of(context)?.blockedUsers ??
                            'Blocked Users',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_blockedUsers.length} ${AppLocalizations.of(context)?.blocked ?? 'blocked'}',
                    style: TextStyle(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _blockedUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_shield,
                            size: 56,
                            color: TradeRepublicTheme.hintColor(context),
                          ),
                          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          Text(
                            AppLocalizations.of(context)?.noBlockedUsers ??
                                'No blocked users',
                            style: TradeRepublicTheme.bodyMedium(context),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      child: TradeRepublicCard(
                        padding: EdgeInsets.zero,
                        backgroundColor: isLight
                            ? Colors.white
                            : Colors.transparent,
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _blockedUsers.length,
                          separatorBuilder: (_, __) =>
                              const TradeRepublicDivider(),
                          itemBuilder: (context, index) {
                            final userId = _blockedUsers.elementAt(index);
                            return TradeRepublicListTile(
                              title: userId,
                              leading: const Icon(
                                CupertinoIcons.nosign,
                                size: 18,
                                color: Color(0xFFFF3B30),
                              ),
                              trailing: TradeRepublicButton(
                                label:
                                    AppLocalizations.of(context)?.unblock ??
                                    'Unblock',
                                backgroundColor: const Color(0xFF34C759),
                                foregroundColor: Colors.white,
                                height: 34,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                onPressed: () async {
                                  HapticFeedback.mediumImpact();
                                  await _unblockUser(userId, userId);
                                  setModalState(() {});
                                  setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Show deleted chats modal
  // Show deleted chats modal
  void _showDeletedChatsModal(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: StatefulBuilder(
        builder: (context, setModalState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Sheet header: Icon left + Title ──
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.trash,
                        size: 22,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        AppLocalizations.of(context)?.deletedChats ??
                            'Deleted Chats',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isLight ? Colors.black : Colors.white,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_deletedChats.length} ${AppLocalizations.of(context)?.deleted ?? 'deleted'}',
                    style: TextStyle(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.5),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _deletedChats.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_circle,
                            size: 56,
                            color: TradeRepublicTheme.hintColor(context),
                          ),
                          const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                          Text(
                            AppLocalizations.of(context)?.noDeletedChats ??
                                'No deleted chats',
                            style: TradeRepublicTheme.bodyMedium(context),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      child: TradeRepublicCard(
                        padding: EdgeInsets.zero,
                        backgroundColor: isLight
                            ? Colors.white
                            : Colors.transparent,
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _deletedChats.length,
                          separatorBuilder: (_, __) =>
                              const TradeRepublicDivider(),
                          itemBuilder: (context, index) {
                            final chatId = _deletedChats.elementAt(index);
                            String chatName;
                            IconData chatIcon;
                            if (chatId.startsWith('order_')) {
                              final orderId = chatId.replaceFirst('order_', '');
                              chatName =
                                  '${AppLocalizations.of(context)?.orderNumber ?? "Order #"}$orderId';
                              chatIcon = CupertinoIcons.bag;
                            } else {
                              chatName = chatId;
                              chatIcon = CupertinoIcons.group;
                            }

                            return TradeRepublicListTile(
                              title: chatName,
                              leading: Icon(
                                chatIcon,
                                size: 18,
                                color: TradeRepublicTheme.iconColor(context),
                              ),
                              trailing: TradeRepublicButton(
                                label:
                                    AppLocalizations.of(context)?.restore ??
                                    'Restore',
                                backgroundColor: const Color(0xFF34C759),
                                foregroundColor: Colors.white,
                                height: 34,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                onPressed: () async {
                                  HapticFeedback.mediumImpact();
                                  setModalState(
                                    () => _deletedChats.remove(chatId),
                                  );
                                  await _saveDeletedChats();
                                  setState(() {});
                                  _fetchOrders();
                                  _loadUserGroups();
                                  TopNotification.success(
                                    context,
                                    AppLocalizations.of(
                                          context,
                                        )?.chatRestored ??
                                        'Chat restored',
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Show new chat modal to search and select users
  void _showNewChatModal(BuildContext context, bool isLight) {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;

    TradeRepublicBottomSheet.show(
      context: context,
      showDragHandle: true,
      child: StatefulBuilder(
        builder: (context, setState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final mq = MediaQuery.of(context);
              final desiredH = mq.size.height * 0.82;
              final maxH = constraints.maxHeight;
              final sheetH = maxH.isFinite
                  ? math.min(desiredH, maxH)
                  : desiredH;

              return Padding(
                padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
                child: SizedBox(
                  height: sheetH,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      TradeRepublicSectionHeader(
                        title: AppLocalizations.of(context)?.newChat ?? 'New Chat',
                        subtitle:
                            AppLocalizations.of(context)?.searchForUsers ??
                            'Search for users to start a conversation',
                        leading: Icon(
                          CupertinoIcons.plus_bubble,
                          size: 20,
                          color: TradeRepublicTheme.textColor(context),
                        ),
                      ),

                      // Search bar
                      TradeRepublicCard(
                        backgroundColor: isLight ? null : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.search,
                              size: 18,
                              color: TradeRepublicTheme.hintColor(context),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TradeRepublicTextField(
                                controller: searchController,
                                filled: false,
                                hintText:
                                    AppLocalizations.of(context)?.enterNameOrId ??
                                    'Enter name or ID...',
                                onChanged: (value) async {
                                  if (value.isEmpty) {
                                    setState(() {
                                      searchResults = [];
                                      isSearching = false;
                                    });
                                    return;
                                  }
                                  setState(() => isSearching = true);
                                  final results = await _searchUsers(value);
                                  setState(() {
                                    searchResults = results;
                                    isSearching = false;
                                  });
                                },
                              ),
                            ),
                            if (searchController.text.isNotEmpty)
                              TradeRepublicButton.icon(
                                icon: Icon(
                                  CupertinoIcons.xmark_circle_fill,
                                  size: 18,
                                  color: TradeRepublicTheme.hintColor(context),
                                ),
                                size: 28,
                                backgroundColor: Colors.transparent,
                                onPressed: () {
                                  searchController.clear();
                                  setState(() {
                                    searchResults = [];
                                    isSearching = false;
                                  });
                                },
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),

                      // Results
                      Expanded(
                        child: isSearching
                            ? Center(child: CultiooLoadingIndicator())
                            : searchResults.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      searchController.text.isEmpty
                                          ? CupertinoIcons.person_2
                                          : CupertinoIcons.search,
                                      size: 52,
                                      color: TradeRepublicTheme.hintColor(context),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      searchController.text.isEmpty
                                          ? (AppLocalizations.of(
                                                  context,
                                                )?.searchForUsers ??
                                                'Search for users')
                                          : (AppLocalizations.of(
                                                  context,
                                                )?.noUsersFound ??
                                                'No users found'),
                                      style: TradeRepublicTheme.titleSmall(context),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      searchController.text.isEmpty
                                          ? (AppLocalizations.of(
                                                  context,
                                                )?.enterNameOrId ??
                                                'Enter a name or ID to find users')
                                          : 'Try a different search term',
                                      style: TradeRepublicTheme.bodySmall(context),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  final user = searchResults[index];
                                  return _buildUserSearchResult(
                                    user,
                                    isLight,
                                    context,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Search for users by name or ID
  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    try {
      print('🔍 Searching for users: $query');

      // Search in both delvioo_users and users tables
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/search/all-users?q=$query'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Search response: ${response.statusCode}');
      print('📡 Search body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final users = List<Map<String, dynamic>>.from(data['users'] ?? []);
          print('✅ Found ${users.length} users');
          return users;
        }
      }
    } catch (e) {
      print('❌ Error searching users: $e');
    }
    return [];
  }

  // Build user search result card
  Widget _buildUserSearchResult(
    Map<String, dynamic> user,
    bool isLight,
    BuildContext context,
  ) {
    final userId = user['user_id'] ?? user['username'] ?? user['id'] ?? '';
    final username = user['username'] ?? userId;
    final businessName = user['business_name'] ?? user['businessName'] ?? '';
    final userType =
        user['user_type'] ?? 'user'; // 'delvioo', 'business', or 'user'

    // Determine display based on user_type from backend
    String displayName;
    String displaySubtitle;
    Color typeColor;
    IconData typeIcon;

    if (userType == 'business') {
      // Business user - show business name
      displayName = businessName.isNotEmpty
          ? businessName
          : (username.isNotEmpty
                ? '@$username'
                : AppLocalizations.of(context)?.sellerLabel ?? 'Seller');
      displaySubtitle = AppLocalizations.of(context)?.sellerLabel ?? 'Seller';
      typeColor = isLight ? Colors.black : Colors.white;
      typeIcon = CupertinoIcons.building_2_fill;
    } else if (userType == 'delvioo') {
      // Delvioo driver
      displayName = username.isNotEmpty
          ? '@$username'
          : AppLocalizations.of(context)?.driverLabel ?? 'Driver';
      displaySubtitle = AppLocalizations.of(context)?.driverLabel ?? 'Driver';
      typeColor = isLight ? Colors.black : Colors.white;
      typeIcon = CupertinoIcons.cube_box;
    } else {
      // Regular user (buyer) - NEVER show business name, always username!
      displayName = username.isNotEmpty
          ? '@$username'
          : AppLocalizations.of(context)?.buyerLabel ?? 'Buyer';
      displaySubtitle = AppLocalizations.of(context)?.buyerLabel ?? 'Buyer';
      typeColor = isLight ? Colors.black : Colors.white;
      typeIcon = CupertinoIcons.person;
    }

    final profilePic =
        user['profile_picture'] ??
        user['profilePicture'] ??
        user['profile_image'] ??
        user['profileImage'] ??
        user['businessLogo'] ??
        '';
    final resolvedProfilePic = ApiConfig.getImageUrl(profilePic.toString());

    Uint8List? profileBytes;
    if (resolvedProfilePic.startsWith('data:') &&
        resolvedProfilePic.contains(',')) {
      try {
        profileBytes = base64Decode(resolvedProfilePic.split(',').last);
      } catch (_) {
        profileBytes = null;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TradeRepublicCard(
        backgroundColor: isLight ? null : Colors.transparent,
        padding: EdgeInsets.zero,
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.pop(context);
          _startNewChat(userId, displayName, userType, isLight);
        },
        child: TradeRepublicListTile(
          title: displayName,
          subtitle: displaySubtitle,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: profilePic.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: profileBytes != null
                        ? Image.memory(
                            profileBytes,
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(typeIcon, color: typeColor, size: 22),
                          )
                        : Image.network(
                            resolvedProfilePic,
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(typeIcon, color: typeColor, size: 22),
                          ),
                  )
                : Icon(typeIcon, color: typeColor, size: 22),
          ),
          trailing: Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: TradeRepublicTheme.hintColor(context),
          ),
        ),
      ),
    );
  }

  // Start new chat with selected user
  void _startNewChat(
    String userId,
    String userName,
    String receiverType,
    bool isLight,
  ) {
    print(
      '💬 Starting new chat with: $userName ($userId) - type: $receiverType',
    );

    // Use the same chat modal design as for orders, but with direct messages
    final TextEditingController messageController = TextEditingController();

    // Store receiverType for message fetching
    final String chatUserType = receiverType;

    // Refresh key to reload messages after sending
    int refreshKey = 0;

    // Hide app bar buttons when chat is open
    setState(() {
      _isChatOpen = true;
    });

    // Hide header
    _hideHeader();

    // Build the chat widget
    Widget chatWidget = StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height,
            child: Column(
              children: [
                // Minimalist Header - Trade Republic Style
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    MediaQuery.of(context).padding.top + 16,
                    20,
                    14,
                  ),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                  ),
                  child: Row(
                    children: [
                      // Back button - Trade Republic Style
                      TradeRepublicButton.icon(
                        icon: Icon(
                          CupertinoIcons.back,
                          size: 20,
                          color: isLight ? Colors.black : Colors.white,
                        ),
                        size: 36,
                        isSecondary: true,
                        onPressed: () => Navigator.pop(context),
                      ),

                      const SizedBox(width: 16),

                      // Customer name with badge
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                userName,
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize() + 6,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                  color: isLight ? Colors.black : Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Role Badge
                            Builder(
                              builder: (context) {
                                String roleLabel = '';
                                Color roleColor =
                                    (isLight ? Colors.black : Colors.white)
                                        .withOpacity(0.5);
                                bool showBorder = true;
                                double borderRadius = 4;

                                if (receiverType == 'business') {
                                  roleLabel =
                                      AppLocalizations.of(
                                        context,
                                      )?.sellerLabel ??
                                      'Seller';
                                  roleColor = const Color(0xFF007AFF); // Blue
                                } else if (receiverType == 'delvioo') {
                                  roleLabel =
                                      AppLocalizations.of(
                                        context,
                                      )?.driverLabel ??
                                      'Driver';
                                  roleColor = Colors.green;
                                } else {
                                  roleLabel =
                                      AppLocalizations.of(
                                        context,
                                      )?.buyerLabel ??
                                      'Buyer';
                                  roleColor =
                                      (isLight ? Colors.black : Colors.white)
                                          .withOpacity(0.5);
                                  showBorder = false;
                                  borderRadius = 25;
                                }

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: roleColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                                  ),
                                  child: Text(
                                    roleLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: roleColor,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Messages Area
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey('direct_messages_$refreshKey'),
                    future: _fetchDirectMessages(
                      userId,
                      userType: chatUserType,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CultiooLoadingIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.chat_bubble,
                                size: 64,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.2),
                              ),
                              const SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                              Text(
                                AppLocalizations.of(context)?.noMessagesYet ??
                                    'No messages yet',
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  fontWeight: FontWeight.w600,
                                  color: isLight ? Colors.black : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(
                                      context,
                                    )?.startTheConversation ??
                                    'Start the conversation',
                                style: TextStyle(
                                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                                  color: (isLight ? Colors.black : Colors.white)
                                      .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final messages = snapshot.data!;

                      // Use the username loaded in initState
                      final myUsername = _myUsername ?? currentUserId;
                      print(
                        '🆔 Comparing messages with myUsername: $myUsername',
                      );

                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];

                          // Compare with sender field (username) - case insensitive
                          final msgSender = message['sender']?.toString() ?? '';
                          final msgSenderType =
                              message['sender_type']?.toString() ?? '';
                          final isMe =
                              msgSenderType == 'delvioo' ||
                              msgSender.toLowerCase() ==
                                  myUsername.toLowerCase() ||
                              msgSender.toLowerCase() ==
                                  currentUserId.toLowerCase();

                          return _buildMessageBubble(message, isMe, isLight);
                        },
                      );
                    },
                  ),
                ),

                // Input bar - Trade Republic Style
                Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(context).padding.bottom + 12,
                  ),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : Colors.black,
                  ),
                  child: Row(
                    children: [
                      // Input field
                      Expanded(
                        child: TradeRepublicTextField(
                          controller: messageController,
                          hintText:
                              AppLocalizations.of(context)?.message ??
                              'Message',
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),

                      const SizedBox(width: 10),

                      // Send button
                      TradeRepublicButton.icon(
                        icon: Icon(
                          CupertinoIcons.arrow_up,
                          size: 18,
                          color: isLight ? Colors.white : Colors.black,
                        ),
                        backgroundColor: isLight ? Colors.black : Colors.white,
                        size: 40,
                        onPressed: () async {
                          final message = messageController.text.trim();
                          if (message.isEmpty) return;

                          HapticFeedback.lightImpact();

                          await _sendDirectMessage(
                            userId,
                            message,
                            receiverType,
                          );

                          messageController.clear();
                          setModalState(() {
                            refreshKey++;
                          });

                          TopNotification.success(
                            context,
                            AppLocalizations.of(context)?.messageSent ??
                                'Message sent',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    Navigator.of(context)
        .push(
          CupertinoPageRoute(
            builder: (ctx) => Scaffold(
              backgroundColor: isLight ? Colors.white : Colors.black,
              body: chatWidget,
            ),
          ),
        )
        .then((_) {
          _showHeader();
          setState(() {
            _isChatOpen = false;
          });
          _fetchOrders();
        });
  }

  // Fetch direct messages with a user (with optional user_type filter)
  Future<List<Map<String, dynamic>>> _fetchDirectMessages(
    String userId, {
    String? userType,
  }) async {
    try {
      print('📱 Fetching direct messages with user: $userId');
      if (userType != null) {
        print('🔍 Filtering by user_type: $userType');
      }

      // Get current user's username
      final prefs = await SharedPreferences.getInstance();
      final myUserId = prefs.getString('username') ?? currentUserId;

      print('🔍 My username for fetching: $myUserId');

      // Build URL with optional user_type parameter
      String url = '${ApiConfig.baseUrl}/api/messages/direct/$myUserId/$userId';
      if (userType != null) {
        url += '?user_type=$userType';
        print('🔗 URL with filter: $url');
        print(
          '⚠️ If you see messages for the WRONG identity, the backend is not filtering correctly!',
        );
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Direct messages response: ${response.statusCode}');
      print('📡 Direct messages body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final allMessages = List<Map<String, dynamic>>.from(
            data['messages'] ?? [],
          );

          // NO FILTERING IN DIRECT MESSAGES
          // Direct messages should show ALL messages in the conversation
          // regardless of which identity sent them. The user can switch identities
          // and the conversation history should remain visible.

          print('💬 Direct messages loaded: ${allMessages.length} messages');
          return allMessages;
        }
      }
    } catch (e) {
      print('❌ Error fetching direct messages: $e');
    }
    return [];
  }

  // Send direct message to a user
  Future<void> _sendDirectMessage(
    String recipientId,
    String messageText,
    String receiverType,
  ) async {
    try {
      print('📨 Sending direct message to: $recipientId (type: $receiverType)');
      print('📨 Message: $messageText');

      // Get sender username from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final sender = prefs.getString('username') ?? currentUserId;

      print('📨 Sender username: $sender');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/messages/direct'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'sender': sender,
          'receiver': recipientId,
          'message_text': messageText,
          'message_type': 'text',
          'sender_type': 'delvioo', // Delvioo driver
          'receiver_type':
              receiverType, // Use the user_type from search results
        }),
      );

      print('📡 Send direct message response: ${response.statusCode}');
      print('📡 Send direct message body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ Direct message sent successfully');
      } else {
        print('❌ Failed to send direct message: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error sending direct message: $e');
    }
  }

  // Format message time - Trade Republic style
  String _formatMessageTime(dynamic timestamp) {
    try {
      DateTime messageTime;
      if (timestamp is String) {
        messageTime = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        messageTime = timestamp;
      } else {
        return '';
      }

      final now = DateTime.now();
      final difference = now.difference(messageTime);

      if (difference.inMinutes < 1) {
        return 'Now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d';
      } else {
        // Format as date
        return '${messageTime.day}.${messageTime.month}';
      }
    } catch (e) {
      return '';
    }
  }
}

// Pulsing Icon Animation for empty state
class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;

  const _PulsingIcon({
    required this.icon,
    required this.size,
    required this.color,
  });

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Icon(widget.icon, size: widget.size, color: widget.color),
        );
      },
    );
  }
}

// ============================================================================
// CullyAI CHAT PAGE
// ============================================================================
class _CullyAiChatPage extends StatefulWidget {
  final bool isLight;
  const _CullyAiChatPage({required this.isLight});

  @override
  State<_CullyAiChatPage> createState() => _CullyAiChatPageState();
}

class _CullyAiChatPageState extends State<_CullyAiChatPage>
    with TickerProviderStateMixin {
  static const _historyPrefsKey = 'cully_ai_chat_history';
  final List<Map<String, String>> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  int? _animatingIndex;
  final Set<int> _newBubbleIndices = {};
  String? _username;
  late AnimationController _pageEntranceCtrl;
  late Animation<double> _pageEntranceFade;
  late Animation<Offset> _pageEntranceSlide;

  @override
  void initState() {
    super.initState();
    _pageEntranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pageEntranceFade = CurvedAnimation(
      parent: _pageEntranceCtrl,
      curve: Curves.easeOut,
    );
    _pageEntranceSlide =
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
          CurvedAnimation(parent: _pageEntranceCtrl, curve: Curves.easeOut),
        );
    _pageEntranceCtrl.forward();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? '';
    // Load persisted chat history
    List<Map<String, String>> history = [];
    final historyJson = prefs.getString(_historyPrefsKey);
    if (historyJson != null) {
      try {
        final decoded = jsonDecode(historyJson) as List;
        history = decoded
            .map((m) => Map<String, String>.from(m as Map))
            .toList();
        if (history.length > 100) {
          history = history.sublist(history.length - 100);
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _username = username;
        if (history.isNotEmpty) _messages.addAll(history);
      });
      if (history.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _messages.length > 100
          ? _messages.sublist(_messages.length - 100)
          : List<Map<String, String>>.from(_messages);
      await prefs.setString(_historyPrefsKey, jsonEncode(toSave));
    } catch (_) {}
  }

  Future<void> _clearChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyPrefsKey);
    if (mounted) setState(() => _messages.clear());
  }

  Future<void> _confirmClearCullyMessages(bool isLight) async {
    final confirm =
        await TradeRepublicBottomSheet.show<bool>(
          context: context,
          showDragHandle: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.trash,
                    size: 22,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)?.clearChat ?? 'Clear Chat',
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
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
              Text(
                AppLocalizations.of(context)?.deleteCullyHistoryConfirm ??
                    'Delete all CullyAI conversation history? This cannot be undone.',
                style: TradeRepublicTheme.bodySmall(context),
              ),
              const SizedBox(height: 28),
              TradeRepublicButton(
                label: AppLocalizations.of(context)?.delete ?? 'Delete',
                onPressed: () => Navigator.pop(context, true),
                backgroundColor: const Color(0xFFFF3B30),
                foregroundColor: Colors.white,
                width: double.infinity,
              ),
              const SizedBox(height: 10),
              TradeRepublicButton(
                label: AppLocalizations.of(context)?.cancel ?? 'Cancel',
                onPressed: () => Navigator.pop(context, false),
                isSecondary: true,
                width: double.infinity,
              ),
              const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await _clearChatHistory();
      if (!mounted) return;
      TopNotification.success(
        context,
        AppLocalizations.of(context)?.chatDeleted ?? 'Chat deleted',
      );
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _pageEntranceCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLoading) return;
    HapticFeedback.lightImpact();

    setState(() {
      _newBubbleIndices.add(_messages.length);
      _messages.add({'role': 'user', 'text': text});
      _isLoading = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final username = _username ?? '';
      // Build history (exclude the just-added user message)
      final history = _messages.length > 1
          ? _messages
                .sublist(0, _messages.length - 1)
                .map((m) => {'role': m['role']!, 'text': m['text']!})
                .toList()
          : <Map<String, String>>[];

      final appSettings = Provider.of<AppSettings>(context, listen: false);
      final langCode = appSettings.selectedLanguage == 'System'
          ? Localizations.localeOf(context).languageCode
          : appSettings.selectedLanguage;

      // Use dynamic currency symbol for Cully responses
      final currencySymbol = appSettings.currencySymbol;

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/delvioo/cully-ai/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': text,
              'username': username,
              'history': history,
              'language': langCode,
              'currency': currencySymbol,
              'assistant_mode': 'driver',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['reply'] as String? ?? "Sorry, I couldn't respond.";
        setState(() {
          _newBubbleIndices.add(_messages.length);
          _messages.add({'role': 'model', 'text': reply});
          _isLoading = false;
          _animatingIndex = _messages.length - 1;
        });
        _saveChatHistory();
      } else {
        setState(() {
          _newBubbleIndices.add(_messages.length);
          _messages.add({
            'role': 'model',
            'text': 'Error ${response.statusCode}. Please try again.',
          });
          _isLoading = false;
          _animatingIndex = _messages.length - 1;
        });
        _saveChatHistory();
      }
    } catch (e) {
      setState(() {
        _newBubbleIndices.add(_messages.length);
        _messages.add({
          'role': 'model',
          'text': 'Network error. Please check your connection.',
        });
        _isLoading = false;
        _animatingIndex = _messages.length - 1;
      });
      _saveChatHistory();
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.isLight;
    final bg = isLight ? Colors.white : Colors.black;
    final cardBg = isLight ? Colors.white : const Color(0xFF0A0A0A);
    final textColor = isLight ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      body: FadeTransition(
        opacity: _pageEntranceFade,
        child: SlideTransition(
          position: _pageEntranceSlide,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(isLight, textColor),
                TradeRepublicDivider(color: textColor.withOpacity(0.06)),
                Expanded(
                  child: _messages.isEmpty
                      ? _buildWelcome(textColor)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: _messages.length + (_isLoading ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == _messages.length) {
                              return _buildTypingIndicator(cardBg);
                            }
                            final msg = _messages[i];
                            return _buildBubble(
                              msg['text']!,
                              msg['role'] == 'user',
                              cardBg,
                              textColor,
                              i,
                            );
                          },
                        ),
                ),
                _buildInputBar(isLight, cardBg, textColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isLight, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          TradeRepublicButton.icon(
            icon: Icon(CupertinoIcons.back, color: textColor, size: 20),
            size: 40,
            isSecondary: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
            child: Image.asset(
              isLight ? 'logo/cully_light.png' : 'logo/cully_dark.png',
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CullyAI',
                  style: TextStyle(
                    fontSize: DesktopOptimizedWidgets.getFontSize(),
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                Row(
                  children: [
                    const _PulsingDot(),
                    const SizedBox(width: 5),
                    Text(
                      AppLocalizations.of(context)?.online ?? 'Online',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF3ECFCF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_messages.isNotEmpty)
            TradeRepublicButton.icon(
              icon: Icon(
                CupertinoIcons.trash,
                color: textColor.withOpacity(0.5),
                size: 17,
              ),
              size: 36,
              isSecondary: true,
              onPressed: () => _confirmClearCullyMessages(isLight),
            ),
        ],
      ),
    );
  }

  Widget _buildWelcome(Color textColor) {
    return _AnimatedWelcome(textColor: textColor, isLight: widget.isLight);
  }

  Widget _buildBubble(
    String text,
    bool isUser,
    Color cardBg,
    Color textColor,
    int index,
  ) {
    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                )
              : null,
          color: isUser ? null : cardBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isUser
                ? const Radius.circular(18)
                : const Radius.circular(4),
            bottomRight: isUser
                ? const Radius.circular(4)
                : const Radius.circular(18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: (index == _animatingIndex && !isUser)
            ? _TypewriterText(
                text: text,
                style: TextStyle(fontSize: 15, color: textColor, height: 1.4),
                onDone: () {
                  if (mounted) setState(() => _animatingIndex = null);
                },
              )
            : Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: isUser ? Colors.white : textColor,
                  height: 1.4,
                ),
              ),
      ),
    );
    if (_newBubbleIndices.contains(index)) {
      return _AnimatedBubble(
        isUser: isUser,
        onDone: () {
          if (mounted) setState(() => _newBubbleIndices.remove(index));
        },
        child: bubble,
      );
    }
    return bubble;
  }

  Widget _buildTypingIndicator(Color cardBg) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => _AiDot(delay: i * 200)),
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isLight, Color cardBg, Color textColor) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(top: BorderSide(color: textColor.withOpacity(0.06))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TradeRepublicTextField(
              controller: _inputController,
              hintText:
                  AppLocalizations.of(context)?.messageCullyAi ??
                  'Message CullyAI…',
              maxLines: null,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(width: 10),
          TradeRepublicButton.icon(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    CupertinoIcons.arrow_up,
                    color: Colors.white,
                    size: 20,
                  ),
            size: 50,
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            onPressed: _isLoading ? null : _sendMessage,
          ),
        ],
      ),
    );
  }
}

// Typing indicator dot
class _AiDot extends StatefulWidget {
  final int delay;
  const _AiDot({required this.delay});

  @override
  State<_AiDot> createState() => _AiDotState();
}

class _AiDotState extends State<_AiDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF6C63FF).withOpacity(0.4 + 0.6 * _anim.value),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final VoidCallback? onDone;
  const _TypewriterText({required this.text, required this.style, this.onDone});

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  int _charCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 14), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _charCount++);
      if (_charCount >= widget.text.length) {
        t.cancel();
        widget.onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.text.substring(0, _charCount.clamp(0, widget.text.length)),
      style: widget.style,
    );
  }
}

// Animated welcome screen with staggered entrance
class _AnimatedWelcome extends StatefulWidget {
  final Color textColor;
  final bool isLight;
  const _AnimatedWelcome({required this.textColor, required this.isLight});

  @override
  State<_AnimatedWelcome> createState() => _AnimatedWelcomeState();
}

class _AnimatedWelcomeState extends State<_AnimatedWelcome>
    with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  late List<Animation<double>> _fades;
  late List<Animation<Offset>> _slides;

  @override
  void initState() {
    super.initState();
    _ctrls = [
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      ),
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      ),
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      ),
    ];
    _fades = _ctrls
        .map(
          (c) =>
              CurvedAnimation(parent: c, curve: Curves.easeOut)
                  as Animation<double>,
        )
        .toList();
    _slides = _ctrls
        .map(
          (c) => Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeOut)),
        )
        .toList();
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: 60 + i * 160), () {
        if (mounted) _ctrls[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _fades[0],
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.4, end: 1.0).animate(
                  CurvedAnimation(parent: _ctrls[0], curve: Curves.elasticOut),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: Image.asset(
                    widget.isLight
                        ? 'logo/cully_light.png'
                        : 'logo/cully_dark.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _fades[1],
              child: SlideTransition(
                position: _slides[1],
                child: Text(
                  AppLocalizations.of(context)?.hiImCullyAi ??
                      'Hi, I\'m CullyAI!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.textColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
            FadeTransition(
              opacity: _fades[2],
              child: SlideTransition(
                position: _slides[2],
                child: Text(
                  AppLocalizations.of(context)?.askMeAnythingDelvioo ??
                      'Ask me anything — orders, deliveries, or just chat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: widget.textColor.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Animated bubble slide-in
class _AnimatedBubble extends StatefulWidget {
  final Widget child;
  final bool isUser;
  final VoidCallback? onDone;
  const _AnimatedBubble({
    required this.child,
    required this.isUser,
    this.onDone,
  });

  @override
  State<_AnimatedBubble> createState() => _AnimatedBubbleState();
}

class _AnimatedBubbleState extends State<_AnimatedBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(widget.isUser ? 0.12 : -0.12, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward().then((_) => widget.onDone?.call());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// Pulsing online dot
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.7,
      end: 1.4,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF3ECFCF),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
