import 'package:flutter/material.dart';
import '../services/bridge_service.dart';
import 'package:spreadsheet_ai/src/rust/api/simple.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../widgets/spreadsheet_grid.dart';

class SpreadsheetScreen extends StatefulWidget {
  const SpreadsheetScreen({super.key});

  @override
  State<SpreadsheetScreen> createState() => _SpreadsheetScreenState();
}

class _SpreadsheetScreenState extends State<SpreadsheetScreen> {
  List<String> _sheets = [];
  String? _activeSheet;
  List<TableInfo> _tables = [];
  String? _selectedTable;
  TableData? _tableData;
  String? _currentPath;
  String _selectedCellAddress = '';
  String _selectedCellValue = '';

  @override
  void initState() {
    super.initState();
    BridgeService.newCanvas('Untitled');
  }

  String _toColLabel(int col) {
    String label = '';
    int c = col - 1;
    do {
      label = String.fromCharCode(65 + (c % 26)) + label;
      c = (c ~/ 26) - 1;
    } while (c >= 0);
    return label;
  }

  void _refreshSheets() {
    final sheets = BridgeService.getSheetsList();
    String? activeSheet = _activeSheet;
    if (sheets.isNotEmpty && activeSheet == null) {
      activeSheet = sheets.first;
      BridgeService.switchSheet(activeSheet);
    }
    final tables = BridgeService.getCanvasTables();
    String? selectedTable = _selectedTable;
    TableData? tableData = _tableData;
    if (tables.isNotEmpty && selectedTable == null) {
      selectedTable = tables.first.name;
      tableData = BridgeService.getTableData(selectedTable);
    }
    setState(() {
      _sheets = sheets;
      _activeSheet = activeSheet;
      _tables = tables;
      _selectedTable = selectedTable;
      _tableData = tableData;
    });
  }

