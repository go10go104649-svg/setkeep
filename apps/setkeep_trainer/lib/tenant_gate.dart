import 'package:flutter/material.dart';
import 'package:setkeep/services/account_auth_service.dart';
import 'package:setkeep/trainer/trainer_repository.dart';
import 'package:setkeep/trainer/tenant_repository.dart';

import 'main.dart' show TrainerShell;
import 'tenant_management.dart';
import 'trainer_widgets.dart';

class TenantGate extends StatefulWidget {
  const TenantGate({super.key, required this.auth, required this.repository});
  final AccountAuthService auth;
  final TrainerRepository repository;
  @override
  State<TenantGate> createState() => _TenantGateState();
}

class _TenantGateState extends State<TenantGate> {
  List<Map<String, dynamic>>? tenants;
  String? selected, error;
  int generation = 0;
  final name = TextEditingController(), code = TextEditingController();
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    name.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    final request = ++generation;
    setState(() {
      tenants = null;
      error = null;
    });
    try {
      final rows = await widget.repository.tenants();
      if (!mounted || request != generation) return;
      setState(() {
        tenants = rows;
        selected = rows.any((t) => t['id'] == selected)
            ? selected
            : rows.firstOrNull?['id'] as String?;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () => error = tr(
            context,
            '所属を取得できませんでした。再試行してください。',
            'Could not load memberships. Retry.',
          ),
        );
      }
    }
  }

  Future<void> create() async {
    if (name.text.trim().isEmpty) return;
    try {
      if (await widget.repository.profile() == null) {
        await widget.repository.saveProfile(name.text);
      }
      selected = await widget.repository.createTenant(name.text, 'personal');
      await reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = tr(context, '作成できませんでした', 'Could not create tenant'),
        );
      }
    }
  }

  Future<void> openManagement(TenantRepository repository) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TenantManagement(
          repository: repository,
          tenant: tenants!.firstWhere((tenant) => tenant['id'] == selected),
        ),
      ),
    );
    if (mounted) await reload();
  }

  @override
  Widget build(BuildContext context) {
    if (tenants == null || tenants!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('SETKEEP TRAINER')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(error!, textAlign: TextAlign.center),
                          OutlinedButton(
                            onPressed: reload,
                            child: Text(tr(context, '再試行', 'Retry')),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (tenants == null && error == null)
                  const LinearProgressIndicator(),
                if (tenants != null) ...[
                  TrainerSectionHeader(
                    title: tr(context, '所属を始める', 'Join an organization'),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            tr(
                              context,
                              '契約する組織・個人事業の名前',
                              'Organization or personal business name',
                            ),
                          ),
                          TextField(controller: name, maxLength: 120),
                          FilledButton(
                            onPressed: create,
                            child: Text(
                              tr(context, 'テナントを作成', 'Create tenant'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: code,
                            decoration: InputDecoration(
                              labelText: tr(
                                context,
                                'スタッフ招待コード',
                                'Staff invitation code',
                              ),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              try {
                                await widget.repository.acceptInvite(
                                  code.text.trim(),
                                  '',
                                  recording: false,
                                  heatmap: false,
                                );
                                await reload();
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () => error = tr(
                                      context,
                                      '招待を確認できませんでした。招待先のメールでログインしてください。',
                                      'Cannot accept invitation. Sign in using the invited email.',
                                    ),
                                  );
                                }
                              }
                            },
                            child: Text(
                              tr(context, '招待を受ける', 'Accept invitation'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (tenants != null)
                  TextButton(
                    onPressed: reload,
                    child: Text(tr(context, '再試行', 'Retry')),
                  ),
                TextButton(
                  onPressed: widget.auth.signOut,
                  child: Text(tr(context, 'ログアウト', 'Sign out')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final repo = widget.repository.forTenant(selected!);
    return Column(
      children: [
        Material(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selected,
                      items: [
                        for (final t in tenants!)
                          DropdownMenuItem(
                            value: t['id'] as String,
                            child: Text(t['name'] as String),
                          ),
                      ],
                      onChanged: (id) {
                        // A new Navigator disposes all old client/editor routes immediately.
                        setState(() {
                          selected = id;
                          generation++;
                        });
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, 'テナント管理', 'Tenant settings'),
                    icon: const Icon(Icons.settings),
                    onPressed: repo is TenantRepository
                        ? () => openManagement(repo)
                        : null,
                  ),
                  IconButton(
                    tooltip: tr(context, 'テナントを追加', 'Add tenant'),
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(tr(ctx, '新しいテナント', 'New tenant')),
                          content: TextField(controller: name),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                create();
                              },
                              child: Text(tr(ctx, '作成', 'Create')),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Navigator(
            key: ValueKey('$selected:$generation'),
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => TrainerShell(
                auth: widget.auth,
                repository: repo,
                onManageTenant: repo is TenantRepository
                    ? () => openManagement(repo)
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
