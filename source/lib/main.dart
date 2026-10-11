import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await ScriptureRepository.load();
  final preferences = await SharedPreferences.getInstance();
  runApp(Scripture365App(AppState(repository, preferences)));
}

class ScriptureEntry {
  const ScriptureEntry({
    required this.title,
    required this.reference,
    required this.excerpt,
    required this.visual,
    required this.month,
    required this.day,
    required this.monthTheme,
    required this.arc,
    required this.accent,
    required this.dayOfYear,
    required this.reflection,
    required this.prayer,
  });

  factory ScriptureEntry.fromJson(Map<String, dynamic> json) => ScriptureEntry(
        title: json['title'] as String? ?? '',
        reference: json['ref'] as String? ?? '',
        excerpt: json['excerpt'] as String? ?? '',
        visual: json['visual'] as String? ?? 'sunrise',
        month: json['month'] as String? ?? '',
        day: (json['day'] as num?)?.toInt() ?? 1,
        monthTheme: json['monthTheme'] as String? ?? '',
        arc: json['arc'] as String? ?? '',
        accent: json['accent'] as String? ?? '#8a6b45',
        dayOfYear: (json['doy'] as num?)?.toInt() ?? 1,
        reflection: json['reflection'] as String? ?? '',
        prayer: json['prayer'] as String? ?? '',
      );

  final String title;
  final String reference;
  final String excerpt;
  final String visual;
  final String month;
  final int day;
  final String monthTheme;
  final String arc;
  final String accent;
  final int dayOfYear;
  final String reflection;
  final String prayer;

  String get shareText => '"' + excerpt + '"\n\n' + reference + '\n— Scripture 365';
}

class MonthInfo {
  const MonthInfo(this.name, this.theme, this.accent);

  factory MonthInfo.fromJson(Map<String, dynamic> json) => MonthInfo(
        json['name'] as String? ?? '',
        json['theme'] as String? ?? '',
        json['accent'] as String? ?? '#8a6b45',
      );

  final String name;
  final String theme;
  final String accent;
}

class ScriptureRepository {
  const ScriptureRepository(this.entries, this.months, this.translation);

