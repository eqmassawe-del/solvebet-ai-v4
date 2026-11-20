/// Lightweight localisation layer. English is complete; Swahili covers the
/// navigation and primary labels and falls back to English per key, so new
/// translations can be added incrementally in [_sw].
class S {
  const S(this.lang);
  final String lang;

  static const supported = {'en': 'English', 'sw': 'Kiswahili'};

  String t(String key) => (lang == 'sw' ? _sw[key] : null) ?? _en[key] ?? key;

  static const _en = <String, String>{
    'dashboard': 'Command',
    'scanner': "King's Scanner",
    'selections': 'My Selections',
    'builder': "King's Builder",
    'capital': 'Capital Control',
    'lab': 'Performance Lab',
    'settings': 'Settings',
    'new_selection': 'New selection',
    'import': 'Import CSV / JSON',
    'import_slip': 'Import slip screenshot',
    'audit': 'Run KING\'S VISA',
    'save': 'Save',
    'approved': 'Approved',
    'watch': 'Watch',
    'rejected': 'Rejected',
    'incomplete': 'Incomplete',
    'manual_mode': 'Manual analysis mode',
    'disclaimer': 'MathBetAI audits evidence. It never guarantees outcomes. '
        'An APPROVED verdict means no failure pathway was found in the recorded evidence — not that the bet will win.',
  };

  static const _sw = <String, String>{
    'dashboard': 'Amri',
    'scanner': 'Skana ya Mfalme',
    'selections': 'Chaguzi Zangu',
    'builder': 'Mjenzi wa Mfalme',
    'capital': 'Udhibiti wa Mtaji',
    'lab': 'Maabara ya Utendaji',
    'settings': 'Mipangilio',
    'new_selection': 'Chaguo jipya',
    'import': 'Ingiza CSV / JSON',
    'import_slip': 'Ingiza picha ya tiketi',
    'audit': 'Endesha KING\'S VISA',
    'save': 'Hifadhi',
    'approved': 'Imeidhinishwa',
    'watch': 'Angalia',
    'rejected': 'Imekataliwa',
    'incomplete': 'Haijakamilika',
    'manual_mode': 'Hali ya uchambuzi wa mkono',
    'disclaimer': 'MathBetAI hukagua ushahidi. Haihakikishi matokeo. '
        'APPROVED inamaanisha hakuna njia ya kushindwa iliyopatikana katika ushahidi uliorekodiwa — si kwamba dau litashinda.',
  };
}
