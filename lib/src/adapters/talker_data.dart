import 'package:hive_ce/hive.dart';
import 'package:talker/talker.dart';
import 'package:talker_persistent/src/adapters/log_level.dart';

@HiveType(typeId: 1)
class TalkerDataPersistent extends HiveObject {
  @override
  final String? key;
  late final DateTime time;
  final String? message;
  final LogLevelPersistent? logLevel;

  final String? title;
  final StackTrace? stackTrace;
  final String logName;

  TalkerDataPersistent({
    required this.logName,
    DateTime? time,
    this.message,
    this.key,
    this.logLevel,
    this.title,
    this.stackTrace,
  }) : time = time ?? DateTime.now();

  TalkerDataPersistent copyWith({
    DateTime? time,
    String? message,
    String? key,
    LogLevelPersistent? logLevel,
    Object? exception,
    Error? error,
    String? title,
    StackTrace? stackTrace,
    String? id,
  }) {
    return TalkerDataPersistent(
      time: time ?? this.time,
      message: message ?? this.message,
      key: key ?? this.key,
      logLevel: logLevel ?? this.logLevel,
      title: title ?? this.title,
      stackTrace: stackTrace ?? this.stackTrace,
      logName: id ?? logName,
    );
  }

  LogLevel? _convertLogLevel() {
    if (logLevel == null) return null;
    switch (logLevel!) {
      case LogLevelPersistent.error:
        return LogLevel.error;
      case LogLevelPersistent.critical:
        return LogLevel.critical;
      case LogLevelPersistent.info:
        return LogLevel.info;
      case LogLevelPersistent.debug:
        return LogLevel.debug;
      case LogLevelPersistent.verbose:
        return LogLevel.verbose;
      case LogLevelPersistent.warning:
        return LogLevel.warning;
    }
  }

  TalkerData toTalkerData() {
    return TalkerData(
      message,
      logLevel: _convertLogLevel(),
      stackTrace: stackTrace,
      title: title ?? 'log',
      time: time,
      key: key,
    );
  }

  static TalkerDataPersistent fromTalkerData({required TalkerData data, required String id}) {
    return TalkerDataPersistent(
      time: data.time,
      message: data.message,
      key: data.key,
      logLevel: data.logLevel == null ? null : LogLevelPersistent.values[data.logLevel!.index],
      stackTrace: data.stackTrace,
      title: data.title,
      logName: id,
    );
  }
}
