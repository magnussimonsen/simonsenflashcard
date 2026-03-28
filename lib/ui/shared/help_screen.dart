import 'package:flutter/material.dart';
import '../../backend/constants.dart';

/// Full-screen help page listing key app concepts.
/// Navigate to it with [Navigator.push]; the AppBar provides a back arrow.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How does Simonsen Flashcard work?')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Key concepts ─────────────────────────────────────────────────
          for (var i = 0; i < keyConcepts.length; i++) ...[
            if (i > 0) const Divider(height: 32),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  keyConcepts[i].term,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(keyConcepts[i].definition),
              ],
            ),
          ],

          // ── Leitner schedule table ────────────────────────────────────
          const Divider(height: 32),
          Text(
            'Leitner Box schedule',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Table(
            border: TableBorder.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(6),
            ),
            columnWidths: const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(2.5),
              2: FlexColumnWidth(2),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                children: const [
                  _TableCell('Box', isHeader: true),
                  _TableCell('Reviewed', isHeader: true),
                  _TableCell('Session numbers', isHeader: true),
                ],
              ),
              const TableRow(
                children: [
                  _TableCell('1'),
                  _TableCell('Every session'),
                  _TableCell('1, 2, 3, 4 …'),
                ],
              ),
              const TableRow(
                children: [
                  _TableCell('2'),
                  _TableCell('Every 2nd session'),
                  _TableCell('2, 4, 6, 8 …'),
                ],
              ),
              const TableRow(
                children: [
                  _TableCell('3'),
                  _TableCell('Every 4th session'),
                  _TableCell('4, 8, 12, 16 …'),
                ],
              ),
              const TableRow(
                children: [
                  _TableCell('4'),
                  _TableCell('Every 8th session'),
                  _TableCell('8, 16, 24 …'),
                ],
              ),
              const TableRow(
                children: [
                  _TableCell('5'),
                  _TableCell('Every 16th session'),
                  _TableCell('16, 32, 48 …'),
                ],
              ),
            ],
          ),

          // ── Rating → box movement ────────────────────────────────────
          const Divider(height: 32),
          Text(
            'How ratings move cards between boxes',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'After you flip a card in Leitner mode, you rate how well you remembered it. '
            'The rating moves the card to a different box:\n\n'
            'Again: you did not remember. The card goes back to Box 1 and will appear every session until you get it right.\n\n'
            'Hard: you remembered, but it was a struggle. The card also goes back to Box 1.\n\n'
            'Good: you remembered with normal effort. The card moves up one box, so it will be reviewed less often.\n\n'
            'Easy: you remembered instantly. The card jumps up two boxes, fast-tracking it to a less frequent review slot.',
          ),

          // ── Keyboard shortcuts ────────────────────────────────────────
          const Divider(height: 32),
          Text(
            'Keyboard shortcuts (desktop)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Table(
            border: TableBorder.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(6),
            ),
            columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(3)},
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                children: const [
                  _TableCell('Key', isHeader: true),
                  _TableCell('Action', isHeader: true),
                ],
              ),
              const TableRow(
                children: [_TableCell('Space'), _TableCell('Flip card')],
              ),
              const TableRow(
                children: [_TableCell('1'), _TableCell('Rate: Again')],
              ),
              const TableRow(
                children: [_TableCell('2'), _TableCell('Rate: Hard')],
              ),
              const TableRow(
                children: [_TableCell('3'), _TableCell('Rate: Good')],
              ),
              const TableRow(
                children: [_TableCell('4'), _TableCell('Rate: Easy')],
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final bool isHeader;

  const _TableCell(this.text, {this.isHeader = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text,
        style: isHeader
            ? Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
            : Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
