Pod::Spec.new do |s|
  s.name = "MapConductorForArcGIS"
  s.version = "1.3.1"
  s.summary = "MapConductor's ArcGIS provider."
  s.license = { :type => "Apache-2.0", :file => "LICENSE" }
  s.author = "MapConductor"
  s.homepage = "https://github.com/MapConductor/ios-for-arcgis"
  s.source = { :git => "https://github.com/MapConductor/ios-for-arcgis.git", :tag => s.version.to_s }
  s.platform = :ios, "17.0"
  s.swift_version = "5.9"
  s.source_files = "Sources/MapConductorForArcGIS/**/*.swift"
  s.dependency "MapConductorCore"
  # ios-sdk/CLAUDE.md's "iOS Provider Distribution" section says a *dynamic* vendor framework
  # should normally stay a plain `s.dependency "VendorSDK"` resolved from that vendor's own public
  # podspec (both ArcGIS.xcframework and CoreArcGIS.xcframework are confirmed dynamic - `file
  # .../ArcGIS` and `.../CoreArcGIS` both report "Mach-O 64-bit dynamically linked shared
  # library"). Esri only distributes the modern ArcGIS Maps SDK for Swift via Swift Package
  # Manager (see Package.swift's two `.binaryTarget`s pointing at gisupdates.esri.com) - there is
  # no public CocoaPods spec named "ArcGIS" to `s.dependency` against (only the legacy, unrelated
  # "ArcGIS-Runtime-SDK-iOS" Objective-C pod exists on trunk). Vendor both binaries directly
  # instead, same as ios-for-here does for heresdk.xcframework.
  #
  # Frameworks/{ArcGIS,CoreArcGIS}.xcframework are downloaded (not committed - see .gitignore)
  # from the exact URLs/checksums pinned in this package's own Package.resolved, by
  # scripts/fetch-arcgis-xcframeworks.sh. CocoaPods requires vendored_frameworks paths to live
  # inside the pod's own directory tree (silently drops anything that escapes it - see
  # ios-for-here's podspec comment for how that was confirmed), so unlike Package.swift's
  # `.binaryTarget` (which references Esri's URLs directly), these must be real local files here.
  s.vendored_frameworks = ["Frameworks/ArcGIS.xcframework", "Frameworks/CoreArcGIS.xcframework"]
end
