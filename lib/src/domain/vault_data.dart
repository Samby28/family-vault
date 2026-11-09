import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/failures.dart';
import 'folder.dart';
import 'vault_item.dart';
import 'vault_settings.dart';

/// Everything a vault contains: the plaintext payload that gets encrypted.
///
/// Immutable. Every change returns a new instance, which is what lets the
/// session hold exactly one current value and write it out atomically.
@immutable
final class VaultData {
  const VaultData({
    this.schemaVersion = currentSchemaVersion,
    this.folders = const <Folder>[],
    this.items = const <VaultItem>[],
    this.settings = const VaultSettings(),
  });

  /// Schema version of the payload, separate from the file format version.
  ///
  /// The file format describes how bytes are protected; this describes what
  /// the decrypted contents mean. They change for different reasons, so they
  /// are versioned separately.
  static const int currentSchemaVersion = 1;

  /// An empty vault.
  static const VaultData empty = VaultData();

  /// Payload schema version.
  final int schemaVersion;

  /// Folders, in no particular order.
  final List<Folder> folders;

  /// Every item, including those in the trash.
  final List<VaultItem> items;

  /// Per-vault preferences.
  final VaultSettings settings;

  /// Items not in the trash.
  List<VaultItem> get liveItems =>
      items.where((VaultItem i) => !i.isDeleted).toList();

  /// Items in the trash.
  List<VaultItem> get trashedItems =>
      items.where((VaultItem i) => i.isDeleted).toList();

  /// Live items of one kind.
  List<VaultItem> itemsOfType(VaultItemType type) =>
      liveItems.where((VaultItem i) => i.type == type).toList();

  /// Live items in a folder, or with no folder when [folderId] is null.
  List<VaultItem> itemsInFolder(String? folderId) =>
      liveItems.where((VaultItem i) => i.folderId == folderId).toList();

  /// Live favourites.
  List<VaultItem> get favourites =>
      liveItems.where((VaultItem i) => i.favourite).toList();

  /// Live items with an authenticator key stored.
  List<VaultItem> get authenticatorItems =>
      liveItems.where((VaultItem i) => i.totpSecret.isNotEmpty).toList();

  /// The folder with this identifier, or null.
  Folder? folderById(String? id) {
    if (id == null) {
      return null;
    }
    for (final Folder folder in folders) {
      if (folder.id == id) {
        return folder;
      }
    }
    return null;
  }

  /// The item with this identifier, or null.
  VaultItem? itemById(String id) {
    for (final VaultItem item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  /// Live items matching [query] by title, username, email, website or folder.
  ///
  /// Matching runs here, on already-decrypted data in memory. Nothing is sent
  /// anywhere: there is no search service to send it to.
  ///
  /// Passwords and other secrets are deliberately not searched. Matching on a
  /// secret would let someone confirm a guessed value by typing it in.
  List<VaultItem> search(String query) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return liveItems;
    }
    return liveItems.where((VaultItem item) {
      if (item.title.toLowerCase().contains(needle)) {
        return true;
      }
      for (final String key in <String>[
        ItemField.username,
        ItemField.email,
        ItemField.url,
        ItemField.fullName,
        ItemField.cardholder,
      ]) {
        if (item.field(key).toLowerCase().contains(needle)) {
          return true;
        }
      }
      if (item.notes.toLowerCase().contains(needle)) {
        return true;
      }
      final Folder? folder = folderById(item.folderId);
      return folder != null && folder.name.toLowerCase().contains(needle);
    }).toList();
  }

  /// Adds an item, or replaces the existing one with the same identifier.
  VaultData upsertItem(VaultItem item) {
    final List<VaultItem> next = List<VaultItem>.of(items);
    final int index = next.indexWhere((VaultItem i) => i.id == item.id);
    if (index >= 0) {
      next[index] = item;
    } else {
      next.add(item);
    }
    return copyWith(items: next);
  }

  /// Moves an item to the trash. Its contents stay encrypted in the file.
  VaultData trashItem(String id, {DateTime? now}) {
    final VaultItem? item = itemById(id);
    if (item == null || item.isDeleted) {
      return this;
    }
    return upsertItem(
      item.copyWith(deletedAt: now ?? DateTime.now(), now: now),
    );
  }

  /// Takes an item back out of the trash.
  VaultData restoreItem(String id, {DateTime? now}) {
    final VaultItem? item = itemById(id);
    if (item == null || !item.isDeleted) {
      return this;
    }
    return upsertItem(item.copyWith(restore: true, now: now));
  }

  /// Removes an item for good.
  VaultData purgeItem(String id) =>
      copyWith(items: items.where((VaultItem i) => i.id != id).toList());

