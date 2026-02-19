import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';

class CalendarPage extends StatefulWidget {
  final String patientId;
  final bool isCaretaker;

  const CalendarPage({
    super.key,
    required this.patientId,
    this.isCaretaker = false,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  List<Map<String, dynamic>> _selectedEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);

    try {
      // Get reminders for this patient
      final snapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .orderBy('time')
          .get();

      Map<DateTime, List<Map<String, dynamic>>> events = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = data['time'] as Timestamp?;

        // Skip snoozed reminders
        if (data['isSnoozed'] == true) {
          continue;
        }

        if (timestamp != null) {
          final date = timestamp.toDate();
          // Normalize to midnight for grouping by day
          final normalizedDate = DateTime(date.year, date.month, date.day);

          final event = {
            'id': doc.id,
            'title': data['title'] ?? 'Untitled',
            'description': data['description'] ?? '',
            'time': date,
            'completed': data['completed'] ?? false,
          };

          if (events[normalizedDate] == null) {
            events[normalizedDate] = [];
          }
          events[normalizedDate]!.add(event);
        }
      }

      setState(() {
        _events = events;
        _selectedEvents = _getEventsForDay(_selectedDay ?? _focusedDay);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading reminders: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return _events[normalizedDay] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _selectedEvents = _getEventsForDay(selectedDay);
      });
    }
  }

  Future<void> _handleRefresh() async {
    await _loadReminders();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calendar refreshed'),
          backgroundColor: Color(0xFF8FA9C9),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _toggleReminderComplete(String reminderId, bool currentStatus) async {
    try {
      await _firestore
          .collection('reminders')
          .doc(reminderId)
          .update({'completed': !currentStatus});

      await _loadReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !currentStatus ? 'Reminder marked as complete' : 'Reminder marked as incomplete',
            ),
            backgroundColor: const Color(0xFF8FA9C9),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error toggling reminder: $e');
    }
  }

  Future<void> _deleteReminder(String reminderId) async {
    try {
      await _firestore.collection('reminders').doc(reminderId).delete();
      await _loadReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder deleted'),
            backgroundColor: Color(0xFF8FA9C9),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Error deleting reminder: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6E8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE8C4C8),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3D2C31)),
        ),
        title: const Text(
          'Calendar',
          style: TextStyle(
            color: Color(0xFF3D2C31),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _handleRefresh,
            icon: const Icon(Icons.refresh, color: Color(0xFF3D2C31)),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF8FA9C9),
        child: Column(
          children: [
            _buildCalendar(),
            const SizedBox(height: 8),
            Expanded(
              child: _buildEventList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TableCalendar(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: _calendarFormat,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        eventLoader: _getEventsForDay,
        startingDayOfWeek: StartingDayOfWeek.sunday,
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          todayDecoration: BoxDecoration(
            color: const Color(0xFF8FA9C9).withOpacity(0.5),
            shape: BoxShape.circle,
          ),
          selectedDecoration: const BoxDecoration(
            color: Color(0xFF8FA9C9),
            shape: BoxShape.circle,
          ),
          markerDecoration: const BoxDecoration(
            color: Color(0xFFE8C4C8),
            shape: BoxShape.circle,
          ),
          markersMaxCount: 3,
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: true,
          titleCentered: true,
          formatButtonDecoration: BoxDecoration(
            color: const Color(0xFFE8C4C8),
            borderRadius: BorderRadius.circular(12),
          ),
          formatButtonTextStyle: const TextStyle(
            color: Color(0xFF3D2C31),
            fontWeight: FontWeight.w600,
          ),
          titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3D2C31),
          ),
        ),
        onDaySelected: _onDaySelected,
        onFormatChanged: (format) {
          if (_calendarFormat != format) {
            setState(() {
              _calendarFormat = format;
            });
          }
        },
        onPageChanged: (focusedDay) {
          _focusedDay = focusedDay;
        },
      ),
    );
  }

  Widget _buildEventList() {
    if (_selectedEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: const Color(0xFF8FA9C9).withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No reminders for this day',
              style: TextStyle(
                fontSize: 16,
                color: const Color(0xFF3D2C31).withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _selectedEvents.length,
      itemBuilder: (context, index) {
        final event = _selectedEvents[index];
        return _buildEventCard(event);
      },
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final time = event['time'] as DateTime;
    final timeStr = DateFormat('h:mm a').format(time);
    final isCompleted = event['completed'] as bool;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFF8FA9C9).withOpacity(0.3)
              : const Color(0xFFE8C4C8),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showEventDetails(event),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Checkbox for completion
                InkWell(
                  onTap: () => _toggleReminderComplete(
                    event['id'],
                    isCompleted,
                  ),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF8FA9C9),
                        width: 2,
                      ),
                      color: isCompleted
                          ? const Color(0xFF8FA9C9)
                          : Colors.transparent,
                    ),
                    child: isCompleted
                        ? const Icon(
                      Icons.check,
                      size: 18,
                      color: Colors.white,
                    )
                        : null,
                  ),
                ),
                const SizedBox(width: 16),

                // Event details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['title'],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF3D2C31),
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: const Color(0xFF5A4046).withOpacity(0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 14,
                              color: const Color(0xFF5A4046).withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      if (event['description']?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(
                          event['description'],
                          style: TextStyle(
                            fontSize: 13,
                            color: const Color(0xFF5A4046).withOpacity(0.6),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Delete button (only for caretakers)
                if (widget.isCaretaker)
                  IconButton(
                    onPressed: () => _showDeleteConfirmation(event['id']),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFFF4757),
                    ),
                    tooltip: 'Delete',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEventDetails(Map<String, dynamic> event) {
    final time = event['time'] as DateTime;
    final timeStr = DateFormat('h:mm a').format(time);
    final dateStr = DateFormat('MMMM dd, yyyy').format(time);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFF5E6E8),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.event,
                    size: 32,
                    color: Color(0xFF8FA9C9),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      event['title'],
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8C4C8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 18,
                          color: Color(0xFF3D2C31),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF3D2C31),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 18,
                          color: Color(0xFF3D2C31),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF3D2C31),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (event['description']?.isNotEmpty ?? false) ...[
                const SizedBox(height: 16),
                const Text(
                  'Description:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3D2C31),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8C4C8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    event['description'],
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF3D2C31),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8FA9C9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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

  void _showDeleteConfirmation(String reminderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Color(0xFFFF4757)),
            SizedBox(width: 12),
            Text('Delete Reminder'),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this reminder?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 16,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteReminder(reminderId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4757),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}