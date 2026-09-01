const assert = require("node:assert/strict");
const test = require("node:test");

const {deleteTrackmarkAccountData} = require("../index");

test("recursively deletes cloud data before deleting the auth user", async () => {
  const calls = [];
  const userReference = {path: "users/test-user"};
  const firestore = {
    collection(name) {
      assert.equal(name, "users");
      return {
        doc(uid) {
          assert.equal(uid, "test-user");
          return userReference;
        },
      };
    },
    async recursiveDelete(reference) {
      assert.equal(reference, userReference);
      calls.push("firestore");
    },
  };
  const auth = {
    async deleteUser(uid) {
      assert.equal(uid, "test-user");
      calls.push("auth");
    },
  };

  await deleteTrackmarkAccountData({
    uid: "test-user",
    firestore,
    auth,
  });

  assert.deepEqual(calls, ["firestore", "auth"]);
});

test("does not delete the auth user when recursive data deletion fails", async () => {
  let authDeleteCalled = false;
  const firestore = {
    collection() {
      return {doc: () => ({path: "users/test-user"})};
    },
    async recursiveDelete() {
      throw new Error("delete failed");
    },
  };
  const auth = {
    async deleteUser() {
      authDeleteCalled = true;
    },
  };

  await assert.rejects(
      deleteTrackmarkAccountData({
        uid: "test-user",
        firestore,
        auth,
      }),
      /delete failed/,
  );
  assert.equal(authDeleteCalled, false);
});
