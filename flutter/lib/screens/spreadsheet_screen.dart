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
  List<TableData> _tableDataCache = [];
  String? _selectedTable;
  String? _currentPath;
  String _selectedCellAddress = '';
  String _selectedCellValue = '';
  double _scale = 1.0;
  int _commitKey = 0;
  bool _editingIsNew = false;

  (int, int)? _editingCell;
  (int, int)? _postCommitCell;
  String _originalCellValue = '';
  String? _editingTableName;
  String? _editingColName;
  int? _editingRowIndex;

  final TextEditingController _formulaController = TextEditingController();
  final FocusNode _formulaBarFocusNode = FocusNode(skipTraversal: true);  bool _formulaBarFocused = false;

  @override
  void initState() {
    super.initState();
    BridgeService.newCanvas('Untitled');
    _formulaBarFocusNode.addListener(() {
      setState(() => _formulaBarFocused = _formulaBarFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _formulaController.dispose();
    _formulaBarFocusNode.dispose();
    super.dispose();
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
    final tableData = tables.map((t) => BridgeService.getTableData(t.name)).toList();
    setState(() {
      _sheets = sheets;
      _activeSheet = activeSheet;
      _tables = tables;
      _tableDataCache = tableData;
      if (tables.isNotEmpty) _selectedTable = tables.first.name;
    });
  }

  void _refreshTableData() {
    final tables = BridgeService.getCanvasTables();
    final tableData = tables.map((t) => BridgeService.getTableData(t.name)).toList();
    setState(() {
      _tables = tables;
      _tableDataCache = tableData;
    });
  }

  void _switchSheet(String name) {
    BridgeService.switchSheet(name);
    final tables = BridgeService.getCanvasTables();
    final tableData = tables.map((t) => BridgeService.getTableData(t.name)).toList();
    setState(() {
      _activeSheet = name;
      _tables = tables;
      _tableDataCache = tableData;
      _selectedTable = tables.isNotEmpty ? tables.first.name : null;
      _editingCell = null;
      _formulaController.text = '';
      _selectedCellAddress = '';
      _selectedCellValue = '';
    });
  }

  Future<void> _commitEdit(String value, {
    String? tableName,
    String? colName,
    int? rowIndex,
    bool isNew = false,
    (int, int)? gridCell,
    (int, int)? selectAfter,
  }) async {
    final cell = gridCell ?? _editingCell;
    final tn = tableName ?? _editingTableName;
    final cn = colName ?? _editingColName;
    final ri = rowIndex ?? _editingRowIndex;
    final ni = isNew || _editingIsNew;

    setState(() {
      _selectedCellValue = value;
      _originalCellValue = value;
      _editingCell = null;
      _editingIsNew = false;
      _selectedCellAddress = '';
      _formulaController.text = '';
      _postCommitCell = selectAfter;
    });

    if (_activeSheet == null) return;

    try {
      if (tn != null && cn != null && ri != null && ri >= 0 && !ni) {
        BridgeService.editCell(_activeSheet!, tn, cn, ri, value);
      } else if (cell != null) {
        final canvasCol = cell.$2 - 1;
        final canvasRow = cell.$1 - 1;
        BridgeService.setCanvasCell(_activeSheet!, canvasCol, canvasRow, value);
      }
    } catch (e) {
      print('commitEdit error: $e');
    }

    _refreshTableData();
    setState(() => _commitKey++);
  }

  void _revertEdit() {
    _formulaController.text = _originalCellValue;
    setState(() => _selectedCellValue = _originalCellValue);
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
        final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['sai']);
        if (result != null) {
          final path = result.files.single.path!;
          BridgeService.openSai(path);
          setState(() { _currentPath = path; _activeSheet = null; _selectedTable = null; });
          _refreshSheets();
        }
        break;
      case 'new':
        BridgeService.newCanvas('Untitled');
        setState(() {
          _sheets = []; _activeSheet = null; _tables = []; _tableDataCache = [];
          _selectedTable = null; _currentPath = null;
          _selectedCellAddress = ''; _selectedCellValue = '';
          _editingCell = null; _formulaController.text = '';
        });
        break;
      case 'import_csv':
        final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
        if (result != null) {
          BridgeService.importCsv(result.files.single.path!);
          setState(() => _activeSheet = null);
        }
        _refreshSheets();
        break;
      case 'import_xlsx':
        final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
        if (result != null) {
          BridgeService.importXlsx(result.files.single.path!);
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
        final path = await FilePicker.platform.saveFile(dialogTitle: 'Export XLSX', fileName: 'export.xlsx', allowedExtensions: ['xlsx'], type: FileType.custom);
        if (path != null) BridgeService.exportXlsx(path);
        break;
      case 'export_csv':
        final path = await FilePicker.platform.saveFile(dialogTitle: 'Export CSV', fileName: 'export.csv', allowedExtensions: ['csv'], type: FileType.custom);
        if (path != null) BridgeService.exportCsv(path, _selectedTable ?? '');
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
            PlatformMenuItemGroup(members: [const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about)]),
            PlatformMenuItemGroup(members: [
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
              const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
            ]),
            PlatformMenuItemGroup(members: [const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit)]),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: 'New', shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true), onSelected: () async => await _handleFileMenu('new')),
              PlatformMenuItem(label: 'Open', shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true), onSelected: () async => await _handleFileMenu('open')),
            ]),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: 'Save', shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true), onSelected: () async => await _handleFileMenu('save')),
              PlatformMenuItem(label: 'Save As', shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true), onSelected: () async => await _handleFileMenu('save_as')),
            ]),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: 'Import CSV', onSelected: () async => await _handleFileMenu('import_csv')),
              PlatformMenuItem(label: 'Import XLSX', onSelected: () async => await _handleFileMenu('import_xlsx')),
            ]),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: 'Export XLSX', onSelected: () async => await _handleFileMenu('export_xlsx')),
              PlatformMenuItem(label: 'Export CSV', onSelected: () async => await _handleFileMenu('export_csv')),
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
                    decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey[300]!, width: 1))),
                    child: Text(_selectedCellAddress, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
                  Expanded(
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                          _revertEdit();
                        }
                      },
                      child: TextField(
                        controller: _formulaController,
                        focusNode: _formulaBarFocusNode,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        ),
                        onChanged: (value) {
                          _selectedCellValue = value;
                          setState(() {});
                        },
                        onSubmitted: (value) => _commitEdit(value, gridCell: _editingCell),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            /// Grid
            Expanded(
              child: SpreadsheetGrid(
                key: ValueKey(_commitKey),
                initialSelection: _postCommitCell,
                formulaBarFocused: _formulaBarFocused,
                tables: _tables,
                tableData: _tableDataCache,
                externalScale: _scale,
                onScaleChanged: (s) => setState(() => _scale = s),
                formulaBarValue: _selectedCellValue,
                formulaBarCell: _editingCell,
                onCellValueChanged: (value) {
                  _formulaController.text = value;
                  _selectedCellValue = value;
                },
                onCellSelected: (cell, value, tableName, colName, rowIndex, isNew) {
                  if (cell == null) {
                    setState(() { _selectedCellAddress = ''; _selectedCellValue = ''; });
                    _formulaController.text = '';
                    _editingCell = null;
                    _editingTableName = null;
                    _editingColName = null;
                    _editingRowIndex = null;
                    _editingIsNew = false;
                    return;
                  }
                  _originalCellValue = value;
                  _formulaController.text = value;
                  setState(() {
                    _selectedCellAddress = '${_toColLabel(cell.$2)}${cell.$1}';
                    _selectedCellValue = value;
                    _editingCell = cell;
                    _editingTableName = tableName;
                    _editingColName = colName;
                    _editingRowIndex = rowIndex;
                    _editingIsNew = isNew;
                  });
                },
                onCellCommit: (cell, value, tableName, colName, rowIndex, isNew, {selectAfter}) {
                  _commitEdit(value,
                    tableName: tableName,
                    colName: colName,
                    rowIndex: rowIndex,
                    isNew: isNew,
                    gridCell: cell,
                    selectAfter: selectAfter,
                  );
                },
                onCellDeleteCommit: (cell, tableName, colName, rowIndex, isNew) {
                  _commitEdit('',
                    tableName: tableName,
                    colName: colName,
                    rowIndex: rowIndex,
                    isNew: isNew,
                    gridCell: cell,
                  );
                },
                onSelectionChanged: (start, end, value) {
                  if (start == null) {
                    setState(() { _selectedCellAddress = ''; _selectedCellValue = ''; });
                    _formulaController.text = '';
                    return;
                  }
                  final startAddr = '${_toColLabel(start.$2)}${start.$1}';
                  final endAddr = (end == null || start == end) ? null : '${_toColLabel(end.$2)}${end.$1}';
                  _formulaController.text = value;
                  _originalCellValue = value;
                  setState(() {
                    _selectedCellAddress = endAddr != null ? '$startAddr:$endAddr' : startAddr;
                    _selectedCellValue = value;
                    _editingCell = (end == null || start == end) ? start : null;
                  });
                },
              ),
            ),
            /// Sheet tabs + zoom bar
            Container(
              height: 36,
              color: Colors.grey[100],
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: _sheets.map((sheet) => GestureDetector(
                        onTap: () => _switchSheet(sheet),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(
                              color: sheet == _activeSheet ? Colors.green : Colors.transparent,
                              width: 2,
                            )),
                          ),
                          alignment: Alignment.center,
                          child: Text(sheet),
                        ),
                      )).toList(),
                    ),
                  ),
                  Container(
                    width: 200,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: Colors.grey[300]!, width: 1)),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _scale = 1.0),
                          child: Text('${(_scale * 100).round()}%', style: const TextStyle(fontSize: 11)),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            ),
                            child: ExcludeFocus(
                              child: Slider(
                                value: _scale.clamp(0.3, 4.0),
                                min: 0.3,
                                max: 4.0,
                                activeColor: Colors.green,
                                onChanged: (v) => setState(() => _scale = v),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}