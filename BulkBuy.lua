-- ============================================================= --
-- BULK BUY MOD
-- ============================================================= --
BulkBuy = {};

addModEventListener(BulkBuy);

-- CREATE NEW CONFIGURATION FOR BULK BUY ITEMS
function BulkBuy:vehicleLoad(superFunc, vehicleData, asyncCallbackFunction, asyncCallbackObject, asyncCallbackArguments)
	if vehicleData.typeName == 'pallet' then
		-- create bulk buy configuration when loading
		local item = g_storeManager:getItemByXMLFilename(vehicleData.filename)
		if item ~= nil and item.configurations ~= nil then
			if item.configurations[BulkBuy.configName] == nil then
				local configurationItems = {}
				for i = 1, 10 do
					StoreItemUtil.addConfigurationItem(configurationItems, tostring(i), nil, 0, 0, false)
				end
				item.configurations[BulkBuy.configName] = configurationItems
			end
		end
	end
	return superFunc(self, vehicleData, asyncCallbackFunction, asyncCallbackObject, asyncCallbackArguments)
end
function BulkBuy:vehicleSaveToXMLFile(superFunc, xmlFile, key, usedModNames)
	if self.configurations[BulkBuy.configName] ~= nil then
		-- remove bulk buy configuration before saving
		self.configurations[BulkBuy.configName] = nil
		self.boughtConfigurations[BulkBuy.configName] = nil
	end
	return superFunc(self, xmlFile, key, usedModNames)
end
function BulkBuy.shopConfigScreenSetStoreItem(self, storeItem, vehicle, configBasePrice)
	if storeItem.categoryName == "PALLETS" or storeItem.categoryName == "BIGBAGS" or storeItem.categoryName == "IBCPALLETS" then
		if storeItem.configurations[BulkBuy.configName] == nil then
			-- create bulk buy configuration when created in shop
			configurationItems = {}
			for i = 1, 10 do
				StoreItemUtil.addConfigurationItem(configurationItems, tostring(i), nil, 0, 0, false)
			end
			storeItem.configurations[BulkBuy.configName] = configurationItems
		end
	end
end

-- EDIT PRICE DISPLAY
function BulkBuy.shopConfigScreenSetConfigPrice(self, superFunc, configName, configIndex, priceTextElement, vehicle)
	if configName ~= BulkBuy.configName then
		return superFunc(self, configName, configIndex, priceTextElement, vehicle)
	end
	local price = (configIndex-1)*self.storeItem.price
	priceTextElement:setText("+" .. self.l10n:formatMoney(price) .. "")
	priceTextElement:setVisible(true)
end
function BulkBuy.shopConfigScreenGetConfigurationCostsAndChanges(self, superFunc, storeItem, vehicle)
	local basePrice = 0
	local upgradePrice = 0
	local hasChanges = false

	if vehicle ~= nil then
		for name, id in pairs(self.configurations) do
			if vehicle.configurations[name] ~= id then
				hasChanges = true
				if not ConfigurationUtil.hasBoughtConfiguration(self.vehicle, name, id) then
					local configs = storeItem.configurations[name]
					local price = math.max(configs[id].price - configs[self.vehicle.configurations[name]].price, 0)
					upgradePrice = upgradePrice + price
				end
			end
		end
	elseif storeItem ~= nil then
		hasChanges = true
		basePrice, upgradePrice = self.economyManager:getBuyPrice(storeItem, self.configurations)
		basePrice = basePrice - upgradePrice
		-- increase upgrade price for the multiple required
		if storeItem.categoryName == "PALLETS" or storeItem.categoryName == "BIGBAGS" or storeItem.categoryName == "IBCPALLETS" then
			if self.configurations.purchaseQuantity ~= nil then
				upgradePrice = (self.configurations.purchaseQuantity-1) * basePrice
			end
		end
	end
	return basePrice, upgradePrice, hasChanges
end

