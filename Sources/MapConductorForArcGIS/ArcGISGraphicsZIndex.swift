import ArcGIS

/// 帯の中の重なり順。ポリゴン・サークル・ポリライン・マーカーのレンダラごとに 1 つ持つ。
///
/// 帯（ポリゴン < サークル < ポリライン < マーカー）は GraphicsOverlay 自体の並びで決まる
/// （``ArcGISOverlayStacking``）。帯の**中**は (state の zIndex, 渡された順) で決め、その順位を
/// 各 Graphic の `zIndex` に書く。
///
/// state の zIndex をそのまま書かないのは、ArcGIS が同じ `zIndex` の Graphic を足した順に描くとは
/// 限らないから（API リファレンスは「通常は」足した順とし、順序が要るなら zIndex を明示せよと
/// している）。iPad の 3D（SceneView）では、zIndex を 1 に上げて 0 に戻した Graphic が、同じ 0 の
/// Graphic の上に来た（先に渡したのに）。android-for-arcgis ではタブレットの 2D で、zIndex=0 の 2 枚の
/// 間に zIndex=1 が挟まると後から足した方が下に描かれた。順位はどれも違う値なので、同じ値の扱いに頼らない。
///
/// 順位は狭義単調増加であればよく、連番である必要はない。外したときは詰めない。足すときは
/// 前後の間に空きがあればそこへ、無ければ後ろの順位を空きが出るところまで 1 ずつずらす。
/// いちばん上に足す（よくある場合）は 1 つ書くだけ。android-for-arcgis の同名の型と同じ。
///
/// 以前は zIndex を属性（`"zIndex"`）に書き、`onPostProcess` で `removeAllGraphics` → 再追加で
/// 並べ替えていた（サークルは並べ替えもしていなかった）。
@MainActor
final class ArcGISGraphicsZIndex {
    private final class Entry {
        let graphic: Graphic
        var zIndex: Int
        var tie: Double
        let seq: Int
        var rank: Int

        init(graphic: Graphic, zIndex: Int, tie: Double, seq: Int) {
            self.graphic = graphic
            self.zIndex = zIndex
            self.tie = tie
            self.seq = seq
            self.rank = 0
        }
    }

    private var entries: [Entry] = []
    private var byGraphic: [ObjectIdentifier: Entry] = [:]
    private var nextSeq = 0

    /// `graphic` を `zIndex`（`nil` は 0）の位置に置く。初めての Graphic は同じ zIndex の中で
    /// いちばん上（渡された順）。置いてある Graphic の zIndex が変わったときは、最初に渡された
    /// 順を保ったまま移す。
    ///
    /// `tie` は同じ zIndex の中の順位（大きいほど上）。マーカーは画面で下・左ほど上
    /// （``MarkerDrawOrder``）にするため位置と地図の向きから求めて渡す。ほかは 0 のまま（渡された順）。
    func place(_ graphic: Graphic, _ zIndex: Int?, tie: Double = 0) {
        let z = zIndex ?? 0
        let entry: Entry
        if let existing = byGraphic[ObjectIdentifier(graphic)] {
            if existing.zIndex == z, existing.tie == tie { return }
            entries.remove(at: indexOf(existing))
            existing.zIndex = z
            existing.tie = tie
            entry = existing
        } else {
            entry = Entry(graphic: graphic, zIndex: z, tie: tie, seq: nextSeq)
            nextSeq += 1
            byGraphic[ObjectIdentifier(graphic)] = entry
        }
        let at = insertionPoint(entry)
        entries.insert(entry, at: at)
        assignRanks(from: at)
    }

    /// 置いてある Graphic の `tie` をまとめて差し替え、並べ直す。地図を回してマーカーの
    /// 順位（``MarkerDrawOrder``）が一斉に変わるときに使う。1 つずつ ``place(_:_:tie:)`` すると
    /// ずらしが件数の 2 乗になるので、1 回並べ替えて順位を振り直す。置いていない Graphic は無視する。
    func retie(_ ties: [(graphic: Graphic, tie: Double)]) {
        var changed = false
        for (graphic, tie) in ties {
            guard let entry = byGraphic[ObjectIdentifier(graphic)], entry.tie != tie else { continue }
            entry.tie = tie
            changed = true
        }
        guard changed else { return }
        entries.sort(by: precedes)
        var previous = -1
        for entry in entries {
            // 順位は狭義単調増加なら何でもよい。前より大きいままなら書き換えない。
            if entry.rank <= previous { entry.rank = previous + 1 }
            if entry.graphic.zIndex != entry.rank { entry.graphic.zIndex = entry.rank }
            previous = entry.rank
        }
    }

    /// `graphic` を外す。順位は詰めない（残りの並びはそのまま正しい）。
    func forget(_ graphic: Graphic) {
        guard let entry = byGraphic.removeValue(forKey: ObjectIdentifier(graphic)) else { return }
        entries.remove(at: indexOf(entry))
    }

    /// まとめて外す。多いときは 1 回の走査で外す（1 つずつだと配列の詰め直しが件数の 2 乗になる）。
    func forget<S: Sequence>(_ graphics: S) where S.Element == Graphic {
        var gone = Set<ObjectIdentifier>()
        for graphic in graphics where byGraphic.removeValue(forKey: ObjectIdentifier(graphic)) != nil {
            gone.insert(ObjectIdentifier(graphic))
        }
        guard !gone.isEmpty else { return }
        entries.removeAll { gone.contains(ObjectIdentifier($0.graphic)) }
    }

    /// `graphic` の順位（大きいほど上）。置いていない Graphic は nil。
    func rank(of graphic: Graphic) -> Int? {
        byGraphic[ObjectIdentifier(graphic)]?.rank
    }

    /// 置いている Graphic の数（テスト用）。
    var count: Int { entries.count }

    private func precedes(_ a: Entry, _ b: Entry) -> Bool {
        if a.zIndex != b.zIndex { return a.zIndex < b.zIndex }
        if a.tie != b.tie { return a.tie < b.tie }
        return a.seq < b.seq
    }

    private func insertionPoint(_ entry: Entry) -> Int {
        var lo = 0
        var hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if precedes(entries[mid], entry) { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func indexOf(_ entry: Entry) -> Int {
        let i = insertionPoint(entry)
        precondition(i < entries.count && entries[i] === entry, "stack order lost track of a graphic")
        return i
    }

    /// `from` の順位を前の 1 つ上にし、後ろが狭義単調増加に戻るところまでずらす。
    private func assignRanks(from: Int) {
        var previous = from > 0 ? entries[from - 1].rank : -1
        for i in from..<entries.count {
            let entry = entries[i]
            if i > from && entry.rank > previous { break }
            entry.rank = previous + 1
            if entry.graphic.zIndex != entry.rank { entry.graphic.zIndex = entry.rank }
            previous = entry.rank
        }
    }
}
