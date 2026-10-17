import 'dart:async';
import 'dart:io';

import 'models.dart';
import 'strings.dart';

class Fmt {
  Fmt._();

  static String bytes(int? value) {
    if (value == null || value < 0) return '—';
    if (value < 1024) return '$value B';
    const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
    double size = value / 1024;
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final String formatted = size >= 100 ? size.toStringAsFixed(0) : size.toStringAsFixed(size >= 10 ? 1 : 2);
    return '$formatted ${units[unit]}';
  }

  static String mb(int? value) => value == null ? '—' : '$value MB';

  static String compactNumber(int? value) {
    if (value == null) return '—';
    if (value < 1000) return '$value';
    if (value < 1000000) return '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}K';
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }

  static String relative(DateTime? date) {
    if (date == null) return L10n.t('unknown');
    final Duration diff = DateTime.now().difference(date);
    if (diff.inSeconds < 45) return L10n.t('justNow');
    String span;
    if (diff.inMinutes < 60) {
      span = '${diff.inMinutes} ${L10n.t('minutes')}';
    } else if (diff.inHours < 24) {
      span = '${diff.inHours} ${L10n.t('hours')}';
    } else if (diff.inDays < 30) {
      span = '${diff.inDays} ${L10n.t('days')}';
    } else {
      span = '${(diff.inDays / 30).floor()} ${L10n.t('days')}';
    }
    return L10n.f('ago', <String, String>{'time': span});
  }

  static String dateTime(DateTime? date) {
    if (date == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  static String dateOnly(DateTime? date) {
    if (date == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static String duration(Duration? d) {
    if (d == null || d.isNegative) return '—';
    final int h = d.inHours;
    final int m = d.inMinutes % 60;
    if (h >= 24) return '${d.inDays}d ${h % 24}h';
    if (h > 0) return '${h}h ${m}m';
    if (d.inMinutes > 0) return '${m}m';
    return '${d.inSeconds}s';
  }

  static String shortSha(String sha) => sha.length >= 7 ? sha.substring(0, 7) : sha;

  /// Maps transport/API failures to a localized, non-leaky message.
  static String error(Object error) {
    if (error is ApiException) {
      if (error.status == 401) return L10n.t('errorUnauthorized');
      if (error.status == 403) {
        if (error.message.toLowerCase().contains('rate limit')) return L10n.t('errorRateLimit');
        return L10n.t('errorForbidden');
      }
      if (error.status == 404) return L10n.t('errorNotFound');
      return error.message;
    }
    if (error is TimeoutException) return L10n.t('errorTimeout');
    if (error is SocketException) return L10n.t('errorNetwork');
    final String message = error.toString();
    if (message.contains('SocketException') || message.contains('Failed host lookup')) {
      return L10n.t('errorNetwork');
    }
    if (message.contains('TimeoutException')) return L10n.t('errorTimeout');
    if (message.startsWith('Exception: ')) return message.substring(11);
    return message.isEmpty ? L10n.t('errorGeneric') : message;
  }

  static String titleCase(String value) {
    if (value.isEmpty) return value;
    return value.substring(0, 1).toUpperCase() + value.substring(1).toLowerCase();
  }

  static String phaseLabel(ServerPhase phase) {
    switch (phase) {
      case ServerPhase.online:
        return L10n.t('online');
      case ServerPhase.offline:
        return L10n.t('offline');
      case ServerPhase.starting:
        return L10n.t('starting');
      case ServerPhase.stopping:
        return L10n.t('stopping');
      case ServerPhase.error:
        return L10n.t('error');
      case ServerPhase.unknown:
        return L10n.t('unknown');
    }
  }
}
