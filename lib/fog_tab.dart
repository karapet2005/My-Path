import 'dart:async';
import 'dart:ui' as ui; 
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle; 
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path; 
import 'package:audioplayers/audioplayers.dart'; 
import 'package:permission_handler/permission_handler.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'database_helper.dart';
import 'models.dart'; 
import 'app_localizations.dart';
import 'unit_helper.dart';

class FogOfWarTab extends StatefulWidget {
  final String currentLocale;
  const FogOfWarTab({super.key, required this.currentLocale});

  @override
  State<FogOfWarTab> createState() => _FogOfWarTabState();
}

class _FogOfWarTabState extends State<FogOfWarTab> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  final MapController _mapController = MapController();
  final AudioPlayer _audioPlayer = AudioPlayer(); 
  
  LatLng? _currentLocation;
  
  // HIER DIE TRENNUNG: Alte Wege und der aktuelle Weg
  List<List<LatLng>> _pastPaths = []; 
  List<LatLng> _currentSessionPath = []; 
  
  bool _isTracking = false;
  bool _isPaused = false; 

  StreamSubscription<Position>? _positionStream; 

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  
  final ValueNotifier<int> _elapsedSeconds = ValueNotifier<int>(0); 
  
  double _tripDistanceKm = 0.0;
  double _totalStoredKm = 0.0;
  int _currentStreak = 0; 
  int _lastAnnouncedKm = 0;
  List<SavedRoute> _allSavedRoutes = [];
  SavedRoute? _activeNavigationRoute;

  late AnimationController _effectController;
  late AnimationController _driftController; 
  ui.Image? _fogTexture; 

  // Kombiniert alte und neue Wege, damit der FogPainter überall den Nebel löscht
  List<List<LatLng>> get _allPathsToDraw {
    List<List<LatLng>> paths = List.from(_pastPaths);
    if (_currentSessionPath.isNotEmpty) {
      paths.add(_currentSessionPath);
    }
    return paths;
  }

  @override
  void initState() {
    super.initState();
    _loadFogTexture(); 
    _loadSavedPathStatsAndRoutes(); 

    _effectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() {
        if (mounted) setState(() {});
      });

    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();

    UnitHelper.instance.useMilesNotifier.addListener(_onUnitChanged);
  }

  @override
  void dispose() {
    UnitHelper.instance.useMilesNotifier.removeListener(_onUnitChanged);
    _positionStream?.cancel(); 
    _timer?.cancel();
    _effectController.dispose();
    _driftController.dispose(); 
    _audioPlayer.dispose(); 
    _elapsedSeconds.dispose();
    super.dispose();
  }

  void _onUnitChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFogTexture() async {
    try {
      final ByteData data = await rootBundle.load('assets/fog.png');
      final ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final ui.FrameInfo fi = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _fogTexture = fi.image;
        });
      }
    } catch (e) {
      debugPrint("Konnte assets/fog.png nicht laden. Fehler: $e");
    }
  }

  // Zerschneidet die Datenbank-Punkte, wenn die Lücke dazwischen > 150m ist
  List<List<LatLng>> _splitPaths(List<LatLng> points) {
    if (points.isEmpty) return [];
    List<List<LatLng>> paths = [];
    List<LatLng> current = [points.first];
    const distanceCalc = Distance();

    for (int i = 1; i < points.length; i++) {
      if (distanceCalc.as(LengthUnit.Meter, points[i - 1], points[i]) > 150.0) {
        paths.add(current);
        current = [points[i]];
      } else {
        current.add(points[i]);
      }
    }
    if (current.isNotEmpty) paths.add(current);
    return paths;
  }

  Future<void> _loadSavedPathStatsAndRoutes() async {
    final savedPoints = await DatabaseHelper.instance.getAllLocations();
    final total = await DatabaseHelper.instance.getTotalKm();
    final streak = await DatabaseHelper.instance.getStreak(); 
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
    setState(() {
      _totalStoredKm = total;
      _currentStreak = streak; 
      _allSavedRoutes = loadedRoutes;
      
      // Wir laden alle alten Punkte und zerschneiden sie sauber in Segmente
      _pastPaths = _splitPaths(savedPoints);
      
      if (savedPoints.isNotEmpty && !_isTracking) {
        _currentLocation = savedPoints.last;
      }
    });
  }

  Future<void> _showRouteSelectionSheet() async {
    final t = AppLocalizations(widget.currentLocale);
    await _loadSavedPathStatsAndRoutes(); 
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121620),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              Text(t.translate('routeSelection'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 15),
              _allSavedRoutes.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(t.translate('noRoute'), style: const TextStyle(color: Colors.white54)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _allSavedRoutes.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ListTile(
                            leading: const Icon(Icons.close, color: Colors.redAccent),
                            title: Text(t.translate('noRoute'), style: const TextStyle(color: Colors.redAccent)),
                            onTap: () {
                              setState(() => _activeNavigationRoute = null);
                              Navigator.pop(context);
                            },
                          );
                        }
                        final route = _allSavedRoutes[index - 1];
                        final formattedDist = UnitHelper.instance.formatDistance(route.distanceKm);
                        final unit = UnitHelper.instance.getUnitLabel();
                        return ListTile(
                          leading: const Icon(Icons.route, color: Colors.blueAccent),
                          title: Text(route.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("${formattedDist.toStringAsFixed(2)} $unit"),
                          onTap: () {
                            setState(() => _activeNavigationRoute = route);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _startTimer() {
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      _elapsedSeconds.value = _stopwatch.elapsed.inSeconds; 
      setState(() {});
    });
  }

  void _stopTimer() {
    _stopwatch.stop();
    _timer?.cancel();
  }

  double _calculatePathDistance(List<LatLng> points) {
    if (points.length < 2) return 0.0;
    const distance = Distance();
    double totalMeters = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalMeters += distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return totalMeters / 1000.0;
  }

  void _checkKilometerMilestone(double currentKm) async {
    int currentFullKm = currentKm.floor(); 
    if (currentFullKm > _lastAnnouncedKm) {
      _lastAnnouncedKm = currentFullKm;
      
      final prefs = await SharedPreferences.getInstance();
      bool audioEnabled = prefs.getBool('audio_enabled') ?? true;

      if (audioEnabled) {
        try {
          await _audioPlayer.play(AssetSource('audio/kilometer.mp3'));
        } catch (e) {
          debugPrint("Audio-Fehler (Kilometer): $e");
        }
      }
    }
  }

  Future<void> _processNewPosition(LatLng newPoint) async {
    final t = AppLocalizations(widget.currentLocale);
    bool isNewTile = await DatabaseHelper.instance.exploreTile(newPoint.latitude, newPoint.longitude);
    
    if (isNewTile && mounted) {
      _effectController.forward(from: 0.0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.translate('newTile'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.greenAccent,
          duration: const Duration(milliseconds: 1200),
        ),
      );
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte aktiviere die GPS-Ortung auf deinem Gerät.')),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Standortberechtigung wurde verweigert.')),
        );
        return false;
      }
    }
    return true;
  }

  void _startTracking() async {
    bool hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    if (!mounted) return;
    setState(() {
      _isTracking = true;
      _isPaused = false;
      _tripDistanceKm = 0.0;
      _lastAnnouncedKm = 0;
      // HIER LEEREN WIR NUR DIE AKTUELLE ROUTE - ALTE BLEIBEN ERHALTEN
      _currentSessionPath.clear();
      _stopwatch.reset();
      _elapsedSeconds.value = 0;
    });
    _startTimer();

    try {
      Position initialPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      LatLng startPoint = LatLng(initialPos.latitude, initialPos.longitude);
      
      await _processNewPosition(startPoint);
      await DatabaseHelper.instance.insertLocation(startPoint);

      if (mounted) {
        setState(() {
          _currentLocation = startPoint;
          _currentSessionPath = [startPoint];
        });
        _mapController.move(startPoint, 16.0);
      }
    } catch (e) {
      debugPrint("Fehler beim initialen Standort: $e");
    }

    LocationSettings locationSettings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(accuracy: LocationAccuracy.high, distanceFilter: 2, forceLocationManager: true, intervalDuration: const Duration(seconds: 3))
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2);

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      if (_isPaused) return;
      if (position.accuracy > 35.0) return; 

      final newPoint = LatLng(position.latitude, position.longitude);
      _processNewPosition(newPoint);

      if (!mounted) return;
      
      setState(() {
        _currentLocation = newPoint;
        _currentSessionPath.add(newPoint);
        _tripDistanceKm = _calculatePathDistance(_currentSessionPath);
      });

      _checkKilometerMilestone(_tripDistanceKm);
      DatabaseHelper.instance.insertLocation(newPoint);
      _mapController.move(newPoint, 16.0);
    });
  }

  void _togglePause() async {
    setState(() {
      _isPaused = !_isPaused;
    });
    
    if (_isPaused) {
      _stopwatch.stop(); 
    } else {
      _stopwatch.start(); 
    }
  }

  void _stopTracking() async {
    _positionStream?.cancel();
    _stopTimer();

    final finalDistance = _tripDistanceKm;
    final finalTime = Duration(seconds: _elapsedSeconds.value).toString().split('.').first.padLeft(8, '0');
    
    double paceMinPerKm = 0.0;
    if (finalDistance > 0 && _stopwatch.elapsedMilliseconds > 0) {
      paceMinPerKm = (_stopwatch.elapsedMilliseconds / 60000.0) / finalDistance;
    }
    
    String finalPace = "--:--";
    if (paceMinPerKm > 0 && paceMinPerKm < 100) {
       int pMin = paceMinPerKm.floor();
       int pSec = ((paceMinPerKm - pMin) * 60).round();
       finalPace = "$pMin:${pSec.toString().padLeft(2, '0')} min/km";
    }

    double oldTotal = _totalStoredKm;

    if (finalDistance > 0) {
      await DatabaseHelper.instance.addTotalKm(finalDistance);
      await DatabaseHelper.instance.updateStreak(); 
      
      final updatedTotal = await DatabaseHelper.instance.getTotalKm();
      final updatedStreak = await DatabaseHelper.instance.getStreak(); 
      
      if (!mounted) return;
      setState(() {
        _totalStoredKm = updatedTotal;
        _currentStreak = updatedStreak; 
      });
    }

    double newTotal = _totalStoredKm; 

    if (!mounted) return;
    setState(() {
      _isTracking = false;
      _isPaused = false;
      // Aktuelle Route wird jetzt zu den alten Routen hinzugefügt
      if (_currentSessionPath.isNotEmpty) {
        _pastPaths.add(List.from(_currentSessionPath));
      }
    });
    
    _showSummarySheet(finalTime, finalDistance, finalPace, oldTotal, newTotal);
  }

  void _showSummarySheet(String time, double distance, String pace, double oldTotal, double newTotal) async {
    final formattedDist = UnitHelper.instance.formatDistance(distance);
    final formattedNewTotal = UnitHelper.instance.formatDistance(newTotal);
    final unit = UnitHelper.instance.getUnitLabel();

    showModalBottomSheet(
      context: context,
      isDismissible: false, 
      enableDrag: false, 
      backgroundColor: const Color(0xFF121620),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events, color: Colors.greenAccent),
                  SizedBox(width: 10),
                  Text("Erkundung beendet!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 20),
              _buildSummaryRow("Gegangene Strecke", "${formattedDist.toStringAsFixed(2)} $unit", Icons.straighten),
              _buildSummaryRow("Dauer", time, Icons.timer),
              _buildSummaryRow("Average Pace", pace, Icons.speed),
              const Divider(color: Colors.white24, height: 30),
              _buildSummaryRow("Neue Gesamtstrecke", "${formattedNewTotal.toStringAsFixed(2)} $unit", Icons.public),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent, 
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("WEITER GEHT'S!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.2)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      }
    );
  }

  Widget _buildSummaryRow(String label, String value, IconData icon) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: Colors.white54),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ]),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 
    final t = AppLocalizations(widget.currentLocale);

    double paceMinPerKm = (_tripDistanceKm > 0 && _stopwatch.elapsedMilliseconds > 0) 
        ? (_stopwatch.elapsedMilliseconds / 60000.0) / _tripDistanceKm 
        : 0.0;
    
    if (UnitHelper.instance.useMiles) {
      paceMinPerKm = paceMinPerKm * 1.60934;
    }
    
    String formattedPace = "--:--";
    if (paceMinPerKm > 0 && paceMinPerKm < 100) {
      int pMin = paceMinPerKm.floor();
      int pSec = ((paceMinPerKm - pMin) * 60).round();
      formattedPace = "$pMin:${pSec.toString().padLeft(2, '0')} min/${UnitHelper.instance.getUnitLabel()}";
    }

    final formattedTotal = UnitHelper.instance.formatDistance(_totalStoredKm);
    final formattedTrip = UnitHelper.instance.formatDistance(_tripDistanceKm);
    final unit = UnitHelper.instance.getUnitLabel();

    return Scaffold(
      extendBodyBehindAppBar: true, 
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(51.165691, 10.451526),
              initialZoom: 16.0, 
              maxZoom: 18.0, 
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.none, 
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.path_tracker',
              ),
              
              if (_activeNavigationRoute != null)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _activeNavigationRoute!.points, strokeWidth: 6.0, color: Colors.blueAccent.withAlpha(150)),
                  ],
                ),

              IgnorePointer( 
                child: AnimatedBuilder(
                  animation: _driftController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: FogPainter(
                        exploredPaths: _allPathsToDraw, // Hier wird ALLES an den Painter übergeben
                        currentLocation: _currentLocation,
                        camera: MapCamera.of(context),
                        fogImage: _fogTexture,
                        driftValue: _driftController.value,
                      ),
                      child: const SizedBox.expand(),
                    );
                  }
                ),
              ),
              
              // Zeichne ALLE vergangenen Routen gedimmt
              for (var path in _pastPaths)
                PolylineLayer(
                  polylines: [
                    Polyline(points: path, strokeWidth: 4.0, color: Colors.greenAccent.withAlpha(80)),
                  ],
                ),

              // Zeichne die AKTUELLE Route leuchtend
              if (_currentSessionPath.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _currentSessionPath, strokeWidth: 4.0, color: Colors.greenAccent),
                  ],
                ),
                
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.greenAccent, blurRadius: 10, spreadRadius: 2)],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          Positioned(
            top: 50, left: 20, right: 20,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(200),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('My Path', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text('${t.translate('total')}: ${formattedTotal.toStringAsFixed(2)} $unit', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                      Row(
                        children: [
                          if (_currentStreak > 0) ...[
                            const Text("🔥", style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 4),
                            Text("$_currentStreak", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                            const SizedBox(width: 15),
                          ],
                          IconButton(
                            icon: Icon(Icons.navigation, color: _activeNavigationRoute != null ? Colors.blueAccent : Colors.grey),
                            onPressed: _showRouteSelectionSheet, 
                          ),
                          Icon(_isTracking ? Icons.satellite_alt : Icons.location_off, color: _isTracking ? Colors.greenAccent : Colors.grey),
                        ],
                      ),
                    ],
                  ),
                ),
                
                if (_isTracking) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(220),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.greenAccent.withAlpha(100)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ValueListenableBuilder<int>(
                          valueListenable: _elapsedSeconds,
                          builder: (context, seconds, child) {
                            String timeStr = Duration(seconds: seconds).toString().split('.').first.padLeft(8, '0');
                            return _buildStatItem(t.translate('time'), timeStr, Icons.timer);
                          },
                        ),
                        _buildStatItem(t.translate('distance'), "${formattedTrip.toStringAsFixed(2)} $unit", Icons.straighten),
                        _buildStatItem(t.translate('pace'), formattedPace, Icons.speed),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 10.0),
        child: !_isTracking 
            ? FloatingActionButton.extended(
                onPressed: _startTracking,
                backgroundColor: Colors.greenAccent,
                elevation: 8,
                icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 28),
                label: Text(t.translate('startExploration'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton.extended(
                    onPressed: _togglePause,
                    backgroundColor: _isPaused ? Colors.greenAccent : Colors.orangeAccent,
                    elevation: 8,
                    icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.black, size: 28),
                    label: Text(_isPaused ? t.translate('resume') : t.translate('pause'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  ),
                  const SizedBox(width: 15),
                  FloatingActionButton.extended(
                    onPressed: _stopTracking,
                    backgroundColor: Colors.redAccent,
                    elevation: 8,
                    icon: const Icon(Icons.stop_rounded, color: Colors.white, size: 28),
                    label: Text(t.translate('stop'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.greenAccent, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ],
    );
  }
}

class FogPainter extends CustomPainter {
  final List<List<LatLng>> exploredPaths;
  final LatLng? currentLocation;
  final MapCamera camera;
  final ui.Image? fogImage;
  final double driftValue;

  FogPainter({
    required this.exploredPaths,
    required this.currentLocation,
    required this.camera,
    this.fogImage,
    this.driftValue = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    if (fogImage != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withAlpha(150));

      final Float64List matrix4 = (Matrix4.identity()
            ..scale(0.4, 0.4) 
            ..translate(driftValue * fogImage!.width, driftValue * fogImage!.height))
          .storage;

      final fogPaint = Paint()
        ..shader = ImageShader(
          fogImage!,
          TileMode.repeated, 
          TileMode.repeated,
          matrix4,
        );

      canvas.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withAlpha(160));
      canvas.drawRect(Offset.zero & size, fogPaint);
      canvas.restore();
      
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color.fromARGB(200, 10, 30, 60));
    }

    final erasePaint = Paint()
      ..color = Colors.black 
      ..blendMode = BlendMode.dstOut 
      ..style = PaintingStyle.stroke
      ..strokeWidth = 90.0 
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20.0); 

    // Alle bisherigen (und aktuellen) Wege radieren den Nebel weg!
    for (var segment in exploredPaths) {
      if (segment.length > 1) {
        final pathPath = Path();
        final firstPoint = camera.getOffsetFromOrigin(segment[0]);
        pathPath.moveTo(firstPoint.dx, firstPoint.dy);
        for (int i = 0; i < segment.length - 1; i++) {
          final p1 = camera.getOffsetFromOrigin(segment[i]);
          final p2 = camera.getOffsetFromOrigin(segment[i + 1]);
          pathPath.quadraticBezierTo(p1.dx, p1.dy, (p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        }
        canvas.drawPath(pathPath, erasePaint);
      } else if (segment.length == 1) {
        final p = camera.getOffsetFromOrigin(segment[0]);
        canvas.drawCircle(p, 45.0, erasePaint..style = PaintingStyle.fill);
      }
    }

    // Zusätzlicher Radius direkt um deine aktuelle Position
    if (currentLocation != null) {
      final circleErasePaint = Paint()
        ..color = Colors.black 
        ..blendMode = BlendMode.dstOut 
        ..style = PaintingStyle.fill 
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25.0);
      final currentPoint = camera.getOffsetFromOrigin(currentLocation!);
      canvas.drawCircle(currentPoint, 90.0, circleErasePaint);
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FogPainter oldDelegate) => true; 
}