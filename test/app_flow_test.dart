import 'package:family_vault/src/app/family_vault_app.dart';
import 'package:family_vault/src/app/vault_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_crypto_service.dart';
import 'support/in_memory_vault_repository.dart';

/// End-to-end tests of the interface, driven the way a person would drive it.
///
/// These run against the real widgets and the real session, with only the
/// cryptography and the file system replaced, so what they prove is that the
/// screens are actually wired to the vault — not merely that they render.
void main() {
  late InMemoryVaultRepository repository;
  late VaultSession session;

  setUp(() {
    repository = InMemoryVaultRepository();
    session = VaultSession(crypto: FakeCryptoService(), repository: repository);
  });

  tearDown(() => session.dispose());

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(FamilyVaultApp(sessionOverride: session));
    await tester.pumpAndSettle();
  }

  /// Creates a vault through the interface, as a first-time user would.
  Future<void> createVault(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextField).first, password);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create my vault'));
    await tester.pumpAndSettle();
  }

  group('first run', () {
    testWidgets('offers to create a vault', (WidgetTester tester) async {
      await start(tester);
      expect(find.text('Set up Family Vault'), findsOneWidget);
      expect(find.text('Create my vault'), findsOneWidget);
    });

    testWidgets('warns that a lost password cannot be recovered', (
      WidgetTester tester,
    ) async {
      await start(tester);
      expect(
        find.textContaining('cannot be opened'),
        findsOneWidget,
        reason: 'the consequence of losing the password must be stated',
      );
    });

    testWidgets('will not create a vault until the warning is acknowledged', (
      WidgetTester tester,
    ) async {
      await start(tester);
      await tester.enterText(find.byType(TextField).first, 'a long password');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'a long password');
      await tester.pumpAndSettle();

      final Finder button = find.widgetWithText(
        FilledButton,
        'Create my vault',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('will not create a vault with a short password', (
      WidgetTester tester,
    ) async {
      await start(tester);
      await tester.enterText(find.byType(TextField).first, 'short');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await tester.pumpAndSettle();
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create my vault'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('creating a vault opens it', (WidgetTester tester) async {
      await start(tester);
      await createVault(tester, 'a proper master password');

      expect(session.status, VaultStatus.unlocked);
      expect(find.text('Dashboard'), findsWidgets);
    });
  });

  group('once a vault exists', () {
    testWidgets('asks for the password and opens on the right one', (
      WidgetTester tester,
    ) async {
      await start(tester);
      await createVault(tester, 'the master password');
      session.lock();
      await tester.pumpAndSettle();

      expect(find.text('Unlock'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'wrong password');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(session.status, VaultStatus.locked);

      await tester.enterText(
        find.byType(TextField).first,
        'the master password',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(session.status, VaultStatus.unlocked);
    });
  });

  group('saving a login through the interface', () {
    testWidgets('it appears in the list and survives a lock', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await start(tester);
      await createVault(tester, 'the master password');

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'My Bank',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'gurpreet',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'A-Strong-Password-99',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Stored in the vault, not merely on screen.
      expect(session.data!.liveItems.length, 1);
      expect(session.data!.liveItems.single.title, 'My Bank');

      // And really written, so it comes back after locking.
      session.lock();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'the master password',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(session.data!.liveItems.single.title, 'My Bank');
    });

    testWidgets('a login with no name is refused', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await start(tester);
      await createVault(tester, 'the master password');

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Give this entry a name'), findsOneWidget);
      expect(session.data!.liveItems, isEmpty);
    });
  });

  group('secrets are not left on screen', () {
    testWidgets('a saved password is masked until revealed', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await start(tester);
      await createVault(tester, 'the master password');

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'My Bank',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'TopSecret-99-Password',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('My Bank'));
      await tester.pumpAndSettle();

      expect(
        find.text('TopSecret-99-Password'),
        findsNothing,
        reason: 'a password must not be on screen before it is revealed',
      );

      await tester.tap(find.byTooltip('Show'));
      await tester.pumpAndSettle();
      expect(find.text('TopSecret-99-Password'), findsOneWidget);
    });
  });

  group('locking', () {
    testWidgets('the lock button closes the vault and hides everything', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await start(tester);
      await createVault(tester, 'the master password');

      await tester.tap(find.byTooltip('Lock vault'));
      await tester.pumpAndSettle();

      expect(session.status, VaultStatus.locked);
      expect(session.data, isNull);
      expect(find.text('Enter your master password'), findsOneWidget);
    });
  });

  group('the generator', () {
    testWidgets('produces something and can be reached from the shell', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await start(tester);
      await createVault(tester, 'the master password');

      await tester.tap(find.byTooltip('Password generator'));
      await tester.pumpAndSettle();

      expect(find.text('Generator'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      final SelectableText shown = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(shown.data, isNotNull);
      expect(shown.data!.length, greaterThanOrEqualTo(8));
    });
  });
}
