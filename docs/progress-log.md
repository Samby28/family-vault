# Family Vault — Development Progress Log

A running record of what was built, what was tested, what passed and what failed.
Newest entry first. Statuses are **NOT STARTED · IN PROGRESS · COMPLETED ·
TESTING · BLOCKED**.

The rule applied throughout: a feature is COMPLETED only when its code exists and
tests covering it pass in CI. A screen that renders is not a completed feature.

---

## Stage summary

| Stage | Deliverable | Status |
|---|---|---|
| 1 | Flutter scaffold and GitHub Actions build pipeline | **COMPLETED** — green on all jobs, run 42612638343 |
| 2 | Cryptographic core: Argon2id, authenticated encryption, vault format, tests | NOT STARTED |
| 3 | Vault interface: folders, logins, notes, cards, identities, generator, search, lock screen, trash | NOT STARTED |
| 4 | TOTP authenticator and password-health reporting | NOT STARTED |
| 5 | Android autofill integration | NOT STARTED |
| 6 | Encrypted cloud-drive synchronisation and Phase 2 integrations | NOT STARTED |

---

## 2026-11-09 — Stage 1 closed: pipeline green on all platforms

**Status: COMPLETED.** CI run `42612638343` on commit `83e45b6` is green on all
three jobs. Four pushes were needed; each failure, including one I misreported,
is recorded below.

### Evidence

| Check | Result |
|---|---|
| Toolchain | Flutter 3.47.9, stable, now pinned in all workflows |
| `dart format` | PASS, blocking |
| `flutter analyze` | PASS, no issues |
| `flutter test` | **11 of 11 passed** |
| Android release APK | **Built, 45.8 MB** (`app-release.apk`, 21.5 MB compressed artifact) |
| Windows release build | **Built**, `family_vault.exe` (11.3 MB compressed artifact) |
| Web demonstration | **Built**, downloadable artifact; live URL blocked on Pages |
| Coverage | Collected and uploaded |

### Build failures, and how each was fixed

Four CI runs were needed. Per MP 17, each is recorded rather than hidden.

| # | Run | Failed at | Cause | Fix |
|---|---|---|---|---|
| 1 | 42609591764 | `flutter analyze` | `dangling_library_doc_comments` in `build_info.dart` — a file-level doc comment with no `library` directive to attach to | Added `library;` |
| 2 | 42610134562 | `dart format` | **A failure I had misreported.** Run 1 showed the format step as "success", so I stated in a commit message that the hand-written source was already format-clean. It was not: the step carried `continue-on-error`, which reports a step as successful even when the command fails. Making the check blocking is what exposed it. | Corrected the record in the next commit message; added a step that prints the formatter's diff on failure, since this environment has no Dart SDK to run the formatter |
| 3 | 42610812140 | `dart format` | Two test files laid out differently from the formatter's preference | Applied the printed diff verbatim rather than guessing |
| 4 | 42611264390 | — | — | **Green.** APK and Windows build both produced |

The lesson from failure 2 is now a standing rule for this project: **`continue-on-error`
makes a step report success, so it hides exactly what CI exists to reveal.** It is
used only where a failure is genuinely acceptable, and where it is used, a
following step states plainly what failed and what to do about it. The Pages
deployment is the one remaining place it appears, and it now does that.

### Also done in this stage

- **Platform projects committed.** `android/`, `windows/` and `web/` were
  generated in CI from Flutter 3.47.9's templates and committed, along with the
  resolved `pubspec.lock`. The repository is now self-contained: a reviewer can
  clone it and run `flutter build` with no extra step. The one-time bootstrap
  workflow was removed; `tool/bootstrap_platforms.sh` stays as a no-op for a
  clean tree.
- **Product names corrected.** The generated templates carried the Dart package
  name `family_vault` into the Android launcher label, the Windows title bar and
  file properties, and the web page title. All are now "Family Vault". Identifiers
  (`applicationId`, `namespace`, Kotlin package, `BINARY_NAME`) were deliberately
  left alone, because an application identifier is a permanent identity and
  changing it later would stop an installed app upgrading in place.
- **Flutter pinned** to 3.47.9 so builds stay reproducible and the toolchain is
  raised deliberately rather than drifting with the stable channel.

### Blocked

**Open question 2 — GitHub Pages is not enabled**, so the web demonstration has
no public URL. The build itself succeeds and the demo is downloadable from the
`family-vault-web-demo` artifact, so nothing is lost but the shareable link.

*Owner action:* at **Settings → Pages**, set Source to **GitHub Actions**. The
next push publishes it to `https://samby28.github.io/family-vault/`.

R-001 (no write access) is **closed** — the first push succeeded.

### Not yet verified

| Not verified | Resolved by |
|---|---|
| The APK installs and runs on a real phone | Owner installing it from the Releases page |
| The Windows build runs on a real Windows machine | Owner unzipping and running it |
| Behaviour on a physical device of any kind | Owner testing |

Nothing has run outside a CI container. The builds exist and are green; that is
not the same as having been used.

---

## 2026-11-09 — Stage 1: scaffold and pipeline

**Status: superseded by the entry above, which closes this stage.** At the time
of writing, nothing had been compiled or executed, because the authoring
environment has no Flutter or Android SDK
and its network policy refuses `pub.dev`, `dl.google.com`, `maven.google.com`
and `services.gradle.org`. This was verified by direct connection attempts, not
assumed. The first CI run is the first compilation and the first test execution.

