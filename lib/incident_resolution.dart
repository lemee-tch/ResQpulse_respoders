import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';

const Color _navy = Color(0xFF0D1B4C);
const Color _green = Color(0xFF2E9E4F);
const Color _ink = Color(0xFF1A1A2E);
const Color _amber = Color(0xFFB45309);

/// One casualty row of the MDRRMC Incident Report (Dead / Injured / Missing).
class _Casualty {
  final name = TextEditingController();
  final age = TextEditingController();
  final address = TextEditingController();
  final cause = TextEditingController();
  final remarks = TextEditingController();
  String? sex;

  _Casualty();

  /// A row from a report that was already filed.
  factory _Casualty.fromJson(dynamic row) {
    final c = _Casualty();
    if (row is Map) {
      c.name.text = (row['name'] ?? '').toString();
      c.age.text = (row['age'] ?? '').toString();
      c.address.text = (row['address'] ?? '').toString();
      c.cause.text = (row['cause'] ?? '').toString();
      c.remarks.text = (row['remarks'] ?? '').toString();
      final sex = (row['sex'] ?? '').toString().toUpperCase();
      c.sex = (sex == 'M' || sex == 'F') ? sex : null;
    }
    return c;
  }

  void dispose() {
    name.dispose();
    age.dispose();
    address.dispose();
    cause.dispose();
    remarks.dispose();
  }

  Map<String, String> toJson() => {
    'name': name.text.trim(),
    'age': age.text.trim(),
    'sex': sex ?? '',
    'address': address.text.trim(),
    'cause': cause.text.trim(),
    'remarks': remarks.text.trim(),
  };

  bool get isEmpty =>
      name.text.trim().isEmpty &&
      age.text.trim().isEmpty &&
      address.text.trim().isEmpty &&
      cause.text.trim().isEmpty &&
      remarks.text.trim().isEmpty;
}

/// The MDRRMC Incident Report (same format as the official paper form),
/// opened from "Submit Report" / "Update Report" on Incident Details and
/// from the Navigation screen. The server turns it into a PDF that the
/// admin sees on the incident's detail page. Submits to
/// POST /api/responder/incidents/{id}/resolve (see
/// Api\IncidentController::resolve()).
///
/// Report Type:
///   Initial  saved, and the incident stays open. The responder can come
///            back and update it as details come in (casualty status,
///            actions taken, ...).
///   Final    saved, and sent to MDRRMO for review (Incidents → For
///            Review). MDRRMO marks the incident resolved, or sends the
///            report back with what to fix — it then opens here as Initial
///            again, with MDRRMO's reason on top. While MDRRMO has it, the
///            report can't be changed — the app asks for confirmation first.
///
/// When the screen opens it loads the report already filed for this
/// incident (GET /api/responder/incidents/{id}/report), so an Initial
/// report opens with everything filled in, including its photo.
///
/// Incident type, location, date, day and time are filled in by the server
/// from the incident itself, so the responder doesn't retype them.
class IncidentResolutionScreen extends StatefulWidget {
  final int? incidentId;
  final String? incidentLabel;

  const IncidentResolutionScreen({
    super.key,
    this.incidentId,
    this.incidentLabel,
  });

  @override
  State<IncidentResolutionScreen> createState() =>
      _IncidentResolutionScreenState();
}

class _IncidentResolutionScreenState extends State<IncidentResolutionScreen> {
  static const int _maxNarrative = 2000;

  String _reportType = 'final'; // initial | final
  final _narrative = TextEditingController();
  final _effects = TextEditingController();
  final _actions = TextEditingController();
  final _releasedBy = TextEditingController();

  final List<_Casualty> _dead = [];
  final List<_Casualty> _injured = [];
  final List<_Casualty> _missing = [];

  File? _photo;
  bool _isSubmitting = false;

  // ── The report already filed (an Initial report being updated) ──────
  bool _isLoading = true;
  String? _loadError;
  bool _hasSavedReport = false;

  /// A Final report was already submitted — nothing left to edit.
  bool _isLocked = false;
  String? _lockedMessage;

