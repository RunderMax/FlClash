import 'dart:convert';

import 'package:fl_clash/common/programs.dart';
import 'package:flutter_test/flutter_test.dart';

const _own = r'C:\Program Files\Sloth Clash';

Map<String, Object?> _exe(String path, {String? description, String? icon}) => {
  'path': path,
  'description': description,
  'running': false,
  'icon': icon,
};

List<String> _names(ProgramGroup group) => [
  for (final program in group.programs) program.packageName,
];

void main() {
  test('keeps the programs of one app together under its name', () {
    final groups = parsePrograms(
      jsonEncode([
        {
          'name': 'WeChat',
          'icon': r'C:\icons\wechat.png',
          'exes': [
            _exe(
              r'C:\Program Files\Tencent\WeChat\WeChat.exe',
              description: 'WeChat',
            ),
            _exe(
              r'C:\Program Files\Tencent\WeChat\WeChatAppEx.exe',
              description: 'WeChat App',
            ),
            _exe(r'C:\Program Files\Tencent\WeChat\uninst.exe'),
            _exe(r'C:\Program Files\Tencent\WeChat\bad,name.exe'),
          ],
        },
        {'name': 'Telegram', 'exes': _exe(r'D:\Apps\Telegram\Telegram.exe')},
      ]),
      own: _own,
    );

    expect([for (final group in groups) group.name], ['WeChat', 'Telegram']);
    expect(_names(groups.first), ['WeChat.exe', 'WeChatAppEx.exe']);
    expect(groups.last.programs.single.label, 'Telegram');
    expect(programIconOf('wechatappex.exe'), r'C:\icons\wechat.png');
  });

  test('leaves this app out and lists an executable only once', () {
    final groups = parsePrograms(
      jsonEncode([
        {
          'name': 'Sloth Clash',
          'exes': [_exe(r'C:\Program Files\Sloth Clash\FlClashCore.exe')],
        },
        {
          'name': 'Chrome',
          'exes': [_exe(r'C:\Chrome\chrome.exe')],
        },
        {
          'name': 'Chrome Beta',
          'exes': [_exe(r'C:\Chrome Beta\CHROME.EXE')],
        },
      ]),
      own: _own,
    );

    expect([for (final group in groups) group.name], ['Chrome']);
  });

  test('takes no output as no programs', () {
    expect(parsePrograms('', own: _own), isEmpty);
  });
}
