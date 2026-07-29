import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_site_data_manager.dart';

void main() {
  const policy = BrowserSiteCookiePolicy();

  test('uses real parent domain and path from cookie metadata', () {
    final currentUri = Uri.parse('https://mail.google.com/mail/u/0/');

    final candidates = policy.deletionCandidates(
      currentUri: currentUri,
      cookies: <Cookie>[
        Cookie(
          name: 'SID',
          value: 'secret',
          domain: '.google.com',
          path: '/accounts',
        ),
      ],
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.url.host, 'mail.google.com');
    expect(candidates.single.domain, '.google.com');
    expect(candidates.single.path, '/accounts');
  });

  test('falls back to parent domains and current path hierarchy', () {
    final candidates = policy.deletionCandidates(
      currentUri: Uri.parse('https://mail.google.com/mail/u/0/'),
      cookies: <Cookie>[Cookie(name: 'SID', value: 'secret')],
    );

    expect(
      candidates,
      contains(
        isA<BrowserSiteCookieDeletion>()
            .having((item) => item.domain, 'domain', '.google.com')
            .having((item) => item.path, 'path', '/mail/u/0/'),
      ),
    );
    expect(
      candidates,
      contains(
        isA<BrowserSiteCookieDeletion>()
            .having((item) => item.domain, 'domain', isNull)
            .having((item) => item.path, 'path', '/'),
      ),
    );
  });

  test('uses cookie domain metadata to include recorded sibling origins', () {
    final currentUri = Uri.parse('https://mail.google.com/mail/u/0/');
    final siteDomains = policy.cookieSiteDomains(
      currentHost: currentUri.host,
      cookies: <Cookie>[
        Cookie(name: 'SID', value: 'secret', domain: '.google.com', path: '/'),
      ],
    );

    final related = policy.relatedOrigins(
      currentUri: currentUri,
      recordedOrigins: const <String>[
        'https://accounts.google.com',
        'https://calendar.google.com',
        'https://example.com',
      ],
      cookieSiteDomains: siteDomains,
    );

    expect(related.map((uri) => uri.host), contains('mail.google.com'));
    expect(related.map((uri) => uri.host), contains('accounts.google.com'));
    expect(related.map((uri) => uri.host), contains('calendar.google.com'));
    expect(related.map((uri) => uri.host), isNot(contains('example.com')));
  });
}
