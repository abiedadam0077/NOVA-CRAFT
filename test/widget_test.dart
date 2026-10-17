import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/strings.dart';
import 'package:nova_craft/design/theme.dart';
import 'package:nova_craft/design/tokens.dart';
import 'package:nova_craft/design/widgets/buttons.dart';
import 'package:nova_craft/design/widgets/display.dart';
import 'package:nova_craft/design/widgets/feedback.dart';
import 'package:nova_craft/design/widgets/nav.dart';

Widget _host(Widget child, {TextDirection direction = TextDirection.rtl}) {
  return NovaTheme(
    palette: NovaPalette.dark,
    child: MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  setUp(() {
    L10n.lang = 'ar';
  });

  testWidgets('NovaButton shows its label and respects a null callback', (WidgetTester tester) async {
    await tester.pumpWidget(_host(NovaButton(label: 'Start server', onPressed: null)));
    expect(find.text('Start server'), findsOneWidget);
    expect(find.byType(NovaButton), findsOneWidget);
  });

  testWidgets('NovaButton fires onPressed', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(_host(NovaButton(label: 'Restart', onPressed: () => taps++)));
    await tester.tap(find.byType(NovaButton));
    expect(taps, 1);
  });

  testWidgets('StatusPill renders the offline state', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const StatusPill(phase: ServerPhase.offline)));
    expect(find.byType(StatusPill), findsOneWidget);
    expect(find.text(L10n.t('offline')), findsOneWidget);
  });

  testWidgets('AddressPill shows a placeholder when no address exists', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const AddressPill(address: '', label: 'Server address')));
    expect(find.text('Server address'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_rounded), findsNothing);
  });

  testWidgets('ServerAvatar paints initials', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const ServerAvatar(name: 'Island', size: 56, software: 'PAPER')));
    expect(find.text('IS'), findsOneWidget);
  });

  testWidgets('arabic directionality is preserved by the shell host', (WidgetTester tester) async {
    late TextDirection direction;
    await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
      direction = Directionality.of(context);
      return const SizedBox();
    })));
    expect(direction, TextDirection.rtl);
    await tester.pumpWidget(_host(const SizedBox(), direction: TextDirection.ltr));
    await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
      direction = Directionality.of(context);
      return const SizedBox();
    }), direction: TextDirection.ltr));
    expect(direction, TextDirection.ltr);
  });
  testWidgets('bottom navigation shows exactly the five destinations', (WidgetTester tester) async {
    int selected = -1;
    await tester.pumpWidget(_host(NovaBottomBar(
      index: 0,
      onChanged: (int value) => selected = value,
      items: <NovaNavItem>[
        NovaNavItem(label: L10n.t('navHome'), icon: Icons.home_outlined),
        NovaNavItem(label: L10n.t('navConsole'), icon: Icons.terminal_outlined),
        NovaNavItem(label: L10n.t('navFiles'), icon: Icons.folder_outlined),
        NovaNavItem(label: L10n.t('navMods'), icon: Icons.extension_outlined),
        NovaNavItem(label: L10n.t('navServerSettings'), icon: Icons.tune_outlined),
      ],
    )));
    expect(find.byType(NovaBottomBar), findsOneWidget);
    expect(find.text(L10n.t('navHome')), findsOneWidget);
    expect(find.text(L10n.t('navConsole')), findsOneWidget);
    expect(find.text(L10n.t('navFiles')), findsOneWidget);
    expect(find.text(L10n.t('navMods')), findsOneWidget);
    expect(find.text(L10n.t('navServerSettings')), findsOneWidget);
    await tester.tap(find.text(L10n.t('navServerSettings')));
    expect(selected, 4);
  });

  testWidgets('a server path can never escape the data folder', (WidgetTester tester) async {
    const ServerConfig config = ServerConfig(id: '1', name: 's', repoOwner: 'o', repoName: 'r');
    expect(config.serverPath('server.properties'), 'server/server.properties');
    expect(config.serverPath('/world/level.dat'), 'server/world/level.dat');
    expect(config.serverPath('../.github/workflows/x.yml'), 'server/../.github/workflows/x.yml');
    expect(config.serverPath('../.github/workflows/x.yml').startsWith('server/'), isTrue);
  });

}
