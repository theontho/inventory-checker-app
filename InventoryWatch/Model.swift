//
//  Model.swift
//  InventoryWatch
//
//  Created by Worth Baker on 11/8/21.
//

import Foundation

struct JsonStore: Codable, Equatable {
    var storeName: String
    var storeNumber: String
    var city: String
}

struct Store: Equatable {
    let storeName: String
    let storeNumber: String
    let city: String
    let state: String?
    
    var locationDescription: String {
        return [city, state].compactMap { $0 }.joined(separator: ", ")
    }
    
    let partsAvailability: [PartAvailability]
}

struct PartAvailability: Equatable, Hashable {
    enum PickupAvailability: String {
        case available, unavailable, ineligible
    }
    
    let partNumber: String
    let storePickupProductTitle: String
    let availability: PickupAvailability
}

extension PartAvailability: Identifiable {
    var id: String {
        partNumber
    }
}

enum ProductType: String, Codable {
    case MacBookPro
    case MacStudio
    case StudioDisplay
    case iPadWifi
    case iPadCellular
    case iPhoneRegular13
    case iPhoneMini13
    case iPhonePro13
    case iPhoneProMax13
    
    var presentableName: String {
        switch self {
        case .MacBookPro:
            return "MacBook Pro"
        case .MacStudio:
            return "Mac Studio"
        case .StudioDisplay:
            return "Studio Display"
        case .iPadWifi:
            return "iPad mini (Wifi)"
        case .iPadCellular:
            return "iPad mini (Cellular)"
        case .iPhoneRegular13:
            return "iPhone 13"
        case .iPhoneMini13:
            return "iPhone 13 mini"
        case .iPhonePro13:
            return "iPhone 13 Pro"
        case .iPhoneProMax13:
            return "iPhone 13 Pro Max"
        }
    }
}

struct AllPhoneModels {
    struct PhoneModel {
        let sku: String
        let productName: String
    }
    
    var proMax13: [PhoneModel]
    var pro13: [PhoneModel]
    var mini13: [PhoneModel]
    var regular13: [PhoneModel]
    
    func toSkuData(_ keypath: KeyPath<AllPhoneModels, [AllPhoneModels.PhoneModel]>) -> SKUData {
        let models = self[keyPath: keypath]
        
        let lookup: [String: String] = models.reduce(into: [:]) { acc, next in
            acc[next.sku] = next.productName
        }
        
        return SKUData(orderedSKUs: models.map { $0.sku }, lookup: lookup)
    }
}

struct GithubTag: Codable {
    let name: String
}

final class Model: ObservableObject {
    enum ModelError: Swift.Error {
        case couldNotGenerateURL
        case invalidStoreResponse
        case failedToParseJSON
        case unexpectedJSONStructure
        case noStoresFound
        case invalidLocalModelStore
        case generic(Error?)
        
        var errorMessage: String {
            switch self {
            case .couldNotGenerateURL:
                return "InventoryWatch failed to construct a valid URL for your search."
            case .invalidStoreResponse, .failedToParseJSON, .unexpectedJSONStructure, .noStoresFound:
                return "Unexpected inventory data found. Please confirm that the selected store is valid for the selected country."
            case .invalidLocalModelStore:
                return "InventoryWatch has invalid or currupted local data. Please contact the developer (@worthbak)."
            case .generic(let optional):
                return "A network error occurred. Details: \(optional?.localizedDescription ?? "unknown")"
            }
        }
    }
    
    @Published var availableParts: [(Store, [PartAvailability])] = []
    @Published var isLoading = false
    @Published var hasLatestVersion = true
    @Published var errorState: ModelError?
    
