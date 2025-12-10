import Vision
import CoreML
import UIKit
import Combine

class CoreMLService {
    // Compile the custom MobileNetV2FP16 model once and reuse
    private lazy var visionModel: VNCoreMLModel? = {
        do {
            let model = try MobileNetV2FP16(configuration: MLModelConfiguration())
            return try VNCoreMLModel(for: model.model)
        } catch {
            print("❌ CoreMLService: Failed to load MobileNetV2FP16: \(error.localizedDescription)")
            return nil
        }
    }()
    
    // Reuse the request to avoid allocation overhead
    private lazy var visionRequest: VNCoreMLRequest? = {
        guard let model = visionModel else { return nil }
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            self?.handleClassification(request: request, error: error)
        }
        request.imageCropAndScaleOption = .centerCrop
        return request
    }()
    
    // Store promise to complete it from the callback
    private var currentPromise: ((Result<String, Error>) -> Void)?
    
    init() {
        print("✅ CoreMLService: Using MobileNetV2FP16.mlmodel")
    }
    
    /// Classify a CVPixelBuffer and return the top identifier
    func classify(image: CVPixelBuffer) -> AnyPublisher<String, Error> {
        return Future<String, Error> { [weak self] promise in
            guard let self = self else { return }
            
            // Perform heavy CoreML work on background queue
            DispatchQueue.global(qos: .userInitiated).async {
                guard let request = self.visionRequest else {
                    promise(.failure(NSError(domain: "CoreMLService",
                                             code: -2,
                                             userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])))
                    return
                }
                
                // Store promise for the callback
                // Note: This simple implementation assumes serial processing (one request at a time).
                // Since ARManager throttles calls (isProcessing flag), this is acceptable.
                // For concurrent requests, we'd need to pass the promise differently, e.g. using a closure in perform.
                self.currentPromise = promise
                
                let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .up)
                do {
                    try handler.perform([request])
                } catch {
                    print("❌ CoreML perform error: \(error.localizedDescription)")
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    private func handleClassification(request: VNRequest, error: Error?) {
        guard let promise = currentPromise else { return }
        
        if let error = error {
            print("❌ CoreML classify error: \(error.localizedDescription)")
            promise(.failure(error))
            return
        }
        
        guard let results = request.results as? [VNClassificationObservation],
              let topResult = results.first else {
            promise(.failure(NSError(domain: "CoreMLService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No results"])))
            return
        }
        
        // Return the top identifier (simplify to first comma term)
        let identifier = String(topResult.identifier.split(separator: ",").first ?? "unknown")
        print("🔍 MobileNetV2 detected: '\(identifier)' (confidence: \(String(format: "%.2f", topResult.confidence)))")
        promise(.success(identifier))
    }
}
