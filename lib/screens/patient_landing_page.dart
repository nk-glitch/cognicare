import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/patient_model.dart';
import 'profile_page.dart';
import 'games_hub_page.dart';

class PatientLandingPage extends StatefulWidget {
  final Patient patient;
  final String emergencyContactName;
  final String emergencyContactPhone;

  const PatientLandingPage({
    Key? key,
    required this.patient,
    this.emergencyContactName = 'Sarah Smith - Daughter',
    this.emergencyContactPhone = '983-398-2830',
  }) : super(key: key);

  @override
  State<PatientLandingPage> createState() => _PatientLandingPageState();
}

class _PatientLandingPageState extends State<PatientLandingPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Sample data for what patient should be doing
  final String currentActivity = 'Getting money';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Landing Page (Patient)',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                _buildEmergencyButton(),
                const SizedBox(height: 20),
                _buildWelcomeCard(),
                const SizedBox(height: 20),
                _buildActivityCard(),
                const SizedBox(height: 20),
                _buildGamesButton(),
                const SizedBox(height: 20),
                _buildRemindersCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmergencyButton() {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: double.infinity,
        height: 80,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF4757), Color(0xFFFF6B7A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4757).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleEmergencyCall,
            borderRadius: BorderRadius.circular(20),
            child: const Center(
              child: Text(
                'Emergency',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfilePage(
                        isCaretaker: false,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(25),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 28,
                    color: Color(0xFF8FA9C9),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Welcome ${widget.patient.name}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3D2C31),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFD4ADB1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.home,
                  size: 22,
                  color: Color(0xFF3D2C31),
                ),
                SizedBox(width: 12),
                Text(
                  'You are Home',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3D2C31),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFD4ADB1), thickness: 1.5),
          const SizedBox(height: 12),
          const Text(
            'Emergency Contact',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D2C31),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.emergencyContactName,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF5A4046),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.phone,
                size: 18,
                color: Color(0xFF5A4046),
              ),
              const SizedBox(width: 6),
              Text(
                widget.emergencyContactPhone,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF5A4046),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8C4C8), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What you are supposed to be doing',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D2C31),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8C4C8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              currentActivity,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF3D2C31),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGamesButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF8FA9C9).withOpacity(0.7),
            const Color(0xFFD47A8A).withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GamesHubPage(
                  playerName: widget.patient.name,
                  isCaretaker: false,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.games,
                    size: 32,
                    color: Color(0xFF8FA9C9),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Play Games',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Connect and have fun!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRemindersCard() {
    // Get today's reminders
    final reminders = widget.patient.reminders;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8C4C8), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's reminders",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF3D2C31),
            ),
          ),
          const SizedBox(height: 16),
          if (reminders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5E6E8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No reminders for today',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF7A6A70),
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...reminders.map((reminder) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8C4C8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                reminder,
                style: const TextStyle(
                  fontSize: 18,
                  color: Color(0xFF3D2C31),
                  fontWeight: FontWeight.w600,
                ),
              ),
            )),
        ],
      ),
    );
  }

  void _handleEmergencyCall() async {
    // Remove any non-digit characters from the phone number
    final phoneNumber = widget.emergencyContactPhone.replaceAll(RegExp(r'[^\d]'), '');
    final uri = Uri(scheme: 'tel', path: phoneNumber);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          _showErrorDialog('Unable to make phone call');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error: ${e.toString()}');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Color(0xFFFF4757)),
            SizedBox(width: 12),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}