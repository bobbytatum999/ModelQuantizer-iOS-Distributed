//
//  HuggingFaceAPI.swift
//  ModelQuantizer
//
//  Real Hugging Face API integration for model search and download.
//

import Foundation
import Combine

/// Hugging Face API Service for model search and metadata
class HuggingFaceAPI: ObservableObject {
    static let shared = HuggingFaceAPI()
    
    private let baseURL = "https://huggingface.co/api"
    private let session: URLSession
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isSearching = false
    @Published var lastError: Error?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Model Search
    
    /// Search for models on Hugging Face Hub
    func searchModels(
        query: String,
        limit: Int = 50,
        filter: ModelFilter = ModelFilter()
    ) async throws -> [HFModel] {
        var components = URLComponents(string: "\(baseURL)/models")!
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "full", value: "true"),
            URLQueryItem(name: "config", value: "true")
        ]
        
        if !query.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: query))
        }
        
        // Apply filters
        if filter.architecture != nil {
            queryItems.append(URLQueryItem(name: "filter", value: filter.architecture))
        }
        
        if filter.sortBy != .downloads {
            queryItems.append(URLQueryItem(name: "sort", value: filter.sortBy.rawValue))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw HFAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add auth token if available
        if let token = getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        await MainActor.run { isSearching = true }
        defer { Task { @MainActor in isSearching = false } }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HFAPIError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let models = try JSONDecoder().decode([HFAPIModel].self, from: data)
            return try await convertToHFModels(models)
        case 401:
            throw HFAPIError.unauthorized
        case 429:
            throw HFAPIError.rateLimited
        default:
            throw HFAPIError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    /// Get detailed model info including files
    func getModelDetails(modelId: String) async throws -> ModelDetails {
        let url = URL(string: "\(baseURL)/models/\(modelId)")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let token = getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw HFAPIError.invalidResponse
        }
        
        return try JSONDecoder().decode(ModelDetails.self, from: data)
    }
    
    /// Get model files (safetensors, bin, etc.)
    func getModelFiles(modelId: String) async throws -> [ModelFile] {
        let url = URL(string: "\(baseURL)/models/\(modelId)/tree/main")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let token = getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Try fallback to main branch
            return try await getModelFilesFallback(modelId: modelId)
        }
        
        let files = try JSONDecoder().decode([HFRepoFile].self, from: data)
        return files.compactMap { file in
            guard file.type == "file" else { return nil }
            return ModelFile(
                name: file.path,
                size: file.size,
                downloadURL: URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(file.path)")
            )
        }
    }
    
    private func getModelFilesFallback(modelId: String) async throws -> [ModelFile] {
        // Try to get files from the model page HTML
        let url = URL(string: "https://huggingface.co/\(modelId)/tree/main")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let token = getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }
        
        let files = try JSONDecoder().decode([HFRepoFile].self, from: data)
        return files.compactMap { file in
            guard file.type == "file" else { return nil }
            return ModelFile(
                name: file.path,
                size: file.size,
                downloadURL: URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(file.path)")
            )
        }
    }
    
    /// Download a model file with progress tracking
    func downloadModelFile(
        from url: URL,
        to destination: URL,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        
        if let token = getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (asyncBytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HFAPIError.downloadFailed
        }
        
        let totalBytes = response.expectedContentLength
        var downloadedBytes: Int64 = 0
        
        // Create parent directory if needed
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Remove existing file
        try? FileManager.default.removeItem(at: destination)
        
        // Write file
        let fileHandle = try FileHandle(forWritingTo: destination)
        defer { try? fileHandle.close() }
        
        var lastProgressUpdate = Date()
        
        for try await byte in asyncBytes {
            fileHandle.write(Data([byte]))
            downloadedBytes += 1
            
            // Update progress every 100ms
            if totalBytes > 0,
               Date().timeIntervalSince(lastProgressUpdate) > 0.1 {
                let progress = Double(downloadedBytes) / Double(totalBytes)
                progressHandler(min(progress, 1.0))
                lastProgressUpdate = Date()
            }
        }
        
        progressHandler(1.0)
    }
    
    /// Get download URL for a specific file
    func getDownloadURL(modelId: String, filename: String) -> URL {
        URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(filename)")!
    }
    
    // MARK: - Private Methods
    
    private func convertToHFModels(_ apiModels: [HFAPIModel]) async throws -> [HFModel] {
        var models: [HFModel] = []
        
        for apiModel in apiModels {
            // Extract parameters from tags or model card
            let parameters = extractParameters(from: apiModel)
            
            // Detect architecture
            let architecture = detectArchitecture(from: apiModel)
            
            // Get model size from siblings
            let sizeBytes = apiModel.siblings?.reduce(0) { total, sibling in
                // Estimate based on file extensions
                if sibling.rfilename.hasSuffix(".safetensors") ||
                   sibling.rfilename.hasSuffix(".bin") {
                    return total + 500_000_000 // Rough estimate
                }
                return total
            } ?? 0
            
            // Get primary download URL
            let downloadURL = apiModel.siblings?.first { sibling in
                sibling.rfilename.hasSuffix("model.safetensors") ||
                sibling.rfilename.contains("pytorch_model") && sibling.rfilename.hasSuffix(".bin")
            }.flatMap { sibling in
                URL(string: "https://huggingface.co/\(apiModel.id)/resolve/main/\(sibling.rfilename)")
            }
            
            let model = HFModel(
                modelId: apiModel.id,
                name: apiModel.modelId.components(separatedBy: "/").last ?? apiModel.modelId,
                description: apiModel.cardData?.description ?? "\(architecture.rawValue) model by \(apiModel.author ?? "Unknown")",
                parameters: parameters,
                architecture: architecture,
                downloadURL: downloadURL,
                sizeBytes: Int64(sizeBytes),
                recommendedContextLength: architecture.defaultContextLength,
                tags: apiModel.tags,
                downloads: apiModel.downloads,
                likes: apiModel.likes
            )
            
            models.append(model)
        }
        
        return models
    }
    
    private func extractParameters(from model: HFAPIModel) -> String {
        // Try to extract from tags
        for tag in model.tags {
            if tag.hasSuffix("B") || tag.hasSuffix("b") {
                let param = tag.uppercased()
                if param.contains("B") {
                    return param
                }
            }
        }
        
        // Try to extract from model name
        let name = model.modelId.lowercased()
        let patterns = [
            "(\\d+\\.?\\d*)b",
            "(\\d+)b-",
            "-(\\d+)b",
            "_(\\d+)b"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: name, options: [], range: NSRange(location: 0, length: name.utf16.count)),
               let range = Range(match.range(at: 1), in: name) {
                let value = String(name[range])
                return "\(value)B"
            }
        }
        
        return "Unknown"
    }
    
    private func detectArchitecture(from model: HFAPIModel) -> ModelArchitecture {
        let tags = model.tags.map { $0.lowercased() }
        let id = model.id.lowercased()
        
        if tags.contains("llama") || id.contains("llama") {
            return .llama
        } else if tags.contains("mistral") || id.contains("mistral") {
            return .mistral
        } else if tags.contains("qwen") || id.contains("qwen") {
            return .qwen2
        } else if tags.contains("gemma") || id.contains("gemma") {
            return .gemma
        } else if tags.contains("phi") || id.contains("phi") {
            return .phi
        } else if tags.contains("falcon") || id.contains("falcon") {
            return .falcon
        } else if tags.contains("gpt2") || id.contains("gpt2") {
            return .gpt2
        } else if tags.contains("bert") || id.contains("bert") {
            return .bert
        }
        
        return .custom
    }
    
    func setAuthToken(_ token: String?) {
        if let token = token {
            UserDefaults.standard.set(token, forKey: "hf_auth_token")
        } else {
            UserDefaults.standard.removeObject(forKey: "hf_auth_token")
        }
    }
}

// MARK: - Supporting Types

struct ModelFilter {
    var architecture: String?
    var sortBy: SortOption = .downloads
    var task: String?
    var library: String?
    
    enum SortOption: String {
        case downloads = "downloads"
        case likes = "likes"
        case created = "createdAt"
        case updated = "lastModified"
    }
}

struct ModelFile: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let downloadURL: URL?
}

struct ModelDetails: Codable {
    let id: String
    let modelId: String
    let author: String?
    let downloads: Int
    let likes: Int
    let tags: [String]
    let pipeline_tag: String?
    let cardData: ModelCardData?
    let config: ModelConfig?
    
    struct ModelCardData: Codable {
        let description: String?
        let license: String?
        let language: [String]?
    }
    
    struct ModelConfig: Codable {
        let architectures: [String]?
        let model_type: String?
        let torch_dtype: String?
    }
}

enum HFAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpError(statusCode: Int)
    case downloadFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Authentication required. Please set your Hugging Face token in settings."
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .downloadFailed:
            return "Failed to download model file"
        case .invalidData:
            return "Invalid data received"
        }
    }
}

// MARK: - API Response Types

struct HFRepoFile: Codable {
    let type: String
    let path: String
    let size: Int64
}
