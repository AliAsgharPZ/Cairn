import 'dart:io';

import 'package:cairn_app/main.dart';
import 'package:cairn_app/studio/project_store.dart';
import 'package:cairn_app/ui/cairn_theme.dart';
import 'package:cairn_app/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// These widget tests touch real file IO (ProjectStore). They therefore run
// the app inside tester.runAsync (real event loop) with bounded real delays
// instead of pumpAndSettle, which never settles against real IO + the
// loading spinner and timed out in CI (run #1, 2026-10-21).
void main() {
  testWidgets(
    'studio opens on the projects screen with the wordmark',
    (tester) async {
      late Directory tmp;
      await tester.runAsync(() async {
        tmp = await Directory.systemTemp.createTemp('cairn_widget_test');
        await tester.pumpWidget(CairnApp(store: ProjectStore(tmp)));
        await Future<void>.delayed(const Duration(milliseconds: 600));
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
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await tester.tap(find.text('پروژهٔ جدید'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.enterText(find.byType(TextField), 'پروژهٔ آزمایشی');
        await tester.tap(find.text('ساختن'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      addTearDown(() => tmp.delete(recursive: true));
      await tester.pump();

      expect(find.text('پروژهٔ آزمایشی'), findsOneWidget);
      // And it is really on disk:
      final listed = await tester.runAsync(() => store.list());
      expect(listed, hasLength(1));
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
