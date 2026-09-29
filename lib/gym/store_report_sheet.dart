import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'gym_repository.dart';

const storeReportKinds = {
  'temporarily_closed': '一時休業している',
  'reopened': '営業再開している',
  'closed': '閉店している',
  'relocated': '移転している',
  'wrong_name': '店舗名が違う',
  'wrong_address': '住所が違う',
  'other': 'その他',
};

Future<void> showGymStoreReport(BuildContext context, {GymStore? store}) async {
  final repo = GymServices.repository;
  if (!repo.canReport) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('店舗情報の報告にはログインが必要です。')));
    return;
  }
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StoreReportSheet(store: store, repo: repo),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('店舗情報の報告を受け付けました。確認のうえ反映します。')),
    );
  }
}

class _StoreReportSheet extends StatefulWidget {
  const _StoreReportSheet({this.store, required this.repo});
  final GymStore? store;
  final GymRepository repo;
  @override
  State<_StoreReportSheet> createState() => _StoreReportSheetState();
}

class _StoreReportSheetState extends State<_StoreReportSheet> {
  late String kind = widget.store == null ? 'new_store' : 'temporarily_closed';
  final chain = TextEditingController(),
      name = TextEditingController(),
      address = TextEditingController(),
      url = TextEditingController(),
      comment = TextEditingController();
  Map<String, String> chains = {};
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.store == null) {
      widget.repo
          .chains()
          .then((value) {
            if (mounted) setState(() => chains = value);
          })
          .catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    for (final c in [chain, name, address, url, comment]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get needsName => kind == 'new_store' || kind == 'wrong_name';
  bool get needsAddress =>
      ['new_store', 'relocated', 'wrong_address'].contains(kind);
  bool get valid =>
      (!needsName || name.text.trim().isNotEmpty) &&
      (!needsAddress || address.text.trim().isNotEmpty) &&
      (kind != 'new_store' || chain.text.trim().isNotEmpty) &&
      (kind != 'other' || comment.text.trim().isNotEmpty) &&
      (url.text.trim().isEmpty ||
          (Uri.tryParse(url.text.trim())?.hasAuthority == true &&
              [
                'http',
                'https',
              ].contains(Uri.tryParse(url.text.trim())?.scheme)));
  Future<void> submit() async {
    if (!valid || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final matches = chains.entries.where((e) => e.value == chain.text.trim());
      await widget.repo.reportStore(
        storeId: widget.store?.id,
        chainId:
            widget.store?.chainId ??
            (matches.length == 1 ? matches.single.key : null),
        chainName: widget.store?.chainName ?? chain.text.trim(),
        kind: kind,
        name: needsName ? name.text.trim() : null,
        address: needsAddress ? address.text.trim() : null,
        officialUrl: url.text.trim().isEmpty ? null : url.text.trim(),
        comment: comment.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (kDebugMode) debugPrint('Store report failed: $e');
      if (mounted) {
        setState(() {
          busy = false;
          error = '報告を送信できませんでした。時間をおいて再度お試しください。';
        });
      }
    }
  }

  Widget field(
    String key,
    String label,
    TextEditingController c, {
    int max = 200,
  }) => TextField(
    key: Key(key),
    controller: c,
    enabled: !busy,
    maxLength: max,
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.store == null ? '掲載されていない店舗を報告' : '店舗情報を報告',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (widget.store != null) Text(widget.store!.displayName),
          if (widget.store != null)
            DropdownButtonFormField<String>(
              key: const Key('storeReportKind'),
              initialValue: kind,
              isExpanded: true,
              items: [
                for (final e in storeReportKinds.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: busy ? null : (value) => setState(() => kind = value!),
            ),
          if (kind == 'new_store') ...[
            const Text('共有の店舗情報への掲載を依頼します。すぐには追加されません。'),
            if (chains.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '登録済みチェーンから入力（任意）',
                ),
                items: [
                  for (final e in chains.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() => chain.text = chains[v] ?? ''),
              ),
            field('storeReportChain', 'ブランド・チェーン（必須）', chain),
          ],
          if (needsName) field('storeReportName', '店舗名（必須）', name),
          if (needsAddress)
            field('storeReportAddress', '住所・所在地（必須）', address, max: 1000),
          field('storeReportUrl', '公式URL（任意）', url, max: 2000),
          field(
            'storeReportComment',
            kind == 'other' ? '内容（必須）' : 'コメント（任意）',
            comment,
            max: 1000,
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            key: const Key('submitStoreReport'),
            onPressed: valid && !busy ? submit : null,
            child: Text(busy ? '送信中…' : '報告を送信'),
          ),
        ],
      ),
    ),
  );
}
