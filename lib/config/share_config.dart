/// Where live-share links point. This is the GoliCat relay on the
/// yeasinfiyaz@gmail.com Cloudflare account (see share/README.md). Not a secret.
/// Test builds can point elsewhere with --dart-define=GOLICAT_BASE=...
const shareBaseUrl = String.fromEnvironment('GOLICAT_BASE', defaultValue: 'https://golicat.yeasinfiyaz.workers.dev');
