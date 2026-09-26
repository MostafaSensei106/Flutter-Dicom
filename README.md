<h1 align="center">Flutter-Dicom</h1>
<p align="center">
  <img src="https://socialify.git.ci/MostafaSensei106/Flutter-Dicom/image?custom_language=Rust&font=KoHo&language=1&logo=https%3A%2F%2Favatars.githubusercontent.com%2Fu%2F138288138%3Fv%3D4&name=1&owner=1&pattern=Floating+Cogs&theme=Light" alt="Banner">
</p>

<p align="center">
  <strong>An advanced medical imaging and DICOM processing library for Flutter, poIred by a high-performance Rust core and GPU Shaders.</strong><br>
  Go beyond basic image loading. Deliver <i>workstation-grade</i> rendering, <i>16-bit precision</i>, and <i>real-time windowing</i> in your medical apps.
</p>

<p align="center">
  <a href="#-key-features">Key Features</a> •
  <a href="#-why-choose-flutter-dicom">Why?</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-basic-usage">Basic Usage</a> •
  <a href="#-advanced-usage">Advanced Usage</a> •
  <a href="#-workstation-demo">Workstation Demo</a> •
  <a href="#-contributing">Contributing</a>
</p>

---

## ✨ Key Features

| Area | What you get |
| :--- | :--- |
| **Viewer** | GPU fragment-shader rendering, LRU frame cache + neighbor prefetch, frame scrubber, cine 1–60 fps with loop |
| **Interaction** | One transform everywhere: zoom / pan / rotation / flip / invert — paint, gestures, and overlays share `DicomViewTransform` |
| **Clinical tools** | Pixel probe (raw / HU / patient mm), scale bar, orientation markers, ruler, rectangle + ellipse ROI with statistics |
| **Windowing** | Built-in presets (brain / bone / lung / abdomen / soft tissue), drag-to-window, custom preset store |
| **Annotations** | Line / rectangle / ellipse / angle / arrow / text / freehand with undo / redo, painted through the view transform |
| **Series → Volume** | Spatial sorting by Image Position/Orientation (not filenames), `DicomVolume` with voxel spacing and origin |
| **MPR / MIP / 3D** | Nearest + trilinear reconstruction, crosshair mediator, MIP/MinIP on any axis, CPU composite volume renderer behind a GPU-ready port |
| **Export** | Windowed PNG / JPEG / TIFF (`package:image` codecs) — rendered from the pipeline, never screenshots |
| **DICOM writing** | Explicit-LE writer + dataset builder (Secondary Capture round-trips through the Rust reader), Structured Reports (Container/Text/Code/Num) |
| **Segmentation** | Threshold / brush / flood-fill strategies, mask statistics, mask overlay |
| **Fusion** | PET/CT blending with slice registration (identity / translation) |
| **Network** | DICOMweb (QIDO/WADO/STOW) and DIMSE (assoc state machine + C-ECHO/C-STORE/C-FIND over Explicit LE) |
| **Architecture** | Facade engine, hexagonal ports & adapters, DI — the viewer never imports Rust/FFI; no singletons |

---

---

## 🤔 Why Choose Flutter-Dicom?
 
> In medical imaging, an 8-bit approximation is often a liability. Your app needs clinical precision, not just a picture.

Most image libraries in Flutter are designed for JPEGs and PNGs. They clamp your data to 8-bits per channel and lack the mathematical context needed for medical diagnostics. A doctor needs to see the exact Hounsfield Units, adjust the contrast (Windowing) in real-time, and zoom without UI stutter. Pure Dart DICOM parsers struggle with the sheer size of 16-bit volumetric data, leading to memory crashes and frozen screens.

### 📊 How I compare

