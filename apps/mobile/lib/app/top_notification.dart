import 'dart:async';
import 'package:flutter/material.dart';

final _notice = ValueNotifier<({String message, bool? success})?>(null);
Timer? _noticeTimer;

void showTopNotification(String message, {bool? success}) {
  _noticeTimer?.cancel();
  _notice.value = (message: message, success: success);
  _noticeTimer = Timer(const Duration(seconds: 4), () => _notice.value = null);
}

class TopNotificationHost extends StatelessWidget {
  const TopNotificationHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(children: [
        child,
        Positioned(
          top: 0,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: ValueListenableBuilder(
              valueListenable: _notice,
              builder: (context, notice, _) => notice == null
                  ? const SizedBox.shrink()
                  : Semantics(
                      liveRegion: true,
                      child: Material(
                          elevation: 8,
                          color: const Color(0xff263244),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                              child: Row(children: [
                                Icon(
                                    notice.success == false
                                        ? Icons.error_outline
                                        : Icons.notifications_outlined,
                                    color: notice.success == false
                                        ? Colors.redAccent
                                        : Colors.amber),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(notice.message,
                                        style: const TextStyle(
                                            color: Colors.white))),
                                IconButton(
                                    key: const ValueKey(
                                        'dismiss-top-notification'),
                                    onPressed: () {
                                      _noticeTimer?.cancel();
                                      _notice.value = null;
                                    },
                                    icon: const Icon(Icons.close,
                                        semanticLabel: 'Dismiss notification',
                                        color: Colors.white70)),
                              ]))),
                    ),
            ),
          ),
        ),
      ]);
}
