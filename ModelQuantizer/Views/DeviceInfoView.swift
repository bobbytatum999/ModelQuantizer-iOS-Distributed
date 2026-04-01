//
//  DeviceInfoView.swift
//  ModelQuantizer
//
//  Detailed device information view.
//

import SwiftUI

struct DeviceInfoView: View {
    @StateObject private var scanner = DeviceScanner.shared
    @State private var selectedSection = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerView
                
                // Device Overview
                deviceOverviewCard
                
                // Section Picker
                sectionPicker
                
                // Section Content
                switch selectedSection {
                case 0:
                    hardwareSpecsSection
                case 1:
                    mlCapabilitiesSection
                case 2:
                    performanceSection
                default:
                    EmptyView()
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .refreshable {
            scanner.performScan()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device Info")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Detailed hardware specifications")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Device Overview
    
    private var deviceOverviewCard: some View {
        LiquidGlassCard {
            VStack(spacing: 20) {
                // Device icon and name
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.4), .cyan.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(spacing: 4) {
                        Text(scanner.currentProfile?.deviceModel ?? "Unknown Device")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                        
                        if let deviceClass = scanner.currentProfile?.deviceClass {
                            Text(deviceClass.rawValue)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.cyan.opacity(0.2))
                                )
                        }
                    }
                }
                
                Divider()
                    .background(.white.opacity(0.2))
                
