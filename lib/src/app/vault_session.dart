import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/failures.dart';
import '../crypto/crypto_service.dart';
import '../domain/folder.dart';
import '../domain/vault_data.dart';
import '../domain/vault_item.dart';
import '../domain/vault_settings.dart';
import '../vault/vault_codec.dart';
import '../vault/vault_repository.dart';

/// What state the vault is in.
enum VaultStatus {
  /// Still working out whether a vault exists.
  starting,

  /// No vault on this device yet; the user needs to create one.
  absent,

  /// A vault exists and is locked.
  locked,

  /// A vault is open and its contents are in memory.
  unlocked,
}

/// Holds the vault's state for the whole application.
///
/// One instance, created at startup. While unlocked it holds the decrypted
/// contents and the derived key; while locked it holds neither.
///
/// It deliberately does not keep the master password. The password is used
/// once, at unlock, to derive a key, and that key then lives in memory the
/// cryptographic library locks and can wipe. A Dart [String] cannot be wiped,
/// so keeping the password around would leave it on the heap for as long as
/// the process ran.
class VaultSession extends ChangeNotifier with WidgetsBindingObserver {
  VaultSession({required CryptoService crypto, required this.repository})
    : _codec = VaultCodec(crypto);

  final VaultCodec _codec;

  /// Where the vault is stored. Public because a private field cannot be a
  /// named initializing formal in Dart.
  final VaultRepository repository;

  VaultStatus _status = VaultStatus.starting;
  VaultData? _data;
  VaultKeyring? _keyring;
  String? _lastError;
  bool _busy = false;
  int _droppedOnOpen = 0;

  Timer? _lockTimer;
  Timer? _clipboardTimer;
  String? _clipboardValue;

  /// Current state.
  VaultStatus get status => _status;

  /// The decrypted vault, or null unless [status] is unlocked.
  VaultData? get data => _data;

  /// The last thing that went wrong, in plain language, or null.
  String? get lastError => _lastError;

  /// True while an operation that should block the interface is running.
  bool get isBusy => _busy;

  /// True when the vault is open.
  bool get isUnlocked => _status == VaultStatus.unlocked && _data != null;

  /// How many unreadable entries were dropped when the vault was opened.
  ///
  /// Non-zero means the file was damaged and the user should be told.
  int get droppedOnOpen => _droppedOnOpen;

  /// Settings of the open vault, or the defaults when locked.
  VaultSettings get settings => _data?.settings ?? const VaultSettings();

  /// Works out whether a vault exists. Call once at startup.
  Future<void> initialise() async {
    WidgetsBinding.instance.addObserver(this);
    _status = await repository.exists()
        ? VaultStatus.locked
        : VaultStatus.absent;
    notifyListeners();
  }

  /// Where the vault file is, for display in settings.
  Future<String> vaultLocation() => repository.location();

  /// Creates a new vault protected by [masterPassword].
  ///
  /// Returns true on success. Refuses if a vault already exists, so an
  /// accidental second creation cannot overwrite a real one.
  Future<bool> createVault(String masterPassword) async {
    if (await repository.exists()) {
      _fail('A vault already exists on this device.');
      return false;
    }
    return _guard(() async {
      final VaultKeyring keyring = _codec.createKeyring(
        masterPassword: masterPassword,
      );
      const VaultData fresh = VaultData.empty;
      await repository.write(
        _codec.sealWith(keyring: keyring, payload: fresh.encode()),
      );
      _keyring = keyring;
      _data = fresh;
      _droppedOnOpen = 0;
      _status = VaultStatus.unlocked;
      _restartLockTimer();
      return true;
    });
  }

  /// Opens the vault with [masterPassword]. Returns true on success.
  Future<bool> unlock(String masterPassword) => _guard(() async {
    final Uint8List file = await repository.read();
    final OpenedVault opened = _codec.unlock(
      file: file,
      masterPassword: masterPassword,
    );
    try {
      final VaultDataDecoding decoded = VaultData.decode(opened.payload);
      _keyring = opened.keyring;
      _data = decoded.data;
      _droppedOnOpen = decoded.droppedItems + decoded.droppedFolders;
      _status = VaultStatus.unlocked;
      _restartLockTimer();
      return true;
    } on Object {
      // The payload decrypted but could not be understood, so the key is of
      // no use and must not be kept.
      opened.keyring.dispose();
      rethrow;
    }
  });

  /// Closes the vault, wiping the key and the decrypted contents.
  void lock() {
    _lockTimer?.cancel();
    _lockTimer = null;
    _keyring?.dispose();
    _keyring = null;
    _data = null;
    _droppedOnOpen = 0;
    _lastError = null;
    if (_status == VaultStatus.unlocked) {
      _status = VaultStatus.locked;
    }
    notifyListeners();
  }

  /// Records that the user did something, restarting the inactivity timer.
  ///
  /// Called from a wrapper around the whole interface, so any touch, key press
  /// or scroll counts.
  void touch() {
    if (_status == VaultStatus.unlocked) {
      _restartLockTimer();
    }
  }

  /// Deletes the vault from this device for good.
  ///
  /// The interface asks for confirmation before calling this; there is no way
  /// back from it.
  Future<bool> deleteVault() => _guard(() async {
    await repository.delete();
    _keyring?.dispose();
    _keyring = null;
    _data = null;
    _status = VaultStatus.absent;
    return true;
  });

  // ---------------------------------------------------------------- contents

  /// Adds or replaces an item and saves.
  Future<bool> saveItem(VaultItem item) =>
      _mutate((VaultData d) => d.upsertItem(item));

  /// Moves an item to the trash and saves.
  Future<bool> trashItem(String id) =>
      _mutate((VaultData d) => d.trashItem(id));

