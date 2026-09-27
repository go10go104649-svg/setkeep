import 'package:setkeep/design/family_theme.dart';

import 'tenant_gate.dart';
import 'trainer_widgets.dart';
import 'client_page.dart';
import 'menu_editor.dart';
export 'client_page.dart';
export 'menu_editor.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:setkeep/config/supabase_config.dart';
import 'package:setkeep/config/auth_redirects.dart';
import 'package:setkeep/services/account_auth_service.dart';
import 'package:setkeep/trainer/trainer_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(
    TrainerApp(
      auth: SupabaseConfig.initialized
          ? SupabaseAccountAuthService(
              Supabase.instance.client,
              SupabaseConfig.authStorage!,
              redirectUrl: AuthRedirects.trainer,
            )
          : null,
      repository: SupabaseConfig.initialized
          ? TrainerRepository(Supabase.instance.client)
          : null,
    ),
  );
}

class TrainerApp extends StatelessWidget {
  const TrainerApp({super.key, this.auth, this.repository});
  final AccountAuthService? auth;
  final TrainerRepository? repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SETKEEP TRAINER',
    debugShowCheckedModeBanner: false,
    supportedLocales: const [Locale('ja'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: familyTheme(FamilyPalette.trainer),
    home: auth == null || repository == null
        ? const SetupPage()
        : AuthGate(auth: auth!, repository: repository!),
  );
}

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SETKEEP TRAINER')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          tr(
            context,
            'Supabase接続設定が必要です。\n共通プロジェクトの設定でアプリを起動してください。',
            'Supabase configuration is required.\nStart the app with the shared project configuration.',
          ),
        ),
      ),
    ),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, required this.repository});
  final AccountAuthService auth;
  final TrainerRepository repository;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<void>? subscription;
  @override
  void initState() {
    super.initState();
    subscription = widget.auth.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.auth.isSignedIn
      ? TenantGate(
          key: ValueKey(widget.repository.userId),
          auth: widget.auth,
          repository: widget.repository,
        )
      : LoginPage(auth: widget.auth);
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth});
  final AccountAuthService auth;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? message;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        message = tr(
          context,
          '認証できませんでした。入力・接続を確認してください。',
          'Authentication failed. Check your input and connection.',
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SETKEEP TRAINER')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Image.asset(
              'assets/brand/trainer_icon.png',
              width: 64,
              height: 64,
              semanticLabel: 'SETKEEP TRAINER',
            ),
            const SizedBox(height: 24),
            Text(
              tr(
                context,
                'いつものアカウントで、指導を始める',
                'Coach with your SETKEEP account',
              ),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              tr(
                context,
                'SETKEEPと同じメール・パスワードでログインできます。',
                'Use the same email and password as SETKEEP.',
              ),
            ),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: tr(context, 'メール', 'Email'),
              ),
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: tr(context, 'パスワード', 'Password'),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => run(
                      () =>
                          widget.auth.signIn(email.text.trim(), password.text),
                    ),
              child: Text(tr(context, 'ログイン', 'Sign in')),
            ),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      final signedIn = await widget.auth.signUp(
                        email.text.trim(),
                        password.text,
                      );
                      if (!signedIn && context.mounted) {
                        message = tr(
                          context,
                          '確認メールのリンクを開いてからログインしてください。',
                          'Confirm your email, then sign in.',
                        );
                      }
                    }),
              child: Text(tr(context, '共通アカウントを作成', 'Create a shared account')),
            ),
            TextButton(
              onPressed: busy ? null : () => run(widget.auth.signInWithGoogle),
              child: const Text('Google'),
            ),
            if (busy) const LinearProgressIndicator(),
            if (message != null) Text(message!),
          ],
        ),
      ),
    ),
  );
}

class TrainerShell extends StatefulWidget {
  const TrainerShell({
    super.key,
    required this.auth,
    required this.repository,
    this.onManageTenant,
  });
  final AccountAuthService auth;
  final TrainerRepository repository;
  final VoidCallback? onManageTenant;
  @override
  State<TrainerShell> createState() => _TrainerShellState();
}

