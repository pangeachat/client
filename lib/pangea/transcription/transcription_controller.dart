// accepts a streaming audio
// gets text from the audio
// when the audio is done, it calls the choreographer for tokens
// these are packaged into a SpeechToTextModel


import 'package:fluffychat/pangea/toolbar/models/speech_to_text_models.dart';

class TranscriptionController {
  final String? authToken;

  // transcription stream
  late Stream<String> transcriptionStream;

  TranscriptionController({this.authToken}){
    initialize();
  }


  Future<void> initialize() async {
    //initialize the transcription controller
    // get the authToken from the server
  }

  Stream<String> openStream(){
    //open the stream to start recording

    return transcriptionStream;
  }


  Future<SpeechToTextModel> closeStream(){
    //close the stream to stop recording

    // calling the tokenize service from choroegrapher
  }
