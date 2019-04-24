//
//  ViewController.swift
//  LoopTloops
//
//  Created by Fritz Ebner on 4/12/19.
//  Copyright © 2019 Fritz Ebner. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import CoreMotion

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    private let motion = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private var position:SCNVector3 = SCNVector3Make(0,0,0)  // updated every frame 60fps
    private var rotation:simd_float3 =  simd_float3(0,0,0) // updated every frame 60fps
    private var lastPosition:SCNVector3 = SCNVector3Make(0,0,0) // updated slowly in startQueuedUpdates
    private var shouldStartUpdating: Bool = false
    private var maxDist:Float = 0
    private var minDist:Float = 0
    private var avgDist:Float = 0
    private var featurePointCount:Int = 0
    private var lastFeaturePointTimestamp:TimeInterval = 0
    private var trackingState:ARCamera.TrackingState = ARCamera.TrackingState.notAvailable
    private var worldMappingStatus:Int = 0 //ARFrame.WorldMappingStatus = ARFrame.WorldMappingStatus.notAvailable
    private var startDate: Date? = nil

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var heading: UILabel!
    @IBOutlet weak var X: UILabel!
    @IBOutlet weak var Y: UILabel!
    @IBOutlet weak var Z: UILabel!
    @IBOutlet weak var theStartButton: UIButton!
    @IBOutlet weak var maxFeatureDistance: UILabel!
    @IBOutlet weak var minFeatureDistance: UILabel!
    @IBOutlet weak var avgFeatureDistance: UILabel!
    
    @IBAction func startButton(_ sender: UIButton) {
        shouldStartUpdating = !shouldStartUpdating
        shouldStartUpdating ? (onStart()) : (onStop())
    }
    
    let documentsPath = NSSearchPathForDirectoriesInDomains(
        .documentDirectory, .userDomainMask, true)[0]
    
    private func writeToFile(content: String, fileName: String = "log.txt") {
        let contentWithNewLine = content+"\n"
        let filePath = NSHomeDirectory() + "/Documents/" + fileName
        let fileHandle = FileHandle(forWritingAtPath: filePath)
        if (fileHandle != nil) {
            fileHandle?.seekToEndOfFile()
            fileHandle?.write(contentWithNewLine.data(using: String.Encoding.utf8)!)
        }
        else {
            do {
                try contentWithNewLine.write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                print("Error while creating \(filePath)")
            }
        }
    }
    
    private func removeFile(fileName: String = "log.txt") {
        let filePath = NSHomeDirectory() + "/Documents/" + fileName
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: filePath) {
                // Delete file
                try fileManager.removeItem(atPath: filePath)
            } else {
                print("File does not exist")
            }
        }
        catch let error as NSError {
            print("An error took place: \(error)")
        }
        
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        removeFile()

        // Set the view's delegate
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints,
                                  ARSCNDebugOptions.showWorldOrigin]
        
        // Create a new scene
        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        
        // Set the scene to the view
        sceneView.scene = scene
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
    }
    
    private func resetsession() {
        // Create a session configuration
        self.sceneView.session.pause()

        let configuration = ARWorldTrackingConfiguration()
        //configuration.worldAlignment = .gravityAndHeading // compass heading is SHIT
        configuration.worldAlignment = .gravity
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        self.sceneView.session.run(configuration, options: [.resetTracking])
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
        
    }
    
    private func onStart() {
        theStartButton.setTitle("Stop", for: .normal)
        startDate = Date()
        checkAuthorizationStatus()
        resetsession()
        startUpdating()
    }
    
    private func onStop() {
        theStartButton.setTitle("Start", for: .normal)
        startDate = nil
        sceneView.session.pause()
        stopUpdating()
    }
    private func startUpdating() {
        startQueuedUpdates()
        
        if CMMotionActivityManager.isActivityAvailable() {
            //startTrackingActivityType()
        } else {
            //activityTypeLabel.text = "Not available"
        }
        
        if CMPedometer.isStepCountingAvailable() {
            //startCountingSteps()
        } else {
            //stepsCountLabel.text = "Not available"
        }
    }
    private func checkAuthorizationStatus() {
        switch CMMotionActivityManager.authorizationStatus() {
        case CMAuthorizationStatus.denied:
            onStop()
            //activityTypeLabel.text = "Not available"
            //stepsCountLabel.text = "Not available"
        default:break
        }
    }
    
    private func stopUpdating() {
        activityManager.stopActivityUpdates()
        //pedometer.stopUpdates()
        //pedometer.stopEventUpdates()
        motion.stopDeviceMotionUpdates()
    }
    // MARK: - ARSCNViewDelegate
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        sceneView.scene.rootNode.childNodes[0].transform = SCNMatrix4Mult(sceneView.scene.rootNode.childNodes[0].transform, SCNMatrix4MakeRotation(Float(Double.pi) / 8, 1, 0, 0))
        //sceneView.scene.rootNode.childNodes[0].transform = SCNMatrix4Mult(sceneView.scene.rootNode.childNodes[0].transform, SCNMatrix4MakeTranslation(0, 0, -1))
        sceneView.scene.rootNode.childNodes[0].transform = SCNMatrix4Mult(sceneView.scene.rootNode.childNodes[0].transform, SCNMatrix4MakeTranslation(0, 0, 0.25))
    }
    func session(_ session: ARSession, cameraDidChangeTrackingState camera:ARCamera) {
        print("cameraDidChangeTrackingState")
    }
