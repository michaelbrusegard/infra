// SPDX-License-Identifier: AGPL-3.0-only
// Run from the pinned WebUI source with its existing npm dependencies installed.
const assert = require('node:assert/strict');
const { webcrypto } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { createRequire } = require('node:module');
const { resolve } = require('node:path');
const vm = require('node:vm');

const sourceRequire = createRequire(resolve('package.json'));
const ts = sourceRequire('typescript');
const origin = 'https://mail.example.test';

async function checkFlow(name, protectedResources, expectedResource) {
  const storage = new Map([['stalwart-oauth-resource', 'https://stale.example.test']]);
  const requests = [];
  const discovery = {
    authorization_endpoint: 'https://id.example.test/authorize',
    token_endpoint: 'https://id.example.test/token',
    stalwart_required_scopes: ['openid', 'email', 'profile', 'groups'],
    ...(protectedResources === undefined ? {} : { protected_resources: protectedResources }),
  };
  const context = vm.createContext({
    URL, URLSearchParams, TextEncoder, Headers, Response, AbortController,
    crypto: webcrypto, btoa, console, setTimeout, clearTimeout,
    window: { location: { origin, pathname: '/admin/login', search: '' } },
    document: {
      querySelector(selector) {
        const content = {
          base: '/admin/',
          'meta[name="oauth-client-id"]': 'stalwart',
          'meta[name="oauth-scopes"]': 'groups',
        }[selector];
        return content === undefined ? null : { getAttribute: () => content };
      },
    },
    sessionStorage: {
      getItem: (key) => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, String(value)),
      removeItem: (key) => storage.delete(key),
    },
    async fetch(url, options) {
      if (url === `${origin}/api/discover/user%40example.test`) {
        return Response.json(discovery);
      }
      assert.equal(url, discovery.token_endpoint);
      assert.equal(options.method, 'POST');
      requests.push(new URLSearchParams(options.body));
      return Response.json({ access_token: 'fixture-access', refresh_token: 'fixture-refresh', expires_in: 3600 });
    },
  });
  const modules = new Map();
  function load(id) {
    if (id === '@/i18n') return { default: { t: (_key, fallback) => fallback }, __esModule: true };
    if (!id.startsWith('@/')) return sourceRequire(id);
    if (modules.has(id)) return modules.get(id).exports;
    const path = resolve('src', `${id.slice(2)}.ts`);
    // Vite supplies these build-time values in production. Keep them unset here.
    const source = readFileSync(path, 'utf8').replaceAll('import.meta.env', '({})');
    const { outputText } = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, esModuleInterop: true },
    });
    const module = { exports: {} };
    modules.set(id, module);
    vm.runInContext(`(function(require, module, exports) {${outputText}\n})`, context, { filename: path })(load, module, module.exports);
    return module.exports;
  }

  const oauth = load('@/services/auth/oauth');
  await oauth.startAuthFlow('user@example.test');
  const authorization = new URL(context.window.location.href);
  assert.equal(authorization.searchParams.get('resource'), expectedResource, `${name}: authorization resource`);
  assert.equal(authorization.searchParams.get('scope'), 'openid email profile groups');
  assert.equal(authorization.searchParams.get('client_id'), 'stalwart');
  assert.equal(authorization.searchParams.get('redirect_uri'), `${origin}/admin/oauth/callback`);
  assert.equal(authorization.searchParams.get('code_challenge_method'), 'S256');

  const stored = oauth.getStoredOAuthData();
  assert.equal(stored.resource, expectedResource, `${name}: stored resource`);
  assert.equal(stored.state, authorization.searchParams.get('state'));
  const tokens = await oauth.exchangeCode('fixture-code', stored.codeVerifier, stored.tokenEndpoint,
    oauth.getOAuthRedirectUri(), stored.clientId, stored.resource);
  const store = load('@/stores/authStore').useAuthStore;
  store.getState().setTokens(tokens.access_token, tokens.refresh_token, tokens.expires_in,
    stored.tokenEndpoint, stored.endSessionEndpoint, stored.clientId, stored.resource);
  await load('@/services/api').refreshAccessToken();
  assert.equal(requests.length, 2);
  assert.equal(requests[0].get('grant_type'), 'authorization_code');
  assert.equal(requests[1].get('grant_type'), 'refresh_token');
  for (const request of requests) {
    assert.equal(request.get('resource'), expectedResource, `${name}: token resource`);
    assert.equal(request.get('client_id'), 'stalwart');
  }
  console.log(`PASS ${name}: authorization, code exchange, refresh`);
}

(async () => {
  await checkFlow('Pocket ID without resource metadata', undefined, null);
  await checkFlow('Stalwart with matching resource', [origin, 'mail.example.test'], origin);
  await checkFlow('Empty resource list', [], null);
  await checkFlow('Different resource', ['https://other.example.test'], null);
})().catch((error) => { console.error(error); process.exitCode = 1; });
