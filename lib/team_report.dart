import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';

const Color _ink = Color(0xFF1A1A2E);
const Color _navy = Color(0xFF0D1B4C);
const Color _green = Color(0xFF2E7D32);
const Color _amber = Color(0xFFB45309);
const Color _purple = Color(0xFF6D28D9);
const Color _orange = Color(0xFFE65100);

/// The team's MDRRMC Incident Report, read-only (item 48): everything the
/// report says, where it stands with MDRRMO, and the same PDF MDRRMO sees.
/// Opened from Incident Details ("VIEW REPORT", or "Full report" under
/// Responders' report) by a responder on the incident — and from the report
/// form when the report can't be changed anymore. Before, a report with
/// MDRRMO or approved only said "Final report submitted": the team couldn't
/// read what it had sent.
///
/// Since item 49 the team sends only the Initial report, and MDRRMO may
/// correct it before approving it: what MDRRMO changed is said at the top,
/// and the report and PDF show the corrected version.
///
/// Loads GET /api/responder/incidents/{id}/report (see
/// Api\IncidentController::reportForResponder()). Its pdf_url is a signed
/// link that works for 30 minutes, opened in the phone's browser or PDF
/// viewer; a fresh one is asked for each time.
class TeamReportScreen extends StatefulWidget {
  final int incidentId;

  /// "Fire", "SOS Alert — Accident"… shown under the title.
  final String? incidentLabel;

  const TeamReportScreen({
    super.key,
    required this.incidentId,
    this.incidentLabel,
  });

  @override
  State<TeamReportScreen> createState() => _TeamReportScreenState();
}

class _TeamReportScreenState extends State<TeamReportScreen> {
  bool _isLoading = true;
  String? _error;

