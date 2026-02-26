import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';

class ProfilePage extends StatefulWidget {
  final bool isCaretaker;

  const ProfilePage({super.key, required this.isCaretaker});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthService _authService = AuthService();

  String userName = "Loading...";
  String? phone;
  String? address;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final userData = await _authService.getUserData(user.uid);
        if (userData != null) {
          setState(() {
            userName = '${userData['firstName']} ${userData['lastName']}';
            phone = userData['phone'];
          });
        }
        if (!widget.isCaretaker) {
          final patientData = await _authService.getPatientData(user.uid);
          if (patientData != null) {
            setState(() {
              address = patientData['address'];
            });
          }
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5E6E8),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5E6E8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildProfileCard(),
                    const SizedBox(height: 20),
                    _buildInfoCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Color(0xFF3D2C31)),
            style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.5), padding: const EdgeInsets.all(8)),
          ),
          const Text('Profile Page', style: TextStyle(fontSize: 16, color: Color(0xFF5A4046), fontWeight: FontWeight.w600)),
          Text(DateFormat('MMM dd, yyyy').format(DateTime.now()), style: const TextStyle(fontSize: 14, color: Color(0xFF5A4046), fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.favorite, color: Color(0xFFD47A8A), size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(userName, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF3D2C31))),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.person, size: 45, color: Color(0xFF8FA9C9)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFC09499), width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Info:', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF3D2C31))),
          const SizedBox(height: 20),
          _buildInfoRow('name:', userName),
          const SizedBox(height: 12),
          _buildInfoRow('phone:', phone ?? 'Not provided'),
          if (!widget.isCaretaker) ...[
            const SizedBox(height: 12),
            _buildInfoRow('address:', address ?? 'Not provided'),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF3D2C31))),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, color: Color(0xFF5A4046))),
      ],
    );
  }
}