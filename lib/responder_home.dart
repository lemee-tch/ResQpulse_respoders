import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'responder_login.dart';
import 'profile.dart';
import 'incident_locations.dart';
import 'safety_tips.dart';
import 'route_map.dart';
import 'navigation_screen.dart';
import 'add_evacuation.dart';
import 'evacuation_centers.dart';

// Same gradient as the citizen app's home header — kept identical so both
// apps in the ResQPulse family read as one product.
const Color _gradientTop = Color(0xFF00308F);
const Color _gradientBottom = Color(0xFF1A5DC8);

const Color _critRedTop = Color(0xFFE53935);
const Color _critRedBottom = Color(0xFFC62828);

class ResponderHomeScreen extends StatefulWidget {
  const ResponderHomeScreen({super.key});

  @override
  State<ResponderHomeScreen> createState() => _ResponderHomeScreenState();
}

class _ResponderHomeScreenState extends State<ResponderHomeScreen> {
  Map<String, dynamic>? _responder;
  bool _isLoading = true;

  List<dynamic> _incidents = [];
  bool _incidentsLoading = true;
  String? _incidentsError;

  @override
  void initState() {
    super.initState();
    _loadResponder();
    _loadIncidents();
    // Re-register in case the FCM token rotated since the last session
    // (this can happen after app reinstalls or Firebase-side refreshes).
    ApiService.registerPushToken();
  }

