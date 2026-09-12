// Operations tool; uses the installed Firebase CLI's signed-in identity.
// No credential files are read and no tokens are printed. Not deployed with Functions.
// node tool/deletion_alerts.cjs configure EMAIL
// node tool/deletion_alerts.cjs inspect
// node tool/deletion_alerts.cjs test
// node tool/deletion_alerts.cjs run-check
// node tool/deletion_alerts.cjs logs
// node tool/deletion_alerts.cjs matched-logs
// node tool/deletion_alerts.cjs repair-open-notification
const base = "/usr/local/lib/node_modules/firebase-tools/lib";
const auth = require(base + "/auth");
const {requireAuth} = require(base + "/requireAuth");
const {Client} = require(base + "/apiv2");
const {randomUUID} = require("node:crypto");
const project = "money-tally-gordonbowles";
const options = {project, nonInteractive: true};
auth.setActiveAccount(options, auth.getProjectDefaultAccount(process.cwd()));
const displayName = "Trackmark account deletion needs attention";
const jobId = "firebase-schedule-monitorTrackmarkAccountDeletions-us-central1";
const filter = `severity>=ERROR AND (
  (resource.type="cloud_run_revision" AND resource.labels.service_name=(
    "deletetrackmarkaccount" OR "resumetrackmarkaccountdeletion" OR
    "monitortrackmarkaccountdeletions")) OR
  (resource.type="cloud_scheduler_job" AND resource.labels.job_id="${jobId}") OR
  (resource.type="global" AND logName="projects/${project}/logs/trackmark-deletion-alert-test"
    AND jsonPayload.event="deletion_alert_delivery_test")
)`;

async function main() {
  await requireAuth(options);
  const monitoring = new Client({urlPrefix: "https://monitoring.googleapis.com", auth: true});
  const prefix = `/v3/projects/${project}`;
  const channels = (await monitoring.get(`${prefix}/notificationChannels`)).body.notificationChannels || [];
  const policies = (await monitoring.get(`${prefix}/alertPolicies`)).body.alertPolicies || [];
  const existing = policies.filter(p => p.displayName === displayName);
  if (existing.length > 1) throw Error("Duplicate Trackmark policies: inspect before changing anything.");
  const mode = process.argv[2];
  if (mode === "configure") {
    const email = process.argv[3];
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw Error("Provide the approved email.");
    let channel = channels.find(c => c.type === "email" && c.labels.email_address === email && c.enabled);
    if (!channel) channel = (await monitoring.post(`${prefix}/notificationChannels`, {
      type: "email", displayName: "Trackmark deletion alerts",
      labels: {email_address: email}, enabled: true,
    })).body;
    const policy = {
      displayName, enabled: true, combiner: "OR",
      documentation: {
        mimeType: "text/markdown",
        content: "Trackmark detected a deletion-function error, an unfinished deletion at least 15 minutes old, or a monitoring failure. The read-only check runs every 30 minutes. Review Cloud Logging for the affected function and the server-only accountDeletions status records. Do not remove a deletion marker or restore access as a workaround. A transient error may already have recovered: confirm status before intervening. Test entries explicitly say DELIVERY TEST and do not delete accounts. Notification throttling is one hour. Incident auto-close after one day without matching logs does not prove cleanup succeeded.",
      },
      conditions: [{displayName: "Deletion or monitor error", conditionMatchedLog: {filter}}],
      alertStrategy: {notificationRateLimit: {period: "3600s"}, autoClose: "86400s", notificationPrompts: ["OPENED"]},
      notificationChannels: [channel.name],
    };
    if (existing.length) {
      if (existing[0].conditions[0].conditionMatchedLog.filter !== filter ||
          !existing[0].notificationChannels.includes(channel.name) || !existing[0].enabled) {
        throw Error("Existing policy differs; inspect before updating.");
      }
      console.log(JSON.stringify({channel, policy: existing[0], reused: true}));
    } else {
      console.log(JSON.stringify({channel, policy: (await monitoring.post(`${prefix}/alertPolicies`, policy)).body}));
    }
  } else if (mode === "repair-open-notification") {
    if (!existing[0]?.enabled) throw Error("Expected an enabled Trackmark policy.");
    const policy = existing[0];
    const result = await monitoring.patch(`/v3/${policy.name}?updateMask=alertStrategy.notificationPrompts`, {
      name: policy.name, alertStrategy: {...policy.alertStrategy, notificationPrompts: ["OPENED"]},
    });
    console.log(JSON.stringify(result.body));
  } else if (mode === "inspect") {
    console.log(JSON.stringify({channels, policies: existing}));
    const scheduler = new Client({urlPrefix: "https://cloudscheduler.googleapis.com", auth: true});
    console.log(JSON.stringify({job: (await scheduler.get(`/v1/projects/${project}/locations/us-central1/jobs/${jobId}`)).body}));
  } else if (mode === "test") {
    if (!existing[0]?.enabled) throw Error("Configure the alert policy before testing.");
    const logging = new Client({urlPrefix: "https://logging.googleapis.com", auth: true});
    await logging.post("/v2/entries:write", {
      logName: `projects/${project}/logs/trackmark-deletion-alert-test`,
      resource: {type: "global", labels: {project_id: project}},
      entries: [{severity: "ERROR", timestamp: new Date().toISOString(),
        insertId: randomUUID(),
        logName: `projects/${project}/logs/trackmark-deletion-alert-test`,
        resource: {type: "global", labels: {project_id: project}},
        jsonPayload: {
        event: "deletion_alert_delivery_test",
        message: "DELIVERY TEST: Trackmark deletion alert setup. No account was deleted and no financial data was changed.",
      }}],
    });
    console.log("Synthetic alert test written; email receipt still requires confirmation.");
  } else if (mode === "logs" || mode === "matched-logs") {
    const logging = new Client({urlPrefix: "https://logging.googleapis.com", auth: true});
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const result = (await logging.post("/v2/entries:list", {
      resourceNames: [`projects/${project}`],
      filter: mode === "matched-logs" ? `timestamp>="${since}" AND (${filter})` : `timestamp>="${since}" AND (
        (resource.type="cloud_run_revision" AND resource.labels.service_name="monitortrackmarkaccountdeletions") OR
        (resource.type="cloud_scheduler_job" AND resource.labels.job_id="${jobId}") OR
        logName="projects/${project}/logs/trackmark-deletion-alert-test")`,
      orderBy: "timestamp desc", pageSize: 30,
    })).body;
    console.log(JSON.stringify(result));
  } else if (mode === "run-check") {
    const scheduler = new Client({urlPrefix: "https://cloudscheduler.googleapis.com", auth: true});
    console.log(JSON.stringify((await scheduler.post(`/v1/projects/${project}/locations/us-central1/jobs/${jobId}:run`, {})).body));
  } else throw Error("Use configure, inspect, test, or run-check.");
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
