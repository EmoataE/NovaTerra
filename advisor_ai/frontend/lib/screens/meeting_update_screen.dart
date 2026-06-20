import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:file_picker/file_picker.dart';

class MeetingUpdateScreen extends StatefulWidget {
  final Map<String, dynamic>? preselectedClient;

  const MeetingUpdateScreen({
    super.key,
    this.preselectedClient,
  });

  @override
  State<MeetingUpdateScreen> createState() => _MeetingUpdateScreenState();
}

class _MeetingUpdateScreenState extends State<MeetingUpdateScreen> {
  List<Map<String, dynamic>> clients = [];
  Map<String, dynamic>? selectedClient;

  final speech = stt.SpeechToText();

  bool isListening = false;
  bool speechReady = false;
  bool isAnalysing = false;
  bool isUploading = false;

  Map<String, dynamic>? aiAnalysis;

  String searchQuery = '';
  String inputMode = 'Type';

  String? uploadedFileName;

  DateTime meetingDate = DateTime.now();
  String interestLevel = 'Interested';

  final titleController = TextEditingController();
  final notesController = TextEditingController();
  final concernController = TextEditingController();
  final personalityController = TextEditingController();
  final riskController = TextEditingController();
  final healthController = TextEditingController();
  final childrenController = TextEditingController();
  final followUpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchClients();
    initSpeech();

