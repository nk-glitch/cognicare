import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'location_map_page.dart';
import 'patient_profile_page.dart';
import 'patient_detail_page.dart';
import 'caretaker_home_page.dart';


class CalendarPage extends StatefulWidget {
  final String patientId;
  final String patientName;
  final bool isCaretaker;

  const CalendarPage({
    super.key,
    required this.patientId,
    this.patientName = '',
    this.isCaretaker = false,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  List<Map<String, dynamic>> _selectedEvents = [];
  bool _isLoading = true;

  String get _patientName => widget.patientName;

  // ── Palette (mirrors CaretakerHomePage) ──────────────────────────────────
  static const _bg       = Color(0xFFF7F4F2);
  static const _card     = Colors.white;
  static const _accent   = Color(0xFF5A7A1A);
  static const _accentSoft = Color(0xFFEEF3E6);
  static const _rose     = Color(0xFFD4A5A5);
  static const _roseSoft = Color(0xFFF4E4E1);
  static const _text     = Color(0xFF1E1A18);
  static const _subtext  = Color(0xFF7A6E6A);
  static const _border   = Color(0xFFF0EBE8);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
        parent: _animController, curve: Curves.easeOut);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _selectedDay = _focusedDay;
    _loadReminders();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _firestore
          .collection('reminders')
          .where('patientId', isEqualTo: widget.patientId)
          .orderBy('time')
          .get();

      final Map<DateTime, List<Map<String, dynamic>>> events = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['isSnoozed'] == true) continue;
        final ts = data['time'] as Timestamp?;
        if (ts == null) continue;

