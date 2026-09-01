const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const {setGlobalOptions} = require("firebase-functions/v2");
const {HttpsError, onCall} = require("firebase-functions/v2/https");

initializeApp();

setGlobalOptions({
  region: "us-central1",
  maxInstances: 2,
});

/**
 * Permanently removes the calling user's Trackmark cloud data and Firebase
 * Authentication identity. Firestore's recursive delete is required because
 * authoritative backup restores can leave multiple nested generations under
 * the user document that a client SDK cannot enumerate safely.
 */
async function deleteTrackmarkAccountData({uid, firestore, auth}) {
  await firestore.recursiveDelete(firestore.collection("users").doc(uid));
  await auth.deleteUser(uid);
}

exports.deleteTrackmarkAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
        "unauthenticated",
        "Sign in again before deleting your Trackmark account.",
    );
  }

  await deleteTrackmarkAccountData({
    uid,
    firestore: getFirestore(),
    auth: getAuth(),
  });

  return {deleted: true};
});

exports.deleteTrackmarkAccountData = deleteTrackmarkAccountData;
