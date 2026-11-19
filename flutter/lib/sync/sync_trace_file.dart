import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'sync_trace.dart';

/// Writes a [SyncTrace] to `sync-traces/<start time>.jsonl` as it's
/// recorded, keeping the newest [_keep] sessions.
///
/// On Android the folder is the app's external files dir, which `adb pull`
/// can read from a release build (no `run-as` needed):
///
///     adb pull /sdcard/Android/data/com.reelay.tv/files/sync-traces
///
/// On macOS it's the app's Application Support folder.
class SyncTraceFile {
  SyncTraceFile._(this._file) : path = _file.path;

  static const _keep = 10;
  static const _flushEvery = Duration(seconds: 5);

  final File _file;
  final String path;
  // Lines wait here and go out in one append every few seconds, each
  // append chained after the last so they never overlap.
  final StringBuffer _pending = StringBuffer();
  Future<void> _writing = Future.value();
  Timer? _flushTimer;
  bool _closed = false;

  /// A trace for one room session, already writing to its own file; null if
  /// there's nowhere to write (a trace is best effort, never in the way).
  static Future<SyncTrace?> start() async {
    try {
      final file = await _open();
      final trace = SyncTrace(onEntry: file._write);
      trace.record('note', {'text': 'trace file', 'path': file.path});
      _active[trace] = file;
      return trace;
    } catch (_) {
      return null;
    }
  }

  static final _active = Expando<SyncTraceFile>();

  /// Flushes and closes [trace]'s file, if it has one.
  static Future<void> finish(SyncTrace trace) async {
    final file = _active[trace];
    if (file == null) return;
    _active[trace] = null;
    await file._close();
  }

  static Future<SyncTraceFile> _open() async {
    final base = Platform.isAndroid
        ? (await getExternalStorageDirectory() ?? await getApplicationSupportDirectory())
        : await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/sync-traces');
    await dir.create(recursive: true);
    await _prune(dir);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final path = '${dir.path}/$stamp.jsonl';
    final file = SyncTraceFile._(File(path));
    file._flushTimer = Timer.periodic(_flushEvery, (_) => file._flush());
    return file;
  }

  static Future<void> _prune(Directory dir) async {
    final traces = await dir.list().where((e) => e is File && e.path.endsWith('.jsonl')).cast<File>().toList();
    traces.sort((a, b) => a.path.compareTo(b.path));
    final excess = traces.length - (_keep - 1);
    for (final old in traces.take(excess < 0 ? 0 : excess)) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  void _write(Map<String, Object?> entry) {
    if (_closed) return;
    try {
      _pending.writeln(jsonEncode(entry));
    } catch (_) {}
  }

  Future<void> _flush() {
    if (_pending.isEmpty) return _writing;
    final chunk = _pending.toString();
    _pending.clear();
    return _writing = _writing.then((_) async {
      try {
        await _file.writeAsString(chunk, mode: FileMode.append, flush: true);
      } catch (_) {}
    });
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _flushTimer?.cancel();
    await _flush();
  }
}
