## 0.2.0

- (arch, breaking): removed the entire legacy API — `DicomController`, `DicomService`/`IDicomLoader`, `MedicalScreen`, `DicomShaderPainter` widget glue, `DicomConfig`/`DicomFrameResult`/generated models from public exports, and all compat shims. The public surface is exactly the §32 contract: engine, domain, ports, analysis, series, volume, annotations, cine, network, advanced, viewer, export, overlays, errors.
- (arch, breaking): `DicomEngine.create()` now initializes the native bridge internally — callers never touch `RustLib`.
- (feat): real Rust-backed `RustDicomParser` (metadata-only parse + lazy per-frame decode via `frame_index`), `RustDicomDecoder`, `RustDicomSeriesLoader` (largest UID group → domain series), and `DicomParseResult.decodeFrame` + `CachedFrameProvider`.
- (feat): `DefaultDicomViewerController` with LRU texture cache (8 frames), and a dumb `DicomViewer` (`controller` + `overlays` + builders + drag-windowing + probe).
- (feat): painted overlays — `ScaleBarOverlay`, `OrientationOverlay` (R/L/A/P/H/F from direction cosines), `PixelProbeOverlay` (crosshair + HU readout).
- (feat): `InMemoryDicomAnnotationController` (undo/redo), `DefaultDicomCineController` + `TimerDicomCineScheduler`, `PngDicomExporter` (dependency-free encoder), `DicomUint16PixelData`/`DicomFloat32PixelData`.
- (fix): `reset()` now also clears inversion; `u_invert`/`MONOCHROME1` carried over.
- (example): rewritten on the new API — engine, overlays, presets, cine play/pause + frame scrubber, domain metadata grid.
- (test): widget + controller tests run on fakes (`tester.runAsync` for GPU texture upload); benchmark suite rewritten onto engine/controller over the 267-frame series.

- (arch, breaking): Dart-first public API contract — `DicomEngine` facade (`open`/`parser`/`decoder`/`renderer`/`exporter`), `DicomSource` factories (`file`/`bytes`/`files`/`bytesList`), `DicomParser`/`DicomParseResult` with lazy `DicomFrameProvider` (parse ≠ decode), spec-signature `DicomDecoder`.
- (arch, breaking): new domain `DicomMetadata` contract (typed, nullable, `tag<T>()`, header `windowPresets` list); generated FRB models are no longer publicly exported — infrastructure detail only.
- (arch): sealed `DicomPixelData` (`Int16`/`Uint8`/`Rgb`) + single-owner `DicomPixelTransform` (`toModalityValue`); `DicomController.huAt` now delegates to it.
- (arch): `DicomWindow` gains `label`, `DicomWindowPreset` becomes the preset authority with `forImage()` + `DicomPresetStore` for user presets.
- (arch): `DicomGeometry` (`screenToImage`/`imageToPatient`/`pixelsToMillimeters`), `DicomTagId` constants, `DicomColorMap`, `DicomRenderOptions`, paint-based `DicomOverlay`.
- (arch): `DicomViewerController` interface (`load`/`setFrame`/`setWindow`/`setColorMap`/`setInvert`/`rotate`/`zoom`/`pan`/`reset` + `states` stream); `DicomController` implements it and emits the expanded `DicomViewerState`.
- (arch): new contracts for analysis (`DicomProbe`/`ModalityProbe`, `DicomRoi`+`RoiStatistics`, `DicomRuler`), series/volume (`DicomSeriesLoader`, `DicomVolume`, MPR/MIP strategies), annotations (sealed + undo/redo controller), cine (`DicomCineController`/`DicomCineScheduler`), network (`DicomWebClient`/`DicomDimseClient`), segmentation/fusion, exporter.
- (feat): `DicomController.load(DicomSource)`, `setFrame`, `setColorMap`, `rotate`/`zoom`/`pan`, `reset()`; `DicomService.loadSeries` now takes `DicomSource.files`.
- (arch): lay Phase 0 domain foundation — `LruFrameCache`, `CineScheduler`, viewer commands, overlay composite.
- (fix): correct HU probe for unsigned 16-bit data via `storedToHu` / `controller.huAt` (reverses Rust `-32768` offset).
- (fix): `MONOCHROME1` now renders inverted via `u_invert` shader uniform + `controller.inverted` / `toggleInvert`.
- (fix): `MedicalScreen.initState` is sync again and chains `initialize().then(load)`.
- (fix): remove stale `series_sorter` bridge with no Rust counterpart.
- (feat): `DicomController.loadFromBytes`, `applyPreset`, `execute` (command path), `viewerState` snapshot.
- (feat): `DicomService.loadFrameFromBytes` / `loadSeries` + `RustDicomRepository` adapter; `BytesDicomLoader`; local const `DicomConfig` defaults (no FFI round-trip).
- (feat): `DicomViewer` builders (`loadingBuilder`, `errorBuilder`, `emptyBuilder`, `probeBuilder`), `showScaleBar` / `showProbe` toggles, typed scale bar via `PixelSpacing`.
- (feat, rust): `DicomConfig.frame_index` multi-frame selection, `auto_normalize` now forces histogram recompute, `dicom_pixel_stats[_from_bytes]`, `dicom_tags[_from_bytes]`.
- (example): clinical preset chips + invert toggle.

## 0.1.0+3

- (docs): refine performance benchmarks in README

## 0.1.0+2

- (feat): add comprehensive performance benchmarks and metadata defaults
- (feat) add `DicomMetadata` defaults and refactor DICOM processing
- (feat): implement `DicomMetadata` defaults and a `new` constructor in Rust; refactor `process_dicom_file` to use them.
- Added `Default` implementation and a `new` constructor for `DicomMetadata` in Rust.
- Refactored `process_dicom_file` to use `DicomMetadata` defaults when tags are missing.
- (feat): add `newInstance` and `default_` static methods to `DicomMetadata` and `DicomFrameResult` Dart classes.
- Added `newInstance` and `default_` static methods to `DicomMetadata` and `DicomFrameResult` Dart classes.
- (feat): introduce `LibShaders` constant for centralized shader asset path management.
- Introduced `LibShaders` constant for centralized shader asset path management.
- (refactor): integrate `LibShaders` into `DicomController`.
- Integrated `LibShaders` into `DicomController` for shader loading.
- (fix): update `MedicalScreen` to support an optional `title` parameter.
- Updated `MedicalScreen` to support an optional `title` parameter.
- (feat): add `series_performance_test.dart` covering throughput, latency, windowing stress, and lifecycle tests.
- (docs): add detailed performance benchmarks and workstation-grade metrics to README.
- (chore): add test series data to `.gitignore`.

## 0.1.0+1

- (fix): README images src

## 0.1.0

 - Initial release of Flutter-Dicom.
 - High-performance Rust core for DICOM parsing and pixel extraction.
 - GPU Fragment Shaders for real-time Windowing (Level/Width).
 - Support for 16-bit precision and Hounsfield Unit (HU) mapping.
 - Built-in `DicomViewer` widget with interactive pan, zoom, and contrast adjustments.
 - Comprehensive metadata extraction (Patient Name, Modality, Rescale Slope/Intercept, etc.).
 - Cross-platform support (Android, iOS, macOS, Windows, Linux).
