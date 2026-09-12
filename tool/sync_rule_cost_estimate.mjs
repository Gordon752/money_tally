// Incremental cost of deletion-barrier security rules, not the total backend bill.
// Verified NAM5 Standard read SKU 369B-DC02-4DAB, 2026-09-12.
import assert from 'node:assert/strict';
const dollarsPerRead = 0.06 / 100000;
const days = 30;
// 14 core requests/sync, plus one request of planning headroom.
const markerReadsPerSync = 15;
const markerReadsPerChangedDocument = 2;
const profiles = [
  {name: 'Light', devices: 1, syncsPerDeviceDaily: 2, changedDocumentsDaily: 5},
  {name: 'Typical', devices: 2, syncsPerDeviceDaily: 3, changedDocumentsDaily: 10},
  {name: 'Heavy', devices: 3, syncsPerDeviceDaily: 8, changedDocumentsDaily: 30},
];
function monthlyReads(profile) {
  return days * (profile.devices * profile.syncsPerDeviceDaily * markerReadsPerSync +
    profile.changedDocumentsDaily * markerReadsPerChangedDocument);
}
assert.equal(monthlyReads(profiles[0]), 1200);
assert.equal(monthlyReads(profiles[1]), 3300);
assert.equal(monthlyReads(profiles[2]), 12600);
assert.ok(Math.abs(monthlyReads(profiles[1]) * 1000 * dollarsPerRead - 1.98) < 1e-9);
console.log('Extra monthly security-rule reads/user:',
  profiles.map(p => `${p.name}: ${monthlyReads(p)}`).join('; '));
console.log('| Active synced users | Light extra USD/mo | Typical extra USD/mo | Heavy extra USD/mo |');
console.log('| ---: | ---: | ---: | ---: |');
for (const users of [100, 1000, 5000, 10000, 25000, 50000, 100000]) {
  console.log(`| ${users.toLocaleString('en-US')} | ${profiles.map(p =>
    (monthlyReads(p) * users * dollarsPerRead).toFixed(2)).join(' | ')} |`);
}
console.log('Gross incremental cost before shared daily free quota; excludes retries, restore loops and deletion cleanup.');
