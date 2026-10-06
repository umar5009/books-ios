// Optional: train a custom Core ML emotion classifier for LumaRead's Mood AI.
//
// Run on a Mac (Create ML ships with Xcode):
//   swift Tools/TrainMoodClassifier.swift path/to/moods.csv
//
// CSV format (header required):
//   text,label
//   "Ugh, three deadlines tomorrow and nothing works",stressed
//   "Just got back from a hike, feeling amazing",joyful
//
// Labels must match Mood raw values: joyful, calm, curious, adventurous, romantic, melancholy, stressed, tired.
// A good starting point is to map an open emotion dataset (e.g. Google's GoEmotions) onto these 8 labels,
// then add a few hundred of your own sentences. Aim for 300+ examples per label.
//
// Output: MoodClassifier.mlmodel — drag it into the LumaRead/ML folder in Xcode.
// MoodEngine loads it automatically and fuses it with the built-in sentiment + voice + face signals.

import CreateML
import Foundation

let args = CommandLine.arguments
guard args.count > 1 else {
    print("Usage: swift TrainMoodClassifier.swift moods.csv")
    exit(1)
}

let data = try MLDataTable(contentsOf: URL(fileURLWithPath: args[1]))
let (train, test) = data.randomSplit(by: 0.85, seed: 42)

// Transfer learning on Apple's contextual BERT-style embeddings (Create ML, macOS 14+).
let params = MLTextClassifier.ModelParameters(
    validation: .split(strategy: .automatic),
    algorithm: .transferLearning(.bertEmbedding, revision: 1),
    language: .english
)
let model = try MLTextClassifier(trainingData: train, textColumn: "text", labelColumn: "label", parameters: params)

let eval = model.evaluation(on: test, textColumn: "text", labelColumn: "label")
print(String(format: "Test accuracy: %.1f%%", (1 - eval.classificationError) * 100))

let meta = MLModelMetadata(author: "LumaRead", shortDescription: "Reader mood classifier (8 moods)", version: "1.0")
try model.write(to: URL(fileURLWithPath: "MoodClassifier.mlmodel"), metadata: meta)
print("Saved MoodClassifier.mlmodel")
