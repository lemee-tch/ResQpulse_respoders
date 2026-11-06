import 'package:flutter/material.dart';
import 'legal.dart';
import 'phone_call.dart';

/// The version shown on About and Profile. Keep it the same as `version:`
/// in pubspec.yaml (the part before the "+").
const String kAppVersion = '1.0.0';

const String _mdrrmoNumber = '#2441';

/// Profile → About Resqponder (item 64 — before, it did nothing).
///
/// What Resqponder does — as the app actually works (item 65): incidents
/// that ring, Accept / Join as backup / Decline, the details, Start
/// navigating, Request backup, the MDRRMC Incident Report, the lists, and
/// MSWD's evacuation screens — a team's responsibilities with residents'
/// information, what it can't do, the team's own information, and
/// Resqponder's own Privacy Policy, Terms and Conditions, Cookie Policy and
/// Accessibility (lib/legal_text.dart; the residents' app has its own).
///
/// Accessibility: section titles are headings for screen readers, rows are
/// read as one item, buttons are at least 48 dp tall, text follows the
/// phone's font size, and every text color has at least 4.5:1 contrast.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const Color _navy = Color(0xFF0D1B4C);
  static const Color _red = Color(0xFFC62828);
  static const Color _ink = Color(0xFF111827);
  static const Color _muted = Color(0xFF4B5563);

  Future<void> _callMdrrmo(BuildContext context) async {
    final opened = await openDialer(_mdrrmoNumber);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Couldn\'t open the phone app. Dial #2441 to reach MDRRMO Rosales.',
          ),
          backgroundColor: _red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: _navy,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'About Resqponder',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            _header(),
            const SizedBox(height: 24),
            _helpCard(context),
            const SizedBox(height: 16),
            _card(
              title: 'What you can do',
              children: const [
                _InfoRow(
                  icon: Icons.notifications_active_outlined,
                  color: _red,
                  title: 'Incidents that ring',
                  text:
                      'MDRRMO sends your team the SOS alerts and reports it '
                      'approves, and they ring like a call. Accept the '
                      'mission, join as backup when MDRRMO sends you as '
                      'backup, or decline.',
                ),
                _InfoRow(
                  icon: Icons.info_outline,
                  color: Color(0xFF1565C0),
                  title: 'All the details',
                  text:
                      'Who reported and their number, the address, landmark '
                      'and GPS pin, photos, the AI photo check and MDRRMO\'s '
                      'instructions. "Copy for a message" leaves out the '
                      'reporter\'s name and number.',
                ),
                _InfoRow(
                  icon: Icons.directions_outlined,
                  color: _navy,
                  title: 'Start navigating',
                  text:
                      'A route from where you are to the incident. Distances '
                      'and times are estimates.',
                ),
                _InfoRow(
                  icon: Icons.group_add_outlined,
                  color: Color(0xFFB45309),
                  title: 'Request backup',
                  text:
                      'Ask MDRRMO for more teams and what you need. You\'re '
                      'notified when MDRRMO answers.',
                ),
                _InfoRow(
                  icon: Icons.assignment_outlined,
                  color: Color(0xFF00796B),
                  title: 'Submit the incident report',
                  text:
                      'The MDRRMC Incident Report: what you found, casualties, '
                      'effects and actions taken, with a photo. MDRRMO may '
                      'correct it before approving it; View Report shows it '
                      'and its PDF.',
                ),
                _InfoRow(
                  icon: Icons.list_alt_rounded,
                  color: Color(0xFF6D28D9),
                  title: 'Your lists',
                  text:
                      'Active Incidents, Accepted Missions, Report History, '
                      'Incident Locations, Disaster Alerts and Safety Tips.',
                ),
                _InfoRow(
                  icon: Icons.night_shelter_outlined,
                  color: Color(0xFF2E7D32),
                  title: 'For MSWD teams',
                  text:
                      'Evacuation Centers (mark them open or full), Add Evac. '
                      'Center, Log Evacuee and Resident Logs.',
                  last: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _card(
              title: 'Your responsibilities',
              children: const [
                _InfoRow(
                  icon: Icons.lock_outline,
                  color: _red,
                  title: 'Residents\' information is confidential',
                  text:
                      'Use names, numbers, locations and photos only for the '
                      'response. Don\'t screenshot, share or post them. '
                      'Misusing them can be a crime under the Data Privacy '
                      'Act.',
                ),
                _InfoRow(
                  icon: Icons.key_outlined,
                  color: _navy,
                  title: 'Keep the agency account in the agency',
                  text:
                      'Don\'t share the password outside your agency. Ask '
                      'MDRRMO to change it when someone leaves.',
                ),
                _InfoRow(
                  icon: Icons.history_rounded,
                  color: Color(0xFF6D28D9),
                  title: 'What you do is recorded',
                  text:
                      'Accepting, declining, reports and backup requests are '
                      'kept in MDRRMO\'s records.',
                  last: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _card(
              title: 'Good to know',
              children: const [
                _InfoRow(
                  icon: Icons.volume_up_outlined,
                  color: _red,
                  title: 'Keep the alarm volume up',
                  text:
                      'Incidents ring on the phone\'s alarm volume. If it\'s '
                      'down, the ring is silent.',
                ),
                _InfoRow(
                  icon: Icons.wifi_off_rounded,
                  color: Color(0xFFB45309),
                  title: 'It needs internet',
                  text:
                      'Without a connection, new incidents can\'t reach your '
                      'phone. Keep your radio on too.',
                ),
                _InfoRow(
                  icon: Icons.auto_awesome,
                  color: Color(0xFF4338CA),
                  title: 'The AI photo check is only a hint',
                  text:
                      'It can be wrong. Check the photo and the place '
                      'yourself.',
                ),
                _InfoRow(
                  icon: Icons.map_outlined,
                  color: Color(0xFF00796B),
                  title: 'Maps and routes',
                  text:
                      'Maps are from OpenStreetMap and routes from the OSRM '
                      'route service. Roads can be closed or flooded; trust '
                      'what you see.',
                  last: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _card(
              title: 'Your information',
              children: [
                const _InfoRow(
                  icon: Icons.badge_outlined,
                  color: _navy,
                  title: 'Your agency account',
                  text:
                      'The agency, station, badge number, email and mobile '
                      'number MDRRMO set up for it.',
                ),
                const _InfoRow(
                  icon: Icons.location_on_outlined,
                  color: _red,
                  title: 'Your location',
                  text:
                      'Used on this phone for maps and routes. It isn\'t sent '
                      'to MDRRMO, except the location of an evacuation center '
                      'you add.',
                  last: true,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        openLegal(context, LegalDoc.privacy, accent: _navy),
                    icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                    label: const Text('Read the Privacy Policy'),
                    style: TextButton.styleFrom(
                      foregroundColor: _navy,
                      minimumSize: const Size(48, 48),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _card(
              title: 'Legal',
              children: const [LegalLinks(accent: _navy)],
            ),
            const SizedBox(height: 20),
            const Text(
              'Resqponder is run by the Municipal Disaster Risk Reduction and '
              'Management Office (MDRRMO) of Rosales, Pangasinan, for its '
              'response teams.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _navy.withOpacity(0.2),
                blurRadius: 16,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.cover,
              semanticLabel: 'ResQPulse logo',
              errorBuilder: (context, error, stackTrace) => Container(
                color: _navy,
                alignment: Alignment.center,
                child: const Text(
                  'RQ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: const Text(
            'Resqponder',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _ink,
            ),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Version $kAppVersion · ResQPulse for response teams',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: _muted),
        ),
        const SizedBox(height: 10),
        const Text(
          'Get the incidents MDRRMO Rosales sends your team, find the way, '
          'and report back.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: Color(0xFF374151),
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _helpCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: const Text(
              'Need MDRRMO?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _navy,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Request backup from the incident, or call MDRRMO Rosales at '
            '#2441. Resqponder helps, but it doesn\'t replace your radio or '
            'a phone call.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF1F2937),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _callMdrrmo(context),
              icon: const Icon(Icons.call, size: 20),
              label: const Text(
                'Call MDRRMO Rosales',
                semanticsLabel: 'Call MDRRMO Rosales at #2441',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// An icon, a title and a sentence — read as one item by screen readers.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final bool last;

  const _InfoRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF4B5563),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
