class WikipediaResult {
  const WikipediaResult({
    required this.title,
    required this.extract,
    required this.language,
    required this.pageUrl,
    this.thumbnailUrl,
  });

  final String title;
  final String extract;
  final String language;
  final String pageUrl;
  final String? thumbnailUrl;
}
