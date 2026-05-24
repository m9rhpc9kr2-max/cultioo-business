import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/services/app_settings.dart';
import '../../../shared/services/app_localizations.dart';
import '../../../config/api_config.dart';
import '../../../shared/widgets/trade_republic_text_field.dart';
import '../../../shared/widgets/trade_republic_button.dart';
import '../../../shared/widgets/trade_republic_card.dart';
import '../../../shared/widgets/cultioo_spinner.dart';
import '../../../shared/widgets/trade_republic_tap.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

class ChatViewPage extends StatefulWidget {
  final String otherPerson;
  final List<Map<String, dynamic>> messages;
  final Function(String) onSendMessage;
  final int? orderId;

  const ChatViewPage({
    super.key,
    required this.otherPerson,
    required this.messages,
    required this.onSendMessage,
    this.orderId,
  });

  @override
  State<ChatViewPage> createState() => _ChatViewPageState();
}

class _ChatViewPageState extends State<ChatViewPage> {
  final AppSettings _appSettings = AppSettings();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _allMessages = [];
  bool _isLoadingMessages = false;

  @override
  void initState() {
    super.initState();
    _allMessages = List.from(widget.messages);

    // Load complete chat history if we have an order ID
    if (widget.orderId != null) {
      _loadCompleteChat();
    }

    // Scroll to bottom when opening chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadCompleteChat() async {
    if (widget.orderId == null) return;

    setState(() {
      _isLoadingMessages = true;
    });

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/messages/orders/${widget.orderId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['messages'] != null) {
          setState(() {
            _allMessages = List<Map<String, dynamic>>.from(data['messages']);
          });

          // Scroll to bottom after loading messages
          Future.delayed(const Duration(milliseconds: 100), () {
            _scrollToBottom();
          });
        }
      }
    } catch (e) {
      print('Error loading complete chat: $e');
    } finally {
      setState(() {
        _isLoadingMessages = false;
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = _appSettings.isLightMode(context);
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : Colors.black,
      appBar: AppBar(
        toolbarHeight: isDesktop ? 68 : kToolbarHeight,
        leading: TradeRepublicButton.icon(
          icon: const Icon(CupertinoIcons.back),
          size: 40,
          isSecondary: true,
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: isDesktop ? 44 : 40,
              height: isDesktop ? 44 : 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withOpacity(0.8),
                    Colors.pink.withOpacity(0.8),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  widget.otherPerson.isNotEmpty
                      ? widget.otherPerson[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherPerson,
                    style: TextStyle(
                      color: isLight ? Colors.black : Colors.white,
                      fontSize: isDesktop ? 20 : 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${_allMessages.length} messages',
                    style: TextStyle(
                      color: (isLight ? Colors.black : Colors.white)
                          .withOpacity(0.6),
                      fontSize: isDesktop ? 13 : 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 980 : double.infinity,
          ),
          child: Column(
            children: [
              Expanded(
                child: _isLoadingMessages
                    ? const Center(child: CultiooLoadingIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 24 : 16,
                          vertical: isDesktop ? 20 : 16,
                        ),
                        itemCount: _allMessages.length,
                        itemBuilder: (context, index) {
                          final message = _allMessages[index];
                          return _buildMessageBubble(
                            message,
                            isLight,
                            isDesktop: isDesktop,
                          );
                        },
                      ),
              ),
              _buildMessageInput(isLight, isDesktop: isDesktop),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _orderChatFileCandidates(Map<String, dynamic> message) {
    final raw = (message['file_url'] ?? message['fileUrl'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty) return const [];
    return ApiConfig.getImageUrlCandidates(raw);
  }

  Widget _orderChatImagePreview(List<String> candidates) {
    Widget buildAt(int index) {
      if (index >= candidates.length) {
        return Icon(
          CupertinoIcons.photo,
          size: 48,
          color: Colors.white.withOpacity(0.6),
        );
      }
      final url = candidates[index];
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 200,
        errorBuilder: (_, __, ___) => buildAt(index + 1),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const SizedBox(
            height: 200,
            child: Center(child: CultiooLoadingIndicator()),
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
      child: buildAt(0),
    );
  }

  Widget _buildMessageBubble(
    Map<String, dynamic> message,
    bool isLight, {
    bool isDesktop = false,
  }) {
    final content = message['message'] ?? message['message_text'] ?? '';
    final sender = message['sender'] ??
      (AppLocalizations.of(context)?.unknown ?? '');
    final timestamp = message['sentAt'] ?? message['created_at'] ?? '';
    final isFromMe = sender == 'Arkadiy' || sender == 'Arkadiy1';
    final messageType =
        (message['message_type'] ?? 'text').toString().toLowerCase();
    final candidates = _orderChatFileCandidates(message);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isFromMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isFromMe) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withOpacity(0.8),
                    Colors.pink.withOpacity(0.8),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  sender.isNotEmpty ? sender[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 620 : 340,
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 14 : 12,
                  vertical: isDesktop ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  color: isFromMe
                      ? Colors.blue.withOpacity(0.8)
                      : isLight
                      ? Colors.black.withOpacity(0.05)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(isDesktop ? 16 : 20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (messageType == 'image' && candidates.isNotEmpty) ...[
                      TradeRepublicTap(
                        onTap: () async {
                          final u = Uri.tryParse(candidates.first);
                          if (u != null && await canLaunchUrl(u)) {
                            await launchUrl(u, mode: LaunchMode.inAppBrowserView);
                          }
                        },
                        child: _orderChatImagePreview(candidates),
                      ),
                      if (content.toString().trim().isNotEmpty &&
                          !content.toString().contains('uploads/')) ...[
                        SizedBox(height: DesktopOptimizedWidgets.getSpacing()),
                        Text(
                          content.toString(),
                          style: TextStyle(
                            color: isFromMe
                                ? Colors.white
                                : isLight
                                ? Colors.black
                                : Colors.white,
                            fontSize: isDesktop ? 15 : 14,
                          ),
                        ),
                      ],
                    ] else if (messageType == 'pdf' && candidates.isNotEmpty) ...[
                      TradeRepublicCard.transparent(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius()),
                        onTap: () {
                          unawaited(() async {
                            final u = Uri.tryParse(candidates.first);
                            if (u != null && await canLaunchUrl(u)) {
                              await launchUrl(
                                u,
                                mode: LaunchMode.inAppBrowserView,
                              );
                            }
                          }());
                        },
                        child: Row(
                          children: [
                            const Icon(
                              CupertinoIcons.doc_text_fill,
                              color: Colors.red,
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                content.toString().isNotEmpty
                                    ? content.toString()
                                    : (AppLocalizations.of(context)
                                            ?.tapToViewDetails ??
                                        'Tap to view details'),
                                style: TextStyle(
                                  color: isFromMe
                                      ? Colors.white
                                      : isLight
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: isDesktop ? 15 : 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              CupertinoIcons.arrow_up_right_square,
                              color: isFromMe
                                  ? Colors.white70
                                  : (isLight ? Colors.black54 : Colors.white70),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ] else
                      Text(
                        content.toString(),
                        style: TextStyle(
                          color: isFromMe
                              ? Colors.white
                              : isLight
                              ? Colors.black
                              : Colors.white,
                          fontSize: isDesktop ? 15 : 14,
                        ),
                      ),
                    if (timestamp.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatMessageTime(timestamp),
                        style: TextStyle(
                          color: isFromMe
                              ? Colors.white.withOpacity(0.7)
                              : (isLight ? Colors.black : Colors.white)
                                    .withOpacity(0.5),
                          fontSize: isDesktop ? 11 : 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isFromMe) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 8),
              ),
              child: const Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInput(bool isLight, {bool isDesktop = false}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        isDesktop ? 12 : 16,
        isDesktop ? 24 : 16,
        isDesktop ? 14 : 16,
      ),
      decoration: BoxDecoration(color: isLight ? Colors.white : Colors.black),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 14 : 16),
                decoration: BoxDecoration(
                  color: (isLight ? Colors.black : Colors.white).withOpacity(
                    0.05,
                  ),
                  borderRadius: BorderRadius.circular(isDesktop ? 14 : 20),
                ),
                child: TradeRepublicTextField(
                  controller: _messageController,
                  hintText: AppLocalizations.of(context)?.typeAMessage ?? 'Type a message...',
                  style: TextStyle(
                    color: isLight ? Colors.black : Colors.white,
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TradeRepublicButton.icon(
              icon: Icon(
                CupertinoIcons.arrow_up,
                size: isDesktop ? 16 : 18,
                color: isLight ? Colors.white : Colors.black,
              ),
              size: isDesktop ? 38 : 44,
              onPressed: _messageController.text.trim().isEmpty
                  ? null
                  : () {
                      final message = _messageController.text.trim();
                      setState(() {
                        _allMessages.add({
                          'id': DateTime.now().millisecondsSinceEpoch,
                          'sender': 'Arkadiy',
                          'receiver': widget.otherPerson,
                          'message': message,
                          'sentAt': DateTime.now().toIso8601String(),
                          'isRead': false,
                          'message_type': 'text',
                          'type': 'user',
                        });
                      });

                      widget.onSendMessage(message);
                      _messageController.clear();
                      HapticFeedback.lightImpact();

                      Future.delayed(const Duration(milliseconds: 100), () {
                        _scrollToBottom();
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  String _formatMessageTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}