/*
    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        let node = SCNNode()
     
        return node
    }
*/

//    TODO: set delegate for this so it gets called. == just need to tell class it implements the ARSessionDelegate protocol
    func session(_ session: ARSession, didUpdate frame:ARFrame) {
        //print("didUpdate")
        let transform = frame.camera.transform
        position = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        //let p2 = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        rotation = frame.camera.eulerAngles
        //let projection = frame.camera.projectionMatrix
        guard let rfp = frame.rawFeaturePoints else {return}
        if rfp.points.count > 0 {
            var dists:[Float] = []
            for point in rfp.points {
                //dists.append(simd_distance(point,p2))
                let x1 = Float(transform.columns.3.x)
                let z1 = Float(transform.columns.3.z)
                let x2 = Float(point.x)
                let z2 = Float(point.z)
                let dist = pow(x1 - x2, 2) + pow(z1 - z2, 2) // 2d distance, exclude Y, vertical
                let dist2 = dist.squareRoot()
                dists.append(dist2)
            }
            
            maxDist = dists.max()!
            minDist = dists.min()!
            avgDist = dists.reduce(0,+)/Float(dists.count)
            featurePointCount = dists.count
            trackingState = frame.camera.trackingState
            worldMappingStatus = frame.worldMappingStatus.rawValue
            lastFeaturePointTimestamp = Date().timeIntervalSince1970
            
        }
        //print(position)
        
        //print(rotation)
        //print(projection)
        //print("=================")
        
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    private func startQueuedUpdates() {
        if motion.isDeviceMotionAvailable {       self.motion.deviceMotionUpdateInterval = 1.0 / 3.0
            self.motion.showsDeviceMovementDisplay = true
            self.motion.startDeviceMotionUpdates(
                using: .xMagneticNorthZVertical,
                to: OperationQueue.main, withHandler: { (data, error) in
                    // Make sure the data is valid before accessing it.
                    if let validData = data {
                        // Get the attitude relative to the magnetic north reference frame.
                        //let roll = validData.attitude.roll  // around z axis looking through the front face
                        //let pitch = validData.attitude.pitch // around x axis left right when phone is portrait
                        //let yaw = validData.attitude.yaw    // around y axis when phone is portait
                        let headingVal = validData.heading
                        //let accel = validData.userAcceleration
                        //let x = round(100*accel.x)/100
                        //let y = round(100*accel.y)/100
                        //let z = round(100*accel.z)/100
                        //let a = round(100*sqrt(pow(accel.x,2) + pow(accel.y,2)))/100
                        //let d = round(100*atan2(accel.y,accel.x))/100
                        DispatchQueue.main.async {
                            self.heading.text = String(headingVal)
                            //self.userAcceleration.text = String(a) + " " + String(d)
                            let formatter = DateFormatter()
                            // initially set the format based on your datepicker date / server String
                            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                            let myString = formatter.string(from: Date()) // string purpose I add here
                            //print(self.position)
                            print("rotation \(self.rotation)")
                            let deltaPos = SCNVector3Make(self.position.x - self.lastPosition.x,
                                                          self.position.y - self.lastPosition.y,
                                                          self.position.z - self.lastPosition.z)
                            self.lastPosition = self.position
                            //print(deltaPos)
                            self.X.text = String(self.position.x)
                            self.Y.text = String(self.position.y)
                            self.Z.text = String(self.position.z)
                            
                            let featurePointTimeDiff = Date().timeIntervalSince1970 - self.lastFeaturePointTimestamp
                            //let pitch = self.rotation[0]
                            //let yaw = self.rotation[1]
                            //let roll = self.rotation[2]
                            self.maxFeatureDistance.text = String(self.maxDist)
                            self.minFeatureDistance.text = String(self.minDist)
                            self.avgFeatureDistance.text = String(self.avgDist)
                            //print("\(myString), HEADING, \(String(describing: self.heading.text!))")
                            self.writeToFile(content: "\(myString), HEADING, \(String(describing: self.heading.text!))")
                            self.writeToFile(content: "\(myString), x, \(self.position.x)")
                            self.writeToFile(content: "\(myString), y, \(self.position.y)")
                            self.writeToFile(content: "\(myString), z, \(self.position.z)")
                            self.writeToFile(content: "\(myString), maxDist, \(self.maxDist)")
                            self.writeToFile(content: "\(myString), minDist, \(self.minDist)")
                            self.writeToFile(content: "\(myString), avgDist, \(self.avgDist)")
                            self.writeToFile(content: "\(myString), featurePointCount, \(self.featurePointCount)")
                            self.writeToFile(content: "\(myString), featurePointTimeDiff, \(featurePointTimeDiff)")
                            self.writeToFile(content: "\(myString), trackingState, \(self.trackingState)")
                            self.writeToFile(content: "\(myString), worldMappingStatus, \(self.worldMappingStatus)")
                            print("\(myString), trackingState, \(self.trackingState)")
                            print("\(myString), worldMappingStatus, \(self.worldMappingStatus)")
                            //self.resetsession() // makes all sorts of flashy yuck. i think its not good for my poor little phone.
                        }
                        
                        // Use the motion data in your app.
                    }
            })
        }
        else {
            DispatchQueue.main.async {
                self.heading.text = "ITS NOT AVAILABLE"
            }
        }
    }
}