  /// An admin already closed the incident (the report can still be
  /// updated and finalized).
  bool _incidentResolved = false;

  /// The Final report is with MDRRMO for review (status for_review).
  bool _underReview = false;

  /// MDRRMO sent the Final report back: what to fix, and when.
  String? _returnedReason;
  DateTime? _returnedAtUtc;

  /// Photo already on the saved report (path on the server's storage).
  String? _savedPhotoPath;
  bool _removeSavedPhoto = false;

  /// When the saved report was last submitted, and how many times.
  DateTime? _savedAtUtc;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _narrative.addListener(() => setState(() {}));
    _loadSavedReport();
  }

  /// Loads the report already filed for this incident, if any.
  Future<void> _loadSavedReport() async {
    final incidentId = widget.incidentId;
    if (incidentId == null) {
      setState(() => _isLoading = false);
      _prefillReleasedBy();
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final result = await ApiService.getIncidentReport(incidentId);
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isLoading = false;
        _loadError = result.error ?? 'Could not load the report.';
      });
      return;
    }

    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : <String, dynamic>{};
    final report = data['report'] is Map
        ? Map<String, dynamic>.from(data['report'] as Map)
        : null;

    setState(() {
      _isLoading = false;
      _isLocked = data['is_final'] == true || data['can_edit'] == false;
      _lockedMessage = data['message']?.toString();
      _incidentResolved = data['incident_status'] == 'resolved';
      _underReview =
          data['under_review'] == true ||
          data['incident_status'] == 'for_review';
      final returned = (data['returned_reason'] ?? '').toString().trim();
      _returnedReason = returned.isEmpty ? null : returned;
      _returnedAtUtc = DateTime.tryParse(
        (data['returned_at'] ?? '').toString(),
      )?.toUtc();
      _savedPhotoPath = (data['photo_path'] ?? '').toString().isEmpty
          ? null
          : data['photo_path'].toString();
      if (report != null) _fillFrom(report);
    });

    if (report == null) _prefillReleasedBy();
  }

  /// Puts a saved report back into the form.
  void _fillFrom(Map<String, dynamic> r) {
    _hasSavedReport = true;
    _reportType = r['report_type'] == 'initial' ? 'initial' : 'final';
    _narrative.text = (r['narrative'] ?? '').toString();
    _effects.text = (r['effects'] ?? '').toString();
    _actions.text = (r['actions_taken'] ?? '').toString();
    _releasedBy.text = (r['released_by'] ?? '').toString();

    final casualties = r['casualties'] is Map
        ? r['casualties'] as Map
        : const <String, dynamic>{};
    _fillCasualties(_dead, casualties['dead']);
    _fillCasualties(_injured, casualties['injured']);
    _fillCasualties(_missing, casualties['missing']);

    _revision = int.tryParse('${r['revision'] ?? ''}') ?? 1;
    _savedAtUtc = DateTime.tryParse(
      (r['updated_at'] ?? r['filed_at'] ?? '').toString(),
    )?.toUtc();
  }

  void _fillCasualties(List<_Casualty> list, dynamic rows) {
    for (final c in list) {
      c.dispose();
    }
    list.clear();
    if (rows is List) {
      for (final row in rows) {
        list.add(_Casualty.fromJson(row));
      }
    }
  }

  /// "Report Released by" = who is filing it — pre-filled from the logged-in
  /// responder's profile, still editable. Only for a new report: an
  /// update keeps what was saved.
  Future<void> _prefillReleasedBy() async {
    final r = await ApiService.getResponder();
    if (r == null || !mounted) return;
    final parts = <String>[
      (r['full_name'] ?? '').toString().toUpperCase(),
      (r['unit_station'] ?? '').toString(),
      (r['agency'] ?? '').toString(),
    ].where((p) => p.trim().isNotEmpty).toList();
    if (_releasedBy.text.isEmpty) {
      _releasedBy.text = parts.join(', ');
    }
  }

  @override
  void dispose() {
    _narrative.dispose();
    _effects.dispose();
    _actions.dispose();
    _releasedBy.dispose();
    for (final c in [..._dead, ..._injured, ..._missing]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Photo ────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
      );
      if (picked != null) setState(() => _photo = File(picked.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upload Photo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 16),
              _sheetTile(
                Icons.camera_alt_outlined,
                'Take a Photo',
                'Open camera',
                () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              _sheetTile(
                Icons.photo_library_outlined,
                'Choose from Gallery',
                'Pick from your photos',
                () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _navy.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _navy),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  /// The saved photo is shown until the responder removes or replaces it.
  bool get _showsSavedPhoto =>
      _photo == null && _savedPhotoPath != null && !_removeSavedPhoto;

  // ── Submit ───────────────────────────────────────────────────────

  void _snack(String msg, {Color color = Colors.redAccent}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Map<String, dynamic> _buildReport() {
    List<Map<String, String>> rows(List<_Casualty> l) =>
        l.where((c) => !c.isEmpty).map((c) => c.toJson()).toList();

    return {
      'report_type': _reportType,
      'narrative': _narrative.text.trim(),
      'casualties': {
        'dead': rows(_dead),
        'injured': rows(_injured),
        'missing': rows(_missing),
      },
      'effects': _effects.text.trim(),
      'actions_taken': _actions.text.trim(),
      'released_by': _releasedBy.text.trim(),
    };
  }

  /// A Final report can't be changed afterwards, so it's confirmed first.
  Future<bool> _confirmFinal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Submit the Final report?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          _incidentResolved
              ? 'After this, the report can no longer be changed.'
              : 'It goes to MDRRMO for review, and they mark the incident '
                    'resolved. You can\'t change it unless MDRRMO sends it '
                    'back to you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Submit Final',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _submit() async {
    final incidentId = widget.incidentId;

    if (incidentId == null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    if (_narrative.text.trim().isEmpty) {
      _snack('Please describe what happened in the narrative.');
      return;
    }

    final bool isFinal = _reportType == 'final';
    if (isFinal && !await _confirmFinal()) return;
    if (!mounted) return;

    setState(() => _isSubmitting = true);

    final result = await ApiService.submitIncidentReport(
      incidentId,
      photo: _photo,
      removePhoto:
          _photo == null && _removeSavedPhoto && _savedPhotoPath != null,
      report: _buildReport(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!result.success) {
      _snack(result.error ?? 'Could not submit the report.');
      return;
    }

    final data = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : <String, dynamic>{};
    final String serverMessage = (data['message'] ?? '').toString();

    if (isFinal) {
      _snack(
        serverMessage.isNotEmpty
            ? serverMessage
            : 'Final report submitted. MDRRMO will review it, then mark '
                  'the incident resolved.',
        color: _green,
      );
      // Pop everything back to Home (past Navigation + Incident Detail).
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    _snack(
      serverMessage.isNotEmpty
          ? serverMessage
          : 'Initial report saved. You can update it until you submit the '
                'Final report.',
      color: _green,
    );
    // Back to where the form was opened from; the incident is still open.
    // The updated incident goes back so Incident Details can show
    // "Update Report".
    Navigator.of(context).pop(
      data['incident'] is Map
          ? Map<String, dynamic>.from(data['incident'] as Map)
          : null,
    );
  }

  // ── UI helpers ───────────────────────────────────────────────────

  static const _months = [
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

  /// Manila time (UTC+8), whatever the phone's own time zone is set to —
  /// same approach as the rest of the app.
  static String _formatManila(DateTime utc) {
    final m = utc.add(const Duration(hours: 8));
    final hour12 = m.hour % 12 == 0 ? 12 : m.hour % 12;
    final minute = m.minute.toString().padLeft(2, '0');
    final period = m.hour >= 12 ? 'PM' : 'AM';
    return '${_months[m.month - 1]} ${m.day}, $hour12:$minute $period';
  }

  String get _submitLabel {
    if (_reportType == 'final') return 'SUBMIT FINAL REPORT';
    return _hasSavedReport ? 'UPDATE INITIAL REPORT' : 'SUBMIT INITIAL REPORT';
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.all(12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _navy, width: 1.6),
    ),
  );

  Widget _label(String text, {String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: _ink,
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 6),
          Text(hint, style: TextStyle(fontSize: 12.5, color: Colors.grey[500])),
        ],
      ],
    ),
  );

  Widget _textBox(
    TextEditingController c,
    String hint, {
    int lines = 3,
    int max = 1000,
  }) {
    return TextField(
      controller: c,
      maxLines: lines,
      maxLength: max,
      textCapitalization: TextCapitalization.sentences,
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) =>
              null,
      style: const TextStyle(fontSize: 14, color: _ink),
      decoration: _decoration(hint),
    );
  }

  Widget _typeChip(String value, String label) {
    final selected = _reportType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: _navy,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? _navy : Colors.grey[300]!),
      labelStyle: TextStyle(
        color: selected ? Colors.white : _ink,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      onSelected: (_) => setState(() => _reportType = value),
    );
  }

  Widget _casualtySection(String title, List<_Casualty> list) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _ink,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => list.add(_Casualty())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(foregroundColor: _navy),
              ),
            ],
          ),
          if (list.isEmpty)
            Text(
              'None',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          for (int i = 0; i < list.length; i++) _casualtyCard(list, i),
        ],
      ),
    );
  }

  Widget _casualtyCard(List<_Casualty> list, int i) {
    final c = list[i];
    Widget small(TextEditingController ctl, String hint, {TextInputType? kb}) =>
        TextField(
          controller: ctl,
          keyboardType: kb,
          style: const TextStyle(fontSize: 13.5, color: _ink),
          decoration: _decoration(hint),
        );

    return Container(
      // A key per row object, so removing a row keeps the others' fields.
      key: ObjectKey(c),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '#${i + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => setState(() {
                  list.removeAt(i).dispose();
                }),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          small(c.name, 'Full name'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: c.age,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  style: const TextStyle(fontSize: 13.5, color: _ink),
                  decoration: _decoration('Age'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: c.sex,
                  isDense: true,
                  decoration: _decoration('Sex'),
                  items: const [
                    DropdownMenuItem(value: 'M', child: Text('M')),
                    DropdownMenuItem(value: 'F', child: Text('F')),
                  ],
                  onChanged: (v) => setState(() => c.sex = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          small(c.address, 'Address'),
          const SizedBox(height: 8),
          small(c.cause, 'Cause (e.g. side sweep, drowning)'),
          const SizedBox(height: 8),
          small(c.remarks, 'Remarks (disposition of casualty)'),
        ],
      ),
    );
  }

  /// Shown at the top while an Initial report is being updated.
  Widget _updatingBanner() {
    final String when = _savedAtUtc != null
        ? ' Last saved ${_formatManila(_savedAtUtc!)}'
              '${_revision > 1 ? ' (updated ${_revision - 1}×)' : ''}.'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB300)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.edit_note, color: _amber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You\'re updating the Initial report.$when '
              'Submit it as Final once everything is in'
              '${_incidentResolved ? '.' : ' — MDRRMO then reviews it.'}',
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF5D4037),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown at the top when MDRRMO sent the Final report back.
  Widget _returnedBanner() {
    final String when = _returnedAtUtc != null
        ? ' (${_formatManila(_returnedAtUtc!)})'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFB8C00)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.assignment_return_outlined,
            color: Color(0xFFE65100),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MDRRMO sent your report back$when',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFBF360C),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _returnedReason!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF5D4037),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Fix it, then submit it as Final again.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5D4037),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Loading / couldn't load / already Final — instead of the form.
  Widget _statusView({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    String? buttonLabel,
    VoidCallback? onPressed,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
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
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onPressed,
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
                child: Text(buttonLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoBox() {
    Widget removeButton(VoidCallback onTap) => Positioned(
      top: 6,
      right: 6,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 16),
        ),
      ),
    );

    Widget child;
    if (_photo != null) {
      // A new photo; removing it shows the saved one again (if any).
      child = Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(_photo!, fit: BoxFit.cover),
          ),
          removeButton(() => setState(() => _photo = null)),
        ],
      );
    } else if (_showsSavedPhoto) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              ApiService.storageUrl(_savedPhotoPath!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.grey[400],
                  size: 34,
                ),
              ),
            ),
          ),
          removeButton(() => setState(() => _removeSavedPhoto = true)),
        ],
      );
    } else {
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt_outlined, size: 34, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            'Add Image',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: (_photo == null && !_showsSavedPhoto)
          ? _showImageSourceSheet
          : null,
      child: Container(
        width: double.infinity,
        height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrativeLength = _narrative.text.length;

    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_loadError != null) {
      body = _statusView(
        icon: Icons.cloud_off_outlined,
        color: Colors.grey[400]!,
        title: 'Couldn\'t open the report',
        message: _loadError!,
        buttonLabel: 'Try Again',
        onPressed: _loadSavedReport,
      );
    } else if (_isLocked) {
      body = _statusView(
        icon: _underReview
            ? Icons.hourglass_top_rounded
            : Icons.verified_outlined,
        color: _underReview ? const Color(0xFF6D28D9) : _green,
        title: _underReview
            ? 'With MDRRMO for review'
            : (_hasSavedReport ? 'Final report submitted' : 'Incident closed'),
        message:
            _lockedMessage ??
            'The final report for this incident was already submitted and '
                'can no longer be changed.',
        buttonLabel: 'Back',
        onPressed: () => Navigator.pop(context),
      );
    } else {
      body = _buildForm(narrativeLength);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _ink),
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

  Widget _buildForm(int narrativeLength) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Heading ──
          Center(
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: _hasSavedReport ? _amber : _green,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _hasSavedReport ? Icons.edit_note : Icons.check,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'MDRRMC Incident Report',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Submit it as Initial to keep updating it, or as Final to '
                  'send it to MDRRMO for review. A PDF copy goes to the '
                  'MDRRMO admin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                if (widget.incidentLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.incidentLabel!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_returnedReason != null) _returnedBanner(),
          if (_hasSavedReport) _updatingBanner(),

          // ── Report type ──
          _label('Report Type'),
          Wrap(
            spacing: 8,
            children: [
              _typeChip('initial', 'Initial'),
              _typeChip('final', 'Final'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _reportType == 'initial'
                ? 'The incident stays open. You can update this report as '
                      'details come in, until you submit it as Final.'
                : (_incidentResolved
                      ? 'The report can no longer be changed after this.'
                      : 'Goes to MDRRMO for review. You can\'t change it '
                            'unless MDRRMO sends it back.'),
            style: TextStyle(
              fontSize: 12.5,
              color: _reportType == 'initial' ? _amber : Colors.grey[600],
              height: 1.35,
            ),
          ),

          const SizedBox(height: 20),

          // ── Narrative ──
          _label('Details / Narrative / Cause', hint: '(required)'),
          _textBox(
            _narrative,
            'What happened, who responded, and when (e.g. times dispatched / arrived)...',
            lines: 6,
            max: _maxNarrative,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$narrativeLength/$_maxNarrative',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Casualties ──
          _label('Casualties', hint: '(leave empty if none)'),
          _casualtySection('A. Dead / Drowned', _dead),
          _casualtySection('B. Injured', _injured),
          _casualtySection('C. Missing', _missing),

          const SizedBox(height: 8),

          // ── Effects / Actions ──
          _label('Effects', hint: '(optional)'),
          _textBox(_effects, 'e.g. Minor abrasion, road blocked...', lines: 3),

          const SizedBox(height: 16),

          _label("Action/s Taken", hint: '(optional)'),
          _textBox(
            _actions,
            'What the team did on scene...',
            lines: 4,
            max: 1500,
          ),

          const SizedBox(height: 16),

          _label('Report Released by'),
          TextField(
            controller: _releasedBy,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 14, color: _ink),
            decoration: _decoration('Name, designation, office/agency'),
          ),

          const SizedBox(height: 20),

          // ── Photo ──
          Row(
            children: [
              const Text(
                'Upload Photo ',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: _ink,
                ),
              ),
              Text(
                '(Optional – added to the PDF)',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _photoBox(),

          const SizedBox(height: 32),

          // ── Submit ──
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                elevation: 2,
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
                      _submitLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
