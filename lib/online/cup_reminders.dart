import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'cup_logic.dart';

/// Old payloads were a bare cup id; new ones are entries ('cup:<id>', 'cupmatch:<cup>:<match>').
String cupEntryOf(String payload) => payload.startsWith('cup:') || payload.startsWith('cupmatch:') ? payload : 'cup:$payload';

/// Device-local notifications for cups (v0.7.0):
///  * the 10-minute check-in alarm is scheduled with the OS (zonedSchedule) for EVERY upcoming cup the player is in:
///    on app start / sign-in ([CupAlerts.syncReminders]), on registration / approval and whenever a cup page loads;
///  * "draw done" / "your match is ready" are shown immediately ([showNow]) while the app is in the background;
///  * tapping one deep-links: payload 'cup:<cupId>' opens the cup page, 'cupmatch:<cupId>:<matchId>' enters the match.
/// No FCM credentials exist in this project, so a fully closed app only gets the pre-scheduled 10-minute alarm.
class CupReminderService {
  CupReminderService._();
  static final i = CupReminderService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Map<String, int> _scheduled = {};
  bool _ready = false, _requestedPermission = false;
  void Function(String entry)? _open;

  /// [open] receives an entry: 'cup:<id>' or 'cupmatch:<cupId>:<matchId>'.
  Future<void> init(void Function(String entry) open) async {
    if (_ready) {
      _open = open;
      return;
    }
    _open = open;
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null && id.isNotEmpty) _open?.call(cupEntryOf(id));
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final launchCup = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && launchCup != null && launchCup.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open?.call(cupEntryOf(launchCup)));
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'cup_live',
      'مسابقه‌های تورنمنت',
      description: 'قرعه‌کشی انجام شد و مسابقه‌ات آماده است',
      importance: Importance.max,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'cup_reminders',
      'یادآور تورنمنت',
      description: 'یادآوری ده دقیقه پیش از شروع و اعلام حضور',
      importance: Importance.high,
    ));
    _ready = true;
  }

  int _id(String value) {
    var h = 0x811c9dc5;
    for (final c in value.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h == 0 ? 1 : h;
  }

  Future<void> sync({required String cupId, required String name, required DateTime startsAt, required bool eligible}) async {
    if (!_ready || cupId.isEmpty) return;
    final at = startsAt.toUtc().subtract(const Duration(minutes: kCupReminderMinutes));
    if (!eligible || !at.isAfter(DateTime.now().toUtc())) {
      await cancel(cupId);
      return;
    }
    final epoch = at.millisecondsSinceEpoch;
    if (_scheduled[cupId] == epoch) return;
    if (!_requestedPermission) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final allowed = await android?.requestNotificationsPermission();
      _requestedPermission = true;
      if (allowed == false) return;
    }
    await _plugin.zonedSchedule(
      _id(cupId),
      '۱۰ دقیقه تا شروع تورنمنت',
      '«$name» نزدیک است؛ وارد صفحه شو و اعلام حضور کن.',
      tz.TZDateTime.from(at, tz.UTC),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'cup_reminders',
          'یادآور تورنمنت',
          channelDescription: 'یادآوری ده دقیقه پیش از شروع و اعلام حضور',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'cup:$cupId',
    );
    _scheduled[cupId] = epoch;
  }

  /// Immediate notification (draw done, match ready) with a deep-link payload.
  Future<void> showNow(String key, String title, String? body, String payload) async {
    if (!_ready) return;
    await _plugin.show(
      _id('now:$key'),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails('cup_live', 'مسابقه‌های تورنمنت',
            channelDescription: 'قرعه‌کشی انجام شد و مسابقه‌ات آماده است', importance: Importance.max, priority: Priority.max,
            category: AndroidNotificationCategory.event),
      ),
      payload: payload,
    );
  }

  /// Cups scheduled in this process (for tests / diagnostics).
  Map<String, int> get scheduled => Map.unmodifiable(_scheduled);

  Future<void> cancel(String cupId) async {
    if (!_ready || cupId.isEmpty) return;
    _scheduled.remove(cupId);
    await _plugin.cancel(_id(cupId));
  }
}
