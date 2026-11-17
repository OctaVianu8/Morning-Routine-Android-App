import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';

class DayEvent {
  const DayEvent({required this.title, required this.start, this.allDay = false});
  final String title;
  final DateTime start;
  final bool allDay;
}

/// Read-only access to today's device-calendar events. Never throws.
class CalendarService {
  CalendarService._();
  static final CalendarService instance = CalendarService._();

  Future<bool> hasPermission() async {
    try {
      return await DeviceCalendar.instance.hasPermissions() ==
          CalendarPermissionStatus.granted;
    } catch (e) {
      debugPrint('CalendarService.hasPermission failed: $e');
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await DeviceCalendar.instance.requestPermissions() ==
          CalendarPermissionStatus.granted;
    } catch (e) {
      debugPrint('CalendarService.requestPermission failed: $e');
      return false;
    }
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
