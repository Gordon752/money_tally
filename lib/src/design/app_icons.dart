import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Central semantic icon registry for Money Tally.
///
/// iOS uses Cupertino glyphs backed by the SF-style Cupertino icon font.
/// Android and other platforms use Material Symbols. Screens should reference
/// this registry rather than selecting a platform glyph directly.
abstract final class AppIcon {
  static bool get _usesCupertino => defaultTargetPlatform == TargetPlatform.iOS;

  static IconData _platform(IconData material, IconData cupertino) =>
      _usesCupertino ? cupertino : material;

  // Navigation and primary destinations.
  static IconData get dashboard =>
      _platform(Icons.dashboard_outlined, CupertinoIcons.square_grid_2x2);
  static IconData get accounts => _platform(
    Icons.account_balance_wallet_outlined,
    CupertinoIcons.creditcard,
  );
  static IconData get ledger =>
      _platform(Icons.receipt_long_outlined, CupertinoIcons.doc_text);
  static IconData get plan =>
      _platform(Icons.pie_chart_outline, CupertinoIcons.chart_pie);
  static IconData get scheduled => _platform(
    Icons.event_repeat_outlined,
    CupertinoIcons.calendar_badge_plus,
  );
  static IconData get reports =>
      _platform(Icons.insights_outlined, CupertinoIcons.chart_bar);
  static IconData get settings =>
      _platform(Icons.settings_outlined, CupertinoIcons.gear);
  static IconData get home =>
      _platform(Icons.home_outlined, CupertinoIcons.house);

  // Money, accounts, and transaction identity.
  static IconData get bank =>
      _platform(Icons.account_balance_outlined, CupertinoIcons.building_2_fill);
  static IconData get bankSolid =>
      _platform(Icons.account_balance, CupertinoIcons.building_2_fill);
  static IconData get wallet => _platform(
    Icons.account_balance_wallet_outlined,
    CupertinoIcons.creditcard,
  );
  static IconData get creditCard =>
      _platform(Icons.credit_card_outlined, CupertinoIcons.creditcard);
  static IconData get loan =>
      _platform(Icons.request_quote_outlined, CupertinoIcons.doc_text);
  static IconData get cash =>
      _platform(Icons.payments_outlined, CupertinoIcons.money_dollar);
  static IconData get money =>
      _platform(Icons.attach_money, CupertinoIcons.money_dollar);
  static IconData get moneyOutlined =>
      _platform(Icons.attach_money_outlined, CupertinoIcons.money_dollar);
  static IconData get currency => _platform(
    Icons.currency_exchange_outlined,
    CupertinoIcons.arrow_right_arrow_left,
  );
  static IconData get expense =>
      _platform(Icons.remove_circle_outline, CupertinoIcons.minus_circle);
  static IconData get income =>
      _platform(Icons.add_circle_outline, CupertinoIcons.add_circled);
  static IconData get transfer =>
      _platform(Icons.swap_horiz, CupertinoIcons.arrow_right_arrow_left);
  static IconData get split =>
      _platform(Icons.call_split_outlined, CupertinoIcons.arrow_branch);
  static IconData get receipt =>
      _platform(Icons.receipt_long_outlined, CupertinoIcons.doc_text);
  static IconData get adjustment => _platform(
    Icons.compare_arrows_outlined,
    CupertinoIcons.arrow_up_arrow_down,
  );

  // Goals and planning.
  static IconData get goal =>
      _platform(Icons.flag_outlined, CupertinoIcons.flag);
  static IconData get target =>
      _platform(Icons.track_changes_outlined, CupertinoIcons.scope);
  static IconData get savings =>
      _platform(Icons.savings_outlined, CupertinoIcons.money_dollar_circle);
  static IconData get shield =>
      _platform(Icons.shield_outlined, CupertinoIcons.shield);
  static IconData get trend =>
      _platform(Icons.trending_up_outlined, CupertinoIcons.chart_bar);
  static IconData get trendUp =>
      _platform(Icons.trending_up, CupertinoIcons.arrow_up_right);
  static IconData get trendDown =>
      _platform(Icons.trending_down, CupertinoIcons.arrow_down_right);
  static IconData get budget =>
      _platform(Icons.pie_chart_outline, CupertinoIcons.chart_pie);

  // Reports and charts.
  static IconData get pieChart =>
      _platform(Icons.pie_chart_outline, CupertinoIcons.chart_pie);
  static IconData get donutChart =>
      _platform(Icons.donut_large_outlined, CupertinoIcons.chart_pie);
  static IconData get barChart =>
      _platform(Icons.bar_chart_outlined, CupertinoIcons.chart_bar);
  static IconData get insights =>
      _platform(Icons.insights_outlined, CupertinoIcons.chart_bar);
  static IconData get info =>
      _platform(Icons.info_outline, CupertinoIcons.info_circle);

