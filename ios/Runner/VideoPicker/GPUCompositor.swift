//
//  GPUCompositor.swift
//  Runner
//
//  Metal‐driven timeline compositor: decodes video+audio, draws overlays, writes H.264+AAC
//

import Foundation
import AVFoundation
import Metal
import MetalKit
import CoreVideo
import simd

public final class GPUCompositor {
    /// One sticker/caption overlay with its transform matrix
    public struct Overlay {
        public let image: CGImage
        public let transform: simd_float4x4
        public init(image: CGImage, transform: simd_float4x4) {
            self.image     = image
            self.transform = transform
        }
    }

    public enum CompositorError: Error {
        case noAssetReader
        case noAssetWriter
        case metalSetupFailed
        case textureCacheFailed
    }

    /// - parameter filterName: unused placeholder if you want to inject CIFilter later
    public static func export(
      sourceURL:  URL,
      filterName: String?,
      overlays:   [Overlay],
      device:     MTLDevice,
      outputURL:  URL,
      completion: @escaping (Result<Void,Error>) -> Void
    ) {
      // ─── 1) AssetReader: video + (optional) audio ─────────────────────────
      let asset = AVAsset(url: sourceURL)
      guard let reader = try? AVAssetReader(asset: asset),
            let videoTrack = asset.tracks(withMediaType: .video).first
      else {
        completion(.failure(CompositorError.noAssetReader))
        return
      }

      let videoOutput = AVAssetReaderTrackOutput(
        track: videoTrack,
        outputSettings: [
          kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_32BGRA
        ]
      )
      reader.add(videoOutput)

      // audio
      var audioOutput: AVAssetReaderTrackOutput?
      if let aTrack = asset.tracks(withMediaType: .audio).first {
        let ao = AVAssetReaderTrackOutput(track: aTrack,
                                          outputSettings: nil)
        reader.add(ao)
        audioOutput = ao
      }

      // ─── 2) AssetWriter: video + audio inputs ────────────────────────────
      guard let writer = try? AVAssetWriter(outputURL: outputURL,
                                            fileType: .mov)
      else {
        completion(.failure(CompositorError.noAssetWriter))
        return
      }

      let w = Int(videoTrack.naturalSize.width)
      let h = Int(videoTrack.naturalSize.height)
      let videoSettings: [String:Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey:  w,
        AVVideoHeightKey: h
      ]
      let videoInput = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: videoSettings
      )
      videoInput.expectsMediaDataInRealTime = false

