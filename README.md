<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages). 
-->

# Talker Persistent

An extension for the [talker](https://pub.dev/packages/talker) package that adds persistence to logs, allowing you to save logs both to files and Hive database, with the flexibility to disable logging when needed.

## Features

- 📝 Save logs to text files
- 💾 Persist logs using Hive database
- 🔄 Maintain configurable history capacity
- 🎨 Beautiful log formatting
- 🚀 Supports all Talker log types
- 📱 Works with both Flutter and pure Dart
- 🎛️ Flexible logging options (local storage or no storage)


## Homologated Versions

While the package is designed to be flexible with dependencies, here are the specific versions that have been thoroughly tested and are known to work well together:

| Package | Version | Description |
|---------|---------|-------------|
| talker |  ^4.8.2 | Core logging functionality |
| path |  ^1.8.0 | Path manipulation utilities |
| hive_ce |  ^2.11.3 | Local database storage |
| collection |  ^1.19.1 | Collection utilities |

These versions are provided for reference only. The package is designed to work with any compatible version of these dependencies to avoid conflicts with your project's requirements.

## Usage

### Basic Initialization

```dart
import 'package:talker_persistent/talker_persistent.dart';
import 'package:talker/talker.dart';

Future<void> main() async {
  // Initialize TalkerPersistent
  await TalkerPersistent.instance.initialize(
    path: 'path/to/hive',
    logNames: {'my_log'},
  );

  // Create a persistent history instance with local storage
  final history = await TalkerPersistentHistory.create(
    logName: 'my_log',
    savePath: 'path/to/logs',  // Set to null to disable file logging
    maxCapacity: 1000,
  );

  // Configure Talker with persistent history
  final talker = Talker(
    history: history,
    settings: TalkerSettings(
      useHistory: true,  // Set to false to disable logging completely
    ),
  );

  // Use normally
  talker.debug('Debug message');
  talker.info('Application started');
  talker.warning('Important warning');
  talker.error('Error occurred', Exception('Test'));
}
```

### Local Logging Options

#### Disable File Logging

If you don't want to save logs to files but still want to keep them in memory:

```dart
final history = await TalkerPersistentHistory.create(
  logName: 'my_log',
  savePath: null,  // This disables file logging
  maxCapacity: 1000,
);
```

#### Disable All Logging

To completely disable logging:

```dart
final talker = Talker(
  settings: TalkerSettings(
    useHistory: false,  // This disables all logging
  ),
);
```

#### Custom Log Directory

Specify a custom directory for your log files:

```dart
final history = await TalkerPersistentHistory.create(
  logName: 'my_log',
  savePath: 'custom/path/to/logs',
  maxCapacity: 1000,
);
```

### Advanced Configuration

#### Maximum Capacity

Configure how many logs to keep in history:

```dart
final history = await TalkerPersistentHistory.create(
  logName: 'my_log',
  maxCapacity: 500, // Keeps only the last 500 logs
);
```

#### Multiple Logs

You can have different log files for different purposes:

```dart
await TalkerPersistent.instance.initialize(
  logNames: {'app_logs', 'error_logs', 'api_logs'},
);

final appHistory = await TalkerPersistentHistory.create(
  logName: 'app_logs',
  savePath: 'logs/app',
);

final errorHistory = await TalkerPersistentHistory.create(
  logName: 'error_logs',
  savePath: 'logs/errors',
);

final apiHistory = await TalkerPersistentHistory.create(
  logName: 'api_logs',
  savePath: 'logs/api',
);
```

### Cleaning Logs

To clean the logs:

```dart
// Cleans both file and Hive history
history.clean();
```

### Retrieving Logs

```dart
// Get all logs from history
final logs = history.history;

// Print each log
for (final log in logs) {
  print(log.displayMessage);
}
```

### Log File Format

Logs are saved in a readable and well-structured format:

```
┌───────────────────────────────────────────────────
│ [debug] 10:30:45 123ms
│ Debug message
└───────────────────────────────────────────────────
┌───────────────────────────────────────────────────
│ [error] 10:30:46 456ms
│ Error occurred
│
│ Type: Exception
│ Message: Test error
│
│ StackTrace:
│   #0 main (file:///example.dart:10:5)
└───────────────────────────────────────────────────
```

## Best Practices

1. **Always initialize TalkerPersistent before use**
   ```dart
   await TalkerPersistent.instance.initialize(...);
   ```

2. **Use the create method to instantiate TalkerPersistentHistory**
   ```dart
   final history = await TalkerPersistentHistory.create(...);
   ```

3. **Dispose when you no longer need the history**
   ```dart
   await history.dispose();
   ```

4. **Configure maxCapacity appropriately**
   - High values may impact performance
   - Low values might lose important information

5. **Consider logging strategy**
   - Enable file logging for production environments
   - Disable file logging for development if not needed
   - Use appropriate log levels for different types of information

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
