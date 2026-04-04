//
//  ModelDownloadView.swift
//  ModelQuantizer
//
//  Created by AI Assistant on 2026-03-31.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ModelDownloadView: View {
    @StateObject private var viewModel = ModelDownloadViewModel()
    @State private var selectedCategory: ModelCategory = .all
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerView
                
                // Category Filter
                categoryFilter
                
                // Featured Models
                if selectedCategory == .all {
                    featuredSection
                }
                
                // Model List
                modelListSection
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .sheet(item: $viewModel.selectedModel) { model in
            DownloadModelDetailSheet(model: model, viewModel: viewModel)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Library")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Browse and download AI models")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Category Filter
    
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ModelCategory.allCases) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Featured Section
    
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Featured")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.featuredModels) { model in
                        FeaturedModelCard(model: model) {
                            viewModel.selectedModel = model
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Model List Section
    
    private var modelListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedCategory == .all ? "All Models" : selectedCategory.rawValue)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("\(filteredModels.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
            }
            
            LazyVStack(spacing: 10) {
                ForEach(filteredModels) { model in
                    LibraryModelRow(model: model) {
                        viewModel.selectedModel = model
                    }
                }
            }
        }
    }
    
    private var filteredModels: [HFModel] {
        if selectedCategory == .all {
            return viewModel.models
        }
        return viewModel.models.filter { model in
            model.tags.contains(selectedCategory.tag) || 
            model.architecture.rawValue.lowercased() == selectedCategory.tag.lowercased()
        }
    }
}

// MARK: - Category Button

struct CategoryButton: View {
    let category: ModelCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.purple.opacity(0.5) : Color.white.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Featured Model Card

struct FeaturedModelCard: View {
    let model: HFModel
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.4), .cyan.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "cube.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(model.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        TagView(text: model.parameters, color: .purple)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                            Text(formatNumber(model.likes))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.pink.opacity(0.8))
                    }
                }
            }
            .padding()
            .frame(width: 220, height: 180)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
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

// MARK: - Library Model Row

struct LibraryModelRow: View {
    let model: HFModel
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Model icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: "cube.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(model.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        TagView(text: model.parameters, color: .purple)
                        TagView(text: model.architecture.rawValue, color: .cyan)
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10))
                            Text(formatNumber(model.downloads))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.white.opacity(0.5))
                        
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                            Text(formatNumber(model.likes))
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.pink.opacity(0.7))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
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

// MARK: - Model Detail Sheet

struct DownloadModelDetailSheet: View {
    let model: HFModel
    @ObservedObject var viewModel: ModelDownloadViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                LiquidGlassBackground()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Model header
                        modelHeader
                        
                        // Stats
                        statsSection
                        
                        // Description
                        descriptionSection
                        
                        // Tags
                        tagsSection
                        
                        // Quantization options
                        quantizationSection
                        
                        // Action buttons
                        actionButtons
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("Model Details")
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
    
