import 'package:url_launcher/url_launcher.dart';

/// Public, app-specific destinations. Never append account data or identifiers.
enum TrackmarkSupportLink {
  help('View Full Help & Guides', 'Setup tips and answers online', 'help'),
  support('Support', 'Get help or contact Trackmark', 'support'),
  privacy('Privacy Policy', 'How your data is handled', 'privacy');

  const TrackmarkSupportLink(this.title, this.subtitle, this.path);

  final String title;
  final String subtitle;
  final String path;

  Uri get uri => Uri.https('mileandmarker.com', '/apps/trackmark-money/$path/');
}

typedef SupportUrlLauncher =
    Future<bool> Function(Uri uri, {required LaunchMode mode});

class SupportLinkService {
  SupportLinkService({SupportUrlLauncher? launcher})
    : _launcher = launcher ?? launchUrl;

  final SupportUrlLauncher _launcher;

  Future<bool> open(TrackmarkSupportLink link) async {
    try {
      // Use the device's browser, without an embedded web view or app data.
      // Launch directly: a canLaunch preflight can give false negatives.
      return await _launcher(link.uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
