//
//  ModelLibraryView.swift
//  ModelQuantizer
//
//  View for managing quantized models.
//

import SwiftUI
import UIKit

struct ModelLibraryView: View {
    @StateObject private var quantizer = QuantizationEngine.shared
    @State private var models: [QuantizedModel] = []
    @State private var showingDeleteConfirmation = false
    @State private var modelToDelete: QuantizedModel?
    @State private var selectedModel: QuantizedModel?
    @State private var showingModelDetail = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerView
                
                if models.isEmpty {
                    emptyStateView
                } else {
                    modelsList
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .onAppear {
            loadModels()
        }
        .refreshable {
            loadModels()
        }
        .sheet(item: $selectedModel) { model in
            ModelDetailSheet(model: model)
        }
        .alert("Delete Model?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    deleteModel(model)
                }
            }
        } message: {
            Text("This will permanently delete '\(modelToDelete?.name ?? "")'. This action cannot be undone.")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My Models")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("\(models.count) quantized model\(models.count == 1 ? "" : "s")")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "cube.box")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.3))
            
            Text("No Quantized Models")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            
            Text("Quantize your first model from the Quantize tab")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            NavigationLink(destination: QuantizeView()) {
                HStack {
                    Image(systemName: "cpu.fill")
                    Text("Quantize a Model")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.purple, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
    
    // MARK: - Models List
    
    private var modelsList: some View {
        LazyVStack(spacing: 12) {
            ForEach(models) { model in
                QuantizedModelRow(
                    model: model,
                    onTap: {
                        selectedModel = model
                    },
                    onDelete: {
                        modelToDelete = model
                        showingDeleteConfirmation = true
                    }
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadModels() {
        models = quantizer.getQuantizedModels()
    }
    
    private func deleteModel(_ model: QuantizedModel) {
        do {
            try quantizer.deleteQuantizedModel(model)
            loadModels()
        } catch {
            print("Failed to delete model: \(error)")
        }
    }
}

// MARK: - Quantized Model Row

struct QuantizedModelRow: View {
    let model: QuantizedModel
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Model icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: 56, height: 56)
                
                Image(systemName: "cube.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple)
            }
            
            VStack(alignment: .leading, spacing: 6) {
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
                
                Text(model.createdDate, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button(action: onTap) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.cyan)
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundStyle(.red.opacity(0.8))
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
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Model Detail Sheet

struct ModelDetailSheet: View {
    let model: QuantizedModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var showingFileExporter = false
    @State private var exportError: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                LiquidGlassBackground()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Model icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.4), .cyan.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "cube.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 20)
                        
                        // Model name
                        Text(model.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        
                        // Details
                        LiquidGlassCard {
                            VStack(spacing: 16) {
                                DetailRow(label: "Quantization", value: model.quantization.rawValue)
                                DetailRow(label: "Size", value: formatBytes(model.size))
                                DetailRow(label: "Created", value: model.createdDate.formatted())
                                DetailRow(label: "Location", value: model.url.lastPathComponent)
                            }
                        }
                        
                        // Actions
                        VStack(spacing: 12) {
                            Button(action: shareModel) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share Model")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.ultraThinMaterial)
                                )
                            }
                            
                            Button(action: exportModel) {
                                HStack {
                                    Image(systemName: "arrow.up.doc")
                                    Text("Export to Files")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.cyan)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.ultraThinMaterial)
                                )
                            }
                        }
                        
                        Spacer()
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
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [model.url])
        }
        .sheet(isPresented: $showingFileExporter) {
            FilesExporter(url: model.url) { error in
                if let error {
                    exportError = error.localizedDescription
                }
            }
        }
        .alert("Export Error", isPresented: Binding(get: {
            exportError != nil
        }, set: { isShowing in
            if !isShowing {
                exportError = nil
            }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown export error.")
        }
    }
    
    private func shareModel() {
        showingShareSheet = true
    }
    
    private func exportModel() {
        showingFileExporter = true
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct FilesExporter: UIViewControllerRepresentable {
    let url: URL
    let onCompletion: (Error?) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Error?) -> Void
        
        init(onCompletion: @escaping (Error?) -> Void) {
            self.onCompletion = onCompletion
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion(nil)
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onCompletion(nil)
        }
    }
}

struct DetailRow: View {
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
                .lineLimit(1)
        }
    }
}

#Preview {
    ModelLibraryView()
        .preferredColorScheme(.dark)
}