  static Future<ScriptureRepository> load() async {
    final raw = await rootBundle.loadString('assets/content/year_365.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (json['entries'] as List<dynamic>)
        .map((item) => ScriptureEntry.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    final months = (json['months'] as List<dynamic>)
        .map((item) => MonthInfo.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    return ScriptureRepository(entries, months, json['translation'] as String? ?? 'World English Bible (WEB)');
  }

  final List<ScriptureEntry> entries;
  final List<MonthInfo> months;
  final String translation;

  int indexForDate(DateTime date) {
    final elapsed = date.difference(DateTime(date.year, 1, 1)).inDays;
    return elapsed.clamp(0, entries.length - 1);
  }
}

class AppState extends ChangeNotifier {
  AppState(this.repository, this.preferences)
      : _themeMode = preferences.getString('theme_mode') ?? 'system',
        onboardingComplete = preferences.getBool('onboarding_complete') ?? false,
        reminderEnabled = preferences.getBool('daily_reminders_enabled') ?? false,
        reminderMinutes = preferences.getInt('daily_reminder_minutes') ?? 480,
        saved = (preferences.getStringList('saved_days') ?? const <String>[]).map(int.parse).toSet(),
        history = (preferences.getStringList('history_days') ?? const <String>[]).map(int.parse).toList();

  final ScriptureRepository repository;
  final SharedPreferences preferences;
  String _themeMode;
  bool onboardingComplete;
  bool reminderEnabled;
  int reminderMinutes;
  final Set<int> saved;
  final List<int> history;

  ThemeMode get themeMode => _themeMode == 'light'
      ? ThemeMode.light
      : _themeMode == 'dark'
          ? ThemeMode.dark
          : ThemeMode.system;
  String get themeModeName => _themeMode;

  Future<void> finishOnboarding() async {
    onboardingComplete = true;
    await preferences.setBool('onboarding_complete', true);
    notifyListeners();
  }

  Future<void> setTheme(String value) async {
    _themeMode = value;
    await preferences.setString('theme_mode', value);
    notifyListeners();
  }

  Future<void> toggleSaved(ScriptureEntry entry) async {
    if (!saved.add(entry.dayOfYear)) saved.remove(entry.dayOfYear);
    await preferences.setStringList('saved_days', saved.map((value) => value.toString()).toList());
    notifyListeners();
  }

  Future<void> recordView(ScriptureEntry entry) async {
    history.remove(entry.dayOfYear);
    history.insert(0, entry.dayOfYear);
    if (history.length > 60) history.removeRange(60, history.length);
    await preferences.setStringList('history_days', history.map((value) => value.toString()).toList());
    notifyListeners();
  }

  Future<void> setReminderEnabled(bool value) async {
    reminderEnabled = value;
    await preferences.setBool('daily_reminders_enabled', value);
    notifyListeners();
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    reminderMinutes = time.hour * 60 + time.minute;
    await preferences.setInt('daily_reminder_minutes', reminderMinutes);
    notifyListeners();
  }
}

class Scripture365App extends StatelessWidget {
  const Scripture365App(this.state, {super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'Scripture 365',
        debugShowCheckedModeBanner: false,
        themeMode: state.themeMode,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        home: state.onboardingComplete ? AppShell(state) : OnboardingScreen(state),
      ),
    );
  }
}

ThemeData appTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff80643f),
    brightness: brightness,
    surface: brightness == Brightness.dark ? const Color(0xff161713) : const Color(0xfff8f4ec),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: const AppBarTheme(scrolledUnderElevation: 0),
    cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    navigationBarTheme: NavigationBarThemeData(height: 72, indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
  );
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen(this.state, {super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/wallpapers/sunrise.webp', fit: BoxFit.cover),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x22000000), Color(0xdd11130e)]))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text('SCRIPTURE 365', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white70, letterSpacing: 2.5)),
                  const SizedBox(height: 12),
                  Text('Scripture, beautifully present every day.', style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600, height: 1.05)),
                  const SizedBox(height: 16),
                  Text('A meaningful verse, reflection and creative wallpaper for every day of the year.', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white.withValues(alpha: .85), height: 1.45)),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: state.finishOnboarding,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Start My Journey')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell(this.state, {super.key});
  final AppState state;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [TodayScreen(widget.state), ExploreScreen(widget.state), SavedScreen(widget.state), SettingsScreen(widget.state)];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.bookmark_outline), selectedIcon: Icon(Icons.bookmark), label: 'Saved'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }
}

class TodayScreen extends StatefulWidget {
  const TodayScreen(this.state, {super.key});
  final AppState state;
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late int index;

  @override
  void initState() {
    super.initState();
    index = widget.state.repository.indexForDate(DateTime.now());
    widget.state.recordView(widget.state.repository.entries[index]);
  }

