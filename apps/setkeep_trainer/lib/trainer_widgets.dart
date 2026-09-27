import 'package:flutter/material.dart';
import 'package:setkeep/trainer/trainer_repository.dart';
import 'package:setkeep/main.dart' show WorkoutRecord, BodyMapPage, RecordedSet;
import 'package:setkeep/exercise_list_thumbnail.dart';
import 'package:setkeep/exercise_form_catalog.dart';
import 'package:setkeep/design/family_theme.dart';

String tr(BuildContext context, String ja, String en) =>
    Localizations.localeOf(context).languageCode == 'ja' ? ja : en;

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Icon(
          Icons.inbox_outlined,
          size: 44,
          color: FamilyPalette.of(context).accent,
        ),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
        if (action != null && onAction != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

class TrainerSectionHeader extends StatelessWidget {
  const TrainerSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

String dateLabel(Object? date) =>
    DateTime.tryParse('$date')?.toLocal().toString().split(' ').first ?? '—';
WorkoutRecord decodeWorkout(Map<String, dynamic> row) =>
    WorkoutRecord.fromJson({
      'date': row['performed_at'],
      'durationSeconds': row['duration_seconds'],
      'gymName': row['gym_name'],
      'sets': row['sets'],
    });

class LatestWorkout extends StatefulWidget {
  const LatestWorkout({
    super.key,
    required this.repository,
    required this.clientId,
  });
  final TrainerRepository repository;
  final String clientId;
  @override
  State<LatestWorkout> createState() => _LatestWorkoutState();
}

class _LatestWorkoutState extends State<LatestWorkout> {
  late Future<List<Map<String, dynamic>>> future = widget.repository.workouts(
    widget.clientId,
  );
  @override
  void didUpdateWidget(covariant LatestWorkout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.clientId != widget.clientId) {
      future = widget.repository.workouts(widget.clientId);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Text(tr(context, '履歴を取得できません', 'History unavailable'));
      }
      if (!snapshot.hasData) return Text(tr(context, '読み込み中', 'Loading'));
      if (snapshot.data!.isEmpty) {
        return Text(tr(context, '共有された記録はありません', 'No shared workouts'));
      }
      final w = decodeWorkout(snapshot.data!.first);
      return Text(
        '${dateLabel(w.date)} · ${w.exerciseNames.map(exerciseDisplayName).join(' / ')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    },
  );
}

class WorkoutCard extends StatelessWidget {
  const WorkoutCard({
    super.key,
    required this.row,
    this.onComment,
    this.onCancel,
  });
  final Map<String, dynamic> row;
  final VoidCallback? onComment;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) {
    final w = decodeWorkout(row);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(
          dateLabel(w.date),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${w.exerciseNames.map(exerciseDisplayName).join(' / ')}\n${w.sets.length} ${tr(context, 'セット', 'sets')} · ${row['record_source'] == 'trainer' ? tr(context, 'トレーナー記録', 'Trainer record') : tr(context, '本人記録', 'Client record')}${row['canceled_at'] == null ? '' : ' · ${tr(context, '取消済み', 'Canceled')}'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          for (final group in w.exerciseGroups.values)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExerciseListThumbnail(exerciseId: group.first.exerciseId),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exerciseDisplayName(
                            group.first.exerciseName,
                            exerciseId: group.first.exerciseId,
                            languageCode: Localizations.localeOf(context)
                                .languageCode,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        for (var i = 0; i < group.length; i++)
                          Text('${i + 1}. ${group[i].displaySummary}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (onComment != null || onCancel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  if (onComment != null)
                    OutlinedButton(
                      onPressed: onComment,
                      child: Text(
                        tr(context, 'この日のコメント', 'Comment on this day'),
                      ),
                    ),
                  const Spacer(),
                  if (onCancel != null)
                    PopupMenuButton<String>(
                      tooltip: tr(context, '記録の操作', 'Record actions'),
                      onSelected: (_) => onCancel!(),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'status',
                          child: Text(
                            row['canceled_at'] == null
                                ? tr(context, '記録を取消', 'Cancel record')
                                : tr(context, '記録を復元', 'Restore record'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class MenuCard extends StatelessWidget {
  const MenuCard({
    super.key,
    required this.menu,
    this.clientName,
    this.onEdit,
    this.onComment,
    this.onStatus,
  });
  final Map<String, dynamic> menu;
  final String? clientName;
  final VoidCallback? onEdit;
  final VoidCallback? onComment;
  final ValueChanged<String>? onStatus;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      title: Text(
        menu['name'] as String,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${clientName == null ? '' : '$clientName · '}${dateLabel(menu['created_at'])} · ${(menu['items'] as List?)?.length ?? 0} ${tr(context, '種目', 'exercises')} · ${switch (menu['status']) {
          'completed' => tr(context, '実施済み', 'Completed'),
          'canceled' => tr(context, '取消', 'Canceled'),
          _ => tr(context, '未実施', 'Planned'),
        }}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(switch (menu['status']) {
                'completed' => tr(context, '実施済み', 'Completed'),
                'canceled' => tr(context, '取消', 'Canceled'),
                _ => tr(context, '未実施', 'Planned'),
              }),
              backgroundColor: menu['status'] == 'canceled'
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : FamilyPalette.of(context).soft,
            ),
          ),
        ),
        for (final i in menu['items'] as List)
          ListTile(
            title: Text(
              exerciseDisplayName(
                '${i['exercise_name']}',
                exerciseId: i['exercise_id'] as String?,
                languageCode: Localizations.localeOf(context).languageCode,
              ),
            ),
            subtitle: Text(
              i['set_values'] is List
                  ? (i['set_values'] as List)
                        .map(
                          (s) => RecordedSet.fromJson(
                            Map<String, dynamic>.from(s as Map),
                          ).displaySummary,
                        )
                        .join(' / ')
                  : '${i['sets']} ${tr(context, 'セット', 'sets')} · ${i['target_weight']} kg × ${i['target_reps']}',
            ),
          ),
        if ((menu['note'] as String? ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(menu['note'] as String),
          ),
        if (onEdit != null || onComment != null || onStatus != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                if (onComment != null)
                  OutlinedButton(
                    onPressed: onComment,
                    child: Text(tr(context, 'コメント', 'Comment')),
                  ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: tr(context, 'メニューの操作', 'Menu actions'),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit?.call();
                    } else {
                      onStatus?.call(value);
                    }
                  },
                  itemBuilder: (_) => [
                    if (onEdit != null && menu['status'] == 'planned')
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(tr(context, '編集', 'Edit')),
                      ),
                    if (onStatus != null && menu['status'] == 'planned')
                      PopupMenuItem(
                        value: 'completed',
                        child: Text(tr(context, '実施済みにする', 'Mark completed')),
                      ),
                    if (onStatus != null && menu['status'] != 'canceled')
                      PopupMenuItem(
                        value: 'canceled',
                        child: Text(tr(context, '取消', 'Cancel')),
                      ),
                    if (onStatus != null && menu['status'] == 'canceled')
                      PopupMenuItem(
                        value: 'planned',
                        child: Text(tr(context, '復元', 'Restore')),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class HeatmapPage extends StatelessWidget {
  const HeatmapPage({super.key, required this.workouts});
  final List<Map<String, dynamic>> workouts;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, '部位ヒートマップ', 'Body-part heatmap'))),
    body: BodyMapPage(
      history: workouts
          .where((w) => w['canceled_at'] == null)
          .map(decodeWorkout)
          .toList(),
    ),
  );
}

class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({super.key, required this.title});
  final String title;
  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: controller, maxLength: 10000, maxLines: 3),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: Text(tr(context, '保存', 'Save')),
      ),
    ],
  );
}