    private var modelHeader: some View {
        VStack(spacing: 16) {
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
                
                Image(systemName: "cube.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 8) {
                Text(model.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 10) {
                    TagView(text: model.parameters, color: .purple)
                    TagView(text: model.architecture.rawValue, color: .cyan)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var statsSection: some View {
        HStack(spacing: 16) {
            StatBadge(
                icon: "arrow.down.circle",
                value: formatNumber(model.downloads),
                label: "Downloads"
            )
            
            StatBadge(
                icon: "heart.fill",
                value: formatNumber(model.likes),
                label: "Likes"
            )
            
            StatBadge(
                icon: "externaldrive",
                value: formatBytes(model.sizeBytes),
                label: "Size"
            )
        }
    }
    
    private var descriptionSection: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("About")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                
                Text(model.description)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineSpacing(4)
            }
        }
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tags")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            
            FlowLayout(spacing: 8) {
                ForEach(model.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
    }
    
    private var quantizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Quantizations")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            
            FlowLayout(spacing: 8) {
                ForEach(model.quantizationOptions, id: \.self) { type in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        Text(type.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: QuantizeView()) {
                HStack {
                    Image(systemName: "cpu.fill")
                    Text("Quantize This Model")
                }
                .font(.system(size: 17, weight: .semibold))
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
            }
            
            Button(action: {
                // Copy model ID
                UIPasteboard.general.string = model.modelId
            }) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy Model ID")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
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
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.cyan)
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Model Category

enum ModelCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case chat = "Chat"
    case code = "Code"
    case instruct = "Instruct"
    case llama = "Llama"
    case mistral = "Mistral"
    case qwen = "Qwen"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .chat: return "bubble.left.and.bubble.right"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .instruct: return "text.bubble"
        case .llama: return "tortoise.fill"
        case .mistral: return "wind"
        case .qwen: return "globe.asia.australia.fill"
        }
    }
    
    var tag: String {
        switch self {
        case .all: return ""
        case .chat: return "chat"
        case .code: return "code"
        case .instruct: return "instruct"
        case .llama: return "llama"
        case .mistral: return "mistral"
        case .qwen: return "qwen"
        }
    }
}

// MARK: - View Model

@MainActor
class ModelDownloadViewModel: ObservableObject {
    @Published var models: [HFModel] = []
    @Published var featuredModels: [HFModel] = []
    @Published var selectedModel: HFModel?
    
    init() {
        loadModels()
    }
    
    private func loadModels() {
        models = [
            HFModel(
                modelId: "microsoft/Phi-3-mini-4k-instruct",
                name: "Phi-3 Mini 4K",
                description: "Microsoft's efficient 3.8B parameter model with excellent performance for its size",
                parameters: "3.8B",
                architecture: .phi,
                sizeBytes: 2_400_000_000,
                recommendedContextLength: 4096,
                tags: ["instruct", "chat", "efficient"],
                downloads: 2_500_000,
                likes: 8500
            ),
            HFModel(
                modelId: "meta-llama/Meta-Llama-3.1-8B-Instruct",
                name: "Llama 3.1 8B Instruct",
                description: "Meta's latest 8B parameter instruction-tuned model with improved reasoning",
                parameters: "8B",
                architecture: .llama,
                sizeBytes: 16_000_000_000,
                recommendedContextLength: 8192,
                tags: ["instruct", "chat", "meta"],
                downloads: 5_000_000,
                likes: 15000
            ),
            HFModel(
                modelId: "mistralai/Mistral-7B-Instruct-v0.3",
                name: "Mistral 7B Instruct v0.3",
                description: "Mistral's powerful 7B instruction model with 32K context support",
                parameters: "7B",
                architecture: .mistral,
                sizeBytes: 14_000_000_000,
                recommendedContextLength: 32768,
                tags: ["instruct", "chat", "long-context"],
                downloads: 8_000_000,
                likes: 22000
            ),
            HFModel(
                modelId: "google/gemma-2-2b-it",
                name: "Gemma 2 2B IT",
                description: "Google's lightweight 2B instruction model, great for mobile devices",
                parameters: "2B",
                architecture: .gemma,
                sizeBytes: 1_600_000_000,
                recommendedContextLength: 8192,
                tags: ["instruct", "chat", "lightweight"],
                downloads: 1_200_000,
                likes: 5600
            ),
            HFModel(
                modelId: "Qwen/Qwen2.5-7B-Instruct",
                name: "Qwen2.5 7B Instruct",
                description: "Alibaba's Qwen2.5 with improved reasoning and multilingual support",
                parameters: "7B",
                architecture: .qwen2,
                sizeBytes: 15_000_000_000,
                recommendedContextLength: 32768,
                tags: ["instruct", "chat", "multilingual"],
                downloads: 3_000_000,
                likes: 9800
            ),
            HFModel(
                modelId: "HuggingFaceTB/SmolLM2-1.7B-Instruct",
                name: "SmolLM2 1.7B Instruct",
                description: "Hugging Face's tiny but capable model, perfect for edge devices",
                parameters: "1.7B",
                architecture: .llama,
                sizeBytes: 3_400_000_000,
                recommendedContextLength: 8192,
                tags: ["instruct", "chat", "tiny"],
                downloads: 800_000,
                likes: 4200
            ),
            HFModel(
                modelId: "codellama/CodeLlama-7b-Instruct-hf",
                name: "CodeLlama 7B Instruct",
                description: "Meta's code-specialized model for programming tasks",
                parameters: "7B",
                architecture: .llama,
                sizeBytes: 13_000_000_000,
                recommendedContextLength: 16384,
                tags: ["code", "instruct", "programming"],
                downloads: 4_500_000,
                likes: 12000
            ),
            HFModel(
                modelId: "deepseek-ai/deepseek-coder-6.7b-instruct",
                name: "DeepSeek Coder 6.7B",
                description: "DeepSeek's code model with strong performance on coding benchmarks",
                parameters: "6.7B",
                architecture: .llama,
                sizeBytes: 13_400_000_000,
                recommendedContextLength: 16384,
                tags: ["code", "instruct", "programming"],
                downloads: 2_000_000,
                likes: 7500
            )
        ]
        
        featuredModels = Array(models.prefix(4))
    }
}

#Preview {
    ModelDownloadView()
        .preferredColorScheme(.dark)
}
