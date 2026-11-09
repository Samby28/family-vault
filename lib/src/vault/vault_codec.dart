import 'dart:typed_data';

import '../core/failures.dart';
import '../crypto/crypto_service.dart';
import '../crypto/kdf_parameters.dart';
import 'vault_header.dart';

/// Turns a plaintext payload into a sealed vault file, and back.
///
/// This is the only place in the project that knows how the two halves of a
/// vault file fit together. It holds no state and keeps no key: a key is
/// derived for one operation and wiped in a `finally` block before the method
/// returns, including when the method throws.
final class VaultCodec {
  const VaultCodec(this._crypto);

  final CryptoService _crypto;

  /// Seals [payload] into a complete vault file.
  ///
  /// A fresh nonce is generated on every call, which is what keeps repeated
  /// writes under the same key safe. Pass [reuseSalt] when re-writing an
  /// existing vault, so that the user's password still derives the same key;
  /// omit it to start a new vault with a new salt.
  ///
  /// [parameters] defaults to the cryptographic library's recommendation.
  Uint8List seal({
    required String masterPassword,
    required Uint8List payload,
    Argon2idParameters? parameters,
    Uint8List? reuseSalt,
  }) {
    final Argon2idParameters costs =
        (parameters ?? _crypto.recommendedParameters).alignedToKib();
    costs.validate();

    final Uint8List salt = reuseSalt ?? _crypto.randomBytes(_crypto.saltLength);
    if (salt.length != _crypto.saltLength) {
      throw VaultFormatFailure(
        'The vault salt is ${salt.length} bytes; '
        '${_crypto.saltLength} were expected.',
      );
    }

    // A new nonce for every write. With a 192-bit nonce, drawing it at random
    // is safe without tracking a counter, which is the main reason this
    // project uses XChaCha20-Poly1305. See CipherId.xChaCha20Poly1305Ietf.
    final Uint8List nonce = _crypto.randomBytes(_crypto.nonceLength);

    final VaultHeader header = VaultHeader(
      formatVersion: VaultHeader.currentFormatVersion,
      kdfAlgorithm: KdfAlgorithmId.argon2id13,
      cipher: CipherId.xChaCha20Poly1305Ietf,
      kdfParameters: costs,
      salt: salt,
      nonce: nonce,
    );
    final Uint8List headerBytes = header.encode();

    final VaultKey key = _crypto.deriveKey(
      masterPassword: masterPassword,
      salt: salt,
      parameters: costs,
    );
    try {
      final Uint8List ciphertext = _crypto.seal(
        plaintext: payload,
        nonce: nonce,
        key: key,
        associatedData: headerBytes,
      );
      final Uint8List file =
          Uint8List(headerBytes.length + ciphertext.length);
      file.setRange(0, headerBytes.length, headerBytes);
      file.setRange(headerBytes.length, file.length, ciphertext);
      return file;
    } finally {
      key.dispose();
    }
  }

  /// Opens a sealed vault file and returns its plaintext payload.
  ///
  /// Throws a [VaultFailure] and never partial or unverified data. The order
  /// matters: the header is parsed and its parameters bounds-checked before
  /// any key derivation, so a hostile file cannot make the application
  /// allocate a gigabyte of memory before it is inspected.
  Uint8List open({
    required Uint8List file,
    required String masterPassword,
  }) {
    final VaultHeader header = VaultHeader.decode(file);

    final int headerLength = header.length;
    if (file.length < headerLength + _crypto.tagLength) {
      throw const VaultFormatFailure(
        'This vault file is truncated: there is no complete encrypted section '
        'after the header.',
      );
    }

    // Authenticate the header bytes exactly as they appear on disk, rather
    // than a re-encoded copy. If the two ever differed, this way verifies the
    // real file instead of our idea of it.
    final Uint8List headerBytes = Uint8List.fromList(
      file.sublist(0, headerLength),
    );
    final Uint8List ciphertext = Uint8List.fromList(
      file.sublist(headerLength),
    );

    final VaultKey key = _crypto.deriveKey(
      masterPassword: masterPassword,
      salt: header.salt,
      parameters: header.kdfParameters,
    );
    try {
      return _crypto.open(
        ciphertext: ciphertext,
        nonce: header.nonce,
        key: key,
        associatedData: headerBytes,
      );
    } finally {
      key.dispose();
    }
  }

  /// Reads a vault's header without needing the master password.
  ///
  /// Useful for showing a user what they are about to open, and for deciding
  /// whether this build can open it at all, before asking for a password.
  /// Reveals nothing about the contents: the header holds only format and cost
  /// information.
  VaultHeader inspect(Uint8List file) => VaultHeader.decode(file);
}
