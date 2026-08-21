import CoreML
import CoreGraphics
import ImageIO
import Foundation
import Accelerate

let inputSize = 256
let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
let std: [Float]  = [0.26862954, 0.26130258, 0.27577711]

func loadCGImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func loadMean(_ path: String) -> [Float] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
    return data.withUnsafeBytes { raw in
        Array(raw.bindMemory(to: Float.self))
    }
}

func preprocess(_ image: CGImage) -> MLMultiArray? {
    let isize = inputSize
    let sw = CGFloat(image.width), sh = CGFloat(image.height)
    let sc = max(CGFloat(isize) / sw, CGFloat(isize) / sh)
    let dw = sw * sc, dh = sh * sc
    let dr = CGRect(x: (CGFloat(isize) - dw) / 2, y: (CGFloat(isize) - dh) / 2, width: dw, height: dh)
    guard let ctx = CGContext(data: nil, width: isize, height: isize, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: isize, height: isize))
    ctx.draw(image, in: dr)
    guard let resized = ctx.makeImage() else { return nil }

    let w = resized.width, h = resized.height, bpr = 4 * w
    var px = [UInt8](repeating: 0, count: w * h * 4)
    guard let c2 = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    c2.draw(resized, in: CGRect(x: 0, y: 0, width: w, height: h))

    guard let ma = try? MLMultiArray(shape: [1, 3, isize, isize] as [NSNumber], dataType: .float32) else { return nil }
    let ptr = ma.dataPointer.bindMemory(to: Float.self, capacity: ma.count)
    let pc = w * h
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let p = y * w + x
            ptr[p] = (Float(px[i]) / 255 - mean[0]) / std[0]
            ptr[pc + p] = (Float(px[i + 1]) / 255 - mean[1]) / std[1]
            ptr[2 * pc + p] = (Float(px[i + 2]) / 255 - mean[2]) / std[2]
        }
    }
    return ma
}

func postProcess(_ vec: inout [Float], globalMean: [Float]) {
    if globalMean.count == vec.count {
        vDSP_vsub(globalMean, 1, vec, 1, &vec, 1, vDSP_Length(vec.count))
    }
    var sumSq: Float = 0
    vDSP_dotpr(vec, 1, vec, 1, &sumSq, vDSP_Length(vec.count))
    var norm = sqrtf(sumSq)
    if norm > 1e-8 {
        vDSP_vsdiv(vec, 1, &norm, &vec, 1, vDSP_Length(vec.count))
    }
}

func embed(model: MLModel, image: CGImage, globalMean: [Float], applyMean: Bool) -> [Float] {
    guard let ma = preprocess(image) else { return [] }
    guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: ma)])),
          let arr = out.featureValue(for: "var_2460")?.multiArrayValue else { return [] }
    var vec = [Float](repeating: 0, count: arr.count)
    let op = arr.dataPointer.bindMemory(to: Float.self, capacity: arr.count)
    for i in 0..<arr.count { vec[i] = op[i] }
    if applyMean { postProcess(&vec, globalMean: globalMean) }
    else {
        var sumSq: Float = 0
        vDSP_dotpr(vec, 1, vec, 1, &sumSq, vDSP_Length(vec.count))
        var norm = sqrtf(sumSq)
        if norm > 1e-8 { vDSP_vsdiv(vec, 1, &norm, &vec, 1, vDSP_Length(vec.count)) }
    }
    return vec
}

func cosine(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
    vDSP_dotpr(a, 1, a, 1, &na, vDSP_Length(a.count))
    vDSP_dotpr(b, 1, b, 1, &nb, vDSP_Length(b.count))
    let d = sqrtf(na) * sqrtf(nb)
    return d > 1e-8 ? dot / d : 0
}

let root = CommandLine.arguments[1]
let img1 = CommandLine.arguments[2]
let img2 = CommandLine.arguments[3]
let pkg = URL(fileURLWithPath: "\(root)/B-easy/VisionTab/mobileclip_s2_image_fp16.mlpackage")
let model = try! MLModel(contentsOf: MLModel.compileModel(at: pkg))
let cg1 = loadCGImage(img1)!
let cg2 = loadCGImage(img2)!
let v1 = embed(model: model, image: cg1, globalMean: [], applyMean: false)
let v2 = embed(model: model, image: cg2, globalMean: [], applyMean: false)
let sim = cosine(v1, v2)
let selfSim = cosine(v1, v1)

print("=== MobileCLIP S2 — Charger Test ===")
print("A: \(URL(fileURLWithPath: img1).lastPathComponent)")
print("B: \(URL(fileURLWithPath: img2).lastPathComponent)")
print("Self-sim (sanity):  \(String(format: "%.4f", selfSim))")
print("Cosine similarity:  \(String(format: "%.4f", sim))")
print("App threshold:      0.82 raw / 0.78 calibrated")
