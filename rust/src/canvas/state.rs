use std::sync::Mutex;

use crate::error::AppError;
use crate::data::import::{load_csv, load_csv_str, load_xlsx};
use crate::canvas::types::{SheetObject, Canvas};

static CANVAS: Mutex<Option<Canvas>> = Mutex::new(None);

// initialize a safe/locked global canvas for read/write safety
pub fn init_canvas(name: &str) -> Result<(), AppError> {
    let mut guard = CANVAS.lock()
        .map_err(|_| AppError::NotFound("Canvas lock poisoned".to_string()))?;
    *guard = Some(Canvas::new(name.to_string()));
    Ok(())
}

// for canvas function use
pub fn with_canvas<F, T>(f: F) -> Result<T, AppError>
where
    F: FnOnce(&mut Canvas) -> T
{
    let mut guard = CANVAS.lock()
        .map_err(|_| AppError::NotFound("Canvas lock poisoned".to_string()))?;
    let canvas = guard.as_mut()
        .ok_or(AppError::NotFound("No canvas loaded".to_string()))?;
    Ok(f(canvas))
}

pub fn canvas_load_csv(path: &str) -> Result<(), AppError> {
    let table = load_csv(path)?;
    with_canvas(|canvas| {
        canvas.add_object(SheetObject::Table(table));
    })
}

pub fn canvas_load_csv_str(name: &str, csv: &str) -> Result<(), AppError> {
    let table = load_csv_str(name, csv)?;
    with_canvas(|canvas| {
        canvas.add_object(SheetObject::Table(table));
    })
}

pub fn canvas_load_xlsx(path: &str) -> Result<(), AppError> {
    let tables = load_xlsx(path)?;
    for table in tables {
        with_canvas(|canvas| {
            canvas.add_object(SheetObject::Table(table.clone()));
        })?;
    }
    Ok(())
}

pub fn set_canvas(canvas: Canvas) -> Result<(), AppError> {
    let mut guard = CANVAS.lock()
        .map_err(|_| AppError::NotFound("Canvas lock poisoned".to_string()))?;
    *guard = Some(canvas);
    Ok(())
}