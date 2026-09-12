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
    this.minimumFontSize,
    this.textAlign,
    super.key,
  });

  final int amountMinor;
  final CurrencyFormatSettings currency;
  final double? fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final bool showPositiveSign;

  /// Opt-in fitting. Below this limit, wrap rather than hide financial digits.
  final double? minimumFontSize;
  final TextAlign? textAlign;

  static double measuredWidth(
    BuildContext context,
    String value,
    double size, {
    FontWeight weight = FontWeight.w800,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: AppTextStyles.money(context, fontSize: size, fontWeight: weight),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final formatter = MoneyFormatter(currency);
    if (minimumFontSize != null) {
      final value = formatter.formatMinor(
        amountMinor,
        showPositiveSign: showPositiveSign,
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final preferred = fontSize ?? AppTextStyles.money(context).fontSize!;
          var size = preferred;
          final floor = minimumFontSize!.clamp(0.1, preferred).toDouble();
          while (size > floor &&
              measuredWidth(context, value, size, weight: fontWeight) >
                  constraints.maxWidth - 1) {
            size = (size - 0.25).clamp(floor, preferred).toDouble();
          }
          return SizedBox(
            width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
            child: Text(
              value,
              textAlign: textAlign,
              softWrap: true,
              style: AppTextStyles.money(
                context,
                fontSize: size,
                fontWeight: fontWeight,
                color: color,
              ),
            ),
          );
        },
      );
    }
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
