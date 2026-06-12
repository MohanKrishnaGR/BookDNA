import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _inNumber = NumberFormat.decimalPattern('en_IN');

/// `186000` → `₹1,86,000` (Indian lakh grouping).
String formatInr(num value) => _inr.format(value);

/// `81340` → `81,340` (en-IN grouping).
String formatNumber(num value) => _inNumber.format(value);

String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// `DateTime` → "2h ago", "Yesterday", "3 days ago", "12 May".
String relativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return DateFormat('d MMM').format(time);
}

String fullDate(DateTime time) => DateFormat('EEEE, d MMMM').format(time);
