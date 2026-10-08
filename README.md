# Transcriber

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
- Playback: video shows a player, audio a transport bar. Click a cue's timestamp to seek;
  the current cue is highlighted and followed during playback (View › Follow Playback).
  ⌥Space plays/pauses, ⌥⌘← / ⌥⌘→ skip 5 s, ⌘J jumps to the current cue.
- Export (File › Export, ⌘E for SRT): `.srt`, `.vtt`, plain `.txt`, `.txt` with a
  `[m:ss]` timestamp per paragraph, `.md` (a heading with the file name, then paragraphs
  with bold timestamps), and **SOAP Note (Markdown)**: a medical SOAP note (summary, Subjective,
  Objective, Assessment, Plan, patient discharge summary) written from the transcript by Apple's
  on-device Foundation Model (`SoapNoteGenerator`; needs Apple Intelligence). Long transcripts
  are condensed part by part first because the model's context window is small. Also available
  as a watched-folder output. Cue text is wrapped to the line limits at export time;
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

## Releases and updates

Updates ship through Sparkle (SPM, 2.6+). The feed is
`https://beardfm.app/transcriber/appcast.xml`, kept in the beardfm.app site repo at
`site/static/transcriber/appcast.xml`; DMGs live at
`site/static/downloads/Transcriber-<version>.dmg` (plus `Transcriber.dmg` for the
always-latest link). The EdDSA signing key is in the login keychain under the Sparkle account
`transcriber`; its public key is `SUPublicEDKey` in `Info.plist`.

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (Sparkle compares the latter) and
   optionally write `release-notes/<version>.html`.
2. `Tools/release.sh` builds, signs and packages `dist/Transcriber <version>.dmg`.
   Add `--notarize` to notarize, and `--notarize --upload` to also sign the update, copy it into
   beardfm.app, add it to the appcast and deploy the site. Commit the beardfm.app changes afterwards.

## License

MIT. See [LICENSE](LICENSE).
