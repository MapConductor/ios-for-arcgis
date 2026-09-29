# Esri の ArcGIS Maps SDK for Swift を CocoaPods から引くためだけの spec。
#
# Esri はこの SDK を Swift Package Manager でしか配っていない（公開 podspec は無い。trunk の
# "ArcGIS-Runtime-SDK-iOS" は旧 Objective-C 版で別物）。そこで、Esri 自身の Package.swift の
# .binaryTarget が指しているのと同じ URL / checksum をここに書き写し、CocoaPods の :http
# ソースとして利用者の環境へ直接ダウンロードさせる。
#
#   https://github.com/Esri/arcgis-maps-sdk-swift/blob/300.1.0/Package.swift
#
# **バイナリは MapConductor 側に一切置かない**（Esri の SDK を再配布する権利は無い）。この
# ファイルはメタデータだけで、実体は毎回 Esri の CDN から降りてくる。SPM 経由で入れたときと
# 同じ経路・同じ checksum なので、SPM 利用者と CocoaPods 利用者が同じバイナリを掴む。
#
# バージョンを上げるときは、上の Package.swift から url と checksum を写し、s.version と
# ios-for-arcgis 側の Package.swift / Package.resolved も同時に合わせること（片方だけ上げると
# SPM 経路と CocoaPods 経路で別バージョンの ArcGIS をビルドすることになる。実際に 200.8.1 と
# 300.1.0 で食い違っていた）。
Pod::Spec.new do |s|
  # Esri の SDK そのものを指すので、名前も素直に "ArcGIS"。Esri がこの SDK を CocoaPods に
  # 出すことはないので、trunk 上で名前が衝突する心配はしなくてよい。
  s.name = "ArcGIS"
  # Esri の SDK バージョンをそのまま名乗る。MapConductor 自身のバージョンとは無関係。
  s.version = "300.1.0"
  s.summary = "Esri's official ArcGIS Maps SDK for Swift binary, fetched from Esri's CDN."
  s.description = <<-DESC
    A metadata-only podspec that points CocoaPods at the official ArcGIS Maps SDK for Swift
    xcframework published by Esri, so CocoaPods-based projects (e.g. React Native apps) can
    depend on it the same way Swift Package Manager users do. No Esri binary is redistributed
    by MapConductor - CocoaPods downloads it straight from Esri.
  DESC
  s.homepage = "https://developers.arcgis.com/swift/"
  s.author = { "Esri" => "https://www.esri.com/" }
  s.license = {
    :type => "Esri Master License Agreement",
    :text => "ArcGIS Maps SDK for Swift is licensed by Esri under the Esri Master License " \
             "Agreement. See https://www.esri.com/legal/pdfs/mla_e204_e300/english",
  }
  # ArcGIS Maps SDK for Swift 300.x requires iOS 18 (Esri's Package.swift declares .iOS(.v18)).
  s.platform = :ios, "18.0"
  s.source = {
    :http => "https://gisupdates.esri.com/ArcGIS_MapsSDK/300.1.0/ArcGIS-Swift-v300.1.xcframework.zip",
    :sha256 => "c6d5bef8a22c23c3c39a9e2cdf4fc2712dd209fc18746f583e7fbb94512868e5",
  }
  # 300.x の zip は直下に ArcGIS.xcframework 1 個だけ（200.x では CoreArcGIS.xcframework が
  # 別バイナリとして分かれていたが、300 で統合された）。
  s.vendored_frameworks = "ArcGIS.xcframework"
end
