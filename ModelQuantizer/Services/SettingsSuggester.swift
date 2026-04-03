//
//  SettingsSuggester.swift
//  ModelQuantizer
//
//  Smart settings recommendation engine based on device capabilities.
//

import Foundation

/// Intelligent settings suggestion engine
class SettingsSuggester {
    static let shared = SettingsSuggester()
    
    private init() {}
    
    /// Suggest optimal quantization settings for a device and model
    func suggestQuantization(
        for profile: DeviceCapabilityProfile,
        modelSize: Int64? = nil
    ) -> QuantizationRecommendation {
        
        let deviceClass = profile.deviceClass
        let totalRAM = profile.totalRAM
        let availableRAM = profile.availableRAM
        let hasNeuralEngine = profile.neuralEngineCores > 0
        let supportsRayTracing = profile.metalSupportsRayTracing
        
        // Determine optimal bits based on device class and model size
        let bits: Int
        let contextLength: Int
        let batchSize: Int
        let useGPU: Bool
        let useNeuralEngine: Bool
        let memoryLimit: Int64
        let threadCount: Int
        let useFlashAttention: Bool
        let offloadLayers: Int
        let description: String
        
        switch deviceClass {
        case .ultra:
            // iPhone 16 Pro, iPad Pro M4
            bits = modelSize.map { size in
                size > 8_000_000_000 ? 4 : 8
            } ?? 8
            contextLength = 16384
            batchSize = 4
            useGPU = true
            useNeuralEngine = hasNeuralEngine
            memoryLimit = min(availableRAM / 2, 8_000_000_000)
            threadCount = max(4, profile.cpuCores - 2)
            useFlashAttention = supportsRayTracing
            offloadLayers = 33
            description = "Optimized for ultra-high-end devices with maximum performance"
            
        case .flagship:
            // iPhone 16/15 Pro
            bits = modelSize.map { size in
                size > 8_000_000_000 ? 4 : 4
            } ?? 4
            contextLength = 8192
            batchSize = 2
            useGPU = true
            useNeuralEngine = hasNeuralEngine
            memoryLimit = min(availableRAM / 2, 6_000_000_000)
            threadCount = max(4, profile.cpuCores - 2)
            useFlashAttention = false
            offloadLayers = 25
            description = "Balanced settings for flagship devices"
            
        case .highEnd:
            // iPhone 14/13 Pro
            bits = 4
            contextLength = 4096
            batchSize = 1
            useGPU = true
            useNeuralEngine = false
            memoryLimit = min(availableRAM / 2, 4_000_000_000)
            threadCount = 4
            useFlashAttention = false
            offloadLayers = 15
            description = "Conservative settings for high-end devices"
            
        case .midRange:
            // iPhone 12/11
            bits = 4
            contextLength = 2048
            batchSize = 1
            useGPU = true
            useNeuralEngine = false
            memoryLimit = min(availableRAM / 3, 2_500_000_000)
            threadCount = 4
            useFlashAttention = false
            offloadLayers = 0
            description = "Memory-efficient settings for mid-range devices"
            
        case .entryLevel:
            // Older devices
            bits = 4
            contextLength = 1024
            batchSize = 1
            useGPU = false
            useNeuralEngine = false
            memoryLimit = min(availableRAM / 3, 1_500_000_000)
            threadCount = 2
            useFlashAttention = false
            offloadLayers = 0
            description = "Ultra-conservative settings for entry-level devices"
        }
        
        // Adjust for specific model size if provided
        if let size = modelSize {
            let estimatedQuantizedSize = Int64(Double(size) * (Double(bits) / 32.0))
            
            // If quantized model would exceed memory, increase compression
            if estimatedQuantizedSize > memoryLimit {
                return adjustForMemoryLimit(
                    original: QuantizationRecommendation(
                        bits: bits,
                        contextLength: contextLength,
                        batchSize: batchSize,
                        useGPU: useGPU,
                        useNeuralEngine: useNeuralEngine,
                        memoryLimit: memoryLimit,
                        threadCount: threadCount,
                        useFlashAttention: useFlashAttention,
                        offloadLayers: offloadLayers,
                        description: description
                    ),
                    modelSize: size,
                    availableMemory: availableRAM
                )
            }
        }
        
        // Adjust for thermal state
        let thermalAdjusted = adjustForThermalState(
            original: QuantizationRecommendation(
                bits: bits,
                contextLength: contextLength,
                batchSize: batchSize,
                useGPU: useGPU,
                useNeuralEngine: useNeuralEngine,
                memoryLimit: memoryLimit,
                threadCount: threadCount,
                useFlashAttention: useFlashAttention,
                offloadLayers: offloadLayers,
                description: description
            ),
            thermalState: profile.thermalState
        )
        
        // Adjust for battery
        return adjustForBattery(
            original: thermalAdjusted,
            batteryLevel: profile.batteryLevel,
            isLowPowerMode: profile.isLowPowerMode
        )
    }
    
