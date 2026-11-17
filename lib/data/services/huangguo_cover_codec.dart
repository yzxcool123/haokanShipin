import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 黄果封面是 AES-CBC 加密的原始二进制，密钥和 IV 按 UTF-8 字节使用（不是十六进制解码）。
class HuangguoCoverCodec {
  static const keyText = 'f5d965df75336270';
  static const ivText = '97b60394abc2fbe1';

  static final _key = Uint8List.fromList(utf8.encode(keyText));
  static final _iv = Uint8List.fromList(utf8.encode(ivText));

  static bool isImage(Uint8List bytes) => mimeOf(bytes) != null;

  static String? mimeOf(Uint8List bytes) {
    if (bytes.length < 3) return null;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
    if (bytes.length >= 3 && bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78) {
      return 'image/png';
    }
    if (bytes[0] == 82 && bytes[1] == 73) return 'image/webp';
    if (bytes[0] == 71 && bytes[1] == 73) return 'image/gif';
    return null;
  }

  /// 先按 PKCS7 解密；WebCrypto 已去垫后，官方还会再剥一层看起来像 PKCS7 的尾部。
  static Uint8List? decrypt(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length % 16 != 0) return null;
    try {
      final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
      cipher.init(
        false,
        PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(_key), _iv), null),
      );
      var plain = cipher.process(bytes);
      plain = _maybeUnpad(plain);
      return plain;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _maybeUnpad(Uint8List data) {
    if (data.isEmpty) return data;
    final n = data[data.length - 1];
    if (n <= 0 || n > 16 || n > data.length) return data;
    for (var i = 0; i < n; i++) {
      if (data[data.length - 1 - i] != n) return data;
    }
    return Uint8List.sublistView(data, 0, data.length - n);
  }
}
