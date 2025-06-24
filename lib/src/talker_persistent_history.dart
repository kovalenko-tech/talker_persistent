import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:talker/talker.dart';
import 'package:path/path.dart' as path;
import 'package:talker_persistent/src/talker_persistent_service.dart';
import 'package:talker_persistent/src/pretty_talker.dart';
import 'package:hive_ce/hive.dart';

/// Message types for isolate communication
enum FileOperationType {
  initialize,
  write,
  read,
  dispose,
}

/// Message class for isolate communication
class FileOperationMessage {
  final FileOperationType type;
  final String? filePath;
  final List<String>? logs;
  final int? maxCapacity;
  SendPort? responsePort;

  FileOperationMessage({
    required this.type,
    this.filePath,
    this.logs,
    this.maxCapacity,
    this.responsePort,
  });
}

/// Response class for isolate communication
class FileOperationResponse {
  final bool success;
  final String? error;
  final int? logCount;
  final String? content;

  FileOperationResponse({
    required this.success,
    this.error,
    this.logCount,
    this.content,
  });
}

/// Isolate function to handle file operations
Future<void> _fileOperationsIsolate(SendPort sendPort) async {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  File? logFile;
  int currentLogCount = 0;

  await for (final message in receivePort) {
    if (message is FileOperationMessage) {
      try {
        switch (message.type) {
          case FileOperationType.initialize:
            if (message.filePath != null) {
              logFile = File(message.filePath!);
              await logFile.parent.create(recursive: true);
              if (await logFile.exists()) {
                final content = await logFile.readAsString();
                currentLogCount = '┌'.allMatches(content).length;
              } else {
                await logFile.writeAsString('');
                currentLogCount = 0;
              }
            }
            message.responsePort?.send(FileOperationResponse(success: true, logCount: currentLogCount));

          case FileOperationType.write:
            if (logFile != null && message.logs != null) {
              final content = '${message.logs!.join('\n')}\n';
              final newLogCount = '┌'.allMatches(content).length;

              if (message.maxCapacity != null) {
                final fileContent = await logFile.readAsString();
                final lines = fileContent.split('\n');
                final logs = <String>[];
                var currentLog = <String>[];
                var foundLog = false;

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

                logs.addAll(message.logs!);

                final skipCount = math.max(0, logs.length - message.maxCapacity!);
                final keepLogs = logs.skip(skipCount).toList();

                await logFile.writeAsString('${keepLogs.join('\n')}\n');
                currentLogCount = keepLogs.length;
              } else {
                await logFile.writeAsString(content, mode: FileMode.append);
                currentLogCount += newLogCount;
              }
            }
            message.responsePort?.send(FileOperationResponse(success: true, logCount: currentLogCount));

          case FileOperationType.read:
            if (logFile != null) {
              final content = await logFile.readAsString();
              currentLogCount = '┌'.allMatches(content).length;
              message.responsePort?.send(FileOperationResponse(
                success: true,
                content: content,
                logCount: currentLogCount,
              ));
            }

          case FileOperationType.dispose:
            logFile = null;
            currentLogCount = 0;
            message.responsePort?.send(FileOperationResponse(success: true));
            break;
        }
      } catch (e, stack) {
        message.responsePort?.send(FileOperationResponse(
          success: false,
          error: 'Error: $e\nStack: $stack',
        ));
      }
    }
  }
}

