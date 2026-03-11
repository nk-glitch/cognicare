import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_service.dart';
import 'calendar_page.dart';
import 'caretaker_home_page.dart';
import 'patient_profile_page.dart';
import 'patient_detail_page.dart';


class LocationMapPage extends StatefulWidget {
  final String patientId;
  final String patientName;

  const LocationMapPage({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<LocationMapPage> createState() => _LocationMapPageState();
}

class _LocationMapPageState extends State<LocationMapPage>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  LatLng _currentPosition = const LatLng(37.7749, -122.4194);
  bool _isLoading = true;
  bool _noLocationAvailable = false;
  DateTime? _lastUpdate;
  StreamSubscription<Map<String, dynamic>?>? _locationSubscription;

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _bg       = Color(0xFFF7F4F2);
  static const _card     = Colors.white;
  static const _accent   = Color(0xFF5A7A1A);
  static const _accentSoft = Color(0xFFEEF3E6);
  static const _rose     = Color(0xFFD4A5A5);
  static const _roseSoft = Color(0xFFF4E4E1);
  static const _text     = Color(0xFF1E1A18);
  static const _subtext  = Color(0xFF7A6E6A);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _checkInitialLocation();
    _listenToLocation();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _noLocationAvailable = true;
        });
        _animController.forward();
      }
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialLocation() async {
    final loc = await _locationService.getStoredLocation(widget.patientId);
    if (loc != null && loc.isNotEmpty && mounted) {
      setState(() {
        _isLoading = false;
        _noLocationAvailable = false;
        _currentPosition = LatLng(
          loc['latitude'] as double,
          loc['longitude'] as double,
        );
        if (loc['timestamp'] != null) {
          _lastUpdate = DateTime.fromMillisecondsSinceEpoch(
              loc['timestamp'] as int);
        }
      });
      _animController.forward();
    }
  }

  Future<void> _retryLoadLocation() async {
    _animController.reset();
    setState(() {
      _isLoading = true;
      _noLocationAvailable = false;
    });
    await _checkInitialLocation();
    if (mounted && _isLoading) {
      setState(() {
        _isLoading = false;
        _noLocationAvailable = true;
      });
      _animController.forward();
    }
  }

  void _listenToLocation() {
    _locationSubscription =
        _locationService.listenToLocation(widget.patientId).listen((data) {
          if (data != null && data.isNotEmpty && mounted) {
            setState(() {
              _isLoading = false;
              _noLocationAvailable = false;
              _currentPosition = LatLng(
                data['latitude'] as double,
                data['longitude'] as double,
              );
              if (data['timestamp'] != null) {
                _lastUpdate = DateTime.fromMillisecondsSinceEpoch(
                    data['timestamp'] as int);
              }
            });
            if (!_animController.isCompleted) _animController.forward();
            _mapController.move(_currentPosition, 15.0);
          }
        }, onError: (e) => debugPrint('Location stream error: $e'));
  }

  String _getLastUpdateText() {
    if (_lastUpdate == null) return 'Just now';
    final diff = DateTime.now().difference(_lastUpdate!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours} hr ago';
  }

  void _centerOnLocation() => _mapController.move(_currentPosition, 16.0);

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Background blobs
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
              children: [
                _buildTopBar(),
                _buildPatientStrip(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton:
      (!_isLoading && !_noLocationAvailable) ? _buildFAB() : null,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          // Back
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
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.favorite_rounded, color: _rose, size: 22),
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

  // ── Patient name + page heading ───────────────────────────────────────────
  Widget _buildPatientStrip() {
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
                  'Live Location',
                  style: TextStyle(
                    fontSize: 14,
                    color: _subtext,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.patientName,
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
          // Refresh button
          GestureDetector(
            onTap: _retryLoadLocation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB07A6E).withOpacity(0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh_rounded,
                    size: 15,
                    color: _isLoading ? _rose : _accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Refresh',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _isLoading ? _rose : _accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_isLoading) return _buildLoadingState();
    if (_noLocationAvailable) return _buildNoLocationState();
    return _buildMap();
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _buildLoadingState() {
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
            child: const Center(
              child: CircularProgressIndicator(
                color: _accent,
                strokeWidth: 2.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Fetching location…',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.patientName} can share location from their app',
            style: const TextStyle(fontSize: 13, color: _subtext),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── No location ───────────────────────────────────────────────────────────
  Widget _buildNoLocationState() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
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
                  child: const Icon(Icons.location_off_rounded,
                      size: 32, color: _rose),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No location shared yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ask ${widget.patientName} to open the app and tap "Allow location" on their home screen. Location works best with GPS on and outdoors.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _subtext,
                    height: 1.55,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _retryLoadLocation,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Map ───────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Stack(
        children: [
          // Map
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24)),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition,
                initialZoom: 15.0,
                minZoom: 5.0,
                maxZoom: 18.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.cognicare',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition,
                      width: 160,
                      height: 80,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Name bubble
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              widget.patientName,
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Pin
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _rose.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: _rose,
                              size: 38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Last-updated card — top overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB07A6E).withOpacity(0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.access_time_rounded,
                        size: 17, color: _accent),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last updated',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _subtext,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _getLastUpdateText(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Live',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
                      patientName: widget.patientName,
                    ),
                  ));
                },
              ),
              _BottomNavItem(
                icon: Icons.calendar_today_outlined,
                label: 'Calendar',
                onTap: () {
                  Navigator.pushReplacement(context, InstantPushMaterialRoute(
                    builder: (_) => CalendarPage(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                      isCaretaker: true,
                    ),
                  ));
                },
              ),
              _BottomNavItem(
                icon: Icons.location_on_rounded,
                label: 'Location',
                active: true,
                onTap: () {},
              ),
              _BottomNavItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                onTap: () {
                  Navigator.pushReplacement(context, InstantPushMaterialRoute(
                    builder: (_) => PatientProfilePage(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
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

  // ── FAB ───────────────────────────────────────────────────────────────────
  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _centerOnLocation,
      backgroundColor: _accent,
      elevation: 4,
      icon: const Icon(Icons.my_location_rounded,
          color: Colors.white, size: 20),
      label: const Text(
        'Center',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }
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