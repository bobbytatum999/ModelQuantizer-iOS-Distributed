//
//  ModelQuantizer.swift
//  ModelQuantizer
//
//  Created by AI Assistant on 2026-03-31.
//

import Foundation
import Metal
import MetalPerformanceShaders
import Accelerate
import Compression

/// Represents a Hugging Face model to be quantized
struct HFModel: Identifiable, Codable, Equatable {
    let id: UUID
    let modelId: String
    let name: String
    let description: String
    let parameters: String
    let architecture: ModelArchitecture
    let downloadURL: URL?
    let sizeBytes: Int64
    let quantizationOptions: [QuantizationType]
    let recommendedContextLength: Int
    let tags: [String]
    let downloads: Int
    let likes: Int
    
    init(modelId: String, name: String, description: String, parameters: String, 
         architecture: ModelArchitecture, downloadURL: URL? = nil, sizeBytes: Int64 = 0,
         quantizationOptions: [QuantizationType] = QuantizationType.allCases,
         recommendedContextLength: Int = 4096, tags: [String] = [], downloads: Int = 0, likes: Int = 0) {
        self.id = UUID()
        self.modelId = modelId
        self.name = name
        self.description = description
        self.parameters = parameters
        self.architecture = architecture
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
        self.quantizationOptions = quantizationOptions
        self.recommendedContextLength = recommendedContextLength
        self.tags = tags
        self.downloads = downloads
        self.likes = likes
    }
}

enum ModelArchitecture: String, Codable, CaseIterable {
    case llama = "Llama"
    case mistral = "Mistral"
    case qwen2 = "Qwen2"
    case gemma = "Gemma"
    case phi = "Phi"
    case falcon = "Falcon"
    case gpt2 = "GPT-2"
    case bert = "BERT"
    case custom = "Custom"
    
    var supportedQuantizations: [QuantizationType] {
        switch self {
        case .llama, .mistral, .qwen2, .gemma, .phi:
            return [.q4_0, .q4_1, .q5_0, .q5_1, .q8_0, .fp16, .fp32]
        case .falcon, .gpt2:
            return [.q4_0, .q4_1, .q8_0, .fp16]
        case .bert:
            return [.q8_0, .fp16, .fp32]
        case .custom:
            return QuantizationType.allCases
        }
    }
}

enum QuantizationType: String, Codable, CaseIterable {
    case q2_K = "Q2_K"
    case q3_K_S = "Q3_K_S"
    case q3_K_M = "Q3_K_M"
    case q3_K_L = "Q3_K_L"
    case q4_0 = "Q4_0"
    case q4_1 = "Q4_1"
    case q4_K_S = "Q4_K_S"
    case q4_K_M = "Q4_K_M"
    case q5_0 = "Q5_0"
    case q5_1 = "Q5_1"
    case q5_K_S = "Q5_K_S"
    case q5_K_M = "Q5_K_M"
    case q6_K = "Q6_K"
    case q8_0 = "Q8_0"
    case fp16 = "F16"
    case fp32 = "F32"
    
    var bits: Double {
        switch self {
        case .q2_K: return 2.0
        case .q3_K_S, .q3_K_M, .q3_K_L: return 3.0
        case .q4_0, .q4_1, .q4_K_S, .q4_K_M: return 4.0
        case .q5_0, .q5_1, .q5_K_S, .q5_K_M: return 5.0
        case .q6_K: return 6.0
        case .q8_0: return 8.0
        case .fp16: return 16.0
        case .fp32: return 32.0
        }
    }
    
