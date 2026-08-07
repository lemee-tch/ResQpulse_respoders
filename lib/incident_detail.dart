import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
      _typeIcons[widget.incident['emergency_type']] ??
      Icons.warning_amber_rounded;

  double? get _lat => double.tryParse('${widget.incident['latitude']}');
  double? get _lng => double.tryParse('${widget.incident['longitude']}');

  String get _reporterName =>
      widget.incident['citizen']?['full_name']?.toString() ?? 'Unknown';

  String? get _reporterMobile =>
      widget.incident['citizen']?['mobile']?.toString();

  String get _formattedDate {
    final raw = widget.incident['created_at']?.toString();
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

  /// TODO(backend): wire this to a real endpoint once one exists, e.g.
  /// POST /api/responder/incidents/{id}/accept — there is currently no
  /// responder-facing route to change an incident's status; only the
  /// admin panel (IncidentController::updateStatus, web.php) can.
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

    setState(() => _isResponding = true);

    // Placeholder — replace with a real ApiService call, e.g.:
    // final result = await ApiService.acceptIncident(widget.incident['id']);
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;
    setState(() => _isResponding = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => NavigationScreen(
          destinationLat: _lat!,
          destinationLng: _lng!,
          destinationLabel:
              widget.incident['location']?.toString() ?? 'Incident',
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

    // TODO(backend): same as accept — no decline endpoint exists yet.
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.incident['emergency_type']?.toString() ?? 'Unknown';
    final location = widget.incident['location']?.toString() ?? '—';
    final description = widget.incident['description']?.toString() ?? '';

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
                        onPressed: _isResponding ? null : _handleAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
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
                            : const Text(
                                'ACCEPT MISSION',
                                style: TextStyle(
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
                        onPressed: _isResponding ? null : _handleDecline,
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
