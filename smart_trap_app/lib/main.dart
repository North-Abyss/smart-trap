import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:async';
//import 'package:flutter/foundation.dart';

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
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
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

  Future<void> _startMockSync() async {
    setState(() {
      _isSyncing = true;
      _logMessages.clear();
      _statusMessage = "Connecting to ESP32 over Serial (Mock)...";
    });

    _addLog("Sending PING to device...");
    await Future.delayed(const Duration(seconds: 1));
    _addLog("Received PONG.");
    
    _addLog("Sending DUMP command...");
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Create a mock payload
    // Payload = SCANNER_ID + TAG_UID + TIMESTAMP + STATUS
    const scannerId = "SCN-014-003";
    const tagUid = "0xE0040150A9B2C1D4";
    const timestamp = 1787654400;
    const status = 1;
    
    // We mock the secret key from the pocketbase database
    // For demo, we just use a hardcoded one or fetch it
    const secretKey = "super_secret_hmac_key_for_demo";
    
    final hmac = Hmac(sha256, utf8.encode(secretKey));
    
    // In actual implementation, ESP32 tagUID has NO 0x during hashing.
    // Let's just create exactly what ESP32 creates:
    final actualPayloadToHash = "$scannerId${tagUid.substring(2)}$timestamp$status";
    final expectedHmac = hmac.convert(utf8.encode(actualPayloadToHash)).toString();

    final mockJson = {
      "scanner_id": scannerId,
      "tag_uid": tagUid,
      "timestamp": timestamp,
      "status": status,
      "hmac": expectedHmac
    };

    _addLog("DATA: ${jsonEncode(mockJson)}");
    _addLog("END");

    _addLog("Verifying HMAC...");
    
    // Try to find the scanner in PocketBase
    try {
      final records = await pb.collection('scanners').getList(filter: 'scanner_id = "$scannerId"');
      String serverKey = secretKey; // fallback
      String scannerDbId = "";
      if (records.items.isNotEmpty) {
        serverKey = records.items.first.getStringValue('secret_key');
        scannerDbId = records.items.first.id;
      } else {
        // Create mock scanner for first run
        final newScanner = await pb.collection('scanners').create(body: {
          "scanner_id": scannerId,
          "secret_key": secretKey,
          "status": "active"
        });
        serverKey = secretKey;
        scannerDbId = newScanner.id;
        _addLog("Registered new scanner in PocketBase.");
      }
      
      final receivedPayloadToHash = "${mockJson['scanner_id']}${mockJson['tag_uid'].toString().substring(2)}${mockJson['timestamp']}${mockJson['status']}";
      final serverHmac = Hmac(sha256, utf8.encode(serverKey));
      final serverDigest = serverHmac.convert(utf8.encode(receivedPayloadToHash)).toString();

      if (serverDigest == mockJson['hmac']) {
        _addLog("✅ HMAC Verified! Record is authentic.");
        
        // Ensure property exists
        final props = await pb.collection('properties').getList(filter: 'tag_uid = "$tagUid"');
        String propId = "";
        if (props.items.isEmpty) {
           final newProp = await pb.collection('properties').create(body: {
             "tag_uid": tagUid,
             "eb_sc_number": "TN-DEMO-${DateTime.now().millisecondsSinceEpoch}",
             "property_type": "residential"
           });
           propId = newProp.id;
        } else {
           propId = props.items.first.id;
        }

        // Upload to PocketBase
        await pb.collection('audit_logs').create(body: {
          "scanner": scannerDbId,
          "property": propId,
          "timestamp": DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toIso8601String(), // In real app, timestamp is epoch ms or sec. Our ESP32 used millis(). Let's just use current time for demo.
          "status": status == 1,
          "hmac_verified": true
        });
        
        _addLog("Uploaded valid record to PocketBase.");
      } else {
        _addLog("❌ HMAC Mismatch! Data tampered.");
      }
      
      _addLog("Sending CLEAR command...");
      await Future.delayed(const Duration(milliseconds: 500));
      _addLog("Received CLEARED.");
      
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
            onPressed: _isSyncing ? null : _startMockSync,
            child: const Text("Start ESP32 Sync (Mock)"),
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
