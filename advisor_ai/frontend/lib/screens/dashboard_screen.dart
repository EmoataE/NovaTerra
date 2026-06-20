import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'meeting_update_screen.dart';
import 'package:url_launcher/url_launcher.dart';


// The Main dashbaord screen
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime selectedDate = DateTime.now();

  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> events = [];
  List<Map<String, dynamic>> suggestedMessages = [];
  Set<String> completedActionIds = {};
  static const Color primary = Color(0xFF4F46E5);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);

  bool isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<Map<String, dynamic>> eventsForDate(DateTime date) {
    return events.where((event) {return isSameDate(event['dateObject'], date);}).toList();
  }

  List<Map<String, dynamic>> get todayEvents {
    return eventsForDate(DateTime.now());
  }

  List<Map<String, dynamic>> get todayActionItems {
    final items = [...todayEvents];
    for (final msg in suggestedMessages) {
      final messageTypes = msg['message_types'] ?? [];
      if (messageTypes.contains('meeting_reminder')) {
          continue;
        }
      final alreadyHasEvent = items.any(
        (event) => event['client_id'] == msg['client_id'],
      );

      if (!alreadyHasEvent) {
        items.add({
          'id': 'suggested-${msg['client_id']}',
          'client_id': msg['client_id'],
          'name': msg['client_name'],
          'phone': msg['phone'],
          'time': (msg['message_types'] ?? []).contains('meeting_reminder')? '': 'Action',
          'purpose': _labelForMessageTypes(msg['message_types'] ?? []),
          'message': msg['message'],
          'is_suggested_action': true,
        });
      }
    }

    items.sort((a, b) {
      final aDone = completedActionIds.contains(a['id'].toString());
      final bDone = completedActionIds.contains(b['id'].toString());
      if (aDone == bDone) return 0;
      return aDone ? 1 : -1;
    });

    return items;
  }

  String _labelForMessageTypes(List types) {
    if (types.contains('birthday') && types.contains('meeting_reminder')) {
      return 'Birthday + Meeting Reminder';
    }
    if (types.contains('birthday')) return 'Birthday Wish';
    if (types.contains('meeting_reminder')) return 'Meeting Reminder';
    if (types.contains('long_silence')) return 'Re-engagement';
    if (types.contains('renewal_reminder')) return 'Renewal Reminder';
    return 'Suggested Follow-up';
  }

  List<Map<String, dynamic>> get selectedEvents {
    return eventsForDate(selectedDate);
  }

  String monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April',
      'May', 'June', 'July', 'August', 'September',
      'October', 'November','December',
    ];
    return months[month - 1];
  }

  String formatDate(DateTime date) {
    return '${date.day} ${monthName(date.month)} ${date.year}';
  }

  int get actionsLeft {
    final todayIds = todayActionItems.map((e) => e['id'].toString()).toSet();
    final completedTodayOnly = completedActionIds.where((id) => todayIds.contains(id)).length;
    return todayActionItems.length - completedTodayOnly;
  }

  int get completedToday {
    final todayIds = todayActionItems.map((e) => e['id'].toString()).toSet();
    return completedActionIds.where((id) => todayIds.contains(id)).length;
  }

  // Lifecycle
  @override
  void initState() {
    super.initState();
    loadDashboardData();
  }

  Future<void> loadDashboardData() async {
    await fetchClients();
    await fetchEvents();
    await fetchSuggestedMessages();
    await fetchCompletedActions();
  }

  // The API Calls
  Future<void> fetchClients() async {
    final response = await http.get(Uri.parse('http://localhost:8000/clients'));

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      setState(() {
        clients = data.map((item) => Map<String, dynamic>.from(item)).toList();
      });
    }
  }

  Future<void> fetchSuggestedMessages() async {
    final response = await http.get(
      Uri.parse('http://localhost:8000/dashboard/messages'),
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);

      setState(() {
        suggestedMessages =
            data.map((item) => Map<String, dynamic>.from(item)).toList();
      });
    }
  }

  Future<void> fetchCompletedActions() async {
    final response = await http.get(
      Uri.parse('http://localhost:8000/completed-actions'),
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);

      setState(() {
        completedActionIds =
            data.map((item) => item['action_id'].toString()).toSet();
      });
    }
  }
  
  Future<void> fetchEvents() async {
    final response = await http.get(Uri.parse('http://localhost:8000/events'));

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);

      setState(() {
        events = data.map((item) {
          final event = Map<String, dynamic>.from(item);

          final matchingClient = clients.firstWhere(
            (client) => client['id'] == event['client_id'],
            orElse: () => {},
          );

          final relationshipScore =
              matchingClient['relationship_score'] ?? 40;

          return {
            ...event,
            ...matchingClient,
            'id': event['id'],
            'client_id': event['client_id'],
            'dateObject': DateTime.parse(event['date']),
            'relationship_score': relationshipScore,
            'relationship_status': getRelationshipStatus(relationshipScore),
            'action': matchingClient['recommended_action'] ??
                'Follow up based on ${event['concern'] ?? 'client needs'}',
          };
        }).toList();

        events.sort((a, b) {
          final dateCompare = a['dateObject'].compareTo(b['dateObject']);
          if (dateCompare != 0) return dateCompare;
          return (a['time'] ?? '').compareTo(b['time'] ?? '');
        });
      });
    }
  }

  
  // Helper functions
  void changeCalendarMonth(int offset) {
    setState(() {
      selectedDate = DateTime(
        selectedDate.year,
        selectedDate.month + offset,
        1,
      );
    });
  }

  // To get the relationship score
  String getRelationshipStatus(int score) {
    if (score >= 80) return 'Strong';
    if (score >= 55) return 'Warm';
    return 'At Risk';
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void openAddEventForm() {
    String clientSearchQuery = '';
    Map<String, dynamic>? selectedClient;
    TimeOfDay selectedTime = TimeOfDay.now();
    DateTime eventDate = selectedDate;
    final purposeController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            final filteredClients = clients.where((client) {
              final name = (client['name'] ?? '').toString().toLowerCase();
              return name.contains(clientSearchQuery);
            }).toList();

            return Container(
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 22,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: const Color(0xFFE0E7FF)),
                      ),
                      child: const Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Color(0xFF4F46E5),
                            child: Icon(
                              Icons.calendar_month,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add Calendar Event',
                                  style: TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Search client, select date and time, then save activity.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search client by name...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        modalSetState(() {
                          clientSearchQuery = value.toLowerCase().trim();
                        });
                      },
                    ),

                    const SizedBox(height: 14),

                    if (clients.isEmpty)
                      const EmptyCard(text: 'No clients found. Add client first.')
                    else if (clientSearchQuery.isNotEmpty)
                      Column(
                        children: [
                          for (final client in filteredClients.take(5))
                            GestureDetector(
                              onTap: () {
                                modalSetState(() {
                                  selectedClient = client;
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: selectedClient?['id'] == client['id']
                                      ? const Color(0xFFEEF2FF)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: selectedClient?['id'] == client['id']
                                        ? primary
                                        : border,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor:
                                          const Color(0xFFE0E7FF),
                                      child: Text(
                                        (client['name'] ?? '?')
                                                .toString()
                                                .isNotEmpty
                                            ? client['name'][0]
                                            : '?',
                                        style: const TextStyle(
                                          color: Color(0xFF4F46E5),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            client['name'] ?? '',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            client['concern'] ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selectedClient?['id'] == client['id'])
                                      const Icon(
                                        Icons.check_circle,
                                        color: Color(0xFF10B981),
                                      )
                                    else
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Colors.grey,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),

                    if (selectedClient != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Selected: ${selectedClient!['name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: eventDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );

                              if (pickedDate != null) {
                                modalSetState(() {
                                  eventDate = pickedDate;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    color: Color(0xFF4F46E5),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${eventDate.day}/${eventDate.month}/${eventDate.year}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final pickedTime = await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );

                              if (pickedTime != null) {
                                modalSetState(() {
                                  selectedTime = pickedTime;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    color: Color(0xFF4F46E5),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: purposeController,
                      decoration: InputDecoration(
                        labelText: 'Meeting Purpose',
                        hintText: 'e.g. Retirement review',
                        prefixIcon: const Icon(Icons.edit_note),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.event_available),
                        label: const Text(
                          'Create Calendar Event',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: () async {
                          if (selectedClient == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please select a client first'),
                              ),
                            );
                            return;
                          }

                          final eventData = {
                            'client_id': selectedClient!['id'],
                            'date':
                                '${eventDate.year}-${eventDate.month.toString().padLeft(2, '0')}-${eventDate.day.toString().padLeft(2, '0')}',
                            'time':
                                '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                            'purpose': purposeController.text,
                          };

                          final response = await http.post(
                            Uri.parse('http://localhost:8000/events'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode(eventData),
                          );

                          if (response.statusCode == 200) {
                            await fetchEvents();
                            setState(() {
                              selectedDate = eventDate;
                            });
                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to save event'),
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

  // Event functions
  Future<void> markActionDone(
    String actionId,
    Map<String, dynamic> event,
  ) async {
      if (completedActionIds.contains(actionId)) {
        final response = await http.delete(
          Uri.parse('http://localhost:8000/completed-actions/$actionId'),
        );

        if (response.statusCode == 200) {
          setState(() {
            completedActionIds.remove(actionId);
          });
        }
      } else {
        final response = await http.post(
          Uri.parse('http://localhost:8000/completed-actions'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action_id': actionId,
            'client_id': event['client_id'],
            'action_type': event['purpose'] ?? '',
            'message': event['message'] ?? '',
          }),
        );

        if (response.statusCode == 200) {
          setState(() {
            completedActionIds.add(actionId);
          });
        }
      }
    }

  Future<void> openWhatsAppMessage({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleanPhone.isEmpty) {
      _snack('No phone number found for this client');
      return;
    }

    if (message.trim().isEmpty) {
      _snack('No message available to send');
      return;
    }

    final url = Uri.parse(
      'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}',
    );

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _snack('Could not open WhatsApp');
    }
  }

  Future<void> deleteEvent(int eventId) async {
    final response = await http.delete(
      Uri.parse('http://localhost:8000/events/$eventId'),
    );

    if (response.statusCode == 200) {
      await fetchEvents();
    }
  }

  Future<void> confirmDeleteEvent(Map<String, dynamic> event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text(
          'Delete ${event['name'] ?? 'this client'}\'s event?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await deleteEvent(event['id']);
    }
  }


  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await fetchClients();
          await fetchEvents();
          await loadDashboardData();
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 18),

            GoodMorningHero(
              todayCount: todayEvents.length,
              clientCount: clients.length,
              actionsLeft: actionsLeft,
              completedToday: completedToday,
              onAddEvent: openAddEventForm,
            ),

            const SizedBox(height: 20),

            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TodaysSchedulePanel(
                      events: todayActionItems,
                      suggestedMessages: suggestedMessages,
                      completedActionIds: completedActionIds,
                      onMarkDone: markActionDone,
                      onDelete: confirmDeleteEvent,
                      onWhatsApp: openWhatsAppMessage,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: ClientIntelligenceCarousel(
                      clients: todayEvents,
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  TodaysSchedulePanel(
                    events: todayActionItems,
                    suggestedMessages: suggestedMessages,
                    completedActionIds: completedActionIds,
                    onMarkDone: markActionDone,
                    onDelete: confirmDeleteEvent,
                    onWhatsApp: openWhatsAppMessage,
                  ),
                  const SizedBox(height: 18),
                  ClientIntelligenceCarousel(
                    clients: todayEvents,
                  ),
                ],
              ),

            const SizedBox(height: 20),

            CompactCalendarPanel(
              selectedDate: selectedDate,
              events: events,
              selectedEvents: selectedEvents,
              monthName: monthName,
              isSameDate: isSameDate,
              eventsForDate: eventsForDate,
              onDateSelected: (date) {
                setState(() {
                  selectedDate = date;
                });
              },
              onMonthChanged: changeCalendarMonth,
              onDelete: confirmDeleteEvent,
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}


/////////////////////////////////////////////////////
/// Widgets
////////////////////////////////////////////////////
class GoodMorningHero extends StatelessWidget {

  final int todayCount;
  final int clientCount;
  final int actionsLeft;
  final int completedToday;
  final VoidCallback onAddEvent;

  const GoodMorningHero({
    super.key,
    required this.todayCount,
    required this.clientCount,
    required this.actionsLeft,
    required this.completedToday,
    // required this.highRiskCount,
    required this.onAddEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Good Morning, Advisor 👋',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Dashboard",
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              HeroStat(
                label: 'Clients',
                value: clientCount.toString(),
              ),
              const SizedBox(width: 12),

              HeroStat(
                label: 'Meetings',
                value: todayCount.toString(),
              ),
              const SizedBox(width: 12),

              HeroStat(
                label: 'Actions Left',
                value: actionsLeft.toString(),
              ),
              const SizedBox(width: 12),

              HeroStat(
                label: 'Completed',
                value: completedToday.toString(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF4F46E5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onAddEvent,
              icon: const Icon(Icons.add),
              label: const Text('Add Calendar Event'),
            ),
          ),
        ],
      ),
    );
  }
}

class HeroStat extends StatelessWidget {
  final String label;
  final String value;

  const HeroStat({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 78,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class TodaysSchedulePanel extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> suggestedMessages;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Future<void> Function({
    required String phone,
    required String message,
  }) onWhatsApp;
  final Set<String> completedActionIds;
  final Future<void> Function(
    String actionId,
    Map<String, dynamic> event,
  ) onMarkDone;

  const TodaysSchedulePanel({
    super.key,
    required this.events,
    required this.suggestedMessages,
    required this.completedActionIds,
    required this.onMarkDone,
    required this.onDelete,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final sortedEvents = [...events];

    sortedEvents.sort((a, b) {
      final aDone = completedActionIds.contains(a['id'].toString());
      final bDone = completedActionIds.contains(b['id'].toString());

      if (aDone == bDone) return 0;
      return aDone ? 1 : -1;
    });

    return CrmCard(
      height: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle(
            title: "Today's Actions",
            icon: Icons.today_outlined,
          ),

          const SizedBox(height: 14),

          if (sortedEvents.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No actions/activities scheduled today.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                  padding: const EdgeInsets.only(right: 8),
                  itemCount: sortedEvents.length,
                  itemBuilder: (context, index) {
                    final event = sortedEvents[index];
                    final actionId = event['id'].toString();
                    final isDone = completedActionIds.contains(actionId);

                    final actionCard = Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFFF1F5F9)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 76,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: isDone
                                  ? const Color(0xFFE5E7EB)
                                  : const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                (event['time'] ?? '').toString().isEmpty
                                    ? 'Action'
                                    : event['time'].toString(),
                                style: TextStyle(
                                  color: isDone
                                      ? Colors.grey
                                      : const Color(0xFF4F46E5),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event['name'] ?? 'Unnamed Client',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    decoration: isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: isDone ? Colors.grey : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  event['purpose'] ?? 'Client meeting',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey,
                                    decoration: isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.chat,
                                  color: isDone
                                      ? Colors.grey
                                      : const Color(0xFF10B981),
                                ),
                                onPressed: isDone
                                    ? null
                                    : () async {
                                        final name =
                                            event['name'] ?? 'there';
                                        final phone = event['phone'] ?? '';
                                        final time = event['time'] ?? '';

                                        final matchedMessage =
                                            suggestedMessages.firstWhere(
                                          (msg) =>
                                              msg['client_id'] ==
                                              event['client_id'],
                                          orElse: () => {},
                                        );

                                        final message = event['message'] ??
                                            matchedMessage['message'] ??
                                            'Hi $name, just a friendly reminder that we have a meeting scheduled today${time.toString().isNotEmpty ? ' at $time' : ''}. Looking forward to speaking with you.';

                                        await onWhatsApp(
                                          phone: phone.toString(),
                                          message: message.toString(),
                                        );
                                      },
                              ),

                              IconButton(
                                icon: Icon(
                                  isDone
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: isDone
                                      ? const Color(0xFF10B981)
                                      : Colors.grey,
                                ),
                                onPressed: () async {
                                  await onMarkDone(actionId, event);
                                },
                              ),

                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: isDone
                                      ? Colors.grey
                                      : const Color(0xFFEF4444),
                                ),
                                onPressed: () async {
                                  await onDelete(event);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );

                    final shouldShowCompletedDivider =
                        isDone &&
                        index > 0 &&
                        !completedActionIds.contains(
                          sortedEvents[index - 1]['id'].toString(),
                        );

                    if (shouldShowCompletedDivider) {
                      return Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'Completed',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                          ),
                          actionCard,
                        ],
                      );
                    }

                    return actionCard;
                  },
                ),
            ),
        ],
      ),
    );
  }
}

class ClientIntelligenceCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> clients;

  const ClientIntelligenceCarousel({
    super.key,
    required this.clients,
  });

  @override
  State<ClientIntelligenceCarousel> createState() =>
      _ClientIntelligenceCarouselState();
}

class _ClientIntelligenceCarouselState
    extends State<ClientIntelligenceCarousel> {
  final PageController controller = PageController();
  int currentIndex = 0;

  Color riskColor(String risk) {
    final value = risk.toLowerCase();
    if (value.contains('high')) return const Color(0xFFEF4444);
    if (value.contains('medium') || value.contains('moderate')) {
      return const Color(0xFFF59E0B);
    }
    return const Color(0xFF10B981);
  }

  String ageSegment(dynamic ageValue) {
    final age = int.tryParse(ageValue?.toString() ?? '');

    if (age == null) return 'Unknown';

    if (age >= 20 && age <= 29) {
      return 'Young Professional';
    }

    if (age >= 40 && age <= 59) {
      return 'Mid Career';
    }

    if (age >= 60) {
      return 'Retirement';
    }

    return 'General Client';
  }

  String familyTag(Map<String, dynamic> client) {
    final marital =
        (client['marital_status'] ?? '').toString().toLowerCase();

    final children =
        int.tryParse(client['children']?.toString() ?? '0') ?? 0;

    if (marital.contains('married') && children > 0) {
      return 'Married with Kids';
    }

    if (marital.contains('married')) {
      return 'Married';
    }

    if (children > 0) {
      return 'Has Kids';
    }

    return 'No Kids';
  }

  @override
  Widget build(BuildContext context) {
    final clients = widget.clients;

    return CrmCard(
      height: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle(
            title: 'Brief Client Information',
            icon: Icons.psychology_alt_outlined,
          ),
          const SizedBox(height: 14),

          if (clients.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No client intelligence for today.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: controller,
                      itemCount: clients.length,
                      onPageChanged: (index) {
                        setState(() {
                          currentIndex = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        final client = clients[index];
                        final relationshipScore = client['relationship_score'] ?? 40;
                        final relationshipStatus = client['relationship_status'] ?? 'At Risk';
                        final risk = client['risk'] ?? 'Not recorded';
                        final color = riskColor(risk.toString());
                        final ageTag = ageSegment(client['age']);
                        final family = familyTag(client);

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: const Color(0xFFEEF2FF),
                                      child: Text(
                                        (client['name'] ?? '?')[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Color(0xFF4F46E5),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 12),

                                    Expanded(
                                      child: Text(
                                        client['name'] ?? 'Unnamed Client',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),

                                    const Spacer(),

                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        ClientTag(
                                          icon: Icons.cake_outlined,
                                          label: '${client['age'] ?? '-'} yrs',
                                        ),
                                        ClientTag(
                                          icon: Icons.work_outline,
                                          label: ageTag,
                                        ),
                                        ClientTag(
                                          icon: Icons.family_restroom_outlined,
                                          label: family,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                InfoSection(
                                  children: [
                                    InfoLine(label: 'Purpose', value: client['purpose'] ?? '-'),
                                    InfoLine(label: 'Concern', value: client['concern'] ?? '-'),
                                    InfoLine(label: 'Personality', value: client['personality'] ?? '-'),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                ActionRecommendations(
                                  actions: client['action'] ?? '',
                                ),

                                const SizedBox(height: 12),

                                RelationshipScoreBox(
                                  score: relationshipScore,
                                  status: relationshipStatus,
                                ),

                                const SizedBox(height: 12),

                                SizedBox(
                                  width: double.infinity,
                                  height: 42,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => MeetingUpdateScreen(
                                            preselectedClient: client,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.edit_note),
                                    label: const Text('Update After Meeting'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  if (clients.length > 1) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: currentIndex == 0
                              ? null
                              : () {
                                  controller.previousPage(
                                    duration:
                                        const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                  );
                                },
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(
                          '${currentIndex + 1} / ${clients.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        IconButton(
                          onPressed: currentIndex == clients.length - 1
                              ? null
                              : () {
                                  controller.nextPage(
                                    duration:
                                        const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                  );
                                },
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class CompactCalendarPanel extends StatelessWidget {
  final DateTime selectedDate;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> selectedEvents;
  final String Function(int) monthName;
  final bool Function(DateTime, DateTime) isSameDate;
  final List<Map<String, dynamic>> Function(DateTime) eventsForDate;
  final Function(DateTime) onDateSelected;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final Function(int) onMonthChanged;

  const CompactCalendarPanel({
    super.key,
    required this.selectedDate,
    required this.events,
    required this.selectedEvents,
    required this.monthName,
    required this.isSameDate,
    required this.eventsForDate,
    required this.onMonthChanged,
    required this.onDateSelected,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateTime(selectedDate.year, selectedDate.month + 1, 0).day;
    final firstDayOfMonth =
        DateTime(selectedDate.year, selectedDate.month, 1);
    final startOffset = firstDayOfMonth.weekday - 1;

    return CrmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle(
            title: 'Calendar',
            icon: Icons.calendar_month_outlined,
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              IconButton(
                onPressed: () => onMonthChanged(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${monthName(selectedDate.month)} ${selectedDate.year}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onMonthChanged(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),

          const SizedBox(height: 16),

          const Row(
            children: [
              CalendarDayLabel('Mon'),
              CalendarDayLabel('Tue'),
              CalendarDayLabel('Wed'),
              CalendarDayLabel('Thu'),
              CalendarDayLabel('Fri'),
              CalendarDayLabel('Sat'),
              CalendarDayLabel('Sun'),
            ],
          ),

          const SizedBox(height: 10),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: daysInMonth + startOffset,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              if (index < startOffset) return const SizedBox();

              final day = index - startOffset + 1;
              final date = DateTime(
                selectedDate.year,
                selectedDate.month,
                day,
              );

              final selected = isSameDate(date, selectedDate);
              final dayEvents = eventsForDate(date);

              return GestureDetector(
                onTap: () => onDateSelected(date),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF4F46E5)
                          : dayEvents.isNotEmpty
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 6),

                      for (final event in dayEvents.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF4F46E5),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  '${event['time'] ?? ''} ${event['purpose'] ?? event['name'] ?? 'Event'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    height: 1.1,
                                    color: selected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (dayEvents.length > 3)
                        Text(
                          '+${dayEvents.length - 3} more',
                          style: TextStyle(
                            fontSize: 10,
                            color: selected ? Colors.white70 : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 18),

          Text(
            'Selected: ${selectedDate.day} ${monthName(selectedDate.month)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 10),

          if (selectedEvents.isEmpty)
            const EmptyCard(text: 'No events for selected date.')
          else
            Column(
              children: [
                for (final event in selectedEvents)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              event['time'] ?? '',
                              style: const TextStyle(
                                color: Color(0xFF4F46E5),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: Text(
                            '${event['name'] ?? 'Client'} • ${event['purpose'] ?? 'Meeting'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Color(0xFFEF4444),
                          ),
                          onPressed: () async {
                            await onDelete(event);
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class PanelTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const PanelTitle({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4F46E5)),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const InfoLine({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class CalendarDayLabel extends StatelessWidget {
  final String label;

  const CalendarDayLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class CrmCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? height;

  const CrmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
}

class EmptyCard extends StatelessWidget {
  final String text;

  const EmptyCard({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return CrmCard(
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }
}

// To show the tags of ages group
class ClientTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const ClientTag({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Color(0xFF4F46E5),
          ),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Color(0xFF4F46E5),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class RelationshipScoreBox extends StatelessWidget {
  final int score;
  final String status;

  const RelationshipScoreBox({
    super.key,
    required this.score,
    required this.status,
  });

  Color get scoreColor {
    if (score >= 80) return const Color(0xFF10B981);
    if (score >= 55) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scoreColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scoreColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.favorite_rounded, color: scoreColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Relationship Score',
                  style: TextStyle(
                    color: scoreColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$status relationship',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          Text(
            '$score%',
            style: TextStyle(
              color: scoreColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class InfoSection extends StatelessWidget {
  final List<Widget> children;

  const InfoSection({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class ActionRecommendations extends StatelessWidget {
  final String actions;

  const ActionRecommendations({
    super.key,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final items = actions
        .split(';')
        .where((e) => e.trim().isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFCD34D),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: Color(0xFFF59E0B),
              ),
              SizedBox(width: 8),
              Text(
                'Recommended Actions',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.trim()),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}