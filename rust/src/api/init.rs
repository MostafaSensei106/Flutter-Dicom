use crate::api::core::{
    config::dicom_config::DicomConfig, models::dicom_frame_result::DicomFrameResult,
    utils::process_dicom_file::process_dicom_file,
};

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub fn load_dicom(path: String, config: DicomConfig) -> anyhow::Result<DicomFrameResult> {
    process_dicom_file(&path, &config)
}
