import MapKit
import SwiftUI

struct HomeView: View {
    var isPresented = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var locationManager: LocationManager
    @State private var cameraManager = CameraManager()
    @State private var mapPosition: MapCameraPosition
    @State private var mapLocation: CLLocation?
    @State private var isCameraExpanded = false

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
        span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
    )

    init(isPresented: Bool = true, locationManager: LocationManager? = nil) {
        self.isPresented = isPresented
        let locationManager = locationManager ?? LocationManager()
        _locationManager = State(initialValue: locationManager)
        let savedLocation = locationManager.lastKnownLocation
        _mapLocation = State(initialValue: savedLocation)
        _mapPosition = State(initialValue: .region(
            savedLocation.map(Self.region(for:)) ?? Self.defaultRegion
        ))
    }

    private var isActive: Bool { isPresented && scenePhase == .active }
    // Resolve the location prompt before presenting the camera prompt.
    private var shouldRunCamera: Bool {
        isActive && locationManager.authorizationStatus != .notDetermined
    }

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let compactWidth = min(geometry.size.width - 48, 260)
            let compactHeight = min(100.0, max(148, geometry.size.height * 0.38))
            let expandedWidth = geometry.size.width + insets.leading + insets.trailing
            let expandedHeight = geometry.size.height + insets.top + insets.bottom

            ZStack(alignment: .top) {
                Map(position: $mapPosition) {
                    if locationManager.isAuthorized {
                        UserAnnotation()
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls { }
                .ignoresSafeArea()
                .opacity(isCameraExpanded ? 0 : 1)
                .allowsHitTesting(!isCameraExpanded)
                .accessibilityHidden(isCameraExpanded)
                .accessibilityIdentifier("homeMap")

                if let message = locationMessage, !isCameraExpanded {
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }

                // This view never moves between branches or navigation containers.
                // Its layer and session survive both directions of the transition.
                cameraWindow
                    .frame(
                        width: isCameraExpanded ? expandedWidth : compactWidth,
                        height: isCameraExpanded ? expandedHeight : compactHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: isCameraExpanded ? 0 : 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: isCameraExpanded ? 0 : 28, style: .continuous)
                            .strokeBorder(.white.opacity(isCameraExpanded ? 0 : 0.35), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(isCameraExpanded ? 0 : 0.22), radius: 20, y: 8)
                    .position(
                        x: (geometry.size.width + (isCameraExpanded ? insets.trailing - insets.leading : 0)) / 2,
                        y: isCameraExpanded
                            ? (geometry.size.height + insets.bottom - insets.top) / 2
                            : geometry.size.height - compactHeight / 2 - 24
                    )

                if isCameraExpanded {
                    ExpandedCameraView { setCameraExpanded(false) }
                        .transition(.opacity)
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
        .statusBarHidden(isCameraExpanded)
        .task(id: isActive) {
            locationManager.setActive(isActive)
        }
        .task(id: shouldRunCamera) {
            cameraManager.setActive(shouldRunCamera)
        }
        .onDisappear {
            locationManager.setActive(false)
            cameraManager.setActive(false)
        }
        .onChange(of: locationManager.location) { _, location in
            // Refresh the starting position without chasing GPS noise or
            // overriding a map the user has deliberately panned or zoomed.
            guard let location, !mapPosition.positionedByUser else { return }
            if let mapLocation,
               location.distance(from: mapLocation) <= max(100, location.horizontalAccuracy) {
                return
            }
            mapLocation = location
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.6)) {
                mapPosition = .region(Self.region(for: location))
            }
        }
        .onChange(of: locationManager.isAuthorized) { _, authorized in
            if !authorized {
                mapLocation = locationManager.lastKnownLocation
                mapPosition = .region(mapLocation.map(Self.region(for:)) ?? Self.defaultRegion)
            }
        }
    }

    private var cameraWindow: some View {
        ZStack {
            Color(white: 0.08)
            CameraPreview(session: cameraManager.session, device: cameraManager.device)

            if cameraManager.status != .running {
                cameraPlaceholder
                    // Keep text wrapping stable as the surrounding camera grows.
                    .frame(maxWidth: 260)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.08))
                    .allowsHitTesting(false)
            }

            if !isCameraExpanded {
                Button {
                    setCameraExpanded(true)
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand camera")
                .accessibilityHint("Opens the live camera full screen")
                .accessibilityIdentifier("expandCamera")

                if cameraManager.status == .running {
                    VStack {
                        Spacer()
                        Text("Scan a ball")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.top, 32)
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            Text(cameraMessage.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Text(cameraMessage.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(20)
        .accessibilityElement(children: .combine)
    }

    private var cameraMessage: (title: String, detail: String) {
        switch cameraManager.status {
        case .idle, .requestingPermission:
            ("Your camera, live", "Allow camera access to get started.")
        case .starting, .running:
            ("Starting camera", "Your live preview will appear here.")
        case .denied:
            ("Camera access is off", "Enable Camera for BallDrop in Settings.")
        case .restricted:
            ("Camera is restricted", "Camera access is limited on this device.")
        case .unavailable:
            ("No camera available", "Try the live preview on an iPhone.")
        case .interrupted:
            ("Camera paused", "The preview will resume when available.")
        case .failed:
            ("Camera unavailable", "Return to the app to try again.")
        }
    }

    private var locationMessage: String? {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            locationManager.lastKnownLocation == nil
                ? "Location is off · Showing Chicago"
                : "Location is off · Showing last location"
        case .authorizedAlways, .authorizedWhenInUse:
            if locationManager.isTemporarilyUnavailable {
                "Location temporarily unavailable"
            } else if locationManager.location == nil && locationManager.lastKnownLocation == nil {
                "Finding your location…"
            } else {
                nil
            }
        default:
            nil
        }
    }

    private nonisolated static func region(for location: CLLocation) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    }

    private func setCameraExpanded(_ expanded: Bool) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.08)) {
            isCameraExpanded = expanded
        }
    }
}

#Preview {
    HomeView(isPresented: false)
}