  // Calendar, recurrence, and notifications.
  static IconData get calendar =>
      _platform(Icons.calendar_today_outlined, CupertinoIcons.calendar);
  static IconData get calendarMonth =>
      _platform(Icons.calendar_month_outlined, CupertinoIcons.calendar);
  static IconData get calendarGrid =>
      _platform(Icons.calendar_view_month_outlined, CupertinoIcons.calendar);
  static IconData get dateRange =>
      _platform(Icons.date_range_outlined, CupertinoIcons.calendar);
  static IconData get event =>
      _platform(Icons.event_outlined, CupertinoIcons.calendar);
  static IconData get eventNote =>
      _platform(Icons.event_note_outlined, CupertinoIcons.calendar);
  static IconData get eventBusy =>
      _platform(Icons.event_busy_outlined, CupertinoIcons.calendar_badge_minus);
  static IconData get repeat => _platform(Icons.repeat, CupertinoIcons.repeat);
  static IconData get recurrence =>
      _platform(Icons.event_repeat_outlined, CupertinoIcons.repeat);
  static IconData get schedule =>
      _platform(Icons.schedule_outlined, CupertinoIcons.clock);
  static IconData get skip =>
      _platform(Icons.skip_next_outlined, CupertinoIcons.forward_end);
  static IconData get notification =>
      _platform(Icons.notifications_outlined, CupertinoIcons.bell);
  static IconData get notificationNone =>
      _platform(Icons.notifications_none_outlined, CupertinoIcons.bell);
  static IconData get notificationActive =>
      _platform(Icons.notifications_active_outlined, CupertinoIcons.bell_fill);
  static IconData get notificationImportant => _platform(
    Icons.notification_important_outlined,
    CupertinoIcons.exclamationmark_circle,
  );

  // People, categories, and descriptive fields.
  static IconData get category =>
      _platform(Icons.sell_outlined, CupertinoIcons.tag);
  static IconData get categoryGroup =>
      _platform(Icons.category_outlined, CupertinoIcons.tags);
  static IconData get categoryTree =>
      _platform(Icons.account_tree_outlined, CupertinoIcons.flowchart);
  static IconData get payee =>
      _platform(Icons.person_outline, CupertinoIcons.person);
  static IconData get addPayee =>
      _platform(Icons.person_add_outlined, CupertinoIcons.person_add);
  static IconData get addPerson =>
      _platform(Icons.person_add_alt_outlined, CupertinoIcons.person_add);
  static IconData get description =>
      _platform(Icons.short_text_outlined, CupertinoIcons.text_alignleft);
  static IconData get notes =>
      _platform(Icons.notes_outlined, CupertinoIcons.doc_text);
  static IconData get text =>
      _platform(Icons.text_fields_outlined, CupertinoIcons.textformat);
  static IconData get numbers =>
      _platform(Icons.numbers_outlined, CupertinoIcons.number);
  static IconData get numberedList => _platform(
    Icons.format_list_numbered_outlined,
    CupertinoIcons.list_number,
  );

  // File, sync, import, and export.
  static IconData get export =>
      _platform(Icons.ios_share_outlined, CupertinoIcons.share);
  static IconData get import =>
      _platform(Icons.file_download_outlined, CupertinoIcons.tray_arrow_down);
  static IconData get backup =>
      _platform(Icons.data_object_outlined, CupertinoIcons.doc);
  static IconData get copy =>
      _platform(Icons.copy_outlined, CupertinoIcons.doc_on_doc);
  static IconData get contentCopy =>
      _platform(Icons.content_copy_outlined, CupertinoIcons.doc_on_doc);
  static IconData get sync =>
      _platform(Icons.sync_outlined, CupertinoIcons.arrow_2_circlepath);
  static IconData get cloud =>
      _platform(Icons.cloud_queue, CupertinoIcons.cloud);
  static IconData get cloudDone =>
      _platform(Icons.cloud_done_outlined, CupertinoIcons.cloud_upload);
  static IconData get cloudOff =>
      _platform(Icons.cloud_off_outlined, CupertinoIcons.cloud);
  static IconData get restore =>
      _platform(Icons.restore_outlined, CupertinoIcons.arrow_counterclockwise);
  static IconData get history => _platform(
    Icons.history_toggle_off_outlined,
    CupertinoIcons.arrow_counterclockwise_circle,
  );

