import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathbetai/data/import/importer.dart';
import 'package:mathbetai/domain/enums.dart';
import 'package:mathbetai/engine/kings_visa_engine.dart';

void main() {
  test('documented example files parse and are always rejected (synthetic)', () {
    final json = Importer.fromJson(File('docs/examples/selections_example.json').readAsStringSync());
    final csv = Importer.selectionsFromCsv(File('docs/examples/selections_example.csv').readAsStringSync());
    final hist = Importer.historyFromCsv(File('docs/examples/history_example.csv').readAsStringSync());
    expect(json.errors, isEmpty);
    expect(csv.errors, isEmpty);
    expect(hist.errors, isEmpty);
    expect(json.selections.length, 2);
    expect(csv.selections.length, 2);
    expect(hist.home.single.goalSequence!.length, 3);
    final engine = KingsVisaEngine(clock: () => DateTime.utc(2030, 1, 5, 8));
    for (final s in [...json.selections, ...csv.selections]) {
      expect(s.origin, DataOrigin.synthetic);
      expect(engine.audit(s).verdict, FinalVerdict.rejected);
    }
  });
}
