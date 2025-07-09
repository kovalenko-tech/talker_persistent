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

An extension for the [talker](https://pub.dev/packages/talker) package that adds persistence to logs, allowing you to save logs both to files and Hive database, with flexible configuration options for buffer management and real-time logging.

## Features

- 📝 Save logs to text files
- 💾 Persist logs using Hive database
- 🔄 Configurable buffer size (real-time or buffered)
- 🚨 Immediate flush for error and critical logs
- 🎨 Beautiful log formatting
- 🚀 Supports all Talker log types
- 📱 Works with both Flutter and pure Dart
- 🎛️ Flexible logging options (local storage or no storage)
- ⚡ Real-time logging support (buffer size = 0)

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

void main() async {
  // Initialize TalkerPersistent
  await TalkerPersistent.instance.initialize(
    path: 'path/to/hive/directory',
    logNames: {'my_app_logs'},
  );

  // Create persistent history with default configuration
  final history = await TalkerPersistentHistory.create(
    logName: 'my_app_logs',
    savePath: 'logs',
  );

  // Use with Talker
  final talker = Talker(history: history);
  
  talker.info('Application started');
  talker.error('An error occurred');
}
```

### Advanced Configuration

The package now supports flexible configuration through `TalkerPersistentConfig`:

```dart
// Configuration with custom settings
final config = TalkerPersistentConfig(
  bufferSize: 0, // Real-time logging (no buffer)
  flushOnError: true, // Immediate flush for errors
  maxCapacity: 1000, // Maximum logs to keep
  enableFileLogging: true, // Enable file logging
  enableHiveLogging: true, // Enable Hive database logging
);

final history = await TalkerPersistentHistory.create(
  logName: 'production_logs',
  savePath: 'logs/production',
  config: config,
);
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `bufferSize` | `int` | `100` | Buffer size for logs. If 0, logs are written immediately (real-time). If > 0, logs are buffered and written when buffer is full. |
| `flushOnError` | `bool` | `true` | Whether to flush immediately for error and critical logs |
| `maxCapacity` | `int` | `1000` | Maximum number of logs to keep in history |
| `enableFileLogging` | `bool` | `true` | Whether to enable file logging |
| `enableHiveLogging` | `bool` | `true` | Whether to enable Hive database logging |
| `saveAllLogs` | `bool` | `false` | Whether to save all logs of the day in daily files |
| `logRetentionPeriod` | `LogRetentionPeriod` | `threeDays` | Period to retain log files when using saveAllLogs |
| `maxFileSize` | `int` | `5MB` | Maximum file size in bytes. When reached, removes oldest half |

### Real-time Logging

For critical applications where immediate log writing is required:

```dart
final config = TalkerPersistentConfig(
  bufferSize: 0, // No buffer - real-time logging
  flushOnError: true, // Always flush errors immediately
  maxCapacity: 5000, // High capacity for production
);

final history = await TalkerPersistentHistory.create(
  logName: 'critical_logs',
  savePath: 'logs/critical',
  config: config,
);
```

### Buffered Logging

For performance optimization with buffered writes:

```dart
final config = TalkerPersistentConfig(
  bufferSize: 100, // Buffer 100 logs before writing
  flushOnError: true, // Still flush errors immediately
  maxCapacity: 1000,
);

final history = await TalkerPersistentHistory.create(
  logName: 'performance_logs',
  savePath: 'logs/performance',
  config: config,
);
```

### File-only Logging

If you only want file logging without Hive database:

```dart
final config = TalkerPersistentConfig(
  bufferSize: 50,
  flushOnError: true,
  maxCapacity: 500,
  enableFileLogging: true,
  enableHiveLogging: false, // Disable Hive
);

final history = await TalkerPersistentHistory.create(
  logName: 'file_only_logs',
  savePath: 'logs/file_only',
  config: config,
);
```

### Error Handling

The package automatically handles error and critical logs with immediate flush when `flushOnError` is enabled:

```dart
final talker = Talker(history: history);

// These will be flushed immediately if flushOnError is true
talker.error('Database connection failed');
talker.critical('Application crash detected');

// Normal logs follow the buffer configuration
talker.info('User logged in');
talker.debug('Processing request');
```

### File Size Control

The package now includes automatic file size management to prevent log files from growing too large:

```dart
final config = TalkerPersistentConfig(
  bufferSize: 0, // Real-time logging
  maxFileSize: 5 * 1024 * 1024, // 5MB limit
  enableFileLogging: true,
);

final history = await TalkerPersistentHistory.create(
  logName: 'controlled_logs',
  savePath: 'logs',
  config: config,
);
```

**How it works:**
- When the log file reaches the specified `maxFileSize` (default: 5MB)
- The system automatically removes the oldest half of the logs
- Keeps only the most recent logs
- This prevents the file from growing indefinitely
- Perfect for long-running applications

**Benefits:**
- ✅ Prevents disk space issues
- ✅ Maintains recent logs for debugging
- ✅ Automatic cleanup without manual intervention
- ✅ Configurable size limit
- ✅ Preserves log integrity

## Examples

See the `example/` directory for complete working examples:

- `talker_persistent_example.dart` - Demonstrates different configuration scenarios
- `example_flutter/` - Flutter-specific example

## Migration from Previous Versions

If you're upgrading from a previous version, the main changes are:

1. **New Configuration Class**: Use `TalkerPersistentConfig` instead of individual parameters
2. **Buffer Control**: New `bufferSize` parameter for real-time vs buffered logging
3. **Error Flush**: New `flushOnError` parameter for immediate error logging
4. **Selective Logging**: New `enableFileLogging` and `enableHiveLogging` parameters

### Old Way:
```dart
final history = await TalkerPersistentHistory.create(
  logName: 'logs',
  savePath: 'logs',
  maxCapacity: 1000,
);
```

### New Way:
```dart
final config = TalkerPersistentConfig(
  bufferSize: 100,
  flushOnError: true,
  maxCapacity: 1000,
  enableFileLogging: true,
  enableHiveLogging: true,
);

final history = await TalkerPersistentHistory.create(
  logName: 'logs',
  savePath: 'logs',
  config: config,
);
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2024 Talker Persistent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

For the complete license text, please see the [LICENSE](LICENSE) file.
