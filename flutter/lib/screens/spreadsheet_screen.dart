import 'package:flutter/material.dart';
import '../services/bridge_service.dart';
import 'package:spreadsheet_ai/src/rust/api/simple.dart';
import '../widgets/table_widget.dart';
import 'package:file_picker/file_picker.dart';

class SpreadsheetScreen extends StatefulWidget {
  const SpreadsheetScreen({super.key});

  @override
  State<SpreadsheetScreen> createState() => _SpreadsheetScreenState();
}

class _SpreadsheetScreenState extends State<SpreadsheetScreen> {
  List<TableInfo> _tables = [];
  String? _selectedTable;
  TableData? _tableData;
  String? _currentPath;

  @override
  void initState() {
    super.initState();
    BridgeService.newCanvas('Untitled');
  }

  void _refreshTables() {
    setState(() {
      _tables = BridgeService.getCanvasTables();
      if (_tables.isNotEmpty && _selectedTable == null) {
        _selectedTable = _tables.first.name;
        _tableData = BridgeService.getTableData(_tables.first.name);
      }
    });
  }

  void _selectTable(String name) {
    setState(() {
      _selectedTable = name;
      _tableData = BridgeService.getTableData(name);
    });
  }

  Future<void> _saveAs() async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save As',
    fileName: 'untitled.sai',
    allowedExtensions: ['sai'],
    type: FileType.custom,
  );
  if (path != null) {
    BridgeService.saveSai(path);
    setState(() => _currentPath = path);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spreadsheet AI'),
        actions: [
          PopupMenuButton<String>(
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('File', style: TextStyle(fontSize: 16)),
            ),
            onSelected: (value) async {
              switch (value) {
                case 'import_csv':
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['csv'],
                  );
                  if (result != null) {
                    final path = result.files.single.path!;
                    BridgeService.importCsv(path);
                  }
                  _refreshTables();
                  break;
                case 'import_xlsx':
                  final result2 = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['xlsx'],
                  );
                  if (result2 != null) {
                    final path = result2.files.single.path!;
                    BridgeService.importXlsx(path);
                  }
                  _refreshTables();
                  break;
                case 'save':
                  if (_currentPath != null) {
                    BridgeService.saveSai(_currentPath!);
                  } else {
                    await _saveAs();  // calls the helper
                  }
                  break;
                case 'save_as':
                  await _saveAs();
                  break;
                case 'export_xlsx':
                  final xlsxPath = await FilePicker.platform.saveFile(
                    dialogTitle: 'Export XLSX',
                    fileName: 'export.xlsx',
                    allowedExtensions: ['xlsx'],
                    type: FileType.custom,
                  );
                  if (xlsxPath != null) {
                    BridgeService.exportXlsx(xlsxPath);
                  }
                  break;
                case 'export_csv':
                  final csvPath = await FilePicker.platform.saveFile(
                    dialogTitle: 'Export CSV',
                    fileName: 'export.csv',
                    allowedExtensions: ['csv'],
                    type: FileType.custom,
                  );
                  if (csvPath != null) {
                    BridgeService.exportCsv(csvPath, _selectedTable ?? '');
                  }
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'import_csv', child: Text('Import CSV')),
              const PopupMenuItem(value: 'import_xlsx', child: Text('Import XLSX')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'save', child: Text('Save (.sai)')),
              const PopupMenuItem(value: 'save_as', child: Text('Save As (.sai)')),
              const PopupMenuItem(value: 'export_xlsx', child: Text('Export XLSX')),
              const PopupMenuItem(value: 'export_csv', child: Text('Export CSV')),
            ],
          ),
        ],
      ),
      body: _tableData == null
          ? const Center(child: Text('Loading...'))
          : TableWidget(data: _tableData!),
    );
  }
}
