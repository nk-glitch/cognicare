import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'patient_detail_screen.dart';
import '../models/patient_model.dart';
import 'profile_page.dart';

class CaretakerHomeScreen extends StatefulWidget {
  const CaretakerHomeScreen({Key? key}) : super(key: key);

  @override
  State<CaretakerHomeScreen> createState() => _CaretakerHomeScreenState();
}

class _CaretakerHomeScreenState extends State<CaretakerHomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Sample data - replace with your actual data source
  final String caretakerName = "David Libungo";
  final List<Patient> patients = [
    Patient(
      name: "John Smith",
      location: "123 Main Street, Springfield",
      reminders: ["Take medication at 2 PM", "Doctor appointment at 4 PM"],
      avatarColor: Colors.blue.shade300,
    ),
    Patient(
      name: "Mary Johnson",
      location: "456 Oak Avenue, Springfield",
      reminders: ["Lunch at 12 PM", "Physical therapy at 3 PM"],
      avatarColor: Colors.purple.shade300,
    ),
  ];

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
      backgroundColor: const Color(0xFFF5E6E8),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _buildPatientList(),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _buildAddPatientFAB(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM dd, yyyy').format(DateTime.now()),
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF5A4046),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.favorite,
                  color: Color(0xFFD47A8A),
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3D2C31),
                        height: 1.2,
                      ),
                    ),
                    Text(
                      caretakerName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5A4046),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfilePage(
                        isCaretaker: true,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(35),
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 40,
                    color: Color(0xFF8FA9C9),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people,
                  size: 18,
                  color: Color(0xFF5A4046),
                ),
                const SizedBox(width: 8),
                Text(
                  '${patients.length} ${patients.length == 1 ? 'Patient' : 'Patients'} Under Care',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A4046),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: patients.length,
      itemBuilder: (context, index) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + (index * 100)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: _buildPatientCard(patients[index]),
        );
      },
    );
  }

  Widget _buildPatientCard(Patient patient) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Navigate to patient details
            _showPatientDetails(patient);
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Hero(
                      tag: 'patient_avatar_${patient.name}',
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: patient.avatarColor,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            patient.name.split(' ').map((n) => n[0]).join(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3D2C31),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 16,
                                color: Color(0xFF8FA9C9),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  patient.location,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF7A6A70),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5E6E8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF8FA9C9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8C4C8).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.notifications_active,
                        size: 18,
                        color: Color(0xFFD47A8A),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      "Today's Reminders:",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3D2C31),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (patient.reminders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5E6E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: Color(0xFF8FA9C9),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'No reminders scheduled',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF7A6A70),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...patient.reminders.map((reminder) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5E6E8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE8C4C8),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD47A8A),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            reminder,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF5A4046),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddPatientFAB() {
    return FloatingActionButton.extended(
      onPressed: () {
        // Add patient logic
        _showAddPatientDialog();
      },
      backgroundColor: const Color(0xFF8FA9C9),
      elevation: 8,
      icon: const Icon(Icons.person_add, color: Colors.white),
      label: const Text(
        'Add Patient',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  void _showPatientDetails(Patient patient) {
    // Navigate to patient detail screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PatientDetailScreen(patient: patient),
      ),
    );
  }

  void _showAddPatientDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Patient'),
        content: const Text('Add patient functionality will be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}