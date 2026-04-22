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
  flutter_dicom: ^0.1.0+2
```

---

## 🚀 Basic Usage

### 1. Initialization

Initialize the library in your `main()` function before starting the app.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the native Rust binary into memory
  await RustLib.init();
  
  runApp(const MyApp());
}
```

### 2. Loading and Displaying DICOM

The `DicomController` is the brain of your Viewer. Pair it with the `DicomViewer` widget for an instant medical-grade experience.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dicom/flutter_dicom.dart';

class MyMedicalApp extends StatefulWidget {
  @override
  State<MyMedicalApp> createState() => _MyMedicalAppState();
}

class _MyMedicalAppState extends State<MyMedicalApp> {
  final _controller = DicomController();

  @override
  void initState() {
    super.initState();
    // Initialize shaders and load a file
    _controller.initialize().then((_) {
      _controller.loadFromFile(filePath: '/sdcard/scans/head_ct.dcm');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DicomViewer(controller: _controller),
    );
  }

  @override
  void dispose() {
    _controller.dispose(); // Critical: Free GPU textures
    super.dispose();
  }
}
```

### 3. Adjusting Windowing Programmatically

```dart
// Manually set Window Center and Width
void applyBoneWindow() {
  _controller.adjustWindowing(deltaX: 1500, deltaY: 300);
}

// Reset to file defaults
void reset() => _controller.resetWindowing();
```

---

## 🔬 Advanced Usage

### Custom Rust Logic with `DicomConfig`

You can tune the Rust engine for specific use cases, such as fast-loading metadata while skipping expensive pixel processing.

```dart
await _controller.loadFromFile(
  filePath: path,
  config: DicomConfig(
    autoNormalize: true, 
    skipPixels: true, // Meta-data only mode
  ),
);
```

### Dependency Injection (DI) Architecture

For enterprise apps, inject a custom `DicomService` to handle different storage backends (S3, local cache, etc.).

```dart
// 1. Define the service with a specific loader
final service = DicomService(loader: FileDicomLoader());

// 2. Inject into the controller
final controller = DicomController(service: service);
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

## ⚡ Performance Benchmarks

The **Flutter-Dicom** library is meticulously optimized for both blistering speed and strict memory efficiency. The following benchmarks were executed on an **AMD Ryzen™ 7 5800H (16 Threads)** using a clinical dataset of **267 DICOM frames**. 

The results highlight the massive performance overhead provided by our Rust + GPU Shader architecture, delivering true workstation-grade capabilities directly inside Flutter.

### 📊 At-a-Glance Summary

| Metric | Performance | Clinical Impact |
| :--- | :--- | :--- |
| **Max Throughput** | **~296 FPS** | Flawless rendering on 120Hz/144Hz displays. |
| **Pipeline Latency** | **3.73 ms / frame** | Instantaneous loading of massive CT/MRI studies. |
| **Windowing Speed** | **3,402 Ops/s** | Zero-lag, real-time contrast & brightness tuning. |
| **Scrubbing Speed** | **323 Ops/s** | Buttery smooth scrolling through slices. |
| **Stability (p99)** | **6.00 ms** | Ultra-consistent frame times; absolutely no UI stutter. |

---

### 🔬 Detailed Deep Dive

#### 🚀 1. Raw Rendering & Latency Distribution
Our zero-copy FFI bridge ensures that frame data flows from disk to GPU without bogging down the Dart isolate. Averaging **296.2 FPS**, the engine delivers rock-solid consistency. 

Out of 801 sampled frames, **95.6% were processed in under 5ms**. Here is the exact latency distribution showcasing our jitter-free pipeline:

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


**Latency Distribution:** Out of 801 sampled frames, the mean processing time was **2.68 ms**. Even the 99th percentile (p99) maxed out at just **6.00 ms**, keeping us well below the 16.6ms threshold required for 60 FPS.

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
## 📜 License

This project is licensed under the **GPL-3.0 License**.
See the [LICENSE](LICENSE) file for full details.

<p align="center">
  Made with ❤️ by <a href="https://github.com/MostafaSensei106">MostafaSensei106</a>
</p>
