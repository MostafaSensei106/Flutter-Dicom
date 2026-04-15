<h1 align="center">Flutter-Dicom</h1>
<p align="center">
  <img src="https://socialify.git.ci/MostafaSensei106/Flutter-Dicom/image?custom_language=Rust&font=KoHo&language=1&logo=https%3A%2F%2Fraw.githubusercontent.com%2Fdicom-rs%2Fdicom-rs%2Fmaster%2Flogo.png&name=1&owner=1&pattern=Floating+Cogs&theme=Light" alt="Banner">
</p>

<p align="center">
  <strong>The Industry-Standard DICOM Engine for Flutter.</strong><br>
  High-performance medical imaging powered by <b>Rust</b> and <b>Hardware-Accelerated Fragment Shaders</b>.
</p>

<p align="center">
  <a href="#-architectural-philosophy">Architecture</a> •
  <a href="#-high-fidelity-rendering">Rendering Pipeline</a> •
  <a href="#-benchmarks--comparison">Benchmarks</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-enterprise-patterns">Enterprise Usage</a> •
  <a href="#-advanced-shaders">Shaders</a>
</p>

---

## 🏗️ Architectural Philosophy

> **Medical diagnostics don't tolerate compromises.**
> Pure Dart implementations fail when handling large volumetric data or 16-bit high-dynamic-range pixels. We built `Flutter-Dicom` with a **Native-First** mindset.

Our architecture offloads CPU-intensive parsing to a dedicated Rust isolate and delegates pixel manipulation to the GPU. This ensures the Flutter UI thread (Main Isolate) remains exclusively for interactions, maintaining a consistent 60/120 FPS even during complex windowing adjustments.

### 📊 Engineering Comparison

| Capability | `Image.memory()` | Pure Dart DICOM | **Flutter-Dicom (Hybrid)** |
| :--- | :---: | :---: | :--- |
| **Bit-Depth Precision** | 8-bit (Clamped) | 16-bit (Software) | **✅ 16-bit (Full Range)** |
| **Windowing Logic** | ❌ N/A | ⚠️ CPU (Slow/Heat) | **⚡ GPU (Shader-Based)** |
| **Memory Pressure** | 🔴 High (Copying) | 🔴 High (GC overhead) | **🟢 Zero-Copy (FFI Buffer)** |
| **Parsing Speed** | Fast (Native) | Slow (Dart VM) | **🚀 Ultra-Fast (Rust/LLVM)** |
| **Extensibility** | Fixed | Low | **🏗️ IDicomLoader Abstraction** |
| **Diagnostic Quality** | Low (Lossy) | Medium | **💎 High (Lossless)** |

---

## ✨ Key Technical Pillars

### 🚀 Rust/LLVM Processing Core
We use `dicom-rs` compiled to native machine code. This allows us to handle:
- **Streaming Parsing**: Efficiently reading multi-frame datasets.
- **Transfer Syntax Support**: Native handling of uncompressed, RLE, and JPEG-lossless encodings.
- **Type-Safe Metadata**: Rigorous parsing of the DICOM tag dictionary.

### 🎨 GPU Fragment Shader Pipeline
Standard rendering downsamples 16-bit medical data to 8-bit, losing critical diagnostic information. Our pipeline:
1.  **Bit-Packing**: We pack 16-bit signed integers into the Red and Green channels of an RGBA texture.
2.  **Bit-Unpacking (Shader Level)**: The GLSL shader reconstructs the 16-bit value in real-time.
3.  **Linear Mapping**: Applies Hounsfield Unit (HU) rescaling and Window/Level algorithms directly on the GPU.

### 🔒 Memory & Thread Safety
- **Isolate-Level FFI**: Heavy computation never blocks the UI.
- **Resource Management**: Native memory is managed via Rust's ownership model, preventing leaks common in platform-channel implementations.

---

## 📦 Installation & Setup

> [!NOTE]
> This library requires the Rust toolchain for the initial build to compile the performance core for your specific target architecture.

### 1. Toolchain Setup
```bash
# Install Rust (Unix/macOS)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### 2. Dependency Integration
Add to `pubspec.yaml`:
```yaml
dependencies:
  flutter_dicom: ^0.1.0

flutter:
  shaders:
    - packages/flutter_dicom/shaders/dicom_window.frag
```

---

## 🚀 Enterprise Usage Patterns

### Dependency Injection & Services
We follow **SOLID** principles to ensure the library fits into enterprise-scale apps using Clean Architecture.

```dart
// Define your loading strategy (File, Network, or encrypted storage)
final dicomService = DicomService(loader: FileDicomLoader());
final controller = DicomController(service: dicomService);

// Initialize GPU resources
await controller.initialize();

// Reactive State Management
ValueListenableBuilder(
  valueListenable: controller,
  builder: (context, state, _) {
    return DicomViewer(controller: controller);
  },
);
```

### The "Diagnostic Guard" Pattern
Prevent rendering until precision requirements are met:

```dart
Future<void> safeLoad(String path) async {
  try {
    await controller.loadFromFile(
      filePath: path,
      config: DicomConfig(autoNormalize: true),
    );
    
    // Verify metadata integrity before display
    if (controller.metadata!.bitsStored < 12) {
      throw DiagnosticQualityException("Insufficient bit depth for diagnosis");
    }
  } catch (e) {
    logger.e("DICOM Pipeline Failure", e);
  }
}
```

---

## 🔬 Deep Dive: The Shader Unpacking Logic

For the senior engineers curious about our precision handling, here is how we maintain 16-bit integrity through an 8-bit texture interface:

```glsl
// Inside dicom_window.frag
void main() {
    vec4 texColor = texture(u_texture, uv);
    
    // Unpack: R (High Byte), G (Low Byte)
    // Reconstruct -32768 to 32767 range
    float raw_value = (texColor.r * 255.0 * 256.0 + texColor.g * 255.0) - 32768.0;
    
    // Apply Rescale Intercept & Slope
    float hu = (raw_value * u_rescale_slope) + u_rescale_intercept;
    
    // Windowing WindowCenter/WindowWidth
    float mapped = (hu - (u_window_center - u_window_width/2.0)) / u_window_width;
    fragColor = vec4(vec3(clamp(mapped, 0.0, 1.0)), 1.0);
}
```

---

## 🧪 Testing Rigor

`Flutter-Dicom` is built for clinical environments where failure isn't an option. Our CI/CD pipeline runs:
- **Rust Crate Tests**: Ensuring byte-perfect parsing.
- **Flutter Goldens**: Pixel-by-pixel rendering verification.
- **Memory Profiling**: Ensuring zero-leak under continuous frame loading.

---

## 🤝 Contributing

We welcome contributions from Medical Imaging experts and Rustaceans. Please read our [Development Architecture Guide](CONTRIBUTING.md).

---

## 📜 License

Licensed under **MIT**. For commercial support or specialized Transfer Syntax implementations, contact the maintainers.

<p align="center">
  Engineering the future of Mobile Diagnostics by <a href="https://github.com/MostafaSensei106">MostafaSensei106</a>
</p>
