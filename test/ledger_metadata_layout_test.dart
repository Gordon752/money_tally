import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart'
    show LedgerJournalRow, ReservationLedgerRow, GoalFundingLedgerRow;
import 'package:money_tally/src/domain/goal_funding.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/ledger/ledger_projection.dart';
import 'package:money_tally/src/ledger/reservation_ledger_activity.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    for (final accountScoped in [false, true]) {
      testWidgets(
        '$platform mixed Ledger rows share timestamp alignment (account: $accountScoped)',
        (tester) async {
          _setSize(tester, const Size(1024, 1366));
          await tester.pumpWidget(
            _ledgerRows(
              platform: platform,
              accountScoped: accountScoped,
              includeMovements: true,
            ),
          );
          for (final width in [
            320.0,
            390.0,
            430.0,
            599.0,
            600.0,
            1024.0,
            1440.0,
          ]) {
            tester.view.physicalSize = Size(width, 1366);
            await tester.pumpAndSettle();
            final timestampRight = tester
                .getTopRight(_slot('timestamp', 'ordinary'))
                .dx;
            for (final id in _movementRowIds) {
              expect(
                tester.getTopRight(_slot('timestamp', id)).dx,
                closeTo(timestampRight, 0.01),
                reason: '$id at width $width',
              );
              expect(
                tester.getTopLeft(_slot('split', id)).dx,
                tester.getTopLeft(_slot('split', 'ordinary')).dx,
              );
              expect(
                tester.getSize(_slot('secondary-amount', id)),
                tester.getSize(_slot('secondary-amount', 'ordinary')),
              );
              expect(
                find.byKey(ValueKey('ledger-split-indicator-$id')),
                findsNothing,
              );
              expect(
                find.byKey(ValueKey('ledger-pending-indicator-$id')),
                findsNothing,
              );
            }
            expect(find.text('reserved'), findsNWidgets(2));
            expect(find.text('returned'), findsNWidgets(2));
            for (final label in ['reserved', 'returned']) {
              for (final text in find.text(label).evaluate()) {
                final bounds = tester.getRect(find.byWidget(text.widget));
                // Scaling on narrow layouts must keep the label below its
                // amount, inside the same right-aligned trailing column.
                expect(bounds.right, closeTo(width - 16, 0.01));
                expect(
                  bounds.left,
                  greaterThanOrEqualTo(
                    width -
                        16 -
                        tester
                            .getSize(_slot('secondary-amount', 'ordinary'))
                            .width -
                        0.01,
                  ),
                );
              }
            }
            if (accountScoped) {
              expect(
                tester
                    .getTopRight(
                      find.byKey(
                        const ValueKey('ledger-running-balance-goal-legacy'),
                      ),
                    )
                    .dx,
                tester.getTopRight(_slot('secondary-amount', 'ordinary')).dx,
              );
            }
            expect(tester.takeException(), isNull);
          }
        },
      );

      testWidgets(
        '$platform mixed rows respect column preferences and larger text (account: $accountScoped)',
        (tester) async {
          _setSize(tester, const Size(390, 1366));
          for (final width in [390.0, 1024.0]) {
            tester.view.physicalSize = Size(width, 1366);
            for (final timestamps in [true, false]) {
              for (final splitIndicators in [true, false]) {
                await tester.pumpWidget(
                  _ledgerRows(
                    platform: platform,
                    accountScoped: accountScoped,
                    includeMovements: true,
                    timestampVisible: timestamps,
                    splitIndicatorVisible: splitIndicators,
                    showIcons: false,
                    textScale: 1.3,
                  ),
                );
                await tester.pumpAndSettle();
                for (final id in ['ordinary', ..._movementRowIds]) {
                  expect(
                    _slot('timestamp', id),
                    timestamps ? findsOneWidget : findsNothing,
                  );
                  expect(
                    _slot('split', id),
                    splitIndicators ? findsOneWidget : findsNothing,
                  );
                  if (timestamps) {
                    expect(
                      tester.getTopRight(_slot('timestamp', id)).dx,
                      closeTo(
                        tester.getTopRight(_slot('timestamp', 'ordinary')).dx,
                        0.01,
                      ),
                    );
                  }
                }
                expect(tester.takeException(), isNull);
              }
            }
          }
        },
      );
    }
  }

  for (final accountScoped in [false, true]) {
    final ledger = accountScoped ? 'account Ledger' : 'main Ledger';

    testWidgets('Mac $ledger matches iPad timestamp and split placement', (
      tester,
    ) async {
      _setSize(tester, const Size(1024, 1366));
      List<double>? iPadPositions;
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        await tester.pumpWidget(
          _ledgerRows(platform: platform, accountScoped: accountScoped),
        );
        await tester.pumpAndSettle();

        final time = _slot('timestamp', 'split');
        final split = _slot('split', 'split');
        final amount = _slot('secondary-amount', 'split');
        expect(tester.getSize(amount).width, accountScoped ? 220 : 230);
        expect(
          tester.getTopRight(time).dx,
          tester.getTopRight(_slot('timestamp', 'ordinary')).dx,
        );
        expect(
          tester.getTopLeft(split).dx,
          tester.getTopLeft(_slot('split', 'ordinary')).dx,
        );
        // The badge sits left of the protected amount/balance column.
        expect(
          tester.getTopRight(split).dx,
          lessThan(tester.getTopLeft(amount).dx),
        );
        expect(
          find.byKey(const ValueKey('ledger-split-indicator-split')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('ledger-split-indicator-ordinary')),
          findsNothing,
        );
        if (accountScoped) {
          expect(
            tester
                .getTopRight(
                  find.byKey(const ValueKey('ledger-running-balance-split')),
                )
                .dx,
            tester.getTopRight(amount).dx,
          );
        }
        final positions = [
          tester.getTopRight(time).dx,
          tester.getTopLeft(split).dx,
          tester.getTopRight(amount).dx,
        ];
        if (platform == TargetPlatform.iOS) {
          iPadPositions = positions;
        } else {
          expect(positions, iPadPositions);
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'Mac $ledger keeps wide inset in short windows and adapts narrow',
      (tester) async {
        _setSize(tester, const Size(1024, 500));
        await tester.pumpWidget(
          _ledgerRows(
            platform: TargetPlatform.macOS,
            accountScoped: accountScoped,
          ),
        );
        for (final width in [1024.0, 600.0, 599.0, 430.0]) {
          tester.view.physicalSize = Size(width, 500);
          await tester.pumpAndSettle();
          expect(
            tester.getSize(_slot('secondary-amount', 'split')).width,
            width >= 600
                ? (accountScoped ? 220 : 230)
                : (accountScoped ? 80 : 44),
          );
          expect(
            tester.getSize(_slot('timestamp', 'split')).width,
            greaterThan(0),
          );
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('ledger-metadata-details-split')),
                )
                .width,
            greaterThan(0),
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('Mac hidden timestamp and split still reclaim metadata space', (
    tester,
  ) async {
    _setSize(tester, const Size(1024, 768));
    final details = find.byKey(const ValueKey('ledger-metadata-details-split'));
    await tester.pumpWidget(_ledgerRows(platform: TargetPlatform.macOS));
    await tester.pumpAndSettle();
    final visibleWidth = tester.getSize(details).width;

    await tester.pumpWidget(
      _ledgerRows(platform: TargetPlatform.macOS, showOptionalColumns: false),
    );
    await tester.pumpAndSettle();
    expect(_slot('timestamp', 'split'), findsNothing);
    expect(_slot('split', 'split'), findsNothing);
    expect(tester.getSize(details).width, greaterThan(visibleWidth));
    expect(tester.takeException(), isNull);
  });
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _slot(String column, String id) =>
    find.byKey(ValueKey('ledger-$column-slot-$id'));

Widget _ledgerRows({
  required TargetPlatform platform,
  bool accountScoped = false,
  bool showOptionalColumns = true,
  bool includeMovements = false,
  bool? timestampVisible,
  bool? splitIndicatorVisible,
  bool showIcons = true,
  double textScale = 1,
}) {
  final timestamps = timestampVisible ?? showOptionalColumns;
  final splitIndicators = splitIndicatorVisible ?? showOptionalColumns;
  return MaterialApp(
    theme: ThemeData(platform: platform),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          for (final isSplit in [true, false])
            LedgerJournalRow(
              projection: LedgerTransactionProjection(
                transaction: TransactionRecord(
                  id: isSplit ? 'split' : 'ordinary',
                  type: TransactionType.expense,
                  accountId: 'checking',
                  categoryId: 'groceries',
                  date: DateTime(2026, 9, 4, isSplit ? 11 : 9, 21),
                  payee: isSplit ? 'Split purchase' : 'Ordinary purchase',
                  amountMinor: 2550,
                  status: isSplit
                      ? TransactionStatus.pending
                      : TransactionStatus.cleared,
                  splitLines: isSplit
                      ? const [
                          TransactionSplitLine(
                            id: 'groceries',
                            categoryId: 'groceries',
                            amountMinor: 2000,
                          ),
                          TransactionSplitLine(
                            id: 'tax',
                            categoryId: 'tax',
                            amountMinor: 550,
                          ),
                        ]
                      : const [],
                  sync: SyncMetadata.fresh(now: DateTime.utc(2026, 9, 4)),
                ),
                displayedAmountMinor: -2550,
                matchingAllocations: const [],
              ),
              currency: const CurrencyFormatSettings(),
              metadataDetails: accountScoped
                  ? 'Groceries • Sales Tax'
                  : 'CTBI • Groceries • Sales Tax',
              isAccountScoped: accountScoped,
              runningBalanceMinor: accountScoped ? 123450 : null,
              reservePendingIndicatorSpace: true,
              showDateContext: false,
              showIcon: showIcons,
              showTimestamp: timestamps,
              showSplitIndicator: splitIndicators,
              onTap: () {},
              onLongPress: () {},
            ),
          if (includeMovements) ...[
            for (final type in ReservationContainerType.values)
              for (final allocation in [true, false])
                ReservationLedgerRow(
                  activity: LedgerReservationActivityProjection(
                    reservationOperationId:
                        '${type.name}-${allocation ? 'allocate' : 'return'}',
                    containerType: type,
                    containerId: type.name,
                    containerName: type == ReservationContainerType.goal
                        ? 'Christmas'
                        : 'Bills',
                    fundingAccountId: 'checking',
                    kind: allocation
                        ? ReservationOperationKind.allocate
                        : ReservationOperationKind.returnFunds,
                    amountMinor: allocation ? 10000 : 3000,
                    effectiveDate: DateTime(2026, 9, 3),
                    createdAt: DateTime(
                      2026,
                      9,
                      4,
                      allocation ? 18 : 10,
                      allocation ? 20 : 44,
                    ),
                  ),
                  currency: const CurrencyFormatSettings(),
                  isAccountScoped: accountScoped,
                  showDateContext: false,
                  showIcon: showIcons,
                  showTimestamp: timestamps,
                  showSplitIndicator: splitIndicators,
                  reservePendingIndicatorSpace: true,
                  onTap: () {},
                ),
            GoalFundingLedgerRow(
              event: GoalFundingEventRecord(
                id: 'legacy',
                sourceAccountId: 'checking',
                totalAmountMinor: 5000,
                date: DateTime(2026, 9, 4, 13, 25),
                allocations: const [
                  GoalFundingAllocation(
                    id: 'allocation',
                    fundingEventId: 'legacy',
                    goalId: 'goal',
                    amountMinor: 5000,
                    order: 0,
                  ),
                ],
                sync: SyncMetadata.fresh(now: DateTime.utc(2026, 9, 4)),
              ),
              currency: const CurrencyFormatSettings(),
              isAccountScoped: accountScoped,
              runningBalanceMinor: accountScoped ? 98765 : null,
              showDateContext: false,
              showIcon: showIcons,
              showTimestamp: timestamps,
              showSplitIndicator: splitIndicators,
              reservePendingIndicatorSpace: true,
              onTap: () {},
            ),
          ],
        ],
      ),
    ),
  );
}

const _movementRowIds = [
  'reservation-fund-allocate',
  'reservation-fund-return',
  'reservation-goal-allocate',
  'reservation-goal-return',
  'goal-legacy',
];
