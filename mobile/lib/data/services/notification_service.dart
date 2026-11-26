import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local Android notifications for new drafts, conflicts, expiring drafts, and
/// collection failures. Notifications NEVER trigger automatic X publishing.
class CinePulseNotificationService {
  CinePulseNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));
    _initialized = true;
  }

  Future<void> notifyAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'cinepulse_alerts',
        'CinePulse Box-Office Alerts',
        channelDescription:
            'Notifications for pending drafts, source conflicts, and collection status.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    await _plugin.show(id, title, body, details);
  }
}
