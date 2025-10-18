import 'package:flutter/material.dart';

class PageInputDialog extends StatelessWidget {
  final int pageCount;

  const PageInputDialog({Key? key, required this.pageCount}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = TextEditingController();

    return AlertDialog(
      title: const Text('Go to Page'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: 'Enter page number (1-$pageCount)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final page = int.tryParse(controller.text);
            if (page != null && page > 0 && page <= pageCount) {
              Navigator.of(context).pop(page);
            }
          },
          child: const Text('Go'),
        ),
      ],
    );
  }
} 