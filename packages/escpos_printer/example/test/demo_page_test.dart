import 'package:escpos_printer/escpos_printer.dart';
import 'package:escpos_printer_example/src/demo_controller.dart';
import 'package:escpos_printer_example/src/demo_page.dart';
import 'package:escpos_printer_example/src/ticket_samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders main sections in vertical layout', (tester) async {
    final controller = FakeDemoController();

    await tester.pumpWidget(
      MaterialApp(home: DemoPage(controller: controller)),
    );

    expect(find.text('1) Current session'), findsOneWidget);
    expect(find.text('2) Printer search'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('3) Manual connection'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('3) Manual connection'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('4) Status and quick commands'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('4) Status and quick commands'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('5) Print sample ticket'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('5) Print sample ticket'), findsOneWidget);
    expect(find.text('Paper width'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('6) Execution log'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('6) Execution log'), findsOneWidget);
  });

  testWidgets('triggers main page callbacks', (tester) async {
    final controller = FakeDemoController();

    await tester.pumpWidget(
      MaterialApp(home: DemoPage(controller: controller)),
    );

    await tester.ensureVisible(find.text('Search printers'));
    await tester.tap(find.text('Search printers'));
    await tester.pump();
    expect(controller.searchCalls, 1);

    await tester.scrollUntilVisible(
      find.text('Connect manually'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Connect manually'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect manually'));
    await tester.pump();
    expect(controller.connectManualCalls, 1);

    await tester.scrollUntilVisible(
      find.text('Print ticket (full DSL)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Print ticket (full DSL)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print ticket (full DSL)'));
    await tester.pump();
    expect(controller.printDslCalls, 1);

    await tester.ensureVisible(find.text('Print ticket (full EscTpl string)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print ticket (full EscTpl string)'));
    await tester.pump();
    expect(controller.printEscTplCalls, 1);

    await tester.ensureVisible(
      find.text('Print ticket (Hybrid DSL+templateBlock)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print ticket (Hybrid DSL+templateBlock)'));
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
