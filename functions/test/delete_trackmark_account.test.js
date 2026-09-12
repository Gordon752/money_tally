const assert = require("node:assert/strict");
const test = require("node:test");
const {deleteTrackmarkAccountData, requestAccountDeletion} = require("../index");

function fixture(initial) {
  let marker = initial;
  const calls = [];
  const failures = {};
  const reference = {
    path: "accountDeletions/test-user",
    async get() {
      return {exists: marker !== undefined, data: () => marker};
    },
    async set(value) {
      if (failures.complete) throw failures.complete;
      calls.push("completed");
      marker = {...marker, ...value};
    },
  };
  const firestore = {
    collection(name) {
      return {doc(uid) {
        assert.equal(uid, "test-user");
        if (name === "accountDeletions") return reference;
        assert.equal(name, "users");
        return {path: "users/test-user"};
      }};
    },
    async runTransaction(callback) {
      let staged;
      await callback({
        get: (ref) => ref.get(),
        create(ref, value) {
          assert.equal(ref, reference);
          assert.equal(marker, undefined);
          staged = value;
        },
      });
      if (failures.commit) throw failures.commit;
      if (staged) {
        marker = staged;
        calls.push("barrier");
      }
    },
    async recursiveDelete(ref) {
      assert.equal(ref.path, "users/test-user");
      assert.equal(marker.status, "pending");
      calls.push("data");
      if (failures.data) throw failures.data;
    },
  };
  const auth = {async deleteUser(uid) {
    assert.equal(uid, "test-user");
    calls.push("auth");
    if (failures.auth) throw failures.auth;
  }};
  return {
    calls, failures, state: () => marker,
    clean: () => deleteTrackmarkAccountData({uid: "test-user", firestore, auth}),
    request: (authTime = 1000) => requestAccountDeletion({
      uid: "test-user", firestore, auth, authTime, now: 1000000,
    }),
  };
}

test("commits the barrier before deleting data, then identity, then completion", async () => {
  const f = fixture();
  await f.request();
  assert.deepEqual(f.calls, ["barrier", "data", "auth", "completed"]);
  assert.equal(f.state().status, "completed");
});

test("cleanup refuses to run without a durable request", async () => {
  const f = fixture();
  await assert.rejects(f.clean(), /not requested/);
  assert.deepEqual(f.calls, []);
});

test("failed barrier commit never starts destructive work", async () => {
  const f = fixture();
  f.failures.commit = new Error("commit failed");
  await assert.rejects(f.request(), /commit failed/);
  assert.equal(f.state(), undefined);
  assert.deepEqual(f.calls, []);
});

test("partial data failure retains the barrier and identity; retry completes", async () => {
  const f = fixture();
  f.failures.data = new Error("partial delete");
  await assert.rejects(f.request(), /partial delete/);
  assert.equal(f.state().status, "pending");
  assert.deepEqual(f.calls, ["barrier", "data"]);
  delete f.failures.data;
  await f.clean();
  assert.equal(f.state().status, "completed");
});

test("auth failure leaves request pending for the worker", async () => {
  const f = fixture({status: "pending"});
  f.failures.auth = new Error("auth unavailable");
  await assert.rejects(f.clean(), /auth unavailable/);
  assert.equal(f.state().status, "pending");
  delete f.failures.auth;
  await f.clean();
  assert.equal(f.state().status, "completed");
});

test("already-deleted identity is successful idempotent cleanup", async () => {
  const f = fixture({status: "pending"});
  f.failures.auth = {code: "auth/user-not-found"};
  await f.clean();
  assert.equal(f.state().status, "completed");
});

test("lost completion write can be retried after identity deletion", async () => {
  const f = fixture({status: "pending"});
  f.failures.complete = new Error("write unavailable");
  await assert.rejects(f.clean(), /write unavailable/);
  assert.equal(f.state().status, "pending");
  delete f.failures.complete;
  f.failures.auth = {code: "auth/user-not-found"};
  await f.clean();
  assert.equal(f.state().status, "completed");
});

test("duplicate completed requests do not repeat destructive work", async () => {
  const f = fixture({status: "completed"});
  await f.request(0);
  await f.clean();
  assert.deepEqual(f.calls, []);
});

test("existing pending request can resume without fresh reauthentication", async () => {
  const f = fixture({status: "pending"});
  await f.request(0);
  assert.equal(f.state().status, "completed");
});

for (const authTime of [undefined, NaN, 0, 699, 1061]) {
  test(`new deletion requires recent authentication (${authTime})`, async () => {
    const f = fixture();
    // undefined bypasses the fixture default to exercise a missing token claim.
    const value = authTime === undefined ? null : authTime;
    await assert.rejects(f.request(value), {code: "failed-precondition"});
    assert.equal(f.state(), undefined);
    assert.deepEqual(f.calls, []);
  });
}
