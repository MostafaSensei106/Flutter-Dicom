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

impl DicomMetadata {
    /// Creates a new [DicomMetadata] instance by copying values from another.
    /// Useful for ensuring a clean ownership transfer when constructing results.
    pub fn new(data: DicomMetadata) -> Self {
        return Self {
            patient_name: data.patient_name,
            photometric_interpretation: data.photometric_interpretation,
            width: data.width,
            height: data.height,
            window_center: data.window_center,
            window_width: data.window_width,
            rescale_intercept: data.rescale_intercept,
            rescale_slope: data.rescale_slope,
            samples_per_pixel: data.samples_per_pixel,
            bits_allocated: data.bits_allocated,
            bits_stored: data.bits_stored,
            high_bit: data.high_bit,
            pixel_representation: data.pixel_representation,
        };
    }
}
impl Default for DicomMetadata {
    /// Provides sensible default values for DICOM metadata.
    /// These defaults are used when specific tags are missing from the file header.
    fn default() -> Self {
        return Self {
            patient_name: "Unknown".to_string(),
            photometric_interpretation: "MONOCHROME2".to_string(),
            width: 0,
            height: 0,
            window_center: 40.0,
            window_width: 400.0,
            rescale_intercept: 0.0,
            rescale_slope: 1.0,
            samples_per_pixel: 1,
            bits_allocated: 16,
            bits_stored: 16,
            high_bit: 15,
            pixel_representation: 0,
        };
    }
}
