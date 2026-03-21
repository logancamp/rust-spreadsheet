use rust_xlsxwriter::Workbook;
use std::path::Path;

use crate::canvas::types::TableObject;
use crate::error::AppError;

pub fn save_xlsx(table: &TableObject, path: impl AsRef<Path>) -> Result<(), AppError> {
    let mut workbook = Workbook::new();
    let sheet = workbook.add_worksheet();

    // Write headers in row 0
    for (col_idx, col) in table.schema().columns().iter().enumerate() {
        sheet.write(0, col_idx as u16, col.name())?;
    }

    // Write data rows starting at row 1
    let df = table.data();
    for row_idx in 0..df.height() {
        for col_idx in 0..df.width() {
            let value = df.get_row(row_idx)?
                .0[col_idx]
                .to_string();
            sheet.write((row_idx + 1) as u32, col_idx as u16, value)?;
        }
    }

    workbook.save(path.as_ref())?;
    Ok(())
}


////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::import::load_csv_str;
    use crate::data::import::load_xlsx;

    const SAMPLE_CSV: &str = "\
name,revenue,active
Acme,150000,true
Globex,320000,false
Initech,98000,true
";

    #[test]
    fn test_save_and_reload_xlsx() {
        let table = load_csv_str("companies", SAMPLE_CSV).unwrap();

        let tmp = tempfile::NamedTempFile::new().unwrap();
        let path = tmp.path().with_extension("xlsx");

        save_xlsx(&table, &path).unwrap();

        let reloaded = load_xlsx(&path).unwrap();
        assert_eq!(reloaded.row_count(), 3usize);
        assert_eq!(reloaded.col_count(), 3usize);
    }
}