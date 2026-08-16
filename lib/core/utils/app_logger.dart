import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

enum LogLevel { info, warn, error }

class LogEntry {
  final DateTime ts;
  final LogLevel level;
  final String tag;
  final String message;
  final String? stackTrace;

  const LogEntry({
    required this.ts,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts.toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };
}

class AppLogger {
  final List<LogEntry> _entries = [];
  final int maxEntries;

  AppLogger({this.maxEntries = 2000});

  void _log(LogLevel l, String tag, String msg, [StackTrace? st]) {
    final e = LogEntry(
      ts: DateTime.now(),
      level: l,
      tag: tag,
      message: msg,
      stackTrace: st?.toString(),
    );
    _entries.add(e);
    if (_entries.length > maxEntries) _entries.removeAt(0);
    final levelStr = e.level.name.toUpperCase();
    if (st != null) {
      debugPrint('[$levelStr] $tag: $msg\n${st.toString()}');
    } else {
      debugPrint('[$levelStr] $tag: $msg');
    }
  }

  void info(String tag, String msg) => _log(LogLevel.info, tag, msg);

  void warn(String tag, String msg, [StackTrace? st]) =>
      _log(LogLevel.warn, tag, msg, st);

  void error(String tag, String msg, [StackTrace? st]) =>
      _log(LogLevel.error, tag, msg, st);

  List<LogEntry> get entries => List.unmodifiable(_entries);

  Future<String> exportToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final name =
        'logs_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jsonl';
    final f = File('${dir.path}/$name');
    final sink = f.openWrite();
    for (final e in _entries) {
      sink.writeln(jsonEncode(e.toJson()));
    }
    await sink.flush();
    await sink.close();
    return f.path;
  }
}

final appLoggerProvider = Provider<AppLogger>((ref) => AppLogger());
