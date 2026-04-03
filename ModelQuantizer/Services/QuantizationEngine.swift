//
//  QuantizationEngine.swift
//  ModelQuantizer
//
//  Experimental on-device quantization engine.
//

import Foundation
import Accelerate
import Metal
import MetalPerformanceShaders

/// Experimental quantization engine for GGUF conversion/quantization prototypes.
@MainActor
class QuantizationEngine: ObservableObject {
    static let shared = QuantizationEngine()
    
    @Published var status: QuantizationStatus = .idle
    @Published var progress: Double = 0
    @Published var currentStage: String = ""
    @Published var estimatedTimeRemaining: TimeInterval?
    
    private var quantizeTask: Task<Void, Never>?
    private let fileManager = FileManager.default
    private let metalDevice: MTLDevice?
    
    private var modelsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Models", isDirectory: true)
    }
    
    private var tempDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Temp", isDirectory: true)
    }
    
    private init() {
        self.metalDevice = MTLCreateSystemDefaultDevice()
        createDirectories()
    }
    
    private func createDirectories() {
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public Methods
    
    func quantize(
        model: HFModel,
        to quantization: QuantizationType,
        contextLength: Int = 4096,
        useGPU: Bool = true
    ) {
        guard status == .idle else { return }
        
        quantizeTask?.cancel()
        
        quantizeTask = Task { [weak self] in
            await self?.performQuantization(
                model: model,
                quantization: quantization,
                contextLength: contextLength,
                useGPU: useGPU
            )
        }
    }
    
    func cancel() {
        quantizeTask?.cancel()
        status = .idle
        progress = 0
        currentStage = ""
    }
    
    // MARK: - Quantization Pipeline
    
    private func performQuantization(
        model: HFModel,
        quantization: QuantizationType,
        contextLength: Int,
        useGPU: Bool
    ) async {
        let startTime = Date()
        
        do {
            // Step 1: Download model files
            let downloadedFiles = try await downloadModelFiles(model: model)
            
            // Step 2: Analyze model structure
            let analysis = try await analyzeModel(files: downloadedFiles, model: model)
            
            // Step 3: Convert to GGUF format
            let ggufURL = try await convertToGGUF(
                files: downloadedFiles,
                analysis: analysis,
                model: model
            )
            
            // Step 4: Perform quantization
            let quantizedURL = try await quantizeGGUF(
                inputURL: ggufURL,
                quantization: quantization,
                model: model
            )
            
            // Step 5: Validate output
            try await validateQuantizedModel(at: quantizedURL, originalModel: model)
            
            // Complete
            let job = QuantizationJob(
                id: UUID(),
                originalModel: model,
                quantizationType: quantization,
                outputURL: quantizedURL,
                outputSize: (try? fileManager.attributesOfItem(atPath: quantizedURL.path)[.size] as? Int64) ?? 0,
                startTime: startTime,
                endTime: Date(),
                contextLength: contextLength
            )
            
            await MainActor.run {
                saveJobToHistory(job)
                status = .completed(outputURL: quantizedURL)
                progress = 1.0
                currentStage = "Complete!"
            }
            
            // Cleanup temp files
            cleanupTempFiles()
            
        } catch is CancellationError {
            await MainActor.run {
                status = .idle
                progress = 0
                currentStage = "Cancelled"
            }
        } catch {
            await MainActor.run {
                status = .failed(error: error.localizedDescription)
                progress = 0
                currentStage = "Failed: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Step 1: Download
    
    private func downloadModelFiles(model: HFModel) async throws -> [URL] {
        await updateStatus(.downloading(progress: 0), stage: "Downloading model files...")
        
        // Get model files from Hugging Face
        let files = try await HuggingFaceAPI.shared.getModelFiles(modelId: model.modelId)
        
        // Filter to relevant files (safetensors, config, tokenizer)
        let relevantFiles = files.filter { file in
            let name = file.name.lowercased()
            return name.hasSuffix(".safetensors") ||
                   name == "config.json" ||
                   name.hasPrefix("tokenizer") ||
                   name == "vocab.json" ||
                   name == "merges.txt"
        }
        
        guard !relevantFiles.isEmpty else {
            throw QuantizationError.noModelFiles
        }
        
        guard relevantFiles.contains(where: { $0.name.lowercased().hasSuffix(".safetensors") }) else {
            throw QuantizationError.unsupportedSourceFormat
        }
        
        var downloadedURLs: [URL] = []
        let totalFiles = relevantFiles.count
        
        for (index, file) in relevantFiles.enumerated() {
            try Task.checkCancellation()
            
            guard let downloadURL = file.downloadURL else { continue }
            
            let destination = tempDirectory.appendingPathComponent(file.name)
            
            await updateStatus(
                .downloading(progress: Double(index) / Double(totalFiles)),
                stage: "Downloading \(file.name)..."
            )
            
            try await HuggingFaceAPI.shared.downloadModelFile(
                from: downloadURL,
                to: destination
            ) { fileProgress in
                Task { @MainActor in
                    let overallProgress = (Double(index) + fileProgress) / Double(totalFiles)
                    self.progress = overallProgress * 0.25 // Download is 25% of total
                    self.currentStage = "Downloading \(file.name) (\(Int(fileProgress * 100))%)"
                }
            }
            
            downloadedURLs.append(destination)
        }
        
        return downloadedURLs
    }
    
    // MARK: - Step 2: Analyze
    
    private struct ModelAnalysis {
        let architecture: ModelArchitecture
        let layerCount: Int
        let tensorCount: Int
        let totalParameters: Int64
        let originalSize: Int64
    }

    private func analyzeModel(files: [URL], model: HFModel) async throws -> ModelAnalysis {
        await updateStatus(.analyzing, stage: "Analyzing model structure...")
        
        var architecture: ModelArchitecture = model.architecture
        var layerCount = 0
        var tensorCount = 0
        var totalParameters: Int64 = 0
        var totalSize: Int64 = 0
        
        // Analyze safetensors files
        for file in files where file.pathExtension == "safetensors" {
            let analysis = try analyzeSafeTensorsFile(at: file)
            layerCount = max(layerCount, analysis.layerCount)
            tensorCount += analysis.tensorCount
            totalParameters += analysis.totalParameters
            
            let attrs = try fileManager.attributesOfItem(atPath: file.path)
            totalSize += attrs[.size] as? Int64 ?? 0
        }
        
        // Analyze config.json for additional info
        if let configFile = files.first(where: { $0.lastPathComponent == "config.json" }) {
            let configData = try Data(contentsOf: configFile)
            if let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                // Extract num_hidden_layers
                if let layers = config["num_hidden_layers"] as? Int {
                    layerCount = max(layerCount, layers)
                }
            }
        }
        
        // Update progress
        await MainActor.run {
            self.progress = 0.30 // Analysis is 30% of total
        }
        
        return ModelAnalysis(
            architecture: architecture,
            layerCount: layerCount,
            tensorCount: tensorCount,
            totalParameters: totalParameters,
            originalSize: totalSize
        )
    }
    
    private func analyzeSafeTensorsFile(at url: URL) throws -> (layerCount: Int, tensorCount: Int, totalParameters: Int64, totalSize: Int64) {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        
        guard data.count >= 8 else {
            return (0, 0, 0, 0)
        }
        
        // Read header length (first 8 bytes, little-endian uint64)
        let headerLength = data.prefix(8).withUnsafeBytes { ptr -> UInt64 in
            UInt64(littleEndian: ptr.loadUnaligned(as: UInt64.self))
        }
        
        guard headerLength > 0 && headerLength < UInt64(data.count) else {
            return (0, 0, 0, 0)
        }
        
        // Parse header JSON
        let headerData = data.dropFirst(8).prefix(Int(headerLength))
        guard let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            return (0, 0, 0, 0)
        }
        
        var layerCount = 0
        var tensorCount = 0
        var totalParameters: Int64 = 0
        var totalSize: Int64 = Int64(data.count)
        
        for (key, value) in header {
            guard let tensorInfo = value as? [String: Any],
                  let shape = tensorInfo["shape"] as? [Int] else { continue }
            
            tensorCount += 1
            let paramCount = shape.reduce(1, *)
            totalParameters += Int64(paramCount)
            
            // Extract layer number from key like "model.layers.0.self_attn.q_proj.weight"
            if key.contains("layers.") {
                let components = key.components(separatedBy: "layers.")
                if components.count > 1,
                   let layerNum = Int(components[1].components(separatedBy: ".").first ?? "") {
                    layerCount = max(layerCount, layerNum + 1)
                }
            }
        }
        
        return (layerCount, tensorCount, totalParameters, totalSize)
    }
    
    // MARK: - Step 3: Convert to GGUF
    
    private func convertToGGUF(
        files: [URL],
        analysis: ModelAnalysis,
        model: HFModel
    ) async throws -> URL {
        await updateStatus(.quantizing(progress: 0.35, stage: "Converting to GGUF..."), stage: "Converting to GGUF format...")
        
        let outputURL = tempDirectory.appendingPathComponent("\(model.modelId.replacingOccurrences(of: "/", with: "_"))_f16.gguf")
        
        // Remove existing file
        try? fileManager.removeItem(at: outputURL)
        
        // Build GGUF file
        var ggufBuilder = GGUFBuilder()
        
        // Add metadata
        ggufBuilder.addMetadata(key: "general.architecture", value: .string(analysis.architecture.rawValue.lowercased()))
        ggufBuilder.addMetadata(key: "general.name", value: .string(model.name))
        ggufBuilder.addMetadata(key: "general.description", value: .string(model.description))
        ggufBuilder.addMetadata(key: "general.quantization_version", value: .uint32(2))
        ggufBuilder.addMetadata(key: "general.file_type", value: .uint32(1)) // F16
        
        // Add architecture-specific metadata
        addArchitectureMetadata(to: &ggufBuilder, analysis: analysis)
        
        // Process tensors from safetensors files
        var processedTensorFiles = 0
        for file in files where file.pathExtension == "safetensors" {
            try Task.checkCancellation()
            
            await MainActor.run {
                self.currentStage = "Processing \(file.lastPathComponent)..."
            }
            
            try await processSafeTensorsFile(file, into: &ggufBuilder)
            processedTensorFiles += 1
        }
        
        guard processedTensorFiles > 0 else {
            throw QuantizationError.unsupportedSourceFormat
        }
        
        // Write GGUF file
        let ggufData = try ggufBuilder.build()
        try ggufData.write(to: outputURL)
        
        await MainActor.run {
            self.progress = 0.45 // Conversion is 45% of total
        }
        
        return outputURL
    }
    
    private func addArchitectureMetadata(to builder: inout GGUFBuilder, analysis: ModelAnalysis) {
        // Add context length
        builder.addMetadata(key: "\(analysis.architecture.rawValue.lowercased()).context_length", value: .uint32(4096))
        builder.addMetadata(key: "\(analysis.architecture.rawValue.lowercased()).embedding_length", value: .uint32(4096))
        builder.addMetadata(key: "\(analysis.architecture.rawValue.lowercased()).block_count", value: .uint32(UInt32(analysis.layerCount)))
        builder.addMetadata(key: "\(analysis.architecture.rawValue.lowercased()).feed_forward_length", value: .uint32(11008))
        builder.addMetadata(key: "\(analysis.architecture.rawValue.lowercased()).attention.head_count", value: .uint32(32))
        builder.addMetadata(key: "\(analysis.architecture.rawValue.lowercased()).attention.head_count_kv", value: .uint32(32))
        builder.addMetadata(key: "\(analysis.architecture.rawValue.lowercased()).attention.layer_norm_rms_epsilon", value: .float32(1e-5))
        builder.addMetadata(key: "\(analysis.architecture.rawValue.lowercased()).rope.dimension_count", value: .uint32(128))
    }
    
    private func processSafeTensorsFile(_ url: URL, into builder: inout GGUFBuilder) async throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 8 else { throw QuantizationError.invalidModelFormat }
        
        // Read header
        let headerLength = data.prefix(8).withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
        let headerData = data.dropFirst(8).prefix(Int(headerLength))
        
        guard let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else { return }
        
        for (key, value) in header {
            try Task.checkCancellation()
            
            if key == "__metadata__" { continue }
            
            guard let tensorInfo = value as? [String: Any],
                  let shape = tensorInfo["shape"] as? [Int],
                  let dtype = tensorInfo["dtype"] as? String,
                  let dataOffsets = tensorInfo["data_offsets"] as? [Int],
                  dataOffsets.count == 2 else { continue }
            
            let dataSectionOffset = 8 + Int(headerLength)
            let tensorStart = dataSectionOffset + dataOffsets[0]
            let tensorEnd = dataSectionOffset + dataOffsets[1]
            
            guard tensorStart >= 0, tensorEnd <= data.count, tensorStart < tensorEnd else { continue }
            
            // Read tensor data
            let tensorData = data.subdata(in: tensorStart..<tensorEnd)
            
            // Convert tensor name to GGUF format
            let ggufName = convertTensorName(key)
            
            // Add tensor to GGUF
            builder.addTensor(
                name: ggufName,
                shape: shape.map { UInt32($0) },
                dataType: ggmlType(for: dtype),
                data: tensorData
            )
        }
    }
    
    private func ggmlType(for dtype: String) -> GGMLType {
        switch dtype {
        case "F16", "float16", "BF16", "bfloat16":
            return .float16
        default:
            return .float32
        }
    }
    
    private func convertTensorName(_ name: String) -> String {
        // Convert Hugging Face tensor names to GGUF format
        let converted = name
            .replacingOccurrences(of: "model.embed_tokens.", with: "token_embd.")
            .replacingOccurrences(of: "model.norm.", with: "output_norm.")
            .replacingOccurrences(of: "lm_head.", with: "output.")
            .replacingOccurrences(of: "model.layers.", with: "blk.")
            .replacingOccurrences(of: ".self_attn.", with: ".attn.")
            .replacingOccurrences(of: ".mlp.", with: ".ffn.")
            .replacingOccurrences(of: ".input_layernorm.", with: ".attn_norm.")
            .replacingOccurrences(of: ".post_attention_layernorm.", with: ".ffn_norm.")
            .replacingOccurrences(of: ".q_proj.", with: ".q.")
            .replacingOccurrences(of: ".k_proj.", with: ".k.")
            .replacingOccurrences(of: ".v_proj.", with: ".v.")
            .replacingOccurrences(of: ".o_proj.", with: ".o.")
            .replacingOccurrences(of: ".gate_proj.", with: ".gate.")
            .replacingOccurrences(of: ".up_proj.", with: ".up.")
            .replacingOccurrences(of: ".down_proj.", with: ".down.")
        
        return converted
    }
    
    // MARK: - Step 4: Quantize
    
    private func quantizeGGUF(
        inputURL: URL,
        quantization: QuantizationType,
        model: HFModel
    ) async throws -> URL {
        let outputFilename = "\(model.modelId.replacingOccurrences(of: "/", with: "_"))_\(quantization.rawValue).gguf"
        let outputURL = modelsDirectory.appendingPathComponent(outputFilename)
        
        // Remove existing file
        try? fileManager.removeItem(at: outputURL)
        
        await updateStatus(
            .quantizing(progress: 0.50, stage: "Quantizing to \(quantization.rawValue)..."),
            stage: "Quantizing tensors to \(quantization.rawValue)..."
        )
        
        // Read input GGUF
        let inputData = try Data(contentsOf: inputURL, options: .mappedIfSafe)
        
        // Parse GGUF header
        var parser = GGUFParser(data: inputData)
        let header = try parser.parseHeader()
        
        // Create output GGUF builder
        var outputBuilder = GGUFBuilder()
        
        // Copy metadata
        for (key, value) in header.metadata {
            outputBuilder.addMetadata(key: key, value: value)
        }
        
        // Update quantization info
        outputBuilder.addMetadata(key: "general.quantization_version", value: .uint32(2))
        outputBuilder.addMetadata(key: "general.file_type", value: .uint32(quantization.ggufFileType))
        
        // Quantize tensors
        let totalTensors = header.tensors.count
        
        for (index, tensorInfo) in header.tensors.enumerated() {
            try Task.checkCancellation()
            
            let progress = 0.50 + (Double(index) / Double(totalTensors)) * 0.45
            await updateStatus(
                .quantizing(progress: progress, stage: "Quantizing \(tensorInfo.name)..."),
                stage: "Quantizing \(tensorInfo.name) (\(index + 1)/\(totalTensors))..."
            )
            
            // Read tensor data from input
            let tensor = try parser.readTensor(info: tensorInfo)
            
            // Quantize tensor
            let quantizedTensor = try quantizeTensor(tensor, to: quantization)
            outputBuilder.addTensor(
                name: quantizedTensor.name,
                shape: quantizedTensor.shape,
                dataType: quantizedTensor.dataType,
                data: quantizedTensor.data
            )
        }
        
        // Write output
        let outputData = try outputBuilder.build()
        try outputData.write(to: outputURL)
        
        await updateStatus(.optimizing, stage: "Optimizing output...")
        
        return outputURL
    }
    
    private func quantizeTensor(_ tensor: GGUFTensor, to quantization: QuantizationType) throws -> GGUFTensor {
        switch quantization {
        case .q4_0:
            return try quantizeToQ4_0(tensor)
        case .q4_1:
            return try quantizeToQ4_1(tensor)
        case .q8_0:
            return try quantizeToQ8_0(tensor)
        case .fp16:
            return try convertToFP16(tensor)
        case .fp32:
            return tensor
        default:
            throw QuantizationError.unsupportedQuantization(type: quantization.rawValue)
        }
    }
    
    // Q4_0 quantization: 4-bit with block-wise scaling
    private func quantizeToQ4_0(_ tensor: GGUFTensor) throws -> GGUFTensor {
        let blockSize = 32
        let floatData = try tensorFloatValues(from: tensor)
        let numElements = floatData.count
        let numBlocks = (numElements + blockSize - 1) / blockSize
        
        var outputData = Data()
        
        for blockIdx in 0..<numBlocks {
            let startIdx = blockIdx * blockSize
            let endIdx = min(startIdx + blockSize, numElements)
            // Find max absolute value in block
            var maxAbs: Float = 0
            for i in startIdx..<endIdx {
                maxAbs = max(maxAbs, abs(floatData[i]))
            }
            
            // Compute scale
            let scale = maxAbs / 7.0
            
            // Write scale (half precision)
            var scaleF16 = Float16(scale)
            withUnsafeBytes(of: &scaleF16) { ptr in
                outputData.append(ptr.bindMemory(to: UInt8.self))
            }
            
            // Quantize values to 4-bit
            var quantizedBytes: [UInt8] = []
            for i in stride(from: startIdx, to: endIdx, by: 2) {
                let val1 = scale > 0 ? Int8(round(floatData[i] / scale)) : 0
                let val2 = (i + 1 < endIdx && scale > 0) ? Int8(round(floatData[i + 1] / scale)) : 0
                
                let q1 = UInt8(clamping: Int(val1) & 0x0F)
                let q2 = UInt8(clamping: Int(val2) & 0x0F)
                
                quantizedBytes.append(q1 | (q2 << 4))
            }
            
            // Pad to full block size
            let expectedBytes = blockSize / 2
            while quantizedBytes.count < expectedBytes {
                quantizedBytes.append(0)
            }
            
            outputData.append(contentsOf: quantizedBytes)
        }
        
        return GGUFTensor(
            name: tensor.name,
            shape: tensor.shape,
            dataType: .q4_0,
            data: outputData
        )
    }
    
    // Q4_1 quantization: 4-bit with block-wise min/max
    private func quantizeToQ4_1(_ tensor: GGUFTensor) throws -> GGUFTensor {
        let blockSize = 32
        let floatData = try tensorFloatValues(from: tensor)
        let numElements = floatData.count
        let numBlocks = (numElements + blockSize - 1) / blockSize
        
        var outputData = Data()
        
        for blockIdx in 0..<numBlocks {
            let startIdx = blockIdx * blockSize
            let endIdx = min(startIdx + blockSize, numElements)
            
            var minVal: Float = .greatestFiniteMagnitude
            var maxVal: Float = -.greatestFiniteMagnitude
            
            for i in startIdx..<endIdx {
                minVal = min(minVal, floatData[i])
                maxVal = max(maxVal, floatData[i])
            }
            
            let scale = (maxVal - minVal) / 15.0
            var minF16 = Float16(minVal)
            var scaleF16 = Float16(scale)
            
            withUnsafeBytes(of: &scaleF16) { ptr in
                outputData.append(ptr.bindMemory(to: UInt8.self))
            }
            withUnsafeBytes(of: &minF16) { ptr in
                outputData.append(ptr.bindMemory(to: UInt8.self))
            }
            
            var quantizedBytes: [UInt8] = []
            for i in stride(from: startIdx, to: endIdx, by: 2) {
                let q1 = scale > 0 ? UInt8(clamping: Int(round((floatData[i] - minVal) / scale)) & 0x0F) : 0
                let q2 = (i + 1 < endIdx && scale > 0) ? UInt8(clamping: Int(round((floatData[i + 1] - minVal) / scale)) & 0x0F) : 0
                quantizedBytes.append(q1 | (q2 << 4))
            }
            
            let expectedBytes = blockSize / 2
            while quantizedBytes.count < expectedBytes {
                quantizedBytes.append(0)
            }
            
            outputData.append(contentsOf: quantizedBytes)
        }
        
        return GGUFTensor(name: tensor.name, shape: tensor.shape, dataType: .q4_1, data: outputData)
    }
    
    // Q8_0 quantization: 8-bit with block-wise scaling
    private func quantizeToQ8_0(_ tensor: GGUFTensor) throws -> GGUFTensor {
        let blockSize = 32
        let floatData = try tensorFloatValues(from: tensor)
        let numElements = floatData.count
        let numBlocks = (numElements + blockSize - 1) / blockSize
        
        var outputData = Data()
        
        for blockIdx in 0..<numBlocks {
            let startIdx = blockIdx * blockSize
            let endIdx = min(startIdx + blockSize, numElements)
            
            var maxAbs: Float = 0
            for i in startIdx..<endIdx {
                maxAbs = max(maxAbs, abs(floatData[i]))
            }
            
            let scale = maxAbs / 127.0
            var scaleF16 = Float16(scale)
            withUnsafeBytes(of: &scaleF16) { ptr in
                outputData.append(ptr.bindMemory(to: UInt8.self))
            }
            
            for i in startIdx..<endIdx {
                let quantized = scale > 0 ? Int8(clamping: Int(round(floatData[i] / scale))) : 0
                outputData.append(UInt8(bitPattern: quantized))
            }
            
            // Pad to block size
            for _ in (endIdx - startIdx)..<blockSize {
                outputData.append(0)
            }
        }
        
        return GGUFTensor(name: tensor.name, shape: tensor.shape, dataType: .q8_0, data: outputData)
    }
    
    // FP16 conversion
    private func convertToFP16(_ tensor: GGUFTensor) throws -> GGUFTensor {
        let floatData = try tensorFloatValues(from: tensor)
        var outputData = Data()
        
        for value in floatData {
            var f16 = Float16(value)
            outputData.append(Data(bytes: &f16, count: MemoryLayout<Float16>.size))
        }
        
        return GGUFTensor(name: tensor.name, shape: tensor.shape, dataType: .float16, data: outputData)
    }
    
    private func tensorFloatValues(from tensor: GGUFTensor) throws -> [Float] {
        switch tensor.dataType {
        case .float32:
            guard tensor.data.count.isMultiple(of: MemoryLayout<Float>.size) else {
                throw QuantizationError.invalidModelFormat
            }
            return tensor.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        case .float16:
            guard tensor.data.count.isMultiple(of: MemoryLayout<UInt16>.size) else {
                throw QuantizationError.invalidModelFormat
            }
            let words = tensor.data.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
            return words.map { Float16(bits: $0).floatValue }
        default:
            throw QuantizationError.invalidModelFormat
        }
    }
    
    // MARK: - Step 5: Validate
    
    private func validateQuantizedModel(at url: URL, originalModel: HFModel) async throws {
        await updateStatus(.validating, stage: "Validating output...")
        
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 8 else { throw QuantizationError.invalidOutput }
        
        // Check GGUF magic number
        let magic = data.prefix(4)
        guard magic == Data("GGUF".utf8) else {
            throw QuantizationError.invalidOutput
        }
        
        // Verify version
        let version = data.dropFirst(4).prefix(4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard version == 3 else {
            throw QuantizationError.invalidOutput
        }
        
        // Check file size is reasonable
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = attrs[.size] as? Int64 ?? 0
        
        guard fileSize > 1024 else {
            throw QuantizationError.invalidOutput
        }
        
        await MainActor.run {
            self.progress = 0.97
        }
    }
    
    // MARK: - Helpers
    
    private func updateStatus(_ status: QuantizationStatus, stage: String) async {
        await MainActor.run {
            self.status = status
            self.currentStage = stage
        }
    }
    
    private func saveJobToHistory(_ job: QuantizationJob) {
        var history = getQuantizationHistory()
        history.insert(job, at: 0)
        
        // Keep only last 50 jobs
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
        
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "quantizationHistory")
        }
    }
    
    func getQuantizationHistory() -> [QuantizationJob] {
        guard let data = UserDefaults.standard.data(forKey: "quantizationHistory"),
              let history = try? JSONDecoder().decode([QuantizationJob].self, from: data) else {
            return []
        }
        return history
    }
    
    private func cleanupTempFiles() {
        try? fileManager.removeItem(at: tempDirectory)
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    func getQuantizedModels() -> [QuantizedModel] {
        guard let contents = try? fileManager.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        return contents.compactMap { url in
            guard url.pathExtension == "gguf" else { return nil }
            return try? QuantizedModel(from: url)
        }.sorted { $0.createdDate > $1.createdDate }
    }
    
    func deleteQuantizedModel(_ model: QuantizedModel) throws {
        try fileManager.removeItem(at: model.url)
    }
}

