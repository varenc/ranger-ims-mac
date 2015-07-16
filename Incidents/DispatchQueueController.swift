//
//  DispatchQueueController.swift
//  Incidents
//
//  © 2015 Burning Man and its contributors. All rights reserved.
//  See the file COPYRIGHT.md for terms.
//

import Cocoa



struct FilteredIncidentsCache {
    let searchText: String
    let incidents: [Incident]
    let openIncidents: [Incident]
}



class DispatchQueueController: NSWindowController {

    var appDelegate: AppDelegate!

    let ims: HTTPIncidentManagementSystem  // FIXME: should be IncidentManagementSystem, but working around a bug
    var imsUsername: String?
    var imsPassword: String?

    var incidentControllers: [Int: IncidentController] = [:]

    var reloadInterval: NSTimeInterval = 10
    var reloadTimer: NSTimer? = nil

    @IBOutlet weak var searchField     : NSSearchField?
    @IBOutlet weak var dispatchTable   : NSTableView?
    @IBOutlet weak var loadingIndicator: NSProgressIndicator?
    @IBOutlet weak var reloadButton    : NSButton?
    @IBOutlet weak var showClosedButton: NSButton?
    @IBOutlet weak var userField       : NSTextField?


    var searchText: String {
        guard let searchFieldCell = searchField?.cell as? NSSearchFieldCell else {
            return ""
        }
        return searchFieldCell.stringValue
    }


    var showClosed: Bool {
        guard let showClosedState = showClosedButton?.state else {
            return false
        }
        return showClosedState == NSOnState
    }


    var sortedIncidents: [Incident] {
        if _sortedIncidents == nil {
            if let sortDescriptors = dispatchTable?.sortDescriptors as [NSSortDescriptor]? {
                func isOrderedBefore(lhs: Incident, rhs: Incident) -> Bool {
                    return incident(lhs, isOrderedBeforeIncident: rhs, usingDescriptors: sortDescriptors)
                }
                _sortedIncidents = ims.incidentsByNumber.values.sort(isOrderedBefore)
            }
            else {
                func isOrderedBefore(i1: Incident, i2: Incident) -> Bool {
                    return i1.number < i2.number
                }
                _sortedIncidents = ims.incidentsByNumber.values.sort(isOrderedBefore)
            }
        }
        guard let sortedIncidents = _sortedIncidents else {
            logError("Sorted incidents is unexpectedly nil")
            return []
        }
        return sortedIncidents
    }
    private var _sortedIncidents: [Incident]? = nil


    var filteredIncidentsCache: FilteredIncidentsCache {
        if let cache = _filteredIncidentsCache {
            if cache.searchText == searchText {
                return cache
            }
        }

        var filteredIncidents    : [Incident] = []
        var filteredOpenIncidents: [Incident] = []

        for incident in sortedIncidents {
            // FIXME *************************  SEARCH  *************************************
            filteredIncidents.append(incident)

            if !showClosed && incident.state != IncidentState.Closed {
                filteredOpenIncidents.append(incident)
            }

        }

        _filteredIncidentsCache = FilteredIncidentsCache(
            searchText: searchText,
            incidents: filteredIncidents,
            openIncidents: filteredOpenIncidents
        )
        
        return _filteredIncidentsCache!
    }
    private var _filteredIncidentsCache: FilteredIncidentsCache? = nil


    convenience init(appDelegate: AppDelegate) {
        self.init(windowNibName: "DispatchQueue")

        self.appDelegate = appDelegate
    }


    override init(window: NSWindow?) {
//        ims = InMemoryIncidentManagementSystem()
//
//        // For debugging... ************************************************************************************
//        _populateWithFakeData(ims as! InMemoryIncidentManagementSystem)

        let defaults = NSUserDefaults.standardUserDefaults()

        let scheme: String
        if defaults.boolForKey("IMSServerDisableTLS") {
            scheme = "http"
        } else {
            scheme = "https"
        }

        let host: String
        if let _host = defaults.stringForKey("IMSServerHostName") {
            host = _host
        } else {
            host = "localhost"
        }

        let port: String
        if let _port = defaults.stringForKey("IMSServerPort") {
            port = ":\(_port)"
        } else {
            port = ""
        }

        let path = "/"

        let url = "\(scheme)://\(host)\(port)\(path)"

        logInfo("IMS Server: \(url)")
        ims = HTTPIncidentManagementSystem(url: url)

        super.init(window: window)

        ims.delegate = self
    }


    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    func reload(force: Bool) {
        if force && reloadTimer != nil {
            reloadTimer!.invalidate()
            reloadTimer = nil
        }

        if (reloadTimer == nil || !reloadTimer!.valid) {
            ims.reload()

            logDebug("Restarting reload timer")
            reloadTimer = NSTimer.scheduledTimerWithTimeInterval(
                reloadInterval,
                target: self,
                selector: Selector("reloadTimerFired:"),
                userInfo: self,
                repeats: false
            )
        }
    }


