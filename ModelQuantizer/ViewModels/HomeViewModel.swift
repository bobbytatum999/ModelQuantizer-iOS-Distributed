//
//  HomeViewModel.swift
//  ModelQuantizer
//
//  ViewModel for the Home tab.
//

import Foundation
import Combine
import UIKit

@MainActor
class HomeViewModel: ObservableObject {
    @Published var recentQuantizations: [QuantizedModel] = []
    @Published var quantizedModelCount = 0
    @Published var totalQuantizedSize: Int64 = 0
    @Published var isLoading = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadRecentQuantizations()
        
        // Refresh when app becomes active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.loadRecentQuantizations()
            }
            .store(in: &cancellables)
    }
    
    func loadRecentQuantizations() {
        isLoading = true
        
        let models = QuantizationEngine.shared.getQuantizedModels()
        recentQuantizations = models
        quantizedModelCount = models.count
        totalQuantizedSize = models.reduce(0) { $0 + $1.size }
        
        isLoading = false
    }
    
    func deleteModel(_ model: QuantizedModel) {
        do {
            try QuantizationEngine.shared.deleteQuantizedModel(model)
            loadRecentQuantizations()
        } catch {
            print("Failed to delete model: \(error)")
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}
