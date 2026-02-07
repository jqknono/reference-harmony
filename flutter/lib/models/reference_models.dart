/// Reference card type
enum ReferenceCardKind { text, qa, code }

/// Reference language
enum ReferenceLang { zh, en }

/// Reference card data
class ReferenceCardData {
  final String id;
  final String sectionId;
  final String title;
  final ReferenceCardKind kind;
  final bool encoded;
  final String? front;
  final String? back;
  final String? body;
  final String? lang;
  final String? code;

  const ReferenceCardData({
    required this.id,
    required this.sectionId,
    required this.title,
    this.kind = ReferenceCardKind.text,
    this.encoded = false,
    this.front,
    this.back,
    this.body,
    this.lang,
    this.code,
  });

  factory ReferenceCardData.fromJson(Map<String, dynamic> json) {
    return ReferenceCardData(
      id: json['id'] as String,
      sectionId: json['sectionId'] as String,
      title: json['title'] as String,
      kind: _parseCardKind(json['kind']),
      encoded: json['encoded'] as bool? ?? false,
      front: json['front'] as String?,
      back: json['back'] as String?,
      body: json['body'] as String?,
      lang: json['lang'] as String?,
      code: json['code'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sectionId': sectionId,
    'title': title,
    'kind': kind.name,
    'encoded': encoded,
    if (front != null) 'front': front,
    if (back != null) 'back': back,
    if (body != null) 'body': body,
    if (lang != null) 'lang': lang,
    if (code != null) 'code': code,
  };

  static ReferenceCardKind _parseCardKind(dynamic value) {
    if (value == null) return ReferenceCardKind.text;
    final str = value.toString();
    switch (str) {
      case 'qa':
        return ReferenceCardKind.qa;
      case 'code':
        return ReferenceCardKind.code;
      default:
        return ReferenceCardKind.text;
    }
  }

  /// Decode title if encoded
  String get decodedTitle => encoded ? Uri.decodeComponent(title) : title;

  /// Decode body if encoded
  String? get decodedBody => 
      encoded && body != null ? Uri.decodeComponent(body!) : body;
}

/// Reference section
class ReferenceSection {
  final String id;
  final String title;
  final int startIndex;

  const ReferenceSection({
    required this.id,
    required this.title,
    required this.startIndex,
  });

  factory ReferenceSection.fromJson(Map<String, dynamic> json) {
    return ReferenceSection(
      id: json['id'] as String,
      title: json['title'] as String,
      startIndex: json['startIndex'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startIndex': startIndex,
  };
}

/// Reference document summary
class ReferenceDocSummary {
  final String id;
  final String name;
  final String title;
  final String? icon;
  final String file;
  final int sectionCount;
  final int cardCount;

  const ReferenceDocSummary({
    required this.id,
    required this.name,
    required this.title,
    this.icon,
    required this.file,
    required this.sectionCount,
    required this.cardCount,
  });

  factory ReferenceDocSummary.fromJson(Map<String, dynamic> json) {
    return ReferenceDocSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      title: json['title'] as String,
      icon: json['icon'] as String?,
      file: json['file'] as String,
      sectionCount: json['sectionCount'] as int,
      cardCount: json['cardCount'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'title': title,
    if (icon != null) 'icon': icon,
    'file': file,
    'sectionCount': sectionCount,
    'cardCount': cardCount,
  };
}

/// Reference manifest source
class ReferenceManifestSource {
  final String repo;
  final String docsPath;
  final String ref;
  final ReferenceLang? lang;
  final String? mode;

  const ReferenceManifestSource({
    required this.repo,
    required this.docsPath,
    required this.ref,
    this.lang,
    this.mode,
  });

  factory ReferenceManifestSource.fromJson(Map<String, dynamic> json) {
    return ReferenceManifestSource(
      repo: json['repo'] as String,
      docsPath: json['docsPath'] as String,
      ref: json['ref'] as String,
      lang: _parseLang(json['lang']),
      mode: json['mode'] as String?,
    );
  }

  static ReferenceLang? _parseLang(dynamic value) {
    if (value == null) return null;
    return value.toString() == 'en' ? ReferenceLang.en : ReferenceLang.zh;
  }
}

/// Reference document source
class ReferenceDocSource {
  final String repo;
  final String path;
  final String ref;
  final String url;
  final ReferenceLang? lang;
  final String? mode;

  const ReferenceDocSource({
    required this.repo,
    required this.path,
    required this.ref,
    required this.url,
    this.lang,
    this.mode,
  });

  factory ReferenceDocSource.fromJson(Map<String, dynamic> json) {
    return ReferenceDocSource(
      repo: json['repo'] as String,
      path: json['path'] as String,
      ref: json['ref'] as String,
      url: json['url'] as String,
      lang: ReferenceManifestSource._parseLang(json['lang']),
      mode: json['mode'] as String?,
    );
  }
}

/// Reference manifest
class ReferenceManifest {
  final ReferenceManifestSource source;
  final List<ReferenceDocSummary> docs;

  const ReferenceManifest({
    required this.source,
    required this.docs,
  });

  factory ReferenceManifest.fromJson(Map<String, dynamic> json) {
    return ReferenceManifest(
      source: ReferenceManifestSource.fromJson(
        json['source'] as Map<String, dynamic>,
      ),
      docs: (json['docs'] as List<dynamic>)
          .map((e) => ReferenceDocSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Reference document
class ReferenceDoc {
  final String id;
  final String name;
  final String title;
  final String? icon;
  final List<ReferenceSection> sections;
  final List<ReferenceCardData> cards;
  final ReferenceDocSource source;

  const ReferenceDoc({
    required this.id,
    required this.name,
    required this.title,
    this.icon,
    required this.sections,
    required this.cards,
    required this.source,
  });

  factory ReferenceDoc.fromJson(Map<String, dynamic> json) {
    return ReferenceDoc(
      id: json['id'] as String,
      name: json['name'] as String,
      title: json['title'] as String,
      icon: json['icon'] as String?,
      sections: (json['sections'] as List<dynamic>)
          .map((e) => ReferenceSection.fromJson(e as Map<String, dynamic>))
          .toList(),
      cards: (json['cards'] as List<dynamic>)
          .map((e) => ReferenceCardData.fromJson(e as Map<String, dynamic>))
          .toList(),
      source: ReferenceDocSource.fromJson(
        json['source'] as Map<String, dynamic>,
      ),
    );
  }
}
