//
//  SwiftUIView.swift
//  tweaks
//
//  Created by Sophia Wisdom on 4/25/20.
//  Copyright © 2020 Sophia Wisdom. All rights reserved.
//

import SwiftUI
import SceneKit

struct ScenekitView : NSViewRepresentable {
    let scene = SCNScene()
    let tree: SerializedLayerTree?
    
    func makeNSView(context: NSViewRepresentableContext<ScenekitView>) -> SCNView {
        // create and add a camera to the scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 50)
        cameraNode.name = "camera"
        cameraNode.camera?.zFar = 200000;
        scene.rootNode.addChildNode(cameraNode)


        /*
        // create and add a light to the scene
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        lightNode.name = "lighting"
        scene.rootNode.addChildNode(lightNode)*/

        // create and add an ambient light to the scene
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = NSColor.white
        ambientLightNode.name = "ambient light"
        scene.rootNode.addChildNode(ambientLightNode)
        
        /*
        let scene = SCNScene(named: "ship.scn")!
        print("scene is \(scene)")*/
        
        /*
//        let fileUrl = URL(fileURLWithPath: "/users/sophiawisdom/tweaks/layerTree.tiff")
        let fileUrl = URL(fileURLWithPath: "/users/sophiawisdom/EWcOxMIUYAAyZv4.jpeg")
        let fileUrl2 = URL(fileURLWithPath: "/users/sophiawisdom/EWWhuoOWAAA9Vdj.jpeg")
        do  {
            let imgData = try Data(contentsOf: fileUrl)
            let imgRep = NSBitmapImageRep(data: imgData)!
            let img = NSImage(cgImage: imgRep.cgImage!, size: imgRep.size)
            let layerNode = SCNNode(geometry: SCNPlane(width: img.size.width, height: img.size.height))
            layerNode.geometry!.firstMaterial!.diffuse.contents! = img
            layerNode.position = SCNVector3(x: 0, y: 0, z: 0)
            layerNode.name = "layer"
            layerNode.isHidden = false
            
            let secondImgData = try Data(contentsOf:fileUrl2)
            let imgRep2 = NSBitmapImageRep(data: secondImgData)!
            let img2 = NSImage(cgImage: imgRep2.cgImage!, size: imgRep2.size)
            let layerNode2 = SCNNode(geometry: SCNPlane(width: img2.size.width, height: img2.size.height))
            layerNode2.geometry!.firstMaterial!.diffuse.contents! = img2
            layerNode2.position = SCNVector3(x: 0, y: 0, z: -5)
            layerNode2.name = "second layer"
            layerNode2.isHidden = false
            layerNode.addChildNode(layerNode2)
            
            
            scene.rootNode.addChildNode(layerNode)
        } catch {
            print("unable to get image data: \(error).")
        }*/
        
        scene.rootNode.addChildNode(tree!.node())

        // retrieve the SCNView
        let scnView = SCNView()
        scnView.scene = scene
        return scnView
    }
    
    func updateNSView(_ scnView: SCNView, context: NSViewRepresentableContext<ScenekitView>) {
        scnView.scene = scene

        // allows the user to manipulate the camera
        scnView.allowsCameraControl = true

        // show statistics such as fps and timing information
        scnView.showsStatistics = true

        // configure the view
        scnView.backgroundColor = NSColor.black
    }
}

#if DEBUG
struct ScenekitView_Previews : PreviewProvider {
    static var previews: some View {
        ScenekitView(tree:nil)
    }
}
#endif
