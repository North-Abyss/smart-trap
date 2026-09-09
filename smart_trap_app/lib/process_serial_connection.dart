// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Serial connection that uses a Python subprocess bridge.
/// This bypasses libserialport's exclusive locking (TIOCEXCL) which causes
/// EBUSY errors on some Linux systems with CP210x drivers.
class ProcessSerialConnection {
  final Process _process;
  final List<String> _lineQueue = [];
  Completer<String>? _waiter;
  bool _isConnected = false;

  ProcessSerialConnection._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      print("SerialBridge RECV: $line");
      if (_waiter != null && !_waiter!.isCompleted) {
        _waiter!.complete(line);
        _waiter = null;
      } else {
        _lineQueue.add(line);
      }
    });

    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      print("SerialBridge STDERR: $line");
    });
  }

  /// Start the Python serial bridge process.
  static Future<ProcessSerialConnection?> start() async {
    try {
      // Find the serial_bridge.py script relative to the app
      final scriptPaths = [
        // When running from the project directory
        '${Directory.current.path}/serial_bridge.py',
        // When running from the smart_trap_app directory
        '${Directory.current.parent.path}/smart_trap_app/serial_bridge.py',
        // Absolute fallback
        '/mnt/sda5/Projects/WMS YI/smart_trap_app/serial_bridge.py',
      ];

      String? scriptPath;
      for (final path in scriptPaths) {
        if (File(path).existsSync()) {
          scriptPath = path;
          break;
        }
      }

      if (scriptPath == null) {
        print("SerialBridge: Could not find serial_bridge.py");
        return null;
      }

      print("SerialBridge: Starting bridge from $scriptPath");
      final process = await Process.start('python3', [scriptPath]);
      final conn = ProcessSerialConnection._(process);

      // Wait for READY signal
      final ready = await conn._readResponse(timeout: const Duration(seconds: 5));
      if (ready != null && ready.startsWith("OK:READY")) {
        print("SerialBridge: Bridge is ready");
        return conn;
      } else {
        print("SerialBridge: Bridge did not respond with READY, got: $ready");
        conn.close();
        return null;
      }
    } catch (e) {
      print("SerialBridge: Failed to start: $e");
      return null;
    }
  }

  /// Send a command to the bridge and get the response.
  void _sendCommand(String cmd) {
    print("SerialBridge SEND: $cmd");
    _process.stdin.writeln(cmd);
  }

  /// Read a response from the bridge.
  Future<String?> _readResponse({Duration timeout = const Duration(seconds: 5)}) async {
    if (_lineQueue.isNotEmpty) {
      return _lineQueue.removeAt(0);
    }
    _waiter = Completer<String>();
    try {
      return await _waiter!.future.timeout(timeout, onTimeout: () {
        _waiter = null;
        return "ERR:Timeout waiting for bridge response";
      });
    } catch (e) {
      return "ERR:$e";
    }
  }

  /// Scan for available serial ports.
  Future<List<String>> scanPorts() async {
    _sendCommand("SCAN");
    final resp = await _readResponse();
    if (resp != null && resp.startsWith("PORTS:")) {
      final jsonStr = resp.substring(6);
      return List<String>.from(jsonDecode(jsonStr));
    }
    return [];
  }

  /// Open a serial port. This may take a while if the bridge needs to retry
  /// or attempt a USB device reset.
  Future<bool> openPort(String portName) async {
    _sendCommand("OPEN:$portName");
    // The bridge may send multiple OK:DIAG: messages before the final response.
    // We need to keep reading until we get a non-DIAG response.
    // Total timeout: 30 seconds (5 retries * ~5s each + USB reset time)
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      final resp = await _readResponse(timeout: remaining);
      if (resp == null) {
        print("SerialBridge: openPort timeout");
        return false;
      }
      if (resp.startsWith("OK:DIAG:")) {
        // Diagnostic message — log it and keep waiting
        print("SerialBridge DIAG: ${resp.substring(8)}");
        continue;
      }
      if (resp.startsWith("OK:")) {
        _isConnected = true;
        return true;
      }
      // ERR or unexpected response
      print("SerialBridge: openPort failed: $resp");
      return false;
    }
    print("SerialBridge: openPort deadline exceeded");
    return false;
  }

  /// Send data to the serial port.
  Future<bool> sendData(String data) async {
    _sendCommand("SEND:$data");
    final resp = await _readResponse();
    return resp != null && resp.startsWith("OK:");
  }

  /// Read a line from the serial port.
  Future<String?> readSerialLine({Duration timeout = const Duration(seconds: 3)}) async {
    _sendCommand("READ:${timeout.inMilliseconds}");
    final resp = await _readResponse(timeout: timeout + const Duration(seconds: 2));
    if (resp != null && resp.startsWith("OK:")) {
      return resp.substring(3);
    }
    return null;
  }

  /// Write a line (like the old SerialConnection.writeLine).
  void writeLine(String line) {
    sendData(line);  // Fire and forget, response will be queued
  }

  /// Read a line (like the old SerialConnection.readLine).
  Future<String> readLine({Duration timeout = const Duration(seconds: 3)}) async {
    final result = await readSerialLine(timeout: timeout);
    if (result == null) {
      throw TimeoutException("Serial read timeout");
    }
    return result;
  }

  bool get isConnected => _isConnected;

  /// Close the connection and kill the bridge process.
  void close() {
    try {
      _sendCommand("QUIT");
    } catch (_) {}
    _isConnected = false;
    Future.delayed(const Duration(milliseconds: 500), () {
      _process.kill();
    });
  }
}
