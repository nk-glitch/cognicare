import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../patient/patient_home_page.dart';
import '../auth/signup_page.dart';

class AccountSetupPage extends StatefulWidget {
  final String userId;

  const AccountSetupPage({
    super.key,
    required this.userId,
  });

  @override
  State<AccountSetupPage> createState() => _AccountSetupPageState();
}

class _AccountSetupPageState extends State<AccountSetupPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _dobController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _animController,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _animController,
              curve: const Interval(0.1, 0.8, curve: Curves.easeOutCubic)),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    _dobController.dispose();
    _emergencyContactController.dispose();
    _animController.dispose();
    super.dispose();
  }

  int get _filledCount {
    int count = 0;
    if (_phoneController.text.isNotEmpty) count++;
    if (_addressController.text.isNotEmpty) count++;
    if (_dobController.text.isNotEmpty) count++;
    if (_emergencyContactController.text.isNotEmpty) count++;
    return count;
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1960),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF5A7A1A),
              onPrimary: Colors.white,
              surface: Color(0xFFFAF6F4),
              onSurface: Color(0xFF3E2723),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dobController.text =
        '${picked.month}/${picked.day}/${picked.year}';
      });
    }
  }

  void _showSnack(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ]),
        backgroundColor:
        success ? const Color(0xFF5A7A1A) : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: success ? 2 : 3),
      ),
    );
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final result = await _authService.updatePatientSetup(
        userId: widget.userId,
        address: _addressController.text.trim(),
        dateOfBirth: _dobController.text.trim(),
        emergencyContact: _emergencyContactController.text.trim(),
        emergencyContactNumber: '',
        phone: _phoneController.text.trim(),
      );

      if (mounted) {
        if (result['success']) {
          _showSnack('Profile setup complete!', success: true);
          await Future.delayed(const Duration(milliseconds: 500));
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PatientHomePage()),
          );
        } else {
          _showSnack(result['message']);
        }
      }
    } catch (_) {
      if (mounted) _showSnack('Setup failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F4),
      body: Stack(
        children: [
          // Decorative blobs — mirror the login page atmosphere
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE8C9C0).withOpacity(0.35),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6B8E23).withOpacity(0.08),
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    // ── App bar ─────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Row(
                        children: [
                          // Back button
                          GestureDetector(
                            onTap: () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SignUpPage()),
                            ),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFB07A6E)
                                        .withOpacity(0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Color(0xFF5D4037),
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Set Up Your Profile',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF3E2723),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // Progress bar
                                AnimatedBuilder(
                                  animation: _animController,
                                  builder: (_, __) => Row(
                                    children: List.generate(4, (i) {
                                      final filled = i < _filledCount;
                                      return Expanded(
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 300),
                                          height: 4,
                                          margin: EdgeInsets.only(
                                              right: i < 3 ? 4 : 0),
                                          decoration: BoxDecoration(
                                            color: filled
                                                ? const Color(0xFF5A7A1A)
                                                : const Color(0xFFD4A5A5)
                                                .withOpacity(0.3),
                                            borderRadius:
                                            BorderRadius.circular(2),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Step counter badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFB07A6E)
                                      .withOpacity(0.10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: AnimatedBuilder(
                              animation: _animController,
                              builder: (_, __) => Text(
                                '$_filledCount / 4',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF5A7A1A),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Scrollable body ────────────────────────────────
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Form(
                          key: _formKey,
                          onChanged: () => setState(() {}),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Info banner
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 13),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5A7A1A)
                                      .withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFF5A7A1A)
                                        .withOpacity(0.20),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    color: Color(0xFF5A7A1A),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'This helps your caretakers assist you better.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: const Color(0xFF5A7A1A)
                                            .withOpacity(0.9),
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ]),
                              ),

                              const SizedBox(height: 24),

                              // ── Form card ──────────────────────────────
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFB07A6E)
                                          .withOpacity(0.10),
                                      blurRadius: 40,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildField(
                                      controller: _phoneController,
                                      label: 'Phone number',
                                      hint: '(555) 123-4567',
                                      icon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Phone number is required'
                                          : null,
                                    ),
                                    const SizedBox(height: 20),
                                    _buildField(
                                      controller: _addressController,
                                      label: 'Home address',
                                      hint: '123 Main Street, City, State',
                                      icon: Icons.home_outlined,
                                      maxLines: 2,
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Address is required'
                                          : null,
                                    ),
                                    const SizedBox(height: 20),
                                    _buildDateField(),
                                    const SizedBox(height: 20),
                                    _buildField(
                                      controller: _emergencyContactController,
                                      label: 'Emergency contact name',
                                      hint: 'Family member or friend',
                                      icon: Icons.person_outline_rounded,
                                      validator: (v) => (v == null || v.isEmpty)
                                          ? 'Emergency contact is required'
                                          : null,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // ── CTA button ─────────────────────────────
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  onPressed:
                                  _isLoading ? null : _handleContinue,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF5A7A1A),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                    const Color(0xFF5A7A1A)
                                        .withOpacity(0.5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                      : const Text(
                                    'Complete Setup',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    int maxLines = 1,
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
            color: Color(0xFF5D4037),
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF2C2C2C),
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 15,
              color: Color(0xFFBDB0AC),
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Icon(icon, color: const Color(0xFFD4A5A5), size: 20),
            filled: true,
            fillColor: const Color(0xFFFAF6F4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Color(0xFFEDE5E2), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Color(0xFFEDE5E2), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Color(0xFF6B8E23), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade400, width: 2),
            ),
            errorStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.red.shade600,
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date of birth',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5D4037),
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: _dobController,
          readOnly: true,
          onTap: _selectDate,
          validator: (v) => (v == null || v.isEmpty)
              ? 'Date of birth is required'
              : null,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF2C2C2C),
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: 'Tap to select date',
            hintStyle: const TextStyle(
              fontSize: 15,
              color: Color(0xFFBDB0AC),
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: const Icon(
              Icons.cake_outlined,
              color: Color(0xFFD4A5A5),
              size: 20,
            ),
            suffixIcon: const Icon(
              Icons.calendar_today_outlined,
              color: Color(0xFFBDB0AC),
              size: 18,
            ),
            filled: true,
            fillColor: const Color(0xFFFAF6F4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Color(0xFFEDE5E2), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Color(0xFFEDE5E2), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Color(0xFF6B8E23), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade400, width: 2),
            ),
            errorStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.red.shade600,
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          ),
        ),
      ],
    );
  }
}