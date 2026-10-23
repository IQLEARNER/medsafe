import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: 'Open MedSafe'),
    );
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> scheduleMedication({
    required int id,
    required String medicationName,
    required DateTime time,
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    var scheduled = tz.TZDateTime.from(time, tz.local);
    final now = tz.TZDateTime.now(tz.local);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id,
      'Time to take $medicationName',
      'Check it off in MedSafe after taking your dose.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'medication_reminders',
          'Medication reminders',
          channelDescription: 'Daily medication dose reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'medication:$id',
    );
  }

  Future<void> scheduleMissedDoseSummary({
    required int id,
    required String medicationName,
    required TimeOfDayValue time,
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      'Medication check-in',
      'Review any missed doses of $medicationName.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'missed_dose_summary',
          'Missed dose summaries',
          channelDescription: 'End of day medication check-ins',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'summary:$id',
    );
  }

  Future<void> scheduleRefillReminder({
    required int id,
    required String medicationName,
    required DateTime runOutDate,
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    var scheduled = tz.TZDateTime.from(
      runOutDate.subtract(const Duration(days: 7)),
      tz.local,
    );
    final now = tz.TZDateTime.now(tz.local);
    if (!scheduled.isAfter(now)) return;

    await _plugin.zonedSchedule(
      id,
      'Refill needed soon',
      '$medicationName is expected to run out in about one week. Contact the pharmacy or caregiver.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'refill_reminders',
          'Refill reminders',
          channelDescription: 'Medication supply refill reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'refill:$id',
    );
  }

  Future<void> cancelMedication(int id) {
    if (!(Platform.isAndroid || Platform.isIOS)) return Future.value();
    return _plugin.cancel(id);
  }
}

class TimeOfDayValue {
  const TimeOfDayValue(this.hour, this.minute);

  final int hour;
  final int minute;
}
