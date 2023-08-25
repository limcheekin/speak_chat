import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:keep_screen_on/keep_screen_on.dart';
import 'package:audio_session/audio_session.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

final Logger _logger = Logger('MyApp');
const defaultLocaleLanguage = 'en';
const defaultLocaleCountry = 'US';
const defaultLocale = '${defaultLocaleLanguage}_$defaultLocaleCountry';
const defaultLocaleId = '$defaultLocaleLanguage-$defaultLocaleCountry';

void main() async {
  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Prevent sleep
  KeepScreenOn.turnOn();

  //initializeDateFormatting();
  Intl.defaultLocale = defaultLocale;

  // Locale and language settings (fixed in Info.plist on iOS)
  Intl.withLocale(defaultLocaleLanguage, () => runApp(const MyApp()));
}

class SettingView extends StatefulWidget {
  const SettingView({super.key});

  @override
  State<SettingView> createState() => _SettingViewState();
}

class _SettingViewState extends State<SettingView> {
  String _selectedItemMy = "error";
  String _selectedItemBot = "error";
  final List<String> _items = ["error"];
  final FlutterTts tts = FlutterTts();
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();

    Future(() async {
      prefs = await SharedPreferences.getInstance();

      List voices = await tts.getVoices;

      _items.clear();
      for (var item in voices) {
        var map = item as Map<Object?, Object?>;
        if (map["locale"]
            .toString()
            .toLowerCase()
            .contains(defaultLocaleLanguage)) {
          _logger.info(map["name"]);
          _items.add(map["name"].toString());
        }
      }
      if (_items.isNotEmpty) {
        _selectedItemMy = prefs.getString("voice_me") ?? _items[0];
        _selectedItemBot = prefs.getString("voice_robot") ?? _items[0];
      }

      // Reflect dropdown
      setState(() {});
    });
  }

  Future<void> _changeVoice(String voiceName, String who, bool speak) async {
    prefs.setString("voice_$who", voiceName);

    if (!speak) {
      return;
    }

    await tts.stop();
    await tts.setVoice({'name': voiceName, 'locale': defaultLocaleId});

    await tts.speak("$who voice has been set");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Setting"),
      ),
      body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('My Voice'),
        DropdownButton<String>(
          value: _selectedItemMy,
          items: _items
              .map((String list) =>
                  DropdownMenuItem(value: list, child: Text(list)))
              .toList(),
          onChanged: (String? value) {
            setState(() {
              _selectedItemMy = value!;
              _changeVoice(_selectedItemMy, "my", true);
            });
          },
        ),
        const Divider(height: 100),
        const Text('Bot Voice'),
        DropdownButton<String>(
          value: _selectedItemBot,
          items: _items
              .map((String list) =>
                  DropdownMenuItem(value: list, child: Text(list)))
              .toList(),
          onChanged: (String? value) {
            setState(() {
              _selectedItemBot = value!;
              _changeVoice(_selectedItemBot, "bot", true);
            });
          },
        ),
      ])),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speak Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Speak Chat'),

      // Locale and language settings (fixed in Info.plist on iOS)
      localizationsDelegates: const [
        // localizations delegate to add
        //AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Locale and language settings (fixed in Info.plist on iOS)
      supportedLocales: const [
        Locale(defaultLocaleLanguage, defaultLocaleCountry)
      ],
      locale: const Locale(defaultLocaleLanguage, defaultLocaleCountry),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String lastWords = '';

  List<Object> chatMessages = [];
  final FlutterTts tts = FlutterTts();
  late SharedPreferences prefs;
  var inputTextcontroller = TextEditingController();
  ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    Future(() async {
      prefs = await SharedPreferences.getInstance();

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    });

    Future(() async {
      // Set to output sound from speaker
      await tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.defaultToSpeaker]);

      // Add to queue (Android only)
      if (Platform.isAndroid) {
        tts.setQueueMode(1);
      }

      // Set speaking speed
      await tts.setPitch(0.9);
      await tts.setSpeechRate(0.6);
    });

    // Open settings screen
    Future(() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SettingView()),
      );
    });
  }

  String _getVoiceName(String type) {
    return (type == "user"
            ? prefs.getString("voice_me")
            : prefs.getString("voice_robot")) ??
        "";
  }

  // Speak
  Future<void> _speach(dynamic item) async {
    // Stop and play
    await tts.stop();
    await tts.setVoice(
        {'name': _getVoiceName(item["role"]), 'locale': defaultLocaleId});

    await tts.speak(item["content"]);
  }

  // Start voice input
  _speak() {
    Future(() async {
      // Stop playback
      await tts.stop();
    });

    // Clear input
    setState(() {
      lastWords = "";
    });

    showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return const SpeechDialog();
      },
    ).then((value) {
      _logger.info("end dialog!");

      setState(() {
        if (value != null) {
          lastWords = value;
        }
      });

      _ai();
    });
  }

  // Clear messages
  Future<void> _cleanMessage() async {
    setState(() {
      chatMessages.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Deleted messages'),
    ));
  }

  // ChatGPT
  Future<void> _ai() async {
    _logger.info("_ai");

    // Skip if no input
    if (lastWords == "") {
      return;
    }

    // Scroll to bottom
    scrollController.jumpTo(scrollController.position.maxScrollExtent);

    // Stop and play
    await tts.stop();
    await tts
        .setVoice({'name': _getVoiceName("user"), 'locale': defaultLocaleId});
    await tts.speak(lastWords);

    // Add send message
    chatMessages.add({"role": "user", "content": lastWords});

    setState(() {
      inputTextcontroller.clear();

      FocusScopeNode currentFocus = FocusScope.of(context);
      if (!currentFocus.hasPrimaryFocus) {
        currentFocus.unfocus();
      }
    });

    // Add current date and time and duplicate
    List<Object> chatMessagesClone = [
      {
        "role": "user",
        "content": DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())
      },
      ...chatMessages
    ];

    final openaiApiKey = dotenv.get("OPENAI_API_KEY");
    final openaiApiBase =
        dotenv.get("OPENAI_API_BASE", fallback: "https://api.openai.com/v1");
    Uri url = Uri.parse("$openaiApiBase/chat/completions");
    Map<String, String> headers = {
      'Content-type': 'application/json',
      "Authorization": "Bearer $openaiApiKey"
    };
    String body = json.encode({
      "frequency_penalty": 0,
      "max_tokens": 512,
      "messages": chatMessagesClone,
      "model": "gpt-3.5-turbo",
      "presence_penalty": 0,
      "stream": true,
      "temperature": 0.7,
      "top_p": 1
    });

    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = body;
    request.followRedirects = false;

    final response = await request.send();

    if (response.statusCode != 200) {
      setState(() {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Communication error occurred ${response.statusCode}"),
        ));
      });

      return;
    }

    _logger.info(response.statusCode);

