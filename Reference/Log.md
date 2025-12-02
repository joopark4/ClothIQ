📊 [AppContainerView] 기존 교정 프로파일 발견
✅ [AppContainerView] 기존 프로파일 활성화: 반바지 기준 (2025-11-06)
Unable to simultaneously satisfy constraints.
	Probably at least one of the constraints in the following list is one you don't want. 
	Try this: 
		(1) look at each constraint and try to figure out which you don't expect; 
		(2) find the code that added the unwanted constraint or constraints and fix it. 
	(Note: If you're seeing NSAutoresizingMaskLayoutConstraints that you don't understand, refer to the documentation for the UIView property translatesAutoresizingMaskIntoConstraints) 
(
    "<NSAutoresizingMaskLayoutConstraint:0x121f10b90 h=--& v=--& _TtCC5UIKit19NavigationButtonBar15ItemWrapperView:0x121c3b9c0.width == 0   (active)>",
    "<NSLayoutConstraint:0x121e27a70 _TtCC5UIKit19NavigationButtonBar15ItemWrapperView:0x121c3b9c0.leading == _UIButtonBarButton:0x121c76800.leading   (active)>",
    "<NSLayoutConstraint:0x121e27ac0 H:[_UIButtonBarButton:0x121c76800]-(0)-|   (active, names: '|':_TtCC5UIKit19NavigationButtonBar15ItemWrapperView:0x121c3b9c0 )>",
    "<NSLayoutConstraint:0x121e27890 'IB_Leading_Leading' H:|-(2)-[_UIModernBarButton:0x10c9c5f80]   (active, names: '|':_UIButtonBarButton:0x121c76800 )>",
    "<NSLayoutConstraint:0x121e278e0 'IB_Trailing_Trailing' H:[_UIModernBarButton:0x10c9c5f80]-(2)-|   (active, names: '|':_UIButtonBarButton:0x121c76800 )>"
)

Will attempt to recover by breaking constraint 
<NSLayoutConstraint:0x121e278e0 'IB_Trailing_Trailing' H:[_UIModernBarButton:0x10c9c5f80]-(2)-|   (active, names: '|':_UIButtonBarButton:0x121c76800 )>

Make a symbolic breakpoint at UIViewAlertForUnsatisfiableConstraints to catch this in the debugger.
The methods in the UIConstraintBasedLayoutDebugging category on UIView listed in <UIKitCore/UIView.h> may also be helpful.
UINavigationBar has changed horizontal size class without updating search bar to new placement. Fixing, but delegate searchBarPlacement callbacks have been skipped. navigationBar = <SwiftUI.UIKitNavigationBar: 0x1047d5200; baseClass = UINavigationBar; frame = (0 10; 400 50); opaque = NO; autoresize = W; gestureRecognizers = <NSArray: 0x10ca15d40>; layer = <CALayer: 0x10ca14e40>> delegate=0x1047d0e00
Unable to simultaneously satisfy constraints.
	Probably at least one of the constraints in the following list is one you don't want. 
	Try this: 
		(1) look at each constraint and try to figure out which you don't expect; 
		(2) find the code that added the unwanted constraint or constraints and fix it. 
	(Note: If you're seeing NSAutoresizingMaskLayoutConstraints that you don't understand, refer to the documentation for the UIView property translatesAutoresizingMaskIntoConstraints) 
(
    "<NSAutoresizingMaskLayoutConstraint:0x10c9a3d90 h=--& v=--& _TtCC5UIKit19NavigationButtonBar15ItemWrapperView:0x121c38000.width == 0   (active)>",
    "<NSLayoutConstraint:0x121c997c0 _TtCC5UIKit19NavigationButtonBar15ItemWrapperView:0x121c38000.leading == _UIButtonBarButton:0x123b34c80.leading   (active)>",
    "<NSLayoutConstraint:0x121c99720 H:[_UIButtonBarButton:0x123b34c80]-(0)-|   (active, names: '|':_TtCC5UIKit19NavigationButtonBar15ItemWrapperView:0x121c38000 )>",
    "<NSLayoutConstraint:0x121c99450 'IB_Leading_Leading' H:|-(2)-[_UIModernBarButton:0x10c9c6680]   (active, names: '|':_UIButtonBarButton:0x123b34c80 )>",
    "<NSLayoutConstraint:0x121c994a0 'IB_Trailing_Trailing' H:[_UIModernBarButton:0x10c9c6680]-(2)-|   (active, names: '|':_UIButtonBarButton:0x123b34c80 )>"
)

Will attempt to recover by breaking constraint 
<NSLayoutConstraint:0x121c994a0 'IB_Trailing_Trailing' H:[_UIModernBarButton:0x10c9c6680]-(2)-|   (active, names: '|':_UIButtonBarButton:0x123b34c80 )>

