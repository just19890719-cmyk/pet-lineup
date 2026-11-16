extends Node
## 真廣告（蘋果手機版）：包住 Poing Studios 的 AdMob 外掛，遊戲只需要呼叫
##   show_rewarded(給獎勵, 沒看成)  玩家自己按才播的獎勵廣告
##   show_interstitial(播完之後)    兩關之間的過關廣告
## 其他平台（電腦、網頁）沒有廣告服務，available() 會是 false，由 main.gd 改用假廣告或直接放行。

# 廣告單元編號：正式版用 REAL_*（AdMob 後台建立的單元）；開發版永遠用谷歌公開的測試編號，避免自己點到真廣告被停權。
const TEST_REWARDED := "ca-app-pub-3940256099942544/1712485313"
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/4411468910"
const REAL_REWARDED := "ca-app-pub-6023320630940952/2403563715"       # AdMob「求救獎勵」
const REAL_INTERSTITIAL := "ca-app-pub-6023320630940952/9603571897"   # AdMob「過關廣告」

# 【送審前一定要改成 false】TestFlight 測試用：true 時正式版也改用谷歌測試廣告，
# 並在「廣告還沒準備好」對話框多顯示錯誤原因，用來確認廣告接線有沒有通。
const DEBUG_ADS := true

const RETRY_SECONDS := 20.0       # 載入失敗後隔多久再試

var ready_ok := false             # 廣告服務初始化完成
var last_error := ""              # 最近一次載入失敗的原因（測試用）
var rewarded: RewardedAd
var interstitial: InterstitialAd
var rewarded_loading := false
var interstitial_loading := false
var showing := false
var _earned := false
var _on_reward: Callable
var _on_fail: Callable
var _on_done: Callable
var _rewarded_loader: RewardedAdLoader
var _interstitial_loader: InterstitialAdLoader


static func available() -> bool:
	return OS.has_feature("ios")


func _unit(real_id: String, test_id: String) -> String:
	return real_id if (real_id != "" and not DEBUG_ADS and not OS.is_debug_build()) else test_id


## 測試用：目前廣告狀態的一行說明（只在 DEBUG_ADS 顯示給玩家看）
func debug_status() -> String:
	return "init=%s loading=%s err=%s" % [ready_ok, rewarded_loading, last_error if last_error != "" else "none"]


## 遊戲啟動時呼叫一次（已買免廣告就不用呼叫）
func start() -> void:
	if not available() or ready_ok or _rewarded_loader != null:
		return
	_rewarded_loader = RewardedAdLoader.new()
	_interstitial_loader = InterstitialAdLoader.new()
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status: InitializationStatus) -> void:
		_after_init.call_deferred()
	MobileAds.initialize(listener)


func _after_init() -> void:
	ready_ok = true
	_load_rewarded()
	_load_interstitial()


func rewarded_ready() -> bool:
	return rewarded != null and not showing


func interstitial_ready() -> bool:
	return interstitial != null and not showing


func _retry(what: Callable) -> void:
	if is_inside_tree():
		get_tree().create_timer(RETRY_SECONDS).timeout.connect(what)


# ───────── 獎勵廣告 ─────────
func _load_rewarded() -> void:
	if not ready_ok or rewarded != null or rewarded_loading:
		return
	rewarded_loading = true
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded_loaded.call_deferred(ad)
	cb.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		last_error = "rewarded %s %s" % [str(error.code), str(error.message)]
		_rewarded_failed.call_deferred()
	_rewarded_loader.load(_unit(REAL_REWARDED, TEST_REWARDED), AdRequest.new(), cb)


func _rewarded_loaded(ad: RewardedAd) -> void:
	rewarded_loading = false
	last_error = ""
	rewarded = ad
	var cb := FullScreenContentCallback.new()
	cb.on_ad_dismissed_full_screen_content = func() -> void:
		_rewarded_closed.call_deferred()
	cb.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void:
		_rewarded_closed.call_deferred()
	rewarded.full_screen_content_callback = cb


func _rewarded_failed() -> void:
	rewarded_loading = false
	_retry(_load_rewarded)


## 播獎勵廣告。看完才呼叫 on_reward；沒準備好、沒看完或播不出來就呼叫 on_fail(是否因為還沒準備好)
func show_rewarded(on_reward: Callable, on_fail: Callable) -> void:
	if not rewarded_ready():
		_load_rewarded()
		on_fail.call(true)
		return
	showing = true
	_earned = false
	_on_reward = on_reward
	_on_fail = on_fail
	_mute(true)
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem) -> void:
		_earned = true
	rewarded.show(listener)


func _rewarded_closed() -> void:
	if rewarded != null:
		rewarded.destroy()
		rewarded = null
	_mute(false)
	showing = false
	_load_rewarded()
	if _earned:
		_on_reward.call()
	else:
		_on_fail.call(false)


# ───────── 過關廣告 ─────────
func _load_interstitial() -> void:
	if not ready_ok or interstitial != null or interstitial_loading:
		return
	interstitial_loading = true
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_interstitial_loaded.call_deferred(ad)
	cb.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		last_error = "interstitial %s %s" % [str(error.code), str(error.message)]
		_interstitial_failed.call_deferred()
	_interstitial_loader.load(_unit(REAL_INTERSTITIAL, TEST_INTERSTITIAL), AdRequest.new(), cb)


func _interstitial_loaded(ad: InterstitialAd) -> void:
	interstitial_loading = false
	interstitial = ad
	var cb := FullScreenContentCallback.new()
	cb.on_ad_dismissed_full_screen_content = func() -> void:
		_interstitial_closed.call_deferred()
	cb.on_ad_failed_to_show_full_screen_content = func(_error: AdError) -> void:
		_interstitial_closed.call_deferred()
	interstitial.full_screen_content_callback = cb


func _interstitial_failed() -> void:
	interstitial_loading = false
	_retry(_load_interstitial)


## 播過關廣告，播完（或沒有廣告可播）就呼叫 on_done。回傳有沒有真的播
func show_interstitial(on_done: Callable) -> bool:
	if not interstitial_ready():
		_load_interstitial()
		on_done.call()
		return false
	showing = true
	_on_done = on_done
	_mute(true)
	interstitial.show()
	return true


func _interstitial_closed() -> void:
	if interstitial != null:
		interstitial.destroy()
		interstitial = null
	_mute(false)
	showing = false
	_load_interstitial()
	_on_done.call()


## 播廣告時把遊戲的聲音關掉，播完恢復
func _mute(on: bool) -> void:
	AudioServer.set_bus_mute(0, on)
