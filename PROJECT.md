# Money Tally Project Architecture

## App Philosophy

Money Tally is a personal finance app for people who want control without clutter. It should feel calm, fast, and practical on iPhone, iPad, and Mac. The app should support everyday manual finance tracking: accounts, ledgers, categories, budgets, scheduled transactions, reminders, and clear reports.

The app intentionally excludes bank sync, attachments, investment tracking, credit scores, debt payoff coaching, and AI financial advice. Those features add cost, privacy concerns, and interface weight that do not match the product goal.

Core product values:

- Manual-first data ownership.
- Clear balances and transaction history.
- Cross-device sync through the user's signed-in account.
- Fast entry of expenses, income, transfers, and balance adjustments.
- A restrained Apple-style interface that works well on compact phone screens and larger iPad/Mac layouts.
- Exportable, restorable data formats so the user is never locked in.

## Current Project State

Money Tally is a Flutter app targeting iPhone, iPad, macOS, and future Android. Firebase Authentication and Firestore are configured for Apple sign-in and cross-device sync. The current UI still runs on the original v1 snapshot store, while the v2 record-based foundation is being built underneath it.

Local v1 persistence uses a snapshot stored through `shared_preferences`, with Firestore currently storing each user's full finance snapshot. V2 persistence uses `FinanceDataSet` records, a local `shared_preferences` repository, and a migration bridge that can convert existing v1 snapshots into the v2 data model.

Current important files:

- `lib/main.dart`: app bootstrap, Firebase startup, auth gate, and root widget wiring.
- `lib/src/app_theme.dart`: current theme colors and Material theme.
- `lib/src/auth_service.dart`: Apple sign-in and Firebase Auth integration.
- `lib/src/domain.dart`: current account, category, transaction, scheduled transaction, budget, sync metadata, and JSON models.
- `lib/src/finance_store.dart`: in-memory app state, seed data, mutations, local persistence, and remote snapshot push/pull.
- `lib/src/finance_home.dart`: current screens, navigation, cards, rows, dialogs, and forms.
- `lib/src/local_finance_repository.dart`: local snapshot load/save.
- `lib/src/firestore_finance_repository.dart`: Firestore snapshot load/save.
- `lib/src/domain/`: v2 account, category, transaction, scheduled transaction, budget, preferences, and sync models.
- `lib/src/design/`: reusable design tokens, money formatting, and shared Money Tally widgets.
- `lib/src/persistence/`: v2 local repository, backup codec, and per-record repository contract.
- `lib/src/store/finance_data_store.dart`: v2 ledger-derived store and mutation API.
- `lib/src/migration/`: v1 snapshot to v2 data migration and bootstrap loader.
- `lib/firebase_options.dart`: generated Firebase configuration.
- `docs/firebase_setup.md`: Firebase setup notes.
- `docs/implementation_notes.md`: earlier implementation notes.

## Target Folder Structure

The current app is still compact, but the next phase should split responsibilities before adding more screens.

Recommended structure:

```text
lib/
  main.dart
  firebase_options.dart
  src/
    app/
      money_tally_app.dart
      app_bootstrap.dart
      app_routes.dart
    auth/
      auth_gate.dart
      auth_service.dart
    design/
      app_theme.dart
      design_tokens.dart
      money_format.dart
      widgets/
        amount_entry_field.dart
        budget_progress_bar.dart
        floating_action_button.dart
        floating_action_menu.dart
        money_text.dart
        section_header.dart
        summary_card.dart
    domain/
      account.dart
      budget.dart
      category.dart
      finance_data_set.dart
      money.dart
      scheduled_transaction.dart
      sync_metadata.dart
      transaction.dart
      user_preferences.dart
    features/
      accounts/
        account_card.dart
        account_form.dart
        accounts_screen.dart
      budgets/
        budget_card.dart
        budget_form.dart
        budgets_screen.dart
      categories/
        category_form.dart
        categories_screen.dart
      dashboard/
        dashboard_screen.dart
      ledger/
        ledger_filters.dart
        ledger_screen.dart
        transaction_form.dart
        transaction_row.dart
      reports/
        reports_screen.dart
      scheduled/
        scheduled_calendar.dart
        scheduled_screen.dart
        scheduled_transaction_row.dart
      settings/
        settings_screen.dart
    notifications/
      notification_scheduler.dart
      notification_preferences.dart
    persistence/
      finance_repository.dart
      firestore_finance_repository.dart
      local_finance_repository.dart
      backup_codec.dart
    store/
      finance_store.dart
      finance_selectors.dart
    migration/
      v1_snapshot_migrator.dart
      finance_data_bootstrapper.dart
```

