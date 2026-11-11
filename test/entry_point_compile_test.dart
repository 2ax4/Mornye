import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/main.dart' as app;

void main() {
  // Compile-time smoke: pulls lib/main.dart and its whole dependency graph
  // through the test compiler without running main().
  test('entry point compiles', () {
    expect(app.main, isA<Function>());
  });
}
