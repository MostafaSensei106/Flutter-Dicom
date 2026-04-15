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

    let photometric_interpretation = obj
        .element(tags::PHOTOMETRIC_INTERPRETATION)
        .map(|e| e.to_str().unwrap_or_default().to_string())
        .unwrap_or_else(|_| "MONOCHROME2".to_string());
    
    let samples_per_pixel = obj
        .element(tags::SAMPLES_PER_PIXEL)
        .map(|e| e.to_int::<u16>().unwrap_or(1))
        .unwrap_or(1);

    let bits_allocated = obj
        .element(tags::BITS_ALLOCATED)
        .map(|e| e.to_int::<u16>().unwrap_or(16))
        .unwrap_or(16);

    let bits_stored = obj
        .element(tags::BITS_STORED)
        .map(|e| e.to_int::<u16>().unwrap_or(16))
        .unwrap_or(16);

    let high_bit = obj
        .element(tags::HIGH_BIT)
        .map(|e| e.to_int::<u16>().unwrap_or(15))
        .unwrap_or(15);

    let pixel_representation = obj
        .element(tags::PIXEL_REPRESENTATION)
        .map(|e| e.to_int::<u16>().unwrap_or(0))
        .unwrap_or(0);

    let metadata = DicomMetadata {
        width,
        height,
        window_center,
        window_width,
        rescale_intercept,
        rescale_slope,
        patient_name,
        photometric_interpretation,
        samples_per_pixel,
        bits_allocated,
        bits_stored,
        high_bit,
        pixel_representation,
    };

    let mut pixel_data: Vec<i16> = Vec::new();
    if !config.skip_pixels {
        // Try to get raw pixel data as i16
        // This works for most uncompressed grayscale DICOM files
        let element = obj.element(tags::PIXEL_DATA).context("Pixel data element not found")?;
        
        // For uncompressed data, we can try to convert to a vector of i16
        // Note: this might need adjustment for different transfer syntaxes or bit depths
        pixel_data = element.to_multi_float64()
            .map(|v| v.into_iter().map(|f| f as i16).collect())
            .unwrap_or_else(|_| {
                // Fallback: try to read as integers if floats don't work
                element.to_multi_int::<i16>().unwrap_or_default()
            });
            
        if pixel_data.is_empty() {
             // Second fallback: try to read raw bytes and manually convert
             let raw_bytes = element.to_bytes().unwrap_or_default();
             if !raw_bytes.is_empty() {
                // Assume 16-bit little endian if we have bytes but to_multi_int failed
                pixel_data = raw_bytes.chunks_exact(2)
                    .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
                    .collect();
             }
        }
    }

    Ok(DicomFrameResult {
        metadata,
        pixel_data,
    })
}
