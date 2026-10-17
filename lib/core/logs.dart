import 'models.dart';

enum LogLevel { info, warn, error, success, debug, command, step }

class LogEntry {
  const LogEntry({required this.text, required this.level, this.timestamp, this.source});

  final String text;
  final LogLevel level;
  final String? timestamp;
  final String? source;
}

class LogParser {
  const LogParser._();

  static final RegExp _stamp = RegExp(r'^\[?(\d{1,2}:\d{2}:\d{2})\]?\s?');
  static final RegExp _dateStamp = RegExp(r'^\[?(\d{4}-\d{2}-\d{2}T[\d:.]+Z?)\]?\s?');

  static LogEntry parse(String raw, {String? source}) {
    final String line = raw.replaceAll('\r', '');
    String? timestamp;
    final RegExpMatch? clock = _stamp.firstMatch(line);
    final RegExpMatch? iso = _dateStamp.firstMatch(line);
    if (clock != null) {
      timestamp = clock.group(1);
    } else if (iso != null) {
      timestamp = iso.group(1);
    }

    final String lower = line.toLowerCase();
    LogLevel level = LogLevel.info;
    if (lower.contains('error') ||
        lower.contains('exception') ||
        lower.contains('fatal') ||
        lower.contains('severe') ||
        lower.contains('failed') ||
        line.contains('✗')) {
      level = LogLevel.error;
    } else if (lower.contains('warn') || line.contains('⚠')) {
      level = LogLevel.warn;
    } else if (lower.contains('done (') || lower.contains('started') || lower.contains('joined the game')) {
      level = LogLevel.success;
    } else if (lower.startsWith('[nova]') || lower.contains('remote command')) {
      level = LogLevel.command;
    } else if (line.trim().startsWith('===') || line.contains('=====')) {
      level = LogLevel.debug;
    }
    return LogEntry(text: line, level: level, timestamp: timestamp, source: source);
  }

  /// Turns the live job/step tree into readable console lines. This is what the
  /// console shows while a run is in progress, because GitHub only serves the
  /// full log archive once a job has finished.
  static List<LogEntry> fromJobs(List<WorkflowJob> jobs) {
    final List<LogEntry> out = <LogEntry>[];
    for (final WorkflowJob job in jobs) {
      out.add(LogEntry(text: '== ${job.name} · ${job.status}${job.conclusion != null ? ' (${job.conclusion})' : ''}', level: LogLevel.debug));
      for (final JobStep step in job.steps) {
        String mark = '•';
        LogLevel level = LogLevel.info;
        if (step.isSuccess) {
          mark = '✓';
          level = LogLevel.success;
        } else if (step.isFailure) {
          mark = '✗';
          level = LogLevel.error;
        } else if (step.isRunning) {
          mark = '▸';
          level = LogLevel.warn;
        }
        final String status = step.conclusion ?? step.status;
        out.add(LogEntry(text: '$mark ${step.number}. ${step.name} — $status', level: level, source: 'steps'));
      }
    }
    return out;
  }

  static List<LogEntry> fromText(String text, {String? source}) {
    final List<String> lines = text.split('\n');
    final List<LogEntry> out = <LogEntry>[];
    for (final String line in lines) {
      if (line.trim().isEmpty) continue;
      out.add(parse(line, source: source));
    }
    return out;
  }
}
