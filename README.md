# gamepad_flutter

Flutter gamepad integration: examples and utilities to detect and map controller inputs across Android, iOS, Windows, macOS, Linux and Web.

## Short description (for GitHub)

Flutter gamepad integration and examples for detecting and mapping controller inputs on Android, iOS, Windows, macOS, Linux, and Web.

## About

This repository contains a Flutter project demonstrating how to integrate and use gamepads/controllers in a cross-platform Flutter application. It provides practical examples for device detection, button and axis mapping, and a small demo app you can adapt for games or interactive applications.

## Features

- Detect connected gamepads (USB/Bluetooth) on supported Flutter platforms.
- Read button presses and axis movements (joysticks, triggers, D-pad).
- Provide mapping examples for different platforms.
- Prepared for Android, iOS, Windows, macOS, Linux and Web.

## Requirements

- Flutter SDK (stable channel recommended)
- Platform-specific development tools (Android SDK, Xcode for iOS/macOS, desktop build tools)

## Installation and running

1. Clone the repository:

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
cd gamepad_flutter
```

2. Install dependencies:

```bash
flutter pub get
```

3. Run the app on a connected device or emulator:

```bash
flutter run
```

Use `flutter devices` to list available devices and `-d <device-id>` to select a specific one.

## Usage

- Connect a gamepad via USB or Bluetooth to your device.
- Open the app and observe the incoming input events (buttons and axes).
- Use the code in the `lib/` directory as a reference for integrating controller input into your own project.

## Project structure

- `lib/` — Flutter app source code (demo and input handling logic)
- `android/`, `ios/`, `windows/`, `linux/`, `macos/`, `web/` — platform-specific code and configuration
- `test/` — tests (if present)

## Contributing

Contributions are welcome. Open issues for bugs or design discussions, and submit focused, well-tested pull requests.

## License

Add a `LICENSE` file with your preferred license (for example, MIT). I can add one for you if you want.

## Contact

If you want help adapting this example to your project, open an issue or contact me on GitHub.