    var description: String {
        switch self {
        case .q2_K: return "2-bit (Smallest, Lowest Quality)"
        case .q3_K_S: return "3-bit Small (Aggressive compression)"
        case .q3_K_M: return "3-bit Medium (Balanced)"
        case .q3_K_L: return "3-bit Large (Better quality)"
        case .q4_0: return "4-bit Legacy (Fast)"
        case .q4_1: return "4-bit Legacy v2 (Better accuracy)"
        case .q4_K_S: return "4-bit K-Quants Small (Recommended)"
        case .q4_K_M: return "4-bit K-Quants Medium (Best 4-bit)"
        case .q5_0: return "5-bit Legacy (Good balance)"
        case .q5_1: return "5-bit Legacy v2 (Better)"
        case .q5_K_S: return "5-bit K-Quants Small (High quality)"
        case .q5_K_M: return "5-bit K-Quants Medium (Best 5-bit)"
        case .q6_K: return "6-bit (Near FP16 quality)"
        case .q8_0: return "8-bit (Excellent quality)"
        case .fp16: return "16-bit Float (Original quality)"
        case .fp32: return "32-bit Float (Maximum precision)"
        }
    }
    
    var compressionRatio: Double {
        return 32.0 / bits
    }
}

/// Quantization progress and status
enum QuantizationStatus: Equatable {
    case idle
    case downloading(progress: Double)
    case analyzing
    case quantizing(progress: Double, stage: String)
    case optimizing
    case validating
    case completed(outputURL: URL)
    case failed(error: String)
    
    static func == (lhs: QuantizationStatus, rhs: QuantizationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.downloading(let p1), .downloading(let p2)): return p1 == p2
        case (.analyzing, .analyzing): return true
        case (.quantizing(let p1, let s1), .quantizing(let p2, let s2)): return p1 == p2 && s1 == s2
        case (.optimizing, .optimizing): return true
        case (.validating, .validating): return true
        case (.completed(let u1), .completed(let u2)): return u1 == u2
        case (.failed(let e1), .failed(let e2)): return e1 == e2
        default: return false
        }
    }
}

/// Main model quantizer engine
@MainActor
class ModelQuantizer: ObservableObject {
    static let shared = ModelQuantizer()
    
    @Published var status: QuantizationStatus = .idle
    @Published var currentModel: HFModel?
    @Published var quantizationHistory: [QuantizationJob] = []
    
    private var quantizeTask: Task<Void, Never>?
    private let fileManager = FileManager.default
    private let metalDevice: MTLDevice?
    
