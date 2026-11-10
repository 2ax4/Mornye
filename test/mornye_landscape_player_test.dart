import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/providers/runtime_profile_provider.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/mornye_landscape_player.dart';

void main() {
  Future<void> pumpPlayer(WidgetTester tester, {bool volume = true}) async {
    tester.view.physicalSize = const Size(852, 393);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var page = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lowEndDeviceProvider.overrideWithValue(true),
          backdropBlurEnabledProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            backgroundColor: const Color(0xFF303030),
            body: StatefulBuilder(
              builder: (context, setState) => MornyeLandscapePlayer(
                page: page,
                onPageChanged: (value) => setState(() => page = value),
                artwork: const SizedBox.expand(
                  child: ColoredBox(
                    key: ValueKey('artwork'),
                    color: Colors.transparent,
                  ),
                ),
                header: const SizedBox(height: 48),
                queue: const SizedBox.expand(key: ValueKey('queue')),
                controls: const SizedBox(height: 68),
                volume: volume
                    ? const SizedBox(key: ValueKey('volume'), height: 48)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder toggle() => find.byIcon(CupertinoIcons.list_bullet);

  testWidgets('opens on the controls page and switches to Up Next', (
    tester,
  ) async {
    await pumpPlayer(tester);
    expect(find.byKey(const ValueKey('landscape-controls')), findsOneWidget);
    expect(find.byKey(const ValueKey('queue')), findsNothing);

    await tester.tap(toggle());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('queue')), findsOneWidget);
    expect(find.byKey(const ValueKey('landscape-controls')), findsNothing);

    await tester.tap(toggle());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('landscape-controls')), findsOneWidget);
    expect(find.byKey(const ValueKey('queue')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Up Next toggle reflects the visible page', (tester) async {
    await pumpPlayer(tester);
    Material materialOfToggle() => tester.widget<Material>(
      find.ancestor(of: toggle(), matching: find.byType(Material)).first,
    );
    expect(materialOfToggle().color, Colors.transparent);

    await tester.tap(toggle());
    await tester.pumpAndSettle();
    expect(materialOfToggle().color, Colors.white.withValues(alpha: 0.16));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides the volume pane when the player menu removes it', (
    tester,
  ) async {
    await pumpPlayer(tester, volume: false);
    expect(find.byKey(const ValueKey('volume')), findsNothing);
    expect(find.byKey(const ValueKey('landscape-controls')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
