/// Gamified password policy shown live on the Create Account screen.
class PasswordRule {
  final String label;
  final bool Function(String) test;
  const PasswordRule(this.label, this.test);
}

abstract final class PasswordRules {
  static final List<PasswordRule> all = [
    PasswordRule('8+ characters', (p) => p.length >= 8),
    PasswordRule('1 UPPERCASE letter', (p) => RegExp(r'[A-Z]').hasMatch(p)),
    PasswordRule('1 lowercase letter', (p) => RegExp(r'[a-z]').hasMatch(p)),
    PasswordRule('1 number (0-9)', (p) => RegExp(r'[0-9]').hasMatch(p)),
    // any symbol: not a letter, digit or whitespace (underscore counts)
    PasswordRule('1 special symbol (!@#\$…)',
        (p) => RegExp(r'[^A-Za-z0-9\s]').hasMatch(p)),
    PasswordRule('No spaces', (p) => !RegExp(r'\s').hasMatch(p)),
  ];

  static int passed(String p) => all.where((r) => r.test(p)).length;
  static bool isStrong(String p) => all.every((r) => r.test(p));
}
