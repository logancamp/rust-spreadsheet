import 'package:spreadsheet_ai/src/rust/api/simple.dart' as bridge;
import 'package:spreadsheet_ai/src/rust/frb_generated.dart';

class BridgeService {
  static Future<void> init() async {
    await RustLib.init();
  }

  static void newCanvas(String name) {
    bridge.newCanvas(name: name);
  }

  static void openSai(String path) {
    bridge.openSai(path: path);
  }

  static void saveSai(String path) {
    bridge.saveSai(path: path);
  }

  static void importCsv(String path) {
    bridge.importCsv(path: path);
  }

  static void importXlsx(String path) {
    bridge.importXlsx(path: path);
  }

  static void exportXlsx(String path) {
      bridge.exportXlsx(path: path);
  }

  static void exportCsv(String path, String tableName) {
      bridge.exportCsv(path: path, tableName: tableName);
  }

  static List<bridge.TableInfo> getCanvasTables() {
    return bridge.getCanvasTables();
  }

  static bridge.TableData getTableData(String tableName) {
    return bridge.getTableData(tableName: tableName);
  }

  static List<String> getSheetsList() {
    return bridge.getSheetsList();
  }

  static void switchSheet(String name) {
      bridge.switchSheet(name: name);
  }

  static bridge.EditResult editCell(String sheetName, String tableName, String colName, int row, String value) {
    return bridge.editCell(
        sheetName: sheetName,
        tableName: tableName,
        colName: colName,
        row: row,
        value: value,
    );
  }
}