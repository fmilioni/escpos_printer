import '../model/exceptions.dart';

final class MustacheRenderer {
  const MustacheRenderer();

  String render(
    String template,
    Map<String, Object?> variables, {
    bool strictMissingVariables = true,
  }) {
    final parseResult = _parseSection(template, 0, null);
    final context = _RenderContext(<Object?>[
      variables,
    ], strictMissingVariables);
    return _renderNodes(parseResult.nodes, context);
  }

  String _renderNodes(List<_TemplateNode> nodes, _RenderContext context) {
    final out = StringBuffer();
    for (final node in nodes) {
      switch (node) {
        case _TextNode(:final value):
          out.write(value);
        case _VariableNode(:final path):
          final resolved = context.resolve(path);
          if (!resolved.found) {
            if (context.strictMissingVariables) {
              throw TemplateRenderException(
                'Variavel obrigatoria ausente: $path',
              );
            }
            continue;
          }
          if (resolved.value != null) {
            out.write(resolved.value);
          }
        case _EachNode(:final path, :final children):
          final resolved = context.resolve(path);
          if (!resolved.found) {
            if (context.strictMissingVariables) {
              throw TemplateRenderException(
                'Colecao obrigatoria ausente em #each: $path',
              );
            }
            continue;
          }

          final iterable = resolved.value;
          if (iterable is! Iterable<Object?>) {
            throw TemplateValidationException(
              'Bloco #each espera Iterable em "$path".',
            );
          }

          for (final item in iterable) {
            out.write(_renderNodes(children, context.push(item)));
          }
        case _IfNode(:final path, :final children):
          final resolved = context.resolve(path);
          if (!resolved.found) {
            if (context.strictMissingVariables) {
              throw TemplateRenderException(
                'Variavel obrigatoria ausente em #if: $path',
              );
            }
            continue;
          }
          if (_truthy(resolved.value)) {
            out.write(_renderNodes(children, context));
          }
      }
    }
    return out.toString();
  }

  _SectionParseResult _parseSection(
    String source,
    int start,
    String? closeTag,
  ) {
    final nodes = <_TemplateNode>[];
    var cursor = start;

    while (cursor < source.length) {
      final open = source.indexOf('{{', cursor);
      if (open < 0) {
        if (closeTag != null) {
          throw TemplateParseException('Bloco {{$closeTag}} nao foi fechado.');
        }
        if (cursor < source.length) {
          nodes.add(_TextNode(source.substring(cursor)));
        }
        return _SectionParseResult(nodes, source.length);
      }

      if (open > cursor) {
        nodes.add(_TextNode(source.substring(cursor, open)));
      }

      final close = source.indexOf('}}', open + 2);
      if (close < 0) {
        throw TemplateParseException(
          'Tag Mustache sem fechamento em indice $open.',
        );
      }

      final rawTag = source.substring(open + 2, close).trim();
      if (rawTag.isEmpty) {
        throw TemplateParseException('Tag Mustache vazia em indice $open.');
      }

      if (rawTag.startsWith('#each ')) {
        final path = rawTag.substring(6).trim();
        if (path.isEmpty) {
          throw TemplateParseException(
            'Bloco #each sem caminho em indice $open.',
          );
        }
        final nested = _parseSection(source, close + 2, 'each');
        nodes.add(_EachNode(path, nested.nodes));
        cursor = nested.nextIndex;
        continue;
      }

      if (rawTag.startsWith('#if ')) {
        final path = rawTag.substring(4).trim();
        if (path.isEmpty) {
          throw TemplateParseException(
            'Bloco #if sem caminho em indice $open.',
          );
        }
        final nested = _parseSection(source, close + 2, 'if');
        nodes.add(_IfNode(path, nested.nodes));
        cursor = nested.nextIndex;
        continue;
      }

      if (rawTag.startsWith('/')) {
        final closingTag = rawTag.substring(1).trim();
        if (closeTag == null) {
          throw TemplateParseException(
            'Fechamento {{$closingTag}} sem abertura correspondente.',
          );
        }
        if (closingTag != closeTag) {
          throw TemplateParseException(
            'Fechamento {{$closingTag}} inesperado. Esperado {{$closeTag}}.',
          );
        }
        return _SectionParseResult(nodes, close + 2);
      }

      nodes.add(_VariableNode(rawTag));
      cursor = close + 2;
    }

    if (closeTag != null) {
      throw TemplateParseException('Bloco {{$closeTag}} nao foi fechado.');
    }

    return _SectionParseResult(nodes, cursor);
  }

  bool _truthy(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value.trim().isNotEmpty;
    }
    if (value is Iterable) {
      return value.isNotEmpty;
    }
    if (value is Map) {
      return value.isNotEmpty;
    }
    return true;
  }
}

final class _RenderContext {
  const _RenderContext(this.scopes, this.strictMissingVariables);

  final List<Object?> scopes;
  final bool strictMissingVariables;

  _RenderContext push(Object? scope) {
    return _RenderContext(<Object?>[scope, ...scopes], strictMissingVariables);
  }

  _ResolveResult resolve(String path) {
    for (final scope in scopes) {
      final fromScope = _resolvePathInScope(scope, path);
      if (fromScope.found) {
        return fromScope;
      }
    }
    return const _ResolveResult.notFound();
  }

  _ResolveResult _resolvePathInScope(Object? scope, String path) {
    if (path == 'this') {
      return _ResolveResult.found(scope);
    }

    final segments = path
        .split('.')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    if (segments.isEmpty) {
      return const _ResolveResult.notFound();
    }

    Object? current;
    var index = 0;
    if (segments.first == 'this') {
      current = scope;
      index = 1;
    } else {
      current = scope;
    }

    for (var i = index; i < segments.length; i++) {
      final segment = segments[i];
      if (current is Map<Object?, Object?>) {
        if (!current.containsKey(segment)) {
          return const _ResolveResult.notFound();
        }
        current = current[segment];
        continue;
      }

      if (current is List<Object?>) {
        final itemIndex = int.tryParse(segment);
        if (itemIndex == null || itemIndex < 0 || itemIndex >= current.length) {
          return const _ResolveResult.notFound();
        }
        current = current[itemIndex];
        continue;
      }

      return const _ResolveResult.notFound();
    }

    if (segments.first != 'this' &&
        segments.length == 1 &&
        scope is Map<Object?, Object?>) {
      if (!scope.containsKey(segments.first)) {
        return const _ResolveResult.notFound();
      }
      return _ResolveResult.found(scope[segments.first]);
    }

    return _ResolveResult.found(current);
  }
}

sealed class _TemplateNode {
  const _TemplateNode();
}

final class _TextNode extends _TemplateNode {
  const _TextNode(this.value);

  final String value;
}

final class _VariableNode extends _TemplateNode {
  const _VariableNode(this.path);

  final String path;
}

final class _EachNode extends _TemplateNode {
  const _EachNode(this.path, this.children);

  final String path;
  final List<_TemplateNode> children;
}

final class _IfNode extends _TemplateNode {
  const _IfNode(this.path, this.children);

  final String path;
  final List<_TemplateNode> children;
}

final class _SectionParseResult {
  const _SectionParseResult(this.nodes, this.nextIndex);

  final List<_TemplateNode> nodes;
  final int nextIndex;
}

final class _ResolveResult {
  const _ResolveResult.found(this.value) : found = true;
  const _ResolveResult.notFound() : found = false, value = null;

  final bool found;
  final Object? value;
}
