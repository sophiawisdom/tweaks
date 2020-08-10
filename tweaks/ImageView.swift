//
//  ImageView.swift
//  tweaks
//
//  Created by Sophia Wisdom on 5/11/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

import SwiftUI

struct ImageView: NSViewRepresentable {
    let tree: SerializedLayerTree
    let windowImg: NSBitmapImageRep
    let windowSize: CGSize
    typealias NSViewType = DrawingViewImplementation
    
    func makeNSView(context: NSViewRepresentableContext<ImageView>) -> ImageView.NSViewType {
        return DrawingViewImplementation(frame: NSMakeRect(0, 0, CGFloat(windowImg.pixelsWide), CGFloat(windowImg.pixelsHigh)), tree: tree, windowImg: windowImg, windowSize: windowSize)
    }
    
    func updateNSView(_ nsView: ImageView.NSViewType, context: NSViewRepresentableContext<ImageView>) {
        nsView.setNeedsDisplay(nsView.bounds)
    }
}
/*
struct ImageView_Previews: PreviewProvider {
    static var previews: some View {
        ImageView()
    }
}*/

public class DrawingViewImplementation: NSView {
    let tree: SerializedLayerTree
    let drawnImg: NSImage
    
    init(frame frameRect: NSRect, tree: SerializedLayerTree, windowImg: NSBitmapImageRep, windowSize: CGSize) {
        self.tree = tree
        
        let imgSize = windowImg.size
        let xscale = windowSize.width/imgSize.width
        let yscale = windowSize.height/imgSize.height
        
        let offscreenrep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(imgSize.width), pixelsHigh: Int(imgSize.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: .alphaFirst, bytesPerRow: 0, bitsPerPixel: 0)!
        let g = NSGraphicsContext.init(bitmapImageRep: offscreenrep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        
        let context = NSGraphicsContext.current!.cgContext
        
        context.draw(windowImg.cgImage!, in: CGRect(origin: .zero, size: windowImg.size))
        
        context.beginPath()
        
        tree.drawRect(withXScale: Double(xscale), yScale: Double(yscale))
        
        context.closePath()
        context.strokePath()
        context.flush()
        
        NSGraphicsContext.restoreGraphicsState()
                
        self.drawnImg = NSImage(size: imgSize)
        self.drawnImg.addRepresentation(offscreenrep)
        
        do {
            try self.drawnImg.tiffRepresentation(using: .lzw, factor: 1)!.write(to: URL(fileURLWithPath: "/users/sophiawisdom/tweaks/annotated.tiff"))
            try windowImg.tiffRepresentation(using: .lzw, factor: 1)!.write(to: URL(fileURLWithPath: "/users/sophiawisdom/tweaks/window_img.tiff"))
        } catch {
            print("oops :)")
        }
        super.init(frame:frameRect)
        print("hi!")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        let frame = self.frame
        let originalImageAspectRatio = drawnImg.size.width/drawnImg.size.height
        let frameAspectRatio = frame.size.width/frame.size.height
        var newSize: NSSize = .zero;
        var scale:CGFloat = 0;
        if (frameAspectRatio > originalImageAspectRatio) { // window is wider than image
            print("frame aspect ratio greater")
            // way to do this single-line but i can't access docs
            newSize.height = frame.size.height
            newSize.width = frame.size.height*originalImageAspectRatio
            scale = drawnImg.size.height/frame.size.height
        } else if ( frameAspectRatio < originalImageAspectRatio) { // image wider than window
            print("frame aspect ratio lesesr")
            newSize.height = frame.size.height*originalImageAspectRatio
            newSize.width = frame.size.width
            scale = drawnImg.size.width/frame.size.width
        } else {
            print("this is extraordinarily unlikely and wasn't prepared for")
            return
        }
        
        let origFrame = NSMakeRect(frame.origin.x, frame.origin.y, newSize.width, newSize.height)
                
        print("frame height is \(newSize.height). Overall window height is \(window!.frame.size.height)")
        
        drawnImg.draw(in: origFrame)
        // origFrame.frame()
        
        var origin = origFrame.origin
        // origin.x += (window!.frame.size.width)-newSize.height
        // origin.y += (window!.frame.size.height-newSize.height)*2
        
        print("Backing version of origin: \(self.convertToBacking(origin))")
                                
        // tree.drawRect(from: self.convertToBacking(origin), scale:scale/2)
    }
    
    public override func mouseMoved(with event: NSEvent) {
        return
    }
}