| Feature | Standard `Image` | `dart_dicom` (Pure Dart) | **Flutter-Dicom** |
| :--- | :---: | :---: | :--- |
| **Parsing Engine** | Platform Native | Dart | **🚀 High-Perf Rust Native Core** |
| **Bit-Depth Precision** | 8-bit (Lossy) | 16-bit (Slow) | **✅ Native 16-bit (Full Range)** |
| **Rendering Engine** | Skia/Impeller | CPU Canvas | **⚡ GPU Fragment Shaders** |
| **UI Responsiveness** | ✅ | ⚠️ | **⚡ Zero UI-Thread Blocking** |
| **Interactive Windowing**| ❌ | ❌ | **📈 Real-time Contrast/Brightness** |
| **Detailed Metadata** | ❌ | ✅ | **🩺 Full Tag Dictionary Access** |
| **Memory Efficiency** | 🔴 High | 🔴 High | **🔋 Zero-Copy FFI Buffers** |
| **Ready-to-use Widget** | ❌ | ❌ | **🤝 Built-in `DicomViewer`** |

---

## 📸 Screenshots & Demo

| Demo |
| :---: |
| <img src="https://raw.githubusercontent.com/MostafaSensei106/Flutter-Dicom/main/.github/assets/demo.gif"></img> |

| Viewer View | Viewer View | Metadata View |
| :---: | :---: | :---: |
| <img src="https://raw.githubusercontent.com/MostafaSensei106/Flutter-Dicom/main/.github/assets/empty_view.png" height="540" /> | <img src="https://raw.githubusercontent.com/MostafaSensei106/Flutter-Dicom/main/.github/assets/viewer_view.png" height="540" /> | <img src="https://raw.githubusercontent.com/MostafaSensei106/Flutter-Dicom/main/.github/assets/metadata_view.png" height="540" /> |

---

## 📦 Installation

> [!TIP]
> **Don't worry about the "Rust Core"!**
> Adding **Flutter-Dicom** to your project is designed to be as simple as adding any other Flutter package. While it uses a high-performance Rust engine, you don't need to be a Rust expert or manage complex builds manually. You just install the language once, and the library handles all the heavy lifting, compiling itself automatically for whatever platform (Android, iOS, macOS, Windows, Linux) or architecture you are targeting.

### 1. Prerequisites (The Rust Toolchain)

Since this library uses a high-speed bridge to connect Flutter and Rust, you need the Rust compiler installed on your development machine.

- **Windows**: Download and run [rustup-init.exe](https://rustup.rs).
- **macOS / Linux**: Run the following command in your terminal:
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```

> [!IMPORTANT]
> Once Rust is installed, the build system will automatically detect your Flutter target and compile the Rust core into a high-performance native shared library. You only need to set this up once!

### 2. Add the Dependency

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_dicom: ^0.2.0
```

---

## 🚀 Basic Usage

### 1. Engine

Create the engine once — it initializes the native bridge, so you never
touch FFI setup yourself.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DicomEngine.create();

  runApp(const MyApp());
}
```

### 2. Loading and Displaying DICOM

Open any source into a document (metadata now, pixels lazily), drive it
with a viewer controller, and render with the dumb `DicomViewer` widget.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

class MyMedicalApp extends StatefulWidget {
  const MyMedicalApp({super.key});

  @override
  State<MyMedicalApp> createState() => _MyMedicalAppState();
}

class _MyMedicalAppState extends State<MyMedicalApp> {
  late final _engineFuture = DicomEngine.create();
  DefaultDicomViewerController? _controller;

  @override
  void initState() {
    super.initState();
    _engineFuture.then((final engine) {
      _controller = DefaultDicomViewerController(parser: engine.parser);
      _controller!.load(const DicomSource.file('/sdcard/scans/head_ct.dcm'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      body: DicomViewer(
        controller: controller,
        overlays: const [
          ScaleBarOverlay(),
          OrientationOverlay(),
          PixelProbeOverlay(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose(); // Critical: frees GPU textures
    super.dispose();
  }
}
```

### 3. Adjusting Windowing Programmatically

