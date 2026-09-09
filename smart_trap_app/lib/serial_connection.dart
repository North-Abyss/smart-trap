// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialConnection {
  final SerialPort port;
  late final SerialPortReader reader;
  late final StreamSubscription sub;
  String _buffer = "";
  
  final List<String> _lineQueue = [];
  Completer<String>? _waiter;
  
  SerialConnection(String portName) : port = SerialPort(portName) {
    port.openReadWrite();
    final config = SerialPortConfig();
    config.baudRate = 115200;
    port.config = config;
    reader = SerialPortReader(port, timeout: 1000);
    print("SerialConnection: Opened reader for $portName");
    sub = reader.stream.listen((data) {
      String chunk = utf8.decode(data, allowMalformed: true);
      print("SerialConnection RAW data: $chunk");
      _buffer += chunk;
      while (_buffer.contains('\n')) {
        int idx = _buffer.indexOf('\n');
        String line = _buffer.substring(0, idx).trim();
        _buffer = _buffer.substring(idx + 1);
        if (line.isNotEmpty) {
          if (_waiter != null && !_waiter!.isCompleted) {
             _waiter!.complete(line);
             _waiter = null;
          } else {
             _lineQueue.add(line);
          }
        }
      }
    }, onError: (e) {
       debugPrint("Serial error: $e");
       if (_waiter != null && !_waiter!.isCompleted) {
          _waiter!.completeError(e);
          _waiter = null;
       }
    });
  }
  
  void writeLine(String line) {
    print("SerialConnection WRITE: $line");
    port.write(Uint8List.fromList(utf8.encode("$line\n")));
  }
  
  Future<String> readLine({Duration timeout = const Duration(seconds: 3)}) async {
    if (_lineQueue.isNotEmpty) {
      return _lineQueue.removeAt(0);
    }
    _waiter = Completer<String>();
    print("SerialConnection: Waiting for readLine (timeout ${timeout.inSeconds}s)...");
    return _waiter!.future.timeout(timeout, onTimeout: () {
      print("SerialConnection: Timeout elapsed!");
      _waiter = null;
      throw TimeoutException("Serial read timeout");
    });
  }
  
  void close() {
    sub.cancel();
    reader.close();
    port.close();
    port.dispose();
  }
}
