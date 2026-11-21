// GoliCat live share relay.
// One Durable Object per share keeps ONLY the latest position (no history).
// The phone writes with a secret token; anyone with the link can read.
// Everything is deleted when the share is stopped or expires.

const ID_RE = /^[A-Za-z0-9_-]{22}$/;
const MAX_SHARE_MS = 24 * 3600 * 1000;
const MIN_WRITE_GAP_MS = 1500;
const MODES = new Set(['starting', 'idle', 'waiting', 'walking', 'fast', 'lost', 'atWork', 'atHome', 'studying', 'hangingOut', 'jammed']);

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    },
  });

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    const path = url.pathname;
    if (path === '/') return Response.redirect(new URL('/get/', url), 302);

    // Download page + APKs: serve the file, count it on the side.
    if (path.startsWith('/get/')) {
      const res = await env.ASSETS.fetch(req);
      const hit = countable(req, res, path);
      if (hit) ctx.waitUntil(record(env, req, hit).catch(() => {}));
      return res;
    }

    // Private download dashboard: the page itself holds no data; the numbers
    // need the dashboard password.
    if (path === '/stats') return Response.redirect(new URL('/stats/', url), 301);
    if (path === '/stats/api') {
      if (!(await authorized(req, env))) return json({ error: 'auth' }, 401);
      const stub = env.STATS.get(env.STATS.idFromName('global'));
      return stub.fetch(new Request('https://stats/report' + url.search));
    }
    if (path.startsWith('/stats/')) {
      // Ask for "/stats/" itself: asking for index.html gets a redirect back here.
      const res = await env.ASSETS.fetch(new Request(new URL('/stats/', url), req));
      const h = new Headers(res.headers);
      h.set('x-robots-tag', 'noindex, nofollow');
      h.set('cache-control', 'no-store');
      return new Response(res.body, { status: res.status, headers: h });
    }

    // Public download counts for the download page: totals, last 30 days,
    // countries. Nothing per person. Cached for a minute at the edge.
    if (path === '/api/downloads' && req.method === 'GET') {
      const stub = env.STATS.get(env.STATS.idFromName('global'));
      const r = await (await stub.fetch('https://stats/report?days=30')).json();
      const res = json({
        since: r.counting_since,
        total: r.totals.all.downloads.n,
        today: r.totals.today.downloads.n,
        last7: r.totals.last7.downloads.n,
        days: r.days.map((d) => ({ day: d.day, n: d.downloads })),
        countries: r.countries.filter((c) => c.downloads > 0).map((c) => ({ country: c.country, n: c.downloads })),
      });
      res.headers.set('cache-control', 'public, max-age=60');
      return res;
    }

    const m = path.match(/^\/api\/s\/([^/]+)$/);
    if (!m) return json({ error: 'not_found' }, 404);
    const id = m[1];
    if (!ID_RE.test(id)) return json({ error: 'bad_id' }, 400);
    if (!['GET', 'POST', 'DELETE'].includes(req.method)) return json({ error: 'method' }, 405);
    const stub = env.SHARES.get(env.SHARES.idFromName(id));
    return stub.fetch(req);
  },
};

// ---- download counting ------------------------------------------------------

const BOT_RE = /bot|crawl|spider|slurp|preview|facebookexternalhit|whatsapp|telegram|discord|skype|curl|wget|python|node-fetch|axios|headless|lighthouse|monitor/i;
const APK_RE = /^\/get\/golicat-(\d+\.\d+\.\d+)-(arm64|armv7)\.apk$/;

/** What this request counts as ({kind: 'download' | 'visit'}), or null. */
function countable(req, res, path) {
  if (req.method !== 'GET' || (res.status !== 200 && res.status !== 206)) return null;
  // Our own checks send this header so they never show up in the numbers.
  if (req.headers.get('x-golicat-nocount')) return null;
  if (BOT_RE.test(req.headers.get('user-agent') || '')) return null;
  const apk = path.match(APK_RE);
  if (apk) {
    // Download managers fetch big files in pieces: count only the first piece.
    const range = req.headers.get('range');
    if (range && !/^bytes=0-/.test(range)) return null;
    return { kind: 'download', version: apk[1], abi: apk[2] };
  }
  if (path === '/get/' || path === '/get/index.html') return { kind: 'visit' };
  return null;
}

/** Dhaka calendar day, e.g. 2026-11-21. */
const dhakaDay = (ms = Date.now()) => new Date(ms + 6 * 3600 * 1000).toISOString().slice(0, 10);

