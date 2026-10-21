import 'dart:io';

import 'package:cairn_app/main.dart';
import 'package:cairn_app/studio/project_store.dart';
import 'package:cairn_app/ui/cairn_theme.dart';
import 'package:cairn_app/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('studio opens on the projects screen with the wordmark',
      (tester) async {
    final tmp = await Directory.systemTemp.createTemp('cairn_widget_test');
    addTearDown(() => tmp.delete(recursive: true));

    await tester.pumpWidget(CairnApp(store: ProjectStore(tmp)));
    await tester.pumpAndSettle();

    expect(find.text('CAIRN'), findsOneWidget); // wordmark (brand red lives here)
    expect(find.text('پروژه‌های ایجنت'), findsOneWidget);
    expect(find.text('هنوز پروژه‌ای نداری'), findsOneWidget); // honest empty state
  });

  testWidgets('creating a project from the UI persists and lists it',
      (tester) async {
    final tmp = await Directory.systemTemp.createTemp('cairn_widget_test');
    addTearDown(() => tmp.delete(recursive: true));
    final store = ProjectStore(tmp);

    await tester.pumpWidget(CairnApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('پروژهٔ جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'پروژهٔ آزمایشی');
    await tester.tap(find.text('ساختن'));
    await tester.pumpAndSettle();

    expect(find.text('پروژهٔ آزمایشی'), findsOneWidget);
    // And it is really on disk:
    expect(await store.list(), hasLength(1));
  });

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
