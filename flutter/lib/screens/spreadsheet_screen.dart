import 'package:flutter/material.dart';
import '../services/bridge_service.dart';
import 'package:spreadsheet_ai/src/rust/api/simple.dart';
import '../widgets/table_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

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

  /// Menu Bar Function
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
            _selectedTable = null;
          });
          _refreshTables();
        }
        break;
      case 'new':
        BridgeService.newCanvas('Untitled');
        setState(() {
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
  }

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Spreadsheet AI',
          menus: [
            PlatformMenuItemGroup(
              members: [
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItemGroup(
              members: [
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
              ],
            ),
            PlatformMenuItemGroup(
              members: [
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
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Import CSV',
                  onSelected: () async => await _handleFileMenu('import_csv'),
                ),
                PlatformMenuItem(
                  label: 'Import XLSX',
                  onSelected: () async => await _handleFileMenu('import_xlsx'),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Export XLSX',
                  onSelected: () async => await _handleFileMenu('export_xlsx'),
                ),
                PlatformMenuItem(
                  label: 'Export CSV',
                  onSelected: () async => await _handleFileMenu('export_csv'),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Window',
          menus: [
            PlatformMenuItemGroup(
              members: [
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen),
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.arrangeWindowsInFront),
              ],
            ),
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
            /// Middle — sidebar + content
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _tableData == null
                              ? const Center(child: Text('No table selected'))
                              : TableWidget(data: _tableData!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            /// Sheet tabs
            Container(
              height: 36,
              color: Colors.grey[100],
              child: Row(
                children: _tables.map((table) => GestureDetector(
                  onTap: () => _selectTable(table.name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: table.name == _selectedTable
                              ? Colors.green
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(table.name),
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
