import 'package:hive_ce/hive.dart';

@HiveType(typeId: 0)
enum LogLevelPersistent {
  @HiveField(0)
  error,
  @HiveField(1)
  critical,
  @HiveField(3)
  info,
  @HiveField(4)
  debug,
  @HiveField(5)
  verbose,
  @HiveField(6)
  warning;
}
