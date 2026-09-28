import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../trainer_invite_qr.dart';
import '../trainer_qr_page.dart';
import 'trainer_repository.dart';

/// Explicit publishing keeps pre-existing local history private by default.
class TrainerSharingPage extends StatefulWidget {
  const TrainerSharingPage({
    super.key,
    required this.history,
    this.onLinked,
    this.repository,
  });
  final List<Map<String, dynamic>> history;
  final Future<void> Function()? onLinked;
  final TrainerRepository? repository;
  @override
  State<TrainerSharingPage> createState() => _TrainerSharingPageState();
}

class _TrainerSharingPageState extends State<TrainerSharingPage> {
  late final TrainerRepository? repo =
      widget.repository ??
      (SupabaseConfig.initialized &&
              Supabase.instance.client.auth.currentUser != null
          ? TrainerRepository(Supabase.instance.client)
          : null);
  final code = TextEditingController(), name = TextEditingController();
  List<Map<String, dynamic>> links = [];
  final selected = <int>{};
  bool busy = false, recording = false, heatmap = false;
  String? trainerName, token, message;
  String text(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;
  @override
  void initState() {
    super.initState();
    if (repo != null) load();
  }

  @override
  void dispose() {
    code.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> load() async {
    await run(() async {
      final result = await repo!.myLinks();
      if (mounted) setState(() => links = result);
    });
  }

  Future<void> run(Future<void> Function() work) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work();
    } catch (_) {
      if (mounted) {
        message = text(
          '処理を完了できませんでした。接続・ログイン・招待の有効期限を確認してください。',
          'Could not complete the action. Check connection, sign-in and invitation expiry.',
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> preview(String raw) => run(() async {
    // Invalidate old preview before another lookup, including failed lookups.
    setState(() {
      trainerName = null;
      token = null;
      recording = false;
      heatmap = false;
    });
    final value = TrainerInviteQr.parse(raw.trim())?.token ?? raw.trim();
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw const FormatException();
    }
    final result = await repo!.previewInvite(value);
    if (result == null) throw const FormatException();
    if (mounted) {
      setState(() {
        trainerName = result;
        token = value;
      });
    }
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('trainerSharingPage'),
    appBar: AppBar(
      title: Text(text('SETKEEP TRAINERと連携', 'Connect to SETKEEP TRAINER')),
    ),
    body: repo == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                text(
                  '先にマイページの「アカウント」でログインしてください。',
                  'Sign in from Account on your profile first.',
                ),
              ),
            ),
          )
        : AbsorbPointer(
            absorbing: busy,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  text('招待コードで連携', 'Link with an invitation'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextField(
                  controller: code,
                  decoration: InputDecoration(
                    labelText: text('招待コード / 招待URL', 'Invitation code / URL'),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => preview(code.text),
                  child: Text(text('招待を確認', 'Check invitation')),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TrainerQrPage(
                          onInvite: (invite) =>
                              Navigator.pop(context, invite.token),
                        ),
                      ),
                    );
                    if (result != null && mounted) await preview(result);
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(text('QRコードを読み取る', 'Scan QR code')),
                ),
                if (trainerName != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text('連携先：$trainerName', 'Trainer: $trainerName'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            text(
                              '承認すると、表示名とクラウド上のトレーニング履歴をこのテナントの担当トレーナーに共有します。端末内の記録は下で選択して送信できます。体重は共有しません。履歴から運動した部位も分かります。',
                              'Approval shares your display name and cloud workout history with assigned trainers in this tenant. Select local records below to publish them. Body weight stays private. Workout history also reveals exercised body parts.',
                            ),
                          ),
                          TextField(
                            controller: name,
                            maxLength: 80,
                            decoration: InputDecoration(
                              labelText: text('相手に表示する名前', 'Your display name'),
                            ),
                          ),
                          CheckboxListTile(
                            value: recording,
                            onChanged: (v) => setState(() => recording = v!),
                            title: Text(
                              text(
                                '顧客本人の履歴への代理記録を許可',
                                'Allow recording sessions in my history',
                              ),
                            ),
                          ),
                          CheckboxListTile(
                            value: heatmap,
                            onChanged: (v) => setState(() => heatmap = v!),
                            title: Text(
                              text(
                                '履歴からの部位ヒートマップ表示を許可',
                                'Allow heatmap display from workout history',
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: () => run(() async {
                              if (name.text.trim().isEmpty) {
                                throw const FormatException();
                              }
                              await repo!.acceptInvite(
                                token!,
                                name.text,
                                recording: recording,
                                heatmap: heatmap,
                              );
                              if (widget.onLinked != null) {
                                await widget.onLinked!();
                              }
                              final updated = await repo!.myLinks();
                              if (mounted) {
                                setState(() {
                                  links = updated;
                                  trainerName = null;
                                  token = null;
                                  message = text(
                                    '連携しました',
                                    'Linked successfully',
                                  );
                                });
                              }
                            }),
                            child: Text(
                              text('内容を確認して承認', 'Approve this sharing'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  text('連携中のトレーナー', 'Linked trainers'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (links.isEmpty) Text(text('連携はありません', 'No active links')),
                for (final l in links)
                  Card(
                    child: ListTile(
                      title: Text(
                        (l['trainer_profiles'] as Map?)?['display_name']
                                as String? ??
                            text('承認済みの連携', 'Approved link'),
                      ),
                      subtitle: Text(
                        text('共有中のトレーニング履歴', 'Shared workout history'),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                text('連携を解除しますか？', 'Revoke this link?'),
                              ),
                              content: Text(
                                text(
                                  '今後の履歴閲覧と代理記録を停止します。既に閲覧された情報やトレーナーのメモは消去されません。',
                                  'This stops future history access and recording. Information already viewed and tenant coaching notes are not erased.',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(text('戻る', 'Cancel')),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(text('解除', 'Revoke')),
                                ),
                              ],
                            ),
                          );
                          if (yes == true && mounted) {
                            await run(() async {
                              await repo!.revoke(l['id'] as String);
                              final updated = await repo!.myLinks();
                              if (mounted) setState(() => links = updated);
                            });
                          }
                        },
                        child: Text(text('解除', 'Revoke')),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  text('端末内の記録を選んで共有', 'Select local records to share'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  text(
                    '選択した記録は、履歴共有を承認したすべての連携中トレーナーが閲覧できます。記録の内容が自分のものであることを確認してください。',
                    'Selected records are visible to all linked trainers authorized to read your history. Confirm that the records belong to you.',
                  ),
                ),
                for (var i = 0; i < widget.history.length; i++)
                  CheckboxListTile(
                    value: selected.contains(i),
                    onChanged: links.isEmpty
                        ? null
                        : (v) => setState(() {
                            if (v!) {
                              selected.add(i);
                            } else {
                              selected.remove(i);
                            }
                          }),
                    title: Text(
                      '${widget.history[i]['date']}'.split('T').first,
                    ),
                    subtitle: Text(
                      '${(widget.history[i]['sets'] as List).length} ${text('セット', 'sets')}',
                    ),
                  ),
                FilledButton(
                  onPressed: selected.isEmpty || links.isEmpty
                      ? null
                      : () => run(() async {
                          for (final i in selected) {
                            await repo!.shareWorkout(widget.history[i]);
                          }
                          if (mounted) {
                            setState(() {
                              message = text(
                                '${selected.length}件を共有しました',
                                'Shared ${selected.length} workouts',
                              );
                              selected.clear();
                            });
                          }
                        }),
                  child: Text(text('選択した記録を共有', 'Share selected workouts')),
                ),
                if (busy) const LinearProgressIndicator(),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(message!),
                  ),
              ],
            ),
          ),
  );
}
