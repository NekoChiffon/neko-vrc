/// 应用级常量。
///
/// VRChat 官方要求第三方应用必须通过 User-Agent 表明身份，格式为
/// `应用名/版本 联系方式`，不规范的 User-Agent 会被 moderation。
/// 上线前请把 [contactInfo] 换成你自己的邮箱或主页。
library;

class AppInfo {
  const AppInfo._();

  static const String applicationName = 'NekoVRC';
  static const String version = '0.45.2';

  /// 联系方式：建议填邮箱或你的域名，方便 VRChat 团队在必要时联系你。
  static const String contactInfo = 'ChiffonNya@126.com';

  static const String displayName = 'Neko VRC';
}