    func reloadTimerFired(timer: NSTimer) {
        if !NSUserDefaults.standardUserDefaults().boolForKey("IMSDisableReloadTimer") {
            logDebug("Reloading after timer")
            reload(true)
        }
    }


    func openIncident(incident: Incident) {
        guard let number = incident.number else {
            logError("Can't open an incident without a number")
            return
        }

        let incidentController: IncidentController

        if let _incidentController = incidentControllers[number] {
            // Already have a controller for the incident in question
            incidentController = _incidentController
        } else {
            // Create a controller for the incident in question
            incidentController = IncidentController(
                dispatchQueueController: self,
                incident: incident
            )
            incidentControllers[number] = incidentController
        }

        incidentController.showWindow(self)
        incidentController.window?.makeKeyAndOrderFront(self)

        let incidentWindowWillClose = {
            (notification: NSNotification) -> Void in

            guard let window = notification.object else {
                logError("Got a window will close notification for a nil window?")
                return
            }

            guard let controller = window.windowController as? IncidentController else {
                logError("Got a window will close notification for an incident window with no incident controller?")
                return
            }

            guard controller == incidentController else {
                logError("Got a window will close notification for an incident window with a different incident controller?")
                return
            }

            guard self.incidentControllers.removeValueForKey(number) != nil else {
                logError("Got a window will close notification for an incident window no longer being tracked?")
                return
            }
        }

        NSNotificationCenter.defaultCenter().addObserverForName(
            NSWindowWillCloseNotification,
            object: incidentController.window,
            queue: nil,
            usingBlock: incidentWindowWillClose
        )
    }


    func openClickedIncident() {
        guard let dispatchTable = self.dispatchTable else { return }

        let rowIndex = dispatchTable.clickedRow

        let incident: Incident
        do {
            incident = try incidentForTableRow(rowIndex)
        } catch {
            logError("No incident for clicked row index \(rowIndex)")
            return
        }

        openIncident(incident)
    }

}



extension DispatchQueueController: HTTPIncidentManagementSystemDelegate {

    func incidentDidUpdate(ims: IncidentManagementSystem, incident: Incident) {
        guard let number = incident.number else {
            logError("Updated incident has no number: \(incident)")
            return
        }
        
        logDebug("Incident updated: \(incident)")
        
        if let incidentController = incidentControllers[number] {
            alert(title: "Implement Me", message: "incidentDidUpdate() with controller \(incidentController)")
        }

        resort(self)
    }


    func handleAuth(
        host host: String,
        port: Int,
        realm: String?
    ) -> HTTPCredential? {
        dispatch_sync(
            dispatch_get_main_queue(),
            {
                let passwordController = PasswordController(dispatchQueueController: self)
                
                if passwordController.window != nil {
                    passwordController.showWindow(self)
                    passwordController.window!.makeKeyAndOrderFront(self)
                
                    NSApp.runModalForWindow(passwordController.window!)
                }
            }
        )
        
        guard let username = imsUsername, password = imsPassword else { return nil }
        
        return HTTPUsernamePasswordCredential(
            username: username,
            password: password
        )
    }
    
}



extension DispatchQueueController: NSWindowDelegate {

     override func windowDidLoad() {
        super.windowDidLoad()

        func arghEvilDeath(uiElementName: String) {
            fatalError("Dispatch queue controller: no \(uiElementName)?")
        }

        if window           == nil { arghEvilDeath("window"            ) }
        if searchField      == nil { arghEvilDeath("search field"      ) }
        if dispatchTable    == nil { arghEvilDeath("dispatch table"    ) }
        if loadingIndicator == nil { arghEvilDeath("loading indicator" ) }
        if reloadButton     == nil { arghEvilDeath("reload button"     ) }
        if showClosedButton == nil { arghEvilDeath("show closed button") }
        if userField        == nil { arghEvilDeath("user field"        ) }

        reloadButton!.hidden     = false
        loadingIndicator!.hidden = true

        if self.respondsToSelector(Selector("openClickedIncident")) {
            dispatchTable!.doubleAction = Selector("openClickedIncident")
        } else {
            arghEvilDeath("DDispatchQueueController doesn't respond to openClickedIncident()")
        }

        reload(false)
    }

}



