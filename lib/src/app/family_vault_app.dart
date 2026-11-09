import 'package:flutter/material.dart';

import '../features/home/shell_screen.dart';
import 'build_info.dart';
import 'theme.dart';

/// Root widget.
///
/// Follows the platform's light or dark setting rather than imposing one, and
/// shows no debug banner so that screenshots taken for the project report look
/// like the real product.
class FamilyVaultApp extends StatelessWidget {
  const FamilyVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const ShellScreen(),
    );
  }
}
