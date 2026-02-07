import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reference_models.dart';

/// App state provider
class AppState extends ChangeNotifier {
  static const String _favoritesPrefKey = 'favoriteDocIds';
  static const String _recentPrefKey = 'recentDocIds';
  static const String _learningModePrefKey = 'learningModeEnabled';
  static const String _langPrefKey = 'lang';
  static const int _recentMaxCount = 3;

  bool _isLoading = false;
  String? _errorMessage;
  ReferenceLang _currentLang = ReferenceLang.zh;
  
  List<ReferenceDocSummary> _docs = [];
  ReferenceDoc? _selectedDoc;
  String _searchQuery = '';
  List<ReferenceCardData> _searchResults = [];
  List<String> _favoriteDocIds = [];
  List<String> _recentDocIds = [];
  bool _learningModeEnabled = false;

  AppState() {
    _loadPreferences();
  }

  // Getters
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ReferenceLang get currentLang => _currentLang;
  List<ReferenceDocSummary> get docs => _docs;
  ReferenceDoc? get selectedDoc => _selectedDoc;
  String get searchQuery => _searchQuery;
  List<ReferenceCardData> get searchResults => _searchResults;
  List<String> get favoriteDocIds => List.unmodifiable(_favoriteDocIds);
  List<String> get recentDocIds => List.unmodifiable(_recentDocIds);
  bool get learningModeEnabled => _learningModeEnabled;

  /// Load document list from assets
  Future<void> loadDocs() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final langPath = _currentLang == ReferenceLang.zh ? 'zh' : 'en';
      final manifestPath = 'assets/reference/$langPath/manifest.json';
      
      final manifestJson = await rootBundle.loadString(manifestPath);
      final manifest = ReferenceManifest.fromJson(
        json.decode(manifestJson) as Map<String, dynamic>,
      );
      
      _docs = manifest.docs;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load documents: $e';
      _docs = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load a specific document
  Future<void> loadDocument(ReferenceDocSummary summary) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final docJson = await rootBundle.loadString('assets/${summary.file}');
      _selectedDoc = ReferenceDoc.fromJson(
        json.decode(docJson) as Map<String, dynamic>,
      );
      _errorMessage = null;

      _pushRecent(summary.id);
    } catch (e) {
      _errorMessage = 'Failed to load document: $e';
      _selectedDoc = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set current language
  Future<void> setLanguage(ReferenceLang lang) async {
    if (_currentLang == lang) return;
    
    _currentLang = lang;
    _selectedDoc = null;
    _searchQuery = '';
    _searchResults = [];
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langPrefKey, lang.name);

    await loadDocs();
  }

  /// Clear selected document
  void clearSelectedDoc() {
    _selectedDoc = null;
    _searchQuery = '';
    _searchResults = [];
    notifyListeners();
  }

  bool isDocFavorite(String docId) => _favoriteDocIds.contains(docId);

  Future<void> toggleDocFavorite(String docId) async {
    if (docId.trim().isEmpty) return;

    final next = List<String>.from(_favoriteDocIds);
    if (next.contains(docId)) {
      next.removeWhere((e) => e == docId);
    } else {
      next.insert(0, docId);
    }
    _favoriteDocIds = next;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesPrefKey, _favoriteDocIds);
  }

  Future<void> setLearningModeEnabled(bool enabled) async {
    if (_learningModeEnabled == enabled) return;
    _learningModeEnabled = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_learningModePrefKey, enabled);
  }

  /// Search within current document
  void searchInDocument(String query) {
    _searchQuery = query;
    
    if (query.isEmpty || _selectedDoc == null) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    final tokens = _normalizeSearchTokens(query);
    _searchResults = _selectedDoc!.cards.where((card) {
      return _cardMatchesTokens(card, tokens);
    }).toList();
    
    notifyListeners();
  }

  /// Normalize search tokens
  List<String> _normalizeSearchTokens(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Check if card matches search tokens
  bool _cardMatchesTokens(ReferenceCardData card, List<String> tokens) {
    final title = card.decodedTitle.toLowerCase();
    final body = (card.decodedBody ?? '').toLowerCase();
    final combined = '$title $body';
    
    return tokens.every((token) => combined.contains(token));
  }

  List<ReferenceDocSummary> getCatalogDocsForDisplay(String query) {
    if (query.trim().isNotEmpty) {
      final filtered = filterDocs(query);
      filtered.sort(_compareCatalogDocs);
      return filtered;
    }

    final favorites = <ReferenceDocSummary>[];
    final recent = <ReferenceDocSummary>[];
    final others = <ReferenceDocSummary>[];

    for (final doc in _docs) {
      if (_favoriteDocIds.contains(doc.id)) {
        favorites.add(doc);
      } else if (_recentDocIds.contains(doc.id)) {
        recent.add(doc);
      } else {
        others.add(doc);
      }
    }

    favorites.sort((a, b) => _favoriteDocIds.indexOf(a.id) - _favoriteDocIds.indexOf(b.id));
    recent.sort((a, b) => _recentDocIds.indexOf(a.id) - _recentDocIds.indexOf(b.id));
    others.sort(_compareCatalogDocs);

    return [...favorites, ...recent, ...others];
  }

  /// Filter docs by search query
  List<ReferenceDocSummary> filterDocs(String query) {
    if (query.isEmpty) return _docs;
    
    final lowerQuery = query.toLowerCase();
    return _docs.where((doc) {
      return doc.name.toLowerCase().contains(lowerQuery) ||
             doc.title.toLowerCase().contains(lowerQuery) ||
             doc.id.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  int _compareCatalogDocs(ReferenceDocSummary a, ReferenceDocSummary b) {
    String sortKey(ReferenceDocSummary d) {
      return (d.name.isNotEmpty ? d.name : (d.title.isNotEmpty ? d.title : d.id))
          .trim()
          .toLowerCase();
    }

    final ak = sortKey(a);
    final bk = sortKey(b);
    if (ak.compareTo(bk) != 0) return ak.compareTo(bk);
    if (a.id.compareTo(b.id) != 0) return a.id.compareTo(b.id);
    return a.file.compareTo(b.file);
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString(_langPrefKey);
    if (lang == 'en') {
      _currentLang = ReferenceLang.en;
    } else if (lang == 'zh') {
      _currentLang = ReferenceLang.zh;
    }
    _favoriteDocIds = prefs.getStringList(_favoritesPrefKey) ?? [];
    _recentDocIds = prefs.getStringList(_recentPrefKey) ?? [];
    _learningModeEnabled = prefs.getBool(_learningModePrefKey) ?? false;
    notifyListeners();
  }

  void _pushRecent(String docId) {
    final id = docId.trim();
    if (id.isEmpty) return;
    final next = <String>[id, ..._recentDocIds.where((e) => e != id)];
    if (next.length > _recentMaxCount) {
      next.removeRange(_recentMaxCount, next.length);
    }
    _recentDocIds = next;

    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(_recentPrefKey, _recentDocIds);
    });
  }
}
