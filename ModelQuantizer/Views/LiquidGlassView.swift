//
//  LiquidGlassView.swift
//  ModelQuantizer
//
//  Liquid Glass design components for iOS 26 aesthetics.
//

import SwiftUI

// MARK: - Liquid Glass Card

struct LiquidGlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.1),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - Liquid Glass Background

struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.05, blue: 0.2),
                    Color(red: 0.05, green: 0.1, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Animated gradient orbs
            GeometryReader { geo in
                ZStack {
                    // Purple orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.purple.opacity(0.3),
                                    Color.purple.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(x: -geo.size.width * 0.3, y: -geo.size.height * 0.2)
                        .blur(radius: 50)
                    
                    // Cyan orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.cyan.opacity(0.25),
                                    Color.cyan.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 350, height: 350)
                        .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.3)
                        .blur(radius: 50)
                    
                    // Pink orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.pink.opacity(0.2),
                                    Color.pink.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .offset(x: geo.size.width * 0.2, y: -geo.size.height * 0.3)
                        .blur(radius: 40)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Liquid Progress Ring

struct LiquidProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let color: Color
    
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    color.opacity(0.2),
                    lineWidth: lineWidth
                )
            
            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [color, color.opacity(0.5)],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { newProgress in
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = newProgress
            }
        }
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: -geo.size.width + (geo.size.width * 2 * phase))
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Glass Text Field

struct GlassTextField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.6))
            
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .foregroundStyle(.white)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Animated Background

struct AnimatedBackground: View {
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base color
                Color(red: 0.05, green: 0.05, blue: 0.1)
                
                // Animated orbs
                ForEach(0..<3) { i in
                    Circle()
                        .fill(
                            [
                                Color.purple,
                                Color.cyan,
                                Color.pink
                            ][i]
                            .opacity(0.2)
                        )
                        .frame(width: 300 + CGFloat(i * 50))
                        .offset(
                            x: animate
                                ? cos(Double(i)) * geo.size.width * 0.3
                                : sin(Double(i)) * geo.size.width * 0.3,
                            y: animate
                                ? sin(Double(i)) * geo.size.height * 0.3
                                : cos(Double(i)) * geo.size.height * 0.3
                        )
                        .blur(radius: 60)
                        .animation(
                            Animation.easeInOut(duration: 8 + Double(i * 2))
                                .repeatForever(autoreverses: true),
                            value: animate
                        )
                }
            }
        }
        .onAppear {
            animate = true
        }
        .ignoresSafeArea()
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LiquidGlassBackground()
        
        VStack(spacing: 20) {
            LiquidGlassCard {
                VStack {
                    Text("Liquid Glass Card")
                        .font(.title)
                        .foregroundStyle(.white)
                    
                    Text("This is a beautiful glassmorphism card")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            
            LiquidProgressRing(progress: 0.65, lineWidth: 12, color: .cyan)
                .frame(width: 100, height: 100)
            
            GlassButton(title: "Action", icon: "star.fill") {}
            
            GlassTextField(text: .constant(""), placeholder: "Enter text", icon: "textformat")
        }
        .padding()
    }
}
