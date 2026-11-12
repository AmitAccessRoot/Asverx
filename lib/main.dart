import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
    };
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    runApp(const AnivoreApp());
  }, (Object error, StackTrace stack) {});
}

class Section {
  const Section(this.title, this.items);

  final String title;
  final List<String> items;

  factory Section.fromJson(Map<String, dynamic> j) {
    return Section(
      (j['title'] ?? '').toString(),
      ((j['items'] ?? []) as List).map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {'title': title, 'items': items};
}

class Topic {
  const Topic({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.image,
    required this.sections,
  });

  final int id;
  final String title;
  final String subtitle;
  final String icon;
  final String image;
  final List<Section> sections;

  factory Topic.fromJson(Map<String, dynamic> j) {
    return Topic(
      id: (j['id'] as num).toInt(),
      title: (j['title'] ?? '').toString(),
      subtitle: (j['subtitle'] ?? '').toString(),
      icon: (j['icon'] ?? '').toString(),
      image: (j['image'] ?? '').toString(),
      sections: ((j['sections'] ?? []) as List)
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  factory Topic.fromRow(Map<String, Object?> r) {
    return Topic(
      id: r['id'] as int,
      title: r['title'] as String,
      subtitle: r['subtitle'] as String,
      icon: r['icon'] as String,
      image: r['image'] as String,
      sections: (jsonDecode(r['content'] as String) as List)
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

Future<List<Topic>> loadTopics() async {
  Map<String, dynamic> map;
  List<Topic> fromJson;
  try {
    final String raw = await rootBundle.loadString('assets/data.json');
    map = jsonDecode(raw) as Map<String, dynamic>;
    fromJson = (map['topics'] as List)
        .map((e) => Topic.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return <Topic>[];
  }

  try {
    final String dir = await getDatabasesPath();
    final Database db = await openDatabase(
      p.join(dir, 'anivore.db'),
      version: 1,
      onCreate: (Database d, int v) async {
        await d.execute(
          'CREATE TABLE topics(id INTEGER PRIMARY KEY, title TEXT, subtitle TEXT, icon TEXT, image TEXT, content TEXT, position INTEGER)',
        );
        await d.execute('CREATE TABLE meta(k TEXT PRIMARY KEY, v INTEGER)');
      },
    );

    final int version = (map['version'] as num?)?.toInt() ?? 1;
    final List<Map<String, Object?>> meta = await db.query(
      'meta',
      where: 'k = ?',
      whereArgs: ['data_version'],
    );
    final int current = meta.isEmpty ? 0 : meta.first['v'] as int;

    if (current < version) {
      await db.transaction((Transaction txn) async {
        await txn.delete('topics');
        final Batch batch = txn.batch();
        for (int i = 0; i < fromJson.length; i++) {
          final Topic t = fromJson[i];
          batch.insert('topics', {
            'id': t.id,
            'title': t.title,
            'subtitle': t.subtitle,
            'icon': t.icon,
            'image': t.image,
            'content': jsonEncode(t.sections.map((s) => s.toJson()).toList()),
            'position': i,
          });
        }
        batch.insert(
          'meta',
          {'k': 'data_version', 'v': version},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await batch.commit(noResult: true);
      });
    }

    final List<Map<String, Object?>> rows =
        await db.query('topics', orderBy: 'position ASC');
    return rows.map(Topic.fromRow).toList();
  } catch (_) {
    return fromJson;
  }
}

IconData iconFor(String name) {
  switch (name) {
    case 'walk':
      return Icons.directions_walk;
    case 'food':
      return Icons.restaurant;
    case 'sun':
      return Icons.wb_twilight;
    case 'hands':
      return Icons.volunteer_activism;
    default:
      return Icons.article_outlined;
  }
}

bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color textColor(BuildContext context) =>
    isDark(context) ? Colors.white : const Color(0xFF111827);

Color softColor(BuildContext context) =>
    isDark(context) ? const Color(0xFFE5E7EB) : const Color(0xFF374151);

ThemeData buildTheme(Brightness b) {
  final bool dark = b == Brightness.dark;
  final Color bg = dark ? Colors.black : Colors.white;
  final Color fg = dark ? Colors.white : const Color(0xFF111827);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    colorScheme: ColorScheme(
      brightness: b,
      primary: fg,
      onPrimary: bg,
      secondary: fg,
      onSecondary: bg,
      error: const Color(0xFFB91C1C),
      onError: Colors.white,
      surface: bg,
      onSurface: fg,
      surfaceTint: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: bg,
      modalBackgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: const Color(0xFF9CA3AF),
    ),
  );
}

class AnivoreApp extends StatelessWidget {
  const AnivoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anivore',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (BuildContext context, Widget? child) {
        final bool dark = isDark(context);
        final Brightness icons = dark ? Brightness.light : Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: icons,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: icons,
            systemNavigationBarContrastEnforced: false,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<List<Topic>> _future;

  @override
  void initState() {
    super.initState();
    _future = loadTopics();
  }

  void _open(BuildContext context, Topic topic) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (BuildContext _) => DetailSheet(topic: topic),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Topic>>(
          future: _future,
          builder: (BuildContext context, AsyncSnapshot<List<Topic>> snap) {
            if (!snap.hasData) {
              return const SizedBox.shrink();
            }
            final List<Topic> topics = snap.data!;
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              itemCount: topics.length,
              itemBuilder: (BuildContext context, int i) {
                return TopicCard(
                  topic: topics[i],
                  onTap: () => _open(context, topics[i]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

Widget topicVisual(BuildContext context, Topic t, double size) {
  final Icon fallback = Icon(
    iconFor(t.icon),
    size: size,
    color: softColor(context),
  );
  if (t.image.isEmpty) {
    return fallback;
  }
  return Image.asset(
    t.image,
    height: size,
    fit: BoxFit.contain,
    errorBuilder: (BuildContext c, Object e, StackTrace? s) => fallback,
  );
}

class TopicCard extends StatelessWidget {
  const TopicCard({super.key, required this.topic, required this.onTap});

  final Topic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = isDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: dark
                ? const <BoxShadow>[]
                : const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 14,
                      offset: Offset(0, 5),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              topicVisual(context, topic, 52),
              const SizedBox(height: 10),
              Text(
                topic.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: textColor(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                topic.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: softColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailSheet extends StatelessWidget {
  const DetailSheet({super.key, required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final double bottom = MediaQuery.of(context).viewPadding.bottom;
    final List<Widget> lines = <Widget>[];

    for (final Section s in topic.sections) {
      lines.add(
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '•',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: textColor(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.title,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: textColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      for (final String item in s.items) {
        lines.add(
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 6, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '○',
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.5,
                    color: textColor(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.5,
                      color: textColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return SizedBox.expand(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(28, 8, 28, 28 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(child: topicVisual(context, topic, 96)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: Text(
                topic.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: textColor(context),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ...lines,
          ],
        ),
      ),
    );
  }
}
