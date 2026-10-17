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
  });

  final String id;
  final String name;
  final String type; // minecraft-java | minecraft-bedrock | …
  final String protocol; // tcp | udp | both
  final String address; // host:port, empty until allocated
  final String disabledReason;

  bool get enabled => disabledReason.isEmpty;
  bool get hasAddress => address.trim().isNotEmpty;

  factory PlayitTunnel.fromJson(Map<String, dynamic> o) {
    final dynamic reason = o['disabled_reason'];
    String reasonText = '';
    if (reason is String) {
      reasonText = reason;
    } else if (reason is Map) {
      reasonText = (reason['type'] ?? reason['reason'] ?? '').toString();
    }
    return PlayitTunnel(
      id: o['id']?.toString() ?? '',
      name: o['name']?.toString() ?? '',
      type: (o['tunnel_type'] ?? o['tunnel_type_display'] ?? '').toString(),
      protocol: o['port_type']?.toString() ?? '',
      address: (o['display_address'] ?? '').toString(),
      disabledReason: reasonText,
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

  /// The tunnel matching the edition we are running.
  PlayitTunnel? tunnelFor({required bool bedrock}) {
    final String want = bedrock ? 'minecraft-bedrock' : 'minecraft-java';
    for (final PlayitTunnel tunnel in tunnels) {
      if (tunnel.type == want) return tunnel;
    }
    return null;
  }
}

/// Reads Playit agent state with the agent secret.
///
/// This uses the same public agent endpoint the official Playit agent and the
/// official Minecraft plugin call (`POST https://api.playit.gg/v1/agents/rundata`
/// with `Authorization: Agent-Key <secret>`). The secret is only sent to
/// Playit, never logged, and never stored outside the device keystore or the
/// repository's Actions secret.
class PlayitApi {
  PlayitApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String apiBase = 'https://api.playit.gg';
  static const Duration _timeout = Duration(seconds: 25);

  /// Reads the agent's tunnels. Never throws: returns an error state instead so
  /// the UI can show "unknown" rather than inventing a connection.
  Future<PlayitAgentState> agentState(String secret, {bool createIfMissing = false, bool bedrock = false}) async {
    final String key = secret.trim();
    if (key.isEmpty) return const PlayitAgentState.unknown('missing-secret');
    try {
      final Map<String, dynamic> data = await _rundata(key);
      if (data.isEmpty) return const PlayitAgentState.unknown('unexpected-response');
      final String agentId = (data['agent_id'] ?? '').toString();
      List<PlayitTunnel> tunnels = _tunnels(data);
      PlayitTunnel? match = _pick(tunnels, bedrock);
      if (match == null && createIfMissing && agentId.isNotEmpty) {
        await createTunnel(key, agentId: agentId, bedrock: bedrock, name: 'NOVA CRAFT');
        await Future<void>.delayed(const Duration(seconds: 6));
        final Map<String, dynamic> refreshed = await _rundata(key);
        tunnels = _tunnels(refreshed);
        match = _pick(tunnels, bedrock);
      }
      return PlayitAgentState(agentId: agentId, tunnels: tunnels);
    } on _PlayitFailure catch (error) {
      return PlayitAgentState.unknown(error.message);
    } catch (error) {
      return PlayitAgentState.unknown(_safeMessage(error));
    }
  }

  List<PlayitTunnel> _tunnels(Map<String, dynamic> data) {
    final List<PlayitTunnel> out = <PlayitTunnel>[];
    final dynamic raw = data['tunnels'];
    if (raw is List) {
      for (final dynamic item in raw) {
        if (item is Map) out.add(PlayitTunnel.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return out;
  }

  PlayitTunnel? _pick(List<PlayitTunnel> tunnels, bool bedrock) {
    final String want = bedrock ? 'minecraft-bedrock' : 'minecraft-java';
    for (final PlayitTunnel tunnel in tunnels) {
      if (tunnel.type == want) return tunnel;
    }
    return null;
  }

  Future<Map<String, dynamic>> _rundata(String secret) async {
    final http.Response response = await _post(secret, '/v1/agents/rundata', <String, dynamic>{});
    return _unwrap(response);
  }

  /// Creates a Minecraft tunnel for the agent. Playit may refuse (verified
  /// account / plan limits); the failure message is surfaced verbatim.
  Future<void> createTunnel(String secret, {required String agentId, required bool bedrock, required String name}) async {
    final String type = bedrock ? 'minecraft-bedrock' : 'minecraft-java';
    final http.Response response = await _post(secret, '/v1/tunnels/create', <String, dynamic>{
      'name': name.length > 20 ? name.substring(0, 20) : name,
      'ports': <String, dynamic>{'type': 'tunnel-type', 'details': type},
      'origin': <String, dynamic>{
        'type': 'agent',
        'data': <String, dynamic>{
          'agent_id': agentId,
          'config': <String, dynamic>{
            'fields': <Map<String, String>>[
              <String, String>{'name': 'local_ip', 'value': '127.0.0.1'},
              <String, String>{'name': 'local_port', 'value': bedrock ? '19132' : '25565'},
            ],
          },
        },
      },
      'enabled': true,
    });
    _unwrap(response);
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
    final dynamic data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    if (map['success'] is Map) return Map<String, dynamic>.from(map['success'] as Map);
    return map;
  }

  static String _safeMessage(Object error) {
    final String text = error.toString();
    // Never let a URL with credentials or a stack trace reach the UI.
    if (text.contains('SocketException') || text.contains('ClientException')) return 'network-error';
    if (text.contains('TimeoutException')) return 'timeout';
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  void dispose() => _client.close();
}

class _PlayitFailure implements Exception {
  const _PlayitFailure(this.message);
  final String message;
}
