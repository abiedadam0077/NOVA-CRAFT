/// Safe relative path predicate shared by the runner manifest consumers.
bool isSafeServerRelativePath(String value) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.startsWith('/') ||
      value.contains(String.fromCharCode(92)) ||
      value.codeUnits.any((int code) => code < 0x20 || code == 0x7f)) {
    return false;
  }
  return value.split('/').every((String part) => part.isNotEmpty && part != '.' && part != '..');
}

/// One entry of the runner's server-data manifest.
class ServerFileEntry {
  const ServerFileEntry({required this.path, required this.size, required this.modified, required this.isDir});

  final String path;
  final int size;
  final DateTime? modified;
  final bool isDir;

  String get name => path.contains('/') ? path.split('/').last : path;

  factory ServerFileEntry.fromJson(Map<String, dynamic> o, {required bool isDir}) {
    final dynamic rawPath = o['path'];
    final dynamic rawSize = o['size'];
    final dynamic rawModified = o['modified'];
    if (rawPath is! String || rawPath.isEmpty || rawSize is! int || rawSize < 0) {
      throw const FormatException('Manifest file entry is missing a valid path or size');
    }
    DateTime? modified;
    if (rawModified is num && rawModified.isFinite && rawModified >= 0) {
      if (rawModified > 8640000000000 || rawModified != rawModified.roundToDouble()) {
        throw const FormatException('Manifest file timestamp is outside the supported range');
      }
      try {
        modified = DateTime.fromMillisecondsSinceEpoch(rawModified.toInt() * 1000).toLocal();
      } on ArgumentError {
        throw const FormatException('Manifest file timestamp is outside the supported range');
      }
    } else if (rawModified is String) {
      modified = DateTime.tryParse(rawModified)?.toLocal();
      if (modified == null) throw const FormatException('Manifest file timestamp is invalid');
    } else if (rawModified != null) {
      throw const FormatException('Manifest file timestamp has an unexpected type');
    }
    return ServerFileEntry(
      path: rawPath,
      size: rawSize.toInt(),
      modified: modified,
      isDir: isDir,
    );
  }
}

/// Parsed `nova-craft/files/manifest.json`, generated from the runner's actual
/// configured data directory (not from a hard-coded repository path).
class ServerFileManifest {
  const ServerFileManifest({required this.entries, required this.generatedAt, this.truncated = false});

  final List<ServerFileEntry> entries;
  final DateTime? generatedAt;
  final bool truncated;

  bool get isEmpty => entries.isEmpty;

  static ServerFileManifest fromJson(Map<String, dynamic> o) {
    final dynamic rawFiles = o['files'];
    final dynamic rawDirs = o['dirs'];
    if (rawFiles is! List || (rawDirs != null && rawDirs is! List)) {
      throw const FormatException('File manifest has no valid files/dirs arrays');
    }

    final List<ServerFileEntry> entries = <ServerFileEntry>[];
    final Set<String> seen = <String>{};
    for (final dynamic raw in (rawDirs as List? ?? <dynamic>[])) {
      if (raw is! String || !isSafeServerRelativePath(raw) || !seen.add(raw)) {
        throw const FormatException('File manifest contains an unsafe or duplicate directory path');
      }
      entries.add(ServerFileEntry(path: raw, size: 0, modified: null, isDir: true));
    }
    for (final dynamic raw in rawFiles) {
      if (raw is! Map) throw const FormatException('File manifest contains a malformed file entry');
      final ServerFileEntry entry = ServerFileEntry.fromJson(Map<String, dynamic>.from(raw), isDir: false);
      if (!isSafeServerRelativePath(entry.path) || !seen.add(entry.path)) {
        throw const FormatException('File manifest contains an unsafe or duplicate file path');
      }
      entries.add(entry);
    }
    final Set<String> filePaths = entries.where((ServerFileEntry entry) => !entry.isDir).map((ServerFileEntry entry) => entry.path).toSet();
    final Set<String> dirPaths = entries.where((ServerFileEntry entry) => entry.isDir).map((ServerFileEntry entry) => entry.path).toSet();
    if (dirPaths.any(filePaths.contains)) {
      throw const FormatException('Manifest declares one path as both a file and directory');
    }
    for (final String path in filePaths) {
      int slash = path.lastIndexOf('/');
      while (slash >= 0) {
        if (filePaths.contains(path.substring(0, slash))) {
          throw const FormatException('Manifest file path is nested below another file');
        }
        slash = path.lastIndexOf('/', slash - 1);
      }
    }
    entries.sort((ServerFileEntry a, ServerFileEntry b) => a.path.compareTo(b.path));
    final dynamic schema = o['schema'];
    if (schema != null && schema != 1) throw const FormatException('Unsupported file manifest schema');
    if (o['truncated'] != null && o['truncated'] is! bool) {
      throw const FormatException('Manifest truncated flag is invalid');
    }
    final dynamic stamp = o['generatedAt'];
    final DateTime? generatedAt = stamp == null ? null : DateTime.tryParse(stamp.toString())?.toLocal();
    if (stamp != null && generatedAt == null) {
      throw const FormatException('File manifest generatedAt is not a valid timestamp');
    }
    return ServerFileManifest(entries: entries, generatedAt: generatedAt, truncated: o['truncated'] == true);
  }
}

/// A verified world folder discovered from a real runner manifest.
class ServerWorldInfo {
  const ServerWorldInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.fileCount,
    required this.modified,
  });

  final String name;
  final String path;
  final int size;
  final int fileCount;
  final DateTime? modified;
}

/// Finds worlds by their edition-specific `level.dat` marker. Java worlds live
/// in `<world>/level.dat`; Bedrock worlds live in `worlds/<name>/level.dat`.
/// Paths in the manifest are relative to the runner's configured dataPath.
List<ServerWorldInfo> discoverServerWorlds(ServerFileManifest manifest, {required bool isBedrock}) {
  final List<ServerFileEntry> files = manifest.entries.where((ServerFileEntry entry) => !entry.isDir).toList();
  final Set<String> roots = <String>{};
  for (final ServerFileEntry file in files) {
    final List<String> parts = file.path.split('/');
    if (parts.isEmpty || parts.last != 'level.dat') continue;
    if (isBedrock) {
      if (parts.length >= 3 && parts.first == 'worlds') roots.add(parts.take(2).join('/'));
    } else if (parts.length == 2) {
      roots.add(parts.first);
    }
  }

  final List<ServerWorldInfo> worlds = <ServerWorldInfo>[];
  for (final String root in roots) {
    final String prefix = '$root/';
    final List<ServerFileEntry> contents = files.where((ServerFileEntry file) => file.path.startsWith(prefix)).toList();
    if (contents.isEmpty) continue;
    if (isBedrock && !contents.any((ServerFileEntry file) => file.path.startsWith('${prefix}db/'))) continue;
    DateTime? modified;
    int size = 0;
    for (final ServerFileEntry file in contents) {
      size += file.size;
      final DateTime? stamp = file.modified;
      if (stamp != null && (modified == null || stamp.isAfter(modified))) modified = stamp;
    }
    worlds.add(ServerWorldInfo(
      name: root.split('/').last,
      path: root,
      size: size,
      fileCount: contents.length,
      modified: modified,
    ));
  }
  worlds.sort((ServerWorldInfo a, ServerWorldInfo b) => a.path.compareTo(b.path));
  return worlds;
}
