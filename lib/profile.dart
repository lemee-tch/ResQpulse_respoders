import 'package:flutter/material.dart';
import 'about.dart';
import 'api_service.dart';
import 'responder_login.dart';

const Color _navy = Color(0xFF0D1B4C);
const Color _navyDeep = Color(0xFF081130);
const Color _ink = Color(0xFF1A1A2E);
const Color _chipBg = Color(0xFFE8EAF4);

/// Same agency → icon mapping used elsewhere in the app (see
/// responder_home.dart), so a responder's badge here matches the icon
/// shown for their agency everywhere else. Falls back to a generic
/// shield if the account's agency is missing or unrecognized.
const Map<String, IconData> _agencyIcons = {
  'PNP': Icons.local_police,
  'BFP': Icons.local_fire_department,
  'SARS': Icons.health_and_safety,
  'HCU': Icons.medical_services,
  'MSWD': Icons.volunteer_activism,
};

class ResponderProfileScreen extends StatefulWidget {
  const ResponderProfileScreen({super.key});

  @override
  State<ResponderProfileScreen> createState() => _ResponderProfileScreenState();
}

class _ResponderProfileScreenState extends State<ResponderProfileScreen> {
  Map<String, dynamic>? _responder;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadResponder();
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
    } else if (_responder == null) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    await ApiService.responderLogout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ResponderLoginScreen()),
      (route) => false,
    );
  }

  /// Personal Information (item 64 — before, it did nothing when tapped):
  /// the agency account's details, read-only. MDRRMO manages them.
  void _showPersonalInformation() {
    final responder = _responder ?? const {};
    String value(String key) {
      final v = responder[key]?.toString().trim() ?? '';
      return v.isEmpty ? 'Not set' : v;
    }

    final rows = <(String, String)>[
      ('Account name', value('full_name')),
      ('Agency', value('agency')),
      ('Station or unit', value('unit_station')),
      ('Badge number', value('badge_number')),
      ('Email', value('email')),
      ('Mobile number', value('mobile')),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Personal Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _ink,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'This agency account is managed by MDRRMO Rosales. To change '
                'these details or the password, ask MDRRMO.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF4B5563),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              for (final row in rows)
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.$1,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          row.$2,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 25, 27, 158),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleLogout();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String name = _responder?['full_name'] ?? 'Responder';
    final String email = _responder?['email']?.toString() ?? '';
    final String agency = _responder?['agency']?.toString() ?? '';
    final IconData badgeIcon = _agencyIcons[agency] ?? Icons.shield_outlined;

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
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      // Loading state intentionally stays plain (navy app bar + spinner on
      // the light body) — the badge header below only makes sense once we
      // actually know which agency to show, so it's skipped rather than
      // shown empty/flickering.
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Identity badge ──
                    // Responder accounts are shared per agency/station, not
                    // individual logins (see Responder-api_service.dart),
                    // so this reads as an agency credential — badge icon +
                    // agency/station name + an explicit "shared account"
                    // tag — rather than a personal avatar and name.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [_navy, _navyDeep],
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(28),
                          bottomRight: Radius.circular(28),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.35),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              badgeIcon,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Shared agency account',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Menu + logout ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionLabel('Account'),
                          const SizedBox(height: 10),
                          _MenuItem(
                            icon: Icons.person_outline,
                            label: 'Personal Information',
                            subtitle: email.isNotEmpty
                                ? email
                                : 'Your agency account\'s details',
                            onTap: _showPersonalInformation,
                          ),

                          const SizedBox(height: 24),
                          const _SectionLabel('About'),
                          const SizedBox(height: 10),
                          _MenuItem(
                            icon: Icons.info_outline_rounded,
                            label: 'About Resqponder',
                            subtitle:
                                'The app, privacy, terms and accessibility',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AboutScreen(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _confirmLogout,
                              icon: const Icon(
                                Icons.logout_rounded,
                                size: 18,
                                color: Color(0xFFDC2626),
                              ),
                              label: const Text(
                                'Logout',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFF5F5),
                                side: const BorderSide(
                                  color: Color(0xFFFCA5A5),
                                  width: 1.3,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),
                          // grey[400] was too faint to read (item 64).
                          const Center(
                            child: Text(
                              'Resqponder · v$kAppVersion',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.bold,
        color: _ink,
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  // Item 64: a real button for screen readers (it was a bare
  // GestureDetector), read as one item, with a ripple when tapped.
  @override
  Widget build(BuildContext context) {
    return MergeSemantics(child: Semantics(button: true, child: _tile()));
  }

  Widget _tile() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      shadowColor: Colors.black.withOpacity(0.2),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _chipBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _navy, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ),
              const ExcludeSemantics(
                child: Icon(
                  Icons.chevron_right,
                  color: Color(0xFF6B7280),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
