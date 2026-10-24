Pod::Spec.new do |s|
  s.name = "MapConductorForArcGIS"
  s.version = "1.3.1"
  s.summary = "MapConductor's ArcGIS provider."
  s.license = { :type => "Apache-2.0", :file => "LICENSE" }
  s.author = "MapConductor"
  s.homepage = "https://github.com/MapConductor/ios-for-arcgis"
  s.source = { :git => "https://github.com/MapConductor/ios-for-arcgis.git", :tag => s.version.to_s }
  # ArcGIS Maps SDK for Swift 300.x requires iOS 18 - Package.swift declares the same floor.
  s.platform = :ios, "18.0"
  s.swift_version = "5.9"
  s.source_files = "Sources/MapConductorForArcGIS/**/*.swift"
  s.dependency "MapConductorCore"
  # ios-sdk/CLAUDE.md's "iOS Provider Distribution" section says a *dynamic* vendor framework
  # should stay a plain `s.dependency "VendorSDK"` resolved from that vendor's own podspec
  # (ArcGIS.xcframework is confirmed dynamic - `file .../ArcGIS` reports "Mach-O 64-bit
  # dynamically linked shared library"). Esri publishes no podspec at all - the modern ArcGIS
  # Maps SDK for Swift ships only through Swift Package Manager (trunk's "ArcGIS-Runtime-SDK-iOS"
  # is the legacy Objective-C SDK, unrelated) - so ArcGIS.podspec in this repo stands in for it:
  # a metadata-only spec whose :http source is Esri's own CDN URL, copied verbatim from Esri's
  # Package.swift .binaryTarget along with its sha256.
  #
  # This deliberately replaces the old `s.vendored_frameworks` setup, which required
  # Frameworks/*.xcframework to be present inside this pod's directory and therefore could not be
  # published: shipping this pod with the binaries committed (or inside the release tag's tarball)
  # would be redistributing Esri's SDK, which we have no license to do. With the dependency
  # instead, each consuming app downloads the binary from Esri itself, exactly as an SPM consumer
  # does, and CocoaPods verifies the checksum and caches it.
  #
  # Because Esri has no spec repo, the consuming app's Podfile has to name where this spec lives,
  # e.g. (React Native, from react-sdk's example):
  #
  #   pod 'ArcGIS', :podspec => 'https://raw.githubusercontent.com/MapConductor/ios-for-arcgis/1.3.1/ArcGIS.podspec'
  #
  # Nothing else about the SDK's version lives here - bump it in ArcGIS.podspec and in
  # Package.swift/Package.resolved together.
  s.dependency "ArcGIS", "300.1.0"
end
