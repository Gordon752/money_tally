const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {setGlobalOptions} = require("firebase-functions/v2");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const {inspectPendingDeletions} = require("./deletion_monitor");

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
  // Outside users/{uid}: recursive cleanup must not remove the access barrier.
  // This minimal server-only marker also survives expired/revoked client tokens.
  const marker = firestore.collection("accountDeletions").doc(uid);
  const request = await marker.get();
  if (!request.exists) throw new Error("Account deletion was not requested.");
  if (request.data()?.status === "completed") return;
  await firestore.recursiveDelete(firestore.collection("users").doc(uid));
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
  await marker.set({status: "completed", completedAt: FieldValue.serverTimestamp()},
      {merge: true});
}

async function requestAccountDeletion({uid, authTime, firestore, auth, now = Date.now()}) {
  const marker = firestore.collection("accountDeletions").doc(uid);
  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(marker);
    if (existing.exists) return; // Safe retry of the same irreversible request.
    if (!Number.isFinite(authTime) || now / 1000 - authTime > 300 ||
        authTime > now / 1000 + 60) {
      throw new HttpsError("failed-precondition", "Sign in again to confirm account deletion.");
    }
    transaction.create(marker, {
      status: "pending", requestedAt: FieldValue.serverTimestamp(),
    });
  });
  await deleteTrackmarkAccountData({uid, firestore, auth});
}

exports.deleteTrackmarkAccount = onCall({timeoutSeconds: 540}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError(
        "unauthenticated",
        "Sign in again before deleting your Trackmark account.",
    );
  }

  await requestAccountDeletion({
    uid,
    authTime: request.auth.token.auth_time,
    firestore: getFirestore(),
    auth: getAuth(),
  });

  return {deleted: true};
});

// Durable recovery if the caller disconnects, times out, or cleanup partially
// fails. Duplicate delivery/callable execution is safe: the barrier never opens.
exports.resumeTrackmarkAccountDeletion = onDocumentCreated({
  document: "accountDeletions/{uid}", retry: true, timeoutSeconds: 540,
}, async (event) => {
  await deleteTrackmarkAccountData({
    uid: event.params.uid, firestore: getFirestore(), auth: getAuth(),
  });
});

exports.deleteTrackmarkAccountData = deleteTrackmarkAccountData;
exports.requestAccountDeletion = requestAccountDeletion;

exports.monitorTrackmarkAccountDeletions = onSchedule({
  schedule: "every 30 minutes", timeZone: "Etc/UTC",
  timeoutSeconds: 60, maxInstances: 1, memory: "256MiB",
  retryCount: 1,
}, async () => {
  try {
    const result = await inspectPendingDeletions({firestore: getFirestore()});
    const log = result.needsAttention ? logger.error : logger.info;
    log("Trackmark account deletion health check", {
      event: result.needsAttention ? "deletion_attention_required" : "deletion_monitor_ok",
      ...result,
    });
  } catch {
    logger.error("Trackmark deletion status check failed", {event: "deletion_monitor_failed"});
    // Retry without exposing query contents or identifiers in an exception.
    throw new Error("Unable to check account deletion status.");
  }
});
