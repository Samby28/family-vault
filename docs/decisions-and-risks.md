# Family Vault — Design Decisions and Risk Register

**Version:** 1.0 · **Date:** 9 November 2026

Every decision here was taken without consulting the project owner, as the engagement
directs. Each records what was chosen, what was rejected, and why. Where a decision
deviates from a literal reading of the source documents, the deviation is stated plainly.

---

## Part 1 — Design decisions

### D-001 · CI is the build and compile environment

**Decision.** All compilation, analysis, testing and packaging happens in GitHub Actions.
No build is attempted in the authoring environment.

**Why.** The authoring environment has no Flutter or Android SDK and its network policy
refuses `pub.dev`, `dl.google.com`, `maven.google.com` and `services.gradle.org`. This was
verified by direct connection attempts, not assumed.

**Consequence.** Turnaround on a compile error is one CI run rather than one second. The
pipeline is therefore ordered to fail fast and cheap: format, then analyze, then test,
then build.

---

### D-002 · Phase 1 ships with no third-party runtime dependencies

**Decision.** The Stage 1 scaffold depends only on the Flutter SDK itself. Third-party
packages are introduced one per commit from Stage 2 onward, each confirmed green in CI
before the next is added.

**Why.** A package version cannot be resolved or verified here. Declaring several unknown
dependencies at once would make the first build fail for reasons that are hard to
separate. Starting at zero makes the first build near-certain, which establishes the
pipeline as a reliable signal before it is relied upon.

**Rejected.** Declaring the full Stage 2 dependency set now and fixing fallout. Faster if
it works, considerably slower if it does not, and it would delay the first installable
APK, which the build route document makes an early priority.

---

### D-003 · XChaCha20-Poly1305 and Argon2id, both from libsodium

**Decided 9 November 2026**, on evidence from three CI probe runs rather than
on preference.

**Decision.** The cipher is XChaCha20-Poly1305 (IETF construction) and the key
derivation is Argon2id, both from libsodium through `package:sodium` 4.1.2+1.

**How the alternative was ruled out.** `package:cryptography` was the only
serious pure-Dart candidate. Its own listing records that the repository moved
"due to lack of maintenance", and it carries discontinued dependencies. D-003
named active maintenance as the deciding factor, so it was out on that ground
alone. The deeper problem was Argon2id: it is memory-hard by design, so a
pure-Dart implementation would make unlocking slow on a phone, and lowering the
cost to compensate is exactly the wrong trade for a password manager.

**Why XChaCha20-Poly1305 over AES-256-GCM.** Its nonce is 192 bits. At that
size a nonce can be drawn at random for every single write with no realistic
chance of a repeat, which removes nonce management — and with it the
counter-handling mistake that breaks AES-GCM catastrophically. AES-GCM's
96-bit nonce is too short for that to be safe, so it would need a counter
persisted across writes and devices, which is precisely the kind of state that
goes wrong during a cloud sync conflict. Hardware-accelerated AES would have
been faster, but the payload here is a vault file of kilobytes, so throughput
is irrelevant and safety is not.

**What the probes established.**

| Probe | Run | Finding |
|---|---|---|
| 1 | 42618366937 | `sodium` resolves; an Android APK and a Windows application both still build with libsodium added; libsodium 1.0.18 installs on the Linux runner |
| 1 | 42618366937 | No `pwhash.dart` in the base API — Argon2id is in the "sumo" interface, not the default one |
| 2 | 42619562544 | `SodiumSumoInit.init()` uses a bundled libsodium, so no dynamic-library loader is needed; `Aead.encrypt`/`decrypt` accept `additionalData`, which is what lets the header be authenticated; `sodium_libs` is **deprecated**, with everything moved into `sodium` |
| 3 | 42620302996 | `CryptoPwhashAlgorithm.argon2id13` is the explicit Argon2id value; `sodium` alone builds on both platforms without the deprecated wrapper |
| 4 | 42624506031 | Correction to probe 2: `SodiumSumoInit.init()` returns `FutureOr<SodiumSumo>`, not `SodiumSumo`. The signature probe 2 read was the FFI-specific one; the conditional export resolves to a declaration that may be asynchronous, because the web build has to load a WebAssembly module first. Initialisation is therefore awaited, which covers both targets from one call site |

**Consequences recorded elsewhere.** Argon2id is named explicitly at the call
site rather than left to the library default, because the same call also offers
Argon2i and a password manager should not infer which function protects the
vault. `sodium_libs` is not used. The header reserves an algorithm identifier
for both the KDF and the cipher, so a future third option needs no format
break.

### D-004 · Platform projects are generated, then committed

**Decision.** The `android/`, `windows/` and `web/` directories are generated by
`flutter create` in CI on the first run via `tool/bootstrap_platforms.sh`, and will then
be committed to the repository so the project is self-contained for a reviewer.

**Why.** Hand-writing a Gradle and CMake project blind is a large, needless risk; Flutter's
own templates are correct by construction. The script copies a platform directory only if
it is absent, so once the real files are committed it never overwrites them.

**Consequence for assessment.** A reviewer who clones the repository after Stage 1 gets a
complete, buildable project. Between now and that commit, the script closes the gap.

---

### D-005 · No state-management library in Stage 1

**Decision.** The Stage 1 shell uses Flutter's own `StatefulWidget`. A state-management
library is chosen in Stage 3, when there is real state to manage.

**Why.** Picking Riverpod, Bloc or Provider now would mean an unverifiable dependency in
the first build for no present benefit, contradicting D-002. The layered architecture
already isolates the presentation layer, so introducing a library later touches only that
layer.

---

### D-006 · Release APK is debug-signed in Phase 1

