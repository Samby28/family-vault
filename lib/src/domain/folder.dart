import 'package:meta/meta.dart';

import 'ids.dart';

/// A folder grouping vault items.
///
/// Folder names are stored inside the encrypted payload, so an observer who
/// holds the vault file cannot tell that a folder is called "Banking".
@immutable
final class Folder {
  const Folder({required this.id, required this.name, required this.createdAt});

  /// Creates a folder with a new identifier and the current time.
  factory Folder.create(String name, {DateTime? now}) =>
      Folder(id: Ids.generate(), name: name, createdAt: now ?? DateTime.now());

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
    return Folder(
      id: id,
      name: name,
      createdAt: created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// Folder identifier, stable across devices.
  final String id;

  /// Name the user chose.
  final String name;

  /// When the folder was created.
  final DateTime createdAt;

  /// A copy with a different name.
  Folder renamed(String newName) =>
      Folder(id: id, name: newName, createdAt: createdAt);

  /// Stored form.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt);
}
