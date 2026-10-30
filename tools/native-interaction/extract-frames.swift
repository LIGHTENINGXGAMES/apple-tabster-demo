import AppKit
import AVFoundation

let video = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let asset = AVURLAsset(url: video)
let duration = CMTimeGetSeconds(asset.duration)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
var frames: [[String: Any]] = []
for seconds in [2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22] where Double(seconds) < duration {
    var actual = CMTime.zero
    let image = try generator.copyCGImage(at: CMTime(seconds: Double(seconds), preferredTimescale: 600), actualTime: &actual)
    let bitmap = NSBitmapImageRep(cgImage: image)
    let filename = String(format: "%02d.png", seconds)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode frame at \(seconds) seconds")
    }
    try png.write(to: output.appendingPathComponent(filename))
    frames.append(["file": filename, "requestedSeconds": seconds, "actualSeconds": CMTimeGetSeconds(actual)])
}
guard !frames.isEmpty else { fatalError("Native video is too short") }
let metadata = try JSONSerialization.data(withJSONObject: ["durationSeconds": duration, "frames": frames], options: [.prettyPrinted, .sortedKeys])
try metadata.write(to: output.appendingPathComponent("frames.json"))
