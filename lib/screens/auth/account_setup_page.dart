import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../patient/patient_home_page.dart';

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
  final _emergencyContactNumberController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    _dobController.dispose();
    _emergencyContactController.dispose();
    _emergencyContactNumberController.dispose();
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
              primary: Colors.brown.shade700,
              onPrimary: Colors.white,
              surface: const Color(0xFFF5E6D3),
              onSurface: Colors.brown.shade900,
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
        emergencyContactNumber: _emergencyContactNumberController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      if (mounted) {
        if (result['success']) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PatientHomePage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'])),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Setup failed: $e')),
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
      backgroundColor: const Color(0xFFF5E6D3),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Account Setup (Patient)',
          style: TextStyle(
            color: Colors.brown.shade800,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Help us set up your profile',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.brown.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This information will help your caretakers assist you better.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.brown.shade700,
                  ),
                ),

                const SizedBox(height: 30),

                // Phone Number
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number:',
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your phone number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Address
                _buildTextField(
                  controller: _addressController,
                  label: 'Address:',
                  maxLines: 2,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your address';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Date of Birth
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date of Birth:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.brown.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _dobController,
                      readOnly: true,
                      onTap: _selectDate,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select your date of birth';
                        }
                        return null;
                      },
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFE8C4C4),
                        suffixIcon: Icon(
                          Icons.calendar_today,
                          color: Colors.brown.shade700,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Emergency Contact Name
                _buildTextField(
                  controller: _emergencyContactController,
                  label: 'Emergency Contact:',
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter emergency contact name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Emergency Contact Number
                _buildTextField(
                  controller: _emergencyContactNumberController,
                  label: 'Emergency Contact Number:',
                  keyboardType: TextInputType.phone,
                  suffixIcon: IconButton(
                    icon: Icon(Icons.info_outline, color: Colors.blue.shade700),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Emergency Contact'),
                          content: const Text(
                            'This person will be called when you press the Emergency Help button.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Got it'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter emergency contact number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 40),

                // Continue Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A5A5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Skip for now
                Center(
                  child: TextButton(
                    onPressed: () {
                      // Navigate to home without completing setup
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You can complete this later in settings'),
                        ),
                      );
                    },
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        color: Colors.brown.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
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
    bool obscureText = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.brown.shade800,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFE8C4C4),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }
}