import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/money.dart';
import '../design_tokens.dart';
import '../money_format.dart';

class AmountEntryField extends StatefulWidget {
  const AmountEntryField({
    required this.onChanged,
    this.initialMinor = 0,
    this.currency = const CurrencyFormatSettings(),
    this.labelText = 'Amount',
    this.autofocus = false,
    this.allowNegative = false,
    this.forceNegative = false,
    this.selectAllOnFocus = false,
    this.keyboardType,
    this.textStyle,
    this.textAlign = TextAlign.right,
    this.decoration,
    this.fieldKey,
    super.key,
  });

  final int initialMinor;
  final CurrencyFormatSettings currency;
  final String? labelText;
  final bool autofocus;
  final bool allowNegative;
  final bool forceNegative;
  final bool selectAllOnFocus;
  final TextInputType? keyboardType;
  final TextStyle? textStyle;
  final TextAlign textAlign;
  final InputDecoration? decoration;
  final Key? fieldKey;
  final ValueChanged<int> onChanged;

  @override
  State<AmountEntryField> createState() => _AmountEntryFieldState();
}

class _AmountEntryFieldState extends State<AmountEntryField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  var _isUpdating = false;
  var _hasAppliedInitialSelection = false;

  MoneyFormatter get _formatter => MoneyFormatter(widget.currency);

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
    _controller = TextEditingController(
      text: _formatter.formatMinor(widget.initialMinor),
    );
  }

  @override
  void didUpdateWidget(covariant AmountEntryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMinor != widget.initialMinor ||
        oldWidget.currency != widget.currency) {
      _setText(_formatter.formatMinor(widget.initialMinor));
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focusNode,
      keyboardType:
          widget.keyboardType ??
          TextInputType.numberWithOptions(
            signed: widget.allowNegative && !widget.forceNegative,
          ),
      textAlign: widget.textAlign,
      textAlignVertical: TextAlignVertical.center,
      autofocus: widget.autofocus,
      inputFormatters: [
        widget.allowNegative && !widget.forceNegative
            ? FilteringTextInputFormatter.allow(RegExp(r'[-0-9]'))
            : FilteringTextInputFormatter.digitsOnly,
      ],
      decoration:
          widget.decoration ??
          InputDecoration(
            labelText: widget.labelText,
            floatingLabelBehavior: widget.labelText == null
                ? FloatingLabelBehavior.never
                : FloatingLabelBehavior.always,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
      style:
          widget.textStyle ??
          Theme.of(context).textTheme.titleLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w900,
          ),
      onTap: _moveCursorToEnd,
      onTapOutside: (_) => _focusNode.unfocus(),
      onChanged: _handleChanged,
    );
  }

  void _handleChanged(String rawValue) {
    if (_isUpdating) return;
    final isNegative =
        widget.forceNegative ||
        (widget.allowNegative && rawValue.trim().startsWith('-'));
    final digits = rawValue.replaceAll(RegExp(r'[^0-9]'), '');
    final unsignedMinor = _formatter.parseDigitsToMinor(digits);
    final minor = isNegative ? -unsignedMinor : unsignedMinor;
    widget.onChanged(minor);
    _setText(_formatter.formatMinor(minor));
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) return;
    if (widget.selectAllOnFocus && !_hasAppliedInitialSelection) {
      _hasAppliedInitialSelection = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusNode.hasFocus) return;
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      });
      return;
    }
    _moveCursorToEnd();
  }

  void _moveCursorToEnd() {
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _setText(String value) {
    _isUpdating = true;
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _isUpdating = false;
  }
}
