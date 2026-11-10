import 'package:flutter/foundation.dart';

import '../app/vault_session.dart';
import 'file_transfer.dart';

/// A [FileTransfer] that holds off the background lock while a system dialog
/// it opened is on screen.
///
/// This exists because of a bug that made every file operation on Android
/// impossible. The file picker and the share sheet are separate screens there,
/// so opening one sends this app to the background; the vault's own
/// "lock when the app is hidden" setting did exactly what it says and wiped
/// the key, and the user came back holding a file with nothing open to put it
/// in. On Windows the dialog is in-process and the app never backgrounds,
/// which is why it showed up on one platform only.
///
/// A decorator rather than a call at each site, wrapped once around the real
/// transfer where the scope is built, so a new screen that picks a file cannot
/// forget to guard itself. [VaultSession.duringSystemDialog] carries the time
/// bound that keeps the suppression honest.
final class GuardedFileTransfer implements FileTransfer {
  const GuardedFileTransfer({required this.inner, required this.session});

  /// The real transfer doing the work.
  final FileTransfer inner;

  /// The session whose background lock is held off.
  final VaultSession session;

  @override
  bool get hasSaveDialog => inner.hasSaveDialog;

  @override
  Future<SaveResult> save({
    required String suggestedName,
    required Uint8List bytes,
  }) => session.duringSystemDialog(
    () => inner.save(suggestedName: suggestedName, bytes: bytes),
  );

  @override
  Future<PickedFile?> pick() => session.duringSystemDialog(inner.pick);

  @override
  Future<String?> pickFolder() => session.duringSystemDialog(inner.pickFolder);
}
