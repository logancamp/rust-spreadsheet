use rust_xlsxwriter::Workbook;
use polars::prelude::CsvWriter;
use std::path::Path;
use std::ffi::OsStr;
use polars::io::SerWriter;

use crate::canvas::types::{Canvas, SheetObject, TableObject};
use crate::canvas::state::{new_sheet, canvas_load_csv_str, read_canvas};
use crate::error::AppError;

/// Export entire Canvas to XLSX — each TableObject becomes a named worksheet
pub fn save_xlsx(canvas: &Canvas, path: impl AsRef<Path>) -> Result<(), AppError> {
    let mut workbook = Workbook::new();

    for obj in canvas.objects() {
        let SheetObject::Table(table) = obj;
        let sheet = workbook.add_worksheet();
        sheet.set_name(table.name())?;

        // Write headers in row 0
        for (col_idx, col) in table.schema().columns().iter().enumerate() {
            sheet.write(0, col_idx as u16, col.name())?;
        }

        // Write data column by column — cache friendly, zero extra allocations
        let df = table.data();
        for (col_idx, col) in df.columns().iter().enumerate() {
            for row_idx in 0..col.len() {
                let value = match col.get(row_idx)? {
                    polars::prelude::AnyValue::String(s) => s.to_string(),
                    polars::prelude::AnyValue::StringOwned(s) => s.to_string(),
                    polars::prelude::AnyValue::Null => String::new(),
                    other => other.to_string(),
                };
                sheet.write((row_idx + 1) as u32, col_idx as u16, value)?;
            }
        }
    }

    workbook.save(path.as_ref())?;
    Ok(())
}

/// Export a single TableObject to CSV
pub fn save_csv(table: &TableObject, path: impl AsRef<Path>) -> Result<(), AppError> {
    if path.as_ref().extension() != Some(OsStr::new("csv")) {
        return Err(AppError::Schema("File must have .csv extension".to_string()));
    }

    let mut file = std::fs::File::create(path)?;
    CsvWriter::new(&mut file)
        .finish(&mut table.data().clone())?;
    Ok(())
}

/// Export all tables in Canvas as separate CSV files into a directory
pub fn save_canvas_csv(canvas: &Canvas, dir_path: impl AsRef<Path>) -> Result<(), AppError> {
    let dir = dir_path.as_ref();
    std::fs::create_dir_all(dir)?;

    for obj in canvas.objects() {
        let SheetObject::Table(table) = obj;
        let path = dir.join(format!("{}.csv", table.name()));
        save_csv(table, path)?;
    }

    Ok(())
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::*;
    use crate::canvas::state::{new_sheet, canvas_load_csv_str, read_canvas, write_canvas};
    use crate::data::import::{load_csv_str, load_csv};
    use tempfile::TempDir;
    use serial_test::serial;

    const SAMPLE_CSV: &str = "name,revenue,active\nAcme,150000,true\nGlobex,320000,false\nInitech,98000,true\n";

    #[test]
    #[serial]
    fn test_save_and_reload_xlsx() {
        new_sheet("xlsx_test").unwrap(); // fresh canvas, clears previous state
        canvas_load_csv_str("xlsx_companies", SAMPLE_CSV).unwrap();

        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("test.xlsx");

        read_canvas(|canvas| save_xlsx(canvas, &path)).unwrap().unwrap();

        let tables = crate::data::import::load_xlsx(&path).unwrap();
        assert_eq!(tables.len(), 1);
        assert_eq!(tables[0].table.row_count(), 3usize);
        assert_eq!(tables[0].table.col_count(), 3usize);
    }

    #[test]
    fn test_save_csv() {
        let table = load_csv_str("companies", SAMPLE_CSV).unwrap();
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("companies.csv");
        save_csv(&table, &path).unwrap();
        let reloaded = load_csv(path).unwrap();
        assert_eq!(reloaded[0].row_count(), 3usize);
        assert_eq!(reloaded[0].col_count(), 3usize);
    }

    #[test]
    #[serial]
    fn test_save_canvas_csv() {
        new_sheet("csv_canvas_test").unwrap();
        canvas_load_csv_str("csv_companies", SAMPLE_CSV).unwrap();
        let tmp = TempDir::new().unwrap();
        read_canvas(|canvas| save_canvas_csv(canvas, tmp.path())).unwrap().unwrap();
        assert!(tmp.path().join("csv_companies.csv").exists());
    }
}