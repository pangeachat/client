import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// Android App Links claim only the inbound link shapes, because an intent
/// filter cannot leave out a single path, and the web sign-in pages must stay
/// in the browser: the `/auth.html` callback, and the `/home` sign-in pages
/// its redirect returns to, which Chrome would otherwise hand to the app as
/// part of the tap on Synapse's Continue button (#9441). A new inbound path
/// shape needs its line in the manifest and a sample here
/// (joining-courses.instructions.md, Deep Linking).
void main() {
  final filter = _AppLinksFilter.load();

  const uuid = 'a1aed3f6-1ef7-4ed0-bc46-4a393aaf880b';
  const claimed = [
    'https://app.pangea.chat',
    'https://app.pangea.chat/',
    'https://app.pangea.chat/?c=%21abc%3Apangea.chat&left=course',
    'https://app.pangea.chat/?right=settings,settingspage:subscription',
    'https://app.pangea.chat/vj3pc8b',
    'https://app.pangea.chat/$uuid',
    'https://app.pangea.chat/$uuid?roomid=%21room%3Apangea.chat',
    'https://app.pangea.chat/invite_user/%40support',
    'https://app.pangea.chat/room/!abc:pangea.chat',
    r'https://app.pangea.chat/room/!abc:pangea.chat/$event',
    'https://app.pangea.chat/gift/SPRING-26',
    'https://app.staging.pangea.chat/vj3pc8b',
  ];
  const unclaimed = [
    'https://app.pangea.chat/auth.html',
    'https://app.pangea.chat/auth.html?return=https%3A%2F%2Fapp.pangea.chat%2Fhome%2Fsignup&loginToken=x',
    'https://app.staging.pangea.chat/auth.html',
    'https://app.pangea.chat/home',
    'https://app.pangea.chat/home/login',
    'https://app.pangea.chat/home/login/email',
    'https://app.pangea.chat/home/signup',
    'https://app.pangea.chat/home/signup/email',
    'https://matrix.pangea.chat/vj3pc8b',
  ];

  for (final url in claimed) {
    test('claims $url', () => expect(filter.claims(Uri.parse(url)), isTrue));
  }
  for (final url in unclaimed) {
    test('leaves $url to the browser', () {
      expect(filter.claims(Uri.parse(url)), isFalse);
    });
  }
}

/// The autoVerify https intent filter, matched the way Android matches it:
/// any listed host, and the path against any `path`, `pathPrefix` or
/// `pathPattern` (a simple glob: `.` is any character, `*` repeats the one
/// before it).
class _AppLinksFilter {
  final Set<String> hosts;
  final List<bool Function(String)> paths;

  _AppLinksFilter(this.hosts, this.paths);

  factory _AppLinksFilter.load() {
    final manifest = XmlDocument.parse(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
    );
    final filter = manifest
        .findAllElements('intent-filter')
        .singleWhere((e) => e.getAttribute('android:autoVerify') == 'true');
    final data = filter.findElements('data');
    return _AppLinksFilter(
      {for (final d in data) ?d.getAttribute('android:host')},
      [
        for (final d in data) ...[
          if (d.getAttribute('android:path') case final p?) (s) => s == p,
          if (d.getAttribute('android:pathPrefix') case final p?)
            (s) => s.startsWith(p),
          if (d.getAttribute('android:pathPattern') case final p?)
            _globToRegExp(p).hasMatch,
        ],
      ],
    );
  }

  bool claims(Uri uri) =>
      uri.scheme == 'https' &&
      hosts.contains(uri.host) &&
      // A filter with no path data claims every path.
      (paths.isEmpty ||
          paths.any((matches) => matches(Uri.decodeFull(uri.path))));

  static RegExp _globToRegExp(String glob) {
    final pattern = StringBuffer('^');
    for (var i = 0; i < glob.length; i++) {
      final c = glob[i];
      if (c == '\\' && i + 1 < glob.length) {
        pattern.write(RegExp.escape(glob[++i]));
      } else if (c == '.') {
        pattern.write('.');
      } else if (c == '*') {
        pattern.write('*');
      } else {
        pattern.write(RegExp.escape(c));
      }
    }
    pattern.write(r'$');
    return RegExp(pattern.toString());
  }
}
