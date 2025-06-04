import 'package:hive_ce/hive.dart';
import 'package:talker_persistent/src/log_level_adapter.dart';
import 'package:talker_persistent/src/talker_data_adapter.dart';

@GenerateAdapters([
  AdapterSpec<LogLevelPersistent>(),
  AdapterSpec<TalkerDataPersistent>(),
])
part 'hive_adapters.g.dart';
