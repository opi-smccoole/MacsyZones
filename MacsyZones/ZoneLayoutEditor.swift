//
// MacsyZones, macOS system utility for managing windows on your Mac.
//
// https://macsyzones.com
//
// Copyright © 2024, Oğuzhan Eroğlu <meowingcate@gmail.com> (https://meowingcat.io)
//
// This file is part of MacsyZones.
// Licensed under GNU General Public License v3.0
// See LICENSE file.
//

import SwiftUI

// Percent-based zone description with the origin at the TOP-LEFT of the
// screen, which is what people expect when typing numbers. SectionConfig
// stores yPercentage from the bottom (Cocoa coordinates), so the
// conversions below flip the y axis.
struct ZoneSpec: Identifiable {
    let id = UUID()
    var name: String
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(name: String = "", x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(sectionConfig: SectionConfig) {
        name = sectionConfig.name ?? ""
        x = sectionConfig.xPercentage * 100
        width = sectionConfig.widthPercentage * 100
        height = sectionConfig.heightPercentage * 100
        y = (1 - sectionConfig.yPercentage - sectionConfig.heightPercentage) * 100
    }

    func toSectionConfig(number: Int) -> SectionConfig {
        let xFraction = min(max(x, 0), 99) / 100
        let yTopFraction = min(max(y, 0), 99) / 100
        let widthFraction = min(min(max(width, 1), 100) / 100, 1 - xFraction)
        let heightFraction = min(min(max(height, 1), 100) / 100, 1 - yTopFraction)

        return SectionConfig(number: number,
                             widthPercentage: widthFraction,
                             heightPercentage: heightFraction,
                             xPercentage: xFraction,
                             yPercentage: max(0, 1 - yTopFraction - heightFraction),
                             name: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name)
    }
}

struct ZoneLayoutPreview: View {
    var zones: [ZoneSpec]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    let width = max(geometry.size.width * zone.width / 100, 2)
                    let height = max(geometry.size.height * zone.height / 100, 2)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                        )
                        .overlay(
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        )
                        .frame(width: width, height: height)
                        .offset(x: geometry.size.width * zone.x / 100,
                                y: geometry.size.height * zone.y / 100)
                }
            }
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

struct EditableZoneFields: Identifiable {
    let id = UUID()
    var name: String
    var x: String
    var y: String
    var width: String
    var height: String

    init(spec: ZoneSpec) {
        name = spec.name
        x = EditableZoneFields.percentText(spec.x)
        y = EditableZoneFields.percentText(spec.y)
        width = EditableZoneFields.percentText(spec.width)
        height = EditableZoneFields.percentText(spec.height)
    }

    var parsedSpec: ZoneSpec? {
        guard let x = EditableZoneFields.parsePercent(x),
              let y = EditableZoneFields.parsePercent(y),
              let width = EditableZoneFields.parsePercent(width),
              let height = EditableZoneFields.parsePercent(height),
              width > 0, height > 0
        else { return nil }

        return ZoneSpec(name: name, x: x, y: y, width: width, height: height)
    }

    static func parsePercent(_ text: String) -> CGFloat? {
        let normalized = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0, value <= 100 else { return nil }
        return CGFloat(value)
    }

    static func percentText(_ value: CGFloat) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

struct ZoneEditorRow: View {
    var number: Int
    @Binding var zone: EditableZoneFields
    var screenSize: CGSize
    var onDelete: () -> Void

    private func percentField(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            TextField("0", text: text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 52)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(number)")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .frame(width: 24, alignment: .leading)

                TextField("Zone Name", text: $zone.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            HStack(spacing: 8) {
                percentField("X %", $zone.x)
                percentField("Y % (top)", $zone.y)
                percentField("Width %", $zone.width)
                percentField("Height %", $zone.height)
            }

            if let spec = zone.parsedSpec {
                Text("\(Int(screenSize.width * spec.width / 100)) × \(Int(screenSize.height * spec.height / 100)) px at (\(Int(screenSize.width * spec.x / 100)), \(Int(screenSize.height * spec.y / 100)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Invalid values: use numbers between 0 and 100")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ZoneEditorView: View {
    @Binding var page: String
    @ObservedObject var layouts = userLayouts

    @State private var zones: [EditableZoneFields]
    @State private var errorMessage: String?

    private let screenSize: CGSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)

    init(page: Binding<String>) {
        _page = page

        let configs = userLayouts.currentLayout.sectionConfigs.values
            .sorted { ($0.number ?? 0) < ($1.number ?? 0) }
        var fields = configs.map { EditableZoneFields(spec: ZoneSpec(sectionConfig: $0)) }
        if fields.isEmpty {
            fields = [EditableZoneFields(spec: ZoneSpec(sectionConfig: SectionConfig.defaultSection))]
        }
        _zones = State(initialValue: fields)
    }

    private func binding(for zone: EditableZoneFields) -> Binding<EditableZoneFields> {
        Binding(
            get: { zones.first(where: { $0.id == zone.id }) ?? zone },
            set: { newValue in
                if let index = zones.firstIndex(where: { $0.id == zone.id }) {
                    zones[index] = newValue
                }
            }
        )
    }

    private var previewZones: [ZoneSpec] {
        zones.compactMap { $0.parsedSpec }
    }

    private func save() {
        var specs: [ZoneSpec] = []

        for (index, fields) in zones.enumerated() {
            guard let spec = fields.parsedSpec else {
                errorMessage = "Zone #\(index + 1) has an invalid value."
                return
            }
            specs.append(spec)
        }

        guard !specs.isEmpty else {
            errorMessage = "A layout needs at least one zone."
            return
        }

        let configs = specs.enumerated().map { $1.toSectionConfig(number: $0 + 1) }
        layouts.replaceZoneConfigs(for: layouts.currentLayoutName, with: configs)

        page = "main"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("MacsyZones").font(.headline)

            Text("Edit Zones: \(layouts.currentLayoutName)").font(.subheadline)

            Text("Positions and sizes are percentages of the screen. X is from the left edge, Y is from the top edge.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ZoneLayoutPreview(zones: previewZones)
                .frame(width: 260, height: 260 * screenSize.height / screenSize.width)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                        ZoneEditorRow(number: index + 1,
                                      zone: binding(for: zone),
                                      screenSize: screenSize,
                                      onDelete: {
                            zones.removeAll { $0.id == zone.id }
                        })
                    }
                }
            }
            .frame(maxHeight: 280)

            Button(action: {
                zones.append(EditableZoneFields(spec: ZoneSpec(sectionConfig: SectionConfig.defaultSection)))
            }) {
                Image(systemName: "plus")
                Text("Add Zone")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(alignment: .center) {
                Button(action: {
                    page = "main"
                }) {
                    Image(systemName: "xmark").foregroundColor(.red)
                    Text("Cancel")
                }

                Button(action: save) {
                    Image(systemName: "checkmark").foregroundColor(.green)
                    Text("Save")
                }
                .disabled(zones.isEmpty)
            }
        }
        .frame(width: 340)
    }
}
