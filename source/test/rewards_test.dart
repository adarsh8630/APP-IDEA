import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scripture365/main.dart';
import 'package:scripture365/monetization.dart';
import 'package:scripture365/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('daily devotional rewards cannot be farmed repeatedly', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final entry = ScriptureEntry(
      title: 'Daily',
      reference: 'John 3:16',
      excerpt: 'For God so loved the world.',
      visual: 'cross',
      month: 'January',
      day: 1,
      monthTheme: 'Faith',
      arc: 'Grace',
      accent: '#000000',
      dayOfYear: 1,
      reflection: 'Reflect.',
      prayer: 'Amen.',
    );
    final state = AppState(
      ScriptureRepository([entry], const [], 'WEB'),
      preferences,
      MonetizationController(),
      NotificationService(),
    );

    await state.recordView(entry);
    await state.recordView(entry);
    expect(state.gracePoints, 10);
    expect(state.readingStreak, 1);

    await state.recordShare();
    await state.recordShare();
    expect(state.gracePoints, 13);

    await state.toggleSaved(entry);
    await state.toggleSaved(entry);
    expect(state.gracePoints, 15);
  });
}
