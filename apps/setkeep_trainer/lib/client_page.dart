import 'package:setkeep/trainer/tenant_repository.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:setkeep/trainer/trainer_repository.dart';

import 'trainer_widgets.dart';
import 'menu_editor.dart';

class ClientPage extends StatefulWidget {
  const ClientPage({super.key, required this.repository, required this.link});
  final TrainerRepository repository;
  final Map<String, dynamic> link;
  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  List<Map<String, dynamic>> workouts = [], notes = [], menus = [];
  bool loading = true, more = true, busy = false;
  String? error;
  String get clientId => widget.link['client_id'] as String;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final w =
          widget.link['linked_user_id'] != null &&
              widget.link['share_workouts'] == false
          ? <Map<String, dynamic>>[]
          : await widget.repository.workouts(clientId);
      final n = await widget.repository.notes(clientId);
      final m = await widget.repository.menus(clientId: clientId);
      if (mounted) {
        setState(() {
          workouts = w;
          notes = n;
          menus = m;
          more = w.length == 100;
        });
      }
    } catch (_) {
      if (mounted) {
        error = tr(
          context,
          '読み込めませんでした。連携が解除された可能性があります。',
          'Could not load data. Sharing may have been revoked.',
        );
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> act(Future<void> Function() work) async {
    setState(() => busy = true);
    try {
      await work();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                '保存できませんでした。接続と権限を確認してください。',
                'Could not save. Check connection and permissions.',
              ),
            ),
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> comment({
    String? menu,
    String? date,
    Map<String, dynamic>? existing,
  }) async {
    final result = widget.repository is TenantRepository
        ? await showDialog<(String, bool)>(
            context: context,
            builder: (_) => _CommentDialog(existing: existing),
          )
        : await showDialog<String>(
            context: context,
            builder: (_) =>
                TextPromptDialog(title: tr(context, 'コメントを追加', 'Add comment')),
          ).then((value) => value == null ? null : (value, false));
    if (!mounted || result == null || result.$1.trim().isEmpty) return;
    await act(() async {
      if (widget.repository case TenantRepository repo) {
        await repo.saveComment(
          clientId,
          result.$1,
          menuId: menu,
          date: date,
          existing: existing,
          shared: result.$2,
        );
      } else {
        await widget.repository.addNote(clientId, result.$1);
      }
      await reload();
    });
  }

  Future<void> deleteComment(Map<String, dynamic> existing) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'コメントを削除しますか？', 'Delete this comment?')),
        content: Text(
          tr(
            ctx,
            '共有コメントは本人のSETKEEPからも表示されなくなります。',
            'Shared comments will also disappear from the client’s SETKEEP.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, '戻る', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, '削除', 'Delete')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await act(() async {
      await (widget.repository as TenantRepository).saveComment(
        clientId,
        '',
        existing: existing,
        delete: true,
      );
      await reload();
    });
  }

  Future<void> _inviteLinkedAccount() => act(() async {
    final token = await (widget.repository as TenantRepository).inviteClient(
      clientId,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          tr(ctx, '本人のSETKEEPと連携', 'Link the client’s SETKEEP account'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: 'setkeep://trainer/invite?v=1&token=$token',
                size: 180,
              ),
              SelectableText(token),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(ctx, '閉じる', 'Close')),
          ),
        ],
      ),
    );
  });

  Future<void> _openEditor({
    bool recording = false,
    Map<String, dynamic>? existing,
  }) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MenuEditor(
          repository: widget.repository,
          clients: [widget.link],
          recording: recording,
          existing: existing,
        ),
      ),
    );
    if (mounted) await reload();
  }

  Future<void> _setMenuStatus(Map<String, dynamic> menu, String status) async {
    if (status == 'canceled') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, 'メニューを取り消しますか？', 'Cancel this menu?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, '戻る', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(ctx, '取消', 'Cancel menu')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await act(() async {
      await (widget.repository as TenantRepository).menuStatus(menu, status);
      await reload();
    });
  }

  Future<void> _toggleRecord(Map<String, dynamic> row) async {
    final canceled = row['canceled_at'] != null;
    if (!canceled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, '記録を取り消しますか？', 'Cancel this record?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, '戻る', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(ctx, '記録を取消', 'Cancel record')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await act(() async {
      await (widget.repository as TenantRepository).cancelRecord(
        clientId,
        row['id'] as String,
        !canceled,
      );
      await reload();
    });
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.link['client_name'] as String,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          widget.link['linked_user_id'] == null
              ? tr(context, 'SETKEEP未連携', 'Not linked to SETKEEP')
              : tr(context, 'SETKEEP連携済み', 'Linked to SETKEEP'),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: widget.link['allow_recording'] == true
                  ? () => _openEditor(recording: true)
                  : null,
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(tr(context, 'セッションを記録', 'Record session')),
            ),
            OutlinedButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text(tr(context, 'メニューを作成', 'Create menu')),
            ),
            OutlinedButton.icon(
              onPressed: widget.link['share_heatmap'] == true
                  ? () => act(() async {
                      final repo = widget.repository;
                      final history = repo is TenantRepository
                          ? await repo.heatmapHistory(clientId)
                          : workouts;
                      if (!context.mounted) return;
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HeatmapPage(workouts: history),
                        ),
                      );
                    })
                  : null,
              icon: const Icon(Icons.accessibility_new_rounded),
              label: Text(tr(context, '部位を見る', 'Heatmap')),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _overview(BuildContext context) {
    final latest = workouts
        .where((row) => row['canceled_at'] == null)
        .firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        const TrainerSectionHeader(title: 'SETKEEP'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    context,
                    '連携日 ${dateLabel(widget.link['created_at'])}',
                    'Linked ${dateLabel(widget.link['created_at'])}',
                  ),
                ),
                Text(tr(context, '体重は共有されません', 'Body weight is private')),
                const SizedBox(height: 8),
                Text(
                  tr(
                    context,
                    '代理記録：${widget.link['allow_recording'] == true ? '許可' : '未許可'}　部位：${widget.link['share_heatmap'] == true ? '許可' : '未許可'}',
                    'Recording: ${widget.link['allow_recording'] == true ? 'allowed' : 'not allowed'} · Heatmap: ${widget.link['share_heatmap'] == true ? 'allowed' : 'not allowed'}',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.repository is TenantRepository &&
            widget.link['linked_user_id'] == null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _inviteLinkedAccount,
            child: Text(
              tr(context, '本人アカウントへの連携コード', 'Create account linking code'),
            ),
          ),
        ],
        TrainerSectionHeader(title: tr(context, '最近のトレーニング', 'Recent workout')),
        if (latest == null)
          EmptyState(
            text: tr(
              context,
              '共有された記録はありません。顧客がSETKEEPから記録を共有できます。',
              'No shared workouts. The client can share records from SETKEEP.',
            ),
          ),
        if (latest != null) WorkoutCard(row: latest),
        TrainerSectionHeader(
          title: tr(context, 'メニュー・コメント', 'Menus & comments'),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr(
                context,
                'メニュー ${menus.length}件 · コメント ${notes.length}件',
                '${menus.length} menus · ${notes.length} comments',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _history(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
    children: [
      TrainerSectionHeader(title: tr(context, 'トレーニング履歴', 'Workout history')),
      if (workouts.isEmpty)
        EmptyState(
          text: tr(
            context,
            '共有された記録はありません。顧客がSETKEEPの連携画面から記録を共有できます。',
            'No shared records. Clients can share workouts from the SETKEEP linking page.',
          ),
        ),
      for (final row in workouts)
        WorkoutCard(
          row: row,
          onComment: widget.repository is TenantRepository
              ? () => comment(date: dateLabel(row['performed_at']))
              : null,
          onCancel:
              widget.repository is TenantRepository &&
                  row['record_source'] == 'trainer'
              ? () => _toggleRecord(row)
              : null,
        ),
      if (more)
        OutlinedButton(
          onPressed: busy
              ? null
              : () => act(() async {
                  final next = await widget.repository.workouts(
                    clientId,
                    offset: workouts.length,
                  );
                  if (mounted) {
                    setState(() {
                      workouts.addAll(next);
                      more = next.length == 100;
                    });
                  }
                }),
          child: Text(tr(context, 'さらに表示', 'Load more')),
        ),
    ],
  );

  Widget _menus(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
    children: [
      TrainerSectionHeader(
        title: tr(context, 'トレーニングメニュー', 'Training menus'),
        action: tr(context, '新規作成', 'Create'),
        onAction: () => _openEditor(),
      ),
      if (menus.isEmpty)
        EmptyState(
          text: tr(context, 'メニューはまだありません', 'No menus yet'),
          action: tr(context, 'メニューを作成', 'Create menu'),
          onAction: () => _openEditor(),
        ),
      for (final menu in menus)
        MenuCard(
          menu: menu,
          onEdit: widget.repository is TenantRepository
              ? () => _openEditor(existing: menu)
              : null,
          onComment: widget.repository is TenantRepository
              ? () => comment(menu: menu['id'] as String)
              : null,
          onStatus: widget.repository is TenantRepository
              ? (status) => _setMenuStatus(menu, status)
              : null,
        ),
    ],
  );

  Widget _comments(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
    children: [
      TrainerSectionHeader(
        title: tr(context, 'コメント・指導メモ', 'Comments & coaching notes'),
      ),
      OutlinedButton.icon(
        onPressed: () => comment(),
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(tr(context, 'コメントを追加', 'Add comment')),
      ),
      const SizedBox(height: 12),
      if (notes.isEmpty)
        EmptyState(text: tr(context, 'コメントはまだありません', 'No comments yet')),
      for (final item in notes)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      item['shared_with_client'] == true
                          ? Icons.chat_bubble_outline
                          : Icons.lock_outline,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item['shared_with_client'] == true
                            ? tr(
                                context,
                                '本人のSETKEEPにも表示',
                                'Visible in client’s SETKEEP',
                              )
                            : tr(context, '担当者のみ', 'Trainers only'),
                      ),
                    ),
                    if (widget.repository is TenantRepository)
                      PopupMenuButton<String>(
                        onSelected: (value) => value == 'edit'
                            ? comment(existing: item)
                            : deleteComment(item),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(
                              tr(context, '編集・共有設定', 'Edit / sharing'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(tr(context, '削除', 'Delete')),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(item['body'] as String),
                const SizedBox(height: 8),
                Text(
                  '${dateLabel(item['updated_at'] ?? item['created_at'])}${item['workout_date'] != null ? ' · ${item['workout_date']}' : ''}${item['menu_id'] != null ? ' · ${tr(context, 'メニュー', 'Menu')}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.link['client_name'] as String),
      actions: [
        IconButton(
          onPressed: reload,
          tooltip: tr(context, '更新', 'Refresh'),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!, textAlign: TextAlign.center),
                FilledButton(
                  onPressed: reload,
                  child: Text(tr(context, '再試行', 'Retry')),
                ),
              ],
            ),
          )
        : DefaultTabController(
            length: 4,
            child: Column(
              children: [
                _header(context),
                TabBar(
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  labelPadding: EdgeInsets.zero,
                  tabs: [
                    Tab(text: tr(context, '概要', 'Overview')),
                    Tab(text: tr(context, '履歴', 'History')),
                    Tab(text: tr(context, 'メニュー', 'Menus')),
                    Tab(text: tr(context, 'コメント', 'Comments')),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _overview(context),
                      _history(context),
                      _menus(context),
                      _comments(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
  );
}

class _CommentDialog extends StatefulWidget {
  const _CommentDialog({this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  late final body = TextEditingController(
    text: widget.existing?['body'] as String? ?? '',
  );
  late bool shared =
      widget.existing == null || widget.existing!['shared_with_client'] == true;
  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr(context, 'コメント', 'Comment')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: body,
            maxLength: 10000,
            minLines: 2,
            maxLines: 5,
          ),
          CheckboxListTile(
            value: shared,
            onChanged: (v) => setState(() => shared = v!),
            title: Text(
              tr(
                context,
                '本人のSETKEEPにも表示する',
                'Also show in the client’s SETKEEP',
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, '戻る', 'Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (body.text, shared)),
        child: Text(tr(context, '保存', 'Save')),
      ),
    ],
  );
}
