import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/shared/screens/notifications_screen.dart'; // To get NotificationItem and NotificationType
import '../services/notification_service.dart';

final notificationsProvider =
    NotifierProvider<NotificationNotifier, List<NotificationItem>>(() {
  return NotificationNotifier();
});

class NotificationNotifier extends Notifier<List<NotificationItem>> {
  static const _prefsKey = 'user_notifications';

  @override
  List<NotificationItem> build() {
    _load();
    _listenToFCM();
    return [];
  }

  void _listenToFCM() {
    NotificationService.instance.messageStreamController.stream.listen((message) {
      final notification = message.notification;
      if (notification != null) {
        addNotification(
          title: notification.title ?? 'Farmaa Update',
          body: notification.body ?? '',
          type: NotificationType.general,
        );
      }
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_prefsKey);
    if (jsonList == null) return;

    final List<NotificationItem> loadedItems = [];
    for (final jsonStr in jsonList) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        loadedItems.add(NotificationItem(
          id: map['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          title: map['title'] ?? '',
          body: map['body'] ?? '',
          type: NotificationType.values.firstWhere(
            (e) => e.toString() == map['type'],
            orElse: () => NotificationType.general,
          ),
          receivedAt: DateTime.tryParse(map['receivedAt'] ?? '') ?? DateTime.now(),
          isRead: map['isRead'] ?? false,
        ));
      } catch (e) {
        // Skip corrupted data
      }
    }
    
    // Sort newly received first
    loadedItems.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    state = loadedItems;
  }

  Future<void> _save(List<NotificationItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = items.map((i) {
      return jsonEncode({
        'id': i.id,
        'title': i.title,
        'body': i.body,
        'type': i.type.toString(),
        'receivedAt': i.receivedAt.toIso8601String(),
        'isRead': i.isRead,
      });
    }).toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }

  Future<void> addNotification({
    required String title,
    required String body,
    NotificationType type = NotificationType.general,
  }) async {
    final newItem = NotificationItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      type: type,
      receivedAt: DateTime.now(),
      isRead: false,
    );

    final updatedMap = [newItem, ...state];
    state = updatedMap;
    await _save(updatedMap);
  }

  Future<void> markAllAsRead() async {
    final updatedMap = state.map((i) {
      return NotificationItem(
        id: i.id,
        title: i.title,
        body: i.body,
        type: i.type,
        receivedAt: i.receivedAt,
        isRead: true,
      );
    }).toList();
    state = updatedMap;
    await _save(updatedMap);
  }

  Future<void> markAsRead(String id) async {
    final updatedMap = state.map((i) {
      if (i.id == id) {
        return NotificationItem(
          id: i.id,
          title: i.title,
          body: i.body,
          type: i.type,
          receivedAt: i.receivedAt,
          isRead: true,
        );
      }
      return i;
    }).toList();
    state = updatedMap;
    await _save(updatedMap);
  }

  Future<void> clearAll() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