  Future<void> _loadResponder() async {
    final cached = await ApiService.getResponder();
    if (mounted && cached != null) {
      setState(() {
        _responder = cached;
        _isLoading = false;
      });
    }

    final result = await ApiService.getResponderMe();
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _responder = result.data;
        _isLoading = false;
      });
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ResponderLoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _loadIncidents() async {
    setState(() {
      _incidentsLoading = true;
      _incidentsError = null;
    });
    final result = await ApiService.getAssignedIncidents();
    if (!mounted) return;
    setState(() {
      if (result.success) {
        _incidents = result.data as List<dynamic>;
      } else {
        _incidentsError = result.error;
      }
      _incidentsLoading = false;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadResponder(), _loadIncidents()]);
  }

  Future<void> _handleLogout() async {
    await ApiService.responderLogout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const ResponderLoginScreen()),
      (route) => false,
    );
  }

  // ── Derived lists ────────────────────────────────────────────────

  /// Everything currently assigned to this responder's agency that
  /// hasn't been resolved yet. This now powers BOTH "Active Incidents"
  /// AND "Incident Locations" — SOS Emergency reports are included here,
  /// so the map/list shows every unresolved incident, not just non-SOS
  /// ones.
  List<dynamic> get _activeIncidents =>
      _incidents.where((i) => i['status'] != 'resolved').toList();

  List<dynamic> get _criticalIncidents => _incidents
      .where((i) => i['priority'] == 'critical' && i['status'] != 'resolved')
      .toList();

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    final String name = _responder?['full_name'] ?? 'Responder';
    final String agency = _responder?['agency'] ?? '';
    final String unit = _responder?['unit_station'] ?? '';
    final String badge = _responder?['badge_number'] ?? '';

    // MSWD doesn't respond to incidents — their home screen skips every
    // response-workflow tile (Active Incidents, Report History, Refresh
    // Feed, Critical Alerts) and instead surfaces evacuation-center
    // management alongside the informational tiles everyone gets.
    final bool isMswd = agency == 'MSWD';

    if (_isLoading && _responder == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: _gradientTop)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
        children: [
          _Header(name: name, agency: agency, unit: unit, badge: badge),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAll,
              color: _gradientTop,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('Quick Access'),
                    const SizedBox(height: 12),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.92,
                      children: isMswd
                          ? [
                              _QuickTile(
                                label: 'Safety\nTips',
                                icon: Icons.lightbulb_outline,
                                iconColor: const Color(0xFFF9A825),
                                bgColor: const Color(0xFFFFFDE7),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SafetyTipsScreen(),
                                  ),
                                ),
                              ),
                              _QuickTile(
                                label: 'Incident\nLocations',
                                icon: Icons.location_on_outlined,
                                iconColor: const Color(0xFF1565C0),
                                bgColor: const Color(0xFFE3F2FD),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => IncidentLocationsScreen(
                                      // All non-resolved incidents,
                                      // including SOS.
                                      incidents: _activeIncidents,
                                      isLoading: _incidentsLoading,
                                      errorMessage: _incidentsError,
                                      onRetry: _loadIncidents,
                                      onOpenDetail: (incident) =>
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  _IncidentDetailScreen(
                                                    incident: incident,
                                                  ),
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              _QuickTile(
                                label: 'Disaster\nAlerts',
                                icon: Icons.campaign_outlined,
                                iconColor: const Color(0xFF6A1B9A),
                                bgColor: const Color(0xFFF3E5F5),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const _DisasterAlertsScreen(),
                                  ),
                                ),
                              ),
                              _QuickTile(
                                label: 'Evacuation\nCenters',
                                icon: Icons.home_work_outlined,
                                iconColor: const Color(0xFF2E7D32),
                                bgColor: const Color(0xFFE8F5E9),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ResponderEvacuationCentersScreen(
                                          isMswd: true,
                                        ),
                                  ),
                                ),
                              ),
                              _QuickTile(
                                label: 'Add\nEvac. Center',
                                icon: Icons.add_home_work_outlined,
                                iconColor: const Color(0xFF00897B),
                                bgColor: const Color(0xFFE0F2F1),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AddEvacuationCenterScreen(),
                                  ),
                                ),
                              ),
                            ]
                          : [
                              _QuickTile(
                                label: 'Safety\nTips',
                                icon: Icons.lightbulb_outline,
                                iconColor: const Color(0xFFF9A825),
                                bgColor: const Color(0xFFFFFDE7),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SafetyTipsScreen(),
                                  ),
                                ),
                              ),
                              _QuickTile(
                                label: 'Active\nIncidents',
                                icon: Icons.assignment_late_outlined,
                                iconColor: const Color(0xFFD32F2F),
                                bgColor: const Color(0xFFFFEBEE),
                                badgeCount: _activeIncidents.length,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _IncidentListScreen(
                                      title: 'Active Incidents',
                                      subtitle:
                                          'Everything currently assigned to your agency.',
                                      incidents: _activeIncidents,
                                      isLoading: _incidentsLoading,
                                      errorMessage: _incidentsError,
                                      onRetry: _loadIncidents,
                                      emptyIcon: Icons.task_alt,
                                      emptyMessage:
                                          'No active incidents right now.',
                                    ),
                                  ),
                                ),
                              ),
                              _QuickTile(
                                label: 'Report\nHistory',
                                icon: Icons.fact_check_outlined,
                                iconColor: const Color(0xFF2E7D32),
                                bgColor: const Color(0xFFE8F5E9),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const _ReportHistoryScreen(),
                                  ),
                                ),
                              ),
                              _QuickTile(
                                label: 'Incident\nLocations',
                                icon: Icons.location_on_outlined,
                                iconColor: const Color(0xFF1565C0),
                                bgColor: const Color(0xFFE3F2FD),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => IncidentLocationsScreen(
                                      // All non-resolved incidents,
                                      // including SOS.
                                      incidents: _activeIncidents,
                                      isLoading: _incidentsLoading,
                                      errorMessage: _incidentsError,
                                      onRetry: _loadIncidents,
                                      onOpenDetail: (incident) =>
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  _IncidentDetailScreen(
                                                    incident: incident,
                                                  ),
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              _QuickTile(
                                label: 'Disaster\nAlerts',
                                icon: Icons.campaign_outlined,
                                iconColor: const Color(0xFF6A1B9A),
                                bgColor: const Color(0xFFF3E5F5),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const _DisasterAlertsScreen(),
                                  ),
                                ),
                              ),
                              _QuickTile(
                                label: 'Refresh\nFeed',
                                icon: Icons.refresh_rounded,
                                iconColor: const Color(0xFF00897B),
                                bgColor: const Color(0xFFE0F2F1),
                                onTap: _refreshAll,
                              ),
                            ],
                    ),

                    // ── Critical Alerts ─────────────────────────────
                    // MSWD doesn't respond to incidents, so this whole
                    // section (critical-priority dispatch cards) is
                    // hidden for that agency — nothing here is
                    // actionable for them.
                    if (!isMswd) ...[
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'CRITICAL ALERT',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                              letterSpacing: 0.3,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _IncidentListScreen(
                                  title: 'Critical Alerts',
                                  subtitle:
                                      'All open incidents flagged critical priority.',
                                  incidents: _criticalIncidents,
                                  isLoading: _incidentsLoading,
                                  errorMessage: _incidentsError,
                                  onRetry: _loadIncidents,
                                  emptyIcon: Icons.shield_outlined,
                                  emptyMessage:
                                      'No critical alerts. All clear.',
                                ),
                              ),
                            ),
                            child: const Text(
                              'View All',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (_incidentsLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: _gradientTop,
                            ),
                          ),
                        )
                      else if (_criticalIncidents.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 26),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                color: Colors.green[400],
                                size: 30,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No critical alerts. All clear.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green[800],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ..._criticalIncidents
                            .take(3)
                            .map(
                              (incident) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _CriticalAlertCard(
                                  incident: incident,
                                  onViewDetails: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => _IncidentDetailScreen(
                                        incident: incident,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Header — responder identity + logout. No pulsing "on duty" circle.
// ══════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final String name;
  final String agency;
  final String unit;
  final String badge;

  const _Header({
    required this.name,
    required this.agency,
    required this.unit,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_gradientTop, _gradientBottom],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $name',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          agency.isNotEmpty
                              ? '$agency${unit.isNotEmpty ? ' · $unit' : ''}'
                              : 'Response Team',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ResponderProfileScreen(),
                      ),
                    ),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CD964),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'On Duty',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (badge.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Badge #$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Shared small widgets
// ══════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1A1A2E),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback onTap;
  final int badgeCount;

  const _QuickTile({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                    height: 1.25,
                  ),
                ),
              ],
            ),
            if (badgeCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyStateCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Incident helpers (icon, colors, formatting) — shared across screens
// ══════════════════════════════════════════════════════════════════

IconData _incidentIcon(String? type) {
  switch (type) {
    case 'Fire':
      return Icons.local_fire_department_outlined;
    case 'Flood':
      return Icons.water_outlined;
    case 'Earthquake':
      return Icons.landscape_outlined;
    case 'Accident':
      return Icons.car_crash_outlined;
    case 'Medical Emergency':
      return Icons.medical_services_outlined;
    case 'Landslide':
      return Icons.terrain_outlined;
    case 'SOS Emergency':
      return Icons.emergency_outlined;
    default:
      return Icons.warning_amber_rounded;
  }
}

const Map<String, Color> _priorityColors = {
  'critical': Color(0xFFDC2626),
  'high': Color(0xFFF97316),
  'moderate': Color(0xFF10B981),
  'low': Color(0xFF3B82F6),
};

const Map<String, Color> _statusColors = {
  'pending': Color(0xFFF59E0B),
  'responding': Color(0xFF3B82F6),
  'acknowledged': Color(0xFF3B82F6),
  'resolved': Color(0xFF10B981),
};

String _statusLabel(String? status) {
  if (status == null || status.isEmpty) return 'Pending';
  return status[0].toUpperCase() + status.substring(1);
}

const List<String> _months = [
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

String _formatDateTime(String? iso) {
  if (iso == null) return '';
  final date = DateTime.tryParse(iso);
  if (date == null) return '';
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  final month = _months[date.month - 1];
  return '$hour12:$minute $period - $month ${date.day}, ${date.year}';
}

/// `photo_path` may be a JSON-encoded array string (new incidents) or a
/// single plain path (older rows) — handle both, same as the admin panel.
List<String> _photoPaths(dynamic photoPath) {
  if (photoPath == null) return [];
  if (photoPath is! String || photoPath.isEmpty) return [];
  try {
    final decoded = jsonDecode(photoPath);
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
  } catch (_) {
    // Not JSON — treat as a single plain path.
  }
  return [photoPath];
}

String _photoUrl(String path) {
  final storageRoot = ApiService.baseUrl.endsWith('/api')
      ? ApiService.baseUrl.substring(0, ApiService.baseUrl.length - 4)
      : ApiService.baseUrl;
  return '$storageRoot/storage/$path';
}

// ══════════════════════════════════════════════════════════════════
// Critical alert card — styled after the MDRRMO reference design
// ══════════════════════════════════════════════════════════════════

class _CriticalAlertCard extends StatelessWidget {
  final Map<String, dynamic> incident;
  final VoidCallback onViewDetails;

  const _CriticalAlertCard({
    required this.incident,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final String type =
        incident['ai_detected_type'] ??
        incident['emergency_type'] ??
        'Emergency';
    final String location = incident['location'] ?? 'Unknown location';
    final String time = _formatDateTime(incident['created_at']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_critRedTop, _critRedBottom],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _critRedBottom.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _incidentIcon(incident['emergency_type']),
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        time,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onViewDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _critRedBottom,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 0,
              ),
              child: const Text(
                'View Details',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Generic incident-list screen — reused for Active Incidents & Critical
// ══════════════════════════════════════════════════════════════════

class _IncidentListScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<dynamic> incidents;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function() onRetry;
  final IconData emptyIcon;
  final String emptyMessage;

  const _IncidentListScreen({
    required this.title,
    required this.subtitle,
    required this.incidents,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    required this.emptyIcon,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
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
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: onRetry,
        color: _gradientTop,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              subtitle,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (errorMessage != null)
              _EmptyStateCard(icon: Icons.error_outline, message: errorMessage!)
            else if (incidents.isEmpty)
              _EmptyStateCard(icon: emptyIcon, message: emptyMessage)
            else
              ...incidents.map(
                (incident) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _IncidentRowCard(
                    incident: incident,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            _IncidentDetailScreen(incident: incident),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IncidentRowCard extends StatelessWidget {
  final Map<String, dynamic> incident;
  final VoidCallback onTap;
  const _IncidentRowCard({required this.incident, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final String type = incident['emergency_type'] ?? 'Unknown';
    final String? aiType = incident['ai_detected_type'];
    final String location = incident['location'] ?? '';
    final String status = (incident['status'] ?? 'pending').toString();
    final String? priority = incident['priority'];
    final bool isSos = type == 'SOS Emergency';
    final statusColor = _statusColors[status] ?? Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isSos
              ? Border.all(color: const Color(0xFFFCA5A5), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color:
                    (priority != null
                            ? _priorityColors[priority] ?? _gradientTop
                            : _gradientTop)
                        .withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _incidentIcon(type),
                color: priority != null
                    ? _priorityColors[priority] ?? _gradientTop
                    : _gradientTop,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isSos ? 'SOS Emergency' : type,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (aiType != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '✨ AI detected: $aiType',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4338CA),
                      ),
                    ),
                  ],
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _formatDateTime(incident['created_at']),
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Report History (Resolved) — the responder feed endpoint only ever
// returns open incidents (see IncidentController::assignedToResponder),
// so this screen is ready to display resolved reports the moment a
// history endpoint exists; for now it explains that clearly instead of
// silently showing nothing.
// ══════════════════════════════════════════════════════════════════

class _ReportHistoryScreen extends StatelessWidget {
  const _ReportHistoryScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
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
          'Report History',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 40),
            Icon(Icons.fact_check_outlined, size: 44, color: Colors.grey[300]),
            const SizedBox(height: 14),
            Text(
              'No resolved reports yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Incidents your agency has resolved will be logged here so you '
              'can review past responses.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Disaster Alerts — same broadcast feed the citizen app reads from
// ══════════════════════════════════════════════════════════════════

class _DisasterAlertsScreen extends StatefulWidget {
  const _DisasterAlertsScreen();

  @override
  State<_DisasterAlertsScreen> createState() => _DisasterAlertsScreenState();
}

class _DisasterAlertsScreenState extends State<_DisasterAlertsScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _alerts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await ApiService.getAlerts();
    if (!mounted) return;
    setState(() {
      if (result.success && result.data is List) {
        _alerts = (result.data as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      } else {
        _error = result.error ?? 'Could not load alerts.';
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
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
          'Disaster Alerts',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _gradientTop,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _EmptyStateCard(icon: Icons.error_outline, message: _error!),
                ],
              )
            : _alerts.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  _EmptyStateCard(
                    icon: Icons.campaign_outlined,
                    message: 'No broadcasts yet.',
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _alerts.length,
                itemBuilder: (context, index) {
                  final alert = _alerts[index];
                  final isAlertType = alert['type'] == 'Alerts';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isAlertType
                                ? const Color(0xFFFFEBEE)
                                : const Color(0xFFE3F2FD),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isAlertType
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline,
                            color: isAlertType
                                ? const Color(0xFFD32F2F)
                                : const Color(0xFF1565C0),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert['title'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                              if (alert['subtitle'] != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  alert['subtitle'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                              if (alert['body'] != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  alert['body'],
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF1A1A2E),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                _formatDateTime(alert['created_at']),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Incident detail — interactive route map + info rows + Accept/Decline.
// Used from Critical Alert cards, Incident Locations, and every other
// incident list on the responder home screen.
//
// The map preview now uses IncidentRouteMap (flutter_map + a live route
// from the responder's current position to the incident) instead of a
// static image, and Accept Mission — after confirmation — launches the
// turn-by-turn NavigationScreen, passing the incident's id through so
// NavigationScreen's "Mark as Resolved" button can open
// IncidentResolutionScreen already knowing which incident it's for.
// ══════════════════════════════════════════════════════════════════

class _IncidentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> incident;
  const _IncidentDetailScreen({required this.incident});

  @override
  State<_IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<_IncidentDetailScreen> {
  // Mission acceptance isn't wired to a backend endpoint yet (there's no
  // /api/responder/incidents/{id}/accept route today) — this tracks the
  // choice locally so the UI reflects it immediately. Once that endpoint
  // exists, swap the two _handle* methods below to call it.
  String? _missionChoice; // null | 'accepted' | 'declined'

  Map<String, dynamic> get incident => widget.incident;

  double get _lat =>
      double.tryParse('${incident['latitude'] ?? ''}') ?? 15.8952;
  double get _lng =>
      double.tryParse('${incident['longitude'] ?? ''}') ?? 120.6263;

  Future<void> _handleAccept() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Accept this mission?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'You\'ll be marked as responding to this incident, and taken '
          'straight to turn-by-turn navigation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _missionChoice = 'accepted');

    // Hand off to the turn-by-turn preview screen. TODO(backend): once
    // /api/responder/incidents/{id}/accept exists, call it here before
    // navigating so the acceptance is actually persisted server-side.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NavigationScreen(
          destinationLat: _lat,
          destinationLng: _lng,
          destinationLabel: incident['location']?.toString() ?? 'Incident',
          incidentId: incident['id'] is int
              ? incident['id'] as int
              : int.tryParse('${incident['id']}'),
        ),
      ),
    );
  }

  Future<void> _handleDecline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Decline this mission?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Other available responders in your agency will still see this '
          'incident.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _missionChoice = 'declined');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mission declined.')));
  }

  void _handleShare() {
    final type = incident['emergency_type'] ?? 'Incident';
    final location = incident['location'] ?? 'Unknown location';
    final time = _formatDateTime(incident['created_at']);
    Clipboard.setData(ClipboardData(text: '$type — $location ($time)'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Incident details copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String type = incident['emergency_type'] ?? 'Unknown';
    final String location = incident['location'] ?? '—';
    final String? priority = incident['priority'];

    final citizen = incident['citizen'] is Map
        ? incident['citizen'] as Map<String, dynamic>
        : null;
    final String reporterName = citizen?['full_name'] ?? 'Not available';
    final String reporterContact = citizen?['mobile'] ?? 'Not available';

    final bool hasCoords =
        incident['latitude'] != null && incident['longitude'] != null;

    final iconColor = priority != null
        ? (_priorityColors[priority] ?? const Color(0xFFDC2626))
        : const Color(0xFFDC2626);

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
              Icons.ios_share_rounded,
              color: Color(0xFF1A1A2E),
              size: 20,
            ),
            onPressed: _handleShare,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Map preview — this incident's location only, plus a live
          // route from the responder's current position ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: hasCoords
                ? IncidentRouteMap(
                    incidentLat: _lat,
                    incidentLng: _lng,
                    incidentLabel: location,
                    height: 200,
                  )
                : Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EDF5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.map_outlined,
                        color: Colors.grey[400],
                        size: 40,
                      ),
                    ),
                  ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Type row ──
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: iconColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _incidentIcon(type),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        type,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    if (_missionChoice != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _missionChoice == 'accepted'
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _missionChoice == 'accepted'
                              ? 'Accepted'
                              : 'Declined',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _missionChoice == 'accepted'
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 22),
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'Location',
                  value: location,
                ),
                const SizedBox(height: 18),
                _InfoRow(
                  icon: Icons.access_time_rounded,
                  label: 'Reported at',
                  value: _formatDateTime(incident['created_at']),
                ),
                const SizedBox(height: 18),
                _InfoRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Reported By',
                  value: reporterName,
                ),
                const SizedBox(height: 18),
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Contact',
                  value: reporterContact,
                ),

                if ((incident['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _InfoRow(
                    icon: Icons.notes_rounded,
                    label: 'Description',
                    value: incident['description'].toString(),
                  ),
                ],

                if (incident['ai_detected_type'] != null) ...[
                  const SizedBox(height: 18),
                  _InfoRow(
                    icon: Icons.auto_awesome,
                    label: 'AI Photo Analysis',
                    value:
                        'Likely ${incident['ai_detected_type']}${incident['ai_confidence'] != null ? ' (${incident['ai_confidence']} confidence)' : ''}',
                  ),
                ],

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _missionChoice == null ? _handleAccept : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E9E4F),
                      disabledBackgroundColor: const Color(
                        0xFF2E9E4F,
                      ).withOpacity(0.5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      _missionChoice == 'accepted'
                          ? 'MISSION ACCEPTED'
                          : 'ACCEPT MISSION',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _missionChoice == null ? _handleDecline : null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey[300]!, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      'DECLINE',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: Colors.grey[700],
                      ),
                    ),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey[500], size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
