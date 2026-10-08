use crate::api::core::{
    config::dicom_config::DicomConfig,
    models::{dicom_frame_result::DicomFrameResult, dicom_metadata::DicomMetadata},
};
use anyhow::{Context, Result};
use dicom::core::Tag;
use dicom::core::dictionary::DataDictionary;
use dicom::core::header::Header;
use dicom::dictionary_std::{tags, StandardDataDictionary};
use dicom::object::{open_file, DefaultDicomObject};
use dicom::core::value::Value as DicomValue;
use dicom::pixeldata::PixelDecoder;

/// Internal utility function for parsing a DICOM file and extracting its metadata and pixels.
///
/// This function uses the `dicom-rs` ecosystem to handle the complex structure of DICOM objects.
///
/// # Implementation Details:
/// - **Metadata Extraction**: Uses clean helper functions to extract all critical tags with
///   sensible fallback defaults for missing or malformed headers.
/// - **Resilience**: Provides sane defaults for missing tags often encountered in non-standard DICOM files.
/// - **Pixel Extraction**: Attempts direct byte-chunking first (fast path for uncompressed data),
///   falling back to the `dicom` crate's transfer-syntax-aware decoding for compressed formats.
///
/// # Returns
/// - `Ok(DicomFrameResult)` on successful processing.
/// - `Err` if the file could not be opened or is missing critical metadata.
pub fn process_dicom_file(path: &str, config: &DicomConfig) -> Result<DicomFrameResult> {
    let obj = open_file(path).context("Failed to open DICOM file")?;
    process_dicom_object(obj, config)
}

pub fn process_dicom_from_bytes(bytes: &[u8], config: &DicomConfig) -> Result<DicomFrameResult> {
    #[cfg(debug_assertions)]
    eprintln!("[RUST] process_dicom_from_bytes ENTRY: bytes.len={}", bytes.len());
    let cursor = std::io::Cursor::new(bytes);
    let obj = dicom::object::from_reader(cursor).context("Failed to read DICOM from bytes")?;
    #[cfg(debug_assertions)]
    eprintln!("[RUST] process_dicom_from_bytes: from_reader OK");
    process_dicom_object(obj, config)
}

fn process_dicom_object(obj: DefaultDicomObject, config: &DicomConfig) -> Result<DicomFrameResult> {
    #[cfg(debug_assertions)]
    eprintln!("[RUST] process_dicom_object START, skip_pixels={}", config.skip_pixels);

    let mut metadata = extract_metadata(&obj);
    let mut pixel_data = Vec::new();

    if !config.skip_pixels {
        #[cfg(debug_assertions)]
        eprintln!("[RUST] metadata built, starting pixel extraction...");
        pixel_data = extract_pixel_data(&obj, &metadata, config.frame_index);
    }

    #[cfg(debug_assertions)]
    eprintln!("[RUST] pixel_data.len={} (i16 elements) window_center={} window_width={}",
        pixel_data.len(), metadata.window_center, metadata.window_width);

    // Window defaults: recompute from the decoded pixels when the header
    // has no windowing OR when auto_normalize explicitly requests it.
    // This finally gives `auto_normalize` a real effect (previously dead).
    if !pixel_data.is_empty()
        && (metadata.window_width == 0.0 || config.auto_normalize)
    {
        if let (Some(&min), Some(&max)) = (pixel_data.iter().min(), pixel_data.iter().max()) {
            metadata.window_width = (max as f32 - min as f32).max(1.0);
            metadata.window_center = (min as f32 + max as f32) / 2.0;
        }
    }

    #[cfg(debug_assertions)]
    eprintln!("[RUST] DONE — returning DicomFrameResult");
    Ok(DicomFrameResult {
        metadata,
        pixel_data,
    })
}

