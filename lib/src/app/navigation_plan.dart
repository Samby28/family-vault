import 'package:flutter/material.dart';

/// How far a section of the application has actually been built.
///
/// This exists so the interface can never overstate progress. A section is
/// [working] only when its code exists and its tests pass.
enum SectionStatus {
  /// Designed and specified, no implementation yet.
  planned('Planned'),

  /// Partly implemented, not yet complete or not yet tested.
  inProgress('In progress'),

  /// Implemented and covered by passing tests.
  working('Working');

  const SectionStatus(this.label);

  /// Short label shown in the interface.
  final String label;
}

/// One destination in the application's navigation, as specified in the
/// requirements checklist (item B11.1).
@immutable
class AppSection {
  const AppSection({
    required this.icon,
    required this.label,
    required this.summary,
    required this.status,
    required this.phase,
  });

  /// Icon shown beside the section name.
  final IconData icon;

  /// Section name as the user sees it.
  final String label;

  /// One line explaining what the section is for, in plain language.
  final String summary;

  /// How much of it is actually built.
  final SectionStatus status;

  /// Which delivery phase the section belongs to.
  final String phase;
}

/// The twelve navigation destinations Family Vault will have, in order.
///
/// The shell renders this list directly, so the interface and the plan cannot
/// drift apart. Statuses here are updated as each stage lands.
const List<AppSection> plannedSections = <AppSection>[
  AppSection(
    icon: Icons.dashboard_outlined,
    label: 'Dashboard',
    summary: 'Counts of items, folders and passwords needing attention.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.list_alt,
    label: 'All Items',
    summary: 'Everything in the vault in one searchable list.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.login,
    label: 'Logins',
    summary: 'Website and app credentials, with optional 2FA codes.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.sticky_note_2_outlined,
    label: 'Secure Notes',
    summary: 'Free-text notes kept inside the encrypted vault.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.credit_card,
    label: 'Payment Cards',
    summary: 'Card details, encrypted and hidden until revealed.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.badge_outlined,
    label: 'Identities',
    summary: 'Personal details kept together for form filling.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.folder_outlined,
    label: 'Folders',
    summary: 'Group entries by banking, shopping, work and so on.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.star_outline,
    label: 'Favourites',
    summary: 'The handful of entries used most often.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.timer_outlined,
    label: 'Authenticator',
    summary: 'Six-digit codes for your other accounts, on a timer.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.health_and_safety_outlined,
    label: 'Password Health',
    summary: 'Finds weak, reused and ageing passwords, on this device.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.delete_outline,
    label: 'Trash',
    summary: 'Deleted entries, still encrypted, restorable until purged.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
  AppSection(
    icon: Icons.settings_outlined,
    label: 'Settings',
    summary: 'Auto-lock, clipboard clearing and optional extra protection.',
    status: SectionStatus.planned,
    phase: 'Phase 1',
  ),
];
