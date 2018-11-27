//
//  ViewController.swift
//  com.awareframework.ios.sensor.activityrecognition
//
//  Created by tetujin on 11/20/2018.
//  Copyright (c) 2018 tetujin. All rights reserved.
//

import UIKit
import com_awareframework_ios_sensor_activityrecognition

class ViewController: UIViewController {
    
    var sensor:ActivityRecognitionSensor?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
//        sensor = ActivityRecognitionSensor.init(ActivityRecognitionSensor.Config().apply{config in
//            config.debug = true
//            config.interval = 1
//        })
//        sensor?.start()
    }
    
    class Observer:ActivityRecognitionObserver{
        func onActivityChanged(data: Array<ActivityRecognitionData>) {
            print(data)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