/// A persistent implementation of [TalkerHistory] that stores logs on disk using Hive.
/// This implementation works for both Dart and Flutter applications.
class TalkerPersistentHistory implements TalkerHistory {
  final String logName;
  final String? savePath;
  final int maxCapacity;
  final int _bufferSize = 100;
  final List<String> _writeBuffer = [];
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool _isInitialized = false;

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
  });

  /// Initializes the persistent storage.
  /// This method must be called before using any other methods.
  Future<void> _initialize() async {
    try {
      if (savePath != null) {
        final logFilePath = path.join(savePath!, '$logName.log');
        log('📝 Initializing log file at: $logFilePath');

        if (!_isInitialized) {
          _receivePort = ReceivePort();
          _isolate = await Isolate.spawn(
            _fileOperationsIsolate,
            _receivePort!.sendPort,
          );

          final sendPort = await _receivePort!.first as SendPort;
          _sendPort = sendPort;

          final response = await _sendMessage(FileOperationMessage(
            type: FileOperationType.initialize,
            filePath: logFilePath,
          ));

          if (!response.success) {
            throw Exception(response.error);
          }

          _isInitialized = true;
        } else {
          log('⚠️ TalkerPersistentHistory já está inicializado');
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
    if (_receivePort == null) return;

    try {
      final response = await _sendMessage(FileOperationMessage(
        type: FileOperationType.read,
      ));

      if (response.success && response.content != null) {
        final content = response.content!;
        final logCount = '┌'.allMatches(content).length;

        if (logCount > maxCapacity) {
          final lines = content.split('\n');
          final logs = <String>[];
          var currentLog = <String>[];
          var foundLog = false;

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

          final skipCount = math.max(0, logs.length - maxCapacity);
          final keepLogs = logs.skip(skipCount).toList();

          await _sendMessage(FileOperationMessage(
            type: FileOperationType.write,
            logs: keepLogs,
            maxCapacity: maxCapacity,
          ));

          log('📊 Log file rotated - new log count: $logCount');
        }
      }
    } catch (e, stack) {
      log('❌ Error rotating log file:');
      log('Error: $e');
      log('Stack: $stack');
    }
  }

  /// Flushes the write buffer to disk
  Future<void> _flushBuffer() async {
    if (_writeBuffer.isEmpty || !_isInitialized) return;

    try {
      final response = await _sendMessage(FileOperationMessage(
        type: FileOperationType.write,
        logs: _writeBuffer,
        maxCapacity: maxCapacity,
      ));

      if (!response.success) {
        throw Exception(response.error);
      }

      _writeBuffer.clear();
    } catch (e, stack) {
      log('❌ Error writing to log file:');
      log('Error: $e');
      log('Stack: $stack');
    }
  }

  @override
  void write(TalkerData data) {
    TalkerPersistent.instance.write(
      data: data,
      logName: logName,
      maxCapacity: maxCapacity,
    );

    if (_isInitialized) {
      final formattedLog = data.toPrettyString();
      try {
        log('📝 Adding log to buffer: ${formattedLog.substring(0, math.min(50, formattedLog.length))}...');
        _writeBuffer.add(formattedLog);

        if (_writeBuffer.length >= _bufferSize) {
          log('🔄 Buffer full, initiating flush');
          _flushBuffer();
          _rotateLogFile();
        }
      } catch (e, stack) {
        log('❌ Error adding log to buffer:');
        log('Error: $e');
        log('Stack: $stack');
      }
    }
  }

  @override
  void clean() {
    TalkerPersistent.instance.clean(logName: logName);
  }

  @override
  List<TalkerData> get history {
    return List.unmodifiable(TalkerPersistent.instance.getLogs(logName: logName));
  }

  /// Disposes of the resources used by this instance.
  Future<void> dispose() async {
    log('🔄 Finalizing TalkerPersistentHistory...');

    if (_isInitialized) {
      if (_writeBuffer.isNotEmpty) {
        log('📝 Writing remaining ${_writeBuffer.length} logs from buffer');
        await _flushBuffer();
      }

      await _sendMessage(FileOperationMessage(
        type: FileOperationType.dispose,
      ));

      _isolate?.kill();
      _receivePort?.close();
      _isInitialized = false;

      // Fecha o Hive
      try {
        await Hive.close();
        log('✅ Hive fechado com sucesso');
      } catch (e, stack) {
        log('❌ Erro ao fechar o Hive:');
        log('Error: $e');
        log('Stack: $stack');
      }
    }

    log('✅ TalkerPersistentHistory finalized');
  }

  Future<FileOperationResponse> _sendMessage(FileOperationMessage message) async {
    if (_sendPort == null) {
      throw Exception('Isolate not initialized');
    }

    final responsePort = ReceivePort();
    message.responsePort = responsePort.sendPort;
    _sendPort!.send(message);

    try {
      final response = await responsePort.first as FileOperationResponse;
      return response;
    } finally {
      responsePort.close();
    }
  }
}
