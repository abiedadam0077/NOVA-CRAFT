/// Guard rails shared with the previous Kotlin implementation.
class Validation {
  const Validation._();

  static final RegExp repoNameRegex = RegExp(r'^[A-Za-z0-9._-]{1,100}$');
  static final RegExp _digits = RegExp(r'^[0-9]+$');

  static const List<String> dangerousCommandPrefixes = <String>[
    'stop',
    'ban-ip',
    'pardon-ip',
    'op ',
    'deop ',
    'whitelist reload',
    'kick ',
    'ban ',
  ];

  static bool validRepoName(String n) => repoNameRegex.hasMatch(n) && n != '.' && n != '..';

  static int clampPlayers(int v) => v.clamp(1, 1000);

  static int clampView(int v) => v.clamp(2, 32);

  static int clampSimulation(int v) => v.clamp(2, 32);

  static int clampMemory(int v) => v.clamp(1024, 12288);

  static int? parsePositiveInt(String value) {
    final trimmed = value.trim();
    if (!_digits.hasMatch(trimmed)) return null;
    return int.tryParse(trimmed);
  }

  /// Rejects traversal and empty segments; returns the cleaned relative path.
  static String? safePath(String p) {
    final clean = p.trim().replaceFirst(RegExp(r'^/+'), '');
    if (clean.isEmpty) return '';
    final parts = clean.split('/');
    for (final part in parts) {
      if (part == '..' || part.isEmpty) return null;
    }
    return parts.join('/');
  }

  static String parentPath(String path) {
    final clean = path.replaceFirst(RegExp(r'/+$'), '');
    final idx = clean.lastIndexOf('/');
    if (idx <= 0) return '';
    return clean.substring(0, idx);
  }

  static String joinPath(String base, String name) {
    final b = base.replaceFirst(RegExp(r'/+$'), '');
    final n = name.replaceFirst(RegExp(r'^/+'), '');
    if (b.isEmpty) return n;
    return '$b/$n';
  }

  static String fileName(String path) {
    final idx = path.lastIndexOf('/');
    return idx < 0 ? path : path.substring(idx + 1);
  }

  static bool isDangerousCommand(String cmd) {
    var c = cmd.trim();
    if (c.startsWith('/')) c = c.substring(1);
    c = c.toLowerCase();
    if (c == 'stop') return true;
    for (final danger in dangerousCommandPrefixes) {
      if (c.startsWith(danger)) return true;
    }
    return false;
  }

  /// Parses `host:port` (also strips tcp:// / udp:// prefixes).
  static HostPort parseHostPort(String address, int defaultPort) {
    final a = address
        .trim()
        .replaceFirst('tcp://', '')
        .replaceFirst('udp://', '')
        .trim();
    if (a.isEmpty) return HostPort('', defaultPort);
    final idx = a.lastIndexOf(':');
    if (idx > 0) {
      final portPart = a.substring(idx + 1);
      final port = int.tryParse(portPart);
      if (port != null) return HostPort(a.substring(0, idx), port);
    }
    return HostPort(a, defaultPort);
  }

  static String sanitizeFileUploadName(String raw) {
    final base = raw.split('/').last.split('\\').last;
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_').trim();
    return safe.isEmpty ? 'upload.bin' : safe;
  }
}

class HostPort {
  const HostPort(this.host, this.port);

  final String host;
  final int port;

  bool get isValid => host.isNotEmpty && port > 0 && port <= 65535;

  String get label => '$host:$port';
}