class _TrainerShellState extends State<TrainerShell> {
  int tab = 0;
  String clientQuery = '';
  bool loading = true, busy = false;
  String? error;
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> clients = [], menus = [];
  final name = TextEditingController();
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  int loadGeneration = 0;
  Future<void> reload() async {
    final generation = ++loadGeneration;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final p = await widget.repository.profile();
      final c = p == null
          ? <Map<String, dynamic>>[]
          : await widget.repository.clients();
      final m = p == null
          ? <Map<String, dynamic>>[]
          : await widget.repository.menus();
      if (mounted && generation == loadGeneration) {
        setState(() {
          profile = p;
          clients = c;
          menus = m;
        });
      }
    } catch (_) {
      if (mounted) {
        error = tr(
          context,
          '読み込めませんでした。接続とDB設定を確認してください。',
          'Could not load data. Check connection and database setup.',
        );
      }
    }
    if (mounted && generation == loadGeneration) {
      setState(() => loading = false);
    }
  }

  Future<void> action(Future<void> Function() work) async {
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
                '処理に失敗しました。接続と権限を確認してください。',
                'Action failed. Check connection and permissions.',
              ),
            ),
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> invite() => action(() async {
    final token = await widget.repository.createInvite();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, '顧客を招待', 'Invite a client')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: 'setkeep://trainer/invite?v=1&token=$token',
                size: 200,
              ),
              SelectableText(token),
              Text(
                tr(
                  context,
                  '24時間有効・1回限り。再発行すると旧コードは無効です。\nSETKEEPの「Trainerと連携」で読み取り・入力し、本人が承認してください。',
                  'Valid for 24 hours and one use. Reissuing invalidates the old code.\nThe client scans or enters it in SETKEEP and approves sharing.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: token)),
            child: Text(tr(context, 'コードをコピー', 'Copy code')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, '閉じる', 'Close')),
          ),
        ],
      ),
    );
  });
  Future<void> openClient(Map<String, dynamic> client) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ClientPage(repository: widget.repository, link: client),
      ),
    );
    if (mounted) await reload();
  }

  List<Map<String, dynamic>> get coachableClients =>
      clients.where((client) => client['can_coach'] != false).toList();

  List<Map<String, dynamic>> get recordableClients => coachableClients
      .where((client) => client['allow_recording'] == true)
      .toList();

  Future<void> openEditor({bool recording = false}) async {
    final eligible = recording ? recordableClients : coachableClients;
    if (eligible.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MenuEditor(
          repository: widget.repository,
          clients: eligible,
          recording: recording,
        ),
      ),
    );
    if (mounted) await reload();
  }

  Widget clientTile(Map<String, dynamic> client) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: FamilyPalette.of(context).soft,
        child: const Icon(Icons.person_outline),
      ),
      title: Text(
        client['client_name'] as String? ?? '',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            client['linked_user_id'] == null
                ? tr(context, '未連携', 'Not linked')
                : tr(context, 'SETKEEP連携済み', 'Linked to SETKEEP'),
          ),
          if (client['can_coach'] == false)
            Text(tr(context, '担当割当が必要です', 'Trainer assignment required'))
          else if (client['linked_user_id'] != null &&
              client['share_workouts'] == false)
            Text(tr(context, '履歴は非共有', 'History is private'))
          else
            LatestWorkout(
              repository: widget.repository,
              clientId: client['client_id'] as String,
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: client['can_coach'] == false ? null : () => openClient(client),
    ),
  );

  Widget _content(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
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
      );
    }
    if (profile == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            tr(context, 'トレーナープロフィール', 'Trainer profile'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            tr(
              context,
              '同じユーザーIDにトレーナープロフィールを追加します。',
              'Add a trainer profile to your existing user ID.',
            ),
          ),
          TextField(
            controller: name,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: tr(context, '表示名', 'Display name'),
            ),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () => action(() async {
                    if (name.text.trim().isEmpty) return;
                    await widget.repository.saveProfile(name.text);
                    await reload();
                  }),
            child: Text(tr(context, '指導を始める', 'Start coaching')),
          ),
          TextButton(
            onPressed: widget.auth.signOut,
            child: Text(tr(context, 'ログアウト', 'Sign out')),
          ),
        ],
      );
    }
    final children = switch (tab) {
      0 => _home(context),
      1 => _clients(context),
      2 => _menus(context),
      _ => _profile(context),
    };
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        key: ValueKey('trainerTab$tab'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: children,
      ),
    );
  }

  List<Widget> _home(BuildContext context) => [
    Text(
      tr(
        context,
        '${profile!['display_name']}さん、こんにちは',
        'Hello, ${profile!['display_name']}',
      ),
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w900),
    ),
    const SizedBox(height: 4),
    Text(tr(context, '今日の指導をここから始めましょう', 'Start today’s coaching here')),
    const SizedBox(height: 20),
    Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(
          tr(context, '担当顧客 ${clients.length}人', '${clients.length} clients'),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(tr(context, '顧客を確認', 'View clients')),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => setState(() => tab = 1),
      ),
    ),
    const SizedBox(height: 10),
    Card(
      child: ListTile(
        title: Text(
          tr(context, '作成済みメニュー ${menus.length}件', '${menus.length} menus'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => setState(() => tab = 2),
      ),
    ),
    TrainerSectionHeader(title: tr(context, 'クイックアクション', 'Quick actions')),
    FilledButton.icon(
      onPressed: busy ? null : invite,
      icon: const Icon(Icons.qr_code_rounded),
      label: Text(tr(context, '顧客を招待', 'Invite a client')),
    ),
    const SizedBox(height: 8),
    OutlinedButton.icon(
      onPressed: recordableClients.isEmpty
          ? null
          : () => openEditor(recording: true),
      icon: const Icon(Icons.edit_note_rounded),
      label: Text(tr(context, 'セッションを記録', 'Record session')),
    ),
    const SizedBox(height: 8),
    OutlinedButton.icon(
      onPressed: coachableClients.isEmpty ? null : () => openEditor(),
      icon: const Icon(Icons.playlist_add_rounded),
      label: Text(tr(context, 'メニューを作成', 'Create menu')),
    ),
    TrainerSectionHeader(
      title: tr(context, '担当顧客', 'Your clients'),
      action: tr(context, '全顧客を見る', 'See all'),
      onAction: () => setState(() => tab = 1),
    ),
    if (clients.isEmpty)
      EmptyState(
        text: tr(
          context,
          '担当顧客はまだいません。招待コードを共有し、顧客の承認を待ちましょう。',
          'No clients yet. Share an invitation and wait for approval.',
        ),
        action: tr(context, '顧客を招待', 'Invite a client'),
        onAction: invite,
      ),
    for (final client in clients.take(3)) clientTile(client),
  ];

  List<Widget> _clients(BuildContext context) {
    final filtered = clients
        .where(
          (client) => '${client['client_name']}'.toLowerCase().contains(
            clientQuery.toLowerCase(),
          ),
        )
        .toList();
    return [
      Text(
        tr(context, '顧客', 'Clients'),
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
      Text(tr(context, '${clients.length}人の顧客', '${clients.length} clients')),
      const SizedBox(height: 16),
      TextField(
        key: const Key('clientSearchField'),
        decoration: InputDecoration(
          labelText: tr(context, '顧客を検索', 'Search clients'),
          prefixIcon: const Icon(Icons.search_rounded),
        ),
        onChanged: (value) => setState(() => clientQuery = value.trim()),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy ? null : invite,
        icon: const Icon(Icons.qr_code_rounded),
        label: Text(tr(context, '顧客を招待', 'Invite a client')),
      ),
      const SizedBox(height: 16),
      if (filtered.isEmpty)
        EmptyState(
          text: clients.isEmpty
              ? tr(
                  context,
                  '担当顧客はまだいません。招待コードを共有し、顧客の承認を待ちましょう。',
                  'No clients yet. Share an invitation and wait for approval.',
                )
              : tr(context, '該当する顧客がいません', 'No matching clients'),
          action: clients.isEmpty
              ? tr(context, '顧客を招待', 'Invite a client')
              : null,
          onAction: clients.isEmpty ? invite : null,
        ),
      for (final client in filtered) clientTile(client),
    ];
  }

  List<Widget> _menus(BuildContext context) => [
    Text(
      tr(context, 'メニュー', 'Menus'),
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w900),
    ),
    Text(tr(context, '${menus.length}件のメニュー', '${menus.length} menus')),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: coachableClients.isEmpty ? null : () => openEditor(),
      icon: const Icon(Icons.add_rounded),
      label: Text(tr(context, '新規作成', 'Create menu')),
    ),
    const SizedBox(height: 16),
    if (menus.isEmpty)
      EmptyState(
        text: tr(
          context,
          'メニューはまだありません。顧客と連携して作成しましょう。',
          'No menus yet. Link a client to create one.',
        ),
        action: coachableClients.isEmpty
            ? null
            : tr(context, 'メニューを作成', 'Create menu'),
        onAction: coachableClients.isEmpty ? null : () => openEditor(),
      ),
    for (final menu in menus)
      MenuCard(
        menu: menu,
        clientName:
            clients
                    .where((client) => client['client_id'] == menu['client_id'])
                    .firstOrNull?['client_name']
                as String?,
      ),
  ];

  List<Widget> _profile(BuildContext context) => [
    Text(
      tr(context, 'マイページ', 'Profile'),
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w900),
    ),
    TrainerSectionHeader(title: tr(context, 'アカウント', 'Account')),
    Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(profile!['display_name'] as String),
            subtitle: Text(widget.auth.email ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(
              tr(context, 'SETKEEPと共通のアカウント', 'Shared SETKEEP account'),
            ),
            subtitle: Text(
              tr(context, '顧客の体重は公開されません', 'Client body weight is private'),
            ),
          ),
        ],
      ),
    ),
    TrainerSectionHeader(
      title: tr(context, '所属・管理', 'Organization & management'),
    ),
    Card(
      child: ListTile(
        leading: const Icon(Icons.business_outlined),
        title: Text(tr(context, 'テナント管理', 'Tenant management')),
        subtitle: Text(
          tr(context, 'スタッフ・顧客・契約を管理', 'Manage staff, clients and billing'),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: widget.onManageTenant,
      ),
    ),
    TrainerSectionHeader(title: tr(context, 'セッション', 'Session')),
    OutlinedButton.icon(
      onPressed: busy ? null : () => action(widget.auth.signOut),
      icon: const Icon(Icons.logout_rounded),
      label: Text(tr(context, 'ログアウト', 'Sign out')),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final labels = [
      tr(context, 'ホーム', 'Home'),
      tr(context, '顧客', 'Clients'),
      tr(context, 'メニュー', 'Menus'),
      tr(context, 'マイページ', 'Profile'),
    ];
    final icons = [
      Icons.home_outlined,
      Icons.people_outline,
      Icons.list_alt,
      Icons.person_outline,
    ];
    final content = _content(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SETKEEP TRAINER'),
        actions: [
          IconButton(
            onPressed: loading ? null : reload,
            tooltip: tr(context, '更新', 'Refresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, size) => Row(
          children: [
            if (size.maxWidth >= 720)
              NavigationRail(
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (var i = 0; i < 4; i++)
                    NavigationRailDestination(
                      icon: Icon(icons[i]),
                      label: Text(labels[i]),
                    ),
                ],
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= 720
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [
                for (var i = 0; i < 4; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
              ],
            ),
    );
  }
}
