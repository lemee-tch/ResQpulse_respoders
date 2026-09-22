import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// ── ResQPulse Responder App — API layer ───────────────────────────
///
/// Rebuilt for consistency: every network call in this file goes
/// through the same three private helpers (`_get`, `_send`,
/// `_multipart`), so there is exactly one place that knows how to
/// build headers, apply a timeout, decode JSON, and turn a
/// non-2xx response into a friendly `ApiResponse.error`. Individual
/// methods below are now just "what endpoint, what body" — the
/// plumbing around them no longer needs to be duplicated (and kept
/// in sync) 20 times over.
///
/// Public method signatures are unchanged from the previous version,
/// so every screen that already calls `ApiService.xxx(...)` keeps
/// working without edits.
class ApiService {
  ApiService._();

  // ── Config ──────────────────────────────────────────────────────
  static const String baseUrl = 'https://resqpulse.com/api';

  static const Duration _shortTimeout = Duration(seconds: 10);
  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const Duration _uploadTimeout = Duration(seconds: 20);

  static const String _tokenKey = 'responder_auth_token';
  static const String _responderKey = 'responder';

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ── Session storage ────────────────────────────────────────────

  static Future<String?> getResponderToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> saveResponderToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> saveResponder(Map<String, dynamic> responder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_responderKey, jsonEncode(responder));
  }

  static Future<Map<String, dynamic>?> getResponder() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_responderKey);
    if (str == null) return null;
    try {
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearResponderSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_responderKey);
  }

  static Future<bool> isResponderLoggedIn() async {
    final token = await getResponderToken();
    return token != null && token.isNotEmpty;
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getResponderToken();
    return {
      ..._jsonHeaders,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Core request helpers ───────────────────────────────────────
  //
  // Every endpoint below funnels through one of these three. They
  // own: header selection, timeout, JSON decoding, and mapping a
  // non-2xx response to a friendly ApiResponse.error with whatever
  // detail the backend sent (message / validation errors / raw body
  // fallback). Nothing else in this file should call `http.` or
  // `jsonDecode` directly.

  static Future<ApiResponse> _get(
    String path, {
    bool authed = true,
    Duration timeout = _defaultTimeout,
  }) async {
    return _send('GET', path, authed: authed, timeout: timeout);
  }

  static Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authed = true,
    Duration timeout = _defaultTimeout,
    int successStatus = 200,
  }) async {
    try {
      final headers = authed ? await _authHeaders() : _jsonHeaders;
      final uri = Uri.parse('$baseUrl$path');
      final encodedBody = body != null ? jsonEncode(body) : null;

      final http.Response response;
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(timeout);
          break;
        case 'POST':
          response = await http
              .post(uri, headers: headers, body: encodedBody)
              .timeout(timeout);
          break;
        case 'PATCH':
          response = await http
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(timeout);
          break;
        default:
          throw UnsupportedError('Unsupported HTTP method: $method');
      }

      return _handleResponse(response, successStatus: successStatus);
    } catch (e) {
      return ApiResponse.error(_describeError(e));
    }
  }

  /// Multipart POST — used only by [resolveIncident], where a photo
  /// (when present) has to ride alongside plain fields.
  static Future<ApiResponse> _multipart(
    String path, {
    required Map<String, String> fields,
    File? file,
    String fileField = 'photo',
    Duration timeout = _uploadTimeout,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = http.MultipartRequest('POST', uri);

      final token = await getResponderToken();
      request.headers['Accept'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';

      fields.forEach((key, value) {
        if (value.isNotEmpty) request.fields[key] = value;
      });

      if (file != null) {
        request.files.add(
          await http.MultipartFile.fromPath(fileField, file.path),
        );
      }

      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } catch (e) {
      return ApiResponse.error(_describeError(e));
    }
  }

  /// Turns any `http.Response` into an `ApiResponse`, consistently.
  /// - 2xx (matching [successStatus] when one is given, else any 2xx)
  ///   → success with the decoded body.
  /// - Otherwise → error, preferring `message`, falling back to the
  ///   first `errors` entry (Laravel validation shape), falling back
  ///   to a truncated raw body so nothing is ever silently swallowed.
  static ApiResponse _handleResponse(
    http.Response response, {
    int? successStatus,
  }) {
    dynamic decoded;
    try {
      decoded = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    } catch (_) {
      decoded = null;
    }

    final isSuccess = successStatus != null
        ? response.statusCode == successStatus
        : response.statusCode >= 200 && response.statusCode < 300;

    if (isSuccess) {
      return ApiResponse.success(decoded);
    }

    return ApiResponse.error(
      _extractErrorMessage(decoded, response),
      data: decoded,
      statusCode: response.statusCode,
    );
  }

  static String _extractErrorMessage(dynamic decoded, http.Response response) {
    if (decoded is Map) {
      if (decoded['message'] is String &&
          (decoded['message'] as String).isNotEmpty) {
        return decoded['message'] as String;
      }
      final errors = decoded['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final firstError = errors.values.first;
        final msg = firstError is List && firstError.isNotEmpty
            ? firstError.first
            : firstError;
        if (msg != null) return msg.toString();
      }
    }
    final raw = response.body;
    final truncated = raw.length > 150 ? '${raw.substring(0, 150)}...' : raw;
    return 'Request failed (${response.statusCode})${truncated.isNotEmpty ? ': $truncated' : '.'}';
  }

  static String _describeError(dynamic e) {
    if (e is TimeoutException) {
      return 'Connection timed out. Please try again.';
    }
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'Cannot connect to server. Check your internet connection.';
    }
    return 'Something went wrong. Please try again.';
  }

  // ── RESPONDER AUTH ─────────────────────────────────────────────
  // No self-service registration, email verification, or password
  // reset — responder accounts are one shared login per agency,
  // pre-created by ResponderSeeder and managed from the admin
  // panel's "Responder Accounts" page. login/me/logout are the only
  // responder-auth endpoints the backend exposes.

  static Future<ApiResponse> responderLogin({
    required String email,
    required String password,
  }) async {
    final result = await _send(
      'POST',
      '/responder/login',
      body: {'email': email, 'password': password},
      authed: false,
      timeout: _shortTimeout + const Duration(seconds: 5),
    );

    if (result.success && result.data is Map) {
      final data = result.data as Map<String, dynamic>;
      await saveResponderToken(data['token']);
      await saveResponder(data['responder']);
    }
    return result;
  }

  static Future<ApiResponse> getResponderMe() async {
    final result = await _get('/responder/me', timeout: _shortTimeout);

    if (result.success && result.data is Map<String, dynamic>) {
      await saveResponder(result.data as Map<String, dynamic>);
    } else if (!result.success) {
      // Any failure here means the stored token is no longer valid —
      // clear it so the app falls back to the login screen cleanly.
      await clearResponderSession();
      return ApiResponse.error('Session expired. Please log in again.');
    }
    return result;
  }

  static Future<ApiResponse> responderLogout() async {
    try {
      final headers = await _authHeaders();
      await http
          .post(Uri.parse('$baseUrl/responder/logout'), headers: headers)
          .timeout(_shortTimeout);
    } catch (_) {
      // Logout is best-effort — the session is cleared locally either way.
    }
    await clearResponderSession();
    return ApiResponse.success({});
  }

  // ── FCM TOKEN ──────────────────────────────────────────────────
  // Reuses the same /api/fcm-token endpoint the citizen app hits —
  // it's not citizen-specific, it just updates whichever
  // authenticated model (Citizen or Responder) owns the Sanctum
  // token making the request.

  static Future<ApiResponse> updateFcmToken(String fcmToken) {
    return _send(
      'POST',
      '/fcm-token',
      body: {'fcm_token': fcmToken},
      timeout: _shortTimeout,
    );
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

  // ── ASSIGNED INCIDENTS ─────────────────────────────────────────

  /// Incidents relevant to this responder's agency — same routing
  /// rules used server-side to decide who gets pushed a notification.
  static Future<ApiResponse> getAssignedIncidents() {
    return _get('/responder/incidents');
  }

  /// Resolved incidents this responder personally responded to —
  /// powers the Report History screen. Separate from
  /// getAssignedIncidents() (which only ever returns open incidents).
  static Future<ApiResponse> getIncidentHistory() {
    return _get('/responder/incidents/history');
  }

  /// Joins this responder onto the incident — NOT an exclusive claim.
  /// Backup support means any number of responders (same or different
  /// agencies) can accept the same incident; the backend just adds the
  /// caller to the incident_responder pivot if they aren't on it
  /// already. The only real failure case is a 409 when the incident
  /// has already been marked resolved — that response still includes
  /// the up-to-date `incident` (in `.data`) so the UI can refresh its
  /// local copy instead of just showing a generic error.
  static Future<ApiResponse> acceptIncident(int incidentId) {
    return _send('POST', '/responder/incidents/$incidentId/accept');
  }

  /// Purely informational today — there's no per-responder "declined"
  /// record kept server-side (declining just means "not me", the
  /// incident stays open for the rest of the agency).
  static Future<ApiResponse> declineIncident(int incidentId) {
    return _send(
      'POST',
      '/responder/incidents/$incidentId/decline',
      timeout: _shortTimeout,
    );
  }

  /// Marks an incident resolved from the field — see
  /// IncidentResolutionScreen. Multipart because the photo is optional
  /// but, when present, is a file a plain JSON POST can't carry. A 409
  /// means someone else already resolved it moments earlier; the
  /// response still carries the current `incident` so the caller can
  /// update its local copy instead of just showing a generic error.
  static Future<ApiResponse> resolveIncident(
    int incidentId, {
    String? notes,
    File? photo,
  }) {
    return _multipart(
      '/responder/incidents/$incidentId/resolve',
      fields: {if (notes != null) 'notes': notes},
      file: photo,
    );
  }

  // ── ALERTS ─────────────────────────────────────────────────────
  // Same /api/alerts endpoint the citizen app hits — not guard
  // specific, so it works fine for an authenticated Responder token
  // too. Used by the "Disaster Alerts" tile on the responder home
  // screen.
  static Future<ApiResponse> getAlerts() {
    return _get('/alerts');
  }

  // ── EVACUATION CENTERS ─────────────────────────────────────────
  // GET is the same public /api/evacuation-centers endpoint the
  // citizen app hits — not guard specific, works with a responder
  // token or none at all.
  //
  // Create/status-update/evacuee-logging are MSWD-only; the backend
  // re-enforces this (403 for anyone else) regardless of what the
  // app shows or hides.
  static Future<ApiResponse> getEvacuationCenters() {
    return _get('/evacuation-centers', authed: false);
  }

  static Future<ApiResponse> createEvacuationCenter({
    required String name,
    required String barangay,
    required double latitude,
    required double longitude,
    required String status,
  }) {
    return _send(
      'POST',
      '/evacuation-centers',
      body: {
        'name': name,
        'barangay': barangay,
        'latitude': latitude,
        'longitude': longitude,
        'status': status,
      },
      successStatus: 201,
    );
  }

  /// Changes an existing center's status — MSWD-only, same as create.
  /// Kept separate from creation (which always starts a center at
  /// 'open') so an MSWD responder marks it full/closed later from the
  /// centers list instead of picking a status up front.
  static Future<ApiResponse> updateEvacuationCenterStatus(
    int centerId,
    String status,
  ) {
    return _send(
      'PATCH',
      '/evacuation-centers/$centerId/status',
      body: {'status': status},
    );
  }

  /// MSWD-only, same gate as above — logs one evacuee (one row per
  /// person, not per household) at a specific center. Arrival only;
  /// there's no matching "check out" call, by design.
  static Future<ApiResponse> logEvacuee({
    required int centerId,
    required String firstName,
    String? middleName,
    required String lastName,
    String? suffix,
    String? contactNumber,
    required String barangay,
    required String gender,
    required int age,
  }) {
    return _send(
      'POST',
      '/evacuation-centers/$centerId/evacuees',
      body: {
        'first_name': firstName,
        'middle_name': middleName,
        'last_name': lastName,
        'suffix': suffix,
        'contact_number': contactNumber,
        'barangay': barangay,
        'gender': gender,
        'age': age,
      },
      successStatus: 201,
    );
  }

  /// All evacuees across every center, newest first — powers the
  /// Resident Logs screen. Same MSWD-only gate as logEvacuee(); the
  /// backend re-checks regardless of what the app shows/hides.
  static Future<ApiResponse> getEvacueeLogs() {
    return _get('/evacuation-centers/evacuees');
  }
}

// ── API Response wrapper ──────────────────────────────────────────
//
// Unchanged shape from the previous version (`.success`, `.data`,
// `.error`) so every existing call site keeps compiling. `statusCode`
// is new and optional — screens that want to special-case a 409 (an
// incident someone else already resolved/claimed) can now check it
// directly instead of string-matching the error message.
class ApiResponse {
  final bool success;
  final dynamic data;
  final String? error;
  final int? statusCode;

  ApiResponse._({
    required this.success,
    this.data,
    this.error,
    this.statusCode,
  });

  factory ApiResponse.success(dynamic data) =>
      ApiResponse._(success: true, data: data, statusCode: 200);

  factory ApiResponse.error(String message, {dynamic data, int? statusCode}) =>
      ApiResponse._(
        success: false,
        error: message,
        data: data,
        statusCode: statusCode,
      );
}
