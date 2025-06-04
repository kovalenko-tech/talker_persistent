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

Uma extensão para o pacote [talker](https://pub.dev/packages/talker) que adiciona persistência aos logs, permitindo salvar logs tanto em arquivo quanto em banco de dados Hive.

## Características

- 📝 Salva logs em arquivo texto
- 💾 Persiste logs usando Hive
- 🔄 Mantém histórico com capacidade configurável
- 🎨 Formatação bonita dos logs
- 🚀 Suporta todos os tipos de logs do Talker
- 📱 Funciona tanto em Flutter quanto em Dart puro

## Instalação

Adicione ao seu `pubspec.yaml`:

```yaml
dependencies:
  talker_persistent: ^1.0.0
```

## Uso

### Inicialização Básica

```dart
import 'package:talker_persistent/talker_persistent.dart';
import 'package:talker/talker.dart';

Future<void> main() async {
  // Inicialize o TalkerPersistent
  await TalkerPersistent.instance.initialize(
    path: 'caminho/para/hive',
    logNames: {'meu_log'},
  );

  // Crie uma instância do histórico persistente
  final history = await TalkerPersistentHistory.create(
    logName: 'meu_log',
    savePath: 'caminho/para/logs',
    maxCapacity: 1000,
  );

  // Configure o Talker com o histórico persistente
  final talker = Talker(
    history: history,
    settings: TalkerSettings(
      useHistory: true,
    ),
  );

  // Use normalmente
  talker.debug('Mensagem de debug');
  talker.info('Aplicação iniciada');
  talker.warning('Aviso importante');
  talker.error('Erro ocorrido', Exception('Teste'));
}
```

### Configurações Avançadas

#### Capacidade Máxima

Você pode configurar quantos logs serão mantidos no histórico:

```dart
final history = await TalkerPersistentHistory.create(
  logName: 'meu_log',
  maxCapacity: 500, // Mantém apenas os últimos 500 logs
);
```

#### Múltiplos Logs

É possível ter diferentes arquivos de log para diferentes propósitos:

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

### Limpeza dos Logs

Para limpar os logs:

```dart
// Limpa tanto o arquivo quanto o histórico do Hive
history.clean();
```

### Recuperando Logs

```dart
// Obtém todos os logs do histórico
final logs = history.history;

// Imprime cada log
for (final log in logs) {
  print(log.displayMessage);
}
```

### Formato do Arquivo de Log

Os logs são salvos em um formato legível e bem estruturado:

```
┌───────────────────────────────────────────────────
│ [debug] 10:30:45 123ms
│ Mensagem de debug
└───────────────────────────────────────────────────
┌───────────────────────────────────────────────────
│ [error] 10:30:46 456ms
│ Erro ocorrido
│
│ Type: Exception
│ Message: Teste de erro
│
│ StackTrace:
│   #0 main (file:///exemplo.dart:10:5)
└───────────────────────────────────────────────────
```

## Boas Práticas

1. **Sempre inicialize o TalkerPersistent antes de usar**
   ```dart
   await TalkerPersistent.instance.initialize(...);
   ```

2. **Use o método create para instanciar TalkerPersistentHistory**
   ```dart
   final history = await TalkerPersistentHistory.create(...);
   ```

3. **Faça dispose quando não precisar mais do histórico**
   ```dart
   await history.dispose();
   ```

4. **Configure maxCapacity adequadamente**
   - Valores muito altos podem impactar a performance
   - Valores muito baixos podem perder informações importantes

## Contribuindo

Contribuições são bem-vindas! Por favor, siga estas etapas:

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## Licença

Este projeto está licenciado sob a MIT License - veja o arquivo [LICENSE](LICENSE) para detalhes.
