import 'package:flutter/material.dart';
import '../../backend/constants.dart';

/// Shows the About dialog for Simonsen Flashcard.
void showAboutAppDialog(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: 'Simonsen Flashcard',
    applicationVersion: '1.0.0',
    applicationIcon: Image.asset(
      'lib/logo/logo.png',
      width: 48,
      height: 48,
      filterQuality: FilterQuality.high,
    ),
    children: [
      const Text(appTitle),
      const SizedBox(height: 16),
      const Text('Authors', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      const Text('Magnus Simonsen\nClaude Sonnet (AI assistant)'),
      const SizedBox(height: 16),
      const Text('License', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      const Text(
        'MIT License\n\n'
        'Copyright © 2026 Magnus Simonsen\n\n'
        'Permission is hereby granted, free of charge, to any person obtaining '
        'a copy of this software and associated documentation files (the '
        '"Software"), to deal in the Software without restriction, including '
        'without limitation the rights to use, copy, modify, merge, publish, '
        'distribute, sublicense, and/or sell copies of the Software, and to '
        'permit persons to whom the Software is furnished to do so, subject to '
        'the following conditions:\n\n'
        'The above copyright notice and this permission notice shall be '
        'included in all copies or substantial portions of the Software.\n\n'
        'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, '
        'EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF '
        'MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND '
        'NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS '
        'BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN '
        'ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN '
        'CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE '
        'SOFTWARE.',
      ),
    ],
  );
}
