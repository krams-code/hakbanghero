/// Basic client-side chat moderation (English + common Filipino words).
///
///  * profanity       -> masked with asterisks, message still sends
///  * links / phone numbers / e-mails -> message is BLOCKED (privacy + spam)
///  * rate limit      -> one message per [minGap]
///
/// This is a first line of defence, not a guarantee: pair it with the
/// REPORT button (chat_screen) and review `reports` in the Firebase console.
class ChatFilter {
  ChatFilter._();

  static const Duration minGap = Duration(milliseconds: 1200);

  // Keep this list short and obvious; extend it as reports come in.
  static const List<String> _bad = [
    'fuck', 'shit', 'bitch', 'asshole', 'bastard', 'dick', 'pussy', 'slut',
    'whore', 'nigga', 'nigger', 'faggot', 'retard', 'cunt',
    'putangina', 'putang ina', 'tangina', 'tang ina', 'puta', 'gago', 'gaga',
    'tarantado', 'bobo', 'tanga', 'ulol', 'pakyu', 'pakshet', 'leche', 'lintik',
    'buwisit', 'siraulo', 'hayop ka', 'bwisit', 'kantot', 'iyot', 'pokpok',
  ];

  // leetspeak -> letters, so "f*ck", "sh1t", "g@go" are still caught
  static const Map<String, String> _leet = {
    '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't',
    '@': 'a', r'$': 's', '!': 'i',
  };

  static final RegExp _url = RegExp(
      r'(https?:\/\/|www\.|\b[a-z0-9-]+\.(com|net|org|ph|io|gg|ly|me|co|app|xyz)\b)',
      caseSensitive: false);
  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
  static final RegExp _phone = RegExp(r'(\+?\d[\d\s\-().]{8,}\d)');

  /// Reason the message must not be sent, or null when it is fine.
  static String? blockReason(String text) {
    if (_url.hasMatch(text)) return 'Links are not allowed in chat.';
    if (_email.hasMatch(text)) return 'Please do not share email addresses.';
    if (_phone.hasMatch(text)) return 'Please do not share phone numbers.';
    return null;
  }

  static String _normalize(String s) {
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      b.write(_leet[ch] ?? ch);
    }
    return b.toString();
  }

  // Words that are also caught when something is stuck on the end
  // ("fucking", "putanginamo"). Everything else must match as a whole word,
  // so innocent words ("reputation", "gagaling") are left alone.
  static const Set<String> _stems = {
    'fuck', 'shit', 'bitch', 'putang', 'tangina', 'pakyu', 'kantot', 'nigg',
  };

  static final List<RegExp> _patterns = [
    for (final w in _bad)
      RegExp('(?<![a-z])${RegExp.escape(w)}' +
          (_stems.any(w.startsWith) ? '[a-z]*' : '(?![a-z])')),
  ];

  /// Masks bad words, keeping the rest of the sentence readable.
  static String clean(String text) {
    var out = text;
    final norm = _normalize(text); // same length as text (1:1 mapping)
    for (final re in _patterns) {
      for (final m in re.allMatches(norm)) {
        out = out.replaceRange(m.start, m.end, '*' * (m.end - m.start));
      }
    }
    return out;
  }

  static bool hasProfanity(String text) => clean(text) != text;
}