    /// Get performance estimate for given settings
    func getPerformanceEstimate(
        for profile: DeviceCapabilityProfile,
        settings: InferenceSettings,
        modelParameters: Double
    ) -> PerformanceEstimate {
        
        let deviceClass = profile.deviceClass
        
        // Base tokens per second estimates by device class
        var baseTokensPerSecond: Double
        switch deviceClass {
        case .ultra: baseTokensPerSecond = 25.0
        case .flagship: baseTokensPerSecond = 18.0
        case .highEnd: baseTokensPerSecond = 12.0
        case .midRange: baseTokensPerSecond = 7.0
        case .entryLevel: baseTokensPerSecond = 3.0
        }
        
        // Adjust for quantization
        let quantizationMultiplier: Double
        switch settings.quantizationType {
        case .q2_K: quantizationMultiplier = 1.8
        case .q3_K_S, .q3_K_M, .q3_K_L: quantizationMultiplier = 1.5
        case .q4_0, .q4_1, .q4_K_S, .q4_K_M: quantizationMultiplier = 1.3
        case .q5_0, .q5_1, .q5_K_S, .q5_K_M: quantizationMultiplier = 1.1
        case .q6_K: quantizationMultiplier = 1.0
        case .q8_0: quantizationMultiplier = 0.85
        case .fp16: quantizationMultiplier = 0.6
        case .fp32: quantizationMultiplier = 0.3
        }
        
        // Adjust for context length (longer context = slower)
        let contextMultiplier = min(1.0, 4096.0 / Double(settings.contextLength))
        
        // Adjust for GPU usage
        let gpuMultiplier = settings.useGPU ? 1.5 : 0.7
        
        // Adjust for Neural Engine
        let aneMultiplier = settings.useNeuralEngine ? 1.3 : 1.0
        
        // Adjust for model size
        let sizeMultiplier = 7.0 / modelParameters // 7B as baseline
        
        let estimatedTokensPerSecond = baseTokensPerSecond *
            quantizationMultiplier *
            contextMultiplier *
            gpuMultiplier *
            aneMultiplier *
            sizeMultiplier
        
        // Estimate memory usage
        let paramCount = modelParameters * 1_000_000_000
        let bytesPerParam = settings.quantizationType.bits / 8.0
        let modelMemory = Int64(paramCount * bytesPerParam)
        
        // Add overhead for context and working memory
        let contextMemory = Int64(settings.contextLength) * Int64(settings.batchSize) * 512
        let overheadMemory = modelMemory / 10 // 10% overhead
        
        let estimatedMemoryUsage = modelMemory + contextMemory + overheadMemory
        
        // Estimate load time
        let loadTimePerGB: Double
        switch deviceClass {
        case .ultra: loadTimePerGB = 0.5
        case .flagship: loadTimePerGB = 0.8
        case .highEnd: loadTimePerGB = 1.2
        case .midRange: loadTimePerGB = 2.0
        case .entryLevel: loadTimePerGB = 3.5
        }
        
        let estimatedLoadTime = Double(modelMemory) / 1_000_000_000 * loadTimePerGB
        
        return PerformanceEstimate(
            estimatedTokensPerSecond: max(0.5, estimatedTokensPerSecond),
            estimatedMemoryUsage: estimatedMemoryUsage,
            estimatedLoadTime: estimatedLoadTime,
            recommendedBatchSize: settings.batchSize,
            canUseGPU: settings.useGPU && deviceClass.rawValue >= DeviceCapabilityProfile.DeviceClass.midRange.rawValue,
            canUseNeuralEngine: settings.useNeuralEngine && profile.neuralEngineCores > 0
        )
    }
    
