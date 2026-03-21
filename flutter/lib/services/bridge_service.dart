import 'package:spreadsheet_ai/src/rust/api/simple.dart';
import 'package:spreadsheet_ai/src/rust/frb_generated.dart';

class BridgeService {
  static Future<void> init() async {
    await RustLib.init();
  }

  static TableData loadCsv(String name, String csv) {
    return loadCsvToFlutter(name: name, csv: csv); // this is the imported one
  }
}