  void _switchSheet(String name) {
    BridgeService.switchSheet(name);
    final tables = BridgeService.getCanvasTables();
    String? selectedTable;
    TableData? tableData;
    if (tables.isNotEmpty) {
      selectedTable = tables.first.name;
      tableData = BridgeService.getTableData(selectedTable);
    }
    setState(() {
      _activeSheet = name;
      _selectedTable = selectedTable;
      _tableData = tableData;
      _tables = tables;
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

  Future<void> _handleFileMenu(String value) async {
    switch (value) {
      case 'open':
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['sai'],
        );
        if (result != null) {
          final path = result.files.single.path!;
          BridgeService.openSai(path);
          setState(() {
            _currentPath = path;
            _activeSheet = null;
            _selectedTable = null;
          });
          _refreshSheets();
        }
        break;
      case 'new':
        BridgeService.newCanvas('Untitled');
        setState(() {
          _sheets = [];
          _activeSheet = null;
          _tables = [];
          _selectedTable = null;
          _tableData = null;
          _currentPath = null;
        });
        break;
      case 'import_csv':
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
        );
        if (result != null) {
          final path = result.files.single.path!;
          BridgeService.importCsv(path);
          setState(() => _activeSheet = null);
        }
        _refreshSheets();
        break;
      case 'import_xlsx':
        final result2 = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );
        if (result2 != null) {
          final path = result2.files.single.path!;
          BridgeService.importXlsx(path);
          setState(() => _activeSheet = null);
        }
        _refreshSheets();
        break;
      case 'save':
        if (_currentPath != null) {
          BridgeService.saveSai(_currentPath!);
        } else {
          await _saveAs();
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
        if (xlsxPath != null) BridgeService.exportXlsx(xlsxPath);
        break;
      case 'export_csv':
        final csvPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Export CSV',
          fileName: 'export.csv',
          allowedExtensions: ['csv'],
          type: FileType.custom,
        );
        if (csvPath != null) BridgeService.exportCsv(csvPath, _selectedTable ?? '');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Spreadsheet AI',
          menus: [
            PlatformMenuItemGroup(members: [
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            ]),
            PlatformMenuItemGroup(members: [
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
            ]),
            PlatformMenuItemGroup(members: [
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
            ]),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(
                label: 'New',
                shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
                onSelected: () async => await _handleFileMenu('new'),
              ),
              PlatformMenuItem(
                label: 'Open',
                shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
                onSelected: () async => await _handleFileMenu('open'),
              ),
            ]),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(
                label: 'Save',
                shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
                onSelected: () async => await _handleFileMenu('save'),
              ),
              PlatformMenuItem(
                label: 'Save As',
                shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
                onSelected: () async => await _handleFileMenu('save_as'),
              ),
            ]),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(
                label: 'Import CSV',
                onSelected: () async => await _handleFileMenu('import_csv'),
              ),
              PlatformMenuItem(
                label: 'Import XLSX',
                onSelected: () async => await _handleFileMenu('import_xlsx'),
              ),
            ]),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(
                label: 'Export XLSX',
                onSelected: () async => await _handleFileMenu('export_xlsx'),
              ),
              PlatformMenuItem(
                label: 'Export CSV',
                onSelected: () async => await _handleFileMenu('export_csv'),
              ),
            ]),
          ],
        ),
        PlatformMenu(
          label: 'Window',
          menus: [
            PlatformMenuItemGroup(members: [
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
            ]),
            PlatformMenuItemGroup(members: [
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen),
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.arrangeWindowsInFront),
            ]),
          ],
        ),
      ],
      child: Scaffold(
        body: Column(
          children: [
            /// Toolbar
            Container(
              height: 40,
              color: Colors.grey[200],
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.format_bold), onPressed: null, tooltip: 'Bold'),
                  IconButton(icon: const Icon(Icons.format_italic), onPressed: null, tooltip: 'Italic'),
                  IconButton(icon: const Icon(Icons.format_underline), onPressed: null, tooltip: 'Underline'),
                  const VerticalDivider(width: 1),
                  IconButton(icon: const Icon(Icons.format_align_left), onPressed: null, tooltip: 'Align Left'),
                  IconButton(icon: const Icon(Icons.format_align_center), onPressed: null, tooltip: 'Center'),
                  IconButton(icon: const Icon(Icons.format_align_right), onPressed: null, tooltip: 'Align Right'),
                ],
              ),
            ),
            /// Name box + formula bar
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey[300]!, width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 80,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.grey[300]!, width: 1)),
                    ),
                    child: Text(
                      _selectedCellAddress,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        _selectedCellValue,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            /// Grid
            Expanded(
              child: SpreadsheetGrid(
                tables: _tables,
                tableData: _tables.map((t) => BridgeService.getTableData(t.name)).toList(),
                onCellSelected: (cell, value) {
                  if (cell == null) {
                    setState(() { _selectedCellAddress = ''; _selectedCellValue = ''; });
                    return;
                  }
                  setState(() {
                    _selectedCellAddress = '${_toColLabel(cell.$2)}${cell.$1}';
                    _selectedCellValue = value;
                  });
                },
                onSelectionChanged: (start, end, value) {
                  if (start == null) {
                    setState(() { _selectedCellAddress = ''; _selectedCellValue = ''; });
                    return;
                  }
                  final startAddr = '${_toColLabel(start.$2)}${start.$1}';
                  if (end == null || start == end) {
                    setState(() { _selectedCellAddress = startAddr; _selectedCellValue = value; });
                  } else {
                    final endAddr = '${_toColLabel(end.$2)}${end.$1}';
                    setState(() { _selectedCellAddress = '$startAddr:$endAddr'; _selectedCellValue = value; });
                  }
                },
              ),
            ),
            /// Sheet tabs
            Container(
              height: 36,
              color: Colors.grey[100],
              child: Row(
                children: _sheets.map((sheet) => GestureDetector(
                  onTap: () => _switchSheet(sheet),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: sheet == _activeSheet ? Colors.green : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(sheet),
                  ),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}