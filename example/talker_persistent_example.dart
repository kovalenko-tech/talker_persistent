import 'package:talker/talker.dart';
import 'package:talker_persistent/talker_persistent.dart';

void main() async {
  // Exemplo 1: Configuração com buffer (padrão)
  print('=== Exemplo 1: Configuração com buffer ===');
  await exemploComBuffer();

  // Exemplo 2: Configuração sem buffer (tempo real)
  print('\n=== Exemplo 2: Configuração sem buffer (tempo real) ===');
  await exemploSemBuffer();

  // Exemplo 3: Configuração personalizada
  print('\n=== Exemplo 3: Configuração personalizada ===');
  await exemploConfiguracaoPersonalizada();
}

/// Exemplo com buffer padrão (100 logs)
Future<void> exemploComBuffer() async {
  final config = TalkerPersistentConfig(
    bufferSize: 100, // Buffer de 100 logs
    flushOnError: true, // Flush imediato para erros
    maxCapacity: 1000, // Máximo de 1000 logs
    enableFileLogging: true,
    enableHiveLogging: true,
  );

  final history = await TalkerPersistentHistory.create(
    logName: 'exemplo_buffer',
    savePath: 'logs',
    config: config,
  );

  final talker = Talker(history: history);

  // Simula logs normais
  for (int i = 1; i <= 5; i++) {
    talker.info('Log normal $i');
    await Future.delayed(Duration(milliseconds: 100));
  }

  // Simula um erro (será flush imediato)
  talker.error('Erro crítico - será flush imediato!');

  // Continua com logs normais
  for (int i = 6; i <= 10; i++) {
    talker.info('Log normal $i');
    await Future.delayed(Duration(milliseconds: 100));
  }

  await history.dispose();
}

/// Exemplo sem buffer (tempo real)
Future<void> exemploSemBuffer() async {
  final config = TalkerPersistentConfig(
    bufferSize: 0, // Sem buffer - tempo real
    flushOnError: true,
    maxCapacity: 500,
    enableFileLogging: true,
    enableHiveLogging: true,
  );

  final history = await TalkerPersistentHistory.create(
    logName: 'exemplo_tempo_real',
    savePath: 'logs',
    config: config,
  );

  final talker = Talker(history: history);

  // Todos os logs serão escritos imediatamente
  for (int i = 1; i <= 5; i++) {
    talker.info('Log tempo real $i');
    await Future.delayed(Duration(milliseconds: 100));
  }

  talker.error('Erro em tempo real');
  talker.critical('Erro crítico em tempo real');

  await history.dispose();
}

/// Exemplo com configuração personalizada
Future<void> exemploConfiguracaoPersonalizada() async {
  final config = TalkerPersistentConfig(
    bufferSize: 50, // Buffer menor
    flushOnError: false, // Não flush imediato para erros
    maxCapacity: 200, // Capacidade menor
    enableFileLogging: true,
    enableHiveLogging: false, // Apenas arquivo, sem Hive
  );

  final history = await TalkerPersistentHistory.create(
    logName: 'exemplo_personalizado',
    savePath: 'logs',
    config: config,
  );

  final talker = Talker(history: history);

  // Logs normais
  for (int i = 1; i <= 10; i++) {
    talker.info('Log personalizado $i');
    await Future.delayed(Duration(milliseconds: 50));
  }

  // Erros não terão flush imediato
  talker.error('Erro sem flush imediato');
  talker.critical('Erro crítico sem flush imediato');

  // Continua até encher o buffer
  for (int i = 11; i <= 60; i++) {
    talker.info('Log para encher buffer $i');
    await Future.delayed(Duration(milliseconds: 10));
  }

  await history.dispose();
}

/// Exemplo de uso em produção
Future<void> exemploProducao() async {
  // Configuração otimizada para produção
  final config = TalkerPersistentConfig(
    bufferSize: 0, // Tempo real para logs críticos
    flushOnError: true, // Sempre flush erros
    maxCapacity: 5000, // Capacidade alta
    enableFileLogging: true,
    enableHiveLogging: true,
  );

  final history = await TalkerPersistentHistory.create(
    logName: 'producao',
    savePath: 'logs/producao',
    config: config,
  );

  final talker = Talker(history: history);

  // Simula logs de produção
  talker.info('Aplicação iniciada');
  talker.info('Conectando ao banco de dados...');

  try {
    // Simula uma operação que pode falhar
    await Future.delayed(Duration(seconds: 1));
    throw Exception('Erro de conexão com banco');
  } catch (e, stack) {
    talker.error('Falha na conexão: $e');
  }

  talker.info('Tentando reconexão...');
  talker.info('Reconexão bem-sucedida');

  await history.dispose();
}