fn extract_metadata(obj: &DefaultDicomObject) -> DicomMetadata {
    let default_meta = DicomMetadata::default();

    // --- Mandatory Dimensions ---
    let width = get_int_tag(obj, tags::COLUMNS, 0u32);
    let height = get_int_tag(obj, tags::ROWS, 0u32);

    // --- Patient & Study Demographics ---
    let patient_id = get_str_tag(obj, tags::PATIENT_ID).unwrap_or_else(|| default_meta.patient_id.clone());
    let patient_name = get_str_tag(obj, tags::PATIENT_NAME).unwrap_or_else(|| default_meta.patient_name.clone());
    let study_date = get_str_tag(obj, tags::STUDY_DATE).unwrap_or_else(|| default_meta.study_date.clone());
    let series_date = get_str_tag(obj, tags::SERIES_DATE).unwrap_or_else(|| default_meta.series_date.clone());
    let acquisition_date = get_str_tag(obj, tags::ACQUISITION_DATE).unwrap_or_else(|| default_meta.acquisition_date.clone());
    let content_date = get_str_tag(obj, tags::CONTENT_DATE).unwrap_or_else(|| default_meta.content_date.clone());
    let study_description = get_str_tag(obj, tags::STUDY_DESCRIPTION).unwrap_or_else(|| default_meta.study_description.clone());

    // --- Equipment & Institution ---
    let modality = get_str_tag(obj, tags::MODALITY).unwrap_or_else(|| default_meta.modality.clone());

    // --- Study / Series / Instance UIDs ---
    let study_instance_uid = get_str_tag(obj, tags::STUDY_INSTANCE_UID).unwrap_or_else(|| default_meta.study_instance_uid.clone());
    let series_instance_uid = get_str_tag(obj, tags::SERIES_INSTANCE_UID).unwrap_or_else(|| default_meta.series_instance_uid.clone());
    let sop_instance_uid = get_str_tag(obj, tags::SOP_INSTANCE_UID).unwrap_or_else(|| default_meta.sop_instance_uid.clone());

    // --- Acquisition Details ---
    let series_description = get_str_tag(obj, tags::SERIES_DESCRIPTION).unwrap_or_else(|| default_meta.series_description.clone());
    let body_part_examined = get_str_tag(obj, tags::BODY_PART_EXAMINED).unwrap_or_else(|| default_meta.body_part_examined.clone());

    // --- Tooth Identification (dental DICOM) ---
    let tooth_info = get_str_tag(obj, Tag(0x0018, 0x6032))
        .or_else(|| get_str_tag(obj, Tag(0x0018, 0x6033)))
        .or_else(|| get_str_tag(obj, Tag(0x0021, 0x1000)))
        .or_else(|| get_str_tag(obj, Tag(0x0029, 0x1010)))
        .or_else(|| get_str_tag(obj, Tag(0x7053, 0x1003)))
        .or_else(|| get_str_tag(obj, Tag(0x0021, 0x1005)))
        .or_else(|| get_str_tag(obj, Tag(0x0029, 0x1060)))
        .or_else(|| get_str_tag(obj, Tag(0x0021, 0x1030)))
        .or_else(|| get_str_tag(obj, tags::IMAGE_COMMENTS))
        .or_else(|| get_str_tag(obj, tags::ACQUISITION_PROTOCOL_NAME))
        .or_else(|| get_str_tag(obj, tags::ACQUISITION_CONTEXT_DESCRIPTION))
        .unwrap_or_default();

    let slice_thickness = get_float_tag(obj, tags::SLICE_THICKNESS, default_meta.slice_thickness);
    let instance_number = get_str_tag(obj, tags::INSTANCE_NUMBER).unwrap_or_else(|| default_meta.instance_number.clone());

    // --- Technical & Display Metadata ---
    let window_center_opt = obj.element(tags::WINDOW_CENTER).ok().and_then(|e| e.to_float32().ok());
    let window_width_opt = obj.element(tags::WINDOW_WIDTH).ok().and_then(|e| e.to_float32().ok());

    let mut window_center = window_center_opt.unwrap_or(0.0);
    let window_width = window_width_opt.unwrap_or(0.0);

    let rescale_intercept = get_float_tag(obj, tags::RESCALE_INTERCEPT, default_meta.rescale_intercept);
    let rescale_slope = get_float_tag(obj, tags::RESCALE_SLOPE, default_meta.rescale_slope);
    let photometric_interpretation = get_str_tag(obj, tags::PHOTOMETRIC_INTERPRETATION).unwrap_or_else(|| default_meta.photometric_interpretation.clone());

    let samples_per_pixel = get_int_tag(obj, tags::SAMPLES_PER_PIXEL, default_meta.samples_per_pixel);
    let bits_allocated = get_int_tag(obj, tags::BITS_ALLOCATED, default_meta.bits_allocated);
    let bits_stored = get_int_tag(obj, tags::BITS_STORED, default_meta.bits_stored);
    let high_bit = get_int_tag(obj, tags::HIGH_BIT, default_meta.high_bit);
    let pixel_representation = get_int_tag(obj, tags::PIXEL_REPRESENTATION, default_meta.pixel_representation);

    // --- Align DICOM window center with our offset pixel storage ---
    window_center = align_window_center(pixel_representation, bits_allocated, window_width, window_center);

    // --- Spatial Positioning (multi-slice / CBCT) ---
    let pixel_spacing = get_str_tag(obj, tags::PIXEL_SPACING).or_else(|| get_str_tag(obj, tags::IMAGER_PIXEL_SPACING)).unwrap_or_default();
    let image_position_patient = get_str_tag(obj, tags::IMAGE_POSITION_PATIENT).unwrap_or_default();
    let image_orientation_patient = get_str_tag(obj, tags::IMAGE_ORIENTATION_PATIENT).unwrap_or_default();
    let slice_location = get_float_tag(obj, tags::SLICE_LOCATION, 0.0);
    let spacing_between_slices = get_float_tag(obj, tags::SPACING_BETWEEN_SLICES, 0.0);
    let number_of_frames = get_int_tag(obj, tags::NUMBER_OF_FRAMES, 1u32);

    DicomMetadata {
        patient_id, patient_name, study_date, series_date, acquisition_date, content_date, study_description,
        modality, study_instance_uid, series_instance_uid, sop_instance_uid, series_description, body_part_examined,
        tooth_info, slice_thickness, instance_number, photometric_interpretation, width, height, window_center,
        window_width, rescale_intercept, rescale_slope, samples_per_pixel, bits_allocated, bits_stored, high_bit,
        pixel_representation, pixel_spacing, image_position_patient, image_orientation_patient, slice_location,
        spacing_between_slices, number_of_frames,
    }
}

