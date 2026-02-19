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

class _AccountSetupPageState extends State<AccountSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _dobController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  final int _totalSteps = 4;

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    _dobController.dispose();
    _emergencyContactController.dispose();
    super.dispose();
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
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF6B8E23),
              onPrimary: Colors.white,
              surface: const Color(0xFFF4E4E1),
              onSurface: const Color(0xFF5D4037),
            ),
            textTheme: TextTheme(
              headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              bodyLarge: TextStyle(fontSize: 18),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dobController.text = '${picked.month}/${picked.day}/${picked.year}';
      });
    }
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.updatePatientSetup(
        userId: widget.userId,
        address: _addressController.text.trim(),
        dateOfBirth: _dobController.text.trim(),
        emergencyContact: _emergencyContactController.text.trim(),
        emergencyContactNumber: '', // Not collected anymore
        phone: _phoneController.text.trim(),
      );

      if (mounted) {
        if (result['success']) {
          // Success feedback
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Profile setup complete!',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              duration: Duration(seconds: 2),
            ),
          );

          await Future.delayed(Duration(milliseconds: 500));

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PatientHomePage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      result['message'],
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red.shade600,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Setup failed. Please try again.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4E4E1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4E4E1),
        elevation: 0,
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(0xFF8D6E63), width: 2),
          ),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: Color(0xFF5D4037), size: 28),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SignUpPage()),
              );
            },
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set Up Your Profile',
              style: TextStyle(
                color: const Color(0xFF5D4037),
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            SizedBox(height: 4),
            // Progress indicator
            Row(
              children: List.generate(_totalSteps, (index) {
                bool isCompleted = false;
                if (index == 0 && _phoneController.text.isNotEmpty) isCompleted = true;
                if (index == 1 && _addressController.text.isNotEmpty) isCompleted = true;
                if (index == 2 && _dobController.text.isNotEmpty) isCompleted = true;
                if (index == 3 && _emergencyContactController.text.isNotEmpty) isCompleted = true;

                return Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(right: index < _totalSteps - 1 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: isCompleted ? Color(0xFF6B8E23) : Color(0xFFD4A5A5).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
        toolbarHeight: 80,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Information box
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade300, width: 3),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade700, size: 32),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This helps your caretakers assist you better',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Phone Number
                _buildTextField(
                  controller: _phoneController,
                  label: 'Your Phone Number',
                  icon: Icons.phone,
                  hint: '(555) 123-4567',
                  keyboardType: TextInputType.phone,
                  stepNumber: 1,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '⚠️ Please enter your phone number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 28),

                // Address
                _buildTextField(
                  controller: _addressController,
                  label: 'Your Home Address',
                  icon: Icons.home,
                  hint: '123 Main Street, City, State',
                  maxLines: 2,
                  stepNumber: 2,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '⚠️ Please enter your address';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 28),

                // Date of Birth
                _buildDateField(),

                const SizedBox(height: 28),

                // Emergency Contact Name
                _buildTextField(
                  controller: _emergencyContactController,
                  label: 'Emergency Contact Name',
                  icon: Icons.person,
                  hint: 'Family member or friend',
                  stepNumber: 4,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '⚠️ Please enter emergency contact name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 48),

                // Continue Button
                SizedBox(
                  width: double.infinity,
                  height: 70,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B8E23),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 6,
                      shadowColor: Colors.black.withOpacity(0.3),
                    ),
                    child: _isLoading
                        ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 28,
                          width: 28,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(width: 16),
                        Text(
                          'Saving...',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, size: 28),
                        SizedBox(width: 12),
                        Text(
                          'Complete Setup',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    required int stepNumber,
    bool obscureText = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with step number and icon
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Color(0xFFD4A5A5),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(0xFF6B8E23),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$stepNumber',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Icon(
                icon,
                color: const Color(0xFF5D4037),
                size: 26,
              ),
              SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF5D4037),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Text field with high contrast
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            maxLines: maxLines,
            validator: validator,
            style: const TextStyle(
              fontSize: 22,
              color: Color(0xFF212121),
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 20,
                color: Colors.grey.shade600,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: const Color(0xFF8D6E63),
                  width: 3,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: const Color(0xFF8D6E63),
                  width: 3,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: const Color(0xFF6B8E23),
                  width: 4,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.red.shade700,
                  width: 3,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.red.shade700,
                  width: 4,
                ),
              ),
              errorStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with step number and icon
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Color(0xFFD4A5A5),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(0xFF6B8E23),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '3',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Icon(
                Icons.cake,
                color: const Color(0xFF5D4037),
                size: 26,
              ),
              SizedBox(width: 10),
              Text(
                'Your Date of Birth',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF5D4037),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Date picker field
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: _dobController,
            readOnly: true,
            onTap: _selectDate,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '⚠️ Please select your date of birth';
              }
              return null;
            },
            style: const TextStyle(
              fontSize: 22,
              color: Color(0xFF212121),
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Tap to select date',
              hintStyle: TextStyle(
                fontSize: 20,
                color: Colors.grey.shade600,
              ),
              suffixIcon: Container(
                margin: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFF6B8E23),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: const Color(0xFF8D6E63),
                  width: 3,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: const Color(0xFF8D6E63),
                  width: 3,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: const Color(0xFF6B8E23),
                  width: 4,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.red.shade700,
                  width: 3,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.red.shade700,
                  width: 4,
                ),
              ),
              errorStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }
}