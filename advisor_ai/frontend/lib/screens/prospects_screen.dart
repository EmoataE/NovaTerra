import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String _base = 'http://localhost:8000';

// ─── Status helpers ───────────────────────────────────────────────────────────

Color _statusColor(String s) => switch (s) {
      'qualified' => const Color(0xFF16A34A),
      'meeting_requested' => const Color(0xFF0EA5E9),
      'meeting_scheduled' => const Color(0xFF7C3AED),
      'converted' => const Color(0xFF7C3AED),
      'contacted' => const Color(0xFFF59E0B),
      _ => const Color(0xFF9CA3AF),
    };

String _statusLabel(String s) => switch (s) {
      'new' => 'New',
      'qualified' => 'Qualified',
      'meeting_requested' => 'Meeting Requested',
      'meeting_scheduled' => 'Meeting Scheduled',
      'contacted' => 'Contacted',
      'converted' => 'Converted',
      _ => s,
    };

// ─── Main screen ──────────────────────────────────────────────────────────────

class ProspectsScreen extends StatefulWidget {
  const ProspectsScreen({super.key});
  @override
  State<ProspectsScreen> createState() => _ProspectsScreenState();
}

class _ProspectsScreenState extends State<ProspectsScreen> {
  List<dynamic> _prospects = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$_base/prospects'));
      if (res.statusCode == 200) setState(() => _prospects = json.decode(res.body));
    } catch (_) {}
    setState(() => _loading = false);
  }

  List<dynamic> get _filtered {
    if (_filter == 'all') return _prospects;
    return _prospects.where((p) => p['status'] == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        title: const Text('Prospects', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open Chat Link',
            onPressed: () async {
              final uri = Uri.parse('$_base/chat');
              if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _FilterBar(selected: _filter, onChange: (v) => setState(() => _filter = v)),
                Expanded(
                  child: list.isEmpty
                      ? _empty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: list.length,
                            itemBuilder: (_, i) => _ProspectCard(
                              data: Map<String, dynamic>.from(list[i]),
                              onRefresh: _load,
                            ),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.link),
        label: const Text('Copy Chat Link'),
        onPressed: () async {
          const url = '$_base/chat';
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No prospects yet', style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Share the chat link to start getting leads.',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                final uri = Uri.parse('$_base/chat');
                if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open Chat Page'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
}

// ─── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String selected;
  final void Function(String) onChange;
  const _FilterBar({required this.selected, required this.onChange});

  static const _tabs = [
    ('all', 'All'),
    ('new', 'New'),
    ('qualified', 'Qualified'),
    ('meeting_requested', 'Meeting'),
    ('converted', 'Converted'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _tabs.map((t) {
            final sel = selected == t.$1;
            return GestureDetector(
              onTap: () => onChange(t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF4F46E5) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(t.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : const Color(0xFF6B7280),
                    )),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── Prospect card ────────────────────────────────────────────────────────────

class _ProspectCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onRefresh;
  const _ProspectCard({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?)?.isNotEmpty == true ? data['name'] as String : 'Anonymous';
    final status = (data['status'] as String?) ?? 'new';
    final score = (data['interest_score'] as int?) ?? 0;
    final products = (data['recommended_products'] as List?) ?? [];
    final goals = (data['goals'] as String?) ?? '';
    final age = (data['age'] as String?) ?? '';
    final marital = (data['marital'] as String?) ?? '';
    final income = (data['income'] as String?) ?? '';
    final slot = (data['meeting_slot'] as String?) ?? '';

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF4F46E5).withOpacity(0.08), Colors.transparent],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFE0E7FF),
                    child: Text(name[0].toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4F46E5), fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (goals.isNotEmpty)
                          Text(goals, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_statusLabel(status),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(status))),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (age.isNotEmpty) _chip('Age $age', Icons.person_outline),
                      if (marital.isNotEmpty) _chip(marital, Icons.favorite_border),
                      if (income.isNotEmpty) _chip(income, Icons.account_balance_wallet_outlined),
                      if (slot.isNotEmpty) _meetingChip(slot),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Interest score bar
                  Row(
                    children: [
                      const Text('Interest', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: score / 100,
                            minHeight: 7,
                            backgroundColor: const Color(0xFFF3F4F6),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              score >= 70 ? const Color(0xFF16A34A) : score >= 40 ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$score%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                          color: score >= 70 ? const Color(0xFF16A34A) : score >= 40 ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF))),
                    ],
                  ),

                  if (products.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: products.take(2).map<Widget>((p) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${p['emoji'] ?? ''} ${p['name']}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF6D28D9), fontWeight: FontWeight.w600)),
                      )).toList(),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _openDetail(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4F46E5),
                            side: const BorderSide(color: Color(0xFF4F46E5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text('View Profile', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      if (status == 'qualified' || status == 'meeting_requested') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _convertToClient(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text('Convert', style: TextStyle(fontSize: 13)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: Colors.grey),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF374151))),
        ]),
      );

  Widget _meetingChip(String slot) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_today, size: 11, color: Color(0xFF0EA5E9)),
          const SizedBox(width: 4),
          Text(slot, style: const TextStyle(fontSize: 11, color: Color(0xFF0369A1), fontWeight: FontWeight.w600)),
        ]),
      );

  void _openDetail(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _ProspectDetail(id: data['id'] as int, onRefresh: onRefresh)));
  }

  Future<void> _convertToClient(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Convert to Client?'),
        content: const Text('This will create a new client profile from this prospect\'s data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final res = await http.post(Uri.parse('$_base/prospects/${data['id']}/convert'));
    if (res.statusCode == 200 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Converted to client successfully!')));
      onRefresh();
    }
  }
}

