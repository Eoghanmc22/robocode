# `robocode`

This project is a custom software stack to control ROVs based on a Raspberry Pi 4/5.
This project It is based on the bevy game engine and is intended to be used in the MATE ROV Competition.

## ROV Hardware Support

The software current only has support for the following hardware

- Raspberry Pi 4 or 5
- The Blue Robotics Navigator Flight Controller
  - ICM20602 (6-axis IMU, Gyro + Accelerometer)
  - MMC5983 (3-axis Magnetometer)
  - PCA9685 (16-channel PWM controller)
    - Controls PWM based ESCs to drive thrusters
- The Blue Robotics Bar30 and Bar02 Depth Sensors
  - MS5837 (Depth sensor)
- Neopixel Light Strips
  - The RGB kind
- Any H.264 webcam
- [Our custom 4 channel DC motor controller](https://github.com/Eoghanmc22/dc-motor)

Hardware support may be expanded in the future, but this is not currently a priority.

## Surface Hardware Support

The recommended way to use the surface application is with the nix flake.
Assuming the nix package manager is installed on your system, you can run the
surface component with `nix run`, however compiling may take a long time.

Getting it to run outside of nix may be challenging, If you choose to do this,
at a minimum the following will need to be installed on your system:

- See [Bevy Linux Deps](https://github.com/bevyengine/bevy/blob/main/docs/linux_dependencies.md)
- See [opencv-rust Deps](https://github.com/twistedfall/opencv-rust)
- TODO: Document gstreamer deps

## Motor configurations

We support control of arbitrary thruster configurations provided the following data is available.

- Thruster Performance curves
  - Needs a mapping between PWM, thrust, and amperage draw.
  - This is already included for Blue Robotics T200 thrusters.
- Thruster Position Information
  - Orientation as a vector
  - Position relative to the robot's origin as a vector

See the `motor_code` crate for more.

## Project Structure

This codebase is broken up into the following crates

- `robot`
  - This is the binary running on the Raspberry Pi
  - Actually manages/controls the robot
  - It is written as a headless bevy app
- `surface`
  - This is the binary running on the laptop controlling the ROV
  - Connects to the ROV, reads human input, displays cameras, runs computer vision
  - Written as a normal bevy app
- `common`
  - This library defines the communication between `robot` and `surface`
  - ECS sync, ECS bundles and components, most type definitions, networking protocol
- `motor_code`
  - This library implements our motor math code
  - The responsible for mapping movement commands to thruster commands
- `networking`
  - This library implements a fast non-blocking TCP server and client
  - Handles low level networking protocol details

## System Ordering

- Startup: Setup what's needed
  - Add necessary data to ECS
- First: Prepare for tick
  - Currently unused
- PreUpdate: Read in new data
  - Read inbound network packets, sensors, user input
- Update: Process state and determine next state
  - Compute new movement, motor math, compute orientation
- PostUpdate Write out new state
  - Write outbound network packets, motor speeds, handle errors
  - Avoid mutating state
- Last: Any cleanup
  - Shutdown logic

## Sync Model

### Background

In this iteration of my software stack, I decided to leverage the bevy game
engine on both the surface and the robot. This choice was made so to keep the
architecture of both halfs more consistent. In our previous codebase
(Eoghanmc22/mate-rov-2023) the surface and robot implementation used
fundamentally different architectures, and this created the possibility desync
and consistency problems due to both sides making slightly different
assumptions and storing data in different ways. Some of the differences I
wanted to eliminate from the 2023 code base include:

- Different core data structure (ECS vs Type erased hash map)
- Different programming paradigms (Data driven vs Event based message passing)
- Different concurrency models (Concurrent game loop vs Every subsystem gets its own thread)
- Probably other things

While the old codebase was functional, it was difficult to maintain and had several limitations.
For example, the opencv thread in the 2023 code did not have access to the robot's state.
Also, we couldn't do goofy things like drive two ROVs at the same time because both ROVs would try to use the same keys in the "distributed" hash map.
Armed with the perfect excuse to rewrite everything, I settled on the idea of a distributed ECS.
This would allow communication between `surface` and `robot` to transparent as synchronization would simply be implemented upon the same infrastructure already used to store local state.
Furthermore, all the (somewhat ugly) sync logic is contained within a single module in `common` instead of being spread throughout the codebase at every state read/write.
This allows for a consistent code style between `robot` and `surface` and a general simplification of the codebase.

### Design

Each component types implements serde's Serialize and Deserialize traits.
Entities with any of these components will be replicated on all peers if they
are tagged with the Replicate component. We take advantage of bevy's change
detection system and send a packet to all peers when a component with a known
type is mutated. This will update the peer's replicated entity to match the
updated value for the component.

## Thanks

Thanks to all the people who made the libraries and tools I used in ways they (probably) never could have imagined.

Made with :heart: in :crab: :rocket: 
