import 'package:flutter/material.dart';
import 'package:cognicare/screens/caretaker_home_screen.dart';
import 'package:cognicare/screens/patient_landing_page.dart';
import 'package:cognicare/models/patient_model.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({Key? key}) : super(key: key);

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF5E6E8),
              Color(0xFFE8C4C8),
              Color(0xFFD4ADB1),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    _buildLogo(),
                    const SizedBox(height: 40),
                    _buildTitle(),
                    const SizedBox(height: 60),
                    _buildRoleButton(
                      icon: Icons.favorite,
                      label: 'Caretaker',
                      subtitle: 'Manage and support patients',
                      color: const Color(0xFF8FA9C9),
                      onTap: () => _navigateToCaretaker(context),
                    ),
                    const SizedBox(height: 20),
                    _buildRoleButton(
                      icon: Icons.person,
                      label: 'Patient',
                      subtitle: 'View your reminders and info',
                      color: const Color(0xFFD47A8A),
                      onTap: () => _navigateToPatient(context),
                    ),
                    const Spacer(),
                    const Text(
                      'Testing Mode',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7A6A70),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(
        Icons.medical_services_rounded,
        size: 50,
        color: Color(0xFF8FA9C9),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        const Text(
          'CogniCare',
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3D2C31),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Supporting Dementia Care',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF5A4046),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: color,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3D2C31),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF7A6A70),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_forward,
                    color: color,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToCaretaker(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CaretakerHomeScreen(),
      ),
    );
  }

  void _navigateToPatient(BuildContext context) {
    // Create a sample patient for testing
    final samplePatient = Patient(
      name: 'John Smith',
      location: 'Home',
      reminders: ['Hot Date 9:00 P.M.'],
      avatarColor: Colors.blue.shade300,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PatientLandingPage(
          patient: samplePatient,
          emergencyContactName: 'Sarah Smith - Daughter',
          emergencyContactPhone: '983-398-2830',
        ),
      ),
    );
  }
}
