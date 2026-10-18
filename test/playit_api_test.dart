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
