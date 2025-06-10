import 'dart:developer';
import 'dart:io';
import 'package:talker/talker.dart';
import 'package:path/path.dart' as path;
import 'package:talker_persistent/src/talker_persistent_service.dart';
import 'package:talker_persistent/src/pretty_talker.dart';

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

        await _logFile!.parent.create(recursive: true);

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
      log('Erro: $e');
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
      if (_currentFileLines > maxCapacity) {
        final tempFile = File('${_logFile!.path}.tmp');
        final lines = await _logFile!.readAsLines();
        final keepLines = lines.skip(lines.length - maxCapacity);

        await tempFile.writeAsString(keepLines.join('\n'));
        await _logFile!.delete();
        await tempFile.rename(_logFile!.path);

        _currentFileLines = maxCapacity;
      }
    } catch (e) {
      log('Error rotating log file: $e');
    } finally {
      _isRotating = false;
    }
  }

  /// Flushes the write buffer to disk
  Future<void> _flushBuffer() async {
    if (_writeBuffer.isEmpty || _logFile == null) return;

    try {
      await _logFile!.writeAsString(
        '${_writeBuffer.join('\n')}\n',
        mode: FileMode.append,
      );
      _currentFileLines += _writeBuffer.length;
      _writeBuffer.clear();

      if (_currentFileLines > maxCapacity + _bufferSize) {
        await _rotateLogFile();
      }
    } catch (e) {
      log('Error flushing log buffer: $e');
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
        _writeBuffer.add(formattedLog);

        if (_writeBuffer.length >= _bufferSize) {
          _flushBuffer();
        }
      } catch (e) {
        log('Error buffering log: $e');
      }
    }
  }

  /// Disposes of the resources used by this instance.
  Future<void> dispose() async {
    await _flushBuffer();
    _logFile = null;
  }
}
