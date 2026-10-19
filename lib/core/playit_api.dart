import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'config.dart';

/// One tunnel as Playit's agent API reports it.
class PlayitTunnel {
  const PlayitTunnel({
    required this.id,
    required this.name,
    required this.type,
    required this.protocol,
    required this.address,
    this.disabledReason = '',
    this.localIp = '',
    this.localPort,
  });

  final String id;
  final String name;
  final String type; // minecraft-java | minecraft-bedrock | …
  final String protocol; // tcp | udp | both
  final String address; // host:port, empty until allocated
  final String disabledReason;
  final String localIp;
  final int? localPort;

  bool get enabled => disabledReason.isEmpty;
  bool get hasAddress => address.trim().isNotEmpty;
  bool supportsEdition({required bool bedrock}) =>
      type.trim() == (bedrock ? 'minecraft-bedrock' : 'minecraft-java') &&
      protocol.trim().toLowerCase() == (bedrock ? 'udp' : 'tcp');

  factory PlayitTunnel.fromJson(Map<String, dynamic> o) {
    final dynamic reason = o['disabled_reason'];
    String reasonText = '';
    if (reason is String) {
      reasonText = reason;
    } else if (reason is Map) {
      reasonText = (reason['type'] ?? reason['reason'] ?? '').toString();
    }
    String localValue(String key) {
      final dynamic direct = o[key];
      if (direct != null && direct.toString().isNotEmpty) return direct.toString();
      final dynamic rawConfig = o['agent_config'];
      final dynamic rawFields = rawConfig is Map ? rawConfig['fields'] : null;
      if (rawFields is Map && rawFields[key] != null) return rawFields[key].toString();
      if (rawFields is List) {
        for (final dynamic field in rawFields) {
          if (field is Map && field['name']?.toString() == key) {
            return (field['value'] ?? field['default_value'] ?? '').toString();
          }
        }
      }
      return '';
    }

    return PlayitTunnel(
      id: (o['tunnel_id'] ?? o['id'])?.toString() ?? '',
      name: o['name']?.toString() ?? '',
      type: (o['tunnel_type'] ?? o['tunnel_type_display'] ?? '').toString(),
      protocol: o['port_type']?.toString() ?? '',
      address: (o['display_address'] ?? '').toString(),
      disabledReason: reasonText,
      localIp: localValue('local_ip'),
      localPort: int.tryParse(localValue('local_port')),
    );
  }
}

/// Result of asking Playit about one agent.
class PlayitAgentState {
  const PlayitAgentState({
    required this.agentId,
    required this.tunnels,
    this.error = '',
  });

  const PlayitAgentState.unknown(this.error)
      : agentId = '',
        tunnels = const <PlayitTunnel>[];

  final String agentId;
  final List<PlayitTunnel> tunnels;
  final String error;

  bool get ok => error.isEmpty;

  bool hasUnsupportedTunnels({required bool bedrock}) =>
      tunnels.isNotEmpty && tunnels.every((PlayitTunnel tunnel) => !tunnel.supportsEdition(bedrock: bedrock));

  /// Matching tunnels for the selected edition and transport. A caller must not silently
  /// choose one when several tunnels of the same type exist.
  List<PlayitTunnel> tunnelsFor({required bool bedrock}) {
    final Set<String> seenIds = <String>{};
    return tunnels.where((PlayitTunnel tunnel) {
      if (!tunnel.supportsEdition(bedrock: bedrock)) return false;
      if (tunnel.id.isEmpty) return true;
      return seenIds.add(tunnel.id);
    }).toList();
  }

  PlayitTunnel? tunnelFor({required bool bedrock, String? tunnelId}) {
    final List<PlayitTunnel> matches = tunnelsFor(bedrock: bedrock);
    if (tunnelId != null && tunnelId.isNotEmpty) {
      for (final PlayitTunnel tunnel in matches) {
        if (tunnel.id == tunnelId) return tunnel;
      }
      return null;
    }
    return matches.length == 1 ? matches.single : null;
  }
}

/// Reads Playit agent state with the agent secret.
///
/// This mirrors the versioned `v1_agents_rundata` call in Playit's official
/// Agent source (`POST https://api.playit.gg/v1/agents/rundata` with
/// `Authorization: Agent-Key <secret>`). The secret is only sent to Playit,
/// never logged, and never stored outside the device keystore or repository
/// Actions secret. Tunnel creation is intentionally not part of this client.
class PlayitApi {
  PlayitApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String apiBase = 'https://api.playit.gg';
  static const Duration _timeout = Duration(seconds: 25);

