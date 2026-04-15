#[derive(Debug, Clone)]
pub struct DicomMetadata {
    pub width: u32,
    pub height: u32,
    pub window_center: f32,
    pub window_width: f32,
    pub rescale_intercept: f32,
    pub rescale_slope: f32,
    pub patient_name: String,
    pub photometric_interpretation: String,
    pub samples_per_pixel: u16,
    pub bits_allocated: u16,
    pub bits_stored: u16,
    pub high_bit: u16,
    pub pixel_representation: u16,
}