    private var modelsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Models", isDirectory: true)
    }
    
    private init() {
        self.metalDevice = MTLCreateSystemDefaultDevice()
        createModelsDirectory()
        loadHistory()
    }
    
    // MARK: - Public Methods
    
    func quantize(model: HFModel, to quantization: QuantizationType, 
                  contextLength: Int? = nil, useGPU: Bool = true) {
        guard status == .idle else { return }
        
        currentModel = model
        quantizeTask?.cancel()
        
        quantizeTask = Task { [weak self] in
            await self?.performQuantization(model: model, quantization: quantization, 
                                           contextLength: contextLength, useGPU: useGPU)
        }
    }
    
    func cancel() {
        quantizeTask?.cancel()
        status = .idle
    }
    
    func getQuantizedModels() -> [QuantizedModel] {
        guard let contents = try? fileManager.contentsOfDirectory(at: modelsDirectory, 
                                                                  includingPropertiesForKeys: nil) else {
            return []
        }
        
        return contents.compactMap { url in
            guard url.pathExtension == "gguf" else { return nil }
            return try? QuantizedModel(from: url)
        }
    }
    
    func deleteQuantizedModel(_ model: QuantizedModel) {
        try? fileManager.removeItem(at: model.url)
        loadHistory()
    }
    
    // MARK: - Private Methods
    
    private func createModelsDirectory() {
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }
    
    private func loadHistory() {
        // Load from UserDefaults or local storage
        if let data = UserDefaults.standard.data(forKey: "quantizationHistory"),
           let history = try? JSONDecoder().decode([QuantizationJob].self, from: data) {
            quantizationHistory = history
        }
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(quantizationHistory) {
            UserDefaults.standard.set(data, forKey: "quantizationHistory")
        }
    }
    
    private func performQuantization(model: HFModel, quantization: QuantizationType, 
                                     contextLength: Int?, useGPU: Bool) async {
        let startTime = Date()
        
        do {
            // Step 1: Download model if needed
            let modelURL = try await downloadModel(model)
            
            // Step 2: Analyze model structure
            status = .analyzing
            let analysis = try await analyzeModel(at: modelURL)
            
            // Step 3: Perform quantization
            let outputURL = modelsDirectory.appendingPathComponent("\(model.modelId)_\(quantization.rawValue).gguf")
            
            try await performActualQuantization(
                inputURL: modelURL,
                outputURL: outputURL,
                analysis: analysis,
                quantization: quantization,
                contextLength: contextLength ?? model.recommendedContextLength,
                useGPU: useGPU
            )
            
            // Step 4: Validate output
            status = .validating
            try await validateQuantizedModel(at: outputURL)
            
            // Complete
            let job = QuantizationJob(
                id: UUID(),
                originalModel: model,
                quantizationType: quantization,
                outputURL: outputURL,
                outputSize: (try? fileManager.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0,
                startTime: startTime,
                endTime: Date(),
                contextLength: contextLength ?? model.recommendedContextLength
            )
            
            quantizationHistory.insert(job, at: 0)
            saveHistory()
            
            status = .completed(outputURL: outputURL)
            
        } catch {
            status = .failed(error: error.localizedDescription)
        }
    }
    
    private func downloadModel(_ model: HFModel) async throws -> URL {
        guard let downloadURL = model.downloadURL else {
            throw QuantizationError.noDownloadURL
        }
        
        let destination = modelsDirectory.appendingPathComponent("\(model.modelId).tmp")
        
        // Check if already downloaded
        if fileManager.fileExists(atPath: destination.path) {
            let attrs = try fileManager.attributesOfItem(atPath: destination.path)
            if let size = attrs[.size] as? Int64, size == model.sizeBytes {
                return destination
            }
        }
        
        // Download with progress
        let session = URLSession(configuration: .default)
        
        let (asyncBytes, response) = try await session.bytes(from: downloadURL)
        let totalBytes = response.expectedContentLength
        var downloadedBytes: Int64 = 0
        var lastProgress: Double = 0
        
        var fileHandle = try FileHandle(forWritingTo: destination)
        defer { try? fileHandle.close() }
        
        for try await byte in asyncBytes {
            fileHandle.write(Data([byte]))
            downloadedBytes += 1
            
            if totalBytes > 0 {
                let currentProgress = Double(downloadedBytes) / Double(totalBytes)
                if currentProgress - lastProgress > 0.01 {
                    lastProgress = currentProgress
                    await MainActor.run {
                        self.status = .downloading(progress: currentProgress)
                    }
                }
            }
        }
        
        return destination
    }
    
    private func analyzeModel(at url: URL) async throws -> ModelAnalysis {
        // Read model file and analyze structure
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        
        // Detect architecture and structure
        var architecture: ModelArchitecture = .custom
        var layerCount = 0
        var tensorCount = 0
        var totalParameters: Int64 = 0
        
        // Parse based on file format (safetensors, bin, etc.)
        if url.pathExtension == "safetensors" {
            // Parse safetensors format
            let analysis = try parseSafeTensors(data)
            architecture = analysis.architecture
            layerCount = analysis.layerCount
            tensorCount = analysis.tensorCount
            totalParameters = analysis.totalParameters
        } else if url.pathExtension == "bin" {
            // Parse PyTorch bin format
            let analysis = try parsePyTorchBin(data)
            architecture = analysis.architecture
            layerCount = analysis.layerCount
            tensorCount = analysis.tensorCount
            totalParameters = analysis.totalParameters
        }
        
        return ModelAnalysis(
            architecture: architecture,
            layerCount: layerCount,
            tensorCount: tensorCount,
            totalParameters: totalParameters,
            originalSize: Int64(data.count)
        )
    }
    
    private func parseSafeTensors(_ data: Data) throws -> ModelAnalysis {
        // SafeTensors format parsing
        // Header is JSON, followed by tensor data
        var architecture: ModelArchitecture = .custom
        var layerCount = 0
        var tensorCount = 0
        var totalParameters: Int64 = 0
        
        // Read header length (first 8 bytes, little-endian uint64)
        let headerLength = data.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self) }
        
        // Parse header JSON
        let headerData = data.dropFirst(8).prefix(Int(headerLength))
        if let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
            
            // Detect architecture from tensor names
            let tensorNames = header.keys
            if tensorNames.contains(where: { $0.contains("llama") || $0.contains("self_attn") }) {
                architecture = .llama
            } else if tensorNames.contains(where: { $0.contains("mistral") }) {
                architecture = .mistral
            } else if tensorNames.contains(where: { $0.contains("qwen") }) {
                architecture = .qwen2
            } else if tensorNames.contains(where: { $0.contains("gemma") }) {
                architecture = .gemma
            }
            
            // Count tensors and parameters
            for (key, value) in header {
                if let tensorInfo = value as? [String: Any],
                   let shape = tensorInfo["shape"] as? [Int] {
                    tensorCount += 1
                    let paramCount = shape.reduce(1, *)
                    totalParameters += Int64(paramCount)
                    
                    if key.contains("layers.") {
                        layerCount = max(layerCount, Int(key.components(separatedBy: "layers.").last?.components(separatedBy: ".").first ?? "0") ?? 0)
                    }
                }
            }
        }
        
        return ModelAnalysis(
            architecture: architecture,
            layerCount: layerCount,
            tensorCount: tensorCount,
            totalParameters: totalParameters,
            originalSize: Int64(data.count)
        )
    }
    
    private func parsePyTorchBin(_ data: Data) throws -> ModelAnalysis {
        // PyTorch pickle format parsing (simplified)
        // This would need a proper pickle parser for full support
        return ModelAnalysis(
            architecture: .custom,
            layerCount: 0,
            tensorCount: 0,
            totalParameters: 0,
            originalSize: Int64(data.count)
        )
    }
    
    private func performActualQuantization(inputURL: URL, outputURL: URL, 
                                          analysis: ModelAnalysis, quantization: QuantizationType,
                                          contextLength: Int, useGPU: Bool) async throws {
        
        let stages = ["Loading tensors", "Quantizing weights", "Building GGUF", "Writing output"]
        let totalStages = stages.count
        
        for (index, stage) in stages.enumerated() {
            try Task.checkCancellation()
            
            let progress = Double(index) / Double(totalStages)
            status = .quantizing(progress: progress, stage: stage)
            
            // Simulate work (in real implementation, this would be actual quantization)
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // Actual quantization would happen here
            if index == 1 {
                try await quantizeTensors(inputURL: inputURL, outputURL: outputURL, 
                                         analysis: analysis, quantization: quantization)
            }
        }
        
        status = .quantizing(progress: 1.0, stage: "Complete")
    }
    
    private func quantizeTensors(inputURL: URL, outputURL: URL, 
                                analysis: ModelAnalysis, quantization: QuantizationType) async throws {
        
        // Create GGUF file structure
        var ggufBuilder = GGUFBuilder()
        
        // Add metadata
        ggufBuilder.addMetadata(key: "general.architecture", value: .string(analysis.architecture.rawValue.lowercased()))
        ggufBuilder.addMetadata(key: "general.name", value: .string(currentModel?.name ?? "Unknown"))
        ggufBuilder.addMetadata(key: "general.quantization_version", value: .uint32(2))
        
        // Add tensor info
        // This would read actual tensors and quantize them
        
        // Write GGUF file
        let ggufData = try ggufBuilder.build()
        try ggufData.write(to: outputURL)
    }
    
    private func validateQuantizedModel(at url: URL) async throws {
        // Verify the quantized model is valid
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        
        // Check GGUF magic number
        let magic = data.prefix(4)
        guard magic == Data("GGUF".utf8) else {
            throw QuantizationError.invalidOutput
        }
        
        // Additional validation would go here
    }
}

