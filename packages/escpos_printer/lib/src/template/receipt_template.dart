import 'operations.dart';
import 'receipt_builder.dart';

sealed class ReceiptTemplate {
  const ReceiptTemplate();

  factory ReceiptTemplate.dsl(void Function(ReceiptBuilder builder) build) =
      DslReceiptTemplate;
  factory ReceiptTemplate.string(String template) = StringReceiptTemplate;
}

final class DslReceiptTemplate extends ReceiptTemplate {
  DslReceiptTemplate(void Function(ReceiptBuilder builder) build)
    : ops = _buildOps(build),
      super();

  final List<PrintOp> ops;

  static List<PrintOp> _buildOps(void Function(ReceiptBuilder builder) build) {
    final builder = ReceiptBuilder();
    build(builder);
    return builder.build();
  }
}

final class StringReceiptTemplate extends ReceiptTemplate {
  const StringReceiptTemplate(this.template) : super();

  final String template;
}
