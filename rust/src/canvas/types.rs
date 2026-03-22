use uuid::Uuid;
use chrono::{DateTime, Utc};
use polars::prelude::DataFrame;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct Canvas {
    id: Uuid,
    name: String,
    objects: Vec<SheetObject>,
    created_at: DateTime<Utc>,
    modified_at: DateTime<Utc>,
    snap_to_grid: bool,
}

#[derive(Debug, Clone)]
pub enum SheetObject {
    Table(TableObject),
}

#[derive(Debug, Clone)]
pub struct TableObject {
    id: Uuid,
    name: String,
    created_at: DateTime<Utc>,
    position: (f32, f32),
    shape: (u32, u32),
    data: DataFrame,
    formats: HashMap<(u32, u32), CellFormat>,
    metadata: TableMetadata,
    schema: TableSchema,
}

#[derive(Debug, Clone)]
#[derive(Default)]
pub(crate) struct CellFormat {
    bold: bool,
    italic: bool,
    underline: bool,
    strikethrough: bool,
    font_size: Option<u8>,
    font_color: Option<u32>,
    number_format: Option<String>,
    border_style: Option<CellBorder>,
    fill: Option<u32>, // hex
    alignment: Option<Alignment>,
}

#[derive(Debug, Clone)]
pub(crate) struct CellBorder {
    top: Option<BorderStyle>,
    bottom: Option<BorderStyle>,
    left: Option<BorderStyle>,
    right: Option<BorderStyle>,
    color: Option<u32>,
}

#[derive(Debug, Clone)]
pub(crate) enum BorderStyle {
    Thin,
    Medium,
    Thick,
    Dashed,
}

#[derive(Debug, Clone)]
pub(crate) enum Alignment {
    Left,
    Center,
    Right,
}

#[derive(Debug, Clone)]
pub struct TableSchema {
    columns: Vec<ColumnSchema>,
}

#[derive(Debug, Clone)]
pub struct ColumnSchema {
    name: String,
    dtype: String,
    nullable: bool,
}

#[derive(Debug, Clone)]
#[derive(Default)]
pub(crate) struct TableMetadata {
    row_meta: Option<DataFrame>,
    column_meta: Option<DataFrame>,
    last_analysed: Option<DateTime<Utc>>,
}

impl Canvas {
    pub fn new(name: String) -> Self {
        Self {
            id: Uuid::new_v4(),
            name,
            objects: Vec::new(),
            created_at: Utc::now(),
            modified_at: Utc::now(),
            snap_to_grid: true,
        }
    }

    pub fn add_object(&mut self, obj: SheetObject) {
        self.objects.push(obj);
    }
    pub fn set_snap_to_grid(&mut self, switch: bool) { self.snap_to_grid = switch; }

    pub fn get_table(&self, name: &str) -> Option<&TableObject> {
        self.objects.iter().find_map(|o| match o {
            SheetObject::Table(t) if t.name == name => Some(t), _ => None,
        })
    }

    pub fn objects(&self) -> &Vec<SheetObject> { &self.objects }
    pub fn name(&self) -> &str { &self.name }
    pub fn snap_to_grid(&self) -> bool { self.snap_to_grid  }
}

impl TableObject {
    pub fn new(name: String, position: (f32, f32), data: DataFrame) -> Self{
        let shape = (data.width() as u32, data.height() as u32);
        let schema = TableSchema::from_dataframe(&data);
        Self {
            id: Uuid::new_v4(),
            name,
            created_at: Utc::now(),
            position,
            shape,
            data,
            formats: HashMap::new(),
            metadata: TableMetadata::default(),
            schema,
        }
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn position(&self) -> &(f32, f32) {
        &self.position
    }

    pub fn shape(&self) -> &(u32, u32) {
        &self.shape
    }

    pub fn schema(&self) -> &TableSchema {
        &self.schema
    }

    pub fn data(&self) -> &DataFrame {
        &self.data
    }

    pub fn row_count(&self) -> usize {
        self.data.height()
    }
    pub fn col_count(&self) -> usize {
        self.data.width()
    }
}

impl TableSchema {
    pub fn from_dataframe(df: &DataFrame) -> Self {
        let columns = df.schema().iter().map(
            |(name, dtype)| {
                ColumnSchema {
                    name: name.to_string(),
                    dtype: dtype.to_string(),
                    nullable: true,
            }
        }).collect();
        Self { columns }
    }

    pub fn columns(&self) -> &Vec<ColumnSchema> {
        &self.columns
    }
}

impl ColumnSchema {
    pub fn name(&self) -> &str {
        &self.name
    }
    
    pub fn dtype(&self) -> &str {
        &self.dtype
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////
#[cfg(test)]
mod tests {
    use super::*;
    use polars::prelude::*;

    #[test]
    fn test_canvas_table_roundtrip() {
        let df = df!(
            "name" => ["Alice", "Bob"],
            "age" => [30i32, 25]
        ).unwrap();

        let table = TableObject::new(
            "people".to_string(),
            (0.0, 0.0),
            df,
        );

        let mut canvas = Canvas::new("test sheet".to_string());
        canvas.add_object(SheetObject::Table(table));

        let retrieved = canvas.get_table("people").unwrap();
        assert_eq!(retrieved.name, "people");
        assert_eq!(retrieved.row_count(), 2usize);
        assert_eq!(retrieved.col_count(), 2usize);
    }
}