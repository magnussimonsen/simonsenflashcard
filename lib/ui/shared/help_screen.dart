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
      body: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: keyConcepts.length,
        separatorBuilder: (_, _) => const Divider(height: 32),
        itemBuilder: (_, i) {
          final concept = keyConcepts[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                concept.term,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(concept.definition),
            ],
          );
        },
      ),
    );
  }
}
