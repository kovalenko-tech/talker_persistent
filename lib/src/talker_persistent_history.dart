import 'dart:developer';
import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'dart:math' as math;
import 'package:talker/talker.dart';
import 'package:path/path.dart' as path;
import 'package:talker_dio_logger/dio_logs.dart';
import 'package:talker_persistent/src/talker_persistent_service.dart';
import 'package:hive_ce/hive.dart';

/// Message types for isolate communication
enum FileOperationType {
  initialize,
  write,
  read,
  dispose,
}

/// Message class for isolate communication
///
const String _extension = 'log';

class FileOperationMessage {
  final FileOperationType type;
  final String? filePath;
  final List<String>? logs;
  final int? maxCapacity;
  final bool? saveAllLogs;
  final LogRetentionPeriod? logRetentionPeriod;
  final int? maxFileSize;
  final String? logName; // Identificador único para cada instância
  SendPort? responsePort;

  FileOperationMessage({
    required this.type,
    this.filePath,
    this.logs,
    this.maxCapacity,
    this.saveAllLogs,
    this.logRetentionPeriod,
    this.maxFileSize,
    this.logName,
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

/// Classe para gerenciar o isolate singleton
class _IsolateManager {
  static _IsolateManager? _instance;
  static _IsolateManager get instance => _instance ??= _IsolateManager._();

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  ReceivePort? _responsePort;
  bool _isInitialized = false;
  final Map<String, Completer<FileOperationResponse>> _pendingRequests = {};
  Completer<void>? _initializationCompleter;

  _IsolateManager._();

  Future<void> initialize() async {
    // Se já está inicializado, retorna imediatamente
    if (_isInitialized) {
      return;
    }

    // Se já está inicializando, aguarda
    if (_initializationCompleter != null) {
      await _initializationCompleter!.future;
      return;
    }

    // Inicia inicialização
    _initializationCompleter = Completer<void>();

    try {
      _receivePort = ReceivePort();
      _isolate = await Isolate.spawn(_fileOperationsIsolate, _receivePort!.sendPort);

      // Timeout para evitar travamento
      _sendPort = await _receivePort!.first.timeout(
        Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Isolate initialization timeout');
        },
      ) as SendPort;

      _responsePort = ReceivePort();

      // Listener para respostas - usando ReceivePort separado
      _responsePort!.listen((message) {
        // Se for uma resposta de operação
        if (message is Map<String, dynamic> && message.containsKey('requestId')) {
          final requestId = message['requestId'] as String;
          final response = FileOperationResponse(
            success: message['success'] as bool,
            error: message['error'] as String?,
            logCount: message['logCount'] as int?,
            content: message['content'] as String?,
          );

          final completer = _pendingRequests.remove(requestId);
          if (completer != null) {
            completer.complete(response);
          }
        }
      });

      _isInitialized = true;
      _initializationCompleter!.complete();
    } catch (e, stack) {
      _initializationCompleter!.completeError(e);
      _initializationCompleter = null;
      throw Exception('Failed to initialize isolate: $e');
    }
  }

  Future<FileOperationResponse> sendMessage(FileOperationMessage message) async {
    if (!_isInitialized) {
      await initialize();
    }

    final requestId = '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1000000)}';

    final completer = Completer<FileOperationResponse>();
    _pendingRequests[requestId] = completer;

    final messageWithId = {
      'requestId': requestId,
      'type': message.type.index,
      'filePath': message.filePath,
      'logs': message.logs,
      'maxCapacity': message.maxCapacity,
      'saveAllLogs': message.saveAllLogs,
      'logRetentionPeriod': message.logRetentionPeriod?.index,
      'maxFileSize': message.maxFileSize,
      'logName': message.logName,
      'responsePort': _responsePort!.sendPort,
    };

    _sendPort!.send(messageWithId);

    // Timeout para evitar travamento se o isolate não responder
    return completer.future.timeout(
      Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        return FileOperationResponse(
          success: false,
          error: 'Isolate response timeout',
        );
      },
    );
  }

  void dispose() {
    _isolate?.kill();
    _receivePort?.close();
    _responsePort?.close();
    _isInitialized = false;
    _pendingRequests.clear();
    _initializationCompleter = null;
  }
}

/// Isolate function to handle file operations (singleton)
Future<void> _fileOperationsIsolate(SendPort sendPort) async {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  // Map para gerenciar múltiplos arquivos de log
  final Map<String, _LogFileManager> fileManagers = {};

  await for (final message in receivePort) {
    if (message is Map<String, dynamic>) {
      try {
        final requestId = message['requestId'] as String;
        final type = FileOperationType.values[message['type'] as int];
        final filePath = message['filePath'] as String?;
        final logs = (message['logs'] as List<dynamic>?)?.cast<String>();
        final maxCapacity = message['maxCapacity'] as int?;
        final saveAllLogs = message['saveAllLogs'] as bool?;
        final logRetentionPeriod = message['logRetentionPeriod'] != null ? LogRetentionPeriod.values[message['logRetentionPeriod'] as int] : null;
        final maxFileSize = message['maxFileSize'] as int?;
        final logName = message['logName'] as String?;
        final responsePort = message['responsePort'] as SendPort?;

        FileOperationResponse response;

        switch (type) {
          case FileOperationType.initialize:
            if (logName != null && filePath != null) {
              fileManagers[logName] = _LogFileManager(
                filePath: filePath,
                saveAllLogs: saveAllLogs ?? false,
                logRetentionPeriod: logRetentionPeriod,
                maxFileSize: maxFileSize,
              );
              await fileManagers[logName]!.initialize();
              response = FileOperationResponse(success: true, logCount: 0);
            } else {
              response = FileOperationResponse(success: false, error: 'Invalid parameters');
            }
            break;

          case FileOperationType.write:
            if (logName != null && fileManagers.containsKey(logName)) {
              await fileManagers[logName]!.write(logs ?? []);
              response = FileOperationResponse(success: true);
            } else {
              response = FileOperationResponse(success: false, error: 'Log manager not found');
            }
            break;

          case FileOperationType.read:
            if (logName != null && fileManagers.containsKey(logName)) {
              final content = await fileManagers[logName]!.read();
              response = FileOperationResponse(success: true, content: content);
            } else {
              response = FileOperationResponse(success: false, error: 'Log manager not found');
            }
            break;

          case FileOperationType.dispose:
            if (logName != null && fileManagers.containsKey(logName)) {
              await fileManagers[logName]!.dispose();
              fileManagers.remove(logName);
              response = FileOperationResponse(success: true);
            } else {
              response = FileOperationResponse(success: true);
            }
            break;
        }

        if (responsePort != null) {
          responsePort.send({
            'requestId': requestId,
            'success': response.success,
            'error': response.error,
            'logCount': response.logCount,
            'content': response.content,
          });
        }
      } catch (e, stack) {
        final responsePort = message['responsePort'] as SendPort?;
        if (responsePort != null) {
          responsePort.send({
            'requestId': message['requestId'],
            'success': false,
            'error': 'Error: $e\nStack: $stack',
          });
        }
      }
    }
  }
}

/// Classe para gerenciar um arquivo de log específico
class _LogFileManager {
  final String filePath;
  final bool saveAllLogs;
  final LogRetentionPeriod? logRetentionPeriod;
  final int? maxFileSize;

