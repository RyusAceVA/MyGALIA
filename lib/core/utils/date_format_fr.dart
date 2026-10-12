/// Formatage de dates en français, sans dépendance externe.
abstract final class DateFormatFr {
  DateFormatFr._();

  static const List<String> _weekdays = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];

  static const List<String> _months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  static const List<String> _weekdaysShort = [
    'Lun',
    'Mar',
    'Mer',
    'Jeu',
    'Ven',
    'Sam',
    'Dim',
  ];

  static const List<String> _monthsShort = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// « Lun »
  static String weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];

  /// « mardi 13 octobre »
  static String dayInline(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  /// « 5 août 2026 »
  static String dateLong(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// Semaine du lundi au vendredi : « 12 – 16 oct. 2026 »,
  /// « 29 sept. – 3 oct. 2026 », « 29 déc. 2025 – 2 janv. 2026 ».
  static String weekRangeShort(DateTime monday) {
    final DateTime friday = DateTime(monday.year, monday.month, monday.day + 4);
    final String end = '${friday.day} ${_monthsShort[friday.month - 1]} ${friday.year}';
    if (monday.year != friday.year) {
      return '${monday.day} ${_monthsShort[monday.month - 1]} ${monday.year} – $end';
    }
    if (monday.month != friday.month) {
      return '${monday.day} ${_monthsShort[monday.month - 1]} – $end';
    }
    return '${monday.day} – $end';
  }

  /// Durée courte : « 25 min », « 1 h 05 », « 3 h ».
  static String duration(Duration d) {
    final int minutes = d.inMinutes < 1 ? 1 : d.inMinutes;
    if (minutes < 60) return '$minutes min';
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0 ? '$hours h' : '$hours h ${_two(rest)}';
  }

  /// « 08:30 »
  static String time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  /// « 19/09/2025 »
  static String date(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  /// « Lundi 13 octobre »
  static String dayLong(DateTime d) {
    final String weekday = _weekdays[d.weekday - 1];
    return '${weekday[0].toUpperCase()}${weekday.substring(1)} '
        '${d.day} ${_months[d.month - 1]}';
  }

  /// « Mis à jour aujourd'hui à 19:30 », « … hier à … », « … le 12/10/2026 à … »
  static String updatedAt(DateTime at, DateTime now) {
    final DateTime local = at.toLocal();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(local.year, local.month, local.day);
    if (day == today) return 'Mis à jour aujourd\'hui à ${time(local)}';
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'Mis à jour hier à ${time(local)}';
    }
    return 'Mis à jour le ${date(local)} à ${time(local)}';
  }
}
