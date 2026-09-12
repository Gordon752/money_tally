import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as app;
import 'package:money_tally/src/design/widgets/money_text.dart';
import 'package:money_tally/src/design/money_format.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/transaction.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/ledger/ledger_projection.dart';

void main() {
  setUpAll(() async {
    var directory = File(Platform.resolvedExecutable).parent;
    File? font;
    while (directory.parent.path != directory.path && font == null) {
      for (final relative in [
        'material_fonts/Roboto-Regular.ttf',
        'artifacts/material_fonts/Roboto-Regular.ttf',
      ]) {
        final candidate = File('${directory.path}/$relative');
        if (candidate.existsSync()) {
          font = candidate;
          break;
        }
      }
      directory = directory.parent;
    }
    if (font == null) throw StateError('Flutter test font not found');
    await (FontLoader('LedgerTest')..addFont(
          Future.value(ByteData.sublistView(await font.readAsBytes())),
        ))
        .load();
  });
  for (final width in [320.0, 393.0, 1024.0]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      for (final amount in [1200, 16000000, 12345678900, -123456789012300]) {
        for (final compact in [false, true]) {
          testWidgets(
            'ledger $width scale $scale amount $amount compact $compact',
            (tester) async {
              tester.view.physicalSize = Size(width, 1600);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              const currency = CurrencyFormatSettings(
                currencyCode: 'PHP',
                symbol: 'PHP ',
              );
              final transaction = TransactionRecord(
                id: 'large',
                type: TransactionType.adjustment,
                accountId: 'test',
                date: DateTime(2026, 9, 12),
                payee: 'Balance adjustment',
                amountMinor: amount,
                sync: SyncMetadata.fresh(now: DateTime(2026)),
              );
              await tester.pumpWidget(
                MaterialApp(
                  theme: app.AppTheme.light().copyWith(
                    textTheme: app.AppTheme.light().textTheme.apply(
                      fontFamily: 'LedgerTest',
                    ),
                  ),
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 1600),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: RepaintBoundary(
                      key: const ValueKey('render'),
                      child: Scaffold(
                        body: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('September 2026'),
                                const SizedBox(height: 12),
                                if (compact)
                                  app.LedgerMonthlyCompactSummary(
                                    incomeMinor: 0,
                                    expensesMinor: 0,
                                    netMinor: amount,
                                    currency: currency,
                                  )
                                else
                                  app.LedgerMonthlySummary(
                                    incomeMinor: 0,
                                    expensesMinor: 0,
                                    netMinor: amount,
                                    currency: currency,
                                  ),
                                const SizedBox(height: 16),
                                app.LedgerJournalRow(
                                  projection: LedgerTransactionProjection(
                                    transaction: transaction,
                                    displayedAmountMinor: amount,
                                    matchingAllocations: const [],
                                  ),
                                  currency: currency,
                                  showDateContext: false,
                                  showIcon: false,
                                  onTap: () {},
                                  onLongPress: () {},
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final primary = find.byKey(
                const ValueKey('ledger-primary-amount-large'),
              );
              final expected = MoneyFormatter(currency).formatMinor(amount);
              expect(
                find.descendant(of: primary, matching: find.text(expected)),
                findsOneWidget,
              );
              for (final element in find.byType(MoneyText).evaluate()) {
                final money = element.widget as MoneyText;
                if (money.minimumFontSize == null) continue;
                final finder = find.descendant(
                  of: find.byWidget(money),
                  matching: find.byType(RichText),
                );
                final render = tester.renderObject<RenderParagraph>(finder);
                expect(render.didExceedMaxLines, isFalse);
                final text = tester.widget<Text>(
                  find.descendant(
                    of: find.byWidget(money),
                    matching: find.byType(Text),
                  ),
                );
                expect(
                  text.style!.fontSize,
                  greaterThanOrEqualTo(money.minimumFontSize!),
                );
                // Line-end whitespace can have selection bounds beyond the
                // paragraph. Check every visible character, including cents.
                final value = render.text.toPlainText();
                final boxes = [
                  for (var i = 0; i < value.length; i++)
                    if (value[i].trim().isNotEmpty)
                      ...render.getBoxesForSelection(
                        TextSelection(baseOffset: i, extentOffset: i + 1),
                      ),
                ];
                for (final box in boxes) {
                  expect(box.right, lessThanOrEqualTo(render.size.width + .5));
                  expect(box.left, greaterThanOrEqualTo(-.5));
                }
              }
              if (width == 393 &&
                  scale == 1 &&
                  compact &&
                  amount == 12345678900) {
                expect(
                  find.byKey(const ValueKey('ledger-summary-stacked')),
                  findsOneWidget,
                );
              }
              final output =
                  Platform.environment['TRACKMARK_LEDGER_RENDER_DIR'];
              if (output != null &&
                  width == 393 &&
                  scale == 1 &&
                  compact &&
                  amount > 0) {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('render')),
                );
                await tester.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 2);
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await Directory(output).create(recursive: true);
                  await File(
                    '$output/ledger-$amount.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
            },
          );
        }
      }
    }
  }
}
