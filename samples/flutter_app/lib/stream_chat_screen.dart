import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

const String _apiKey = String.fromEnvironment('API_KEY');

class StreamChatScreen extends StatefulWidget {
  const StreamChatScreen({super.key, required this.title});

  final String title;

  @override
  State<StreamChatScreen> createState() => _StreamChatScreenState();
}

class _StreamChatScreenState extends State<StreamChatScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: const ChatWidget(apiKey: _apiKey),
    );
  }
}

class ChatWidget extends StatefulWidget {
  const ChatWidget({
    required this.apiKey,
    super.key,
  });

  final String apiKey;

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  late final GenerativeModel _model;
  late final ChatSession _chat;

  final FocusNode _textFieldFocus = FocusNode();

  final List<({Image? image, String? text, bool fromUser})> _generatedContent =
      <({Image? image, String? text, bool fromUser})>[];

  bool _loading = false;

  bool get loading => _loading;

  set loading(bool value) {
    if (_loading != value && mounted) {
      _loading = value;
      setState(() {});
    }
  }

  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _model = GenerativeModel(
      model: 'gemini-1.5-flash-latest',
      apiKey: widget.apiKey,
      safetySettings: [
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
      ]
    );
    _chat = _model.startChat();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(
          milliseconds: 750,
        ),
        curve: Curves.easeOutCirc,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textFieldDecoration = InputDecoration(
      contentPadding: const EdgeInsets.all(15),
      hintText: 'Enter a prompt...',
      border: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(14),
        ),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(14),
        ),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _apiKey.isNotEmpty
                ? ListView.builder(
                    controller: _scrollController,
                    itemBuilder: (context, idx) {
                      final content = _generatedContent[idx];
                      return MessageWidget(
                        text: content.text,
                        image: content.image,
                        isFromUser: content.fromUser,
                      );
                    },
                    itemCount: _generatedContent.length,
                  )
                : ListView(
                    children: const [
                      Text(
                        'No API key found. Please provide an API Key using '
                        "'--dart-define' to set the 'API_KEY' declaration.",
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 25,
              horizontal: 15,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    autofocus: true,
                    focusNode: _textFieldFocus,
                    decoration: textFieldDecoration,
                    controller: _textController,
                    onSubmitted: _sendChatMessage,
                  ),
                ),
                const SizedBox.square(dimension: 15),
                IconButton(
                  onPressed: !loading
                      ? () async {
                          _sendImagePrompt(_textController.text);
                        }
                      : null,
                  icon: Icon(
                    Icons.image,
                    color: loading
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (!loading)
                  IconButton(
                    onPressed: () {
                      _sendChatMessage(_textController.text);
                    },
                    icon: Icon(
                      Icons.send,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                else
                  IconButton(
                    onPressed: () {
                      _stopGenerated();
                      loading = false;
                    },
                    icon: Icon(
                      Icons.stop_circle_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendImagePrompt(String message) async {
    loading = true;

    ByteData catBytes = await rootBundle.load('assets/images/cat.jpg');
    ByteData sconeBytes = await rootBundle.load('assets/images/scones.jpg');
    final content = [
      Content.multi([
        TextPart(message),
        // The only accepted mime types are image/*.
        DataPart('image/jpeg', catBytes.buffer.asUint8List()),
        DataPart('image/jpeg', sconeBytes.buffer.asUint8List()),
      ])
    ];
    _generatedContent.add((
      image: Image.asset("assets/images/cat.jpg"),
      text: message,
      fromUser: true
    ));
    _generatedContent.add((
      image: Image.asset("assets/images/scones.jpg"),
      text: null,
      fromUser: true
    ));

    final stream = _model.generateContentStream(content);
    _updateFromStream(stream);
  }

  void _sendChatMessage(String message) {
    loading = true;

    _textController.clear();
    _generatedContent.add((image: null, text: message, fromUser: true));

    final stream = _chat.sendMessageStream(
      Content.text(message),
    );

    _updateFromStream(stream);
  }

  Future<void> _updateFromStream(
    Stream<GenerateContentResponse> contentStream,
  ) async {
    _generatedContent.add((image: null, text: "", fromUser: false));
    setState(() {});

    updateGenerateText(String text) {
      final last = _generatedContent.removeLast();
      _generatedContent.add((
        image: null,
        text: "${last.text}$text",
        fromUser: false,
      ));
      setState(() {
        _scrollDown();
      });
    }

    await _stopGenerated();
    _subscription = contentStream.listen(
      (event) {
        final text = event.text ?? "";
        updateGenerateText(text);
      },
      onError: (e, s) {
        print(e);
        print(s);
        _showError(e.toString());
        loading = false;
      },
      onDone: () {
        print("_updateFromStream onDone");
        _textController.clear();
        loading = false;
        _textFieldFocus.requestFocus();
      },
    );
  }

  Future<void> _stopGenerated() async {
    print("_stopGenerated called");
    await _subscription?.cancel();
    _subscription = null;
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Something went wrong'),
          content: SingleChildScrollView(
            child: SelectableText(message),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            )
          ],
        );
      },
    );
  }
}

class MessageWidget extends StatelessWidget {
  const MessageWidget({
    super.key,
    this.image,
    this.text,
    required this.isFromUser,
  });

  final Image? image;
  final String? text;
  final bool isFromUser;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          isFromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: isFromUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 15,
              horizontal: 20,
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                if (text case final text?) MarkdownBody(data: text),
                if (image case final image?) image,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
