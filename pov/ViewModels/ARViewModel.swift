import Foundation
import Combine
import SwiftUI

class ARViewModel: ObservableObject {
    @Published var arManager: ARManager
    @Published var poetryViewModel: PoetryViewModel
    @Published var recorderService: RecorderService
    @Published var showSavedToast = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("🟡 [ARViewModel] init started")
        self.arManager = ARManager()
        print("🟡 [ARViewModel] ARManager created")
        self.poetryViewModel = PoetryViewModel()
        print("🟡 [ARViewModel] PoetryViewModel created")
        self.recorderService = RecorderService()
        print("🟡 [ARViewModel] RecorderService created")
        
        // Connect recorder with ARManager so it can receive frames and words
        self.arManager.attachRecorder(self.recorderService)
        // Provide poetry view model for video compositing (matches UI exactly)
        self.recorderService.poetryViewModel = self.poetryViewModel
        // Video saved callback -> show toast
        self.recorderService.onVideoSaved = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                withAnimation(.easeInOut(duration: 1.5)) {
                    self.showSavedToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    withAnimation(.easeInOut(duration: 1.5)) {
                        self?.showSavedToast = false
                    }
                }
            }
        }
        
        setupBindings()
        print("🟡 [ARViewModel] init completed")
    }
    
    private func setupBindings() {
        // Listen for word selection/unselection from ARManager
        arManager.onWordSelected = { [weak self] word in
            self?.poetryViewModel.captureWord(word)
        }
        
        arManager.onWordUnselected = { [weak self] word in
            self?.poetryViewModel.uncaptureWord(word)
        }
        
        // CRITICAL: Forward ARManager's objectWillChange to ARViewModel
        // This ensures SwiftUI updates when floatingWords/keptWords change
        arManager.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Also forward poetryViewModel changes
        poetryViewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Also forward recorderService changes
        recorderService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
