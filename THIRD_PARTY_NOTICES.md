# Third-party notices

DictateLocal is licensed under the Apache License 2.0. It builds on the software below,
and it downloads speech and language models from Hugging Face when you first use them.
The models are not part of this repository or of the app download.

## Software included in the app

| Component | Version | License |
| --- | --- | --- |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | pinned revision, see `Package.resolved` | Apache License 2.0 |
| [MLX Swift](https://github.com/ml-explore/mlx-swift) | 0.32.3 | MIT |
| [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) | 3.32.3 | MIT |
| [MLX Metal shaders](https://pypi.org/project/mlx-metal/) (`mlx.metallib`) | 0.32.2 | MIT |
| [Swift Numerics](https://github.com/apple/swift-numerics) | 1.1.1 | Apache License 2.0 with Runtime Library Exception |
| [SwiftSyntax](https://github.com/swiftlang/swift-syntax) (build time only) | 603.0.2 | Apache License 2.0 with Runtime Library Exception |

MLX itself bundles [fmt](https://github.com/fmtlib/fmt) (MIT), [nlohmann/json](https://github.com/nlohmann/json) (MIT)
and [metal-cpp](https://developer.apple.com/metal/cpp/) (Apache License 2.0).
FluidAudio lists further components in its
[ThirdPartyLicenses](https://github.com/FluidInference/FluidAudio/tree/main/ThirdPartyLicenses) folder.

The Apache License 2.0 text is in [LICENSE](LICENSE). The MIT licenses follow.

### MLX Swift

```text
MIT License

Copyright (c) 2023 ml-explore

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### MLX Swift LM

```text
MIT License

Copyright (c) 2024 ml-explore

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Models downloaded at run time

| Model | Used for | Source | License |
| --- | --- | --- | --- |
| NVIDIA Nemotron Unified ASR 0.6B, Core ML conversion | Speech recognition (streaming) | [FluidInference/nemotron-labs-unified-asr-0.6b-coreml](https://huggingface.co/FluidInference/nemotron-labs-unified-asr-0.6b-coreml) | [OpenMDW-1.1](https://huggingface.co/FluidInference/nemotron-labs-unified-asr-0.6b-coreml/blob/main/LICENSE.md) |
| Parakeet Ultra, Core ML conversion | Speech recognition (on release) | [FluidInference/parakeet-ultra-coreml](https://huggingface.co/FluidInference/parakeet-ultra-coreml), based on [moondream/parakeet-ultra](https://huggingface.co/moondream/parakeet-ultra) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Spokenly Cleanup 1, converted to 4-bit on your Mac | Optional on-device text cleanup | [spokenly/cleanup-1](https://huggingface.co/spokenly/cleanup-1), a fine-tune of [Qwen/Qwen3-0.6B-Base](https://huggingface.co/Qwen/Qwen3-0.6B-Base) | Apache License 2.0 |

Parakeet Ultra is used under CC BY 4.0: credit goes to its authors as listed on the model pages above;
the Core ML conversion changes the format, not the weights' content.

## Online service

The optional Claude Haiku cleanup sends dictated text to the [Anthropic API](https://www.anthropic.com/legal)
with your own API key. It is not part of DictateLocal and is governed by Anthropic's terms.

## Trademarks

NVIDIA, Nemotron and Parakeet are trademarks of NVIDIA Corporation. Claude and Anthropic are trademarks
of Anthropic, PBC. Apple, Mac and macOS are trademarks of Apple Inc. DictateLocal is not affiliated with
or endorsed by any of them; the names only describe which models and services it can use.
