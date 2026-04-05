//
//  QuantizeViewModel.swift
//  ModelQuantizer
//
//  ViewModel for the Quantize tab with real Hugging Face API integration.
//

import Foundation
import Combine

@MainActor
class QuantizeViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var models: [HFModel] = []
    @Published var filteredModels: [HFModel] = []
    @Published var selectedModel: HFModel?
    @Published var selectedQuantization: QuantizationType = .q4_1
    @Published var customContextLength: Int = 4096
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    @Published var quantizationStatus: QuantizationStatus = .idle
    @Published var progress: Double = 0
    @Published var currentStage: String = ""
    
    @Published var deviceProfile: DeviceCapabilityProfile?
    @Published var recommendedSettings: QuantizationRecommendation?
    @Published var useGPU = true
    @Published var useNeuralEngine = true
    @Published var useFlashAttention = false
    @Published var useMemoryMapping = true
    
    private var cancellables = Set<AnyCancellable>()
    private let scanner = DeviceScanner.shared
    private let quantizer = QuantizationEngine.shared
    private let suggester = SettingsSuggester.shared
    private let hfAPI = HuggingFaceAPI.shared
    
    // Search debounce
    private var searchTask: Task<Void, Never>?
    private let searchDebounceInterval: TimeInterval = 0.5
    
    init() {
        setupBindings()
        loadPopularModels()
        updateDeviceProfile()
    }
    
    private func setupBindings() {
        // Device profile updates
        scanner.$currentProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.deviceProfile = profile
                self?.updateRecommendations()
            }
            .store(in: &cancellables)
        
        // Quantization status updates
        quantizer.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.quantizationStatus = status
                self?.updateProgress(from: status)
            }
            .store(in: &cancellables)
        
        quantizer.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progress = progress
            }
            .store(in: &cancellables)
        
        quantizer.$currentStage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stage in
                self?.currentStage = stage
            }
            .store(in: &cancellables)
        
        // Search query with debounce
        $searchQuery
            .debounce(for: .seconds(searchDebounceInterval), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }
    
    private func updateProgress(from status: QuantizationStatus) {
        // Progress is now directly from the quantizer
    }
    
    private func updateDeviceProfile() {
        deviceProfile = scanner.currentProfile
        updateRecommendations()
    }
    
    private func updateRecommendations() {
        guard let profile = deviceProfile else { return }
        recommendedSettings = scanner.getRecommendedQuantization()
        
        // Auto-select recommended quantization
        applyRecommendedSettings()
    }
    
    private func loadPopularModels() {
        models = []
        filteredModels = []
        Task {
            await fetchPopularModelsFromAPI()
        }
    }
    
    private func fetchPopularModelsFromAPI() async {
        await MainActor.run {
            isSearching = true
        }
        defer {
            Task { @MainActor in
                isSearching = false
            }
        }

        do {
            let popularModels = try await hfAPI.searchModels(
                query: "",
                limit: 20,
                filter: ModelFilter(sortBy: .downloads)
            )
            
            await MainActor.run {
                self.models = popularModels
                self.filterLocalModels(query: self.searchQuery)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load models from Hugging Face: \(error.localizedDescription)"
                self.showError = true
                self.models = []
                self.filteredModels = []
            }
        }
    }
    
    private func performSearch(query: String) {
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            filteredModels = models
            return
        }
        
        searchTask = Task { @MainActor in
            isSearching = true
            defer { isSearching = false }
            
            // First, filter local models
            filterLocalModels(query: query)
            
            // Then search Hugging Face API
            do {
                let apiModels = try await hfAPI.searchModels(
                    query: query,
                    limit: 30
                )
                
                // Merge results, avoiding duplicates
                let existingIds = Set(self.models.map { $0.modelId })
                let newModels = apiModels.filter { !existingIds.contains($0.modelId) }
                
                self.models.append(contentsOf: newModels)
                self.filterLocalModels(query: query)
                
            } catch let error as HFAPIError  {
                if case .rateLimited = error {
                    self.errorMessage = "Rate limit reached. Please try again later."
                } else {
                    self.errorMessage = error.localizedDescription
                }
                self.showError = true
            } catch {
                // Don't show error for search failures - local results are still available
                print("API search failed: \(error)")
            }
        }
    }
    
    private func filterLocalModels(query: String) {
        if query.isEmpty {
            filteredModels = models
        } else {
            let lowerQuery = query.lowercased()
            filteredModels = models.filter { model in
                model.name.lowercased().contains(lowerQuery) ||
                model.description.lowercased().contains(lowerQuery) ||
                model.modelId.lowercased().contains(lowerQuery) ||
                model.tags.contains(where: { $0.lowercased().contains(lowerQuery) })
            }
        }
        
        // Sort by relevance (downloads as proxy for popularity)
        filteredModels.sort { $0.downloads > $1.downloads }
    }
    
    func searchModels() {
        performSearch(query: searchQuery)
    }
    
    func selectModel(_ model: HFModel) {
        selectedModel = model
        
        // Update recommendations based on model size
        if let profile = deviceProfile {
            recommendedSettings = suggester.suggestQuantization(for: profile, modelSize: model.sizeBytes)
            applyRecommendedSettings(modelContextLimit: model.recommendedContextLength)
        }
    }
    
    func startQuantization() {
        guard let model = selectedModel else { return }
        
        guard model.architecture.supportedQuantizations.contains(selectedQuantization) else {
            errorMessage = "\(selectedQuantization.rawValue) is not supported for \(model.architecture.rawValue) in this build."
            showError = true
            return
        }
        
        // Check if model requires authentication
        if model.modelId.hasPrefix("meta-llama/") && HuggingFaceAPI.shared.getAuthToken() == nil {
            errorMessage = "This model requires Hugging Face authentication. Please add your token in Settings."
            showError = true
            return
        }
        
        quantizer.quantize(
            model: model,
            to: selectedQuantization,
            contextLength: customContextLength,
            useGPU: useGPU,
            useNeuralEngine: useNeuralEngine,
            useFlashAttention: useFlashAttention,
            useMemoryMapping: useMemoryMapping
        )
    }
    
    func cancelQuantization() {
        quantizer.cancel()
    }
    
    func getPerformanceEstimate() -> PerformanceEstimate? {
        guard let profile = deviceProfile,
              let model = selectedModel else { return nil }
        
        let settings = InferenceSettings(
            contextLength: customContextLength,
            batchSize: recommendedSettings?.batchSize ?? 1,
            threadCount: recommendedSettings?.threadCount ?? 4,
            useGPU: recommendedSettings?.useGPU ?? true,
            useNeuralEngine: recommendedSettings?.useNeuralEngine ?? false,
            gpuLayers: recommendedSettings?.offloadLayers ?? 0,
            memoryLimit: recommendedSettings?.memoryLimit ?? 4_000_000_000,
            useFlashAttention: recommendedSettings?.useFlashAttention ?? false,
            useMemoryMapping: true,
            temperature: 0.7,
            topP: 0.9,
            topK: 40,
            repeatPenalty: 1.1,
            maxTokens: 2048,
            quantizationType: selectedQuantization
        )
        
        let params = Double(model.parameters.replacingOccurrences(of: "B", with: "")) ?? 7.0
        return suggester.getPerformanceEstimate(for: profile, settings: settings, modelParameters: params)
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func quantizationTypeFromBits(_ bits: Int) -> QuantizationType {
        switch bits {
        case 4: return .q4_1
        case 5: return .q8_0
        case 6: return .q8_0
        case 8: return .q8_0
        case 16: return .fp16
        default: return .q4_1
        }
    }
    
    private func applyRecommendedSettings(modelContextLimit: Int? = nil) {
        guard let rec = recommendedSettings else { return }
        selectedQuantization = quantizationTypeFromBits(rec.bits)
        if let modelContextLimit {
            customContextLength = min(rec.contextLength, modelContextLimit)
        } else {
            customContextLength = rec.contextLength
        }
        useGPU = rec.useGPU
        useNeuralEngine = rec.useNeuralEngine
        useFlashAttention = rec.useFlashAttention
        useMemoryMapping = true
    }
}

// MARK: - Hugging Face API Token Extension

extension HuggingFaceAPI {
    func getAuthToken() -> String? {
        UserDefaults.standard.string(forKey: "hf_auth_token")
    }
}