```dart
// Named clinical presets (the controller is the nullable field from §2).
void applyBoneWindow() {
  _controller?.setWindow(DicomWindowPreset.bone);
}

// Custom presets persist through the store port.
Future<void> saveMyLung(final DicomPresetStore presets) async {
  await presets.save('My Lung', _controller!.state.window);
}

// Reset to file defaults
void reset() => _controller?.reset();
```

---

## 🔬 Advanced Usage

> Fragments below build on §2: `_controller` is the loaded, non-null viewer
> controller, `pixels` the current frame, and `geometry` its spatial context.

### Any Source, Same Pipeline

```dart
final engine = await DicomEngine.create();

// Local file, in-memory bytes (Web / PACS), or file lists (series).
final doc = await engine.open(const DicomSource.file('scan.dcm'));
final webDoc = await engine.open(DicomSource.bytes(bytes));
final seriesDoc = await engine.open(DicomSource.files(paths));

// Parse ≠ decode: fetch frames lazily, never 400 buffers at once.
final frame = await doc.frames.get(0);
final third = await doc.frames.get(3);

// Typed metadata with unknown-tag fallback.
final name = doc.metadata.patientName ?? 'Anonymous';
final kvp = doc.metadata.tag<double>(const DicomTagId(0x0018, 0x0060));
```

### Windowing, Cine & Analysis

```dart
// Window presets + modality-aware default.
_controller.setWindow(DicomWindowPreset.lung);
_controller.setWindow(doc.metadata.defaultWindow);

// Frame navigation + cine playback over the document.
await _controller.nextFrame();
final cine = DefaultDicomCineController(onFrame: _controller.setFrame);
await cine.play(frameCount: doc.frameCount);

// One transform: zoom / pan / rotate / flip stay consistent across
// paint, gestures, probe, ruler, ROI, and annotations.
_controller.zoom(2);
_controller.rotate(90);
_controller.setFlipH(true);

// Probing returns raw + HU + patient coordinates in millimeters.
final result = _controller.probeAt(
  const DicomPoint(100, 100),
  const DicomViewport(width: 200, height: 200),
);
final stats = await DicomRoi(const DicomRect(0, 0, 64, 64)).analyze(pixels);
final dist = const DicomRuler().measure(a, b, geometry);

// Multi-format export of the windowed view.
final png = await engine.exporter.export(pixels, format: DicomExportFormat.png);
final jpeg = await engine.exporter.export(
  pixels,
  format: DicomExportFormat.jpeg,
  options: const DicomExportOptions(quality: 90),
);
```

### Series → Volume → MPR / MIP / 3D

```dart
// Spatially sorted series (Image Position/Orientation, not filenames).
final series = await engine.openSeries(DicomSource.files(paths));
await _controller.load(DicomSource.files(series.filePaths));

// Assemble voxels, then reconstruct / project / render.
final slices = <DicomPixelData>[];
for (final path in series.filePaths) {
  final sliceDoc = await engine.open(DicomSource.file(path));
  slices.add((await sliceDoc.frames.get(0)).pixelData!);
}
final meta = DicomVolume.fromSeries(
  series,
  width: slices.first.width,
  height: slices.first.height,
);
final volume = DicomVoxelVolume.assemble(meta: meta, slices: slices);

final axial = await const NearestReconstruction()
    .reconstruct(volume, DicomPlane.axial, 10);
final mip = await const MipProjection().project(
  volume,
  const DicomProjectionOptions(),
);
// One crosshair moves axial + coronal + sagittal together.
final crosshair = DefaultDicomMprCoordinator();
crosshair.setPoint(const DicomMprPoint(64, 64, 10));
final render = await const CpuCompositeVolumeRenderer().render(
  volume,
  const DicomVolumeRenderOptions(),
);
```

### Writing & Structured Reports

