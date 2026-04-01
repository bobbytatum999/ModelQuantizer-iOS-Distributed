//
//  SettingsView.swift
//  ModelQuantizer
//
//  App settings and configuration.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("hf_auth_token") private var authToken = ""
    @AppStorage("auto_quantize") private var autoQuantize = false
    @AppStorage("default_quantization") private var defaultQuantization = "Q4_K_M"
    @AppStorage("save_history") private var saveHistory = true
    @AppStorage("wifi_only") private var wifiOnly = true
    
    @State private var showingTokenInfo = false
    @State private var showingClearConfirmation = false
    @State private var cacheSize: Int64 = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerView
                
                // Hugging Face Auth
                authSection
                
                // Quantization Defaults
                defaultsSection
                
                // Data & Storage
                storageSection
                
                // About
                aboutSection
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .onAppear {
            calculateCacheSize()
        }
        .alert("Hugging Face Token", isPresented: $showingTokenInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your Hugging Face token is required to download gated models like Llama. Get your token from huggingface.co/settings/tokens")
        }
        .alert("Clear All Data?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will delete all quantized models and history. This action cannot be undone.")
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Configure app preferences")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Auth Section
    
    private var authSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hugging Face")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            
            LiquidGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Access Token")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Button(action: { showingTokenInfo = true }) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.cyan)
                        }
                    }
                    
                    SecureField("Enter your Hugging Face token", text: $authToken)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.1))
                        )
                    
                    if !authToken.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Token configured")
                                .font(.system(size: 13))
                                .foregroundStyle(.green)
                        }
                    }
                    
                    Text("Required for gated models like Llama. Your token is stored securely on your device.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
    
    // MARK: - Defaults Section
    
    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Defaults")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            
            LiquidGlassCard {
                VStack(spacing: 16) {
                    Toggle("Wi-Fi Only Downloads", isOn: $wifiOnly)
                        .foregroundStyle(.white)
                    
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    Toggle("Save Quantization History", isOn: $saveHistory)
                        .foregroundStyle(.white)
                    
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Quantization")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                        
                        Picker("Quantization", selection: $defaultQuantization) {
                            Text("Q2_K (2-bit)").tag("Q2_K")
                            Text("Q3_K_M (3-bit)").tag("Q3_K_M")
                            Text("Q4_K_M (4-bit)").tag("Q4_K_M")
                            Text("Q5_K_M (5-bit)").tag("Q5_K_M")
                            Text("Q6_K (6-bit)").tag("Q6_K")
                            Text("Q8_0 (8-bit)").tag("Q8_0")
                            Text("FP16 (16-bit)").tag("FP16")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }
    
    // MARK: - Storage Section
    
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data & Storage")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            
            LiquidGlassCard {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cache Size")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                            
                            Text(formatBytes(cacheSize))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.cyan)
                        }
                        
                        Spacer()
                        
                        Button(action: clearCache) {
                            Text("Clear")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                    }
                    
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    Button(action: { showingClearConfirmation = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete All Models & Data")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            
            LiquidGlassCard {
                VStack(spacing: 16) {
                    HStack {
                        Text("Version")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Text("1.0.0")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    Link(destination: URL(string: "https://github.com/NightVibes3/ModelQuantizer-iOS")!) {
                        HStack {
                            Text("GitHub Repository")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.cyan)
                        }
                    }
                    
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    Link(destination: URL(string: "https://huggingface.co")!) {
                        HStack {
                            Text("Hugging Face")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.cyan)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculateCacheSize() {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let tempDir = docs.appendingPathComponent("Temp")
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: Int64 = 0
            for url in contents {
                let attrs = try fileManager.attributesOfItem(atPath: url.path)
                totalSize += attrs[.size] as? Int64 ?? 0
            }
            cacheSize = totalSize
        } catch {
            cacheSize = 0
        }
    }
    
    private func clearCache() {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let tempDir = docs.appendingPathComponent("Temp")
        
        do {
            try fileManager.removeItem(at: tempDir)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            cacheSize = 0
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }
    
    private func clearAllData() {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let modelsDir = docs.appendingPathComponent("Models")
        let tempDir = docs.appendingPathComponent("Temp")
        
        do {
            try fileManager.removeItem(at: modelsDir)
            try fileManager.removeItem(at: tempDir)
            try fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Clear history
            UserDefaults.standard.removeObject(forKey: "quantizationHistory")
            
            cacheSize = 0
        } catch {
            print("Failed to clear data: \(error)")
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