  /// Takes an item out of the trash and saves.
  Future<bool> restoreItem(String id) =>
      _mutate((VaultData d) => d.restoreItem(id));

  /// Deletes an item for good and saves.
  Future<bool> purgeItem(String id) =>
      _mutate((VaultData d) => d.purgeItem(id));

  /// Empties the trash and saves.
  Future<bool> emptyTrash() => _mutate((VaultData d) => d.emptyTrash());

  /// Turns an item's favourite flag on or off and saves.
  Future<bool> toggleFavourite(String id) => _mutate((VaultData d) {
    final VaultItem? item = d.itemById(id);
    if (item == null) {
      return d;
    }
    return d.upsertItem(item.copyWith(favourite: !item.favourite));
  });

  /// Creates a folder and saves.
  Future<bool> addFolder(String name) =>
      _mutate((VaultData d) => d.addFolder(Folder.create(name)));

  /// Renames a folder and saves.
  Future<bool> renameFolder(String id, String name) =>
      _mutate((VaultData d) => d.renameFolder(id, name));

  /// Deletes a folder, keeping its items, and saves.
  Future<bool> deleteFolder(String id) =>
      _mutate((VaultData d) => d.deleteFolder(id));

  /// Replaces the vault's settings and saves.
  Future<bool> updateSettings(VaultSettings next) async {
    final bool saved = await _mutate((VaultData d) => d.withSettings(next));
    if (saved) {
      // The new timeout takes effect at once rather than after the next unlock.
      _restartLockTimer();
    }
    return saved;
  }

  /// Changes the master password, re-encrypting the whole vault.
  ///
  /// The contents are unchanged; a new salt and key are derived, so the old
  /// password cannot open the new file.
  Future<bool> changeMasterPassword(String newPassword) {
    final VaultData? current = _data;
    if (current == null) {
      _fail('Unlock the vault before changing its password.');
      return Future<bool>.value(false);
    }
    return _guard(() async {
      final VaultKeyring replacement = _codec.createKeyring(
        masterPassword: newPassword,
      );
      await repository.write(
        _codec.sealWith(keyring: replacement, payload: current.encode()),
      );
      _keyring?.dispose();
      _keyring = replacement;
      return true;
    });
  }

  /// Produces an encrypted copy of the vault, for the user to keep elsewhere.
  ///
  /// Protected by its own password, so a backup can be given a different one.
  Uint8List? exportEncrypted(String password) {
    final VaultData? current = _data;
    if (current == null) {
      _fail('Unlock the vault before exporting it.');
      return null;
    }
    try {
      return _codec.seal(masterPassword: password, payload: current.encode());
    } on VaultFailure catch (failure) {
      _fail(failure.message);
      return null;
    }
  }

  // --------------------------------------------------------------- clipboard

  /// Copies [value] to the clipboard and schedules it to be cleared.
  ///
  /// Clearing only happens if the clipboard still holds this value, so it
  /// never wipes something the user copied in the meantime.
  Future<void> copyToClipboard(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _clipboardTimer?.cancel();
    _clipboardValue = value;
    final int seconds = settings.clipboardClearSeconds;
    if (seconds <= 0) {
      return;
    }
    _clipboardTimer = Timer(Duration(seconds: seconds), _clearClipboard);
  }

  Future<void> _clearClipboard() async {
    final String? expected = _clipboardValue;
    _clipboardValue = null;
    if (expected == null) {
      return;
    }
    final ClipboardData? current = await Clipboard.getData('text/plain');
    if (current?.text == expected) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }

  // ------------------------------------------------------------- app lifecyle

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Locked when the app leaves the screen, not merely when it loses focus:
    // on a desktop, clicking another window should not lock the vault, but a
    // phone going back to its home screen should.
    final bool offScreen =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (offScreen && isUnlocked && settings.lockWhenHidden) {
      lock();
    }
  }

  // ----------------------------------------------------------------- plumbing

  void _restartLockTimer() {
    _lockTimer?.cancel();
    final int minutes = settings.autoLockMinutes;
    if (minutes <= 0) {
      _lockTimer = null;
      return;
    }
    _lockTimer = Timer(Duration(minutes: minutes), lock);
  }

  /// Applies [change] to the open vault and writes the result.
  ///
  /// The in-memory copy is only replaced after the write succeeds, so a failed
  /// save leaves the interface showing what is actually on disk rather than an
  /// edit that was never stored.
  Future<bool> _mutate(VaultData Function(VaultData data) change) {
    final VaultData? current = _data;
    final VaultKeyring? keyring = _keyring;
    if (current == null || keyring == null) {
      _fail('The vault is locked.');
      return Future<bool>.value(false);
    }
    return _guard(() async {
      final VaultData next = change(current);
      await repository.write(
        _codec.sealWith(keyring: keyring, payload: next.encode()),
      );
      _data = next;
      _restartLockTimer();
      return true;
    });
  }

  /// Runs [action], turning any failure into a message a user can read.
  Future<bool> _guard(Future<bool> Function() action) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      return await action();
    } on VaultFailure catch (failure) {
      _lastError = failure.message;
      return false;
    } on StateError catch (error) {
      _lastError = error.message;
      return false;
    } on Object catch (error) {
      // Nothing here includes the vault contents or the password: only the
      // type of what went wrong, so a log cannot leak a secret.
      _lastError = 'Something went wrong: ${error.runtimeType}.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _fail(String message) {
    _lastError = message;
    notifyListeners();
  }

  /// Clears the last error, after the interface has shown it.
  void clearError() {
    if (_lastError != null) {
      _lastError = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    _clipboardTimer?.cancel();
    _keyring?.dispose();
    _data = null;
    super.dispose();
  }
}
