import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Calculator-style percentage input that treats typed digits as hundredths
/// of one percent while leaving the controller value as a plain number.
///
/// For example, sequential digits `2`, `8`, `4`, `9` resolve to controller
/// text `28.49`. The percent sign is presentation-only and is never stored.
class ShiftedPercentageInputFormatter extends TextInputFormatter {
  const ShiftedPercentageInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();

    final hundredths = int.parse(digits);
    final formatted = (hundredths / 100).toStringAsFixed(2);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PercentageEntryField extends StatefulWidget {
  const PercentageEntryField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.decoration,
    this.fieldKey,
    this.hintText,
    this.hintStyle,
    this.style,
    this.textInputAction = TextInputAction.done,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final InputDecoration decoration;
  final Key? fieldKey;
  final String? hintText;
  final TextStyle? hintStyle;
  final TextStyle? style;
  final TextInputAction textInputAction;

  @override
  State<PercentageEntryField> createState() => _PercentageEntryFieldState();
}

class _PercentageEntryFieldState extends State<PercentageEntryField> {
  static const _formatter = ShiftedPercentageInputFormatter();
  var _showRequiredError = false;

  @override
  void initState() {
    super.initState();
    _normalizeExistingValue();
    widget.focusNode.addListener(_handleFocusChanged);
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(PercentageEntryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      _normalizeExistingValue();
      widget.controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChanged);
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      keyboardType: TextInputType.number,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      inputFormatters: const [_formatter],
      decoration: widget.decoration.copyWith(
        hintText: widget.hintText,
        hintStyle: widget.hintStyle,
        suffixText: '%',
        errorText: _showRequiredError ? 'Enter an APR' : null,
      ),
      style: widget.style,
    );
  }

  void _normalizeExistingValue() {
    final parsed = double.tryParse(widget.controller.text.trim());
    if (parsed == null || parsed.isNegative) return;
    final formatted = parsed.toStringAsFixed(2);
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void _handleTextChanged() {
    if (_showRequiredError && widget.controller.text.isNotEmpty) {
      setState(() => _showRequiredError = false);
    }
  }

  void _handleFocusChanged() {
    if (widget.focusNode.hasFocus) return;
    final shouldShowError = widget.controller.text.trim().isEmpty;
    if (shouldShowError != _showRequiredError) {
      setState(() => _showRequiredError = shouldShowError);
    }
  }
}
