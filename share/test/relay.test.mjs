// End-to-end checks against a running relay: BASE=http://127.0.0.1:8799 node --test test/
import test from 'node:test';
import assert from 'node:assert/strict';
const BASE = process.env.BASE || 'http://127.0.0.1:8799';
const rid = () => Buffer.from(crypto.getRandomValues(new Uint8Array(16))).toString('base64url');
const tok = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64url');
const call = (id, method, body, token = tok) =>
  fetch(`${BASE}/api/s/${id}`, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

test('full share lifecycle', async () => {
  const id = rid();
  assert.equal((await call(id, 'GET', null, null)).status, 404);
  let r = await call(id, 'POST', { until: Date.now() + 3600e3, lat: 23.78, lng: 90.394, acc: 5, mode: 'atWork', heading: 90, speed: 0, moving: false });
  assert.equal(r.status, 200);
  r = await call(id, 'GET', null, null);
  const g = await r.json();
  assert.equal(g.status, 'live');
  assert.equal(g.state.mode, 'atWork');
  assert.equal(g.state.lat, 23.78);
  assert.equal(r.headers.get('cache-control'), 'no-store');
  // wrong token cannot write or stop
  const bad = 'x'.repeat(43);
  assert.equal((await call(id, 'POST', { lat: 1, lng: 1 }, bad)).status, 403);
  assert.equal((await call(id, 'DELETE', null, bad)).status, 403);
  assert.equal((await call(id, 'POST', { lat: 1, lng: 1 }, null)).status, 401);
  // too fast
  assert.equal((await call(id, 'POST', { lat: 23.781, lng: 90.394 })).status, 429);
  await wait(1600);
  r = await call(id, 'POST', { lat: 23.781, lng: 90.3941, mode: 'walking', moving: true, speed: 1.3 });
  assert.equal(r.status, 200);
  assert.equal((await (await call(id, 'GET', null, null)).json()).state.mode, 'walking');
  // junk mode / coords
  await wait(1600);
  await call(id, 'POST', { lat: 999, lng: 1, mode: 'hacker' });
  assert.equal((await (await call(id, 'GET', null, null)).json()).state.lat, 23.781);
  // stop → ended, position gone, can't restart
  assert.equal((await call(id, 'DELETE')).status, 200);
  r = await call(id, 'GET', null, null);
  assert.equal(r.status, 410);
  assert.equal((await r.json()).state, undefined);
  await wait(1600);
  assert.equal((await call(id, 'POST', { lat: 1, lng: 1 })).status, 410);
});

test('bad ids and routes', async () => {
  assert.equal((await fetch(`${BASE}/api/s/short`)).status, 400);
  assert.equal((await fetch(`${BASE}/api/other`)).status, 404);
  assert.equal((await call(rid(), 'PUT', {})).status, 405);
});

test('share length is capped at 24 h', async () => {
  const id = rid();
  const r = await call(id, 'POST', { until: Date.now() + 9e9 });
  const { until } = await r.json();
  assert.ok(until <= Date.now() + 24 * 3600e3 + 1000);
});

test('viewer page is served for share links', async () => {
  const r = await fetch(`${BASE}/s/${rid()}`, { headers: { 'sec-fetch-mode': 'navigate', accept: 'text/html' } });
  assert.equal(r.status, 200);
  assert.match(await r.text(), /<html|<!doctype/i);
});
