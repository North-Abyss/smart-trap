// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'dart:convert';
void main() async {
  print("=== Serial Diagnostics ===");
  final ports = SerialPort.availablePorts;
  print("Available ports: $ports");
  
  if (!ports.contains("/dev/ttyUSB2")) {
    print("Error: /dev/ttyUSB2 not found in available ports!");
    exit(1);
  }

  print("Found /dev/ttyUSB2. Attempting to open...");
  final port = SerialPort("/dev/ttyUSB2");
  
  try {
    if (!port.openReadWrite()) {
      print("Failed to open port. Error code: ${SerialPort.lastError}");
      exit(1);
    }
    print("Port opened successfully!");
    
    final config = SerialPortConfig();
    config.baudRate = 115200;
    port.config = config;
    print("Configured baud rate to 115200.");
    
    print("Sending PING...");
    port.write(Uint8List.fromList(utf8.encode("PING\n")));
    
    print("Waiting for response (up to 3 seconds)...");
    final reader = SerialPortReader(port, timeout: 1000);
    
    reader.stream.listen((data) {
      print("Received: ${utf8.decode(data, allowMalformed: true)}");
    }, onError: (e) {
      print("Stream Error: \$e");
    });
    
    await Future.delayed(Duration(seconds: 3));
    print("Closing port...");
    reader.close();
    port.close();
    port.dispose();
    print("Done.");
    exit(0);
    
  } catch (e) {
    print("Exception occurred:");
    print(e);
    exit(1);
  }
}
