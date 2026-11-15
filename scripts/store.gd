extends Node
## 內購（蘋果手機版）：包住 ios-in-app-purchase 外掛，只賣一樣東西「免廣告」。
## 訊號：
##   owned_changed()          確認玩家已經擁有免廣告（剛買、恢復購買、或開機時查到）
##   purchase_finished(ok, cancelled)   按下購買之後的結果
##   restore_finished(found)  按下恢復購買之後的結果
##   price_ready()            拿到商店顯示的價格
## 其他平台沒有商店，available() 是 false。

signal owned_changed
signal purchase_finished(ok: bool, cancelled: bool)
signal restore_finished(found: bool)
signal price_ready

## 要跟 App Store Connect 建立的內購商品編號一模一樣（非消耗性商品）
const PRODUCT_ID := "com.lucastudio.petlineup.noads"

var owned := false
var price := ""                   # 商店顯示的價格文字（含幣別），還沒拿到是空字串
var busy := false                 # 正在購買或恢復中
var _plugin: Object
var _restoring := false


static func available() -> bool:
	return Engine.has_singleton("IOSInAppPurchase")


func start() -> void:
	if not available() or _plugin != null:
		return
	_plugin = Engine.get_singleton("IOSInAppPurchase")
	_plugin.response.connect(_on_response)
	_plugin.request("startUpdateTask", {})
	_plugin.request("proceedUnfinishedTransactions", {})
	_request_products()
	_plugin.request("transactionCurrentEntitlements", {})


func _request_products() -> void:
	_plugin.request("products", {"productIDs": [PRODUCT_ID]})


func buy() -> void:
	if _plugin == null or busy:
		return
	busy = true
	if _plugin.request("purchase", {"productID": PRODUCT_ID}) != 0:
		busy = false
		purchase_finished.emit(false, false)


func restore() -> void:
	if _plugin == null or busy:
		return
	busy = true
	_restoring = true
	if _plugin.request("appStoreSync", {}) != 0:
		_finish_restore()


func _on_response(response_name: String, data: Dictionary) -> void:
	_handle.call_deferred(response_name, data)


func _handle(response_name: String, data: Dictionary) -> void:
	var result := str(data.get("result", ""))
	match response_name:
		"products":
			if result == "success":
				for p in data.get("products", []):
					if str(p.get("id", "")) == PRODUCT_ID:
						price = str(p.get("displayPrice", ""))
						price_ready.emit()
			elif is_inside_tree():
				get_tree().create_timer(15.0).timeout.connect(_request_products)
		"purchase":
			var mine := str(data.get("productID", PRODUCT_ID)) == PRODUCT_ID
			var revoked := str(data.get("revocationDate", "")) != ""
			var ok := result == "success" and mine and not revoked
			if ok:
				_set_owned()
			if busy and not _restoring:
				busy = false
				purchase_finished.emit(ok, result.to_lower().contains("cancel"))
		"transactionCurrentEntitlements":
			if result == "success":
				for t in data.get("transactions", []):
					if str(t.get("productID", "")) == PRODUCT_ID and str(t.get("revocationDate", "")) == "":
						_set_owned()
			if _restoring:
				_finish_restore()
		"appStoreSync":
			# 跟商店同步完，再查一次目前擁有的項目
			if _restoring and _plugin.request("transactionCurrentEntitlements", {}) != 0:
				_finish_restore()


func _finish_restore() -> void:
	_restoring = false
	busy = false
	restore_finished.emit(owned)


func _set_owned() -> void:
	if owned:
		return
	owned = true
	owned_changed.emit()
