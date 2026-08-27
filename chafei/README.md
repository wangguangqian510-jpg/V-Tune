# 茶沸（ChaFei）

iOS 竖屏彩墨风解压小游戏。茶人静心，以水线压制浮沫/焦苦/杂念。

## 技术栈

- Expo SDK 51 + React Native + TypeScript
- React Native Skia（程序化水墨图形）
- React Native Reanimated（游戏循环）
- EAS Build 云端出 ipa（无 Mac）
- GitHub Actions 自动构建

## 目录

```
chafei/
  package.json
  app.json          # bundleId = com.chafei.app
  eas.json          # iOS preview / production
  src/
    App.tsx
    game/           # engine + upgrades + config
    components/     # HUD + GameCanvas + UpgradeCards
  .github/workflows/ios-build.yml
```

## 本地开发

```bash
cd chafei
npm install
npx expo start
```

## 无 Mac 出 ipa 流程

1. 在 Expo 后台创建 token：https://expo.dev/accounts/{你的账号}/settings/access-tokens
2. 把 token 存到 GitHub 仓库 Secret：`EXPO_TOKEN`
3. 推送 `main` 分支，Actions 自动调 EAS Build
4. EAS Build 完成后下载 `.ipa`
5. 用第三方自签工具（v-tune 同款 p12 + mobileprovision）签名安装

## 第三方自签

`eas.json` 已设 `credentialsSource: "local"`。构建前在仓库根目录放：

```
credentials/
  ios/
    distributionCert.p12
    provisioningProfile.mobileprovision
```

然后运行：

```bash
cd chafei
npx eas credentials
```

## 设计要点

- 单局 2 分钟
- 敌人 3 种：浮沫（直沉）、焦苦（斜冲）、杂念（死亡分裂 2 小个）
- 玩家 100 心境值，茶筅每 0.9s 自动发射水线
- 灵墨满弹 → 三选一升级
- 技能树 3 系：茶种（龙井/普洱/白毫）× 手法（点茶/煎茶/煮茶）× 心境（静/空灵墨/明）
