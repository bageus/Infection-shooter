extends "res://game/infrastructure/platform/public/platform_adapter.gd"
## Yandex Games SDK through JavaScriptBridge. The page loads /sdk.js (head_include of the Web Yandex preset).
## State lives in window variables that are polled, so no JavaScript callback has to outlive this object.


func start() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.ysdkReady = false; if (window.YaGames) { YaGames.init().then(function (sdk) { window.ysdk = sdk; window.ysdkReady = true; }); }")


func request_ad() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.ysdkAd = 'open'; if (window.ysdk) { window.ysdk.adv.showFullscreenAdv({callbacks: {onClose: function () { window.ysdkAd = 'closed'; }, onError: function () { window.ysdkAd = 'failed'; }}}); } else { window.ysdkAd = 'failed'; }")


func poll_ad() -> String:
	if not OS.has_feature("web"):
		return AD_FAILED
	var state := str(JavaScriptBridge.eval("window.ysdkAd || 'failed'"))
	return AD_PENDING if state == "open" else (AD_CLOSED if state == "closed" else AD_FAILED)