  /// Reads the agent's tunnels. Never throws: returns an error state instead so
  /// the UI can show "unknown" rather than inventing a connection.
  Future<PlayitAgentState> agentState(String secret) async {
    final String key = secret.trim();
    if (key.isEmpty) return const PlayitAgentState.unknown('missing-secret');
    try {
      final Map<String, dynamic> data = await _rundata(key);
      final dynamic rawAgentId = data['agent_id'];
      final dynamic rawTunnels = data['tunnels'];
      if (rawAgentId is! String || rawAgentId.isEmpty || rawTunnels is! List) {
        throw const _PlayitFailure('invalid-rundata-schema');
      }
      final String agentId = rawAgentId;
      final List<PlayitTunnel> tunnels = _tunnels(rawTunnels);
      // Reading rundata is the only side effect of this operation. Tunnel
      // creation is always a user action in the Playit dashboard.
      return PlayitAgentState(agentId: agentId, tunnels: tunnels);
    } on _PlayitFailure catch (error) {
      return PlayitAgentState.unknown(_redact(error.message, key));
    } catch (error) {
      return PlayitAgentState.unknown(_safeMessage(error, key));
    }
  }

  List<PlayitTunnel> _tunnels(List<dynamic> raw) {
    final List<PlayitTunnel> out = <PlayitTunnel>[];
    for (final dynamic item in raw) {
      if (item is! Map) throw const _PlayitFailure('invalid-rundata-tunnel');
      final Map<String, dynamic> tunnel = Map<String, dynamic>.from(item);
      final dynamic id = tunnel['id'] ?? tunnel['tunnel_id'];
      final dynamic name = tunnel['name'];
      final dynamic portType = tunnel['port_type'];
      final dynamic displayAddress = tunnel['display_address'];
      if (id is! String || id.isEmpty || name is! String || portType is! String || displayAddress is! String) {
        throw const _PlayitFailure('invalid-rundata-tunnel');
      }
      out.add(PlayitTunnel.fromJson(tunnel));
    }
    return out;
  }

  Future<Map<String, dynamic>> _rundata(String secret) async {
    final http.Response response = await _post(secret, '/v1/agents/rundata', <String, dynamic>{});
    return _unwrap(response);
  }

  /// Performs one agent-API POST. The Authorization header is the only place
  /// the key appears; responses are unwrapped by [_unwrap].
  Future<http.Response> _post(String secret, String path, Map<String, dynamic> body) {
    return _client
        .post(
          Uri.parse('$apiBase$path'),
          headers: <String, String>{
            'Authorization': 'Agent-Key ${secret.trim()}',
            'Content-Type': 'application/json',
            'User-Agent': AppConfig.userAgent,
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
  }

  Map<String, dynamic> _unwrap(http.Response response) {
    if (response.body.isEmpty) {
      throw _PlayitFailure('empty-response');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw _PlayitFailure('invalid-json');
    }
    if (decoded is! Map) throw _PlayitFailure('unexpected-response');
    final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
    final String status = (map['status'] ?? '').toString();
    if (status == 'fail' || status == 'error') {
      final dynamic fail = map['fail'] ?? map['error'];
      final String message = fail is String ? fail : jsonEncode(fail);
      throw _PlayitFailure(message.isEmpty ? status : message);
    }
    if (response.statusCode == 429) throw _PlayitFailure('rate-limited');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _PlayitFailure('http-${response.statusCode}');
    }
    final dynamic data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    if (map['success'] is Map) return Map<String, dynamic>.from(map['success'] as Map);
    return map;
  }

  static String _safeMessage(Object error, String secret) {
    final String text = error.toString();
    // Never let a URL with credentials or a stack trace reach the UI.
    if (text.contains('SocketException') || text.contains('ClientException')) return 'network-error';
    if (text.contains('TimeoutException')) return 'timeout';
    return _redact(text, secret);
  }

  static String _redact(String text, String secret) {
    final String safe = secret.isEmpty ? text : text.replaceAll(secret, '[REDACTED]');
    return safe.length > 160 ? '${safe.substring(0, 160)}…' : safe;
  }


  void dispose() => _client.close();
}

class _PlayitFailure implements Exception {
  const _PlayitFailure(this.message);
  final String message;
}
