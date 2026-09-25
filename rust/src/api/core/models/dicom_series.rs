use crate::api::core::models::dicom_metadata::DicomMetadata;

#[derive(Debug, Clone)]
pub struct DicomSlice {
    pub file_path: String,
    pub metadata: DicomMetadata,
}

#[derive(Debug, Clone)]
pub struct DicomSeries {
    pub series_instance_uid: String,
    pub slices: Vec<DicomSlice>,
}