// Add received message
    chatMessages.add({"role": "assistant", "content": ""});
    setState(() {
      chatMessages = chatMessages;
    });

    var receiveMsg = "";
    var receiveMsgSpeak = "";
    var receiveDone = false;

    await for (final message in response.stream.transform(utf8.decoder)) {
      message.split("\n").forEach((msg) {
        if (!msg.startsWith("data: ")) {
          return;
        }

        var jsonMsg = msg.replaceFirst(RegExp("^data: "), "");

        if (jsonMsg == "[DONE]") {
          return;
        }

        final data = json.decode(jsonMsg);

        var content = data["choices"][0]["delta"]["content"];
        if (content == null) {
          return;
        }

        receiveMsg += content;

        receiveMsgSpeak += content;

        // When not finished yet
        if (!receiveDone) {
          // Minimum check so as not to start speaking with small text
          if (receiveMsgSpeak.length > 50) {
            var stopIndex = receiveMsgSpeak.indexOf(RegExp("、|。|\n"), 50);
            if (stopIndex > 0) {
              var speackMsg = receiveMsgSpeak.substring(0, stopIndex);
              receiveMsgSpeak = receiveMsgSpeak.substring(
                  stopIndex + 1, receiveMsgSpeak.length);

              () async {
                // Speak received message
                await tts.setVoice({
                  'name': _getVoiceName("robot"),
                  'locale': defaultLocaleId
                });
                await tts.speak(speackMsg);
              }();
            }
          }
        }

        // Set text to last added data
        dynamic item = chatMessages[chatMessages.length - 1];
        item["content"] = receiveMsg;
        chatMessages[chatMessages.length - 1] = item;

        setState(() {
          chatMessages = chatMessages;

          // Scroll to bottom
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        });
      });
    }

    receiveDone = true;

    // Scroll to bottom
    scrollController.jumpTo(scrollController.position.maxScrollExtent);

    // Speak remaining received messages
    await tts
        .setVoice({'name': _getVoiceName("robot"), 'locale': defaultLocaleId});
    await tts.speak(receiveMsgSpeak);
  }

  // change text input
  void _handleText(String e) {
    setState(() {
      lastWords = e;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingView()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: chatMessages
                          .map((dynamic item) => (GestureDetector(
                              onTap: () {
                                _speach(item);
                              },
                              child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item["role"] == "user"
                                              ? "Me  :"
                                              : "Bot :",
                                          style: TextStyle(
                                            color: item["role"] == "user"
                                                ? Colors.blue
                                                : Colors
                                                    .green, // Set text color to blue
                                          ),
                                        ),
                                        Expanded(
                                            child: Text(
                                          item["content"],
                                          softWrap: true,
                                        ))
                                      ])))))
                          .toList())),
            ),
          ),
          Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 10),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color.fromARGB(255, 0, 149, 255),
                      child: IconButton(
                        onPressed: _cleanMessage,
                        icon: const Icon(Icons.cleaning_services),
                        iconSize: 18,
                        color: const Color.fromARGB(255, 255, 255, 255),
                      ),
                    ),
                  ),
                  Expanded(
                      child: TextFormField(
                    controller: inputTextcontroller,
                    enabled: true,
                    obscureText: false,
                    maxLines: null,
                    onChanged: _handleText,
                    decoration: InputDecoration(
                      suffixIcon: IconButton(
                        onPressed: _speak,
                        icon: const Icon(Icons.mic),
                      ),
                    ),
                  )),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color.fromARGB(255, 0, 149, 255),
                    child: IconButton(
                      onPressed: _ai,
                      icon: const Icon(Icons.send),
                      iconSize: 18,
                      color: const Color.fromARGB(255, 255, 255, 255),
                    ),
                  )
                ],
              ))
        ],
      ),
    );
  }
}

