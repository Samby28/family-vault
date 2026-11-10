import 'package:meta/meta.dart';

import 'ids.dart';

/// A folder grouping vault items.
///
/// Folder names are stored inside the encrypted payload, so an observer who
/// holds the vault file cannot tell that a folder is called "Banking".
@immutable
final class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    DateTime? updatedAt,
  }) : _updatedAt = updatedAt;

  /// Creates a folder with a new identifier and the current time.
  factory Folder.create(String name, {DateTime? now}) {
    final DateTime stamp = now ?? DateTime.now();
    return Folder(
      id: Ids.generate(),
      name: name,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  /// Reads a folder from its stored form.
  ///
  /// Returns null rather than throwing when the entry is unusable, so that one
  /// damaged folder cannot make an otherwise good vault unopenable.
  static Folder? fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? name = json['name'];
    final Object? createdAt = json['createdAt'];
    if (id is! String || !Ids.isValid(id) || name is! String) {
      return null;
    }
    final DateTime? created = createdAt is String
        ? DateTime.tryParse(createdAt)
        : null;
    final Object? updated = json['updatedAt'];
    return Folder(
      id: id,
      name: name,
      createdAt: created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      // Absent in schema 1, where a folder had no change stamp. [updatedAt]
      // then falls back to the creation time.
      updatedAt: updated is String ? DateTime.tryParse(updated) : null,
    );
  }

  /// Folder identifier, stable across devices.
  final String id;

  /// Name the user chose.
  final String name;

  /// When the folder was created.
  final DateTime createdAt;

  final DateTime? _updatedAt;

  /// When the folder was last changed, falling back to [createdAt].
  ///
  /// This exists for merging two devices. If the same folder was renamed on
  /// both while they were apart, this is the only thing that says which rename
  /// came later — without it, a merge would have to guess.
  DateTime get updatedAt => _updatedAt ?? createdAt;

  /// A copy with a different name, stamped as changed.
  Folder renamed(String newName, {DateTime? now}) => Folder(
    id: id,
    name: newName,
    createdAt: createdAt,
    updatedAt: now ?? DateTime.now(),
  );

  /// Stored form.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt, updatedAt);
}
