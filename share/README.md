# GoliCat live share (relay + web viewer)

Live at **https://golicat.yeasinfiyaz.workers.dev** on the **yeasinfiyaz@gmail.com**
Cloudflare account (free plan). It's a personal project, kept separate from the NRF account.

- `src/worker.js` is a Worker plus one Durable Object per share. It keeps only the
  latest position and mode, never a history. The phone writes with a secret token
  (only its SHA-256 is stored). Anyone with the link can read it. Shares last at
  most 24 h. Stopping a share deletes the position, and an alarm wipes everything
  1 h after expiry.
- The viewer is the Flutter web build of `lib/viewer_main.dart` (same cat code as
  the app), served as static assets. `/s/<id>` falls back to the single-page app,
  and `/api/*` runs the Worker.

## Deploy

Always use `./deploy.sh`. It keeps GoliCat's own wrangler login in
`share/.wrangler-home` (git-ignored), so the global (NRF) login is never touched.

```
flutter build web -t lib/viewer_main.dart --release   # from the project root
find build/web -name "*.map" -delete
cd share && ./deploy.sh whoami    # must say yeasinfiyaz@gmail.com
./deploy.sh deploy
BASE=https://golicat.yeasinfiyaz.workers.dev npm test   # live end-to-end checks
```

If the login has expired: `./deploy.sh login --browser=false`, then open the link in a
Chrome **Incognito** window and allow access within about 2 minutes.
