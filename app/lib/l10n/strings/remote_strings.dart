class RemoteStrings {
  const RemoteStrings({required this.isEnglish});

  final bool isEnglish;

  String get title => isEnglish ? 'Remote connections' : '远程连接';
  String get subtitle =>
      isEnglish ? 'Save once, then connect in one tap' : '保存一次，之后一键进入设备';
  String get transferCenter => isEnglish ? 'Transfer center' : '传输中心';
  String get newConnection => isEnglish ? 'New remote connection' : '新建远程连接';
  String get savedConnections => isEnglish ? 'Saved connections' : '已保存连接';
  String get emptyTitle =>
      isEnglish ? 'Connect to a router or server' : '连接路由器或服务器';
  String get emptyBody => isEnglish
      ? 'Open a terminal and remote files over SSH, or browse an SMB2 / SMB3 file share.'
      : '通过 SSH 打开终端和远程文件，或浏览 SMB2 / SMB3 文件共享。';
  String get newSsh => isEnglish ? 'New SSH' : '新建 SSH';
  String get newSmb => isEnglish ? 'New SMB' : '新建 SMB';
  String get privateKeyAuth => isEnglish ? 'Private key' : '私钥认证';
  String get passwordAuth => isEnglish ? 'Password' : '密码认证';
  String get connectNow => isEnglish ? 'Connect now' : '立即连接';
  String get sshTunnel => isEnglish ? 'SSH tunnel' : 'SSH 隧道';
  String get editProfile => isEnglish ? 'Edit profile' : '编辑配置';
  String get deleteBody => isEnglish
      ? 'The connection profile and its secure credentials will be removed from this device.'
      : '连接配置和对应的安全凭据将从本机删除。';

  String deleteTitle(String name) =>
      isEnglish ? 'Delete “$name”?' : '删除“$name”？';
}