Guiding rule: domain models and persistence should not depend on UI widgets. Feature screens may depend on domain, store, and reusable design widgets.

## Design System

Create the design system before individual screen rewrites.

Design requirements:

- Use the system SF Pro font through platform defaults where possible.
- Use a consistent spacing scale: `4`, `8`, `12`, `16`, `24`, `32`.
- Use tabular numbers for all money values.
- Keep card radius modest and consistent, with restrained borders/shadows.
- Keep button heights, padding, labels, and alignment consistent.
- Keep form fields visually aligned with consistent height, padding, labels, and focus states.
- Support Light Mode, Dark Mode, and System Mode.
- Support Dynamic Type where practical without breaking dense financial layouts.
- Use SF Symbols only for icons.
- Avoid one-off colors and one-off text styles inside screens.

Reusable components to add:

- `SummaryCard`
- `AccountCard`
- `TransactionRow`
- `BudgetProgressBar`
- `ScheduledTransactionRow`
- `FloatingActionButton`
- `FloatingActionMenu`
- `SectionHeader`
- `MoneyText`
- `AmountEntryField`

Money values should render through `MoneyText` or a shared formatter. The formatter should respect selected currency, decimal places, thousands separator, sign display, and tabular figure styling.

## Navigation

Phone navigation should use bottom navigation:

- Dashboard
- Ledger
- Accounts
- Budgets
- More

`More` should contain:

- Scheduled
- Reports
- Settings
- Export/Import placeholders

iPad and Mac should move toward a sidebar-style layout. The sidebar should expose the same top-level areas without crowding the main content. The same feature screens should be reusable across phone, iPad, and Mac with adaptive shells rather than separate duplicate screens.

A persistent floating add button should be available on all main screens except Reports. The user can place it left or right in Settings.

Floating add menu actions:

- Expense
- Income
- Transfer
- Account
- Category
- Scheduled Transaction

## Data Model

Use integer minor units for stored money values. For USD, cents are stored as integers. Currency formatting belongs in presentation/formatting code, not in the stored transaction model.

Every syncable record should include:

- `id`
- `createdAt`
- `updatedAt`
- `deletedAt`
- `deviceId`
- `version`

Prefer soft archive/delete for syncable records. Hard delete can be a later cleanup operation after sync safety is proven.

### Account

Target fields:

- `id`
- `name`
- `type`: banking, cash, creditCard, loan
- `openingBalanceMinor`
- `currentBalanceMinor` or derived balance strategy
- `isArchived`
- `includeInGroupBalance`
- `includeInNetWorth`
- sync metadata

Settled balance rule: account balances are derived from opening balance plus ledger activity. Expenses, income, transfers, and balance adjustments are all ledger transactions. The app should not silently mutate account balances. `Adjust Balance` creates an explicit adjustment transaction so the balance change remains auditable, exportable, and syncable. The app can cache computed balances for performance later, but the ledger remains the source of truth.

### Category

Target fields:

- `id`
- `name`
- `kind`: income, expense, transfer, system
- `parentCategoryId`
- `iconName`
- `colorValue`
- `isArchived`
- sync metadata

Categories must support parent/subcategory hierarchies. Budgets should be able to target one or more categories, and eventually decide whether a parent budget includes subcategories.

Category icons are optional. If an icon is used, it should come from a small curated set of clean, professional SF Symbols. Do not use emoji or cartoon-like icons. If no icon is selected, display a subtle color dot or only the category name depending on context.

### Transaction

Target fields:

- `id`
- `type`: expense, income, transfer, adjustment
- `accountId`
- `transferAccountId`
- `categoryId`
- `date`
- `payee`
- `amountMinor`
- `note`
- `status`
- `splitGroupId`
- `scheduledTransactionId`
- sync metadata

Settled transfer rule: transfers are first-class transaction records, not income, not expense, and not a normal transaction with an `isTransfer` flag. A transfer has a source account and destination account, affects both balances, does not affect spending, income, or budgets, appears in the ledger for both affected accounts, and is edited as one logical transfer.

Split transactions need child split lines:

- `id`
- `transactionId`
- `categoryId`
- `amountMinor`
- `note`

The parent transaction total must equal the sum of split lines.

Settled split rule: budgets and category reports use split lines when present, not the parent category. Editing split lines must revalidate that the child line total equals the parent transaction amount before saving.

### Scheduled Transaction

Target fields:

- `id`
- `type`: expense, income, transfer
- `accountId`
- `transferAccountId`
- `categoryId`
- `payee`
- `amountMinor`
- `nextDate`
- `frequency`
- `endDate`
- `alertPreference`
- `customAlertTime`
- `repeatAlertUntilResolved`
- `lastAction`: paid, skipped, none
- sync metadata

