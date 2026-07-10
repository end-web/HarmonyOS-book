# Book Download Stability Design

## Purpose

This change hardens the first version of long-lived audio downloads before it
is treated as release-ready. It keeps the current `DownloadService` and
`DownloadStore` architecture, fixes correctness and scalability issues, and
adds the minimum UI and test coverage required for reliable use.

## Scope

- Stream audio responses to disk instead of buffering complete chapters.
- Write through a temporary `.part` file and publish only validated files.
- Batch initial chapter persistence for full-book and range downloads.
- Prevent paused or deleted tasks from writing stale state after async work.
- Restore interrupted tasks automatically after application restart.
- Preserve explicit user pauses across restart.
- Apply source headers and cookies to audio download requests.
- Add pause and resume actions to the existing book detail download panel.
- Add focused tests for task policy, stable identity, cancellation, and file
  validation behavior.

## Non-Goals

- HLS playlist and segment downloading is not supported. `.m3u8` responses are
  rejected with a clear failure reason.
- No system background download agent is introduced.
- No HTTP Range resume is introduced. A failed or paused chapter restarts from
  byte zero.
- No global download management page is added.
- Temporary preload behavior in `ChapterCacheService` is not redesigned.

## Architecture

### DownloadService

`DownloadService` remains the owner of book queues, URL resolution, task
versions, active transports, pause/resume, deletion, restart restoration, and
download update events.

Each queued task captures a generation value. Pausing, deleting, or clearing a
task increments the relevant generation and cancels its active HTTP request.
After every awaited operation, the worker checks that its captured generation
is still current before changing persistent state or enqueuing another stage.

### DownloadStore

`DownloadStore` remains the durable JSON store under `filesDir/downloads`.
It gains a batch preparation operation that creates or updates one book and all
selected chapter records with a single persistence write.

Chapter state updates no longer call a saving `ensureBookRecord()` internally.
A mutation performs at most one store write. Store write failures are logged
and propagated to callers instead of being silently reported as success.

### AudioDownloadTransport

A small `AudioDownloadTransport` helper owns one streaming HTTP transfer. It
has no UI dependency and exposes start and cancel operations.

The transport uses HarmonyOS `http.HttpRequest.requestInStream()` and listens
for `dataReceive` events. Chunks are appended to a serialized file write chain
so callback overlap cannot reorder file contents.

The transfer writes to `<finalPath>.part`. The final file is created only when:

- The response code is `200`.
- The request was not cancelled.
- The received byte count matches the written byte count.
- The file is larger than the existing minimum usable threshold.
- The response is not HTML, JSON, or an HLS playlist.

After validation, the temporary file is atomically moved to the final path.
Cancellation and failure delete the temporary file.

## Audio Request Resolution

`BookSourceService` exposes a download request resolver returning a clean audio
URL and request headers.

For normal sources it merges source headers, URL-specific headers, and the
matching cookie-jar cookie. For built-in sources it also uses the source
plugin's `getAudioHeaders()` result. Explicit URL headers take precedence over
source defaults.

The resolver rejects non-HTTP URLs. HLS URLs or HLS response content types are
reported as unsupported rather than being saved as an MP3 file.

## State Model

Chapter state follows:

`pending -> resolving -> downloading -> completed | failed`

Cancellation is an operation result, not a persisted failure state.

- User pause: active requests are cancelled, unfinished chapters become
  `pending`, and the book becomes `paused`.
- User resume: all non-completed chapters are queued again from byte zero.
- Interrupted process: books previously in `queued` or `downloading` remain
  restartable and are automatically queued during `DownloadService.init()`.
- Explicitly paused books remain paused during startup.
- Delete: task generations are invalidated before files and records are
  removed, so late resolver results cannot recreate deleted records.

Book status and counters continue to be derived from chapter records.

## Stable Chapter Identity

Online chapters are identified by `pageUrl` first and `chapterId` second.
Lookup, status display, retry, and deletion use the same matching rule. This
keeps single-chapter deletion working when a refreshed table of contents
changes generated chapter IDs but preserves the page URL.

## UI Behavior

The existing detail-page panel remains compact:

- `Download all`, `Next 20`, and `Incremental` remain available.
- A downloading or queued book shows `Pause`.
- A paused book shows `Resume`.
- Delete remains available when the book has downloadable records.
- Persistence or queue preparation failures show a toast and do not show the
  successful "queued" message.

The player chapter list keeps its current status indicators and long-press
single-chapter action. No download work runs from ArkUI `build()` methods.
New user-facing download text is stored in string resources.

## Error Handling

- Missing source: chapter fails with a source-not-found reason.
- URL resolution failure: chapter fails without starting a file transfer.
- HTTP error: chapter fails with the response code.
- Unsupported HLS: chapter fails with an explicit unsupported-format reason.
- File open/write/move failure: the `.part` file is deleted and the chapter
  fails.
- Cancellation: temporary files are deleted and failure counters are not
  incremented.
- Store failure: the error is logged and returned to the initiating UI action.

## Verification

Focused automated checks cover:

- Batch preparation deduplicates chapters by stable page URL.
- Interrupted books resume while explicitly paused books do not.
- A generation invalidated by delete cannot write a later resolver result.
- Single-chapter deletion works after generated chapter IDs change.
- HLS URLs and response types are rejected.
- Partial files are not accepted as completed downloads.

Build verification uses the default debug HAP build. Manual verification covers
full-book download, pause/resume, restart restoration, deletion during URL
resolution, clearing downloads, and playback with network access disabled.

## Acceptance Criteria

- Downloading two large chapters does not buffer either complete file in the
  ArkTS heap.
- A failed or cancelled transfer never leaves a reusable final audio file.
- Enqueuing a full book performs one initial batch store write.
- Deleting a book or chapter cannot recreate its record after a late callback.
- Interrupted tasks resume after restart; explicitly paused tasks do not.
- Sources requiring audio request headers can download successfully.
- The project builds successfully and focused download tests pass.