```dart
// Secondary Capture of the current windowed view.
final dataset = (DicomDatasetBuilder()
      ..sop(
        classUid: DicomSopClass.secondaryCapture,
        instanceUid: DicomUid.generate(),
      )
      ..patient(name: 'Doe^John', id: '123')
      ..study(studyUid: DicomUid.generate())
      ..series(seriesUid: DicomUid.generate(), modality: 'OT')
      ..image(rows: h, columns: w)
      ..pixelData(gray8, bitsAllocated: 8))
    .build();
await DicomWriter.writeFile(dataset, '/tmp/view.dcm');

// Measurements become a real SR document.
final report = StructuredReport(
  studyUid: DicomUid.generate(),
  seriesUid: DicomUid.generate(),
  sopUid: DicomUid.generate(),
  items: [
    SrContainer(
      concept: const DicomCode(scheme: 'DCM', value: '121071', meaning: 'Finding'),
      items: [
        SrText(concept: finding, value: 'Nodule in right upper lobe'),
        SrNum(concept: finding, value: 12.5, units: mmCode),
      ],
    ),
  ],
);
await DicomWriter.writeFile(report.toDataset(), '/tmp/report.dcm');
```

### Segmentation, Fusion & Network

```dart
// Threshold / brush / flood-fill share one algorithm port.
final mask = await const ThresholdSegmentation(lower: 200, upper: 800)
    .segment(pixels);
final segStats = DicomSegmentationStats.compute(
  mask,
  spacing: geometry.pixelSpacing,
);

// PET/CT fusion with slice registration.
final fused = await const DicomFusionRenderer().render(
  ct: ctPixels,
  ctWindow: DicomWindowPreset.softTissue,
  pet: petPixels,
  petWindow: const DicomWindow(center: 5, width: 10),
);

// DICOMweb: QIDO search, WADO retrieve, STOW store.
final web = HttpDicomWebClient(baseUrl: Uri.parse('http://pacs:8080/dicom-web'));
final studies = await web.searchStudies(const DicomStudyQuery(modality: 'CT'));
await web.storeInstance(await File('/tmp/view.dcm').readAsBytes());

// DIMSE: associate, then Echo / Store / Find as commands.
final dimse = DefaultDicomDimseClient(parser: engine.parser);
await dimse.associate(host: '127.0.0.1', port: 104, calledAe: 'PACS');
final rtt = await dimse.execute(const DimseEchoCommand()) as Duration;
final found = await dimse.execute(
  const DimseFindCommand(DicomStudyQuery()),
) as List<DicomFindResult>;
await dimse.release();
```

### Precision Texture Unpacking (GLSL)

If you are curious about how I maintain 16-bit integrity through an 8-bit texture interface, look at shader logic:

```glsl
void main() {
    vec4 texColor = texture(u_texture, uv);
    
    // Unpack R (High Byte) and G (Low Byte)
    float high = texColor.r * 255.0;
    float low = texColor.g * 255.0;
    float raw_value = (high * 256.0 + low) - 32768.0;
    
    // HU = (Pixel * Slope) + Intercept
    float hu = (raw_value * u_rescale_slope) + u_rescale_intercept;
    // ... Windowing calculations follow
}
```
---

## 🏛️ Architecture (v0.2.0+)

The library is being rebuilt as a workstation-grade toolkit in layers, so new
features extend abstractions instead of adding `if/else` to the viewer:

```text
Flutter UI (Viewer / Overlays)
Application (Controllers / Commands / State / Cine / Cache)
Domain (Image / Geometry / Windowing / Pixel — pure Dart, no FFI)
Infrastructure (Rust FFI / Filesystem / DICOMweb adapters)
Native Core (Rust + dicom crate + GPU)
```

Key entry points (v0.2.0 contract — Dart-first, Rust/FFI stays an implementation detail):

