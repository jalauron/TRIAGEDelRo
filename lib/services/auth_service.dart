import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  static final supabase.SupabaseClient _db = supabase.Supabase.instance.client;

  // ═══════════════════════════════════════════════════════════
  // REGISTER — RESIDENT
  // Primary: security-definer RPC (bypasses RLS).
  // Fallback: direct upserts (works when email-confirm is OFF
  //           because signUp returns an active session).
  // ═══════════════════════════════════════════════════════════
  static Future<void> registerResident({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String username,
    required String phoneNumber,
    required String address,
  }) async {
    supabase.User? user;
    try {
      final res = await _db.auth.signUp(email: email, password: password);
      user = res.user;
      if (user == null) {
        throw AuthException(
          'SIGN-UP RETURNED NO USER — TURN OFF "CONFIRM EMAIL" IN SUPABASE',
        );
      }

      // Try RPC first (bypasses RLS)
      bool rpcOk = false;
      try {
        await _db.rpc(
          'register_resident',
          params: {
            'p_id': user.id,
            'p_role': 'community_member',
            'p_first_name': firstName,
            'p_last_name': lastName,
            'p_username': username,
            'p_phone': phoneNumber,
            'p_address': address,
          },
        );
        rpcOk = true;
        _log('registerResident', 'RPC succeeded');
      } catch (rpcErr) {
        _log('registerResident', 'RPC failed, trying direct insert: $rpcErr');
      }

      // Fallback: direct upserts (session is active, auth.uid() works)
      if (!rpcOk) {
        await _db.from('users').upsert({
          'id': user.id,
          'role': 'community_member',
        });
        await _db.from('residents').upsert({
          'id': user.id,
          'first_name': firstName,
          'last_name': lastName,
          'username': username,
          'phone_number': phoneNumber,
          'address': address,
        });
        _log('registerResident', 'Direct upsert succeeded');
      }

      await _db.auth.signOut();
    } on supabase.AuthException catch (e) {
      try {
        await _db.auth.signOut();
      } catch (_) {}
      throw AuthException(_friendlyAuthError(e.message));
    } on AuthException {
      try {
        await _db.auth.signOut();
      } catch (_) {}
      rethrow;
    } catch (e) {
      try {
        await _db.auth.signOut();
      } catch (_) {}
      throw AuthException(_friendlyError(e.toString()));
    }
  }

  // ═══════════════════════════════════════════════════════════
  // REGISTER — OFFICIAL
  // ═══════════════════════════════════════════════════════════
  static Future<void> registerOfficial({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String username,
    required String position,
    String role = 'barangay_official',
  }) async {
    supabase.User? user;
    try {
      final res = await _db.auth.signUp(email: email, password: password);
      user = res.user;
      if (user == null) {
        throw AuthException(
          'SIGN-UP RETURNED NO USER — TURN OFF "CONFIRM EMAIL" IN SUPABASE',
        );
      }

      bool rpcOk = false;
      try {
        await _db.rpc(
          'register_official',
          params: {
            'p_id': user.id,
            'p_role': role,
            'p_first_name': firstName,
            'p_last_name': lastName,
            'p_username': username,
            'p_position': position,
          },
        );
        rpcOk = true;
        _log('registerOfficial', 'RPC succeeded');
      } catch (rpcErr) {
        _log('registerOfficial', 'RPC failed, trying direct insert: $rpcErr');
      }

      if (!rpcOk) {
        await _db.from('users').upsert({'id': user.id, 'role': role});
        await _db.from('officials').upsert({
          'id': user.id,
          'first_name': firstName,
          'last_name': lastName,
          'username': username,
          'position': position,
        });
        _log('registerOfficial', 'Direct upsert succeeded');
      }

      await _db.auth.signOut();
    } on supabase.AuthException catch (e) {
      try {
        await _db.auth.signOut();
      } catch (_) {}
      throw AuthException(_friendlyAuthError(e.message));
    } on AuthException {
      try {
        await _db.auth.signOut();
      } catch (_) {}
      rethrow;
    } catch (e) {
      try {
        await _db.auth.signOut();
      } catch (_) {}
      throw AuthException(_friendlyError(e.toString()));
    }
  }

  // ═══════════════════════════════════════════════════════════
  // LOGIN — returns role string, throws AuthException on failure
  // ═══════════════════════════════════════════════════════════
  static Future<String> login(String email, String password) async {
    try {
      final res = await _db.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.session == null) {
        throw AuthException('LOGIN FAILED — PLEASE TRY AGAIN');
      }

      final profile = await refreshUserData();
      if (profile == null) {
        await _db.auth.signOut();
        throw AuthException(
          'ACCOUNT DATA NOT FOUND.\n'
          'Your credentials are valid but your profile is missing.\n'
          'Please contact the barangay admin.',
        );
      }
      return (profile['role'] as String?) ?? 'community_member';
    } on supabase.AuthException catch (e) {
      _log('login', e.message);
      throw AuthException(_friendlyAuthError(e.message));
    } on AuthException {
      rethrow;
    } catch (e) {
      _log('login', e.toString());
      throw AuthException(_friendlyError(e.toString()));
    }
  }

  static Future<void> logout() async {
    try {
      await _db.auth.signOut();
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════
  // REFRESH PROFILE — reads DB, patches auth metadata cache.
  // Returns null if user has no DB record.
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>?> refreshUserData() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;

    try {
      final userRow = await _db
          .from('users')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (userRow == null) return null;

      final r = (userRow['role'] as String?) ?? 'community_member';
      Map<String, dynamic> profile;

      if (r == 'barangay_official' || r == 'bdrrmc_member') {
        final row = await _db
            .from('officials')
            .select('first_name, last_name, username, position')
            .eq('id', user.id)
            .maybeSingle();
        if (row == null) return null;
        profile = {
          'role': r,
          'first_name': row['first_name'] ?? '',
          'last_name': row['last_name'] ?? '',
          'username': row['username'] ?? '',
          'position': row['position'] ?? '',
        };
      } else {
        final row = await _db
            .from('residents')
            .select('first_name, last_name, username, phone_number, address')
            .eq('id', user.id)
            .maybeSingle();
        if (row == null) return null;
        profile = {
          'role': r,
          'first_name': row['first_name'] ?? '',
          'last_name': row['last_name'] ?? '',
          'username': row['username'] ?? '',
          'phone_number': row['phone_number'] ?? '',
          'address': row['address'] ?? '',
        };
      }

      await _db.auth.updateUser(supabase.UserAttributes(data: profile));
      return profile;
    } catch (e) {
      _log('refreshUserData', e.toString());
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UPDATE PROFILE
  // ═══════════════════════════════════════════════════════════
  static Future<void> updateResidentProfile({
    required String firstName,
    required String lastName,
    required String username,
    required String phoneNumber,
    required String address,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw AuthException('Not authenticated.');
    await _db
        .from('residents')
        .update({
          'first_name': firstName,
          'last_name': lastName,
          'username': username,
          'phone_number': phoneNumber,
          'address': address,
        })
        .eq('id', uid);
    await refreshUserData();
  }

  static Future<void> updateOfficialProfile({
    required String firstName,
    required String lastName,
    required String username,
    required String position,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw AuthException('Not authenticated.');
    await _db
        .from('officials')
        .update({
          'first_name': firstName,
          'last_name': lastName,
          'username': username,
          'position': position,
        })
        .eq('id', uid);
    await refreshUserData();
  }

  // ═══════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════
  static Map<String, dynamic>? getUserData() =>
      _db.auth.currentUser?.userMetadata;

  static String get username => getUserData()?['username'] ?? '';
  static String get firstName => getUserData()?['first_name'] ?? '';
  static String get lastName => getUserData()?['last_name'] ?? '';
  static String get fullName => '$firstName $lastName'.trim();
  static String get role => getUserData()?['role'] ?? 'community_member';
  static String get position => getUserData()?['position'] ?? '';
  static String get phoneNumber => getUserData()?['phone_number'] ?? '';
  static String get address => getUserData()?['address'] ?? '';
  static String? get userId => _db.auth.currentUser?.id;

  static bool get isOfficial =>
      role == 'barangay_official' || role == 'bdrrmc_member';

  static Stream<supabase.AuthState> get onAuthChange =>
      _db.auth.onAuthStateChange;

  // ═══════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════
  static String _friendlyAuthError(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('invalid login') ||
        r.contains('invalid credentials') ||
        r.contains('wrong password') ||
        r.contains('invalid email or password')) {
      return 'INCORRECT EMAIL OR PASSWORD';
    }
    if (r.contains('already registered') ||
        r.contains('already exists') ||
        r.contains('duplicate')) {
      return 'EMAIL ALREADY REGISTERED — LOG IN INSTEAD';
    }
    if (r.contains('password')) return 'PASSWORD TOO WEAK — MIN 6 CHARACTERS';
    if (r.contains('invalid email') || r.contains('unable to validate')) {
      return 'INVALID EMAIL ADDRESS';
    }
    if (r.contains('network') || r.contains('connection')) {
      return 'NETWORK ERROR — CHECK YOUR CONNECTION';
    }
    return raw.toUpperCase();
  }

  static String _friendlyError(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('could not find the function') ||
        r.contains('register_resident') ||
        r.contains('register_official')) {
      return 'DB FUNCTION NOT FOUND — RUN supabase_setup.sql IN YOUR SUPABASE SQL EDITOR';
    }
    if (r.contains('rls') || r.contains('row-level') || r.contains('policy')) {
      return 'DATABASE PERMISSION ERROR — RUN supabase_setup.sql AGAIN';
    }
    if (r.contains('network') || r.contains('connection')) {
      return 'NETWORK ERROR — CHECK YOUR CONNECTION';
    }
    return raw.toUpperCase();
  }

  static void _log(String tag, String msg) {
    assert(() {
      // ignore: avoid_print
      print('[AuthService][$tag] $msg');
      return true;
    }());
  }
}
