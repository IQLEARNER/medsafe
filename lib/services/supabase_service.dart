import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static final instance = SupabaseService._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
  SupabaseClient get client => Supabase.instance.client;
  User? get currentUser => isConfigured ? client.auth.currentUser : null;

  Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }

  Future<AuthResponse> signInOrCreate({
    required String email,
    required String password,
    required String displayName,
    required String role,
  }) async {
    final existing = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (existing.user != null) {
      await _ensureProfile(displayName: displayName, role: role);
      return existing;
    }

    final created = await client.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': displayName, 'role': role},
    );
    if (created.user != null && created.session != null) {
      await _ensureProfile(displayName: displayName, role: role);
    }
    return created;
  }

  Future<void> _ensureProfile({required String displayName, required String role}) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('profiles').upsert({
      'id': user.id,
      'display_name': displayName,
      'role': role.toLowerCase(),
    });
  }

  Future<void> signOut() async {
    if (isConfigured) await client.auth.signOut();
  }
}
