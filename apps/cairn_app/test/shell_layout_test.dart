import 'dart:io';

import 'package:cairn_app/main.dart';
import 'package:cairn_app/studio/project_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression guard for the v1.2 Android blank-screen bug: the capsule
// nav wrapped its pill in a Center inside bottomNavigationBar, which
// expanded to the full screen height — the body collapsed to zero
// and the pill rendered mid-screen. The older widget tests ran at
// the default 800px-wide surface (NavigationRail path) and never
// exercised the capsule at all. This test runs at a real phone size
// and asserts GEOMETRY: content has real height and the pill sits
// at the bottom of the screen.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets(
    'phone size: projects page is visible and the capsule nav is at the bottom',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late Directory tmp;
      await tester.runAsync(() async {
        tmp = await Directory.systemTemp.createTemp('cairn_shell_test');
        await tester.pumpWidget(CairnApp(store: ProjectStore(tmp)));
        await _settle(tester);
      });
      addTearDown(() => tmp.delete(recursive: true));
      await tester.pump();

      // No PageView slide anymore (owner disliked it).
      expect(find.byType(PageView), findsNothing);

      // The projects content must have real, visible geometry —
      // not a zero-height body under a screen-eating bottom bar.
      final emptyState = find.text('هنوز پروژه‌ای نداری');
      expect(emptyState, findsOneWidget);
      final rect = tester.getRect(emptyState);
      expect(rect.height, greaterThan(0));
      expect(rect.top, greaterThan(0));
      expect(rect.bottom, lessThan(740 - 60),
          reason: 'content must end above the bottom navigation area');

      // The capsule pill (settings destination icon — it appears
      // nowhere in the projects body) must sit at the bottom of the
      // screen, not in the middle.
      final navIcon = find.byIcon(Icons.settings_outlined);
      expect(navIcon, findsOneWidget);
      final navRect = tester.getRect(navIcon);
      expect(navRect.center.dy, greaterThan(740 - 120),
          reason:
              'capsule nav must be at the bottom (was centered by the v1.2 Center bug)');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
