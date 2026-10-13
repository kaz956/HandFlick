import RealityKit
import SwiftUI
import UIKit
import simd

/// A lightweight in-world guide for the 12 tracked phalange regions.  It uses only tracked
/// joint transforms and never feeds rendered/recovered geometry back into recognition.
@MainActor
final class HandFlickOverlay {
    private let root = Entity()
    private let cylinder = MeshResource.generateCylinder(height: 1, radius: 1)
    private var regions: [String: ModelEntity] = [:]
    private var labels: [String: ModelEntity] = [:]

    func install(in content: RealityViewContent) {
        guard root.parent == nil else { return }
        root.name = "HandFlickInputOverlay"
        root.isEnabled = false
        for finger in FingerID.allCases {
            for segment in SegmentID.allCases {
                let region = HandRegion(finger: finger, segment: segment)
                let entity = ModelEntity(mesh: cylinder, materials: [material(for: .idle)])
                entity.name = region.id
                root.addChild(entity)
                regions[region.id] = entity

                let label = ModelEntity(
                    mesh: MeshResource.generateText(
                        labelText(for: region),
                        extrusionDepth: 0.001,
                        font: .systemFont(ofSize: 0.008, weight: .bold),
                        containerFrame: .zero,
                        alignment: .center,
                        lineBreakMode: .byTruncatingTail
                    ),
                    materials: [UnlitMaterial(color: .white)]
                )
                label.name = "\(region.id)-label"
                // Keep group labels readable as the user naturally moves their hand.
                label.components.set(BillboardComponent())
                root.addChild(label)
                labels[region.id] = label
            }
        }
        content.add(root)
    }

    func update(geometry: HandGeometry, activeRegion: HandRegion?, state: HandFlickState) {
        root.isEnabled = true
        for (region, start, end) in geometry.segments {
            guard let entity = regions[region.id] else { continue }
            let isMappedRegion = !labelText(for: region).isEmpty
            guard isMappedRegion else {
                entity.isEnabled = false
                labels[region.id]?.isEnabled = false
                continue
            }
            let vector = end - start; let length = simd_length(vector)
            guard length.isFinite, length > 0.001 else { entity.isEnabled = false; continue }
            entity.isEnabled = true
            entity.position = (start + end) * 0.5
            entity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: vector / length)
            // The contact volume is shown at its true, palm-width-normalized radius.
            let radius = geometry.handWidth * 0.20
            entity.scale = SIMD3<Float>(radius, length, radius)
            let visualState: VisualState = region == activeRegion ? (state == .contact ? .contact : .approaching) : .idle
            entity.model?.materials = [material(for: visualState)]

            if let label = labels[region.id] {
                // Float just above the palm-facing side of the segment, avoiding z-fighting.
                label.position = (start + end) * 0.5 + geometry.normal * 0.016
                label.isEnabled = true
            }
        }
    }

    func hide() { root.isEnabled = false }

    private enum VisualState { case idle, approaching, contact }
    private func labelText(for region: HandRegion) -> String {
        switch (region.finger, region.segment) {
        case (.index, .middle): "ABC"
        case (.index, .distal): "DEF"
        case (.middle, .proximal): "GHI"
        case (.middle, .middle): "JKL"
        case (.middle, .distal): "MNO"
        case (.ring, .proximal): "PQRS"
        case (.ring, .middle): "TUV"
        case (.ring, .distal): "WXYZ"
        case (.little, .proximal): "a/A"
        case (.little, .middle): "␣"
        case (.little, .distal): "⌫"
        default: ""
        }
    }
    private func material(for state: VisualState) -> UnlitMaterial {
        switch state {
        case .idle: UnlitMaterial(color: UIColor(red: 0.10, green: 0.78, blue: 1.0, alpha: 0.32))
        case .approaching: UnlitMaterial(color: UIColor(red: 1.0, green: 0.70, blue: 0.10, alpha: 0.70))
        case .contact: UnlitMaterial(color: UIColor(red: 0.10, green: 1.0, blue: 0.38, alpha: 0.90))
        }
    }
}
