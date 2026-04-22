use crate::api::core::constants::lib_constants::DefaultConfigs;

/// Configuration options for the DICOM processing engine.
///
/// Use this struct to tune the balance between precision and performance.
#[derive(Debug, Clone)]
pub struct DicomConfig {
    /// If true, the pixel values will be automatically normalized into standard ranges
    /// based on the metadata found in the DICOM headers.
    pub auto_normalize: bool,

    /// If true, the Rust engine will only parse the file metadata (tags) and
    /// skip the expensive pixel data extraction. This is useful for building
    /// fast metadata viewers or file explorers.
    pub skip_pixels: bool,
}

impl Default for DicomConfig {
    /// Provides the standard production-ready defaults:
    /// - auto_normalize: true
    /// - skip_pixels: false
    fn default() -> Self {
        Self {
            auto_normalize: DefaultConfigs::AUTO_NORMALIZE,
            skip_pixels: DefaultConfigs::SKIP_PIXELS,
        }
    }
}
