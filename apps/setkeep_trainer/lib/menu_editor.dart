import 'package:setkeep/trainer/trainer_menu_codec.dart';
import 'package:flutter/material.dart';
import 'package:setkeep/trainer/trainer_repository.dart';
import 'package:setkeep/trainer/tenant_repository.dart';
import 'package:setkeep/main.dart'
    show
        RecordedSet,
        WorkoutRecord,
        WorkoutExercise,
        WorkoutSet,
        ExerciseSelection,
        ExercisePickerSheet,
        ExercisePickerViewport,
        ExerciseInputCard,
        WorkoutNumericInputController;

import 'trainer_widgets.dart';

class MenuEditor extends StatefulWidget {
  const MenuEditor({
    super.key,
    required this.repository,
    required this.clients,
    this.recording = false,
    this.existing,
  });
  final TrainerRepository repository;
  final List<Map<String, dynamic>> clients;
  final bool recording;
  final Map<String, dynamic>? existing;
  @override
  State<MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends State<MenuEditor> {
  late final name = TextEditingController(
        text: widget.existing?['name'] as String? ?? '',
      ),
      note = TextEditingController(
        text: widget.existing?['note'] as String? ?? '',
      );
  final sessionComment = TextEditingController();
  late String clientId =
      widget.existing?['client_id'] as String? ??
      widget.clients.first['client_id'] as String;
  final exercises = <WorkoutExercise>[];
  late final numericInput = WorkoutNumericInputController(() => exercises);
  final requestId = TrainerRepository.requestId();
  List<WorkoutRecord> history = [];
  int historyGeneration = 0;
  late String schedule = widget.existing?['schedule'] as String? ?? 'single';
  late DateTime? due = DateTime.tryParse('${widget.existing?['due_at']}');
  DateTime date = DateTime.now();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    loadHistory();
    if (widget.existing != null) loadItems(widget.existing!['items'] as List);
  }

  @override
  void dispose() {
    name.dispose();
    note.dispose();
    sessionComment.dispose();
    numericInput.dispose();
    super.dispose();
  }

  Future<void> loadHistory() async {
    final generation = ++historyGeneration;
    history = [];
    try {
      final records = <WorkoutRecord>[];
      var offset = 0;
      while (true) {
        final page = await widget.repository.workouts(clientId, offset: offset);
        if (!mounted || generation != historyGeneration) return;
        records.addAll(
          page.where((r) => r['canceled_at'] == null).map(decodeWorkout),
        );
        if (page.length < 100) break;
        offset += page.length;
      }
      if (mounted && generation == historyGeneration) {
        setState(() => history = records);
      }
    } catch (_) {
      // Menus are still usable when the client has not consented to history sharing.
      if (mounted && generation == historyGeneration) {
        setState(() => history = []);
      }
    }
  }

  void loadItems(List items) {
    exercises
      ..clear()
      ..addAll(TrainerMenuCodec.exercises(items));
  }

  RecordedSet recorded(WorkoutExercise e, WorkoutSet s) => RecordedSet(
    exerciseName: e.name,
    exerciseId: e.exerciseId,
    bodyPart: e.bodyPart,
    equipment: e.equipment,
    recordType: e.recordType,
    distanceUnit: e.distanceUnit,
    weight: s.weight,
    reps: s.reps,
    durationSeconds: s.durationSeconds,
    distanceKm: s.distanceKm,
    speedKmh: s.speedKmh,
    inclinePercent: s.inclinePercent,
    resistanceLevel: s.resistanceLevel,
    paceSecondsPerKm: s.paceSecondsPerKm,
    completed: true,
  );
  List<Map<String, dynamic>> get items => [
    for (final e in exercises)
      {
        'exercise_id': e.exerciseId,
        'exercise_name': e.name,
        'body_part': e.bodyPart,
        'equipment': e.equipment,
        'record_type': e.recordType.name,
        'set_values': [for (final s in e.sets) recorded(e, s).toJson()],
      },
  ];
  Future<void> add() async {
    final picked = await showModalBottomSheet<List<ExerciseSelection>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ExercisePickerViewport(
        child: ExercisePickerSheet(
          existingIdentities: exercises.map((e) => e.identity).toSet(),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      for (final p in picked) {
        final t = p.template;
        exercises.add(
          WorkoutExercise(
            name: t.name,
            exerciseId: t.exerciseId,
            distanceUnit: t.distanceUnit,
            bodyPart: t.bodyPart,
            equipment: t.equipment,
            recordType: t.recordType,
            sets: [WorkoutSet(weight: t.startWeight, reps: t.startReps)],
          ),
        );
      }
    });
  }