extension DispatchQueueController: NSTableViewDataSource {

    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        return viewableIncidents.count
    }


    func tableView(
        tableView: NSTableView,
        objectValueForTableColumn column: NSTableColumn?,
        row rowIndex: Int
    ) -> AnyObject? {
        let incident: Incident
        do {
            incident = try incidentForTableRow(rowIndex)
        } catch {
            logError("No incident for row index \(rowIndex)")
            return nil
        }

        guard let label = column?.identifier else {
            logError("Unidentified column: \(column)")
            return nil
        }

        switch label {
            case "number":
                return incident.number

            case "priority":
                return incident.priority?.description

            case "created":
                return incident.created?.asShortString()

            case "state":
                return incident.state?.description

            case "rangers":
                return incident.rangersAsText

            case "location":
                return incident.location?.description

            case "incidentTypes":
                return incident.incidentTypesAsText

            case "summary":
                return incident.summaryAsText

            default:
                logError("Unknown column: \(label)")
                return nil
        }
    }


    // Not NSTableViewDataSource, but related

    var viewableIncidents: [Incident] {
        if showClosed {
            return filteredIncidentsCache.incidents
        } else {
            return filteredIncidentsCache.openIncidents
        }
    }


    @IBAction func updateViewedIncidents(sender: AnyObject?) {
        if let dispatchTable = self.dispatchTable {
            // Make sure UI stuff goes to the main thread
            dispatch_async(dispatch_get_main_queue()) {
                () -> Void in
                dispatchTable.reloadData()
            }
        }
    }


    @IBAction func resort(sender: AnyObject?) {
        _sortedIncidents        = nil
        _filteredIncidentsCache = nil

        updateViewedIncidents(self)
    }


    func incidentForTableRow(rowIndex: Int) throws -> Incident {
        guard rowIndex >= 0 else {
            throw DispatchQueueTableSourceError.RowIndexOutOfRange(rowIndex)
        }
        
        guard rowIndex <= viewableIncidents.count else {
            throw DispatchQueueTableSourceError.RowIndexOutOfRange(rowIndex)
        }

        return viewableIncidents[rowIndex]
    }


    func selectedIncident() -> Incident? {
        guard let dispatchTable = self.dispatchTable else {
            return nil
        }

        let incident: Incident
        do {
            incident = try incidentForTableRow(dispatchTable.selectedRow)
        } catch {
            logError("Unable to look up selected incident: \(error)")
            return nil
        }
        return incident
    }


    @IBAction func userReload(sender: AnyObject?) {
        reload(true)
    }

}



enum DispatchQueueTableSourceError: ErrorType {
    case RowIndexOutOfRange(Int)
}



extension DispatchQueueController: NSTableViewDelegate {

    func tableView(tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        resort(self)
    }

}



func incident(
    lhs: Incident,
    isOrderedBeforeIncident rhs: Incident,
    usingDescriptors descriptors: [NSSortDescriptor]
) -> Bool {
    for descriptor in descriptors {
        guard let keyPath: String = descriptor.key else {
            logError("Sort descriptor specified no key.")
            continue
        }

        if incident(lhs, isOrderedBeforeIncident: rhs, usingKeyPath: keyPath) {
            return descriptor.ascending
        }
        else if incident(rhs, isOrderedBeforeIncident: lhs, usingKeyPath: keyPath) {
            return !descriptor.ascending
        }
    }
    return false
}



func incident(
    lhs: Incident,
    isOrderedBeforeIncident rhs: Incident,
    usingKeyPath keyPath: String
) -> Bool {
    switch keyPath {
        case "number":
            return lhs.number < rhs.number
            
        case "priority":
            if lhs.priority == nil { logError("Ordered incident \(lhs) has nil priority"); return true  }
            if rhs.priority == nil { logError("Ordered incident \(rhs) has nil priority"); return false }
            return lhs.priority! < rhs.priority!
            
        case "summary":
            return lhs.summaryAsText < rhs.summaryAsText
            
        case "location":
            if lhs.location == nil { return true  }
            if rhs.location == nil { return false }
            return lhs.location! < rhs.location!
            
        case "rangers":
            return lhs.rangersAsText < rhs.rangersAsText
            
        case "incidentTypes":
            return lhs.rangersAsText < rhs.rangersAsText
            
        case "reportEntries":
            return false
            
        case "created":
            if lhs.created == nil { logError("Ordered incident \(lhs) has nil created"); return true  }
            if rhs.created == nil { logError("Ordered incident \(rhs) has nil created"); return false }
            return lhs.created! < rhs.created!
            
        case "state":
            if lhs.state == nil { logError("Ordered incident \(lhs) has nil state"); return true  }
            if rhs.state == nil { logError("Ordered incident \(rhs) has nil state"); return false }
            return lhs.state! < rhs.state!
            
        default:
            logError("Unknown sort descriptor key path: \(keyPath)")
            return false
    }
}



