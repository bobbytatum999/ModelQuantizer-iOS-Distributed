//
//  HomeView.swift
//  ModelQuantizer
//
//  Home dashboard view.
//

import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var scanner = DeviceScanner.shared
    @StateObject private var quantizer = QuantizationEngine.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerView
                
                // Device Overview Card
                deviceOverviewCard
                
                // Quick Actions
                quickActionsSection
                
                // Recent Quantizations
                recentQuantizationsSection
                
                // Storage Usage
                storageSection
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .refreshable {
            scanner.performScan()
            viewModel.loadRecentQuantizations()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ModelQuantizer")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text("Quantize AI models on your device")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Device Overview
    
    private var deviceOverviewCard: some View {
        LiquidGlassCard {
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Device")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Text(scanner.currentProfile?.deviceModel ?? "Scanning...")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        
                        if let deviceClass = scanner.currentProfile?.deviceClass {
                            Text(deviceClass.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.cyan)
                        }
                    }
                    
                    Spacer()
                    
                    // Device icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.4), .cyan.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
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
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            
            HStack(spacing: 12) {
                NavigationLink(destination: QuantizeView()) {
                    QuickActionButton(
                        icon: "cpu.fill",
                        title: "Quantize",
                        subtitle: "New Model",
                        color: .purple
                    )
                }
                
                NavigationLink(destination: ModelLibraryView()) {
                    QuickActionButton(
                        icon: "folder.fill",
                        title: "My",
                        subtitle: "Models",
                        color: .cyan
                    )
                }
            }
        }
    }
    
    // MARK: - Recent Quantizations
    
    private var recentQuantizationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Quantizations")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                if !viewModel.recentQuantizations.isEmpty {
                    NavigationLink(destination: ModelLibraryView()) {
                        Text("See All")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.cyan)
                    }
                }
            }
            
            if viewModel.recentQuantizations.isEmpty {
                EmptyStateView(
                    icon: "cube.box",
                    title: "No quantizations yet",
                    subtitle: "Quantize your first model to see it here"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.recentQuantizations.prefix(3)) { model in
                        RecentModelRow(model: model)
                    }
                }
            }
        }
    }
    
    // MARK: - Storage Section
    
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            
            if let profile = scanner.currentProfile {
                LiquidGlassCard {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Quantized Models")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.7))
                                
                                Text("\(viewModel.quantizedModelCount) models")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            
                            Spacer()
                            
                            Text(formatBytes(viewModel.totalQuantizedSize))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.cyan)
                        }
                        
                        Divider()
                            .background(.white.opacity(0.2))
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Available Space")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.7))
                                
                                Text(formatBytes(profile.storageAvailable))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            
                            Spacer()
                            
                            // Storage bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.white.opacity(0.2))
                                        .frame(height: 8)
                                    
                                    if profile.storageTotal > 0 {
                                        let usedRatio = Double(profile.storageTotal - profile.storageAvailable) / Double(profile.storageTotal)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.cyan, .purple],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(
                                                width: geo.size.width * CGFloat(usedRatio),
                                                height: 8
                                            )
                                    }
                                }
                            }
                            .frame(width: 80, height: 8)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        formatBytes(Int64(bytes))
    }
}

// MARK: - Supporting Views

struct QuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
            
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 14))
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct RecentModelRow: View {
    let model: QuantizedModel
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "cube.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    TagView(text: model.quantization.rawValue, color: .cyan)
                    
                    Text(formatBytes(model.size))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.3))
            
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - View Model

class HomeViewModel: ObservableObject {
    @Published var recentQuantizations: [QuantizedModel] = []
    @Published var quantizedModelCount = 0
    @Published var totalQuantizedSize: Int64 = 0
    
    init() {
        loadRecentQuantizations()
    }
    
    func loadRecentQuantizations() {
        let models = QuantizationEngine.shared.getQuantizedModels()
        recentQuantizations = models
        quantizedModelCount = models.count
        totalQuantizedSize = models.reduce(0) { $0 + $1.size }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
