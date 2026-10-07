// DEVECO_HOME=<Release IDE> node scripts/test-auto-backup.cjs
const { assert, fs, fixtures, harness, until } = require('./backup-test-harness.cjs');

const day = 86400000;
function setup() {
  const h = harness();
  const { AutoBackupService } = h.load('service/AutoBackupService');
  const automatic = AutoBackupService.instance;
  automatic.setForeground(h.context, true);
  return { ...h, automatic };
}
async function finish(h) {
  h.automatic.setForeground(h.context, false);
  await h.automatic.pauseForManual();
  h.automatic.resumeAfterManual();
  h.settled();
}

(async () => {
  const free = setup();
  free.control.member = false;
  await assert.rejects(free.automatic.configure(free.context, true, 3), /MEMBERSHIP_REQUIRED/);
  await assert.rejects(free.automatic.configure(free.context, false, 7), /MEMBERSHIP_REQUIRED/);
  assert.equal(free.automatic.settings.enabled, false);
  // Previously enabled settings cannot bypass an expired/refunded/unverified entitlement.
  free.automatic.settings.enabled = true;
  free.automatic.settings.intervalDays = 7;
  free.automatic.settings.nextCheckAt = 0;
  await free.automatic.check(free.context);
  assert.equal(free.control.cloudWrites, 0);
  assert.equal(free.automatic.settings.enabled, false);
  assert.equal(free.automatic.settings.intervalDays, 1);
  const { AutoBackupService: ResetBackup } = free.load('service/AutoBackupService');
  const resetBackup = new ResetBackup();
  await resetBackup.refresh(free.context);
  assert.equal(resetBackup.settings.enabled, false);
  assert.equal(resetBackup.settings.intervalDays, 1, 'default persisted across restart');
  await free.automatic.pauseForManual();
  const manual = await free.service.backup(free.context);
  free.automatic.resumeAfterManual();
  assert.equal(manual.uploaded, true, 'manual cloud backup stays free');
  await finish(free);

  const expired = setup();
  await expired.automatic.configure(expired.context, true, 7);
  await expired.automatic.check(expired.context);
  expired.control.member = false;
  expired.control.autoSettingsFlushError = true;
  await expired.automatic.resetMembershipDefaults(expired.context);
  assert.equal(expired.automatic.settings.enabled, false);
  assert.equal(expired.automatic.settings.intervalDays, 1);
  assert.equal(expired.automatic.storageFailed, true);
  expired.control.autoSettingsFlushError = false;
  await expired.automatic.resetMembershipDefaults(expired.context);
  assert.equal(expired.automatic.storageFailed, false, 'retry must persist defaults after disk failure');
  await finish(expired);

  const h = setup();
  await h.automatic.check(h.context);
  assert.equal(h.control.cloudWrites, 0, 'default off must not upload');
  await h.automatic.configure(h.context, true, 1);
  await h.automatic.check(h.context);
  assert.ok(h.automatic.settings.lastSuccessAt > 0);
  assert.equal(h.automatic.settings.digest.length, 64);
  const writes = h.control.cloudWrites;
  await h.automatic.check(h.context);
  assert.equal(h.control.cloudWrites, writes, 'not due must not upload');
  h.automatic.settings.nextCheckAt = 0;
  await h.automatic.check(h.context);
  assert.equal(h.control.cloudWrites, writes, 'export timestamp alone must not count as a change');
  h.control.backupPreferences.favorites.push('new-book');
  h.automatic.settings.nextCheckAt = 0;
  await h.automatic.check(h.context);
  assert.ok(h.control.cloudWrites > writes, 'changed data must upload');
  assert.equal(fs.readdirSync(h.context.cloudFileDir).length, 2);
  await h.automatic.configure(h.context, true, 7);
  assert.equal(h.automatic.settings.nextCheckAt, h.automatic.settings.lastSuccessAt + 7 * day);
  const { AutoBackupService, AutoBackupSettings } = h.load('service/AutoBackupService');
  const restarted = new AutoBackupService();
  await restarted.refresh(h.context);
  assert.equal(restarted.settings.enabled, true);
  assert.equal(restarted.settings.intervalDays, 7);
  assert.equal(restarted.settings.digest, h.automatic.settings.digest);
  assert.equal(AutoBackupSettings.parse('{broken').enabled, false);
  await finish(h);

  const remote = setup();
  remote.seed();
  await remote.automatic.configure(remote.context, true, 1);
  await remote.automatic.check(remote.context);
  assert.equal(remote.automatic.settings.needsDecision, true);
  assert.equal(remote.control.cloudWrites, 0, 'new device must not replace remote backup');
  await remote.automatic.pauseForManual();
  const receipt = await remote.service.backup(remote.context);
  await remote.automatic.recordManualSuccess(remote.context, receipt);
  remote.automatic.resumeAfterManual();
  assert.equal(remote.automatic.settings.needsDecision, false);
  assert.equal(remote.automatic.settings.lastSuccessAt, receipt.exportedAt);
  const afterManual = remote.control.cloudWrites;
  await remote.automatic.check(remote.context);
  assert.equal(remote.control.cloudWrites, afterManual, 'manual success postpones automatic backup');
  await finish(remote);

  const retry = setup();
  retry.control.startError = 22400005;
  await retry.automatic.configure(retry.context, true, 3);
  await retry.automatic.check(retry.context);
  assert.equal(retry.automatic.settings.lastSuccessAt, 0);
  assert.equal(retry.automatic.settings.errorCode, retry.codes.SERVER);
  assert.ok(retry.automatic.settings.nextCheckAt >= Date.now() + 290000);
  const attempts = retry.syncTasks.length;
  await retry.automatic.check(retry.context);
  assert.equal(retry.syncTasks.length, attempts, 'failed task must back off');
  retry.control.startError = 0;
  retry.automatic.settings.nextCheckAt = 0;
  await retry.automatic.check(retry.context);
  assert.ok(retry.automatic.settings.lastSuccessAt > 0);
  assert.equal(retry.automatic.settings.errorCode, 0);
  retry.auth.openID = retry.control.identity = 'account-B';
  await retry.automatic.check(retry.context);
  assert.equal(retry.automatic.settings.enabled, false, 'account B cannot inherit account A consent');
  retry.auth.openID = retry.control.identity = 'account-A';
  await retry.automatic.refresh(retry.context);
  assert.equal(retry.automatic.settings.enabled, true);
  assert.equal(retry.automatic.settings.intervalDays, 3);
  retry.auth.isLoggedIn = false;
  await retry.automatic.check(retry.context);
  assert.equal(retry.automatic.accountId, '');
  await finish(retry);

  const takeover = setup();
  takeover.control.auto = false;
  await takeover.automatic.configure(takeover.context, true, 1);
  await until(() => takeover.syncTasks.length === 1);
  await takeover.automatic.pauseForManual();
  assert.equal(takeover.service.busy, false);
  assert.equal(takeover.auth.dataOperation, false);
  assert.equal(takeover.control.cloudWrites, 0);
  takeover.control.auto = true;
  await takeover.service.backup(takeover.context);
  takeover.automatic.resumeAfterManual();
  await finish(takeover);

  const restore = setup();
  restore.seed();
  await restore.automatic.configure(restore.context, true, 1);
  await restore.automatic.check(restore.context);
  await restore.automatic.pauseForManual();
  assert.equal(await restore.service.restore(restore.context, async () => true), true);
  await restore.automatic.recordRestoreSuccess(restore.context, restore.auth.openID);
  restore.automatic.resumeAfterManual();
  assert.equal(restore.automatic.settings.needsDecision, false);
  assert.equal(restore.automatic.settings.trusted, true);
  assert.equal(restore.automatic.settings.lastSuccessAt, 0, 'restore is not an upload');
  await finish(restore);

  const background = setup();
  background.automatic.setForeground(background.context, false);
  await background.automatic.configure(background.context, true, 1);
  await background.automatic.check(background.context);
  assert.equal(background.control.cloudWrites, 0, 'background must not start an automatic task');
  assert.equal(background.timers.size, 0);
  await finish(background);

  const disk = setup();
  disk.control.autoSettingsFlushError = true;
  await assert.rejects(disk.automatic.configure(disk.context, true, 1));
  assert.equal(disk.automatic.settings.enabled, false, 'failed opt-in must not authorize an upload');
  assert.equal(disk.control.cloudWrites, 0);
  disk.control.autoSettingsFlushError = false;
  await disk.automatic.configure(disk.context, true, 1);
  await disk.automatic.check(disk.context);
  assert.ok(disk.automatic.settings.lastSuccessAt > 0);
  disk.control.backupPreferences.favorites.push('later-change');
  disk.automatic.settings.nextCheckAt = 0;
  disk.control.autoSettingsFlushError = true;
  await disk.automatic.check(disk.context);
  assert.equal(disk.automatic.storageFailed, true);
  const diskWrites = disk.control.cloudWrites;
  await disk.automatic.check(disk.context);
  assert.equal(disk.control.cloudWrites, diskWrites, 'failed schedule persistence must not repeatedly rotate cloud backups');
  await finish(disk);
  console.log('PASS: automatic backup opt-in, intervals, unchanged content, remote protection, manual takeover, retry, account isolation, restore and lifecycle cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  for (const dir of fixtures) fs.rmSync(dir, { recursive: true, force: true });
});
