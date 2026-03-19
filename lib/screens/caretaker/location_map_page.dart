import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_service.dart';
import '../../services/geofence_service.dart';
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
  final GeofenceService _geofenceService = GeofenceService();

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  LatLng _currentPosition = const LatLng(37.7749, -122.4194);
  bool _isLoading = true;
  bool _noLocationAvailable = false;
  DateTime? _lastUpdate;
  StreamSubscription<Map<String, dynamic>?>? _locationSubscription;
  StreamSubscription<Map<String, dynamic>?>? _geofenceSubscription;

  // Geofence state
  Map<String, dynamic>? _geofence;

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _bg        = Color(0xFFF7F4F2);
  static const _card      = Colors.white;
  static const _accent    = Color(0xFF5A7A1A);
  static const _accentSoft = Color(0xFFEEF3E6);
  static const _rose      = Color(0xFFD4A5A5);
  static const _roseSoft  = Color(0xFFF4E4E1);
  static const _text      = Color(0xFF1E1A18);
  static const _subtext   = Color(0xFF7A6E6A);
  static const _warning   = Color(0xFFF57C00);
  static const _warningSoft = Color(0xFFFFF3E0);

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
    _listenToGeofence();

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
    _geofenceSubscription?.cancel();
    _animController.dispose();
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────

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

  // ── Geofence ──────────────────────────────────────────────────────────────

  void _listenToGeofence() {
    _geofenceSubscription =
        _geofenceService.listenToGeofence(widget.patientId).listen((data) {
          if (mounted) setState(() => _geofence = data);
        });
  }

  bool get _isOutsideGeofence {
    if (_geofence == null || !(_geofence!['isActive'] as bool? ?? false)) {
      return false;
    }
    final distance = GeofenceService.distanceInMeters(
      _currentPosition.latitude,
      _currentPosition.longitude,
      _geofence!['centerLat'] as double,
      _geofence!['centerLng'] as double,
    );
    return distance > (_geofence!['radiusMeters'] as double);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
          Positioned(
            top: -50, right: -50,
            child: Container(
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _rose.withOpacity(0.14),
              ),
            ),
          ),
          Positioned(
            bottom: 60, left: -70,
            child: Container(
              width: 260, height: 260,
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
                // Out-of-zone warning banner
                if (_isOutsideGeofence) _buildBreachBanner(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: (!_isLoading && !_noLocationAvailable)
          ? _buildFABs()
          : null,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Breach banner ─────────────────────────────────────────────────────────
  Widget _buildBreachBanner() {
    final distance = GeofenceService.distanceInMeters(
      _currentPosition.latitude,
      _currentPosition.longitude,
      _geofence!['centerLat'] as double,
      _geofence!['centerLng'] as double,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _warningSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _warning.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.warning_amber_rounded,
                size: 18, color: _warning),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Outside Safe Zone',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: _warning),
                ),
                Text(
                  '${widget.patientName} is ${GeofenceService.formatDistance(distance)} from '
                      '"${_geofence!['label']}"',
                  style: TextStyle(
                      fontSize: 12,
                      color: _warning.withOpacity(0.8)),
                ),
              ],
            ),
          ),
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
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB07A6E).withOpacity(0.12),
                    blurRadius: 12, offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _text, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Row(
            children: [
              ColoredBox(
                color: _bg,
                child: Image.asset(
                  'assets/images/logo_no_text.png',
                  width: 26, height: 26,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.favorite_rounded, color: _rose, size: 22),
                ),
              ),
              const SizedBox(width: 7),
              RichText(
                text: const TextSpan(children: [
                  TextSpan(
                    text: 'Cogni',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w300,
                        color: Color(0xFF5D4037), letterSpacing: -0.5),
                  ),
                  TextSpan(
                    text: 'Care',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: Color(0xFF5D4037), letterSpacing: -0.5),
                  ),
                ]),
              ),
            ],
          ),
          const Spacer(),
          // Geofence status pill
          if (_geofence != null)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (_geofence!['isActive'] as bool? ?? false)
                    ? _accentSoft
                    : const Color(0xFFF0EBE8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_rounded,
                    size: 13,
                    color: (_geofence!['isActive'] as bool? ?? false)
                        ? _accent
                        : _subtext,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    (_geofence!['isActive'] as bool? ?? false)
                        ? 'Zone On'
                        : 'Zone Off',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: (_geofence!['isActive'] as bool? ?? false)
                          ? _accent
                          : _subtext,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Patient strip ─────────────────────────────────────────────────────────
  Widget _buildPatientStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _roseSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_rounded, size: 14, color: _rose),
                const SizedBox(width: 6),
                Text(
                  widget.patientName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: _rose),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Map body ──────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _accent),
      );
    }
    if (_noLocationAvailable) {
      return _buildNoLocationView();
    }
    return _buildMapView();
  }

  Widget _buildMapView() {
    final hasGeofence = _geofence != null;
    final geofenceActive = hasGeofence &&
        (_geofence!['isActive'] as bool? ?? false);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition,
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.cognicare.app',
                  retinaMode: MediaQuery.of(context).devicePixelRatio > 1.0,
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      '© OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.parse('https://openstreetmap.org/copyright'),
                      ),
                    ),
                  ],
                  alignment: AttributionAlignment.bottomLeft,
                  popupBackgroundColor: Colors.white,
                  popupBorderRadius: BorderRadius.circular(8),
                ),

                // ── Geofence circle ──────────────────────────────────────
                if (hasGeofence)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(
                          _geofence!['centerLat'] as double,
                          _geofence!['centerLng'] as double,
                        ),
                        radius: _geofence!['radiusMeters'] as double,
                        color: (geofenceActive ? _accent : _subtext)
                            .withOpacity(0.12),
                        borderColor: (geofenceActive ? _accent : _subtext)
                            .withOpacity(0.55),
                        borderStrokeWidth: 2.0,
                        useRadiusInMeter: true,
                      ),
                    ],
                  ),

                // ── Geofence center pin ──────────────────────────────────
                if (hasGeofence)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          _geofence!['centerLat'] as double,
                          _geofence!['centerLng'] as double,
                        ),
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            color: (geofenceActive ? _accent : _subtext)
                                .withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: geofenceActive ? _accent : _subtext,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.shield_rounded,
                            size: 14,
                            color: geofenceActive ? _accent : _subtext,
                          ),
                        ),
                      ),
                    ],
                  ),

                // ── Patient marker ───────────────────────────────────────
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition,
                      width: 48,
                      height: 56,
                      child: Column(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: _rose,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _rose.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.person_rounded,
                                color: Colors.white, size: 20),
                          ),
                          CustomPaint(
                            size: const Size(10, 8),
                            painter: _TrianglePainter(color: _rose),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Last-updated card
            Positioned(
              top: 16, left: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB07A6E).withOpacity(0.10),
                      blurRadius: 16, offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34, height: 34,
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
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: _subtext, letterSpacing: 0.4),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _getLastUpdateText(),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: _text),
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
                            width: 6, height: 6,
                            decoration: const BoxDecoration(
                              color: _accent, shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text('Live',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700,
                                  color: _accent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Geofence label (bottom of map, above FAB area)
            if (hasGeofence)
              Positioned(
                bottom: 16, left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _card.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: geofenceActive
                          ? _accent.withOpacity(0.3)
                          : _subtext.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_rounded,
                          size: 12,
                          color: geofenceActive ? _accent : _subtext),
                      const SizedBox(width: 5),
                      Text(
                        '${_geofence!['label']}  •  '
                            '${GeofenceService.formatDistance(_geofence!['radiusMeters'] as double)}',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: geofenceActive ? _accent : _subtext),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoLocationView() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: _roseSoft,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.location_off_rounded,
                    size: 38, color: _rose),
              ),
              const SizedBox(height: 20),
              const Text(
                'No location available',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: _text),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ask the patient to open the app\nto share their location.',
                style: TextStyle(
                    fontSize: 14, color: _subtext, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _retryLoadLocation,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── FABs ──────────────────────────────────────────────────────────────────
  Widget _buildFABs() {
    return FloatingActionButton.extended(
      onPressed: _centerOnLocation,
      backgroundColor: _accent,
      elevation: 4,
      icon: const Icon(Icons.my_location_rounded, color: Colors.white, size: 20),
      label: const Text(
        'Center',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );
  }

  // ── Bottom nav ────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB07A6E).withOpacity(0.10),
            blurRadius: 16, offset: const Offset(0, -4),
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
                  Navigator.pushReplacement(
                      context,
                      InstantPushMaterialRoute(
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
                  Navigator.pushReplacement(
                      context,
                      InstantPushMaterialRoute(
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
                  Navigator.pushReplacement(
                      context,
                      InstantPushMaterialRoute(
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
}

// ── Triangle painter (map pin tail) ──────────────────────────────────────────
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
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
          Icon(icon, size: 24,
              color: active
                  ? const Color(0xFF5A7A1A)
                  : const Color(0xFFBDB0AC)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? const Color(0xFF5A7A1A)
                      : const Color(0xFFBDB0AC))),
        ],
      ),
    );
  }
}