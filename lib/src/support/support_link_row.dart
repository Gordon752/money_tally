part of '../../main.dart';

/// The same Settings row treatment for web links in Settings and the guide.
class TrackmarkSupportLinkRow extends StatefulWidget {
  const TrackmarkSupportLinkRow({
    required this.link,
    this.showDivider = true,
    this.service,
    this.title,
    super.key,
  });

  final TrackmarkSupportLink link;
  final bool showDivider;
  final SupportLinkService? service;
  final String? title;

  @override
  State<TrackmarkSupportLinkRow> createState() =>
      _TrackmarkSupportLinkRowState();
}

class _TrackmarkSupportLinkRowState extends State<TrackmarkSupportLinkRow> {
  var _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    final link = widget.link;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _opening = true);
    final opened = await (widget.service ?? SupportLinkService()).open(link);
    if (!mounted) return;
    setState(() => _opening = false);
    if (opened) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Could not open ${link.title}. Please try again.'),
          action: SnackBarAction(
            label: 'Copy link',
            onPressed: () => copyExportToClipboard(
              context,
              title: 'Link copied',
              payload: link.uri.toString(),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => SettingsActionRow(
    icon: switch (widget.link) {
      TrackmarkSupportLink.help => AppIcon.info,
      TrackmarkSupportLink.support => AppIcon.support,
      TrackmarkSupportLink.privacy => AppIcon.shield,
    },
    title: widget.title ?? widget.link.title,
    subtitle: widget.link.subtitle,
    subtitleMaxLines: 4,
    showDivider: widget.showDivider,
    showProgress: _opening,
    onTap: _opening ? null : _open,
  );
}