                // Quick stats
                HStack(spacing: 20) {
                    if let profile = scanner.currentProfile {
                        QuickStatView(
                            icon: "memorychip",
                            value: formatBytes(profile.totalRAM),
                            label: "RAM"
                        )
                        
                        Divider()
                            .background(.white.opacity(0.2))
                        
                        QuickStatView(
                            icon: "cpu",
                            value: "\(profile.cpuCores)",
                            label: "Cores"
                        )
                        
                        Divider()
                            .background(.white.opacity(0.2))
                        
                        QuickStatView(
                            icon: "bolt.fill",
                            value: "\(profile.neuralEngineCores)",
                            label: "ANE"
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Section Picker
    
    private var sectionPicker: some View {
        Picker("Section", selection: $selectedSection) {
            Text("Hardware").tag(0)
            Text("ML Capabilities").tag(1)
            Text("Performance").tag(2)
        }
        .pickerStyle(SegmentedPickerStyle())
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Hardware Specs Section
    
    private var hardwareSpecsSection: some View {
        VStack(spacing: 16) {
            if let profile = scanner.currentProfile {
                // CPU Card
                SpecCard(title: "CPU", icon: "cpu") {
                    VStack(spacing: 12) {
                        SpecRow(label: "Architecture", value: profile.cpuArchitecture)
                        SpecRow(label: "Cores", value: "\(profile.cpuCores)")
                        SpecRow(label: "Available RAM", value: formatBytes(profile.availableRAM))
                        SpecRow(label: "Total RAM", value: formatBytes(profile.totalRAM))
                    }
                }
                
                // GPU Card
                SpecCard(title: "GPU", icon: "gpu") {
                    VStack(spacing: 12) {
                        SpecRow(label: "Name", value: profile.gpuName)
                        SpecRow(label: "GPU Cores", value: "\(profile.gpuCores)")
                        SpecRow(label: "Metal Version", value: profile.metalVersion)
                    }
                }
                
                // Storage Card
                SpecCard(title: "Storage", icon: "externaldrive") {
                    VStack(spacing: 12) {
                        SpecRow(label: "Total", value: formatBytes(profile.storageTotal))
                        SpecRow(label: "Available", value: formatBytes(profile.storageAvailable))
                        
                        // Storage bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(0.2))
                                    .frame(height: 8)
                                
                                if profile.storageTotal > 0 {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            LinearGradient(
                                                colors: [.cyan, .purple],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(
                                            width: geo.size.width * CGFloat(Double(profile.storageTotal - profile.storageAvailable) / Double(profile.storageTotal)),
                                            height: 8
                                        )
                                }
                            }
                        }
                        .frame(height: 8)
                    }
                }
                
                // Power Card
                SpecCard(title: "Power & Thermal", icon: "battery.100") {
                    VStack(spacing: 12) {
                        SpecRow(label: "Battery Level", value: "\(Int(profile.batteryLevel * 100))%")
                        SpecRow(label: "Low Power Mode", value: profile.isLowPowerMode ? "On" : "Off")
                        SpecRow(label: "Thermal State", value: profile.thermalState.rawValue)
                    }
                }
            }
        }
    }
    
    // MARK: - ML Capabilities Section
    
    private var mlCapabilitiesSection: some View {
        VStack(spacing: 16) {
            if let profile = scanner.currentProfile {
                // Neural Engine Card
                SpecCard(title: "Neural Engine", icon: "bolt.fill") {
                    VStack(spacing: 12) {
                        SpecRow(label: "Cores", value: "\(profile.neuralEngineCores)")
                        SpecRow(label: "Compute Power", value: "\(String(format: "%.1f", profile.neuralEngineTops)) TOPS")
                        
                        HStack {
                            Text("Status")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(profile.neuralEngineCores > 0 ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(profile.neuralEngineCores > 0 ? "Available" : "Unavailable")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(profile.neuralEngineCores > 0 ? .green : .red)
                        }
                    }
                }
                
                // Metal Features Card
                SpecCard(title: "Metal Features", icon: "metallogo") {
                    VStack(spacing: 12) {
                        FeatureRow(
                            label: "Float16 Support",
                            enabled: profile.metalSupportsFloat16
                        )
                        FeatureRow(
                            label: "BFloat16 Support",
                            enabled: profile.metalSupportsBFloat16
                        )
                        FeatureRow(
                            label: "Ray Tracing",
                            enabled: profile.metalSupportsRayTracing
                        )
                    }
                }
                
                // Recommendations Card
                SpecCard(title: "ML Recommendations", icon: "wand.and.stars") {
                    VStack(spacing: 12) {
                        let rec = SettingsSuggester.shared.suggestQuantization(for: profile)
                        
                        RecommendationRow(
                            icon: "text.alignleft",
                            label: "Context Length",
                            value: "\(rec.contextLength) tokens"
                        )
                        
                        RecommendationRow(
                            icon: "number",
                            label: "Quantization",
                            value: "Q\(rec.bits)"
                        )
                        
                        RecommendationRow(
                            icon: "cpu",
                            label: "GPU Layers",
                            value: "\(rec.offloadLayers)"
                        )
                        
                        RecommendationRow(
                            icon: "memorychip",
                            label: "Memory Limit",
                            value: formatBytes(rec.memoryLimit)
                        )
                        
                        Divider()
                            .background(.white.opacity(0.2))
                        
                        Text(rec.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
    
    // MARK: - Performance Section
    
    private var performanceSection: some View {
        VStack(spacing: 16) {
            if let profile = scanner.currentProfile {
                // Device Class Info
                SpecCard(title: "Device Classification", icon: "sparkles") {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.deviceClass.rawValue)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.cyan)
                                
                                Text("Based on hardware capabilities")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            // Class badge
                            ZStack {
                                Circle()
                                    .fill(deviceClassColor(profile.deviceClass).opacity(0.3))
                                    .frame(width: 60, height: 60)
                                
                                Text(String(profile.deviceClass.rawValue.prefix(1)))
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(deviceClassColor(profile.deviceClass))
                            }
                        }
                        
                        Divider()
                            .background(.white.opacity(0.2))
                        
                        VStack(spacing: 10) {
                            CapabilityRow(
                                label: "Max Model Size",
                                value: formatBytes(profile.deviceClass.recommendedMaxModelSize)
                            )
                            CapabilityRow(
                                label: "Recommended Context",
                                value: "\(profile.deviceClass.recommendedContextLength) tokens"
                            )
                            CapabilityRow(
                                label: "Batch Size",
                                value: "\(profile.deviceClass.recommendedBatchSize)"
                            )
                        }
                    }
                }
                
                // Performance Tiers
                SpecCard(title: "Supported Model Sizes", icon: "chart.bar") {
                    VStack(spacing: 12) {
                        ModelSizeRow(
                            size: "1-3B",
                            quantization: "Q4-Q8",
                            supported: true,
                            recommended: profile.deviceClass.rawValue >= DeviceCapabilityProfile.DeviceClass.entryLevel.rawValue
                        )
                        
                        ModelSizeRow(
                            size: "7B",
                            quantization: "Q4-Q5",
                            supported: profile.deviceClass.rawValue >= DeviceCapabilityProfile.DeviceClass.midRange.rawValue,
                            recommended: profile.deviceClass.rawValue >= DeviceCapabilityProfile.DeviceClass.highEnd.rawValue
                        )
                        
                        ModelSizeRow(
                            size: "13B",
                            quantization: "Q4",
                            supported: profile.deviceClass.rawValue >= DeviceCapabilityProfile.DeviceClass.highEnd.rawValue,
                            recommended: profile.deviceClass.rawValue >= DeviceCapabilityProfile.DeviceClass.flagship.rawValue
                        )
                        
                        ModelSizeRow(
                            size: "30B+",
                            quantization: "Q2-Q4",
                            supported: profile.deviceClass.rawValue >= DeviceCapabilityProfile.DeviceClass.flagship.rawValue,
                            recommended: profile.deviceClass.rawValue >= DeviceCapabilityProfile.DeviceClass.ultra.rawValue
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    private func deviceClassColor(_ deviceClass: DeviceCapabilityProfile.DeviceClass) -> Color {
        switch deviceClass {
        case .entryLevel: return .gray
        case .midRange: return .blue
        case .highEnd: return .green
        case .flagship: return .purple
        case .ultra: return .orange
        }
    }
}

// MARK: - Supporting Views

struct QuickStatView: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.cyan)
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

struct SpecCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.cyan)
                
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            content
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SpecRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct FeatureRow: View {
    let label: String
    let enabled: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 14))
                Text(enabled ? "Yes" : "No")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(enabled ? .green : .red)
        }
    }
}

struct RecommendationRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.cyan)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct CapabilityRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan)
        }
    }
}

struct ModelSizeRow: View {
    let size: String
    let quantization: String
    let supported: Bool
    let recommended: Bool
    
    var body: some View {
        HStack {
            // Size badge
            Text(size)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(supported ? Color.purple.opacity(0.4) : Color.gray.opacity(0.3))
                )
            
            // Quantization
            Text(quantization)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            // Status
            if recommended {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                    Text("Recommended")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.2))
                )
            } else if supported {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10))
                    Text("Supported")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.cyan.opacity(0.2))
                )
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                    Text("Not Recommended")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.red.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.2))
                )
            }
        }
        .opacity(supported ? 1.0 : 0.5)
    }
}

#Preview {
    DeviceInfoView()
        .preferredColorScheme(.dark)
}
