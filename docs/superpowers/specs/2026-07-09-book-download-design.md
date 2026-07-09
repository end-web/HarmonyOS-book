# Book Download And Incremental Cache Design

## Background

ListenBook already has chapter-level preloading through `ChapterCacheService`.
That cache is temporary: it is optimized for smooth playback and can be cleared
from Settings. The new feature adds long-lived offline downloads without
breaking the existing playback cache.

The implementation must follow current HarmonyOS ArkTS and ArkUI project
patterns:

- ArkUI pages use existing `@ComponentV2`, `@Local`, `@Param`, and `@Event`
  style.
- UI uses project tokens from `Theme.ets` for colors, font sizes, spacing, and
  radii.
- Network, file I/O, media metadata, and event delivery use HarmonyOS Kit APIs
  already used by this project.
- `build()` and Builder methods stay side-effect free.

## Goals

- Support full-book download.
- Support downloading the next N chapters from a chosen chapter.
- Support incremental download after a book directory is refreshed.
- Support deleting a full book download.
- Support deleting a single chapter download.
- Keep long-lived downloads separate from temporary preloaded cache.
- Let downloads continue while the app stays alive, even after leaving the
  detail/player page.
- Persist task state so unfinished downloads can resume the next time the app
  opens.
- Allow downloading on any network type.

## Non-Goals

- No complex background download service in the first version. If the app is
  killed by the system, the task pauses and resumes on next app open.
- No global download management page in the first version. Entry points are
  added to existing book detail, player, and settings screens.
- No partial HTTP range resume in the first version. Failed chapters retry from
  the beginning.
- No DRM bypass or source-specific behavior outside existing book source rules.

## Existing Context

- `AudioService` resolves a chapter page URL to a real audio URL through
  `BookSourceService.getAudioUrl`.
- `ChapterCacheService` can download audio files into `cacheDir` and restore
  usable files by chapter and page URL.
- `BookDetailPage` refreshes online book metadata and TOC, then stores the
  latest chapter list through `DataService.upsertCachedBook`.
- `DataService` stores online book metadata and chapter sidecar files.
- `SettingsPage` already has a "preload chapters" setting and a temporary cache
  clearing action.
- `PlayerPage` already checks chapter cache status in the chapter list.

## Architecture

Add a new service layer for long-lived downloads:

- `DownloadService`
  - Owns task queue, task lifecycle, retry, pause/resume, deletion, and events.
  - Resolves chapter audio URLs through existing source services.
  - Writes downloaded audio to a long-lived downloads directory.
  - Updates persistent state through `DownloadStore`.
- `DownloadStore`
  - Persists books, chapter download records, task status, file path, file size,
    timestamps, and failure reason.
  - Uses JSON storage under app files, for example
    `<filesDir>/downloads/download_store.json`.
- `ChapterCacheService`
  - Continues to own temporary preloading.
- `AudioService`
  - Checks `DownloadService.getDownloadedFilePath(bookId, chapter)` before
    checking temporary preload cache.
- UI pages
  - Call `DownloadService` methods.
  - Subscribe to download events and refresh local state.
  - Do not perform download work directly.

## Playback Priority

When playing an audio chapter, source selection follows this order:

1. Long-lived downloaded chapter file.
2. Temporary preloaded file from `ChapterCacheService`.
3. Cached resolved URL.
4. Network resolution through `BookSourceService`.

This keeps downloaded books reliable offline while preserving the current fast
switch behavior.

## Persistent Data Model

`DownloadBookRecord`

- `bookId`
- `title`
- `author`
- `cover`
- `sourceUrl`
- `bookUrl`
- `contentType`
- `chapterCount`
- `downloadedCount`
- `failedCount`
- `totalBytes`
- `status`: `idle | queued | downloading | paused | completed | failed`
- `updatedAt`
- `chapters`

`DownloadChapterRecord`

- `chapterId`
- `chapterIndex`
- `title`
- `pageUrl`
- `audioUrl`
- `filePath`
- `bytes`
- `status`: `pending | resolving | downloading | completed | failed | deleted`
- `failureReason`
- `updatedAt`

Stable identity:

- `pageUrl` is the stable key for online chapters.
- `chapterId` is still stored for UI and current app compatibility.
- If TOC order changes but `pageUrl` is the same, the existing file is reused.
- If `pageUrl` changes, the chapter is treated as a new downloadable item.