```dart
// Engine facade: orchestration only.
final engine = await DicomEngine.create();
final doc = await engine.open(const DicomSource.file('/sdcard/scan.dcm'));
// Parse once, decode lazily — never 400 frames in memory.
final frame = await doc.frames.get(0);

// Any source ends at the same pipeline.
final webDoc = await engine.open(DicomSource.bytes(bytes)); // Web/PACS
final seriesDoc = await engine.open(DicomSource.files(paths)); // Series

// Clinical presets + inversion.
controller.setWindow(DicomWindowPreset.bone);
controller.setInvert(true);

// One HU math owner: DicomPixelTransform.
final probe = const ModalityProbe().probe(pixels, point);

// Composable overlays instead of viewer properties.
DicomViewer(
  controller: controller,
  loadingBuilder: (ctx) => const CircularProgressIndicator(),
  errorBuilder: (ctx, err) => Text('$err'),
  overlays: const [
    ScaleBarOverlay(),
    OrientationOverlay(),
    PixelProbeOverlay(),
  ],
);
```

Public surface (`package:flutter_dicom/flutter_dicom.dart`): `dicom_engine.dart`,
`domain/` (source, frame, metadata, tag id, pixel data, window, color map,
geometry), application ports (parser, decoder, renderer, exporter, cache,
viewer state), `analysis/` (probe, ruler, ROI, segmentation),
`series/` (series + ordering strategies), `volume/` (volume, voxels, MPR,
projection, CPU renderer), `annotations/`, `cine/`, `export/` (PNG/JPEG/TIFF),
`writing/` (dataset, writer, structured reports), `fusion/`, `network/`
(DICOMweb, DIMSE PDU + client), presentation overlays, errors.
Rust internals and FRB-generated models are not part of the public contract.

Core patterns (each solves one problem, nothing decorative): Strategy for
decoders/renderers/windowing/reconstruction/projection/segmentation, State
for viewer/cine/association lifecycle, Adapter at the Rust boundary, Factory
for sources/exporters, Composite for annotations/overlays/SR, Mediator for
the MPR crosshair, Facade (`DicomEngine`), Repository for series/network
data, Proxy for lazy frames, LRU cache, Command for undoable/network ops,
Observer for reactive state. No singletons — lifetimes stay injectable.

---

## 🖥️ Workstation Demo

`example/` is a four-tab workstation exercising every milestone against the
public API only (one shared `DicomViewerController`, dumb widgets):

| Tab | Covers |
| :--- | :--- |
| **Viewer** | Open file / bytes / spatially-sorted series; presets + custom preset store; level/width; flip / rotate / zoom / invert; frames + cine + FPS; metadata grid |
| **Measure** | Tap probe readout (px / raw / HU / patient mm); two-tap ruler; rect/ellipse ROI + statistics; annotations (line/rect/arrow/text + undo/redo); threshold segmentation + mask overlay |
| **Volume** | Series assembly with progress; MPR (axial/coronal/sagittal, nearest/trilinear); MIP/MinIP on any axis; CPU 3D render; PET/CT fusion with overlay picker — all previewed as in-memory PNGs |
| **Share** | PNG/JPEG/TIFF export; Secondary Capture + Structured Report writing; DICOMweb search + STOW; DIMSE associate / C-ECHO / C-FIND / C-STORE / release |

```bash
cd example
flutter run
```

> A widget smoke test (`example/test/workstation_smoke_test.dart`) builds all
> four tabs with an injected fake engine — no native bridge required.

---

## ⚡ Performance Benchmarks

The **Flutter-Dicom** library is meticulously optimized for both blistering speed and strict memory efficiency. The following benchmarks were executed on an **AMD Ryzen™ 7 5800H (16 Threads)** using a clinical dataset of **267 DICOM frames**. 
The results highlight the massive performance overhead provided by our Rust + GPU Shader architecture.

### 📊 At-a-Glance Summary

| Metric | Performance | Status |
| :--- | :--- | :--- |
| **Max Throughput** | **~461 FPS** | ✅ Ultra Fast |
| **Pipeline Latency** | **2.16 ms / frame** | ✅ Sub-16ms |
| **Windowing Speed** | **~1.4M Ops/s** | ✅ Real-time |
| **Scrubbing Speed** | **266 Ops/s** | ✅ Fluid |
| **Stability (p99)** | **4.74 ms** | ✅ Consistent |

