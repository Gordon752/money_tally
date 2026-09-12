// Explicitly emulator-only: never accepts a production project or remote host.
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const host = process.env.FIRESTORE_EMULATOR_HOST;
assert.match(host || '', /^127\.0\.0\.1:\d+$/);
const project = 'demo-trackmark-deletion';
assert.equal(process.env.GCLOUD_PROJECT, project);
const root = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const uid = `deletion-${randomUUID()}`;
const other = `unaffected-${randomUUID()}`;
function token(user) {
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({alg: 'none', typ: 'JWT'})}.${encode({
    sub: user, user_id: user, aud: project,
    iss: `https://securetoken.google.com/${project}`, iat: now, exp: now + 3600,
    auth_time: now, firebase: {sign_in_provider: 'custom', identities: {}},
  })}.`;
}
const staleToken = token(uid);
async function request(path, method, bearer, value = 'test') {
  const headers = {'Content-Type': 'application/json'};
  if (bearer) headers.Authorization = `Bearer ${bearer}`;
  const response = await fetch(`${root}/${path}`, {
    method, headers,
    ...(method === 'PATCH' ? {body: JSON.stringify({fields: {
      value: {stringValue: value},
    }})} : {}),
  });
  const body = await response.text();
  return {status: response.status, body};
}
async function expectStatus(path, method, bearer, status) {
  const result = await request(path, method, bearer);
  assert.equal(result.status, status, `${method} ${path}: ${result.body}`);
}

async function main() {
  const collections = ['accounts', 'categories', 'transactions',
    'scheduledTransactions', 'budgets', 'goals', 'funds', 'reservationOperations',
    'goalContributions', 'goalFundingEvents', 'preferences'];
  const paths = [
    ...collections.map((name) => `users/${uid}/${name}/test`),
    ...collections.map((name) => `users/${uid}/restoreGenerations/old/${name}/test`),
    `users/${uid}/finance/legacy`,
    `users/${uid}/metadata/restoreAuthority`,
    `users/${uid}/metadata/syncClock`,
  ];
  for (const path of paths) {
    await expectStatus(path, 'PATCH', staleToken, 200);
    await expectStatus(path, 'GET', staleToken, 200);
    await expectStatus(path, 'GET', token(other), 403);
    await expectStatus(path, 'GET', null, 403);
  }
  const marker = `accountDeletions/${uid}`;
  await expectStatus(marker, 'PATCH', staleToken, 403);
  await expectStatus(marker, 'PATCH', 'owner', 200);
  // Same still-valid token, all known root and restored paths now denied.
  for (const path of paths) {
    await expectStatus(path, 'GET', staleToken, 403);
    await expectStatus(path, 'PATCH', staleToken, 403);
    await expectStatus(path, 'DELETE', staleToken, 403);
  }
  await expectStatus(marker, 'GET', staleToken, 403);
  await expectStatus(marker, 'DELETE', staleToken, 403);
  await expectStatus(marker, 'PATCH', staleToken, 403);
  // Removing the financial record cannot let the stale device recreate it.
  await expectStatus(paths[0], 'DELETE', 'owner', 200);
  await expectStatus(paths[0], 'PATCH', staleToken, 403);
  await expectStatus(`users/${other}/accounts/test`, 'PATCH', token(other), 200);
  await expectStatus(`users/${other}/accounts/test`, 'GET', token(other), 200);
  console.log(`PASS: ${paths.length} paths, stale-token read/write/delete barrier, ` +
    'marker protection, unauthenticated/cross-account isolation, unaffected user.');
}
main().catch((error) => {console.error(error); process.exitCode = 1;});
