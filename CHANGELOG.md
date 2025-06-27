# Changelog

## [2.0.0+1] - 2024-12-19

### Added
- **Configuração de Buffer**: Nova classe `TalkerPersistentConfig` para controle avançado do comportamento de logging
- **Logging em Tempo Real**: Suporte para buffer size = 0, permitindo logs imediatos (real-time)
- **Flush Imediato para Erros**: Configuração `flushOnError` para flush automático de logs de erro e críticos
- **Controle Seletivo de Logging**: Opções `enableFileLogging` e `enableHiveLogging` para habilitar/desabilitar tipos específicos de logging
- **Logs de Configuração**: Logs informativos durante a inicialização mostrando as configurações aplicadas

### Changed
- **API Breaking**: Construtor `TalkerPersistentHistory` agora usa `TalkerPersistentConfig` ao invés de parâmetros individuais
- **Comportamento Padrão**: Buffer padrão alterado para 100 logs com flush imediato para erros
- **Melhor Performance**: Otimizações no sistema de buffer e flush

### Fixed
- **Correção de Propriedade**: Corrigido acesso à propriedade `logLevel` do `TalkerData`
- **Tratamento de Erros**: Melhor tratamento de erros durante operações de arquivo

### Migration Guide
Para migrar de versões anteriores:

```dart
// Antes
final history = await TalkerPersistentHistory.create(
  logName: 'logs',
  savePath: 'logs',
  maxCapacity: 1000,
);

// Depois
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

## [1.0.0+4] - 2024-12-18

### Added
- Initial release with basic persistent logging functionality
- File and Hive database logging support
- Configurable history capacity
- Beautiful log formatting
- Support for all Talker log types

## 1.0.0+3

- FIX: write file on windows

## 1.0.0+3

- FIX: recursive save file

## 1.0.0+2

- Added maxLines handling for fixed log files
- Improved performance of physical file writing with buffering
- Added file rotation to maintain log file size

## 1.0.0

- Initial version.