class SpeechDialog extends StatefulWidget {
  const SpeechDialog({Key? key}) : super(key: key);

  @override
  SpeechDialogState createState() => SpeechDialogState();
}

class SpeechDialogState extends State<SpeechDialog> {
  String lastStatus = "";
  String lastError = "";
  String lastWords = "";
  stt.SpeechToText speech = stt.SpeechToText();
  ScrollController scrollController = ScrollController();
  double soundLevel = 0;

  @override
  void initState() {
    super.initState();

    Future(() async {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    });

    Future(() async {
      // Initialize speech
      bool available =
          await speech.initialize(onError: (SpeechRecognitionError error) {
        if (!mounted) {
          return;
        }
        setState(() {
          lastError = '${error.errorMsg} - ${error.permanent}';
        });
      }, onStatus: (String status) {
        if (!mounted) {
          return;
        }
        setState(() {
          lastStatus = status;
          _logger.info(status);

          // Scroll to bottom
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        });
      });

      if (available) {
        speech.listen(
            onResult: (SpeechRecognitionResult result) {
              if (!mounted) {
                return;
              }

              setState(() {
                lastWords = result.recognizedWords;
              });
            },
            onSoundLevelChange: (level) {
              if (!mounted) {
                return;
              }

              setState(() {
                if (lastStatus != "listening") {
                  // TODO: On iOS, the recording ready sound does not play, so I want to play it, but it does not play in speech.listen state (vibration also no good)
                }
                lastStatus = "listening";
                soundLevel = level * -1;
              });
            },
            localeId: defaultLocaleId);
      } else {
        _logger.info("The user has denied the use of speech recognition.");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Center(
          child: Text(lastStatus == "done"
              ? "Finished"
              : lastStatus == "listening"
                  ? "Listening"
                  : "Preparing $lastStatus")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 100,
            child: SingleChildScrollView(
              controller: scrollController,
              child: Text(
                lastWords,
                style: const TextStyle(color: Colors.cyan),
              ),
            ),
          ),
          CircleAvatar(
            radius: 20 + soundLevel,
            backgroundColor: lastStatus == "listening"
                ? const Color.fromARGB(255, 0, 149, 255)
                : const Color.fromARGB(255, 128, 128, 128),
            child: IconButton(
              onPressed: () {
                Navigator.of(context).pop(lastWords);
              },
              icon: const Icon(Icons.mic),
              iconSize: 18 + soundLevel,
              color: const Color.fromARGB(255, 255, 255, 255),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Perform necessary cleanup
    super.dispose();

    speech.stop();
  }
}
