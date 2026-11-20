import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/theme.dart';
import 'data/db/app_database.dart';
import 'state/providers.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MathBetApp(),
  ));
}

class MathBetApp extends StatelessWidget {
  const MathBetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MathBetAI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(),
        themeMode: ThemeMode.dark,
        home: const HomeShell(),
      );
}
