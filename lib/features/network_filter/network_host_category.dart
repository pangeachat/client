import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/map_tiles.dart';

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

  /// Whether the category is one of our own servers, which a deploy restarts.
  /// While it restarts it refuses connections, the way a filter does.
  bool get isOurServer => this == chatServer || this == pangeaApi;

  /// A cheap URL on the category's host. Any answer means the host is
  /// reachable, so the path only has to exist on that host — and answer
  /// there: a browser follows redirects unseen, and one to plain `http` is
  /// refused as mixed content, which reads as a block on every network.
  Uri get probeUrl => switch (this) {
    chatServer => _withScheme(
      Environment.synapseURL,
    ).resolve('/_matrix/client/versions'),
    pangeaApi => Uri.parse(PApiUrls.appVersion),
    images => Uri.https(AppConfig.contentCdnHost),
    video => Uri.https(_videoEmbedHost),
    // Not the bare host: it redirects to stadiamaps.com, which the native
    // probe reads as a filter's block page. `/tiles/` answers 404 in place.
    map => Uri.https(MapTiles.host, '/tiles/'),
    googleSignIn => Uri.https('accounts.google.com', '/generate_204'),
    // Not /favicon.ico: it redirects to http://www.apple.com (#9441).
    appleSignIn => Uri.https(
      'appleid.apple.com',
      '/.well-known/openid-configuration',
    ),
  };

  /// The domains IT staff must allow for this category to work.
  List<String> get allowlistDomains => switch (this) {
    chatServer => [_withScheme(Environment.synapseURL).host],
    // The CMS host may be its own (CMS_API); the set folds it when it isn't.
    pangeaApi => {
      _withScheme(Environment.choreoApi).host,
      _withScheme(Environment.cmsApi).host,
    }.toList(),
    images => [AppConfig.contentCdnHost],
    video => [
      'youtube-nocookie.com',
      'youtube.com',
      'ytimg.com',
      'googlevideo.com',
    ],
    map => [MapTiles.host],
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
