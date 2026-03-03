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
      final snapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .orderBy('time')
          .get();

      Map<DateTime, List<Map<String, dynamic>>> events = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = data['time'] as Timestamp?;

        if (data['isSnoozed'] == true) {
          continue;
        }

        if (timestamp != null) {
          final date = timestamp.toDate();
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
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.refresh, color: Colors.white),
              SizedBox(width: 12),
              Text(
                'Calendar refreshed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          duration: Duration(seconds: 2),
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
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    !currentStatus ? 'Marked as complete' : 'Marked as incomplete',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            duration: Duration(seconds: 2),
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
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.delete, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  'Reminder deleted',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade600,
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
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          'My Calendar',
          style: TextStyle(
            color: const Color(0xFF5D4037),
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Color(0xFF8D6E63), width: 2),
            ),
            child: IconButton(
              onPressed: _handleRefresh,
              icon: Icon(Icons.refresh, color: Color(0xFF5D4037), size: 24),
              tooltip: 'Refresh',
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Color(0xFFD4A5A5),
          strokeWidth: 4,
        ),
      )
          : RefreshIndicator(
        onRefresh: _handleRefresh,
        color: Color(0xFFD4A5A5),
        child: Column(
          children: [
            _buildCalendar(),
            SizedBox(height: 16),
            _buildSelectedDateHeader(),
            SizedBox(height: 12),
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
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(0xFFD4A5A5), width: 3),
        boxShadow: [
          BoxShadow(
            color: Color(0xFFD4A5A5).withOpacity(0.2),
            blurRadius: 16,
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
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF8D6E63),
          ),
          weekendStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFFD4A5A5),
          ),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          defaultTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5D4037),
          ),
          weekendTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFFD4A5A5),
          ),
          todayDecoration: BoxDecoration(
            color: Color(0xFF6B8E23).withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(color: Color(0xFF6B8E23), width: 2),
          ),
          todayTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5D4037),
          ),
          selectedDecoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFD4A5A5), Color(0xFFE8B5B5)],
            ),
            shape: BoxShape.circle,
          ),
          selectedTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          markerDecoration: BoxDecoration(
            color: Color(0xFF6B8E23),
            shape: BoxShape.circle,
          ),
          markersMaxCount: 3,
          markerSize: 6,
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          leftChevronIcon: Icon(
            Icons.chevron_left,
            color: Color(0xFF5D4037),
            size: 28,
          ),
          rightChevronIcon: Icon(
            Icons.chevron_right,
            color: Color(0xFF5D4037),
            size: 28,
          ),
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5D4037),
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

  Widget _buildSelectedDateHeader() {
    final dateStr = DateFormat('EEEE, MMMM dd').format(_selectedDay ?? _focusedDay);
    final eventCount = _selectedEvents.length;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFFD4A5A5), width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFD4A5A5), Color(0xFFE8B5B5)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.calendar_today,
              color: Colors.white,
              size: 22,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  eventCount == 0
                      ? 'No reminders'
                      : '$eventCount ${eventCount == 1 ? 'reminder' : 'reminders'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8D6E63),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventList() {
    if (_selectedEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_busy,
                size: 64,
                color: Color(0xFFD4A5A5),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'No reminders today',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5D4037),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Enjoy your free time!',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF8D6E63),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isCompleted ? Color(0xFFF0F0F0) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCompleted ? Color(0xFF6B8E23) : Color(0xFFD4A5A5),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: (isCompleted ? Color(0xFF6B8E23) : Color(0xFFD4A5A5)).withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showEventDetails(event),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // Checkbox
                GestureDetector(
                  onTap: () => _toggleReminderComplete(event['id'], isCompleted),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Color(0xFF6B8E23),
                        width: 3,
                      ),
                      color: isCompleted ? Color(0xFF6B8E23) : Colors.white,
                    ),
                    child: isCompleted
                        ? Icon(
                      Icons.check,
                      size: 22,
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
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5D4037),
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFF5F3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 16,
                              color: Color(0xFF8D6E63),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8D6E63),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (event['description']?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 8),
                        Text(
                          event['description'],
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF8D6E63),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Delete button (caretakers only)
                if (widget.isCaretaker)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      onPressed: () => _showDeleteConfirmation(event['id']),
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade700,
                        size: 24,
                      ),
                      tooltip: 'Delete',
                    ),
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
    final dateStr = DateFormat('EEEE, MMMM dd, yyyy').format(time);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFF4E4E1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFD4A5A5), Color(0xFFE8B5B5)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.event,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Reminder Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5D4037),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Color(0xFFD4A5A5), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event['title'],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5D4037),
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildDetailRow(Icons.calendar_today, 'Date', dateStr),
                    SizedBox(height: 12),
                    _buildDetailRow(Icons.access_time, 'Time', timeStr),
                  ],
                ),
              ),
              if (event['description']?.isNotEmpty ?? false) ...[
                const SizedBox(height: 16),
                Text(
                  'Notes:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Color(0xFFD4A5A5), width: 2),
                  ),
                  child: Text(
                    event['description'],
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF5D4037),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFD4A5A5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                  ),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      fontSize: 18,
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Color(0xFFD4A5A5)),
        SizedBox(width: 10),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8D6E63),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF5D4037),
            ),
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(String reminderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: Color(0xFFFFF5F5),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 32),
            SizedBox(width: 12),
            Text(
              'Delete Reminder?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5D4037),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this reminder? This cannot be undone.',
          style: TextStyle(
            fontSize: 16,
            color: Color(0xFF5D4037),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF8D6E63),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteReminder(reminderId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete, size: 20),
                SizedBox(width: 6),
                Text(
                  'Delete',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}