// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hive_adapters.dart';

// **************************************************************************
// AdaptersGenerator
// **************************************************************************

class LogLevelPersistentAdapter extends TypeAdapter<LogLevelPersistent> {
  @override
  final typeId = 0;

  @override
  LogLevelPersistent read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return LogLevelPersistent.error;
      case 1:
        return LogLevelPersistent.critical;
      case 2:
        return LogLevelPersistent.info;
      case 3:
        return LogLevelPersistent.debug;
      case 4:
        return LogLevelPersistent.verbose;
      case 5:
        return LogLevelPersistent.warning;
      default:
        return LogLevelPersistent.error;
    }
  }

  @override
  void write(BinaryWriter writer, LogLevelPersistent obj) {
    switch (obj) {
      case LogLevelPersistent.error:
        writer.writeByte(0);
      case LogLevelPersistent.critical:
        writer.writeByte(1);
      case LogLevelPersistent.info:
        writer.writeByte(2);
      case LogLevelPersistent.debug:
        writer.writeByte(3);
      case LogLevelPersistent.verbose:
        writer.writeByte(4);
      case LogLevelPersistent.warning:
        writer.writeByte(5);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogLevelPersistentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TalkerDataPersistentAdapter extends TypeAdapter<TalkerDataPersistent> {
  @override
  final typeId = 1;

  @override
  TalkerDataPersistent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TalkerDataPersistent(
      logName: fields[8] as String,
      time: fields[1] as DateTime?,
      message: fields[2] as String?,
      key: fields[0] as String?,
      logLevel: fields[3] as LogLevelPersistent?,
      title: fields[6] as String?,
      stackTrace: fields[7] as StackTrace?,
    );
  }

  @override
  void write(BinaryWriter writer, TalkerDataPersistent obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.time)
      ..writeByte(2)
      ..write(obj.message)
      ..writeByte(3)
      ..write(obj.logLevel)
      ..writeByte(6)
      ..write(obj.title)
      ..writeByte(7)
      ..write(obj.stackTrace)
      ..writeByte(8)
      ..write(obj.logName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TalkerDataPersistentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