Make a symbolic breakpoint at UIViewAlertForUnsatisfiableConstraints to catch this in the debugger.
The methods in the UIConstraintBasedLayoutDebugging category on UIView listed in <UIKitCore/UIView.h> may also be helpful.
{"msg":"#Warning Error reading file", "file":"\/\/private\/var\/Managed Preferences\/mobile\/com.apple.CoreMotion.plist", "error":"Error Domain=NSCocoaErrorDomain Code=257 \"The file “com.apple.CoreMotion.plist” couldn’t be opened because you don’t have permission to view it.\" UserInfo={NSFilePath=\/\/private\/var\/Managed Preferences\/mobile\/com.apple.CoreMotion.plist, NSURL=file:\/\/\/\/private\/var\/Managed%20Preferences\/mobile\/com.apple.CoreMotion.plist, NSUnderlyingError=0x121d60780 {Error Domain=NSPOSIXErrorDomain Code=1 \"Operation not permitted\"}}"}
Could not locate file 'default-binaryarchive.metallib' in bundle.
asset string 'engine:throttleGhosted.rematerial' parse failed: Invalid asset path: Unknown asset type suffix 'engine:throttleGhosted.rematerial'
Video texture allocator is not initialized.
[VideoLightSpillGenerator] [VideoLightSpillMPSCallsPrewarm] Failed to create input texture with MTLPixelFormat MTLPixelFormatBGRA8Unorm_sRGB
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/suFeatheringCreateMergedOcclusionMask.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arKitPassthrough.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arSegmentationComposite.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute0.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute1.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute2.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute3.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute4.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute5.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute6.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute7.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute8.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute9.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute10.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute11.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute12.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute13.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute14.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
Could not resolve material name 'engine:BuiltinRenderGraphResources/AR/arInPlacePostProcessCombinedPermute15.rematerial' in bundle at '/private/var/containers/Bundle/Application/075EB61C-C1A0-4247-94F2-0964C3485947/ClothIQ.app'. Loading via asset path.
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
<0x1045ee6c0> Gesture: System gesture gate timed out.
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:276) - (err=-12784)
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:513) - (err=-12784)
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:276) - (err=-12784)
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:513) - (err=-12784)
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:276) - (err=-12784)
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:513) - (err=-12784)
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
🎯 [ViewModel] 포인트 샘플링 시작 at (276.5625, 399.00439238653)
🎯 [Sampling] 샘플링 시작: CDEC9D17-459D-488B-A767-D2F9DBE4BAFC
  - 화면 좌표: (276.5625, 399.00439238653)
  - 목표 샘플 수: 15
  - 샘플링 ID: CDEC9D17-459D-488B-A767-D2F9DBE4BAFC
  - 목표 샘플 수: 15
📊 [Sampling] 샘플 수집: 1/15 (6%)
📊 [ViewModel] 샘플 수집 진행: 6% (1/15)
📊 [Sampling] 샘플 수집: 2/15 (13%)
📊 [ViewModel] 샘플 수집 진행: 13% (2/15)
📊 [Sampling] 샘플 수집: 3/15 (20%)
📊 [ViewModel] 샘플 수집 진행: 20% (3/15)
📊 [Sampling] 샘플 수집: 4/15 (26%)
📊 [ViewModel] 샘플 수집 진행: 26% (4/15)
📊 [Sampling] 샘플 수집: 5/15 (33%)
📊 [ViewModel] 샘플 수집 진행: 33% (5/15)
📊 [Sampling] 샘플 수집: 6/15 (40%)
📊 [ViewModel] 샘플 수집 진행: 40% (6/15)
📊 [Sampling] 샘플 수집: 7/15 (46%)
📊 [ViewModel] 샘플 수집 진행: 46% (7/15)
📊 [Sampling] 샘플 수집: 8/15 (53%)
📊 [ViewModel] 샘플 수집 진행: 53% (8/15)
📊 [Sampling] 샘플 수집: 9/15 (60%)
📊 [ViewModel] 샘플 수집 진행: 60% (9/15)
📊 [Sampling] 샘플 수집: 10/15 (66%)
📊 [ViewModel] 샘플 수집 진행: 66% (10/15)
📊 [Sampling] 샘플 수집: 11/15 (73%)
📊 [ViewModel] 샘플 수집 진행: 73% (11/15)
📊 [Sampling] 샘플 수집: 12/15 (80%)
📊 [ViewModel] 샘플 수집 진행: 80% (12/15)
📊 [Sampling] 샘플 수집: 13/15 (86%)
📊 [ViewModel] 샘플 수집 진행: 86% (13/15)
📊 [Sampling] 샘플 수집: 14/15 (93%)
📊 [ViewModel] 샘플 수집 진행: 93% (14/15)
📊 [Sampling] 샘플 수집: 15/15 (100%)
✅ [ViewModel] 샘플링 완료, 포인트 정제 중...
✅ [Sampling] 샘플링 완료!
  - 최종 포인트: SIMD3<Float>(-0.02463507, -0.88377875, -0.49377024)
  - 평균 신뢰도: 0.5
  - 표준편차: 0.15591387cm
