/// Guard rails shared with the previous Kotlin implementation.
class Validation {
  const Validation._();

  static final RegExp repoNameRegex = RegExp(r'^[A-Za-z0-9._-]{1,100}$');
  static final RegExp _digits = RegExp(r'^[0-9]+$');

  static const Set<String> dangerousCommandRoots = <String>{
    'stop',
    'ban',
    'ban-ip',
    'pardon',
    'pardon-ip',
    'op',
    'deop',
    'whitelist',
    'kick',
    'save-off',
    'save-on',
    'reload',
    'function',
    'execute',
    'clear',
  };

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

  static bool isSafeConsoleCommand(String command) {
    final String value = command.trim();
    if (value.isEmpty || value.length > 512) return false;
    for (final int codeUnit in value.codeUnits) {
      if (codeUnit < 0x20 || codeUnit == 0x7f) return false;
    }
    return true;
  }

  static bool isDangerousCommand(String cmd) {
    var c = cmd.trim();
    if (c.startsWith('/')) c = c.substring(1);
    c = c.toLowerCase();
    if (c.isEmpty) return false;
    final String root = c.split(RegExp(r'\s+')).first;
    return dangerousCommandRoots.contains(root);
  }

  /// Parses `host:port` (also strips tcp:// / udp:// prefixes).
  static HostPort parseHostPort(String address, int defaultPort) {
    final String value = address.trim().replaceFirst('tcp://', '').replaceFirst('udp://', '').trim();
    if (value.isEmpty) return HostPort('', defaultPort);
    if (value.startsWith('[')) {
      final int close = value.indexOf(']');
      if (close < 0) return const HostPort('', 0);
      final String host = value.substring(0, close + 1);
      final String suffix = value.substring(close + 1);
      if (suffix.isEmpty) return HostPort(host, defaultPort);
      if (!suffix.startsWith(':') || suffix.length == 1) return const HostPort('', 0);
      final int? port = int.tryParse(suffix.substring(1));
      return port == null ? const HostPort('', 0) : HostPort(host, port);
    }
    final int firstColon = value.indexOf(':');
    final int lastColon = value.lastIndexOf(':');
    if (firstColon > 0 && firstColon == lastColon) {
      final int? port = int.tryParse(value.substring(firstColon + 1));
      if (port == null) return const HostPort('', 0);
      return HostPort(value.substring(0, firstColon), port);
    }
    // Multiple unbracketed colons are treated as an IPv6 literal with the
    // edition's default port; a single colon must contain a numeric port.
    return HostPort(value, defaultPort);
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
