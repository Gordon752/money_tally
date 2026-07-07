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
    this.fieldKey,
    super.key,
  });

  final int initialMinor;
  final CurrencyFormatSettings currency;
  final String labelText;
  final bool autofocus;
  final bool allowNegative;
  final Key? fieldKey;
  final ValueChanged<int> onChanged;

  @override
  State<AmountEntryField> createState() => _AmountEntryFieldState();
}

class _AmountEntryFieldState extends State<AmountEntryField> {
  late final TextEditingController _controller;
  var _isUpdating = false;

  MoneyFormatter get _formatter => MoneyFormatter(widget.currency);

  @override
  void initState() {
    super.initState();
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      keyboardType: TextInputType.numberWithOptions(
        signed: widget.allowNegative,
      ),
      textAlign: TextAlign.right,
      textAlignVertical: TextAlignVertical.center,
      autofocus: widget.autofocus,
      inputFormatters: [
        widget.allowNegative
            ? FilteringTextInputFormatter.allow(RegExp(r'[-0-9]'))
            : FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        labelText: widget.labelText,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w900,
      ),
      onChanged: _handleChanged,
    );
  }

  void _handleChanged(String rawValue) {
    if (_isUpdating) return;
    final isNegative = widget.allowNegative && rawValue.trim().startsWith('-');
    final digits = rawValue.replaceAll(RegExp(r'[^0-9]'), '');
    final unsignedMinor = _formatter.parseDigitsToMinor(digits);
    final minor = isNegative ? -unsignedMinor : unsignedMinor;
    widget.onChanged(minor);
    _setText(_formatter.formatMinor(minor));
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