// MARK: - Supporting Types

struct ModelAnalysis {
    let architecture: ModelArchitecture
    let layerCount: Int
    let tensorCount: Int
    let totalParameters: Int64
    let originalSize: Int64
}

struct QuantizationJob: Codable, Identifiable {
    let id: UUID
    let originalModel: HFModel
    let quantizationType: QuantizationType
    let outputURL: URL
    let outputSize: Int64
    let startTime: Date
    let endTime: Date
    let contextLength: Int
    
    var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
    
    var compressionRatio: Double {
        return Double(originalModel.sizeBytes) / Double(outputSize)
    }
}

struct QuantizedModel: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let quantization: QuantizationType
    let createdDate: Date
    
    init?(from url: URL) throws {
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        self.size = attrs[.size] as? Int64 ?? 0
        self.createdDate = attrs[.creationDate] as? Date ?? Date()
        
        // Detect quantization from filename
        let filename = url.lastPathComponent.lowercased()
        if let qType = QuantizationType.allCases.first(where: { filename.contains($0.rawValue.lowercased()) }) {
            self.quantization = qType
        } else {
            self.quantization = .q4_0
        }
    }
}

enum QuantizationError: Error, LocalizedError {
    case noDownloadURL
    case downloadFailed
    case invalidModelFormat
    case quantizationFailed
    case invalidOutput
    case insufficientMemory
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .noDownloadURL: return "No download URL provided for model"
        case .downloadFailed: return "Failed to download model"
        case .invalidModelFormat: return "Unsupported model format"
        case .quantizationFailed: return "Quantization process failed"
        case .invalidOutput: return "Generated model is invalid"
        case .insufficientMemory: return "Insufficient memory for quantization"
        case .cancelled: return "Quantization cancelled"
        }
    }
}

