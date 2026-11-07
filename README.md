# DictateLocal

Dictation that runs entirely on the Mac: no API keys, no cloud, no cost.

Hold or press the shortcut and speak. With Nemotron the text is typed live at the cursor after a few seconds. The last words appear on release, and the cleaned-up version then replaces the text. With Parakeet Ultra it is inserted once on release. Outside a text field, the text is pasted on release or offered for copying. If you switch to another app before releasing, the whole text is pasted there, and words already typed stay in the first app.

## Build

Requires an Apple Silicon Mac with macOS 26 or newer and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/merkLui/DictateLocal.git
cd DictateLocal
scripts/build-app.sh
cp -R dist/DictateLocal.app /Applications/
open /Applications/DictateLocal.app
```

If `MacOSX26.5.sdk` is missing and the build reports a SwiftUI macro error, install Xcode and run `sudo xcode-select -s /Applications/Xcode.app`.

The first launch downloads the default speech model (about 600 MB) to `~/Library/Application Support/FluidAudio`. After that the app works offline and keeps the model loaded.

Grant Accessibility, Input Monitoring and Microphone under Settings > Diagnostics.

## Models

Choose under Settings > Model > Speech to Text; the info button next to each setting explains it, including disk and memory use per model. Each is downloaded on demand (about 600 MB), and only the selected one is ever in memory. Deleting the selected model switches to the other one; the last installed model cannot be deleted.

- **NVIDIA Nemotron Unified ASR 0.6B** (default): int8 encoder, 2.08 s streaming tier, German language prompt. Types at the cursor while you speak.
- **Parakeet Ultra**: decodes the whole recording once on release and then inserts the text.

Improve Text works with both models, on device or in the cloud:

- **Spokenly Cleanup** removes filler words and adds punctuation. It runs [spokenly/cleanup-1](https://huggingface.co/spokenly/cleanup-1) through MLX: the first switch-on downloads the 1.2 GB original once and reduces it to 4 bit (331 MB). It loads when dictation starts and leaves memory after five idle minutes. If it changes more than filler words, the original sentence is kept.
- **Format lists**, shown while Claude Haiku is off, uses rules only and turns explicit enumerations and list headings into lists. Ordinary sentences stay sentences, and single-line fields never get lists. Line breaks are pasted, so they do not send chat messages.
- **Claude Haiku** is the cloud option: it sends the transcript to Claude Haiku 5.5 instead of Spokenly, which also fixes misheard words and formats lists and paragraphs itself. It needs an Anthropic API key, kept in `~/Library/Application Support/DictateLocal/anthropic-api-key` and readable only by you; the key row shows whether a short test request succeeds. The prompt can be viewed and edited under Prompt. Reasoning sets how much it thinks first: Low takes about one second per dictation, Off is faster but sometimes translates English phrases. Turning it on turns Spokenly off. Without network, or if the answer is not plausibly the same text, the transcript stays as spoken and the list rules above apply.

Both run through a pinned FluidAudio revision. To add a model, implement `SpeechTranscriber` and add it to `SpeechModel`.

## Cleanup

`TextCleanup` removes hesitation sounds such as "äh" and applies the replacements from Settings > Vocabulary. It never rewrites or invents text.

## Checks

```bash
swift run DictateChecks                 # cleanup checks
swift run DictateChecks audio.wav       # stream a file in real time
swift run DictateChecks audio.wav --fast
swift run DictateChecks --claude low     # clean stdin lines with Claude, key in ANTHROPIC_API_KEY
```
