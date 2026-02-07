import 'package:flutter/material.dart';

/// App localizations
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'zh': {
      'appTitle': '速查手册',
      'catalog': '目录',
      'read': '清单',
      'quiz': '测验',
      'settings': '设置',
      'customList': '记忆',
      'search': '搜索',
      'searchHint': '搜索文档...',
      'searchInDoc': '在文档中搜索...',
      'noResults': '无结果',
      'loading': '加载中...',
      'error': '错误',
      'retry': '重试',
      'language': '语言',
      'theme': '主题',
      'themeLight': '浅色',
      'themeDark': '深色',
      'themeSystem': '跟随系统',
      'about': '关于',
      'version': '版本',
      'cards': '卡片',
      'sections': '分区',
      'backToCatalog': '返回目录',
      'tocTitle': '目录',
      'intro': '简介',
      'favorite': '收藏',
      'unfavorite': '取消收藏',
      'learning': '学习模式',
      'learningDesc': '用于记忆/问答卡片（可用时）',
    },
    'en': {
      'appTitle': 'Reference Harmony',
      'catalog': 'Catalog',
      // Keep "Cheatsheet" from being truncated on narrow screens.
      'read': 'Cheat\u200Bsheet',
      'quiz': 'Quiz',
      'settings': 'Settings',
      'customList': 'Memory',
      'search': 'Search',
      'searchHint': 'Search documents...',
      'searchInDoc': 'Search in document...',
      'noResults': 'No results',
      'loading': 'Loading...',
      'error': 'Error',
      'retry': 'Retry',
      'language': 'Language',
      'theme': 'Theme',
      'themeLight': 'Light',
      'themeDark': 'Dark',
      'themeSystem': 'System',
      'about': 'About',
      'version': 'Version',
      'cards': 'Cards',
      'sections': 'Sections',
      'backToCatalog': 'Back to catalog',
      'tocTitle': 'Contents',
      'intro': 'Introduction',
      'favorite': 'Favorite',
      'unfavorite': 'Unfavorite',
      'learning': 'Learning mode',
      'learningDesc': 'For memory / QA cards (when available)',
    },
  };

  String get appTitle => _localizedValues[locale.languageCode]!['appTitle']!;
  String get catalog => _localizedValues[locale.languageCode]!['catalog']!;
  String get read => _localizedValues[locale.languageCode]!['read']!;
  String get quiz => _localizedValues[locale.languageCode]!['quiz']!;
  String get settings => _localizedValues[locale.languageCode]!['settings']!;
  String get customList => _localizedValues[locale.languageCode]!['customList']!;
  String get search => _localizedValues[locale.languageCode]!['search']!;
  String get searchHint => _localizedValues[locale.languageCode]!['searchHint']!;
  String get searchInDoc => _localizedValues[locale.languageCode]!['searchInDoc']!;
  String get noResults => _localizedValues[locale.languageCode]!['noResults']!;
  String get loading => _localizedValues[locale.languageCode]!['loading']!;
  String get error => _localizedValues[locale.languageCode]!['error']!;
  String get retry => _localizedValues[locale.languageCode]!['retry']!;
  String get language => _localizedValues[locale.languageCode]!['language']!;
  String get theme => _localizedValues[locale.languageCode]!['theme']!;
  String get themeLight => _localizedValues[locale.languageCode]!['themeLight']!;
  String get themeDark => _localizedValues[locale.languageCode]!['themeDark']!;
  String get themeSystem => _localizedValues[locale.languageCode]!['themeSystem']!;
  String get about => _localizedValues[locale.languageCode]!['about']!;
  String get version => _localizedValues[locale.languageCode]!['version']!;
  String get cards => _localizedValues[locale.languageCode]!['cards']!;
  String get sections => _localizedValues[locale.languageCode]!['sections']!;
  String get backToCatalog => _localizedValues[locale.languageCode]!['backToCatalog']!;
  String get tocTitle => _localizedValues[locale.languageCode]!['tocTitle']!;
  String get intro => _localizedValues[locale.languageCode]!['intro']!;
  String get favorite => _localizedValues[locale.languageCode]!['favorite']!;
  String get unfavorite => _localizedValues[locale.languageCode]!['unfavorite']!;
  String get learning => _localizedValues[locale.languageCode]!['learning']!;
  String get learningDesc => _localizedValues[locale.languageCode]!['learningDesc']!;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['zh', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
