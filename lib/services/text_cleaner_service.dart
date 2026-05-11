class TextCleanerService {
  static String normalizePdfText(String input) {
    var text = input.trim();

    // Unisce parole spezzate a fine riga:
    // exam-
    // ple  -> example
    text = text.replaceAllMapped(
      RegExp(r'([A-Za-zÀ-ÿ])-\s*\n\s*([A-Za-zÀ-ÿ])'),
      (match) => '${match.group(1)}${match.group(2)}',
    );

    // Trasforma gli a capo singoli in spazi.
    text = text.replaceAll(RegExp(r'\s*\n\s*'), ' ');

    // Riduce spazi multipli a uno solo.
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');

    // Sistema spazi prima della punteggiatura.
    text = text.replaceAll(RegExp(r'\s+([,.!?;:])'), r'$1');

    // Sistema spazi dopo parentesi/apostrofi semplici.
    text = text.replaceAll(RegExp(r'([\(\[\{])\s+'), r'$1');
    text = text.replaceAll(RegExp(r'\s+([\)\]\}])'), r'$1');

    return text.trim();
  }
}
