import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/reference_models.dart';

/// Reference card widget
class ReferenceCardWidget extends StatelessWidget {
  final ReferenceCardData card;

  const ReferenceCardWidget({
    super.key,
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = card.decodedTitle;
    final body = card.decodedBody ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          if (title.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(128),
              ),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          
          // Body
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildBody(context, body),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, String body) {
    final theme = Theme.of(context);

    // Check if body contains code block
    if (_isCodeBlock(body)) {
      return _buildCodeBlock(context, body);
    }

    // Check if body is a table
    if (_isTable(body)) {
      return _buildTable(context, body);
    }

    // Regular text
    return SelectableText(
      body,
      style: theme.textTheme.bodyMedium,
    );
  }

  bool _isCodeBlock(String body) {
    return body.trim().startsWith('```');
  }

  bool _isTable(String body) {
    final lines = body.split('\n');
    if (lines.length < 2) return false;
    return lines[0].contains('|') && 
           lines.length > 1 && 
           RegExp(r'^[\s|:-]+$').hasMatch(lines[1].replaceAll('|', ''));
  }

  Widget _buildCodeBlock(BuildContext context, String body) {
    final theme = Theme.of(context);
    
    // Parse code blocks
    final codeBlocks = _parseCodeBlocks(body);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: codeBlocks.map((block) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? Colors.grey.shade900
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Language tag and copy button
              if (block.lang.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        block.lang,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      InkWell(
                        onTap: () => _copyToClipboard(context, block.code),
                        child: Icon(
                          Icons.copy,
                          size: 16,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Code content
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  block.code,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTable(BuildContext context, String body) {
    final theme = Theme.of(context);
    final lines = body.split('\n').where((l) => l.trim().isNotEmpty).toList();
    
    if (lines.length < 2) return Text(body);
    
    final headerCells = _parseTableRow(lines[0]);
    if (headerCells.isEmpty) return Text(body);
    
    final columnCount = headerCells.length;
    
    // Skip the separator line (lines[1]) and get data rows
    final dataRows = lines.skip(2).map((line) {
      final cells = _parseTableRow(line);
      // Normalize row to have the same number of columns as header
      if (cells.length < columnCount) {
        return [...cells, ...List.filled(columnCount - cells.length, '')];
      } else if (cells.length > columnCount) {
        return cells.take(columnCount).toList();
      }
      return cells;
    }).where((row) => row.isNotEmpty).toList();

    if (dataRows.isEmpty) {
      return Text(body);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          theme.colorScheme.surfaceContainerHighest,
        ),
        columns: headerCells.map((cell) {
          return DataColumn(
            label: Flexible(
              child: Text(
                cell,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }).toList(),
        rows: dataRows.map((row) {
          return DataRow(
            cells: row.map((cell) {
              return DataCell(
                Text(
                  cell,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  List<String> _parseTableRow(String line) {
    // Handle escaped pipes and properly parse table rows
    String trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
    
    // Skip separator lines
    if (RegExp(r'^[\s:-]+$').hasMatch(trimmed.replaceAll('|', ''))) {
      return [];
    }
    
    return trimmed
        .split('|')
        .map((cell) => cell.trim())
        .toList();
  }

  List<_CodeBlock> _parseCodeBlocks(String body) {
    final blocks = <_CodeBlock>[];
    final regex = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
    final matches = regex.allMatches(body);

    for (final match in matches) {
      blocks.add(_CodeBlock(
        lang: match.group(1) ?? '',
        code: match.group(2)?.trim() ?? '',
      ));
    }

    if (blocks.isEmpty) {
      // Fallback: treat entire body as code
      blocks.add(_CodeBlock(lang: '', code: body.trim()));
    }

    return blocks;
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}

class _CodeBlock {
  final String lang;
  final String code;

  const _CodeBlock({required this.lang, required this.code});
}
