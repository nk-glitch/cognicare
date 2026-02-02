import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_service.dart';

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

class _LocationMapPageState extends State<LocationMapPage> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  LatLng _currentPosition = const LatLng(37.7749, -122.4194);
  bool _isLoading = true;
  bool _noLocationAvailable = false;
  DateTime? _lastUpdate;
  StreamSubscription<Map<String, dynamic>?>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialLocation();
    _listenToLocation();
    // If no location after 3s, show "no location" state so caretaker knows what to do
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _noLocationAvailable = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialLocation() async {
    final storedLocation = await _locationService.getStoredLocation(widget.patientId);
    if (storedLocation != null && storedLocation.isNotEmpty && mounted) {
      setState(() {
        _isLoading = false;
        _noLocationAvailable = false;
        _currentPosition = LatLng(
          storedLocation['latitude'] as double,
          storedLocation['longitude'] as double,
        );
        if (storedLocation['timestamp'] != null) {
          _lastUpdate = DateTime.fromMillisecondsSinceEpoch(
            storedLocation['timestamp'] as int,
          );
        }
      });
    }
  }

  Future<void> _retryLoadLocation() async {
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
    }
  }

  void _listenToLocation() {
    _locationSubscription = _locationService
        .listenToLocation(widget.patientId)
        .listen((data) {
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
              data['timestamp'] as int,
            );
          }
        });
        _mapController.move(_currentPosition, 15.0);
      }
    }, onError: (error) {
      print('Error in location stream: $error');
    });
  }

  String _getLastUpdateText() {
    if (_lastUpdate == null) return 'Just now';
    final difference = DateTime.now().difference(_lastUpdate!);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    return '${difference.inHours} hr ago';
  }

  void _centerOnLocation() {
    _mapController.move(_currentPosition, 16.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6E8),
      appBar: AppBar(
        title: Text(
          '${widget.patientName}\'s Location',
          style: const TextStyle(
            color: Color(0xFF3D2C31),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: const Color(0xFFE8C4C8),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3D2C31)),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: Color(0xFF8FA9C9),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Waiting for location...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Patient can share location from their app',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            )
          : _noLocationAvailable
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No location shared yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Ask ${widget.patientName} to open the app and tap "Allow location" on their home screen. Location works best with GPS on and outdoors.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _retryLoadLocation,
                          icon: const Icon(Icons.refresh, size: 22),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8FA9C9),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPosition,
                    initialZoom: 15.0,
                    minZoom: 5.0,
                    maxZoom: 18.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.cognicare',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _currentPosition,
                          width: 150,
                          height: 80,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8FA9C9),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  widget.patientName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Icon(
                                Icons.location_on,
                                color: Color(0xFFD47A8A),
                                size: 40,
                                shadows: [
                                  Shadow(
                                    color: Colors.black38,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 20,
                          color: Color(0xFF8FA9C9),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Last updated: ${_getLastUpdateText()}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF5A4046),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: (_isLoading || _noLocationAvailable)
          ? null
          : FloatingActionButton(
              onPressed: _centerOnLocation,
              backgroundColor: const Color(0xFF8FA9C9),
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
    );
  }
}