## File Storage

Long-lived downloads are stored under app `filesDir`, for example:

`<filesDir>/downloads/audio/<bookHash>/<chapterHash>.mp3`

Temporary preloads remain under `cacheDir` and keep the existing eviction
behavior. "Clear preload cache" only deletes temporary cache. "Delete download"
deletes long-lived files and their `DownloadStore` records.

## DownloadService API

Public methods:

- `init(context)`
- `downloadBook(book)`
- `downloadNextChapters(book, startIndex, count)`
- `downloadIncremental(book)`
- `downloadChapter(book, chapter)`
- `pauseBook(bookId)`
- `resumeBook(bookId)`
- `deleteBookDownload(bookId)`
- `deleteChapterDownload(bookId, chapterId)`
- `getBookStatus(bookId)`
- `getChapterStatus(bookId, chapter)`
- `getDownloadedFilePath(bookId, chapter)`

Events:

- `app.download.updated`
- Event payload includes `bookId`, optional `chapterId`, current status,
  downloaded count, failed count, and total count.

Queue behavior:

- File downloads run with a small concurrency limit, initially 2.
- URL resolution also uses a small concurrency limit, initially 2.
- If the app restarts, queued/downloading chapters are restored as pending.
- Failed chapters stay visible and can be retried through resume or incremental
  download.

## Incremental Download

Incremental download flow:

1. Refresh book info and TOC using the same source path as `BookDetailPage`.
2. Save the latest TOC through `DataService.upsertCachedBook`.
3. Build a set of completed chapter `pageUrl` values from `DownloadStore`.
4. Enqueue only chapters whose `pageUrl` has no completed local file.
5. Keep previously completed files whose `pageUrl` still exists.
6. Keep unmatched old files until the user deletes the book download. This
   avoids data loss if a source temporarily returns an incomplete TOC.

## Deletion

Full-book deletion:

- Cancels pending/running tasks for that book.
- Deletes all long-lived downloaded files for the book.
- Removes the book's download records from `DownloadStore`.
- Does not delete the book from shelf/favorites/history.
- Does not delete temporary preload cache.

Single-chapter deletion:

- Cancels pending/running task for that chapter.
- Deletes that chapter's long-lived file.
- Marks or removes the chapter record so UI returns to "not downloaded".
- A later incremental download can download the chapter again.

## UI Design

Book detail page:

- Add a compact download action near existing book actions.
- Tapping it opens an action sheet:
  - Download full book
  - Download next 10 chapters
  - Download next 20 chapters
  - Download next 50 chapters
  - Incremental download
  - Delete book download, shown only when downloaded content exists
- Show lightweight status text such as "12/80 downloaded" or "3 failed".

Player page:

- Chapter list shows status:
  - Downloading: small progress/loading indicator.
  - Downloaded: local/offline icon.
  - Failed: warning/retry affordance.
  - Not downloaded: cloud/download icon.
- Long press or more action supports single chapter download/delete.

Settings page:

- Keep "Clear preload cache" for temporary cache.
- Add "Clear downloaded content" for all long-lived downloads, with a confirm
  dialog.

## Error Handling

- Source missing: mark chapter failed with source error.
- Audio URL resolution returns original page URL: mark failed, because that
  usually means no playable audio URL was found.
- HTTP non-200 or empty result: mark failed with response code.
- File write failure: mark failed and delete partial file.
- Metadata parsing failure: keep the downloaded file; duration can remain
  unknown.
- User pause/delete takes priority over retry.

## Verification

Build:

- Run default HAP build after implementation.

Manual checks:

- Download full book and play with network unavailable.
- Download next N chapters from the middle of a book.
- Refresh TOC and run incremental download; already downloaded chapters are
  skipped.
- Delete one chapter and confirm playback falls back to cache/network.
- Delete full book download and confirm shelf/history remain.
- Clear preload cache and confirm long-lived downloads remain.
- Clear downloaded content and confirm temporary preload behavior still works.

Focused code checks:

- No download work in ArkUI `build()` methods.
- Dynamic lists use stable keys.
- Services avoid direct UI dependencies.
- Delete operations only remove intended files under the app download directory.