  void select(int value) {
    final safe = value.clamp(0, widget.state.repository.entries.length - 1);
    setState(() => index = safe);
    widget.state.recordView(widget.state.repository.entries[safe]);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.state.repository.entries[index];
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Scripture 365'),
            actions: [
              IconButton(tooltip: 'Previous day', onPressed: index > 0 ? () => select(index - 1) : null, icon: const Icon(Icons.chevron_left)),
              IconButton(tooltip: 'Next day', onPressed: index < 364 ? () => select(index + 1) : null, icon: const Icon(Icons.chevron_right)),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            sliver: SliverList.list(
              children: [
                Text(DateFormat('EEEE, MMMM d').format(DateTime(DateTime.now().year, 1, 1).add(Duration(days: index))), style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Text('DAY ' + entry.dayOfYear.toString() + ' OF 365', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.8)),
                const SizedBox(height: 14),
                ScriptureCard(entry: entry, saved: widget.state.saved.contains(entry.dayOfYear), onSaved: () => widget.state.toggleSaved(entry)),
                const SizedBox(height: 20),
                SectionCard(label: 'A THOUGHT FOR TODAY', text: entry.reflection, icon: Icons.lightbulb_outline),
                const SizedBox(height: 12),
                SectionCard(label: "TODAY'S PRAYER", text: entry.prayer, icon: Icons.self_improvement),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(onPressed: () => Share.share(entry.shareText), icon: const Icon(Icons.ios_share), label: const Text('Share')),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: entry.shareText));
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scripture copied to clipboard.')));
                      },
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy Scripture'),
                    ),
                    FilledButton.tonalIcon(onPressed: () => showWallpaperSheet(context, entry), icon: const Icon(Icons.wallpaper), label: const Text('Create Wallpaper')),
                  ],
                ),
                const SizedBox(height: 18),
                Text(widget.state.repository.translation, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ScriptureCard extends StatelessWidget {
  const ScriptureCard({required this.entry, required this.saved, required this.onSaved, super.key});
  final ScriptureEntry entry;
  final bool saved;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: .78,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(wallpaperFor(entry.visual), fit: BoxFit.cover),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [.15, .55, 1], colors: [Color(0x22000000), Color(0x55000000), Color(0xdd090b08)]))),
            Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(entry.monthTheme.toUpperCase(), style: const TextStyle(color: Colors.white70, letterSpacing: 1.3, fontSize: 11, fontWeight: FontWeight.w600))),
                    IconButton.filledTonal(onPressed: onSaved, tooltip: saved ? 'Remove favorite' : 'Add favorite', icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline)),
                  ]),
                  const Spacer(),
                  Text(entry.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Text(entry.excerpt, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, height: 1.5)),
                  const SizedBox(height: 14),
                  Text(entry.reference, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: .4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({required this.label, required this.text, required this.icon, super.key});
  final String label;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
            ])),
          ],
        ),
      ),
    );
  }
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen(this.state, {super.key});
  final AppState state;
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String query = '';
  String? month;

  @override
  Widget build(BuildContext context) {
    final entries = widget.state.repository.entries.where((entry) {
      final needle = query.toLowerCase();
      return (month == null || entry.month == month) &&
          (needle.isEmpty || entry.title.toLowerCase().contains(needle) || entry.reference.toLowerCase().contains(needle) || entry.monthTheme.toLowerCase().contains(needle) || entry.arc.toLowerCase().contains(needle));
    }).toList();
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('Explore')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('A thoughtfully curated year of Scripture', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SearchBar(hintText: 'Search Scripture, theme or feeling', leading: const Icon(Icons.search), onChanged: (value) => setState(() => query = value)),
                const SizedBox(height: 14),
                SizedBox(
                  height: 42,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(label: const Text('All year'), selected: month == null, onSelected: (_) => setState(() => month = null))),
                    ...widget.state.repository.months.map((item) => Padding(padding: const EdgeInsets.only(right: 8), child: FilterChip(label: Text(item.name), selected: month == item.name, onSelected: (_) => setState(() => month = item.name)))),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(entries.length.toString() + ' days', style: Theme.of(context).textTheme.labelMedium),
              ]),
            ),
          ),
          if (entries.isEmpty)
            const SliverFillRemaining(child: Center(child: Text('No matching Scripture entries yet.')))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
              sliver: SliverList.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => EntryTile(entry: entries[index], saved: widget.state.saved.contains(entries[index].dayOfYear), onSaved: () => widget.state.toggleSaved(entries[index])),
              ),
            ),
        ],
      ),
    );
  }
}

class EntryTile extends StatelessWidget {
  const EntryTile({required this.entry, required this.saved, required this.onSaved, super.key});
  final ScriptureEntry entry;
  final bool saved;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .86,
            minChildSize: .5,
            maxChildSize: .95,
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                ScriptureCard(entry: entry, saved: saved, onSaved: onSaved),
                const SizedBox(height: 16),
                SectionCard(label: 'A THOUGHT FOR TODAY', text: entry.reflection, icon: Icons.lightbulb_outline),
                const SizedBox(height: 10),
                SectionCard(label: "TODAY'S PRAYER", text: entry.prayer, icon: Icons.self_improvement),
              ],
            ),
          ),
        ),
        child: Row(children: [
          SizedBox(width: 92, height: 110, child: Image.asset(wallpaperFor(entry.visual), fit: BoxFit.cover)),
          Expanded(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(entry.reference),
              const SizedBox(height: 8),
              Text(entry.month + ' ' + entry.day.toString() + ' • ' + entry.arc, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ]),
          )),
          IconButton(onPressed: onSaved, icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline)),
        ]),
      ),
    );
  }
}

