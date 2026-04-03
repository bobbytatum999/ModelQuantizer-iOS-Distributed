//
//  DeviceScanner.swift
//  ModelQuantizer
//
//  Comprehensive device scanner for ML model optimization.
//

import Foundation
import Metal
import MachO
import Darwin
import SystemConfiguration

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Represents the device capability profile for model quantization
struct DeviceCapabilityProfile: Codable, Equatable {
    let deviceModel: String
    let osVersion: String
    let deviceClass: DeviceClass
    let totalRAM: Int64
    let availableRAM: Int64
    let cpuCores: Int
    let cpuArchitecture: String
    let gpuName: String
    let gpuCores: Int
    let metalVersion: String
    let metalSupportsFloat16: Bool
    let metalSupportsBFloat16: Bool
    let metalSupportsRayTracing: Bool
    let neuralEngineCores: Int
    let neuralEngineTops: Double
    let storageTotal: UInt64
    let storageAvailable: UInt64
    let thermalState: ThermalState
    let batteryLevel: Float
    let isLowPowerMode: Bool
    
    enum DeviceClass: String, Codable, CaseIterable {
        case entryLevel = "Entry Level"
        case midRange = "Mid Range"
        case highEnd = "High End"
        case flagship = "Flagship"
        case ultra = "Ultra"
        
        var recommendedMaxModelSize: Int64 {
            switch self {
            case .entryLevel: return 2_000_000_000      // 2GB
            case .midRange: return 4_000_000_000       // 4GB
            case .highEnd: return 7_000_000_000        // 7GB
            case .flagship: return 12_000_000_000      // 12GB
            case .ultra: return 24_000_000_000         // 24GB
            }
        }
        
        var recommendedContextLength: Int {
            switch self {
            case .entryLevel: return 2048
            case .midRange: return 4096
            case .highEnd: return 8192
            case .flagship: return 16384
            case .ultra: return 32768
            }
        }
        
        var recommendedBatchSize: Int {
            switch self {
            case .entryLevel: return 1
            case .midRange: return 2
            case .highEnd: return 4
            case .flagship: return 8
            case .ultra: return 16
            }
        }
    }
    
    enum ThermalState: String, Codable {
        case nominal = "Nominal"
        case fair = "Fair"
        case serious = "Serious"
        case critical = "Critical"
        
        init(from state: ProcessInfo.ThermalState) {
            switch state {
            case .nominal: self = .nominal
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            @unknown default: self = .nominal
            }
        }
    }
}

/// Comprehensive device scanner for ML model optimization
class DeviceScanner: ObservableObject, @unchecked Sendable {
    static let shared = DeviceScanner()
    
    @Published var currentProfile: DeviceCapabilityProfile?
    @Published var isScanning = false
    @Published var lastScanDate: Date?
    
    private var timer: Timer?
    private let metalDevice: MTLDevice?
    
