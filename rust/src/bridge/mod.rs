use flutter_rust_bridge::frb;

use crate::data::import::load_csv_str;
use crate::error::AppError;

pub struct TableData {
    pub name: String,
    pub columns: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

#[frb(sync)]
pub fn load_csv_to_flutter(name: &str, csv: &str) -> Result<TableData, AppError> {
    let table = load_csv_str(name, csv)?;
    Ok(TableData {
        name: table.name().to_string(),
        columns: table.schema().columns().iter().map(|c| c.name().to_string()).collect(),
        rows: (0..table.data().height()).map(|row_idx| {
            table.data().get_row(row_idx).unwrap().0
                .iter().map(|v| v.to_string()).collect()
        }).collect(),
    })
}