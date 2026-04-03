//
//  ContentView.swift
//  ModelQuantizer
//
//  Main content view with tab navigation.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2),
                    Color(red: 0.05, green: 0.1, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(0)
                
                QuantizeView()
                    .tabItem {
                        Image(systemName: "cpu.fill")
                        Text("Quantize")
                    }
                    .tag(1)
                
                ModelLibraryView()
                    .tabItem {
                        Image(systemName: "cube.fill")
                        Text("Models")
                    }
                    .tag(2)
                
                DeviceInfoView()
                    .tabItem {
                        Image(systemName: "iphone")
                        Text("Device")
                    }
                    .tag(3)
                
                SettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .tag(4)
            }
            .tint(.cyan)
        }
    }
}

#Preview {
    ContentView()
}