fn extract_pixel_data(
    obj: &DefaultDicomObject,
    metadata: &DicomMetadata,
    frame_index: u32,
) -> Vec<i16> {
    let mut pixel_data = Vec::new();
    let bytes_per_sample = (metadata.bits_allocated as usize).div_ceil(8);
    let samples_per_frame = (metadata.width as usize) * (metadata.height as usize) * (metadata.samples_per_pixel as usize);
    let frame_bytes = samples_per_frame * bytes_per_sample;

    let raw_element = obj.element(tags::PIXEL_DATA).ok();
    let is_encapsulated = raw_element.as_ref().map(|e| matches!(e.value(), DicomValue::PixelSequence(_))).unwrap_or(false);

    // Selects the requested frame slice; falls back to frame 0 when the
    // index is out of range (backwards compatible with single-frame files).

    // PATH 1: raw element read (works for native/uncompressed data).
    if !is_encapsulated {
        if let Some(elem) = raw_element {
            if let Ok(raw_bytes) = elem.to_bytes() {
                let raw_slice = raw_bytes.as_ref();
                if !raw_slice.is_empty() && frame_bytes > 0 {
                    let frame = select_frame_bytes(raw_slice, frame_bytes, frame_index);
                    pixel_data = convert_pixels(frame, metadata.bits_allocated, metadata.pixel_representation);
                }
            }
        }
    }

    // PATH 2: compressed — use full decoder
    if pixel_data.is_empty() {
        if let Ok(decoded) = obj.decode_pixel_data() {
            // Prefer the decoded frame count API when available; fall back
            // to byte-slicing the concatenated buffer.
            let frame_count = decoded.number_of_frames() as usize;
            let raw_bytes = decoded.data();
            if !raw_bytes.is_empty() && frame_bytes > 0 {
                let frame = if frame_count > 1 {
                    select_frame_bytes(raw_bytes, frame_bytes, frame_index)
                } else if raw_bytes.len() > frame_bytes {
                    &raw_bytes[..frame_bytes]
                } else {
                    raw_bytes
                };
                pixel_data = convert_pixels(frame, metadata.bits_allocated, metadata.pixel_representation);
            }
        }
    }

    pixel_data
}

