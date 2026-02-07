import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/reference_models.dart';

/// Table of contents drawer
class TocDrawer extends StatelessWidget {
  final ReferenceDoc doc;
  final void Function(ReferenceSection section)? onSectionTap;

  const TocDrawer({
    super.key,
    required this.doc,
    this.onSectionTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.tocTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    doc.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Sections list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: doc.sections.length,
                itemBuilder: (context, index) {
                  final section = doc.sections[index];
                  final cardCount = _getCardCountForSection(doc, section);
                  
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                      section.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '$cardCount ${l10n.cards}',
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () => onSectionTap?.call(section),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _getCardCountForSection(ReferenceDoc doc, ReferenceSection section) {
    return doc.cards.where((c) => c.sectionId == section.id).length;
  }
}
