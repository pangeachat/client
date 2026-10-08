import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/routes/world/world_map_constants.dart';

/// A host, or group of hosts, the app needs to reach. A network filter blocks
/// the app one category at a time. See filtered-network.instructions.md,
/// "Hosts the app needs".
enum NetworkHostCategory {
  chatServer,
  pangeaApi,
  images,
  video,
  map,
  googleSignIn,
  appleSignIn;

  /// The host the activity video player embeds from: `youtube_player_iframe`
  /// with `privacyEnhancedMode` on.
  static const String _videoEmbedHost = 'www.youtube-nocookie.com';

  /// Whether a block stops the app as a whole, rather than one feature.
  bool get stopsApp => this == chatServer || this == pangeaApi;

  /// A cheap URL on the category's host. Any answer means the host is
  /// reachable, so the path only has to exist on that host.
  Uri get probeUrl => switch (this) {
    chatServer => _withScheme(
      Environment.synapseURL,
    ).resolve('/_matrix/client/versions'),
    pangeaApi => Uri.parse(PApiUrls.appVersion),
    images => Uri.https(AppConfig.contentCdnHost),
    video => Uri.https(_videoEmbedHost),
    map => Uri.https(WorldMapConstants.tileHost),
    googleSignIn => Uri.https('accounts.google.com', '/generate_204'),
    appleSignIn => Uri.https('appleid.apple.com', '/favicon.ico'),
  };

  /// The domains IT staff must allow for this category to work.
  List<String> get allowlistDomains => switch (this) {
    chatServer => [_withScheme(Environment.synapseURL).host],
    pangeaApi => [_withScheme(Environment.choreoApi).host],
    images => [AppConfig.contentCdnHost],
    video => [
      'youtube-nocookie.com',
      'youtube.com',
      'ytimg.com',
      'googlevideo.com',
    ],
    map => [WorldMapConstants.tileHost],
    googleSignIn => ['accounts.google.com'],
    appleSignIn => ['appleid.apple.com'],
  };

  /// Every domain the app needs, in the order the categories are listed.
  static List<String> get allAllowlistDomains => [
    for (final category in values) ...category.allowlistDomains,
  ];

  /// The category a failed request to [url] belongs to, for the hosts whose
  /// requests the app watches directly; null for any other host.
  static NetworkHostCategory? ofRequest(Uri url) {
    final host = url.host.toLowerCase();
    if (host.isEmpty) return null;
    if (host == _withScheme(Environment.synapseURL).host) return chatServer;
    if (host == _withScheme(Environment.choreoApi).host ||
        host == _withScheme(Environment.cmsApi).host) {
      return pangeaApi;
    }
    if (host == AppConfig.contentCdnHost) return images;
    return null;
  }

  /// [Environment]'s base URLs may be configured with or without a scheme.
  static Uri _withScheme(String url) => Uri.parse(
    url.startsWith('http://') || url.startsWith('https://')
        ? url
        : 'https://$url',
  );
}
