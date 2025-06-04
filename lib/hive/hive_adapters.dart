import 'package:hive_ce/hive.dart';
import 'package:talker_persistent/src/adapters/log_level.dart';
import 'package:talker_persistent/src/adapters/talker_data.dart';

@GenerateAdapters([
  AdapterSpec<LogLevelPersistent>(),
  AdapterSpec<TalkerDataPersistent>(),
])
part 'hive_adapters.g.dart';
