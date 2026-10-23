import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

const String kDefaultModel = 'gemini-3.5-flash';

const String kSystemPrompt = '''
तिमी एक नेपाली सहायक हौ। सधैं देवनागरी नेपालीमा छोटो र मिलनसार जवाफ देऊ।
प्रयोगकर्ताले कुनै काम गर्न भन्यो भने action भर। केवल JSON फर्काऊ, अरू केही होइन:
{"reply":"...","action":"none|open_app|call|search","target":"..."}
- open_app को target: facebook, whatsapp, youtube, instagram मध्ये एक
- call को target: फोन नम्बर
- search को target: खोज्ने शब्द
- कुनै काम छैन भने action "none" र target "" राख।
''';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'मेरो सहायक',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const ChatPage(),
      );
}

class Msg {
  final bool me;
  final String text;
  Msg(this.me, this.text);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _controller = TextEditingController();
  final List<Msg> _msgs = [];
  final List<Map<String, dynamic>> _history = [];
  String _apiKey = '';
  String _model = kDefaultModel;
  bool _sttReady = false;
  bool _listening = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('api_key') ?? '';
    _model = prefs.getString('model') ?? kDefaultModel;
    _sttReady = await _stt.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
    );
    await _tts.setLanguage('ne-NP');
    await _tts.setSpeechRate(0.45);
    if (mounted) setState(() {});
  }

  Future<void> _saveSettings(String key, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', key.trim());
    await prefs.setString('model', model.trim());
    setState(() {
      _apiKey = key.trim();
      _model = model.trim().isEmpty ? kDefaultModel : model.trim();
      _history.clear();
    });
  }

  void _openSettings() {
    final keyC = TextEditingController(text: _apiKey);
    final modelC = TextEditingController(text: _model);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('सेटिङ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyC,
              decoration: const InputDecoration(labelText: 'Gemini API Key'),
            ),
            TextField(
              controller: modelC,
              decoration: const InputDecoration(labelText: 'मोडेलको नाम'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveSettings(keyC.text, modelC.text);
              Navigator.pop(context);
            },
            child: const Text('सेभ गर्नुहोस्'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleListen() async {
    if (!_sttReady) {
      _add(false, 'माइक्रोफोन अनुमति चाहिन्छ।');
      return;
    }
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(
      localeId: 'ne_NP',
      onResult: (r) {
        _controller.text = r.recognizedWords;
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          _send(r.recognizedWords);
        }
      },
    );
  }

  void _add(bool me, String text) {
    setState(() => _msgs.add(Msg(me, text)));
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    if (_apiKey.isEmpty) {
      _openSettings();
      return;
    }
    _controller.clear();
    _add(true, text);
    setState(() => _busy = true);
    try {
      final result = await _ask(text);
      final reply = (result['reply'] ?? '').toString();
      _add(false, reply);
      await _tts.speak(reply);
      await _doAction(
        (result['action'] ?? 'none').toString(),
        (result['target'] ?? '').toString(),
      );
    } catch (e) {
      final safe = e
          .toString()
          .replaceAll(RegExp(r'key=[^&\s]+'), 'key=***');
      _add(false, 'केही समस्या आयो: $safe');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>> _ask(String text) async {
    _history.add({
      'role': 'user',
      'parts': [
        {'text': text}
      ]
    });
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey',
    );
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': kSystemPrompt}
          ]
        },
        'contents': _history,
        'generationConfig': {'responseMimeType': 'application/json'},
      }),
    );
    if (res.statusCode != 200) {
      _history.removeLast();
      final body = utf8.decode(res.bodyBytes);
      final short = body.length > 400 ? body.substring(0, 400) : body;
      throw 'मोडेल: $_model, कोड ${res.statusCode}\n$short';
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final parts = data['candidates'][0]['content']['parts'] as List;
    final out = parts.map((p) => p['text'] ?? '').join();
    _history.add({
      'role': 'model',
      'parts': [
        {'text': out}
      ]
    });
    return jsonDecode(out) as Map<String, dynamic>;
  }

  Future<void> _doAction(String action, String target) async {
    if (action == 'open_app') {
      const schemes = {
        'facebook': 'fb://feed',
        'whatsapp': 'whatsapp://send',
        'youtube': 'vnd.youtube://',
        'instagram': 'instagram://app',
      };
      const web = {
        'facebook': 'https://facebook.com',
        'whatsapp': 'https://web.whatsapp.com',
        'youtube': 'https://youtube.com',
        'instagram': 'https://instagram.com',
      };
      final key = target.toLowerCase();
      final scheme = schemes[key];
      if (scheme == null) return;
      final ok = await launchUrl(Uri.parse(scheme),
          mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(Uri.parse(web[key]!),
            mode: LaunchMode.externalApplication);
      }
    } else if (action == 'call' && target.isNotEmpty) {
      await launchUrl(Uri.parse('tel:$target'));
    } else if (action == 'search' && target.isNotEmpty) {
      await launchUrl(
        Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(target)}'),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('मेरो सहायक'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _msgs.length,
              itemBuilder: (_, i) {
                final m = _msgs[i];
                return Align(
                  alignment:
                      m.me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 300),
                    decoration: BoxDecoration(
                      color: m.me ? Colors.teal.shade700 : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(m.text, style: const TextStyle(fontSize: 16)),
                  ),
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton.filled(
                  onPressed: _toggleListen,
                  icon: Icon(_listening ? Icons.stop : Icons.mic),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'यहाँ लेख्नुहोस् वा माइक थिच्नुहोस्...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _send,
                  ),
                ),
                IconButton(
                  onPressed: () => _send(_controller.text),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
