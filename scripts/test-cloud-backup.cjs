// DEVECO_HOME=<Release IDE> node scripts/test-cloud-backup.cjs
const { assert, fs, path, fixtures, snapshot, harness, until } = require('./backup-test-harness.cjs');

(async () => {
  const manual = harness();
  manual.control.auto = false;
  const backup = manual.service.backup(manual.context);
  await until(() => manual.syncTasks.length === 1);
  assert.equal(manual.service.lastBackupAt, 0);
  assert.equal(manual.control.cloudWrites, 0);
  manual.syncTasks[0].emit(4, 0);
  await until(() => manual.syncTasks.length === 2);
  assert.equal(manual.service.lastBackupAt, 0, 'start() and local writes alone must not imply success');
  assert.equal(manual.service.busy, true);
  manual.syncTasks[1].emit(4, 0);
  await backup;
  assert.ok(manual.service.lastBackupAt > 0);
  assert.equal(JSON.parse(fs.readFileSync(manual.cloudPath(), 'utf8')).preferences.favorites[0], 'online-book');
  manual.settled();

  const unavailable = harness();
  unavailable.control.startError = 22400001;
  await assert.rejects(unavailable.service.backup(unavailable.context), e => e.code === unavailable.codes.UNAVAILABLE);
  assert.equal(unavailable.control.cloudWrites, 0);
  assert.equal(unavailable.service.lastBackupAt, 0);
  unavailable.settled();

  const full = harness();
  full.control.auto = false;
  const fullTask = full.service.backup(full.context);
  const fullReject = assert.rejects(fullTask, e => e.code === full.codes.CLOUD_FULL);
  await until(() => full.syncTasks.length === 1);
  full.syncTasks[0].emit(1, 5);
  await fullReject;
  assert.equal(full.control.stopCount, 1);
  full.settled();

  for (const mode of ['cancel', 'timeout', 'switch']) {
    const h = harness();
    h.control.auto = false;
    const task = h.service.backup(h.context);
    const code = mode === 'cancel' ? h.codes.CANCELLED : mode === 'timeout' ? h.codes.TIMEOUT : h.codes.ACCOUNT_CHANGED;
    const rejected = assert.rejects(task, e => e.code === code);
    await until(() => h.syncTasks.length === 1);
    if (mode === 'cancel') h.service.cancel();
    if (mode === 'timeout') [...h.timers.values()][0]();
    if (mode === 'switch') { h.control.identity = 'account-B'; [...h.intervals.values()][0](); }
    await rejected;
    assert.equal(h.control.cloudWrites, 0);
    assert.equal(h.control.stopCount, 1);
    h.settled();
  }

  const sourceFailure = harness();
  sourceFailure.control.sourceError = true;
  await assert.rejects(sourceFailure.service.backup(sourceFailure.context));
  assert.equal(sourceFailure.control.cloudWrites, 0, 'unreadable sources must not become an empty cloud backup');
  sourceFailure.settled();

  const unconfirmed = harness();
  unconfirmed.control.uploadState = 3;
  await assert.rejects(unconfirmed.service.backup(unconfirmed.context), e => e.code === unconfirmed.codes.SERVER);
  assert.equal(unconfirmed.service.lastBackupAt, 0, 'completed app sync with an unuploaded file is not backup success');
  unconfirmed.settled();

  const restore = harness();
  restore.seed();
  assert.equal(await restore.service.restore(restore.context, async info => {
    assert.equal(info.exportedAt, snapshot().exportedAt);
    assert.equal(info.bookCount, 1);
    assert.equal(restore.control.localRestores, 0, 'no local writes before concrete confirmation');
    return true;
  }), true);
  assert.equal(restore.control.localRestores, 3);
  assert.ok(fs.existsSync(path.join(restore.context.filesDir, 'backup/before_cloud_restore.json')));
  restore.settled();

  const declined = harness(); declined.seed();
  assert.equal(await declined.service.restore(declined.context, async () => false), false);
  assert.equal(declined.control.localRestores, 0);
  declined.settled();

  const changed = harness(); changed.seed();
  await assert.rejects(changed.service.restore(changed.context, async () => {
    changed.control.identity = 'account-B'; return true;
  }), e => e.code === changed.codes.ACCOUNT_CHANGED);
  assert.equal(changed.control.localRestores, 0);
  changed.settled();

  const foreign = harness(); foreign.seed(snapshot(), 'account-B');
  await assert.rejects(foreign.service.restore(foreign.context, async () => true), e => e.code === foreign.codes.NO_BACKUP);
  assert.equal(foreign.control.localRestores, 0);
  foreign.settled();

  for (const corrupt of [null, { ...snapshot(), version: 99 },
    { ...snapshot(), preferences: { ...snapshot().preferences, favorites: [123] } },
    { ...snapshot(), preferences: { ...snapshot().preferences, accentColor: {} } },
    { ...snapshot(), ruleSources: [{ bookSourceUrl: 123 }] },
    { ...snapshot(), stats: [{ bookId: 'book', days: null }] }]) {
    const invalid = harness(); invalid.seed(corrupt);
    await assert.rejects(invalid.service.restore(invalid.context, async () => {
      invalid.control.confirmed++; return true;
    }), e => e.code === invalid.codes.INVALID_BACKUP);
    assert.equal(invalid.control.localRestores, 0);
    assert.equal(invalid.control.confirmed, 0);
    invalid.settled();
  }

  const remote = harness(); remote.seed(); remote.control.remoteOnly = true;
  const download = remote.service.restore(remote.context, async () => true);
  await until(() => remote.downloadTasks.length === 1);
  assert.equal(remote.control.localRestores, 0);
  remote.downloadTasks[0].emit(1, 0, 'file://unrelated');
  assert.equal(remote.control.localRestores, 0);
  remote.downloadTasks[0].emit(1);
  assert.equal(await download, true);
  remote.settled();

  const partial = harness(); partial.seed(); partial.control.restoreError = true;
  await assert.rejects(partial.service.restore(partial.context, async () => true), e => e.code === partial.codes.RESTORE_FAILED);
  assert.ok(fs.existsSync(path.join(partial.context.filesDir, 'backup/before_cloud_restore.json')));
  partial.settled();
  console.log('PASS: cloud completion, unavailable/full/timeout/cancel, account isolation, download, confirmation, validation, restore errors');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  for (const dir of fixtures) fs.rmSync(dir, { recursive: true, force: true });
});
