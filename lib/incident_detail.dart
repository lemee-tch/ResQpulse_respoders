import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import 'route_map.dart';
import 'navigation_screen.dart';

const Color _navy = Color(0xFF0D1B4C);

/// Incident Details screen for the responder app — shown when a responder
/// taps an incident card on the home screen's "Assigned Incidents" list.
///
/// [incident] is the raw JSON map as returned by
/// ApiService.getAssignedIncidents() (see responder_home.dart / _IncidentCard
/// for the same field names: emergency_type, location, latitude, longitude,
/// description, created_at, citizen, status, priority, ai_detected_type).
class IncidentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> incident;

  const IncidentDetailScreen({super.key, required this.incident});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  bool _isResponding = false;

  // Mutable local copy so a successful accept/decline can update the
  // status + responders list in place without needing the caller
  // (responder_home.dart's list) to refetch just to reflect this screen.
  late Map<String, dynamic> _incident;

  // The signed-in responder's own id — needed to tell "someone else has
  // already accepted this" (show BACKUP MISSION) apart from "I'm already
  // on this incident myself" (show ALREADY RESPONDING, no network call).
  int? _myResponderId;

  @override
  void initState() {
    super.initState();
    _incident = Map<String, dynamic>.from(widget.incident);
    ApiService.getResponder().then((responder) {
      if (!mounted || responder == null) return;
      setState(() => _myResponderId = responder['id'] as int?);
    });
  }

  List<dynamic> get _responders =>
      (_incident['responders'] as List<dynamic>?) ?? const [];

  bool get _iAmAlreadyResponding =>
      _myResponderId != null &&
      _responders.any((r) => r is Map && r['id'] == _myResponderId);

  /// Someone (anyone) has already accepted — tapping now joins as backup
  /// support rather than being the first responder on scene.
  bool get _isBackupJoin =>
      !_iAmAlreadyResponding &&
      (_incident['status'] == 'responding' || _responders.isNotEmpty);

  bool get _isResolved => _incident['status'] == 'resolved';

  String get _acceptButtonLabel {
    if (_isResolved) return 'RESOLVED';
    if (_iAmAlreadyResponding) return 'CONTINUE TO SCENE';
    if (_isBackupJoin) return 'BACKUP MISSION';
    return 'ACCEPT MISSION';
  }

  static const Map<String, IconData> _typeIcons = {
    'Fire': Icons.local_fire_department_outlined,
    'Flood': Icons.water_outlined,
    'Earthquake': Icons.landscape_outlined,
    'Accident': Icons.car_crash_outlined,
    'Medical Emergency': Icons.medical_services_outlined,
    'Landslide': Icons.terrain_outlined,
    'SOS Emergency': Icons.emergency_outlined,
  };

  IconData get _icon =>
      _typeIcons[_incident['emergency_type']] ?? Icons.warning_amber_rounded;

  /// "SOS Alert — Accident", etc. once the citizen picked a hazard type
  /// on the SOS screen — see Incident::getDisplayTypeAttribute() on the
  /// backend. Falls back to the raw emergency_type for older rows/API
  /// responses that don't carry display_type. Only used for the label
  /// shown — [_icon] above stays keyed on the raw emergency_type.
  String get _displayType =>
      _incident['display_type']?.toString() ??
      _incident['emergency_type']?.toString() ??
      'Unknown';

  double? get _lat => double.tryParse('${_incident['latitude']}');
  double? get _lng => double.tryParse('${_incident['longitude']}');

  String get _reporterName =>
      _incident['citizen']?['full_name']?.toString() ?? 'Unknown';

  String? get _reporterMobile => _incident['citizen']?['mobile']?.toString();

  String get _formattedDate {
    final raw = _incident['created_at']?.toString();
    final date = DateTime.tryParse(raw ?? '');
    if (date == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[date.month - 1];
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period - $month ${date.day}, ${date.year}';
  }

  Future<void> _callReporter() async {
    final mobile = _reporterMobile;
    if (mobile == null || mobile.isEmpty) return;
    final uri = Uri.parse('tel:$mobile');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Accepts (or, if someone's already on it, joins as backup on) this
  /// incident via POST /api/responder/incidents/{id}/accept. If I'm
  /// already on the incident myself, there's nothing to call — just go
  /// straight to navigation.
  Future<void> _handleAccept() async {
    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This incident has no location to navigate to.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_iAmAlreadyResponding) {
      _goToNavigation();
      return;
    }

    setState(() => _isResponding = true);

    final result = await ApiService.acceptIncident(
      _incident['id'] is int
          ? _incident['id'] as int
          : int.tryParse('${_incident['id']}') ?? 0,
    );

    if (!mounted) return;
    setState(() => _isResponding = false);

    if (!result.success) {
      // A 409 here means the incident was resolved before this tap
      // landed — refresh the local copy (if the backend sent one back)
      // so the button/labels reflect reality instead of retrying blind.
      if (result.data is Map && result.data['incident'] != null) {
        setState(
          () => _incident = Map<String, dynamic>.from(
            result.data['incident'] as Map,
          ),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Could not accept this mission.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (result.data is Map && result.data['incident'] != null) {
      setState(
        () => _incident = Map<String, dynamic>.from(
          result.data['incident'] as Map,
        ),
      );
    }

    _goToNavigation();
  }

  void _goToNavigation() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => NavigationScreen(
          destinationLat: _lat!,
          destinationLng: _lng!,
          destinationLabel: _incident['location']?.toString() ?? 'Incident',
          incidentId: _incident['id'] is int
              ? _incident['id'] as int
              : int.tryParse('${_incident['id']}'),
        ),
      ),
    );
  }

  Future<void> _handleDecline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Decline this mission?'),
        content: const Text(
          'This incident will be offered to other available responders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Fire-and-forget-ish: decline has no real server effect for this
    // responder today (see ApiService.declineIncident), so the screen
    // closes regardless of whether the request itself succeeds.
    ApiService.declineIncident(
      _incident['id'] is int
          ? _incident['id'] as int
          : int.tryParse('${_incident['id']}') ?? 0,
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final type = _displayType;
    final location = _incident['location']?.toString() ?? '—';
    final description = _incident['description']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Color(0xFF1A1A2E),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Incident Details',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.ios_share,
              color: Color(0xFF1A1A2E),
              size: 20,
            ),
            onPressed: () {
              // Optional: wire up share_plus if you want a real share sheet.
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Route map: shows ONLY this incident's location, plus
              // a route line from the responder's current position ──
              if (_lat != null && _lng != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: IncidentRouteMap(
                    incidentLat: _lat!,
                    incidentLng: _lng!,
                    incidentLabel: location,
                    height: 220,
                  ),
                )
              else
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  height: 180,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9ECF3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.map_outlined,
                      size: 40,
                      color: Colors.grey[400],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type badge
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD32F2F),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_icon, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          type,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: 'Location',
                      value: location,
                    ),
                    _DetailRow(
                      icon: Icons.access_time,
                      label: 'Reported at',
                      value: _formattedDate,
                    ),
                    _DetailRow(
                      icon: Icons.person_outline,
                      label: 'Reported By',
                      value: _reporterName,
                    ),
                    if (_reporterMobile != null && _reporterMobile!.isNotEmpty)
                      GestureDetector(
                        onTap: _callReporter,
                        child: _DetailRow(
                          icon: Icons.call_outlined,
                          label: 'Contact',
                          value: _reporterMobile!,
                          valueColor: _navy,
                        ),
                      ),
                    if (description.isNotEmpty)
                      _DetailRow(
                        icon: Icons.notes_outlined,
                        label: 'Description',
                        value: description,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_isResponding || _isResolved)
                            ? null
                            : _handleAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isBackupJoin
                              ? const Color(0xFFEF6C00)
                              : const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[400],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: _isResponding
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                _acceptButtonLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: (_isResponding || _isResolved)
                            ? null
                            : _handleDecline,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.grey[300]!,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Text(
                          'DECLINE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? const Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
