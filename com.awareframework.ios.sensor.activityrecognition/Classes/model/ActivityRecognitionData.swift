//
//  ActivityRecognitionData.swift
//  com.aware.ios.sensor.activityrecognition
//
//  Created by Yuuki Nishiyama on 2018/11/13.
//

import UIKit
import com_awareframework_ios_sensor_core

public class ActivityRecognitionData: AwareObject {

    public static let TABLE_NAME = "activityRecognitionData"
    
    @objc dynamic public var activities:String = ""
    @objc dynamic public var confidence:Int    = 0
    @objc dynamic public var stationary:Bool   = false
    @objc dynamic public var walking:Bool      = false
    @objc dynamic public var running:Bool      = false
    @objc dynamic public var automotive:Bool   = false
    @objc dynamic public var cycling:Bool      = false
    @objc dynamic public var unknown:Bool      = false
    
    public override func toDictionary() -> Dictionary<String, Any> {
        var dict = super.toDictionary()
        dict["activities"] = activities
        dict["confidence"] = confidence
        dict["stationary"] = stationary
        dict["walking"] = walking
        dict["running"] = running
        dict["automotive"] = automotive
        dict["cycling"] = cycling
        dict["unknown"] = unknown
        return dict
    }
    
}
