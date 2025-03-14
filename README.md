# AWARE: Activity Recognition

[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)

**Aware Activity Recognition** (com.awareframework.ios.sensor.activityrecognition) is a plugin for AWARE Framework which is one of an open-source context-aware instrument. This plugin allows us to manage motion activity data (such as running, walking, and automotive) that is provided by iOS [CMMotionActivityManager](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager).

## Requirements
iOS 13 or later

## Installation

You can integrate this framework into your project via Swift Package Manager (SwiftPM) or CocoaPods.

### SwiftPM
1. Open Package Manager Windows
    * Open `Xcode` -> Select `Menu Bar` -> `File` -> `App Package Dependencies...` 

2. Find the package using the manager
    * Select `Search Package URL` and type `git@github.com:awareframework/com.awareframework.ios.sensor.activityrecognition.git`

3. Import the package into your target.

### CocoaPods
1. To install it, simply add the following line to your Podfile:
```ruby
pod 'com.awareframework.ios.sensor.activityrecognition'
```

2. com_awareframework_ios_sensor_activityrecognition  library into your source code.
```swift
import com_awareframework_ios_sensor_activityrecognition
```

3. Add a description of `NSMotionUsageDescription` into Info.plist

## Public functions

### ActivityRecognitionSensor

+ `init(config:ActivityRecognitionSensor.Config?)` : Initializes the activity recognition sensor with the optional configuration.
+ `start()`: Starts the activity recognition sensor with the optional configuration.
+ `stop()`: Stops the service.

### ActivityRecognitionSensor.Config

Class to hold the configuration of the sensor.

#### Fields

+ `sensorObserver: ActivityRecognitionObserver`: Callback for live data updates.
+ `interval: Int`: Data sampling interval in minute. (default = 10)
+ `enabled: Boolean` Sensor is enabled or not. (default = `false`)
+ `debug: Boolean` enable/disable logging to `Logcat`. (default = `false`)
+ `label: String` Label for the data. (default = "")
+ `deviceId: String` Id of the device that will be associated with the events and the sensor. (default = "")
+ `dbEncryptionKey: String` Encryption key for the database. (default = `null`)
+ `dbType: Engine` Which db engine to use for saving data. (default = `Engine.DatabaseType.NONE`)
+ `dbPath: String` Path of the database. (default = "aware_activityrecognition")
+ `dbHost: String` Host for syncing the database. (default = `null`)

## Broadcasts

### Fired Broadcasts

+ `ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION` fired when accelerometer saved data to db after the period ends.

### Received Broadcasts

+ `ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION_START`: received broadcast to start the sensor.
+ `ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION_STOP`: received broadcast to stop the sensor.
+ `ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION_SYNC`: received broadcast to send sync attempt to the host.
+ `ActivityRecognitionSensor.ACTION_AWARE_ACTIVITYRECOGNITION_SET_LABEL`: received broadcast to set the data label. Label is expected in the `ActivityRecognitionSensor.EXTRA_LABEL` field of the intent extras.

## Data Representations

### Activity Recognition Data

Contains the raw sensor data.

| Field     | Type   | Description                                                         |
| --------- | ------ | ------------------------------------------------------------------- |
| activities | String | The detected activities' name  |
| confidence | Int | The confidence that the motion data is accurate. (0=low, 1=medium, 2=high) |
| stationary | Bool | A Boolean indicating whether the device is stationary.  |
| walking | String | A Boolean indicating whether the device is on a walking person. |
| running | String | A Boolean indicating whether the device is on a running person.  |
| automotive | String | A Boolean indicating whether the device is in an automobile.  |
| cycling | String | A Boolean indicating whether the device is in a bicycle.  |
| unknown | String | A Boolean indicating whether the type of motion is unknown.  |
| label     | String | Customizable label. Useful for data calibration or traceability     |
| deviceId  | String | AWARE device UUID                                                                 |
| label     | String | Customizable label. Useful for data calibration or traceability     |
| timestamp | Int64   | Unixtime milliseconds since 1970                                          |
| timezone  | Int    | Timezone  of the device                                       |
| os        | String | Operating system of the device (ex. ios)                              |


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
* [ Apple | CMMotionActivityManager ](https://developer.apple.com/documentation/coremotion/cmmotionactivitymanager)
* [ Apple | CMMotionActivity ](https://developer.apple.com/documentation/coremotion/cmmotionactivity)
* [ Apple | CMMotionActivityConfidence ](https://developer.apple.com/documentation/coremotion/cmmotionactivityconfidence)

## License

Copyright (c) 2021 AWARE Mobile Context Instrumentation Middleware/Framework (http://www.awareframework.com)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
