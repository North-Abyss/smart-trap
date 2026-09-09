import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_connection.dart';

final pb = PocketBase('http://127.0.0.1:8090');

void main() {
  runApp(const SmartTrapApp());
}

class SmartTrapApp extends StatelessWidget {
  const SmartTrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMART-TRAP Municipal System',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    SyncToolWidget(),
    ComplianceDashboardWidget(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMART-TRAP Dashboard'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.usb),
            label: 'Depot Sync Tool',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Compliance',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.green[800],
        onTap: _onItemTapped,
      ),
    );
  }
}

// ----------------------------------------------------
// SYNC TOOL WIDGET (Mocks USB Serial for Demo purposes)
// ----------------------------------------------------
class SyncToolWidget extends StatefulWidget {
  const SyncToolWidget({super.key});

  @override
  State<SyncToolWidget> createState() => _SyncToolWidgetState();
}

class _SyncToolWidgetState extends State<SyncToolWidget> {
  String _statusMessage = "Waiting for device...";
  bool _isSyncing = false;
  final List<String> _logMessages = [];

  void _addLog(String msg) {
    setState(() {
      _logMessages.add("[${DateTime.now().toIso8601String().substring(11, 19)}] $msg");
    });
  }

  Future<SerialConnection?> _autoDetectESP32() async {
    _addLog("Scanning available ports...");
    for (final name in SerialPort.availablePorts) {
      _addLog("Checking port: $name");
      SerialConnection? conn;
      try {
        conn = SerialConnection(name);
        await Future.delayed(const Duration(milliseconds: 1500));
        conn.writeLine("PING");
        final response = await conn.readLine(timeout: const Duration(milliseconds: 2000));
        if (response == "PONG") {
          _addLog("ESP32 found on $name!");
          return conn;
        }
      } catch (e) {
        _addLog("Failed on $name: $e");
      }
      conn?.close();
    }
    return null;
  }

  Future<void> _startRealSync() async {
    setState(() {
      _isSyncing = true;
      _logMessages.clear();
      _statusMessage = "Auto-detecting ESP32 over USB...";
    });

    SerialConnection? conn;
    try {
      conn = await _autoDetectESP32();
      if (conn == null) {
        throw Exception("ESP32 not found. Check USB connection and Linux dialout permissions.");
      }

      _addLog("Sending DUMP command...");
      conn.writeLine("DUMP");
      
      List<Map<String, dynamic>> records = [];
      while (true) {
        final line = await conn.readLine(timeout: const Duration(seconds: 5));
        if (line == "END") {
          break;
        } else if (line.startsWith("DATA:")) {
          final jsonStr = line.substring(5);
          try {
             records.add(jsonDecode(jsonStr));
             _addLog("DATA: $jsonStr");
          } catch(e) {
             _addLog("Invalid JSON: $jsonStr");
          }
        }
      }
      
      _addLog("Verifying HMACs for ${records.length} records...");
      
      for (final jsonPayload in records) {
        final scannerId = jsonPayload['scanner_id'];
        final tagUid = jsonPayload['tag_uid'];
        final timestamp = jsonPayload['timestamp'];
        final status = jsonPayload['status'];
        final payloadHmac = jsonPayload['hmac'];

        final recordsList = await pb.collection('scanners').getList(filter: 'scanner_id = "$scannerId"');
        String serverKey = "super_secret_hmac_key_for_demo"; // fallback
        String scannerDbId = "";
        
        if (recordsList.items.isNotEmpty) {
          serverKey = recordsList.items.first.getStringValue('secret_key');
          scannerDbId = recordsList.items.first.id;
        } else {
          final newScanner = await pb.collection('scanners').create(body: {
            "scanner_id": scannerId,
            "secret_key": serverKey,
            "status": "active"
          });
          scannerDbId = newScanner.id;
          _addLog("Registered new scanner in PocketBase.");
        }
        final receivedPayloadToHash = "$scannerId${tagUid.toString().substring(2)}$timestamp$status";
        final serverHmacObj = Hmac(sha256, utf8.encode(serverKey));
        final serverDigest = serverHmacObj.convert(utf8.encode(receivedPayloadToHash)).toString();

        if (serverDigest == payloadHmac) {
          _addLog("✅ HMAC Verified! Record authentic.");
          
          final props = await pb.collection('properties').getList(filter: 'tag_uid = "$tagUid"');
          String propId = "";
          if (props.items.isEmpty) {
             final wards = await pb.collection('wards').getList(page: 1, perPage: 1);
             String wardId = wards.items.isNotEmpty ? wards.items.first.id : "";
             final newProp = await pb.collection('properties').create(body: {
               "tag_uid": tagUid,
               "eb_sc_number": "TN-DEMO-${DateTime.now().millisecondsSinceEpoch}",
               "property_type": "residential",
               "ward": wardId
             });
             propId = newProp.id;
          } else {
             propId = props.items.first.id;
          }

          await pb.collection('audit_logs').create(body: {
            "scanner": scannerDbId,
            "property": propId,
            "timestamp": DateTime.fromMillisecondsSinceEpoch(timestamp).toIso8601String(),
            "status": status == 1,
            "hmac_verified": true
          });
        } else {
          _addLog("❌ HMAC Mismatch! Data tampered.");
        }
      }
      
      if (records.isNotEmpty) {
        _addLog("Sending CLEAR command...");
        conn.writeLine("CLEAR");
        final clearResp = await conn.readLine(timeout: const Duration(seconds: 3));
        if (clearResp == "CLEARED") {
          _addLog("Device memory wiped.");
        }
      } else {
        _addLog("No records to sync.");
      }
      
      setState(() {
        _statusMessage = "Sync Complete.";
        _isSyncing = false;
      });

    } catch (e) {
       _addLog("Error: $e");
       setState(() {
        _statusMessage = "Sync Failed.";
        _isSyncing = false;
      });
      _showConnectionError();
    } finally {
      conn?.close();
    }
  }