---

### 🔬 Detailed Deep Dive

#### 🚀 1. Raw Rendering & Latency Distribution
FFI bridge ensures that frame data flows from disk to GPU without bogging down the Dart isolate. Averaging **461 FPS** on the 267-frame series, the engine delivers rock-solid consistency.

**Latency Distribution:** Out of 801 sampled frames, the median processing time was **1.82 ms**. Even the 99th percentile (p99) maxed out at just **4.74 ms**, keeping us well below the 16.6ms threshold required for 60 FPS.

```text
▶ LATENCY DISTRIBUTION (801 Samples)
────────────────────────────────────────────────────
  Mean Latency   : 2.68 ms
  p50 (Median)   : 2.00 ms
  p95            : 4.00 ms
  p99            : 6.00 ms  ✅ (Well below 16.6ms target)
────────────────────────────────────────────────────
  Latency Histogram (bucket=5 ms):
    0– 5 ms │ ████████████████████████████   766
    5–10 ms │ █                               35
   10–15 ms │                                  0
   15–20 ms │                                  0
   20–25 ms │                                  0
────────────────────────────────────────────────────
```

#### 🎛️ 2. Workstation-Grade Interaction
Offloading Hounsfield Unit (HU) mapping to the GPU means complex math doesn't slow down your UI.
* **Windowing Stress Test:** Processed **14,685 rapid contrast adjustments** in just **4.32 seconds** (~3,402 ops/sec). Doctors can drag to adjust window levels as fast as humanly possible with instantaneous visual feedback.
* **Rapid Scrubbing:** Simulating fast bidirectional scrolling through the 267-frame series yielded **323 operations per second**.

#### 🧽 3. Memory Safety & Full Pipeline
Testing the complete lifecycle ensures there are no memory leaks during extended diagnostic sessions.
* **Full Pipeline:** Loading, parsing, rendering, windowing (x5), and disposing of all 267 files sequentially took under 1 second (**996.0 ms total**).
* **Controller Lifecycle:** Creating, loading, and safely destroying controllers for 267 frames averaged **3.57 ms** per file, proving rock-solid garbage collection and GPU texture freeing.

#### 🛡️ 4. Edge-Case Resilience
Medical data can be messy. The core engine is built to handle anomalies gracefully without crashing your Flutter app.
* **Mathematical Overflow:** Passing extreme windowing values (e.g., `9.0e+307` and `-9.0e+307`) resulted in safe handling with 0 load errors.
* **Concurrency Handling:** Rapid burst loads (firing 10 file loads with minimal await gaps) maintained a **232.6 Effective FPS** without race conditions.


---

## 🤝 Contributing

Contributions are welcome! Here’s how to get started:

1.  Fork the repository.
2.  Create a new branch:
    `git checkout -b feature/YourFeature`
3.  Commit your changes:
    `git commit -m "Add amazing feature"`
4.  Push to your branch:
    `git push origin feature/YourFeature`
5.  Open a pull request.

> 💡 Please read our **[Contributing Guidelines](CONTRIBUTING.md)** and open an issue first for major feature ideas or changes.

---
## ⚖️ License

This project is dual-licensed:

1. **Open Source License**: GPL-3.0
   - Free to use, modify, and distribute under GPL terms.
   - Any distributed modified version must also be GPL-3.0.

2. **Commercial License**:
   - Required for using the library in proprietary / closed-source products.
   - Only available from the copyright holder (Mostafa Mahmoud).
   - Contact: [mostafasensei106@gmail.com](mailto:mostafasensei106@gmail.com)

See the [LICENSE](LICENSE) file for full details.

<p align="center">
  Made with ❤️ by <a href="https://github.com/MostafaSensei106">MostafaSensei106</a>
</p>
