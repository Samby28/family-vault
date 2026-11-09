import 'package:family_vault/src/app/navigation_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('navigation plan', () {
    test('declares the twelve sections the requirements specify', () {
      expect(plannedSections.length, 12);
    });

    test('lists the sections in the specified order', () {
      final List<String> labels = plannedSections
          .map((AppSection section) => section.label)
          .toList();
      expect(labels, <String>[
        'Dashboard',
        'All Items',
        'Logins',
        'Secure Notes',
        'Payment Cards',
        'Identities',
        'Folders',
        'Favourites',
        'Authenticator',
        'Password Health',
        'Trash',
        'Settings',
      ]);
    });

    test('gives every section a plain-language summary', () {
      for (final AppSection section in plannedSections) {
        expect(
          section.summary.trim(),
          isNotEmpty,
          reason: '${section.label} has no summary',
        );
      }
    });

    test('has no duplicate section labels', () {
      final Set<String> labels = plannedSections
          .map((AppSection section) => section.label)
          .toSet();
      expect(labels.length, plannedSections.length);
    });

    // Honesty guard. A section may only be marked as working once its feature
    // is actually implemented and tested. Stage 1 implements none of them, so
    // any "working" status here means a status was changed prematurely.
    test('claims nothing is working at Stage 1', () {
      final Iterable<AppSection> overclaimed = plannedSections.where(
        (AppSection section) => section.status == SectionStatus.working,
      );
      expect(
        overclaimed,
        isEmpty,
        reason:
            'sections marked working without an implementation: '
            '${overclaimed.map((AppSection s) => s.label).join(', ')}',
      );
    });
  });
}