/// Returns the byte window for [frame_index], falling back to frame 0 when
/// the index is out of range (backwards compatible with single-frame files).
fn select_frame_bytes(buf: &[u8], frame_bytes: usize, frame_index: u32) -> &[u8] {
    if frame_bytes == 0 || buf.is_empty() {
        return &[];
    }
    let offset = (frame_index as usize).saturating_mul(frame_bytes);
    if offset >= buf.len() {
        if buf.len() > frame_bytes { &buf[..frame_bytes] } else { buf }
    } else {
        let end = (offset + frame_bytes).min(buf.len());
        &buf[offset..end]
    }
}

/// Min / max / mean of the stored pixel buffer (for auto-windowing UIs).
#[derive(Debug, Clone)]
pub struct PixelStats {
    pub min: i16,
    pub max: i16,
    pub mean: f32,
    pub count: u32,
}

/// Computes statistics without allocating a full frame result.
pub fn pixel_stats_for_path(path: &str, config: &DicomConfig) -> Result<PixelStats> {
    let result = process_dicom_file(path, config)?;
    Ok(pixel_stats_of(&result.pixel_data))
}

/// Computes statistics from in-memory bytes (Web path).
pub fn pixel_stats_for_bytes(bytes: &[u8], config: &DicomConfig) -> Result<PixelStats> {
    let result = process_dicom_from_bytes(bytes, config)?;
    Ok(pixel_stats_of(&result.pixel_data))
}

fn pixel_stats_of(pixels: &[i16]) -> PixelStats {
    if pixels.is_empty() {
        return PixelStats { min: 0, max: 0, mean: 0.0, count: 0 };
    }
    let min = *pixels.iter().min().unwrap_or(&0);
    let max = *pixels.iter().max().unwrap_or(&0);
    let sum: i64 = pixels.iter().map(|&v| v as i64).sum();
    PixelStats {
        min,
        max,
        mean: sum as f32 / pixels.len() as f32,
        count: pixels.len() as u32,
    }
}

/// A single flattened DICOM tag for debugging / tag-dump UIs.
/// Pixel Data values are truncated to keep the bridge payload small.
#[derive(Debug, Clone)]
pub struct DicomTagEntry {
    pub group: u16,
    pub element: u16,
    pub keyword: String,
    pub value: String,
}

const TAG_VALUE_LIMIT: usize = 256;

/// Flattens top-level dataset tags (skips bulky pixel data payloads).
pub fn dicom_tags_for_path(path: &str) -> Result<Vec<DicomTagEntry>> {
    let obj = open_file(path).context("Failed to open DICOM file")?;
    Ok(flatten_tags(&obj))
}

/// Tag dump from in-memory bytes (Web path).
pub fn dicom_tags_for_bytes(bytes: &[u8]) -> Result<Vec<DicomTagEntry>> {
    let cursor = std::io::Cursor::new(bytes);
    let obj = dicom::object::from_reader(cursor).context("Failed to read DICOM from bytes")?;
    Ok(flatten_tags(&obj))
}

fn flatten_tags(obj: &DefaultDicomObject) -> Vec<DicomTagEntry> {
    let mut out = Vec::new();
    for elem in obj.iter() {
        let tag = elem.header().tag();
        // Never ship full pixel payloads over the bridge.
        if tag == tags::PIXEL_DATA {
            out.push(DicomTagEntry {
                group: tag.group(),
                element: tag.element(),
                keyword: "PixelData".to_string(),
                value: "<pixel data>".to_string(),
            });
            continue;
        }
        let keyword = StandardDataDictionary
            .by_tag(tag)
            .map(|e| e.alias.to_string())
            .unwrap_or_else(|| format!("({:04X},{:04X})", tag.group(), tag.element()));
        let mut value = elem.value().to_str().map(|c| c.to_string()).unwrap_or_default();
        value = value.trim().to_string();
        if value.len() > TAG_VALUE_LIMIT {
            value.truncate(TAG_VALUE_LIMIT);
            value.push('…');
        }
        out.push(DicomTagEntry {
            group: tag.group(),
            element: tag.element(),
            keyword,
            value,
        });
    }
    out
}

// --- Helper Functions ---

