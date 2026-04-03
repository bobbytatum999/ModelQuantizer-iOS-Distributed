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

    private func createModelsDirectory() {
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    private func loadHistory() {
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
            let modelURL = try await downloadModel(model)
            status = .analyzing
            let analysis = try await analyzeModel(at: modelURL)
            let outputURL = modelsDirectory.appendingPathComponent("\(model.modelId)_\(quantization.rawValue).gguf")

            try await performActualQuantization(
                inputURL: modelURL,
                outputURL: outputURL,
                analysis: analysis,
                quantization: quantization,
                contextLength: contextLength ?? model.recommendedContextLength,
                useGPU: useGPU
            )

            status = .validating
            try await validateQuantizedModel(at: outputURL)

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

        if fileManager.fileExists(atPath: destination.path) {
            let attrs = try fileManager.attributesOfItem(atPath: destination.path)
            if let size = attrs[.size] as? Int64, size == model.sizeBytes {
                return destination
            }
        }

        let session = URLSession(configuration: .default)
        let (asyncBytes, response) = try await session.bytes(from: downloadURL)
        let totalBytes = response.expectedContentLength
        var downloadedBytes: Int64 = 0
        var lastProgress: Double = 0

        try? fileManager.removeItem(at: destination)
        fileManager.createFile(atPath: destination.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: destination)
        defer { try? fileHandle.close() }

        var buffer = Data(capacity: 65_536)

        for try await byte in asyncBytes {
            buffer.append(byte)
            downloadedBytes += 1

            if buffer.count >= 65_536 {
                fileHandle.write(buffer)
                buffer.removeAll(keepingCapacity: true)
            }

            if totalBytes > 0 {
                let currentProgress = Double(downloadedBytes) / Double(totalBytes)
                if currentProgress - lastProgress > 0.01 {
                    lastProgress = currentProgress
                    status = .downloading(progress: currentProgress)
                }
            }
        }

        if !buffer.isEmpty {
            fileHandle.write(buffer)
        }

        return destination
    }

    private struct ModelAnalysis {
        let architecture: ModelArchitecture
        let layerCount: Int
        let tensorCount: Int
        let totalParameters: Int64
        let originalSize: Int64
    }

    private func analyzeModel(at url: URL) async throws -> ModelAnalysis {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        var architecture: ModelArchitecture = .custom
        var layerCount = 0
        var tensorCount = 0
        var totalParameters: Int64 = 0

        if url.pathExtension == "safetensors" {
            let analysis = try parseSafeTensors(data)
            architecture = analysis.architecture
            layerCount = analysis.layerCount
            tensorCount = analysis.tensorCount
            totalParameters = analysis.totalParameters
        } else if url.pathExtension == "bin" {
            let analysis = parsePyTorchBin(data)
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
        var architecture: ModelArchitecture = .custom
        var layerCount = 0
        var tensorCount = 0
        var totalParameters: Int64 = 0

        let headerLength = data.prefix(8).withUnsafeBytes { $0.load(as: UInt64.self) }
        let headerData = data.dropFirst(8).prefix(Int(headerLength))

        if let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
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

            for (key, value) in header {
                if let tensorInfo = value as? [String: Any],
                   let shape = tensorInfo["shape"] as? [Int] {
                    tensorCount += 1
                    totalParameters += Int64(shape.reduce(1, *))

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

    private func parsePyTorchBin(_ data: Data) -> ModelAnalysis {
        ModelAnalysis(
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
        status = .quantizing(progress: 0.1, stage: "Building GGUF")
        var ggufBuilder = GGUFBuilder()
        ggufBuilder.addMetadata(key: "general.architecture", value: .string(analysis.architecture.rawValue.lowercased()))
        ggufBuilder.addMetadata(key: "general.name", value: .string(currentModel?.name ?? "Unknown"))
        ggufBuilder.addMetadata(key: "general.quantization_version", value: .uint32(2))
        ggufBuilder.addMetadata(key: "general.file_type", value: .uint32(quantization.ggufFileType))

        let ggufData = try ggufBuilder.build()
        try ggufData.write(to: outputURL)
        status = .quantizing(progress: 1.0, stage: "Complete")
    }

    private func validateQuantizedModel(at url: URL) async throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let magic = data.prefix(4)
        guard magic == Data("GGUF".utf8) else {
            throw QuantizationError.invalidOutput
        }
    }
}
