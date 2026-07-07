import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/money.dart';
import '../money_format.dart';

class AmountEntryField extends StatefulWidget {
  const AmountEntryField({
    required this.onChanged,
    this.initialMinor = 0,
    this.currency = const CurrencyFormatSettings(),
    this.labelText = 'Amount',
    super.key,
  });

  final int initialMinor;
  final CurrencyFormatSettings currency;
  final String labelText;
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
      controller: _controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.right,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: widget.labelText),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w800,
      ),
      onChanged: _handleChanged,
    );
  }

  void _handleChanged(String rawValue) {
    if (_isUpdating) return;
    final digits = rawValue.replaceAll(RegExp(r'[^0-9]'), '');
    final minor = _formatter.parseDigitsToMinor(digits);
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
