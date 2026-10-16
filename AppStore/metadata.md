# Transcriber — App Store listing

Everything entered in App Store Connect for 1.2, kept here as the source of truth. Uploaded by
`Tools/appstore.mjs` (metadata, screenshots, build attachment, submission).

## App Information

- **Name:** Transcriber: Subtitles & Notes (as created in App Store Connect; plain "Transcriber" was taken)
- **Subtitle (30):** On-device transcripts & SRT
- **Bundle ID:** fm.beard.Transcriber (Mac + iPhone + iPad, universal purchase)
- **Primary category:** Productivity
- **Secondary category:** Photo & Video
- **Content rights:** Does not contain, show, or access third-party content
- **Age rating:** 4+ (no questionnaire items apply)
- **Price:** Free, all territories
- **Copyright:** 2026 Stephen Robles
- **Privacy policy URL:** https://beardfm.app/transcriber/privacy/
- **Support URL:** https://beardfm.app/transcriber/
- **Marketing URL:** https://beardfm.app/transcriber/
- **App privacy:** Data Not Collected

## Version Information (1.2)

**Promotional text (170):**
Turn any video or audio file into an editable, timestamped transcript on your own device, then export YouTube-ready subtitles or clean text. Nothing is uploaded.

**Description (4000):**
Transcriber turns a video or audio file into a transcript you can edit, with every word timed, using Apple's on-device speech engine. Nothing leaves your Mac, iPhone or iPad.

Pick a file, and the text appears as it is recognized. A ten-minute video takes well under a minute on Apple silicon. The words are grouped into subtitle cues the way YouTube and broadcast captions expect them, so the SRT you export drops straight into your video.

WHAT IT DOES
• Transcribes MP4, MOV, M4A, MP3, WAV, AIFF and anything else your device can play
• Keeps the moment every word was spoken, so subtitles land exactly on the speech
• Groups text into cues of two lines up to 42 characters, broken at sentence ends, commas and pauses (adjustable)
• Plays the file in the window with the current cue shown over the video as a caption, in a classic, boxed or outlined style, exactly as it will look in the SRT
• Edit any cue in place, split a cue at the cursor, merge two, or retime one. Find & Replace fixes a misheard name everywhere at once, and everything is undoable
• A Text view shows the transcript as readable paragraphs, with optional timestamps and Copy All

EXPORT
• SRT and WebVTT subtitles for YouTube and video editors
• Plain text as paragraphs, text with a timestamp on each paragraph for show notes and chapters, or Markdown with bold timestamps
• Save the project to come back to it later

LANGUAGES
• Everything Apple's on-device engines support: English, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Hindi and more through Apple's newest model, plus Swedish, Danish, Norwegian, Finnish, Dutch, Russian, Polish, Turkish, Greek, Arabic, Hebrew, Thai, Vietnamese and others through Apple's earlier dictation model
• Pick the language right in the window; the model downloads once, then works offline

ON THE MAC
• Drop files on the window or the Dock icon
• Watched folders: point Transcriber at a folder and every new file that lands in it is transcribed automatically, with the outputs you choose saved next to it
• Open at Login keeps it running quietly in the background

PRIVATE BY DESIGN
• Transcription runs on your device's Neural Engine. There is no account, no analytics and no network feature of any kind
• The first use of a language downloads Apple's speech model for it; after that it works offline

Transcriber requires macOS 26, iOS 26 or iPadOS 26 and a device that supports Apple's on-device speech recognition.

**Keywords (100):**
transcribe,transcript,subtitles,srt,captions,speech to text,dictation,youtube,vtt,offline,private

**What's New (1.2):**
First App Store release. Transcribe video and audio on-device, edit the cues, see captions over the video as it plays, and export SRT, WebVTT, text or Markdown.

**Support URL:** https://beardfm.app/transcriber/
**Marketing URL:** https://beardfm.app/transcriber/

## App Review Information

- **Sign-in required:** No
- **Contact:** Stephen Robles, steve@beard.fm
- **Notes:**
  Transcriber transcribes audio and video entirely on the device with Apple's Speech framework
  (SpeechAnalyzer / SpeechTranscriber, with DictationTranscriber for languages the newer model
  lacks). There is no account, server or network feature. To test: open the app, create a
  document (iPhone/iPad) or use the empty window (Mac), choose any video or audio file with
  speech from Files or Photos, and the transcript appears within seconds; then try the Export
  button for SRT. The first transcription in a language downloads Apple's speech model for it,
  which needs a network connection once. On the Mac, Settings › Watched Folders uses
  security-scoped bookmarks to read folders the user picks and to save transcripts next to the
  files; Open at Login uses SMAppService.

## Screenshots

- Mac: 2880×1800, `screenshots/mac-*.png`
- iPhone 6.3" (1206×2622), `screenshots/iphone-*.png`
- iPad 13" (2064×2752), `screenshots/ipad-*.png`
