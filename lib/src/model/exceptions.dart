class EscPosException implements Exception {
  EscPosException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return 'EscPosException: $message';
    }
    return 'EscPosException: $message (cause: $cause)';
  }
}

class ConnectionException extends EscPosException {
  ConnectionException(super.message, [super.cause]);
}

class TransportException extends EscPosException {
  TransportException(super.message, [super.cause]);
}

class TemplateRenderException extends EscPosException {
  TemplateRenderException(super.message, [super.cause]);
}

class TemplateParseException extends EscPosException {
  TemplateParseException(super.message, [super.cause]);
}

class TemplateValidationException extends EscPosException {
  TemplateValidationException(super.message, [super.cause]);
}
