import 'package:flutter/material.dart';

import '../../domain/account.dart';
import '../../domain/money.dart';
import '../account_balance_presentation.dart';
import '../design_tokens.dart';
import '../money_format.dart';
import 'money_text.dart';

class AccountBalanceText extends StatelessWidget {
  const AccountBalanceText({
    required this.accountType,
    required this.signedBalanceMinor,
    this.currency = const CurrencyFormatSettings(),
    this.fontSize,
    this.fontWeight = FontWeight.w800,
    this.compactCreditLabel = false,
    this.neutralColor,
    super.key,
  });

  final AccountType accountType;
  final int signedBalanceMinor;
  final CurrencyFormatSettings currency;
  final double? fontSize;
  final FontWeight fontWeight;
  final bool compactCreditLabel;
  final Color? neutralColor;

  @override
  Widget build(BuildContext context) {
    final presentation = accountBalancePresentation(
      accountType,
      signedBalanceMinor,
    );
    final color = presentation.needsAttention
        ? AppColors.danger
        : presentation.isCredit
        ? AppColors.accent
        : neutralColor;
    final formatted = MoneyFormatter(
      currency,
    ).formatMinor(presentation.amountMinor);
    final creditLabel = compactCreditLabel ? 'cr' : presentation.suffix;

    return Semantics(
      label: presentation.isCredit ? '$formatted credit' : formatted,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyText(
              amountMinor: presentation.amountMinor,
              currency: currency,
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
            ),
            if (presentation.isCredit) ...[
              const SizedBox(width: 4),
              Text(
                creditLabel,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
