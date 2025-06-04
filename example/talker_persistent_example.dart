import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:talker/talker.dart';
import 'package:talker_persistent/talker_persistent.dart';

Future<void> main() async {
  try {
    // Initialize Hive
    final currentDir = Directory.current;
    final hivePath = path.join(currentDir.path, 'example', 'hive');
    await Directory(hivePath).create(recursive: true);

    // Initialize TalkerPersistent with the log name we'll use
    await TalkerPersistent.instance.initialize(
      path: hivePath,
      logNames: {'example_logs'},
    );

    // Create logs directory in the example folder
    final logsPath = path.join(currentDir.path, 'example', 'logs');
    await Directory(logsPath).create(recursive: true);

    // Initialize Talker with persistent history
    final history = await TalkerPersistentHistory.create(
      logName: 'example_logs',
      savePath: logsPath,
      maxCapacity: 100,
    );

    final talker = Talker(
      history: history,
      settings: TalkerSettings(
        useHistory: true,
      ),
    );

    // Test different types of logs
    talker.debug('This is a debug message');
    talker.info('Application started');
    talker.warning('This is a warning message');
    talker.error('This is an error message', Exception('Test error'));

    // Test history retrieval
    print('\nCurrent history:');
    for (final log in history.history) {
      print('- ${log.displayMessage}');
    }

    final logFile = File(path.join(logsPath, 'example_logs.log'));
    if (await logFile.exists()) {
      print('\nLog file contents:');
      print(await logFile.readAsString());
    } else {
      print('\nError: Log file was not created!');
    }

    // Clean up
    await history.dispose();

    print('\nExample completed successfully!');
  } catch (e, stack) {
    print('Error running example: $e');
    print('Stack trace: $stack');
    rethrow;
  }
}
