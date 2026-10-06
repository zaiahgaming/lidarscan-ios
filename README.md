# LidarScan (iOS LiDAR & Spatial Splat Scanner)

**LidarScan** is an open-source, Polycam-like 3D LiDAR scanning and Gaussian Splatting keyframe capture app for iOS (iOS 17+).

It captures high-density LiDAR point clouds, reconstructs textured meshes in real-time, extracts camera poses and sharp keyframes for 3D Gaussian Splatting, and exports industry-standard formats (`.lidarscan.zip`, Nerfstudio `transforms.json`, COLMAP sparse models, OBJ, PLY, USDZ, GLB).

---

## Features

- **Polycam-style Capture Modes**:
  1. **LiDAR Mesh**: ARWorldTracking with `sceneReconstruction = .meshWithClassification`, `.sceneDepth`, and `.smoothedSceneDepth`. Real-time cyan wireframe mesh overlay as you scan.
  2. **Photo / Splat Capture**: Intelligent pose delta keyframing (>5cm translation or >5° rotation), motion blur filtering, coverage hints, and continuous point cloud accumulation.
- **On-Device 3D Exports**:
  - `pointcloud.ply`: Binary little-endian colored world-space point cloud (voxel downsampled to ~1cm).
  - `mesh/mesh.obj` (+ `mesh.mtl`): Unified textured mesh.
  - `mesh/mesh.ply`: Binary polygon mesh.
  - `mesh/mesh.usdz`: Universal Scene Description export via ModelIO / SceneKit.
  - `mesh/mesh.glb`: Standard binary glTF 2.0 format.
  - `transforms.json`: Nerfstudio / Gaussian Splatting camera convention (OpenGL camera coordinates, row-major matrices).
  - `colmap/sparse/0/`: COLMAP PINHOLE cameras.txt, world-to-camera images.txt with quaternions, and subsampled points3D.txt.
  - `metadata.json`: Device model, frame count, depth units (mm), coordinate system.
  - `<name>.lidarscan.zip`: Streamed pure-Swift zip archive with root folder contract.
- **Interactive 3D Viewer**:
  - Orbit, pinch-to-zoom, and two-finger pan controls in SceneKit.
  - Switch between Mesh and Point Cloud viewing modes.
  - Wireframe toggle.
- **Send to PC Studio**:
  - Automatic zero-configuration Bonjour discovery (`_lidarscan._tcp`) on local Wi-Fi.
  - Manual IP:Port entry with Ping health check (`GET /api/ping`).
  - Fast chunked multipart upload (`POST /api/upload`) with live upload progress percentage.
- **Scans Library & Files App Support**:
  - Built-in document browser with swipe to rename, share, or delete.
  - `UIFileSharingEnabled` & `LSSupportsOpeningDocumentsInPlace` enabled: access captures directly from the iOS **Files** app under *On My iPhone -> LidarScan*.
- **Hardware Fallback**:
  - Graceful detection and guidance on non-LiDAR hardware.

---

## Capture Bundle Specification (v1)

Each capture `<name>.lidarscan.zip` follows the shared format contract:

```
<name>/
  metadata.json                 # Format metadata & device info
  transforms.json               # Nerfstudio / Splatting camera poses & intrinsics
  pointcloud.ply                # Binary little-endian colored world point cloud
  images/frame_00000.jpg ...    # RGB keyframes (full sensor res, JPEG q=0.9)
  depth/frame_00000.png ...     # 16-bit uint16 depth in millimeters (LiDAR 256x192)
  confidence/frame_00000.png ...# 8-bit confidence (0=low, 1=medium, 2=high)
  mesh/mesh.obj (+ mesh.mtl)    # Reconstructed 3D surface mesh
  mesh/mesh.ply
  mesh/mesh.usdz
  mesh/mesh.glb
  colmap/sparse/0/cameras.txt   # COLMAP text model
  colmap/sparse/0/images.txt
  colmap/sparse/0/points3D.txt
```

---

## Sideloading Instructions

Because this repository builds unsigned IPA packages using GitHub Actions macOS runners, you can install it on any compatible iPhone or iPad using **AltStore**, **SideStore**, or **Sideloadly**.

### Prerequisites
- iPhone 12 Pro, 13 Pro, 14 Pro, 15 Pro, 16 Pro, or iPad Pro with LiDAR scanner.
- iOS 17.0 or newer.

### Option 1: Sideloadly (macOS & Windows)
1. Download **Sideloadly** from [sideloadly.io](https://sideloadly.io/).
2. Download `LidarScan-unsigned.ipa` from the latest [GitHub Release](../../releases).
3. Connect your iPhone to your computer via USB.
4. Drag and drop `LidarScan-unsigned.ipa` into Sideloadly.
5. Enter your Apple ID (used for free self-signing).
6. Click **Start**.
7. On your iPhone, go to **Settings > General > VPN & Device Management**, tap your developer certificate, and tap **Trust**.
8. Go to **Settings > Privacy & Security > Developer Mode** and enable Developer Mode (device will reboot).
9. Open **LidarScan** and start scanning!

### Option 2: AltStore / SideStore
1. Download `LidarScan-unsigned.ipa` on your iPhone (e.g. from GitHub Releases in Safari).
2. Open **AltStore** (or **SideStore**) on your device.
3. Go to the **My Apps** tab, tap the `+` button in the top left corner.
4. Select the downloaded `LidarScan-unsigned.ipa`.
5. AltStore will sign and install the app onto your device.

---

## Building from Source

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to define the project structure deterministically in `project.yml`.

### On macOS:
```bash
brew install xcodegen
xcodegen generate
xcodebuild -project LidarScan.xcodeproj -scheme LidarScan -sdk iphoneos -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

---

## License

MIT License.
