import 'package:supabase_flutter/supabase_flutter.dart';

class FriendsRepository {
  FriendsRepository(this.client);
  final SupabaseClient client;
  String get userId => client.auth.currentUser!.id;

  Future<Map<String, dynamic>?> profile() async => await client
      .from('friend_profiles')
      .select()
      .eq('user_id', userId)
      .maybeSingle();
  Future<void> saveProfile(String name, String visibility) async {
    final existing = await profile();
    final values = {'display_name': name.trim(), 'visibility': visibility};
    if (existing == null) {
      await client.from('friend_profiles').insert({
        'user_id': userId,
        ...values,
      });
    } else {
      await client.from('friend_profiles').update(values).eq('user_id', userId);
    }
  }

  static Future<void> _publication = Future<void>.value();
  Future<void> publish(List<Map<String, dynamic>> records) {
    final owner = userId;
    final payload = records
        .where(
          (r) =>
              r['trainerOwnerUserId'] == null ||
              r['trainerOwnerUserId'] == owner,
        )
        .map(
          (r) => {
            'date': r['date'],
            'durationSeconds': r['durationSeconds'],
            'sets': r['sets'],
          },
        )
        .toList();
    final next = _publication.then((_) async {
      if (client.auth.currentUser?.id != owner) return;
      await client.rpc('publish_friend_workouts', params: {'records': payload});
    });
    _publication = next.catchError((Object _) {});
    return next;
  }

  Future<List<Map<String, dynamic>>> connections() async =>
      List<Map<String, dynamic>>.from(
        await client.rpc('list_friend_connections'),
      );
  Future<void> request(String code) async {
    await client.rpc('request_friend', params: {'code': code.trim()});
  }

  Future<void> accept(String id) async {
    await client.rpc('accept_friend', params: {'connection_id': id});
  }

  Future<void> remove(String id) async {
    await client.from('friend_connections').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> feed({String? owner}) async {
    final query = client
        .from('friend_workouts')
        .select(
          '*, friend_profiles!inner(display_name), friend_likes(user_id), friend_comments(id)',
        );
    return await (owner == null
            ? query.neq('user_id', userId)
            : query.eq('user_id', owner))
        .order('performed_at', ascending: false)
        .limit(1000);
  }

  Future<List<Map<String, dynamic>>> comments(String id) async => await client
      .from('friend_comments')
      .select()
      .eq('workout_id', id)
      .order('created_at');
  Future<void> like(String id, bool liked) async {
    if (liked) {
      await client.from('friend_likes').insert({
        'workout_id': id,
        'user_id': userId,
      });
    } else {
      await client
          .from('friend_likes')
          .delete()
          .eq('workout_id', id)
          .eq('user_id', userId);
    }
  }

  Future<void> comment(String id, String body) async {
    final text = body.trim();
    if (text.isEmpty || text.runes.length > 140) {
      throw ArgumentError('1–140 characters required');
    }
    await client.from('friend_comments').insert({
      'workout_id': id,
      'user_id': userId,
      'body': text,
    });
  }

  Future<void> deleteComment(String id) async {
    await client
        .from('friend_comments')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }
}
