import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Today's weather, reduced to what the briefing needs.
class WeatherReport {
  const WeatherReport({
    required this.now,
    required this.min,
    required this.max,
    required this.code,
    this.rainChance,
  });

  final double now, min, max;
  final int? rainChance;

  /// WMO weather code of the day.
  final int code;

  /// Short, speakable phrase for [code].
  String get description {
    if (code == 0) return 'clear';
    if (code == 1) return 'mostly clear';
    if (code == 2) return 'partly cloudy';
    if (code == 3) return 'overcast';
    if (code == 45 || code == 48) return 'foggy';
    if (code >= 51 && code <= 57) return 'drizzly';
    if (code >= 61 && code <= 67) return 'rainy';
    if (code >= 71 && code <= 77) return 'snowy';
    if (code >= 80 && code <= 82) return 'showery';
    if (code == 85 || code == 86) return 'snowy with showers';
    if (code >= 95 && code <= 99) return 'stormy';
    return 'unsettled';
  }

  /// Parses an Open-Meteo forecast response; null if anything essential is missing.
  static WeatherReport? parse(Map<String, dynamic> json) {
    try {
      final cur = json['current'] as Map<String, dynamic>;
      final daily = json['daily'] as Map<String, dynamic>;
      double d(String k) => ((daily[k] as List).first as num).toDouble();
      final rain = (daily['precipitation_probability_max'] as List?)?.firstOrNull;
      return WeatherReport(
        now: (cur['temperature_2m'] as num).toDouble(),
        max: d('temperature_2m_max'),
        min: d('temperature_2m_min'),
        rainChance: (rain as num?)?.round(),
        code: ((daily['weather_code'] as List).first as num).toInt(),
      );
    } catch (e) {
      debugPrint('WeatherReport.parse failed: $e');
      return null;
    }
  }
}

/// Open-Meteo client (free, no API key). Never throws; null = unavailable.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();
  static final WeatherService instance = WeatherService();

  final http.Client _client;
  static const _timeout = Duration(seconds: 6);
  static const _ttl = Duration(minutes: 30);
  final Map<String, ({DateTime at, WeatherReport report})> _cache = {};

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final r = await _client.get(uri).timeout(_timeout);
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('WeatherService request failed: $e');
      return null;
    }
  }

  Future<({double lat, double lon, String label})?> geocode(String city) async {
    final name = city.trim();
    if (name.isEmpty) return null;
    final j = await _getJson(Uri.https('geocoding-api.open-meteo.com',
        '/v1/search', {'name': name, 'count': '1', 'language': 'en', 'format': 'json'}));
    try {
      final r = (j?['results'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (r == null) return null;
      final n = r['name'] as String? ?? name;
      final c = r['country'] as String?;
      return (
        lat: (r['latitude'] as num).toDouble(),
        lon: (r['longitude'] as num).toDouble(),
        label: c == null || c.isEmpty ? n : '$n, $c',
      );
    } catch (e) {
      debugPrint('WeatherService.geocode parse failed: $e');
      return null;
    }
  }

  Future<WeatherReport?> today(double lat, double lon) async {
    final key = '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) return hit.report;
    final j = await _getJson(Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'temperature_2m,weather_code',
      'daily': 'temperature_2m_max,temperature_2m_min,'
          'precipitation_probability_max,weather_code',
      'timezone': 'auto',
      'forecast_days': '1',
    }));
    final report = j == null ? null : WeatherReport.parse(j);
    if (report != null) _cache[key] = (at: DateTime.now(), report: report);
    return report;
  }
}
