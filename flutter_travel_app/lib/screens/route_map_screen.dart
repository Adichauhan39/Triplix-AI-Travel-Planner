import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../services/maps_service.dart';

class RouteMapScreen extends StatefulWidget {
  final String origin;
  final String destination;
  final String mode;

  const RouteMapScreen({
    super.key,
    required this.origin,
    required this.destination,
    this.mode = 'driving',
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  GoogleMapController? _mapController;
  final MapsService _mapsService = MapsService();

  RouteInfo? _routeInfo;
  bool _isLoading = true;
  String? _error;
  String _selectedMode = 'driving';
  bool _showSteps = false;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.mode;
    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final routeInfo = await _mapsService.getDirections(
        origin: widget.origin,
        destination: widget.destination,
        mode: _selectedMode,
      );

      _markers = {
        Marker(
          markerId: const MarkerId('origin'),
          position: routeInfo.originLatLng,
          infoWindow: InfoWindow(
            title: 'From: ${widget.origin}',
            snippet: routeInfo.origin,
          ),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: routeInfo.destinationLatLng,
          infoWindow: InfoWindow(
            title: 'To: ${widget.destination}',
            snippet: routeInfo.destination,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };

      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: routeInfo.polylinePoints,
          color: AppConfig.primaryColor,
          width: 5,
          patterns: _selectedMode == 'transit'
              ? [PatternItem.dash(20), PatternItem.gap(10)]
              : [],
        ),
      };

      setState(() {
        _routeInfo = routeInfo;
        _isLoading = false;
      });

      // Animate camera to fit route
      if (routeInfo.polylinePoints.length >= 2 && _mapController != null) {
        final bounds =
            _mapsService.boundsFromPoints(routeInfo.polylinePoints);
        _mapController!
            .animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // If route is already loaded, fit camera
    if (_routeInfo != null && _routeInfo!.polylinePoints.length >= 2) {
      Future.delayed(const Duration(milliseconds: 300), () {
        final bounds =
            _mapsService.boundsFromPoints(_routeInfo!.polylinePoints);
        controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
      });
    }
  }

  String _getModeIcon(String mode) {
    switch (mode) {
      case 'driving':
        return '🚗';
      case 'transit':
        return '🚆';
      case 'walking':
        return '🚶';
      default:
        return '🚗';
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.origin} → ${widget.destination}'),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Travel mode selector
          _buildModeSelector(),

          // Map
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(
                      AppConfig.defaultLatitude,
                      AppConfig.defaultLongitude,
                    ),
                    zoom: 5,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),

                // Loading overlay
                if (_isLoading)
                  Container(
                    color: Colors.white.withValues(alpha: 0.7),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: AppConfig.primaryColor,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Finding best route...',
                            style: TextStyle(
                              color: AppConfig.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Error overlay
                if (_error != null)
                  Container(
                    color: Colors.white.withValues(alpha: 0.9),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: AppConfig.errorColor),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppConfig.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchRoute,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Zoom controls
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    children: [
                      _buildMapButton(
                        icon: Icons.add,
                        onTap: () => _mapController
                            ?.animateCamera(CameraUpdate.zoomIn()),
                      ),
                      const SizedBox(height: 8),
                      _buildMapButton(
                        icon: Icons.remove,
                        onTap: () => _mapController
                            ?.animateCamera(CameraUpdate.zoomOut()),
                      ),
                      const SizedBox(height: 8),
                      _buildMapButton(
                        icon: Icons.fit_screen,
                        onTap: () {
                          if (_routeInfo != null &&
                              _routeInfo!.polylinePoints.length >= 2) {
                            final bounds = _mapsService
                                .boundsFromPoints(_routeInfo!.polylinePoints);
                            _mapController?.animateCamera(
                                CameraUpdate.newLatLngBounds(bounds, 60));
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Route info card
          if (_routeInfo != null) _buildRouteInfoCard(),

          // Steps panel
          if (_showSteps && _routeInfo != null) _buildStepsPanel(),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildModeChip('driving', '🚗', 'Drive'),
          _buildModeChip('transit', '🚆', 'Transit'),
          _buildModeChip('walking', '🚶', 'Walk'),
        ],
      ),
    );
  }

  Widget _buildModeChip(String mode, String icon, String label) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        if (_selectedMode != mode) {
          setState(() => _selectedMode = mode);
          _fetchRoute();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppConfig.primaryColor
              : AppConfig.primaryColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? AppConfig.primaryColor
                : AppConfig.borderColor,
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppConfig.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteInfoCard() {
    final route = _routeInfo!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Origin
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.origin,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Distance/Duration
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: AppConfig.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      route.distance,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      route.duration,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Destination
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            widget.destination,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${_getModeIcon(_selectedMode)}  via ${_selectedMode == 'driving' ? 'Road' : _selectedMode == 'transit' ? 'Public Transit' : 'Walking'}',
                style: const TextStyle(
                  color: AppConfig.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (route.steps.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _showSteps = !_showSteps),
                  child: Row(
                    children: [
                      Text(
                        _showSteps ? 'Hide Steps' : '${route.steps.length} Steps',
                        style: const TextStyle(
                          color: AppConfig.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        _showSteps
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        color: AppConfig.primaryColor,
                        size: 18,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepsPanel() {
    final steps = _routeInfo!.steps;
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: AppConfig.borderColor)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: steps.length,
        itemBuilder: (context, index) {
          final step = steps[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppConfig.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppConfig.primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.instruction,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${step.distance} • ${step.duration}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppConfig.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppConfig.textPrimary),
        ),
      ),
    );
  }
}
