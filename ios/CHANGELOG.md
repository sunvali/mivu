# Changelog

## [1.2.1](https://github.com/sunvali/mivu/compare/ios-v1.2.0...ios-v1.2.1) (2026-10-31)


### Bug Fixes

* **coach:** close the keyboard when tapping the conversation ([#99](https://github.com/sunvali/mivu/issues/99)) ([3b3e754](https://github.com/sunvali/mivu/commit/3b3e7540b8825f373973f55eb7d3d4e912591beb))
* **coach:** end held delete Undo on time and restore photos under new IDs ([#92](https://github.com/sunvali/mivu/issues/92)) ([72dcd4d](https://github.com/sunvali/mivu/commit/72dcd4d7ec898193b4276324e3e1d2d8ebdc1333))
* **diary:** keep the diary and camera request on a locked launch ([#91](https://github.com/sunvali/mivu/issues/91)) ([e6404ad](https://github.com/sunvali/mivu/commit/e6404adb1c68a26953881e03f2f333485232bff9))

## [1.2.0](https://github.com/sunvali/mivu/compare/v1.1.3...v1.2.0) (2026-10-29)


### Features

* **coach:** undo Coach deletes and add visible meal and food delete ([3cd57f7](https://github.com/sunvali/mivu/commit/3cd57f7654a497dc24f30721e383ffbdc571bcd4))


### Bug Fixes

* **diary:** never start a new diary when the existing one cannot be read ([#86](https://github.com/sunvali/mivu/issues/86)) ([737d647](https://github.com/sunvali/mivu/commit/737d6475733d35fa1e12d77a5cef07f9e2da5f58))
* **diary:** zoom meal photos around the pinch point ([#87](https://github.com/sunvali/mivu/issues/87)) ([e462f02](https://github.com/sunvali/mivu/commit/e462f02dbee1589360daa3eed006dfbeaadc853b))
* **siri:** approve locked-phone Siri messages and harden connection requests ([92ac174](https://github.com/sunvali/mivu/commit/92ac17440476a5c0ad708b7b168bd41c909e04e9))

## [1.1.3](https://github.com/sunvali/mivu/compare/v1.1.2...v1.1.3) (2026-10-28)


### Bug Fixes

* **review:** add Report Reply and tighten privacy wording ([#80](https://github.com/sunvali/mivu/issues/80)) ([443eedc](https://github.com/sunvali/mivu/commit/443eedc106edf9f0da88d9d0307da13bcca0a52f))

## [1.1.2](https://github.com/sunvali/mivu/compare/v1.1.1...v1.1.2) (2026-10-28)


### Bug Fixes

* **live-activity:** clear the outdated card iOS keeps after ending an activity ([#76](https://github.com/sunvali/mivu/issues/76)) ([8657ee8](https://github.com/sunvali/mivu/commit/8657ee8996e418dc7b015a8b819b23af7afe18bb))
* **onboarding:** save setup targets on the waking day ([#75](https://github.com/sunvali/mivu/issues/75)) ([5afd977](https://github.com/sunvali/mivu/commit/5afd977fcec8e9ceb256cfdd615748926b07e506))

## [1.1.1](https://github.com/yakov103/mivu/compare/v1.1.0...v1.1.1) (2026-10-24)


### Bug Fixes

* **coach:** give Pip's bubble and day chip the composer's full width ([#70](https://github.com/yakov103/mivu/issues/70)) ([5279293](https://github.com/yakov103/mivu/commit/5279293c1926819f87d0ba3230661204f7b2f34e))
* **coach:** never leave a failed turn stuck on Thinking ([#71](https://github.com/yakov103/mivu/issues/71)) ([f0c78a4](https://github.com/yakov103/mivu/commit/f0c78a4cde6ec998265f14f712bdc22cf58e3a5b))
* **companion:** keep Pip moving in Low Power Mode on every tab ([#69](https://github.com/yakov103/mivu/issues/69)) ([30b76a3](https://github.com/yakov103/mivu/commit/30b76a3eeb3daf5bebba995c948eb876e73e856d))
* **notifications:** say a meal's calories are a floor when some foods lack them ([#72](https://github.com/yakov103/mivu/issues/72)) ([1533d77](https://github.com/yakov103/mivu/commit/1533d779239d46c4df065b5144402387aeea47f1))

## [1.1.0](https://github.com/yakov103/mivu/compare/v1.0.0...v1.1.0) (2026-10-24)


### Features

* add continuous Coach history and camera-first capture ([5a63421](https://github.com/yakov103/mivu/commit/5a6342146d5e773f71a51b9e9da9eff35b5edb2f))
* add expressive Pip companion with Lottie ([6fca93d](https://github.com/yakov103/mivu/commit/6fca93d99802367553da13b17c3b43b91d4dde7e))
* **capture:** log food from Shortcuts, Action button and Home Screen ([#30](https://github.com/yakov103/mivu/issues/30)) ([cfc7f38](https://github.com/yakov103/mivu/commit/cfc7f38d8071e984f193911a60947746d1706ed8))
* **ci:** add quick checks and automated version releases ([cfe9578](https://github.com/yakov103/mivu/commit/cfe9578f304d1c5276374d40f24080bb93900ca7))
* **coach:** float the composer over the chat with the camera in the field ([#46](https://github.com/yakov103/mivu/issues/46)) ([c987be1](https://github.com/yakov103/mivu/commit/c987be1ab64d28976da040c985ffd0274df90806))
* **coach:** log food by voice and redesign the composer ([#41](https://github.com/yakov103/mivu/issues/41)) ([4f42526](https://github.com/yakov103/mivu/commit/4f42526ff154c63cef3974e2ce3548cd7269b8ef))
* **coach:** on-device Apple Intelligence fallback with ChatGPT recommended ([#49](https://github.com/yakov103/mivu/issues/49)) ([f66b889](https://github.com/yakov103/mivu/commit/f66b8896777af1ebec8e004ca53b041bd3e94532))
* **coach:** Pip speaks in a bubble with a day intake chip ([#67](https://github.com/yakov103/mivu/issues/67)) ([ca8422d](https://github.com/yakov103/mivu/commit/ca8422d1b789c2a7c15aae9e741a855b4ee8f8c0))
* **coach:** reply to a message or Diary record ([#39](https://github.com/yakov103/mivu/issues/39)) ([9cc2693](https://github.com/yakov103/mivu/commit/9cc2693cdeac449e2098653701586e91c94dec1b))
* **coach:** short checked replies with Today-styled receipt cards ([#59](https://github.com/yakov103/mivu/issues/59)) ([437027f](https://github.com/yakov103/mivu/commit/437027f90f5690932a362c358b06f96f71ba45a0))
* **coach:** understand what the person means and act on it ([#44](https://github.com/yakov103/mivu/issues/44)) ([dd5e8c3](https://github.com/yakov103/mivu/commit/dd5e8c34f6f89eb846dda43ee78d3cebb1b5c2ee))
* **connection:** show ChatGPT plan use in Coach and confirm it once ([#52](https://github.com/yakov103/mivu/issues/52)) ([e9aa516](https://github.com/yakov103/mivu/commit/e9aa51686b303f696522d3c7f41c57700cc77049))
* **day:** automatic waking-day rollover with a morning check-in ([#27](https://github.com/yakov103/mivu/issues/27)) ([93fa727](https://github.com/yakov103/mivu/commit/93fa727fefa60ceeb5eb3a8d1606bbee60a1364b))
* **dev:** add fast commit and conditional native push checks ([8cf1e85](https://github.com/yakov103/mivu/commit/8cf1e85e0920726638b987468260f35410d4fa53))
* **diary:** one way to log with Pip and quoted Ask Pip everywhere ([#45](https://github.com/yakov103/mivu/issues/45)) ([d2b0fec](https://github.com/yakov103/mivu/commit/d2b0fecdd50c0af66d0d222434481938957df618))
* **diary:** week-strip Diary, photo-led meal detail and Coach-editable foods ([#38](https://github.com/yakov103/mivu/issues/38)) ([270d881](https://github.com/yakov103/mivu/commit/270d881960f29eac0a961376762cc8a85f22a394))
* enable complete Coach editing and native activity feedback ([#12](https://github.com/yakov103/mivu/issues/12)) ([a71a175](https://github.com/yakov103/mivu/commit/a71a175be10de1219f95130af41ce17ee5117c8a))
* enrich Precision Glass with semantic colors ([f7b8d53](https://github.com/yakov103/mivu/commit/f7b8d53325c73d8a292040f9685fe44d1b098a39))
* **live-activity:** calories left in the Dynamic Island ([#37](https://github.com/yakov103/mivu/issues/37)) ([aa3a436](https://github.com/yakov103/mivu/commit/aa3a4364d645e69eb141e0266d41716c6583a43b))
* **notifications:** tell the user when a logged meal is analyzed ([#34](https://github.com/yakov103/mivu/issues/34)) ([11f4c21](https://github.com/yakov103/mivu/commit/11f4c21b6ed1750e14fbe9306c8a9cfe55a667a7))
* **onboarding:** Pip-hosted setup that sets daily targets ([#26](https://github.com/yakov103/mivu/issues/26)) ([2450c71](https://github.com/yakov103/mivu/commit/2450c71c889ce19c92a3f17e02faf9858446f660))
* **pip:** layered reactive Pip rig ([#23](https://github.com/yakov103/mivu/issues/23)) ([0525c0e](https://github.com/yakov103/mivu/commit/0525c0e03fbc06c80e249a5fe14c940e03147368))
* **pip:** natural motion, drawn blink and the Coach design pose ([#25](https://github.com/yakov103/mivu/issues/25)) ([5c55ebc](https://github.com/yakov103/mivu/commit/5c55ebcdd0d9d136063e01b6bc19e46a43738f49))
* **progress:** chart-first Progress tab with Pip presenting the chart ([#51](https://github.com/yakov103/mivu/issues/51)) ([c691d13](https://github.com/yakov103/mivu/commit/c691d13fb773ee56ddf7f7a0b2557f8214b103c9))
* refresh diary with Precision Glass ([#15](https://github.com/yakov103/mivu/issues/15)) ([021b27a](https://github.com/yakov103/mivu/commit/021b27a7170b2519d0ffc866c025c57e928e6a73))
* **settings:** delete any local profile from the profiles list ([#50](https://github.com/yakov103/mivu/issues/50)) ([1f47b3c](https://github.com/yakov103/mivu/commit/1f47b3c53e866d3514366319f21713e83ccc15eb))
* **settings:** share diary reports as PDF or CSV ([#33](https://github.com/yakov103/mivu/issues/33)) ([8059a5d](https://github.com/yakov103/mivu/commit/8059a5dbc6c8690790872da5766a41eb3b09d4a7))
* **siri:** send Siri prompts to the Coach ([#54](https://github.com/yakov103/mivu/issues/54)) ([cec2127](https://github.com/yakov103/mivu/commit/cec21275aa54618bd948b61bb3f4edf2aa3f7172))
* streamline food logging and diary navigation ([#21](https://github.com/yakov103/mivu/issues/21)) ([fc2d37d](https://github.com/yakov103/mivu/commit/fc2d37dfe71ec18271ad1bc6f8335fba1076a24c))
* use Pip portrait for app icon ([#28](https://github.com/yakov103/mivu/issues/28)) ([66e9f6c](https://github.com/yakov103/mivu/commit/66e9f6c26502c94aaa48757e1684cc90f4fdf891))
* **widget:** calories, Log Food and Coach widgets ([#35](https://github.com/yakov103/mivu/issues/35)) ([0c06d06](https://github.com/yakov103/mivu/commit/0c06d0626cf5abe4e24131876abb9041eecaa5bf))


### Bug Fixes

* App Review readiness and connect ChatGPT from anywhere ([#29](https://github.com/yakov103/mivu/issues/29)) ([17a3dd6](https://github.com/yakov103/mivu/commit/17a3dd6003b782477ccb700eb1cbe561cfb2e651))
* **ci:** run hosted checks only on Linux ([536aea0](https://github.com/yakov103/mivu/commit/536aea00512613980b017f188d4c99966e3d5963))
* **coach:** let the model correct rejected tool calls and retry failed replies once ([#66](https://github.com/yakov103/mivu/issues/66)) ([75173cc](https://github.com/yakov103/mivu/commit/75173ccbc7564d2dafb8163357f1c3fd8f67e540))
* **day:** auto-closed days with skip, drop pending, Snap It shortcut ([#58](https://github.com/yakov103/mivu/issues/58)) ([e4f4b3a](https://github.com/yakov103/mivu/commit/e4f4b3a119df09944bb836f3824bf6da6f4ed599))
* **diary:** add known nutrient values when some foods lack them ([#64](https://github.com/yakov103/mivu/issues/64)) ([2ed34e4](https://github.com/yakov103/mivu/commit/2ed34e43eb599dfe0c58b5646ee5113b2c88b927))
* **live-activity:** mark the calorie figure when a food lacks calories ([#65](https://github.com/yakov103/mivu/issues/65)) ([41b8a65](https://github.com/yakov103/mivu/commit/41b8a6554b88ace85b93c5671b833cf585f8a067))
* **live-activity:** match the Lock Screen card to its text colors ([#62](https://github.com/yakov103/mivu/issues/62)) ([2776ea0](https://github.com/yakov103/mivu/commit/2776ea002e6bd70d45689087ea7d87c607058ded))
* **onboarding:** keep Next and Done above the number pad ([#56](https://github.com/yakov103/mivu/issues/56)) ([665264c](https://github.com/yakov103/mivu/commit/665264c9d57e69f991648856af023a19a8f20521))
* **pip:** draw the front and left head views ([#24](https://github.com/yakov103/mivu/issues/24)) ([6e93921](https://github.com/yakov103/mivu/commit/6e939212bcaebbe8a25e0733dd0928fafdbb898b))
* reuse recent portions and estimate photo servings ([#14](https://github.com/yakov103/mivu/issues/14)) ([eddf0e5](https://github.com/yakov103/mivu/commit/eddf0e5764346d835e2bc5381884b9b47945a736))
* **settings:** point the privacy policy link at mivuapp.com ([cd56d8a](https://github.com/yakov103/mivu/commit/cd56d8aadab39ac280ff59242fb2069bd1dc8bdd))
* **ui-tests:** bound test time and make the full UI suite pass ([#47](https://github.com/yakov103/mivu/issues/47)) ([b41c7aa](https://github.com/yakov103/mivu/commit/b41c7aa8326089dd3f3804834a769fafc4013b34))
* **ui:** repair pre-existing UI test failures ([#40](https://github.com/yakov103/mivu/issues/40)) ([1d16ec8](https://github.com/yakov103/mivu/commit/1d16ec87ff0dbaacb289f41adf3635cc9ae3e473))
