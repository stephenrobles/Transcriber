# iPhone Duo screenshots (inner display, 2853 × 2007)

Five shots for the App Store `APP_IPHONE_DUO` slot, which earns the "Made for iPhone Duo"
badge. Framed like Kan Do's, Stash's and Captioner's sets: the whole device in Apple's Duo
frame under a centered white SF Bold headline, on Transcriber's lavender-to-purple icon
gradient. Raw captures are in `raw/` (no status bar; see the recipe). First made for 1.3.1.

| Shot | Video (BT Shorts) | Seek | Look | Headline |
|---|---|---|---|---|
| 01-side-by-side | iPhone Duo Action Control | 4.3 | flat, Cues | Your video and transcript, side by side. |
| 02-folded | iPhone Duo Action Control | 4.3 | `TRANSCRIBER_HINGE=book-v` | Fold it like a book. Nothing hides in the hinge. |
| 03-text | iPhone Duo Action Control | 12.9 | Text view | Read it as text, ready to copy. |
| 04-find | iPhone Duo Action Control | 12.9 | `TRANSCRIBER_FIND="action button"`, `_REPLACE="Action Button"` | Fix a misheard name everywhere at once. |
| 05-dark | iPhone Duo Apple Pay | 6.2 | dark appearance | Dark mode. All on your device. |

## Recipe

1. **Projects.** The simulator has no speech models, so transcribe on the Mac with the app's
   own engine into a `.transcriber` project, then give it a plain bookmark to the video inside
   the simulator app container (the Mac bookmark resolves there, so no "Locate…" step):
   a small CLI built from `Transcriber/Model/{Transcript,TimeFormatting,CueBuilder,TranscriptExporter,MediaAudioReader,TranscriptionEngine,LanguageCatalog,AppSettings}.swift`
   plus `Views/CaptionOverlay.swift` that runs `TranscriptionEngine.transcribe` and writes a
   `ProjectFile`; then rewrite `mediaBookmark` (base64 of `url.bookmarkData()`) and `mediaPath`.
   Fix brand words by hand (Duo, Touch ID, Apple Pay).
2. **Simulator.** "iPhone Duo (Transcriber)" (E1B59060-5CA8-4791-BA26-400022F2FFFD, iOS 27.1).
   Build the Debug scheme for `generic/platform=iOS Simulator`, `simctl install`, copy the
   videos and projects into `<container>/Documents`, `simctl status_bar … override --time 9:41`.
3. **Launch.** `SIMCTL_CHILD_TRANSCRIBER_SEEK=<s> SIMCTL_CHILD_TRANSCRIBER_NO_FOCUS=1 xcrun simctl launch <udid> fm.beard.Transcriber`,
   then tap the project in the document browser. Debug-only launch hooks (DocumentView,
   FindReplaceBar, FoldLayout): `TRANSCRIBER_SEEK` parks the player, `TRANSCRIBER_FIND` /
   `TRANSCRIBER_REPLACE` open the Find bar prefilled, `TRANSCRIBER_NO_FOCUS` keeps the keyboard
   away, `TRANSCRIBER_HINGE=closed|open|book|book-h|book-v` forces a posture. Menus and
   popovers don't survive the display move below; sheets and view state do.
4. **Capture.** `Marketing/duo-tools/capture-duo.sh raw/NN.png`. The fold can't be scripted, so
   the app is moved to a hidden 951 × 669 pt "Resizable" display with `devicectl device appResize`
   and captured there: the inner display's exact size and layout, no status bar.
5. **Compose.** `swiftc -O Marketing/compose-duo-frame.swift -o build/compose-duo`, then
   `build/compose-duo 2853 2007 raw/NN.png NN.png "Headline"`. The bezel and Apple's license
   are in `Marketing/Bezels/` (copied from Kan Do).
