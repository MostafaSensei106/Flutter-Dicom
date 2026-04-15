use crate::api::core::models::dicom_metadata::DicomMetadata;

#[derive(Debug)]
pub struct DicomFrameResult {
    pub metadata: DicomMetadata,
    pub pixel_data: Vec<i16>,
}
