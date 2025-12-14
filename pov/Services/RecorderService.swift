import Foundation
import AVFoundation
import Photos
import ReplayKit
import UIKit

class RecorderService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var error: String?
    
    // References
    weak var arManager: ARManager?
    weak var poetryViewModel: PoetryViewModel?
    var onVideoSaved: (() -> Void)?
    
    // AVFoundation recording
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var videoOutputURL: URL?
    private var isWritingStarted = false
    private var sessionStartTime: CMTime?
    
    private var recordingTimer: Timer?
    private var startTime: Date?
    
    // ReplayKit
    private let recorder = RPScreenRecorder.shared()
    
    override init() {
        super.init()
    }
    
    var canRecord: Bool { recorder.isAvailable }
    
    // MARK: Recording Control
    func startRecording() {
        guard !isRecording else { return }
        
        // Ensure Microphone is enabled
        recorder.isMicrophoneEnabled = true
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoName = "pov_\(Int(Date().timeIntervalSince1970)).mp4"
        videoOutputURL = documentsPath.appendingPathComponent(videoName)
        
        if let url = videoOutputURL { try? FileManager.default.removeItem(at: url) }
        
        guard setupVideoWriter() else {
            error = "Failed to setup video writer"
            return
        }
        
        print("🎬 Starting Screen Recording...")
        
        recorder.startCapture { [weak self] sampleBuffer, bufferType, error in
            guard let self = self else { return }
            if let error = error {
                print("❌ ReplayKit Error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.stopRecording() } // Safety stop
                return
            }
            
            self.processSampleBuffer(sampleBuffer, type: bufferType)
            
        } completionHandler: { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Failed to start capture: \(error.localizedDescription)")
                    self.error = error.localizedDescription
                } else {
                    self.isRecording = true
                    self.isWritingStarted = false
                    self.sessionStartTime = nil
                    self.startTime = Date()
                    self.startTimer()
                    print("🎬 Recording started successfully")
                }
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        print("🎬 Stopping recording...")
        stopTimer()
        isRecording = false
        
        recorder.stopCapture { [weak self] error in
            if let error = error {
                print("❌ Stop capture error: \(error)")
            }
            self?.finishWriting()
        }
    }
    
    // MARK: Setup Writer
    private func setupVideoWriter() -> Bool {
        guard let url = videoOutputURL else { return false }
        
        do {
            videoWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
            
            // Get screen size for video settings
            let screenSize = UIScreen.main.bounds.size
            let scale = UIScreen.main.scale
            let width = Int(screenSize.width * scale)
            let height = Int(screenSize.height * scale)
            
            // Video Settings
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            self.videoInput = videoInput
            
            // Audio Settings (Mic + App Audio)
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            self.audioInput = audioInput
            
            if let writer = videoWriter {
                if writer.canAdd(videoInput) { writer.add(videoInput) }
                if writer.canAdd(audioInput) { writer.add(audioInput) }
            }
            
            return true
        } catch {
            print("❌ Failed to create video writer: \(error)")
            return false
        }
    }
    
    // MARK: Frame Processing
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        guard let writer = videoWriter, writer.status != .failed else { return }
        
        // Start session on first video frame
        if !isWritingStarted && type == .video {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
            sessionStartTime = timestamp
            isWritingStarted = true
        }
        
        guard isWritingStarted, writer.status == .writing else { return }
        
        if type == .video, let input = videoInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        } else if type == .audioMic, let input = audioInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
        // Note: .audioApp is app internal audio, we could mix it if needed, but for now just mic
    }
    
    // MARK: Finish Writing
    private func finishWriting() {
        guard let writer = videoWriter else { return }
        
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        writer.finishWriting { [weak self] in
            guard let self = self, let url = self.videoOutputURL else { return }
            
            DispatchQueue.main.async {
                if writer.status == .completed {
                    print("🎬 Video saved to: \(url)")
                    self.saveToPhotoLibrary(url: url)
                } else if let error = writer.error {
                    print("❌ Video writing failed: \(error)")
                    self.error = error.localizedDescription
                }
                
                self.cleanup()
            }
        }
    }
    
    private func cleanup() {
        videoWriter = nil
        videoInput = nil
        audioInput = nil
        isWritingStarted = false
        sessionStartTime = nil
    }
    
    // MARK: Save
    private func saveToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("🎬 Video saved to Photo Library!")
                        try? FileManager.default.removeItem(at: url)
                        self.onVideoSaved?()
                    }
                }
            }
        }
    }
    
    // MARK: Timer
    private func startTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let startTime = self?.startTime else { return }
            self?.recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
    }
}

// Remove AVCaptureAudioDataOutputSampleBufferDelegate conformance as ReplayKit handles it
