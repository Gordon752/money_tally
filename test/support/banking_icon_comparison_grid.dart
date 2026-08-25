import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:money_tally/src/design/design_tokens.dart';

@immutable
class BankingIconCandidate {
  const BankingIconCandidate({
    required this.label,
    required this.purpose,
    required this.hugeIcon,
    required this.hugeName,
  });

  final String label;
  final String purpose;
  final List<List<dynamic>> hugeIcon;
  final String hugeName;
}

/// Curated Hugeicons candidates for Trackmark's account-appearance picker.
///
/// This remains developer-only until the candidates are visually approved.
/// Account appearance IDs, production mappings, and persisted records are not
/// affected by this list.
const bankingIconCandidates = <BankingIconCandidate>[
  BankingIconCandidate(
    label: 'Bank',
    purpose: 'Financial institution',
    hugeIcon: HugeIcons.strokeRoundedBank,
    hugeName: 'bank',
  ),
  BankingIconCandidate(
    label: 'Bank Office',
    purpose: 'Branch / commercial building',
    hugeIcon: HugeIcons.strokeRoundedBuilding01,
    hugeName: 'building01',
  ),
  BankingIconCandidate(
    label: 'Checking',
    purpose: 'Closed wallet',
    hugeIcon: HugeIcons.strokeRoundedWallet01,
    hugeName: 'wallet01',
  ),
  BankingIconCandidate(
    label: 'Cash Wallet',
    purpose: 'Open billfold',
    hugeIcon: HugeIcons.strokeRoundedWallet04,
    hugeName: 'wallet04',
  ),
  BankingIconCandidate(
    label: 'Savings Vault',
    purpose: 'Protected savings',
    hugeIcon: HugeIcons.strokeRoundedSafeBox,
    hugeName: 'safeBox',
  ),
  BankingIconCandidate(
    label: 'Savings Piggy',
    purpose: 'Traditional savings',
    hugeIcon: HugeIcons.strokeRoundedPiggyBank,
    hugeName: 'piggyBank',
  ),
  BankingIconCandidate(
    label: 'Savings Deposit',
    purpose: 'Hand and coin',
    hugeIcon: HugeIcons.strokeRoundedSavings,
    hugeName: 'savings',
  ),
  BankingIconCandidate(
    label: 'Cash',
    purpose: 'Banknote',
    hugeIcon: HugeIcons.strokeRoundedMoney02,
    hugeName: 'money02',
  ),
  BankingIconCandidate(
    label: 'Credit Card',
    purpose: 'Card account',
    hugeIcon: HugeIcons.strokeRoundedCreditCard,
    hugeName: 'creditCard',
  ),
  BankingIconCandidate(
    label: 'Portfolio',
    purpose: 'Investment growth',
    hugeIcon: HugeIcons.strokeRoundedChartUp,
    hugeName: 'chartUp',
  ),
];

class BankingIconComparisonGrid extends StatelessWidget {
  const BankingIconComparisonGrid({super.key});

  static const rowHeight = 88.0;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('banking-icon-comparison-grid'),
      child: ColoredBox(
        color: AppColors.pageLight,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.panelLight,
              border: Border.all(color: AppColors.lineLight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hugeicons · Banking appearance candidates',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Exact Trackmark account badge geometry: '
                        '18 / 23 / 27 px glyphs in 36 / 46 / 54 px containers.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.lineLight),
                const _BankingHeaderRow(),
                for (final candidate in bankingIconCandidates) ...[
                  const Divider(height: 1, color: AppColors.lineLight),
                  SizedBox(
                    height: rowHeight,
                    child: _BankingCandidateRow(candidate: candidate),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BankingHeaderRow extends StatelessWidget {
  const _BankingHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
    );
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          const SizedBox(width: 24),
          SizedBox(width: 220, child: Text('Appearance', style: style)),
          SizedBox(width: 265, child: Text('Intended use', style: style)),
          SizedBox(
            width: 330,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Trackmark account badges', style: style),
                const SizedBox(height: 2),
                Text(
                  '18 px          23 px          27 px',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.muted,
                    fontFeatures: const [AppTextStyles.tabularFigures],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 150, child: Text('Hugeicons ID', style: style)),
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}

class _BankingCandidateRow extends StatelessWidget {
  const _BankingCandidateRow({required this.candidate});

  final BankingIconCandidate candidate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 24),
        SizedBox(
          width: 220,
          child: Text(
            candidate.label,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 265,
          child: Text(
            candidate.purpose,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ),
        SizedBox(
          width: 330,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (
                var index = 0;
                index < _AccountPreviewSize.values.length;
                index++
              ) ...[
                _AccountPreviewBadge(
                  previewSize: _AccountPreviewSize.values[index],
                  hugeIcon: candidate.hugeIcon,
                ),
                if (index != _AccountPreviewSize.values.length - 1)
                  const SizedBox(width: 34),
              ],
            ],
          ),
        ),
        SizedBox(
          width: 150,
          child: Text(
            candidate.hugeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.muted,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(width: 24),
      ],
    );
  }
}

enum _AccountPreviewSize {
  compact(glyph: 18, container: 36),
  standard(glyph: 23, container: 46),
  large(glyph: 27, container: 54);

  const _AccountPreviewSize({required this.glyph, required this.container});

  final double glyph;
  final double container;
}

class _AccountPreviewBadge extends StatelessWidget {
  const _AccountPreviewBadge({
    required this.previewSize,
    required this.hugeIcon,
  });

  final _AccountPreviewSize previewSize;
  final List<List<dynamic>> hugeIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: previewSize.container,
      height: previewSize.container,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(previewSize.container * 0.26),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.23)),
      ),
      child: HugeIcon(
        icon: hugeIcon,
        size: previewSize.glyph,
        color: AppColors.accent,
        strokeWidth: 1.8,
      ),
    );
  }
}
