import 'package:intl/intl.dart';

/// Converts UTC timestamps to Asia/Kolkata (IST, UTC+05:30) for display.
class IstFormatter {
  const IstFormatter._();

  static const Duration _istOffset = Duration(hours: 5, minutes: 30);

  static DateTime toIst(DateTime utcTime) => utcTime.toUtc().add(_istOffset);

  static String formatDateTime(DateTime utcTime) {
    final ist = toIst(utcTime);
    return '${DateFormat('dd MMM yyyy • HH:mm').format(ist)} IST';
  }

  static String formatShortTime(DateTime utcTime) {
    final ist = toIst(utcTime);
    return '${DateFormat('dd MMM • HH:mm').format(ist)} IST';
  }

  static String formatDateOnly(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  static String formatExpiryCountdown(DateTime expiresAtUtc, {DateTime? now}) {
    final ref = (now ?? DateTime.now()).toUtc();
    final diff = expiresAtUtc.toUtc().difference(ref);
    if (diff.isNegative) return 'Expired';
    if (diff.inHours >= 1) return 'Expires in ${diff.inHours}h';
    return 'Expires in ${diff.inMinutes}m';
  }
}
