import SwiftUI

struct RecordButtonView: View {
    @ObservedObject var recorder: RecorderService
    
    var body: some View {
        VStack(spacing: 8) {
            // Recording duration
            if recorder.isRecording {
                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
            }
            
            // Record button
            Button(action: {
                if recorder.isRecording {
                    recorder.stopRecording()
                } else {
                    recorder.startRecording()
                }
            }) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 64, height: 64)
                    
                    // Inner circle / square
                    if recorder.isRecording {
                        // Stop: Red square
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red)
                            .frame(width: 24, height: 24)
                    } else {
                        // Record: Red circle
                        Circle()
                            .fill(Color.red)
                            .frame(width: 52, height: 52)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
            
            // Label
            Text(recorder.isRecording ? "停止" : "录制")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct RecordButtonView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            RecordButtonView(recorder: RecorderService())
        }
    }
}

