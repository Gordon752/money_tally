import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_tally/main.dart' as app;
import 'package:money_tally/src/design/widgets/amount_entry_field.dart';
import 'package:money_tally/src/domain/account.dart';
import 'package:money_tally/src/domain/finance_data_set.dart';
import 'package:money_tally/src/domain/fund.dart';
import 'package:money_tally/src/domain/goal.dart';
import 'package:money_tally/src/domain/money.dart';
import 'package:money_tally/src/domain/reservation.dart';
import 'package:money_tally/src/domain/sync_metadata.dart';
import 'package:money_tally/src/domain/user_preferences.dart';
import 'package:money_tally/src/store/finance_data_store.dart';
import 'package:money_tally/src/store/finance_data_store_scope.dart';

const _renderKey = ValueKey('polish-render');

FinanceDataStore _store() {
  final sync = SyncMetadata.fresh(now: DateTime(2026, 9, 11));
  return FinanceDataStore(
    dataSet: FinanceDataSet(
      accounts: [
        AccountRecord(
          id: 'checking',
          name: 'Checking',
          type: AccountType.checking,
          openingBalanceMinor: 100000,
          sync: sync,
        ),
      ],
      categories: const [],
      transactions: const [],
      scheduledTransactions: const [],
      budgets: const [],
      preferences: const UserPreferences(),
      funds: [
        FundRecord(
          id: 'bills',
          name: 'Bills',
          fundingAccountId: 'checking',
          status: FundStatus.active,
          sync: sync,
        ),
      ],
      goals: [
        GoalRecord(
          id: 'goal',
          name: 'Christmas',
          targetAmountMinor: 50000,
          status: GoalStatus.active,
          fundingMethod: GoalFundingMethod.accountFunded,
          defaultFundingAccountId: 'checking',
          reservationModelVersion: 1,
          sync: sync,
        ),
        GoalRecord(
          id: 'progress',
          name: 'Progress',
          targetAmountMinor: 50000,
          status: GoalStatus.active,
          fundingMethod: GoalFundingMethod.trackingOnly,
          sync: sync,
        ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
    for (final font in {
      'PolishText': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      var directory = File(Platform.resolvedExecutable).parent;
      File? file;
      while (directory.parent.path != directory.path && file == null) {
        for (final relative in [
          'material_fonts/${font.value}',
          'artifacts/material_fonts/${font.value}',
        ]) {
          final candidate = File('${directory.path}/$relative');
          if (candidate.existsSync()) {
            file = candidate;
            break;
          }
        }
        directory = directory.parent;
      }
      final bytes = await file!.readAsBytes();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  final forms = <String, Future<void> Function(BuildContext, FinanceDataStore)>{
    'return_fund': (c, s) =>
        app.showFundAmountDialog(c, fundId: 'bills', isReturn: true),
    'return_goal': (c, s) => app.showReservationAmountDialog(
      c,
      containerType: ReservationContainerType.goal,
      containerId: 'goal',
      containerName: 'Christmas',
      isReturn: true,
    ),
    'allocate_one': (c, s) =>
        app.showFundAmountDialog(c, fundId: 'bills', isReturn: false),
    'allocate_funds': (c, s) => app.showAllocateFundsSheet(c),
    'fund_goals': (c, s) => app.showFundGoalsSheet(c),
    'fund_target': (c, s) =>
        app.showFundEditor(c, initialFund: s.fundById('bills')),
    'goal_target': (c, s) =>
        app.showGoalEditor(c, initialGoal: s.goalById('goal')),
    'scheduled_fund': (c, s) async {
      await app.showScheduledFundFundingDialog(c);
    },
    'scheduled_goal': (c, s) async {
      await app.showScheduledGoalFundingDialog(c);
    },
    'progress': (c, s) => app.showAddGoalContributionSheet(c, 'progress'),
    'adjust_balance': (c, s) =>
        app.showAdjustBalanceDialog(c, s.accountById('checking')),
  };
  final layouts = [
    (
      name: 'phone',
      size: const Size(393, 852),
      scale: 1.0,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'phone_keyboard',
      size: const Size(393, 852),
      scale: 1.0,
      keyboard: 320.0,
      dark: false,
    ),
    (
      name: 'phone_large',
      size: const Size(320, 568),
      scale: 1.6,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'ipad',
      size: const Size(768, 1024),
      scale: 1.0,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'ipad_landscape',
      size: const Size(1194, 834),
      scale: 1.0,
      keyboard: 350.0,
      dark: false,
    ),
    (
      name: 'mac',
      size: const Size(1440, 900),
      scale: 1.0,
      keyboard: 0.0,
      dark: false,
    ),
    (
      name: 'mac_dark',
      size: const Size(1024, 768),
      scale: 1.0,
      keyboard: 0.0,
      dark: true,
    ),
  ];
  for (final form in forms.entries) {
    for (final layout in layouts) {
      testWidgets(
        '${form.key} polished layout ${layout.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = layout.size;
          tester.view.viewInsets = FakeViewPadding(bottom: layout.keyboard);
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            tester.view.resetViewInsets();
          });
          final store = _store();
          final base = layout.dark ? app.AppTheme.dark() : app.AppTheme.light();
          await tester.pumpWidget(
            FinanceDataStoreScope(
              store: store,
              child: RepaintBoundary(
                key: _renderKey,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: base.copyWith(
                    textTheme: base.textTheme.apply(fontFamily: 'PolishText'),
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => TextButton(
                        onPressed: () => form.value(context, store),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(find.byType(app.TransactionSheetFrame), findsOneWidget);
          expect(find.byType(app.TransactionFormActions), findsOneWidget);
          final amounts = tester.widgetList<AmountEntryField>(
            find.byType(AmountEntryField),
          );
          expect(amounts, isNotEmpty);
          for (final amount in amounts) {
            expect(amount.visualStyle, isNot(AmountEntryVisualStyle.standard));
            final field = tester.widget<TextField>(
              find.byKey(amount.fieldKey!),
            );
            if (amount.visualStyle == AmountEntryVisualStyle.inline) {
              expect(field.decoration!.border, InputBorder.none);
              expect(field.decoration!.labelText, isNull);
              expect(field.textAlign, TextAlign.left);
            } else {
              expect(field.textAlign, TextAlign.right);
              expect(field.style!.fontSize, 18);
              expect(field.style!.fontWeight, FontWeight.w600);
            }
          }
          expect(tester.takeException(), isNull);
          final output = Platform.environment['TRACKMARK_POLISH_RENDER_DIR'];
          if (output != null) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(_renderKey),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(output).create(recursive: true);
              await File(
                '$output/${form.key}_${layout.name}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
          expect(
            tester.getRect(cancel).bottom,
            lessThanOrEqualTo(layout.size.height - layout.keyboard),
          );
          await tester.ensureVisible(cancel);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(store.transactions, isEmpty);
          expect(store.reservationOperations, isEmpty);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          store.dispose();
        },
        variant: TargetPlatformVariant({
          layout.name.startsWith('mac')
              ? TargetPlatform.macOS
              : TargetPlatform.iOS,
        }),
      );
    }
  }
  testWidgets('zero allocation remaining is neutral, not an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: app.AppTheme.light(),
        home: const Scaffold(
          body: app.GoalAllocationSummary(
            totalAmountMinor: 0,
            allocatedAmountMinor: 0,
            currency: CurrencyFormatSettings(),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Remaining\n\$0.00'));
    expect(
      text.style!.color,
      Theme.of(
        tester.element(find.byType(app.GoalAllocationSummary)),
      ).colorScheme.onSurfaceVariant,
    );
  });
}
