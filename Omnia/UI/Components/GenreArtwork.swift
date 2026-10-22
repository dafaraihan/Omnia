//
//  GenreArtwork.swift
//  Omnia
//

import SwiftUI

/// A Browse by Genre card: Omnia-owned art with the genre's name, the same
/// size and corners as the poster cards beside it (Dafa, 2026-10-22).
struct GenreCardLabel<Artwork: View>: View {
    @Environment(\.displayPreferences) private var display
    let title: String
    var width: CGFloat?
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork()

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(14)
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .frame(width: width)
        .clipShape(.rect(cornerRadius: display.posterCornerRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: display.posterCornerRadius, style: .continuous))
        .cardDepth(.posters, cornerRadius: display.posterCornerRadius)
    }
}

/// Omnia-owned genre art. These are intentionally abstract compositions, not
/// borrowed title posters, so a genre remains recognizable even as catalogs
/// change or a provider has no artwork available.
struct GenreArtwork: View {
    let genre: BrowseGenre

    var body: some View {
        GenreArtworkCanvas(colors: genre.artworkColors) { size in
            motif(in: size)
        }
    }

    @ViewBuilder
    private func motif(in size: CGSize) -> some View {
        switch genre {
        case .action:
            ZStack {
                Capsule().fill(.white.opacity(0.28)).frame(width: size.width * 1.45, height: size.height * 0.16).rotationEffect(.degrees(-34))
                Capsule().fill(.black.opacity(0.22)).frame(width: size.width * 1.35, height: size.height * 0.09).rotationEffect(.degrees(-34)).offset(y: size.height * 0.19)
                Circle().fill(.white.opacity(0.28)).frame(width: size.width * 0.32).offset(x: size.width * 0.21, y: -size.height * 0.23)
            }
        case .adventure:
            ZStack(alignment: .bottom) {
                Circle().fill(.yellow.opacity(0.32)).frame(width: size.width * 0.42).offset(x: size.width * 0.18, y: -size.height * 0.25)
                RoundedRectangle(cornerRadius: size.width * 0.12).fill(.black.opacity(0.26)).frame(width: size.width * 0.92, height: size.height * 0.68).rotationEffect(.degrees(45)).offset(y: size.height * 0.34)
                RoundedRectangle(cornerRadius: size.width * 0.1).fill(.white.opacity(0.16)).frame(width: size.width * 0.8, height: size.height * 0.54).rotationEffect(.degrees(-38)).offset(x: -size.width * 0.2, y: size.height * 0.4)
            }
        case .scienceFiction:
            ZStack {
                Ellipse().stroke(.white.opacity(0.38), lineWidth: max(2, size.width * 0.025)).frame(width: size.width * 0.9, height: size.height * 0.32).rotationEffect(.degrees(-28))
                Ellipse().stroke(.white.opacity(0.2), lineWidth: max(2, size.width * 0.02)).frame(width: size.width * 0.72, height: size.height * 0.25).rotationEffect(.degrees(34))
                Circle().fill(.white.opacity(0.75)).frame(width: size.width * 0.16)
                Circle().fill(.cyan.opacity(0.34)).frame(width: size.width * 0.55)
            }
        case .drama:
            HStack(spacing: size.width * 0.08) {
                RoundedRectangle(cornerRadius: size.width * 0.13).fill(.white.opacity(0.14)).frame(width: size.width * 0.26).offset(y: -size.height * 0.15)
                RoundedRectangle(cornerRadius: size.width * 0.13).fill(.black.opacity(0.28)).frame(width: size.width * 0.36).offset(y: size.height * 0.09)
                RoundedRectangle(cornerRadius: size.width * 0.13).fill(.white.opacity(0.12)).frame(width: size.width * 0.22).offset(y: -size.height * 0.28)
            }
            .rotationEffect(.degrees(-15))
        case .comedy:
            ZStack {
                Circle().fill(.yellow.opacity(0.34)).frame(width: size.width * 0.82).offset(x: -size.width * 0.21, y: size.height * 0.1)
                Circle().stroke(.white.opacity(0.38), lineWidth: max(2, size.width * 0.035)).frame(width: size.width * 0.42).offset(x: size.width * 0.23, y: -size.height * 0.2)
                Circle().fill(.white.opacity(0.24)).frame(width: size.width * 0.13).offset(x: size.width * 0.32, y: size.height * 0.26)
            }
        case .family:
            ZStack {
                Circle().fill(.white.opacity(0.22)).frame(width: size.width * 0.72).offset(x: -size.width * 0.18, y: size.height * 0.14)
                Circle().fill(.yellow.opacity(0.34)).frame(width: size.width * 0.42).offset(x: size.width * 0.22, y: -size.height * 0.19)
                Circle().stroke(.white.opacity(0.44), lineWidth: max(2, size.width * 0.028)).frame(width: size.width * 0.88)
            }
        case .romance:
            ZStack {
                Circle().fill(.white.opacity(0.2)).frame(width: size.width * 0.64).offset(x: -size.width * 0.17, y: -size.height * 0.12)
                Circle().fill(.black.opacity(0.14)).frame(width: size.width * 0.59).offset(x: size.width * 0.23, y: size.height * 0.22)
                Capsule().fill(.white.opacity(0.32)).frame(width: size.width * 0.17, height: size.height * 0.76).rotationEffect(.degrees(42))
            }
        case .horror:
            ZStack(alignment: .topTrailing) {
                Circle().fill(.white.opacity(0.26)).frame(width: size.width * 0.56).offset(x: size.width * 0.14, y: -size.height * 0.18)
                RoundedRectangle(cornerRadius: size.width * 0.2).fill(.black.opacity(0.42)).frame(width: size.width * 0.84, height: size.height * 0.64).rotationEffect(.degrees(-15)).offset(x: -size.width * 0.2, y: size.height * 0.28)
            }
        case .thriller:
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(index.isMultiple(of: 2) ? .white.opacity(0.2) : .black.opacity(0.25))
                        .frame(width: size.width * 1.3, height: max(2, size.width * 0.03))
                        .rotationEffect(.degrees(-32))
                        .offset(y: CGFloat(index - 2) * size.height * 0.19)
                }
            }
        case .animation:
            // Overlapping cels.
            ZStack {
                RoundedRectangle(cornerRadius: size.width * 0.1).fill(.white.opacity(0.18)).frame(width: size.width * 0.62, height: size.height * 0.42).rotationEffect(.degrees(-12)).offset(x: -size.width * 0.12, y: -size.height * 0.16)
                RoundedRectangle(cornerRadius: size.width * 0.1).fill(.black.opacity(0.16)).frame(width: size.width * 0.62, height: size.height * 0.42).rotationEffect(.degrees(8)).offset(x: size.width * 0.14, y: size.height * 0.02)
                Circle().fill(.white.opacity(0.4)).frame(width: size.width * 0.2).offset(x: size.width * 0.18, y: -size.height * 0.28)
                Circle().stroke(.white.opacity(0.32), lineWidth: max(2, size.width * 0.025)).frame(width: size.width * 0.34).offset(x: -size.width * 0.2, y: size.height * 0.26)
            }
        case .crime:
            // A spotlight crossing a striped wall.
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? .white.opacity(0.1) : .black.opacity(0.2))
                        .frame(width: size.width * 0.16, height: size.height * 1.2)
                        .offset(x: CGFloat(index) * size.width * 0.27 - size.width * 0.4)
                }
                Circle().fill(.white.opacity(0.24)).frame(width: size.width * 0.66).offset(x: size.width * 0.12, y: -size.height * 0.12)
                Circle().fill(.white.opacity(0.2)).frame(width: size.width * 0.32).offset(x: size.width * 0.12, y: -size.height * 0.12)
            }
        case .documentary:
            // A lens.
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(.white.opacity(0.36 - Double(index) * 0.1), lineWidth: max(2, size.width * 0.03))
                        .frame(width: size.width * (0.34 + CGFloat(index) * 0.26))
                }
                Circle().fill(.black.opacity(0.24)).frame(width: size.width * 0.3)
                Circle().fill(.white.opacity(0.5)).frame(width: size.width * 0.08).offset(x: -size.width * 0.06, y: -size.width * 0.06)
            }
            .offset(y: -size.height * 0.08)
        case .fantasy:
            // A crescent moon among stars.
            ZStack {
                Circle().fill(.white.opacity(0.32)).frame(width: size.width * 0.62)
                    .mask {
                        ZStack {
                            Rectangle()
                            Circle().frame(width: size.width * 0.56).offset(x: size.width * 0.18, y: -size.width * 0.1).blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .offset(x: -size.width * 0.08, y: -size.height * 0.12)
                Circle().fill(.white.opacity(0.6)).frame(width: size.width * 0.06).offset(x: size.width * 0.3, y: -size.height * 0.3)
                Circle().fill(.white.opacity(0.45)).frame(width: size.width * 0.04).offset(x: size.width * 0.22, y: size.height * 0.06)
                Circle().fill(.white.opacity(0.5)).frame(width: size.width * 0.05).offset(x: -size.width * 0.3, y: size.height * 0.2)
            }
        case .mystery:
            // A keyhole.
            ZStack {
                Circle().stroke(.white.opacity(0.26), lineWidth: max(2, size.width * 0.03)).frame(width: size.width * 0.86)
                Circle().fill(.black.opacity(0.34)).frame(width: size.width * 0.28).offset(y: -size.height * 0.08)
                RoundedRectangle(cornerRadius: size.width * 0.04).fill(.black.opacity(0.34)).frame(width: size.width * 0.14, height: size.height * 0.24).offset(y: size.height * 0.06)
            }
            .offset(y: -size.height * 0.06)
        case .history:
            // A row of columns.
            VStack(spacing: size.height * 0.03) {
                RoundedRectangle(cornerRadius: size.width * 0.03).fill(.white.opacity(0.24)).frame(width: size.width * 0.84, height: size.height * 0.05)
                HStack(spacing: size.width * 0.08) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: size.width * 0.04)
                            .fill(index.isMultiple(of: 2) ? .white.opacity(0.2) : .black.opacity(0.18))
                            .frame(width: size.width * 0.13, height: size.height * 0.44)
                    }
                }
                RoundedRectangle(cornerRadius: size.width * 0.03).fill(.black.opacity(0.22)).frame(width: size.width * 0.92, height: size.height * 0.05)
            }
            .offset(y: -size.height * 0.08)
        case .war:
            // Chevrons.
            VStack(spacing: -size.height * 0.02) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 0) {
                        Capsule().fill(.white.opacity(0.26 - Double(index) * 0.06)).frame(width: size.width * 0.44, height: size.height * 0.07).rotationEffect(.degrees(28), anchor: .trailing)
                        Capsule().fill(.white.opacity(0.26 - Double(index) * 0.06)).frame(width: size.width * 0.44, height: size.height * 0.07).rotationEffect(.degrees(-28), anchor: .leading)
                    }
                    .frame(height: size.height * 0.16)
                }
            }
            .offset(y: -size.height * 0.1)
        case .western:
            // A low sun over a mesa.
            ZStack(alignment: .bottom) {
                Circle().fill(.yellow.opacity(0.36)).frame(width: size.width * 0.62).offset(y: -size.height * 0.38)
                RoundedRectangle(cornerRadius: size.width * 0.06).fill(.black.opacity(0.3)).frame(width: size.width * 0.58, height: size.height * 0.3).offset(x: -size.width * 0.18, y: -size.height * 0.2)
                Rectangle().fill(.black.opacity(0.24)).frame(width: size.width, height: size.height * 0.24)
            }
            .frame(width: size.width, height: size.height, alignment: .bottom)
        case .music:
            // Equalizer bars.
            HStack(alignment: .bottom, spacing: size.width * 0.06) {
                ForEach([0.34, 0.58, 0.42, 0.72, 0.5], id: \.self) { height in
                    Capsule()
                        .fill(height > 0.5 ? .white.opacity(0.28) : .black.opacity(0.2))
                        .frame(width: size.width * 0.11, height: size.height * height)
                }
            }
            .offset(y: -size.height * 0.08)
        case .reality:
            // A camera frame around a subject.
            ZStack {
                RoundedRectangle(cornerRadius: size.width * 0.08).stroke(.white.opacity(0.34), lineWidth: max(2, size.width * 0.03)).frame(width: size.width * 0.76, height: size.height * 0.46)
                Circle().fill(.white.opacity(0.24)).frame(width: size.width * 0.26).offset(y: -size.height * 0.05)
                Capsule().fill(.black.opacity(0.22)).frame(width: size.width * 0.44, height: size.height * 0.12).offset(y: size.height * 0.13)
                Circle().fill(.red.opacity(0.6)).frame(width: size.width * 0.07).offset(x: size.width * 0.28, y: -size.height * 0.18)
            }
            .offset(y: -size.height * 0.08)
        }
    }
}

