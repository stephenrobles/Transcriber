# Transcriber (App Store branch)

This branch is the App Store build: one target for Mac, iPhone and iPad, sandboxed, no
Sparkle, and without the SOAP note export. The `main` branch is the direct-download Mac build
served from beardfm.app.

On iPhone and iPad the app opens in the system document browser: create a project, then
choose a video or audio file from Files or a video from Photos (copied into the app's
`Documents/Media` folder). Editing, playback with captions, Find & Replace and the five exports
(through the share-style file exporter) are the same as on the Mac. Watched folders and Open
at Login are Mac-only. Platform splits are `#if os(macOS)` / `#if os(iOS)` blocks; the engine,
cue builder, exporters and project format have none.

Foldable iPhone (iPhone Duo): `FoldLayout.swift` watches the hinge through UIKit's
`UIHingeInteraction` (iOS 27.1+; older systems and flat devices see no change). On the inner
display the editor puts the player beside the cue list when the window is wider than tall; while
the device is bent, the player and the list sit either side of the fold with a 36 pt band kept
clear of content, and the drop zone, ready and transcribing screens stay in the pane away from
the hinge. The fold bisects the inner display's longer side (horizontal hinge in portrait,
vertical in landscape). Debug builds take `TRANSCRIBER_HINGE=closed|book|open|book-h|book-v`
to force a posture for screenshots (`SIMCTL_CHILD_TRANSCRIBER_HINGE=book xcrun simctl launch …`).

A Mac app that turns a video or audio file into a transcript with Apple's on-device speech
engine (the `SpeechAnalyzer` / `SpeechTranscriber` API in macOS 26), then lets you fix it up
and export subtitles.

- Drop an MP4 / MOV / M4A / MP3 / WAV / AIFF (anything AVFoundation reads) on the window, the
  Dock icon, or use File › Open Media… (⇧⌘O). Transcription starts right away and the text
  streams in while it runs; a 90-minute talk takes well under a minute on Apple silicon.
- The transcript is kept as **words with timestamps** and grouped into **subtitle cues**
  (two lines of ≤ 42 characters, ≤ 6 s, broken at sentence ends, clauses and pauses; all
  adjustable in Settings and re-appliable with Transcript › Rebuild Cues).
- **Cues** view: click a cue to edit it inline, ⌘↩ splits at the cursor, ⌃⌘M merges with the
  next cue, ⌥⌘N inserts one, ⌫ deletes, the clock button under a timestamp retimes it (with
  "Playhead" buttons). ⌘F opens Find & Replace (match case, whole words, Replace / All, all undoable).
- **Text** view: the transcript as paragraphs, with optional timestamps and Copy All.
- Playback: video shows a player with the current cue drawn over it as a caption (three
  styles in Settings › Subtitles, toggle with ⇧⌘C; not burned in), audio a transport bar. Click a cue's timestamp to seek;
  the current cue is highlighted and followed during playback (View › Follow Playback).
  ⌥Space plays/pauses, ⌥⌘← / ⌥⌘→ skip 5 s, ⌘J jumps to the current cue.
- Export (File › Export, ⌘E for SRT): `.srt`, `.vtt`, plain `.txt`, `.txt` with a
  `[m:ss]` timestamp per paragraph, and `.md` (a heading with the file name, then paragraphs
  with bold timestamps). Cue text is wrapped to the line limits at export time;
  a newline typed in a cue forces a line break.
- Projects save as `.transcriber` files (JSON: words, cues, settings and a bookmark + path to
  the media). If the media moved, the window offers Locate…; editing and export work without it.
- **Watched folders** (Settings): new video or audio files dropped into a watched folder are
  transcribed automatically and the chosen outputs (SRT, VTT, TXT, Markdown, project) are
  written next to them, with a notification when done. Files already in the folder are left
  alone; a file is picked up once it has stopped changing for a few seconds. "Open at Login"
  (system login item) keeps the app running quietly without a window.
- Everything runs locally. The first use of a language downloads Apple's speech model for it.

## Project notes

- Xcode 27 project, macOS 26 or later, Swift with approachable concurrency and MainActor default
  isolation. Sources live in `Transcriber/` as a synchronized folder: `Model/` has the engine,
  cue builder, exporters and the `ReferenceFileDocument`; `Views/` the SwiftUI.
- `OTHER_LDFLAGS` links AVKit, AVFoundation and Speech explicitly. Without `-framework AVKit`
  only the `_AVKit_SwiftUI` overlay gets linked and `VideoPlayer` aborts at runtime while
  resolving its superclass metadata.
- `Info.plist` registers the `fm.beard.transcriber.project` type (`.transcriber`) and lists
  movie/audio as openable so media can land on the Dock icon; `AppDelegate` routes those to a
  blank document. The app registers `NSShowAppCentricOpenPanelInsteadOfUntitledFile = NO` so a
  launch opens the drop zone instead of the Open panel.
- Direct download build: Developer ID, hardened runtime, notarized, not sandboxed, with Sparkle
  for updates.
- Icon: `swift Tools/make-icon.swift Transcriber/Assets.xcassets/AppIcon.appiconset` regenerates
  the icon set (purple tile, waveform turning into text lines).
- Engine smoke test without the UI: compile `Transcriber/Model/{Transcript,TimeFormatting,CueBuilder,TranscriptExporter,MediaAudioReader,TranscriptionEngine}.swift`
  with a small `main.swift` that iterates `TranscriptionEngine.transcribe(url:locale:)`
  (`say -o speech.aiff "…"` makes a quick test clip).

## Sandbox notes

- Entitlements (macOS SDK only): app sandbox, user-selected files read/write, app-scoped
  bookmarks. iOS uses `Info-iOS.plist` (document browser, file sharing, project type only).
- `ScopedAccess` wraps `startAccessingSecurityScopedResource` for the lifetime of an object.
  A project's media is saved as a security-scoped bookmark and re-opened through it; the
  "Locate…" button re-grants access through the open panel.
- Watched folders keep a security-scoped bookmark each, resolved at launch and while enabled,
  which also covers writing transcripts next to the files inside them.
- Exports go through the save panel. `PrivacyInfo.xcprivacy` declares the UserDefaults API use.
- Stephen archives and uploads to App Store Connect himself.
