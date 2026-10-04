import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../main.dart' show WorkoutRecord, BodyMapPage;
import 'friends_repository.dart';

FriendsRepository? configuredFriends() =>
    SupabaseConfig.initialized &&
        Supabase.instance.client.auth.currentUser != null
    ? FriendsRepository(Supabase.instance.client)
    : null;

WorkoutRecord socialWorkout(Map<String, dynamic> row) =>
    WorkoutRecord.fromJson({
      'date': row['performed_at'],
      'durationSeconds': row['duration_seconds'],
      'sets': row['sets'],
    });
String friendName(Map<String, dynamic> row) =>
    (row['friend_profiles'] as Map?)?['display_name'] as String? ?? 'Friend';
String dateLabel(WorkoutRecord w) =>
    '${w.date.toLocal().year}/${w.date.toLocal().month}/${w.date.toLocal().day}';
bool english(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'en';
String label(BuildContext context, String ja, String en) =>
    english(context) ? en : ja;

class FriendsSection extends StatefulWidget {
  const FriendsSection({
    super.key,
    required this.history,
    this.repository,
    this.historyReady = true,
  });
  final List<WorkoutRecord> history;
  final FriendsRepository? repository;
  final bool historyReady;
  @override
  State<FriendsSection> createState() => _FriendsSectionState();
}

class _FriendsSectionState extends State<FriendsSection> {
  late final FriendsRepository? repo = widget.repository ?? configuredFriends();
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  bool failed = false;
  int refreshGeneration = 0;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(FriendsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history ||
        oldWidget.historyReady != widget.historyReady) {
      refresh();
    }
  }

  Future<void> refresh() async {
    final generation = ++refreshGeneration;
    try {
      if (widget.historyReady) {
        await repo?.publish(widget.history.map((w) => w.toJson()).toList());
      }
      final result = await repo?.feed() ?? <Map<String, dynamic>>[];
      if (mounted && generation == refreshGeneration) {
        setState(() {
          rows = result;
          failed = false;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && generation == refreshGeneration) {
        setState(() {
          rows = [];
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label(context, 'フレンドのトレーニング', 'Friends’ workouts'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: label(context, '更新', 'Refresh'),
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: label(context, 'フレンド・公開範囲', 'Friends & privacy'),
            icon: const Icon(Icons.people_outline),
            onPressed: repo == null
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FriendsSettingsPage(
                          repository: repo!,
                          history: widget.history,
                        ),
                      ),
                    );
                    await refresh();
                  },
          ),
        ],
      ),
      if (loading)
        const LinearProgressIndicator()
      else if (failed)
        TextButton(
          onPressed: refresh,
          child: Text(
            label(context, '読み込めませんでした。再試行', 'Could not load. Retry'),
          ),
        )
      else if (rows.isEmpty)
        Text(
          label(
            context,
            repo == null ? 'ログインするとフレンドを利用できます' : 'フレンドの共有トレーニングはまだありません',
            repo == null ? 'Sign in to use friends' : 'No shared workouts yet',
          ),
        ),
      for (final row in rows.take(10))
        Card(
          child: ListTile(
            leading: const Icon(Icons.fitness_center),
            title: Text(friendName(row)),
            subtitle: Text(
              '${dateLabel(socialWorkout(row))} · ${socialWorkout(row).summaryLabel}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FriendActivityPage(
                    repository: repo!,
                    owner: row['user_id'] as String,
                    selectedId: row['id'] as String,
                  ),
                ),
              );
              await refresh();
            },
          ),
        ),
    ],
  );
}

class FriendsSettingsPage extends StatefulWidget {
  const FriendsSettingsPage({
    super.key,
    required this.repository,
    required this.history,
  });
  final FriendsRepository repository;
  final List<WorkoutRecord> history;
  @override
  State<FriendsSettingsPage> createState() => _FriendsSettingsPageState();
}

