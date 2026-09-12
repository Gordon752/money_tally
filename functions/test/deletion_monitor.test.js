const test = require("node:test");
const assert = require("node:assert/strict");
const {inspectPendingDeletions} = require("../deletion_monitor");
const now = 1800000;

function fixture(ages) {
  const query = {
    where(...args) { assert.deepEqual(args, ["status", "==", "pending"]); return this; },
    select(...args) { assert.deepEqual(args, ["requestedAt"]); return this; },
    limit(n) { assert.equal(n, 501); return this; },
    async get() { return {docs: ages.map(age => ({data: () => ({
      requestedAt: age === null ? undefined : {toMillis: () => now - age * 60000},
    })}))}; },
  };
  return {collection(name) { assert.equal(name, "accountDeletions"); return query; }};
}

test("empty and recent deletions require no alert", async () => {
  for (const ages of [[], [0, 14.99]]) {
    const result = await inspectPendingDeletions({firestore: fixture(ages), now});
    assert.equal(result.needsAttention, false);
    assert.equal(result.pendingCount, ages.length);
  }
});
test("15-minute threshold and oldest age", async () => {
  const result = await inspectPendingDeletions({firestore: fixture([1, 15, 25.5]), now});
  assert.equal(result.needsAttention, true);
  assert.equal(result.staleCount, 2);
  assert.equal(result.oldestAgeMinutes, 25);
});
test("missing or future timestamps require investigation", async () => {
  const result = await inspectPendingDeletions({firestore: fixture([null, -1]), now});
  assert.equal(result.needsAttention, true);
  assert.equal(result.invalidTimestampCount, 2);
});
test("scan cap cannot silently hide old requests", async () => {
  const result = await inspectPendingDeletions({firestore: fixture(Array(501).fill(1)), now});
  assert.equal(result.needsAttention, true);
  assert.equal(result.scanLimitReached, true);
});
test("database errors propagate instead of reporting healthy", async () => {
  await assert.rejects(inspectPendingDeletions({firestore: {
    collection() { throw Error("unavailable"); },
  }, now}), /unavailable/);
});
