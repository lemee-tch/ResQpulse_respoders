import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class ApiService {
  // ── Point this at your Laravel ResQPulse backend ──────────────────
  // Android emulator:        'http://10.0.2.2:8000/api'
  // Real device on same WiFi: 'http://192.168.1.X:8000/api'
  // Live server:              'https://yourdomain.com/api'
  static const String baseUrl = 'http://192.168.1.2:8000/api';

  static const Map<String, String> _baseHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ── Responder token helpers ────────────────────────────────────────

  static Future<String?> getResponderToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('responder_auth_token');
  }

  static Future<void> saveResponderToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('responder_auth_token', token);
  }

  static Future<void> saveResponder(Map<String, dynamic> responder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('responder', jsonEncode(responder));
  }

  static Future<Map<String, dynamic>?> getResponder() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('responder');
    if (str == null) return null;
    return jsonDecode(str);
  }

  static Future<void> clearResponderSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('responder_auth_token');
    await prefs.remove('responder');
  }

  static Future<bool> isResponderLoggedIn() async {
    final token = await getResponderToken();
    return token != null && token.isNotEmpty;
  }

  static Future<Map<String, String>> _responderAuthHeaders() async {
    final token = await getResponderToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── RESPONDER AUTH ────────────────────────────────────────────────

  static Future<ApiResponse> responderRegister({
    required String firstName,
    String? middleName,
    required String lastName,
    String? suffix,
    required String badgeNumber,
    required String agency,
    required String unitStation,
    required String mobile,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/responder/register'),
            headers: _baseHeaders,
            body: jsonEncode({
              'first_name': firstName,
              if (middleName != null && middleName.isNotEmpty)
                'middle_name': middleName,
              'last_name': lastName,
              if (suffix != null && suffix.isNotEmpty) 'suffix': suffix,
              'badge_number': badgeNumber,
              'agency': agency,
              'unit_station': unitStation,
              'mobile': mobile,
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // OTP sent — no account exists yet.
        return ApiResponse.success(data);
      }
      if (data['errors'] != null) {
        final errors = data['errors'] as Map<String, dynamic>;
        final firstError = errors.values.first;
        final msg = firstError is List ? firstError.first : firstError;
        return ApiResponse.error(msg.toString());
      }
      return ApiResponse.error(data['message'] ?? 'Registration failed.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  /// Step 2 — verifies the OTP only. No account is created and no token
  /// is returned; the person still has to confirm their details.
  static Future<ApiResponse> responderVerifyEmail({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/responder/verify-email'),
            headers: _baseHeaders,
            body: jsonEncode({'email': email, 'otp': otp}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResponse.success(data);
      }
      return ApiResponse.error(data['message'] ?? 'Invalid or expired code.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  /// Step 3 — actually creates the responder account. Returns no token;
  /// the person logs in manually afterward.
  static Future<ApiResponse> responderConfirmRegistration({
    required String email,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/responder/confirm-registration'),
            headers: _baseHeaders,
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return ApiResponse.success(data);
      }
      if (data['errors'] != null) {
        final errors = data['errors'] as Map<String, dynamic>;
        final firstError = errors.values.first;
        final msg = firstError is List ? firstError.first : firstError;
        return ApiResponse.error(msg.toString());
      }
      return ApiResponse.error(data['message'] ?? 'Could not create account.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  static Future<ApiResponse> responderResendVerificationOtp({
    required String email,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/responder/resend-verification-otp'),
            headers: _baseHeaders,
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return ApiResponse.success(data);
      return ApiResponse.error(data['message'] ?? 'Could not resend code.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  static Future<ApiResponse> responderLogin({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/responder/login'),
            headers: _baseHeaders,
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await saveResponderToken(data['token']);
        await saveResponder(data['responder']);
        return ApiResponse.success(data);
      }

      if (response.statusCode == 403 && data['needs_verification'] == true) {
        return ApiResponse.error(
          data['message'] ?? 'Please verify your email first.',
          data: {'email': data['email']},
        );
      }

      return ApiResponse.error(data['message'] ?? 'Invalid email or password.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  static Future<ApiResponse> getResponderMe() async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/responder/me'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await saveResponder(data);
        return ApiResponse.success(data);
      } else {
        await clearResponderSession();
        return ApiResponse.error('Session expired. Please log in again.');
      }
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  static Future<ApiResponse> responderLogout() async {
    try {
      final headers = await _responderAuthHeaders();
      await http
          .post(Uri.parse('$baseUrl/responder/logout'), headers: headers)
          .timeout(const Duration(seconds: 10));
      await clearResponderSession();
      return ApiResponse.success({});
    } catch (e) {
      await clearResponderSession();
      return ApiResponse.success({});
    }
  }

  // ── FCM TOKEN ────────────────────────────────────────────────────
  // Reuses the same /api/fcm-token endpoint the citizen app hits — it's
  // not citizen-specific, it just updates whichever authenticated model
  // (Citizen or Responder) owns the Sanctum token making the request.

  static Future<ApiResponse> updateFcmToken(String fcmToken) async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/fcm-token'),
            headers: headers,
            body: jsonEncode({'fcm_token': fcmToken}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return ApiResponse.success(jsonDecode(response.body));
      }
      return ApiResponse.error('Failed to register push token.');
    } catch (e) {
      // Non-critical — a failed token registration shouldn't disrupt the
      // responder's session. Silently ignored by the caller.
      return ApiResponse.error(_handleError(e));
    }
  }

  /// Fetches the device's current FCM token and registers it with the
  /// backend in one step. Call this right after login and once on app
  /// startup (in case the token rotated since the last session). Errors
  /// are swallowed on purpose — a push-registration hiccup should never
  /// block the responder from using the app.
  static Future<void> registerPushToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await updateFcmToken(fcmToken);
      }
    } catch (_) {
      // Ignored — see doc comment above.
    }
  }

  // ── ASSIGNED INCIDENTS ───────────────────────────────────────────

  /// Incidents relevant to this responder's agency — same routing rules
  /// used server-side to decide who gets pushed a notification.
  static Future<ApiResponse> getAssignedIncidents() async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/responder/incidents'), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return ApiResponse.success(data);
      }

      // Surface the real status + body instead of a generic message —
      // makes 401/403/404/500 immediately distinguishable in the UI.
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['message'] != null) {
          detail = decoded['message'].toString();
        }
      } catch (_) {
        // response.body wasn't JSON (e.g. a raw HTML error page) — just
        // show it truncated as-is.
        detail = detail.length > 150
            ? '${detail.substring(0, 150)}...'
            : detail;
      }
      return ApiResponse.error(
        'Failed to load incidents (${response.statusCode}): $detail',
      );
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  // ── ALERTS ────────────────────────────────────────────────────────
  // Same /api/alerts endpoint the citizen app hits — it isn't guard
  // specific, so it works fine for an authenticated Responder token too.
  // Used by the "Disaster Alerts" tile on the responder home screen.
  static Future<ApiResponse> getAlerts() async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/alerts'), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResponse.success(jsonDecode(response.body));
      }
      return ApiResponse.error('Could not load alerts.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  // ── Error handler ─────────────────────────────────────────────────

  static String _handleError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'Cannot connect to server. Check your internet or server URL.';
    }
    if (msg.contains('TimeoutException')) {
      return 'Connection timed out. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}

// ── API Response wrapper ────────────────────────────────────────────

class ApiResponse {
  final bool success;
  final dynamic data;
  final String? error;

  ApiResponse._({required this.success, this.data, this.error});

  factory ApiResponse.success(dynamic data) =>
      ApiResponse._(success: true, data: data);

  factory ApiResponse.error(String message, {dynamic data}) =>
      ApiResponse._(success: false, error: message, data: data);
}
