import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_state.dart';
import 'tabs/catalog_tab.dart';
import 'tabs/read_tab.dart';
import 'tabs/quiz_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/custom_list_tab.dart';

/// Home page with bottom navigation
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Load docs on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadDocs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appState = context.watch<AppState>();

    // Auto switch to read tab when document is selected
    if (appState.selectedDoc != null && _currentIndex == 0) {
      _currentIndex = 1;
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CatalogTab(
            onDocSelected: (doc) {
              context.read<AppState>().loadDocument(doc);
              setState(() => _currentIndex = 1);
            },
          ),
          const ReadTab(),
          const QuizTab(),
          const CustomListTab(),
          const SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.list_alt_outlined),
            selectedIcon: const Icon(Icons.list_alt),
            label: l10n.catalog,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l10n.read,
          ),
          NavigationDestination(
            icon: const Icon(Icons.help_outline),
            selectedIcon: const Icon(Icons.help),
            label: l10n.quiz,
          ),
          NavigationDestination(
            icon: const Icon(Icons.psychology_outlined),
            selectedIcon: const Icon(Icons.psychology),
            label: l10n.customList,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.settings,
          ),
        ],
      ),
    );
  }
}
