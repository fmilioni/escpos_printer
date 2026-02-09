import 'dart:async';
import 'dart:math';

import '../encoding/escpos_encoder.dart';
import '../model/endpoints.dart';
import '../model/exceptions.dart';
import '../model/options.dart';
import '../model/result.dart';
import '../model/status.dart';
import '../template/esctpl_parser.dart';
import '../template/mustache_renderer.dart';
import '../template/operations.dart';
import '../template/receipt_template.dart';
import '../transport/default_transport_factory.dart';
import '../transport/transport.dart';

final class EscPosClient {
  EscPosClient({
    TransportFactory? transportFactory,
    ReconnectPolicy reconnectPolicy = const ReconnectPolicy(),
    MustacheRenderer renderer = const MustacheRenderer(),
    EscTplParser parser = const EscTplParser(),
  }) : _transportFactory = transportFactory ?? const DefaultTransportFactory(),
       _defaultReconnectPolicy = reconnectPolicy,
       _renderer = renderer,
       _parser = parser;

  final TransportFactory _transportFactory;
  final ReconnectPolicy _defaultReconnectPolicy;
  final MustacheRenderer _renderer;
  final EscTplParser _parser;

  final Random _random = Random();

  Future<void> _queueTail = Future<void>.value();

  PrinterEndpoint? _endpoint;
  PrinterTransport? _transport;
  ReconnectPolicy? _sessionReconnectPolicy;

  bool get isConnected => _transport?.isConnected == true;

  Future<void> connect(PrinterEndpoint endpoint, {ReconnectPolicy? policy}) {
    return _enqueue<void>(() async {
      await _disconnectInternal();
      _endpoint = endpoint;
      _sessionReconnectPolicy = policy ?? _defaultReconnectPolicy;
      _transport = await _transportFactory.create(endpoint);
      await _transport!.connect();
    });
  }

  Future<void> disconnect() {
    return _enqueue<void>(() async {
      await _disconnectInternal();
    });
  }

  Future<PrintResult> print({
    required ReceiptTemplate template,
    Map<String, Object?> variables = const <String, Object?>{},
    TemplateRenderOptions renderOptions = const TemplateRenderOptions(),
    PrintOptions printOptions = const PrintOptions(),
  }) {
    return _enqueue<PrintResult>(() async {
      return _printInternal(
        template: template,
        variables: variables,
        renderOptions: renderOptions,
        printOptions: printOptions,
      );
    });
  }

  Future<PrintResult> printFromString({
    required String template,
    required Map<String, Object?> variables,
    TemplateRenderOptions renderOptions = const TemplateRenderOptions(),
    PrintOptions printOptions = const PrintOptions(),
  }) {
    return print(
      template: ReceiptTemplate.string(template),
      variables: variables,
      renderOptions: renderOptions,
      printOptions: printOptions,
    );
  }

  Future<PrintResult> printOnce({
    required PrinterEndpoint endpoint,
    required ReceiptTemplate template,
    Map<String, Object?> variables = const <String, Object?>{},
    TemplateRenderOptions renderOptions = const TemplateRenderOptions(),
    PrintOptions printOptions = const PrintOptions(),
    ReconnectPolicy? reconnectPolicy,
  }) {
    return _enqueue<PrintResult>(() async {
      await _disconnectInternal();
      _endpoint = endpoint;
      _sessionReconnectPolicy = reconnectPolicy ?? _defaultReconnectPolicy;
      _transport = await _transportFactory.create(endpoint);
      await _transport!.connect();

      try {
        return await _printInternal(
          template: template,
          variables: variables,
          renderOptions: renderOptions,
          printOptions: printOptions,
        );
      } finally {
        await _disconnectInternal();
      }
    });
  }

  Future<void> feed(int lines) {
    return _enqueue<void>(() async {
      await _sendOps(<PrintOp>[FeedOp(lines)]);
    });
  }

  Future<void> cut([CutMode mode = CutMode.partial]) {
    return _enqueue<void>(() async {
      await _sendOps(<PrintOp>[CutOp(mode)]);
    });
  }

  Future<void> openCashDrawer({
    DrawerPin pin = DrawerPin.pin2,
    int onMs = 120,
    int offMs = 240,
  }) {
    return _enqueue<void>(() async {
      await _sendOps(<PrintOp>[
        DrawerKickOp(pin: pin, onMs: onMs, offMs: offMs),
      ]);
    });
  }

  Future<PrinterStatus> getStatus() {
    return _enqueue<PrinterStatus>(() async {
      final transport = _transport;
      if (transport == null) {
        throw ConnectionException(
          'Nenhuma sessao ativa. Execute connect() antes de getStatus().',
        );
      }

      if (!transport.isConnected) {
        await _reconnect();
      }

      try {
        return await _transport!.getStatus();
      } catch (_) {
        return const PrinterStatus.unknown();
      }
    });
  }

