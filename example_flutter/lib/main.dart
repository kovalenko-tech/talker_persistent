import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:talker/talker.dart';
import 'package:talker_persistent/talker_persistent.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
        home: const MyHomePage(title: 'Flutter Demo Home Page'));
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final int _counter = 0;

  Future<void> _incrementCounter() async {
    try {
      // Initialize Hive
      final directory = await getApplicationDocumentsDirectory();
      log('\n📂 Diretório base do aplicativo:');
      log(directory.path);

      final hivePath = path.join(directory.path);
      log('\n🏠 Caminho completo para o Hive:');
      log(hivePath);

      await Directory(hivePath).create(recursive: true);

      // Initialize TalkerPersistent with the log name we'll use
      await TalkerPersistent.instance.initialize(
        path: hivePath,
        logNames: {'logzinho'},
      );

      // Create logs directory in the example folder
      final logsPath = path.join(hivePath, 'log');
      log('\n📝 Caminho para os logs:');
      log(logsPath);
      log('\n💡 Para encontrar o arquivo no Finder:');
      log('1. Abra o Finder');
      log('2. Pressione Cmd + Shift + G');
      log('3. Cole o caminho acima');

      log('\n🔍 Verificando diretório...');
      await Directory(logsPath).create(recursive: true);

      final dirExists = await Directory(logsPath).exists();
      log('📁 Diretório existe? $dirExists');

      // Initialize Talker with persistent history
      log('🔄 Iniciando TalkerPersistentHistory...');
      final history = await TalkerPersistentHistory.create(
        logName: 'biel',
        savePath: logsPath,
        maxCapacity: 100,
      );
      log('✅ TalkerPersistentHistory inicializado');

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
      log('\nCurrent history:');
      for (final logr in history.history) {
        log('- ${logr.displayMessage}');
      }

      final logFile = File(path.join(logsPath, 'biel.log'));
      log('\n📄 Arquivo de log:');
      log(logFile.path);

      if (await logFile.exists()) {
        log('✅ Arquivo encontrado!');
        final stat = await logFile.stat();
        log('📊 Tamanho: ${stat.size} bytes');
        log('⏰ Última modificação: ${stat.modified}');
        log('\n📝 Conteúdo do arquivo:');
        log(await logFile.readAsString());
      } else {
        log('❌ Arquivo não encontrado!');
        log('Verifique se você tem permissões para acessar o diretório.');
      }

      // Clean up
      // await history.dispose();

      log('\n✨ Exemplo finalizado com sucesso!');
    } catch (e, stack) {
      log('Error running example: $e');
      log('Stack trace: $stack');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.inversePrimary, title: Text(widget.title)),
      body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
        const Text('You have pushed the button this many times:'),
        Text('$_counter', style: Theme.of(context).textTheme.headlineMedium)
      ])),
      floatingActionButton: FloatingActionButton(onPressed: _incrementCounter, tooltip: 'Increment', child: const Icon(Icons.add)),
    );
  }
}
