import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../data/import/importer.dart';
import '../data/import/slip_parser.dart';
import '../domain/market.dart';
import '../domain/selection.dart';
import '../state/providers.dart';
import 'screens/selection_editor_screen.dart';
import 'widgets/common.dart';

/// Picks a CSV or JSON file, previews the parsed selections and saves them
/// after the user confirms. Each saved selection is audited immediately.
Future<void> importSelectionsFile(BuildContext context, WidgetRef ref) async {
  List<PlatformFile> files;
  try {
    files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'json']);
  } catch (e) {
    if (context.mounted) toast(context, 'File picker failed: $e');
    return;
  }
  if (files.isEmpty || !context.mounted) return;
  final f = files.first;
  String text;
  try {
    text = await f.xFile.readAsString();
  } catch (e) {
    if (context.mounted) toast(context, 'Could not read file: $e');
    return;
  }
  final res = (f.extension ?? '').toLowerCase() == 'json' ? Importer.fromJson(text) : Importer.selectionsFromCsv(text);
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Import ${res.selections.length} selection(s)?'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          const Text('Imported rows are recorded as USER-ENTERED data. Each will be audited; missing evidence '
              'will make it INCOMPLETE, never approved.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 8),
          for (final s in res.selections)
            Text('• ${s.matchLabel} (${s.market.type.title}) @ ${s.odds?.toStringAsFixed(2) ?? '?'}'),
          for (final e in res.errors) Text('⚠ $e', style: const TextStyle(color: AppColors.fail, fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
            onPressed: res.selections.isEmpty ? null : () => Navigator.pop(context, true), child: const Text('Import')),
      ],
    ),
  );
  if (ok != true) return;
  final ctl = ref.read(selectionsProvider.notifier);
  for (final s in res.selections) {
    final id = await ctl.save(s.copyWith(checks: StructuralCheck.defaults()));
    await ctl.audit(id);
  }
  if (context.mounted) toast(context, 'Imported and audited ${res.selections.length} selection(s).');
}

/// OCR import of a betting-slip screenshot. Extracted text only creates
/// drafts; the user must review and save each one before analysis.
Future<void> importSlipScreenshot(BuildContext context, WidgetRef ref) async {
  final img = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (img == null || !context.mounted) return;
  List<SlipDraft> drafts;
  final recognizer = TextRecognizer();
  try {
    final text = await recognizer.processImage(InputImage.fromFilePath(img.path));
    drafts = SlipParser.parse(text.text);
  } catch (e) {
    if (context.mounted) toast(context, 'Text recognition failed: $e');
    return;
  } finally {
    await recognizer.close();
  }
  if (!context.mounted) return;
  if (drafts.isEmpty) {
    toast(context, 'No "Team vs Team" lines recognised. Enter the selection manually.');
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        const Text('EXTRACTED FROM SCREENSHOT — UNCONFIRMED',
            style: TextStyle(color: AppColors.watch, fontWeight: FontWeight.w800)),
        const Text('OCR can misread names and prices. Open each draft, verify every field against the slip, '
            'define the exact market, then save.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 8),
        for (final d in drafts)
          Card(
            child: ListTile(
              title: Text('${d.home} vs ${d.away}'),
              subtitle: Text('Market text: ${d.marketText.isEmpty ? '?' : d.marketText} · Odds: ${d.odds ?? '?'}'),
              trailing: const Icon(Icons.edit_note),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SelectionEditorScreen(
                      initial: Selection(
                        homeTeam: d.home,
                        awayTeam: d.away,
                        odds: d.odds,
                        oddsSource: 'Betting slip screenshot (user-confirmed)',
                        market: const MarketSpec(type: MarketType.overUnderGoals),
                        notes: 'Slip text: "${d.rawLine}" / "${d.marketText}". Verify before saving.',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ]),
    ),
  );
}