/// Extracts a string value from a DICOM tag, trimming whitespace.
/// Returns `None` if the tag is missing or cannot be read as a string.
fn get_str_tag(obj: &DefaultDicomObject, tag: Tag) -> Option<String> {
    obj.element(tag)
        .ok()
        .and_then(|e| e.to_str().ok().map(|s| s.trim().to_string()))
}

/// Extracts a float value from a DICOM tag, falling back to the provided default.
fn get_float_tag(obj: &DefaultDicomObject, tag: Tag, default: f32) -> f32 {
    obj.element(tag)
        .ok()
        .and_then(|e| e.to_float32().ok())
        .unwrap_or(default)
}

/// Extracts an integer value from a DICOM tag, falling back to the provided default.
/// Generic over the integer type — works for `u16`, `u32`, etc.
fn get_int_tag<T>(obj: &DefaultDicomObject, tag: Tag, default: T) -> T
where
    T: TryFrom<i64> + Copy,
{
    obj.element(tag)
        .ok()
        .and_then(|e| e.to_int::<i64>().ok())
        .and_then(|v| T::try_from(v).ok())
        .unwrap_or(default)
}

/// Aligns a DICOM window centre with the stored-pixel coordinate space.
///
/// DICOM Window Center/Width are defined in the original pixel value space.
/// For unsigned data, our pipeline offsets raw pixel values by `-32768` to
/// fit in `i16` (and the shader reverses this) — but ONLY for sample widths
/// greater than 8 bits (`convert_pixels` keeps unsigned 8-bit samples in their
/// native `0..255` range). The window centre is offset identically to the
/// stored samples so that metadata and pixels share a coordinate space.
///
/// Offsetting an unsigned 8-bit centre (e.g. 128 → −32640) would put pixels
/// and window in incompatible coordinate systems and clip the whole image.
fn align_window_center(
    pixel_representation: u16,
    bits_allocated: u16,
    window_width: f32,
    window_center: f32,
) -> f32 {
    if pixel_representation == 0 && bits_allocated > 8 && window_width > 0.0 {
        window_center - 32768.0
    } else {
        window_center
    }
}

