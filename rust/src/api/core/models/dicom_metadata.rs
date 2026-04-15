#[derive(Debug, Clone)]
pub struct DicomMetadata {
    pub width: u32,
    pub height: u32,
    pub window_center: f32,
    pub window_width: f32,
    pub rescale_intercept: f32,
    pub rescale_slope: f32,
    pub patient_name: String,
}
