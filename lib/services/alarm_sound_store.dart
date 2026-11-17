import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Imports user-chosen alarm sounds into app-private persistent storage so the
/// alarm can still find them weeks later (picker results are temp copies).
///
/// Files live in `<documents>/alarm_sounds/` (on Android that is `app_flutter/`,
/// which the alarm plugin also uses as its base for relative paths).
class AlarmSoundStore {
  AlarmSoundStore._();
  static final AlarmSoundStore instance = AlarmSoundStore._();

  static const maxBytes = 30 * 1024 * 1024;
  static const dirName = 'alarm_sounds';

  /// Human-readable reason for the last failed [pickAndImport] (e.g. too big).
  String? lastError;

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, dirName)).create(recursive: true);
  }

  /// Opens the system picker, copies the file into private storage and returns
  /// its new absolute path and original name. Null on cancel or error.
  Future<({String path, String name})?> pickAndImport(int alarmId) async {
    lastError = null;
    File? dest;
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.audio,
        dialogTitle: 'Choose alarm sound',
      );
      if (picked == null) return null;
      final size = picked.lengthSync() ?? await picked.length();
      if (size != null && size > maxBytes) {
        lastError = 'That file is too large (max 30 MB).';
        return null;
      }
      final dir = await _dir();
      final ext = (picked.extension ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      dest = File(p.join(dir.path, '${alarmId}_$stamp${ext.isEmpty ? '' : '.$ext'}'));
      final sink = dest.openWrite();
      var written = 0;
      try {
        await for (final chunk in picked.readAsByteStream()) {
          written += chunk.length;
          if (written > maxBytes) break;
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (written > maxBytes) {
        await _safeDelete(dest);
        lastError = 'That file is too large (max 30 MB).';
        return null;
      }
      if (written == 0) {
        await _safeDelete(dest);
        lastError = 'That file is empty.';
        return null;
      }
      return (path: dest.path, name: picked.name);
    } catch (e) {
      debugPrint('AlarmSoundStore.pickAndImport failed: $e');
      if (dest != null) await _safeDelete(dest);
      return null;
    }
  }

  Future<void> _safeDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('AlarmSoundStore delete failed: $e');
    }
  }

  Future<void> delete(String path) async {
    try {
      await _safeDelete(File(path));
    } catch (e) {
      debugPrint('AlarmSoundStore.delete failed: $e');
    }
  }

  Future<bool> exists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// Deletes imported files no alarm references any more.
  Future<void> pruneUnused(Iterable<String> usedPaths) async {
    try {
      final dir = await _dir();
      final used = usedPaths.map(p.normalize).toSet();
      await for (final f in dir.list()) {
        if (f is File && !used.contains(p.normalize(f.path))) await _safeDelete(f);
      }
    } catch (e) {
      debugPrint('AlarmSoundStore.pruneUnused failed: $e');
    }
  }
}
