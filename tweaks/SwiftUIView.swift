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
