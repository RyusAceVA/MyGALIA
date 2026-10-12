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

  static String _two(int n) => n.toString().padLeft(2, '0');

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

  /// « du 13 au 17 octobre », « du 29 septembre au 3 octobre »
  static String weekRange(DateTime monday) {
    final DateTime friday = DateTime(monday.year, monday.month, monday.day + 4);
    if (monday.month == friday.month) {
      return 'du ${monday.day} au ${friday.day} ${_months[friday.month - 1]}';
    }
    return 'du ${monday.day} ${_months[monday.month - 1]} '
        'au ${friday.day} ${_months[friday.month - 1]}';
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
