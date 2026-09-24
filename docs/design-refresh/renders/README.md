# Rendered SwiftUI specimens

These PNGs are captures of the **implemented SwiftUI specimen views** at their stated window sizes. They are useful for reviewing actual tokens, typography, component spacing, and light/dark behavior. The views use fixture content and are not wired to `AppStore` or the audio engine yet.

| Screen | Dark | Light | Size |
| --- | --- | --- | --- |
| Live | [Dark](signal-grid-live-dark.png) | [Light](signal-grid-live-light.png) | 1200 × 700 |
| Rehearse | [Dark](signal-grid-rehearse-dark.png) | [Light](signal-grid-rehearse-light.png) | 1200 × 700 |
| Rehearse stacked | [Dark](signal-grid-rehearse-stacked-dark.png) | — | 760 × 700, scrollable |

The integrated captures below render `RootView` with `AppStore.preview()` in an offscreen 1200 × 700 SwiftUI window. They include the real sidebar and runtime view layout, using synthetic preview state; they do **not** prove audio output or live hardware behavior.

| Integrated state | Dark capture |
| --- | --- |
| Live, playing with another song cued | [Live](signal-grid-live-integrated-dark.png) |
| Live, countoff beat 1 of 4 | [Countoff](signal-grid-live-countoff-dark.png) |
| Rehearse, pad and click playing | [Rehearse](signal-grid-rehearse-integrated-dark.png) |

The earlier [Signal Grid mockup](../future-signal/signal-grid-live-open-status.png) remains the visual reference. It is an AI-generated concept image, while these captures show the actual component implementation. Fixture route names and song choices are examples; production views must use runtime and routing state.