// MARK: - Supporting Types

struct GGUFTensor {
    let name: String
    let shape: [UInt32]
    let dataType: GGMLType
    let data: Data
}

public enum GGMLType: UInt32 {
    case float32 = 0
    case float16 = 1
    case q4_0 = 2
    case q4_1 = 3
    case q5_0 = 6
    case q5_1 = 7
    case q8_0 = 8
}

public struct GGUFHeader {
    public let version: UInt32
    public let tensorCount: UInt64
    public let metadata: [(String, GGUFBuilder.MetadataValue)]
    public let tensors: [GGUFTensorInfo]
}

public struct GGUFTensorInfo {
    public let name: String
    public let shape: [UInt64]
    public let type: GGMLType
    public let offset: UInt64
}

// MARK: - GGUF Parser

public struct GGUFParser {
    let data: Data
    public var offset: Int = 0

    public init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }
    
    public mutating func parseHeader() throws -> GGUFHeader {
        // Magic
        let magic = readData(count: 4)
        guard magic == Data("GGUF".utf8) else {
            throw QuantizationError.invalidModelFormat
        }
        
        // Version
        let version = readUInt32()
        guard version == 3 else {
            throw QuantizationError.unsupportedVersion
        }
        
        // Tensor count
        let tensorCount = readUInt64()
        
        // Metadata count
        let metadataCount = readUInt64()
        
        // Parse metadata
        var metadata: [(String, GGUFBuilder.MetadataValue)] = []
        for _ in 0..<metadataCount {
            let key = readString()
            let value = try readMetadataValue()
            metadata.append((key, value))
        }
        
        // Parse tensor info
        var tensors: [GGUFTensorInfo] = []
        for _ in 0..<tensorCount {
            let name = readString()
            let nDims = Int(readUInt32())
            var shape: [UInt64] = []
            for _ in 0..<nDims {
                shape.append(readUInt64())
            }
            let type = GGMLType(rawValue: readUInt32()) ?? .float32
            let tensorOffset = readUInt64()
            
            tensors.append(GGUFTensorInfo(name: name, shape: shape, type: type, offset: tensorOffset))
        }
        
        return GGUFHeader(version: version, tensorCount: tensorCount, metadata: metadata, tensors: tensors)
    }
    
    internal mutating func readData(count: Int) -> Data {
        guard count >= 0, offset >= 0, offset + count <= data.count else {
            return Data()
        }
        let data = self.data.subdata(in: offset..<(offset + count))
        offset += count
        return data
    }
    
    private mutating func readUInt32() -> UInt32 {
        let bytes = readData(count: 4)
        guard bytes.count == 4 else { return 0 }
        let value = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return UInt32(littleEndian: value)
    }
    
    private mutating func readUInt64() -> UInt64 {
        let bytes = readData(count: 8)
        guard bytes.count == 8 else { return 0 }
        let value = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        return UInt64(littleEndian: value)
    }
    
    private mutating func readString() -> String {
        let length = Int(readUInt64())
        guard length >= 0, offset >= 0, offset + length <= data.count else { return "" }
        let stringData = data.subdata(in: offset..<(offset + length))
        offset += length
        return String(data: stringData, encoding: .utf8) ?? ""
    }
    
    private mutating func readMetadataValue() throws -> GGUFBuilder.MetadataValue {
        let type = readUInt32()
        
        switch type {
        case 0: // UINT8
            return .uint8(readData(count: 1).first ?? 0)
        case 1: // INT8
            return .int8(Int8(bitPattern: readData(count: 1).first ?? 0))
        case 2: // UINT16
            let bytes = readData(count: 2)
            guard bytes.count == 2 else { throw QuantizationError.invalidModelFormat }
            let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            return .uint16(UInt16(littleEndian: raw))
        case 3: // INT16
            let bytes = readData(count: 2)
            guard bytes.count == 2 else { throw QuantizationError.invalidModelFormat }
            let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            return .int16(Int16(bitPattern: UInt16(littleEndian: raw)))
        case 4: // UINT32
            return .uint32(readUInt32())
        case 5: // INT32
            return .int32(Int32(bitPattern: readUInt32()))
        case 6: // FLOAT32
            let bytes = readData(count: 4)
            guard bytes.count == 4 else { throw QuantizationError.invalidModelFormat }
            let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return .float32(Float(bitPattern: UInt32(littleEndian: raw)))
        case 7: // BOOL
            return .bool(readData(count: 1).first != 0)
        case 8: // STRING
            return .string(readString())
        case 9: // ARRAY
            let elementType = readUInt32()
            let count = readUInt64()
            var array: [GGUFBuilder.MetadataValue] = []
            for _ in 0..<count {
                array.append(try readMetadataArrayElement(type: elementType))
            }
            return .array(array)
        case 10: // UINT64
            return .uint64(readUInt64())
        case 11: // INT64
            return .int64(Int64(bitPattern: readUInt64()))
        case 12: // FLOAT64
            let bytes = readData(count: 8)
            guard bytes.count == 8 else { throw QuantizationError.invalidModelFormat }
            let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            return .float64(Double(bitPattern: UInt64(littleEndian: raw)))
        default:
            throw QuantizationError.invalidModelFormat
        }
    }
    
    private mutating func readMetadataArrayElement(type: UInt32) throws -> GGUFBuilder.MetadataValue {
        switch type {
        case 0: return .uint8(readData(count: 1).first ?? 0)
        case 1: return .int8(Int8(bitPattern: readData(count: 1).first ?? 0))
        case 2:
            let bytes = readData(count: 2)
            guard bytes.count == 2 else { throw QuantizationError.invalidModelFormat }
            let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            return .uint16(UInt16(littleEndian: raw))
        case 3:
            let bytes = readData(count: 2)
            guard bytes.count == 2 else { throw QuantizationError.invalidModelFormat }
            let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
            return .int16(Int16(bitPattern: UInt16(littleEndian: raw)))
        case 4: return .uint32(readUInt32())
        case 5: return .int32(Int32(bitPattern: readUInt32()))
        case 6:
            let bytes = readData(count: 4)
            guard bytes.count == 4 else { throw QuantizationError.invalidModelFormat }
            let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return .float32(Float(bitPattern: UInt32(littleEndian: raw)))
        case 7: return .bool(readData(count: 1).first != 0)
        case 8: return .string(readString())
        case 10: return .uint64(readUInt64())
        case 11: return .int64(Int64(bitPattern: readUInt64()))
        case 12:
            let bytes = readData(count: 8)
            guard bytes.count == 8 else { throw QuantizationError.invalidModelFormat }
            let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            return .float64(Double(bitPattern: UInt64(littleEndian: raw)))
        default:
            throw QuantizationError.invalidModelFormat
        }
    }
    
    mutating func readTensor(info: GGUFTensorInfo) throws -> GGUFTensor {
        // Move to tensor data offset
        offset = Int(info.offset)
        
        // Calculate tensor size based on shape and type
        let numElements = info.shape.reduce(1, *)
        let elementSize: Int
        switch info.type {
        case .float32: elementSize = 4
        case .float16: elementSize = 2
        case .q4_0: elementSize = 18 // 2 bytes scale + 16 bytes data per 32 elements
        case .q4_1: elementSize = 20 // 2 bytes scale + 2 bytes min + 16 bytes data per 32 elements
        case .q5_0: elementSize = 22
        case .q5_1: elementSize = 24
        case .q8_0: elementSize = 34 // 2 bytes scale + 32 bytes data per 32 elements
        }
        
        let tensorSize: Int
        switch info.type {
        case .float32, .float16:
            tensorSize = Int(numElements) * elementSize
        default:
            tensorSize = ((Int(numElements) + 31) / 32) * elementSize // Block quantized formats
        }
        let tensorData = readData(count: tensorSize)
        guard tensorData.count == tensorSize else {
            throw QuantizationError.invalidModelFormat
        }
        
        return GGUFTensor(
            name: info.name,
            shape: info.shape.map { UInt32($0) },
            dataType: info.type,
            data: tensorData
        )
    }
}

