const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('typescript');

// Run the actual TypeScript handlers with injected boundaries. No deployment,
// credentials or network access are needed for these authorization tests.
function loadModule(file, { modules = {}, env = {}, fetch } = {}) {
  const filename = path.resolve(__dirname, '..', file);
  const source = ts.transpileModule(readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText;
  const exported = {};
  vm.runInNewContext(source, {
    exports: exported,
    process: { env },
    console: { warn() {} },
    fetch: fetch ?? (() => { throw new Error('Unexpected network access'); }),
    require(name) {
      if (Object.hasOwn(modules, name)) return modules[name];
      if (name === 'convex/values') return require(name);
      throw new Error(`Unexpected module: ${name}`);
    },
  }, { filename });
  return exported;
}

const TEST_KEY = 'test-only-not-a-credential';
const subscriber = (entitlement) => ({
  subscriber: { entitlements: entitlement === undefined ? {} : { pro: entitlement } },
});

for (const [name, entitlement, expected] of [
  ['active subscription', { expires_date: '2999-01-01T00:00:00Z' }, true],
  ['lifetime entitlement', { expires_date: null }, true],
  ['expired subscription', { expires_date: '2000-01-01T00:00:00Z' }, false],
  ['no entitlement', undefined, false],
  ['invalid expiration', { expires_date: 'invalid' }, false],
  ['missing expiration', {}, false],
]) {
  test(`RevenueCat: ${name}`, async () => {
    const { hasProEntitlement } = loadModule('convex/revenuecat.ts', {
      env: { REVENUECAT_API_KEY: TEST_KEY },
      fetch: async (url, options) => {
        assert.equal(url, 'https://api.revenuecat.com/v1/subscribers/user%2Fverified');
        assert.equal(options.headers.Authorization, `Bearer ${TEST_KEY}`);
        return { ok: true, json: async () => subscriber(entitlement) };
      },
    });
    assert.equal(await hasProEntitlement('user/verified'), expected);
  });
}

test('RevenueCat: missing server key denies without making a request', async () => {
  let requests = 0;
  const { hasProEntitlement } = loadModule('convex/revenuecat.ts', {
    fetch: async () => { requests++; throw new Error('Must not fetch'); },
  });
  assert.equal(await hasProEntitlement('user_verified'), false);
  assert.equal(requests, 0);
});

for (const status of [401, 403, 429, 500]) {
  test(`RevenueCat: upstream status ${status} denies access`, async () => {
    const { hasProEntitlement } = loadModule('convex/revenuecat.ts', {
      env: { REVENUECAT_API_KEY: TEST_KEY },
      fetch: async () => ({ ok: false, status }),
    });
    assert.equal(await hasProEntitlement('user_verified'), false);
  });
}

for (const [name, fetch] of [
  ['network failure', async () => { throw new Error('offline'); }],
  ['malformed JSON', async () => ({ ok: true, json: async () => { throw new Error('invalid JSON'); } })],
  ['unexpected response shape', async () => ({ ok: true, json: async () => ({}) })],
]) {
  test(`RevenueCat: ${name} denies access`, async () => {
    const { hasProEntitlement } = loadModule('convex/revenuecat.ts', {
      env: { REVENUECAT_API_KEY: TEST_KEY }, fetch,
    });
    assert.equal(await hasProEntitlement('user_verified'), false);
  });
}

function loadAction({ identity = { subject: 'user_verified' }, pro = true, allowed = true } = {}) {
  const checkedUsers = [];
  const rateKeys = [];
  let geminiRequests = 0;
  const { extract } = loadModule('convex/aiExtract.ts', {
    env: { GEMINI_API_KEY: TEST_KEY },
    modules: {
      './_generated/server': { action: (definition) => definition },
      './_generated/api': { internal: { rateLimit: { check: 'rateLimit:check' } } },
      './revenuecat': { hasProEntitlement: async (id) => { checkedUsers.push(id); return pro; } },
      './gemini': { callGemini: async () => { geminiRequests++; return '{"summary":"Test"}'; } },
    },
  });
  const ctx = {
    auth: { getUserIdentity: async () => identity },
    runMutation: async (_name, args) => { rateKeys.push(args.key); return { allowed }; },
  };
  const args = { url: 'https://example.com', title: 'Example', requestedFields: ['summary'], language: 'en' };
  return { extract, ctx, args, checkedUsers, rateKeys, geminiRequests: () => geminiRequests };
}

test('AI extraction denies unauthenticated callers before any upstream call', async () => {
  const action = loadAction({ identity: null });
  await assert.rejects(action.extract.handler(action.ctx, action.args), /Not authenticated/);
  assert.deepEqual(action.checkedUsers, []);
  assert.deepEqual(action.rateKeys, []);
  assert.equal(action.geminiRequests(), 0);
});

test('AI extraction checks only the verified identity, even with a forged subscriber ID', async () => {
  const action = loadAction();
  assert.equal(Object.hasOwn(action.extract.args, 'appUserId'), false);
  const result = await action.extract.handler(action.ctx, { ...action.args, appUserId: 'someone_else' });
  assert.deepEqual(action.checkedUsers, ['user_verified']);
  assert.deepEqual(action.rateKeys, ['user:user_verified']);
  assert.equal(action.geminiRequests(), 1);
  assert.equal(result, '{"summary":"Test"}');
});

test('AI extraction denies a verified user without Pro before calling Gemini', async () => {
  const action = loadAction({ pro: false });
  await assert.rejects(action.extract.handler(action.ctx, action.args), /Pro subscription required/);
  assert.equal(action.geminiRequests(), 0);
});

test('AI extraction denies rate-limited users before RevenueCat or Gemini', async () => {
  const action = loadAction({ allowed: false });
  await assert.rejects(action.extract.handler(action.ctx, action.args), /Rate limit exceeded/);
  assert.deepEqual(action.checkedUsers, []);
  assert.equal(action.geminiRequests(), 0);
});
