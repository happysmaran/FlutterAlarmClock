// ignore_for_file: library_private_types_in_public_api, avoid_print, unnecessary_string_escapes

import 'dart:convert';
import 'package:alarmclock/settings_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

// Main Function
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AndroidAlarmManager.initialize();
  runApp(const AlarmClockApp());
}

// ThemeNotifier class for managing theme state
class ThemeNotifier extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  ThemeData get themeData {
    return _isDarkMode ? ThemeData.dark() : ThemeData.light();
  }
}

// Main App Widget
class AlarmClockApp extends StatelessWidget {
  const AlarmClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: Consumer<ThemeNotifier>(
        builder: (context, themeNotifier, _) {
          return MaterialApp(
            title: 'Alarm Clock',
            theme: themeNotifier.themeData,
            home: const AlarmListScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

// Alarm Class with JSON serialization
class Alarm {
  final String id;
  TimeOfDay time;
  List<bool> days;
  bool isSet;
  Color color;
  String name;
  String? audioPath;
  String audioURL;

  Alarm({
    required this.id,
    required this.time,
    required this.days,
    this.isSet = false,
    this.color = Colors.blue,
    this.name = '',
    this.audioPath,
    this.audioURL = '', //only for audio URLs
  });

  // Convert Alarm to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'time': {
          'hour': time.hour,
          'minute': time.minute,
        },
        'days': days,
        'isSet': isSet,
        'color': color.value,
        'name': name,
        'audioPath': audioPath,
        'audioURL': audioURL,
      };

  // Create Alarm from JSON
  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
        id: json['id'],
        time: TimeOfDay(
            hour: json['time']['hour'], minute: json['time']['minute']),
        days: List<bool>.from(json['days']),
        isSet: json['isSet'],
        color: Color(json['color']),
        name: json['name'],
        audioPath: json['audioPath'],
        audioURL: json['audioURL'],
      );
}

// Storage Helper Class for saving/loading alarms
class StorageHelper {
  static const _alarmsKey = 'alarms';

  static Future<void> saveAlarms(List<Alarm> alarms) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = alarms.map((alarm) => jsonEncode(alarm.toJson())).toList();
    await prefs.setStringList(_alarmsKey, jsonList);
  }

  static Future<List<Alarm>> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_alarmsKey) ?? [];
    return jsonList.map((json) => Alarm.fromJson(jsonDecode(json))).toList();
  }
}

// Alarm List Screen
class AlarmListScreen extends StatefulWidget {
  const AlarmListScreen({super.key});

  @override
  _AlarmListScreenState createState() => _AlarmListScreenState();
}

