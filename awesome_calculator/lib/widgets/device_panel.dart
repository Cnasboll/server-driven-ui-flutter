import 'dart:async';
import 'package:shql/shql.dart';
import 'package:awesome_calculator/widgets/post_it_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'keyboard.dart';
import 'cash_register_display.dart';
import 'terminal_display.dart';
import 'package:awesome_calculator/utils/sound_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';

/// A retro-styled computer terminal with a steampunk mechanical keyboard.
///
/// Features:
/// - Green CRT-style terminal display with blinking cursor
/// - Full ASCII keyboard with shift support and drum rotation animations
/// - Command history navigation (up/down arrows)
/// - Multi-line input support (SHIFT-ENTER for soft returns)
/// - Click-to-position cursor placement
/// - Physical and virtual keyboard synchronization
class DevicePanel extends StatefulWidget {
  const DevicePanel({super.key});

  @override
  State<DevicePanel> createState() => _DevicePanelState();
}

class _DevicePanelState extends State<DevicePanel>
    with SingleTickerProviderStateMixin {
  late CancellationToken _cancellationToken;
  bool _isExecuting = false;
  List<Offset> _plotPoints = [];

  Future<void> _copyAllShqlAssetsToExternalStorage() async {
    if (kIsWeb) {
      return; // Path provider is not supported on web
    }
    try {
      // Map filename → asset path (stdlib lives in the shql package, rest are local)
      final assetPaths = {
        'stdlib.shql': 'packages/shql/assets/stdlib.shql',
        'hello_world.shql': 'assets/shql/hello_world.shql',
        'hello_name.shql': 'assets/shql/hello_name.shql',
        'calculator.shql': 'assets/shql/calculator.shql',
        'threads.shql': 'assets/shql/threads.shql',
      };
      Directory extDir = Platform.isAndroid
          ? Directory('/storage/emulated/0/Download')
          : await getApplicationDocumentsDirectory();
      for (final entry in assetPaths.entries) {
        final data = await rootBundle.loadString(entry.value);
        final file = File('${extDir.path}/${entry.key}');
        await file.writeAsString(data);
      }
    } catch (e) {
      // Optionally print or handle error
    }
  }

  Future<void> _handleLoadPressed() async {
    try {
      String? initialDirectory;
      if (!kIsWeb) {
        Directory extDir = Platform.isAndroid
            ? Directory('/storage/emulated/0/Download')
            : await getApplicationDocumentsDirectory();
        initialDirectory = extDir.path;
      }

      final result = await FilePicker.platform.pickFiles(
        initialDirectory: initialDirectory,
        type: FileType.custom,
        allowedExtensions: ['shql'],
      );

      if (result != null) {
        String contents;
        if (kIsWeb) {
          // On web, read bytes and decode
          final bytes = result.files.single.bytes;
          if (bytes != null) {
            contents = utf8.decode(bytes);
          } else {
            throw Exception("Failed to load file bytes on web.");
          }
        } else {
          // On other platforms, read from path
          final path = result.files.single.path;
          if (path != null) {
            final file = File(path);
            contents = await file.readAsString();
          } else {
            throw Exception("File path is null on a non-web platform.");
          }
        }

        await execute(
          contents,
          "Finished executing ${result.files.single.name}.",
        );
      }
    } catch (e) {
      terminalPrint('LOAD ERROR: $e');
    }
  }

  void _printStartupBanner() {
    setState(() {
      // Clear terminal and print banner
      _terminalText = '';
      _cursorPosition = _inputStartPosition = 0;
      terminalPrint('SHQL™ v 5.0');
      showPrompt();
    });
  }

  Future<void> loadStandardLibrary() async {
    final stdlibCode = await rootBundle.loadString('packages/shql/assets/stdlib.shql');
    terminalPrint("Loading standard library...");
    execute(stdlibCode, "Standard library loaded.");
  }

  Future<void> execute(String code, String complete) async {
    terminalPrint(code);
    setState(() {
      _currentInput = '';
      _isExecuting = true;
      _cancellationToken.reset();
    });
    try {
      await Engine.execute(
        code,
        runtime: runtime,
        constantsSet: constantsSet,
        cancellationToken: _cancellationToken,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExecuting = false;
        });
      }
    }
    terminalPrint(complete);
    _printStartupBanner();
  }

  void resetEngine() {
    setState(() {
      constantsSet = Runtime.prepareConstantsSet();
      runtime = Runtime.prepareRuntime(constantsSet);
      runtime.readlineFunction = () async => await readline();
      runtime.promptFunction = (String prompt) async {
        return await readline(prompt);
      };
      runtime.printFunction = (p1) => terminalPrint(p1.toString());

      runtime.clsFunction = () async {
        _printStartupBanner();
      };

      runtime.hideGraphFunction = () async {
        setState(() {
          _plotPoints.clear();
        });
      };

      runtime.plotFunction = (xVector, yVector) async {
        final points = <Offset>[];
        if (xVector is List && yVector is List) {
          final length = xVector.length < yVector.length
              ? xVector.length
              : yVector.length;
          for (int i = 0; i < length; i++) {
            final x = xVector[i];
            final y = yVector[i];
            if (x is num && y is num) {
              points.add(Offset(x.toDouble(), y.toDouble()));
            }
          }
        } else {
          throw Exception("plot() arguments must be lists of numbers");
        }
        setState(() {
          _plotPoints = points;
        });
      };
    });
    _printStartupBanner();
    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    await loadStandardLibrary();
  }

  late ConstantsSet constantsSet;
  late Runtime runtime;
  // Constants
  static const String _promptSymbol = '> ';
  static const int _tabSpaces = 4;
  static const Duration _cursorBlinkDuration = Duration(milliseconds: 530);
  static const Duration _keyPressDuration = Duration(milliseconds: 150);

  // Terminal state
  String _terminalText = _promptSymbol;
  int _cursorPosition = _promptSymbol.length;
  int _inputStartPosition =
      0; // Position of the current prompt in _terminalText
  final List<String> _commandHistory = [];
  int _historyIndex = -1;
  String _currentInput = '';

  // Terminal I/O state
  bool _waitingForInput = false;
  void Function(String)? _readlineCallback;

  static const int maxWheels = 12;
  // Cash register display
  String _displayValue = 'NULL'.padLeft(maxWheels, ' ');

  // UI state
  String? _pressedKey;
  bool _showCursor = true;
  late AnimationController _cursorController;

  // Keyboard state
  bool _virtualShiftToggled = false;
  bool _physicalShiftPressed = false;
  bool get _shiftPressed => _virtualShiftToggled || _physicalShiftPressed;

  final FocusNode _focusNode = FocusNode();

  // Define keyboard layout - calculator-optimized (all calc symbols unshifted, QWERTY preserved)
  final List<List<String>> _keyboardLayout = [
    ['SIN', 'COS', 'TAN', 'ASIN', 'ACOS', 'ATAN', 'SQRT', 'EXP', 'LOG'],
    ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '(', ')'],
    ['+', '-', '*', '/', '^', '%', '=', '<', '>', '!', '&', '|', '`', '~'],
    ['TAB', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']'],
    [
      'a',
      's',
      'd',
      'f',
      'g',
      'h',
      'j',
      'k',
      'l',
      ':',
      '\'',
      '"',
      '\\',
      '@',
      '#',
      '\$',
    ],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', ',', ';', '.', '/', '_', 'ENTER'],
    ['SHIFT', 'SPACE', 'BACK', 'DEL', '←', '↑', '↓', '→'],
    ['BREAK', 'LOAD', 'RESET'],
  ];

  // Shift mappings for characters
  final Map<String, String> _shiftMap = {
    '[': '{', ']': '}',
    '/': '?',
    'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D', 'e': 'E', 'f': 'F', 'g': 'G',
    'h': 'H', 'i': 'I', 'j': 'J', 'k': 'K', 'l': 'L', 'm': 'M', 'n': 'N',
    'o': 'O', 'p': 'P', 'q': 'Q', 'r': 'R', 's': 'S', 't': 'T', 'u': 'U',
    'v': 'V', 'w': 'W', 'x': 'X', 'y': 'Y', 'z': 'Z',
    'ENTER': '↵', // Soft return / line break
    // Arrow keys don't shift
  };

  // Function names that insert with parentheses
  final Set<String> _functionNames = {
    'SIN',
    'COS',
    'TAN',
    'ASIN',
    'ACOS',
    'ATAN',
    'SQRT',
    'EXP',
    'LOG',
  };

  @override
  void initState() {
    super.initState();
    _cancellationToken = CancellationToken();
    _copyAllShqlAssetsToExternalStorage();
    resetEngine();

    _cursorController = AnimationController(
      vsync: this,
      duration: _cursorBlinkDuration,
    )..repeat(reverse: true);

    _cursorController.addListener(() {
      setState(() {
        _showCursor = _cursorController.value > 0.5;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    _printStartupBanner();
    // Initialize display to show NULL for empty input
    _evaluateCurrentInput();
  }

  @override
  void dispose() {
    _cursorController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Print text to terminal (appends to display, doesn't create new prompt)
  void terminalPrint(String text) {
    setState(() {
      // Move cursor to end and append text with newline
      _terminalText += '\n$text';
      _cursorPosition = _inputStartPosition = _terminalText.length;
    });
  }

  /// Request input from user with an optional prompt
  /// Returns a Future that completes when user presses ENTER
  Future<String> readline([String? prompt]) async {
    final completer = Completer<String>();

    // If the execution is cancelled while waiting for input, complete immediately.
    if (_cancellationToken.isCancelled) {
      completer.complete('');
      return completer.future;
    }

    final subscription = Stream.periodic(const Duration(milliseconds: 100))
        .listen((_) {
          if (_cancellationToken.isCancelled) {
            if (!completer.isCompleted) {
              completer.complete('');
            }
          }
        });

    completer.future.whenComplete(() {
      subscription.cancel();
    });

    setState(() {
      _waitingForInput = true;
      _readlineCallback = (String input) {
        if (!completer.isCompleted) {
          completer.complete(input);
        }
        _waitingForInput = false;
        _readlineCallback = null;
      };

      // Add prompt if provided, otherwise just position for input
      if (prompt != null && prompt.isNotEmpty) {
        _terminalText += '\n$prompt';
      } else {
        _terminalText += '\n';
      }
      _inputStartPosition = _terminalText.length;
      _cursorPosition = _terminalText.length;
    });

    return completer.future;
  }

  /// Get the current input text (after the current prompt, may be multi-line)
  String _getCurrentLine() {
    return _terminalText.substring(_inputStartPosition).trim();
  }

  /// Replace current input with text from history (handles multi-line)
  void _replaceCurrentLine(String text) {
    _terminalText = _terminalText.substring(0, _inputStartPosition) + text;
    _cursorPosition = _terminalText.length;
  }

  /// Navigate command history (up/down arrows)
  void _navigateHistory(bool isUp) {
    if (_commandHistory.isEmpty) return;

    // Save current input when first navigating history
    if (_historyIndex == -1) {
      _currentInput = _getCurrentLine();
    }

    if (isUp) {
      // Move backward in history (older commands)
      if (_historyIndex < _commandHistory.length - 1) {
        _historyIndex++;
        final historyCommand =
            _commandHistory[_commandHistory.length - 1 - _historyIndex];
        _replaceCurrentLine(historyCommand);
      }
    } else {
      // Move forward in history (newer commands)
      if (_historyIndex > 0) {
        _historyIndex--;
        final historyCommand =
            _commandHistory[_commandHistory.length - 1 - _historyIndex];
        _replaceCurrentLine(historyCommand);
      } else if (_historyIndex == 0) {
        // Restore current input
        _historyIndex = -1;
        _replaceCurrentLine(_currentInput);
      }
    }
  }

  (String, String) _formatResult(dynamic result) {
    final String padding = ' ';

    if (result is UserFunction) {
      return ('USER FUNCTION ${result.name}', padding);
    }

    // Format result based on type
    if (result == null) {
      return ('NULL', padding);
    }

    if (result is int) {
      return (result.toString(), '0');
    }

    if (result is double) {
      if (result.isNaN) {
        return ('GARLIC NAAN', padding);
      }
      if (result.isInfinite) {
        return (result.isNegative ? '-INFINITY' : 'INFINITY', padding);
      } // Format with up to 6 decimal places
      return (
        result
            .toStringAsFixed(6)
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll(RegExp(r'\.$'), ''),
        '0',
      );
    }

    if (result is String) {
      return (result, padding);
    }

    return (result.toString(), padding);
  }

  /// Evaluate the current input and update the cash register display
  void _evaluateCurrentInput() {
    final currentInput = _terminalText.substring(_inputStartPosition).trim();

    if (currentInput.isEmpty) {
      final (formatted, padding) = _formatResult(null);
      setState(() {
        _displayValue = formatted.padLeft(maxWheels, padding);
      });
      return;
    }

    Engine.evalExpr(
          currentInput,
          runtime: runtime.sandbox(),
          constantsSet: constantsSet,
        )
        .then((result) {
          if (!mounted) return;
          final (formatted, padding) = _formatResult(result);
          setState(() {
            _displayValue = formatted.padLeft(maxWheels, padding);
          });
        })
        .catchError((e) {
          // Keep previous valid result
          if (!mounted) return;
          print(e);
        });
  }

  /// Handle up arrow: command history on last line, cursor movement otherwise
  void _handleArrowUp() {
    final isInInputSection = _cursorPosition >= _inputStartPosition;

    if (!isInInputSection) return;

    // Don't navigate history if waiting for readline input
    if (_waitingForInput) {
      return; // Just stay in place, don't allow history navigation during readline
    }

    // Check if we're on the first line of input
    final firstNewlineInInput = _terminalText.indexOf(
      '\n',
      _inputStartPosition,
    );
    final isOnFirstLine =
        firstNewlineInInput == -1 || _cursorPosition <= firstNewlineInInput;

    if (isOnFirstLine) {
      // On first line: navigate history
      _navigateHistory(true);
      _evaluateCurrentInput();
    } else {
      // Not on first line: move cursor up within current input
      int currentLineStart =
          _terminalText.lastIndexOf('\n', _cursorPosition - 1) + 1;
      int prevLineStart =
          _terminalText.lastIndexOf('\n', currentLineStart - 2) + 1;

      // Make sure we don't go before the prompt
      if (prevLineStart < _inputStartPosition) {
        prevLineStart = _inputStartPosition;
      }

      int offsetInLine = _cursorPosition - currentLineStart;
      _cursorPosition = prevLineStart + offsetInLine;

      int prevLineEnd = currentLineStart - 1;
      if (_cursorPosition > prevLineEnd) _cursorPosition = prevLineEnd;
    }
  }

  void showPrompt() {
    setState(() {
      _terminalText += '\n$_promptSymbol';
      _inputStartPosition = _cursorPosition = _terminalText.length;
    });
  }

  /// Handle down arrow: command history on last line, cursor movement otherwise
  void _handleArrowDown() {
    final isInInputSection = _cursorPosition >= _inputStartPosition;

    if (!isInInputSection) return;

    // Don't navigate history if waiting for readline input
    if (_waitingForInput) {
      return; // Just stay in place, don't allow history navigation during readline
    }

    // Check if there's a next line in the current input
    final nextNewline = _terminalText.indexOf('\n', _cursorPosition);
    final isOnLastLine = nextNewline == -1;

    if (isOnLastLine) {
      // On last line: navigate history
      _navigateHistory(false);
      _evaluateCurrentInput();
    } else {
      // Not on last line: move cursor down within current input
      int currentLineStart =
          _terminalText.lastIndexOf('\n', _cursorPosition - 1) + 1;
      int nextLineStart = nextNewline + 1;
      int offsetInLine = _cursorPosition - currentLineStart;
      _cursorPosition = nextLineStart + offsetInLine;

      int nextLineEnd = _terminalText.indexOf('\n', nextLineStart);
      if (nextLineEnd == -1) nextLineEnd = _terminalText.length;
      if (_cursorPosition > nextLineEnd) _cursorPosition = nextLineEnd;
    }
  }

  void _handleKeyPress(String key) async {
    if (key == 'ENTER' && !_shiftPressed) {
      SoundManager().playSound('sounds/typewriter-line-break-1.wav');
      if (_waitingForInput && _readlineCallback != null) {
        _readlineCallback!(_terminalText.substring(_inputStartPosition));
      } else {
        final currentInput = _terminalText
            .substring(_inputStartPosition)
            .trim();
        if (currentInput.isNotEmpty) {
          setState(() {
            _commandHistory.add(currentInput);
            _historyIndex = -1;
            _currentInput = '';
            _isExecuting = true;
            _cancellationToken.reset();
          });

          await Future.delayed(Duration.zero);

          try {
            final result = await Engine.execute(
              currentInput,
              runtime: runtime,
              constantsSet: constantsSet,
              cancellationToken: _cancellationToken,
            );
            if (!mounted) return;
            final (formatted, padding) = _formatResult(result);
            terminalPrint(formatted);
          } catch (e) {
            if (!mounted) return;
            terminalPrint(e.toString());
          } finally {
            if (!mounted) return;
            setState(() {
              _isExecuting = false;
            });
            showPrompt();
          }
        } else {
          showPrompt();
        }
      }
      return;
    }

    setState(() {
      var sound = "sounds/typewriter_key.wav";
      _pressedKey = key;

      // Handle arrow keys for cursor movement
      if (key == '←') {
        if (_cursorPosition > 0) {
          _cursorPosition--;
          // Don't allow cursor before the current prompt
          if (_cursorPosition < _inputStartPosition) {
            _cursorPosition = _inputStartPosition;
          }
        }
      } else if (key == '→') {
        if (_cursorPosition < _terminalText.length) {
          _cursorPosition++;
        }
      } else if (key == '↑') {
        _handleArrowUp();
      } else if (key == '↓') {
        _handleArrowDown();
      } else if (key == 'LOAD') {
        _handleLoadPressed();
      } else if (key == 'RESET') {
        resetEngine();
      } else if (key == 'BREAK') {
        if (_isExecuting) {
          _cancellationToken.cancel();
        }
      } else if (key == 'SHIFT') {
        if (!_physicalShiftPressed) {
          _virtualShiftToggled = !_virtualShiftToggled;
        }
      } else if (key == 'TAB') {
        _terminalText =
            _terminalText.substring(0, _cursorPosition) +
            ' ' * _tabSpaces +
            _terminalText.substring(_cursorPosition);
        _cursorPosition += _tabSpaces;
      } else if (key == 'ENTER') {
        sound = 'sounds/typewriter-line-break-1.wav';
        if (_shiftPressed) {
          // SHIFT-ENTER: Soft return (line break without prompt)
          _terminalText =
              '${_terminalText.substring(0, _cursorPosition)}\n${_terminalText.substring(_cursorPosition)}';
          _cursorPosition += 1;
        }
      } else if (key == 'BACK') {
        // Play typewriter sound for key press
        sound = 'sounds/typewriter-backspace-1.wav';
        if (_cursorPosition > _inputStartPosition) {
          _terminalText =
              _terminalText.substring(0, _cursorPosition - 1) +
              _terminalText.substring(_cursorPosition);
          _cursorPosition--;
        }
      } else if (key == 'DEL') {
        sound = 'sounds/typewriter-backspace-1.wav';
        if (_cursorPosition >= _inputStartPosition &&
            _cursorPosition < _terminalText.length) {
          _terminalText =
              _terminalText.substring(0, _cursorPosition) +
              _terminalText.substring(_cursorPosition + 1);
        }
      } else if (key == 'SPACE') {
        _terminalText =
            _terminalText.substring(0, _cursorPosition) +
            ' ' +
            _terminalText.substring(_cursorPosition);
        _cursorPosition++;
      } else {
        // Regular character input
        String char = key;
        if (_shiftPressed) {
          char = _shiftMap[key.toLowerCase()] ?? key.toUpperCase();
        }

        // Insert parentheses for function names
        if (_functionNames.contains(char)) {
          char += '()';
          _terminalText =
              _terminalText.substring(0, _cursorPosition) +
              char +
              _terminalText.substring(_cursorPosition);
          _cursorPosition += char.length - 1; // Position cursor inside ()
        } else {
          _terminalText =
              _terminalText.substring(0, _cursorPosition) +
              char +
              _terminalText.substring(_cursorPosition);
          _cursorPosition += char.length;
        }
      }
      // Play typewriter sound for key press
      SoundManager().playSound(sound);

      // After any text modification, evaluate the current input for the cash register display
      _evaluateCurrentInput();

      // Reset pressed key visual feedback
      Future.delayed(_keyPressDuration, () {
        if (mounted) {
          setState(() {
            _pressedKey = null;
          });
        }
      });
    });
  }

  /// Handle physical keyboard events
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Play typewriter sound for physical keyboard
      var sound = "sounds/typewriter_key.wav";
      if (event.logicalKey == LogicalKeyboardKey.backspace ||
          event.logicalKey == LogicalKeyboardKey.delete) {
        sound = "sounds/typewriter-backspace-1.wav";
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        sound = "sounds/typewriter-line-break-1.wav";
      }
      SoundManager().playSound(sound);

      String? key;

      // Handle arrow keys for cursor movement
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _handleKeyPress('←');
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _handleKeyPress('→');
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _handleKeyPress('↑');
        return;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _handleKeyPress('↓');
        return;
      }

      // Map physical keyboard keys to our virtual keyboard
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        key = 'TAB';
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        key = 'SPACE';
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        key = 'ENTER';
      } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
        key = 'BACK';
      } else if (event.logicalKey == LogicalKeyboardKey.delete) {
        key = 'DEL';
      } else {
        final label = event.logicalKey.keyLabel;
        if (label.length == 1) {
          final code = label.codeUnitAt(0);
          // Accept all printable ASCII characters
          if (code >= 32 && code <= 126) {
            // The physical keyboard sends the actual character already shifted
            // So we need to map back to the base key
            if (code >= 97 && code <= 122) {
              // a-z (lowercase)
              key = label;
            } else if (code >= 65 && code <= 90) {
              // A-Z (uppercase from shift)
              key = label.toLowerCase(); // Map back to base key
            } else {
              // For symbols, the physical keyboard sends the shifted version
              // Find which base key produces this character
              final baseKey = _shiftMap.entries
                  .firstWhere(
                    (entry) => entry.value == label,
                    orElse: () => MapEntry(label, label),
                  )
                  .key;
              key = baseKey;
            }
          }
        }
      }

      if (key != null) {
        _handleKeyPress(key);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                event.logicalKey == LogicalKeyboardKey.shiftRight) {
              setState(() {
                _physicalShiftPressed = true;
                _virtualShiftToggled = false;
              });
              return;
            }
          } else if (event is KeyUpEvent) {
            if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                event.logicalKey == LogicalKeyboardKey.shiftRight) {
              setState(() {
                _physicalShiftPressed = false;
              });
              return;
            }
          }

          _handleKeyEvent(event);
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF2B2B2B),
          child: Stack(
            children: [
              Column(
                children: [
                  // Terminal Display
                  TerminalDisplay(
                    terminalText: _terminalText,
                    cursorPosition: _cursorPosition,
                    showCursor: _showCursor,
                    inputStartPosition: _inputStartPosition,
                    promptSymbol: _promptSymbol,
                    onTapRequest: () => _focusNode.requestFocus(),
                    onCursorPositionChanged: (newPosition) {
                      setState(() {
                        _cursorPosition = newPosition;
                      });
                    },
                    plotPoints: _plotPoints,
                  ),

                  // Cash Register Display
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: CashRegisterDisplay(
                        value: _displayValue,
                        maxWheels: maxWheels,
                      ),
                    ),
                  ),

                  // Keyboard
                  Keyboard(
                    keyboardLayout: _keyboardLayout,
                    shiftMap: _shiftMap,
                    pressedKey: _pressedKey,
                    isShifted: _shiftPressed,
                    virtualShiftToggled: _virtualShiftToggled,
                    physicalShiftPressed: _physicalShiftPressed,
                    onKeyPress: _handleKeyPress,
                    isExecuting: _isExecuting,
                  ),
                ],
              ),
              // Post-it note overlapping terminal lower right corner
              Positioned(
                top: null,
                bottom: 332,
                right: 10,
                child: PostItNote(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