  void _showConnectionError() {
    Timer? timer;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        // Automatically close after 5 seconds
        timer = Timer(const Duration(seconds: 5), () {
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        });

        return AlertDialog(
          title: const Text("Device Not Connected"),
          content: const Text("The device is not connected correctly or sync failed. Please check the USB connection and try again."),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
            ),
          ],
        );
      },
    ).then((_) {
      timer?.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Icon(Icons.usb, size: 64, color: Colors.blueGrey),
          const SizedBox(height: 16),
          Text(_statusMessage, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isSyncing ? null : _startRealSync,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.black),
            child: const Text("Start ESP32 Sync", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8)
              ),
              child: ListView.builder(
                itemCount: _logMessages.length,
                itemBuilder: (context, index) {
                  return Text(
                    _logMessages[index],
                    style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
                  );
                },
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ----------------------------------------------------
// COMPLIANCE DASHBOARD WIDGET
// ----------------------------------------------------
class ComplianceDashboardWidget extends StatefulWidget {
  const ComplianceDashboardWidget({super.key});

  @override
  State<ComplianceDashboardWidget> createState() => _ComplianceDashboardWidgetState();
}

class _ComplianceDashboardWidgetState extends State<ComplianceDashboardWidget> {
  List<RecordModel> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _loading = true);
    try {
      final records = await pb.collection('audit_logs').getList(
        sort: '-created',
        expand: 'property,scanner',
      );
      setState(() {
        _logs = records.items;
      });
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading 
      ? const CircularProgressIndicator()
      : Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Recent Scans", style: Theme.of(context).textTheme.headlineSmall),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchLogs)
                ]
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final isGreen = log.getBoolValue('status');
                    final isVerified = log.getBoolValue('hmac_verified');
                    final propertyVal = log.getStringValue('expand.property.eb_sc_number');
                    final property = propertyVal.isEmpty ? "Unknown" : propertyVal;
                    
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isGreen ? Icons.check_circle : Icons.warning,
                          color: isGreen ? Colors.green : Colors.red,
                        ),
                        title: Text("Property EB: $property"),
                        subtitle: Text("Scanned: ${log.getStringValue('created')}"),
                        trailing: isVerified 
                          ? const Tooltip(message: "HMAC Verified", child: Icon(Icons.verified_user, color: Colors.blue))
                          : const Tooltip(message: "Tampered", child: Icon(Icons.gpp_bad, color: Colors.red)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
  }
}
