class Colours {
  // Text colors
  static const String green = '\x1B[32m';
  static const String brightGreen = '\x1B[92m';
  static const String white = '\x1B[37m';
  static const String reset = '\x1B[0m';
  
  // Cursor control - try different approach for PowerShell
  static const String blinkOn = '\x1B[5m';  // Standard blink
  static const String blinkOff = '\x1B[25m';
  static const String bold = '\x1B[1m';     // Bold as alternative
  static const String boldOff = '\x1B[22m';
  
  // Clear screen and position cursor
  static const String clearScreen = '\x1B[2J';
  static const String home = '\x1B[H';
  
  // Hide/show cursor
  static const String hideCursor = '\x1B[?25l';
  static const String showCursor = '\x1B[?25h';
}