//
//  PiPSampleBuffer.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 09/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import CoreMedia
import UIKit

enum PiPSampleBuffer {
    /// Wraps a snapshot of the PiP content in a ready JPEG sample buffer, timed at the current host time. Small JPEGs
    /// contain only the rendered interface; there is no video encoder and no long-lived pixel buffer.
    static func make(from image: UIImage, duration: CMTime, displaysImmediately: Bool) -> CMSampleBuffer? {
        guard let imageData = image.jpegData(compressionQuality: 1), let cgImage = image.cgImage else { return nil }
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_JPEG,
                                             width: Int32(cgImage.width), height: Int32(cgImage.height), extensions: nil,
                                             formatDescriptionOut: &format) == noErr, let format else { return nil }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: imageData.count,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: imageData.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
            let block else { return nil }
        let copied = imageData.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var size = imageData.count
        var buffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                        sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &buffer) == noErr,
            let buffer else { return nil }
        // These are snapshots of the interface, not a timed video. Present the first
        // image immediately, including when the renderer only draws on store updates.
        if displaysImmediately {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true) as? [NSMutableDictionary],
                  let attachment = attachments.first else { return nil }
            attachment[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return buffer
    }
}
