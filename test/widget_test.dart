import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_craft/core/models.dart';
import 'package:nova_craft/core/strings.dart';
import 'package:nova_craft/design/theme.dart';
import 'package:nova_craft/design/tokens.dart';
import 'package:nova_craft/design/widgets/buttons.dart';
import 'package:nova_craft/design/widgets/display.dart';
import 'package:nova_craft/design/widgets/feedback.dart';

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
}
