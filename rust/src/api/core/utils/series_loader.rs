use std::fs;
use std::collections::HashMap;
use anyhow::Result;

use crate::api::core::{
    config::dicom_config::DicomConfig,
    utils::process_dicom_file::process_dicom_file,
    models::dicom_series::{DicomSeries, DicomSlice},
};

pub struct SeriesLoader {}

impl SeriesLoader {
    /// Loads all DICOM files in a directory, applies a sorting strategy, and groups them by Series Instance UID.
    pub fn load_directory(dir_path: &str) -> Result<Vec<DicomSeries>> {
        let mut paths = Vec::new();
        if let Ok(entries) = fs::read_dir(dir_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_file() {
                    paths.push(path.to_string_lossy().to_string());
                }
            }
        }
        Self::load_files(paths)
    }

    /// Loads a specific set of DICOM files.
    pub fn load_files(paths: Vec<String>) -> Result<Vec<DicomSeries>> {
        let mut config = DicomConfig::default();
        config.skip_pixels = true; // IMPORTANT for fast loading!
        
        let mut slices = Vec::new();
        
        for path in paths {
            if let Ok(result) = process_dicom_file(&path, &config) {
                slices.push(DicomSlice {
                    file_path: path,
                    metadata: result.metadata,
                });
            }
        }
        
        // Group by series instance UID
        let mut series_map: HashMap<String, Vec<DicomSlice>> = HashMap::new();
        
        for slice in slices {
            let uid = slice.metadata.series_instance_uid.clone();
            series_map.entry(uid).or_default().push(slice);
        }
        
        let mut output = Vec::new();
        for (uid, mut slice_group) in series_map {
            let has_spatial = slice_group.iter().any(|s| s.metadata.slice_location != 0.0);
            if has_spatial {
                slice_group.sort_by(|a, b| {
                    a.metadata.slice_location.partial_cmp(&b.metadata.slice_location)
                        .unwrap_or(std::cmp::Ordering::Equal)
                });
            } else {
                slice_group.sort_by(|a, b| {
                    let num_a = a.metadata.instance_number.parse::<i32>().unwrap_or(0);
                    let num_b = b.metadata.instance_number.parse::<i32>().unwrap_or(0);
                    num_a.cmp(&num_b)
                });
            }
            
            output.push(DicomSeries {
                series_instance_uid: uid,
                slices: slice_group,
            });
        }
        
        Ok(output)
    }
}
