import 'package:flutter/widgets.dart';

/// Lightweight localization (English / Russian / Ukrainian). Language follows
/// the system locale via [Localizations.localeOf].
class S {
  final String _lang;
  S(this._lang);

  static const supportedLocales = [Locale('en'), Locale('ru'), Locale('uk')];

  static S of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return S(code == 'ru' || code == 'uk' ? code : 'en');
  }

  String _t(String en, String ru, String uk) {
    switch (_lang) {
      case 'ru':
        return ru;
      case 'uk':
        return uk;
      default:
        return en;
    }
  }

  // Menu
  String get channels => _t('Channels', 'Каналы', 'Канали');
  String get guide => _t('Guide', 'Программа', 'Програма');
  String get favorites => _t('Favorites', 'Избранное', 'Вибране');
  String get history => _t('History', 'История', 'Історія');
  String get settings => _t('Settings', 'Настройки', 'Налаштування');
  String get all => _t('All', 'Все', 'Усі');

  // Channels / search
  String get search => _t('Search…', 'Поиск…', 'Пошук…');
  String get searchChannels =>
      _t('Search channels…', 'Поиск каналов…', 'Пошук каналів…');

  // Guide
  String get noGuideData =>
      _t('No guide data', 'Нет данных программы', 'Немає даних програми');
  String get other => _t('Other', 'Другое', 'Інше');

  // Player / archive
  String get live => _t('Live', 'Эфир', 'Ефір');
  String get loadingArchive =>
      _t('Loading archive…', 'Загрузка архива…', 'Завантаження архіву…');
  String get noArchive => _t(
    'No archive programmes for this channel',
    'Нет архивных передач для этого канала',
    'Немає архівних передач для цього каналу',
  );
  String get selectAudio => _t('Select audio', 'Выбор аудио', 'Вибір аудіо');
  String get selectSubtitles =>
      _t('Select subtitles', 'Выбор субтитров', 'Вибір субтитрів');

  // Channel context menu
  String get play => _t('Play', 'Смотреть', 'Дивитися');
  String get addToFavorites =>
      _t('Add to Favorites', 'Добавить в избранное', 'Додати у вибране');
  String get removeFromFavorites => _t(
    'Remove from Favorites',
    'Убрать из избранного',
    'Прибрати з вибраного',
  );
  String get addedToFavorites =>
      _t('Added to favorites', 'Добавлено в избранное', 'Додано у вибране');
  String get removedFromFavorites => _t(
    'Removed from favorites',
    'Убрано из избранного',
    'Прибрано з вибраного',
  );

  // Settings
  String get donate => _t('Donate', 'Поддержать', 'Підтримати');
  String get defaultView =>
      _t('Default view', 'Вид по умолчанию', 'Вигляд за замовчуванням');
  String get forceTvMode => _t(
    'Force TV Mode',
    'Принудительный ТВ-режим',
    'Примусовий ТБ-режим',
  );
  String get lowLatency => _t(
    'Low latency livestreams',
    'Низкая задержка эфира',
    'Низька затримка ефіру',
  );
  String get lowLatencySub => _t(
    'Minimal delay, smaller buffer (may stutter on weak networks)',
    'Минимальная задержка, меньше буфер (возможны рывки на слабой сети)',
    'Мінімальна затримка, менший буфер (можливі ривки на слабкій мережі)',
  );
  String get bufferSize => _t('Buffer size', 'Размер буфера', 'Розмір буфера');
  String get auto => _t('Auto', 'Авто', 'Авто');
  String get bufferAutoSub => _t(
    'Auto — grows when the stream stalls',
    'Авто — растёт при подвисаниях',
    'Авто — зростає при підвисаннях',
  );
  String bufferSecondsSub(int s) => _t(
    '$s seconds — larger = more stable HD',
    '$s сек — больше = стабильнее HD',
    '$s сек — більше = стабільніше HD',
  );
  String get seconds => _t('seconds', 'сек', 'сек');
  String get extendedArchive => _t(
    'Extended archive (7 days)',
    'Расширенный архив (7 дней)',
    'Розширений архів (7 днів)',
  );
  String get extendedArchiveSub => _t(
    'More history via iptvx.one — slower first open (default: 1 day)',
    'Больше истории через iptvx.one — первое открытие дольше (по умолчанию 1 день)',
    'Більше історії через iptvx.one — перше відкриття довше (за замовчуванням 1 день)',
  );
  String get fillLogos =>
      _t('Fill logos from EPG', 'Логотипы из EPG', 'Логотипи з EPG');
  String get fillLogosSub => _t(
    'Use an EPG (XMLTV) source to fill missing channel logos',
    'Брать логотипы каналов из EPG (XMLTV)',
    'Брати логотипи каналів з EPG (XMLTV)',
  );
  String get epgUrl => _t('EPG URL', 'EPG URL', 'EPG URL');
  String get notSet => _t('Not set', 'Не задано', 'Не задано');
  String get refreshOnStart => _t(
    'Refresh sources on start',
    'Обновлять источники при запуске',
    'Оновлювати джерела під час запуску',
  );
  String get showLivestreams =>
      _t('Show livestreams', 'Показывать эфиры', 'Показувати ефіри');
  String get showMovies =>
      _t('Show movies', 'Показывать фильмы', 'Показувати фільми');
  String get showSeries =>
      _t('Show series', 'Показывать сериалы', 'Показувати серіали');
  String get sources => _t('Sources', 'Источники', 'Джерела');

  // Common
  String get cancel => _t('Cancel', 'Отмена', 'Скасувати');
  String get save => _t('Save', 'Сохранить', 'Зберегти');
  String get next => _t('Next', 'Далее', 'Далі');
  String get back => _t('Back', 'Назад', 'Назад');

  // Updates
  String updateAvailable(String version) => _t(
    'Update available ($version)',
    'Доступно обновление ($version)',
    'Доступне оновлення ($version)',
  );
  String get update => _t('Update', 'Обновить', 'Оновити');
  String get later => _t('Later', 'Позже', 'Пізніше');
  String get downloadingUpdate => _t(
    'Downloading update…',
    'Загрузка обновления…',
    'Завантаження оновлення…',
  );

  // Setup wizard
  String welcomeTitle(String app) =>
      _t('Welcome to $app', 'Добро пожаловать в $app', 'Ласкаво просимо до $app');
  String welcomeSub(bool first) => first
      ? _t(
          "Let's set up your first source",
          'Давайте настроим ваш первый источник',
          'Налаштуймо ваше перше джерело',
        )
      : _t(
          "Let's set up your new source",
          'Давайте настроим новый источник',
          'Налаштуймо нове джерело',
        );
  String get providerType => _t(
    'What is your provider type?',
    'Какой у вас тип провайдера?',
    'Який у вас тип провайдера?',
  );
  String get nameQuestion => _t(
    'What should we name this source?',
    'Как назвать этот источник?',
    'Як назвати це джерело?',
  );
  String get name => _t('Name', 'Название', 'Назва');
  String get urlQuestion => _t(
    "What is your provider's URL?",
    'Какой URL у провайдера?',
    'Який URL у провайдера?',
  );
  String get url => _t('URL', 'URL', 'URL');
  String get usernameQuestion =>
      _t('What is your username?', 'Ваш логин?', 'Ваш логін?');
  String get username => _t('Username', 'Логин', 'Логін');
  String get passwordQuestion =>
      _t('What is your password?', 'Ваш пароль?', 'Ваш пароль?');
  String get password => _t('Password', 'Пароль', 'Пароль');
  String get selectFile => _t('Select file', 'Выбрать файл', 'Вибрати файл');
  String get finish => _t('Finish', 'Готово', 'Готово');
  String get doneTitle => _t('Done!', 'Готово!', 'Готово!');
  String get doneSub =>
      _t("You're all set 🎉", 'Всё настроено 🎉', 'Усе налаштовано 🎉');
  String get nameExists =>
      _t('Name already exists', 'Название уже занято', 'Назва вже зайнята');
}
