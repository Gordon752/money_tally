// Read-only health check. Never log account identifiers or financial data.
async function inspectPendingDeletions({firestore, now = Date.now()}) {
  const snapshot = await firestore.collection("accountDeletions")
      .where("status", "==", "pending").select("requestedAt").limit(501).get();
  let staleCount = 0;
  let invalidTimestampCount = 0;
  let oldestAgeMinutes = 0;
  for (const doc of snapshot.docs) {
    const requestedAt = doc.data().requestedAt;
    const milliseconds = requestedAt?.toMillis?.();
    if (!Number.isFinite(milliseconds) || milliseconds > now) {
      invalidTimestampCount++;
      continue;
    }
    const age = (now - milliseconds) / 60000;
    oldestAgeMinutes = Math.max(oldestAgeMinutes, Math.floor(age));
    if (age >= 15) staleCount++;
  }
  const scanLimitReached = snapshot.docs.length >= 501;
  return {
    needsAttention: staleCount > 0 || invalidTimestampCount > 0 || scanLimitReached,
    pendingCount: snapshot.docs.length,
    staleCount,
    invalidTimestampCount,
    oldestAgeMinutes,
    scanLimitReached,
  };
}

module.exports = {inspectPendingDeletions};
