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
        self.arManager = ARManager()
        self.poetryViewModel = PoetryViewModel()
        self.recorderService = RecorderService()
        
        // Connections
        arManager.attachRecorder(recorderService)
        poetryViewModel.arManager = arManager
        recorderService.poetryViewModel = poetryViewModel
        
        // Bindings
        arManager.onWordSelected = { [weak self] word in
            self?.poetryViewModel.captureWord(word)
        }
        
        // ⚠️ 修复点：删除了 arManager.onWordUnselected 的绑定
        
        arManager.onContextUpdated = { context in
            print("Context updated: \(context.visualContexts.count) visuals")
        }
        
        recorderService.onVideoSaved = { [weak self] in
            DispatchQueue.main.async {
                withAnimation { self?.showSavedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { self?.showSavedToast = false }
                }
            }
        }
        
        // Refresh UI
        arManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        poetryViewModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        recorderService.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }
}