class _AlarmListScreenState extends State<AlarmListScreen> {
  List<Alarm> _alarms = [];
  Timer? _timer;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _startTimer();
    _loadAlarms();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initializeNotifications() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin, // For iOS
      macOS: initializationSettingsDarwin, // For macOS
    );
    _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkAlarms();
    });
  }

  void _checkAlarms() {
    final now = DateTime.now();
    final nowTimeOfDay = TimeOfDay.fromDateTime(now);
    final currentDay = now.weekday - 1; // Monday = 0, ..., Sunday = 6

    for (var alarm in _alarms) {
      if (alarm.isSet &&
          alarm.days[currentDay] &&
          nowTimeOfDay.hour == alarm.time.hour &&
          nowTimeOfDay.minute == alarm.time.minute) {
        _ringAlarm(alarm);
      }
    }
  }

  void _ringAlarm(Alarm alarm) async {
    final now = DateTime.now();
    final scheduledDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      alarm.time.hour,
      alarm.time.minute,
    );

    _scheduleAlarm(scheduledDateTime, alarm.id.hashCode);
  }

  void _scheduleAlarm(DateTime scheduledDateTime, int alarmId) {
    AndroidAlarmManager.oneShotAt(
      scheduledDateTime,
      alarmId,
      _showNotification,
      exact: true,
      wakeup: true,
    );
  }

  void _showNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'alarm_channel_id',
      'Alarm Channel',
      channelDescription: 'Channel for alarm notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.show(
      0,
      'Alarm Ringing',
      'It\'s time!',
      platformChannelSpecifics,
    );
  }

  void _navigateToAlarmDetail(Alarm alarm) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlarmDetailScreen(alarm: alarm),
      ),
    );
    if (result != null && result is Alarm) {
      setState(() {
        final index = _alarms.indexWhere((a) => a.id == result.id);
        if (index != -1) {
          _alarms[index] = result; // Update existing alarm
        } else {
          _alarms.add(result); // Add new alarm
        }
        _saveAlarms(); // Save updated list
      });
    }
  }

  void _deleteAlarm(Alarm alarm) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this alarm?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () {
                setState(() {
                  _alarms.removeWhere((a) => a.id == alarm.id);
                  _saveAlarms(); // Save updated list
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadAlarms() async {
    _alarms = await StorageHelper.loadAlarms();
    setState(() {});
  }

  Future<void> _saveAlarms() async {
    await StorageHelper.saveAlarms(_alarms);
  }

  String _getSelectedDays(Alarm alarm) {
    List<String> selectedDayNames = [];
    for (int i = 0; i < alarm.days.length; i++) {
      if (alarm.days[i]) {
        selectedDayNames.add(_getDayName(i));
      }
    }
    return selectedDayNames.isEmpty
        ? 'No days selected'
        : selectedDayNames.join(', ');
  }

  String _getDayName(int index) {
    switch (index) {
      case 0:
        return 'Monday';
      case 1:
        return 'Tuesday';
      case 2:
        return 'Wednesday';
      case 3:
        return 'Thursday';
      case 4:
        return 'Friday';
      case 5:
        return 'Saturday';
      case 6:
        return 'Sunday';
      default:
        return '';
    }
  }

  Color _getTextColor(Color backgroundColor) {
    // Calculate luminance of the background color
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alarm Clock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _navigateToAlarmDetail(
              Alarm(
                id: DateTime.now().toString(), // Unique ID
                time: const TimeOfDay(hour: 4, minute: 20),
                days: List.generate(7, (index) => false),
                color: Colors.blue,
                name: '',
              ),
            ),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: _alarms.length,
        itemBuilder: (context, index) {
          final alarm = _alarms[index];
          return Card(
            color: alarm.color,
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            elevation: 4.0,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16.0),
              title: Text(
                '${alarm.name.isEmpty ? 'Alarm' : alarm.name} - ${alarm.time.hour}:${alarm.time.minute.toString().padLeft(2, '0')} - ${_getSelectedDays(alarm)}',
                style: TextStyle(color: _getTextColor(alarm.color)),
              ),
              onTap: () => _navigateToAlarmDetail(alarm),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      alarm.isSet ? Icons.toggle_on : Icons.toggle_off,
                      color: alarm.isSet ? Colors.blue : Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        alarm.isSet = !alarm.isSet;
                        if (alarm.isSet) {
                          print(
                              'Alarm set for ${alarm.time.hour}:${alarm.time.minute}');
                        } else {
                          print(
                              'Alarm canceled for ${alarm.time.hour}:${alarm.time.minute}');
                        }
                        _saveAlarms(); // Save updated list
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteAlarm(alarm),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Alarm Detail Screen
class AlarmDetailScreen extends StatefulWidget {
  final Alarm alarm;

  const AlarmDetailScreen({required this.alarm, super.key});

  @override
  _AlarmDetailScreenState createState() => _AlarmDetailScreenState();
}

class _AlarmDetailScreenState extends State<AlarmDetailScreen> {
  late TimeOfDay _alarmTime;
  late List<bool> _selectedDays;
  late Color _alarmColor;
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  String? _audioPath;

  @override
  void initState() {
    super.initState();
    _alarmTime = widget.alarm.time;
    _selectedDays = List.from(widget.alarm.days);
    _alarmColor = widget.alarm.color;
    _nameController = TextEditingController(text: widget.alarm.name);
    _urlController = TextEditingController(text: widget.alarm.audioURL);
    _audioPath = widget.alarm.audioPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.isNotEmpty) {
      _audioPath = result.files.single.path!; // Get the selected file path
    } else {}
  }

  Future<void> _selectAlarmTime(BuildContext context) async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: _alarmTime,
    );
    if (pickedTime != null && pickedTime != _alarmTime) {
      setState(() {
        _alarmTime = pickedTime;
      });
    }
  }

  Future<void> _selectDays(BuildContext context) async {
    final List<bool>? result = await showDialog<List<bool>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Days'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(7, (index) {
                return CheckboxListTile(
                  title: Text(_getDayName(index)),
                  value: _selectedDays[index],
                  onChanged: (bool? value) {
                    setState(() {
                      _selectedDays[index] = value ?? false;
                    });
                  },
                );
              }),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Done'),
              onPressed: () => Navigator.of(context).pop(_selectedDays),
            ),
          ],
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedDays = result;
      });
    }
  }

  void _pickColor() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pick a Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: _alarmColor,
              onColorChanged: (Color color) {
                setState(() {
                  print(color);
                  _alarmColor = color;
                });
              },
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              //_alarmColor=_tempAlarmColor;
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Select'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  String _getDayName(int index) {
    switch (index) {
      case 0:
        return 'Monday';
      case 1:
        return 'Tuesday';
      case 2:
        return 'Wednesday';
      case 3:
        return 'Thursday';
      case 4:
        return 'Friday';
      case 5:
        return 'Saturday';
      case 6:
        return 'Sunday';
      default:
        return '';
    }
  }

  /*Color _getTextColor(Color backgroundColor) {
    // Calculate luminance of the background color
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }*/

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alarm Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              Navigator.pop(
                context,
                Alarm(
                  id: widget.alarm.id,
                  time: _alarmTime,
                  days: _selectedDays,
                  color: _alarmColor,
                  name: _nameController.text,
                  audioURL: _urlController.text,
                  audioPath: _audioPath,
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            ListTile(
                title: const Text('Alarm Time'),
                trailing: Text(_alarmTime.format(context)),
                onTap: () => _selectAlarmTime(context),
                shape: const Border(
                  bottom: BorderSide(),
                )),
            ListTile(
                title: const Text('Days'),
                //titleTextStyle: const TextStyle(color: Colors.black, fontSize: 16),
                trailing: Text(_selectedDays
                    .asMap()
                    .entries
                    .where((entry) => entry.value)
                    .map((entry) => _getDayName(entry.key))
                    .join(', ')),
                onTap: () => _selectDays(context),
                shape: const Border(
                  bottom: BorderSide(),
                )),
            ListTile(
                title: const Text('Color'),
                //titleTextStyle: const TextStyle(color: Colors.black, fontSize: 16),
                trailing: Container(
                  width: 24,
                  height: 24,
                  color: _alarmColor,
                ),
                onTap: _pickColor,
                shape: const Border(
                  bottom: BorderSide(),
                )),
            ListTile(
                title: const Text('Audio File'),
                //titleTextStyle: const TextStyle(color: Colors.black, fontSize: 16),
                trailing: Text(_audioPath?.split('/').last ?? 'None'),
                onTap: _pickAudioFile,
                shape: const Border(
                  bottom: BorderSide(),
                )),
            TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  prefixIcon: Text("   \Au\d\i\o\ \U\R\L  "),
                  prefixIconConstraints:
                      BoxConstraints(minWidth: 0, minHeight: 0),
                  //labelText: 'Audio URL',
                  contentPadding: EdgeInsets.symmetric(horizontal: 10.0),
                  //border: InputBorder.none,
                  //hintText: "Enter URL here"
                )),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                prefixIcon: Text("   \A\l\ar\m\ \N\a\m\e  "),
                prefixIconConstraints:
                    BoxConstraints(minWidth: 0, minHeight: 0),
                contentPadding: EdgeInsets.symmetric(horizontal: 10.0),
                border: InputBorder.none,
                //hintText: "Enter name here"
                //labelStyle: TextStyle(color: _alarmColor),
              ),
              //style: TextStyle(color: _alarmColor),
            ),
          ],
        ),
      ),
    );
  }
}