/// Converts raw pixel bytes into i16 values, applying offset for unsigned data.
///
/// [bytes] should be the raw pixel data (1 or 2 bytes per sample).
/// [bits_allocated] determines byte width (≤8 = 1 byte, >8 = 2 bytes).
/// [pixel_representation] = 0 for unsigned, 1 for signed.
fn convert_pixels(bytes: &[u8], bits_allocated: u16, pixel_representation: u16) -> Vec<i16> {
    if bits_allocated <= 8 {
        if pixel_representation == 1 {
            bytes.iter().map(|&b| b as i8 as i16).collect()
        } else {
            bytes.iter().map(|&b| b as i16).collect()
        }
    } else if bytes.len().is_multiple_of(2) {
        if pixel_representation == 0 {
            // Unsigned 16-bit → offset to signed range for shader
            bytes
                .as_chunks::<2>()
                .0
                .iter()
                .map(|chunk| {
                    let raw = u16::from_le_bytes([chunk[0], chunk[1]]);
                    (raw as i32 - 32768) as i16
                })
                .collect()
        } else {
            bytes
                .as_chunks::<2>()
                .0
                .iter()
                .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]))
                .collect()
        }
    } else {
        Vec::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── convert_pixels: 8-bit paths ─────────────────────────────

    #[test]
    fn converts_unsigned_8bit_passthrough() {
        // bits <= 8, pixel_representation == 0 → byte as positive i16.
        assert_eq!(convert_pixels(&[0, 1, 127, 128, 255], 8, 0), vec![0, 1, 127, 128, 255]);
    }

    #[test]
    fn converts_signed_8bit_two_complement() {
        // bits <= 8, pixel_representation == 1 → i8 sign extension.
        assert_eq!(convert_pixels(&[0, 1, 127, 128, 255], 8, 1), vec![0, 1, 127, -128, -1]);
    }

    // ── convert_pixels: 16-bit paths ────────────────────────────

    #[test]
    fn converts_signed_16bit_little_endian() {
        let bytes = [0x34, 0x12, 0xFC, 0xFF]; // 0x1234 = 4660; 0xFFFC = -4
        assert_eq!(convert_pixels(&bytes, 16, 1), vec![4660, -4]);
    }

    #[test]
    fn offsets_unsigned_16bit_into_signed_range() {
        // Unsigned raw 0 → 0 - 32768 = -32768
        assert_eq!(convert_pixels(&[0x00, 0x00], 16, 0), vec![-32768]);
        // Unsigned raw 0x8000 (32768) → 32768 - 32768 = 0
        assert_eq!(convert_pixels(&[0x00, 0x80], 16, 0), vec![0]);
        // Unsigned raw 0xFFFF (65535) → 65535 - 32768 = 32767
        assert_eq!(convert_pixels(&[0xFF, 0xFF], 16, 0), vec![32767]);
    }

    #[test]
    fn handles_16bit_little_endian_byte_order() {
        // 0x1234 little-endian is bytes [0x34, 0x12].
        let bytes = [0x34, 0x12];
        assert_eq!(convert_pixels(&bytes, 16, 1), vec![0x1234]);
        // Wrong order [0x12, 0x34] gives 0x3412.
        assert_eq!(convert_pixels(&[0x12, 0x34], 16, 1), vec![0x3412]);
    }

    #[test]
    fn returns_empty_for_odd_length_16bit() {
        // Buffers with a trailing byte cannot be chunked → empty.
        assert_eq!(convert_pixels(&[0x01, 0x02, 0x03], 16, 0), Vec::<i16>::new());
        assert_eq!(convert_pixels(&[0x01, 0x02, 0x03], 16, 1), Vec::<i16>::new());
    }

    #[test]
    fn returns_empty_for_empty_input() {
        assert_eq!(convert_pixels(&[], 16, 0), Vec::<i16>::new());
        assert_eq!(convert_pixels(&[], 16, 1), Vec::<i16>::new());
        assert_eq!(convert_pixels(&[], 8, 0), Vec::<i16>::new());
    }

    #[test]
    fn boundary_bits_allocated_switches_width() {
        // bits_allocated == 8 → 1-byte path.
        assert_eq!(convert_pixels(&[255], 8, 0), vec![255]);
        // bits_allocated == 9 → 2-byte path.
        assert_eq!(convert_pixels(&[0xFF, 0xFF], 9, 0), vec![32767]);
        // bits_allocated == 0 ≤ 8 → treated as 1-byte.
        assert_eq!(convert_pixels(&[7], 0, 0), vec![7]);
    }

    #[test]
    fn signed_16bit_full_range_roundtrip() {
        // -32768 (0x8000) and 32767 (0x7FFF) round-trip exactly.
        assert_eq!(convert_pixels(&[0x00, 0x80], 16, 1), vec![-32768]);
        assert_eq!(convert_pixels(&[0xFF, 0x7F], 16, 1), vec![32767]);
    }

    // ── align_window_center: unsigned 8-bit vs 16-bit ──────────

    #[test]
    fn offset_unsigned_16bit_window_center_into_signed_range() {
        // Unsigned 16-bit samples are shifted -32768; the centre must be too.
        // DICOM centre 32768 → 0 in stored-pixel space.
        assert_eq!(align_window_center(0, 16, 256.0, 32768.0), 0.0);
        assert_eq!(align_window_center(0, 16, 256.0, 128.0), 128.0 - 32768.0);
    }

    #[test]
    fn does_not_offset_unsigned_8bit_window_center() {
        // Unsigned 8-bit samples stay in 0..255, so the centre must stay too:
        // centre 128 → mid-gray, NOT −32640.
        assert_eq!(align_window_center(0, 8, 256.0, 128.0), 128.0);
        assert_eq!(align_window_center(0, 8, 256.0, 128.0), 128.0);
    }

    #[test]
    fn does_not_offset_signed_window_center() {
        // Signed samples need no offset regardless of bit width.
        assert_eq!(align_window_center(1, 16, 256.0, 128.0), 128.0);
        assert_eq!(align_window_center(1, 8, 256.0, 128.0), 128.0);
    }

    #[test]
    fn does_not_offset_when_window_width_is_zero() {
        // Zero/absent window width means no windowing metadata to align.
        assert_eq!(align_window_center(0, 16, 0.0, 32768.0), 32768.0);
        assert_eq!(align_window_center(0, 16, -1.0, 32768.0), 32768.0);
    }
}