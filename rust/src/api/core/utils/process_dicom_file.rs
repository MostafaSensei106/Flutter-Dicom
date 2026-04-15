use crate::api::core::{
    config::dicom_config::DicomConfig,
    models::{dicom_frame_result::DicomFrameResult, dicom_metadata::DicomMetadata},
};
use anyhow::{Context, Result};
use dicom::dictionary_std::tags;
use dicom::object::open_file;

pub fn process_dicom_file(path: &str, config: &DicomConfig) -> Result<DicomFrameResult> {
    let obj = open_file(path).context("Failed to open file")?;

    let width = obj.element(tags::COLUMNS)?.to_int::<u32>()?;
    let height = obj.element(tags::ROWS)?.to_int::<u32>()?;
    let window_center = obj
        .element(tags::WINDOW_CENTER)
        .map(|e| e.to_float32().unwrap_or(40.0))
        .unwrap_or(40.0);
    let window_width = obj
        .element(tags::WINDOW_WIDTH)
        .map(|e| e.to_float32().unwrap_or(400.0))
        .unwrap_or(400.0);
    let rescale_intercept = obj
        .element(tags::RESCALE_INTERCEPT)
        .map(|e| e.to_float32().unwrap_or(0.0))
        .unwrap_or(0.0);
    let rescale_slope = obj
        .element(tags::RESCALE_SLOPE)
        .map(|e| e.to_float32().unwrap_or(1.0))
        .unwrap_or(1.0);
    let patient_name = obj
        .element(tags::PATIENT_NAME)
        .map(|e| e.to_str().unwrap_or_default().to_string())
        .unwrap_or_else(|_| "Unknown".to_string());

    let metadata = DicomMetadata {
        width,
        height,
        window_center,
        window_width,
        rescale_intercept,
        rescale_slope,
        patient_name,
    };

    let mut pixel_data: Vec<i16> = Vec::new();
    if !config.skip_pixels {
        pixel_data = vec![0; (metadata.width * metadata.height) as usize]; // Dummy data
    }

    Ok(DicomFrameResult {
        metadata,
        pixel_data,
    })
}