### Completed

**Documentation**

| File | Contents |
|---|---|
| `docs/requirements-checklist.md` | 120+ requirements consolidated from both source documents, each traced to its source and given a status |
| `docs/architecture.md` | Layered architecture, dependency rules, directory layout, unlock sequence, vault format outline, technology decisions |
| `docs/decisions-and-risks.md` | 10 design decisions with reasoning and rejected alternatives; 10-entry risk register; 3 open questions for the owner |
| `docs/known-limitations.md` | What is not implemented, what will always be limited, build and testing limitations |
| `README.md` | Product overview, security design, install and build instructions |
| `docs/progress-log.md` | This file |

**Application scaffold**

| File | Purpose |
|---|---|
| `pubspec.yaml` | Project metadata. **No third-party runtime dependencies** (decision D-002) |
| `analysis_options.yaml` | `flutter_lints` plus strict casts, strict inference, strict raw types, and `avoid_print` to keep secrets out of device logs |
| `lib/main.dart` | Entry point |
| `lib/src/app/build_info.dart` | Version, stage and the compile-time `isDemoBuild` flag |
| `lib/src/app/theme.dart` | Seeded light and dark themes |
| `lib/src/app/navigation_plan.dart` | The twelve navigation sections as public, testable data with honest status values |
| `lib/src/app/family_vault_app.dart` | Root widget, follows the platform light/dark setting |
| `lib/src/features/home/shell_screen.dart` | Stage 1 shell: responsive, states the current stage, lists planned sections, no empty screens implying features |

**Tests written** (11 cases, not yet executed)

| File | Covers |
|---|---|
| `test/navigation_plan_test.dart` | Section count, exact order, non-empty summaries, no duplicate labels, and an honesty guard asserting nothing is marked working at Stage 1 |
| `test/app_shell_test.dart` | App builds, product name shown, sections listed, stage stated, about dialog reports the version, tapping an unbuilt section says so, no demo banner in a normal build |

**Build pipeline**

| Workflow | Jobs |
|---|---|
| `ci.yml` | `quality` (resolve, format check, analyse, test, upload coverage) then `android` (universal release APK) and `windows` (release build, zipped) in parallel |
| `web-demo.yml` | Build the demo with `FAMILY_VAULT_DEMO=true`, upload a downloadable copy, deploy to Pages |
| `release.yml` | On a `v*` tag: test and build both platforms, then publish to a GitHub Release with plain-language install notes |

**Supporting**

| File | Purpose |
|---|---|
| `tool/bootstrap_platforms.sh` | Generates `android/`, `windows/` and `web/` from Flutter's templates, only when absent, in a scratch directory so app code can never be overwritten (decision D-004) |
| `.gitignore` | Security guard first: blocks `*.fvault`, `*.keystore`, `*.jks`, `*.p12`, `*.pem`, `*.key`, `key.properties`, `*.env`, `recovery-sheet*` and password CSV patterns |

### Verified locally

What could be checked without a Flutter SDK was checked:

| Check | Result |
|---|---|
| All five YAML files parse | PASS — `ci.yml` (3 jobs), `release.yml` (3 jobs), `web-demo.yml` (2 jobs), `pubspec.yaml`, `analysis_options.yaml` |
| `tool/bootstrap_platforms.sh` shell syntax | PASS — `bash -n` clean |
| Bootstrap script behaviour | PASS — correctly detects all three platform directories absent and attempts generation |
| Dart import graph | PASS — every relative import resolves to a file that exists |
| Repository contains no secret material | PASS — no vault, key, keystore or credential file present |

### Not verified

| Not verified | Why | Resolved by |
|---|---|---|
| The Dart code compiles | No Dart SDK available | First CI run |
| Tests pass | No Flutter SDK available | First CI run |
| `flutter analyze` is clean | No analyser available | First CI run |
| Dependency resolution succeeds | `pub.dev` refused | First CI run |
| The APK installs and runs | No Android SDK or device | Owner testing on a physical phone |
| The Windows build runs | No Windows machine | First CI run, then owner testing |

### Failed

Nothing has failed, because nothing has yet been executed. This is recorded
explicitly so that "no failures" is not mistaken for "tests passed".

### Blocked

**R-001 — pushes to the repository are refused.** The repository
`Samby28/family-vault` was attached successfully and can be read, but this
session reports that it lacks write access, so no commit can reach GitHub and no
build can run.

**Owner action required:** authorise the Claude GitHub App for the repository at
`https://github.com/apps/claude/installations/select_target`. If it reports the
app is already installed, reconnect GitHub from claude.ai → Settings →
Connectors.

Everything above is written and waiting locally; the push is the only thing
standing between it and the first build.

### Next

1. Owner authorises repository write access.
2. Push Stage 1; read the first CI run.
3. Fix whatever the analyser and the test run report, per MP 17 — iterate until
   green, and record each failure and its resolution here.
4. Pin the Flutter version to the first known-good release; make the format
   check blocking.
5. Commit the generated `android/`, `windows/` and `web/` directories and the
   resolved `pubspec.lock`.
6. Tag `v0.1.0` so the first installable APK reaches the Releases page.
7. Begin Stage 2: evaluate Argon2id and AEAD libraries in CI on both platforms,
   settle decision D-003, then build the crypto core test-first.