Scheduled transactions should not silently post unless an explicit future preference is added. Initial behavior should remind, allow Mark Paid, Skip Once, Edit, Duplicate, and Delete.

### Budget

Target fields:

- `id`
- `name`
- `period`: monthly first
- `amountMinor`
- `categoryIds`
- `rolloverMode`
- `isArchived`
- sync metadata

Budget display should show budget amount, spent amount, remaining amount, and over-budget state in plain language.

Example:

`Spent $200 of $90 - Over by $110`

### User Preferences

Target fields:

- `launchScreen`
- `appearance`: light, dark, system
- `floatingAddButtonPosition`: left, right
- `currencyCode`
- `customCurrencySymbol`
- `decimalPlaces`
- `thousandsSeparator`
- `defaultTransactionType`: expense, income, transfer, lastUsed
- notification preferences
- sync metadata or local-only preference metadata

Most preferences should sync, but some device-specific preferences may remain local. Decide per preference before implementation.

## Sync and Data Ownership

Current sync uses full snapshot push/pull at:

`users/{userId}/finance/snapshot`

This is acceptable for the prototype, but the target architecture is per-record sync before the app becomes a daily driver. A v1-to-v2 migration bridge now exists so existing snapshot data can be converted to ledger-derived v2 records without losing visible account balances.

```text
users/{userId}/accounts/{accountId}
users/{userId}/categories/{categoryId}
users/{userId}/transactions/{transactionId}
users/{userId}/scheduledTransactions/{scheduledTransactionId}
users/{userId}/budgets/{budgetId}
users/{userId}/preferences/main
```

Before larger multi-device use, define merge rules:

- Highest `updatedAt` wins for ordinary edits.
- Deletes/archives must win over older edits.
- Transactions should be append-friendly.
- Balance adjustment conflicts should be represented by explicit adjustment records.
- Snapshot backup export/import must preserve ids and sync metadata.

Settled sync rule: per-record Firestore sync is the real implementation target. Snapshot sync may remain only as a migration or backup bridge.

Migration rules:

- Existing v1 account balances become v2 opening balances adjusted by migrated transaction deltas, so the visible current balance is preserved.
- Existing v1 expenses and income become v2 transaction records with positive minor-unit amounts.
- Legacy v1 transfer transactions do not have a destination account, so they migrate as explicit adjustment transactions with a migration note.
- V2 data should be loaded first; v1 migration should run only when no v2 local data exists.
- During the screen migration phase, v1 saves also write a local v2 mirror. This is temporary and should be removed once v2 is the single source of truth.

Prepare for:

- CSV export
- JSON export
- Local backup
- Restore from backup
- iCloud backup later

Do not build all export features immediately, but keep models serializable, stable, and versioned.

## Notifications

Use local notifications for scheduled transaction alerts through a dedicated `NotificationScheduler` service. UI screens should not schedule notifications directly.

Required alert options:

- No alert
- Same day
- 1 day before
- 3 days before
- 1 week before
- Custom
- Custom alert time
- Optional repeat alert until marked paid/skipped
- Badge count for upcoming due items
- Due today notification support

Notification scheduling should live outside UI screens in a notification service. Store scheduled notification ids so edits, skips, deletes, and mark-paid actions can cancel/reschedule correctly.

Platform note: iOS, iPadOS, macOS, and Android notification permissions and badge behavior differ. Hide platform-specific details behind `NotificationScheduler`.

Settled notification rule: use `flutter_local_notifications`, ask permission only when the user enables alerts, keep initial behavior reminder-only with no auto-posting, and keep badge counts focused on due or overdue scheduled items.

## Coding Conventions

- Keep models immutable and serializable.
- Store money as integers in minor units, not doubles.
- Keep formatting out of domain models.
- Keep UI widgets stateless where practical.
- Use small feature-specific widgets rather than very large screen files.
- Use `copyWith` for model updates.
- Soft-delete/archive syncable records before hard-deleting.
- Keep all persistence behind repository interfaces.
- Keep date calculations in selectors/services, not inline in widgets.
- Keep haptics in command handlers, not scattered through low-level widgets.
- Prefer adaptive layout components over duplicate phone/tablet/desktop implementations.
- Avoid adding screen-specific design constants when a design token exists.
- Run `dart format`, `flutter analyze`, and focused tests before installing builds.

## Product Modules and Requirements

### Dashboard

Show richer summary cards:

- Net Worth
- Total Assets
- Total Liabilities
- Available Cash
- This Month: Income, Expenses, Remaining
- Upcoming scheduled transactions
- Budget progress preview

Keep the dashboard clean and scannable. Do not crowd every metric into the first viewport.

### Accounts