    private init() {
        self.metalDevice = MTLCreateSystemDefaultDevice()
        performScan()
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func performScan() {
        isScanning = true
        
        Task {
            let profile = await createProfile()
            await MainActor.run {
                self.currentProfile = profile
                self.lastScanDate = Date()
                self.isScanning = false
            }
        }
    }
    
    @MainActor
    func getRecommendedQuantization(for modelSize: Int64? = nil) -> QuantizationRecommendation {
        guard let profile = currentProfile else {
            return QuantizationRecommendation.default
        }
        
        return SettingsSuggester.shared.suggestQuantization(for: profile, modelSize: modelSize)
    }
    
    // MARK: - Private Methods
    
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.performScan()
        }
    }
    
    private func createProfile() async -> DeviceCapabilityProfile {
        let deviceModel = getDeviceModel()
        let deviceClass = classifyDevice(deviceModel)
        let ram = getRAMInfo()
        let cpu = getCPUInfo()
        let gpu = getGPUInfo()
        let metal = getMetalCapabilities()
        let neural = getNeuralEngineInfo()
        let storage = getStorageInfo()
        
        return DeviceCapabilityProfile(
            deviceModel: deviceModel,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceClass: deviceClass,
            totalRAM: ram.total,
            availableRAM: ram.available,
            cpuCores: cpu.cores,
            cpuArchitecture: cpu.architecture,
            gpuName: gpu.name,
            gpuCores: gpu.cores,
            metalVersion: metal.version,
            metalSupportsFloat16: metal.supportsFloat16,
            metalSupportsBFloat16: metal.supportsBFloat16,
            metalSupportsRayTracing: metal.supportsRayTracing,
            neuralEngineCores: neural.cores,
            neuralEngineTops: neural.tops,
            storageTotal: storage.total,
            storageAvailable: storage.available,
            thermalState: DeviceCapabilityProfile.ThermalState(from: ProcessInfo.processInfo.thermalState),
            batteryLevel: await MainActor.run { getBatteryLevel() },
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
    
    // MARK: - Device Information Gathering
    
    private func getDeviceModel() -> String {
        #if targetEnvironment(simulator)
        let env = ProcessInfo.processInfo.environment
        if let simIdentifier = env["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(mapToMarketingName(simIdentifier)) (Simulator)"
        }
        return "Simulator"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        return mapToMarketingName(identifier)
        #endif
    }
    
    private func mapToMarketingName(_ identifier: String) -> String {
        let deviceMap: [String: String] = [
            // iPhone 16 Series
            "iPhone17,1": "iPhone 16 Pro Max",
            "iPhone17,2": "iPhone 16 Pro",
            "iPhone17,3": "iPhone 16 Plus",
            "iPhone17,4": "iPhone 16",
            // iPhone 15 Series
            "iPhone16,1": "iPhone 15 Pro Max",
            "iPhone16,2": "iPhone 15 Pro",
            "iPhone15,4": "iPhone 15 Plus",
            "iPhone15,5": "iPhone 15",
            // iPhone 14 Series
            "iPhone15,2": "iPhone 14 Pro Max",
            "iPhone15,3": "iPhone 14 Pro",
            "iPhone14,7": "iPhone 14 Plus",
            "iPhone14,8": "iPhone 14",
            // iPhone 13 Series
            "iPhone14,2": "iPhone 13 Pro Max",
            "iPhone14,3": "iPhone 13 Pro",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            // iPhone 12 Series
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            // iPhone 11 Series
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            // iPhone SE
            "iPhone14,6": "iPhone SE (3rd gen)",
            "iPhone12,8": "iPhone SE (2nd gen)",
            // iPad Pro
            "iPad16,1": "iPad Pro 13\" (M4)",
            "iPad16,2": "iPad Pro 11\" (M4)",
            "iPad14,8": "iPad Pro 12.9\" (M2)",
            "iPad14,9": "iPad Pro 11\" (M2)",
            // iPad Air
            "iPad14,1": "iPad Air 11\" (M2)",
            "iPad14,2": "iPad Air 13\" (M2)",
            // iPad
            "iPad13,1": "iPad (10th gen)",
            "iPad13,2": "iPad (10th gen)",
        ]
        
        return deviceMap[identifier] ?? identifier
    }
    
    private func classifyDevice(_ model: String) -> DeviceCapabilityProfile.DeviceClass {
        let ultraDevices = ["iPhone 16 Pro Max", "iPhone 16 Pro", "iPhone 15 Pro Max", "iPhone 15 Pro", "iPad Pro 13\" (M4)", "iPad Pro 11\" (M4)"]
        let flagshipDevices = ["iPhone 16 Plus", "iPhone 16", "iPhone 15 Plus", "iPhone 15", "iPhone 14 Pro Max", "iPhone 14 Pro", "iPad Pro 12.9\" (M2)", "iPad Pro 11\" (M2)"]
        let highEndDevices = ["iPhone 14 Plus", "iPhone 14", "iPhone 13 Pro Max", "iPhone 13 Pro", "iPhone 13", "iPad Air 11\" (M2)", "iPad Air 13\" (M2)"]
        let midRangeDevices = ["iPhone 13 mini", "iPhone 12 Pro Max", "iPhone 12 Pro", "iPhone 12", "iPhone 11 Pro Max", "iPhone 11 Pro", "iPhone 11"]
        
        if ultraDevices.contains(where: { model.contains($0) }) {
            return .ultra
        } else if flagshipDevices.contains(where: { model.contains($0) }) {
            return .flagship
        } else if highEndDevices.contains(where: { model.contains($0) }) {
            return .highEnd
        } else if midRangeDevices.contains(where: { model.contains($0) }) {
            return .midRange
        }
        return .entryLevel
    }
    
    private func getRAMInfo() -> (total: Int64, available: Int64) {
        let totalRAM = Int64(ProcessInfo.processInfo.physicalMemory)
        
        // Get available memory using vm_statistics64
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        
        var available: Int64 = 0
        if result == KERN_SUCCESS {
            let pageSize = Int64(getpagesize())
            let freePages = Int64(stats.free_count)
            let inactivePages = Int64(stats.inactive_count)
            available = (freePages + inactivePages) * pageSize
        }
        
        return (totalRAM, available)
    }
    
    private func getCPUInfo() -> (cores: Int, architecture: String) {
        let cores = ProcessInfo.processInfo.processorCount
        
        var architecture = "Unknown"
        #if arch(arm64)
        architecture = "ARM64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #endif
        
        return (cores, architecture)
    }
    
    private func getGPUInfo() -> (name: String, cores: Int) {
        guard let device = metalDevice else {
            return ("Unknown", 0)
        }
        
        let name = device.name
        
        // Estimate GPU cores based on device class
        let model = getDeviceModel()
        var cores = 4 // Default
        
        if model.contains("Pro") || model.contains("Max") {
            cores = device.supportsRaytracing ? 10 : 6
        } else if model.contains("Plus") || model.contains("iPhone 16") {
            cores = 5
        }
        
        return (name, cores)
    }
    
    private func getMetalCapabilities() -> (version: String, supportsFloat16: Bool, supportsBFloat16: Bool, supportsRayTracing: Bool) {
        guard let device = metalDevice else {
            return ("Not Available", false, false, false)
        }
        
        let version: String
        if #available(iOS 18.0, *) {
            version = "Metal 3.2"
        } else if #available(iOS 17.0, *) {
            version = "Metal 3.1"
        } else {
            version = "Metal 3.0"
        }
        
        // Check for float16/bfloat16 support using GPU family
        let supports16BitFloat = device.supportsFamily(.apple3)
        let supportsBFloat16 = false // BFloat16 not widely supported
        
        return (
            version,
            supports16BitFloat,
            supportsBFloat16,
            device.supportsRaytracing
        )
    }
    
    private func getNeuralEngineInfo() -> (cores: Int, tops: Double) {
        // Estimate Neural Engine cores based on device
        let model = getDeviceModel()
        var cores = 8
        var tops = 15.8
        
        if model.contains("16 Pro") {
            cores = 16
            tops = 35.0
        } else if model.contains("15 Pro") || model.contains("16") {
            cores = 16
            tops = 35.0
        } else if model.contains("14 Pro") {
            cores = 16
            tops = 17.0
        } else if model.contains("Pro") {
            cores = 16
            tops = 15.8
        } else if model.contains("M4") {
            cores = 16
            tops = 38.0
        } else if model.contains("M2") {
            cores = 16
            tops = 15.8
        }
        
        return (cores, tops)
    }
    
    private func getStorageInfo() -> (total: UInt64, available: UInt64) {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(values.volumeAvailableCapacity ?? 0)
            
            return (total, available)
        } catch {
            return (0, 0)
        }
    }
    
    @MainActor
    private func getBatteryLevel() -> Float {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
        #else
        return 1.0 // Default battery level for macOS
        #endif
    }
}

// MARK: - Quantization Recommendation

struct QuantizationRecommendation: Codable {
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
    
    static let `default` = QuantizationRecommendation(
        bits: 4,
        contextLength: 2048,
        batchSize: 1,
        useGPU: true,
        useNeuralEngine: true,
        memoryLimit: 2_000_000_000,
        threadCount: 4,
        useFlashAttention: false,
        offloadLayers: 0,
        description: "Default conservative settings"
    )
}
