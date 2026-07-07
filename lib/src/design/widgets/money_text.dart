import 'package:flutter/material.dart';

import '../../domain/money.dart';
import '../design_tokens.dart';
import '../money_format.dart';

class MoneyText extends StatelessWidget {
  const MoneyText({
    required this.amountMinor,
    this.currency = const CurrencyFormatSettings(),
    this.fontSize,
    this.fontWeight = FontWeight.w800,
    this.color,
    this.showPositiveSign = false,
    super.key,
  });

  final int amountMinor;
  final CurrencyFormatSettings currency;
  final double? fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final bool showPositiveSign;

  @override
  Widget build(BuildContext context) {
    final formatter = MoneyFormatter(currency);
    return Text(
      formatter.formatMinor(amountMinor, showPositiveSign: showPositiveSign),
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: AppTextStyles.money(
        context,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    );
  }
}