async function record(env, req, hit) {
  const day = dhakaDay();
  const country = (req.cf && req.cf.country) || 'XX';
  // A same-day "seen before" code: one-way and salted per day, so it can't be
  // turned back into an IP or linked across days. The IP itself is never stored.
  const ip = req.headers.get('cf-connecting-ip') || '';
  const ua = req.headers.get('user-agent') || '';
  const h = (await sha256(`${env.STATS_SALT || 'golicat'}|${day}|${ip}|${ua}`)).slice(0, 20);
  const stub = env.STATS.get(env.STATS.idFromName('global'));
  await stub.fetch('https://stats/record', { method: 'POST', body: JSON.stringify({ ...hit, day, country, h }) });
}

async function authorized(req, env) {
  const want = env.STATS_PASSWORD;
  if (!want) return false;
  const auth = req.headers.get('authorization') || '';
  const got = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!got) return false;
  // Compare digests so every wrong guess takes the same time.
  const [a, b] = await Promise.all([sha256(got), sha256(want)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function sha256(text) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function cleanState(b) {
  const num = (v, lo, hi) => (typeof v === 'number' && Number.isFinite(v) && v >= lo && v <= hi ? v : null);
  const lat = num(b.lat, -90, 90), lng = num(b.lng, -180, 180);
  if (lat === null || lng === null) return null;
  return {
    lat: Math.round(lat * 1e6) / 1e6,
    lng: Math.round(lng * 1e6) / 1e6,
    acc: num(b.acc, 0, 10000) ?? 0,
    heading: num(b.heading, -360, 720) ?? 0,
    speed: num(b.speed, 0, 200) ?? 0,
    moving: b.moving === true,
    mode: MODES.has(b.mode) ? b.mode : 'idle',
    // Avatar id (a short lowercase word); anything else is dropped.
    ...(typeof b.skin === 'string' && /^[a-z]{1,24}$/.test(b.skin) ? { skin: b.skin } : {}),
    ts: Date.now(),
  };
}

export class Share {
  constructor(ctx) {
    this.ctx = ctx;
  }

  async fetch(req) {
    const st = this.ctx.storage;
    const now = Date.now();
    const meta = await st.get('meta'); // {hash, until, ended}
    if (meta && now > meta.until) {
      await st.deleteAll();
      return json({ status: 'ended' }, 410);
    }

    if (req.method === 'GET') {
      if (!meta) return json({ status: 'unknown' }, 404);
      if (meta.ended) return json({ status: 'ended' }, 410);
      const state = (await st.get('state')) ?? null;
      return json({ status: 'live', until: meta.until, now, state });
    }

    const auth = req.headers.get('authorization') || '';
    const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
    if (token.length < 32 || token.length > 128) return json({ error: 'auth' }, 401);
    const hash = await sha256(token);
    if (meta && meta.hash !== hash) return json({ error: 'auth' }, 403);

    if (req.method === 'DELETE') {
      if (!meta) return json({ status: 'ended' });
      // Keep only a tombstone (no position) so viewers see "ended" until it expires.
      await st.delete('state');
      await st.put('meta', { ...meta, ended: true });
      return json({ status: 'ended' });
    }

    // POST: create (first write) or update.
    if (meta?.ended) return json({ status: 'ended' }, 410);
    const text = await req.text();
    if (text.length > 2048) return json({ error: 'too_big' }, 413);
    let body;
    try {
      body = JSON.parse(text);
    } catch {
      return json({ error: 'bad_json' }, 400);
    }
    if (meta && now - (meta.lastWrite ?? 0) < MIN_WRITE_GAP_MS) return json({ error: 'slow_down' }, 429);

    const wantUntil = typeof body.until === 'number' ? body.until : now + 3600 * 1000;
    const until = Math.min(Math.max(wantUntil, now + 60 * 1000), now + MAX_SHARE_MS);
    // Position pushes carry no `until`: they must not extend the share the user chose.
    const newMeta = meta
      ? { ...meta, lastWrite: now, ...(typeof body.until === 'number' ? { until: Math.min(until, meta.created + MAX_SHARE_MS) } : {}) }
      : { hash, until, created: now, lastWrite: now, ended: false };
    await st.put('meta', newMeta);
    const state = body.lat === undefined ? null : cleanState(body);
    if (state) await st.put('state', state);
    // Wipe everything an hour after the share expires.
    await st.setAlarm(newMeta.until + 3600 * 1000);
    return json({ status: 'live', until: newMeta.until });
  }

  async alarm() {
    await this.ctx.storage.deleteAll();
  }
}

// ---- download statistics (one global Durable Object, SQLite) ------------------
// Keeps daily totals per kind / version / phone type / country. No IPs, no
// device IDs. The one-day "seen" codes (for unique counts) go after 90 days.

const KEEP_SEEN_DAYS = 90;

export class Stats {
  constructor(ctx) {
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS hits (
        day TEXT NOT NULL, kind TEXT NOT NULL, version TEXT NOT NULL, abi TEXT NOT NULL,
        country TEXT NOT NULL, n INTEGER NOT NULL, uniq INTEGER NOT NULL,
        PRIMARY KEY (day, kind, version, abi, country));
      CREATE TABLE IF NOT EXISTS seen (
        day TEXT NOT NULL, kind TEXT NOT NULL, h TEXT NOT NULL,
        PRIMARY KEY (day, kind, h));`);
  }

  async fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === '/record' && req.method === 'POST') return this.record(await req.json());
    if (url.pathname === '/report') return json(this.report(url.searchParams.get('days')));
    return json({ error: 'not_found' }, 404);
  }

  record(b) {
    const kind = b.kind === 'download' ? 'download' : 'visit';
    const day = /^\d{4}-\d{2}-\d{2}$/.test(b.day) ? b.day : dhakaDay();
    const version = kind === 'download' && /^\d+\.\d+\.\d+$/.test(b.version) ? b.version : '';
    const abi = kind === 'download' && (b.abi === 'arm64' || b.abi === 'armv7') ? b.abi : '';
    const country = /^[A-Z]{2}$/.test(b.country) ? b.country : 'XX';
    const h = String(b.h || '').slice(0, 20);
    let fresh = 0;
    if (h && !this.sql.exec('SELECT 1 FROM seen WHERE day=? AND kind=? AND h=?', day, kind, h).toArray().length) {
      this.sql.exec('INSERT INTO seen (day, kind, h) VALUES (?, ?, ?)', day, kind, h);
      fresh = 1;
    }
    this.sql.exec(
      `INSERT INTO hits (day, kind, version, abi, country, n, uniq) VALUES (?, ?, ?, ?, ?, 1, ?)
       ON CONFLICT (day, kind, version, abi, country) DO UPDATE SET n = n + 1, uniq = uniq + excluded.uniq`,
      day, kind, version, abi, country, fresh);
    this.sql.exec('DELETE FROM seen WHERE day < ?', dhakaDay(Date.now() - KEEP_SEEN_DAYS * 86400e3));
    return json({ ok: true });
  }

  report(daysParam) {
    const days = Math.min(Math.max(parseInt(daysParam || '30', 10) || 30, 7), 365);
    const now = Date.now();
    const today = dhakaDay(now);
    const from = dhakaDay(now - (days - 1) * 86400e3);
    const q = (text, ...args) => this.sql.exec(text, ...args).toArray();
    const sum = (kind, since) =>
      q('SELECT COALESCE(SUM(n),0) AS n, COALESCE(SUM(uniq),0) AS u FROM hits WHERE kind=? AND day>=?', kind, since)[0];

    const byDay = {};
    for (let i = days - 1; i >= 0; i--) byDay[dhakaDay(now - i * 86400e3)] = { downloads: 0, people: 0, visits: 0 };
    for (const r of q('SELECT day, kind, SUM(n) AS n, SUM(uniq) AS u FROM hits WHERE day>=? GROUP BY day, kind', from)) {
      const d = byDay[r.day];
      if (!d) continue;
      if (r.kind === 'download') {
        d.downloads = r.n;
        d.people = r.u;
      } else d.visits = r.n;
    }

    return {
      today,
      counting_since: q('SELECT MIN(day) AS d FROM hits')[0].d,
      range_days: days,
      totals: {
        all: { downloads: sum('download', '0000'), visits: sum('visit', '0000') },
        today: { downloads: sum('download', today), visits: sum('visit', today) },
        last7: { downloads: sum('download', dhakaDay(now - 6 * 86400e3)), visits: sum('visit', dhakaDay(now - 6 * 86400e3)) },
        range: { downloads: sum('download', from), visits: sum('visit', from) },
      },
      days: Object.entries(byDay).map(([day, v]) => ({ day, ...v })),
      countries: q(
        `SELECT country, SUM(CASE WHEN kind='download' THEN n ELSE 0 END) AS downloads,
                SUM(CASE WHEN kind='visit' THEN n ELSE 0 END) AS visits
         FROM hits WHERE day>=? GROUP BY country ORDER BY downloads DESC, visits DESC`, from),
      versions: q(
        `SELECT version, abi, SUM(n) AS downloads FROM hits WHERE kind='download' AND day>=?
         GROUP BY version, abi ORDER BY version DESC, abi`, from),
    };
  }
}