// MARK: - Float16 Support

struct Float16: Equatable {
    var bits: UInt16
    
    init(_ value: Float) {
        self.bits = floatToHalf(value)
    }
    
    init(bits: UInt16) {
        self.bits = bits
    }
    
    var floatValue: Float {
        halfToFloat(bits)
    }
}

private func floatToHalf(_ value: Float) -> UInt16 {
    let bits = value.bitPattern
    let sign = UInt16((bits >> 16) & 0x8000)
    var exponent = Int((bits >> 23) & 0xFF) - 127 + 15
    var mantissa = bits & 0x007F_FFFF
    
    if exponent <= 0 {
        if exponent < -10 { return sign }
        mantissa |= 0x0080_0000
        let shift = UInt32(14 - exponent)
        var halfMantissa = UInt16(mantissa >> shift)
        if ((mantissa >> (shift - 1)) & 1) == 1 {
            halfMantissa &+= 1
        }
        return sign | halfMantissa
    }
    
    if exponent >= 31 {
        return sign | 0x7C00
    }
    
    var halfMantissa = UInt16(mantissa >> 13)
    if ((mantissa >> 12) & 1) == 1 {
        halfMantissa &+= 1
        if halfMantissa == 0x0400 {
            halfMantissa = 0
            exponent += 1
            if exponent >= 31 {
                return sign | 0x7C00
            }
        }
    }
    
    return sign | UInt16(exponent << 10) | halfMantissa
}

