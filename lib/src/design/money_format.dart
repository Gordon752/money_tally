import '../domain/money.dart';

class MoneyFormatter {
  const MoneyFormatter(this.settings);

  final CurrencyFormatSettings settings;

  String formatMinor(int minorUnits, {bool showPositiveSign = false}) {
    final isNegative = minorUnits < 0;
    final absMinor = minorUnits.abs();
    final scale = _scale(settings.decimalPlaces);
    final whole = absMinor ~/ scale;
    final decimal = absMinor % scale;
    final wholeText = _withThousands(whole);
    final decimalText = settings.decimalPlaces == 0
        ? ''
        : '.${decimal.toString().padLeft(settings.decimalPlaces, '0')}';
    final sign = isNegative
        ? '-'
        : showPositiveSign && minorUnits > 0
        ? '+'
        : '';
    return '$sign${settings.symbol}$wholeText$decimalText';
  }

  int parseDigitsToMinor(String digitsOnly) {
    if (digitsOnly.isEmpty) return 0;
    return int.parse(digitsOnly);
  }

  String _withThousands(int whole) {
    final raw = whole.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < raw.length; index += 1) {
      final remaining = raw.length - index;
      buffer.write(raw[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(settings.thousandsSeparator);
      }
    }
    return buffer.toString();
  }

  int _scale(int decimalPlaces) {
    var value = 1;
    for (var i = 0; i < decimalPlaces; i += 1) {
      value *= 10;
    }
    return value;
  }
}
