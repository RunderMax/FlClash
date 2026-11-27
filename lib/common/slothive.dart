import 'package:fl_clash/models/models.dart';

const slothiveName = 'SLOTHIVE';

/// Services of the SLOTHIVE desk, each a proxy user of its own on the mixed
/// port; the user names are kept in step with the desk.
enum SlothiveService {
  entrance('Entrance', 'PROCESS-NAME,cloudflared'),
  chatGpt('ChatGPT', 'IN-USER,slothive-chatgpt'),
  deepSeek('DeepSeek', 'IN-USER,slothive-deepseek'),
  openRouter('OpenRouter', 'IN-USER,slothive-openrouter'),
  otherAi('AI', 'IN-USER,slothive-ai'),
  search('Search', 'IN-USER,slothive-search'),
  web('Web', 'IN-USER,slothive-web'),
  mailSend('Mail Send', 'IN-USER,slothive-mail-send'),
  mailFetch('Mail Fetch', 'IN-USER,slothive-mail-fetch'),
  whatsApp('WhatsApp', 'IN-USER,slothive-whatsapp'),
  market('Market', 'IN-USER,slothive-market');

  const SlothiveService(this.id, this.matcher);

  final String id;
  final String matcher;

  String get key => '@$slothiveName $id';

  static SlothiveService? of(String key) {
    for (final service in values) {
      if (service.key == key) return service;
    }
    return null;
  }
}

Package slothivePackage(SlothiveService service, String label) => Package(
  packageName: service.key,
  label: label,
  system: false,
  internet: true,
  lastUpdateTime: 0,
);
