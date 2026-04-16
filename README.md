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

## ✨ Key Features

- **🚀 High-Performance Rust Core**: All heavy lifting—file parsing, transfer syntax decoding, and 16-bit pixel extraction—happens in a native Rust engine. This ensures sub-millisecond parsing precision without ever dropping a frame in your Flutter UI.

- **🎨 GPU-Accelerated Shaders**: Medical Windowing (Level/Width) calculations aren't done on the CPU. I pack the 16-bit data into textures and compute the exact Hounsfield Units on the GPU via Fragment Shaders, ensuring a buttery smooth 60fps experience during drag gestures.

- **🩺 Diagnostic-Grade Precision**: 
  - Supports full 16-bit pixel depth (-32768 to 32767).
  - Automatically extracts `RescaleSlope` and `RescaleIntercept`.
  - Maps real-world physical values accurately to Hounsfield Units (HU).

- **🤝 Interactive Viewer Widget**: The built-in `DicomViewer` handles everything you need out of the box:
  - Interactive Pan & Zoom (`InteractiveViewer` integration).
  - Drag-to-adjust contrast (Window Width) and brightness (Window Center).
  - Double-tap to reset to original DICOM metadata defaults.

- **📈 Comprehensive Metadata**: Instantly access critical technical and patient data: `patientName`, `photometricInterpretation`, `samplesPerPixel`, `bitsAllocated`, `bitsStored`, `highBit`, and `pixelRepresentation`.

---

## 📸 Screenshots & Demo

| Windowing Demo | Interactive Zoom | Metadata View |
| :---: | :---: | :---: |
| <img src=".github/assets/windowing.gif" width="250" /> | <img src=".github/assets/zoom.gif" width="250" /> | <img src=".github/assets/metadata.png" width="250" /> |

| Bone Window | Soft Tissue Window | Lung Window |
| :---: | :---: | :---: |
| <img src=".github/assets/bone_window.png" width="250" /> | <img src=".github/assets/tissue_window.png" width="250" /> | <img src=".github/assets/lung_window.png" width="250" /> |

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
  flutter_dicom: ^0.1.0
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