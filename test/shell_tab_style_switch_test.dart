import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/screens/main_shell.dart';
import 'package:mornye/services/shell_navigation_service.dart';

void main() {
  int? switched(int index, {required bool fromMornye, bool desktop = true}) =>
      shellIndexOfTab(
        shellTabAt(index, mornye: fromMornye),
        mornye: !fromMornye,
        desktop: desktop,
      );

  test('switching styles keeps the tab, not the index', () {
    const materialSettings = 2;
    const mornyeSearch = 2;
    const mornyeSettings = 3;

    // Material Settings stays Settings instead of becoming Search.
    expect(switched(materialSettings, fromMornye: false), mornyeSettings);
    expect(switched(mornyeSettings, fromMornye: true), materialSettings);
    // Mornye's Search lands on Material's Home, where Material searches.
    expect(switched(mornyeSearch, fromMornye: true), 0);
    for (final index in [0, 1]) {
      expect(switched(index, fromMornye: false), index);
    }
    // Mornye phones have no Settings destination.
    expect(
      switched(materialSettings, fromMornye: false, desktop: false),
      isNull,
    );
  });

  test('Mornye Search maps to its own tab', () {
    expect(shellTabAt(2, mornye: true), ShellTab.search);
  });
}
