import 'package:flutter_test/flutter_test.dart';
import 'package:scripture365/main.dart';

void main() {
  test('ScriptureEntry parses preserved content', () {
    final entry = ScriptureEntry.fromJson(const {
      'title': 'A New Beginning',
      'ref': 'Isaiah 43:19',
      'excerpt': 'Behold, I will do a new thing.',
      'visual': 'sunrise',
      'month': 'January',
      'day': 1,
      'monthTheme': 'Renewal',
      'arc': 'Fresh Start',
      'accent': '#b88a45',
      'doy': 1,
      'reflection': 'Begin again.',
      'prayer': 'Amen.',
    });
    expect(entry.dayOfYear, 1);
    expect(entry.reference, 'Isaiah 43:19');
    expect(entry.shareText, contains('Scripture 365'));
  });

  test('date indexing stays inside the 365-day corpus', () {
    final entries = List.generate(365, (index) => ScriptureEntry(
      title: 'Day', reference: 'Ref', excerpt: 'Text', visual: 'sunrise',
      month: 'January', day: 1, monthTheme: 'Theme', arc: 'Arc',
      accent: '#000000', dayOfYear: index + 1, reflection: 'Reflection', prayer: 'Prayer',
    ));
    final repository = ScriptureRepository(entries, const [], 'WEB');
    expect(repository.indexForDate(DateTime(2025, 1, 1)), 0);
    expect(repository.indexForDate(DateTime(2025, 12, 31)), 364);
    expect(repository.indexForDate(DateTime(2024, 12, 31)), 364);
  });
}
