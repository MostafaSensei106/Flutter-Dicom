<h1 align="center">Flutter-Dicom</h1>
<p align="center">
  <img src="https://socialify.git.ci/MostafaSensei106/Flutter-Dicom/image?custom_language=Rust&font=KoHo&language=1&logo=https%3A%2F%2Favatars.githubusercontent.com%2Fu%2F138288138%3Fv%3D4&name=1&owner=1&pattern=Floating+Cogs&theme=Light" alt="Banner">
</p>

<p align="center">
  <strong>An advanced medical imaging and DICOM processing library for Flutter, poIred by a high-performance Rust core and GPU Shaders.</strong><br>
  Go beyond basic image loading. Deliver <i>workstation-grade</i> rendering, <i>16-bit precision</i>, and <i>real-time windowing</i> in your medical apps.
</p>

<p align="center">
  <a href="#-why-choose-flutter-dicom">Why?</a> •
  <a href="#-key-features">Key Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-basic-usage">Basic Usage</a> •
  <a href="#-advanced-usage">Advanced Usage</a> •
  <a href="#-contributing">Contributing</a>
</p>

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
  final _controller = DefaultDicomViewerController();

  @override
  void initState() {
    super.initState();
    _controller.load(const DicomSource.file('/sdcard/scans/head_ct.dcm'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DicomViewer(
        controller: _controller,
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
    _controller.dispose(); // Critical: frees GPU textures
    super.dispose();
  }
}
```

### 3. Adjusting Windowing Programmatically

```dart
// Named clinical presets
void applyBoneWindow() {
  _controller.setWindow(DicomWindowPreset.bone);
}

// Reset to file defaults
void reset() => _controller.reset();
```

---

## 🔬 Advanced Usage

### Any Source, Same Pipeline

```dart
final engine = await DicomEngine.create();

// Local file, in-memory bytes (Web / PACS), or file lists (series).
final doc = await engine.open(const DicomSource.file('scan.dcm'));
final webDoc = await engine.open(DicomSource.bytes(bytes));
final seriesDoc = await engine.open(DicomSource.files(paths));

// Parse ≠ decode: fetch frames lazily, never 400 buffers at once.
final frame = await doc.frames.get(0);
final pixels = await doc.decodeFrame(3);

// Typed metadata with unknown-tag fallback.
final name = doc.metadata.patientName ?? 'Anonymous';
final kvp = doc.metadata.tag<double>(const DicomTagId(0x0018, 0x0060));
```

### Windowing, Cine & Analysis

```dart
// Window presets + modality-aware default.
_controller.setWindow(DicomWindowPreset.lung);
_controller.setWindow(doc.metadata.defaultWindow);

// Cine playback over the document.
final cine = DefaultDicomCineController(onFrame: _controller.setFrame);
await cine.play(frameCount: doc.frameCount);

// Probing, ROI stats, and physical measurements share one HU owner.
const probe = ModalityProbe();
final result = probe.probe(pixels, const DicomPoint(128, 128));
final stats = await DicomRoi(const DicomRect(0, 0, 64, 64)).analyze(pixels);
final dist = const DicomRuler().measure(a, b, geometry);

// PNG export of the windowed view.
final png = await const PngDicomExporter().exportWindowed(
  pixels,
  DicomWindowPreset.bone,
);
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
`domain/` (source, metadata, tag id, pixel data, window, color map, geometry),
application ports, `analysis/`, `series/`, `volume/`, `annotations/`, `cine/`,
`network/`, `export` ports. Rust internals and FRB-generated models are not
part of the public contract.

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
