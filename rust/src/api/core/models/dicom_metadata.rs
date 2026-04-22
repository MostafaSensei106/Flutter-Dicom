/// Represents the extracted medical metadata from a DICOM file header.
///
/// This struct contains critical parameters for clinical rendering,
/// including spatial dimensions, windowing defaults, and patient identity.
#[derive(Debug, Clone)]
pub struct DicomMetadata {
    /// The name of the patient as recorded in the file header.
    pub patient_name: String,

    /// The Photometric Interpretation (e.g., "MONOCHROME1", "MONOCHROME2").
    /// Informs the renderer how to map pixel values to grayscale intensities.
    pub photometric_interpretation: String,

    /// The number of pixel columns in the image.
    pub width: u32,
    /// The number of pixel rows in the image.
    pub height: u32,

    /// The default Window Center (Level) provided in the DICOM metadata.
    pub window_center: f32,
    /// The default Window Width provided in the DICOM metadata.
    pub window_width: f32,

    /// The Rescale Intercept (Tag 0028,1052).
    pub rescale_intercept: f32,
    /// The Rescale Slope (Tag 0028,1053).
    pub rescale_slope: f32,

    /// The number of color components in this image (e.g., 1 for Grayscale).
    pub samples_per_pixel: u16,

    /// The number of bits allocated per pixel (typically 16).
    pub bits_allocated: u16,
    /// The number of bits actually used to store the pixel data (typically 12 or 16).
    pub bits_stored: u16,
    /// The most significant bit of the pixel data (typically bits_stored - 1).
    pub high_bit: u16,

    /// Specifies whether the pixel data is signed (1) or unsigned (0).
    pub pixel_representation: u16,
}
