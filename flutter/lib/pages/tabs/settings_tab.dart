import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/reference_models.dart';
import '../../providers/app_state.dart';
import '../../providers/theme_provider.dart';

/// Settings tab
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        children: [
          // Theme section
          _buildSectionHeader(context, l10n.theme),
          _buildThemeSelector(context, themeProvider, l10n),
          
          const Divider(),

          _buildSectionHeader(context, l10n.learning),
          SwitchListTile(
            value: appState.learningModeEnabled,
            onChanged: (v) => appState.setLearningModeEnabled(v),
            title: Text(l10n.learning),
            subtitle: Text(l10n.learningDesc),
            secondary: const Icon(Icons.school_outlined),
          ),
          
          const Divider(),
          
          // Language section
          _buildSectionHeader(context, l10n.language),
          _buildLanguageSelector(context, appState),
          
          const Divider(),
          
          // About section
          _buildSectionHeader(context, l10n.about),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.version),
            subtitle: const Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Flutter + HarmonyOS'),
            subtitle: Text(
              'Built with Flutter OHOS',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildThemeSelector(
    BuildContext context,
    ThemeProvider themeProvider,
    AppLocalizations l10n,
  ) {
    return RadioGroup<ThemePreference>(
      groupValue: themeProvider.themePreference,
      onChanged: (value) {
        if (value == null) return;
        themeProvider.setThemePreference(value);
      },
      child: Column(
        children: [
          RadioListTile<ThemePreference>(
            value: ThemePreference.light,
            title: Text(l10n.themeLight),
            secondary: const Icon(Icons.light_mode),
          ),
          RadioListTile<ThemePreference>(
            value: ThemePreference.dark,
            title: Text(l10n.themeDark),
            secondary: const Icon(Icons.dark_mode),
          ),
          RadioListTile<ThemePreference>(
            value: ThemePreference.system,
            title: Text(l10n.themeSystem),
            secondary: const Icon(Icons.brightness_auto),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector(BuildContext context, AppState appState) {
    return RadioGroup<String>(
      groupValue: appState.currentLang.name,
      onChanged: (value) {
        if (value == null) return;
        if (value == 'en') {
          appState.setLanguage(ReferenceLang.en);
        } else {
          appState.setLanguage(ReferenceLang.zh);
        }
      },
      child: const Column(
        children: [
          RadioListTile<String>(
            value: 'zh',
            title: Text('中文'),
            secondary: Icon(Icons.language),
          ),
          RadioListTile<String>(
            value: 'en',
            title: Text('English'),
            secondary: Icon(Icons.language),
          ),
        ],
      ),
    );
  }
}
