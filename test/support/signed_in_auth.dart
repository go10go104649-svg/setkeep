import 'package:setkeep/services/account_auth_service.dart';

/// Existing UI tests enter through the authenticated app route without a live
/// Supabase server. Authentication transitions are tested separately.
class SignedInTestAuth implements AccountAuthService {
  const SignedInTestAuth();

  @override
  bool get isSignedIn => true;
  @override
  String? get email => 'test@example.com';
  @override
  Stream<void> get changes => const Stream<void>.empty();
  @override
  Future<void> signIn(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<bool> signUp(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<void> signInWithGoogle() => throw UnimplementedError();
  @override
  Future<void> signOut() => throw UnimplementedError();
  @override
  Future<void> deleteAccount() => throw UnimplementedError();
}