  /// The whole reply: the report, where it stands, the PDF link…
  Map<String, dynamic> _data = const {};
  Map<String, dynamic>? _report;
  bool _openingPdf = false;

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
    final result = await ApiService.getIncidentReport(widget.incidentId);
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _isLoading = false;
        _error = result.error ?? 'Couldn\'t load the report.';
      });
      return;
    }
    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : <String, dynamic>{};
    setState(() {
      _isLoading = false;
      _data = data;
      _report = data['report'] is Map
          ? Map<String, dynamic>.from(data['report'] as Map)
          : null;
    });
  }

  /// Opens the PDF in the phone's browser or PDF viewer, with a fresh link
  /// (each one works for 30 minutes).
  Future<void> _openPdf() async {
    setState(() => _openingPdf = true);
    final result = await ApiService.getIncidentReport(widget.incidentId);
    final link = result.success && result.data is Map
        ? _text((result.data as Map)['pdf_url'])
        : null;

    bool opened = false;
    if (link != null) {
      try {
        opened = await launchUrl(
          Uri.parse(link),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        opened = false;
      }
    }
    if (!mounted) return;
    setState(() => _openingPdf = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Couldn\'t open the PDF. Check your connection and try again.'
                : (result.error ?? 'Couldn\'t open the PDF.'),
          ),
        ),
      );
    }
  }

  // ── Where the report stands ────────────────────────────────────────

  bool get _isInitial => _report?['report_type'] == 'initial';
  String? get _returnedReason => _text(_data['returned_reason']);
  bool get _underReview => _data['under_review'] == true;
  bool get _resolved => _data['incident_status'] == 'resolved';

  /// Saved on the incident but not sent to MDRRMO: an Initial report saved
  /// before item 49 (MDRRMO sent back ones say so instead).
  bool get _notSent => _data['can_edit'] == true && _returnedReason == null;

  /// The status chip: what's happening with the report now.
  String get _stageText {
    if (_returnedReason != null) return 'Sent back by MDRRMO';
    // Not resolved yet: MDRRMO marks it resolved when it approves the
    // report (item 50).
    if (_underReview) return 'For Review';
    if (_resolved) return 'Approved by MDRRMO';
    if (_notSent) return 'Saved — not sent yet';
    return 'Sent';
  }

  Color get _stageColor {
    if (_returnedReason != null) return _orange;
    if (_underReview) return _purple;
    if (_notSent) return _amber;
    return _green;
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _message(
        icon: Icons.cloud_off_outlined,
        title: 'Couldn\'t open the report',
        text: _error!,
        action: 'Try Again',
        onAction: _load,
      );
    } else if (_report == null) {
      body = _message(
        icon: Icons.description_outlined,
        title: 'No report yet',
        text:
            'The team hasn\'t filed the MDRRMC Incident Report for this '
            'incident yet.',
        action: 'Back',
        onAction: () => Navigator.pop(context),
      );
    } else {
      body = RefreshIndicator(onRefresh: _load, child: _buildReport(_report!));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _ink, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Incident Report',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _buildReport(Map<String, dynamic> r) {
    final String stageText = _stageText;
    final Color stageColor = _stageColor;
    final String? pdfUrl = _text(_data['pdf_url']);
    final int revision = int.tryParse('${r['revision'] ?? ''}') ?? 1;
    final String filedAt = _manila(r['filed_at']);
    final String updatedAt = _manila(r['updated_at']);
    final String submittedAt = _manila(_data['submitted_at']);
    final String? reviewedBy = _text(r['reviewed_by']);
    final String? reviewedAt = _text(r['reviewed_at']);
    // What MDRRMO corrected before approving it (item 49).
    final String? editedBy = _text(r['edited_by']);
    final String editedAt = _manila(r['edited_at']);
    final String editedParts = r['edited_parts'] is List
        ? (r['edited_parts'] as List)
              .map((p) => p.toString())
              .where((p) => p.trim().isNotEmpty)
              .join(', ')
        : '';
    final String? photoPath = _text(_data['photo_path']);
    final casualties = r['casualties'] is Map
        ? r['casualties'] as Map
        : const {};
    final team = r['team'] is List ? r['team'] as List : const [];

    final String when = [
      _text(r['incident_date']),
      if (_text(r['incident_day']) != null) '(${_text(r['incident_day'])})',
      _text(r['incident_time']),
    ].whereType<String>().join(' ');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        // ── What this is ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: stageColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.description_outlined,
                color: stageColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MDRRMC Incident Report',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _ink,
                      height: 1.25,
                    ),
                  ),
                  if (widget.incidentLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.incidentLabel!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Chip(
                        label: _isInitial ? 'Initial' : 'Final',
                        color: _isInitial ? _amber : _green,
                        filled: true,
                      ),
                      _Chip(label: stageText, color: stageColor),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          [
            if (filedAt.isNotEmpty)
              '${_notSent ? 'Saved' : 'First sent'} $filedAt',
            if (revision > 1 && updatedAt.isNotEmpty)
              '${_notSent ? 'updated' : 'sent again'} $updatedAt'
                  '${revision > 2 ? ' (${revision - 1} times)' : ''}',
            if (submittedAt.isNotEmpty && filedAt.isEmpty)
              'sent to MDRRMO $submittedAt',
          ].join(' · '),
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),

        // ── What MDRRMO did with it ──
        if (editedBy != null)
          _Notice(
            icon: Icons.edit_note,
            color: _purple,
            background: const Color(0xFFF3E8FF),
            text:
                'Corrected by $editedBy'
                '${editedAt.isNotEmpty ? ' — $editedAt' : ''}'
                '${editedParts.isNotEmpty ? ': $editedParts' : ''}. '
                'The report and the PDF show the corrections.',
          ),
        if (_returnedReason != null)
          _Notice(
            icon: Icons.assignment_return_outlined,
            color: _orange,
            background: const Color(0xFFFFF3E0),
            text:
                'MDRRMO sent it back: $_returnedReason. Fix it with UPDATE & '
                'SEND REPORT on Incident Details, then send it again.',
          )
        else if (_underReview)
          const _Notice(
            icon: Icons.hourglass_top_rounded,
            color: _purple,
            background: Color(0xFFF3E8FF),
            text:
                'For Review: MDRRMO is checking it. The incident isn\'t '
                'resolved until they approve it. It can\'t be changed unless '
                'MDRRMO sends it back.',
          )
        else if (reviewedBy != null)
          _Notice(
            icon: Icons.verified_outlined,
            color: _green,
            background: const Color(0xFFE8F5E9),
            text:
                'Reviewed by $reviewedBy'
                '${reviewedAt != null ? ' — $reviewedAt' : ''}. '
                'The incident is resolved.',
          )
        else if (_notSent)
          const _Notice(
            icon: Icons.edit_note,
            color: _amber,
            background: Color(0xFFFFF8E1),
            text:
                'Saved but not sent to MDRRMO yet: send it with UPDATE & SEND '
                'REPORT on Incident Details.',
          ),

        // ── The report itself ──
        _Section(
          title: 'Incident',
          children: [
            _Line('Type', _text(r['incident_type']) ?? '—'),
            _Line('Location', _text(r['location']) ?? '—'),
            if (when.isNotEmpty) _Line('Date and time', when),
          ],
        ),
        _Section(
          title: 'Details / Narrative / Cause',
          children: [
            _Line(
              null,
              _text(r['narrative']) ?? 'Nothing written.',
              plain: true,
            ),
          ],
        ),
        _Section(
          title: 'Casualties',
          children: [
            _casualtyGroup('Dead / Drowned', casualties['dead']),
            _casualtyGroup('Injured', casualties['injured']),
            _casualtyGroup('Missing', casualties['missing']),
          ],
        ),
        _Section(
          title: 'Effects',
          children: [
            _Line(null, _text(r['effects']) ?? 'None written.', plain: true),
          ],
        ),
        _Section(
          title: 'Action/s Taken',
          children: [
            _Line(
              null,
              _text(r['actions_taken']) ?? 'None written.',
              plain: true,
            ),
          ],
        ),
        if (team.isNotEmpty)
          _Section(
            title: 'Responding Team',
            children: [
              for (final member in team)
                if (member is Map) _teamMember(member),
            ],
          ),
        _Section(
          title: 'Report Released by',
          children: [_Line(null, _text(r['released_by']) ?? '—')],
        ),
        if (photoPath != null)
          _Section(title: 'Photo', children: [_photo(photoPath)]),

        // ── The PDF ──
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: pdfUrl == null || _openingPdf ? null : _openPdf,
            icon: _openingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, size: 20),
            label: const Text(
              'OPEN PDF',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _navy.withOpacity(0.4),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The same PDF MDRRMO sees, opened in your phone\'s PDF viewer.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  /// One casualty group: "Injured (1)" and a card per person.
  Widget _casualtyGroup(String title, dynamic rows) {
    final people = rows is List ? rows.whereType<Map>().toList() : <Map>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title (${people.length})',
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: _ink,
          ),
        ),
        const SizedBox(height: 6),
        if (people.isEmpty)
          Text('None', style: TextStyle(fontSize: 13, color: Colors.grey[600]))
        else
          for (final p in people) _person(p),
      ],
    );
  }

  Widget _person(Map p) {
    final String details = [
      if (_text(p['age']) != null) '${_text(p['age'])} yrs',
      if (_text(p['sex']) != null) _text(p['sex'])!,
      if (_text(p['address']) != null) _text(p['address'])!,
    ].join(' · ');
    final String? cause = _text(p['cause']);
    final String? remarks = _text(p['remarks']);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _text(p['name']) ?? 'Name not known',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _ink,
            ),
          ),
          if (details.isNotEmpty)
            Text(
              details,
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
            ),
          if (cause != null)
            Text(
              'Cause: $cause',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
            ),
          if (remarks != null)
            Text(
              'Remarks: $remarks',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
            ),
        ],
      ),
    );
  }

  /// "Juan Dela Cruz" / "Lead · BFP — Rosales Station · joined 9:38 AM".
  Widget _teamMember(Map m) {
    final String details = [
      _text(m['role']),
      _text(m['agency']),
      if (_text(m['joined']) != null) 'joined ${_text(m['joined'])}',
    ].whereType<String>().join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text(m['name']) ?? 'Responder',
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.bold,
            color: _ink,
          ),
        ),
        if (details.isNotEmpty)
          Text(
            details,
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
      ],
    );
  }

  /// The report's photo; tap it to see it full screen.
  Widget _photo(String path) {
    final url = _storageUrl(path);
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        barrierColor: Colors.black,
        builder: (ctx) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(child: Image.network(url, fit: BoxFit.contain)),
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
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Container(
            height: 120,
            color: const Color(0xFFF0F0F0),
            child: Icon(Icons.broken_image_outlined, color: Colors.grey[400]),
          ),
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String text,
    required String action,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
              ),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}

