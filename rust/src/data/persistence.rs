use serde::{Serialize, Deserialize};
use polars::prelude::*;
use std::io::Cursor;
use std::path::Path;
use std::ffi::OsStr;
use indexmap::IndexMap;

use crate::canvas::types::{Canvas, SheetObject, TableObject, Workbook};
use crate::error::AppError;

#[derive(Serialize, Deserialize)]
pub struct SavedWorkbook {
    pub active_sheet: Option<String>,
    pub sheets: IndexMap<String, SavedCanvas>,
}

#[derive(Serialize, Deserialize)]
pub struct SavedCanvas {
    pub name: String,
    pub snap_to_grid: bool,
    pub tables: Vec<SavedTable>,
}

#[derive(Serialize, Deserialize)]
pub struct SavedTable {
    pub name: String,
    pub position: (f32, f32),
    pub shape: (u32, u32),
    pub parquet_bytes: Vec<u8>,
}

impl SavedCanvas {
    pub fn from_canvas(canvas: &Canvas) -> Result<Self, AppError> {
        let mut tables = Vec::new();

        for obj in canvas.objects() {
            let SheetObject::Table(table) = obj;
            let mut df = table.data().clone();
            let mut buf = Cursor::new(Vec::new());
            ParquetWriter::new(&mut buf).finish(&mut df)?;

            tables.push(SavedTable {
                name: table.name().to_string(),
                position: *table.position(),
                shape: *table.shape(),
                parquet_bytes: buf.into_inner(),
            });
        }

        Ok(SavedCanvas {
            name: canvas.name().to_string(),
            snap_to_grid: canvas.snap_to_grid(),
            tables,
        })
    }

    pub fn into_canvas(self) -> Result<Canvas, AppError> {
        let mut canvas = Canvas::new(self.name);
        canvas.set_snap_to_grid(self.snap_to_grid);

        for saved_table in self.tables {
            let cursor = Cursor::new(saved_table.parquet_bytes);
            let df = ParquetReader::new(cursor).finish()?;
            let table = TableObject::new(
                saved_table.name,
                saved_table.position,
                df,
            );
            canvas.add_object(SheetObject::Table(table));
        }

        Ok(canvas)
    }
}

impl SavedWorkbook {
    pub fn from_workbook(workbook: &Workbook) -> Result<Self, AppError> {
        let mut sheets: IndexMap<String, SavedCanvas> = IndexMap::new();
        for (name, canvas) in &workbook.sheets {
            sheets.insert(name.clone(), SavedCanvas::from_canvas(canvas)?);
        }
        Ok(SavedWorkbook {
            active_sheet: workbook.active_sheet.clone(),
            sheets,
        })
    }

    pub fn into_workbook(self) -> Result<Workbook, AppError> {
        let mut sheets: IndexMap<String, Canvas> = IndexMap::new();
        for (name, saved_canvas) in self.sheets {
            sheets.insert(name, saved_canvas.into_canvas()?);
        }
        Ok(Workbook {
            active_sheet: self.active_sheet,
            sheets,
        })
    }
}

pub fn save_workbook(workbook: &Workbook, path: impl AsRef<Path>) -> Result<(), AppError> {
    if path.as_ref().extension() != Some(OsStr::new("sai")) {
        return Err(AppError::Schema("File must have .sai extension".to_string()));
    }
    let saved = SavedWorkbook::from_workbook(workbook)?;
    let bytes = bincode::serialize(&saved)
        .map_err(|e| AppError::Schema(e.to_string()))?;
    std::fs::write(path, bytes)?;
    Ok(())
}

pub fn load_workbook(path: impl AsRef<Path>) -> Result<Workbook, AppError> {
    if path.as_ref().extension() != Some(OsStr::new("sai")) {
        return Err(AppError::Schema("File must have .sai extension".to_string()));
    }
    let bytes = std::fs::read(path)?;
    let saved: SavedWorkbook = bincode::deserialize(&bytes)
        .map_err(|e| AppError::Schema(e.to_string()))?;
    saved.into_workbook()
}

////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::*;
    use crate::canvas::state::{new_sheet, canvas_load_csv_str, read_canvas, read_workbook, write_workbook};
    use tempfile::TempDir;
    use serial_test::serial;

    const CSV: &str = "name,revenue,active\nAcme,150000,true\nGlobex,320000,false\nInitech,98000,true\n";

    #[test]
    #[serial]
    fn test_save_and_load_sai() {
        new_sheet("test").unwrap();
        canvas_load_csv_str("companies", CSV).unwrap();

        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("test.sai");

        read_canvas(|canvas| {
            // save just this canvas for the test
            let saved = SavedCanvas::from_canvas(canvas).unwrap();
            let wb = SavedWorkbook {
                active_sheet: Some("test".to_string()),
                sheets: {
                    let mut m = IndexMap::new();
                    m.insert("test".to_string(), saved);
                    m
                },
            };
            let bytes = bincode::serialize(&wb).unwrap();
            std::fs::write(&path, bytes).unwrap();
        }).unwrap();

        let workbook = load_workbook(&path).unwrap();
        let canvas = workbook.sheets.get("test").unwrap();
        let table = canvas.get_table("companies").unwrap();
        assert_eq!(table.name(), "companies");
        assert_eq!(table.row_count(), 3usize);
        assert_eq!(table.col_count(), 3usize);
    }

    #[test]
    fn test_save_rejects_wrong_extension() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("test.xlsx");
        let wb = Workbook::new();
        let result = save_workbook(&wb, &path);
        assert!(result.is_err());
    }

    #[test]
    fn test_load_rejects_wrong_extension() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("test.csv");
        let result = load_workbook(&path);
        assert!(result.is_err());
    }

    #[test]
    #[serial]
    fn test_save_and_load_multi_sheet_sai() {
        write_workbook(|wb| {
            wb.sheets.clear();
            wb.active_sheet = None;
        }).unwrap();

        canvas_load_csv_str("sheet1", "a,b\n1,2\n").unwrap();
        canvas_load_csv_str("sheet2", "c,d\n3,4\n").unwrap();

        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("multi.sai");

        read_workbook(|wb| save_workbook(wb, &path)).unwrap().unwrap();

        let workbook = load_workbook(&path).unwrap();
        assert_eq!(workbook.sheets.len(), 2);
        assert!(workbook.sheets.contains_key("sheet1"));
        assert!(workbook.sheets.contains_key("sheet2"));
    }

    #[test]
    #[serial]
    fn test_active_sheet_persists() {
        new_sheet("first").unwrap();
        new_sheet("second").unwrap();

        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("active.sai");

        read_workbook(|wb| save_workbook(wb, &path)).unwrap().unwrap();

        let workbook = load_workbook(&path).unwrap();
        assert_eq!(workbook.active_sheet, Some("second".to_string()));
    }
}