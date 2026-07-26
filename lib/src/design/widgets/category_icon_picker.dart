import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../category_icon_catalog.dart';
import '../design_tokens.dart';

const categoryIconNoneKey = '__none__';

/// Opens Money Tally's curated, searchable category icon picker.
Future<String?> showCategoryIconPicker(
  BuildContext context, {
  required String selectedKey,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _CategoryIconPicker(selectedKey: selectedKey),
  );
}

class _CategoryIconPicker extends StatefulWidget {
  const _CategoryIconPicker({required this.selectedKey});

  final String selectedKey;

  @override
  State<_CategoryIconPicker> createState() => _CategoryIconPickerState();
}

class _CategoryIconPickerState extends State<_CategoryIconPicker> {
  final _searchController = TextEditingController();
  String _query = '';
  late String _previewKey = widget.selectedKey;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = CategoryIconCatalog.matching(_query);
    final grouped = <String, List<AppCategoryIcon>>{
      for (final group in CategoryIconCatalog.groups)
        group: results.where((icon) => icon.group == group).toList(),
    }..removeWhere((_, icons) => icons.isEmpty);
    final preview = CategoryIconCatalog.find(_previewKey);

    return FractionallySizedBox(
      heightFactor: .9,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 52,
            height: 5,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose Icon',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Semantics(
                  label: preview == null
                      ? 'No icon selected'
                      : '${preview.label} selected',
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: .09),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      preview?.icon ?? AppIcon.hidden,
                      size: AppIconSize.action,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search 160 icons',
                prefixIcon: Icon(AppIcon.search, size: AppIconSize.row),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: Icon(AppIcon.clearFilter),
                      ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
          ),
          Expanded(
            child: grouped.isEmpty
                ? Center(
                    child: Text(
                      'No matching icons',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : CustomScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverToBoxAdapter(
                        child: _NoIconTile(
                          selected: _previewKey == categoryIconNoneKey,
                          onTap: () {
                            setState(() => _previewKey = categoryIconNoneKey);
                            Navigator.pop(context, categoryIconNoneKey);
                          },
                        ),
                      ),
                      for (final entry in grouped.entries) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.md,
                              AppSpacing.lg,
                              AppSpacing.xs,
                            ),
                            child: Text(
                              entry.key,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          sliver: SliverGrid.builder(
                            itemCount: entry.value.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  mainAxisExtent: 86,
                                  crossAxisSpacing: AppSpacing.xs,
                                  mainAxisSpacing: AppSpacing.xs,
                                ),
                            itemBuilder: (context, index) {
                              final item = entry.value[index];
                              return _IconChoice(
                                item: item,
                                selected: item.key == _previewKey,
                                onTap: () {
                                  setState(() => _previewKey = item.key);
                                  Navigator.pop(context, item.key);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.lg),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoIconTile extends StatelessWidget {
  const _NoIconTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Icon(AppIcon.hidden, size: AppIconSize.form),
      title: const Text('No icon'),
      trailing: selected
          ? Icon(
              AppIcon.checkRounded,
              size: AppIconSize.row,
              color: AppColors.accent,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppCategoryIcon item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${item.label} icon',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.control),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: .09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.control),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: .5)
                  : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: AppIconSize.action,
                color: selected
                    ? AppColors.accent
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                item.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  height: 1.05,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
