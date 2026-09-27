import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setkeep/trainer/tenant_repository.dart';
import 'package:setkeep_trainer/client_page.dart';

import 'trainer_app_test.dart' show FakeRepository, link;

class CommentRepository extends FakeRepository implements TenantRepository {
  final rows = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> notes(String clientId) async => [...rows];
  @override
  Future<void> saveComment(
    String clientId,
    String body, {
    Map<String, dynamic>? existing,
    String? menuId,
    String? date,
    bool shared = true,
    bool delete = false,
  }) async {
    if (existing != null) {
      expect(existing['version'], rows.single['version']);
      rows.removeWhere((r) => r['id'] == existing['id']);
    }
    if (!delete) {
      rows.add({
        'id': existing?['id'] ?? 'new-comment',
        'client_id': clientId,
        'body': body,
        'shared_with_client': shared,
        'version': ((existing?['version'] as int?) ?? 0) + 1,
        'created_at': '2026-09-25',
        'updated_at': '2026-09-25',
      });
    }
  }
}

void main() {
  testWidgets(
    'TRAINER publishes, edits same comment, then deletes with confirmation',
    (t) async {
      t.view.physicalSize = const Size(600, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = CommentRepository();
      await t.pumpWidget(
        MaterialApp(
          home: ClientPage(repository: repo, link: link()),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Comments'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add comment'));
      await t.pumpAndSettle();
      await t.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Client advice',
      );
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.rows.single['client_id'], 'client-id');
      expect(repo.rows.single['shared_with_client'], true);
      await t.ensureVisible(find.byType(PopupMenuButton<String>));
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Edit / sharing'));
      await t.pumpAndSettle();
      await t.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Edited advice',
      );
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.rows.single['id'], 'new-comment');
      expect(repo.rows.single['body'], 'Edited advice');
      expect(repo.rows.single['version'], 2);
      await t.ensureVisible(find.byType(PopupMenuButton<String>));
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(repo.rows, hasLength(1));
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect(repo.rows, isEmpty);
    },
  );
  testWidgets('existing internal notes are not published just by editing', (
    t,
  ) async {
    t.view.physicalSize = const Size(600, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = CommentRepository()
      ..rows.add({
        'id': 'old',
        'body': 'Private',
        'version': 1,
        'shared_with_client': false,
      });
    await t.pumpWidget(
      MaterialApp(
        home: ClientPage(repository: repo, link: link()),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Comments'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byType(PopupMenuButton<String>));
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Edit / sharing'));
    await t.pumpAndSettle();
    final checkbox = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(CheckboxListTile),
    );
    expect(t.widget<CheckboxListTile>(checkbox).value, false);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(repo.rows.single['shared_with_client'], false);
  });
}
