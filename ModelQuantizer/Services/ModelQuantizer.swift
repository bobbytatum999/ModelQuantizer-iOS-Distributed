//
//  ModelQuantizer.swift
//  ModelQuantizer
//
//  Compatibility facade over QuantizationEngine.
//

import Foundation
import Combine

@MainActor
final class ModelQuantizer: ObservableObject {
    static let shared = ModelQuantizer()

    @Published var status: QuantizationStatus = .idle
    @Published var currentModel: HFModel?
    @Published var quantizationHistory: [QuantizationJob] = []

    private let engine = QuantizationEngine.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        bindEngine()
        refreshHistory()
    }

    func quantize(
        model: HFModel,
        to quantization: QuantizationType,
        contextLength: Int? = nil,
        useGPU: Bool = true
    ) {
        currentModel = model
        engine.quantize(
            model: model,
            to: quantization,
            contextLength: contextLength ?? model.recommendedContextLength,
            useGPU: useGPU
        )
    }

    func cancel() {
        engine.cancel()
    }

    func getQuantizedModels() -> [QuantizedModel] {
        engine.getQuantizedModels()
    }

    func deleteQuantizedModel(_ model: QuantizedModel) {
        try? engine.deleteQuantizedModel(model)
        refreshHistory()
    }

    private func bindEngine() {
        engine.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                guard let self else { return }
                self.status = newStatus
                switch newStatus {
                case .completed, .failed, .idle:
                    self.refreshHistory()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func refreshHistory() {
        quantizationHistory = engine.getQuantizationHistory()
    }
}