    lazy private(set) var allStores: [JsonStore] = {
        let location = "Stores"
        let fileType = "json"
        if let path = Bundle.main.path(forResource: location, ofType: fileType) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let decoder = JSONDecoder()
                
                if let jsonStores = try? decoder.decode([JsonStore].self, from: data) {
                    return jsonStores
                } else {
                    return []
                }
                
            } catch {
                print(error)
                return []
            }
        } else {
            return []
        }
    }()
    
    lazy private var iPhoneModels: [Country: AllPhoneModels] = {
        let phoneModelsJson = loadIPhoneModels()
        var rv = [Country: AllPhoneModels]()
        
        for (countryCode, phones) in phoneModelsJson {
            guard let country = Countries[countryCode.uppercased()] else {
                self.updateErrorState(to: ModelError.invalidLocalModelStore)
                return [:]
            }
            
            let modelsData = [
                (phones["proMax13"], \AllPhoneModels.proMax13),
                (phones["pro13"], \AllPhoneModels.pro13),
                (phones["mini13"], \AllPhoneModels.mini13),
                (phones["regular13"], \AllPhoneModels.regular13)
            ]
            
            var phoneModels = AllPhoneModels(proMax13: [], pro13: [], mini13: [], regular13: [])
            for (models, keyPath) in modelsData {
                guard let models = models else {
                    continue
                }
                
                let parsed: [AllPhoneModels.PhoneModel] = models.map { modelData in
                    return AllPhoneModels.PhoneModel(sku: modelData.key, productName: modelData.value)
                }
                
                phoneModels[keyPath: keyPath] = parsed
            }
            
            rv[country] = phoneModels
        }
        
        return rv
    }()
    
    func phoneModels(for country: Country) -> AllPhoneModels {
        guard let models = iPhoneModels[country] else {
            self.updateErrorState(to: ModelError.invalidLocalModelStore)
            return AllPhoneModels(proMax13: [], pro13: [], mini13: [], regular13: [])
        }
        
        return models
    }
    
                                    // country: type:    model:   description
    private func loadIPhoneModels() -> [String: [String: [String: String]]] {
        let location = "iPhoneModels-intl"
        let fileType = "json"
        if let path = Bundle.main.path(forResource: location, ofType: fileType) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let decoder = JSONDecoder()
                
                if let jsonStores = try? decoder.decode([String: [String: [String: String]]].self, from: data) {
                    return jsonStores
                } else {
                    return [:]
                }
                
            } catch {
                print(error)
                return [:]
            }
        } else {
            return [:]
        }
    }
    
    private var preferredStoreInfoBacking: JsonStore?
    @Published var preferredStoreInfo: String? = nil
    
    private var preferredCountry: String {
        return UserDefaults.standard.string(forKey: "preferredCountry") ?? "US"
    }
    
    private var preferredProductType: String {
        return UserDefaults.standard.string(forKey: "preferredProductType") ?? "MacBookPro"
    }
    
    private var countryPathElement: String {
        let country = preferredCountry
        if country == "US" {
            return "/"
        } else if country == "CN" {
            return ".cn/"
        } else {
            return "/" + country + "/"
        }
    }
    
    private var preferredStoreNumber: String {
        return UserDefaults.standard.string(forKey: "preferredStoreNumber") ?? "R032"
    }
    
    private var preferredSKUs: Set<String> {
        guard let defaults = UserDefaults.standard.string(forKey: "preferredSKUs") else {
            return []
        }
        
        return defaults.components(separatedBy: ",").reduce(into: Set<String>()) { partialResult, next in
            partialResult.insert(next)
        }
    }
    
    var skuData: SKUData {
        let productType = ProductType(rawValue: preferredProductType) ?? .MacBookPro
        let country = Countries[preferredCountry] ?? USData
        
        switch productType {
        case .MacBookPro:
            let country = Countries[preferredCountry] ?? USData
            return MBPDataForCountry(country)
        case .MacStudio:
            let country = Countries[preferredCountry] ?? USData
            return MacStudioDataForCountry(country)
        case .StudioDisplay:
            let country = Countries[preferredCountry] ?? USData
            return StudioDisplayForCountry(country)
        case .iPadWifi:
            let country = Countries[preferredCountry] ?? USData
            return iPadDataForCountry(country, isWifi: true)
        case .iPadCellular:
            let country = Countries[preferredCountry] ?? USData
            return iPadDataForCountry(country, isWifi: false)
        case .iPhoneRegular13:
            return phoneModels(for: country).toSkuData(\.regular13)
        case .iPhoneMini13:
            return phoneModels(for: country).toSkuData(\.mini13)
        case .iPhonePro13:
            return phoneModels(for: country).toSkuData(\.pro13)
        case .iPhoneProMax13:
            return phoneModels(for: country).toSkuData(\.proMax13)
        }
    }
    
    private var updateTimer: Timer?
    
    private let isTest: Bool
    
    init(isTest: Bool = false) {
        self.isTest = isTest
    }
    
    func clearCurrentAvailableParts() {
        availableParts = []
    }
    
    func updateErrorState(to error: Error?, deactivateLoadingState: Bool = true) {
        DispatchQueue.main.async {
            if deactivateLoadingState {
                self.isLoading = false
            }
            
            print(error?.localizedDescription ?? "errorState: nil")
            guard let error = error else {
                self.errorState = nil
                return
            }
            
            if let modelError = error as? ModelError {
                self.errorState = modelError
            } else {
                self.errorState = ModelError.generic(error)
            }
        }
    }
    
    func fetchLatestGithubRelease() {
        guard
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let url = URL(string: "https://api.github.com/repos/worthbak/inventory-checker-app/tags")
        else {
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, let parsed = try? JSONDecoder().decode([GithubTag].self, from: data) else {
                return
            }
            
            let processedData = parsed
                .filter { !$0.name.hasPrefix("v") }
                .sorted { first, second in
                    switch compareNumeric(first.name, second.name) {
                    case .orderedAscending, .orderedSame:
                        return false
                    case .orderedDescending:
                        return true
                    }
                }
            
            guard let latestReleaseVersion = processedData.first?.name else {
                return
            }
            
            let isLatestRelease: Bool
            switch compareNumeric(latestReleaseVersion, appVersion) {
            case .orderedAscending, .orderedSame:
                isLatestRelease = true
            case .orderedDescending:
                isLatestRelease = false
            }
            
            DispatchQueue.main.async {
                print("Has \(isLatestRelease ? "latest" : "outdated") version: local: \(appVersion), remote: \(latestReleaseVersion)")
                self.hasLatestVersion = isLatestRelease
            }
        }.resume()
    }
    
    func fetchLatestInventory() {
        guard !isTest else {
            return
        }
        
        syncPreferredStore()
        isLoading = true
        
        self.fetchLatestGithubRelease()
        self.updateErrorState(to: .none, deactivateLoadingState: false)
        
        let filterForPreferredModels = UserDefaults.standard.bool(forKey: "showResultsOnlyForPreferredModels")
        let filterModels = filterForPreferredModels ? preferredSKUs : nil
        
        let urlRoot = "https://www.apple.com\(countryPathElement.lowercased())shop/fulfillment-messages?"
        let query = generateQueryString()
        
        guard let url = URL(string: urlRoot + query) else {
            updateErrorState(to: ModelError.couldNotGenerateURL)
            return
        }
        
        print("query url: \(url)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            do {
                try self.parseStoreResponse(data, filterForModels: filterModels)
            } catch {
                self.updateErrorState(to: error)
            }
        }.resume()
        
        var updateInterval = UserDefaults.standard.integer(forKey: "preferredUpdateInterval")
        if UserDefaults.standard.object(forKey: "preferredUpdateInterval") == nil {
            updateInterval = 1
            UserDefaults.standard.set(updateInterval, forKey: "preferredUpdateInterval")
        }
        
        if let existingTimer = updateTimer, existingTimer.timeInterval != Double(updateInterval * 60) {
            existingTimer.invalidate()
            updateTimer = nil
        }
        
        if updateTimer == nil {
            let interval = Double(updateInterval * 60)
            updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { _ in
                self.fetchLatestInventory()
            })
        }
        
            AnalyticsData.updateAnalyticsData()
    }
    
    private func parseStoreResponse(_ responseData: Data?, filterForModels: Set<String>?) throws {
        guard let responseData = responseData else {
            throw ModelError.invalidStoreResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: responseData, options: []) as? [String : Any] else {
            throw ModelError.failedToParseJSON
        }
        
        guard
            let body = json["body"] as? [String: Any],
                let content = body["content"] as? [String: Any],
                let pickupMessage = content["pickupMessage"] as? [String: Any]
        else {
            throw ModelError.unexpectedJSONStructure
        }
        
        guard let storeList = pickupMessage["stores"] as? [[String: Any]] else {
            throw ModelError.noStoresFound
        }
        
        let collectedStores: [Store] = storeList.compactMap { storeJSON in
            guard let name = storeJSON["storeName"] as? String else { return nil }
            guard let number = storeJSON["storeNumber"] as? String else { return nil }
            guard let city = storeJSON["city"] as? String else { return nil }
            let state = storeJSON["state"] as? String
            
            guard let partsAvailability = storeJSON["partsAvailability"] as? [String: [String: Any]] else { return nil }
            let parsedParts: [PartAvailability] = partsAvailability.values.compactMap { part in
                guard let partNumber = part["partNumber"] as? String else { return nil }
                guard let storePickupProductTitle = part["storePickupProductTitle"] as? String else { return nil }
                guard
                    let availabilityString = part["pickupDisplay"] as? String,
                        let availability = PartAvailability.PickupAvailability(rawValue: availabilityString)
                else {
                    return nil
                }
                
                return PartAvailability(partNumber: partNumber, storePickupProductTitle: storePickupProductTitle, availability: availability)
            }
            
            return Store(storeName: name, storeNumber: number, city: city, state: state, partsAvailability: parsedParts)
        }
        
        try self.parseAvailableModels(from: collectedStores, filterForModels: filterForModels)
    }
    
    private func parseAvailableModels(from stores: [Store], filterForModels: Set<String>?) throws {
        let allAvailableModels: [(Store, [PartAvailability])] = stores.compactMap { store in
            let rv: [PartAvailability] = store.partsAvailability.filter { part in
                switch part.availability {
                case .available:
                    if let filter = filterForModels, filter.contains(part.partNumber) == false {
                        return false
                    }
                    
                    return true
                case .unavailable, .ineligible:
                    return false
                }
            }
            
            if rv.isEmpty {
                return nil
            } else {
                return (store, rv)
            }
        }
        
        DispatchQueue.main.async {
            self.availableParts = allAvailableModels
            self.isLoading = false
            
            let df = DateFormatter()
            df.dateFormat = "MMM d, h:mm a"
            let str = df.string(from: Date())
            UserDefaults.standard.setValue(str, forKey: "lastUpdateDate")
            
            var hasPreferredModel = false
            let preferredModels = self.preferredSKUs
            for model in allAvailableModels {
                for submodel in model.1 {
                    if hasPreferredModel == false && preferredModels.contains(submodel.partNumber) {
                        hasPreferredModel = true
                        break
                    }
                    
                    if hasPreferredModel == false, let customSku = UserDefaults.standard.string(forKey: "customSku"), submodel.partNumber == customSku {
                        hasPreferredModel = true
                        break
                    }
                }
            }
            
            if !self.isTest {
                if UserDefaults.standard.bool(forKey: "notifyOnlyForPreferredModels") && !hasPreferredModel {
                    return
                }
                
                let message = self.generateNotificationText(from: allAvailableModels)
                NotificationManager.shared.sendNotification(title: hasPreferredModel ? "Preferred Model Found!" : "Apple Store Invetory", body: message)
            }
        }
    }
    
    private func generateNotificationText(from data: [(Store, [PartAvailability])]) -> String {
        guard data.isEmpty == false else {
            return "No Inventory Found"
        }
        
        var collector: [String: Int] = [:]
        for (_, parts) in data {
            for part in parts {
                collector[part.partNumber, default: 0] += 1
            }
        }
        
        let combined: [String] = collector.reduce(into: []) { partialResult, next in
            let (key, value) = next
            let name = skuData.productName(forSKU: key) ?? key
            partialResult.append("\(name): \(value) found")
        }
        
        return combined.joined(separator: ", ")
    }
    
    private func generateQueryString() -> String {
        var allSkus = skuData.orderedSKUs
        if let customSku = UserDefaults.standard.string(forKey: "customSku") {
            allSkus.append(customSku)
        }
        
        var queryItems: [String] = allSkus
            .enumerated()
            .compactMap { next in
                guard next.element.isEmpty == false else {
                    return nil
                }
                
                let count = next.offset
                let sku = next.element
                return "parts.\(count)=\(sku)"
            }
        
        queryItems.append("searchNearby=true")
        queryItems.append("store=\(preferredStoreNumber)")
        
        return queryItems.joined(separator: "&")
    }
    
    func productName(forSKU sku: String) -> String {
        if let name = skuData.productName(forSKU: sku){
            return name
        } else if let custom = UserDefaults.standard.string(forKey: "customSku"), custom == sku {
            if let nickname = UserDefaults.standard.string(forKey: "customSkuNickname"), nickname.isEmpty == false {
                return "\(nickname) (custom SKU)"
            } else {
                return "\(sku) (custom SKU)"
            }
        } else {
            return sku
        }
    }
    
    func syncPreferredStore() {
        if preferredStoreInfoBacking == nil || (preferredStoreInfoBacking != nil && preferredStoreInfoBacking!.storeNumber != preferredStoreNumber) {
            preferredStoreInfoBacking = allStores.first(where: { $0.storeNumber == preferredStoreNumber })
            preferredStoreInfo = preferredStoreInfoBacking?.storeName
        }
    }
}

extension Model {
    static var testData: Model {
        let model = Model(isTest: true)
        
        let testParts: [PartAvailability] = [
            PartAvailability(partNumber: "MKGT3LL/A", storePickupProductTitle: "", availability: .available),
            PartAvailability(partNumber: "MKGQ3LL/A", storePickupProductTitle: "", availability: .available),
            PartAvailability(partNumber: "MMQX3LL/A", storePickupProductTitle: "", availability: .available),
        ]
        
        let testStores: [Store] = [
            Store(storeName: "Twenty Ninth St", storeNumber: "R452", city: "Boulder", state: "CO", partsAvailability: testParts),
            Store(storeName: "Flatirons Crossing", storeNumber: "R462", city: "Louisville", state: "CO", partsAvailability: testParts),
            Store(storeName: "Cherry Creek", storeNumber: "R552", city: "Denver", state: "CO", partsAvailability: testParts)
        ]
        
        model.availableParts = testStores.map { ($0, testParts) }
        model.updateErrorState(to: ModelError.noStoresFound)
        
        return model
    }
}
