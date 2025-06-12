import 'dart:developer';
import 'dart:io';
import 'package:talker/talker.dart';
import 'package:path/path.dart' as path;
import 'package:talker_persistent/src/talker_persistent_service.dart';
import 'package:talker_persistent/src/pretty_talker.dart';
import 'dart:math' as math;

/// A persistent implementation of [TalkerHistory] that stores logs on disk using Hive.
/// This implementation works for both Dart and Flutter applications.
class TalkerPersistentHistory implements TalkerHistory {
  final String logName;
  final String? savePath;
  File? _logFile;
  final int maxCapacity;

  int _currentFileLines = 0;
  static const int _bufferSize = 100;
  final List<String> _writeBuffer = [];
  bool _isRotating = false;

  /// Private constructor

  /// Creates a new instance of [TalkerPersistentHistory].
  ///
  /// [logName] unique identifier for this history instance.
  /// [savePath] optional path to save logs to a file. If provided, logs will be written to both Hive and the file.
  /// [maxCapacity] defines the maximum number of logs to keep in history.
  /// When the capacity is reached, older logs will be removed.
  TalkerPersistentHistory({
    required this.logName,
    this.savePath,
    this.maxCapacity = 1000,
  }) {
    _initialize();
  }

  /// Initializes the persistent storage.
  /// This method must be called before using any other methods.
  Future<void> _initialize() async {
    try {
      if (savePath != null) {
        final logFilePath = path.join(savePath!, '$logName.log');

        _logFile = File(logFilePath);
        final parentDir = _logFile!.parent;

        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }

        if (!await _logFile!.exists()) {
          await _logFile!.writeAsString('');
        } else {
          final contents = await _logFile!.readAsString();
          _currentFileLines = '\n'.allMatches(contents).length + 1;
        }
      } else {
        log('⚠️ savePath is null, file will not be created');
      }
    } catch (e, stack) {
      log('❌ Error initializing log file:');
      log('Error: $e');
      log('Stack: $stack');
      rethrow;
    }
  }

  /// Creates a new instance of [TalkerPersistentHistory].
  static Future<TalkerPersistentHistory> create({
    required String logName,
    String? savePath,
    int maxCapacity = 1000,
  }) async {
    final history = TalkerPersistentHistory(
      logName: logName,
      savePath: savePath,
      maxCapacity: maxCapacity,
    );
    await history._initialize();
    return history;
  }

  /// Rotates the log file by keeping only the most recent logs
  Future<void> _rotateLogFile() async {
    if (_isRotating || _logFile == null) return;
    _isRotating = true;

    try {
      final content = await _logFile!.readAsString();
      final logCount = '┌'.allMatches(content).length;

      if (logCount > maxCapacity) {
        log('🔄 Rotating log file - current logs: $logCount, max capacity: $maxCapacity');

        final lines = content.split('\n');
        final logs = <String>[];
        var currentLog = <String>[];
        var foundLog = false;

        // Process each line to group logs
        for (var line in lines) {
          if (line.contains('┌')) {
            if (foundLog) {
              logs.add(currentLog.join('\n'));
            }
            currentLog = [line];
            foundLog = true;
          } else if (foundLog) {
            currentLog.add(line);
          }
        }
        if (foundLog) {
          logs.add(currentLog.join('\n'));
        }

        // Keep only the most recent logs
        final keepLogs = logs.skip(logs.length - maxCapacity).toList();

        // Write back to file
        await _logFile!.writeAsString('${keepLogs.join('\n')}\n');
        _currentFileLines = keepLogs.length;

        log('📊 Log file rotated - new log count: $_currentFileLines');
      }
    } catch (e, stack) {
      log('❌ Error rotating log file:');
      log('Error: $e');
      log('Stack: $stack');
    } finally {
      _isRotating = false;
    }
  }

  /// Flushes the write buffer to disk
  Future<void> _flushBuffer() async {
    if (_writeBuffer.isEmpty || _logFile == null) return;

    try {
      final content = '${_writeBuffer.join('\n')}\n';

      // Check current log count
      final currentContent = await _logFile!.readAsString();
      final currentLogCount = '┌'.allMatches(currentContent).length;
      final newLogCount = '┌'.allMatches(content).length;

      if (currentLogCount + newLogCount > maxCapacity) {
        log('🔄 Rotating logs - current: $currentLogCount, adding: $newLogCount, max: $maxCapacity');
        await _rotateLogFile();
      }

      // Open file in write mode
      final sink = _logFile!.openWrite(mode: FileMode.append);
      sink.write(content);
      await sink.flush();
      await sink.close();

      _currentFileLines = '┌'.allMatches(await _logFile!.readAsString()).length;
      _writeBuffer.clear();
    } catch (e, stack) {
      log('❌ Error writing to log file:');
      log('Error: $e');
      log('Stack: $stack');
    }
  }

  @override
  void clean() {
    TalkerPersistent.instance.clean(logName: logName);
    if (savePath != null) {
      final logFilePath = path.join(savePath!, '$logName.log');
      File(logFilePath).writeAsStringSync('');
    }
  }

  @override
  List<TalkerData> get history {
    return List.unmodifiable(TalkerPersistent.instance.getLogs(logName: logName));
  }

  @override
  void write(TalkerData data) {
    TalkerPersistent.instance.write(
      data: data,
      logName: logName,
      maxCapacity: maxCapacity,
    );

    if (_logFile != null) {
      final formattedLog = data.toPrettyString();
      try {
        log('📝 Adding log to buffer: ${formattedLog.substring(0, math.min(50, formattedLog.length))}...');
        _writeBuffer.add(formattedLog);

        // Only flush if buffer is full
        if (_writeBuffer.length >= _bufferSize) {
          log('🔄 Buffer full, initiating flush');
          _flushBuffer();
        }
      } catch (e, stack) {
        log('❌ Error adding log to buffer:');
        log('Error: $e');
        log('Stack: $stack');
      }
    }
  }

  /// Disposes of the resources used by this instance.
  Future<void> dispose() async {
    log('🔄 Finalizing TalkerPersistentHistory...');

    // Ensure any remaining logs in buffer are written
    if (_writeBuffer.isNotEmpty) {
      log('📝 Writing remaining ${_writeBuffer.length} logs from buffer');
      await _flushBuffer();
    }

    _logFile = null;
    log('✅ TalkerPersistentHistory finalized');
  }
}
