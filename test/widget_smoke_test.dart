import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathbetai/data/db/app_database.dart';
import 'package:mathbetai/data/secure_store.dart';
import 'package:mathbetai/main.dart';
import 'package:mathbetai/state/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('app starts in manual mode without fabricated fixtures', (tester) async {
    sqfliteFfiInit();
    final db = await tester.runAsync(() => AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db!),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
      ],
      child: const MathBetApp(),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('MATHematics BET AI'), findsOneWidget);
    expect(find.textContaining('Manual analysis mode'), findsOneWidget);

    // Scanner tab shows manual mode, not matches.
    await tester.tap(find.text('Scanner'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('never displays invented'), findsOneWidget);
    await tester.runAsync(() => db.close());
  });
}