// ===================================================================== //

func _populateWithFakeData(ims: InMemoryIncidentManagementSystem) {
    let date1String = "1971-04-20T16:20:04Z"
    let date2String = "1972-06-29T08:04:15Z"
    let date3String = "1972-06-30T18:40:51Z"
    let date4String = "1972-06-30T18:40:52Z"

    let date1 = DateTime.fromRFC3339String(date1String)
    let date2 = DateTime.fromRFC3339String(date2String)
    let date3 = DateTime.fromRFC3339String(date3String)
    let date4 = DateTime.fromRFC3339String(date4String)

    let cannedIncidentTypes = Set([
        "Airport",
        "Animal",
        "Art",
        "Assault",
        "Fire",
        "Law Enforcement",
        "Medical",
        "Staff",
        "Theft",
        "Vehicle",
    ])


    let cannedRangers = [
        "k8"         : Ranger(handle: "k8"         ),
        "Safety Phil": Ranger(handle: "Safety Phil"),
        "Splinter"   : Ranger(handle: "Splinter"   ),
        "Tool"       : Ranger(handle: "Tool"       ),
        "Tulsa"      : Ranger(handle: "Tulsa"      ),
    ]

    let cannedLocations = [
        "The Man": Location(
            name: "The Man",
            address: Address(textDescription: "The Man")
        ),
        "The Temple": Location(
            name: "The Temple",
            address: Address(textDescription: "The Temple")
        ),
        "Camp Fishes": Location(
            name: "Camp Fishes",
            address: RodGarettAddress(
                concentric: ConcentricStreet.J,
                radialHour: 3,
                radialMinute: 30,
                textDescription: "Big fish tank"
            )
        ),
    ]

    let cannedIncidents = [
        Incident(
            number: 1,
            priority: IncidentPriority.Normal,
            summary: "Participant fell from structure at Camp Fishes",
            location: cannedLocations["Camp Fishes"]!,
            rangers: [cannedRangers["Splinter"]!],
            incidentTypes: ["Medical"],
            reportEntries: [
                ReportEntry(
                    author: cannedRangers["k8"]!,
                    text: "Participant fell from structure at Camp Fishes.\nSplinter on scene.",
                    created: date1
                )
            ],
            created: date1,
            state: IncidentState.OnScene
        ),
        Incident(
            number: 2,
            priority: IncidentPriority.Low,
            summary: "Lost keys",
            location: Location(
                address: Address(textDescription: "Near the portos on 9:00 promenade")
            ),
            rangers: [cannedRangers["Safety Phil"]!],
            created: date2,
            state: IncidentState.OnHold
        ),
        Incident(
            number: 3,
            priority: IncidentPriority.High,
            summary: "Speeding near the Man",
            location: cannedLocations["The Man"]!,
            rangers: [cannedRangers["Tulsa"]!],
            incidentTypes: ["Vehicle"],
            reportEntries: [
                ReportEntry(
                    author: cannedRangers["Tool"]!,
                    text: "Black sedan, unlicensed, travelling at high speed around the Man.",
                    created: date3
                )
            ],
            created: date2,
            state: IncidentState.Dispatched
        ),
        Incident(
            number: 4,
            priority: IncidentPriority.High,
            summary: "Need MHB at the Temple",
            location: cannedLocations["The Temple"]!,
            rangers: [cannedRangers["Tulsa"]!],
            incidentTypes: ["Medical"],
            reportEntries: [
                ReportEntry(
                    author: cannedRangers["Tool"]!,
                    text: "Highly agitated male at Temple.",
                    created: date4
                )
            ],
            created: date4,
            state: IncidentState.Closed
        ),
        Incident(
            number: 5,
            priority: IncidentPriority.Normal,
            created: date4,
            state: IncidentState.New
        ),
    ]

    for incidentType in cannedIncidentTypes {
        ims.addIncidentType(incidentType)
    }

    for ranger in cannedRangers.values {
        ims.addRanger(ranger)
    }

    for incident in cannedIncidents {
        let incidentWithoutNumber = Incident(
            number       : nil,
            priority     : incident.priority,
            summary      : incident.summary,
            location     : incident.location,
            rangers      : incident.rangers,
            incidentTypes: incident.incidentTypes,
            reportEntries: incident.reportEntries,
            created      : incident.created,
            state        : incident.state
        )

        do {
            try ims.createIncident(incidentWithoutNumber)
        } catch {
            logError("Unable to create incident: \(error)")
            alert(title: "Unable to create incident", message: "\(error)")
        }
    }
}
