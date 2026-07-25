import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';

class SshTerminalSurface extends StatelessWidget {
  const SshTerminalSurface({
    super.key,
    required this.terminal,
    required this.focusNode,
    required this.onSend,
  });

  final Terminal terminal;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;

  static const _theme = TerminalTheme(
    cursor: Color(0xFFB7D5FF),
    selection: Color(0x663A78D8),
    foreground: Color(0xFFDCE6F5),
    background: Color(0xFF101419),
    black: Color(0xFF11151B),
    red: Color(0xFFFF6B72),
    green: Color(0xFF5BD89A),
    yellow: Color(0xFFFFD866),
    blue: Color(0xFF65A8FF),
    magenta: Color(0xFFC99CFF),
    cyan: Color(0xFF55D6E8),
    white: Color(0xFFDCE6F5),
    brightBlack: Color(0xFF7E8998),
    brightRed: Color(0xFFFF8790),
    brightGreen: Color(0xFF79E7AE),
    brightYellow: Color(0xFFFFE38C),
    brightBlue: Color(0xFF8FC1FF),
    brightMagenta: Color(0xFFDDBDFF),
    brightCyan: Color(0xFF82E9F5),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFD866),
    searchHitBackgroundCurrent: Color(0xFF5BD89A),
    searchHitForeground: Color(0xFF101419),
  );

  @override
  Widget build(BuildContext context) {
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return ColoredBox(
      color: _theme.background,
      child: Column(
        children: [
          _TerminalToolbar(focusNode: focusNode),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: focusNode.requestFocus,
              child: TerminalView(
                terminal,
                focusNode: focusNode,
                autofocus: true,
                hardwareKeyboardOnly: desktop,
                alwaysShowCursor: true,
                cursorType: TerminalCursorType.block,
                theme: _theme,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                textStyle: TerminalStyle(
                  fontSize: desktop ? 14.5 : 13.5,
                  height: 1.25,
                  fontFamily: Platform.isWindows
                      ? 'Cascadia Mono'
                      : 'monospace',
                  fontFamilyFallback: const [
                    'Cascadia Code',
                    'Consolas',
                    'JetBrains Mono',
                    'Noto Sans Mono CJK SC',
                    'NetToolsCJK',
                    'monospace',
                  ],
                ),
                onTapUp: (_, _) => focusNode.requestFocus(),
              ),
            ),
          ),
          _QuickKeyBar(onSend: onSend, onRefocus: focusNode.requestFocus),
        ],
      ),
    );
  }
}

class _TerminalToolbar extends StatelessWidget {
  const _TerminalToolbar({required this.focusNode});

  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: Color(0xFF171C23),
      border: Border(bottom: BorderSide(color: Color(0xFF29313D))),
    ),
    child: Row(
      children: [
        const Icon(Icons.terminal_rounded, size: 16, color: Color(0xFF8FC1FF)),
        const SizedBox(width: 8),
        const Text(
          'xterm-256color',
          style: TextStyle(
            color: Color(0xFFB5C0CF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        ListenableBuilder(
          listenable: focusNode,
          builder: (context, _) => Row(
            children: [
              Icon(
                focusNode.hasFocus
                    ? Icons.keyboard_rounded
                    : Icons.mouse_rounded,
                size: 15,
                color: focusNode.hasFocus
                    ? const Color(0xFF5BD89A)
                    : const Color(0xFF7E8998),
              ),
              const SizedBox(width: 5),
              LocalizedText(
                focusNode.hasFocus ? '可输入' : '点击终端后输入',
                style: TextStyle(
                  color: focusNode.hasFocus
                      ? const Color(0xFF8DDDB5)
                      : const Color(0xFF909BAA),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _QuickKeyBar extends StatelessWidget {
  const _QuickKeyBar({required this.onSend, required this.onRefocus});

  final ValueChanged<String> onSend;
  final VoidCallback onRefocus;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      color: const Color(0xFF171C23),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final key in const [
              ('Esc', '\x1b'),
              ('Tab', '\t'),
              ('Ctrl+C', '\x03'),
              ('Ctrl+D', '\x04'),
              ('↑', '\x1b[A'),
              ('↓', '\x1b[B'),
              ('←', '\x1b[D'),
              ('→', '\x1b[C'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC6D2E2),
                    side: const BorderSide(color: Color(0xFF3A4554)),
                    minimumSize: const Size(48, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () {
                    onSend(key.$2);
                    onRefocus();
                  },
                  child: Text(key.$1),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
