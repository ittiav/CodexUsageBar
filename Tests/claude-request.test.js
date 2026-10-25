const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '..', 'ClaudeUsageClient.swift'), 'utf8');
const script = source.match(/static let requestScript = #"""\n([\s\S]*?)\n    """#/)[1];
const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
const execute = new AsyncFunction('fetch', 'selectedOrganization', 'location', script);
const one = '11111111-1111-4111-8111-111111111111';
const two = '22222222-2222-4222-8222-222222222222';
const orgs = [{uuid: one, name: 'Test account'}, {uuid: two, name: 'Other test account'}];
function response(data, status = 200, extra = {}) {
  return {ok: status >= 200 && status < 300, status,
    headers: {get: key => ({'Content-Type': 'application/json', ...extra})[key] || null},
    json: async () => data};
}
async function run(responses, selected = '') {
  const calls = [];
  const result = await execute(async (url, options) => {
    assert.equal(options.credentials, 'same-origin');
    assert.equal(options.cache, 'no-store');
    assert.equal(options.redirect, 'error');
    assert.ok(url.startsWith('/api/organizations'));
    calls.push(url);
    assert.ok(responses.length, 'Unexpected extra request');
    return responses.shift();
  }, selected, {origin: 'https://claude.ai'});
  return {result, calls};
}
(async () => {
  let r = await run([response([orgs[0]]), response({five_hour: {utilization: 25, private_field: 'omit'}, email: 'omit', extra_usage: {used_credits: 42}})]);
  assert.equal(r.result.kind, 'usage'); assert.equal(r.result.data.five_hour.utilization, 25);
  assert.equal(r.result.data.extra_usage, undefined);
  assert.equal(r.result.data.email, undefined);
  assert.equal(r.result.data.five_hour.private_field, undefined);
  assert.equal(r.calls[1], '/api/organizations/' + one + '/usage');
  r = await run([response(orgs)]);
  assert.equal(r.result.kind, 'choose'); assert.equal(r.calls.length, 1);
  r = await run([response(orgs), response({seven_day: {utilization: 50}})], two);
  assert.equal(r.result.organization, two);
  r = await run([response({}, 401)]);
  assert.equal(r.result.status, 401); assert.equal(r.calls.length, 1);
  r = await run([response({}, 429, {'Retry-After': '600'})]);
  assert.equal(r.result.retryAfter, 600); assert.equal(r.calls.length, 1);
  r = await run([response('login page', 200, {'Content-Type': 'text/html'})]);
  assert.equal(r.result.status, 401);
  r = await run([response([{uuid: '../../not-an-organization'}])]);
  assert.equal(r.result.status, 401); assert.equal(r.calls.length, 1);
  r = await run([response({unexpected: []})]);
  assert.equal(r.result.kind, 'invalid');
  r = await run([response([orgs[0]])], two);
  assert.equal(r.result.kind, 'choose'); assert.equal(r.calls.length, 1);
  const wrongOrigin = await execute(() => { throw Error('Must not fetch off-origin'); }, '', {origin: 'https://example.com'});
  assert.equal(wrongOrigin.kind, 'invalid');
  console.log('10 Claude request scenarios passed (including origin, redirects, workspace changes, and data minimization)');
})().catch(error => { console.error(error); process.exitCode = 1; });
