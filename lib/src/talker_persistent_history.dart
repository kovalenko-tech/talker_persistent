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
  final bool? saveAllLogs;
  final LogRetentionPeriod? logRetentionPeriod;
  SendPort? responsePort;

  FileOperationMessage({
    required this.type,
    this.filePath,
    this.logs,
    this.maxCapacity,
    this.saveAllLogs,
    this.logRetentionPeriod,
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
  bool saveAllLogs = false;
  String? currentDate;
  LogRetentionPeriod? logRetentionPeriod;

  await for (final message in receivePort) {
    if (message is FileOperationMessage) {
      try {
        switch (message.type) {
          case FileOperationType.initialize:
            if (message.filePath != null) {
              saveAllLogs = message.saveAllLogs ?? false;
              logRetentionPeriod = message.logRetentionPeriod;

              if (saveAllLogs) {
                // Para saveAllLogs, o arquivo será baseado na data atual
                final now = DateTime.now();
                currentDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                final basePath = path.dirname(message.filePath!);
                final baseName = path.basenameWithoutExtension(message.filePath!);
                final dailyFilePath = path.join(basePath, '$baseName-$currentDate.log');
                logFile = File(dailyFilePath);
                // Apaga arquivos antigos conforme retenção
                if (logRetentionPeriod != null) {
                  final dir = Directory(basePath);
                  if (await dir.exists()) {
                    final files = await dir.list().toList();
                    final now = DateTime.now();
                    Duration retention;
                    switch (logRetentionPeriod) {
                      case LogRetentionPeriod.threeDays:
                        retention = Duration(days: 3);
                        break;
                      case LogRetentionPeriod.week:
                        retention = Duration(days: 7);
                        break;
                      case LogRetentionPeriod.fortnight:
                        retention = Duration(days: 15);
                        break;
                      case LogRetentionPeriod.month:
                        retention = Duration(days: 31);
                        break;
                      default:
                        retention = Duration(days: 3650); // 10 anos, fallback
                    }
                    for (final f in files) {
                      if (f is File && f.path.contains(baseName) && f.path.endsWith('.log')) {
                        final regex = RegExp(r'(\d{4})-(\d{2})-(\d{2})');
                        final match = regex.firstMatch(f.path);
                        if (match != null) {
                          final fileDate = DateTime(
                            int.parse(match.group(1)!),
                            int.parse(match.group(2)!),
                            int.parse(match.group(3)!),
                          );
                          if (now.difference(fileDate) > retention) {
                            await f.delete();
                          }
                        }
                      }
                    }
                  }
                }
              } else {
                logFile = File(message.filePath!);
              }

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
              // Verifica se mudou o dia quando saveAllLogs está ativo
              if (saveAllLogs) {
                final now = DateTime.now();
                final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

                if (currentDate != today) {
                  // Mudou o dia, cria novo arquivo
                  currentDate = today;
                  final basePath = logFile.parent.path;
                  final baseName = path.basenameWithoutExtension(logFile.path).split('-').first;
                  final dailyFilePath = path.join(basePath, '$baseName-$currentDate.log');
                  logFile = File(dailyFilePath);
                  currentLogCount = 0;
                }
              }

              final content = '${message.logs!.join('\n')}\n';
              final newLogCount = '┌'.allMatches(content).length;

              if (message.maxCapacity != null && !saveAllLogs) {
                // Aplica maxCapacity apenas quando não está salvando todos os logs
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
                // Para saveAllLogs, sempre adiciona ao final do arquivo
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
            currentDate = null;
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

/// Enum para definir o período de retenção dos arquivos de log
enum LogRetentionPeriod {
  threeDays,
  week,
  fortnight,
  month,
}

/// Configuration class for TalkerPersistentHistory
class TalkerPersistentConfig {
  /// Buffer size for logs. If 0, logs are written immediately (real-time).
  /// If > 0, logs are buffered and written when buffer is full.
  final int bufferSize;

  /// Whether to flush immediately for error and critical logs
  final bool flushOnError;

  /// Maximum capacity of logs to keep
  final int maxCapacity;

  /// Whether to enable file logging
  final bool enableFileLogging;

  /// Whether to enable Hive database logging
  final bool enableHiveLogging;

  /// Whether to save all logs of the day in a daily file
  /// When true, logs will be saved in files named as 'logName-YYYY-MM-DD.log'
  final bool saveAllLogs;

  /// Período de retenção dos arquivos de log (usado com saveAllLogs)
  final LogRetentionPeriod logRetentionPeriod;

  const TalkerPersistentConfig({
    this.bufferSize = 100,
    this.flushOnError = true,
    this.maxCapacity = 1000,
    this.enableFileLogging = true,
    this.enableHiveLogging = true,
    this.saveAllLogs = false,
    this.logRetentionPeriod = LogRetentionPeriod.threeDays,
  });
}

/// A persistent implementation of [TalkerHistory] that stores logs on disk using Hive.
/// This implementation works for both Dart and Flutter applications.
class TalkerPersistentHistory implements TalkerHistory {
  final String logName;
  final String? savePath;
  final TalkerPersistentConfig config;

  final List<String> _writeBuffer = [];
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  bool _isInitialized = false;

  /// Creates a new instance of [TalkerPersistentHistory].
  ///
  /// [logName] unique identifier for this history instance.
  /// [savePath] optional path to save logs to a file. If provided, logs will be written to both Hive and the file.
  /// [config] configuration for the persistent history behavior.
  TalkerPersistentHistory({
    required this.logName,
    this.savePath,
    TalkerPersistentConfig? config,
  }) : config = config ?? const TalkerPersistentConfig();

  /// Initializes the persistent storage.
  /// This method must be called before using any other methods.
  Future<void> _initialize() async {
    try {
      if (savePath != null && config.enableFileLogging) {
        final logFilePath = path.join(savePath!, '$logName.log');
        log('📝 Initializing log file at: $logFilePath');
        log('📊 Buffer size: ${config.bufferSize} (${config.bufferSize == 0 ? 'real-time' : 'buffered'})');
        log('🚨 Flush on error: ${config.flushOnError}');
        log('💾 Max capacity: ${config.maxCapacity}');
        log('📅 Save all logs: ${config.saveAllLogs}');

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
            saveAllLogs: config.saveAllLogs,
            logRetentionPeriod: config.logRetentionPeriod,
          ));

          if (!response.success) {
            throw Exception(response.error);
          }

          _isInitialized = true;
        } else {
          log('⚠️ TalkerPersistentHistory já está inicializado');
        }
      } else {
        if (savePath == null) {
          log('⚠️ savePath is null, file logging disabled');
        }
        if (!config.enableFileLogging) {
          log('⚠️ File logging disabled in config');
        }
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
    TalkerPersistentConfig? config,
  }) async {
    final history = TalkerPersistentHistory(
      logName: logName,
      savePath: savePath,
      config: config,
    );
    await history._initialize();
    return history;
  }

  /// Rotates the log file by keeping only the most recent logs
  Future<void> _rotateLogFile() async {
    if (_receivePort == null || !config.enableFileLogging || config.saveAllLogs) return;

    try {
      final response = await _sendMessage(FileOperationMessage(
        type: FileOperationType.read,
      ));

      if (response.success && response.content != null) {
        final content = response.content!;
        final logCount = '┌'.allMatches(content).length;

        if (logCount > config.maxCapacity) {
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

          final skipCount = math.max(0, logs.length - config.maxCapacity);
          final keepLogs = logs.skip(skipCount).toList();

          await _sendMessage(FileOperationMessage(
            type: FileOperationType.write,
            logs: keepLogs,
            maxCapacity: config.maxCapacity,
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
    if (_writeBuffer.isEmpty || !_isInitialized || !config.enableFileLogging) return;

    try {
      final response = await _sendMessage(FileOperationMessage(
        type: FileOperationType.write,
        logs: _writeBuffer,
        maxCapacity: config.saveAllLogs ? null : config.maxCapacity,
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

  /// Checks if a log level requires immediate flush
  bool _shouldFlushImmediately(TalkerData data) {
    if (!config.flushOnError) return false;
    return data.logLevel == LogLevel.error || data.logLevel == LogLevel.critical;
  }

  @override
  void write(TalkerData data) {
    // Write to Hive if enabled
    if (config.enableHiveLogging) {
      TalkerPersistent.instance.write(
        data: data,
        logName: logName,
        maxCapacity: config.maxCapacity,
      );
    }

    // Write to file if enabled
    if (_isInitialized && config.enableFileLogging) {
      final formattedLog = data.toPrettyString();
      try {
        log('📝 Adding log to buffer: ${formattedLog.substring(0, math.min(50, formattedLog.length))}...');
        _writeBuffer.add(formattedLog);

        // Check if we should flush immediately
        final shouldFlush = config.bufferSize == 0 || // Real-time mode
            _shouldFlushImmediately(data) || // Error/critical logs
            _writeBuffer.length >= config.bufferSize; // Buffer full

        if (shouldFlush) {
          final reason = config.bufferSize == 0
              ? 'real-time mode'
              : _shouldFlushImmediately(data)
                  ? 'error/critical log'
                  : 'buffer full';
          log('🔄 Flushing buffer ($reason)');
          _flushBuffer();
          if (!config.saveAllLogs) {
            _rotateLogFile();
          }
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
    if (config.enableHiveLogging) {
      TalkerPersistent.instance.clean(logName: logName);
    }
  }

  @override
  List<TalkerData> get history {
    if (!config.enableHiveLogging) return [];
    return List.unmodifiable(TalkerPersistent.instance.getLogs(logName: logName));
  }

  /// Disposes of the resources used by this instance.
  Future<void> dispose() async {
    log('🔄 Finalizing TalkerPersistentHistory...');

    if (_isInitialized && config.enableFileLogging) {
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
    }

    // Fecha o Hive se estiver habilitado
    if (config.enableHiveLogging) {
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
