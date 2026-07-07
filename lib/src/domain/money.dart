class MoneyAmount implements Comparable<MoneyAmount> {
  const MoneyAmount(this.minorUnits);

  factory MoneyAmount.zero() => const MoneyAmount(0);

  final int minorUnits;

  bool get isNegative => minorUnits < 0;
  bool get isPositive => minorUnits > 0;
  MoneyAmount get abs => MoneyAmount(minorUnits.abs());

  MoneyAmount operator +(MoneyAmount other) {
    return MoneyAmount(minorUnits + other.minorUnits);
  }

  MoneyAmount operator -(MoneyAmount other) {
    return MoneyAmount(minorUnits - other.minorUnits);
  }

  @override
  int compareTo(MoneyAmount other) => minorUnits.compareTo(other.minorUnits);
}

class CurrencyFormatSettings {
  const CurrencyFormatSettings({
    this.currencyCode = 'USD',
    this.symbol = r'$',
    this.decimalPlaces = 2,
    this.thousandsSeparator = ',',
  });

  final String currencyCode;
  final String symbol;
  final int decimalPlaces;
  final String thousandsSeparator;

  Map<String, Object?> toJson() {
    return {
      'currencyCode': currencyCode,
      'symbol': symbol,
      'decimalPlaces': decimalPlaces,
      'thousandsSeparator': thousandsSeparator,
    };
  }

  factory CurrencyFormatSettings.fromJson(Map<String, Object?> json) {
    return CurrencyFormatSettings(
      currencyCode: json['currencyCode'] as String? ?? 'USD',
      symbol: json['symbol'] as String? ?? r'$',
      decimalPlaces: json['decimalPlaces'] as int? ?? 2,
      thousandsSeparator: json['thousandsSeparator'] as String? ?? ',',
    );
  }
}
