use crate::api::core::models::dicom_metadata::DicomMetadata;

/// Represents a single processed DICOM frame, ready for rendering.
///
/// It encapsulates both the medical [metadata] extracted from the headers 
/// and the raw [pixel_data] buffer processed by the Rust engine.
#[derive(Debug)]
pub struct DicomFrameResult {
    /// The clinical and technical metadata associated with this frame.
    pub metadata: DicomMetadata,

    /// A 16-bit integer buffer containing the raw pixel values.
    /// This buffer maintains full diagnostic precision and is designed 
    /// for GPU consumption via fragment shaders.
    pub pixel_data: Vec<i16>,
}
