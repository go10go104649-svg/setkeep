import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'official_source_repository.dart';

/// Read-only monitoring. Policy approval and scheduled activation stay server-side.
class OfficialSourcePage extends StatefulWidget {
  const OfficialSourcePage({super.key, this.repository});
  final OfficialSourceRepository? repository;

  @override
  State<OfficialSourcePage> createState() => _OfficialSourcePageState();
}

class _OfficialSourcePageState extends State<OfficialSourcePage> {
  late final repo = widget.repository ?? SupabaseOfficialSourceRepository();
  StreamSubscription<void>? subscription;
  List<Map<String, dynamic>> rows = [];
  bool busy = true, admin = false, more = false;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    load();
    subscription = repo.authChanges.listen((_) => load());
  }

  Future<void> load({bool append = false}) async {
    final version = ++generation;
    setState(() {
      busy = true;
      error = null;
      if (!append) {
        admin = false;
        rows = [];
      }
    });
    try {
      final allowed = await repo.isAdmin();
      if (!mounted || version != generation) return;
      if (!allowed) {
        setState(() {
          busy = false;
          admin = false;
          rows = [];
        });
        return;
      }
      final batch = await repo.sources(append ? rows.length : 0);
      if (!mounted || version != generation) return;
      setState(() {
        admin = true;
        busy = false;
        more = batch.length == 50;
        rows = append ? [...rows, ...batch] : batch;
      });
    } catch (_) {
      if (mounted && version == generation) {
        setState(() {
          busy = false;
          error = '公式情報を取得できませんでした。再度お試しください。';
        });
      }
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('公式情報の取得状況'),
      actions: [
        IconButton(
          onPressed: busy ? null : () => load(),
          icon: const Icon(Icons.refresh),
          tooltip: '再読み込み',
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (!busy && error == null && !admin) const Text('管理者のみ利用できます'),
          if (admin)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('利用条件を確認するまで定期取得は無効です。再確認の指定だけでは取得を開始しません。'),
                  if (rows.isEmpty) const Text('公式情報の取得対象はありません'),
                  for (final source in rows)
                    ExpansionTile(
                      title: Text(
                        '${(source['gym_chains'] as Map?)?['name'] ?? ''} '
                        '${(source['gym_stores'] as Map?)?['name'] ?? source['url']}',
                      ),
                      subtitle: Text(
                        '${officialStatus(source['status'])} ・ '
                        '${source['enabled'] == true ? '取得対象' : '定期取得無効'}\n'
                        '最終確認 ${officialDate(source['last_checked_at'])}',
                      ),
                      children: [
                        _SourceDetails(
                          key: ValueKey(source['id']),
                          source: source,
                          repo: repo,
                        ),
                      ],
                    ),
                  if (more)
                    TextButton(
                      onPressed: busy ? null : () => load(append: true),
                      child: const Text('さらに表示'),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _SourceDetails extends StatefulWidget {
  const _SourceDetails({super.key, required this.source, required this.repo});
  final Map<String, dynamic> source;
  final OfficialSourceRepository repo;
  @override
  State<_SourceDetails> createState() => _SourceDetailsState();
}

class _SourceDetailsState extends State<_SourceDetails> {
  late final snapshots = widget.repo.snapshots(widget.source['id'] as String);
  bool busy = false;
  String? message;

  Future<void> mark() async {
    setState(() => busy = true);
    try {
      await widget.repo.markForReview(widget.source['id'] as String);
      if (mounted) setState(() => message = '再確認対象にしました（取得は開始しません）');
    } catch (_) {
      if (mounted) setState(() => message = '更新できませんでした。権限と通信状態を確認してください。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const encoder = JsonEncoder.withIndent('  ');
    final source = widget.source;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(source['url'] as String),
          Text('最終成功 ${officialDate(source['last_success_at'])}'),
          Text('最終変更 ${officialDate(source['last_changed_at'])}'),
          Text('HTTP ${source['last_http_status'] ?? '未取得'}'),
          Text(
            '利用条件 ${source['policy_status'] == 'approved' ? '確認済み' : '確認が必要'}',
          ),
          Text(source['policy_note'] as String? ?? ''),
          if (source['last_error'] != null)
            Text(source['last_error'].toString()),
          Text('パーサー ${source['current_parser_version'] ?? '未実行'}'),
          if (source['parser_review_required'] == true)
            const Text('パーサー変更による差分の確認が必要です'),
          const Text('現在の抽出結果'),
          if (source['current_data'] == null)
            const Text('取得結果はありません')
          else
            SelectableText(encoder.convert(source['current_data'])),
          TextButton(
            onPressed: busy ? null : mark,
            child: const Text('再確認対象にする'),
          ),
          if (message != null) Text(message!),
          const Text('直近10件の取得履歴'),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: snapshots,
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('取得履歴を読み込めませんでした');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in snapshot.data!)
                    ExpansionTile(
                      title: Text(officialDate(row['fetched_at'])),
                      subtitle: Text(
                        'HTTP ${row['http_status'] ?? '-'} ・ '
                        '${row['error'] ?? (row['is_changed'] == true ? '変更あり' : '変更なし')}',
                      ),
                      children: [SelectableText(encoder.convert(row))],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
