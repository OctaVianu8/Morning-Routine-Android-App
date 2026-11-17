import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

class DayEvent {
  const DayEvent({required this.title, required this.start, this.allDay = false});
  final String title;
  final DateTime start;
  final bool allDay;
}

/// Outcome of asking for calendar access. [blocked] means the system will not
/// show its dialog (again); the user has to allow it in the app settings.
enum CalendarAccess { granted, denied, blocked, error }

/// Read-only access to today's device-calendar events. Never throws.
class CalendarService {
  CalendarService._();
  static final CalendarService instance = CalendarService._();

  static const _channel = MethodChannel('morning_glory/calendar');
  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// On Android the permission is handled by the app itself (MainActivity):
  /// the plugin's own permission calls refuse to work unless WRITE_CALENDAR is
  /// declared too, and this app only reads. Reading events through the plugin
  /// needs READ_CALENDAR alone.
  Future<bool> hasPermission() async {
    try {
      if (_android) return await _channel.invokeMethod<bool>('has') ?? false;
      return await DeviceCalendar.instance.hasPermissions() ==
          CalendarPermissionStatus.granted;
    } catch (e) {
      debugPrint('CalendarService.hasPermission failed: $e');
      return false;
    }
  }

  Future<CalendarAccess> requestPermission() async {
    try {
      if (_android) {
        return switch (await _channel.invokeMethod<String>('request')) {
          'granted' => CalendarAccess.granted,
          'blocked' => CalendarAccess.blocked,
          _ => CalendarAccess.denied,
        };
      }
      final status = await DeviceCalendar.instance.requestPermissions();
      if (status == CalendarPermissionStatus.granted) return CalendarAccess.granted;
      // iOS never re-prompts after a refusal.
      return status == CalendarPermissionStatus.denied
          ? CalendarAccess.blocked
          : CalendarAccess.denied;
    } catch (e) {
      debugPrint('CalendarService.requestPermission failed: $e');
      return CalendarAccess.error;
    }
  }

  /// Asks for access and tells the user what happened when it was not granted.
  /// Returns whether access is now available.
  Future<bool> connect(ScaffoldMessengerState messenger) async {
    final r = await requestPermission();
    switch (r) {
      case CalendarAccess.granted:
        return true;
      case CalendarAccess.blocked:
        messenger.showSnackBar(SnackBar(
          content: const Text('Calendar access is blocked. Allow it in the app settings.'),
          action: SnackBarAction(label: 'Open settings', onPressed: openAppSettings),
        ));
      case CalendarAccess.denied:
        messenger.showSnackBar(
            const SnackBar(content: Text('Calendar permission was not granted.')));
      case CalendarAccess.error:
        messenger.showSnackBar(
            const SnackBar(content: Text("Couldn't ask for calendar access. Try again.")));
    }
    return false;
  }

  /// Events from now to the end of today (in progress and all-day included).
  /// Does not prompt for permission.
  Future<List<DayEvent>> todayEvents() async {
    try {
      if (!await hasPermission()) return [];
      final now = DateTime.now();
      final end = DateTime(now.year, now.month, now.day + 1);
      final startOfDay = DateTime(now.year, now.month, now.day);
      // Query from midnight so all-day events (which start at 00:00) are found.
      final events = await DeviceCalendar.instance.listEvents(startOfDay, end);
      final seen = <String>{};
      final out = <DayEvent>[];
      for (final e in events) {
        if (e.isAllDay ? !e.endDate.isAfter(startOfDay) : !e.endDate.isAfter(now)) {
          continue;
        }
        final title = e.title.trim();
        if (!seen.add('$title|${e.startDate.millisecondsSinceEpoch}')) continue;
        out.add(DayEvent(
            title: title.isEmpty ? 'Untitled event' : title,
            start: e.startDate,
            allDay: e.isAllDay));
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      return out;
    } catch (e) {
      debugPrint('CalendarService.todayEvents failed: $e');
      return [];
    }
  }
}
