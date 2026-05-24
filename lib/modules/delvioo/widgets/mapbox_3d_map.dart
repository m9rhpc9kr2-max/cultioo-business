import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:latlong2/latlong.dart';

/// Modern 3D MapBox Map Widget with real 3D buildings
class MapBox3DMap extends StatefulWidget {
  final LatLng? initialCenter;
  final double initialZoom;
  final bool isLightMode;
  final Function(LatLng)? onMapTap;
  final List<Widget> overlayWidgets;

  const MapBox3DMap({
    super.key,
    this.initialCenter,
    this.initialZoom = 13.0,
    required this.isLightMode,
    this.onMapTap,
    this.overlayWidgets = const [],
  });

  @override
  State<MapBox3DMap> createState() => _MapBox3DMapState();
}

class _MapBox3DMapState extends State<MapBox3DMap> {
  @override
  Widget build(BuildContext context) {
    final center = widget.initialCenter ?? const LatLng(51.3571486, 6.638026);

    return Stack(
      children: [
        MapWidget(
          key: ValueKey('mapbox_3d_${widget.isLightMode ? 'light' : 'dark'}'),
          cameraOptions: CameraOptions(
            center: Point(
              coordinates: Position(center.longitude, center.latitude),
            ),
            zoom: widget.initialZoom,
            pitch: 45.0, // 3D viewing angle
            bearing: 0.0,
          ),
          styleUri: widget.isLightMode
              ? MapboxStyles
                    .STANDARD // Modern standard style with 3D
              : MapboxStyles.DARK, // Dark mode with 3D
          textureView: true, // Better performance on mobile
          onMapCreated: _onMapCreated,
          onTapListener: _onMapTap,
        ),
        // Overlay widgets (markers, controls, etc.)
        ...widget.overlayWidgets,
      ],
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) {
    print('🗺️ MapBox 3D Map created successfully with 3D buildings');
  }

  void _onMapTap(MapContentGestureContext context) {
    if (widget.onMapTap != null) {
      final point = context.point;
      widget.onMapTap!(
        LatLng(
          point.coordinates.lat.toDouble(),
          point.coordinates.lng.toDouble(),
        ),
      );
    }
  }
}
