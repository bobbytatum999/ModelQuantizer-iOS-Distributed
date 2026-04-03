//
//  ModelTypes.swift
//  ModelQuantizer
//
//  Core model types for the app.
//

import Foundation

/// Represents a Hugging Face model
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
    
    init(
        modelId: String,
        name: String,
        description: String,
        parameters: String,
        architecture: ModelArchitecture,
        downloadURL: URL? = nil,
        sizeBytes: Int64 = 0,
        quantizationOptions: [QuantizationType] = QuantizationType.allCases,
        recommendedContextLength: Int = 4096,
        tags: [String] = [],
        downloads: Int = 0,
        likes: Int = 0
    ) {
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
    
    var defaultContextLength: Int {
        switch self {
        case .llama: return 8192
        case .mistral: return 32768
        case .qwen2: return 32768
        case .gemma: return 8192
        case .phi: return 4096
        case .falcon: return 2048
        case .gpt2: return 1024
        case .bert: return 512
        case .custom: return 4096
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
    
    var ggufFileType: UInt32 {
        switch self {
        case .fp32: return 0
        case .fp16: return 1
        case .q4_0: return 2
        case .q4_1: return 3
        case .q5_0: return 6
        case .q5_1: return 7
        case .q8_0: return 8
        default: return 2 // Default to Q4_0 for K-quants
        }
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
    
    var isActive: Bool {
        switch self {
        case .idle, .completed, .failed:
            return false
        default:
            return true
        }
    }
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
        return Double(originalModel.sizeBytes) / Double(max(outputSize, 1))
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

// MARK: - Hugging Face API Models

struct HFSearchResponse: Codable {
    let models: [HFAPIModel]
}

struct HFAPIModel: Codable {
    let id: String
    let modelId: String
    let author: String?
    let downloads: Int
    let likes: Int
    let tags: [String]
    let pipelineTag: String?
    let siblings: [HFSibling]?
    let cardData: HFModelCardData?
    let config: HFModelConfig?
    
    enum CodingKeys: String, CodingKey {
        case id
        case modelId = "modelId"
        case author
        case downloads
        case likes
        case tags
        case pipelineTag = "pipeline_tag"
        case siblings
        case cardData
        case config
    }
}

struct HFModelCardData: Codable {
    let description: String?
    let license: String?
    let language: [String]?
}

struct HFModelConfig: Codable {
    let architectures: [String]?
    let modelType: String?
    let torchDtype: String?
    
    enum CodingKeys: String, CodingKey {
        case architectures
        case modelType = "model_type"
        case torchDtype = "torch_dtype"
    }
}

struct HFSibling: Codable {
    let rfilename: String
}

// MARK: - Performance Estimate

struct PerformanceEstimate {
    let estimatedTokensPerSecond: Double
    let estimatedMemoryUsage: Int64
    let estimatedLoadTime: TimeInterval
    let recommendedBatchSize: Int
    let canUseGPU: Bool
    let canUseNeuralEngine: Bool
}

struct InferenceSettings {
    let contextLength: Int
    let batchSize: Int
    let threadCount: Int
    let useGPU: Bool
    let useNeuralEngine: Bool
    let gpuLayers: Int
    let memoryLimit: Int64
    let useFlashAttention: Bool
    let useMemoryMapping: Bool
    let temperature: Double
    let topP: Double
    let topK: Int
    let repeatPenalty: Double
    let maxTokens: Int
    let quantizationType: QuantizationType
}

enum QuantizationError: Error, LocalizedError {
    case noDownloadURL
    case noModelFiles
    case downloadFailed
    case invalidModelFormat
    case unsupportedVersion
    case quantizationFailed
    case invalidOutput
    case insufficientMemory
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDownloadURL: return "No download URL provided for model"
        case .noModelFiles: return "No model files found in repository"
        case .downloadFailed: return "Failed to download model files"
        case .invalidModelFormat: return "Invalid or unsupported model format"
        case .unsupportedVersion: return "Unsupported GGUF version"
        case .quantizationFailed: return "Quantization process failed"
        case .invalidOutput: return "Generated model file is invalid"
        case .insufficientMemory: return "Insufficient memory for quantization"
        case .cancelled: return "Quantization was cancelled"
        }
    }
}
