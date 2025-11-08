import 'package:flutter/material.dart';
import 'licenses_screen.dart';


//In case it's needed in the future:
//  𝗪𝗵𝗮𝘁 𝘁𝗵𝗶𝘀 𝗮𝗽𝗽 𝗶𝘀 𝗡𝗼𝘁:  
//This isn't a RAG (Retrieval-augmented generation) application. While it integrates neural networks, it doesn't automatically generate answers. Instead, it attempts to understand your query and locate relevant sections in PDFs. The drawback is that you must assess if the provided information fits your needs—much like sorting through Google search results. The advantage is that there's no risk of a generative AI misinterpreting the original content due to hardware constraints.
//
class FAQScreen extends StatelessWidget {
  const FAQScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAQ / INFO / SUPPORT'),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            FAQItem(
              question: 'What is this App?',
              answer: '''
• An offline semantic search engine that enables you to search a local database of PDFs and HTML files as you would with Google search, retrieving results by detecting the portions of the documents that may contain the answer.

• It uses semantic search (or meaning-based search) by default—a sophisticated approach that grasps the intent behind your query instead of relying solely on keyword matching. This is the type of technology behind most popular search engines.

• The App essentially brings a mini internet to your pocket by integrating an internal database, neural network inference, vector-based search, and other components on-device, allowing it to work without an internet connection.
              ''',
            ),
            FAQItem(
              question: 'Who is it for?',
              answer: '''
This offline search engine covers two main use cases:

• Writers, Researchers, Students, journalists:
  It enables users to perform searches within their locally curated knowledge base without uploading their documents to the cloud or registering for an external service. Everything runs on-device.

• Offline:
  Hikers, mountaineers, off-roaders, preppers and hobbyists who might need information when there's no internet. Pre-equipped with a variety of offline resources, including car manuals and survival guides, the app makes it possible to locate answers as you would with a search engine, even in situations where there's no internet.


              ''',
            ),
            FAQItem(
              question: 'Is my data private?',
              answer: '''
Yes!

• This application runs entirely offline, all the processing is done on your device.

• No Data Collection & Zero External Communication:
  None of this App's data ever leaves your device. The App does not send anything externally and requires no internet connection (except for the initial download of the pre-populated database, which is optional).
              ''',
            ),
            FAQItem(
              question: 'Semantic Search, Syntactic Search, Hybrid Search, what does it all mean?',
              answer: '''
• Semantic (meaning-based) search, which this app uses by default, understands the meaning behind your query. For example:
  Search query: 𝘄𝗵𝗲𝗿𝗲 𝘁𝗼 𝗳𝗶𝗻𝗱 𝘄𝗮𝘁𝗲𝗿 𝗶𝗻 𝘁𝗵𝗲 𝘄𝗶𝗹𝗱
  ➜ It will try to find the best matches related to the concept of locating water in the wild, even if the exact words don't match
  ➜ The app understands the meaning of your query and finds relevant information even if it uses different words to express the same concept

• Syntactic (exact match) search looks for specific words or phrases. You can do this by putting words in quotes. For example:
  Search query: \"𝗿𝗲𝗲𝗳 𝗸𝗻𝗼𝘁\"
  ➜ Will only find sections that contain those exact words together
  ➜ If many results are found, tries to select most useful ones

• Hybrid Search combines both approaches:
  Search query: \"𝗳𝗶𝗹𝘁𝗲𝗿\" 𝘄𝗮𝘁𝗲𝗿 𝗽𝘂𝗿𝗶𝗳𝗶𝗰𝗮𝘁𝗶𝗼𝗻
  ➜ Will semantically search for filter water purification but require the exact word "filter" to appear in the results
  ➜ This is useful when you want to ensure specific terms appear while still getting semantically relevant results

The app defaults to semantic search for natural language queries, but you can use quotes to require exact matches when needed.''',
            ),
            FAQItem(
              question: 'Is there an upper limit to how much data I can add?',
              answer: '''
Yes, there are two main limitations:

• Individual file size: While there's no hard limit, we recommend files under 20MB for PDFs and HTML files. The bigger the file, the longer it will take to open it for viewing.

• Total database size: There is currently a hard-coded 15GB database size limit, which is typically enough to index thousands of documents (PDFs and HTML files).

Most users never reach these limits in practical use.
              ''',
            ),
            SizedBox(height: 32),
            Text(
              'Support Information',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            SupportInfo(),
            SizedBox(height: 32),
            Text(
              'Legal',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            LicensesButton(),
          ],
        ),
      ),
    );
  }
}

class FAQItem extends StatelessWidget {
  final String question;
  final String answer;

  const FAQItem({
    super.key,
    required this.question,
    required this.answer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C3E50),
          ),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Text(
              answer,
              style: const TextStyle(
                fontSize: 16,
                height: 1.6,
                color: Color(0xFF34495E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SupportInfo extends StatelessWidget {
  const SupportInfo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoRow(
            icon: Icons.email_outlined,
            label: 'Support Email',
            value: 'pocketse.contact@gmail.com',
          ),
          SizedBox(height: 12),
          InfoRow(
            icon: Icons.language_outlined,
            label: 'Website',
            value: 'pocketsearchengine.com',
          ),
          SizedBox(height: 12),
          InfoRow(
            icon: Icons.info_outline,
            label: 'Version',
            value: '1.1.1',
          ),
          SizedBox(height: 12),
          InfoRow(
            icon: Icons.build_outlined,
            label: 'Build',
            value: '2025.03',
          ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class LicensesButton extends StatelessWidget {
  const LicensesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: const Text('Open Source Licenses'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const OpenSourceLicensesScreen(),
            ),
          );
        },
      ),
    );
  }
} 