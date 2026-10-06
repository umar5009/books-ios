# LumaRead — books that read the room

An iOS 17+ SwiftUI reading app with eye-driven reading, touch-free gestures, mood-aware AI and a recommendation feed that learns from you. All the machine learning runs on the iPhone itself.

## Run it

1. Open `LumaRead.xcodeproj` in **Xcode 16 or newer**. The project uses synchronized folders, so any file you add under `LumaRead/` is picked up automatically.
2. Target → *Signing & Capabilities* → pick your Team. If needed, change the bundle ID `com.umar.lumaread`.
3. To test purchases locally: *Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration* → `Products.storekit`.
4. Run it on a **physical iPhone with Face ID** (iPhone X or later). The Simulator has no TrueDepth camera, so in the Simulator the library, feed, reader and typed mood input work, but eye tracking and Air Zoom don't.

In Debug builds every Plus feature is unlocked (there's a *Debug: unlock all* toggle on the paywall). Release builds use real StoreKit.

## Features → how they work

| Feature | Implementation |
|---|---|
| **Eye-Flow line + word highlight** | ARKit `ARFaceTrackingConfiguration` gives `lookAtPoint` and the head pose. A 9-point **per-user calibration** fits a ridge regression from those features to screen points. A **1€ filter** smooths the result. TextKit pagination gives exact line and word rectangles, and a reading-cursor model with hysteresis plus return-sweep detection picks the current line and word. |
| **Auto page turn** | When your gaze reaches the last ~40% of the last line, the turn is armed. The page turns after 0.9 s, or right away when your eyes sweep back to the top. |
| **Double-blink page turn** | ARKit eyelid blend shapes (`eyeBlinkLeft/Right`). Two short blinks within 0.7 s count. |
| **Air Zoom (no touch)** | The same camera frames go to Vision `VNDetectHumanHandPoseRequest` (21 hand joints). The thumb–index gap is divided by palm size, so moving your hand nearer or farther doesn't trigger it. Spreading the fingers makes text larger and pinching makes it smaller. |
| **Mood AI** | Multimodal fusion of on-device Speech (what you say), Apple's `NLTagger` sentiment model, an emotion lexicon, voice energy and speaking pace, ARKit facial expression (smile, frown, brow, droopy eyes), and an optional custom Core ML classifier (`Tools/TrainMoodClassifier.swift`). |
| **Mood → books** | Each mood maps to topics that either match the mood or gently lift it (setting: *Lift low moods*). |
| **Temu-style "For You" feed** | Online learning from impressions, dwell time, skips, opens, searches, minutes read, finishes, likes and dislikes. It combines a 512-d interest embedding (`NLEmbedding.sentenceEmbedding`), decayed tag affinities, a **Thompson-sampling bandit** per topic (keeps exploring) and **MMR** re-ranking (variety). Each infinite-scroll batch is re-ranked with the latest profile. |
| **Library** | 75k+ free public-domain books from Project Gutenberg via the Gutendex API, so there are no licensing costs and that's what keeps the price low. |
| **Pricing** | Free: the whole library, AI feed and reader. **Plus**: $1.99/mo or $11.99/yr with a 7-day trial, or $24.99 lifetime. Plus unlocks Eye-Flow, hands-free turns, Air Zoom and Mood AI. |

## Accuracy notes

- iPhone gaze estimation is good to roughly **1–2 lines** after calibration. **Line-level** highlighting is reliable. **Word-level** highlighting is approximate, so it's damped to move forward smoothly.
- Glasses, low light and holding the phone very close or far all reduce accuracy. Re-calibrate from *Reader → Aa → Calibrate*.
- The camera is shared, so face tracking and hand tracking run from a single ARKit session.

## Project layout

```
LumaRead/
  App/        LumaReadApp, AppSettings, Theme (aurora + glass design system)
  Models/     Book, ReadingProgress
  ML/         SensorHub (ARKit gaze/blink/expression), AirZoomDetector (Vision),
              GazeMath (1€ filter, ridge-regression calibration),
              MoodEngine + Mood, RecommendationEngine (embeddings + bandit + MMR)
  Services/   GutendexService, LibraryStore, Paginator (TextKit), ReaderModel, FeedModel, SubscriptionStore
  Views/      Home, Discover, Library, Profile, BookDetail, MoodCheckIn, Paywall, Onboarding
  Views/Reader ReaderView, ReaderSettingsSheet, CalibrationView
Tools/TrainMoodClassifier.swift  – Create ML training script for a custom emotion model
Products.storekit                – local StoreKit test products
```

## Before App Store submission

- Add privacy nutrition labels: Camera, Microphone and Speech are all used **on-device only**.
- Replace the generated app icon if you like (`Resources/Assets.xcassets/AppIcon`).
- Create the three products in App Store Connect with the same IDs.
- Gutendex is a free community API. For production, mirror the catalogue or self-host Gutendex.