  File? logFile;
  int currentLogCount = 0;
  String? currentDate;
  int fileCounter = 1;
  String? baseName;

  _LogFileManager({
    required this.filePath,
    required this.saveAllLogs,
    this.logRetentionPeriod,
    this.maxFileSize,
  });

  Future<void> initialize() async {
    baseName = path.basenameWithoutExtension(filePath);

    if (saveAllLogs) {
      final now = DateTime.now();
      currentDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final basePath = path.dirname(filePath);
      final dailyFilePath = path.join(basePath, '$baseName-$currentDate.$_extension');
      logFile = File(dailyFilePath);
      await deleteOldFiles();
    } else {
      logFile = File(filePath);
    }

    await logFile!.parent.create(recursive: true);
    if (await logFile!.exists()) {
      final content = await logFile!.readAsString();
      currentLogCount = '┌'.allMatches(content).length;
    } else {
      await logFile!.writeAsString('');
      currentLogCount = 0;
    }
  }

  Future<void> deleteOldFiles() async {
    if (logRetentionPeriod == null || baseName == null) return;

    try {
      final basePath = logFile?.parent.path;
      if (basePath == null) return;

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
          case null:
            retention = Duration(days: 3650); // 10 anos, fallback
            break;
        }

        for (final f in files) {
          if (f is File && f.path.contains(baseName!) && f.path.endsWith('.$_extension')) {
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
    } catch (e) {
      // Ignora erros na deleção
    }
  }

  Future<void> write(List<String> logs) async {
    if (logFile == null || logs.isEmpty) return;

    // Verifica se mudou o dia quando saveAllLogs está ativo
    if (saveAllLogs) {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      if (currentDate != today) {
        currentDate = today;
        final basePath = logFile!.parent.path;
        final dailyFilePath = path.join(basePath, ' $baseName-$currentDate.$_extension');
        logFile = File(dailyFilePath);
        currentLogCount = 0;
        fileCounter = 1;
        await deleteOldFiles();
      }
    }

    final content = '${logs.join('\n')}\n';
    final newLogCount = '┌'.allMatches(content).length;

    // Verifica se precisa rotacionar por tamanho
    if (maxFileSize != null && await logFile!.exists()) {
      final fileSize = await logFile!.length();
      if (fileSize + content.length > maxFileSize!) {
        await _rotateFileBySize();
      }
    }

    // Para saveAllLogs, sempre adiciona ao final do arquivo
    await logFile!.writeAsString(content, mode: FileMode.append);
    currentLogCount += newLogCount;
  }

  /// Rotaciona o arquivo removendo a metade mais antiga quando atinge o tamanho máximo
  Future<void> _rotateFileBySize() async {
    if (maxFileSize == null || !await logFile!.exists()) return;

    try {
      final content = await logFile!.readAsString();
      final lines = content.split('\n');
      final logs = <String>[];
      var currentLog = <String>[];
      var foundLog = false;

      // Separa os logs individuais
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

      // Remove a metade mais antiga
      final keepCount = (logs.length / 2).ceil();
      final keepLogs = logs.skip(logs.length - keepCount).toList();

      // Cria novo arquivo com apenas os logs mais recentes
      final newContent = keepLogs.join('\n');
      await logFile!.writeAsString(newContent);

      // Atualiza o contador de logs
      currentLogCount = '┌'.allMatches(newContent).length;

      print('📊 Arquivo rotacionado - removidos ${logs.length - keepCount} logs antigos, mantidos $keepCount logs recentes');
    } catch (e) {
      print('❌ Erro ao rotacionar arquivo por tamanho: $e');
    }
  }

  Future<String> read() async {
    if (logFile == null) return '';
    return await logFile!.readAsString();
  }

  Future<void> dispose() async {
    logFile = null;
    currentLogCount = 0;
    currentDate = null;
    baseName = null;
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
  /// When true, logs will be saved in files named as 'logName-YYYY-MM-DD.$_extension'
  final bool saveAllLogs;

  /// Período de retenção dos arquivos de log (usado com saveAllLogs)
  final LogRetentionPeriod logRetentionPeriod;

  /// Tamanho máximo do arquivo de log em bytes (padrão: 5MB)
  /// Quando o arquivo atinge este tamanho, um novo arquivo é criado
  final int maxFileSize;

  const TalkerPersistentConfig({
    this.bufferSize = 100,
    this.flushOnError = true,
    this.maxCapacity = 1000,
    this.enableFileLogging = true,
    this.enableHiveLogging = true,
    this.saveAllLogs = false,
    this.logRetentionPeriod = LogRetentionPeriod.threeDays,
    this.maxFileSize = 5 * 1024 * 1024, // 5MB
  });
}

/// A persistent implementation of [TalkerHistory] that stores logs on disk using Hive.
/// This implementation works for both Dart and Flutter applications.
class TalkerPersistentHistory implements TalkerHistory {
  final String logName;
  final String? savePath;
  final TalkerPersistentConfig config;

  final List<String> _writeBuffer = [];
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
        final logFilePath = path.join(savePath!, '$logName.$_extension');
        log('📝 Initializing log file at: $logFilePath');
        log('📊 Buffer size: ${config.bufferSize} (${config.bufferSize == 0 ? 'real-time' : 'buffered'})');
        log('🚨 Flush on error: ${config.flushOnError}');
        log('💾 Max capacity: ${config.maxCapacity}');
        log('📅 Save all logs: ${config.saveAllLogs}');
        log('📏 Max file size: ${(config.maxFileSize / (1024 * 1024)).toStringAsFixed(1)}MB');

        if (!_isInitialized) {
          final response = await _IsolateManager.instance.sendMessage(FileOperationMessage(
            type: FileOperationType.initialize,
            filePath: logFilePath,
            saveAllLogs: config.saveAllLogs,
            logRetentionPeriod: config.logRetentionPeriod,
            maxFileSize: config.maxFileSize,
            logName: logName,
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
    if (!config.enableFileLogging || config.saveAllLogs) return;

    try {
      final response = await _IsolateManager.instance.sendMessage(FileOperationMessage(
        type: FileOperationType.read,
        logName: logName,
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

          await _IsolateManager.instance.sendMessage(FileOperationMessage(
            type: FileOperationType.write,
            logs: keepLogs,
            maxCapacity: config.maxCapacity,
            logName: logName,
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
      final response = await _IsolateManager.instance.sendMessage(FileOperationMessage(
        type: FileOperationType.write,
        logs: _writeBuffer,
        maxCapacity: config.saveAllLogs ? null : config.maxCapacity,
        logName: logName,
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

  String formatLogSimple(TalkerData data) {
    final timestamp = data.time.toIso8601String();
    final level = data.logLevel?.name.toUpperCase() ?? 'UNKNOWN';
    String msg = (data.message ?? '').replaceAll(RegExp(r'[\r\n]+'), ' ');

    // Para logs HTTP, criar logs separados para requisição e body
    if (_isHttpLog(data)) {
      final body = _extractHttpBody(data);

      // Se tem body, retorna apenas o body (a requisição será logada separadamente)
      if (body.isNotEmpty && body != msg) {
        return '$timestamp [$level] [BODY]: $body';
      }

      // Se não tem body ou é igual à mensagem, retorna como requisição
      return '$timestamp [$level] [REQUEST] $msg';
    }

    // Trunca mensagens muito longas
    if (msg.length > 800) {
      msg = '${msg.substring(0, 800)}...';
    }

    if (data.logLevel == LogLevel.error || data.logLevel == LogLevel.critical) {
      final stack = data.stackTrace?.toString().replaceAll(RegExp(r'[\r\n]+'), ' ') ?? '';
      return '$timestamp [$level] $msg${stack.isNotEmpty ? ' [STACK] $stack' : ''}';
    }
    return '$timestamp [$level] $msg';
  }

  bool _isHttpLog(TalkerData data) {
    // Verificar se é um DioResponseLog
    if (data is DioResponseLog) {
      return true;
    }

    // Verificar por título
    final title = data.title?.toLowerCase() ?? '';
    return [
      'httperror',
      'httprequest',
      'httpresponse',
      'http-request',
      'http-response',
      'http-error',
    ].contains(title);
  }

  String _extractHttpBody(TalkerData data) {
    try {
      final message = data.message ?? '';

      // Tentar extrair diretamente do DioResponseLog se disponível
      if (data is DioResponseLog) {
        final response = data.response;
        if (response.data != null) {
          final responseData = response.data;

          // Verificar se não é bytes e não é muito grande
          if (responseData is! List<int> && responseData.toString().length < 1000) {
            return responseData.toString();
          }
        }
      }

      // Extrair body da requisição (formato do TalkerDioLogger)
      final requestBodyMatch = RegExp(r'Data:\s*(\{.*?\}|\[.*?\]|"[^"]*"|\S+)', dotAll: true).firstMatch(message);
      if (requestBodyMatch != null) {
        return requestBodyMatch.group(1) ?? '';
      }

      // Extrair body da resposta (formato do TalkerDioLogger)
      final responseBodyMatch = RegExp(r'Data:\s*(\{.*?\}|\[.*?\]|"[^"]*"|\S+)', dotAll: true).firstMatch(message);
      if (responseBodyMatch != null) {
        return responseBodyMatch.group(1) ?? '';
      }

      // Extrair body da requisição (outros formatos)
      final requestBodyMatch2 = RegExp(r'Body:\s*(\{.*?\}|\[.*?\]|"[^"]*"|\S+)', dotAll: true).firstMatch(message);
      if (requestBodyMatch2 != null) {
        return requestBodyMatch2.group(1) ?? '';
      }

      // Extrair body da resposta (outros formatos)
      final responseBodyMatch2 = RegExp(r'Response:\s*(\{.*?\}|\[.*?\]|"[^"]*"|\S+)', dotAll: true).firstMatch(message);
      if (responseBodyMatch2 != null) {
        return responseBodyMatch2.group(1) ?? '';
      }

      // Tentar capturar JSON/objetos diretamente
      final jsonMatch = RegExp(r'(\{[^{}]*\}|\[[\[\]]*\])', dotAll: true).firstMatch(message);
      if (jsonMatch != null) {
        return jsonMatch.group(1) ?? '';
      }

      // Tentar capturar strings entre aspas
      final stringMatch = RegExp(r'"([^"]*)"').firstMatch(message);
      if (stringMatch != null) {
        return stringMatch.group(1) ?? '';
      }

      // Se não encontrou nada, retorna a mensagem inteira (URL ou o que vier)
      return message;
    } catch (e) {
      return data.message ?? '';
    }
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
      try {
        // Para logs HTTP, criar logs separados para requisição e resposta
        if (_isHttpLog(data)) {
          final body = _extractHttpBody(data);
          final timestamp = data.time.toIso8601String();
          final level = data.logLevel?.name.toUpperCase() ?? 'UNKNOWN';
          final msg = (data.message ?? '').replaceAll(RegExp(r'[\r\n]+'), ' ');

          // Determinar se é REQUEST ou RESPONSE baseado no título ou presença de body
          final isResponse = data.title?.toLowerCase().contains('response') == true || (data is DioResponseLog && data.response.data != null);

          if (isResponse) {
            // Para respostas, mostrar apenas [RESPONSE]: com os dados
            if (body.isNotEmpty && body != msg) {
              final responseLog = '$timestamp [$level] [RESPONSE]: $body';
              log('📝 Adding response log to buffer: ${responseLog.substring(0, math.min(50, responseLog.length))}...');
              _writeBuffer.add(responseLog);
            } else {
              // Se não tem body, mostrar como resposta normal
              final responseLog = '$timestamp [$level] [RESPONSE] $msg';
              log('📝 Adding response log to buffer: ${responseLog.substring(0, math.min(50, responseLog.length))}...');
              _writeBuffer.add(responseLog);
            }
          } else {
            // Para requisições, mostrar [REQUEST] com a URL
            final requestLog = '$timestamp [$level] [REQUEST] $msg';
            log('📝 Adding request log to buffer: ${requestLog.substring(0, math.min(50, requestLog.length))}...');
            _writeBuffer.add(requestLog);
          }
        } else {
          // Log normal (não HTTP)
          final formattedLog = formatLogSimple(data);
          log('📝 Adding log to buffer: ${formattedLog.substring(0, math.min(50, formattedLog.length))}...');
          _writeBuffer.add(formattedLog);
        }

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

      await _IsolateManager.instance.sendMessage(FileOperationMessage(
        type: FileOperationType.dispose,
        logName: logName,
      ));

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
}
