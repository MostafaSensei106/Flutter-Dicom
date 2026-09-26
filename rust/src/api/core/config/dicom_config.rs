use crate::api::core::constants::lib_constants::DefaultConfigs;

/// Configuration options for the DICOM processing engine.
///
/// Use this struct to tune the balance between precision and performance.
#[derive(Debug, Clone)]
pub struct DicomConfig {
    /// Recompute window center/width from the decoded pixel histogram even
    /// when the header provides values. Useful for modalities with missing
    /// or unreliable windowing tags (MR, XA, US).
    pub auto_normalize: bool,

    /// If true, the Rust engine will only parse the file metadata (tags) and
    /// skip the expensive pixel data extraction. This is useful for building
    /// fast metadata viewers or file explorers.
    pub skip_pixels: bool,

    /// Zero-based frame index for multi-frame files (NumberOfFrames > 1).
    /// Out-of-range values fall back to frame 0.
    pub frame_index: u32,
}

impl Default for DicomConfig {
    /// Provides the standard production-ready defaults:
    /// - auto_normalize: false
    /// - skip_pixels: false
    /// - frame_index: 0
    fn default() -> Self {
        Self {
            auto_normalize: DefaultConfigs::AUTO_NORMALIZE,
            skip_pixels: DefaultConfigs::SKIP_PIXELS,
            frame_index: 0,
        }
    }
}
