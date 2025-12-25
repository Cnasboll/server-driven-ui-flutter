import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:hero_common/models/biography_model.dart';
import 'package:hero_common/models/hero_model.dart';
import 'package:v04/terminal/terminal.dart';

class Sound {
  // Track currently playing sounds to prevent overlaps
  static final Map<String, Future<void>> _playingSounds = {};
  
  static Future<void> _playAudioFileInternal(String fileName) async {
    try {
      // Construct path to assets folder
      final assetsPath = path.join(Directory.current.path, 'assets', fileName);
      final file = File(assetsPath);
      
      if (!await file.exists()) {
        Terminal.println('Audio file not found: $assetsPath');  
        return;
      }
      
      // Check supported formats
      final extension = fileName.toLowerCase().split('.').last;
      final supportedFormats = ['wav', 'mp3', 'aac', 'm4a', 'flac', 'ogg'];
      
      if (!supportedFormats.contains(extension)) {
        Terminal.println('Unsupported audio format: .$extension');
        Terminal.println('Supported formats: ${supportedFormats.join(', ')}');
        return;
      }
      
      // Platform-specific audio playback
      if (Platform.isWindows) {
        await _playOnWindows(assetsPath);
      } else if (Platform.isMacOS) {
        await _playOnMacOS(assetsPath);
      } else if (Platform.isLinux) {
        await _playOnLinux(assetsPath);
      } else {
        Terminal.println('Audio playback not supported on this platform');
      }
    } catch (e) {
      Terminal.println('Error playing audio file: $e');
    }
  }
  
  static Future<void> playAudioFile(String fileName) async {
    var future = _playingSounds[fileName];
    if (future != null) {
      return future;
    }

    // Add to playing sounds
    future = _playingSounds[fileName] = _playAudioFileInternal(fileName);

    try {
      await future;
    } finally {
      // Always reset playing state when done
      _playingSounds.remove(fileName);
    }
  }
  
  static Future<void> _playOnWindows(String filePath) async {
    // Check file extension to use appropriate player
    final extension = filePath.toLowerCase().split('.').last;
    
    if (extension == 'wav') {
      // Use Media.SoundPlayer for WAV files
      await Process.run('powershell', [
        '-Command',
        '(New-Object Media.SoundPlayer "$filePath").PlaySync()'
      ]);
    } else {
      // Use Windows Media Player for MP3, MP4, etc.
      try {
        await Process.run('powershell', [
          '-Command',
          'Add-Type -AssemblyName presentationCore; '
          '\$mediaPlayer = New-Object system.windows.media.mediaplayer; '
          '\$mediaPlayer.open([uri]"$filePath"); '
          '\$mediaPlayer.Play(); '
          'while (\$mediaPlayer.NaturalDuration.HasTimeSpan -eq \$false) { Start-Sleep -Milliseconds 100 }; '
          'while (\$mediaPlayer.Position -lt \$mediaPlayer.NaturalDuration.TimeSpan) { Start-Sleep -Milliseconds 100 }; '
          '\$mediaPlayer.Close()'
        ]);
      } catch (e) {
        // Fallback: Use mciSendString for better MP3 support
        try {
          await Process.run('powershell', [
            '-Command',
            'Add-Type -TypeDefinition "using System; using System.Runtime.InteropServices; public class Audio { [DllImport(\\"winmm.dll\\")]public static extern int mciSendString(string command, string buffer, int bufferSize, IntPtr hwndCallback); }"; '
            '[Audio]::mciSendString("open \\"$filePath\\" type mpegvideo alias MediaFile", "", 0, 0); '
            '[Audio]::mciSendString("play MediaFile wait", "", 0, 0); '
            '[Audio]::mciSendString("close MediaFile", "", 0, 0);'
          ]);
        } catch (e2) {
          // Final fallback to trying to open with default program
          await Process.run('cmd', ['/c', 'start', '/min', filePath]);
        }
      }
    }
  }
  
  static Future<void> _playOnMacOS(String filePath) async {
    // Use afplay command on macOS
    await Process.run('afplay', [filePath]);
  }
  
  static Future<void> _playOnLinux(String filePath) async {
    // Try different audio players available on Linux
    final List<List<String>> players = [
      ['aplay', filePath],           // ALSA player
      ['paplay', filePath],          // PulseAudio player  
      ['ffplay', '-nodisp', '-autoexit', filePath], // FFmpeg player
      ['play', filePath],            // SoX player
    ];
    
    for (final player in players) {
      try {
        final result = await Process.run(player[0], player.sublist(1));
        if (result.exitCode == 0) {
          return; // Successfully played
        }
      } catch (e) {
        continue; // Try next player
      }
    }
    
    // If no player worked, print error
    Terminal.println('No audio player found. Install aplay, paplay, ffplay, or play.');
  }
  
    static Future<void> playOnlineSound() async {
   
    return playAudioFile('online.wav'); 
  }
  
  static Future<void> playSearchSound() async {
    await playAudioFile('hero_search.mp3');
  }

  static Future<void> playHeroDeletedSound() async {
    await playAudioFile('hero_delete.wav');
  }

  static Future<void> playWarningSound() async {
    await playAudioFile('deletion_warning.wav');
  }

  static Future<void> playDownloadComplete() async {
    await playAudioFile('download_complete.wav');
  }

  static Future<void> playReconciliationComplete() async {
    await playAudioFile('reconciliation_complete.wav');
  }

  static Future<void> playExitSound() async {
    await playAudioFile('system_exit.wav');
  }
  
  static Future<void> playMenuSound() async {
    await playAudioFile('menu_select.wav');
  }

static Future<void> playCharacterSavedSound(HeroModel hero) async {
    if (hero.biography.alignment.index > Alignment.good.index) {
      await playVillainSavedSound();
    } else {
      await playHeroSavedSound();
    }
  }

  static Future<void> playHeroSavedSound() async {
    await playAudioFile('hero_saved.wav');
  }
  static Future<void> playVillainSavedSound() async {
    await playAudioFile('villain_saved.wav');
  }
}