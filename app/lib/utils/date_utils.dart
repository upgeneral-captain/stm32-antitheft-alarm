import 'package:intl/intl.dart';

/// 日期时间工具：统一格式，避免各页面各写一套
class DateUtilsX {
  DateUtilsX._();

  static final DateFormat _ymd = DateFormat('yyyy-MM-dd');
  static final DateFormat _hms = DateFormat('HH:mm:ss');
  static final DateFormat _ymdHms = DateFormat('yyyy-MM-dd HH:mm:ss');

  static String ymd(DateTime t) => _ymd.format(t);
  static String hms(DateTime t) => _hms.format(t);
  static String full(DateTime t) => _ymdHms.format(t);
}