/// The Anime card's art, in the same style as the genre cards: a rising sun
/// with speed lines.
struct AnimeGenreArtwork: View {
    var body: some View {
        GenreArtworkCanvas(colors: [.indigo, .pink]) { size in
            ZStack {
                Circle().fill(.white.opacity(0.3)).frame(width: size.width * 0.58).offset(x: size.width * 0.14, y: -size.height * 0.2)
                Circle().fill(.pink.opacity(0.32)).frame(width: size.width * 0.3).offset(x: size.width * 0.14, y: -size.height * 0.2)
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index.isMultiple(of: 2) ? .white.opacity(0.24) : .black.opacity(0.18))
                        .frame(width: size.width * (0.9 - CGFloat(index) * 0.14), height: max(2, size.height * 0.025))
                        .offset(x: -size.width * 0.2, y: size.height * (0.04 + CGFloat(index) * 0.08))
                }
            }
        }
    }
}

/// The gradient, motif and shade every genre card shares.
private struct GenreArtworkCanvas<Motif: View>: View {
    let colors: [Color]
    @ViewBuilder let motif: (CGSize) -> Motif

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            GeometryReader { proxy in
                motif(proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.22)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }
}

extension BrowseGenre {
    var artworkColors: [Color] {
        switch self {
        case .action: [.orange, .red]
        case .adventure: [.teal, .green]
        case .scienceFiction: [.indigo, .cyan]
        case .drama: [.blue, .black]
        case .comedy: [.mint, .green]
        case .family: [.pink, .orange]
        case .romance: [.pink, .purple]
        case .horror: [.orange, .black]
        case .thriller: [.red, .black]
        case .animation: [.yellow, .orange]
        case .crime: [.gray, .black]
        case .documentary: [.teal, .blue]
        case .fantasy: [.purple, .indigo]
        case .mystery: [.indigo, .black]
        case .history: [.brown, .orange]
        case .war: [Color(red: 0.4, green: 0.45, blue: 0.24), .black]
        case .western: [.orange, .brown]
        case .music: [.pink, .indigo]
        case .reality: [.cyan, .blue]
        }
    }
}
