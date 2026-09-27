import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:setkeep/trainer/tenant_repository.dart';

import 'trainer_widgets.dart';

class TenantManagement extends StatefulWidget {
  const TenantManagement({
    super.key,
    required this.repository,
    required this.tenant,
  });
  final TenantRepository repository;
  final Map<String, dynamic> tenant;
  @override
  State<TenantManagement> createState() => _TenantManagementState();
}

class _TenantManagementState extends State<TenantManagement> {
  List<Map<String, dynamic>>? members, clients, assignments;
  Map<String, dynamic>? billing;
  String? error;
  bool busy = false, inviteAdmin = false, inviteTrainer = true;
  final name = TextEditingController(),
      email = TextEditingController(),
      code = TextEditingController();
  bool get owner =>
      widget.tenant['billing_owner_id'] == widget.repository.userId;
  bool get admin =>
      members
          ?.where((m) => m['user_id'] == widget.repository.userId)
          .firstOrNull?['is_admin'] ==
      true;
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final m = await widget.repository.members();
      final c = await widget.repository.clients();
      final a = await widget.repository.assignments();
      final b = owner ? await widget.repository.billing() : null;
      if (mounted) {
        setState(() {
          error = null;
          members = m;
          clients = c;
          assignments = a;
          billing = b;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(context, '読み込めませんでした', 'Could not load settings'),
        );
      }
    }
  }

  Future<void> run(Future<void> Function() f) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
      await reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(
            context,
            '処理できませんでした。権限・招待先・トライアルの人数上限を確認してください。',
            'Action failed. Check permissions, invitation email and trial seat limit.',
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> showCode(String token) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          tr(ctx, '24時間・1回限りの招待', 'One-use invitation, valid 24 hours'),
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
            onPressed: () => Clipboard.setData(ClipboardData(text: token)),
            child: Text(tr(ctx, 'コピー', 'Copy')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(ctx, '閉じる', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<bool> confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, '戻る', 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(ctx, '続ける', 'Continue')),
            ),
          ],
        ),
      ) ??
      false;

  Widget _staff(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    children: [
      TrainerSectionHeader(title: tr(context, '招待を受ける', 'Accept invitation')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: tr(
                    context,
                    '別テナントのスタッフ招待コード',
                    'Staff invitation to another tenant',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => run(() async {
                  await widget.repository.acceptInvite(
                    code.text.trim(),
                    '',
                    recording: false,
                    heatmap: false,
                  );
                  if (context.mounted) Navigator.pop(context);
                }),
                child: Text(tr(context, '招待を受ける', 'Accept invitation')),
              ),
            ],
          ),
        ),
      ),
      if (admin) ...[
        TrainerSectionHeader(title: tr(context, 'スタッフを招待', 'Invite staff')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: tr(context, '招待先メール', 'Invited email'),
                  ),
                ),
                CheckboxListTile(
                  value: inviteAdmin,
                  onChanged: (v) => setState(() => inviteAdmin = v!),
                  title: const Text('Admin'),
                ),
                CheckboxListTile(
                  value: inviteTrainer,
                  onChanged: (v) => setState(() => inviteTrainer = v!),
                  title: const Text('Trainer'),
                ),
                FilledButton(
                  onPressed: !inviteAdmin && !inviteTrainer
                      ? null
                      : () => run(() async {
                          final result = await widget.repository.mutate(
                            'staff_invite',
                            {
                              'email': email.text.trim(),
                              'admin': inviteAdmin,
                              'trainer': inviteTrainer,
                            },
                          );
                          await showCode(result['id'] as String);
                        }),
                  child: Text(tr(context, 'コードを発行', 'Create code')),
                ),
              ],
            ),
          ),
        ),
      ],
      TrainerSectionHeader(title: tr(context, '所属スタッフ', 'Members')),
      for (final member in members ?? <Map<String, dynamic>>[])
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
            title: Text(
              member['display_name'] as String? ?? 'Member',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${member['status']}${widget.tenant['billing_owner_id'] == member['user_id'] ? ' · Billing Owner' : ''}',
            ),
            children: admin
                ? [
                    for (final role in ['admin', 'trainer'])
                      CheckboxListTile(
                        title: Text(role == 'admin' ? 'Admin' : 'Trainer'),
                        value: member['is_$role'] == true,
                        onChanged: (value) async {
                          if (value == false &&
                              !await confirm(
                                tr(context, '権限を解除しますか？', 'Remove this role?'),
                              )) {
                            return;
                          }
                          await run(
                            () => widget.repository
                                .mutate('member', {
                                  'user_id': member['user_id'],
                                  'admin': role == 'admin'
                                      ? value
                                      : member['is_admin'],
                                  'trainer': role == 'trainer'
                                      ? value
                                      : member['is_trainer'],
                                  'status': member['status'],
                                })
                                .then((_) {}),
                          );
                        },
                      ),
                    ListTile(
                      leading: Icon(
                        member['status'] == 'active'
                            ? Icons.person_remove_outlined
                            : Icons.person_add_outlined,
                      ),
                      title: Text(
                        member['status'] == 'active'
                            ? tr(context, '所属を解除', 'Remove membership')
                            : tr(context, '再有効化', 'Reactivate'),
                      ),
                      onTap: () async {
                        if (member['status'] == 'active' &&
                            !await confirm(
                              tr(
                                context,
                                '所属を解除しますか？',
                                'Remove this membership?',
                              ),
                            )) {
                          return;
                        }
                        await run(
                          () => widget.repository
                              .mutate('member', {
                                'user_id': member['user_id'],
                                'admin': member['is_admin'],
                                'trainer': member['is_trainer'],
                                'status': member['status'] == 'active'
                                    ? 'removed'
                                    : 'active',
                              })
                              .then((_) {}),
                        );
                      },
                    ),
                    if (owner &&
                        member['user_id'] != widget.repository.userId &&
                        member['status'] == 'active')
                      ListTile(
                        leading: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        title: Text(
                          tr(context, '請求責任者を移譲', 'Transfer billing ownership'),
                        ),
                        onTap: () async {
                          if (!await confirm(
                            tr(
                              context,
                              '請求責任者を移譲しますか？',
                              'Transfer billing ownership?',
                            ),
                          )) {
                            return;
                          }
                          await run(() async {
                            await widget.repository.mutate('owner', {
                              'user_id': member['user_id'],
                            });
                            if (context.mounted) Navigator.pop(context);
                          });
                        },
                      ),
                  ]
                : [],
          ),
        ),
    ],
  );

  Widget _clients(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    children: [
      TrainerSectionHeader(title: tr(context, '顧客管理', 'Client management')),
      if (!admin)
        EmptyState(text: tr(context, '管理者権限が必要です', 'Admin access required')),
      if (admin) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: name,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: tr(context, 'オフライン顧客名', 'Offline client name'),
                  ),
                ),
                FilledButton(
                  onPressed: () => run(() async {
                    await widget.repository.mutate('client', {
                      'name': name.text.trim(),
                    });
                    name.clear();
                  }),
                  child: Text(tr(context, '顧客を登録', 'Create client')),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final client in clients ?? <Map<String, dynamic>>[])
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(client['client_name'] as String),
              subtitle: Text(
                client['linked_user_id'] == null
                    ? tr(context, 'SETKEEP未連携', 'Not linked to SETKEEP')
                    : tr(context, 'SETKEEP連携済み', 'Linked to SETKEEP'),
              ),
            ),
          ),
        if (clients?.isEmpty == true)
          EmptyState(text: tr(context, '顧客はまだいません', 'No clients yet')),
      ],
    ],
  );

  Widget _assignments(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    children: [
      TrainerSectionHeader(title: tr(context, '担当割当', 'Trainer assignments')),
      if (!admin)
        EmptyState(text: tr(context, '管理者権限が必要です', 'Admin access required')),
      if (admin)
        for (final client in clients ?? <Map<String, dynamic>>[])
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              title: Text(client['client_name'] as String),
              subtitle: Text(
                tr(context, '担当トレーナーを選択', 'Choose assigned trainers'),
              ),
              children: [
                for (final member in members ?? <Map<String, dynamic>>[])
                  if (member['is_trainer'] == true &&
                      member['status'] == 'active')
                    CheckboxListTile(
                      title: Text(
                        member['display_name'] as String? ?? 'Member',
                      ),
                      value: (assignments ?? []).any(
                        (assignment) =>
                            assignment['client_id'] == client['id'] &&
                            assignment['user_id'] == member['user_id'],
                      ),
                      onChanged: (value) async {
                        if (value == false &&
                            !await confirm(
                              tr(
                                context,
                                '担当を解除しますか？',
                                'Remove this assignment?',
                              ),
                            )) {
                          return;
                        }
                        await run(
                          () => widget.repository
                              .mutate(value! ? 'assign' : 'unassign', {
                                'client_id': client['id'],
                                'user_id': member['user_id'],
                              })
                              .then((_) {}),
                        );
                      },
                    ),
              ],
            ),
          ),
    ],
  );

  Widget _billing(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    children: [
      TrainerSectionHeader(
        title: tr(context, '契約・請求', 'Subscription & billing'),
      ),
      if (billing == null)
        EmptyState(
          text: tr(context, '請求責任者のみ確認できます', 'Billing owner access required'),
        ),
      if (billing != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${billing!['status']} · ${billing!['active_trainers']} Trainer IDs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '¥${billing!['monthly_jpy']} / ${tr(context, '月', 'month')}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 14),
                Text(
                  tr(
                    context,
                    '月額3,980円（5名まで）、追加1名500円。14日間のトライアルはカード登録後に開始し、5名までです。決済画面の接続は準備中です。',
                    '¥3,980/month includes 5 trainers, then ¥500 per trainer. The 14-day trial requires a card and allows 5 trainers. Checkout integration is pending.',
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.tenant['name'] as String),
        actions: [
          IconButton(
            onPressed: reload,
            tooltip: tr(context, '更新', 'Refresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: Column(
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: Text(error!)),
                    TextButton(
                      onPressed: reload,
                      child: Text(tr(context, '再試行', 'Retry')),
                    ),
                  ],
                ),
              ),
            if (busy || (members == null && error == null))
              const LinearProgressIndicator(),
            TabBar(
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              labelPadding: EdgeInsets.zero,
              tabs: [
                Tab(text: tr(context, 'スタッフ', 'Staff')),
                Tab(text: tr(context, '顧客', 'Clients')),
                Tab(text: tr(context, '担当割当', 'Assignments')),
                Tab(text: tr(context, '契約', 'Billing')),
              ],
            ),
            Expanded(
              child: members == null
                  ? error == null
                        ? const Center(child: CircularProgressIndicator())
                        : EmptyState(text: error!)
                  : TabBarView(
                      children: [
                        _staff(context),
                        _clients(context),
                        _assignments(context),
                        _billing(context),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
