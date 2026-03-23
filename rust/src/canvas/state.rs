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
    let table = load_csv(path)?.with_source_path(path);
    with_canvas(|canvas| {
        canvas.add_or_replace_table(table);
    })
}

pub fn canvas_load_csv_str(name: &str, csv: &str) -> Result<(), AppError> {
    let table = load_csv_str(name, csv)?;
    // no source path for string imports
    with_canvas(|canvas| {
        canvas.add_or_replace_table(table);
    })
}

pub fn canvas_load_xlsx(path: &str) -> Result<(), AppError> {
    let tables = load_xlsx(path)?;
    for table in tables {
        let table = table.with_source_path(path);
        with_canvas(|canvas| {
            canvas.add_or_replace_table(table.clone());
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


////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use serial_test::serial;
    use crate::canvas::SheetObject;
    use crate::canvas::state::{canvas_load_csv_str, init_canvas, with_canvas};

    #[test]
    #[serial]
    fn test_table_name_deduplication() {
        init_canvas("dedup_test").unwrap();
        canvas_load_csv_str("Sheet1", "a,b\n1,2\n").unwrap();
        canvas_load_csv_str("Sheet1", "c,d\n3,4\n").unwrap();

        with_canvas(|canvas| {
            let names: Vec<String> = canvas.objects().iter().filter_map(|o| match o {
                SheetObject::Table(t) => Some(t.name().to_string()),
            }).collect();
            assert_eq!(names.len(), 2);
            assert!(names.contains(&"Sheet1".to_string()));
            assert!(names.contains(&"Sheet1_1".to_string()));
        }).unwrap();
    }
}