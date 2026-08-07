import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'responder_login.dart';
import 'verify_email.dart';

const Color _navy = Color(0xFF0D1B4C);
const Color _blue = Color(0xFF1857C4);

class ResponderRegisterScreen extends StatefulWidget {
  const ResponderRegisterScreen({super.key});

  @override
  State<ResponderRegisterScreen> createState() =>
      _ResponderRegisterScreenState();
}

class _ResponderRegisterScreenState extends State<ResponderRegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _suffixController = TextEditingController();
  final _badgeController = TextEditingController();
  final _unitController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _agency = 'SARS';
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  // True once the OTP has been verified — locks the fields and switches
  // the primary button into "confirm & create" mode.
  bool _otpVerified = false;

  static const List<Map<String, String>> _agencies = [
    {'value': 'SARS', 'label': 'SARS (Search and Rescue)'},
    {'value': 'PNP', 'label': 'PNP'},
    {'value': 'BFP', 'label': 'BFP'},
    {'value': 'HCU', 'label': 'Health Care Unit'},
    {'value': 'MSWD', 'label': 'MSWD'},
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _suffixController.dispose();
    _badgeController.dispose();
    _unitController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Step 1 — validates the form and requests the OTP. Pushes the OTP
  /// screen (doesn't replace this one — this screen stays on the stack
  /// so we can come back to it for the confirm step).
  Future<void> _handleSendCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await ApiService.responderRegister(
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      suffix: _suffixController.text.trim(),
      badgeNumber: _badgeController.text.trim(),
      agency: _agency,
      unitStation: _unitController.text.trim(),
      mobile: _mobileController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.success) {
      setState(() => _errorMessage = result.error);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Verification code sent! Check your email.'),
        backgroundColor: _navy,
      ),
    );

    final verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ResponderVerifyEmailScreen(email: _emailController.text.trim()),
      ),
    );

    if (!mounted) return;

    if (verified == true) {
      setState(() => _otpVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Email verified! Review your details below, then confirm to '
            'finish creating your account.',
          ),
          backgroundColor: Color(0xFF2E7D32),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  /// Step 3 — actually creates the account now that the email is
  /// verified and the person has reviewed their details.
  Future<void> _handleConfirmAccount() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await ApiService.responderConfirmRegistration(
      email: _emailController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created! Please log in.'),
          backgroundColor: _navy,
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ResponderLoginScreen()),
        (route) => false,
      );
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    final bool fieldsEnabled = !_otpVerified;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _navy, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Responder Registration',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_otpVerified) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E7D32)),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.check_circle,
                          color: Color(0xFF2E7D32),
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Email verified. Confirm your details below to finish.',
                            style: TextStyle(
                              color: Color(0xFF1B5E20),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                _field(
                  _firstNameController,
                  'First Name',
                  Icons.person_outline,
                  enabled: fieldsEnabled,
                ),
                const SizedBox(height: 14),
                _field(
                  _middleNameController,
                  'Middle Name (optional)',
                  Icons.person_outline,
                  required: false,
                  enabled: fieldsEnabled,
                ),
                const SizedBox(height: 14),
                _field(
                  _lastNameController,
                  'Last Name',
                  Icons.person_outline,
                  enabled: fieldsEnabled,
                ),
                const SizedBox(height: 14),
                _field(
                  _suffixController,
                  'Suffix (optional)',
                  Icons.badge_outlined,
                  required: false,
                  enabled: fieldsEnabled,
                ),
                const SizedBox(height: 14),

                _field(
                  _badgeController,
                  'Badge Number',
                  Icons.badge_outlined,
                  enabled: fieldsEnabled,
                ),
                const SizedBox(height: 14),

                const Text(
                  'Agency',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF444466),
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _agency,
                  onChanged: fieldsEnabled
                      ? (v) => setState(() => _agency = v ?? 'SARS')
                      : null,
                  isExpanded: true,
                  decoration: _decoration(
                    'Select agency',
                    Icons.local_police_outlined,
                  ),
                  items: _agencies
                      .map(
                        (a) => DropdownMenuItem(
                          value: a['value'],
                          child: Text(a['label']!),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 14),

                _field(
                  _unitController,
                  'Unit / Station',
                  Icons.location_city_outlined,
                  required: false,
                  enabled: fieldsEnabled,
                ),
                const SizedBox(height: 14),

                _field(
                  _mobileController,
                  'Mobile Number',
                  Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  required: false,
                  enabled: fieldsEnabled,
                ),
                const SizedBox(height: 14),

                _field(
                  _emailController,
                  'Email',
                  Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: fieldsEnabled,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!RegExp(
                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                    ).hasMatch(v)) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: fieldsEnabled,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1A1A2E),
                  ),
                  decoration: _decoration(
                    'Create a password',
                    Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.grey[500],
                        size: 22,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (v.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : (_otpVerified
                              ? _handleConfirmAccount
                              : _handleSendCode),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _otpVerified
                          ? const Color(0xFF2E7D32)
                          : _navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 3,
                      shadowColor: _navy.withOpacity(0.4),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            _otpVerified
                                ? 'CONFIRM & CREATE ACCOUNT'
                                : 'CREATE ACCOUNT',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    bool required = true,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF444466),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          enabled: enabled,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E)),
          decoration: _decoration(label, icon),
          validator:
              validator ??
              (v) {
                if (!required) return null;
                return (v == null || v.trim().isEmpty)
                    ? '$label is required'
                    : null;
              },
        ),
      ],
    );
  }

  InputDecoration _decoration(
    String hint,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8F9FF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _blue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }
}
