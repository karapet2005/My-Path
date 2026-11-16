import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path; 
import 'package:path_provider/path_provider.dart'; 
import 'package:share_plus/share_plus.dart'; 
import 'database_helper.dart';
import 'models.dart';
import 'app_localizations.dart';

class PlanningTab extends StatefulWidget {
  final String currentLocale;
  const PlanningTab({super.key, required this.currentLocale});

  @override
  State<PlanningTab> createState() => _PlanningTabState();
}

class _PlanningTabState extends State<PlanningTab> {
  final MapController _planningMapController = MapController();
  final List<LatLng> _currentDraftRoute = [];
  SavedRoute? _selectedSavedRoute;

  double _calculateDraftDistance() {
    if (_currentDraftRoute.length < 2) return 0.0;
    const distance = Distance();
    double totalMeters = 0;
    for (int i = 0; i < _currentDraftRoute.length - 1; i++) {
      totalMeters += distance.as(LengthUnit.Meter, _currentDraftRoute[i], _currentDraftRoute[i + 1]);
    }
    return totalMeters / 1000.0;
  }

  void _saveCurrentDraftSheet() {
    final t = AppLocalizations(widget.currentLocale);
    final distance = _calculateDraftDistance();
    TextEditingController nameController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: const Color(0xFF121620),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 25, right: 25, top: 25,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            Text(t.translate('saveRoute'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 10),
            Text("Distanz: ${distance.toStringAsFixed(2)} km", style: const TextStyle(color: Colors.greenAccent, fontSize: 16)),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              autofocus: true,
              decoration: InputDecoration(
                labelText: t.translate('routeName'),
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.greenAccent)),
                filled: true,
                fillColor: Colors.white.withAlpha(10),
              ),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent, 
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  await DatabaseHelper.instance.saveRoute(nameController.text, _currentDraftRoute, distance);
                  if (mounted) {
                    setState(() {
                      _currentDraftRoute.clear();
                    });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.translate('routeSavedSuccess'), style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.greenAccent));
                  }
                }
              },
              child: Text(t.translate('saveRoute'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _showSavedRoutesSheet() async {
    final t = AppLocalizations(widget.currentLocale);
    final routeData = await DatabaseHelper.instance.getAllSavedRoutes();
    final loadedRoutes = routeData.map((row) {
      final pointsStr = row['points'] as String;
      final pointList = pointsStr.split(';').map((p) {
        final coords = p.split(',');
        return LatLng(double.parse(coords[0]), double.parse(coords[1]));
      }).toList();

      return SavedRoute(
        id: row['id'] as int,
        name: row['name'] as String,
        distanceKm: row['distanceKm'] as double,
        points: pointList,
      );
    }).toList();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121620),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            Text(t.translate('savedRoutes'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 15),
            loadedRoutes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(t.translate('noRoutesAvailable'), style: const TextStyle(color: Colors.white54)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: loadedRoutes.length,
                    itemBuilder: (context, index) {
                      final route = loadedRoutes[index];
                      return ListTile(
                        leading: const Icon(Icons.route, color: Colors.greenAccent),
                        title: Text(route.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${route.distanceKm.toStringAsFixed(2)} km"),
                        onTap: () {
                          setState(() {
                            _selectedSavedRoute = route;
                            _currentDraftRoute.clear();
                          });
                          _planningMapController.move(route.points.first, 14.0);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _exportRouteToGPX(SavedRoute route) async {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="My Path App">');
    buffer.writeln('  <trk>');
    buffer.writeln('    <name>${route.name}</name>');
    buffer.writeln('    <trkseg>');
    for (var point in route.points) {
      buffer.writeln('      <trkpt lat="${point.latitude}" lon="${point.longitude}"></trkpt>');
    }
    buffer.writeln('    </trkseg>');
    buffer.writeln('  </trk>');
    buffer.writeln('</gpx>');

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${route.name.replaceAll(' ', '_')}.gpx');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles([XFile(file.path)], text: 'Hier ist meine Route aus My Path: ${route.name}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations(widget.currentLocale);
    final activePoints = _selectedSavedRoute != null ? _selectedSavedRoute!.points : _currentDraftRoute;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _planningMapController,
            options: MapOptions(
              initialCenter: const LatLng(51.165691, 10.451526),
              initialZoom: 6.0,
              maxZoom: 18.0, 
              onTap: (tapPosition, point) => setState(() { _selectedSavedRoute = null; _currentDraftRoute.add(point); }),
            ),
            children: [
              TileLayer(
                // HIER: Der neue Google-Maps-ähnliche Style (Hell, mit klaren Straßen)
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.path_tracker',
              ),
              if (activePoints.isNotEmpty) 
                PolylineLayer(
                  polylines: [
                    Polyline(points: activePoints, strokeWidth: 5.0, color: _selectedSavedRoute != null ? Colors.greenAccent : Colors.blueAccent)
                  ]
                ),
            ],
          ),
          
          Positioned(
            top: 50, right: 20,
            child: FloatingActionButton(
              heroTag: 'load_route_btn',
              backgroundColor: Colors.black.withAlpha(200),
              onPressed: _showSavedRoutesSheet,
              child: const Icon(Icons.folder_open, color: Colors.greenAccent),
            ),
          ),
          
          if (_currentDraftRoute.isEmpty && _selectedSavedRoute == null)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 60.0, right: 60.0), 
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(200),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app, color: Colors.greenAccent, size: 20),
                      const SizedBox(width: 10),
                      Text(t.translate('planningHint'), style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          
          if (_currentDraftRoute.isNotEmpty)
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(220),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.translate('draft'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        Text("${_calculateDraftDistance().toStringAsFixed(2)} km", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => setState(() => _currentDraftRoute.clear()),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                          icon: const Icon(Icons.save),
                          label: Text(t.translate('saveRoute')),
                          onPressed: _saveCurrentDraftSheet,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          if (_selectedSavedRoute != null)
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(220),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blueAccent.withAlpha(100)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_selectedSavedRoute!.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                          Text("${_selectedSavedRoute!.distanceKm.toStringAsFixed(2)} km", style: const TextStyle(color: Colors.blueAccent, fontSize: 14)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                          icon: const Icon(Icons.share, size: 18),
                          label: Text(t.translate('gpxExport')),
                          onPressed: () => _exportRouteToGPX(_selectedSavedRoute!),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => setState(() => _selectedSavedRoute = null),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}