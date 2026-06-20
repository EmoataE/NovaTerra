import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final List<Map<String, dynamic>> clients = [];
  final TextEditingController searchController = TextEditingController();

  String searchQuery = '';
  String? _selectedLifeStage;

  @override
  void initState() {
    super.initState();
    fetchClients();
  }

  Future<void> fetchClients() async {
    final response = await http.get(Uri.parse('http://localhost:8000/clients'));

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);

      setState(() {
        clients.clear();
        clients.addAll(data.map((client) => Map<String, dynamic>.from(client)));
      });
    }
  }

  int _clientAge(Map<String, dynamic> client) {
    final bday = (client['birthday'] ?? '').toString();
    if (bday.isNotEmpty && bday != 'Not selected') {
      final parts = bday.split('/');
      if (parts.length == 3) {
        try {
          final year = int.parse(parts[2]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[0]);
          final dob = DateTime(year, month, day);
          final now = DateTime.now();
          int age = now.year - dob.year;
          if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
          return age;
        } catch (_) {}
      }
    }
    return int.tryParse((client['age'] ?? '').toString()) ?? 0;
  }

  String? _lifeStageOf(Map<String, dynamic> client) {
    final age = _clientAge(client);
    if (age >= 20 && age <= 29) return 'young_pro';
    if (age >= 30 && age <= 39) return 'family';
    if (age >= 40 && age <= 59) return 'mid_career';
    if (age >= 60) return 'retirement';
    return null;
  }

  List<Map<String, dynamic>> get filteredClients {
    return clients.where((client) {
      if (searchQuery.isNotEmpty) {
        final name = client['name'].toString().toLowerCase();
        final concern = client['concern'].toString().toLowerCase();
        final personality = client['personality'].toString().toLowerCase();
        final query = searchQuery.toLowerCase();
        if (!name.contains(query) && !concern.contains(query) && !personality.contains(query)) {
          return false;
        }
      }
      if (_selectedLifeStage != null) {
        return _lifeStageOf(client) == _selectedLifeStage;
      }
      return true;
    }).toList();
  }

  Widget _buildStageChip(String? stage, String label, IconData icon, Color color) {
    final selected = _selectedLifeStage == stage;
    return GestureDetector(
      onTap: () => setState(() => _selectedLifeStage = stage),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: selected ? color.withOpacity(0.28) : Colors.black.withOpacity(0.04),
              blurRadius: selected ? 10 : 4,
              offset: const Offset(0, 3),
            ),
          ],
          border: selected ? null : Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF374151),
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void openClientForm({Map<String, dynamic>? existingClient}) {
    final bool isEditing = existingClient != null;

    final nameController =
        TextEditingController(text: existingClient?['name'] ?? '');
     final phoneController =
        TextEditingController(text: existingClient?['phone'] ?? '');
    final ageController =
        TextEditingController(text: existingClient?['age'] ?? '');
    final childrenController =
        TextEditingController(text: existingClient?['children'] ?? '');
    final healthController =
        TextEditingController(text: existingClient?['health'] ?? '');
    final concernController =
        TextEditingController(text: existingClient?['concern'] ?? '');
    final personalityController =
        TextEditingController(text: existingClient?['personality'] ?? '');
    final riskController =
        TextEditingController(text: existingClient?['risk'] ?? '');

    String selectedBirthday = existingClient?['birthday'] ?? 'Not selected';
    String selectedSex = existingClient?['sex'] ?? 'Male';
    String selectedMarital = existingClient?['marital'] ?? 'Single';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F6FA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 45,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      isEditing ? 'Edit Client Profile' : 'Add Client Profile',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      isEditing
                          ? 'Update client memory and relationship information.'
                          : 'Create a new client memory profile.',
                      style: const TextStyle(color: Colors.grey),
                    ),

                    const SizedBox(height: 20),

                    buildTextField(nameController, 'Name'),
                    buildTextField(phoneController, 'Phone'),
                    buildTextField(ageController, 'Age'),

                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        title: Text('Birthday: $selectedBirthday'),
                        trailing: const Icon(Icons.calendar_month),
                        onTap: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime(1990),
                            firstDate: DateTime(1940),
                            lastDate: DateTime.now(),
                          );

                          if (pickedDate != null) {
                            modalSetState(() {
                              selectedBirthday =
                                  '${pickedDate.day}/${pickedDate.month}/${pickedDate.year}';
                            });
                          }
                        },
                      ),
                    ),

                    buildDropdown(
                      label: 'Sex',
                      value: selectedSex,
                      items: const ['Male', 'Female', 'Other'],
                      onChanged: (value) {
                        modalSetState(() {
                          selectedSex = value!;
                        });
                      },
                    ),

                    buildDropdown(
                      label: 'Marital Status',
                      value: selectedMarital,
                      items: const [
                        'Single',
                        'Married',
                        'Divorced',
                        'Widowed',
                      ],
                      onChanged: (value) {
                        modalSetState(() {
                          selectedMarital = value!;
                        });
                      },
                    ),

                    buildTextField(healthController, 'Health Condition'),
                    buildTextField(childrenController, 'Children'),
                    buildTextField(concernController, 'Major Concern'),
                    buildTextField(personalityController, 'Personality'),
                    buildTextField(riskController, 'Risk Level'),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        icon: Icon(isEditing ? Icons.save : Icons.add),
                        label: Text(isEditing ? 'Save Changes' : 'Save Client'),
                        onPressed: () async {
                          final clientData = {
                            'name': nameController.text,
                            'phone': phoneController.text,
                            'age': ageController.text,
                            'birthday': selectedBirthday,
                            'sex': selectedSex,
                            'marital': selectedMarital,
                            'health': healthController.text,
                            'children': childrenController.text,
                            'concern': concernController.text,
                            'personality': personalityController.text,
                            'risk': riskController.text,
                          };

                          http.Response response;

                          if (isEditing) {
                            response = await http.put(
                              Uri.parse(
                                'http://localhost:8000/clients/${existingClient['id']}',
                              ),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode(clientData),
                            );
                          } else {
                            response = await http.post(
                              Uri.parse('http://localhost:8000/clients'),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode(clientData),
                            );
                          }

                          if (response.statusCode == 200) {
                            await fetchClients();
                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to save client'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        items: items.map((item) {
          return DropdownMenuItem(value: item, child: Text(item));
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shownClients = filteredClients;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Clients',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => openClientForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),

          const SizedBox(height: 6),

          const Text(
            'Search, edit and manage client memory profiles.',
            style: TextStyle(color: Colors.grey),
          ),

          const SizedBox(height: 18),

          TextField(
            controller: searchController,
            onChanged: (value) {
              setState(() {
                searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search client by name, concern or personality...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Life stage filter
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildStageChip(null, 'All\nClients', Icons.people_outline, const Color(0xFF4F46E5)),
                _buildStageChip('young_pro', 'Young Pro\n(20s)', Icons.trending_up_outlined, const Color(0xFF0EA5E9)),
                _buildStageChip('family', 'Family\n(30s)', Icons.family_restroom, const Color(0xFF10B981)),
                _buildStageChip('mid_career', 'Mid Career\n(40–50s)', Icons.work_outline, const Color(0xFFF59E0B)),
                _buildStageChip('retirement', 'Retirement\n(60+)', Icons.self_improvement, const Color(0xFF8B5CF6)),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Filter count label
          if (_selectedLifeStage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${shownClients.length} client${shownClients.length == 1 ? '' : 's'} in this segment',
                style: const TextStyle(color: Color(0xFF4F46E5), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),

          const SizedBox(height: 6),

          if (shownClients.isEmpty)
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 60,
                    color: Color(0xFF4F46E5),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No Clients Found',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Add a client or try another search keyword.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          else
            for (final client in shownClients)
              ClientProfileCard(
                client: client,
                onEdit: () => openClientForm(existingClient: client),
              ),
        ],
      ),
    );
  }
}

class ClientProfileCard extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onEdit;

  const ClientProfileCard({
    super.key,
    required this.client,
    required this.onEdit,
  });

  void openFullText(BuildContext context, String title, String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(text.isEmpty ? 'No content available.' : text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget longTextBlock(
    BuildContext context, {
    required String title,
    required String text,
    int maxLines = 3,
  }) {
    final safeText = text.trim().isEmpty ? 'No content available.' : text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          safeText,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openFullText(context, title, safeText),
            icon: const Icon(Icons.open_in_full, size: 16),
            label: const Text('View full text'),
          ),
        ),
      ],
    );
  }

  Future<void> _downloadPdf(BuildContext context, int clientId, String clientName) async {
    final uri = Uri.parse('http://localhost:8000/clients/$clientId/report-pdf');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open PDF')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void openAIMemory(BuildContext context) {
    final memories = client['memories'] ?? [];
    final opportunities = client['opportunities'] ?? [];
    final suggestedPolicies = client['suggested_policies'] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F6FA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 45,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    '${client['name']} AI Memory',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Relationship Score: ${client['relationship_score'] ?? 'N/A'}',
                    style: const TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 18),

                  // Financial Coverage section
                  _CoverageSection(clientId: client['id']),

                  const SizedBox(height: 4),

                  // Export PDF button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _downloadPdf(context, client['id'], client['name']),
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('Export Client Report PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  AIMemorySection(
                    title: 'Latest Meeting Summary',
                    icon: Icons.summarize,
                    child: longTextBlock(
                      context,
                      title: 'Latest Meeting Summary',
                      text: (client['latest_summary'] ?? '').toString().isEmpty
                          ? 'No meeting summary yet.'
                          : client['latest_summary'].toString(),
                      maxLines: 4,
                    ),
                  ),

                  AIMemorySection(
                    title: 'Client Status',
                    icon: Icons.insights,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sentiment: ${client['latest_sentiment'] ?? 'N/A'}'),
                        Text(
                          'Interest Level: ${client['latest_interest_level'] ?? 'N/A'}',
                        ),
                      ],
                    ),
                  ),

                  AIMemorySection(
                    title: 'Meeting History',
                    icon: Icons.history,
                    child: FutureBuilder<http.Response>(
                      future: http.get(
                        Uri.parse(
                          'http://localhost:8000/meeting-updates/${client['id']}',
                        ),
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Text('Loading meeting history...');
                        }

                        if (snapshot.hasError || !snapshot.hasData) {
                          return const Text('Unable to load meeting history.');
                        }

                        final response = snapshot.data!;

                        if (response.statusCode != 200) {
                          return const Text('Unable to load meeting history.');
                        }

                        final List meetings = jsonDecode(response.body);

                        if (meetings.isEmpty) {
                          return const Text('No past meetings yet.');
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final meeting in meetings)
                              MeetingHistoryCard(
                                meeting: Map<String, dynamic>.from(meeting),
                                onViewFullText: (title, text) {
                                  openFullText(context, title, text);
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ),

                  AIMemorySection(
                    title: 'Client Memories',
                    icon: Icons.memory,
                    child: memories.isEmpty
                        ? const Text('No extracted memories yet.')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final memory in memories)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    '• ${memory['content']} '
                                    '(${memory['confidence']}% confidence)',
                                  ),
                                ),
                            ],
                          ),
                  ),

                  AIMemorySection(
                    title: 'AI Opportunities',
                    icon: Icons.lightbulb,
                    child: opportunities.isEmpty
                        ? const Text('No opportunities detected yet.')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final opp in opportunities)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: longTextBlock(
                                    context,
                                    title: opp['opportunity_type'] ?? 'Opportunity',
                                    text:
                                        '• ${opp['opportunity_type']}\n'
                                        'Reason: ${opp['reason']}\n'
                                        'Suggested action: ${opp['suggested_action']}',
                                    maxLines: 4,
                                  ),
                                ),
                            ],
                          ),
                  ),

                  AIMemorySection(
                    title: 'Suggested Policies',
                    icon: Icons.policy,
                    child: suggestedPolicies.isEmpty
                        ? const Text('No suggested policies yet.')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final policy in suggestedPolicies)
                                Text('• $policy'),
                            ],
                          ),
                  ),

                  AIMemorySection(
                    title: 'Follow-up Message',
                    icon: Icons.message,
                    child: longTextBlock(
                      context,
                      title: 'Follow-up Message',
                      text: (client['follow_up_message'] ?? '').toString().isEmpty
                          ? 'No follow-up message generated yet.'
                          : client['follow_up_message'].toString(),
                      maxLines: 4,
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static int _ageFrom(Map<String, dynamic> client) {
    final bday = (client['birthday'] ?? '').toString();
    if (bday.isNotEmpty && bday != 'Not selected') {
      final parts = bday.split('/');
      if (parts.length == 3) {
        try {
          final dob = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          final now = DateTime.now();
          int age = now.year - dob.year;
          if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
          return age;
        } catch (_) {}
      }
    }
    return int.tryParse((client['age'] ?? '').toString()) ?? 0;
  }

  static ({String label, Color bg, Color fg}) _stageInfo(Map<String, dynamic> client) {
    final age = _ageFrom(client);
    if (age >= 20 && age <= 29) return (label: 'Young Pro', bg: const Color(0xFFE0F2FE), fg: const Color(0xFF0369A1));
    if (age >= 30 && age <= 39) return (label: 'Family', bg: const Color(0xFFDCFCE7), fg: const Color(0xFF15803D));
    if (age >= 40 && age <= 59) return (label: 'Mid Career', bg: const Color(0xFFFEF3C7), fg: const Color(0xFFB45309));
    if (age >= 60) return (label: 'Retirement', bg: const Color(0xFFEDE9FE), fg: const Color(0xFF6D28D9));
    return (label: 'Other', bg: const Color(0xFFF3F4F6), fg: const Color(0xFF6B7280));
  }

  @override
  Widget build(BuildContext context) {
    final name = client['name'] ?? '';
    final concern = client['concern'] ?? '';
    final risk = client['risk'] ?? '';
    final stage = _stageInfo(client);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: stage.bg,
                child: Text(
                  name.isNotEmpty ? name[0] : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: stage.fg,
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      concern,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),

              // Life stage badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: stage.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  stage.label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: stage.fg),
                ),
              ),

              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip(label: 'Age ${client['age']}'),
              InfoChip(label: client['sex'] ?? ''),
              InfoChip(label: client['marital'] ?? ''),
              InfoChip(label: 'Risk: $risk'),
              InfoChip(label: 'Score: ${client['relationship_score'] ?? 'N/A'}'),
            ],
          ),

          const SizedBox(height: 14),

          InfoRow(icon: Icons.cake, text: 'Birthday: ${client['birthday']}'),
          InfoRow(
            icon: Icons.phone,
            text: 'Phone: ${client['phone'] ?? 'Not set'}',
          ),
          InfoRow(icon: Icons.cake, text: 'Birthday: ${client['birthday']}'),
          InfoRow(
            icon: Icons.health_and_safety,
            text: 'Health: ${client['health']}',
          ),
          InfoRow(
            icon: Icons.family_restroom,
            text: 'Children: ${client['children']}',
          ),
          InfoRow(
            icon: Icons.psychology,
            text: 'Personality: ${client['personality']}',
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openAIMemory(context),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('View AI Memory'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MeetingHistoryCard extends StatelessWidget {
  final Map<String, dynamic> meeting;
  final Function(String title, String text) onViewFullText;

  const MeetingHistoryCard({
    super.key,
    required this.meeting,
    required this.onViewFullText,
  });

  @override
  Widget build(BuildContext context) {
    final title = (meeting['title'] ?? '').toString().isEmpty
        ? 'Untitled Meeting'
        : meeting['title'].toString();

    final notes = (meeting['notes'] ?? '').toString();
    final summary = (meeting['summary'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Date: ${meeting['meeting_date'] ?? 'N/A'}'),
          Text('Sentiment: ${meeting['sentiment'] ?? 'N/A'}'),
          Text('Interest: ${meeting['interest_level'] ?? 'N/A'}'),

          const SizedBox(height: 10),

          const Text(
            'Summary',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            summary.isEmpty ? 'No summary available.' : summary,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          TextButton.icon(
            onPressed: () => onViewFullText(
              'Meeting Summary',
              summary.isEmpty ? 'No summary available.' : summary,
            ),
            icon: const Icon(Icons.open_in_full, size: 16),
            label: const Text('View full summary'),
          ),

          const Text(
            'Original Notes',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            notes.isEmpty ? 'No notes available.' : notes,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          TextButton.icon(
            onPressed: () => onViewFullText(
              'Original Meeting Notes',
              notes.isEmpty ? 'No notes available.' : notes,
            ),
            icon: const Icon(Icons.notes, size: 16),
            label: const Text('View full notes'),
          ),
        ],
      ),
    );
  }
}

class AIMemorySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const AIMemorySection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF4F46E5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  final String label;

  const InfoChip({
    super.key,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: const Color(0xFFF3F4F6),
      side: BorderSide.none,
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const InfoRow({
    super.key,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF4F46E5)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

// ─── Financial Coverage Section ───────────────────────────────────────────────

class _CoverageSection extends StatefulWidget {
  final int clientId;
  const _CoverageSection({required this.clientId});

  @override
  State<_CoverageSection> createState() => _CoverageSectionState();
}

class _CoverageSectionState extends State<_CoverageSection> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  static const _cats = [
    ('cashflow_management', 'Cashflow Management', Icons.account_balance_wallet_outlined),
    ('savings_investment', 'Savings & Investment', Icons.savings_outlined),
    ('retirement_planning', 'Retirement Planning', Icons.elderly_outlined),
    ('estate_planning', 'Estate Planning', Icons.gavel_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('http://localhost:8000/clients/${widget.clientId}/coverage'));
      if (res.statusCode == 200) {
        setState(() => _data = json.decode(res.body));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rtl, color: Color(0xFF4F46E5)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Financial Planning Coverage',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (!_loading)
                GestureDetector(
                  onTap: _load,
                  child: const Icon(Icons.refresh, size: 18, color: Colors.grey),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else if (_data == null)
            const Text('Could not load coverage. Tap refresh to retry.',
                style: TextStyle(color: Colors.grey))
          else ...[
            ..._cats.map((cat) {
              final key = cat.$1;
              final label = cat.$2;
              final icon = cat.$3;
              final catData = _data![key] as Map<String, dynamic>? ?? {};
              final covered = catData['covered'] == true;
              final note = catData['note'] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18,
                        color: covered ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(label,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: covered
                                      ? const Color(0xFFDCFCE7)
                                      : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  covered ? 'Covered' : 'Not Covered',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: covered
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            if ((_data!['priority_actions'] as List?)?.isNotEmpty == true) ...[
              const Divider(height: 20),
              const Text('Priority Actions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              ...(_data!['priority_actions'] as List).map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold)),
                    Expanded(child: Text(a.toString(), style: const TextStyle(fontSize: 12))),
                  ],
                ),
              )),
            ],
          ],
        ],
      ),
    );
  }
}