class _FriendsSettingsPageState extends State<FriendsSettingsPage> {
  final name = TextEditingController();
  final code = TextEditingController();
  String visibility = 'private';
  String? invite;
  List<Map<String, dynamic>> connections = [];
  bool busy = true;
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    run(load);
  }

  @override
  void dispose() {
    name.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final profile = await widget.repository.profile();
    final items = await widget.repository.connections();
    if (!mounted) return;
    setState(() {
      name.text = profile?['display_name'] as String? ?? '';
      visibility = profile?['visibility'] as String? ?? 'private';
      invite = profile?['invite_code'] as String?;
      connections = items;
      loaded = true;
    });
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              label(
                context,
                '操作できませんでした。接続・入力を確認して再試行してください',
                'Could not complete. Check connection and input, then retry',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(label(context, 'フレンド・公開範囲', 'Friends & privacy')),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        TextField(
          controller: name,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: label(context, '表示名', 'Display name'),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: visibility,
          key: ValueKey(visibility),
          items: [
            DropdownMenuItem(
              value: 'private',
              child: Text(label(context, '非公開', 'Private')),
            ),
            DropdownMenuItem(
              value: 'friends',
              child: Text(
                label(context, '承認済みフレンドのみ', 'Approved friends only'),
              ),
            ),
          ],
          onChanged: busy ? null : (v) => setState(() => visibility = v!),
        ),
        Text(
          label(
            context,
            '公開すると記録済みトレーニングの日時・種目・セットが共有されます。場所・メモ・体重は共有しません。',
            'Sharing includes workout dates, exercises and sets. Locations, notes and body weight stay private.',
          ),
        ),
        FilledButton(
          onPressed: busy || !loaded
              ? null
              : () => run(() async {
                  await widget.repository.saveProfile(name.text, visibility);
                  await widget.repository.publish(
                    widget.history.map((w) => w.toJson()).toList(),
                  );
                  await load();
                }),
          child: Text(label(context, '保存', 'Save')),
        ),
        if (invite != null) ...[
          SelectableText(
            '${label(context, 'あなたの招待コード', 'Your invite code')}\n$invite',
          ),
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: invite!)),
            icon: const Icon(Icons.copy),
            label: Text(label(context, 'コピー', 'Copy')),
          ),
          TextField(
            controller: code,
            decoration: InputDecoration(
              labelText: label(context, '相手の招待コード', 'Friend’s invite code'),
            ),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await widget.repository.request(code.text);
                    code.clear();
                    await load();
                  }),
            child: Text(label(context, 'フレンド申請', 'Send request')),
          ),
        ],
        for (final item in connections)
          Card(
            child: ListTile(
              title: Text(
                item['status'] == 'accepted'
                    ? label(context, '承認済みフレンド', 'Approved friend')
                    : label(context, '承認待ち', 'Pending request'),
              ),
              subtitle: Text(item['friend_name'] as String),
              trailing: Wrap(
                children: [
                  if (item['status'] == 'pending' &&
                      item['recipient'] == widget.repository.userId)
                    IconButton(
                      tooltip: label(context, '承認', 'Accept'),
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              await widget.repository.accept(
                                item['id'] as String,
                              );
                              await load();
                            }),
                      icon: const Icon(Icons.check),
                    ),
                  IconButton(
                    tooltip: label(context, '解除・申請取消', 'Remove / cancel'),
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await widget.repository.remove(
                              item['id'] as String,
                            );
                            await load();
                          }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class FriendActivityPage extends StatefulWidget {
  const FriendActivityPage({
    super.key,
    required this.repository,
    required this.owner,
    required this.selectedId,
  });
  final FriendsRepository repository;
  final String owner;
  final String selectedId;
  @override
  State<FriendActivityPage> createState() => _FriendActivityPageState();
}

class _FriendActivityPageState extends State<FriendActivityPage> {
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> comments = [];
  final text = TextEditingController();
  bool busy = true;
  Map<String, dynamic>? selected;
  @override
  void initState() {
    super.initState();
    run(load);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final result = await widget.repository.feed(owner: widget.owner);
    final matches = result.where(
      (r) => r['id'] == (selected?['id'] ?? widget.selectedId),
    );
    final current = matches.isEmpty ? null : matches.first;
    final messages = current == null
        ? <Map<String, dynamic>>[]
        : await widget.repository.comments(current['id'] as String);
    if (mounted) {
      setState(() {
        rows = result;
        selected = current;
        comments = messages;
      });
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          rows = [];
          selected = null;
          comments = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              label(
                context,
                '読み込み・操作に失敗しました。再試行してください',
                'Could not load or complete action. Retry',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = selected;
    final workout = row == null ? null : socialWorkout(row);
    final likes = (row?['friend_likes'] as List?) ?? [];
    final liked = likes.any((l) => l['user_id'] == widget.repository.userId);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          rows.isEmpty
              ? label(context, 'フレンド', 'Friend')
              : friendName(rows.first),
        ),
        actions: [
          IconButton(
            onPressed: busy ? null : () => run(load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (!busy && rows.isEmpty)
            Text(label(context, '公開トレーニングはありません', 'No visible workouts')),
          if (rows.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.accessibility_new),
              label: Text(label(context, '筋肉ヒートマップ', 'Muscle heatmap')),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(friendName(rows.first))),
                    body: BodyMapPage(
                      history: rows.map(socialWorkout).toList(),
                    ),
                  ),
                ),
              ),
            ),
          for (final r in rows)
            ListTile(
              selected: r['id'] == row?['id'],
              title: Text(dateLabel(socialWorkout(r))),
              subtitle: Text(socialWorkout(r).summaryLabel),
              onTap: busy
                  ? null
                  : () => run(() async {
                      selected = r;
                      await load();
                    }),
            ),
          if (workout != null) ...[
            const Divider(),
            Text(
              '${dateLabel(workout)} · ${workout.summaryLabel}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final group in workout.exerciseGroups.values) ...[
              Text(
                group.first.exerciseName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final set in group) Text(set.displaySummary),
            ],
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      await widget.repository.like(
                        row!['id'] as String,
                        !liked,
                      );
                      await load();
                    }),
              icon: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? const Color(0xFFC7F36B) : null,
              ),
              label: Text('${label(context, 'いいね', 'Like')} ${likes.length}'),
            ),
            for (final message in comments)
              ListTile(
                title: Text(message['body'] as String),
                subtitle: Text(
                  message['user_id'] == widget.repository.userId
                      ? label(context, 'あなた', 'You')
                      : label(context, 'フレンド', 'Friend'),
                ),
                trailing: message['user_id'] != widget.repository.userId
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                await widget.repository.deleteComment(
                                  message['id'] as String,
                                );
                                await load();
                              }),
                      ),
              ),
            TextField(
              controller: text,
              maxLength: 140,
              decoration: InputDecoration(
                labelText: label(context, '短いコメント', 'Short comment'),
              ),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      await widget.repository.comment(
                        row!['id'] as String,
                        text.text,
                      );
                      text.clear();
                      await load();
                    }),
              child: Text(label(context, 'コメント', 'Comment')),
            ),
          ],
        ],
      ),
    );
  }
}
