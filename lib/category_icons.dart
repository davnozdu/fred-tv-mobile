/// Maps a playlist category name to one of the bundled category icons
/// (assets/categories/*.png). Matching is keyword-based and multilingual;
/// returns null when nothing fits (the caller then shows a fallback icon).

String _a(String name) => 'assets/categories/$name.png';

// Genre / country / section keywords, ordered most-specific first.
const List<(String, List<String>)> _table = [
  // App sections / special
  ('favorites', ['избран', 'улюблен', 'favorit', 'favourite']),
  ('adult', ['18+', 'adult', 'xxx', 'взросл', 'эротик', 'porn', 'для дорослих']),
  ('archive', ['архив', 'архів', 'archive', 'catchup', 'catch-up']),
  ('radio', ['радио', 'радіо', 'radio', ' fm', 'fm ']),
  ('search', ['поиск', 'пошук', 'search']),
  ('settings', ['настрой', 'налашт', 'setting']),
  ('launcher', ['launcher', 'лаунчер']),
  ('premium', ['premium', 'премиум', 'преміум', 'vip', 'плюс', 'plus']),
  ('new', ['новинк', 'новинки', ' new', 'new ', 'нове ', 'свеж']),
  // Genres
  ('news', ['новост', 'news', 'інформ', 'инфо', 'новини']),
  ('movies', ['кино', 'кіно', 'фильм', 'фільм', 'movie', 'cinema', 'кінозал']),
  ('series', ['сериал', 'серіал', 'series', 'сериус', 'tv show']),
  ('kids', ['дет', 'діт', 'kids', 'child', 'мульт', 'cartoon', 'малыш', 'дитяч']),
  ('music', ['муз', 'music', 'музык', 'музич', 'концерт']),
  ('edu', [
    'познават', 'наук', 'science', 'discovery', 'educ', 'образоват',
    'докум', 'document', 'пізнавальн', 'природ'
  ]),
  ('sports_alt', ['футбол', 'football', 'soccer', 'матч']),
  ('sports', ['спорт', 'sport']),
  ('family', ['семейн', 'сімейн', 'family', 'для всей семьи', 'общие', 'загальн']),
  // Countries / regions
  ('usa', ['usa', 'сша', 'америк', 'united states', 'us ', 'eng', 'английск']),
  ('ukraine', ['україн', 'украин', 'ukrain', 'укр ']),
  ('moldova', ['moldov', 'молдов', 'romanian', 'român', 'румын', 'молдавськ']),
  ('turkey', ['türk', 'turk', 'турец', 'туреч', 'турк', 'turkish']),
  ('israel', [
    'israel', 'ізраїл', 'израил', 'עברית', 'ישראל', 'hebrew', 'еврей', 'іврит'
  ]),
  ('armenia', ['armenia', 'армян', 'вірмен', 'հայ', 'арм ']),
  ('georgia', ['georgia', 'грузин', 'ქართ', 'груз', 'georgian']),
  ('kazakhstan', ['казах', 'қазақ', 'kazakh']),
  ('azerbaijan', ['азерб', 'azərb', 'azer', 'азербайдж']),
  ('belarus', ['белар', 'білор', 'belarus', 'беларус']),
  ('central_asia', [
    'тадж', 'тоҷик', 'tajik', 'центральн', 'central asia', 'узбек', 'uzbek',
    'кыргыз', 'kyrgyz', 'туркмен', 'средняя азия', 'азия'
  ]),
  ('international', [
    'междунар', 'міжнар', 'international', 'world', 'світ', 'зарубеж',
    'иностран', 'foreign', 'global', 'мир '
  ]),
  ('regional', [
    'регион', 'регіон', 'regional', 'местн', 'міськ', 'област', 'край',
    'город', 'локальн'
  ]),
];

String? categoryIconAsset(String name) {
  final n = name.toLowerCase().trim();
  if (n.isEmpty) return null;
  bool has(String s) => n.contains(s);
  for (final e in _table) {
    for (final k in e.$2) {
      if (has(k)) return _a(e.$1);
    }
  }
  // Quality markers last (so "Кино HD" stays movies, but a plain "HD" group
  // gets the HD icon).
  if (has('8k')) return _a('uhd_8k');
  if (has('4k') || has('uhd') || has('ultra')) return _a('uhd_4k');
  if (has('orig')) return _a('hd_orig');
  if (has('hd')) return _a('hd');
  return null;
}
