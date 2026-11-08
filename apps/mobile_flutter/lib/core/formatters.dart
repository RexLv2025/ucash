import 'package:intl/intl.dart';

String money(num cents, {bool symbol = false, bool decimals = true}) {
  final v = cents / 100;
  final f = NumberFormat(decimals ? '#,##0.00' : '#,##0', 'zh_CN');
  return '${symbol ? '¥' : ''}${f.format(v)}';
}

String moneyShort(num cents) {
  final yuan = cents / 100;
  if (yuan >= 10000) {
    final w = yuan / 10000;
    return w == w.roundToDouble() ? '${w.toStringAsFixed(0)}万' : '${w.toStringAsFixed(1)}万';
  }
  return NumberFormat('#,##0', 'zh_CN').format(yuan);
}

String rate(num bp, {int digits = 2}) => (bp / 100).toStringAsFixed(digits);

String dateShort(String? iso) {
  if (iso == null || iso.isEmpty) return '--';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso.length >= 10 ? iso.substring(0, 10) : iso;
  return DateFormat('yyyy-MM-dd').format(d.toLocal());
}

String dateTimeShort(String? iso) {
  if (iso == null || iso.isEmpty) return '--';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return DateFormat('yyyy-MM-dd HH:mm').format(d.toLocal());
}

String maskPhoneLocal(String phone) {
  if (phone.length < 7) return phone;
  return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
}

int daysBetween(String from, String to) {
  final a = DateTime.tryParse(from);
  final b = DateTime.tryParse(to);
  if (a == null || b == null) return 0;
  return b.difference(a).inDays;
}

String statusText(String status) {
  switch (status) {
    case 'reviewing':
      return '审核中';
    case 'disbursing':
      return '放款中';
    case 'active':
      return '还款中';
    case 'overdue':
      return '已逾期';
    case 'settled':
      return '已结清';
    case 'rejected':
      return '未通过';
    case 'failed':
      return '放款失败';
    case 'unpaid':
      return '待还款';
    case 'paid':
      return '已还清';
    case 'partial':
      return '部分还款';
    case 'approved':
      return '已激活';
    case 'manual':
      return '人工审核中';
    case 'none':
    case 'expired':
      return '待申请';
    default:
      return status;
  }
}
