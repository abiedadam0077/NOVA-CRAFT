import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/workflow_templates.dart';

void main() {
  late Directory temp;
  late File parser;
  late File input;
  late File output;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nova-playit-runner-test-');
    parser = File('${temp.path}/playit.py')..writeAsStringSync(WorkflowTemplates.playitScript);
    input = File('${temp.path}/rundata.json');
    output = File('${temp.path}/tunnel.env');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<String> parse(
    Map<String, dynamic> response, {
    String edition = 'JAVA',
    String tunnelId = '',
  }) async {
    await input.writeAsString(jsonEncode(response));
    final ProcessResult result = await Process.run(
      'python3',
      <String>[parser.path, 'parse', input.path, output.path, edition, tunnelId],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return output.readAsString();
  }

  group('runner rundata diagnostics', () {
    test('no tunnel is explicitly not_created and never gets an invented address', () async {
      final String env = await parse(<String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{'agent_id': 'agent-1', 'tunnels': <dynamic>[]},
      });
      expect(env, contains('TUNNEL_STATE=not_created'));
      expect(env, contains('TUNNEL_ADDR=\'\''));
    });

    test('a tunnel with the wrong edition or transport is unsupported', () async {
      final String env = await parse(<String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{
          'agent_id': 'agent-1',
          'tunnels': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'wrong',
              'tunnel_type': 'minecraft-java',
              'port_type': 'udp',
              'display_address': 'wrong.playit.gg:19132',
            },
          ],
        },
      });
      expect(env, contains('TUNNEL_STATE=unsupported'));
      expect(env, contains('Tunnel type unsupported'));
    });

    test('a matching tunnel without a Playit address stays address_unavailable', () async {
      final String env = await parse(<String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{
          'agent_id': 'agent-1',
          'tunnels': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'java-1',
              'tunnel_type': 'minecraft-java',
              'port_type': 'tcp',
              'display_address': '',
            },
          ],
        },
      });
      expect(env, contains('TUNNEL_STATE=address_unavailable'));
      expect(env, contains('TUNNEL_ADDR=\'\''));
    });

    test('Java Tunnel output reports only the address and local origin from rundata', () async {
      final String env = await parse(<String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{
          'agent_id': 'agent-1',
          'tunnels': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'java-1',
              'name': 'Java server',
              'tunnel_type': 'minecraft-java',
              'port_type': 'tcp',
              'display_address': 'real-from-api.playit.gg:25565',
              'agent_config': <String, dynamic>{
                'fields': <Map<String, dynamic>>[
                  <String, dynamic>{'name': 'local_ip', 'value': '127.0.0.1'},
                  <String, dynamic>{'name': 'local_port', 'value': '25565'},
                ],
              },
            },
          ],
        },
      });
      expect(env, contains('TUNNEL_STATE=allocated'));
      expect(env, contains('TUNNEL_ADDR=real-from-api.playit.gg:25565'));
      expect(env, contains('TUNNEL_LOCAL_IP=127.0.0.1'));
      expect(env, contains('TUNNEL_LOCAL_PORT=25565'));
      expect(env, isNot(contains('connection_ready')));
    });

    test('an explicit selection cannot silently choose a different Tunnel', () async {
      final String env = await parse(
        <String, dynamic>{
          'status': 'success',
          'data': <String, dynamic>{
            'agent_id': 'agent-1',
            'tunnels': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'java-1',
                'tunnel_type': 'minecraft-java',
                'port_type': 'tcp',
                'display_address': 'real.playit.gg:25565',
              },
            ],
          },
        },
        tunnelId: 'not-this-tunnel',
      );
      expect(env, contains('TUNNEL_STATE=selection_required'));
      expect(env, contains('TUNNEL_ADDR=\'\''));
    });
  });

  group('Minecraft Java Server List Ping', () {
    List<int> varint(int value) {
      final List<int> bytes = <int>[];
      while (true) {
        int part = value & 0x7f;
        value >>= 7;
        if (value != 0) {
          part |= 0x80;
        }
        bytes.add(part);
        if (value == 0) return bytes;
      }
    }

    Future<int> probeAgainstMockServer({required bool validStatus}) async {
      final ServerSocket server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final List<int> statusJson = utf8.encode(jsonEncode(<String, dynamic>{
        'version': <String, dynamic>{'name': 'mock-java', 'protocol': 767},
        'players': <String, dynamic>{'online': 0, 'max': 20},
      }));
      final List<int> payload = <int>[0, ...varint(statusJson.length), ...statusJson];
      final List<int> validPacket = <int>[...varint(payload.length), ...payload];
      server.listen((Socket client) {
        bool replied = false;
        client.listen((List<int> _) {
          if (replied) return;
          replied = true;
          client.add(validStatus ? validPacket : <int>[1, 2, 3]);
          client.flush().then((_) => client.destroy(), onError: (_) => client.destroy());
        });
      });
      final ProcessResult result = await Process.run(
        'python3',
        <String>[parser.path, 'probe', '127.0.0.1:${server.port}', 'JAVA'],
      );
      await server.close();
      return result.exitCode;
    }

    test('a real Java status response passes; a raw TCP accept with bad protocol data fails', () async {
      expect(await probeAgainstMockServer(validStatus: true), 0);
      expect(await probeAgainstMockServer(validStatus: false), 1);
    });

    test('the Java default game port remains 25565 in runner and configuration contracts', () {
      expect(WorkflowTemplates.runnerScript.contains('GAME_PORT=25565'), isTrue);
      expect(WorkflowTemplates.configScript.contains('"server-port=25565"'), isTrue);
      expect(WorkflowTemplates.runnerScript.contains(r'probe_tunnel "127.0.0.1:$GAME_PORT" false'), isTrue);
      expect(WorkflowTemplates.runnerScript.contains(r'probe_tunnel "$TUNNEL_ADDR" true'), isTrue);
    });
  });
}
