import SwiftUI

/// Feel: how much Clover moves, and its touch and sound.
struct FeelSection: View {
    @Binding var motion: MotionPreference
    @Binding var haptics: Bool
    @Binding var completionSound: Bool
    @Binding var leafStyle: LeafStyle

    var body: some View {
        Form {
            Section {
                Picker("Motion", selection: $motion) {
                    ForEach(MotionPreference.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Motion")
            } footer: {
                FormFooter("Reduced uses fades only. Follow the system uses Reduce motion in System Settings.")
            }

            Section {
                Toggle("Haptic taps", isOn: $haptics)
            } header: {
                Text("Haptics")
            } footer: {
                FormFooter("A small tap on the trackpad when a leaf lights up, when you drop and when a conversion finishes.")
            }

            Section {
                Toggle("Finish sound", isOn: $completionSound)
                LabeledContent("Preview") {
                    Button("Play") { ChipFeedback.playFinishSound(force: true) }
                        .help("Hear the finish sound")
                }
            } header: {
                Text("Sound")
            } footer: {
                FormFooter("A soft sound when a conversion finishes, once however many files it holds.")
            }

            Section {
                Picker("Leaf colour", selection: $leafStyle) {
                    ForEach(LeafStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Glass")
            } footer: {
                FormFooter("Clover green tints the glass of the clover and the result chip. Clear shows the desktop.")
            }
        }
        .formStyle(.grouped)
    }
}
