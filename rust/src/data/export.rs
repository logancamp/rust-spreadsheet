use rust_xlsxwriter::Workbook;
use polars::prelude::CsvWriter;
use std::path::Path;
use std::ffi::OsStr;
use polars::io::SerWriter;

use crate::canvas::types::{Canvas, SheetObject, TableObject};
use crate::error::AppError;

/// Export entire Canvas to XLSX — each TableObject becomes a named worksheet
pub fn save_xlsx(canvas: &Canvas, path: impl AsRef<Path>) -> Result<(), AppError> {
    let mut workbook = Workbook::new();

    for obj in canvas.objects() {
        let SheetObject::Table(table) = obj;
        let sheet = workbook.add_worksheet();
        sheet.set_name(table.name())?;

        for (col_idx, col) in table.schema().columns().iter().enumerate() {
            sheet.write(0, col_idx as u16, col.name())?;
        }

        let df = table.data();
        for row_idx in 0..df.height() {
            for col_idx in 0..df.width() {
                let value = df.get_row(row_idx)
                    .unwrap()
                    .0[col_idx]
                    .to_string();
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
    use crate::canvas::state::{init_canvas, canvas_load_csv_str, with_canvas};
    use crate::data::import::{load_csv_str, load_csv};
    use tempfile::TempDir;
    use serial_test::serial;

    const SAMPLE_CSV: &str = "name,revenue,active\nAcme,150000,true\nGlobex,320000,false\nInitech,98000,true\n";

    #[test]
    #[serial]
    fn test_save_and_reload_xlsx() {
        init_canvas("xlsx_test").unwrap(); // fresh canvas, clears previous state
        canvas_load_csv_str("xlsx_companies", SAMPLE_CSV).unwrap();

        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("test.xlsx");

        with_canvas(|canvas| save_xlsx(canvas, &path)).unwrap().unwrap();

        let tables = crate::data::import::load_xlsx(&path).unwrap();
        assert_eq!(tables.len(), 1);
        assert_eq!(tables[0].row_count(), 3usize);
        assert_eq!(tables[0].col_count(), 3usize);
    }

    #[test]
    fn test_save_csv() {
        let table = load_csv_str("companies", SAMPLE_CSV).unwrap();
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("companies.csv");
        save_csv(&table, &path).unwrap();
        let reloaded = load_csv(&path).unwrap();
        assert_eq!(reloaded.row_count(), 3usize);
        assert_eq!(reloaded.col_count(), 3usize);
    }

    #[test]
    #[serial]
    fn test_save_canvas_csv() {
        init_canvas("csv_canvas_test").unwrap();
        canvas_load_csv_str("csv_companies", SAMPLE_CSV).unwrap();
        let tmp = TempDir::new().unwrap();
        with_canvas(|canvas| save_canvas_csv(canvas, tmp.path())).unwrap().unwrap();
        assert!(tmp.path().join("csv_companies.csv").exists());
    }
}