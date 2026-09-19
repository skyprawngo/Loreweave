# 앱 아이콘

앱 아이콘 원본은 `TextlinkEditor/AppIcon.icon`이다. Icon Composer에서 열어 레이어와 Liquid Glass 속성을 편집한다. Xcode의 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`과 동기화된 소스 폴더를 통해 빌드에 포함된다. 이전 PNG `AppIcon.appiconset`은 제거했다.

TextLinkViewer의 `TextLinkViewer/Assets.xcassets/AppIcon.icon`에서 구름, 책장, 책 표지 원본 이미지와 효과 설정을 가져왔다. 새 `Editor Pen` 그룹은 몸체, 파란 장식, 금속·펜촉의 SVG 레이어로 구성된다. 원본의 3개 이미지 레이어는 그대로 보존하며 완성된 아이콘을 PNG로 합성해 넣지 않는다.

Icon Composer의 Default, Dark, Mono 외관을 확인했다. 앱 배포용 크기와 시스템 외관은 Xcode가 `.icon`에서 생성한다. 형식과 연결 방식은 [Apple Icon Composer 문서](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)를 따른다.
