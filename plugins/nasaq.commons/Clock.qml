pragma Singleton
import QtQuick
import Quickshell

// One way to write dates and times on every NASAQ surface (island, desktop
// cards, notification centre; the lock screen uses the same order in its own
// file, since it imports no sibling plugin). Day and month names follow the
// interface language; digits stay Western in both.
Singleton {
  id: root
  readonly property bool arabic: Tr.language === "ar"
  readonly property var names: Qt.locale(arabic ? "ar_SA" : "en_US")
  readonly property var en: Qt.locale("en_US")

  function weekday(d) { return names.dayName(d.getDay() === 0 ? 7 : d.getDay(), Locale.LongFormat) }
  function month(d) { return names.monthName(d.getMonth(), Locale.LongFormat) }   // QML Locale months are 0-based (days are 1-7)
  function monthShort(d) { return names.monthName(d.getMonth(), Locale.ShortFormat) }
  // "Saturday, 17 October" / "السبت، 17 أكتوبر"
  function dateLong(d) { return weekday(d) + (arabic ? "، " : ", ") + d.getDate() + " " + month(d) }
  // "17 October"
  function dayMonth(d) { return d.getDate() + " " + month(d) }
  // "17 Oct"
  function dateShort(d) { return d.getDate() + " " + monthShort(d) }
  // "October 2026"
  function monthYear(d) { return month(d) + " " + d.getFullYear() }
  // "1:33" (12-hour, no AM/PM: the shell's clocks never show it)
  function time(d) { return en.toString(d, "h:mm") }
  // "11:40 PM" where the half matters (events, file dates)
  function timeAP(d) { return en.toString(d, "h:mm AP") }
  // Hijri from the prayer-times data: "25 ربيع الآخر 1448 هـ"
  function hijri(h) { return h ? h.day + " " + h.month + " " + h.year + " هـ" : "" }
}
