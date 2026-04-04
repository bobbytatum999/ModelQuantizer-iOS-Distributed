//
//  QuantizeView.swift
//  ModelQuantizer
//
//  Main quantization interface with real Hugging Face API integration.
//

import SwiftUI

struct QuantizeView: View {
    @StateObject private var viewModel = QuantizeViewModel()
    @State private var showingQuantizationSheet = false
    @State private var showingAuthAlert = false
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerView
                    
                    // Search Bar
                    searchBar
                    
                    // Selected Model Card
                    if let model = viewModel.selectedModel {
                        selectedModelCard(model)
                    }
                    
                    // Model List
                    if viewModel.isSearching {
                        loadingView
                    } else if !viewModel.filteredModels.isEmpty {
                        modelList
                    } else {
                        emptyStateView
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            
            // Quantization Progress Overlay
            if viewModel.quantizationStatus.isActive {
                quantizationOverlay
            }
        }
        .sheet(isPresented: $showingQuantizationSheet) {
            if let model = viewModel.selectedModel {
                QuantizationConfigSheet(viewModel: viewModel, model: model)
            }
        }
        .alert("Authentication Required", isPresented: $showingAuthAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Some models require Hugging Face authentication. Please add your token in Settings.")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quantize Model")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Search Hugging Face and quantize models")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            
            Text("Experimental: output quality/compatibility may vary by model.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange.opacity(0.9))
            
            if let profile = viewModel.deviceProfile {
                Text("Device: \(profile.deviceModel) • \(profile.osVersion)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.6))
            
            TextField("Search Hugging Face models...", text: $viewModel.searchQuery)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            if viewModel.isSearching {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            } else if !viewModel.searchQuery.isEmpty {
                Button(action: { viewModel.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Selected Model Card
    
    private func selectedModelCard(_ model: HFModel) -> some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected Model")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Text(model.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    Button(action: { viewModel.selectedModel = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                }
                
                Text(model.description)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    TagView(text: model.parameters, color: .purple)
                    TagView(text: model.architecture.rawValue, color: .cyan)
                    
                    Spacer()
                    
                    Text(viewModel.formatBytes(model.sizeBytes))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Divider()
                    .background(.white.opacity(0.2))
                
                // Recommended settings preview
                if let rec = viewModel.recommendedSettings {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended for your device:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 12))
                                Text("Q\(rec.bits)")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.cyan)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "number")
                                    .font(.system(size: 12))
                                Text("\(rec.contextLength) ctx")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.green)
                            
                            if rec.useNeuralEngine {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 12))
                                    Text("ANE")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                
                // Performance estimate
                if let estimate = viewModel.getPerformanceEstimate() {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Estimated Performance:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        HStack(spacing: 16) {
                            PerformanceBadge(
                                icon: "speedometer",
                                value: "~\(String(format: "%.1f", estimate.estimatedTokensPerSecond))",
                                unit: "tok/s"
                            )
                            
                            PerformanceBadge(
                                icon: "memorychip",
                                value: viewModel.formatBytes(estimate.estimatedMemoryUsage),
                                unit: "RAM"
                            )
                        }
                    }
                }
                