    if (widget.preselectedClient != null) {
      final client = widget.preselectedClient!;
      selectedClient = client;
      titleController.text = client['purpose'] ?? '';
      concernController.text = client['concern'] ?? '';
      personalityController.text = client['personality'] ?? '';
      riskController.text = client['risk'] ?? '';
      healthController.text = client['health'] ?? '';
      childrenController.text = client['children'] ?? '';
    }
  }

  Future<void> initSpeech() async {
    speechReady = await speech.initialize();
    setState(() {});
  }

  Future<void> fetchClients() async {
    final response =
        await http.get(Uri.parse('http://localhost:8000/clients'));
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      setState(() {
        clients =
            data.map((item) => Map<String, dynamic>.from(item)).toList();
      });
    }
  }

  List<Map<String, dynamic>> get filteredClients {
    if (searchQuery.trim().isEmpty) return [];

    return clients.where((client) {
      final name = (client['name'] ?? '').toString().toLowerCase();
      return name.contains(searchQuery);
    }).toList();
  }

  void selectClient(Map<String, dynamic> client) {
    setState(() {
      selectedClient = client;
      concernController.text = client['concern'] ?? '';
      personalityController.text = client['personality'] ?? '';
      riskController.text = client['risk'] ?? '';
      healthController.text = client['health'] ?? '';
      childrenController.text = client['children'] ?? '';
      aiAnalysis = null;
    });
  }

  void _applyAnalysis(Map<String, dynamic> data) {
    final memories = data['memories'] as List? ?? [];
    final opportunities = data['opportunities'] as List? ?? [];

    setState(() {
      aiAnalysis = data;
      interestLevel = data['interest_level'] ?? interestLevel;

      if (opportunities.isNotEmpty) {
        concernController.text =
            opportunities.first['opportunity_type'] ?? concernController.text;
        followUpController.text =
            opportunities.first['suggested_action'] ?? followUpController.text;
      }

      if (memories.isNotEmpty) {
        personalityController.text =
            memories.first['content'] ?? personalityController.text;
      }

      if ((data['risk'] ?? '').toString().isNotEmpty) {
        riskController.text = data['risk'];
      }

      isAnalysing = false;
      isUploading = false;
    });
  }

  Future<void> startListening() async {
    if (!speechReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is not ready')),
      );
      return;
    }
    setState(() => isListening = true);
    await speech.listen(
      onResult: (result) {
        setState(() {
          notesController.text = result.recognizedWords;
        });
      },
    );
  }

  Future<void> stopListening() async {
    await speech.stop();
    setState(() => isListening = false);
  }

  Future<void> analyseMeetingNotes() async {
    if (selectedClient == null) {
      _snack('Please select a client first');
      return;
    }
    if (notesController.text.trim().isEmpty) {
      _snack('Please enter meeting notes first');
      return;
    }

    setState(() {
      isAnalysing = true;
      aiAnalysis = null;
    });

    final response = await http.post(
      Uri.parse('http://localhost:8000/ai/copilot'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': selectedClient!['id'],
        'notes': notesController.text,
      }),
    );

    if (response.statusCode == 200) {
      _applyAnalysis(Map<String, dynamic>.from(jsonDecode(response.body)));
    } else {
      setState(() => isAnalysing = false);
      _snack('AI analysis failed: ${response.body}');
    }
  }

  Future<void> pickAndUploadFile() async {
    if (selectedClient == null) {
      _snack('Please select a client first');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        // Documents
        'pdf', 'txt', 'md',
        // Images (handwritten notes)
        'jpg', 'jpeg', 'png', 'webp', 'heic',
        // Audio recordings
        'mp3', 'wav', 'm4a', 'webm', 'ogg',
      ],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      _snack('Could not read file');
      return;
    }

    setState(() {
      isUploading = true;
      uploadedFileName = file.name;
      aiAnalysis = null;
    });

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://localhost:8000/process-upload'),
    );
    request.fields['client_id'] = selectedClient!['id'].toString();
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      file.bytes!,
      filename: file.name,
    ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      if (data.containsKey('error')) {
        setState(() => isUploading = false);
        _snack(data['error']);
        return;
      }
      if (data['extracted_text'] != null) {
        notesController.text = data['extracted_text'];
      }
      _applyAnalysis(data);
    } else {
      setState(() => isUploading = false);
      _snack('Upload failed: ${response.body}');
    }
  }

  Future<void> saveMeetingUpdate() async {
    if (selectedClient == null) {
      _snack('Please select a client first');
      return;
    }

    final updateData = {
      'client_id': selectedClient!['id'],
      'title': titleController.text,
      'meeting_date':
          '${meetingDate.year}-${meetingDate.month.toString().padLeft(2, '0')}-${meetingDate.day.toString().padLeft(2, '0')}',
      'notes': notesController.text,
      'interest_level': interestLevel,
    };

    final response = await http.post(
      Uri.parse('http://localhost:8000/meeting-updates'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(updateData),
    );

    if (response.statusCode == 200) {
      final savedData =
          Map<String, dynamic>.from(jsonDecode(response.body));
      await fetchClients();
      _snack('AI memory saved');
      setState(() {
        aiAnalysis = savedData;
        selectedClient = null;
        titleController.clear();
        notesController.clear();
        concernController.clear();
        personalityController.clear();
        riskController.clear();
        healthController.clear();
        childrenController.clear();
        followUpController.clear();
        interestLevel = 'Interested';
        inputMode = 'Type';
        uploadedFileName = null;
      });
    } else {
      _snack('Failed to save: ${response.body}');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Widgets ──────────────────────────────────────────────────────────────

  Widget buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget buildSectionCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _inputModeChip(String label, IconData icon) {
    final selected = inputMode == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => inputMode = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF4F46E5)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? Colors.white : Colors.grey[600]),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildCaptureNotesCard() {
    return buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '3. Capture Notes',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Type, speak, or upload your unstructured meeting notes. AI will extract structured intelligence.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 14),

          // Mode tabs
          Row(
            children: [
              _inputModeChip('Type', Icons.edit_note),
              const SizedBox(width: 8),
              _inputModeChip('Audio', Icons.mic),
              const SizedBox(width: 8),
              _inputModeChip('Upload', Icons.upload_file),
            ],
          ),

          const SizedBox(height: 16),

          // Audio panel
          if (inputMode == 'Audio')
            Container(
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isListening
                          ? Colors.red.withOpacity(0.10)
                          : const Color(0xFFEEF2FF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isListening ? Icons.graphic_eq : Icons.mic_none,
                      color: isListening ? Colors.red : const Color(0xFF4F46E5),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isListening ? 'Recording in progress' : 'Record meeting audio',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isListening
                              ? 'Speak clearly. Your speech will appear in the notes box below.'
                              : 'Use voice input to quickly capture your meeting notes.',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: isListening ? stopListening : startListening,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isListening ? Colors.red : const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(isListening ? 'Stop' : 'Start'),
                  ),
                ],
              ),
            ),

          // Upload panel
          if (inputMode == 'Upload')
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFE5E7EB),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload_outlined,
                      size: 44, color: Color(0xFF4F46E5)),
                  const SizedBox(height: 10),
                  const Text(
                    'Upload notes, image or audio',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'PDF / TXT — typed or printed notes\nJPG / PNG — handwritten note photo\nMP3 / WAV / M4A — voice recording\n\nGemini AI will extract and analyse automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  if (uploadedFileName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.insert_drive_file,
                              size: 16, color: Color(0xFF4F46E5)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              uploadedFileName!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isUploading ? null : pickAndUploadFile,
                      icon: isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(isUploading
                          ? 'Processing…'
                          : 'Choose File & Analyse'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Notes text box (always visible)
          buildTextField(
            notesController,
            inputMode == 'Audio'
                ? 'Transcribed Speech'
                : inputMode == 'Upload'
                    ? 'Extracted Text (editable)'
                    : 'Meeting Notes',
            maxLines: 6,
          ),

          const SizedBox(height: 6),

          if (inputMode != 'Upload')
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: isAnalysing ? null : analyseMeetingNotes,
                icon: isAnalysing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(isAnalysing
                    ? 'Analysing…'
                    : 'Analyse with AI'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _outputRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                  fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                  fontSize: 13,
                  color: valueColor ?? Colors.black87,
                  fontWeight: valueColor != null
                      ? FontWeight.bold
                      : FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipList(List<String> items, Color bg, Color fg) {
    if (items.isEmpty) return const Text('—', style: TextStyle(fontSize: 13));
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: items
          .map((e) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(e,
                    style: TextStyle(
                        fontSize: 12,
                        color: fg,
                        fontWeight: FontWeight.w500)),
              ))
          .toList(),
    );
  }

  Widget buildAiAnalysisCard() {
    if (aiAnalysis == null) return const SizedBox.shrink();

    final memories = aiAnalysis!['memories'] as List? ?? [];
    final opportunities = aiAnalysis!['opportunities'] as List? ?? [];
    final policies =
        (aiAnalysis!['suggested_policies'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
    final followUps = (aiAnalysis!['follow_up'] as String? ?? '')
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final sentimentColor = {
          'Positive': Colors.green[700],
          'Concerned': Colors.orange[700],
          'Neutral': Colors.blue[700],
        }[aiAnalysis!['sentiment']] ??
        Colors.black87;

    final interestColor = {
          'Interested': Colors.green[700],
          'Maybe': Colors.orange[700],
          'Not interested': Colors.red[700],
        }[aiAnalysis!['interest_level']] ??
        Colors.black87;

    return buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Color(0xFF4F46E5), size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'AI Structured Output',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(height: 24),

          // Meeting Summary
          const Text('Meeting Summary',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              aiAnalysis!['summary'] ?? '—',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),

          // Scores row
          Row(
            children: [
              Expanded(
                child: _scoreChip(
                  'Sentiment',
                  aiAnalysis!['sentiment'] ?? '—',
                  sentimentColor!,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _scoreChip(
                  'Interest',
                  aiAnalysis!['interest_level'] ?? '—',
                  interestColor!,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _scoreChip(
                  'Risk',
                  aiAnalysis!['risk'] ?? '—',
                  Colors.grey[700]!,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Key Concerns
          const Text('Key Concerns',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _chipList(
            (aiAnalysis!['concern'] as String? ?? '')
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
            const Color(0xFFFEF3C7),
            const Color(0xFF92400E),
          ),
          const SizedBox(height: 16),

          // Product Interests
          const Text('Product Interests',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _chipList(
              policies,
              const Color(0xFFEDE9FE),
              const Color(0xFF5B21B6)),
          const SizedBox(height: 16),

          // Action Items
          const Text('Action Items',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          if (followUps.isEmpty)
            const Text('—', style: TextStyle(fontSize: 13))
          else
            for (final item in followUps)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: Color(0xFF4F46E5)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(item,
                            style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
          const SizedBox(height: 16),

          // AI Memory Extracted
          const Text('AI Memory Extracted',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          if (memories.isEmpty)
            const Text('No memory extracted.',
                style: TextStyle(fontSize: 13, color: Colors.grey))
          else
            for (final m in memories)
              _memoryRow(
                m['memory_type']?.toString() ?? '',
                m['content']?.toString() ?? '',
                (m['confidence'] as num?)?.toInt() ?? 0,
              ),
          const SizedBox(height: 16),

          // Opportunities
          const Text('Opportunities Detected',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          if (opportunities.isEmpty)
            const Text('No opportunities detected.',
                style: TextStyle(fontSize: 13, color: Colors.grey))
          else
            for (final opp in opportunities)
              _opportunityRow(opp),
          const SizedBox(height: 16),

          // Follow-up message
          const Text('Recommended Follow-up Message',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              aiAnalysis!['follow_up_message'] ?? '—',
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: Color(0xFF3730A3)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _memoryRow(String type, String content, int confidence) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.memory, size: 15, color: Color(0xFF4F46E5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(content,
                style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Text('$confidence%',
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _opportunityRow(Map opp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  size: 15, color: Color(0xFF15803D)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  opp['opportunity_type']?.toString() ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF15803D)),
                ),
              ),
              Text(
                '${opp['confidence'] ?? 0}%',
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF15803D),
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
          if ((opp['suggested_action'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 21),
              child: Text(
                opp['suggested_action'].toString(),
                style: const TextStyle(
                    fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedName = selectedClient?['name'] ?? 'Meeting Update';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header banner
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.mic, color: Colors.white, size: 34),
                  const SizedBox(height: 14),
                  Text(
                    selectedClient == null
                        ? 'Meeting Update'
                        : 'Meeting with ${selectedClient!['name']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Capture notes, upload files, or record voice — AI converts everything into structured client intelligence.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 1. Select Client
            buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Select Client',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),

                  if (selectedClient == null)
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search client by name...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) {
                        setState(() {
                          searchQuery = v.trim().toLowerCase();
                        });
                      },
                    ),

                  if (selectedClient == null && searchQuery.isNotEmpty)
                    const SizedBox(height: 14),

                  if (selectedClient == null && searchQuery.isNotEmpty)
                    if (filteredClients.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'No client found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      for (final client in filteredClients.take(5))
                        GestureDetector(
                          onTap: () => selectClient(client),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFFE0E7FF),
                                  child: Text(
                                    (client['name'] ?? '?').toString().isNotEmpty
                                        ? client['name'][0]
                                        : '?',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    client['name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),

                  if (selectedClient != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Color(0xFF4F46E5)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Selected: ${selectedClient!['name']}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                selectedClient = null;
                                searchQuery = '';
                              });
                            },
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // 2. Meeting Details
            buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('2. Meeting Details',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  buildTextField(titleController, 'Meeting Title'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        'Meeting Date: ${meetingDate.day}/${meetingDate.month}/${meetingDate.year}'),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: meetingDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setState(() => meetingDate = picked);
                      }
                    },
                  ),
                ],
              ),
            ),

            // 3. Capture Notes
            buildCaptureNotesCard(),

            // AI Output
            buildAiAnalysisCard(),

            // 4. Review Memory Fields
            buildSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('4. Review & Edit Memory Fields',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'AI has pre-filled these from your notes. Edit before saving.',
                    style:
                        TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  buildTextField(
                      concernController, 'Key Concern / Opportunity'),
                  buildTextField(
                      personalityController, 'Personality / Memory'),
                  buildTextField(riskController, 'Risk Level'),
                  buildTextField(healthController, 'Health Condition'),
                  buildTextField(childrenController, 'Children'),
                  buildTextField(
                      followUpController, 'Recommended Follow-up'),
                  DropdownButtonFormField<String>(
                    value: interestLevel,
                    decoration: InputDecoration(
                      labelText: 'Interest Level',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'Interested',
                          child: Text('Interested')),
                      DropdownMenuItem(
                          value: 'Maybe',
                          child: Text('Maybe / Needs follow-up')),
                      DropdownMenuItem(
                          value: 'Not interested',
                          child: Text('Not interested')),
                    ],
                    onChanged: (v) =>
                        setState(() => interestLevel = v!),
                  ),
                ],
              ),
            ),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: saveMeetingUpdate,
                icon: const Icon(Icons.save),
                label: const Text('Save to Client Memory'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
