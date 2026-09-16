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

  static const Map<String, int> _priorityRank = {
    'critical': 0,
    'high': 1,
    'moderate': 2,
    'low': 3,
  };

  /// Everything currently assigned to this responder's agency that
  /// hasn't been resolved yet. This now powers BOTH "Active Incidents"
  /// AND "Incident Locations" — SOS Emergency reports are included here,
  /// so the map/list shows every unresolved incident, not just non-SOS
  /// ones.
  ///
  /// Sorted so critical-priority incidents always show first (then high,
  /// moderate, low, and finally anything with no priority set). Incidents
  /// that share a priority keep their original relative order from the
  /// API (most-recent-first) — done via an index-based sort since Dart's
  /// List.sort isn't guaranteed stable.
  List<dynamic> get _activeIncidents {
    final list = _incidents.where((i) => i['status'] != 'resolved').toList();

    final indexed = list.asMap().entries.toList()
      ..sort((a, b) {
        final rankA = _priorityRank[a.value['priority']] ?? 4;
        final rankB = _priorityRank[b.value['priority']] ?? 4;
        if (rankA != rankB) return rankA.compareTo(rankB);
        return a.key.compareTo(b.key);
      });

    return indexed.map((e) => e.value).toList();
  }

  List<dynamic> get _criticalIncidents => _incidents
      .where((i) => i['priority'] == 'critical' && i['status'] != 'resolved')
      .toList();

  /// Missions THIS responder has personally accepted (or joined as
  /// backup on) and that aren't resolved yet — distinct from "Active
  /// Incidents" above, which is everything assigned to the whole
  /// agency regardless of who (if anyone) has accepted it.
  List<dynamic> get _acceptedMissions {
    final myId = _responder?['id'];
    if (myId == null) return const [];

    return _incidents.where((i) {
      if (i['status'] == 'resolved') return false;
      final responders = (i['responders'] as List<dynamic>?) ?? const [];
      return responders.any((r) => r is Map && r['id'] == myId);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    final String name = _responder?['full_name'] ?? 'Responder';
    final String agency = _responder?['agency'] ?? '';
    final String unit = _responder?['unit_station'] ?? '';

    // MSWD doesn't respond to incidents — their home screen skips every
    // response-workflow tile (Active Incidents, Report History, Accepted
    // Missions, Critical Alerts) and instead surfaces evacuation-center
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
          _Header(name: name, agency: agency, unit: unit),
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
                                label: 'Accepted\nMissions',
                                icon: Icons.task_alt_outlined,
                                iconColor: const Color(0xFF00897B),
                                bgColor: const Color(0xFFE0F2F1),
                                badgeCount: _acceptedMissions.length,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _IncidentListScreen(
                                      title: 'Accepted Missions',
                                      subtitle:
                                          'Missions you\'ve personally accepted or backed up.',
                                      incidents: _acceptedMissions,
                                      isLoading: _incidentsLoading,
                                      errorMessage: _incidentsError,
                                      onRetry: _loadIncidents,
                                      emptyIcon: Icons.task_alt_outlined,
                                      emptyMessage:
                                          'You haven\'t accepted any missions yet.',
                                    ),
                                  ),
                                ),
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
// Header — responder identity, agency icon, and duty/date status.
// Time-based greeting + today's date instead of a static "Hello" that
// never changes; agency icon (PNP/BFP/SARS/HCU/MSWD) replaces the
// generic shield so the card actually reflects who's signed in.
// ══════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final String name;
  final String agency;
  final String unit;

  const _Header({required this.name, required this.agency, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_gradientTop, _gradientBottom],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: _gradientTop.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
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
                    child: Icon(
                      _agencyIcons[agency] ?? Icons.shield,
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
                          '${_greeting()}, $name',
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4CD964),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          'On Duty',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _todayLabel(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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

const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "Monday, Sep 14" — reuses the same [_months] table as
/// [_formatDateTime] above rather than a second copy.
String _todayLabel() {
  final now = DateTime.now();
  return '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}';
}

/// Good morning/afternoon/evening by device clock — purely cosmetic, but
/// a static "Hello" never changes and starts feeling like dead chrome;
/// this at least reflects when the responder is actually opening the app.
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

const Map<String, IconData> _agencyIcons = {
  'PNP': Icons.local_police,
  'BFP': Icons.local_fire_department,
  'SARS': Icons.health_and_safety,
  'HCU': Icons.medical_services,
  'MSWD': Icons.volunteer_activism,
};

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

/// Full-screen, pinch-to-zoom viewer for a tapped incident photo —
/// swipeable if there's more than one. Kept intentionally minimal (no
/// download/share) since this is just for a responder to size up the
/// scene before heading out.
void _openPhotoViewer(
  BuildContext context,
  List<String> photoPaths,
  int initialIndex,
) {
  showDialog(
    context: context,
    barrierColor: Colors.black,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: PageController(initialPage: initialIndex),
            itemCount: photoPaths.length,
            itemBuilder: (context, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  _photoUrl(photoPaths[i]),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey[600],
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ],
      ),
    ),
  );
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
    final List<dynamic> respondersRaw = incident['responders'] is List
        ? incident['responders'] as List
        : const [];
    final List<Map<String, dynamic>> responders = respondersRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

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
                  if (responders.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.shield,
                          size: 12,
                          color: Color(0xFF2E7D32),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            responders.length == 1
                                ? 'Responding: ${responders.first['full_name'] ?? 'Assigned'}'
                                : 'Responding: ${responders.first['full_name'] ?? 'Assigned'} +${responders.length - 1} more',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      ],
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

/// Picks an icon + color that actually matches what the alert is about.
/// Mirrors the same fix in the citizen app's alert.dart — the Alert
/// model's `type` column is an audience switch (Citizens/Responders/
/// Both), not a hazard category, and was never 'Alerts'/'Updates' after
/// that migration. The old `alert['type'] == 'Alerts'` check here was
/// checking a value that no longer exists, so every card silently
/// always rendered as the same generic "info" style.
class _AlertStyle {
  final IconData icon;
  final Color bgColor;
  final Color iconColor;
  const _AlertStyle(this.icon, this.bgColor, this.iconColor);
}

const _defaultAlertStyle = _AlertStyle(
  Icons.campaign_outlined,
  Color(0xFFE3F2FD),
  Color(0xFF1565C0),
);

const Map<String, _AlertStyle> _alertKeywordStyles = {
  'fire': _AlertStyle(
    Icons.local_fire_department,
    Color(0xFFFFEBEE),
    Color(0xFFD32F2F),
  ),
  'flood': _AlertStyle(Icons.water, Color(0xFFE3F2FD), Color(0xFF1565C0)),
  'typhoon': _AlertStyle(Icons.cyclone, Color(0xFFF3E5F5), Color(0xFF6A1B9A)),
  'storm': _AlertStyle(Icons.cyclone, Color(0xFFF3E5F5), Color(0xFF6A1B9A)),
  'earthquake': _AlertStyle(
    Icons.landscape,
    Color(0xFFEFEBE9),
    Color(0xFF6D4C41),
  ),
  'landslide': _AlertStyle(Icons.terrain, Color(0xFFEFEBE9), Color(0xFF6D4C41)),
  'evacuat': _AlertStyle(
    // evacuate/evacuation
    Icons.directions_run,
    Color(0xFFFFF3E0),
    Color(0xFFE65100),
  ),
  'health': _AlertStyle(
    Icons.local_hospital,
    Color(0xFFE0F2F1),
    Color(0xFF00897B),
  ),
  'power': _AlertStyle(Icons.bolt, Color(0xFFFFFDE7), Color(0xFFF9A825)),
  'water supply': _AlertStyle(
    Icons.water_drop,
    Color(0xFFE3F2FD),
    Color(0xFF1565C0),
  ),
  'road': _AlertStyle(
    Icons.warning_amber_rounded,
    Color(0xFFFFF3E0),
    Color(0xFFE65100),
  ),
};

_AlertStyle _styleForAlert(Map<String, dynamic> alert) {
  final text = '${alert['title'] ?? ''} ${alert['subtitle'] ?? ''}'
      .toLowerCase();
  for (final entry in _alertKeywordStyles.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return _defaultAlertStyle;
}

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
                  final style = _styleForAlert(alert);
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
                            color: style.bgColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            style.icon,
                            color: style.iconColor,
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
  // 'declined' only reflects what THIS responder just did in this
  // session (declining has no server-side record — see
  // Api\IncidentController::decline). Whether the mission has been
  // accepted, and by whom — including possibly several backup
  // responders — is read straight from incident['responders'], which
  // the backend now returns as a list once
  // /api/responder/incidents/{id}/accept has been called by anyone.
  String? _missionChoice; // null | 'accepted' | 'declined'
  bool _isSubmitting = false;

  // This device's own responder id — used only to tell "I've already
  // joined this incident" apart from "someone else has, but not me",
  // since backup support means both can be true for different people
  // looking at the same incident at the same time.
  String? _myResponderId;

  // Mutable local copy so a successful accept call can update who's
  // shown as "responding" immediately, without waiting on a full list
  // refresh from the home screen.
  late Map<String, dynamic> incident = Map<String, dynamic>.from(
    widget.incident,
  );

  @override
  void initState() {
    super.initState();
    _loadMyResponderId();
  }

  Future<void> _loadMyResponderId() async {
    final me = await ApiService.getResponder();
    if (!mounted || me == null) return;
    setState(() => _myResponderId = me['id']?.toString());
  }

  List<Map<String, dynamic>> get _responders {
    final raw = incident['responders'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  bool get _hasResponders => _responders.isNotEmpty;

  /// Whether the responder currently looking at this screen is already
  /// on the incident — this, not [_hasResponders], is what should
  /// disable the Accept button. Other agencies/teams joining as backup
  /// shouldn't lock anyone else out.
  bool get _iHaveJoined =>
      _myResponderId != null &&
      _responders.any((r) => r['id']?.toString() == _myResponderId);

  double get _lat =>
      double.tryParse('${incident['latitude'] ?? ''}') ?? 15.8952;
  double get _lng =>
      double.tryParse('${incident['longitude'] ?? ''}') ?? 120.6263;

  Future<void> _handleAccept() async {
    // Already joined by THIS responder — nothing to confirm, just say
    // so. The Accept button is disabled in this case too, but this
    // guards against a stale tap racing the rebuild.
    if (_iHaveJoined) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You\'re already responding to this incident.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final bool isBackup = _hasResponders;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isBackup ? 'Join as backup support?' : 'Accept this mission?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          isBackup
              ? '${_responders.length} team${_responders.length == 1 ? ' is' : 's are'} '
                    'already responding. You\'ll be added as backup support and '
                    'taken straight to turn-by-turn navigation.'
              : 'You\'ll be marked as responding to this incident, and taken '
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

    final incidentId = incident['id'] is int
        ? incident['id'] as int
        : int.tryParse('${incident['id']}');

    if (incidentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This incident has no valid ID — cannot accept.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await ApiService.acceptIncident(incidentId);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!result.success) {
      // Only a genuine failure (network error, incident already
      // resolved, etc.) reaches here now — joining as backup never
      // "loses a race", so there's no partial-success incident data to
      // recover from the error response anymore.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Could not accept this mission.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Success — pick up the server's copy (now includes the full
    // `responders` list and status: 'responding') so the UI reflects
    // the real, persisted state.
    final data = result.data;
    if (data is Map && data['incident'] is Map) {
      incident = Map<String, dynamic>.from(data['incident'] as Map);
    }
    setState(() => _missionChoice = 'accepted');

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NavigationScreen(
          destinationLat: _lat,
          destinationLng: _lng,
          destinationLabel: incident['location']?.toString() ?? 'Incident',
          incidentId: incidentId,
        ),
      ),
    );
  }

  Future<void> _handleDecline() async {
    if (_iHaveJoined) return;

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

    setState(() => _isSubmitting = true);

    final incidentId = incident['id'] is int
        ? incident['id'] as int
        : int.tryParse('${incident['id']}');
    if (incidentId != null) {
      // Best-effort/informational only — there's no per-responder
      // "declined" record server-side, so this never blocks the local
      // UI update below even if the call fails.
      await ApiService.declineIncident(incidentId);
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _missionChoice = 'declined';
    });
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

    final List<String> photoPaths = _photoPaths(incident['photo_path']);

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
                    if (_hasResponders)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _responders.length == 1
                              ? 'Responding'
                              : '${_responders.length} Responding',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      )
                    else if (_missionChoice == 'declined')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Declined',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 22),
                if (_hasResponders) ...[
                  const Text(
                    'Responding Team',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._responders.map((r) {
                    final bool isMe =
                        _myResponderId != null &&
                        r['id']?.toString() == _myResponderId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 18,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${r['full_name'] ?? 'Unknown responder'}'
                              '${r['agency'] != null ? ' · ${r['agency']}' : ''}'
                              '${isMe ? ' (You)' : ''}',
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                ],
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

                if (photoPaths.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    photoPaths.length == 1 ? 'Photo' : 'Photos',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: photoPaths.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => _openPhotoViewer(context, photoPaths, i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            _photoUrl(photoPaths[i]),
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                width: 92,
                                height: 92,
                                color: const Color(0xFFF0F0F0),
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stack) => Container(
                              width: 92,
                              height: 92,
                              color: const Color(0xFFF0F0F0),
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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
                    onPressed:
                        (_missionChoice == null &&
                            !_iHaveJoined &&
                            !_isSubmitting)
                        ? _handleAccept
                        : null,
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
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            _iHaveJoined
                                ? 'YOU\'RE RESPONDING'
                                : (_hasResponders
                                      ? 'JOIN AS BACKUP'
                                      : 'ACCEPT MISSION'),
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
                    onPressed:
                        (_missionChoice == null &&
                            !_iHaveJoined &&
                            !_isSubmitting)
                        ? _handleDecline
                        : null,
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
