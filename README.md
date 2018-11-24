# Aware Activity Recognition

[![CI Status](https://img.shields.io/travis/awareframework/com.awareframework.ios.sensor.activityrecognition.svg?style=flat)](https://travis-ci.org/awareframework/com.awareframework.ios.sensor.activityrecognition)
[![Version](https://img.shields.io/cocoapods/v/com.awareframework.ios.sensor.activityrecognition.svg?style=flat)](https://cocoapods.org/pods/com.awareframework.ios.sensor.activityrecognition)
[![License](https://img.shields.io/cocoapods/l/com.awareframework.ios.sensor.activityrecognition.svg?style=flat)](https://cocoapods.org/pods/com.awareframework.ios.sensor.activityrecognition)
[![Platform](https://img.shields.io/cocoapods/p/com.awareframework.ios.sensor.activityrecognition.svg?style=flat)](https://cocoapods.org/pods/com.awareframework.ios.sensor.activityrecognition)

**Aware Activity Recognition** (com.awareframework.ios.sensor.activityrecognition) is a plugin for AWARE Framework which is one of an open-source context-aware instrument. This plugin allows us to manage motion activity data (such as running, walking, and automotive) that is provided by iOS [CMMotionActivityManager](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager).

## Requirements
iOS 10 or later

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

## Data Representations

### Activity Recognition Data
| Field        | Type   | Description                                                            |
| ------------ | ------ | ---------------------------------------------------------------------- |
| startDate   | Long | The time (unixtime milliseconds since 1970) at which the change in motion occurred. |
| confidence  | Int  | The [confidence](https://developer.apple.com/documentation/coremotion/cmmotionactivityconfidence) in the assessment of the motion type. |
| stationary  | Bool | A Boolean indicating whether the device is stationary.|
| walking     | Bool | A Boolean indicating whether the device is on a walking person. |
| running     | Bool | A Boolean indicating whether the device is on a running person. |
| automotive  | Bool | A Boolean indicating whether the device is in an automobile. |
| cycling     | Bool | A Boolean indicating whether the device is in a bicycle. |
| unknown     | Bool | A Boolean indicating whether the type of motion is unknown. |
| deviceId     | String | AWARE device UUID                                                      |
| label        | String | Customizable label. Useful for data calibration or traceability        |
| timestamp    | Long   | Unixtime milliseconds since 1970                                       |
| timezone     | Int    | Timezone of the device                                 |
| os           | String | Operating system of the device (e.g., iOS)                           |


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

Yuuki Nishiyama, yuuki.nishiyama@oulu.fi

## Related Links
* [Apple | CMMotionActivityManager](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager)
* [Apple | CMMotionActivity](https://developer.apple.com/documentation/coremotion/cmmotionactivity)
* [Apple | CMMotionActivityConfidence](https://developer.apple.com/documentation/coremotion/cmmotionactivityconfidence)

## License

Copyright (c) 2018 AWARE Mobile Context Instrumentation Middleware/Framework (http://www.awareframework.com)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
