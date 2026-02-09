import 'package:escpos_printer/escpos_printer.dart';
import 'package:escpos_printer_example/src/demo_controller.dart';
import 'package:escpos_printer_example/src/demo_page.dart';
import 'package:escpos_printer_example/src/ticket_samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renderiza secoes principais no layout vertical', (tester) async {
    final controller = FakeDemoController();

    await tester.pumpWidget(
      MaterialApp(home: DemoPage(controller: controller)),
    );

    expect(find.text('1) Sessao atual'), findsOneWidget);
    expect(find.text('2) Busca de impressoras'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('3) Conexao manual'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('3) Conexao manual'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('4) Status e comandos diretos'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('4) Status e comandos diretos'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('5) Imprimir ticket de exemplo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('5) Imprimir ticket de exemplo'), findsOneWidget);
    expect(find.text('Largura do papel'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('6) Log de execucao'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('6) Log de execucao'), findsOneWidget);
  });

  testWidgets('aciona callbacks principais da tela', (tester) async {
    final controller = FakeDemoController();

    await tester.pumpWidget(
      MaterialApp(home: DemoPage(controller: controller)),
    );

    await tester.ensureVisible(find.text('Buscar impressoras'));
    await tester.tap(find.text('Buscar impressoras'));
    await tester.pump();
    expect(controller.searchCalls, 1);

    await tester.scrollUntilVisible(
      find.text('Conectar manual'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Conectar manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conectar manual'));
    await tester.pump();
    expect(controller.connectManualCalls, 1);

    await tester.scrollUntilVisible(
      find.text('Imprimir ticket (DSL completo)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Imprimir ticket (DSL completo)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imprimir ticket (DSL completo)'));
    await tester.pump();
    expect(controller.printDslCalls, 1);

    await tester.ensureVisible(
      find.text('Imprimir ticket (EscTpl string completo)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imprimir ticket (EscTpl string completo)'));
    await tester.pump();
    expect(controller.printEscTplCalls, 1);

    await tester.ensureVisible(
      find.text('Imprimir ticket (Hibrido DSL+templateBlock)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imprimir ticket (Hibrido DSL+templateBlock)'));
    await tester.pump();
    expect(controller.printHybridCalls, 1);
  });
}

class FakeDemoController extends DemoController {
  int searchCalls = 0;
  int connectManualCalls = 0;
  int printDslCalls = 0;
  int printEscTplCalls = 0;
  int printHybridCalls = 0;

  @override
  Future<void> searchPrinters({
    required Set<DiscoveryTransport> transports,
    required Duration timeout,
    required int wifiPort,
    required List<String> wifiCidrs,
  }) async {
    searchCalls++;
  }

  @override
  Future<void> connectManual(ManualConnectionDraft draft) async {
    connectManualCalls++;
  }

  @override
  Future<void> printDslTicket(
    DemoTicketData data, {
    PrintOptions printOptions = const PrintOptions(paperWidthChars: 48),
  }) async {
    printDslCalls++;
  }

  @override
  Future<void> printEscTplTicket(
    DemoTicketData data, {
    PrintOptions printOptions = const PrintOptions(paperWidthChars: 48),
  }) async {
    printEscTplCalls++;
  }

  @override
  Future<void> printHybridTicket(
    DemoTicketData data, {
    PrintOptions printOptions = const PrintOptions(paperWidthChars: 48),
  }) async {
    printHybridCalls++;
  }
}
