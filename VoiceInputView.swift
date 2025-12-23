// Create a new file: VoiceInputView.swift
import SwiftUI
import Speech

struct VoiceInputView: View {
    @Binding var text: String
    @State private var isRecording = false
    @State private var recognizedText = ""
    @State private var audioEngine = AVAudioEngine()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @State private var isPermissionDenied = false
    
    var body: some View {
        VStack {
            HStack {
                TextField("Text", text: $text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(isRecording)
                
                Button(action: toggleRecording) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .foregroundColor(isRecording ? .red : .blue)
                        .font(.title)
                }
                .disabled(isPermissionDenied)
            }
            
            if isRecording {
                Text("Listening...")
                    .foregroundColor(.blue)
                    .padding(.top, 5)
            }
            
            if isPermissionDenied {
                Text("Speech recognition permission denied")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            requestSpeechAuthorization()
        }
    }
    
    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status != .authorized {
                    self.isPermissionDenied = true
                }
            }
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        
        recognizedText = ""
        
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            Logger.error(error, message: "Failed to set up audio session", category: .app)
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            Logger.error("Unable to create speech recognition request", category: .app)
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.recognizedText = result.bestTranscription.formattedString
                self.text = self.recognizedText
            }
            
            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                self.isRecording = false
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
               inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                   self.recognitionRequest?.append(buffer)
               }
               
               audioEngine.prepare()
               
               do {
                   try audioEngine.start()
                   isRecording = true
               } catch {
                   Logger.error(error, message: "Audio engine failed to start", category: .app)
               }
           }
           
           private func stopRecording() {
               if isRecording {
                   audioEngine.stop()
                   recognitionRequest?.endAudio()
                   isRecording = false
               }
           }
       }
