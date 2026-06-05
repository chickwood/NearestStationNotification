# iOS Info.plist 需要手动添加的配置项

在 `ios/Runner/Info.plist` 的 `<dict>` 内追加以下内容：

```xml
<!-- 位置情報使用説明（必須） -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>最寄り駅を表示するために位置情報を使用します。</string>

<!-- バックグラウンドモード（画面点灯中の他アプリ利用時も継続） -->
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
</array>
```

## 注意事項

- `NSLocationAlwaysUsageDescription` および
  `NSLocationAlwaysAndWhenInUseUsageDescription` は追加しないこと。
  「常に許可」を誘導しない設計のため。
- `UIBackgroundModes` に `location` を含めることで、
  画面点灯中に他アプリを使用していても GPS 取得が継続される。
