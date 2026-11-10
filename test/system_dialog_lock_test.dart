import 'dart:typed_data';

import 'package:family_vault/src/app/vault_session.dart';
import 'package:family_vault/src/domain/vault_item.dart';
import 'package:family_vault/src/domain/vault_settings.dart';
import 'package:family_vault/src/platform/file_transfer.dart';
import 'package:family_vault/src/platform/guarded_file_transfer.dart';
import 'package:family_vault/src/vault/vault_merge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_crypto_service.dart';
import 'support/fake_file_transfer.dart';
import 'support/in_memory_device_settings.dart';
import 'support/in_memory_vault_repository.dart';

/// The background lock versus the system file picker.
///
/// A regression suite for a bug that made EVERY file operation on Android
/// impossible, and that the existing tests could not have caught: the fake
/// picker returned in-process, so the app never went to the background the
/// way a real Android picker sends it there.
///
/// On Android the picker and the share sheet are separate screens. Opening
/// one backgrounds this app, "lock when the app is hidden" did exactly what
/// it says, and the key was wiped while the user was still choosing the file
/// they meant to import. They came back holding it with nothing open to put
/// it in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCryptoService crypto;
  late InMemoryVaultRepository repository;
  late InMemoryDeviceSettingsStore deviceStore;
  late FakeFileTransfer files;
  late VaultSession session;
  late GuardedFileTransfer guarded;

  setUp(() {
    crypto = FakeCryptoService();
    repository = InMemoryVaultRepository();
    deviceStore = InMemoryDeviceSettingsStore();
    files = FakeFileTransfer();
    session = VaultSession(
      crypto: crypto,
      repository: repository,
      deviceSettings: deviceStore,
    );
    guarded = GuardedFileTransfer(inner: files, session: session);
  });

  tearDown(() => session.dispose());

  /// Sends the app off screen, as Android does when a picker opens.
  void goesToBackground() =>
      session.didChangeAppLifecycleState(AppLifecycleState.paused);

  Future<void> openVault() async {
    await session.createVault('master password for the test');
    await session.saveItem(
      VaultItem.create(
        type: VaultItemType.login,
        title: 'Bank',
        fields: const <String, String>{ItemField.password: 'a-password-99'},
      ),
    );
  }

  group('the bug itself', () {
    test('the vault survives a picker that backgrounds the app', () async {
      await openVault();
      files.nextPick = PickedFile(name: 'b.fvault', bytes: Uint8List(0));
      files.whileDialogOpen = () async => goesToBackground();

      await guarded.pick();

      expect(
        session.isUnlocked,
        isTrue,
        reason:
            'this is the bug: the key was wiped mid-pick, leaving the '
            'import with nothing to merge into',
      );
      expect(session.data!.liveItems, hasLength(1));
    });

    test('and the file picked that way can still be imported', () async {
      await openVault();
      final Uint8List backup = session.exportEncrypted('the backup password')!;
      files.nextPick = PickedFile(name: 'b.fvault', bytes: backup);
      files.whileDialogOpen = () async => goesToBackground();

      final PickedFile? chosen = await guarded.pick();
      final BackupContents? read = await session.readBackup(
        file: chosen!.bytes,
        password: 'the backup password',
      );
      final MergeOutcome? outcome = await session.mergeBackup(read!);

      expect(outcome, isNotNull, reason: session.lastError);
      expect(session.isUnlocked, isTrue);
    });
  });

  group('every file operation, not only the import', () {
    setUp(() async {
      await openVault();
      files.whileDialogOpen = () async => goesToBackground();
    });

    test('sharing a copy survives it', () async {
      await guarded.save(
        suggestedName: 'b.fvault',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      expect(session.isUnlocked, isTrue);
    });

    test('choosing a shared folder survives it', () async {
      files.nextFolder = '/shared';

      expect(await guarded.pickFolder(), '/shared');
      expect(session.isUnlocked, isTrue);
    });
  });

  group('the setting still does its job', () {
    test('backgrounding locks when no dialog is open', () async {
      // The fix narrows the rule; it does not remove it. Switching to another
      // app by hand must still lock the vault.
      await openVault();

      goesToBackground();

      expect(session.isUnlocked, isFalse);
    });

    test('the suppression is off again once the dialog returns', () async {
      await openVault();
      files.whileDialogOpen = () async => goesToBackground();
      await guarded.pick();
      expect(session.inSystemDialog, isFalse);

      // This one is a real background: the user switched apps.
      goesToBackground();

      expect(session.isUnlocked, isFalse);
    });

    test('a user who turned the setting off is still obeyed', () async {
      await openVault();
      await session.updateSettings(const VaultSettings(lockWhenHidden: false));

      goesToBackground();

      expect(session.isUnlocked, isTrue);
    });
  });

  group('a dialog left open too long', () {
    test('locks the vault as soon as it returns', () async {
      // The phone was put down on the file picker, or the user wandered off
      // to another app from it. Suppressing the lock indefinitely would leave
      // an unlocked vault on a handset lying on a table.
      await openVault();
      session.systemDialogGrace = Duration.zero;
      files.nextPick = PickedFile(name: 'b.fvault', bytes: Uint8List(0));
      files.whileDialogOpen = () async {
        goesToBackground();
        await Future<void>.delayed(const Duration(milliseconds: 2));
      };

      await guarded.pick();

      expect(session.isUnlocked, isFalse);
    });

    test(
      'so the operation fails safely instead of quietly proceeding',
      () async {
        await openVault();
        final Uint8List backup = session.exportEncrypted(
          'the backup password',
        )!;
        session.systemDialogGrace = Duration.zero;
        files.nextPick = PickedFile(name: 'b.fvault', bytes: backup);
        files.whileDialogOpen = () async {
          goesToBackground();
          await Future<void>.delayed(const Duration(milliseconds: 2));
        };

        final PickedFile? chosen = await guarded.pick();
        final BackupContents? read = await session.readBackup(
          file: chosen!.bytes,
          password: 'the backup password',
        );

        expect(await session.mergeBackup(read!), isNull);
        expect(session.lastError, contains('Unlock'));
      },
    );

    test(
      'respects the setting being off, the same as any other lock',
      () async {
        await openVault();
        await session.updateSettings(
          const VaultSettings(lockWhenHidden: false),
        );
        session.systemDialogGrace = Duration.zero;
        files.whileDialogOpen = () async =>
            Future<void>.delayed(const Duration(milliseconds: 2));

        await guarded.pick();

        expect(session.isUnlocked, isTrue);
      },
    );
  });

  group('bookkeeping', () {
    test('two overlapping dialogs both have to finish', () async {
      await openVault();

      await session.duringSystemDialog(() async {
        await session.duringSystemDialog(() async {
          expect(session.inSystemDialog, isTrue);
        });
        expect(
          session.inSystemDialog,
          isTrue,
          reason: 'the inner dialog finishing must not unguard the outer one',
        );
        goesToBackground();
      });

      expect(session.inSystemDialog, isFalse);
      expect(session.isUnlocked, isTrue);
    });

    test('a dialog that throws still releases the suppression', () async {
      await openVault();

      await expectLater(
        session.duringSystemDialog(
          () async => throw StateError('the picker died'),
        ),
        throwsStateError,
      );

      expect(session.inSystemDialog, isFalse);
      goesToBackground();
      expect(session.isUnlocked, isFalse);
    });
  });
}
