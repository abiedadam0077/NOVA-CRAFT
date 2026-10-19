import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_craft/core/playit_api.dart';

void main() {
  group('Playit Tunnel selection', () {
    final List<PlayitTunnel> tunnels = <PlayitTunnel>[
      PlayitTunnel.fromJson(<String, dynamic>{
        'tunnel_id': 'java-a',
        'name': 'Java A',
        'tunnel_type': 'minecraft-java',
        'port_type': 'tcp',
        'display_address': 'a.playit.gg:25565',
      }),
      PlayitTunnel.fromJson(<String, dynamic>{
        'id': 'java-b',
        'name': 'Java B',
        'tunnel_type': 'minecraft-java',
        'port_type': 'tcp',
        'display_address': 'b.playit.gg:25565',
      }),
      PlayitTunnel.fromJson(<String, dynamic>{
        'id': 'bedrock-a',
        'name': 'Bedrock',
        'tunnel_type': 'minecraft-bedrock',
        'port_type': 'udp',
        'display_address': 'bedrock.playit.gg:19132',
      }),
    ];

    test('tunnel_id and id fields are both parsed', () {
      expect(tunnels.map((PlayitTunnel tunnel) => tunnel.id), <String>['java-a', 'java-b', 'bedrock-a']);
    });

    test('never silently selects among multiple matching tunnels', () {
      final PlayitAgentState state = PlayitAgentState(agentId: 'agent', tunnels: tunnels);
      expect(state.tunnelFor(bedrock: false), isNull);
      expect(state.tunnelFor(bedrock: false, tunnelId: 'java-b')?.address, 'b.playit.gg:25565');
    });

    test('selects the only edition-matching tunnel when unambiguous', () {
      final PlayitAgentState state = PlayitAgentState(agentId: 'agent', tunnels: tunnels);
      expect(state.tunnelFor(bedrock: true)?.id, 'bedrock-a');
    });

    test('flags incompatible tunnel protocols instead of silently selecting them', () {
      final PlayitAgentState state = PlayitAgentState(
        agentId: 'agent',
        tunnels: <PlayitTunnel>[
          PlayitTunnel.fromJson(<String, dynamic>{
            'id': 'wrong-java',
            'tunnel_type': 'minecraft-java',
            'port_type': 'udp',
            'display_address': 'example.playit.gg:19132',
          }),
        ],
      );
      expect(state.tunnelsFor(bedrock: false), isEmpty);
      expect(state.hasUnsupportedTunnels(bedrock: false), isTrue);
    });

    test('reads the configured tunnel origin without inventing a fallback', () {
      final PlayitTunnel tunnel = PlayitTunnel.fromJson(<String, dynamic>{
        'id': 'java-origin',
        'tunnel_type': 'minecraft-java',
        'port_type': 'tcp',
        'display_address': 'java.playit.gg:25565',
        'agent_config': <String, dynamic>{
          'fields': <Map<String, dynamic>>[
            <String, dynamic>{'name': 'local_ip', 'value': '127.0.0.1'},
            <String, dynamic>{'name': 'local_port', 'value': '25565'},
          ],
        },
      });
      expect(tunnel.localIp, '127.0.0.1');
      expect(tunnel.localPort, 25565);

      final PlayitTunnel unknownOrigin = PlayitTunnel.fromJson(<String, dynamic>{
        'id': 'java-unknown',
        'tunnel_type': 'minecraft-java',
        'port_type': 'tcp',
      });
      expect(unknownOrigin.localIp, isEmpty);
      expect(unknownOrigin.localPort, isNull);
    });

    test('decodes the versioned AgentRunDataV1 fields used by Playit official source', () async {
      final PlayitApi api = PlayitApi(
        client: MockClient((http.Request request) async => http.Response(
              jsonEncode(<String, dynamic>{
                'status': 'success',
                'data': <String, dynamic>{
                  'agent_id': 'agent-7',
                  'tunnels': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'tunnel-7',
                      'internal_id': 7,
                      'name': 'Java',
                      'display_address': 'real.playit.gg:25565',
                      'port_type': 'tcp',
                      'port_count': 1,
                      'tunnel_type': 'minecraft-java',
                      'tunnel_type_display': 'Minecraft Java',
                      'agent_config': <String, dynamic>{
                        'fields': <Map<String, String>>[
                          <String, String>{'name': 'local_ip', 'value': '127.0.0.1'},
                          <String, String>{'name': 'local_port', 'value': '25565'},
                        ],
                      },
                      'disabled_reason': null,
                    },
                  ],
                  'pending': <dynamic>[],
                  'notices': <dynamic>[],
                  'permissions': <String, dynamic>{
                    'is_self_managed': false,
                    'has_premium': false,
                    'account_status': 'verified',
                  },
                },
              }),
              200,
            )),
      );
      final PlayitAgentState state = await api.agentState('secret-value');
      api.dispose();
      expect(state.ok, isTrue);
      expect(state.agentId, 'agent-7');
      expect(state.tunnels.single.id, 'tunnel-7');
      expect(state.tunnels.single.address, 'real.playit.gg:25565');
      expect(state.tunnels.single.localIp, '127.0.0.1');
      expect(state.tunnels.single.localPort, 25565);
    });

    test('malformed rundata schema is not treated as a genuine empty tunnel list', () async {
      final PlayitApi api = PlayitApi(
        client: MockClient((http.Request request) async => http.Response(
              jsonEncode(<String, dynamic>{
                'status': 'success',
                'data': <String, dynamic>{'agent_id': 'agent-7', 'tunnels': 'not-an-array'},
              }),
              200,
            )),
      );
      final PlayitAgentState state = await api.agentState('secret-value');
      api.dispose();
      expect(state.ok, isFalse);
      expect(state.error, 'invalid-rundata-schema');
      expect(state.tunnels, isEmpty);
    });

    test('a malformed tunnel entry is an API error rather than a missing Tunnel', () async {
      final PlayitApi api = PlayitApi(
        client: MockClient((http.Request request) async => http.Response(
              jsonEncode(<String, dynamic>{
                'status': 'success',
                'data': <String, dynamic>{'agent_id': 'agent-7', 'tunnels': <dynamic>[null]},
              }),
              200,
            )),
      );
      final PlayitAgentState state = await api.agentState('secret-value');
      api.dispose();
      expect(state.ok, isFalse);
      expect(state.error, 'invalid-rundata-tunnel');
    });

    test('API errors never echo the submitted key into a user-visible diagnostic', () async {
      const String secret = 'secret-value';
      final PlayitApi api = PlayitApi(
        client: MockClient((http.Request request) async => http.Response(
              jsonEncode(<String, dynamic>{'status': 'error', 'error': 'rejected $secret'}),
              401,
            )),
      );
      final PlayitAgentState state = await api.agentState(secret);
      api.dispose();
      expect(state.ok, isFalse);
      expect(state.error, isNot(contains(secret)));
      expect(state.error, contains('[REDACTED]'));
    });

    test('reads rundata through the official agent-key endpoint without creating tunnels', () async {
      final List<http.Request> seen = <http.Request>[];
      final http.Client client = MockClient((http.Request request) async {
        seen.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'success',
            'data': <String, dynamic>{'agent_id': 'agent-7', 'tunnels': <Map<String, String>>[]},
          }),
          200,
        );
      });
      final PlayitApi api = PlayitApi(client: client);
      final PlayitAgentState state = await api.agentState('secret-value');
      api.dispose();

      expect(state.ok, isTrue);
      expect(state.agentId, 'agent-7');
      expect(seen, hasLength(1));
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/v1/agents/rundata');
      expect(seen.single.headers['Authorization'], 'Agent-Key secret-value');
      expect(seen.single.url.path, isNot(contains('tunnels/create')));
    });
  });
}
