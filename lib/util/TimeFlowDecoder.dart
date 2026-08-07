/// Cloudreve V4 混淆缩略图 URL 解码器（时间流混淆算法）
///
/// `GET /file/thumb` 在 `obfuscated: true` 时返回经过时间混淆的 URL，
/// 需按官方文档给出的算法解码出真实图片地址。
class TimeFlowDecoder {
  /// 解码混淆字符串，失败返回 null。
  /// 服务器生成时间与本地时钟存在 ±1s 偏差时依次尝试修正。
  static String? decode(String str, {int? nowMillis}) {
    if (str.isEmpty) return null;
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    for (final t in [now, now - 1000, now + 1000]) {
      try {
        final r = _decodeAt(str, t);
        if (r != null && r.isNotEmpty) return r;
      } catch (_) {}
    }
    return null;
  }

  static String? _decodeAt(String str, int timeNowMillis) {
    final timeNow = timeNowMillis ~/ 1000;
    final timeNowBackup = timeNow;

    // 拆出当前时间的每一位数字
    final timeDigits = <int>[];
    if (timeNow == 0) {
      timeDigits.add(0);
    } else {
      var t = timeNow;
      while (t > 0) {
        timeDigits.add(t % 10);
        t ~/= 10;
      }
    }

    final res = str.split('');
    final secret = List<String>.from(res);
    var add = secret.length % 2 == 0;
    var timeDigitIndex = (secret.length - 1) % timeDigits.length;
    final l = secret.length;

    for (var pos = 0; pos < l; pos++) {
      final targetIndex = l - 1 - pos;
      var newIndex = targetIndex;
      if (add) {
        newIndex += timeDigits[timeDigitIndex] * timeDigitIndex;
      } else {
        newIndex = 2 * timeDigitIndex * timeDigits[timeDigitIndex] - newIndex;
      }
      if (newIndex < 0) newIndex = -newIndex;
      newIndex %= secret.length;

      res[targetIndex] = secret[newIndex];

      // 与末尾字符交换后移除末尾，缩小 secret 长度
      final lastIndex = secret.length - 1;
      final a = secret[newIndex];
      final b = secret[lastIndex];
      secret[newIndex] = b;
      secret[lastIndex] = a;
      secret.removeLast();

      add = !add;
      timeDigitIndex--;
      if (timeDigitIndex < 0) timeDigitIndex = timeDigits.length - 1;
    }

    final resStr = res.join();
    final sep = resStr.indexOf('|');
    if (sep < 0) return null;
    // 头部应为时间戳，校验失败说明使用的基准时间不对
    if (resStr.substring(0, sep) != timeNowBackup.toString()) return null;
    return resStr.substring(sep + 1);
  }
}
