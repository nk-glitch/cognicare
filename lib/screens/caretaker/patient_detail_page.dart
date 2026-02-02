import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PatientDetailPage extends StatefulWidget {
  final String patientId;
  final String patientName;

  const PatientDetailPage({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _selectedNavIndex = 2;
  Map<String, dynamic>? _patientData;
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadPatientData();
  }

  Future<void> _loadPatientData() async {
    try {
      // Load patient data
      final patientDoc = await _firestore
          .collection('patients')
          .doc(widget.patientId)
          .get();

      if (patientDoc.exists) {
        setState(() {
          _patientData = patientDoc.data();
        });
      }

      // Load reminders for this patient
      final remindersSnapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .orderBy('time')
          .get();

      setState(() {
        _reminders = remindersSnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading patient data: $e');
      setState(() {
        _isLoading = false;
      });
    }
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
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildPatientInfoCard(),
                    const SizedBox(height: 20),
                    _buildActionGrid(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Color(0xFF3D2C31)),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.5),
              padding: const EdgeInsets.all(8),
            ),
          ),
          Text(
            DateFormat('MMMM dd, yyyy').format(DateTime.now()),
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF5A4046),
              fontWeight: FontWeight.w600,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
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
    );
  }

  Widget _buildPatientInfoCard() {
    final location = _patientData?['address'] ?? 'No location set';
    final todaysReminders = _reminders.where((reminder) {
      final reminderDate = (reminder['time'] as Timestamp?)?.toDate();
      final today = DateTime.now();
      return reminderDate != null &&
          reminderDate.year == today.year &&
          reminderDate.month == today.month &&
          reminderDate.day == today.day;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.patientName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3D2C31),
                    ),
                  ),
                ),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 32,
                    color: Color(0xFF8FA9C9),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFD4ADB1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFC09499),
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Patient: ${widget.patientName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3D2C31),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current location: $location',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF5A4046),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Today's Reminders:",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3D2C31),
                  ),
                ),
                const SizedBox(height: 12),
                if (todaysReminders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No reminders for today',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7A6A70),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  ...todaysReminders.map((reminder) {
                    final time = (reminder['time'] as Timestamp?)?.toDate();
                    final timeStr = time != null
                        ? DateFormat('h:mm a').format(time)
                        : '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(fontSize: 16)),
                          Expanded(
                            child: Text(
                              '${reminder['title']} ${timeStr.isNotEmpty ? 'at $timeStr' : ''}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF3D2C31),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _showReminderPopup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4ADB1),
                  foregroundColor: const Color(0xFF3D2C31),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  'Add Reminder',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _buildActionCard(
                icon: Icons.calendar_month,
                label: 'Calendar',
                onTap: () => _showComingSoon('Calendar'),
              ),
              const SizedBox(height: 16),
              _buildActionCard(
                icon: Icons.extension,
                label: 'Activities',
                onTap: () => _showComingSoon('Activities & Games'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionCard(
            icon: Icons.location_on,
            label: 'Location',
            height: 280,
            isLarge: true,
            onTap: () => _showComingSoon('Location Tracking'),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double? height,
    bool isLarge = false,
  }) {
    return Container(
      height: height ?? 132,
      decoration: BoxDecoration(
        color: const Color(0xFFE8C4C8),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: isLarge
              ? Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: const Color(0xFFD4E5D4),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: 64,
                    color: const Color(0xFF8FA9C9).withOpacity(0.5),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3D2C31),
                    ),
                  ),
                ),
              ),
            ],
          )
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: const Color(0xFF3D2C31),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3D2C31),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavButton(Icons.calendar_today, 0),
              _buildNavButton(Icons.location_on, 1),
              _buildCenterAddButton(),
              _buildNavButton(Icons.extension, 3),
              _buildNavButton(Icons.person, 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(IconData icon, int index) {
    final isSelected = _selectedNavIndex == index;
    return IconButton(
      onPressed: () {
        setState(() {
          _selectedNavIndex = index;
        });
        _handleNavigation(index);
      },
      icon: Icon(
        icon,
        color: isSelected ? const Color(0xFF8FA9C9) : const Color(0xFF9E9E9E),
        size: 28,
      ),
    );
  }

  Widget _buildCenterAddButton() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF8FA9C9),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8FA9C9).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showReminderPopup,
          borderRadius: BorderRadius.circular(28),
          child: const Icon(
            Icons.add,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  void _handleNavigation(int index) {
    switch (index) {
      case 0:
        _showComingSoon('Calendar');
        break;
      case 1:
        _showComingSoon('Location');
        break;
      case 3:
        _showComingSoon('Activities');
        break;
      case 4:
        Navigator.pop(context);
        break;
    }
  }

  void _showReminderPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReminderPopup(
        patientId: widget.patientId,
        onSave: () {
          _loadPatientData(); // Reload reminders
        },
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature feature coming soon!'),
        backgroundColor: const Color(0xFF8FA9C9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// Reminder Popup Widget
class ReminderPopup extends StatefulWidget {
  final String patientId;
  final VoidCallback onSave;

  const ReminderPopup({
    super.key,
    required this.patientId,
    required this.onSave,
  });

  @override
  State<ReminderPopup> createState() => _ReminderPopupState();
}

class _ReminderPopupState extends State<ReminderPopup> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedType = 'Event';
  TimeOfDay? _selectedTime;
  String _selectedRepeat = 'Once';
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveReminder() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a title'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Create reminder time
      final now = DateTime.now();
      DateTime reminderTime = DateTime(
        now.year,
        now.month,
        now.day,
        _selectedTime?.hour ?? now.hour,
        _selectedTime?.minute ?? now.minute,
      );

      await _firestore.collection('reminders').add({
        'patientId': widget.patientId,
        'title': _titleController.text,
        'description': _descriptionController.text,
        'type': _selectedType.toLowerCase(),
        'time': Timestamp.fromDate(reminderTime),
        'repeating': _selectedRepeat.toLowerCase(),
        'completed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      widget.onSave();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Reminder added successfully!'),
            backgroundColor: const Color(0xFF8FA9C9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      print('Error saving reminder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save reminder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF3D2C31),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Reminder Popup',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF5E6E8),
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInputField(
                      label: 'Title:',
                      controller: _titleController,
                      hint: 'Enter reminder title',
                    ),
                    const SizedBox(height: 16),
                    _buildInputField(
                      label: 'Description:',
                      controller: _descriptionController,
                      hint: 'Enter description',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildTypeSelector(),
                    const SizedBox(height: 16),
                    _buildTimeSelector(),
                    const SizedBox(height: 16),
                    _buildRepeatSelector(),
                    const SizedBox(height: 32),
                    _buildSaveButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3D2C31),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE8C4C8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: Color(0xFF3D2C31)),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: const Color(0xFF3D2C31).withOpacity(0.5)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: [
        Expanded(child: _buildTypeButton('Event')),
        const SizedBox(width: 12),
        Expanded(child: _buildTypeButton('Task')),
      ],
    );
  }

  Widget _buildTypeButton(String type) {
    final isSelected = _selectedType == type;
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE8C4C8) : const Color(0xFFD4ADB1),
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: const Color(0xFF8FA9C9), width: 2)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedType = type),
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              type,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: const Color(0xFF3D2C31),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Times:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3D2C31),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF8FA9C9),
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (time != null) {
              setState(() => _selectedTime = time);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFE8C4C8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time, color: Color(0xFF3D2C31)),
                const SizedBox(width: 12),
                Text(
                  _selectedTime != null
                      ? _selectedTime!.format(context)
                      : 'Select time',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF3D2C31),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRepeatSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Repeating?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3D2C31),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFE8C4C8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedRepeat,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF3D2C31)),
              style: const TextStyle(fontSize: 16, color: Color(0xFF3D2C31)),
              dropdownColor: const Color(0xFFE8C4C8),
              items: ['Once', 'Daily', 'Weekly', 'Monthly']
                  .map((value) => DropdownMenuItem(
                value: value,
                child: Text(value),
              ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedRepeat = value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveReminder,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8FA9C9),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        child: _isSaving
            ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        )
            : const Text(
          'Save Reminder',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}