// MARK: - Integer to Data Extension

extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}

// MARK: - GGUF Builder

struct GGUFBuilder {
    enum MetadataValue {
        case uint32(UInt32)
        case uint64(UInt64)
        case int32(Int32)
        case int64(Int64)
        case float32(Float)
        case float64(Double)
        case bool(Bool)
        case string(String)
        case array([MetadataValue])
    }
    
    private var metadata: [(String, MetadataValue)] = []
    private var tensors: [(name: String, shape: [Int], data: Data)] = []
    
    mutating func addMetadata(key: String, value: MetadataValue) {
        metadata.append((key, value))
    }
    
    mutating func addTensor(name: String, shape: [Int], data: Data) {
        tensors.append((name, shape, data))
    }
    
    func build() throws -> Data {
        var data = Data()
        
        // Magic number
        data.append(Data("GGUF".utf8))
        
        // Version
        data.append(UInt32(3).littleEndianData)
        
        // Tensor count
        data.append(UInt64(tensors.count).littleEndianData)
        
        // Metadata count
        data.append(UInt64(metadata.count).littleEndianData)
        
        // Metadata
        for (key, value) in metadata {
            // Key length and string
            data.append(UInt64(key.utf8.count).littleEndianData)
            data.append(Data(key.utf8))
            
            // Value type and data
            switch value {
            case .uint32(let v):
                data.append(UInt32(4).littleEndianData) // type
                data.append(v.littleEndianData)
            case .uint64(let v):
                data.append(UInt32(5).littleEndianData)
                data.append(v.littleEndianData)
            case .string(let s):
                data.append(UInt32(8).littleEndianData)
                data.append(UInt64(s.utf8.count).littleEndianData)
                data.append(Data(s.utf8))
            default:
                break
            }
        }
        
        // Tensor info and data would follow
        
        return data
    }
}
