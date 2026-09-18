import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class ApiService {
  // ── Point this at your Laravel ResQPulse backend ──────────────────
  static const String baseUrl = 'https://resqpulse.com/api';

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
  // No self-service registration, email verification, or password
  // reset — responder accounts are one shared login per agency,
  // pre-created by ResponderSeeder and managed from the admin panel's
  // "Responder Accounts" page (including password resets). login/me/
  // logout are the only responder-auth endpoints the backend exposes;
  // see api.php and Api\ResponderAuthController.

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

  /// Joins this responder onto the incident — NOT an exclusive claim.
  /// Backup support means any number of responders (same or different
  /// agencies) can accept the same incident; the backend just adds the
  /// caller to the incident_responder pivot if they aren't on it
  /// already (see IncidentController::accept()). The only real failure
  /// case is a 409 when the incident has already been marked resolved —
  /// that response still includes the up-to-date `incident` so the UI
  /// can refresh its local copy instead of just showing a generic error.
  static Future<ApiResponse> acceptIncident(int incidentId) async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/responder/incidents/$incidentId/accept'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResponse.success(data);
      }

      // 409 (already claimed) and anything else both carry a message —
      // and 409 also carries the current `incident` so the caller can
      // refresh its local copy (e.g. to show who did accept it).
      return ApiResponse.error(
        data['message'] ?? 'Could not accept this mission.',
        data: data,
      );
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  /// Purely informational today — there's no per-responder "declined"
  /// record kept server-side (declining just means "not me", the
  /// incident stays open for the rest of the agency), so this never
  /// blocks the caller's local UI update even if the request fails.
  static Future<ApiResponse> declineIncident(int incidentId) async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/responder/incidents/$incidentId/decline'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return ApiResponse.success(jsonDecode(response.body));
      }
      return ApiResponse.error('Failed to decline.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
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
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/responder/incidents/$incidentId/resolve');
      final request = http.MultipartRequest('POST', uri);

      final token = await getResponderToken();
      request.headers['Accept'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';

      if (notes != null && notes.isNotEmpty) {
        request.fields['notes'] = notes;
      }
      if (photo != null) {
        request.files.add(
          await http.MultipartFile.fromPath('photo', photo.path),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 20),
      );
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResponse.success(data);
      }
      return ApiResponse.error(
        data['message'] ?? 'Could not mark this incident resolved.',
        data: data,
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

  // ── EVACUATION CENTERS ───────────────────────────────────────────
  // GET is the same public /api/evacuation-centers endpoint the citizen
  // app hits (see Api\EvacuationCenterController::index) — not guard
  // specific, works fine with a responder token or none at all.
  //
  // POST is new: only MSWD responders are allowed to add a center. The
  // backend re-checks this (403 for anyone else), this is just so the
  // UI can show a clean error instead of a raw 403 body.
  static Future<ApiResponse> getEvacuationCenters() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/evacuation-centers'), headers: _baseHeaders)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResponse.success(jsonDecode(response.body));
      }
      return ApiResponse.error('Could not load evacuation centers.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  static Future<ApiResponse> createEvacuationCenter({
    required String name,
    required String barangay,
    required double latitude,
    required double longitude,
    required String status,
  }) async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/evacuation-centers'),
            headers: headers,
            body: jsonEncode({
              'name': name,
              'barangay': barangay,
              'latitude': latitude,
              'longitude': longitude,
              'status': status,
            }),
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
      return ApiResponse.error(
        data['message'] ?? 'Failed to add evacuation center.',
      );
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  /// The "action" for changing an existing center's status — MSWD-only,
  /// same as create. Separate from creation (which always starts a
  /// center at 'open') so an MSWD responder marks it full/closed later
  /// from the centers list instead of picking a status up front.
  static Future<ApiResponse> updateEvacuationCenterStatus(
    int centerId,
    String status,
  ) async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .patch(
            Uri.parse('$baseUrl/evacuation-centers/$centerId/status'),
            headers: headers,
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResponse.success(data);
      }
      return ApiResponse.error(data['message'] ?? 'Could not update status.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  /// MSWD-only, same gate as createEvacuationCenter/updateEvacuationCenterStatus
  /// above — logs one evacuee (one row per person, not per household) at
  /// a specific center. Arrival only; there's no matching "check out"
  /// call, by design (see the backend's Evacuee model doc comment).
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
  }) async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/evacuation-centers/$centerId/evacuees'),
            headers: headers,
            body: jsonEncode({
              'first_name': firstName,
              'middle_name': middleName,
              'last_name': lastName,
              'suffix': suffix,
              'contact_number': contactNumber,
              'barangay': barangay,
              'gender': gender,
              'age': age,
            }),
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
      return ApiResponse.error(data['message'] ?? 'Could not log evacuee.');
    } catch (e) {
      return ApiResponse.error(_handleError(e));
    }
  }

  /// All evacuees across every center, newest first — powers the
  /// Resident Logs quick-access screen. Same MSWD-only gate as
  /// logEvacuee(); the backend re-checks regardless of what the app
  /// shows/hides.
  static Future<ApiResponse> getEvacueeLogs() async {
    try {
      final headers = await _responderAuthHeaders();
      final response = await http
          .get(
            Uri.parse('$baseUrl/evacuation-centers/evacuees'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResponse.success(jsonDecode(response.body));
      }
      final data = jsonDecode(response.body);
      return ApiResponse.error(
        data['message'] ?? 'Could not load evacuee logs.',
      );
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
