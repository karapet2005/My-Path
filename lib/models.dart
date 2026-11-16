import 'package:latlong2/latlong.dart';

class SavedRoute {
  final int id;
  final String name;
  final List<LatLng> points;
  final double distanceKm;

  SavedRoute({
    required this.id,
    required this.name,
    required this.points,
    required this.distanceKm,
  });
}