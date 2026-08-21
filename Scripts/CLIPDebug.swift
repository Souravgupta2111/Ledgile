import CoreML
import CoreGraphics
import ImageIO
import Foundation

let img = "/Users/apple/.cursor/projects/Users-apple-Desktop-B-easy-copy-2/assets/IMG_0012-49b6fb4c-025b-4030-9473-9001830fd548.jpg"
let url = URL(fileURLWithPath: img)
let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
print("image", cg.width, cg.height)

let pkg = URL(fileURLWithPath: "/Users/apple/Desktop/B-easy copy 2/B-easy/VisionTab/mobileclip_s2_image_fp16.mlpackage")
let model = try MLModel(contentsOf: MLModel.compileModel(at: pkg))

let isize = 256
let sw = CGFloat(cg.width), sh = CGFloat(cg.height)
let sc = max(CGFloat(isize)/sw, CGFloat(isize)/sh)
let dw = sw*sc, dh = sh*sc
let dr = CGRect(x:(CGFloat(isize)-dw)/2,y:(CGFloat(isize)-dh)/2,width:dw,height:dh)
let ctx = CGContext(data:nil,width:isize,height:isize,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(gray:0,alpha:1)); ctx.fill(CGRect(x:0,y:0,width:isize,height:isize))
ctx.draw(cg,in:dr)
let resized = ctx.makeImage()!
print("resized", resized.width, resized.height)

let mean:[Float]=[0.48145466,0.4578275,0.40821073]
let std:[Float]=[0.26862954,0.26130258,0.27577711]
let w=resized.width,h=resized.height,bpr=4*w
var px=[UInt8](repeating:0,count:w*h*4)
let c2=CGContext(data:&px,width:w,height:h,bitsPerComponent:8,bytesPerRow:bpr,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
c2.draw(resized,in:CGRect(x:0,y:0,width:w,height:h))
print("pixel sample", px[0], px[1], px[2], px[3])

let ma = try MLMultiArray(shape:[1,3,isize,isize] as [NSNumber], dataType:.float32)
let ptr = ma.dataPointer.bindMemory(to:Float.self,capacity:ma.count)
let pc=w*h
for y in 0..<h { for x in 0..<w {
  let i=(y*w+x)*4, p=y*w+x
  ptr[p]=(Float(px[i])/255-mean[0])/std[0]
  ptr[pc+p]=(Float(px[i+1])/255-mean[1])/std[1]
  ptr[2*pc+p]=(Float(px[i+2])/255-mean[2])/std[2]
}}
print("input min/max", (0..<ma.count).map{ptr[$0]}.min()!, (0..<ma.count).map{ptr[$0]}.max()!)

let out = try model.prediction(from: try MLDictionaryFeatureProvider(dictionary:["image":MLFeatureValue(multiArray:ma)]))
let arr = out.featureValue(for:"var_2460")!.multiArrayValue!
let op = arr.dataPointer.bindMemory(to:Float.self,capacity:arr.count)
var vals=[Float](repeating:0,count:arr.count); for i in 0..<arr.count{vals[i]=op[i]}
print("output count", arr.count, "min", vals.min()!, "max", vals.max()!, "sumsq", vals.reduce(0,+))
