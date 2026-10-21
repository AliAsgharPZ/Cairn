import 'dart:io';

import 'package:cairn_app/main.dart';
import 'package:cairn_app/studio/project_store.dart';
import 'package:cairn_app/ui/cairn_theme.dart';
import 'package:cairn_app/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// These widget tests touch real file IO (ProjectStore), so the app runs
// inside tester.runAsync (real event loop). Inside runAsync, widget
// animations advance ONLY when frames are pumped with a duration — real
// Future.delayed waits do not move them (that mismatch stalled the
// create-project dialog flow in CI runs #4/#7). [_settle] therefore
// alternates duration pumps with short real delays so both the fake
// animation clock and real IO make progress.
Future<void> _settle(WidgetTester tester) async {
  // 60 rounds (up from 30): the shell's startup work grew with M6–M9
  // (skills/providers reloads) and CI run #27 showed the shorter
  // settle starving the full-app tests again.
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  testWidgets(
    'studio opens on the projects screen with the wordmark',
    (tester) async {
      late Directory tmp;
      await tester.runAsync(() async {
        tmp = await Directory.systemTemp.createTemp('cairn_widget_test');
        await tester.pumpWidget(CairnApp(store: ProjectStore(tmp)));
        await _settle(tester);
      });
      addTearDown(() => tmp.delete(recursive: true));
      await tester.pump();

      expect(find.text('CAIRN'), findsOneWidget); // wordmark (brand red)
      expect(find.text('پروژه‌های ایجنت'), findsOneWidget);
      expect(find.text('هنوز پروژه‌ای نداری'), findsOneWidget); // empty state
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'creating a project from the UI persists and lists it',
    (tester) async {
      late Directory tmp;
      late ProjectStore store;
      await tester.runAsync(() async {
        tmp = await Directory.systemTemp.createTemp('cairn_widget_test');
        store = ProjectStore(tmp);
        await tester.pumpWidget(CairnApp(store: store));
        await _settle(tester);
        await tester.tap(find.text('پروژهٔ جدید'));
        await _settle(tester);
        await tester.enterText(find.byType(TextField), 'پروژهٔ آزمایشی');
        await tester.tap(find.text('ساختن'));
        await _settle(tester);
      });
      addTearDown(() => tmp.delete(recursive: true));
      await tester.pump();

      // Persistence first: if this fails, the create flow itself is
      // broken; if it passes but the UI expect below fails, it is a
      // rendering/refresh problem. (CI runs #4/#7 failed the UI expect.)
      final listed = await tester.runAsync(() => store.list());
      expect(listed, hasLength(1),
          reason: 'the created project must be persisted by the store');
      if (find.text('پروژهٔ آزمایشی').evaluate().isEmpty) {
        debugDumpApp(); // captured in the CI log on failure
      }
      expect(find.text('پروژهٔ آزمایشی'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('theme honours the Oracle tokens', () {
    final theme = buildCairnTheme(Brightness.light);
    // Primary actions are the charcoal, never a coloured CTA.
    expect(theme.colorScheme.primary, CairnColors.primary);
    expect(theme.scaffoldBackgroundColor, CairnColors.canvas);
    // No elevation anywhere in the system.
    expect(theme.cardTheme.elevation, 0);
    expect(theme.appBarTheme.elevation, 0);
    // Persian typeface is the default, Inter the fallback.
    expect(theme.textTheme.bodyMedium?.fontFamily, CairnFonts.persian);
    expect(theme.textTheme.bodyMedium?.fontFamilyFallback,
        contains(CairnFonts.latin));
    // Brand red must not leak into interactive theme colours.
    expect(theme.colorScheme.error, CairnColors.error);
    expect(theme.colorScheme.primary, isNot(CairnColors.brandMark));
  });
}
