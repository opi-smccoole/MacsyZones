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

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct AIZoneSpec {
    @Guide(description: "Short descriptive name for the zone, e.g. 'Left Half' or 'Editor'")
    var name: String

    @Guide(description: "Distance of the zone's left edge from the left edge of the screen, as a percentage of screen width", .range(0...99))
    var x: Int

    @Guide(description: "Distance of the zone's top edge from the top edge of the screen, as a percentage of screen height", .range(0...99))
    var y: Int

    @Guide(description: "Zone width as a percentage of screen width", .range(1...100))
    var width: Int

    @Guide(description: "Zone height as a percentage of screen height", .range(1...100))
    var height: Int
}

@available(macOS 26.0, *)
@Generable
struct AILayoutProposal {
    @Guide(description: "A short, friendly reply to the user describing the layout you designed")
    var reply: String

    @Guide(description: "A short name for the layout, e.g. 'Coding + Chat'")
    var layoutName: String

    @Guide(description: "The zones of the layout")
    var zones: [AIZoneSpec]
}

@available(macOS 26.0, *)
class AILayoutAssistant: ObservableObject {
    struct Message: Identifiable {
        enum Role {
            case user
            case assistant
            case error
        }

        let id = UUID()
        let role: Role
        let text: String
    }

    @Published var messages: [Message] = []
    @Published var isGenerating = false
    @Published var proposal: AILayoutProposal?

    private let session: LanguageModelSession

    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence, so layout chat isn't available."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to design layouts by chatting."
        case .unavailable(.modelNotReady):
            return "The Apple Intelligence model is still getting ready (it may be downloading). Please try again in a bit."
        case .unavailable:
            return "Apple Intelligence is unavailable on this Mac, so layout chat isn't available."
        }
    }

    init() {
        session = LanguageModelSession(instructions: """
            You design window layouts for MacsyZones, a macOS window tiling utility.
            A layout is a set of rectangular zones on one screen; the user drags windows onto zones to snap them there.
            All zone values are integer percentages of the screen: x is measured from the left edge, y from the top edge.
            Zones must stay within the screen: x + width must not exceed 100, and y + height must not exceed 100.
            Adjacent zones must share edges exactly. For example "editor on the left two thirds, terminal top right, notes bottom right" means:
            Editor x=0 y=0 width=67 height=100, Terminal x=67 y=0 width=33 height=50, Notes x=67 y=50 width=33 height=50.
            Zones may overlap only when they are meant as alternative placements for the same area.
            Unless the user asks otherwise, the zones together should cover the whole screen without gaps.
            Keep layouts practical: 2 to 8 zones is typical.
            When the user asks for changes, update your previous layout accordingly and return the full layout again.
            """)
    }

    @MainActor
    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        messages.append(Message(role: .user, text: prompt))
        isGenerating = true

        Task { @MainActor in
            do {
                let response = try await session.respond(to: prompt, generating: AILayoutProposal.self)
                proposal = response.content
                messages.append(Message(role: .assistant, text: response.content.reply))
            } catch {
                messages.append(Message(role: .error, text: "Something went wrong: \(error.localizedDescription)"))
            }

            isGenerating = false
        }
    }

    var proposalZoneSpecs: [ZoneSpec] {
        guard let proposal else { return [] }

        return proposal.zones.map {
            ZoneSpec(name: $0.name,
                     x: CGFloat($0.x),
                     y: CGFloat($0.y),
                     width: CGFloat($0.width),
                     height: CGFloat($0.height))
        }
    }
}

@available(macOS 26.0, *)
struct AILayoutChatView: View {
    @Binding var page: String
    @ObservedObject var layouts = userLayouts

    @StateObject private var assistant = AILayoutAssistant()
    @State private var input = ""
    @State private var layoutName = ""
    @State private var showAlreadyExistsAlert = false

    private let screenSize: CGSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)

    private func send() {
        let text = input
        input = ""
        assistant.send(text)
    }

    private func createLayout() {
        let name = layoutName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, assistant.proposal != nil else { return }

        if layouts.layouts.keys.contains(name) {
            showAlreadyExistsAlert = true
            return
        }

        let configs = assistant.proposalZoneSpecs.enumerated().map { $1.toSectionConfig(number: $0 + 1) }
        layouts.createLayout(name: name, sectionConfigs: configs)

        page = "main"
    }

    private func bubbleColor(for role: AILayoutAssistant.Message.Role) -> Color {
        switch role {
        case .user: return Color.accentColor.opacity(0.2)
        case .assistant: return Color.gray.opacity(0.15)
        case .error: return Color.red.opacity(0.15)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("MacsyZones").font(.headline)

            Text("Design a Layout with Apple Intelligence").font(.subheadline)

            if let message = AILayoutAssistant.availabilityMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)

                Button(action: { page = "main" }) {
                    Image(systemName: "xmark").foregroundColor(.red)
                    Text("Back")
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if assistant.messages.isEmpty {
                                Text("Describe the layout you want, e.g. “A big editor on the left two thirds, terminal top right, notes bottom right.”")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            ForEach(assistant.messages) { message in
                                HStack {
                                    if message.role == .user { Spacer(minLength: 30) }

                                    Text(message.text)
                                        .font(.caption)
                                        .padding(8)
                                        .background(bubbleColor(for: message.role))
                                        .cornerRadius(8)
                                        .fixedSize(horizontal: false, vertical: true)

                                    if message.role != .user { Spacer(minLength: 30) }
                                }
                                .id(message.id)
                            }

                            if assistant.isGenerating {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Designing…").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                    }
                    .frame(height: 170)
                    .onChange(of: assistant.messages.count) { _ in
                        if let lastMessage = assistant.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("What do you want on your screen?", text: $input)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit(send)
                        .disabled(assistant.isGenerating)

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(assistant.isGenerating || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if assistant.proposal != nil {
                    Divider()

                    ZoneLayoutPreview(zones: assistant.proposalZoneSpecs)
                        .frame(width: 220, height: 220 * screenSize.height / screenSize.width)

                    HStack(spacing: 6) {
                        TextField("Layout Name", text: $layoutName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: createLayout) {
                            Image(systemName: "checkmark").foregroundColor(.green)
                            Text("Create")
                        }
                        .disabled(layoutName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Button(action: { page = "main" }) {
                    Image(systemName: "xmark").foregroundColor(.red)
                    Text("Cancel")
                }
            }
        }
        .frame(width: 340)
        .onReceive(assistant.$proposal) { proposal in
            if let proposal {
                layoutName = proposal.layoutName
            }
        }
        .alert(isPresented: $showAlreadyExistsAlert) {
            Alert(
                title: Text("Omg! 😊"),
                message: Text("Another layout with this name already exists. Please choose another name."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct AILayoutView: View {
    @Binding var page: String

    var body: some View {
        if #available(macOS 26.0, *) {
            AILayoutChatView(page: $page)
        } else {
            AILayoutUnavailableView(page: $page)
        }
    }
}

#else

struct AILayoutView: View {
    @Binding var page: String

    var body: some View {
        AILayoutUnavailableView(page: $page)
    }
}

#endif

struct AILayoutUnavailableView: View {
    @Binding var page: String

    var body: some View {
        VStack(spacing: 10) {
            Text("MacsyZones").font(.headline)

            Text("Designing layouts by chatting needs Apple Intelligence, which requires macOS 26 or later.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { page = "main" }) {
                Image(systemName: "xmark").foregroundColor(.red)
                Text("Back")
            }
        }
        .frame(width: 300)
    }
}