      let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: videoInput,
        sourcePixelBufferAttributes: [
          kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_32BGRA,
          kCVPixelBufferWidthKey  as String: w,
          kCVPixelBufferHeightKey as String: h
        ]
      )
      writer.add(videoInput)

      // audio input
      var audioInput: AVAssetWriterInput?
      if audioOutput != nil {
        let ai = AVAssetWriterInput(mediaType: .audio,
                                    outputSettings: nil)
        ai.expectsMediaDataInRealTime = false
        writer.add(ai)
        audioInput = ai
      }

      // ─── 3) Metal setup ────────────────────────────────────────────────
      guard let queueCmd = device.makeCommandQueue() else {
        completion(.failure(CompositorError.metalSetupFailed)); return
      }
      var cacheRef: CVMetalTextureCache?
      guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cacheRef) == kCVReturnSuccess,
            let textureCache = cacheRef
      else {
        completion(.failure(CompositorError.textureCacheFailed)); return
      }

      let library      = device.makeDefaultLibrary()!
      let vFunc        = library.makeFunction(name: "vertex_main")!
      let fFunc        = library.makeFunction(name: "fragment_main")!
      let pd           = MTLRenderPipelineDescriptor()
      pd.vertexFunction   = vFunc
      pd.fragmentFunction = fFunc
      pd.colorAttachments[0].pixelFormat = .bgra8Unorm
      let pipelineState = try! device.makeRenderPipelineState(descriptor: pd)

      // ─── 4) Start reading + writing; bail if failures ─────────────────────
      guard reader.startReading() else {
        completion(.failure(reader.error
          ?? CompositorError.noAssetReader))
        return
      }
      guard writer.startWriting() else {
        completion(.failure(writer.error
          ?? CompositorError.noAssetWriter))
        return
      }
      writer.startSession(atSourceTime: .zero)

      // ─── 5) Audio pass (if present) ────────────────────────────────────
      if let audioOut = audioOutput,
         let audioIn  = audioInput
      {
        let aq = DispatchQueue(label: "gpu.compositor.audio")
        audioIn.requestMediaDataWhenReady(on: aq) {
          while audioIn.isReadyForMoreMediaData {
            if let smp = audioOut.copyNextSampleBuffer() {
              audioIn.append(smp)
            } else {
              audioIn.markAsFinished()
              break
            }
          }
        }
      }

      // ─── 6) Video + overlays loop ──────────────────────────────────────
      let vq = DispatchQueue(label: "gpu.compositor.video")
      videoInput.requestMediaDataWhenReady(on: vq) {
        while videoInput.isReadyForMoreMediaData {
          // if reader stops, finish
          if reader.status != .reading {
            videoInput.markAsFinished()
            writer.finishWriting { completion(.success(())) }
            break
          }
          // pull next sample
          guard let smp = videoOutput.copyNextSampleBuffer(),
                let px  = CMSampleBufferGetImageBuffer(smp)
          else {
            videoInput.markAsFinished()
            writer.finishWriting { completion(.success(())) }
            break
          }

          let time = CMSampleBufferGetPresentationTimeStamp(smp)
          let w0 = CVPixelBufferGetWidth(px)
          let h0 = CVPixelBufferGetHeight(px)

          // wrap CVPixelBuffer → MTLTexture
          var tmp: CVMetalTexture?
          CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, px, nil,
            .bgra8Unorm, w0, h0, 0, &tmp
          )
          guard let tref = tmp,
                let videoTex = CVMetalTextureGetTexture(tref)
          else { continue }

          // create render‐target
          let desc = MTLTextureDescriptor
            .texture2DDescriptor(
              pixelFormat: .bgra8Unorm,
              width:  w, height: h, mipmapped: false
            )
          desc.usage = [
            .renderTarget, .shaderRead, .shaderWrite
          ]
          let renderTex = device.makeTexture(descriptor: desc)!

          // --- BLIT the video frame into renderTex ---
          let cmd = queueCmd.makeCommandBuffer()!
          if let blit = cmd.makeBlitCommandEncoder() {
            blit.copy(
              from: videoTex,
              sourceSlice:      0,
              sourceLevel:      0,
              sourceOrigin:     MTLOrigin(x:0,y:0,z:0),
              sourceSize:       MTLSize(width: w, height: h, depth:1),
              to: renderTex,
              destinationSlice: 0,
              destinationLevel: 0,
              destinationOrigin: MTLOrigin(x:0,y:0,z:0)
            )
            blit.endEncoding()
          }

          // --- Draw overlays on top (loadAction = .load) ---
          let pass = MTLRenderPassDescriptor()
          pass.colorAttachments[0].texture     = renderTex
          pass.colorAttachments[0].loadAction  = .load
          pass.colorAttachments[0].storeAction = .store

          let enc = cmd.makeRenderCommandEncoder(
            descriptor: pass
          )!
          enc.setRenderPipelineState(pipelineState)

          for overlay in overlays {
            let ovTex = try! MTKTextureLoader(device: device)
              .newTexture(cgImage: overlay.image,
                          options: [.SRGB: false])
            enc.setFragmentTexture(ovTex, index: 1)

            var mat = overlay.transform
            enc.setVertexBytes(
              &mat,
              length: MemoryLayout<simd_float4x4>.stride,
              index: 0
            )
            enc.drawPrimitives(
              type: .triangleStrip,
              vertexStart: 0,
              vertexCount: 4
            )
          }
          enc.endEncoding()

          cmd.commit()
          cmd.waitUntilCompleted()

          // copy back → CVPixelBuffer, append to writer
          var outPB: CVPixelBuffer?
          CVPixelBufferPoolCreatePixelBuffer(
            nil, adaptor.pixelBufferPool!, &outPB
          )
          guard let dst = outPB else { continue }
          CVPixelBufferLockBaseAddress(dst, [])
          let ptr = CVPixelBufferGetBaseAddress(dst)!
          renderTex.getBytes(
            ptr,
            bytesPerRow: CVPixelBufferGetBytesPerRow(dst),
            from: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0
          )
          CVPixelBufferUnlockBaseAddress(dst, [])

          adaptor.append(dst, withPresentationTime: time)
        }
      }
    }
}