/// A part of the report in a light card, its name on top.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A label (optional) and its value.
class _Line extends StatelessWidget {
  final String? label;
  final String value;

  /// Regular weight, for longer text.
  final bool plain;

  const _Line(this.label, this.value, {this.plain = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
        ],
        Text(
          value,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: plain ? FontWeight.w500 : FontWeight.bold,
            color: _ink,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;

  const _Chip({required this.label, required this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }
}

/// A coloured note under the heading: sent back, for review, reviewed.
class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  const _Notice({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [value] as trimmed text, or null when it's missing or blank.
String? _text(dynamic value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

/// An API time as Manila wall-clock time, "10:16 AM - Oct 20, 2026" — by the
/// fixed UTC+8 offset, not the phone's time zone (same as Home's
/// _formatDateTime).
String _manila(dynamic iso) {
  final at = DateTime.tryParse((iso ?? '').toString())?.toUtc();
  if (at == null) return '';
  final t = at.add(const Duration(hours: 8));
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
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = t.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period - ${months[t.month - 1]} ${t.day}, ${t.year}';
}

/// A file on the server's public storage (the report photo).
String _storageUrl(String path) {
  final base = ApiService.baseUrl;
  final root = base.endsWith('/api')
      ? base.substring(0, base.length - 4)
      : base;
  return '$root/storage/$path';
}
