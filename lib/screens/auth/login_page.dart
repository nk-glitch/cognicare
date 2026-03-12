import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'signup_page.dart';
import 'account_setup_page.dart';
import '../patient/patient_home_page.dart';
import '../caretaker/caretaker_home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _emailFocused = false;
  bool _passwordFocused = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        if (result['success']) {
          // Success feedback
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Welcome back!',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              duration: Duration(seconds: 2),
            ),
          );

          String userType = result['userType'];
          String uid = result['uid'];

          // Small delay to show success message
          await Future.delayed(Duration(milliseconds: 500));

          // Navigate based on user type
          if (userType == 'patient') {
            // Check if setup is complete
            final patientData = await _authService.getPatientData(uid);
            bool setupComplete = patientData?['setupComplete'] ?? false;

            if (setupComplete) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const PatientHomePage()),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => AccountSetupPage(userId: uid)),
              );
            }
          } else {
            // Caretaker
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
                    'Login failed. Please try again.',
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

  Future<void> _handleForgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (context) => _ForgotPasswordDialog(),
    );

    if (email != null && email.isNotEmpty) {
      final result = await _authService.resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  result['success'] ? Icons.check_circle : Icons.error_outline,
                  color: Colors.white,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    result['message'],
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: result['success'] ? Colors.green.shade600 : Colors.orange.shade600,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4E4E1), // Solid background - no gradient
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo with strong visual presence
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4E4E1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFD4A5A5),
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 100,
                        height: 100,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.favorite,
                            size: 80,
                            color: const Color(0xFFD4A5A5),
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // App Name - High contrast
                  Text(
                    'CogniCare',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF5D4037), // Dark brown for contrast
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1.5,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Clear instruction
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFD4A5A5),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      'Please enter your details to sign in',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF5D4037),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Email Field - High contrast with clear instructions
                  _buildTextField(
                    controller: _emailController,
                    label: 'Your Email Address',
                    hint: 'example@email.com',
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                    isFocused: _emailFocused,
                    onFocusChange: (focused) {
                      setState(() => _emailFocused = focused);
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '⚠️ Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return '⚠️ Please enter a valid email address';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 28),

                  // Password Field - High contrast with clear instructions
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Your Password',
                    hint: 'Min 8 chars, upper, lower, number, special',
                    icon: Icons.lock,
                    obscureText: true,
                    isFocused: _passwordFocused,
                    onFocusChange: (focused) {
                      setState(() => _passwordFocused = focused);
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '⚠️ Please enter your password';
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

                  const SizedBox(height: 20),

                  // Forgot Password - Clear and accessible
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: TextButton(
                      onPressed: _handleForgotPassword,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.5),
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.help_outline,
                            color: const Color(0xFF5D4037),
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Forgot your password?',
                            style: TextStyle(
                              color: const Color(0xFF5D4037),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Login Button - High contrast, clear action
                  SizedBox(
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B8E23), // Olive green for "go"
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
                            'Signing in...',
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
                          Icon(Icons.login, size: 28),
                          SizedBox(width: 12),
                          Text(
                            'Sign In',
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

                  const SizedBox(height: 24),

                  // Divider with text
                  Row(
                    children: [
                      Expanded(child: Divider(color: Color(0xFF8D6E63), thickness: 2)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF5D4037),
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Color(0xFF8D6E63), thickness: 2)),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Sign Up Button - Different color for different action
                  SizedBox(
                    width: double.infinity,
                    height: 70,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SignUpPage()),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF5D4037),
                        backgroundColor: Colors.white,
                        side: const BorderSide(
                          color: Color(0xFF8D6E63),
                          width: 3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_add, size: 28),
                          SizedBox(width: 12),
                          Text(
                            'Create New Account',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    bool isFocused = false,
    required Function(bool) onFocusChange,
    String? Function(String?)? validator,
  }) {
    return Focus(
      onFocusChange: onFocusChange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label with icon - Very clear
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isFocused ? Color(0xFF6B8E23).withOpacity(0.2) : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFocused ? Color(0xFF6B8E23) : Color(0xFFD4A5A5),
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
                color: Color(0xFF212121), // Very dark for readability
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 20,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.normal,
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
                    color: const Color(0xFF6B8E23), // Green when active
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
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      backgroundColor: const Color(0xFFF4E4E1),
      title: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color(0xFFD4A5A5), width: 2),
        ),
        child: Row(
          children: [
            Icon(
              Icons.lock_reset,
              color: const Color(0xFF5D4037),
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reset Your Password',
                style: TextStyle(
                  color: Color(0xFF5D4037),
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
          ],
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade300, width: 2),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade700, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'We\'ll send a reset link to your email',
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your Email:',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5D4037),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(
              fontSize: 20,
              color: Color(0xFF212121),
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'example@email.com',
              hintStyle: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 18,
              ),
              prefixIcon: Icon(
                Icons.email,
                color: const Color(0xFF5D4037),
                size: 28,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: const Color(0xFF8D6E63),
                  width: 3,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: const Color(0xFF8D6E63),
                  width: 3,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: const Color(0xFF6B8E23),
                  width: 3,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            ),
          ),
        ],
      ),
      actions: [
        // Cancel button
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF5D4037),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.close, size: 22),
              SizedBox(width: 8),
              Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // Send button
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, _emailController.text.trim());
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6B8E23),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 16,
            ),
            elevation: 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.send, size: 22),
              SizedBox(width: 8),
              Text(
                'Send Reset Link',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}