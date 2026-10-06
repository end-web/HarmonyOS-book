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
  await free.automatic.configure(free.context, true, 3);
  await free.automatic.check(free.context);
  assert.equal(free.automatic.settings.enabled, true);
  assert.equal(free.automatic.settings.intervalDays, 3);
  assert.ok(free.control.cloudWrites > 0, 'automatic backup is available without membership');
  await free.automatic.configure(free.context, true, 7);
  assert.equal(free.automatic.settings.intervalDays, 7);
  await free.automatic.configure(free.context, false, 1);
  assert.equal(free.automatic.settings.enabled, false);
  await finish(free);

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
