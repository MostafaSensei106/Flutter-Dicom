use flutter_rust_bridge::frb;

use crate::api::core::models::dicom_metadata::DicomMetadata;

/// Represents a single processed DICOM frame, ready for rendering.
///
/// It encapsulates both the medical [metadata] extracted from the headers
/// and the raw [pixel_data] buffer processed by the Rust engine.
#[derive(Debug)]
#[frb(sync)]
pub struct DicomFrameResult {
    /// The clinical and technical metadata associated with this frame.
    pub metadata: DicomMetadata,

    /// A 16-bit integer buffer containing the raw pixel values.
    /// This buffer maintains full diagnostic precision and is designed
    /// for GPU consumption via fragment shaders.
    pub pixel_data: Vec<i16>,
}

impl DicomFrameResult {
    /// Creates a new instance of [DicomFrameResult] from an existing one.
    pub fn new(result: DicomFrameResult) -> Self {
        return Self {
            metadata: result.metadata,
            pixel_data: result.pixel_data,
        };
    }
}
