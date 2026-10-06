import SwiftUI

struct ReaderSettingsSheet: View {
    @ObservedObject var model: ReaderModel
    @Binding var handsFree: Bool
    var onCalibrate: () -> Void
    var onToggleHandsFree: () -> Void
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sensors: SensorHub

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    HStack {
                        Button { model.setFont(model.fontSize - 2); settings.fontSize = Double(model.fontSize) } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        Slider(value: Binding(get: { Double(model.fontSize) },
                                              set: { model.setFont(CGFloat($0.rounded())); settings.fontSize = $0.rounded() }),
                               in: 14...36, step: 1)
                        Button { model.setFont(model.fontSize + 2); settings.fontSize = Double(model.fontSize) } label: {
                            Image(systemName: "textformat.size.larger")
                        }
                    }
                    .buttonStyle(.borderless)
                    Picker("Theme", selection: Binding(get: { settings.readerTheme }, set: { settings.readerTheme = $0 })) {
                        ForEach(ReaderTheme.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if model.totalPages > 1 {
                        Slider(value: Binding(get: { model.fraction }, set: { model.jump(toFraction: $0) }))
                    }
                }

                Section {
                    Toggle("Hands-free mode", isOn: Binding(get: { handsFree }, set: { _ in onToggleHandsFree() }))
                    Toggle("Follow my eyes (line highlight)", isOn: $settings.eyeTrackingEnabled)
                    Toggle("Highlight current word", isOn: $settings.wordHighlight)
                    Toggle("Auto turn page at the end", isOn: $settings.autoPageTurn)
                    Toggle("Double-blink to turn page", isOn: $settings.doubleBlinkTurn)
                    Toggle("Air Zoom (finger spread / pinch)", isOn: $settings.airZoomEnabled)
                        .onChange(of: settings.airZoomEnabled) { _, on in sensors.gestureDetectionEnabled = on }
                    Toggle("Show gaze dot", isOn: $settings.showGazeDot)
                    Button("Calibrate eye tracking", action: onCalibrate)
                } header: {
                    Text("Eye-Flow & gestures")
                } footer: {
                    Text(sensors.calibration.meanErrorPoints.map { "Calibrated · average error ≈ \(Int($0)) pt" }
                         ?? "Calibrate once for line-accurate tracking.")
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