  // Common actions and state.
  static IconData get add => _platform(Icons.add, CupertinoIcons.add);
  static IconData get addRounded =>
      _platform(Icons.add_rounded, CupertinoIcons.add);
  static IconData get edit =>
      _platform(Icons.edit_outlined, CupertinoIcons.pencil);
  static IconData get delete =>
      _platform(Icons.delete_outline, CupertinoIcons.trash);
  static IconData get archive =>
      _platform(Icons.archive_outlined, CupertinoIcons.archivebox);
  static IconData get unarchive =>
      _platform(Icons.unarchive_outlined, CupertinoIcons.archivebox_fill);
  static IconData get undo =>
      _platform(Icons.undo_outlined, CupertinoIcons.arrow_uturn_left);
  static IconData get check =>
      _platform(Icons.check, CupertinoIcons.check_mark);
  static IconData get checkRounded =>
      _platform(Icons.check_rounded, CupertinoIcons.check_mark);
  static IconData get success =>
      _platform(Icons.check_circle_outline, CupertinoIcons.check_mark_circled);
  static IconData get error =>
      _platform(Icons.error_outline, CupertinoIcons.exclamationmark_circle);
  static IconData get hidden =>
      _platform(Icons.hide_source_outlined, CupertinoIcons.eye_slash);
  static IconData get clearColor =>
      _platform(Icons.format_color_reset_outlined, CupertinoIcons.paintbrush);
  static IconData get palette =>
      _platform(Icons.palette_outlined, CupertinoIcons.paintbrush);
  static IconData get signOut =>
      _platform(Icons.logout_outlined, CupertinoIcons.square_arrow_right);
  static IconData get signOutSolid =>
      _platform(Icons.logout, CupertinoIcons.square_arrow_right);

  // Navigation controls and utility affordances.
  static IconData get search => _platform(Icons.search, CupertinoIcons.search);
  static IconData get filter =>
      _platform(Icons.tune_outlined, CupertinoIcons.slider_horizontal_3);
  static IconData get tune =>
      _platform(Icons.tune, CupertinoIcons.slider_horizontal_3);
  static IconData get clearFilter =>
      _platform(Icons.filter_alt_off_outlined, CupertinoIcons.clear);
  static IconData get chevronLeft =>
      _platform(Icons.chevron_left, CupertinoIcons.chevron_left);
  static IconData get chevronRight =>
      _platform(Icons.chevron_right, CupertinoIcons.chevron_right);
  static IconData get chevronRightRounded =>
      _platform(Icons.chevron_right_rounded, CupertinoIcons.chevron_right);
  static IconData get chevronDown =>
      _platform(Icons.keyboard_arrow_down, CupertinoIcons.chevron_down);
  static IconData get chevronDownRounded =>
      _platform(Icons.keyboard_arrow_down_rounded, CupertinoIcons.chevron_down);
  static IconData get chevronUp =>
      _platform(Icons.keyboard_arrow_up, CupertinoIcons.chevron_up);
  static IconData get dropdown =>
      _platform(Icons.arrow_drop_down_rounded, CupertinoIcons.chevron_down);
  static IconData get arrowForward =>
      _platform(Icons.arrow_forward, CupertinoIcons.arrow_right);
  static IconData get arrowUp =>
      _platform(Icons.arrow_upward, CupertinoIcons.arrow_up);
  static IconData get arrowDown =>
      _platform(Icons.arrow_downward, CupertinoIcons.arrow_down);
  static IconData get drag =>
      _platform(Icons.drag_handle, CupertinoIcons.line_horizontal_3);
  static IconData get circle =>
      _platform(Icons.circle, CupertinoIcons.circle_fill);

  // Settings and appearance.
  static IconData get contrast =>
      _platform(Icons.contrast_outlined, CupertinoIcons.circle_lefthalf_fill);
  static IconData get appearance =>
      _platform(Icons.palette_outlined, CupertinoIcons.paintbrush);

  // Frequently used real-world category identities.
  static IconData get dining => _platform(
    Icons.restaurant_outlined,
    CupertinoIcons.device_phone_portrait,
  );
  static IconData get shopping =>
      _platform(Icons.shopping_cart_outlined, CupertinoIcons.cart);
  static IconData get auto =>
      _platform(Icons.directions_car_outlined, CupertinoIcons.car);
  static IconData get fuel =>
      _platform(Icons.local_gas_station_outlined, CupertinoIcons.drop);
  static IconData get entertainment =>
      _platform(Icons.movie_outlined, CupertinoIcons.film);
  static IconData get medical =>
      _platform(Icons.medical_services_outlined, CupertinoIcons.bandage);
  static IconData get phone =>
      _platform(Icons.phone_outlined, CupertinoIcons.phone);
  static IconData get utilities =>
      _platform(Icons.bolt_outlined, CupertinoIcons.bolt);
  static IconData get maintenance =>
      _platform(Icons.build_outlined, CupertinoIcons.wrench);

  // Compatibility-only semantic entries for rare framework concepts.
  static IconData get apple =>
      _platform(Icons.apple, CupertinoIcons.device_phone_portrait);
  static IconData get any =>
      _platform(Icons.help_outline, CupertinoIcons.question_circle);
}

abstract final class AppIconSize {
  static const double compact = 16;
  static const double inline = 18;
  static const double row = 20;
  static const double form = 22;
  static const double action = 24;
  static const double navigation = 24;
  static const double hero = 28;
  static const double prominent = 32;
  static const double brand = 48;
}
