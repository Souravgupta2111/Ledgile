---
license: apache-2.0
library_name: coreml
pipeline_tag: mask-generation
tags:
  - coreml
  - core-ml
  - ios
  - macos
  - apple
  - on-device
  - segment-anything
  - sam
  - promptable-segmentation
  - arxiv:2306.14289
---

# MobileSAM — Core ML

*Segment Anything, 2023*

Lightweight Segment Anything. Tap any point to generate a segmentation mask. ViT-Tiny encoder + lightweight decoder. ~60× smaller than SAM.

<p><img src="https://huggingface.co/mlboydaisuke/MobileSAM-CoreML/resolve/main/media/2ae4448e16.gif" alt="MobileSAM demo"></p>

Core ML conversion of [ChaoningZhang/MobileSAM](https://github.com/ChaoningZhang/MobileSAM) for on-device inference on iPhone, iPad and Mac. Converted with `coremltools`; the packages are stateless, so all sequencing and buffering lives in your Swift code.

| | |
|---|---|
| Task | mask generation |
| Upstream | [ChaoningZhang/MobileSAM](https://github.com/ChaoningZhang/MobileSAM) |
| Packages | 1 |
| Download size | 19 MB |
| Minimum iOS | 17.0 |
| Peak RAM | ~300 MB |

## Files

| File | Size | Compute units | SHA-256 |
|---|---:|---|---|
| `MobileSAM.zip` | 19 MB | `all` | `0d8d48cb90a48cd8…` |
| **Total** | **19 MB** | | |

`compute_units` is not a suggestion -- it is the configuration the conversion was verified against. Moving a package to a different compute unit can silently change the numerics (FP16 attention overflow) or crash on the GPU.

## Download

```bash
hf download mlboydaisuke/coreml-zoo --include "mobilesam/*" --local-dir ./mobilesam
unzip './mobilesam/mobilesam/*.zip' -d ./mobilesam
```

## Use in Swift

```swift
import CoreML

let config = MLModelConfiguration()
config.computeUnits = .all   // as converted — see the table above

// Unzip the .mlpackage, drop it into your Xcode target and Xcode compiles it
// at build time:
let model = try MobileSAM.zip(configuration: config)

// ...or compile a downloaded .mlpackage at runtime:
let compiled = try await MLModel.compileModel(at: mlpackageURL)
let model = try MLModel(contentsOf: compiled, configuration: config)
```

## Demo

- **Sample app** — [SamKit](https://github.com/john-rocky/SamKit), a standalone iOS project.
- **Models Zoo** — this model is downloadable and runnable inside the [Models Zoo app](https://apps.apple.com/app/id6762083207) on the App Store, no build required.

## Conversion

- Pitfalls hit during conversion (FP16 overflow, ANE buffer limits, stride handling): [`docs/coreml_conversion_notes.md`](https://github.com/john-rocky/CoreML-Models/blob/master/docs/coreml_conversion_notes.md)
- Model index: [CoreML-Models](https://github.com/john-rocky/CoreML-Models)

## License

The conversion inherits the upstream license: **Apache-2.0**.

## Credits

- Upstream authors: [ChaoningZhang/MobileSAM](https://github.com/ChaoningZhang/MobileSAM), 2023
- Core ML conversion: john-rocky (Daisuke Majima)

<!-- funnel:v1 -->

---

**More models in this format:** [Core ML Model Zoo](https://huggingface.co/collections/mlboydaisuke/core-ml-model-zoo-6a7078dc888e7b13efd35631) — 46 models, each with the recipe that produced it.

**Want a different model on-device?** [Open a request](https://github.com/john-rocky/on-device-requests) — free, open weights only; the export and its measured numbers get published publicly.

<!-- /funnel:v1 -->
