# DrowsinessWatch — Apple Watch 居眠り防止アプリ

Apple Watch 単体で動作する、居眠り検知 + 振動アラートアプリです。
運転中・会議中・自習中など、「寝てはいけない」シーンで装着し監視を開始すると、
居眠りを検知した瞬間に Apple Watch が段階的に強く振動し、眠気を覚まします。

## 機能

- **心拍数モニタリング**: HealthKit で心拍数をリアルタイム取得し、個人のベースラインを動的に学習します。
- **体動モニタリング**: CoreMotion の加速度センサーで手首の動き (活動量) を計測します。
- **居眠り判定**: 心拍数がベースラインより一定割合低下し、かつ腕の動きがほぼ無い状態が
  一定時間続いた場合に「居眠り」と判定します。
- **振動アラート**: Taptic Engine で `notification → failure → retry → notification` の
  段階的ハプティクスを連続再生し、確実にユーザーを起こします。
- **バックグラウンド安定化**: `HKWorkoutSession` (activityType: `.other`) を併用し、
  画面消灯中・他アプリ表示中もセンサー取得と判定を継続します。トグルで ON/OFF 可能。
- **設定と累計発報数の永続化**: 感度・ワークアウトセッション利用可否・累計発報回数を
  `UserDefaults` に保存し、アプリ再起動後も引き継ぎます。
- **発報履歴**: 直近 50 件の発報時刻・心拍・ベースライン・活動量を保存し、
  履歴画面から一覧・削除できます。
- **感度調整**: 0.5〜2.0 のスライダーで閾値をカスタマイズ可能。
- **振動テスト**: その場で振動の強さを体感できるボタンを搭載。

## 検知ロジック

| 条件 | 既定値 |
|------|--------|
| 心拍数の低下率 (対ベースライン) | 12% 以上 |
| 活動量 (加速度 RMS) の静止閾値 | 0.03 m/s² 以下 |
| 連続して満たす時間 | 30 秒 |
| アラートのクールダウン | 10 秒 |

両条件を同時に 30 秒連続で満たしたときに居眠りとして振動します。
誤検知を抑えつつ、静止したまま心拍が下がる「まさに眠りに落ちる瞬間」を捉える設計です。

## プロジェクト構成

```
DrowsinessWatch Watch App/
├── DrowsinessWatchApp.swift        # アプリエントリーポイント
├── Managers/
│   ├── DrowsinessDetector.swift    # 検知ロジック本体
│   ├── HealthKitManager.swift      # 心拍数取得
│   ├── MotionManager.swift         # 加速度取得
│   ├── HapticManager.swift         # 振動再生
│   ├── WorkoutSessionManager.swift # HKWorkoutSession 管理 (バックグラウンド)
│   ├── SettingsStore.swift         # 設定永続化 (UserDefaults)
│   └── AlertHistoryStore.swift     # 発報履歴永続化
├── Views/
│   ├── ContentView.swift           # SwiftUI ホーム画面
│   └── HistoryView.swift           # 発報履歴一覧画面
└── Resources/
    └── Info.plist                  # 権限・watchOS 設定
```

## セットアップ

1. Xcode 15 以上で新規 **watchOS App** プロジェクトを作成します
   (Interface: SwiftUI / Language: Swift)。
2. 生成された `Watch App` ターゲット配下に本リポジトリの `DrowsinessWatch Watch App/`
   配下のファイルをドラッグ & ドロップで追加します。
3. ターゲットの **Signing & Capabilities** で以下を有効にします:
   - HealthKit
   - Background Modes → Workout processing
4. `Info.plist` の権限文言 (`NSHealthShareUsageDescription`, `NSMotionUsageDescription`) を
   必要に応じて編集します。
5. Apple Watch 実機にビルドしてインストールします (ハプティクスとセンサーはシミュレータでは動きません)。

## 使い方

1. Apple Watch でアプリを起動します。
2. 「監視開始」をタップし、HealthKit の権限を許可します。
3. 画面上部のステータスが **監視中** になると検知が稼働します。
4. 居眠りを検知すると **居眠り検知!!** となり Apple Watch が振動します。
5. 「停止」で監視を終了します。

## 注意事項

- 本アプリは医療機器ではありません。あくまで眠気対策補助ツールとしてご利用ください。
- 運転中など安全が重要な場面では、過信せず、こまめな休憩を優先してください。
- `HKWorkoutSession` を利用するため、監視中は watchOS がワークアウト記録中と認識されます。
  (ワークアウト自体は保存せず破棄します)

## ライセンス

MIT License