-- BUY MULTIPLE ITEMS BEFORE FINAL PURCHASE
function BulkBuy.shopControllerUpdate(self, dt)
	if self.buyVehicleNow == 2 then
		if self.buyItemConfigurations.purchaseQuantity ~= nil then
			BulkBuy.purchaseQuantity = self.buyItemConfigurations.purchaseQuantity
			BulkBuy.numberBought = 0
			BulkBuy.numberFailed = 0
		end
	end
end
function BulkBuy.shopControllerOnVehicleBought(self, leaseVehicle, price)
	if self.buyItemConfigurations.purchaseQuantity ~= nil then
		BulkBuy.numberBought = BulkBuy.numberBought + 1
		--print("number bought = " .. BulkBuy.numberBought)
		if BulkBuy.numberBought < BulkBuy.purchaseQuantity then
			self.client:getServerConnection():sendEvent(BuyVehicleEvent:new(self.buyItemFilename, self.buyItemIsOutsideBuy, self.buyItemConfigurations, self.buyItemIsLeasing, self.playerFarmId))
		end
	end
end

-- EDIT ERROR MESSAGE
function BulkBuy.shopControllerOnVehicleBuyFailed(self, leaseVehicle, errorCode)
	if self.buyItemConfigurations.purchaseQuantity ~= nil then
		BulkBuy.numberFailed = BulkBuy.numberFailed + 1
		--print("number failed = " .. BulkBuy.numberFailed)
		if errorCode == BuyVehicleEvent.STATE_NO_SPACE then
			g_gui:closeAllDialogs()
			local text = g_i18n:getText("bulkBuy_messageNoSpace") .. string.format(": %d/%d", BulkBuy.numberBought, BulkBuy.purchaseQuantity)
			g_gui:showInfoDialog({
				text = text,
				callback = self.onBoughtCallback,
				target = self
			})
		end
	end
end

-- BULK BUY FUNCTIONS
function BulkBuy:loadMap(name)
	--print("Load Mod: 'BULK BUY'")
	BulkBuy.configName = "purchaseQuantity"
	g_configurationManager:addConfigurationType(BulkBuy.configName, g_i18n:getText("configuration_buyableBaleAmount"), nil, nil, nil, nil, ConfigurationUtil.SELECTOR_MULTIOPTION)

	Vehicle.load = Utils.overwrittenFunction(Vehicle.load, BulkBuy.vehicleLoad)
	Vehicle.saveToXMLFile = Utils.overwrittenFunction(Vehicle.saveToXMLFile, BulkBuy.vehicleSaveToXMLFile)
	
	ShopConfigScreen.setStoreItem = Utils.prependedFunction(ShopConfigScreen.setStoreItem, BulkBuy.shopConfigScreenSetStoreItem)
	ShopConfigScreen.setConfigPrice = Utils.overwrittenFunction(ShopConfigScreen.setConfigPrice, BulkBuy.shopConfigScreenSetConfigPrice)
	ShopConfigScreen.getConfigurationCostsAndChanges = Utils.overwrittenFunction(ShopConfigScreen.getConfigurationCostsAndChanges, BulkBuy.shopConfigScreenGetConfigurationCostsAndChanges)
	ShopController.update = Utils.prependedFunction(ShopController.update, BulkBuy.shopControllerUpdate)
	ShopController.onVehicleBought = Utils.appendedFunction(ShopController.onVehicleBought, BulkBuy.shopControllerOnVehicleBought)
	ShopController.onVehicleBuyFailed = Utils.appendedFunction(ShopController.onVehicleBuyFailed, BulkBuy.shopControllerOnVehicleBuyFailed)

	BulkBuy.initialised = false
end

function BulkBuy:deleteMap()
end

function BulkBuy:mouseEvent(posX, posY, isDown, isUp, button)
end

function BulkBuy:keyEvent(unicode, sym, modifier, isDown)
end

function BulkBuy:draw()
end

function BulkBuy:update(dt)
	if not BulkBuy.initialised then
		BulkBuy.initialised = true
	end
end