        final date = ts.toDate();
        final key = DateTime(date.year, date.month, date.day);
        events.putIfAbsent(key, () => []).add({
          'id': doc.id,
          'title': data['title'] ?? 'Untitled',
          'description': data['description'] ?? '',
          'time': date,
          'completed': data['completed'] ?? false,
        });
      }

      setState(() {
        _events = events;
        _selectedEvents = _getEventsForDay(_selectedDay ?? _focusedDay);
        _isLoading = false;
      });
      _animController.forward(from: 0);
    } catch (e) {
      debugPrint('Error loading reminders: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _events[key] ?? [];
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
    _animController.reset();
    await _loadReminders();
  }

  Future<void> _toggleReminderComplete(
      String reminderId, bool currentStatus) async {
    try {
      await _firestore
          .collection('reminders')
          .doc(reminderId)
          .update({'completed': !currentStatus});
      await _loadReminders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(_snack(
          !currentStatus ? 'Marked as complete' : 'Marked as incomplete',
          success: !currentStatus,
        ));
      }
    } catch (e) {
      debugPrint('Error toggling reminder: $e');
    }
  }

  Future<void> _deleteReminder(String reminderId) async {
    try {
      await _firestore.collection('reminders').doc(reminderId).delete();
      await _loadReminders();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(_snack('Reminder deleted'));
      }
    } catch (e) {
      debugPrint('Error deleting reminder: $e');
    }
  }

  SnackBar _snack(String msg, {bool success = false}) => SnackBar(
    content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
    backgroundColor: success ? _accent : _subtext,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.all(16),
  );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: widget.isCaretaker ? _buildBottomNav() : null,
      body: Stack(
        children: [
          // Background blobs — mirrors home page
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _rose.withOpacity(0.14),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: -70,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withOpacity(0.05),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(),
                Expanded(
                  child: _isLoading
                      ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                      : FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: RefreshIndicator(
                        onRefresh: _handleRefresh,
                        color: _accent,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  _buildMonthHeader(),
                                  _buildCalendar(),
                                  const SizedBox(height: 20),
                                  _buildSelectedDateChip(),
                                  const SizedBox(height: 14),
                                ],
                              ),
                            ),
                            _selectedEvents.isEmpty
                                ? SliverFillRemaining(
                                child: _buildEmptyState())
                                : SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 0, 20, 32),
                              sliver: SliverList(
                                delegate:
                                SliverChildBuilderDelegate(
                                      (_, i) => TweenAnimationBuilder<
                                      double>(
                                    tween:
                                    Tween(begin: 0.0, end: 1.0),
                                    duration: Duration(
                                        milliseconds:
                                        200 + i * 70),
                                    curve: Curves.easeOutCubic,
                                    builder: (_, v, child) =>
                                        Opacity(
                                          opacity: v,
                                          child: Transform.translate(
                                            offset:
                                            Offset(0, 14 * (1 - v)),
                                            child: child,
                                          ),
                                        ),
                                    child: _buildEventCard(
                                        _selectedEvents[i]),
                                  ),
                                  childCount:
                                  _selectedEvents.length,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),                // closes FadeTransition
                ),                  // closes Expanded
              ],                    // closes Column children
            ),                      // closes Column
          ),                        // closes SafeArea
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB07A6E).withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _text, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          // Logo + wordmark
          Row(
            children: [
              ColoredBox(
                color: _bg,
                child: Image.asset(
                  'assets/images/logo_no_text.png',
                  width: 26,
                  height: 26,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.favorite_rounded,
                    color: _rose,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Cogni',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w300,
                        color: Color(0xFF5D4037),
                        letterSpacing: -0.5,
                      ),
                    ),
                    TextSpan(
                      text: 'Care',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF5D4037),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          // Date pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB07A6E).withOpacity(0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              DateFormat('MMM d').format(DateTime.now()),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _subtext,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Month / page heading ──────────────────────────────────────────────────
  Widget _buildMonthHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Schedule',
                  style: TextStyle(
                    fontSize: 14,
                    color: _subtext,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMMM yyyy').format(_focusedDay),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _text,
                    letterSpacing: -0.8,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          // Add reminder button
          GestureDetector(
            onTap: _showAddReminderDialog,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ── Calendar widget ───────────────────────────────────────────────────────
  Widget _buildCalendar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.09),
            blurRadius: 28,
            offset: const Offset(0, 8),
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
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _subtext,
            letterSpacing: 0.5,
          ),
          weekendStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _rose.withOpacity(0.8),
            letterSpacing: 0.5,
          ),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          defaultTextStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _text,
          ),
          weekendTextStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _rose.withOpacity(0.9),
          ),
          disabledTextStyle: const TextStyle(
            fontSize: 14,
            color: Color(0xFFCCC5C0),
          ),
          todayDecoration: BoxDecoration(
            color: _accentSoft,
            shape: BoxShape.circle,
            border: Border.all(color: _accent, width: 1.5),
          ),
          todayTextStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _accent,
          ),
          selectedDecoration: const BoxDecoration(
            color: _rose,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          markerDecoration: const BoxDecoration(
            color: _accent,
            shape: BoxShape.circle,
          ),
          markersMaxCount: 3,
          markerSize: 5,
          markerMargin: const EdgeInsets.only(top: 1),
          cellMargin: const EdgeInsets.all(5),
        ),
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          headerPadding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          leftChevronIcon: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F4F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.chevron_left_rounded,
                color: _subtext, size: 20),
          ),
          rightChevronIcon: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F4F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.chevron_right_rounded,
                color: _subtext, size: 20),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _text,
            letterSpacing: -0.3,
          ),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFF0EBE8), width: 1),
            ),
          ),
        ),
        onDaySelected: _onDaySelected,
        onFormatChanged: (format) {
          if (_calendarFormat != format) {
            setState(() => _calendarFormat = format);
          }
        },
        onPageChanged: (focusedDay) {
          setState(() => _focusedDay = focusedDay);
        },
      ),
    );
  }

  // ── Selected date chip ────────────────────────────────────────────────────
  Widget _buildSelectedDateChip() {
    final day = _selectedDay ?? _focusedDay;
    final isToday = isSameDay(day, DateTime.now());
    final dateStr = isToday
        ? 'Today — ${DateFormat('MMMM d').format(day)}'
        : DateFormat('EEEE, MMMM d').format(day);
    final count = _selectedEvents.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _text,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'No reminders scheduled'
                      : '$count ${count == 1 ? 'reminder' : 'reminders'}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _subtext,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (count > 0)
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 14, color: _accent),
                  const SizedBox(width: 5),
                  Text(
                    '${_selectedEvents.where((e) => e['completed'] == true).length}/$count done',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Event card ────────────────────────────────────────────────────────────
  Widget _buildEventCard(Map<String, dynamic> event) {
    final time = event['time'] as DateTime;
    final timeStr = DateFormat('h:mm a').format(time);
    final isCompleted = event['completed'] as bool;
    final title = event['title'] as String? ?? '';
    final description = event['description'] as String? ?? '';

    return GestureDetector(
      onTap: () => _showEventDetails(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isCompleted ? const Color(0xFFF9F9F7) : _card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB07A6E).withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Completion toggle
              GestureDetector(
                onTap: () =>
                    _toggleReminderComplete(event['id'], isCompleted),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted ? _accent : Colors.transparent,
                    border: Border.all(
                      color: isCompleted ? _accent : _border,
                      width: 2,
                    ),
                  ),
                  child: isCompleted
                      ? const Icon(Icons.check_rounded,
                      size: 18, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 14),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isCompleted ? _subtext : _text,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: _subtext,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _subtext,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Time chip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isCompleted ? _accentSoft : _roseSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isCompleted ? _accent : _rose,
                  ),
                ),
              ),

              // Delete (caretaker only)
              if (widget.isCaretaker) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showDeleteConfirmation(event['id']),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F4F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        size: 16, color: _subtext),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB07A6E).withOpacity(0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.event_available_rounded,
                size: 32, color: _rose),
          ),
          const SizedBox(height: 16),
          const Text(
            'Nothing scheduled',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No reminders for this day',
            style: TextStyle(fontSize: 14, color: _subtext),
          ),
        ],
      ),
    );
  }

  // ── Event detail dialog ───────────────────────────────────────────────────
  void _showEventDetails(Map<String, dynamic> event) {
    final time = event['time'] as DateTime;
    final timeStr = DateFormat('h:mm a').format(time);
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(time);
    final description = event['description'] as String? ?? '';

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB07A6E).withOpacity(0.18),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon header
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: _roseSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_rounded,
                    color: _rose, size: 24),
              ),
              const SizedBox(height: 16),
              Text(
                event['title'] as String? ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _text,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: _border),
              const SizedBox(height: 12),
              _detailRow(Icons.calendar_today_rounded, 'Date', dateStr),
              const SizedBox(height: 10),
              _detailRow(Icons.access_time_rounded, 'Time', timeStr),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F4F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _subtext,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rose,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: _rose),
        const SizedBox(width: 10),
        Text(
          '$label:  ',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _subtext,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: _text,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }


  // ── Bottom nav (shared caretaker bar) ────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                onTap: () {
                  Navigator.pushReplacement(context, InstantPushMaterialRoute(
                    builder: (_) => PatientDetailPage(
                      patientId: widget.patientId,
                      patientName: _patientName,
                    ),
                  ));
                },
              ),
              _BottomNavItem(
                icon: Icons.calendar_today_rounded,
                label: 'Calendar',
                active: true,
                onTap: () {},
              ),
              _BottomNavItem(
                icon: Icons.location_on_outlined,
                label: 'Location',
                onTap: () {
                  Navigator.pushReplacement(context, InstantPushMaterialRoute(
                    builder: (_) => LocationMapPage(
                      patientId: widget.patientId,
                      patientName: _patientName,
                    ),
                  ));
                },
              ),
              _BottomNavItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                onTap: () {
                  Navigator.pushReplacement(context, InstantPushMaterialRoute(
                    builder: (_) => PatientProfilePage(
                      patientId: widget.patientId,
                      patientName: _patientName,
                    ),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Delete confirmation ───────────────────────────────────────────────────
  void _showDeleteConfirmation(String reminderId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Text(
          'Delete reminder?',
          style: TextStyle(
              fontWeight: FontWeight.w700, color: Color(0xFF3E2723)),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: _subtext),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: _subtext)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteReminder(reminderId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Add reminder dialog ───────────────────────────────────────────────────
  void _showAddReminderDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    bool isSaving = false;
    int? missedAlertDelayMinutes = 5; // null = no caretaker alert

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB07A6E).withOpacity(0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon badge
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add_alarm_rounded,
                      color: _accent, size: 24),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Add Reminder',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _text,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  DateFormat('EEEE, MMMM d').format(
                      _selectedDay ?? _focusedDay),
                  style: const TextStyle(
                    fontSize: 13,
                    color: _subtext,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 20),

                // Title field
                _dialogLabel('Title'),
                const SizedBox(height: 6),
                _dialogTextField(
                  controller: titleController,
                  hint: 'e.g. Take medication',
                  icon: Icons.title_rounded,
                ),
                const SizedBox(height: 14),

                // Notes field
                _dialogLabel('Notes (optional)'),
                const SizedBox(height: 6),
                _dialogTextField(
                  controller: descController,
                  hint: 'Any additional details…',
                  icon: Icons.notes_rounded,
                ),
                const SizedBox(height: 14),

                // Time picker row
                _dialogLabel('Time'),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: selectedTime,
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: _accent,
                            onPrimary: Colors.white,
                            surface: Colors.white,
                            onSurface: _text,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedTime = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF6F4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFEDE5E2), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            color: _rose, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          selectedTime.format(ctx),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _text,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.edit_rounded,
                            size: 14, color: _subtext),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Missed-alert delay picker
                _dialogLabel('Alert caretaker if missed after'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF6F4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFEDE5E2), width: 1.5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: missedAlertDelayMinutes,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: _subtext, size: 20),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _text),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('No alert'),
                        ),
                        DropdownMenuItem(
                          value: 1,
                          child: Text('1 minute'),
                        ),
                        DropdownMenuItem(
                          value: 3,
                          child: Text('3 minutes'),
                        ),
                        DropdownMenuItem(
                          value: 5,
                          child: Text('5 minutes'),
                        ),
                        DropdownMenuItem(
                          value: 10,
                          child: Text('10 minutes'),
                        ),
                        DropdownMenuItem(
                          value: 15,
                          child: Text('15 minutes'),
                        ),
                        DropdownMenuItem(
                          value: 30,
                          child: Text('30 minutes'),
                        ),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => missedAlertDelayMinutes = val),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        foregroundColor: _subtext,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                          final title =
                          titleController.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(_snack(
                                'Please enter a title'));
                            return;
                          }
                          setDialogState(
                                  () => isSaving = true);
                          try {
                            final day = _selectedDay ??
                                _focusedDay;
                            final dt = DateTime(
                              day.year,
                              day.month,
                              day.day,
                              selectedTime.hour,
                              selectedTime.minute,
                            );
                            await _firestore
                                .collection('reminders')
                                .add({
                              'patientId': widget.patientId,
                              'title': title,
                              'description':
                              descController.text.trim(),
                              'time': Timestamp.fromDate(dt),
                              'completed': false,
                              'isSnoozed': false,
                              'missedAlertDelayMinutes': missedAlertDelayMinutes,
                              'createdAt':
                              FieldValue.serverTimestamp(),
                            });
                            if (mounted) {
                              Navigator.pop(ctx);
                              await _loadReminders();
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(_snack(
                                  'Reminder added',
                                  success: true));
                            }
                          } catch (e) {
                            debugPrint(
                                'Error adding reminder: \$e');
                            setDialogState(
                                    () => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(_snack(
                                  'Something went wrong'));
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                          _accent.withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: isSaving
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white),
                        )
                            : const Text('Add Reminder',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF5D4037),
    ),
  );

  Widget _dialogTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) =>
      TextField(
        controller: controller,
        style: const TextStyle(
            fontSize: 15, color: _text, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
          const TextStyle(color: Color(0xFFBDB0AC), fontSize: 15),
          prefixIcon: Icon(icon, color: _rose, size: 20),
          filled: true,
          fillColor: const Color(0xFFFAF6F4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
            const BorderSide(color: Color(0xFFEDE5E2), width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
            const BorderSide(color: Color(0xFFEDE5E2), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accent, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
        ),
      );
}

// ── Bottom nav item ───────────────────────────────────────────────────────────
class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 24,
            color: active
                ? const Color(0xFF5A7A1A)
                : const Color(0xFFBDB0AC),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active
                  ? const Color(0xFF5A7A1A)
                  : const Color(0xFFBDB0AC),
            ),
          ),
        ],
      ),
    );
  }
}