**Decision.** The Android release APK is signed with Flutter's default debug key until a
release keystore exists.

**Why.** A real signing key must be generated by the owner and held as a repository
secret; it cannot be created here, and committing one to a public repository would be a
serious error. A debug-signed APK installs and runs correctly for family use and faculty
assessment.

**Stated limitation.** A debug-signed APK is not suitable for Play Store distribution and
shows an "unknown developer" warning on install. Recorded in `docs/known-limitations.md`.

---

### D-007 · The web demo is a separate, data-isolated build

**Decision.** The web demonstration is built from the same codebase behind a compile-time
demo flag. It is seeded with synthetic data, labelled as a demonstration in the interface,
and has no access to a real vault file.

**Why.** Browser storage is not a safe place for a real vault, and the demo exists for
assessment rather than use. A compile-time flag, rather than a runtime setting, means the
demo build physically cannot open a real vault file.

---

### D-008 · Vault header is plaintext but authenticated

**Decision.** The format version, KDF parameters, salt, cipher identifier and nonce are
stored unencrypted, and are covered by the AEAD authentication tag as associated data.

**Why.** They are required *in order to* derive the key, so they cannot be encrypted under
it. Authenticating them means tampering invalidates the file instead of silently weakening
it — for instance, an attacker lowering the Argon2id cost to make a brute-force cheaper.

**Accepted exposure.** An attacker holding the file learns that it is a Family Vault file,
its format version and its KDF cost. None of these reveal anything about the contents.

---

### D-009 · Argon2id parameters validated against bounds before use

**Decision.** Parameters read from a vault header are checked against a permitted range
before any memory is allocated.

**Why.** The parameters come from a file, and a file can be hostile. A header claiming
16 GB of memory cost would otherwise crash or hang the app on open — a denial-of-service
triggered by a file the user merely received. This is required by MP 5.3 and is a security
test case, not a nicety.

---

### D-010 · No TOTP gate on vault opening

**Decision.** Optional second-factor protection is implemented as key-file or FIDO2
hardware-key material mixed into key derivation. A TOTP code check is not offered for
opening a vault.

**Why.** With no server, an in-app code check is enforced by code the attacker controls,
on a file they already hold. It could be bypassed by patching the app or reading the file
directly, while giving the user a false sense of protection. A key file or hardware key
genuinely changes the decryption key and cannot be bypassed.

**This matches the source documents** and was the subject of the owner's explicit
instruction that vault 2FA be optional. The built-in TOTP authenticator for the user's
*other* accounts is unaffected and is a Phase 1 feature.

---

## Part 2 — Risk register

Likelihood and impact are rated Low, Medium or High. Risks are ordered by current
priority.

| ID | Risk | Likelihood | Impact | Mitigation | Owner |
|---|---|---|---|---|---|
| ~~R-001~~ | ~~Pushes to the repository are refused~~ **CLOSED 9 Nov 2026**: the first push succeeded | — | — | — | — |
| R-002 | First CI build fails on an unforeseen toolchain detail | High | Medium | Zero dependencies in Stage 1; fail-fast pipeline ordering; logs read and fixed per MP 17 | Agent |
| ~~R-003~~ | ~~No Dart Argon2id library builds cleanly on both Android and Windows~~ **CLOSED 9 Nov 2026**: libsodium builds on both; verified by CI runs 42618366937 and 42620302996 | — | — | Resolved by decision D-003 | — |
| R-004 | Owner loses a master password and the vault becomes unrecoverable | Medium | **High** — permanent data loss | Explicit warnings at creation; Phase 2 recovery sheet; no false promise of recovery | Shared |
| R-005 | Android autofill proves unreliable across OEM skins | Medium | Medium | Built last in Phase 1, after the vault is stable; documented honestly if partial | Agent |
| R-006 | A real credential is committed to the public repository | Low | **High** — irreversible exposure | `.gitignore` blocks vault and key extensions; synthetic data only; no secret ever requested in chat | Agent |
| R-007 | Flutter Windows desktop limitations block a required control | Low | Medium | Windows targeted first so problems surface early; limitations documented rather than worked around insecurely | Agent |
| R-008 | Cloud-drive sync corrupts a vault through a race between two devices | Medium | High | Phase 2 conflict detection; never overwrite a newer file; integrity check before replacing a local vault | Agent |
| R-009 | Scope grows beyond what one project can deliver | Medium | Medium | Three-phase roadmap treated as authoritative; Phase 1 acceptance criteria fixed in the checklist | Shared |
| R-010 | Debug-signed APK is mistaken for production-ready | Low | Low | Stated in the known-limitations document and in the release notes | Agent |

### Risks accepted without further mitigation

- **A compromised device defeats the design.** If malware has the device while the vault
  is unlocked, it can read the decrypted contents from memory. No password manager solves
  this, and Family Vault does not claim to.
- **File size leaks a rough item count.** Mitigating this would require padding the
  payload to fixed blocks. Judged not worth the complexity for a family tool; recorded
  rather than hidden.

---

## Part 3 — Open questions requiring owner input

Only items that genuinely need a decision from the owner appear here. Everything else has
been decided above.

| # | Question | Needed by | Default if no answer |
|---|---|---|---|
| 1 | Authorise the Claude GitHub App for `Samby28/family-vault` so builds can run | Immediately | None. This is a hard blocker. |
| 2 | Enable GitHub Pages for the repository so the web demo gets a public URL | Before faculty review | Web demo artifact downloadable from CI instead of a live link |
| 3 | Which cloud drive the family actually uses (Google Drive, OneDrive, something else) | Start of Phase 2 | Local file plus manual copy; sync layer built provider-independent regardless |