  /// Empties the trash.
  VaultData emptyTrash() => copyWith(items: liveItems);

  /// Adds a folder.
  VaultData addFolder(Folder folder) =>
      copyWith(folders: <Folder>[...folders, folder]);

  /// Renames a folder.
  VaultData renameFolder(String id, String name) => copyWith(
    folders: folders
        .map((Folder f) => f.id == id ? f.renamed(name) : f)
        .toList(),
  );

  /// Deletes a folder, leaving its items in place with no folder.
  ///
  /// Items are never deleted along with a folder. Losing entries because a
  /// folder was tidied away would be the worst kind of surprise in a password
  /// manager.
  VaultData deleteFolder(String id, {DateTime? now}) {
    final List<VaultItem> movedOut = items
        .map(
          (VaultItem i) =>
              i.folderId == id ? i.copyWith(clearFolder: true, now: now) : i,
        )
        .toList();
    return copyWith(
      folders: folders.where((Folder f) => f.id != id).toList(),
      items: movedOut,
    );
  }

  /// Replaces the settings.
  VaultData withSettings(VaultSettings next) => copyWith(settings: next);

  /// A copy with the given changes.
  VaultData copyWith({
    List<Folder>? folders,
    List<VaultItem>? items,
    VaultSettings? settings,
  }) => VaultData(
    schemaVersion: schemaVersion,
    folders: folders ?? this.folders,
    items: items ?? this.items,
    settings: settings ?? this.settings,
  );

  /// Stored form.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'folders': folders.map((Folder f) => f.toJson()).toList(),
    'items': items.map((VaultItem i) => i.toJson()).toList(),
    'settings': settings.toJson(),
  };

  /// Serialises the payload to the bytes that get encrypted.
  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Reads a payload from decrypted bytes.
  ///
  /// Throws [VaultFormatFailure] only when the payload as a whole is
  /// unusable. Individual items or folders that cannot be read are dropped and
  /// counted, so one damaged entry never costs the user the rest of the vault.
  /// Parses the decrypted bytes as JSON.
  ///
  /// Separated out so that a malformed payload and malformed UTF-8 both arrive
  /// as the same typed failure, rather than as a raw [FormatException] from
  /// somewhere inside the decoder.
  static Object? _parseJson(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const VaultFormatFailure(
        'The vault opened but its contents could not be read.',
      );
    }
  }

  static VaultDataDecoding decode(Uint8List bytes) {
    final Object? root = _parseJson(bytes);
    if (root is! Map<String, Object?>) {
      throw const VaultFormatFailure(
        'The vault opened but its contents were not in the expected form.',
      );
    }

    final Object? version = root['schemaVersion'];
    if (version is int && version > currentSchemaVersion) {
      throw VaultVersionFailure(
        'This vault was saved by a newer version of Family Vault. Please '
        'update the app to open it.',
        fileVersion: version,
      );
    }

    int droppedFolders = 0;
    final List<Folder> folders = <Folder>[];
    final Object? rawFolders = root['folders'];
    if (rawFolders is List<Object?>) {
      for (final Object? entry in rawFolders) {
        final Folder? folder = entry is Map<String, Object?>
            ? Folder.fromJson(entry)
            : null;
        if (folder == null) {
          droppedFolders++;
        } else {
          folders.add(folder);
        }
      }
    }

    int droppedItems = 0;
    final List<VaultItem> items = <VaultItem>[];
    final Object? rawItems = root['items'];
    if (rawItems is List<Object?>) {
      for (final Object? entry in rawItems) {
        final VaultItem? item = entry is Map<String, Object?>
            ? VaultItem.fromJson(entry)
            : null;
        if (item == null) {
          droppedItems++;
        } else {
          items.add(item);
        }
      }
    }

    final Object? rawSettings = root['settings'];
    return VaultDataDecoding(
      data: VaultData(
        folders: folders,
        items: items,
        settings: rawSettings is Map<String, Object?>
            ? VaultSettings.fromJson(rawSettings)
            : const VaultSettings(),
      ),
      droppedItems: droppedItems,
      droppedFolders: droppedFolders,
    );
  }
}

/// The result of reading a payload, including anything that had to be dropped.
@immutable
final class VaultDataDecoding {
  const VaultDataDecoding({
    required this.data,
    this.droppedItems = 0,
    this.droppedFolders = 0,
  });

  /// What was read successfully.
  final VaultData data;

  /// Items that could not be read and were left out.
  final int droppedItems;

  /// Folders that could not be read and were left out.
  final int droppedFolders;

  /// True when something had to be dropped, so the user can be told.
  bool get hadLosses => droppedItems > 0 || droppedFolders > 0;
}
