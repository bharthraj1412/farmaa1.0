import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:farmaa_mobile/main.dart';

void main() {
  testWidgets('App root smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: FarmaaApp(),
      ),
    );

    // Verify that the app mounts successfully
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
