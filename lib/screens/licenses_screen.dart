import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../oss_licenses.dart';

class OpenSourceLicensesScreen extends StatefulWidget {
  const OpenSourceLicensesScreen({super.key});

  @override
  State<OpenSourceLicensesScreen> createState() => _OpenSourceLicensesScreenState();
}

class _OpenSourceLicensesScreenState extends State<OpenSourceLicensesScreen> {
  String? _rustLicenses;

  @override
  void initState() {
    super.initState();
    _loadRustLicenses();
  }

  Future<void> _loadRustLicenses() async {
    final text = await rootBundle.loadString('lib/oss_licenses_rust.txt');
    setState(() {
      _rustLicenses = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Source Licenses'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Flutter dependencies
          ...allDependencies.map((package) => Card(
                margin: const EdgeInsets.only(bottom: 16.0),
                child: ExpansionTile(
                  title: Text(
                    package.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Version: ${package.version}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (package.description != null) ...[
                            Text(
                              'Description:',
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              package.description!,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            'License:',
                            style: TextStyle(
                              color: Colors.grey[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              package.license ?? 'License not available',
                              style: const TextStyle(
                                fontSize: 14,
                                fontFamily: 'monospace',
                                height: 1.5,
                              ),
                            ),
                          ),
                          if (package.homepage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Homepage:',
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              package.homepage!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          // Rust licenses
          if (_rustLicenses != null)
            Card(
              margin: const EdgeInsets.only(bottom: 16.0),
              child: ExpansionTile(
                title: const Text(
                  'Rust Open Source Licenses',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _rustLicenses!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
} 