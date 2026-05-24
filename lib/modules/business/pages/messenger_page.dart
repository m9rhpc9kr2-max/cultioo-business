import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import '../../../shared/services/app_settings.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import '../../../config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/trade_republic_bottom_sheet.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_list_tile.dart';
import '../../../shared/widgets/trade_republic_divider.dart';
import '../../../shared/widgets/trade_republic_card.dart';
import '../../../shared/widgets/trade_republic_section_header.dart';
import '../../../shared/widgets/trade_republic_swipe_action.dart';
import 'chat_view_page.dart';
import '../../../shared/widgets/trade_republic_theme.dart';
import '../../../shared/widgets/top_notification.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';

class MessengerPage extends StatefulWidget {
  const MessengerPage({super.key});

  @override
  State<MessengerPage> createState() => _MessengerPageState();
}

class _MessengerPageState extends State<MessengerPage>
    with TickerProviderStateMixin {
  final AppSettings _appSettings = AppSettings();
  final ScrollController _scrollController = ScrollController();
  bool isLoading = true;
  bool _isInitialLoad = true;
  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> conversations = [];
  int totalMessages = 0;
  int unreadCount = 0;

  // Dynamic logged-in user - loaded from AppSettings
  String get currentUser =>
      _appSettings.userName ?? (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr(''));

  // Get all variations of the current user name for matching
  // This handles cases like "Arkadiy Tatarynskyy" matching "Arkadiy", "arkadiy1", etc.
  List<String> get currentUserVariations {
    final user = currentUser;
    final userLower = user.toLowerCase();

    // Extract first name (before space) for matching database entries
    final firstName = user.split(' ').first;
    final firstNameLower = firstName.toLowerCase();

    return [
      user, // "Arkadiy Tatarynskyy"
      '${user}1', // "Arkadiy Tatarynskyy1"
      userLower, // "arkadiy tatarynskyy"
      '${userLower}1', // "arkadiy tatarynskyy1"
      firstName, // "Arkadiy"
      '${firstName}1', // "Arkadiy1"
      firstNameLower, // "arkadiy"
      '${firstNameLower}1', // "arkadiy1"
    ];
  }

  // Check if a username matches the current user (flexible matching)
  bool _isCurrentUser(String username) {
    final usernameLower = username.toLowerCase();
    return currentUserVariations.any((v) => v.toLowerCase() == usernameLower);
  }

  // Modern Animation Controllers - Delvioo Style
  late AnimationController _headerAnimController;
  late AnimationController _contentAnimController;
  late Animation<double> _headerSlideAnim;
  late Animation<double> _headerFadeAnim;

  // Global file preview variables - persistent across chat sessions
  Map<String, XFile?>? _globalSelectedImage;
  Map<String, PlatformFile?>? _globalSelectedFile;
  Map<String, String?>? _globalPreviewType;
  String? _currentChatPerson;

  // Swipe functionality variables
  Set<String> _pinnedChats = <String>{};

  // Haptic feedback tracking for swipe gestures
  final Map<String, bool> _swipeHapticTriggered = {};

  // Track swipe progress for animations
  final Map<String, double> _swipeProgress = {};

  // Track if chat modal is open
  bool _isChatModalOpen = false;

  // Get unique conversations from messages, excluding delvioo messages
  List<Map<String, dynamic>> _getUniqueConversations() {
    Map<String, Map<String, dynamic>> conversationMap = {};

    for (var message in messages) {
      // Skip delvioo messages
      String sender = message['sender'] ?? AppLocalizations.of(context)!.tr('');
      String receiver = message['receiver'] ?? AppLocalizations.of(context)!.tr('');
      if (sender.toLowerCase().contains('delvioo') ||
          receiver.toLowerCase().contains('delvioo')) {
        continue;
      }

      // Determine the other person in the conversation
      // Use case-insensitive comparison and check for all user variations

      String otherPerson;
      String senderLower = sender.toLowerCase();
      String receiverLower = receiver.toLowerCase();

      // Check if sender is current user (any variation)
      bool senderIsCurrentUser = currentUserVariations.any(
        (v) => v.toLowerCase() == senderLower,
      );
      // Check if receiver is current user (any variation)
      bool receiverIsCurrentUser = currentUserVariations.any(
        (v) => v.toLowerCase() == receiverLower,
      );

      if (senderIsCurrentUser) {
        otherPerson = receiver;
      } else if (receiverIsCurrentUser) {
        otherPerson = sender;
      } else {
        // Neither sender nor receiver is the current user, skip this message
        continue;
      }

      // Skip system-to-system conversations
      if (otherPerson.toLowerCase().contains('system') &&
          sender.toLowerCase().contains('system')) {
        continue;
      }

      // Create conversation key based on participants
      // Normalize to lowercase to avoid duplicates
      String conversationKey;
      final normalizedOtherPerson = otherPerson.toLowerCase();
      if (message['order_id'] != null && message['order_id'] != 0) {
        // Order-based conversation (only if order_id is valid, not 0)
        conversationKey = 'order_${message['order_id']}_$normalizedOtherPerson';
      } else {
        // Personal conversation
        conversationKey = 'personal_$normalizedOtherPerson';
      }

      // Check if this conversation already exists
      if (!conversationMap.containsKey(conversationKey)) {
        // Determine user type from the message based on who the OTHER person is
        // Use sender_type if otherPerson is sender, receiver_type if otherPerson is receiver
        String userType = 'user'; // default

        if (sender == otherPerson) {
          // otherPerson sent this message, use sender_type
          userType = message['sender_type'] ?? AppLocalizations.of(context)!.tr('user');
          print(
            '🎯 Setting userType for $otherPerson from sender_type: $userType',
          );
        } else if (receiver == otherPerson) {
          // otherPerson received this message, use receiver_type
          userType = message['receiver_type'] ?? AppLocalizations.of(context)!.tr('user');
          print(
            '🎯 Setting userType for $otherPerson from receiver_type: $userType',
          );
        }

        conversationMap[conversationKey] = {
          'id': conversationKey,
          'otherPerson': otherPerson,
          'lastMessage': message['message'] ?? message['message_text'] ?? AppLocalizations.of(context)!.tr(''),
          'lastMessageTime': message['sentAt'] ?? AppLocalizations.of(context)!.tr(''),
          'unreadCount': 0,
          'messages': <Map<String, dynamic>>[],
          'order_id': message['order_id'],
          'message_count': 0,
          'userType': userType, // Add user type from message
        };
      } else {
        // Conversation exists, but update userType if we find more specific type info
        if (sender == otherPerson) {
          String messageType = message['sender_type'] ?? AppLocalizations.of(context)!.tr('user');
          // Update if we find a more specific type (delvioo > business > user)
          if (messageType == 'delvioo' ||
              (messageType == 'business' &&
                  conversationMap[conversationKey]!['userType'] == 'user')) {
            conversationMap[conversationKey]!['userType'] = messageType;
            print('🔄 Updated userType for $otherPerson to $messageType');
          }
        }
      }

      // Add message to conversation
      conversationMap[conversationKey]!['messages'].add(message);
      conversationMap[conversationKey]!['message_count'] =
          (conversationMap[conversationKey]!['messages'] as List).length;

      // Update last message if this one is newer
      String currentTime = conversationMap[conversationKey]!['lastMessageTime'];
      String messageTime = message['sentAt'] ?? AppLocalizations.of(context)!.tr('');
      try {
        if (messageTime.isNotEmpty &&
            (currentTime.isEmpty ||
                DateTime.parse(
                  messageTime,
                ).isAfter(DateTime.parse(currentTime)))) {
          conversationMap[conversationKey]!['lastMessage'] =
              message['message'] ?? message['message_text'] ?? AppLocalizations.of(context)!.tr('');
          conversationMap[conversationKey]!['lastMessageTime'] = messageTime;
        }
      } catch (e) {
        // Fallback if date parsing fails
        conversationMap[conversationKey]!['lastMessage'] =
            message['message'] ?? message['message_text'] ?? AppLocalizations.of(context)!.tr('');
        conversationMap[conversationKey]!['lastMessageTime'] = messageTime;
      }

      // Count unread messages
      bool isRead = message['isRead'] == true || message['isRead'] == 1;
      String messageReceiver = message['receiver'] ?? AppLocalizations.of(context)!.tr('');

      // Only count as unread if current user is the receiver and message is not read
      if (!isRead &&
          (messageReceiver == currentUser ||
              messageReceiver == '${currentUser}1')) {
        conversationMap[conversationKey]!['unreadCount']++;
      }
    }

    // Convert to list and sort by last message time
    List<Map<String, dynamic>> conversations = conversationMap.values.toList();
    conversations.sort((a, b) {
      // First sort by pinned status
      String aId = a['id'] ?? a['otherPerson'] ?? AppLocalizations.of(context)!.tr('');
      String bId = b['id'] ?? b['otherPerson'] ?? AppLocalizations.of(context)!.tr('');
      bool aIsPinned = _pinnedChats.contains(aId);
      bool bIsPinned = _pinnedChats.contains(bId);

      if (aIsPinned && !bIsPinned) return -1;
      if (!aIsPinned && bIsPinned) return 1;

      // Then sort by time within same pin status
      try {
        String aTime = a['lastMessageTime'] ?? AppLocalizations.of(context)!.tr('');
        String bTime = b['lastMessageTime'] ?? AppLocalizations.of(context)!.tr('');

        if (aTime.isEmpty && bTime.isEmpty) return 0;
        if (aTime.isEmpty) return 1;
        if (bTime.isEmpty) return -1;

        return DateTime.parse(bTime).compareTo(DateTime.parse(aTime));
      } catch (e) {
        return 0;
      }
    });

    return conversations;
  }

  @override
  void initState() {
    super.initState();

    // Initialize modern animation controllers
    _headerAnimController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _headerSlideAnim = Tween<double>(begin: -20, end: 0).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut),
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

    // Start content animation on next frame for proper stagger effect
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _contentAnimController.forward();
      }
    });

    _loadPinnedChats();
    _loadMessages();
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    _contentAnimController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Load pinned chats from local storage
  Future<void> _loadPinnedChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pinnedList = prefs.getStringList('pinned_chats') ?? [];
      setState(() {
        _pinnedChats = Set<String>.from(pinnedList);
      });
      print('📌 Loaded pinned chats: $_pinnedChats');
    } catch (e) {
      print('[ERROR] Error loading pinned chats: $e');
    }
  }

  // Save pinned chats to local storage
  Future<void> _savePinnedChats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pinned_chats', _pinnedChats.toList());
      print('💾 Saved pinned chats: $_pinnedChats');
    } catch (e) {
      print('[ERROR] Error saving pinned chats: $e');
    }
  }

  Future<String?> _getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('auth_token');

    return token;
  }

  // Save messages to local storage
  Future<void> _saveMessagesToLocal(List<Map<String, dynamic>> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = jsonEncode(messages);
      await prefs.setString('cached_messages', messagesJson);
      await prefs.setString(
        'messages_cache_time',
        DateTime.now().toIso8601String(),
      );
      print('💾 Messages saved to local storage: ${messages.length} messages');
    } catch (e) {
      print('❌ Error saving messages to local: $e');
    }
  }

  // Load messages from local storage
  Future<List<Map<String, dynamic>>> _loadMessagesFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = prefs.getString('cached_messages');
      if (messagesJson != null) {
        final List<dynamic> decoded = jsonDecode(messagesJson);
        final messages = decoded
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        print('📦 Loaded ${messages.length} messages from local storage');
        return messages;
      }
    } catch (e) {
      print('❌ Error loading messages from local: $e');
    }
    return [];
  }

  Future<void> _loadMessages() async {
    print('💬 Loading ALL messages from database...');
    if (mounted && _isInitialLoad) {
      setState(() {
        isLoading = true;
      });
    }

    // Load cached messages first for instant display
    final cachedMessages = await _loadMessagesFromLocal();
    if (cachedMessages.isNotEmpty && mounted) {
      setState(() {
        messages = cachedMessages;
        conversations = _getUniqueConversations();
        totalMessages = messages.length;
        unreadCount = messages.where((msg) {
          String receiver = msg['receiver'] ?? AppLocalizations.of(context)!.tr('');
          bool isRead = msg['isRead'] == true || msg['isRead'] == 1;
          return !isRead &&
              currentUserVariations.any(
                (v) => v.toLowerCase() == receiver.toLowerCase(),
              );
        }).length;
        isLoading = false;
      });
      print('⚡ Displayed ${cachedMessages.length} cached messages instantly');
    }

    try {
      final token = await _getStoredToken();

      // Load ALL messages from the main messages table
      final endpoint = '/api/messages/all';

      try {
        final response = await http
            .get(
              Uri.parse('${ApiConfig.baseUrl}$endpoint'),
              headers: {
                'Content-Type': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token',
              },
            )
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                throw TimeoutException(
                  'Loading messages is taking longer than expected. Please try again.',
                );
              },
            );

        print('💬 Trying endpoint: $endpoint - Status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final responseData = json.decode(response.body);

          if (responseData['success'] == true &&
              responseData['messages'] != null) {
            final rawMessages = List<Map<String, dynamic>>.from(
              responseData['messages'],
            );

            // Debug: Check if type field exists in messages
            final driverMessages = rawMessages
                .where((m) => m['type'] == 'delvioo')
                .toList();
            print('🔍 Found ${driverMessages.length} delvioo messages');
            if (driverMessages.isNotEmpty) {
              print(
                '🔍 First message type field: ${driverMessages.first['type']}',
              );
              print('🔍 Message keys: ${driverMessages.first.keys.toList()}');
            }

            // Filter out delvioo messages and convert to our format
            messages = rawMessages
                .where((msg) {
                  String sender = msg['sender']?.toString() ?? AppLocalizations.of(context)!.tr('');
                  String receiver = msg['receiver']?.toString() ?? AppLocalizations.of(context)!.tr('');
                  return !sender.toLowerCase().contains('delvioo') &&
                      !receiver.toLowerCase().contains('delvioo');
                })
                .map((msg) {
                  // Use the message as-is since it's already in the correct format from the database
                  return {
                    'id': msg['id'],
                    'sender': msg['sender'],
                    'receiver': msg['receiver'],
                    'message': msg['message'],
                    'message_text': msg['message'], // Add for consistency
                    'sentAt': msg['sentAt'],
                    'isRead': msg['isRead'] ?? false,
                    'message_type': msg['message_type'] ?? AppLocalizations.of(context)!.tr('text'),
                    'type':
                        msg['type'] ?? AppLocalizations.of(context)!.tr('user'), // Use actual type from database
                    'sender_type':
                        msg['sender_type'] ?? AppLocalizations.of(context)!.tr('user'), // Extract sender_type from API
                    'receiver_type':
                        msg['receiver_type'] ?? AppLocalizations.of(context)!.tr('user'), // Extract receiver_type from API
                    'order_id': msg['order_id'],
                    'fileUrl': msg['fileUrl'],
                    'file_url': msg['fileUrl'], // Backward compatibility
                    'file_name': msg['file_name'],
                    'file_type': msg['file_type'],
                    'file_size': msg['file_size'],
                    'file_mimetype': msg['file_mimetype'],
                  };
                })
                .toList();

            print(
              '[SUCCESS] Messages loaded: ${messages.length} messages (delvioo messages filtered out)',
            );

            // Save messages to local storage for offline access
            await _saveMessagesToLocal(messages);
          }
        } else {
          print('[ERROR] Failed to load messages: ${response.statusCode}');
          print('Response: ${response.body}');
        }
      } catch (e) {
        print('[ERROR] Error loading messages: $e');
      }

      // Calculate statistics - exclude delvioo messages and count only relevant unread messages
      totalMessages = messages.length;

      // Count unread messages only where current user is the receiver
      unreadCount = messages.where((msg) {
        String receiver = msg['receiver'] ?? AppLocalizations.of(context)!.tr('');
        bool isRead = msg['isRead'] == true || msg['isRead'] == 1;

        // Only count unread messages where current user is the receiver (using getter)
        return !isRead &&
            currentUserVariations.any(
              (v) => v.toLowerCase() == receiver.toLowerCase(),
            );
      }).length;

      // Rebuild conversations list with updated messages
      conversations = _getUniqueConversations();

      if (mounted) {
        setState(() {
          isLoading = false;
          _isInitialLoad = false;
        });
      }

      print(
        '✅ Messages loaded successfully: $totalMessages total, $unreadCount unread for $currentUser',
      );
      print('Current user variations: $currentUserVariations');
      print('Conversations: ${conversations.length}');
    } catch (e) {
      print('❌ Error loading messages: $e');
      if (mounted) {
        setState(() {
          messages = [];
          conversations = [];
          totalMessages = 0;
          unreadCount = 0;
          isLoading = false;
          _isInitialLoad = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = _appSettings.isLightMode(context);

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
                      CultiooSliverRefreshControl(onRefresh: _loadMessages),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          isDesktop
                              ? 32.0
                              : MediaQuery.of(context).padding.top + 20.0,
                          horizontalPadding,
                          MediaQuery.of(context).padding.bottom + 120.0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header - same style as Orders
                              _buildAnimatedSection(
                                delay: 0,
                                slideFromBottom: false,
                                child: _buildTradeRepublicHeader(
                                  isLight,
                                  isDesktop: isDesktop,
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Conversations list — CullyAI always at top
                              _buildAnimatedSection(
                                delay: 1,
                                slideFromBottom: true,
                                child: _buildConversationsList(isLight),
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

  Widget _buildTradeRepublicHeader(bool isLight, {bool isDesktop = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: _headerAnimController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _headerSlideAnim.value),
                child: Opacity(opacity: _headerFadeAnim.value, child: child),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.messages ?? AppLocalizations.of(context)!.tr('Messages'),
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                    fontSize: isDesktop ? 40 : 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_getUniqueConversations().length} Conversations',
                  style: TextStyle(
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.5,
                    ),
                    fontSize: isDesktop ? 16 : 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (unreadCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isLight ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$unreadCount',
              style: TextStyle(
                color: isLight ? Colors.white : Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        if (!_isChatModalOpen) ...[
          TradeRepublicButton.icon(
            icon: Icon(
              CupertinoIcons.person_crop_circle_badge_minus,
              size: isDesktop ? 20 : 22,
              color: isLight ? Colors.black : Colors.white,
            ),
            size: isDesktop ? 40 : 44,
            backgroundColor: (isLight ? Colors.black : Colors.white)
                .withOpacity(0.05),
            foregroundColor: isLight ? Colors.black : Colors.white,
            onPressed: () {
              HapticFeedback.lightImpact();
              _showBlockedUsersBottomSheet(isLight);
            },
          ),
          const SizedBox(width: 8),
          TradeRepublicButton.icon(
            icon: Icon(
              CupertinoIcons.slider_horizontal_3,
              size: isDesktop ? 20 : 22,
              color: isLight ? Colors.black : Colors.white,
            ),
            size: isDesktop ? 40 : 44,
            backgroundColor: (isLight ? Colors.black : Colors.white)
                .withOpacity(0.05),
            foregroundColor: isLight ? Colors.black : Colors.white,
            onPressed: () => _showMessengerSettingsBottomSheet(isLight),
          ),
        ],
      ],
    );
  }

  Widget _buildConversationsList(bool isLight) {
    final uniqueConversations = _getUniqueConversations();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CullyAI — always pinned at top
        _buildCullyAiCard(isLight),
        const SizedBox(height: 8),
        ...uniqueConversations.asMap().entries.map((entry) {
          final index = entry.key + 1;
          final conversation = entry.value;
          return _buildAnimatedSection(
            delay: index,
            child: _buildConversationCard(conversation, isLight),
          );
        }),
        const SizedBox(height: 20),
      ],
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

  Widget _buildMessagesSummary(bool isLight) {
    // Get unique conversations count and calculate total visible messages
    final conversations = _getUniqueConversations();
    int conversationsCount = conversations.length;

    // Count only messages that are part of visible conversations
    int visibleMessagesCount = 0;
    for (var conversation in conversations) {
      final conversationMessages = List<Map<String, dynamic>>.from(
        conversation['messages'] ?? [],
      );
      visibleMessagesCount += conversationMessages.length;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trade Republic Style - Simple conversation count
          Text(
            '$conversationsCount CONVERSATIONS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isLight ? Colors.black : Colors.white,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isLight) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.chat_bubble,
              size: 48,
              color: isLight
                  ? Colors.black.withOpacity(0.3)
                  : Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)?.noMessages ?? AppLocalizations.of(context)!.tr('No Messages'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isLight ? Colors.black : Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)?.yourConversationsWillAppearHere ?? AppLocalizations.of(context)!.tr('Your conversations will appear here'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isLight
                    ? Colors.black.withOpacity(0.5)
                    : Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(bool isLight) {
    // Get unique conversations
    List<Map<String, dynamic>> conversations = _getUniqueConversations();

    // Always show CullyAI at the top
    final List<Widget> items = [
      _buildAnimatedSection(delay: 0, child: _buildCullyAiCard(isLight)),
      ...conversations.asMap().entries.map((entry) {
        return _buildAnimatedSection(
          delay: entry.key + 1,
          child: _buildConversationCard(entry.value, isLight),
        );
      }),
    ];

    if (conversations.isEmpty) {
      return Column(
        children: [
          _buildAnimatedSection(delay: 0, child: _buildCullyAiCard(isLight)),
        ],
      );
    }

    return Column(children: items);
  }

  Widget _buildCullyAiCard(bool isLight) {
    return TradeRepublicTap(
      onTap: () {
        HapticFeedback.lightImpact();
        _openCullyAiChat(isLight);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isLight ? Colors.transparent : const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // CullyAI Avatar
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                isLight ? 'logo/cully_light.png' : 'logo/cully_dark.png',
                width: 56,
                height: 56,
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
                          fontSize: 16,
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
                          color: isLight ? Colors.black : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: isLight ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your intelligent assistant — tap to chat',
                    style: TextStyle(
                      fontSize: 14,
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
      _isChatModalOpen = true;
    });
    Navigator.of(context)
        .push(
          CupertinoPageRoute(
            builder: (context) => _CullyAiChatPage(isLight: isLight),
          ),
        )
        .then(
          (_) => setState(() {
            _isChatModalOpen = false;
          }),
        );
  }

  Widget _buildConversationCard(
    Map<String, dynamic> conversation,
    bool isLight,
  ) {
    final otherPerson =
      conversation['otherPerson'] ?? (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr(''));
    final lastMessage = conversation['lastMessage'] ?? AppLocalizations.of(context)!.tr('');
    final lastMessageTime = conversation['lastMessageTime'] ?? AppLocalizations.of(context)!.tr('');
    final unreadCount = conversation['unreadCount'] ?? 0;
    final messages = List<Map<String, dynamic>>.from(
      conversation['messages'] ?? [],
    );
    final hasUnread = unreadCount > 0;
    final conversationId = conversation['id'] ?? otherPerson;
    final isPinned = _pinnedChats.contains(conversationId);
    final userType =
        conversation['userType'] as String?; // Get user type from conversation

    // Always check user type to load profile picture
    if (!_userTypeCache.containsKey(otherPerson)) {
      _checkUserType(otherPerson);
    }

    return TradeRepublicSwipeAction(
      key: ValueKey(conversationId),
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
          final confirmed =
              await _showDeleteChatConfirmation(otherPerson, isLight);
          if (confirmed) {
            _deleteChatWithUser(otherPerson);
          }
        },
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        _openChatView(otherPerson, messages, isLight);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isLight
              ? Colors.transparent
              : const Color.fromARGB(255, 0, 0, 0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Avatar - Modern Circle Stylse
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: (isLight ? Colors.black : Colors.white).withOpacity(
                  0.06,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: _buildConversationProfileImage(
                  otherPerson,
                  userType: userType,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                otherPerson,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isLight ? Colors.black : Colors.white,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isPinned)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color:
                                        (isLight ? Colors.black : Colors.white)
                                            .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.pin_fill,
                                    color: isLight
                                        ? Colors.black
                                        : Colors.white,
                                    size: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        _formatTime(lastMessageTime),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: (isLight ? Colors.black : Colors.white)
                                .withOpacity(hasUnread ? 0.9 : 0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          margin: const EdgeInsets.only(left: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isLight ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Chevron indicator
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: (isLight ? Colors.black : Colors.white).withOpacity(0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      } else {
        return 'now';
      }
    } catch (e) {
      return '';
    }
  }

  /// Sends a chat message to [otherPerson] using the same backend logic as the
  /// inline modal-based chat. Used by the standalone [ChatViewPage].
  Future<void> _sendDirectMessage(
    String otherPerson,
    dynamic orderId,
    String text,
  ) async {
    if (text.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final senderUsername = prefs.getString('username') ??
          prefs.getString('business_username') ??
          prefs.getString('user_name') ??
          '';
      final token = await _getStoredToken();
      final isOrderConversation =
          orderId != null && orderId != 0 && orderId.toString() != '0';
      final endpoint = isOrderConversation
          ? '${ApiConfig.baseUrl}/api/messages/orders/$orderId/messages'
          : '${ApiConfig.baseUrl}/api/messages/send';
      await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: json.encode(
              isOrderConversation
                  ? {
                      'message_text': text,
                      'sender': senderUsername,
                      'receiver': otherPerson,
                      'type': 'user',
                      'message_type': 'text',
                      'order_id': orderId,
                    }
                  : {
                      'sender_id': senderUsername,
                      'sender_type': 'business',
                      'recipient_type': 'driver',
                      'receiver_id': otherPerson,
                      'order_id': 0,
                      'message': text,
                    },
            ),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      print('❌ Error sending direct message: $e');
    }
  }

  void _openChatView(
    String otherPerson,
    List<Map<String, dynamic>> messages,
    bool isLight,
  ) {
    // Get order_id from the first message to load complete chat history
    final orderId = messages.isNotEmpty ? messages.first['order_id'] : null;

    // Set current chat person for file attachment tracking
    _currentChatPerson = otherPerson;

    // Hide CNPopupMenuButton when chat modal opens
    setState(() {
      _isChatModalOpen = true;
    });

    Navigator.of(context)
        .push(
          CupertinoPageRoute(
            builder: (context) => ChatViewPage(
              otherPerson: otherPerson,
              messages: messages,
              orderId: orderId is int
                  ? orderId
                  : int.tryParse('${orderId ?? ''}'),
              onSendMessage: (text) =>
                  _sendDirectMessage(otherPerson, orderId, text),
            ),
          ),
        )
        .then((_) {
          // Show CNPopupMenuButton again when chat modal closes
          setState(() {
            _isChatModalOpen = false;
          });
          // Reload messages when returning from chat to update unread counts
          print(
            '🔄 Reloading messages after chat closed to update unread counts',
          );
          _loadMessages();
        });
  }

  Widget _buildChatBottomSheet(
    String otherPerson,
    List<Map<String, dynamic>> initialMessages,
    int? orderId,
    bool isLight,
  ) {
    // Create controllers outside of builder to persist
    final TextEditingController messageController = TextEditingController();
    final FocusNode messageFocusNode = FocusNode();

    return StatefulBuilder(
      builder: (context, setModalState) {
        List<Map<String, dynamic>> chatMessages = List.from(initialMessages);
        bool isLoadingMessages = false;
        bool isMounted = true; // Track modal mount state

        // Determine receiver type from messages
        String receiverType = 'business'; // Default
        try {
          // Find messages where otherPerson is sender or receiver
          final conversationMessages = messages.where((msg) {
            final sender = msg['sender']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');
            final receiver = msg['receiver']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');
            final other = otherPerson.toLowerCase();
            return sender == other || receiver == other;
          }).toList();

          if (conversationMessages.isNotEmpty) {
            final msg = conversationMessages.first;
            final sender = msg['sender']?.toString().toLowerCase() ?? AppLocalizations.of(context)!.tr('');
            final senderType = msg['sender_type']?.toString() ?? AppLocalizations.of(context)!.tr('');
            final receiverTypeFromMsg = msg['receiver_type']?.toString() ?? AppLocalizations.of(context)!.tr('');

            // If otherPerson is sender, use sender_type; if receiver, use receiver_type
            if (sender == otherPerson.toLowerCase()) {
              receiverType = senderType.isNotEmpty ? senderType : 'business';
            } else {
              receiverType = receiverTypeFromMsg.isNotEmpty
                  ? receiverTypeFromMsg
                  : 'business';
            }
          }
        } catch (e) {
          print('⚠️ Could not determine receiver_type, using default: $e');
        }

        print('📋 Receiver type for $otherPerson: $receiverType');

        // Helper functions to work with global preview state for this specific chat
        bool hasSelectedFile() {
          final key = _currentChatPerson ?? AppLocalizations.of(context)!.tr('');
          _globalSelectedImage ??= {};
          _globalSelectedFile ??= {};
          return (_globalSelectedImage!.containsKey(key) &&
                  _globalSelectedImage![key] != null) ||
              (_globalSelectedFile!.containsKey(key) &&
                  _globalSelectedFile![key] != null);
        }

        XFile? getSelectedImage() {
          final key = _currentChatPerson ?? AppLocalizations.of(context)!.tr('');
          _globalSelectedImage ??= {};
          final image = _globalSelectedImage!.containsKey(key)
              ? _globalSelectedImage![key]
              : null;
          print('🟡 getSelectedImage for $key: ${image?.name}');
          return image;
        }

        PlatformFile? getSelectedFile() {
          final key = _currentChatPerson ?? AppLocalizations.of(context)!.tr('');
          _globalSelectedFile ??= {};
          final file = _globalSelectedFile!.containsKey(key)
              ? _globalSelectedFile![key]
              : null;
          print('🟡 getSelectedFile for $key: ${file?.name}');
          return file;
        }

        String? getPreviewType() {
          final key = _currentChatPerson ?? AppLocalizations.of(context)!.tr('');
          _globalPreviewType ??= {};
          return _globalPreviewType!.containsKey(key)
              ? _globalPreviewType![key]
              : null;
        }

        void updateSelectedImage(XFile? value) {
          final key = _currentChatPerson ?? AppLocalizations.of(context)!.tr('');
          print('🟡 updateSelectedImage for $key: ${value?.name}');
          _globalSelectedImage ??= {};
          _globalSelectedImage![key] = value;
        }

        void updateSelectedFile(PlatformFile? value) {
          final key = _currentChatPerson ?? AppLocalizations.of(context)!.tr('');
          print('🟡 updateSelectedFile for $key: ${value?.name}');
          _globalSelectedFile ??= {};
          _globalSelectedFile![key] = value;
        }

        void updatePreviewType(String? value) {
          final key = _currentChatPerson ?? AppLocalizations.of(context)!.tr('');
          _globalPreviewType ??= {};
          _globalPreviewType![key] = value;
        }

        // Mark messages as read for this conversation - prevent multiple calls
        bool hasMarkedAsRead = false;
        Future<void> markMessagesAsRead() async {
          if (hasMarkedAsRead) return; // Prevent multiple calls
          hasMarkedAsRead = true;

          try {
            final token = await _getStoredToken();

            // Get actual username from SharedPreferences instead of display name
            final prefs = await SharedPreferences.getInstance();
            final currentUsername = prefs.getString('username') ?? currentUser;

            // We want to mark all messages where the current user is the receiver as read
            // So we set the sender to the other person and receiver to current user's USERNAME
            String requestSender = otherPerson;
            String requestReceiver = currentUsername;

            // Special case: if otherPerson is exactly the current user (shouldn't happen but let's be safe)
            if (currentUserVariations.any(
              (v) => v.toLowerCase() == otherPerson.toLowerCase(),
            )) {
              print(
                '⚠️ Cannot mark messages as read: otherPerson is current user ($otherPerson)',
              );
              return;
            }

            // For personal messages (non-order messages), explicitly set order_id to null
            final actualOrderId = (orderId == null || orderId == 0)
                ? null
                : orderId;

            print(
              '🔄 Marking messages as read ONCE: sender=$requestSender, receiver=$requestReceiver, order_id=$actualOrderId',
            );

            final response = await http.put(
              Uri.parse('${ApiConfig.baseUrl}/api/messages/mark-read'),
              headers: {
                'Content-Type': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token',
              },
              body: json.encode({
                'sender': requestSender,
                'receiver': requestReceiver,
                if (actualOrderId != null)
                  'order_id': actualOrderId, // Only include if not null
              }),
            );

            print(
              '📤 Mark-read request body: ${json.encode({'sender': requestSender, 'receiver': requestReceiver, if (actualOrderId != null) 'order_id': actualOrderId})}',
            );

            if (response.statusCode == 200) {
              final data = json.decode(response.body);
              print('✅ Marked ${data['markedAsRead']} messages as read');

              // Update local message state immediately for better UX
              if (isMounted) {
                try {
                  setModalState(() {
                    for (var msg in chatMessages) {
                      if (msg['sender'] == otherPerson &&
                          msg['receiver'] == currentUser) {
                        msg['isRead'] = true;
                      }
                    }
                  });
                } catch (e) {
                  print('⚠️ Cannot update modal state: $e');
                }
              }
            } else {
              print(
                '⚠️ Failed to mark messages as read: ${response.statusCode}',
              );
              print('Response: ${response.body}');
            }
          } catch (e) {
            print('❌ Error marking messages as read: $e');
          }
        }

        // Load complete chat history for this conversation
        void loadCompleteChat() async {
          if (!mounted) return;

          if (mounted) {
            setModalState(() {
              isLoadingMessages = true;
            });
          }

          try {
            // Filter all messages for this specific conversation
            List<Map<String, dynamic>> conversationMessages = [];

            for (var msg in messages) {
              String sender = msg['sender'] ?? AppLocalizations.of(context)!.tr('');
              String receiver = msg['receiver'] ?? AppLocalizations.of(context)!.tr('');

              // Skip delvioo messages
              if (sender.toLowerCase().contains('delvioo') ||
                  receiver.toLowerCase().contains('delvioo')) {
                continue;
              }

              // Use dynamic currentUser getter (no more hardcoded 'Arkadiy')
              String senderLower = sender.toLowerCase();
              String receiverLower = receiver.toLowerCase();
              bool senderIsCurrentUser = currentUserVariations.any(
                (v) => v.toLowerCase() == senderLower,
              );
              bool receiverIsCurrentUser = currentUserVariations.any(
                (v) => v.toLowerCase() == receiverLower,
              );

              // Check if this message is part of this conversation
              bool isPartOfConversation = false;

              // orderId must be not null AND not 0 to be a valid order conversation
              final isOrderChat = orderId != null && orderId != 0;

              if (isOrderChat) {
                // Order-based conversation - match by order_id and participants
                if (msg['order_id'] == orderId) {
                  if ((senderIsCurrentUser && receiver == otherPerson) ||
                      (sender == otherPerson && receiverIsCurrentUser)) {
                    isPartOfConversation = true;
                  }
                }
              } else {
                // Personal conversation - match by participants only
                if (senderIsCurrentUser && receiver == otherPerson) {
                  isPartOfConversation = true;
                } else if (sender == otherPerson && receiverIsCurrentUser) {
                  isPartOfConversation = true;
                }
              }

              if (isPartOfConversation) {
                conversationMessages.add(msg);
              }
            }

            // Sort messages by timestamp
            conversationMessages.sort((a, b) {
              try {
                String aTime = a['sentAt'] ?? AppLocalizations.of(context)!.tr('');
                String bTime = b['sentAt'] ?? AppLocalizations.of(context)!.tr('');

                if (aTime.isEmpty && bTime.isEmpty) return 0;
                if (aTime.isEmpty) return 1;
                if (bTime.isEmpty) return -1;

                return DateTime.parse(aTime).compareTo(DateTime.parse(bTime));
              } catch (e) {
                return 0;
              }
            });

            if (isMounted) {
              setModalState(() {
                chatMessages = conversationMessages;
              });
            }

            // Mark messages as read now that user has opened the chat - only once
            Future.delayed(const Duration(milliseconds: 200), () {
              if (isMounted) {
                markMessagesAsRead();
              }
            });

            // Scroll to bottom after loading messages
            // Auto-scroll removed - DraggableScrollableSheet manages scrolling
          } catch (e) {
            print('Error loading complete chat: $e');
          } finally {
            if (isMounted) {
              setModalState(() {
                isLoadingMessages = false;
              });
            }
          }
        }

        // Send message function
        Future<void> sendMessage(String messageText, String messageType) async {
          if (messageText.isEmpty &&
              getSelectedImage() == null &&
              getSelectedFile() == null) {
            return;
          }

          try {
            // Get actual username from SharedPreferences instead of full name
            final prefs = await SharedPreferences.getInstance();
            final senderUsername =
                prefs.getString('username') ??
                prefs.getString('business_username') ??
                prefs.getString('user_name') ??
                currentUser;

            print(
              '👤 Sender username: $senderUsername (full name: $currentUser)',
            );

            // Add message immediately to UI for better UX
            setModalState(() {
              chatMessages.add({
                'id': DateTime.now().millisecondsSinceEpoch,
                'sender': senderUsername,
                'receiver': otherPerson,
                'message': messageText,
                'message_text': messageText,
                'sentAt': DateTime.now().toIso8601String(),
                'isRead': false,
                'message_type': messageType,
                'type': 'user',
              });
            });

            messageController.clear();
            HapticFeedback.lightImpact();

            // Auto-scroll removed - DraggableScrollableSheet manages scrolling

            // Send message to server
            print('📡 Getting auth token...');
            final token = await _getStoredToken();
            print('🔑 Token: ${token != null ? "Found" : "Missing"}');

            // Choose endpoint based on whether this is an order conversation or personal
            // orderId must be not null AND not 0 to be a valid order conversation
            final isOrderConversation = orderId != null && orderId != 0;
            final endpoint = isOrderConversation
                ? '${ApiConfig.baseUrl}/api/messages/orders/$orderId/messages'
                : '${ApiConfig.baseUrl}/api/messages/send';

            print('📍 Endpoint: $endpoint');
            print(
              '📦 Payload: sender=$senderUsername, receiver=$otherPerson, orderId=$orderId, isOrderConversation=$isOrderConversation',
            );

            print('🚀 Sending HTTP POST request...');
            final response = await http
                .post(
                  Uri.parse(endpoint),
                  headers: {
                    'Content-Type': 'application/json',
                    if (token != null) 'Authorization': 'Bearer $token',
                  },
                  body: json.encode(
                    isOrderConversation
                        ? {
                            // Order conversation uses different format
                            'message_text': messageText,
                            'sender': senderUsername,
                            'receiver': otherPerson,
                            'type': 'user',
                            'message_type': messageType,
                            'order_id': orderId,
                          }
                        : {
                            // Personal chat uses /send endpoint format
                            'sender_id': senderUsername,
                            'sender_type': 'business',
                            'recipient_type': 'driver',
                            'receiver_id': otherPerson,
                            'order_id': 0,
                            'message': messageText,
                          },
                  ),
                )
                .timeout(
                  const Duration(seconds: 10),
                  onTimeout: () {
                    print('⏰ Request timed out after 10 seconds');
                    throw Exception('Request timeout');
                  },
                );

            print('📬 Server response: ${response.statusCode}');
            if (response.statusCode == 200 || response.statusCode == 201) {
              print('✅ Message sent successfully to server');
              print('Response: ${response.body}');

              // Reload messages from server to get the persisted message
              print('🔄 Reloading messages from server...');
              await _loadMessages();

              // Reload the chat after messages are updated
              if (isMounted) {
                loadCompleteChat();
              }
            } else {
              print('❌ Failed to send message: ${response.statusCode}');
              print('Response body: ${response.body}');
            }
          } catch (e, stackTrace) {
            print('❌ Error sending message: $e');
            print('Stack trace: $stackTrace');
          }
        }

        // Format file size
        String formatFileSize(int bytes) {
          if (bytes < 1024) return '$bytes B';
          if (bytes < 1024 * 1024) {
            return '${(bytes / 1024).toStringAsFixed(1)} KB';
          }
          return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        }

        // Handle image attachment
        Future<void> handleImageAttachment(XFile image) async {
          try {
            final fileName = image.name;
            final fileSize = await image.length();

            // Get actual username from SharedPreferences
            final prefs = await SharedPreferences.getInstance();
            final senderUsername =
                prefs.getString('username') ??
                prefs.getString('business_username') ??
                prefs.getString('user_name') ??
                currentUser;

            // Show uploading message
            setModalState(() {
              chatMessages.add({
                'id': 'uploading_${DateTime.now().millisecondsSinceEpoch}',
                'sender': senderUsername,
                'receiver': otherPerson,
                'message': '📤 Uploading image...',
                'message_text': '📤 Uploading image...',
                'sentAt': DateTime.now().toIso8601String(),
                'isRead': false,
                'message_type': 'uploading',
                'type': 'user',
              });
            });

            // Upload image to server
            final token = await _getStoredToken();
            final bytes = await image.readAsBytes();

            // Use general upload endpoint for chat, or order-specific if orderId exists
            // orderId must be not null AND not 0 to be a valid order
            final isOrderChat = orderId != null && orderId != 0;
            final uploadUrl = isOrderChat
                ? '${ApiConfig.baseUrl}/api/messages/orders/$orderId/upload'
                : '${ApiConfig.baseUrl}/api/messages/upload';

            print('🚀 Starting upload to: $uploadUrl');
            print(
              '🚀 orderId: $orderId, otherPerson: $otherPerson, isOrderChat: $isOrderChat',
            );

            final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));

            request.headers.addAll({
              if (token != null) 'Authorization': 'Bearer $token',
            });

            request.fields['sender'] = senderUsername;
            request.fields['receiver'] = otherPerson;
            request.fields['message_type'] = 'image';
            request.fields['sender_type'] = 'business';
            request.fields['receiver_type'] = receiverType;

            print(
              '📤 Image upload fields: sender=$senderUsername, receiver=$otherPerson, receiver_type=$receiverType',
            );

            request.files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: fileName),
            );

            final response = await request.send();
            final responseBody = await response.stream.bytesToString();

            if (response.statusCode == 201) {
              final data = json.decode(responseBody);
              print('✅ Image uploaded successfully. Full response: $data');
              print('✅ File URL: ${data['file_url']}');

              // Reload messages from server to get the persisted attachment
              print('🔄 Reloading messages from server after image upload...');
              await _loadMessages();

              // Remove uploading message and reload chat
              if (isMounted) {
                setModalState(() {
                  chatMessages.removeWhere(
                    (msg) => msg['id'].toString().startsWith('uploading_'),
                  );
                });
                loadCompleteChat();
              }
            } else {
              print('❌ Failed to upload image: ${response.statusCode}');
              print('Response: $responseBody');

              // Remove uploading message and show error
              if (isMounted) {
                setModalState(() {
                  chatMessages.removeWhere(
                    (msg) => msg['id'].toString().startsWith('uploading_'),
                  );
                  chatMessages.add({
                    'id': DateTime.now().millisecondsSinceEpoch,
                    'sender': currentUser,
                    'receiver': otherPerson,
                    'message': '❌ Failed to upload image',
                    'message_text': '❌ Failed to upload image',
                    'sentAt': DateTime.now().toIso8601String(),
                    'isRead': false,
                    'message_type': 'error',
                    'type': 'user',
                  });
                });
              }
            }

            print('📎 Image processing completed: $fileName');
          } catch (e) {
            print('Error handling image attachment: $e');

            // Show error message
            if (isMounted) {
              setModalState(() {
                chatMessages.removeWhere(
                  (msg) => msg['id'].toString().startsWith('uploading_'),
                );
                chatMessages.add({
                  'id': DateTime.now().millisecondsSinceEpoch,
                  'sender': currentUser,
                  'receiver': otherPerson,
                  'message': '❌ Error uploading image: $e',
                  'message_text': '❌ Error uploading image: $e',
                  'sentAt': DateTime.now().toIso8601String(),
                  'isRead': false,
                  'message_type': 'error',
                  'type': 'user',
                });
              });
            }
          }
        }

        // Handle file attachment
        Future<void> handleFileAttachment(
          PlatformFile file,
          String type,
        ) async {
          try {
            final fileName = file.name;
            final fileSize = file.size;

            // Get actual username from SharedPreferences
            final prefs = await SharedPreferences.getInstance();
            final senderUsername =
                prefs.getString('username') ??
                prefs.getString('business_username') ??
                prefs.getString('user_name') ??
                currentUser;

            // Show uploading message
            setModalState(() {
              chatMessages.add({
                'id': 'uploading_${DateTime.now().millisecondsSinceEpoch}',
                'sender': senderUsername,
                'receiver': otherPerson,
                'message': '📤 Uploading ${type.toUpperCase()}...',
                'message_text': '📤 Uploading ${type.toUpperCase()}...',
                'sentAt': DateTime.now().toIso8601String(),
                'isRead': false,
                'message_type': 'uploading',
                'type': 'user',
              });
            });

            // Upload file to server - support both order and general chats
            print(
              '🔍 Debug file bytes: file.bytes = ${file.bytes != null ? "NOT NULL (${file.bytes!.length} bytes)" : "NULL"}',
            );
            print('🔍 Debug file path: file.path = ${file.path}');
            print('🔍 Debug file size: file.size = ${file.size}');

            // Try to get file bytes - either from bytes property or read from path
            Uint8List? fileBytes;
            if (file.bytes != null) {
              fileBytes = file.bytes!;
              print('🔍 Using file.bytes directly');
            } else if (file.path != null) {
              try {
                print('🔍 Attempting to read file from path...');
                final File fileFromPath = File(file.path!);

                // Check if file exists
                bool exists = await fileFromPath.exists();
                print('🔍 File exists: $exists');

                if (exists) {
                  fileBytes = await fileFromPath.readAsBytes();
                  print(
                    '🔍 Successfully read ${fileBytes.length} bytes from path',
                  );
                } else {
                  print('❌ File does not exist at path: ${file.path}');
                }
              } catch (e) {
                print('❌ Error reading file from path: $e');
                print('❌ Stack trace: ${StackTrace.current}');
              }
            } else {
              print('❌ No file.bytes and no file.path available');
            }

            print(
              '🔍 Final fileBytes: ${fileBytes != null ? "${fileBytes.length} bytes" : "NULL"}',
            );

            if (fileBytes != null) {
              final token = await _getStoredToken();

              // Use general upload endpoint for chat, or order-specific if orderId exists
              // orderId must be not null AND not 0 to be a valid order
              final isOrderChat = orderId != null && orderId != 0;
              final uploadUrl = isOrderChat
                  ? '${ApiConfig.baseUrl}/api/messages/orders/$orderId/upload'
                  : '${ApiConfig.baseUrl}/api/messages/upload';

              print('🚀 Starting file upload to: $uploadUrl');
              print(
                '🚀 File: $fileName, type: $type, orderId: $orderId, isOrderChat: $isOrderChat',
              );

              final request = http.MultipartRequest(
                'POST',
                Uri.parse(uploadUrl),
              );

              request.headers.addAll({
                if (token != null) 'Authorization': 'Bearer $token',
              });

              request.fields['sender'] = senderUsername;
              request.fields['receiver'] = otherPerson;
              request.fields['message_type'] = type;
              request.fields['sender_type'] = 'business';
              request.fields['receiver_type'] = receiverType;
              request.fields['file_name'] = fileName;

              print(
                '📤 File upload fields: sender=$senderUsername, receiver=$otherPerson, type=$type, receiver_type=$receiverType',
              );

              request.files.add(
                http.MultipartFile.fromBytes(
                  'file',
                  fileBytes,
                  filename: fileName,
                ),
              );

              final response = await request.send();
              final responseBody = await response.stream.bytesToString();

              if (response.statusCode == 201) {
                final data = json.decode(responseBody);
                print('✅ File uploaded successfully: ${data['file_url']}');

                // Reload messages from server to get the persisted attachment
                print('🔄 Reloading messages from server after file upload...');
                await _loadMessages();

                // Remove uploading message and reload chat
                if (isMounted) {
                  setModalState(() {
                    chatMessages.removeWhere(
                      (msg) => msg['id'].toString().startsWith('uploading_'),
                    );
                  });
                  loadCompleteChat();
                }
              } else {
                print('❌ Failed to upload file: ${response.statusCode}');
                print('Response: $responseBody');

                // Remove uploading message and show error
                if (isMounted) {
                  setModalState(() {
                    chatMessages.removeWhere(
                      (msg) => msg['id'].toString().startsWith('uploading_'),
                    );
                    chatMessages.add({
                      'id': DateTime.now().millisecondsSinceEpoch,
                      'sender': currentUser,
                      'receiver': otherPerson,
                      'message': '❌ Failed to upload ${type.toUpperCase()}',
                      'message_text':
                          '❌ Failed to upload ${type.toUpperCase()}',
                      'sentAt': DateTime.now().toIso8601String(),
                      'isRead': false,
                      'message_type': 'error',
                      'type': 'user',
                    });
                  });
                }
              }
            } else {
              // No order_id or file bytes - just show local message
              final attachmentMessage =
                  '📎 ${type.toUpperCase()}: $fileName (${formatFileSize(fileSize)})';
              await sendMessage(attachmentMessage, type);
            }

            print('📎 File processing completed: $fileName');
          } catch (e) {
            print('Error handling file attachment: $e');

            // Show error message
            if (isMounted) {
              setModalState(() {
                chatMessages.removeWhere(
                  (msg) => msg['id'].toString().startsWith('uploading_'),
                );
                chatMessages.add({
                  'id': DateTime.now().millisecondsSinceEpoch,
                  'sender': currentUser,
                  'receiver': otherPerson,
                  'message': '❌ Error uploading file: $e',
                  'message_text': '❌ Error uploading file: $e',
                  'sentAt': DateTime.now().toIso8601String(),
                  'isRead': false,
                  'message_type': 'error',
                  'type': 'user',
                });
              });
            }
          }
        }

        // Send selected attachment
        Future<void> sendSelectedAttachment() async {
          print(
            '🔴 _sendSelectedAttachment called - Image: ${getSelectedImage() != null}, File: ${getSelectedFile() != null}',
          );

          if (getSelectedImage() != null) {
            print('🔴 Handling image attachment: ${getSelectedImage()!.name}');
            await handleImageAttachment(getSelectedImage()!);
            setModalState(() {
              updateSelectedImage(null);
              updatePreviewType(null);
            });
          } else if (getSelectedFile() != null) {
            print('🔴 Handling file attachment: ${getSelectedFile()!.name}');
            await handleFileAttachment(
              getSelectedFile()!,
              getPreviewType() ?? AppLocalizations.of(context)!.tr('file'),
            );
            setModalState(() {
              updateSelectedFile(null);
              updatePreviewType(null);
            });
          } else {
            print('🔴 No attachment to send!');
          }
        }

        // Clear selected attachment
        void clearSelectedAttachment() {
          setModalState(() {
            updateSelectedImage(null);
            updateSelectedFile(null);
            updatePreviewType(null);
          });
        }

        // Pick image from camera
        Future<void> pickImageFromCamera(BuildContext context) async {
          try {
            final picker = ImagePicker();
            final XFile? image = await picker.pickImage(
              source: ImageSource.camera,
            );
            if (image != null) {
              setModalState(() {
                updateSelectedImage(image);
                updateSelectedFile(null);
                updatePreviewType('image');
              });
            }
          } catch (e) {
            print('Error picking image from camera: $e');
          }
        }

        // Pick image from gallery
        Future<void> pickImageFromGallery(BuildContext context) async {
          try {
            final picker = ImagePicker();
            final XFile? image = await picker.pickImage(
              source: ImageSource.gallery,
            );
            if (image != null) {
              setModalState(() {
                updateSelectedImage(image);
                updateSelectedFile(null);
                updatePreviewType('image');
              });
            }
          } catch (e) {
            print('Error picking image from gallery: $e');
          }
        }

        // Pick PDF file
        Future<void> pickPdfFile(BuildContext context) async {
          try {
            FilePickerResult? result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['pdf'],
            );

            if (result != null && result.files.isNotEmpty) {
              setModalState(() {
                updateSelectedFile(result.files.first);
                updateSelectedImage(null);
                updatePreviewType('pdf');
              });
            }
          } catch (e) {
            print('Error picking PDF file: $e');
          }
        }

        // Pick other files
        Future<void> pickOtherFile(BuildContext context) async {
          try {
            FilePickerResult? result = await FilePicker.platform.pickFiles();

            if (result != null && result.files.isNotEmpty) {
              setModalState(() {
                updateSelectedFile(result.files.first);
                updateSelectedImage(null);
                updatePreviewType('file');
              });
            }
          } catch (e) {
            print('Error picking file: $e');
          }
        }

        // Build attachment option row
        Widget buildAttachmentOption({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
          required bool isLight,
        }) {
          return TradeRepublicTap(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: Colors.transparent),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white : Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: isLight ? Colors.black : Colors.white,
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
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isLight ? Colors.black : Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: isLight ? Colors.black : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: isLight ? Colors.black : Colors.white,
                  ),
                ],
              ),
            ),
          );
        }

        // Show attachment options
        void showAttachmentOptions(BuildContext context, bool isLight) {
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
                        CupertinoIcons.paperclip,
                        size: 22,
                        color: isLight ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          AppLocalizations.of(context)?.sendAttachment ?? AppLocalizations.of(context)!.tr('Attachment'),
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

                  // Options
                  buildAttachmentOption(
                    icon: CupertinoIcons.camera_fill,
                    title: AppLocalizations.of(context)?.camera ?? AppLocalizations.of(context)!.tr('Camera'),
                    subtitle:
                        AppLocalizations.of(context)?.takeAPhoto ?? AppLocalizations.of(context)!.tr('Take a photo'),
                    onTap: () => pickImageFromCamera(context),
                    isLight: isLight,
                  ),

                  buildAttachmentOption(
                    icon: CupertinoIcons.photo_on_rectangle,
                    title:
                        AppLocalizations.of(context)?.photoGallery ?? AppLocalizations.of(context)!.tr('Photo Gallery'),
                    subtitle:
                        AppLocalizations.of(context)?.chooseFromGallery ?? AppLocalizations.of(context)!.tr('Choose from gallery'),
                    onTap: () => pickImageFromGallery(context),
                    isLight: isLight,
                  ),

                  buildAttachmentOption(
                    icon: CupertinoIcons.doc_text,
                    title:
                        AppLocalizations.of(context)?.pdfDocument ?? AppLocalizations.of(context)!.tr('PDF Document'),
                    subtitle:
                        AppLocalizations.of(context)?.uploadPdfFile ?? AppLocalizations.of(context)!.tr('Upload PDF file'),
                    onTap: () => pickPdfFile(context),
                    isLight: isLight,
                  ),

                  const SizedBox(height: 12),

                  // Cancel button
                  TradeRepublicButton(
                    label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    isSecondary: true,
                  ),
                ],
              ),
            ),
          );
        }

        // Track if the modal is still mounted

        // Load complete chat when opening - only once
        bool hasLoadedOnce = false;
        Future.delayed(const Duration(milliseconds: 100), () {
          if (isMounted && !hasLoadedOnce) {
            hasLoadedOnce = true;
            loadCompleteChat();
          }
        });

        return Scaffold(
          backgroundColor: isLight ? Colors.white : Colors.black,
          body: Builder(
            builder: (context) {
              final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
              final topPadding = MediaQuery.of(context).padding.top;

              return Padding(
                padding: EdgeInsets.only(bottom: keyboardHeight),
                child: Column(
                  children: [
                    // Trade Republic Style Header - Clean & Minimal
                    Container(
                      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 14),
                      decoration: BoxDecoration(
                        color: isLight ? Colors.white : Colors.black,
                      ),
                      child: Row(
                        children: [
                          // Back button
                          TradeRepublicButton(
                            icon: Icon(
                              CupertinoIcons.chevron_back,
                              size: 18,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                            isSecondary: true,
                            width: 44,
                            height: 44,
                            padding: EdgeInsets.zero,
                            borderRadius: BorderRadius.circular(25),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 14),
                          // Name - Trade Republic style
                          Expanded(
                            child: Text(
                              otherPerson,
                              style: TextStyle(
                                color: isLight ? Colors.black : Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          // Menu button
                          TradeRepublicButton(
                            icon: Icon(
                              CupertinoIcons.ellipsis,
                              size: 18,
                              color: isLight ? Colors.black : Colors.white,
                            ),
                            isSecondary: true,
                            width: 44,
                            height: 44,
                            padding: EdgeInsets.zero,
                            borderRadius: BorderRadius.circular(25),
                            onPressed: () => _showChatMenuBottomSheet(
                              context,
                              otherPerson,
                              isLight,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Messages list
                    Expanded(
                      child: isLoadingMessages
                          ? Center(child: CultiooLoadingIndicator(size: 20))
                          : ListView.builder(
                              reverse: true, // Start from bottom (last message)
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                100,
                              ),
                              addAutomaticKeepAlives:
                                  true, // Cache widgets to prevent rebuilds
                              itemCount: chatMessages.length,
                              itemBuilder: (context, index) {
                                // Reverse index to show messages in correct order
                                final reversedIndex =
                                    chatMessages.length - 1 - index;
                                final message = chatMessages[reversedIndex];
                                final sender = message['sender'] ?? AppLocalizations.of(context)!.tr('');
                                // Use dynamic currentUserVariations instead of hardcoded 'arkadiy'
                                final isFromMe = currentUserVariations.any(
                                  (v) =>
                                      v.toLowerCase() == sender.toLowerCase(),
                                );

                                // Direct render without animation for better performance
                                return _buildMessageBubble(message, isLight);
                              },
                            ),
                    ),

                    // File preview section - Trade Republic Style
                    if (getSelectedImage() != null || getSelectedFile() != null)
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isLight
                              ? Colors.transparent
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            // Preview thumbnail - Trade Republic Style
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: isLight ? Colors.black : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: getSelectedImage() != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: Image.file(
                                        File(getSelectedImage()!.path),
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              print('Image error: $error');
                                              return Icon(
                                                CupertinoIcons
                                                    .exclamationmark_triangle,
                                                color: isLight
                                                    ? Colors.black
                                                    : Colors.white,
                                              );
                                            },
                                      ),
                                    )
                                  : Icon(
                                      getPreviewType() == 'pdf'
                                          ? Icons.picture_as_pdf
                                          : Icons.attach_file,
                                      color: isLight
                                          ? Colors.black
                                          : Colors.white,
                                      size: 24,
                                    ),
                            ),
                            const SizedBox(width: 12),

                            // File info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    getSelectedImage()?.name ??
                                        getSelectedFile()?.name ??
                                        AppLocalizations.of(
                                          context,
                                        )?.unknownFile ?? AppLocalizations.of(context)!.tr('Unknown file'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isLight
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    getSelectedImage() != null
                                        ? AppLocalizations.of(
                                                context,
                                              )?.imageReadyToSend ?? AppLocalizations.of(context)!.tr('Image • Ready to send')
                                        : '${getPreviewType()?.toUpperCase()} • ${(getSelectedFile()?.size ?? 0) > 0 ? formatFileSize(getSelectedFile()!.size) : 'Unknown size'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isLight
                                          ? Colors.black
                                          : Colors.white,
                                    ),
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
                              backgroundColor: Colors.red.withValues(alpha: 0.1),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setModalState(() {
                                  clearSelectedAttachment();
                                });
                              },
                            ),
                          ],
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
                          // Attachment button
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: TradeRepublicButton.icon(
                              icon: Icon(CupertinoIcons.plus, size: 20),
                              onPressed: () => _showAttachmentOptions(
                                context,
                                orderId,
                                isLight,
                                setModalState,
                                getSelectedImage,
                                getSelectedFile,
                                updateSelectedImage,
                                updateSelectedFile,
                                updatePreviewType,
                              ),
                              backgroundColor:
                                  (isLight ? Colors.black : Colors.white)
                                      .withValues(alpha: 0.06),
                              foregroundColor: isLight
                                  ? Colors.black
                                  : Colors.white,
                              size: 40,
                            ),
                          ),

                          // Input field
                          Expanded(
                            child: TradeRepublicTextField(
                              controller: messageController,
                              focusNode: messageFocusNode,
                              hintText:
                                  AppLocalizations.of(context)?.message ?? AppLocalizations.of(context)!.tr('Message'),
                              maxLines: null,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (value) => setModalState(() {}),
                            ),
                          ),

                          const SizedBox(width: 10),

                          // Send button
                          TradeRepublicButton.icon(
                            icon: const Icon(
                              CupertinoIcons.arrow_up,
                              size: 18,
                            ),
                            size: 40,
                            onPressed:
                                (messageController.text.trim().isEmpty &&
                                        getSelectedImage() == null &&
                                        getSelectedFile() == null)
                                    ? null
                                    : () {
                                        unawaited(() async {
                                          final message =
                                              messageController.text.trim();
                                          final hasAttachment =
                                              getSelectedImage() != null ||
                                                  getSelectedFile() != null;
                                          HapticFeedback.lightImpact();
                                          if (hasAttachment) {
                                            await sendSelectedAttachment();
                                          } else if (message.isNotEmpty) {
                                            await sendMessage(message, 'text');
                                          }
                                        }());
                                      },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Show attachment options with iOS-style design
  void _showAttachmentOptions(
    BuildContext context,
    int? orderId,
    bool isLight,
    StateSetter setModalState,
    XFile? Function() getSelectedImage,
    PlatformFile? Function() getSelectedFile,
    void Function(XFile?) updateSelectedImage,
    void Function(PlatformFile?) updateSelectedFile,
    void Function(String?) updatePreviewType,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DragHandle(),

          TradeRepublicSectionHeader(
            title:
                AppLocalizations.of(context)?.sendAttachment ?? AppLocalizations.of(context)!.tr('Attachment'),
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
                  title: AppLocalizations.of(context)?.photoLabel ?? AppLocalizations.of(context)!.tr('Photo'),
                  subtitle:
                      AppLocalizations.of(context)?.takeOrUploadAPhoto ?? AppLocalizations.of(context)!.tr('Take or upload a photo'),
                  leading: Icon(
                    CupertinoIcons.camera,
                    size: 20,
                    color: TradeRepublicTheme.textColor(context),
                  ),
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);

                    final picker = ImagePicker();
                    final XFile? image = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 70,
                    );

                    if (image != null) {
                      setModalState(() {
                        updateSelectedImage(image);
                        updatePreviewType('image');
                        updateSelectedFile(null);
                      });
                    }
                  },
                ),
                const TradeRepublicDivider(),
                TradeRepublicListTile.navigation(
                  title:
                      AppLocalizations.of(context)?.documentLabel ?? AppLocalizations.of(context)!.tr('Document'),
                  subtitle:
                      AppLocalizations.of(context)?.uploadAPdfFile ?? AppLocalizations.of(context)!.tr('Upload a PDF file'),
                  leading: Icon(
                    CupertinoIcons.doc,
                    size: 20,
                    color: TradeRepublicTheme.textColor(context),
                  ),
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);

                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                    );

                    if (result != null && result.files.isNotEmpty) {
                      setModalState(() {
                        updateSelectedFile(result.files.first);
                        updatePreviewType('pdf');
                        updateSelectedImage(null);
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            width: double.infinity,
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            isSecondary: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isLight) {
    final content = message['message'] ?? message['message_text'] ?? AppLocalizations.of(context)!.tr('');
    final fileUrl = message['fileUrl'] ?? message['file_url'] ?? AppLocalizations.of(context)!.tr('');
    final sender =
      message['sender'] ?? (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr(''));
    final timestamp = message['sentAt'] ?? AppLocalizations.of(context)!.tr('');
    // Use dynamic currentUserVariations instead of hardcoded 'arkadiy'
    final isFromMe = currentUserVariations.any(
      (v) => v.toLowerCase() == sender.toLowerCase(),
    );
    final messageType = message['message_type'] ?? AppLocalizations.of(context)!.tr('text');
    final orderId = message['order_id'];
    final hasOrderId = orderId != null && orderId != 0;

    // Check user type in database if not already cached (only once per user)
    if (!isFromMe && !_userTypeCache.containsKey(sender)) {
      _checkUserType(sender);
    }

    // Format time - Telegram style
    String timeString = '';
    if (timestamp.isNotEmpty) {
      try {
        final dateTime = DateTime.parse(timestamp);
        timeString =
            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        timeString = '';
      }
    }

    // Check if the message has a file attachment
    final isImageUrl =
        messageType == 'image' && (fileUrl.isNotEmpty || content.isNotEmpty);
    final isFileUrl =
        (messageType == 'pdf' || messageType == 'file') &&
        (fileUrl.isNotEmpty || content.isNotEmpty);

    // Construct full URL for images
    String? imageUrl;
    if (isImageUrl) {
      // Priority: fileUrl first, then content
      String urlSource = fileUrl.isNotEmpty ? fileUrl : content;

      if (urlSource.startsWith('http')) {
        // Already a full URL
        imageUrl = urlSource;
      } else if (urlSource.startsWith('/uploads/')) {
        // Relative path - add base URL
        imageUrl = '${ApiConfig.baseUrl}$urlSource';
      } else if (urlSource.startsWith('📷 Image: ')) {
        // Extract filename from "📷 Image: filename"
        final filename = urlSource.replaceFirst('📷 Image: ', '');
        imageUrl = '${ApiConfig.baseUrl}/uploads/chat-attachments/$filename';
      } else {
        // Just a filename - construct full URL
        imageUrl = '${ApiConfig.baseUrl}/uploads/chat-attachments/$urlSource';
      }
    }

    // Trade Republic Style Message Bubble - Modern & Bold
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isFromMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isFromMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Profile picture for received messages (left side)
              if (!isFromMe) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 10, bottom: 2),
                  child: _buildChatProfileImage(sender),
                ),
              ],
              // ── IMAGE bubble ─────────────────────────────────────────
              if (isImageUrl)
                TradeRepublicTap(
                  onTap: () => _openImageViewer(
                    imageUrl!,
                    AppLocalizations.of(context)?.image ?? AppLocalizations.of(context)!.tr('Image'),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 240,
                            maxHeight: 240,
                            minWidth: 120,
                            minHeight: 80,
                          ),
                          child: Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                width: 200,
                                height: 150,
                                color: isLight
                                    ? Colors.transparent
                                    : Colors.transparent,
                                child: Center(
                                  child: CultiooLoadingIndicator(size: 20),
                                ),
                              );
                            },
                            errorBuilder: (context, _, __) => Container(
                              width: 200,
                              height: 120,
                              color: isLight
                                  ? Colors.transparent
                                  : Colors.transparent,
                              child: Icon(
                                CupertinoIcons.photo,
                                size: 32,
                                color: (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.3),
                              ),
                            ),
                          ), // Image.network
                        ), // ConstrainedBox
                        if (timeString.isNotEmpty)
                          Positioned(
                            bottom: 8,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.45),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                timeString,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              // ── FILE / PDF bubble ─────────────────────────────────────
              else if (isFileUrl)
                TradeRepublicTap(
                  onTap: () {
                    String downloadUrl = fileUrl.isNotEmpty ? fileUrl : content;
                    if (!downloadUrl.startsWith('http')) {
                      downloadUrl = downloadUrl.startsWith('/uploads/')
                          ? '${ApiConfig.baseUrl}$downloadUrl'
                          : '${ApiConfig.baseUrl}/uploads/chat-attachments/$downloadUrl';
                    }
                    String fileName = downloadUrl.split('/').last;
                    if (fileName.isEmpty || !fileName.contains('.')) {
                      fileName = messageType == 'pdf' ? 'document.pdf' : 'file';
                    }
                    _downloadFile(downloadUrl, fileName);
                  },
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 260),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isFromMe
                          ? (isLight ? Colors.black : Colors.white)
                          : (isLight
                                ? Colors.transparent
                                : Colors.transparent),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icon container
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color:
                                (isFromMe
                                        ? (isLight
                                              ? Colors.white
                                              : Colors.black)
                                        : (isLight
                                              ? Colors.black
                                              : Colors.white))
                                    .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            messageType == 'pdf'
                                ? CupertinoIcons.doc_text_fill
                                : CupertinoIcons.paperclip,
                            size: 18,
                            color: isFromMe
                                ? (isLight ? Colors.white : Colors.black)
                                : (isLight ? Colors.black : Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                () {
                                  String src = fileUrl.isNotEmpty
                                      ? fileUrl
                                      : content;
                                  String fname = src.split('/').last;
                                  if (fname.isEmpty || !fname.contains('.')) {
                                    return messageType == 'pdf'
                                        ? (AppLocalizations.of(
                                                context,
                                              )?.pdfDocument ?? AppLocalizations.of(context)!.tr('PDF Document'))
                                        : 'File';
                                  }
                                  return fname.length > 22
                                      ? '${fname.substring(0, 19)}…'
                                      : fname;
                                }(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                  color: isFromMe
                                      ? (isLight ? Colors.white : Colors.black)
                                      : (isLight ? Colors.black : Colors.white),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppLocalizations.of(context)?.tapToDownload ?? AppLocalizations.of(context)!.tr('Tap to download'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color:
                                      (isFromMe
                                              ? (isLight
                                                    ? Colors.white
                                                    : Colors.black)
                                              : (isLight
                                                    ? Colors.black
                                                    : Colors.white))
                                          .withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          CupertinoIcons.arrow_down_circle_fill,
                          size: 20,
                          color:
                              (isFromMe
                                      ? (isLight ? Colors.white : Colors.black)
                                      : (isLight ? Colors.black : Colors.white))
                                  .withOpacity(0.4),
                        ),
                      ],
                    ),
                  ),
                )
              // ── TEXT bubble ───────────────────────────────────────────
              else
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isFromMe
                          ? (isLight ? Colors.black : Colors.white)
                          : (isLight
                                ? Colors.transparent
                                : Colors.transparent),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Order badge
                        if (hasOrderId)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (isFromMe
                                          ? (isLight
                                                ? Colors.white
                                                : Colors.black)
                                          : (isLight
                                                ? Colors.black
                                                : Colors.white))
                                      .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.tag,
                                  size: 10,
                                  color: isFromMe
                                      ? (isLight ? Colors.white : Colors.black)
                                      : (isLight ? Colors.black : Colors.white),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '#$orderId',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isFromMe
                                        ? (isLight
                                              ? Colors.white
                                              : Colors.black)
                                        : (isLight
                                              ? Colors.black
                                              : Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Text + inline time
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                content,
                                style: TextStyle(
                                  color: isFromMe
                                      ? (isLight ? Colors.white : Colors.black)
                                      : (isLight ? Colors.black : Colors.white),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  height: 1.45,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (timeString.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 1),
                                child: Text(
                                  timeString,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.1,
                                    color:
                                        (isFromMe
                                                ? (isLight
                                                      ? Colors.white
                                                      : Colors.black)
                                                : (isLight
                                                      ? Colors.black
                                                      : Colors.white))
                                            .withOpacity(0.45),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatMessageTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    try {
      // Parse the UTC timestamp and add 4 hours to get the correct local time
      final parsedDate = DateTime.parse(dateString);
      final localDate = parsedDate.add(Duration(hours: 4));

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final messageDate = DateTime(
        localDate.year,
        localDate.month,
        localDate.day,
      );

      // Check if the message is from today
      if (messageDate == today) {
        // Show only time for today's messages
        return '${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
      } else {
        // Show date and time for older messages
        return '${_appSettings.formatDate(localDate)} ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      print('Error formatting message time: $e');
      return '';
    }
  }

  // Open image viewer
  // Open image viewer
  void _openImageViewer(String imageUrl, String imageName) {
    final isLight = _appSettings.isLightMode(context);

    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      enableDrag: true,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            DragHandle(),
            // Image
            Expanded(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      width: 300,
                      height: 300,
                      color: Colors.black,
                      child: const Center(child: CultiooLoadingIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 300,
                      height: 300,
                      color: Colors.black,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            CupertinoIcons.exclamationmark_triangle,
                            size: 64,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context)?.failedToLoadImage ?? AppLocalizations.of(context)!.tr('Failed to load image'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Download file function
  Future<void> _downloadFile(String fileUrl, String fileName) async {
    try {
      // Construct full URL if it's a relative path
      String fullUrl = fileUrl;

      // If URL is a local server path, convert to GCS URL
      if (fileUrl.contains('/uploads/chat-attachments/')) {
        // Extract just the filename
        final filename = fileUrl.split('/').last;
        // Use Google Cloud Storage URL directly
        fullUrl =
            'https://storage.googleapis.com/cultioo-uploads/chat-attachments/$filename';
        print('🔄 Converted local URL to GCS: $fullUrl');
      } else if (fileUrl.startsWith('/uploads/')) {
        // Relative path - add base URL
        fullUrl = '${ApiConfig.baseUrl}$fileUrl';
      } else if (!fileUrl.startsWith('http')) {
        // Just a filename - construct GCS URL
        fullUrl =
            'https://storage.googleapis.com/cultioo-uploads/chat-attachments/$fileUrl';
        print('🔄 Constructed GCS URL from filename: $fullUrl');
      }

      print('📥 Attempting to download: $fullUrl');

      // Import url_launcher
      final Uri uri = Uri.parse(fullUrl);

      // Try to launch the URL - this will either download or open in browser
      final bool launched = await canLaunchUrl(uri);
      if (launched) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('✅ Download started: $fileName');
      } else {
        print('❌ Could not launch URL: $fullUrl');
      }
    } catch (e) {
      print('❌ Error downloading file: $e');
    }
  }

  // Show delete user confirmation bottom sheet
  void _showDeleteUserDialog(
    BuildContext context,
    String userName,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DragHandle(),

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
                AppLocalizations.of(context)?.deleteUser ?? AppLocalizations.of(context)!.tr('Delete User'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Content
          Text(
            'Are you sure you want to delete user "$userName"? All messages will be permanently removed.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons - Trade Republic Style
          Row(
            children: [
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  isSecondary: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)?.delete ?? AppLocalizations.of(context)!.tr('Delete'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop(); // Close chat
                    _deleteUser(userName);
                  },
                  isDestructive: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Show block user confirmation bottom sheet
  void _showBlockUserDialog(
    BuildContext context,
    String userName,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DragHandle(),

          // ── Sheet header: Icon left + Title ──
          Row(
            children: [
              Icon(
                CupertinoIcons.hand_raised,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.blockUser ?? AppLocalizations.of(context)!.tr('Block User'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Content
          Text(
            'Are you sure you want to block user "$userName"? Blocked users cannot send you messages.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isLight ? Colors.black : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons - Trade Republic Style
          Row(
            children: [
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  isSecondary: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TradeRepublicButton(
                  label: AppLocalizations.of(context)?.block ?? AppLocalizations.of(context)!.tr('Block'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop(); // Close chat
                    _blockUser(userName);
                  },
                  isDestructive: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Show chat menu bottom sheet
  void _showChatMenuBottomSheet(
    BuildContext context,
    String userName,
    bool isLight,
  ) {
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DragHandle(),
          // User options header
          Row(
            children: [
              Icon(
                CupertinoIcons.person_crop_circle,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  userName,
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
          const SizedBox(height: 12),

          TradeRepublicCard(
            backgroundColor: isLight ? null : Colors.transparent,
            padding: EdgeInsets.zero,
            child: TradeRepublicListTile.destructive(
              title: AppLocalizations.of(context)?.blockUser ?? AppLocalizations.of(context)!.tr('Block User'),
              subtitle:
                  AppLocalizations.of(context)?.stopReceivingMessages ?? AppLocalizations.of(context)!.tr('Stop receiving messages'),
              leading: Container(
                width: 30,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  CupertinoIcons.hand_raised_fill,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                _showBlockUserDialog(context, userName, isLight);
              },
            ),
          ),

          const SizedBox(height: 24),

          // Cancel button - Trade Republic Style
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            isSecondary: true,
          ),
        ],
      ),
    );
  }

  Widget _buildChatMenuOption(
    String option,
    bool isSelected,
    VoidCallback onTap,
    bool isLight,
    IconData icon,
    Color iconColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TradeRepublicButton(
        label: option,
        onPressed: onTap,
        isSecondary:
            option !=
            (AppLocalizations.of(context)?.deleteChat ?? AppLocalizations.of(context)!.tr('Delete Chat')),
        isDestructive:
            option ==
                (AppLocalizations.of(context)?.deleteChat ?? AppLocalizations.of(context)!.tr('Delete Chat')) ||
            option == (AppLocalizations.of(context)?.blockUser ?? AppLocalizations.of(context)!.tr('Block User')),
      ),
    );
  }

  // Delete user function
  Future<void> _deleteUser(String userName) async {
    try {
      final token = await _getStoredToken();

      // Make API call to delete user and their messages
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/users/delete/$userName'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        TopNotification.success(
          context,
          '${AppLocalizations.of(context)?.userSuccessfullyDeleted ?? AppLocalizations.of(context)!.tr('User successfully deleted')}: "$userName"',
        );

        // Reload messages to reflect changes
        _loadMessages();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error deleting user: $e');

      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorDeletingUser ?? AppLocalizations.of(context)!.tr('Error deleting user')}: "$userName"',
      );
    }
  }

  // Block user function
  Future<void> _blockUser(String userName) async {
    try {
      final token = await _getStoredToken();

      // Make API call to block user using the new endpoint
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/messages/block-user'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'blocked_username': userName}),
      );

      if (response.statusCode == 200) {
        TopNotification.warning(
          context,
          '${AppLocalizations.of(context)?.userSuccessfullyBlocked ?? AppLocalizations.of(context)!.tr('User successfully blocked')}: "$userName"',
        );

        // Reload messages to reflect changes
        _loadMessages();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error blocking user: $e');

      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorBlockingUser ?? AppLocalizations.of(context)!.tr('Error blocking user')}: "$userName"',
      );
    }
  }

  // Show messenger settings bottom sheet
  void _showMessengerSettingsBottomSheet(bool isLight) {
    TradeRepublicBottomSheet.show(
      context: context,
      bottomPadding: 20.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),

          // ── Header ──
          Row(
            children: [
              Icon(
                CupertinoIcons.settings,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.settings ?? AppLocalizations.of(context)!.tr('Settings'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Options ──
          TradeRepublicListTile.navigation(
            title:
                AppLocalizations.of(context)?.blockedUsers ?? AppLocalizations.of(context)!.tr('Blocked Users'),
            subtitle:
                AppLocalizations.of(context)?.manageBlockedContacts ?? AppLocalizations.of(context)!.tr('Manage blocked contacts'),
            leading: const Icon(
              CupertinoIcons.hand_raised_fill,
              size: 18,
              color: Color(0xFFFF3B30),
            ),
            onTap: () {
              Navigator.pop(context);
              _showBlockedUsersBottomSheet(isLight);
            },
          ),

          const TradeRepublicDivider(),

          TradeRepublicListTile.navigation(
            title:
                AppLocalizations.of(context)?.deletedUsers ?? AppLocalizations.of(context)!.tr('Deleted Users'),
            subtitle:
                AppLocalizations.of(context)?.viewRecentlyDeletedChats ?? AppLocalizations.of(context)!.tr('View recently deleted chats'),
            leading: const Icon(
              CupertinoIcons.trash,
              size: 18,
              color: Color(0xFFFF9500),
            ),
            onTap: () {
              Navigator.pop(context);
              _showDeletedUsersBottomSheet(isLight);
            },
          ),

          const TradeRepublicDivider(),

          TradeRepublicListTile.destructive(
            title:
                AppLocalizations.of(context)?.clearAllChats ?? AppLocalizations.of(context)!.tr('Clear All Chats'),
            subtitle:
                AppLocalizations.of(context)?.deleteAllMessageHistory ?? AppLocalizations.of(context)!.tr('Delete all message history'),
            leading: const Icon(
              CupertinoIcons.delete_solid,
              size: 18,
              color: Color(0xFFFF3B30),
            ),
            onTap: () {
              Navigator.pop(context);
              _showClearAllChatsBottomSheet(isLight);
            },
          ),

          const SizedBox(height: 12),

          // ── Cancel ──
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            onPressed: () => Navigator.pop(context),
            isSecondary: true,
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllChats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_messages');
    await prefs.remove('messages_cache_time');
    await prefs.remove('cully_ai_chat_history_business');
    await prefs.remove('cully_ai_chat_history');
    await prefs.remove('cully_messages');

    if (!mounted) return;
    setState(() {
      messages.clear();
      conversations = _getUniqueConversations();
      totalMessages = 0;
      unreadCount = 0;
    });

    TopNotification.success(
      context,
      AppLocalizations.of(context)?.chatDeleted ?? AppLocalizations.of(context)!.tr('Chat history deleted'),
    );
  }

  void _showClearAllChatsBottomSheet(bool isLight) {
    TradeRepublicBottomSheet.show<bool>(
      context: context,
      showDragHandle: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.delete_solid,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.clearAllChats ?? AppLocalizations.of(context)!.tr('Clear All Chats'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(context)?.deleteAllMessageHistory ?? AppLocalizations.of(context)!.tr('Delete all message history'),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: (isLight ? Colors.black : Colors.white).withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.delete ?? AppLocalizations.of(context)!.tr('Delete'),
            onPressed: () async {
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
              await _clearAllChats();
            },
            backgroundColor: const Color(0xFFFF3B30),
            foregroundColor: Colors.white,
            width: double.infinity,
          ),
          const SizedBox(height: 10),
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            isSecondary: true,
            width: double.infinity,
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildMessengerSettingsOption(
    String option,
    bool isSelected,
    VoidCallback onTap,
    bool isLight,
    IconData icon,
    Color iconColor,
  ) {
    return TradeRepublicButton(
      label: option,
      onPressed: onTap,
      isSecondary: true,
    );
  }

  // Show blocked users bottom sheet
  void _showBlockedUsersBottomSheet(bool isLight) async {
    // Load blocked users from the API
    List<Map<String, dynamic>> blockedUsers = [];
    bool isLoading = true;

    TradeRepublicBottomSheet.show(
      context: context,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          // Load blocked users when sheet opens
          if (isLoading) {
            _loadBlockedUsers().then((users) {
              if (context.mounted) {
                setModalState(() {
                  blockedUsers = users;
                  isLoading = false;
                });
              }
            });
          }

          return Column(
            children: [
              const DragHandle(),
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
                    AppLocalizations.of(context)?.blockedUsers ?? AppLocalizations.of(context)!.tr('Blocked Users'),
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

              // Content
              Expanded(
                child: isLoading
                    ? Center(child: CultiooLoadingIndicator(size: 20))
                    : blockedUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.nosign,
                              size: 48,
                              color: (isLight ? Colors.black : Colors.white)
                                  .withOpacity(0.2),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)?.noBlockedUsers ?? AppLocalizations.of(context)!.tr('No Blocked Users'),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(
                                    context,
                                  )?.usersYouBlockWillAppearHere ?? AppLocalizations.of(context)!.tr('Users you block will appear here'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: isLight ? Colors.black : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: blockedUsers.length,
                        itemBuilder: (context, index) {
                          final blockedUser = blockedUsers[index];
                          final userName =
                                blockedUser['blocked_username'] ??
                                  (AppLocalizations.of(context)?.unknown ?? AppLocalizations.of(context)!.tr(''));
                          final blockedAt = blockedUser['blocked_at'] ?? AppLocalizations.of(context)!.tr('');

                          return _buildBlockedUserItem(
                            userName,
                            blockedAt,
                            () async {
                              await _unblockUser(userName);
                              // Refresh the list
                              final updatedUsers = await _loadBlockedUsers();
                              if (context.mounted) {
                                setModalState(() {
                                  blockedUsers = updatedUsers;
                                });
                              }
                            },
                            isLight,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBlockedUserItem(
    String userName,
    String blockedAt,
    VoidCallback onUnblock,
    bool isLight,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isLight ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                  style: TextStyle(
                    color: isLight ? Colors.white : Colors.black,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (blockedAt.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Blocked ${_formatBlockedTime(blockedAt)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: (isLight ? Colors.black : Colors.white)
                              .withOpacity(0.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TradeRepublicTap(
              onTap: () {
                HapticFeedback.lightImpact();
                onUnblock();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  AppLocalizations.of(context)?.unblock ?? AppLocalizations.of(context)!.tr('Unblock'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadBlockedUsers() async {
    try {
      final token = await _getStoredToken();

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/messages/blocked-users'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['blocked_users'] != null) {
          return List<Map<String, dynamic>>.from(data['blocked_users']);
        }
      }
    } catch (e) {
      print('❌ Error loading blocked users: $e');
    }
    return [];
  }

  // Show deleted users bottom sheet
  void _showDeletedUsersBottomSheet(bool isLight) async {
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
                CupertinoIcons.trash,
                size: 22,
                color: isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.deletedUsers ?? AppLocalizations.of(context)!.tr('Deleted Users'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Empty state for now
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.tray,
                    size: 48,
                    color: (isLight ? Colors.black : Colors.white).withOpacity(
                      0.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)?.noDeletedUsers ?? AppLocalizations.of(context)!.tr('No deleted users'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isLight ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)?.deletedUsersWillAppearHere ?? AppLocalizations.of(context)!.tr('Deleted users will appear here'),
                    style: TextStyle(
                      fontSize: 14,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)?.deletedUsersWillAppearHere ?? AppLocalizations.of(context)!.tr('Deleted users will appear here'),
                    style: TextStyle(
                      fontSize: 14,
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unblockUser(String userName) async {
    try {
      final token = await _getStoredToken();

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/messages/unblock-user'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'blocked_username': userName}),
      );

      if (response.statusCode == 200) {
        TopNotification.success(
          context,
          '${AppLocalizations.of(context)?.userSuccessfullyUnblocked ?? AppLocalizations.of(context)!.tr('User successfully unblocked')}: "$userName"',
        );

        // Reload messages to reflect changes
        _loadMessages();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error unblocking user: $e');

      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorUnblockingUser ?? AppLocalizations.of(context)!.tr('Error unblocking user')}: "$userName"',
      );
    }
  }

  String _formatBlockedTime(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return AppLocalizations.of(context)?.justNow ?? AppLocalizations.of(context)!.tr('just now');
      }
    } catch (e) {
      return '';
    }
  }

  // Build profile image for conversation list (48px size)
  Widget _buildConversationProfileImage(String userName, {String? userType}) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Check if we have cached profile data
    final userData = _userTypeCache[userName];
    final isBusiness = userData?['isBusiness'] == true;
    final profilePic = userData?['profilePic'];
    final businessLogo = userData?['businessLogo'];
    final firstName = userData?['firstName'] ?? AppLocalizations.of(context)!.tr('');
    final lastName = userData?['lastName'] ?? AppLocalizations.of(context)!.tr('');

    // Determine which image to show (already GCS URL from cache)
    String? imageToShow;
    if (isBusiness && businessLogo != null && businessLogo.isNotEmpty) {
      imageToShow = businessLogo;
    } else if (profilePic != null && profilePic.isNotEmpty) {
      imageToShow = profilePic;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: imageToShow == null
            ? (isLight
                  ? Colors.black.withOpacity(0.06)
                  : Colors.white.withOpacity(0.06))
            : null,
      ),
      child: imageToShow != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: _buildProfileImageFromData(imageToShow, userName),
            )
          : Center(
              child: Text(
                _getInitials(userName, firstName, lastName),
                style: TextStyle(
                  color: isLight ? Colors.black : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
    );
  }

  // Build profile image widget with correct business/personal profile
  Widget _buildProfileImage(String userName) {
    // Check if we have cached profile data
    final userData = _userTypeCache[userName];
    final isBusiness = userData?['isBusiness'] == true;
    final profilePic = userData?['profilePic'];
    final businessLogo = userData?['businessLogo'];
    final firstName = userData?['firstName'] ?? AppLocalizations.of(context)!.tr('');
    final lastName = userData?['lastName'] ?? AppLocalizations.of(context)!.tr('');

    // Determine which image to show (already GCS URL from cache)
    String? imageToShow;
    if (isBusiness && businessLogo != null && businessLogo.isNotEmpty) {
      // Business user with business logo
      imageToShow = businessLogo;
    } else if (profilePic != null && profilePic.isNotEmpty) {
      // Regular profile picture
      imageToShow = profilePic;
    }

    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: imageToShow == null
            ? (isLight ? Colors.black : Colors.white)
            : null,
      ),
      child: imageToShow != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _buildProfileImageFromData(imageToShow, userName),
            )
          : Center(
              child: Text(
                _getInitials(userName, firstName, lastName),
                style: TextStyle(
                  color: isLight ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
            ),
    );
  }

  // Build profile image for chat messages (smaller size)
  Widget _buildChatProfileImage(String userName) {
    // Check if we have cached profile data
    final userData = _userTypeCache[userName];
    final isBusiness = userData?['isBusiness'] == true;
    final profilePic = userData?['profilePic'];
    final businessLogo = userData?['businessLogo'];
    final firstName = userData?['firstName'] ?? AppLocalizations.of(context)!.tr('');
    final lastName = userData?['lastName'] ?? AppLocalizations.of(context)!.tr('');

    // Determine which image to show (already GCS URL from cache)
    String? imageToShow;
    if (isBusiness && businessLogo != null && businessLogo.isNotEmpty) {
      // Business user with business logo
      imageToShow = businessLogo;
    } else if (profilePic != null && profilePic.isNotEmpty) {
      // Regular profile picture
      imageToShow = profilePic;
    }

    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: imageToShow == null
            ? (isLight ? Colors.black : Colors.white)
            : null,
      ),
      child: imageToShow != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _buildChatProfileImageFromData(imageToShow, userName),
            )
          : Center(
              child: Text(
                _getInitials(userName, firstName, lastName),
                style: TextStyle(
                  color: isLight ? Colors.white : Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
            ),
    );
  }

  // Build profile image from SVG data or URL for chat messages
  Widget _buildChatProfileImageFromData(String imageData, String userName) {
    print('🖼️ Chat profile image data for $userName: $imageData');

    if (imageData.startsWith('<svg')) {
      // SVG data - render as text with extracted color and letter
      return _buildChatSvgProfileImage(imageData, userName);
    } else if (imageData.startsWith('http')) {
      // Full URL - use directly (already converted to GCS in cache)
      print('🖼️ Loading chat profile image from HTTP: $imageData');

      return Image.network(
        imageData,
        fit: BoxFit.cover,
        width: 32,
        height: 32,
        errorBuilder: (context, error, stackTrace) {
          print(
            '❌ Failed to load chat profile image: $imageData - Error: $error',
          );
          return _buildChatFallbackAvatar(userName);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            print('✅ Successfully loaded chat profile image for $userName');
            return child;
          }
          return Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CultiooLoadingIndicator(size: 20),
            ),
          );
        },
      );
    } else if (imageData.startsWith('/')) {
      // Relative path - convert to GCS
      final filename = imageData.split('/').last;
      final gcsUrl =
          'https://storage.googleapis.com/cultioo-uploads/profile-images/$filename';
      print(
        '🖼️ Loading chat profile from relative path, converted to GCS: $gcsUrl',
      );

      return Image.network(
        gcsUrl,
        fit: BoxFit.cover,
        width: 32,
        height: 32,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Failed to load chat profile from GCS: $gcsUrl');
          return _buildChatFallbackAvatar(userName);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CultiooLoadingIndicator(size: 20),
            ),
          );
        },
      );
    } else if (imageData.isNotEmpty) {
      // Just a filename - use GCS URL
      final imageUrl =
          'https://storage.googleapis.com/cultioo-uploads/profile-images/$imageData';
      print('🖼️ Loading chat profile from filename, using GCS: $imageUrl');

      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: 32,
        height: 32,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Failed to load chat profile from filename: $imageUrl');
          return _buildChatFallbackAvatar(userName);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CultiooLoadingIndicator(size: 20),
            ),
          );
        },
      );
    } else {
      // Unknown format - use fallback
      print('⚠️ Empty or unknown image data for $userName');
      return _buildChatFallbackAvatar(userName);
    }
  }

  // Build SVG profile image for chat messages - Trade Republic style
  Widget _buildChatSvgProfileImage(String svgData, String userName) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    try {
      // Extract letter from SVG
      final textMatch = RegExp(
        r'<text[^>]*>([^<]+)</text>',
      ).firstMatch(svgData);
      String letter = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';

      if (textMatch != null) {
        letter = textMatch.group(1)!;
      }

      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isLight ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            letter,
            style: TextStyle(
              color: isLight ? Colors.white : Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
        ),
      );
    } catch (e) {
      print('❌ Error parsing SVG for chat $userName: $e');
      return _buildChatFallbackAvatar(userName);
    }
  }

  // Build fallback avatar for chat messages
  Widget _buildChatFallbackAvatar(String userName) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isLight ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
          style: TextStyle(
            color: isLight ? Colors.white : Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  // Build profile image from SVG data or URL
  Widget _buildProfileImageFromData(String imageData, String userName) {
    if (imageData.startsWith('<svg')) {
      // SVG data - render as text with extracted color and letter
      return _buildSvgProfileImage(imageData, userName);
    } else if (imageData.startsWith('http')) {
      // Full URL - convert to GCS URL if it's a server URL
      String imageUrl = imageData;

      // Convert server URLs to GCS URLs
      if (imageData.contains('/uploads/profile-images/')) {
        final filename = imageData.split('/').last;
        imageUrl =
            'https://storage.googleapis.com/cultioo-uploads/profile-images/$filename';
        print('🔄 Converted server profile URL to GCS: $imageUrl');
      } else if (imageData.contains('localhost:3006')) {
        imageUrl = imageData.replaceAll(
          'http://localhost:3006',
          ApiConfig.baseUrl,
        );
      }

      print('🖼️ Loading profile image from: $imageUrl');

      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Failed to load profile image: $imageUrl');
          print('❌ Error: $error');
          return _buildFallbackAvatar(userName);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            print('✅ Successfully loaded profile image: $imageUrl');
            return child;
          }
          return Center(child: CultiooLoadingIndicator(size: 20));
        },
      );
    } else if (imageData.startsWith('/')) {
      // Relative path - try GCS URL
      final filename = imageData.split('/').last;
      final gcsUrl =
          'https://storage.googleapis.com/cultioo-uploads/profile-images/$filename';

      return Image.network(
        gcsUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // Silently fall back to avatar - profile images may not exist in GCS yet
          return _buildFallbackAvatar(userName);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildFallbackAvatar(userName);
        },
      );
    } else if (imageData.isNotEmpty) {
      // Just a filename - use GCS URL instead of server URL
      final imageUrl =
          'https://storage.googleapis.com/cultioo-uploads/profile-images/$imageData';
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // Silently fall back to avatar - profile images may not exist in GCS yet
          return _buildFallbackAvatar(userName);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildFallbackAvatar(userName);
        },
      );
    } else {
      // Unknown format - use fallback
      return _buildFallbackAvatar(userName);
    }
  }

  // Build SVG profile image - Trade Republic style
  Widget _buildSvgProfileImage(String svgData, String userName) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    try {
      // Extract letter from SVG
      final textMatch = RegExp(
        r'<text[^>]*>([^<]+)</text>',
      ).firstMatch(svgData);
      String letter = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';

      if (textMatch != null) {
        letter = textMatch.group(1)!;
      }

      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isLight ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            letter,
            style: TextStyle(
              color: isLight ? Colors.white : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
        ),
      );
    } catch (e) {
      print('❌ Error parsing SVG for $userName: $e');
      return _buildFallbackAvatar(userName);
    }
  }

  // Build fallback avatar - Trade Republic style
  Widget _buildFallbackAvatar(String userName) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isLight ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
          style: TextStyle(
            color: isLight ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  // Get initials for display
  String _getInitials(String userName, String firstName, String lastName) {
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    } else if (firstName.isNotEmpty) {
      return firstName[0].toUpperCase();
    } else if (userName.isNotEmpty) {
      return userName[0].toUpperCase();
    } else {
      return 'U';
    }
  }

  // Cache for user type data to avoid repeated API calls
  final Map<String, Map<String, dynamic>> _userTypeCache = {};

  // Helper function to convert image URLs to GCS storage
  String _convertToGcsUrl(String imageUrl) {
    if (imageUrl.isEmpty) return imageUrl;

    // If it's a full server URL, convert to GCS
    if (imageUrl.contains('/uploads/profile-images/')) {
      final filename = imageUrl.split('/').last;
      return 'https://storage.googleapis.com/cultioo-uploads/profile-images/$filename';
    }

    // If it's a relative path, use GCS
    if (imageUrl.startsWith('/uploads/')) {
      final filename = imageUrl.split('/').last;
      return 'https://storage.googleapis.com/cultioo-uploads/profile-images/$filename';
    }

    // If it's just a filename, use GCS
    if (!imageUrl.startsWith('http')) {
      return 'https://storage.googleapis.com/cultioo-uploads/profile-images/$imageUrl';
    }

    // Otherwise return as-is (already a full URL)
    return imageUrl;
  }

  // Get user type color based on actual database check - Trade Republic Style
  Color _getUserTypeColor(String userName, {bool isLight = true}) {
    // Trade Republic style: Use black/white instead of colors
    return isLight ? Colors.black : Colors.white;
  }

  // Get user type icon based on actual database check
  IconData _getUserTypeIcon(String userName, {String? userType}) {
    // If userType is provided directly from message data, use it
    if (userType != null) {
      return userType == 'delvioo'
          ? CupertinoIcons.cube_box
          : CupertinoIcons.building_2_fill;
    }

    // Check cache first
    if (_userTypeCache.containsKey(userName)) {
      final userData = _userTypeCache[userName]!;
      return userData['isDriver'] == true
          ? CupertinoIcons.cube_box
          : CupertinoIcons.building_2_fill;
    }

    // Default to business icon until we verify
    return CupertinoIcons.building_2_fill;
  }

  // Get user type text based on actual database check
  String _getUserTypeText(String userName, {String? userType}) {
    // If userType is provided directly from message data, use it
    if (userType != null) {
      return userType == 'delvioo'
          ? AppLocalizations.of(context)?.driverLabel ?? AppLocalizations.of(context)!.tr('Driver')
          : AppLocalizations.of(context)?.businessLabel ?? AppLocalizations.of(context)!.tr('Business');
    }

    // Check cache first
    if (_userTypeCache.containsKey(userName)) {
      final userData = _userTypeCache[userName]!;
      return userData['isDriver'] == true
          ? AppLocalizations.of(context)?.driverLabel ?? AppLocalizations.of(context)!.tr('Driver')
          : AppLocalizations.of(context)?.businessLabel ?? AppLocalizations.of(context)!.tr('Business');
    }

    // Default to business until we verify
    return AppLocalizations.of(context)?.businessLabel ?? AppLocalizations.of(context)!.tr('Business');
  }

  // Check if user is actually a driver via database
  Future<void> _checkUserType(String userName) async {
    // Skip if already cached
    if (_userTypeCache.containsKey(userName)) return;

    try {
      // Try driver endpoint first
      var response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/user-data/$userName'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Driver API response for $userName: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final profileData = data['data'];

          // Get profile image and convert to GCS URL
          String? profilePicUrl;
          final profileImage = profileData?['profileImage']?.toString();
          if (profileImage != null && profileImage.isNotEmpty) {
            profilePicUrl = _convertToGcsUrl(profileImage);
            print('🖼️ Driver profile image URL: $profilePicUrl');
          }

          setState(() {
            _userTypeCache[userName] = {
              'isDriver': true,
              'isUser': false,
              'checkedAt': DateTime.now().toIso8601String(),
              'profilePic': profilePicUrl,
              'businessLogo': null,
              'isBusiness': false,
              'businessName': null,
              'firstName': profileData?['firstName'] ?? AppLocalizations.of(context)!.tr(''),
              'lastName': profileData?['lastName'] ?? AppLocalizations.of(context)!.tr(''),
            };
          });
          print(
            '✅ Loaded driver profile for $userName with image: ${profilePicUrl != null}',
          );
          return;
        }
      }

      // If driver endpoint fails, try business users endpoint
      response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/business/profile/$userName'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 Business API response for $userName: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final profileData = data['data'];

          // Get profile image and business logo, convert to GCS URLs
          String? profilePicUrl;
          String? businessLogoUrl;

          final profilePic = profileData?['profilePic']?.toString();
          if (profilePic != null && profilePic.isNotEmpty) {
            profilePicUrl = _convertToGcsUrl(profilePic);
            print('🖼️ Business profile pic URL: $profilePicUrl');
          }

          final businessLogo = profileData?['businessLogo']?.toString();
          if (businessLogo != null && businessLogo.isNotEmpty) {
            businessLogoUrl = _convertToGcsUrl(businessLogo);
            print('🖼️ Business logo URL: $businessLogoUrl');
          }

          setState(() {
            _userTypeCache[userName] = {
              'isDriver': false,
              'isUser': true,
              'checkedAt': DateTime.now().toIso8601String(),
              'profilePic': profilePicUrl,
              'businessLogo': businessLogoUrl,
              'isBusiness':
                  profileData?['isBusiness'] == 1 ||
                  profileData?['isBusiness'] == true,
              'businessName': profileData?['businessName'],
              'firstName': profileData?['firstName'] ?? AppLocalizations.of(context)!.tr(''),
              'lastName': profileData?['lastName'] ?? AppLocalizations.of(context)!.tr(''),
            };
          });
          print(
            '✅ Loaded business profile for $userName with image: ${profilePicUrl != null || businessLogoUrl != null}',
          );
          return;
        }
      }

      // If both fail, set default
      print('⚠️ Could not load profile for $userName from either endpoint');
      setState(() {
        _userTypeCache[userName] = {
          'isDriver': false,
          'isUser': true,
          'checkedAt': DateTime.now().toIso8601String(),
          'profilePic': null,
          'businessLogo': null,
          'isBusiness': false,
          'businessName': null,
          'firstName': '',
          'lastName': '',
        };
      });
    } catch (e) {
      print('❌ Error checking user type for $userName: $e');
      // Cache as business user if check fails
      setState(() {
        _userTypeCache[userName] = {
          'isDriver': false,
          'isUser': true,
          'checkedAt': DateTime.now().toIso8601String(),
          'profilePic': null,
          'businessLogo': null,
          'isBusiness': false,
          'businessName': null,
          'firstName': '',
          'lastName': '',
        };
      });
    }
  }

  // Toggle pin status for a chat
  void _togglePinChat(String conversationId) {
    setState(() {
      if (_pinnedChats.contains(conversationId)) {
        _pinnedChats.remove(conversationId);
        print('📌 Unpinned chat: $conversationId');
      } else {
        _pinnedChats.add(conversationId);
        print('📌 Pinned chat: $conversationId');
      }
    });
    // Save to local storage
    _savePinnedChats();
  }

  // Show delete chat confirmation dialog
  Future<bool> _showDeleteChatConfirmation(
    String userName,
    bool isLight,
  ) async {
    return await TradeRepublicBottomSheet.show<bool>(
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
                      color: isLight ? Colors.black : Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)?.deleteChat ?? AppLocalizations.of(context)!.tr('Delete Chat'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isLight ? Colors.black : Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Content
                Text(
                  'Are you sure you want to delete the chat with $userName? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: isLight ? Colors.black : Colors.white,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 24),

                // Buttons Row - Trade Republic Style
                Row(
                  children: [
                    // Cancel button
                    Expanded(
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
                        isSecondary: true,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(false);
                        },
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Delete button
                    Expanded(
                      child: TradeRepublicButton(
                        label: AppLocalizations.of(context)?.delete ?? AppLocalizations.of(context)!.tr('Delete'),
                        isDestructive: true,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(true);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  // Delete chat with specific user
  Future<void> _deleteChatWithUser(String userName) async {
    try {
      // Remove from local conversations - use dynamic currentUser
      setState(() {
        messages.removeWhere((msg) {
          String sender = msg['sender'] ?? AppLocalizations.of(context)!.tr('');
          String receiver = msg['receiver'] ?? AppLocalizations.of(context)!.tr('');
          String senderLower = sender.toLowerCase();
          String receiverLower = receiver.toLowerCase();

          bool senderIsCurrentUser = currentUserVariations.any(
            (v) => v.toLowerCase() == senderLower,
          );
          bool receiverIsCurrentUser = currentUserVariations.any(
            (v) => v.toLowerCase() == receiverLower,
          );

          return (sender == userName || receiver == userName) ||
              (senderIsCurrentUser && receiver == userName) ||
              (sender == userName && receiverIsCurrentUser);
        });
        conversations = _getUniqueConversations();
      });

      // Show success message
      TopNotification.success(
        context,
        '${AppLocalizations.of(context)?.chatDeleted ?? AppLocalizations.of(context)!.tr('Chat Deleted')} - $userName',
      );

      // Optional: Also delete from server
      // await _deleteUserMessagesFromServer(userName);
    } catch (e) {
      print('❌ Error deleting chat: $e');

      TopNotification.error(
        context,
        '${AppLocalizations.of(context)?.errorDeletingChatWith ?? AppLocalizations.of(context)!.tr('Error deleting chat with')} "$userName"',
      );
    }
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
  static const _historyPrefsKey = 'cully_ai_chat_history_business';
  final AppSettings _appSettings = AppSettings();
  final List<Map<String, String>> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  int? _animatingIndex;
  final Set<int> _newBubbleIndices = {};
  String? _username;
  @override
  void initState() {
    super.initState();
    _loadUsername();
    _loadCullyMessages();
  }

  // Save CullyAI messages to local storage
  Future<void> _saveCullyMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _messages.length > 100
          ? _messages.sublist(_messages.length - 100)
          : List<Map<String, String>>.from(_messages);
      final messagesJson = jsonEncode(toSave);
      await prefs.setString(_historyPrefsKey, messagesJson);
      print('💾 CullyAI messages saved: ${_messages.length} messages');
    } catch (e) {
      print('❌ Error saving Cully messages: $e');
    }
  }

  // Load CullyAI messages from local storage
  Future<void> _loadCullyMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = prefs.getString(_historyPrefsKey);
      if (messagesJson != null) {
        final List<dynamic> decoded = jsonDecode(messagesJson);
        final history = decoded
            .map((m) => Map<String, String>.from(m as Map))
            .toList();
        setState(() {
          _messages.clear();
          _messages.addAll(
            history.length > 100
                ? history.sublist(history.length - 100)
                : history,
          );
        });
        print('📦 Loaded ${_messages.length} CullyAI messages from local');
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      print('❌ Error loading Cully messages: $e');
    }
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUsername = prefs.getString('username');
    if (mounted) {
      setState(() {
        _username = _normalizeUsername(rawUsername);
      });
    }
  }

  String _normalizeUsername(String? username) {
    final value = (username ?? AppLocalizations.of(context)!.tr('')).trim();
    if (value.isEmpty) return '';
    return value.startsWith('@') ? value : '@$value';
  }

  Future<void> _clearCullyMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyPrefsKey);

    if (!mounted) return;
    setState(() {
      _messages.clear();
      _newBubbleIndices.clear();
      _animatingIndex = null;
    });

    TopNotification.success(
      context,
      AppLocalizations.of(context)?.deleted ?? AppLocalizations.of(context)!.tr('Chat history deleted'),
    );
  }

  void _confirmClearCullyMessages() {
    TradeRepublicBottomSheet.show<bool>(
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
                color: widget.isLight ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                AppLocalizations.of(context)?.deleteChat ?? AppLocalizations.of(context)!.tr('Delete Chat'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isLight ? Colors.black : Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(context)?.thisActionCannotBeUndone ?? AppLocalizations.of(context)!.tr('This action cannot be undone.'),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: (widget.isLight ? Colors.black : Colors.white).withOpacity(
                0.7,
              ),
            ),
          ),
          const SizedBox(height: 24),
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.delete ?? AppLocalizations.of(context)!.tr('Delete'),
            onPressed: () async {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop(true);
              await _clearCullyMessages();
            },
            backgroundColor: const Color(0xFFFF3B30),
            foregroundColor: Colors.white,
            width: double.infinity,
          ),
          const SizedBox(height: 10),
          TradeRepublicButton(
            label: AppLocalizations.of(context)?.cancel ?? AppLocalizations.of(context)!.tr('Cancel'),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop(false);
            },
            isSecondary: true,
            width: double.infinity,
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
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
    await _saveCullyMessages(); // Save user message immediately

    try {
      final prior = _messages.sublist(0, _messages.length - 1);
      final history = _messages.length > 1
          ? (prior.length > 10 ? prior.sublist(prior.length - 10) : prior)
                .map((m) => {'role': m['role']!, 'text': m['text']!})
                .toList()
          : <Map<String, String>>[];

      final prefs2 = await SharedPreferences.getInstance();
      final selectedLang = prefs2.getString('selected_language') ?? AppLocalizations.of(context)!.tr('System');
      final langCode = selectedLang == 'System'
          ? Localizations.localeOf(context).languageCode
          : selectedLang.split('_').first;
      final token = prefs2.getString('auth_token');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/delvioo/cully-ai/chat'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'message': text,
              'username': _normalizeUsername(_username),
              'history': history,
              'language': langCode,
              'currency': _appSettings.currencySymbol,
              'assistant_mode': 'business',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['reply'] as String? ??
          (AppLocalizations.of(context)?.aiNoResponse ?? AppLocalizations.of(context)!.tr(''));
        setState(() {
          _newBubbleIndices.add(_messages.length);
          _messages.add({'role': 'model', 'text': reply});
          _isLoading = false;
          _animatingIndex = _messages.length - 1;
        });
        await _saveCullyMessages(); // Save after successful response
      } else {
        // Parse error details from backend
        String errorMessage = 'Error ${response.statusCode}. Please try again.';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['details'] != null) {
            errorMessage = 'Error: ${errorData['details']}';
            print('🔴 Backend error details: ${errorData['details']}');
          }
        } catch (e) {
          print('🔴 Could not parse error response: $e');
        }

        setState(() {
          _newBubbleIndices.add(_messages.length);
          _messages.add({'role': 'model', 'text': errorMessage});
          _isLoading = false;
          _animatingIndex = _messages.length - 1;
        });
        await _saveCullyMessages(); // Save even on error
      }
    } catch (e) {
      print('🔴 Network error: $e');
      setState(() {
        _newBubbleIndices.add(_messages.length);
        _messages.add({
          'role': 'model',
          'text': 'Network error: ${e.toString()}',
        });
        _isLoading = false;
        _animatingIndex = _messages.length - 1;
      });
      await _saveCullyMessages(); // Save even on network error
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
    // Solid surface so the page never appears empty / black-on-black.
    final bg = isLight ? Colors.white : Colors.black;
    final cardBg = isLight ? Colors.white : const Color(0xFF0A0A0A);
    final textColor = isLight ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      // Note: CupertinoPageRoute already animates the page in. Adding another
      // FadeTransition on top can leave the screen blank for ~500ms, which the
      // user perceived as a permanent black screen.
      body: SafeArea(
        child: LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = constraints.maxWidth;
                final isDesktop = screenWidth >= 960;
                final shellMaxWidth = isDesktop ? 1100.0 : double.infinity;
                final chatMaxWidth = isDesktop ? 760.0 : screenWidth;

                final content = Column(
                  children: [
                    _buildHeader(isLight, textColor, isDesktop: isDesktop),
                    TradeRepublicDivider(color: textColor.withOpacity(0.06)),
                    Expanded(
                      child: _messages.isEmpty
                          ? _buildWelcome(textColor, maxWidth: chatMaxWidth)
                          : Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: chatMaxWidth,
                                ),
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isDesktop ? 24 : 16,
                                    vertical: isDesktop ? 20 : 12,
                                  ),
                                  itemCount:
                                      _messages.length + (_isLoading ? 1 : 0),
                                  itemBuilder: (context, i) {
                                    if (i == _messages.length) {
                                      return _buildTypingIndicator(
                                        cardBg,
                                        chatMaxWidth,
                                      );
                                    }
                                    final msg = _messages[i];
                                    return _buildBubble(
                                      msg['text']!,
                                      msg['role'] == 'user',
                                      cardBg,
                                      textColor,
                                      i,
                                      chatMaxWidth,
                                    );
                                  },
                                ),
                              ),
                            ),
                    ),
                    _buildInputBar(
                      isLight,
                      bg,
                      textColor,
                      chatMaxWidth,
                      isDesktop: isDesktop,
                    ),
                  ],
                );

                if (!isDesktop) {
                  return content;
                }

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: shellMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: content,
                    ),
                  ),
                );
              },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isLight, Color textColor, {bool isDesktop = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 16,
        vertical: isDesktop ? 18 : 12,
      ),
      child: Row(
        children: [
          TradeRepublicButton.icon(
            icon: Icon(CupertinoIcons.back, color: textColor, size: 20),
            size: isDesktop ? 44 : 40,
            backgroundColor: isLight
                ? Colors.transparent
                : Colors.transparent,
            foregroundColor: textColor,
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              isLight ? 'logo/cully_light.png' : 'logo/cully_dark.png',
              width: isDesktop ? 44 : 40,
              height: isDesktop ? 44 : 40,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isDesktop ? 18 : 16,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                Row(
                  children: [
                    const _PulsingDot(),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        AppLocalizations.of(context)?.online ?? AppLocalizations.of(context)!.tr('Online'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor.withOpacity(0.55),
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TradeRepublicButton.icon(
            icon: Icon(CupertinoIcons.trash, color: textColor, size: 19),
            size: isDesktop ? 44 : 40,
            backgroundColor: isLight
                ? Colors.transparent
                : Colors.transparent,
            foregroundColor: textColor,
            onPressed: () {
              HapticFeedback.lightImpact();
              _confirmClearCullyMessages();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome(Color textColor, {double? maxWidth}) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (maxWidth ?? 680) * 0.9),
        child: _AnimatedWelcome(textColor: textColor, isLight: widget.isLight),
      ),
    );
  }

  Widget _buildBubble(
    String text,
    bool isUser,
    Color cardBg,
    Color textColor,
    int index,
    double availableWidth,
  ) {
    // Trade Republic flat bubble style:
    // - User: solid accent (black on light, white on dark) with inverse text
    // - AI:   subtle 5% accent overlay, fully flat, symmetric corners
    final isLight = widget.isLight;
    final accent = isLight ? Colors.black : Colors.white;
    final inverse = isLight ? Colors.white : Colors.black;
    // Bumped contrast so AI bubbles are clearly visible on the theme bg.
    final aiBg = accent.withOpacity(isLight ? 0.06 : 0.14);
    final userText = inverse;
    final aiText = textColor;

    final bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: availableWidth > 820
              ? 620
              : availableWidth * (availableWidth > 600 ? 0.72 : 0.78),
        ),
        decoration: BoxDecoration(
          color: isUser ? accent : aiBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: (index == _animatingIndex && !isUser)
            ? TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.98, end: 1.0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  alignment: Alignment.centerLeft,
                  child: child,
                ),
                child: _TypewriterText(
                  text: text,
                  style: TextStyle(
                    fontSize: 15,
                    color: aiText,
                    height: 1.4,
                    letterSpacing: -0.1,
                  ),
                  onDone: () {
                    if (mounted) setState(() => _animatingIndex = null);
                  },
                ),
              )
            : Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: isUser ? userText : aiText,
                  height: 1.4,
                  letterSpacing: -0.1,
                  fontWeight: FontWeight.w500,
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

  Widget _buildTypingIndicator(Color cardBg, double availableWidth) {
    final isLight = widget.isLight;
    final accent = isLight ? Colors.black : Colors.white;
    final aiBg = accent.withOpacity(isLight ? 0.06 : 0.14);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: availableWidth > 820
              ? 620
              : availableWidth * (availableWidth > 600 ? 0.72 : 0.78),
        ),
        decoration: BoxDecoration(
          color: aiBg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _AiDot(delay: i * 200)),
            ),
            const SizedBox(height: 6),
            _ThinkingText(isLight: widget.isLight),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(
    bool isLight,
    Color cardBg,
    Color textColor,
    double maxWidth, {
    bool isDesktop = false,
  }) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Container(
      padding: EdgeInsets.only(
        left: isDesktop ? 24 : 16,
        right: isDesktop ? 24 : 16,
        top: isDesktop ? 16 : 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + (isDesktop ? 18 : 8),
      ),
      decoration: BoxDecoration(
        color: cardBg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TradeRepublicTextField(
                  controller: _inputController,
                  hintText:
                      AppLocalizations.of(context)?.messageCullyAi ?? AppLocalizations.of(context)!.tr('Message CullyAI…'),
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              if (!keyboardOpen) ...[
                const SizedBox(width: 10),
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  scale: _isLoading ? 0.96 : 1.0,
                  child: TradeRepublicButton.icon(
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              key: const ValueKey('cully_loading'),
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isLight ? Colors.white : Colors.black,
                              ),
                            )
                          : Icon(
                              CupertinoIcons.arrow_up,
                              key: const ValueKey('cully_send'),
                              color: isLight ? Colors.white : Colors.black,
                              size: 20,
                            ),
                    ),
                    size: 50,
                    backgroundColor: isLight ? Colors.black : Colors.white,
                    foregroundColor: isLight ? Colors.white : Colors.black,
                    onPressed: _isLoading ? null : _sendMessage,
                  ),
                ),
              ],
            ],
          ),
        ),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final accent = isLight ? Colors.black : Colors.white;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.25 + 0.5 * _anim.value),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _ThinkingText extends StatefulWidget {
  final bool isLight;
  const _ThinkingText({required this.isLight});

  @override
  State<_ThinkingText> createState() => _ThinkingTextState();
}

class _ThinkingTextState extends State<_ThinkingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.45,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isLight ? Colors.black : Colors.white;
    return FadeTransition(
      opacity: _opacity,
      child: Text(
        'Cully is thinking…',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textColor.withOpacity(0.55),
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
                      AppLocalizations.of(context)!.tr("Hi, I'm CullyAI!"),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: widget.textColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _fades[2],
              child: SlideTransition(
                position: _slides[2],
                child: Text(
                  AppLocalizations.of(context)?.askMeAnythingDelvioo ?? AppLocalizations.of(context)!.tr('Ask me anything — orders, deliveries, or just chat.'),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: (isLight ? Colors.black : Colors.white).withOpacity(0.55),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}