Account groups:

- Banking
- Cash
- Credit Cards
- Loans

Features:

- Add account
- Edit account
- Archive account
- Delete account
- Collapsible account groups
- Include in group balance
- Include in net worth

Long press account actions:

- Add Expense
- Add Income
- Transfer
- Adjust Balance
- Edit
- Archive/Delete

Remove the standalone Adjust Balance button. Balance adjustments should live in account actions and should create auditable records if the ledger model supports it.

### Ledger

Features:

- Add expense
- Add income
- Add transfer
- Edit transaction
- Duplicate transaction
- Delete transaction
- Split transaction
- Make transaction scheduled
- Search transactions
- Filter by account, category, date, and type

Long press transaction actions:

- Edit
- Duplicate
- Split
- Make Scheduled
- Delete

### Scheduled Transactions

Features:

- Scheduled expense
- Scheduled income
- Scheduled transfer
- Collapsible calendar at top
- Mark dates that have scheduled items
- List scheduled items below calendar
- Local notification alerts and reminders

Long press scheduled transaction actions:

- Mark Paid
- Skip Once
- Edit
- Duplicate
- Delete

### Budgets

Budget cards should show:

- Budget amount
- Spent amount
- Remaining amount
- Over-budget warning when applicable
- Progress bar

Budgets must support assigned categories.

### Categories

Features:

- Add category
- Edit category
- Delete/archive category
- Parent categories
- Subcategories
- Optional SF Symbol
- Optional color

Example hierarchy:

```text
Food
  Groceries
  Dining
  Snacks
Transportation
  Fuel
  Insurance
  Maintenance
```

### Settings

Settings should include:

- Launch screen preference
- Appearance: Light, Dark, System
- Floating add button position: Left, Right
- Currency: USD, PHP, EUR, GBP, CAD, AUD, JPY, Custom if practical
- Decimal places
- Thousands separator
- Default transaction type
- Manage accounts
- Manage categories
- Notification preferences
- Export/import placeholders

### Amount Entry

Use calculator-style money entry:

- Always show selected decimal places.
- Automatically place decimals.
- Automatically add thousands separators.
- User should not need to type a decimal point.
- Use the selected currency symbol.

Examples for two decimal places:

- `5 0 0` displays `$5.00`
- `1 2 3 4 5` displays `$123.45`
- `1 0 0 0 0 0 0` displays `$10,000.00`

### Reports

Keep reports simple:

- Monthly spending
- Income vs expenses
- Category breakdown
- Cash flow
- Net worth history
- Budget history

Exclude investment, debt payoff, credit score, and AI financial advice features.

## Known Architecture Decisions Before Implementation

1. Account balances are ledger-derived: opening balance plus transactions plus explicit balance adjustment transactions.
2. Transfers are first-class records, not normal transactions with an `isTransfer` flag.
3. Splits use child split lines; child totals must equal the parent transaction amount before saving.
4. Per-record Firestore sync is the target architecture. Snapshot sync is only a prototype/migration bridge.
5. Category icons are optional and must stay clean, professional, and curated. No emoji.
6. Local notifications require stable scheduled transaction ids and a dedicated service that can cancel/reschedule alerts.
7. iPad and Mac need an adaptive sidebar shell; phone should keep bottom navigation.
8. Settings should exist before the design system is fully used, because appearance, currency, decimal places, and FAB placement affect many components.
9. Category hierarchy affects budgets and reports; implement categories before final budget/report logic.
10. Simulator is useful for UI/layout testing, but real iPhone and Mac remain the source of truth for Apple sign-in and sync.

## Development Priority

Build in this order:

1. Data models
2. Design system
3. Settings/preferences
4. Accounts
5. Ledger
6. Scheduled transactions and alerts
7. Dashboard
8. Budgets/categories
9. Reports
10. Polish pass

Do not rush into screen-by-screen patching. Build the reusable foundation first, then use that foundation to replace screens consistently.

## Future Roadmap

Near term:

- Wire app bootstrap to the v2 migration loader when screens are ready to move off the v1 store.
- Move Accounts and Ledger screens onto the v2 `FinanceDataStore`.
- Refactor remaining file structure into app/auth/features boundaries.
- Finish user preferences UI and appearance mode wiring.
- Continue expanding reusable design components where screens need them.
- Add adaptive navigation shell.

Mid term:

- Add scheduled transaction calendar and local notifications.
- Add budget/category management.
- Add simple reports.
- Add JSON backup and restore.
- Add CSV export.

Later:

- Replace full-snapshot Firestore sync with per-record Firestore sync.
- Add iCloud backup support.
- Add Android build and Play Store setup.
- Add App Store/TestFlight archive workflow.