    // MARK: - Private Helpers
    
    private func adjustForMemoryLimit(
        original: QuantizationRecommendation,
        modelSize: Int64,
        availableMemory: Int64
    ) -> QuantizationRecommendation {
        var bits = original.bits
        var contextLength = original.contextLength
        var memoryLimit = original.memoryLimit
        
        // Only recommend quantizers implemented in this build.
        for candidate in [8, 4] where candidate <= bits {
            let estimatedSize = Int64(Double(modelSize) / (32.0 / Double(candidate)))
            if estimatedSize < availableMemory / 2 {
                bits = candidate
                memoryLimit = estimatedSize * 2
                break
            }
        }
        
        // If still too large at lowest supported bits, reduce context.
        let smallestSupportedEstimate = Int64(Double(modelSize) / 8.0)
        if smallestSupportedEstimate > availableMemory / 2 {
            contextLength = max(512, contextLength / 2)
        }
        
        return QuantizationRecommendation(
            bits: bits,
            contextLength: contextLength,
            batchSize: 1,
            useGPU: original.useGPU,
            useNeuralEngine: false,
            memoryLimit: memoryLimit,
            threadCount: original.threadCount,
            useFlashAttention: false,
            offloadLayers: 0,
            description: "Memory-optimized settings for large model"
        )
    }
    
    private func adjustForThermalState(
        original: QuantizationRecommendation,
        thermalState: DeviceCapabilityProfile.ThermalState
    ) -> QuantizationRecommendation {
        switch thermalState {
        case .nominal, .fair:
            return original
            
        case .serious:
            return QuantizationRecommendation(
                bits: original.bits,
                contextLength: original.contextLength / 2,
                batchSize: 1,
                useGPU: false, // Disable GPU to reduce heat
                useNeuralEngine: original.useNeuralEngine,
                memoryLimit: original.memoryLimit,
                threadCount: max(2, original.threadCount - 2),
                useFlashAttention: false,
                offloadLayers: original.offloadLayers / 2,
                description: "Thermally-constrained settings"
            )
            
        case .critical:
            return QuantizationRecommendation(
                bits: 4,
                contextLength: 1024,
                batchSize: 1,
                useGPU: false,
                useNeuralEngine: false,
                memoryLimit: original.memoryLimit / 2,
                threadCount: 2,
                useFlashAttention: false,
                offloadLayers: 0,
                description: "Emergency thermal settings - very limited performance"
            )
        }
    }
    
    private func adjustForBattery(
        original: QuantizationRecommendation,
        batteryLevel: Float,
        isLowPowerMode: Bool
    ) -> QuantizationRecommendation {
        // If battery is low or low power mode is on, be more conservative
        if batteryLevel < 0.2 || isLowPowerMode {
            return QuantizationRecommendation(
                bits: original.bits,
                contextLength: original.contextLength / 2,
                batchSize: 1,
                useGPU: false, // GPU uses more power
                useNeuralEngine: original.useNeuralEngine, // ANE is power-efficient
                memoryLimit: original.memoryLimit,
                threadCount: max(2, original.threadCount - 2),
                useFlashAttention: false,
                offloadLayers: original.offloadLayers / 2,
                description: isLowPowerMode ? "Low power mode settings" : "Low battery settings"
            )
        }
        
        return original
    }
}