  Future<PrintResult> _printInternal({
    required ReceiptTemplate template,
    required Map<String, Object?> variables,
    required TemplateRenderOptions renderOptions,
    required PrintOptions printOptions,
  }) async {
    final startedAt = DateTime.now();
    final resolvedOps = _resolveTemplate(
      template: template,
      variables: variables,
      renderOptions: renderOptions,
    );

    final encoder = EscPosEncoder(
      paperWidthChars: printOptions.paperWidthChars,
    );
    final bytes = encoder.encode(
      resolvedOps,
      initializePrinter: printOptions.initializePrinter,
    );

    await _sendBytes(bytes);

    final status = await _readStatusBestEffort();
    return PrintResult(
      bytesSent: bytes.length,
      duration: DateTime.now().difference(startedAt),
      status: status,
    );
  }

  List<PrintOp> _resolveTemplate({
    required ReceiptTemplate template,
    required Map<String, Object?> variables,
    required TemplateRenderOptions renderOptions,
  }) {
    return switch (template) {
      DslReceiptTemplate(:final ops) => _resolveDslOps(
        ops,
        variables,
        renderOptions,
      ),
      StringReceiptTemplate(:final template) => _resolveStringTemplate(
        template,
        variables,
        renderOptions,
      ),
    };
  }

  List<PrintOp> _resolveDslOps(
    List<PrintOp> rawOps,
    Map<String, Object?> variables,
    TemplateRenderOptions renderOptions,
  ) {
    final result = <PrintOp>[];

    for (final op in rawOps) {
      switch (op) {
        case TextTemplateOp(:final template, :final vars, :final style):
          final mergedVars = <String, Object?>{...variables, ...vars};
          final rendered = _renderer.render(
            template,
            mergedVars,
            strictMissingVariables: renderOptions.strictMissingVariables,
          );
          result.add(TextOp(rendered, style: style));

        case TemplateBlockOp(:final template, :final vars):
          final mergedVars = <String, Object?>{...variables, ...vars};
          final rendered = _renderer.render(
            template,
            mergedVars,
            strictMissingVariables: renderOptions.strictMissingVariables,
          );
          result.addAll(_parser.parse(rendered));

        default:
          result.add(op);
      }
    }

    return List<PrintOp>.unmodifiable(result);
  }

  List<PrintOp> _resolveStringTemplate(
    String source,
    Map<String, Object?> variables,
    TemplateRenderOptions renderOptions,
  ) {
    final rendered = _renderer.render(
      source,
      variables,
      strictMissingVariables: renderOptions.strictMissingVariables,
    );
    return _parser.parse(rendered);
  }

  Future<void> _sendOps(List<PrintOp> ops) async {
    final encoder = EscPosEncoder();
    final bytes = encoder.encode(ops, initializePrinter: false);
    await _sendBytes(bytes);
  }

  Future<void> _sendBytes(List<int> bytes) async {
    final policy = _sessionReconnectPolicy ?? _defaultReconnectPolicy;
    final maxAttempts = policy.maxAttempts;

    for (var attempt = 0; ; attempt++) {
      try {
        final transport = _transport;
        if (transport == null) {
          throw ConnectionException(
            'Nenhuma sessao ativa. Execute connect() antes de imprimir.',
          );
        }

        if (!transport.isConnected) {
          await _reconnect();
        }

        await _transport!.write(bytes);
        return;
      } catch (error) {
        if (attempt >= maxAttempts) {
          throw ConnectionException(
            'Falha ao enviar dados para a impressora apos retries.',
            error,
          );
        }

        await _reconnect();
        await Future<void>.delayed(
          policy.delayForAttempt(attempt + 1, random: _random),
        );
      }
    }
  }

  Future<void> _reconnect() async {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw ConnectionException(
        'Nao e possivel reconectar sem endpoint configurado.',
      );
    }

    await _transport?.disconnect();
    _transport = await _transportFactory.create(endpoint);
    await _transport!.connect();
  }

  Future<PrinterStatus> _readStatusBestEffort() async {
    final transport = _transport;
    if (transport == null) {
      return const PrinterStatus.unknown();
    }

    try {
      return await transport.getStatus();
    } catch (_) {
      return const PrinterStatus.unknown();
    }
  }

  Future<void> _disconnectInternal() async {
    final transport = _transport;
    _transport = null;
    _endpoint = null;
    _sessionReconnectPolicy = null;

    if (transport != null) {
      await transport.disconnect();
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();

    _queueTail = _queueTail.catchError((_) {}).then((_) async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }
}
