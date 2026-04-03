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
        if let rec = recommendedSettings {
            selectedQuantization = quantizationTypeFromBits(rec.bits)
            customContextLength = rec.contextLength
        }
    }
    
    private func loadPopularModels() {
        // Load a curated list of popular models while we fetch from API
        models = [
            HFModel(
                modelId: "microsoft/Phi-3-mini-4k-instruct",
                name: "Phi-3 Mini 4K",
                description: "Microsoft's efficient 3.8B parameter model with excellent performance",
                parameters: "3.8B",
                architecture: .phi,
                downloadURL: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct/resolve/main/model.safetensors"),
                sizeBytes: 7_600_000_000,
                recommendedContextLength: 4096,
                tags: ["instruct", "chat", "efficient"],
                downloads: 2_500_000,
                likes: 8500
            ),
            HFModel(
                modelId: "meta-llama/Meta-Llama-3.1-8B-Instruct",
                name: "Llama 3.1 8B Instruct",
                description: "Meta's latest 8B parameter instruction-tuned model",
                parameters: "8B",
                architecture: .llama,
                downloadURL: URL(string: "https://huggingface.co/meta-llama/Meta-Llama-3.1-8B-Instruct/resolve/main/model.safetensors"),
                sizeBytes: 16_000_000_000,
                recommendedContextLength: 8192,
                tags: ["instruct", "chat", "meta"],
                downloads: 5_000_000,
                likes: 15000
            ),
            HFModel(
                modelId: "mistralai/Mistral-7B-Instruct-v0.3",
                name: "Mistral 7B Instruct v0.3",
                description: "Mistral's powerful 7B instruction model",
                parameters: "7B",
                architecture: .mistral,
                downloadURL: URL(string: "https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.3/resolve/main/model.safetensors"),
                sizeBytes: 14_000_000_000,
                recommendedContextLength: 32768,
                tags: ["instruct", "chat", "long-context"],
                downloads: 8_000_000,
                likes: 22000
            ),
            HFModel(
                modelId: "google/gemma-2-2b-it",
                name: "Gemma 2 2B IT",
                description: "Google's lightweight 2B instruction model",
                parameters: "2B",
                architecture: .gemma,
                downloadURL: URL(string: "https://huggingface.co/google/gemma-2-2b-it/resolve/main/model.safetensors"),
                sizeBytes: 4_000_000_000,
                recommendedContextLength: 8192,
                tags: ["instruct", "chat", "lightweight"],
                downloads: 1_200_000,
                likes: 5600
            ),
            HFModel(
                modelId: "Qwen/Qwen2.5-7B-Instruct",
                name: "Qwen2.5 7B Instruct",
                description: "Alibaba's Qwen2.5 with improved reasoning",
                parameters: "7B",
                architecture: .qwen2,
                downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-7B-Instruct/resolve/main/model.safetensors"),
                sizeBytes: 15_000_000_000,
                recommendedContextLength: 32768,
                tags: ["instruct", "chat", "multilingual"],
                downloads: 3_000_000,
                likes: 9800
            ),
            HFModel(
                modelId: "HuggingFaceTB/SmolLM2-1.7B-Instruct",
                name: "SmolLM2 1.7B Instruct",
                description: "Hugging Face's tiny but capable model",
                parameters: "1.7B",
                architecture: .llama,
                downloadURL: URL(string: "https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct/resolve/main/model.safetensors"),
                sizeBytes: 3_400_000_000,
                recommendedContextLength: 8192,
                tags: ["instruct", "chat", "tiny"],
                downloads: 800_000,
                likes: 4200
            )
        ]
        
        filteredModels = models
        
        // Also fetch from API for more up-to-date results
        Task {
            await fetchPopularModelsFromAPI()
        }
    }
    
    private func fetchPopularModelsFromAPI() async {
        do {
            let popularModels = try await hfAPI.searchModels(
                query: "",
                limit: 20,
                filter: ModelFilter(sortBy: .downloads)
            )
            
            await MainActor.run {
                // Merge with existing models, avoiding duplicates
                let existingIds = Set(self.models.map { $0.modelId })
                let newModels = popularModels.filter { !existingIds.contains($0.modelId) }
                self.models.append(contentsOf: newModels)
                self.filterLocalModels(query: self.searchQuery)
            }
        } catch {
            // Silently fail - we already have fallback models
            print("Failed to fetch from API: \(error)")
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
                self.errorMessage = "Rate limit reached. Please try again later."
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
            if let rec = recommendedSettings {
                selectedQuantization = quantizationTypeFromBits(rec.bits)
                customContextLength = min(rec.contextLength, model.recommendedContextLength)
            }
        }
    }
    
    func startQuantization() {
        guard let model = selectedModel else { return }
        
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard osMajor >= 18 else {
            errorMessage = "iOS/iPadOS 18 or later is required for on-device quantization."
            showError = true
            return
        }
        
        if let profile = deviceProfile {
            let maxRecommended = profile.deviceClass.recommendedMaxModelSize
            if model.sizeBytes > maxRecommended {
                errorMessage = "Model is too large for this device class (\(profile.deviceClass.rawValue)). Recommended max is \(formatBytes(maxRecommended))."
                showError = true
                return
            }
        }
        
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
            useGPU: recommendedSettings?.useGPU ?? true
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
}

// MARK: - Hugging Face API Token Extension

extension HuggingFaceAPI {
    func getAuthToken() -> String? {
        UserDefaults.standard.string(forKey: "hf_auth_token")
    }
}
