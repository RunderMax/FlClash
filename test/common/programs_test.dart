import 'dart:convert';

import 'package:fl_clash/common/programs.dart';
import 'package:flutter_test/flutter_test.dart';

const _systemRoot = r'C:\Windows';
const _own = r'C:\Program Files\Sloth Clash';

Map<String, String?> _process(String path, [String? description]) => {
  'Path': path,
  'Description': description,
};

void main() {
  test('names each running program once by its executable', () {
    final programs = parsePrograms(
      jsonEncode([
        _process(
          r'C:\Program Files\Google\Chrome\Application\chrome.exe',
          'Google Chrome',
        ),
        _process(
          r'C:\Program Files\Google\Chrome\Application\CHROME.EXE',
          'Google Chrome',
        ),
        _process(r'D:\Apps\Telegram\Telegram.exe', ''),
      ]),
      systemRoot: _systemRoot,
      own: _own,
    );

    expect([for (final program in programs) program.packageName], [
      'chrome.exe',
      'Telegram.exe',
    ]);
    expect([for (final program in programs) program.label], [
      'Google Chrome',
      'Telegram',
    ]);
  });

  test('marks what Windows ships as system and leaves this app out', () {
    final programs = parsePrograms(
      jsonEncode([
        _process(r'c:\windows\explorer.exe', 'Windows Explorer'),
        _process(r'C:\Program Files\Sloth Clash\FlClashCore.exe'),
        _process(r'C:\Tools\Code - Insiders.exe', 'VS Code Insiders'),
        _process(r'C:\Tools\bad,name.exe', 'Bad'),
      ]),
      systemRoot: _systemRoot,
      own: _own,
    );

    expect([for (final program in programs) program.packageName], [
      'explorer.exe',
      'Code - Insiders.exe',
    ]);
    expect(programs.first.system, isTrue);
    expect(programs.first.launchable, isFalse);
    expect(programs.last.system, isFalse);
  });

  test('reads the single object PowerShell writes for one process', () {
    final programs = parsePrograms(
      jsonEncode(_process(r'C:\Apps\Discord.exe', 'Discord')),
      systemRoot: _systemRoot,
      own: _own,
    );

    expect(programs.single.packageName, 'Discord.exe');
  });

  test('takes no output as no programs', () {
    expect(parsePrograms('', systemRoot: _systemRoot, own: _own), isEmpty);
  });
}
