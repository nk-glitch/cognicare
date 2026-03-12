import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'account_setup_page.dart';
import '../caretaker/caretaker_home_page.dart';
import 'login_page.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  String _userType = 'patient'; // 'patient' or 'caretaker'
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        userType: _userType,
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
                      'Account created successfully!',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              duration: Duration(seconds: 2),
            ),
          );

          String uid = result['uid'];
          String userType = result['userType'];

          await Future.delayed(Duration(milliseconds: 500));

          // Navigate based on user type
          if (userType == 'patient') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => AccountSetupPage(userId: uid),
              ),
            );
          } else {
            // Caretaker goes directly to home
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const CaretakerHomePage()),
            );
          }
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
                    'Sign up failed. Please try again.',
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
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
          ),
        ),
        title: Text(
          'Create New Account',
          style: TextStyle(
            color: const Color(0xFF5D4037),
            fontWeight: FontWeight.bold,
            fontSize: 24,
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
                          'Fill in your information to get started',
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
                  label: 'Phone Number',
                  icon: Icons.phone,
                  hint: '(555) 123-4567',
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '⚠️ Please enter your phone number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // First Name
                _buildTextField(
                  controller: _firstNameController,
                  label: 'First Name',
                  icon: Icons.person,
                  hint: 'John',
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '⚠️ Please enter your first name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Last Name
                _buildTextField(
                  controller: _lastNameController,
                  label: 'Last Name',
                  icon: Icons.person_outline,
                  hint: 'Smith',
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '⚠️ Please enter your last name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Email
                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  icon: Icons.email,
                  hint: 'example@email.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '⚠️ Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return '⚠️ Please enter a valid email';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Password
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  icon: Icons.lock,
                  hint: 'Min 8 chars, upper, lower, number, special',
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '⚠️ Please enter a password';
                    }
                    final password = value;
                    if (password.length < 8) {
                      return '⚠️ Password must be at least 8 characters';
                    }
                    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
                    final hasLower = RegExp(r'[a-z]').hasMatch(password);
                    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
                    final hasSpecial = RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(password);
                    if (!hasUpper ||
                        !hasLower ||
                        !hasDigit ||
                        !hasSpecial) {
                      return '⚠️ Must include upper, lower, number, and special character';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Confirm Password
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: 'Confirm Password',
                  icon: Icons.lock_outline,
                  hint: 'Type password again',
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '⚠️ Please confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return '⚠️ Passwords do not match';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // User Type Selection Header
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
                      Icon(
                        Icons.person_pin,
                        color: const Color(0xFF5D4037),
                        size: 26,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'I am a...',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF5D4037),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // User Type Selection
                Row(
                  children: [
                    Expanded(
                      child: _buildUserTypeOption('Patient', 'patient', Icons.personal_injury),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildUserTypeOption('Caretaker', 'caretaker', Icons.medical_services),
                    ),
                  ],
                ),

                const SizedBox(height: 48),

                // Sign Up Button
                SizedBox(
                  width: double.infinity,
                  height: 70,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignUp,
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
                          'Creating Account...',
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
                        Icon(Icons.person_add, size: 28),
                        SizedBox(width: 12),
                        Text(
                          'Create Account',
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
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label with icon
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

  Widget _buildUserTypeOption(String label, String value, IconData icon) {
    final isSelected = _userType == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _userType = value),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 100,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6B8E23) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF5D4037) : const Color(0xFF8D6E63),
              width: isSelected ? 4 : 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isSelected ? 0.2 : 0.1),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : const Color(0xFF5D4037),
                size: 32,
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (BuildContext context) {
                  return DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF5D4037),
                      decoration: TextDecoration.none,
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(boldText: false),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : const Color(0xFF5D4037),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}