private func halfToFloat(_ bits: UInt16) -> Float {
    let sign = UInt32((bits >> 15) & 0x1)
    let exponent = Int((bits >> 10) & 0x1F)
    let mantissa = UInt32(bits & 0x3FF)
    
    var result: UInt32
    
    if exponent == 31 {
        // Infinity or NaN
        result = (sign << 31) | 0x7F800000 | (mantissa << 13)
    } else if exponent == 0 && mantissa == 0 {
        // Zero
        result = sign << 31
    } else {
        // Normalized or denormal
        var exp = exponent
        var mant = mantissa
        
        if exp == 0 {
            // Denormal
            exp = 1
            while (mant & 0x400) == 0 {
                mant <<= 1
                exp -= 1
            }
            mant &= 0x3FF
        }
        
        exp = exp - 15 + 127 // Adjust bias
        result = (sign << 31) | (UInt32(exp) << 23) | (mant << 13)
    }
    
    var floatResult: Float = 0
    withUnsafeMutableBytes(of: &floatResult) { ptr in
        ptr.storeBytes(of: result, as: UInt32.self)
    }
    
    return floatResult
}

// MARK: - Quantization Type Extension

extension QuantizationType {
    var localGGUFFileType: UInt32 {
        switch self {
        case .fp32: return 0
        case .fp16: return 1
        case .q4_0: return 2
        case .q4_1: return 3
        case .q5_0: return 6
        case .q5_1: return 7
        case .q8_0: return 8
        default: return 2 // Default to Q4_0
        }
    }
}

enum QuantizationError: Error, LocalizedError {
    case noModelFiles
    case downloadFailed
    case invalidModelFormat
    case unsupportedVersion
    case quantizationFailed
    case invalidOutput
    case insufficientMemory
    case cancelled
    case unsupportedQuantization(type: String)
    case unsupportedSourceFormat
    
    var errorDescription: String? {
        switch self {
        case .noModelFiles:
            return "No model files found in repository"
        case .downloadFailed:
            return "Failed to download model files"
        case .invalidModelFormat:
            return "Invalid or unsupported model format"
        case .unsupportedVersion:
            return "Unsupported GGUF version"
        case .quantizationFailed:
            return "Quantization process failed"
        case .invalidOutput:
            return "Generated model file is invalid"
        case .insufficientMemory:
            return "Insufficient memory for quantization"
        case .cancelled:
            return "Quantization was cancelled"
        case .unsupportedQuantization(let type):
            return "Quantization type \(type) is not supported in this build"
        case .unsupportedSourceFormat:
            return "Only SafeTensors-based model repositories are currently supported"
        }
    }
}