                // Quantize button
                Button(action: {
                    if model.modelId.hasPrefix("meta-llama/") && HuggingFaceAPI.shared.getAuthToken() == nil {
                        showingAuthAlert = true
                    } else {
                        showingQuantizationSheet = true
                    }
                }) {
                    HStack {
                        Image(systemName: "cpu.fill")
                        Text("Configure & Quantize")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.purple.opacity(0.8), .cyan.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
    
    // MARK: - Model List
    
    private var modelList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Models")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("\(viewModel.filteredModels.count) found")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            LazyVStack(spacing: 10) {
                ForEach(viewModel.filteredModels) { model in
                    ModelRow(model: model, isSelected: viewModel.selectedModel?.id == model.id) {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.selectModel(model)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Searching Hugging Face...")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))
            
            Text("No models found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(viewModel.searchQuery.isEmpty ? "Start typing to search" : "Try a different search term")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    // MARK: - Quantization Overlay
    
    private var quantizationOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            LiquidGlassCard {
                VStack(spacing: 24) {
                    // Progress ring
                    ZStack {
                        LiquidProgressRing(
                            progress: viewModel.progress,
                            lineWidth: 12,
                            color: .cyan
                        )
                        .frame(width: 140, height: 140)
                        
                        VStack {
                            Text("\(Int(viewModel.progress * 100))%")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    
                    VStack(spacing: 8) {
                        Text(viewModel.currentStage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        
                        if let model = viewModel.selectedModel {
                            Text(model.name)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    
                    // Cancel button
                    Button(action: { viewModel.cancelQuantization() }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                }
                .padding(32)
            }
            .frame(maxWidth: 320)
        }
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: HFModel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Model icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.purple.opacity(0.4) : Color.purple.opacity(0.2))
                        .frame(width: 48, height: 48)

                    if let iconURL = model.publisherIconURL {
                        AsyncImage(url: iconURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 34, height: 34)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                PublisherInitialBadge(publisher: model.publisher)
                            }
                        }
                    } else {
                        PublisherInitialBadge(publisher: model.publisher)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(model.publisherDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                    
                    Text(model.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        TagView(text: model.parameters, color: .purple)
                        TagView(text: model.architecture.rawValue, color: .cyan)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10))
                            Text(formatNumber(model.downloads))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.white.opacity(0.5))
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.purple)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.purple.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.purple.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
}

private struct PublisherInitialBadge: View {
    let publisher: String

    private var initial: String {
        String((publisher.first ?? "M")).uppercased()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.15))
            .frame(width: 34, height: 34)
            .overlay(
                Text(initial)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Quantization Config Sheet

struct QuantizationConfigSheet: View {
    @ObservedObject var viewModel: QuantizeViewModel
    let model: HFModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                LiquidGlassBackground()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Model info
                        modelInfoSection
                        
                        // Quantization type
                        quantizationTypeSection
                        
                        // Context length
                        contextLengthSection
                        
                        // Advanced options
                        advancedOptionsSection
                        
                        // Start button
                        startButton
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("Configure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var modelInfoSection: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                
                Text(model.description)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                
                HStack(spacing: 12) {
                    TagView(text: model.parameters, color: .purple)
                    TagView(text: model.architecture.rawValue, color: .cyan)
                    TagView(text: viewModel.formatBytes(model.sizeBytes), color: .green)
                }
            }
        }
    }
    
    private var quantizationTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quantization Type")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(model.architecture.supportedQuantizations, id: \.self) { type in
                    QuantizationTypeButton(
                        type: type,
                        isSelected: viewModel.selectedQuantization == type,
                        recommendedBits: viewModel.recommendedSettings?.bits
                    ) {
                        viewModel.selectedQuantization = type
                    }
                }
            }
        }
    }
    
    private var contextLengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Context Length")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("\(viewModel.customContextLength) tokens")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.cyan)
            }
            
            Slider(
                value: Binding(
                    get: { Double(viewModel.customContextLength) },
                    set: { viewModel.customContextLength = Int($0) }
                ),
                in: 512...32768,
                step: 512
            )
            .tint(.cyan)
            
            HStack {
                Text("512")
                Spacer()
                Text("Recommended: \(viewModel.recommendedSettings?.contextLength ?? 4096)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("32K")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
        }
    }
    
    private var advancedOptionsSection: some View {
        DisclosureGroup {
            VStack(spacing: 16) {
                Toggle("Use GPU Acceleration", isOn: $viewModel.useGPU)
                    .foregroundStyle(.white)
                
                Toggle("Use Neural Engine", isOn: $viewModel.useNeuralEngine)
                    .foregroundStyle(.white)
                    .disabled(!viewModel.useGPU)
                
                Toggle("Flash Attention", isOn: $viewModel.useFlashAttention)
                    .foregroundStyle(.white)
                
                Toggle("Memory Mapping", isOn: $viewModel.useMemoryMapping)
                    .foregroundStyle(.white)
                
                if let rec = viewModel.recommendedSettings {
                    Button("Reset to Device Recommended") {
                        viewModel.useGPU = rec.useGPU
                        viewModel.useNeuralEngine = rec.useNeuralEngine
                        viewModel.useFlashAttention = rec.useFlashAttention
                        viewModel.useMemoryMapping = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 12)
        } label: {
            Text("Advanced Options")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
        .tint(.white)
    }
    
    private var startButton: some View {
        Button(action: {
            dismiss()
            viewModel.startQuantization()
        }) {
            HStack {
                Image(systemName: "play.fill")
                Text("Start Quantization")
            }
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [.purple, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .purple.opacity(0.4), radius: 15, x: 0, y: 8)
        }
    }
}

// MARK: - Supporting Views

struct TagView: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.2))
            )
    }
}

struct PerformanceBadge: View {
    let icon: String
    let value: String
    let unit: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
            
            Text(unit)
                .font(.system(size: 11))
                .opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }
}

struct QuantizationTypeButton: View {
    let type: QuantizationType
    let isSelected: Bool
    let recommendedBits: Int?
    let action: () -> Void
    
    var isRecommended: Bool {
        guard let recBits = recommendedBits else { return false }
        return Int(type.bits) == recBits
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(type.rawValue)
                        .font(.system(size: 16, weight: .bold))
                    
                    Spacer()
                    
                    if isRecommended {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                    }
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                    }
                }
                
                Text("\(Int(type.bits))-bit")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                
                Text("\(String(format: "%.1f", type.compressionRatio))× compression")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding()
            .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.purple.opacity(0.4) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.purple : Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    QuantizeView()
        .preferredColorScheme(.dark)
}
