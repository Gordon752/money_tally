import 'package:flutter/material.dart';

import '../design_tokens.dart';

class FloatingActionMenuItem {
  const FloatingActionMenuItem({
    required this.label,
    required this.onSelected,
    this.leading,
  });

  final String label;
  final VoidCallback onSelected;
  final Widget? leading;
}

class MoneyTallyFloatingActionMenu extends StatelessWidget {
  const MoneyTallyFloatingActionMenu({required this.items, super.key});

  final List<FloatingActionMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                ListTile(
                  dense: true,
                  leading: item.leading,
                  title: Text(
                    item.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: item.onSelected,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
