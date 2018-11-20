# com.aware.ios.sensor.activityrecognition

[![CI Status](https://img.shields.io/travis/tetujin/com.aware.ios.sensor.activityrecognition.svg?style=flat)](https://travis-ci.org/tetujin/com.aware.ios.sensor.activityrecognition)
[![Version](https://img.shields.io/cocoapods/v/com.aware.ios.sensor.activityrecognition.svg?style=flat)](https://cocoapods.org/pods/com.aware.ios.sensor.activityrecognition)
[![License](https://img.shields.io/cocoapods/l/com.aware.ios.sensor.activityrecognition.svg?style=flat)](https://cocoapods.org/pods/com.aware.ios.sensor.activityrecognition)
[![Platform](https://img.shields.io/cocoapods/p/com.aware.ios.sensor.activityrecognition.svg?style=flat)](https://cocoapods.org/pods/com.aware.ios.sensor.activityrecognition)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

## Installation

com.aware.ios.sensor.activityrecognition is available through [CocoaPods](https://cocoapods.org). 

1. To install it, simply add the following line to your Podfile:
```ruby
pod 'com.aware.ios.sensor.activityrecognition'
```

2. com_aware_ios_sensor_activityrecognition  library into your source code.
```swift
import com_aware_ios_sensor_activityrecognition
```

3. Add a description of `NSMotionUsageDescription` into Info.plist

## Example usage
```swift
let activitySensor = ActivityRecognitionSensor.init(ActivityRecognitionSensor.Config().apply{config in
    config.debug = true
    config.interval = 15
    config.dbType = .REALM
    config.sensorObserver = Observer()
})
activitySensor.start()
```

```swift
class Observer:ActivityRecognitionObserver {
    func onActivityChanged(data: Array<ActivityRecognitionData>) {
        // Your code here ..
    }
}
```

## Author

Yuuki Nishiyama, tetujin@ht.sfc.keio.ac.jp

## License

Copyright (c) 2018 AWARE Mobile Context Instrumentation Middleware/Framework (http://www.awareframework.com)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