✅ [ViewModel] 정제된 포인트 추가 완료!
🎯 [ViewModel] 포인트 샘플링 시작 at (1218.75, 384.7730600292826)
🎯 [Sampling] 샘플링 시작: CEBF3889-15F5-4B26-8484-48C36CF4966E
  - 화면 좌표: (1218.75, 384.7730600292826)
  - 목표 샘플 수: 15
  - 샘플링 ID: CEBF3889-15F5-4B26-8484-48C36CF4966E
  - 목표 샘플 수: 15
📊 [Sampling] 샘플 수집: 1/15 (6%)
📊 [ViewModel] 샘플 수집 진행: 6% (1/15)
📊 [Sampling] 샘플 수집: 2/15 (13%)
📊 [ViewModel] 샘플 수집 진행: 13% (2/15)
📊 [Sampling] 샘플 수집: 3/15 (20%)
📊 [ViewModel] 샘플 수집 진행: 20% (3/15)
📊 [Sampling] 샘플 수집: 4/15 (26%)
📊 [ViewModel] 샘플 수집 진행: 26% (4/15)
📊 [Sampling] 샘플 수집: 5/15 (33%)
📊 [ViewModel] 샘플 수집 진행: 33% (5/15)
📊 [Sampling] 샘플 수집: 6/15 (40%)
📊 [ViewModel] 샘플 수집 진행: 40% (6/15)
📊 [Sampling] 샘플 수집: 7/15 (46%)
📊 [ViewModel] 샘플 수집 진행: 46% (7/15)
📊 [Sampling] 샘플 수집: 8/15 (53%)
📊 [ViewModel] 샘플 수집 진행: 53% (8/15)
📊 [Sampling] 샘플 수집: 9/15 (60%)
📊 [ViewModel] 샘플 수집 진행: 60% (9/15)
📊 [Sampling] 샘플 수집: 10/15 (66%)
📊 [ViewModel] 샘플 수집 진행: 66% (10/15)
📊 [Sampling] 샘플 수집: 11/15 (73%)
📊 [ViewModel] 샘플 수집 진행: 73% (11/15)
📊 [Sampling] 샘플 수집: 12/15 (80%)
📊 [ViewModel] 샘플 수집 진행: 80% (12/15)
📊 [Sampling] 샘플 수집: 13/15 (86%)
📊 [ViewModel] 샘플 수집 진행: 86% (13/15)
📊 [Sampling] 샘플 수집: 14/15 (93%)
📊 [ViewModel] 샘플 수집 진행: 93% (14/15)
📊 [Sampling] 샘플 수집: 15/15 (100%)
✅ [ViewModel] 샘플링 완료, 포인트 정제 중...
✅ [Sampling] 샘플링 완료!
  - 최종 포인트: SIMD3<Float>(-0.23366064, -0.86279845, 0.021993196)
  - 평균 신뢰도: 0.5
  - 표준편차: 0.1465043cm
✅ [ViewModel] 정제된 포인트 추가 완료!
ARSession <0x12548f200>: The delegate of ARSession is retaining 11 ARFrames. The camera will stop delivering camera images if the delegate keeps holding on to too many ARFrames. This could be a threading or memory management issue in the delegate and should be fixed.
ARSession <0x12548f200>: The delegate of ARSession is retaining 11 ARFrames. The camera will stop delivering camera images if the delegate keeps holding on to too many ARFrames. This could be a threading or memory management issue in the delegate and should be fixed.
ARSession <0x12548f200>: The delegate of ARSession is retaining 11 ARFrames. The camera will stop delivering camera images if the delegate keeps holding on to too many ARFrames. This could be a threading or memory management issue in the delegate and should be fixed.
ARSession <0x12548f200>: The delegate of ARSession is retaining 11 ARFrames. The camera will stop delivering camera images if the delegate keeps holding on to too many ARFrames. This could be a threading or memory management issue in the delegate and should be fixed.
ARSession <0x12548f200>: The delegate of ARSession is retaining 11 ARFrames. The camera will stop delivering camera images if the delegate keeps holding on to too many ARFrames. This could be a threading or memory management issue in the delegate and should be fixed.
📏 [AR Calibration] 교정 계수 적용
  - 측정 타입: 허리둘레
  - 의류 타입: 반바지
  - 원본 값: 47.19cm
  - 교정 후: 37.63cm
  - 보정: -9.56cm (-20.3%)
ARSession <0x12548f200>: The delegate of ARSession is retaining 11 ARFrames. The camera will stop delivering camera images if the delegate keeps holding on to too many ARFrames. This could be a threading or memory management issue in the delegate and should be fixed.