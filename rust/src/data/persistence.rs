use serde::{Serialize, Deserialize};
use polars::prelude::*;
use std::io::Cursor;
use std::path::Path;
use std::ffi::OsStr;

use crate::canvas::types::{Canvas, SheetObject, TableObject};
use crate::error::AppError;

// derive custom file type (.sai) for read/write native efficiency
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
    pub parquet_bytes: Vec<u8>,  // the DataFrame serialized as Parquet
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

pub fn save_canvas(canvas: &Canvas, path: impl AsRef<Path>) -> Result<(), AppError> {
    if path.as_ref().extension() != Some(OsStr::new("sai")) {
        return Err(AppError::Schema("File must have .sai extension".to_string()));
    }

    let saved = SavedCanvas::from_canvas(canvas)?;
    let bytes = bincode::serialize(&saved)
        .map_err(|e| AppError::Schema(e.to_string()))?;
    std::fs::write(path, bytes)?;
    Ok(())
}

pub fn load_canvas(path: impl AsRef<Path>) -> Result<Canvas, AppError> {
    if path.as_ref().extension() != Some(OsStr::new("sai")) {
        return Err(AppError::Schema("File must have .sai extension".to_string()));
    }

    let bytes = std::fs::read(path)?;
    let saved: SavedCanvas = bincode::deserialize(&bytes)
        .map_err(|e| AppError::Schema(e.to_string()))?;
    saved.into_canvas()
}


////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::*;
    use crate::canvas::state::{init_canvas, canvas_load_csv_str};
    use crate::canvas::state::with_canvas;
    use tempfile::TempDir;
    use serial_test::serial;

    #[test]
    #[serial]
    fn test_save_and_load_sai() {
        let csv = "name,revenue,active\nAcme,150000,true\nGlobex,320000,false\nInitech,98000,true\n";

        init_canvas("test").unwrap();
        canvas_load_csv_str("companies", csv).unwrap();

        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("test.sai");

        with_canvas(|canvas| {
            save_canvas(canvas, &path).unwrap();
        }).unwrap();

        let canvas = load_canvas(&path).unwrap();
        let table = canvas.get_table("companies").unwrap();
        assert_eq!(table.name(), "companies");
        assert_eq!(table.row_count(), 3usize);
        assert_eq!(table.col_count(), 3usize);
    }

    #[test]
    #[serial]
    fn test_save_rejects_wrong_extension() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("test.xlsx");

        init_canvas("test").unwrap();

        with_canvas(|canvas| {
            let result = save_canvas(canvas, &path);
            assert!(result.is_err());
        }).unwrap();
    }

    #[test]
    fn test_load_rejects_wrong_extension() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("test.csv");

        let result = load_canvas(&path);
        assert!(result.is_err());
    }
}