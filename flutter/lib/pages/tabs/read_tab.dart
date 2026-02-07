import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/reference_models.dart';
import '../../providers/app_state.dart';
import '../../widgets/reference_card_widget.dart';
import '../../widgets/toc_drawer.dart';

/// Read tab - document reading view
class ReadTab extends StatefulWidget {
  const ReadTab({super.key});

  @override
  State<ReadTab> createState() => _ReadTabState();
}

class _ReadTabState extends State<ReadTab> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appState = context.watch<AppState>();
    final doc = appState.selectedDoc;

    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.read)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.backToCatalog,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    final cards = appState.searchQuery.isEmpty
        ? doc.cards
        : appState.searchResults;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(doc.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => appState.clearSelectedDoc(),
          tooltip: l10n.backToCatalog,
        ),
        actions: [
          IconButton(
            icon: Icon(
              appState.isDocFavorite(doc.id) ? Icons.star : Icons.star_border,
              color: appState.isDocFavorite(doc.id) ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () => appState.toggleDocFavorite(doc.id),
            tooltip: appState.isDocFavorite(doc.id) ? l10n.unfavorite : l10n.favorite,
          ),
          IconButton(
            icon: const Icon(Icons.toc),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
            tooltip: l10n.tocTitle,
          ),
        ],
      ),
      endDrawer: TocDrawer(
        doc: doc,
        onSectionTap: (section) {
          _scrollToSection(doc, section);
          Navigator.pop(context);
        },
      ),
      body: Column(
        children: [
          if (appState.searchQuery.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${cards.length} ${l10n.cards}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            ),
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchInDoc,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: appState.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          appState.searchInDocument('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onChanged: (value) => appState.searchInDocument(value),
            ),
          ),

          // Cards list
          Expanded(
            child: cards.isEmpty
                ? Center(
                    child: Text(l10n.noResults),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: cards.length,
                    itemBuilder: (context, index) {
                      final card = cards[index];
                      final section = _getSectionForCard(doc, card);
                      final isFirstInSection = _isFirstCardInSection(
                        doc,
                        cards,
                        index,
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isFirstInSection && section != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 16,
                                bottom: 8,
                              ),
                              child: Text(
                                section.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ReferenceCardWidget(card: card),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  ReferenceSection? _getSectionForCard(
    ReferenceDoc doc,
    ReferenceCardData card,
  ) {
    return doc.sections.where((s) => s.id == card.sectionId).firstOrNull;
  }

  bool _isFirstCardInSection(
    ReferenceDoc doc,
    List<ReferenceCardData> cards,
    int index,
  ) {
    if (index == 0) return true;
    return cards[index].sectionId != cards[index - 1].sectionId;
  }

  void _scrollToSection(ReferenceDoc doc, ReferenceSection section) {
    final cardIndex = doc.cards.indexWhere((c) => c.sectionId == section.id);
    if (cardIndex >= 0) {
      // Approximate scroll position
      _scrollController.animateTo(
        cardIndex * 150.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
}