// ─── Prospect detail ──────────────────────────────────────────────────────────

class _ProspectDetail extends StatefulWidget {
  final int id;
  final VoidCallback onRefresh;
  const _ProspectDetail({required this.id, required this.onRefresh});
  @override
  State<_ProspectDetail> createState() => _ProspectDetailState();
}

class _ProspectDetailState extends State<_ProspectDetail> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$_base/prospects/${widget.id}'));
      if (res.statusCode == 200) setState(() => _data = json.decode(res.body));
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _convert() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Convert to Client?'),
        content: const Text('This will create a new client profile from this prospect\'s information.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await http.post(Uri.parse('$_base/prospects/${widget.id}/convert'));
    if (res.statusCode == 200 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Converted to client!')));
      widget.onRefresh();
      Navigator.pop(context);
    }
  }

  Future<void> _updateStatus(String status) async {
    await http.put(
      Uri.parse('$_base/prospects/${widget.id}/status'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'status': status}),
    );
    _load();
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_data == null) return const Scaffold(body: Center(child: Text('Failed to load.')));

    final d = _data!;
    final name = (d['name'] as String?)?.isNotEmpty == true ? d['name'] as String : 'Anonymous';
    final status = (d['status'] as String?) ?? 'new';
    final score = (d['interest_score'] as int?) ?? 0;
    final products = (d['recommended_products'] as List?) ?? [];
    final messages = (d['messages'] as List?) ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _updateStatus,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('Mark as New')),
              PopupMenuItem(value: 'contacted', child: Text('Mark as Contacted')),
              PopupMenuItem(value: 'qualified', child: Text('Mark as Qualified')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Score + status header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Text(name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                        child: Text(_statusLabel(status),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text('$score%', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    const Text('Interest', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Profile fields
          _section('Client Profile', Icons.person_outline, [
            _row('Name', d['name'] ?? '-'),
            _row('Age', d['age'] ?? '-'),
            _row('Income', d['income'] ?? '-'),
            _row('Marital Status', d['marital'] ?? '-'),
            _row('Children', d['children'] ?? '-'),
            _row('Health', d['health'] ?? '-'),
            _row('Goals', d['goals'] ?? '-'),
            _row('Risk Appetite', d['risk'] ?? '-'),
            _row('Language', d['language'] ?? '-'),
            if ((d['meeting_slot'] as String?)?.isNotEmpty == true)
              _row('Meeting Slot', d['meeting_slot'] as String),
          ]),
          const SizedBox(height: 12),

          // Product recommendations
          if (products.isNotEmpty) ...[
            _sectionHeader('Recommended Products', Icons.lightbulb_outline),
            const SizedBox(height: 8),
            ...products.map((p) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: const Border(left: BorderSide(color: Color(0xFF4F46E5), width: 3)),
                  ),
                  child: Row(
                    children: [
                      Text(p['emoji'] ?? '', style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(p['description'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
                        child: Text('${p['match_pct']}%',
                            style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
          ],

          // Conversation
          _sectionHeader('AI Conversation (${messages.length} messages)', Icons.chat_bubble_outline),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: messages.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('No messages yet.', style: TextStyle(color: Colors.grey)))
                : Column(
                    children: messages.take(20).map<Widget>((m) {
                      final isUser = m['role'] == 'user';
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            if (!isUser) ...[
                              const CircleAvatar(radius: 12, backgroundColor: Color(0xFFE0E7FF),
                                  child: Text('AI', style: TextStyle(fontSize: 8, color: Color(0xFF4F46E5), fontWeight: FontWeight.bold))),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isUser ? const Color(0xFFDCF8C6) : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text((m['content'] as String?) ?? '',
                                    style: const TextStyle(fontSize: 12, height: 1.4)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 20),

          // Actions
          if (status != 'converted') ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _convert,
                icon: const Icon(Icons.person_add),
                label: const Text('Convert to Client'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF4F46E5)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      );

  Widget _section(String title, IconData icon, List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(title, icon),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _row(String label, String value) {
    if (value == '-' || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    );
  }
}
