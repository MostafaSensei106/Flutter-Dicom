use flutter_rust_bridge::frb;

use crate::api::core::constants::lib_constants::DefaultConfigs;

#[derive(Debug, Clone)]
#[frb()]
pub struct DicomConfig {
    pub auto_normalize: bool,
    pub skip_pixels: bool,
}

impl Default for DicomConfig {
    fn default() -> Self {
        Self {
            auto_normalize: DefaultConfigs::AUTO_NORMALIZE,
            skip_pixels: DefaultConfigs::SKIP_PIXELS,
        }
    }
}
