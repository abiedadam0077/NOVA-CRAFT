import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/validation.dart';

void main() {
  group('Validation', () {
    test('repository names reject traversal and spaces', () {
      expect(Validation.validRepoName('nova-craft'), isTrue);
      expect(Validation.validRepoName('NOVA.server_1'), isTrue);
      expect(Validation.validRepoName('..'), isFalse);
      expect(Validation.validRepoName('.'), isFalse);
      expect(Validation.validRepoName('has space'), isFalse);
      expect(Validation.validRepoName('emoji😀'), isFalse);
      expect(Validation.validRepoName(''), isFalse);
    });

    test('numeric clamps cover the documented ranges', () {
      expect(Validation.clampPlayers(0), 1);
      expect(Validation.clampPlayers(5000), 1000);
      expect(Validation.clampView(1), 2);
      expect(Validation.clampView(64), 32);
      expect(Validation.clampSimulation(1), 2);
      expect(Validation.clampMemory(512), 1024);
      expect(Validation.clampMemory(90000), 12288);
    });

    test('parsePositiveInt rejects junk', () {
      expect(Validation.parsePositiveInt('42'), 42);
      expect(Validation.parsePositiveInt('-1'), isNull);
      expect(Validation.parsePositiveInt('4.2'), isNull);
      expect(Validation.parsePositiveInt('abc'), isNull);
    });

    test('Playit agent secrets are locally checked as non-empty hex', () {
      expect(Validation.validPlayitSecret('aabb0011'), isTrue);
      expect(Validation.validPlayitSecret(' aAbB0011 '), isTrue);
      expect(Validation.validPlayitSecret(''), isFalse);
      expect(Validation.validPlayitSecret('abc'), isFalse);
      expect(Validation.validPlayitSecret('not-a-key'), isFalse);
      expect(Validation.validPlayitSecret('aa bb'), isFalse);
    });

    test('path helpers normalise user input', () {
      expect(Validation.safePath('/server/../etc'), isNull);
      expect(Validation.safePath('server/world'), 'server/world');
      expect(Validation.safePath('/server//world'), isNull);
      expect(Validation.parentPath('server/mods'), 'server');
      expect(Validation.parentPath('server'), '');
      expect(Validation.joinPath('server', 'mods'), 'server/mods');
      expect(Validation.joinPath('', 'server'), 'server');
      expect(Validation.fileName('server/mods/test.jar'), 'test.jar');
    });

    test('dangerous console commands are detected by root command', () {
      expect(Validation.isDangerousCommand('stop'), isTrue);
      expect(Validation.isDangerousCommand('/stop'), isTrue);
      expect(Validation.isDangerousCommand('ban SomePlayer'), isTrue);
      expect(Validation.isDangerousCommand('op notchnotch'), isTrue);
      expect(Validation.isDangerousCommand('whitelist add player'), isTrue);
      expect(Validation.isDangerousCommand('stopper'), isFalse);
      expect(Validation.isDangerousCommand('say hello'), isFalse);
      expect(Validation.isDangerousCommand('list'), isFalse);
    });

    test('console commands reject multiline and control characters', () {
      expect(Validation.isSafeConsoleCommand('say hello'), isTrue);
      expect(Validation.isSafeConsoleCommand('  say hello  '), isTrue);
      expect(Validation.isSafeConsoleCommand('say one\nsay two'), isFalse);
      expect(Validation.isSafeConsoleCommand('say\rhello'), isFalse);
      expect(Validation.isSafeConsoleCommand(''), isFalse);
      expect(Validation.isSafeConsoleCommand(List<String>.filled(513, 'x').join()), isFalse);
    });

    test('host:port parsing handles schemes and defaults', () {
      final HostPort withPort = Validation.parseHostPort('play.example.gg:25570', 25565);
      expect(withPort.host, 'play.example.gg');
      expect(withPort.port, 25570);
      expect(withPort.isValid, isTrue);
      expect(withPort.label, 'play.example.gg:25570');

      final HostPort tcp = Validation.parseHostPort('tcp://play.example.gg:3000', 25565);
      expect(tcp.host, 'play.example.gg');
      expect(tcp.port, 3000);

      final HostPort bare = Validation.parseHostPort('play.example.gg', 19132);
      expect(bare.host, 'play.example.gg');
      expect(bare.port, 19132);

      final HostPort empty = Validation.parseHostPort('   ', 25565);
      expect(empty.isValid, isFalse);
      expect(Validation.parseHostPort('play.example.gg:abc', 25565).isValid, isFalse);
      expect(Validation.parseHostPort('[2001:db8::1]:25565', 25565).label, '[2001:db8::1]:25565');
      expect(Validation.parseHostPort('2001:db8::1', 25565).port, 25565);
    });

    test('upload names are sanitised', () {
      expect(Validation.sanitizeFileUploadName('../../etc/passwd'), 'passwd');
      expect(Validation.sanitizeFileUploadName('my world.zip'), 'my world.zip');
      expect(Validation.sanitizeFileUploadName('???'), '___');
      expect(Validation.sanitizeFileUploadName(''), 'upload.bin');
    });
  });
}
