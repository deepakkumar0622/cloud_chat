import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/models/message_model.dart';
import 'chat_date_separator.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMoreMessages,
    required this.error,
    required this.emptyBuilder,
    required this.onLoadMore,
    required this.itemBuilder,
  });

  final List<MessageModel> messages;
  final ScrollController scrollController;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMoreMessages;
  final String? error;
  final WidgetBuilder emptyBuilder;
  final VoidCallback onLoadMore;
  final Widget Function(MessageModel message) itemBuilder;

  void _checkIfMoreMessagesNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients ||
          !hasMoreMessages ||
          isLoading ||
          isLoadingMore) {
        return;
      }

      final position = scrollController.position;

      // If the messages don't fill the screen, load another page.
      // Also handles reaching the older-message end.
      if (position.hasContentDimensions && position.extentAfter <= 200) {
        onLoadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7568F5)),
      );
    }

    if (error != null) {
      return const Center(
        child: Text(
          'Unable to load messages.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    if (messages.isEmpty) {
      return emptyBuilder(context);
    }

    // Check after layout so we know whether the list is scrollable.
    _checkIfMoreMessagesNeeded();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Load only when the user actually scrolls.
        if (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle &&
            notification.metrics.extentAfter <= 200 &&
            hasMoreMessages &&
            !isLoadingMore &&
            !isLoading) {
          onLoadMore();
        }

        return false;
      },
      child: ListView.builder(
        controller: scrollController,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        itemCount: messages.length + (isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF7568F5),
                  ),
                ),
              ),
            );
          }

          final messageIndex = messages.length - 1 - index;
          final message = messages[messageIndex];
          final date = message.createdAt;

          var showDate = false;

          if (date != null) {
            if (messageIndex == 0) {
              showDate = true;
            } else {
              final olderDate = messages[messageIndex - 1].createdAt;

              showDate =
                  olderDate == null ||
                  !DateUtils.isSameDay(date.toLocal(), olderDate.toLocal());
            }
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDate) ChatDateSeparator(date: date!),
              itemBuilder(message),
            ],
          );
        },
      ),
    );
  }
}
