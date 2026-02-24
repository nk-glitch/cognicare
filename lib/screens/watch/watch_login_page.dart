import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class WatchLoginPage extends StatefulWidget {
  const WatchLoginPage({super.key});

  @override
  State<WatchLoginPage> createState() => _WatchLoginPageState();
}

class _WatchLoginPageState extends State<WatchLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Fill in all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        if (!result['success']) {
          setState(() {
            _errorMessage = 'Invalid credentials';
            _isLoading = false;
          });
        }
        // If success, WatchActiveFace's StreamBuilder will automatically
        // detect the auth change and navigate to WatchPatientScreen
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Login failed';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6D3),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Icon(Icons.favorite, color: Colors.brown.shade400, size: 24),
              const SizedBox(height: 4),
              Text(
                'CogniCare',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade800,
                  fontStyle: FontStyle.italic,
                ),
              ),

              const SizedBox(height: 10),

              // Email field
              _WatchTextField(
                controller: _emailController,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 6),

              // Password field
              _WatchTextField(
                controller: _passwordController,
                label: 'Password',
                obscureText: true,
              ),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 10),

              // Login button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A5A5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Compact text field sized for watch screens
class _WatchTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;

  const _WatchTextField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.brown.shade800,
          ),
        ),
        const SizedBox(height: 3),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 11),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFE8C4C4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            isDense: true,
          ),
        ),
      ],
    );
  }
}