  Future<void> save() async {
    final sets = [
      for (final e in exercises)
        for (final s in e.sets) recorded(e, s),
    ];
    if ((!widget.recording && name.text.trim().isEmpty) ||
        sets.isEmpty ||
        sets.length > 100 ||
        sets.any((s) => !s.hasRequiredValues)) {
      setState(
        () => error = tr(
          context,
          'メニュー名・各セットの数値を確認してください（1〜100セット）',
          'Check menu name and set values (1–100 sets)',
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      final repo = widget.repository;
      if (widget.recording) {
        await repo.recordWorkout(
          clientId,
          requestId,
          date,
          sets.map((s) => s.toJson()).toList(),
          note: sessionComment.text.trim(),
        );
      } else if (repo is TenantRepository) {
        await repo.saveMenu(
          clientId,
          name.text,
          note.text,
          items,
          existing: widget.existing,
          schedule: schedule,
          due: due,
        );
      } else {
        await repo.addMenu(clientId, name.text, note.text, items);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(
            context,
            '保存できませんでした。権限・入力値を確認してください。他の担当者が変更した場合は開き直してください。',
            'Could not save. Check permissions and values; reopen if another trainer changed this menu.',
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> template() async {
    final repo = widget.repository;
    if (repo is! TenantRepository) return;
    try {
      final rows = await repo.templates();
      if (!mounted) return;
      final picked = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(tr(ctx, 'テナントのテンプレート', 'Tenant templates')),
          children: [
            for (final t in rows)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, t),
                child: Text(t['name'] as String),
              ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr(ctx, 'テンプレートはありません', 'No templates')),
              ),
          ],
        ),
      );
      if (mounted && picked != null) {
        setState(() => loadItems(picked['items'] as List));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(
            context,
            'テンプレートを取得できませんでした',
            'Could not load templates',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.recording
            ? tr(context, 'セッションを記録', 'Record session')
            : widget.existing == null
            ? tr(context, 'メニューを作成', 'Create menu')
            : tr(context, 'メニューを編集', 'Edit menu'),
      ),
    ),
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        numericInput.keypad,
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : save,
                child: Text(tr(context, '保存', 'Save')),
              ),
            ),
          ),
        ),
      ],
    ),
    body: numericInput.wrap(
      AbsorbPointer(
        absorbing: busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            TrainerSectionHeader(
              title: tr(context, '対象と設定', 'Client & settings'),
            ),
            DropdownButtonFormField<String>(
              initialValue: clientId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr(context, '対象顧客', 'Client'),
              ),
              items: [
                for (final c in widget.clients)
                  DropdownMenuItem(
                    value: c['client_id'] as String,
                    child: Text(c['client_name'] as String),
                  ),
              ],
              onChanged: widget.existing != null
                  ? null
                  : (v) {
                      setState(() => clientId = v!);
                      loadHistory();
                    },
            ),
            if (!widget.recording) ...[
              TextField(
                controller: name,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: tr(context, 'メニュー名', 'Menu name'),
                ),
              ),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'single',
                    label: Text(tr(context, '単発', 'Single')),
                  ),
                  ButtonSegment(
                    value: 'repeat',
                    label: Text(tr(context, '繰り返し', 'Repeat')),
                  ),
                ],
                selected: {schedule},
                onSelectionChanged: (s) => setState(() => schedule = s.single),
              ),
              ListTile(
                title: Text(tr(context, '実施期限', 'Due date')),
                subtitle: Text(dateLabel(due)),
                trailing: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => due = null),
                ),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: due ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (mounted && d != null) setState(() => due = d);
                },
              ),
              if (widget.repository is TenantRepository)
                OutlinedButton(
                  onPressed: template,
                  child: Text(tr(context, 'テンプレートから追加', 'Load template')),
                ),
            ] else ...[
              ListTile(
                title: Text(dateLabel(date)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (mounted && d != null) setState(() => date = d);
                },
              ),
            ],
            TrainerSectionHeader(
              title: tr(context, '種目とセット', 'Exercises & sets'),
            ),
            for (var i = 0; i < exercises.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ExerciseInputCard(
                  key: ObjectKey(exercises[i]),
                  exerciseIndex: i,
                  exercise: exercises[i],
                  history: history,
                  showCompletionCheck: false,
                  numericNodes: numericInput.nodesFor,
                  nextNumeric: numericInput.nextNumeric,
                  onAddSet: () => setState(
                    () => exercises[i].sets.add(
                      WorkoutSet.nextFrom(exercises[i].sets.lastOrNull),
                    ),
                  ),
                  onRemoveSet: (s) =>
                      setState(() => exercises[i].sets.removeAt(s)),
                  onRemove: () => setState(() => exercises.removeAt(i)),
                  onToggleSet: (_) {},
                  onApplyPrevious: (previous) => setState(() {
                    exercises[i].sets
                      ..clear()
                      ..addAll(previous.map(TrainerMenuCodec.editable));
                    if (previous.isNotEmpty) {
                      exercises[i].recordType = previous.first.recordType;
                    }
                  }),
                  onSetAllCompleted: (_) {},
                  onValuesChanged: () {},
                  onRecordTypeChanged: () => setState(() {}),
                ),
              ),
            OutlinedButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: Text(tr(context, '種目を追加', 'Add exercise')),
            ),
            TrainerSectionHeader(
              title: widget.recording
                  ? tr(context, 'トレーナーコメント', 'Trainer comment')
                  : tr(context, 'メモ', 'Notes'),
            ),
            if (widget.recording)
              TextField(
                key: const Key('sessionCommentField'),
                controller: sessionComment,
                minLines: 3,
                maxLines: 5,
                maxLength: 10000,
                decoration: InputDecoration(
                  labelText: tr(context, 'トレーナーコメント', 'Trainer comment'),
                  alignLabelWithHint: true,
                ),
              )
            else
              TextField(
                controller: note,
                maxLength: 10000,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: tr(context, 'メモ', 'Notes'),
                ),
              ),
            if (error != null) Text(error!),
            if (busy) const LinearProgressIndicator(),
            if (!widget.recording && widget.repository is TenantRepository)
              TextButton(
                onPressed: () async {
                  try {
                    await (widget.repository as TenantRepository).mutate(
                      'template',
                      {'name': name.text.trim(), 'items': items},
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(context, 'テンプレートを保存しました', 'Template saved'),
                          ),
                        ),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      setState(
                        () => error = tr(
                          context,
                          '名前・セットの値を確認してください',
                          'Check name and set values',
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  tr(context, 'テナントのテンプレートとして保存', 'Save as tenant template'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
