import 'package:flutter/material.dart';

import '../widgets.dart';

class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        GradientHeader(title: 'Calls'),
        Expanded(
          child: EmptyState(
            icon: Icons.call_outlined,
            title: 'No calls yet',
            subtitle: 'Your call history will appear here.',
          ),
        ),
      ],
    );
  }
}