class SavedScreen extends StatelessWidget {
  const SavedScreen(this.state, {super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final favorites = state.repository.entries.where((entry) => state.saved.contains(entry.dayOfYear)).toList();
    final viewed = state.history.where((day) => day > 0 && day <= state.repository.entries.length).map((day) => state.repository.entries[day - 1]).toList();
    return SafeArea(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: const AppBar(title: Text('Saved'), bottom: TabBar(tabs: [Tab(text: 'Favorites'), Tab(text: 'History')])),
          body: TabBarView(children: [
            EntryList(entries: favorites, state: state, empty: 'Tap Save on Today to keep a verse here.'),
            EntryList(entries: viewed, state: state, empty: 'Verses you view will appear here.'),
          ]),
        ),
      ),
    );
  }
}

class EntryList extends StatelessWidget {
  const EntryList({required this.entries, required this.state, required this.empty, super.key});
  final List<ScriptureEntry> entries;
  final AppState state;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(empty, textAlign: TextAlign.center)));
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => EntryTile(entry: entries[index], saved: state.saved.contains(entries[index].dayOfYear), onSaved: () => state.toggleSaved(entries[index])),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen(this.state, {super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: state.reminderMinutes ~/ 60, minute: state.reminderMinutes % 60);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          SettingsGroup(title: 'Appearance', children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto), label: Text('System')),
                ButtonSegment(value: 'light', icon: Icon(Icons.light_mode), label: Text('Light')),
                ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode), label: Text('Dark')),
              ],
              selected: {state.themeModeName},
              onSelectionChanged: (value) => state.setTheme(value.first),
            ),
          ]),
          SettingsGroup(title: 'Daily rhythm', children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Daily Scripture reminder'),
              subtitle: Text('New Scripture available at ' + time.format(context)),
              value: state.reminderEnabled,
              onChanged: state.setReminderEnabled,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Reminder time'),
              subtitle: Text(time.format(context)),
              enabled: state.reminderEnabled,
              onTap: () async {
                final selected = await showTimePicker(context: context, initialTime: time);
                if (selected != null) await state.setReminderTime(selected);
              },
            ),
          ]),
          SettingsGroup(title: 'Widgets', children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('Add Home Screen Widget'),
              subtitle: const Text('Keep Scripture where you see it most.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('How to Add a Widget'),
                  content: const Text('Open your launcher widget picker and choose Scripture 365. Widget data refreshes with the daily entry in signed Android and iOS builds.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
                ),
              ),
            ),
          ]),
          SettingsGroup(title: 'About', children: [
            const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.auto_awesome), title: Text('Scripture 365'), subtitle: Text('Version 1.0.0 • 365-day journey')),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.menu_book_outlined), title: const Text('Bible translation'), subtitle: Text(state.repository.translation)),
            const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.verified_outlined), title: Text('Content integrity'), subtitle: Text('Scripture first, then meaning, visual direction and artwork.')),
          ]),
        ],
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.title, required this.children, super.key});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }
}

Future<void> showWallpaperSheet(BuildContext context, ScriptureEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Create Wallpaper', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        AspectRatio(
          aspectRatio: .7,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(fit: StackFit.expand, children: [
              Image.asset(wallpaperFor(entry.visual), fit: BoxFit.cover),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x11000000), Color(0xcc000000)]))),
              Padding(
                padding: const EdgeInsets.all(26),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(entry.excerpt, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, height: 1.35)),
                  const SizedBox(height: 12),
                  Text(entry.reference, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: () => Share.share(entry.shareText), icon: const Icon(Icons.ios_share), label: const Text('Share Scripture')),
      ]),
    ),
  );
}

String wallpaperFor(String visual) {
  const supported = {'forest', 'harvest', 'meadow', 'mist', 'mountain', 'night', 'path', 'still', 'sunrise', 'sunset', 'trail', 'valley'};
  final name = supported.contains(visual) ? visual : visual == 'sacred' ? 'night' : visual == 'sky' ? 'valley' : 'sunrise';
  return 'assets/wallpapers/' + name + '.webp';
}
