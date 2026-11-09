import 'package:family_vault/src/app/build_info.dart';
import 'package:family_vault/src/app/family_vault_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('application shell', () {
    testWidgets('builds without error and shows the product name',
        (WidgetTester tester) async {
      await tester.pumpWidget(const FamilyVaultApp());

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.text(appName), findsWidgets);
    });

    testWidgets('lists planned sections rather than empty screens',
        (WidgetTester tester) async {
      await tester.pumpWidget(const FamilyVaultApp());

      expect(find.text('Planned sections'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('All Items'), findsOneWidget);
    });

    testWidgets('states the current stage instead of implying completeness',
        (WidgetTester tester) async {
      await tester.pumpWidget(const FamilyVaultApp());

      expect(find.text(appStage), findsWidgets);
    });

    testWidgets('about dialog reports the version', (WidgetTester tester) async {
      await tester.pumpWidget(const FamilyVaultApp());

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.text('Version $appVersion'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('tapping an unbuilt section says so plainly',
        (WidgetTester tester) async {
      await tester.pumpWidget(const FamilyVaultApp());

      await tester.tap(find.text('Dashboard'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('is not built yet'),
        findsOneWidget,
      );
    });

    testWidgets('shows no demonstration banner in a normal build',
        (WidgetTester tester) async {
      await tester.pumpWidget(const FamilyVaultApp());

      // isDemoBuild is a compile-time constant, false unless the build passes
      // --dart-define=FAMILY_VAULT_DEMO=true.
      expect(isDemoBuild, isFalse);
      expect(find.textContaining('Demonstration build'), findsNothing);
    });
  });
}
