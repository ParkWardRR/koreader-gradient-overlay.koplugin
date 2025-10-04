# Gradient Overlay

[![License](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://opensource.org/license/bsd-3-clause)


A KOReader plugin that renders a horizontal color gradient under each text line to aid tracking on color e‑ink devices. It computes in-line “break at” positions locally (no network) using simple linguistic rules and supports automatic night mode detection with a separate palette and opacity.

Note: This approximates the visual effect popularized by certain browser reading aids; it does not embed or use their proprietary code or services.

## Features
- Local segmentation: punctuation, conjunctions, and long words; fallback to halves/thirds.
- Color gradient overlay per line with adjustable opacity and bar height.
- Automatic night mode detection with a distinct palette and opacity.
- Zero network calls; privacy‑friendly.

## Installation
1. Create folder `koreader/frontend/plugins/koreader-gradient-overlay.koplugin/`.
2. Copy `init.lua` and `_meta.lua` into that folder.
3. Restart KOReader.
4. In a book: Menu → Gradient Overlay → Enable overlay.

## Settings
- Segmentation method: smart | thirds | halves.
- Light/Night opacity.
- Bar height percent and vertical offset.
- Auto night detection toggle.

## Color devices
Designed for color e‑ink (e.g., Bigme B6). On grayscale screens the effect is limited.

## Roadmap
- Optional per-paragraph detection.
- Tune palettes per device gamut.
- Optional CSS-aware line rects when exposed by KOReader.

## Development
- Structure follows KOReader plugin conventions (`init.lua`, `_meta.lua`). See KOReader docs for APIs and events.
- Versioning: Semantic Versioning (1.1.0). 

## Trademark note
Mentions of “BeeLine” in this README are purely descriptive to explain the general visual concept and compatibility expectations; no affiliation or code reuse is implied.

## License
MIT
