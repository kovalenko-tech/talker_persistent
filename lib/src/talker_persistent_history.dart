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
    if (savePath != null) {
      final logFilePath = path.join(savePath!, '$logName.log');
      _logFile = File(logFilePath);
      await _logFile!.parent.create(recursive: true);
    }
  }

  /// Creates and initializes a new instance of [TalkerPersistentHistory].
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

  /// Disposes of the resources used by this instance.
  Future<void> dispose() async {
    _logFile = null;
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
        _logFile!.writeAsStringSync('$formattedLog\n', mode: FileMode.append);
      } catch (e) {
        print('Error writing to log file: $e');
      }
    }
  }
}
