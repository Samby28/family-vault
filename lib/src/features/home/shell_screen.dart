import 'package:flutter/material.dart';

import '../../app/build_info.dart';
import '../../app/navigation_plan.dart';

/// The Stage 1 application shell.
///
/// This screen exists so that there is a real, installable application from the
/// first build onward, as the build route requires. It states plainly what has
/// been built and what has not, rather than showing empty screens that imply
/// working features. Each section is replaced by its real implementation as the
/// stages land.
class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key});

  /// Width past which the layout switches to a two-column desktop form.
  static const double _wideBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About this build',
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isWide = constraints.maxWidth >= _wideBreakpoint;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    if (isDemoBuild) const _DemoBanner(),
                    const _StageCard(),
                    const SizedBox(height: 16),
                    Text(
                      'Planned sections',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (isWide)
                      _SectionGrid(sections: plannedSections)
                    else
                      _SectionList(sections: plannedSections),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('About $appName'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Version $appVersion'),
              SizedBox(height: 8),
              Text(appStage),
              SizedBox(height: 12),
              Text(
                'Your passwords are encrypted on this device. Nothing is sent '
                'to us, and no server of ours can read your vault.',
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

/// Shown only in the public web demonstration build.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.visibility_outlined, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Demonstration build. Sample data only - do not store real '
                'passwords here.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header card describing the current delivery stage honestly.
class _StageCard extends StatelessWidget {
  const _StageCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Secure, offline-first password manager',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(appStage, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text(
              'This build confirms that the project compiles and installs on '
              'Android and Windows. The encrypted vault is built next, before '
              'any screen below is wired up.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Single-column layout, used on phones.
class _SectionList extends StatelessWidget {
  const _SectionList({required this.sections});

  final List<AppSection> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (final AppSection section in sections)
          _SectionTile(section: section),
      ],
    );
  }
}

/// Two-column layout, used on Windows and wide windows.
class _SectionGrid extends StatelessWidget {
  const _SectionGrid({required this.sections});

  final List<AppSection> sections;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < sections.length; i += 2) {
      final AppSection left = sections[i];
      final AppSection? right =
          i + 1 < sections.length ? sections[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _SectionTile(section: left)),
            const SizedBox(width: 12),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : _SectionTile(section: right),
            ),
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

/// One planned section, with its honest status.
class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(section.icon),
        title: Text(section.label),
        subtitle: Text(section.summary),
        trailing: Text(
          section.status.label,
          style: theme.textTheme.labelMedium,
        ),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${section.label} is not built yet - '
                '${section.phase}, ${section.status.label.toLowerCase()}.',
              ),
            ),
          );
        },
      ),
    );
  }
}
