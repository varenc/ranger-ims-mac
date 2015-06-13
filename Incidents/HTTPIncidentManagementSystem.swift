//
//  HTTPIncidentManagementSystem.swift
//  Incidents
//
//  © 2015 Burning Man and its contributors. All rights reserved.
//  See the file COPYRIGHT.md for terms.
//

import Foundation



class HTTPIncidentManagementSystem: NSObject, IncidentManagementSystem {

    let url: String

    private var loadingState: IMSLoadingState = IMSLoadingState.Reset

    var incidentTypes: Set<String> {
        return _incidentTypes
    }
    private var _incidentTypes: Set<String> = Set()

    var rangersByHandle: [String: Ranger] {
        return _rangersByHandle
    }
    private var _rangersByHandle: [String: Ranger] = Dictionary()

    var locationsByName: [String: Location] {
        return _locationsByName
    }
    private var _locationsByName: [String: Location] = Dictionary()

    var incidentsByNumber: [Int: Incident] {
        return _incidentsByNumber
    }
    private var _incidentsByNumber: [Int: Incident] = Dictionary()

    private var httpSession: HTTPSession {
        if _httpSession == nil {
            _httpSession = HTTPSession(
                userAgent: "Ranger IMS (Mac OS)",
                idleTimeOut: 2, timeOut: 30
            )
        }
        return _httpSession!
    }
    private var _httpSession: HTTPSession? = nil


    init(url: String) {
        self.url = url
    }


    func reload() {
        switch loadingState {
            case .Reset:
                connect()
            case .Trying:
                return
            case .Loading:
                return
            case .Idle:
                loadingState = IMSLoadingState.Loading([:])
                loadIncidentTypes()
                loadPersonnel()
                loadLocations()
        }
    }


    func createIncident(incident: Incident) -> Failable {
        return Failable(Error("Unimplemented"))
    }


    func updateIncident(incident: Incident) -> Failable {
        return Failable(Error("Unimplemented"))
    }


//    func reloadIncidentWithNumber(number: Int) -> Failable {
//        return Failable(Error("Unimplemented"))
//    }
    
    
    private func connect() {
        switch loadingState {
        case .Reset:
            break
        default:
            return
        }

        let pingURL = "\(self.url)ping/"

        func onResponse(json: AnyObject?) {
            logInfo("Successfully connected to IMS Server: \(self.url)")
            loadingState = IMSLoadingState.Idle

            reload()
        }

        func onError(message: String) {
            logError("Error while attempting ping request: \(message)")
            resetConnection()
        }

        logInfo("Sending ping request to: \(pingURL)")

        guard let connection = self.httpSession.sendJSON(
            url: pingURL,
            json: nil,
            responseHandler: onResponse,
            errorHandler: onError
            ) else {
                logError("Unable to create ping connection?")
                resetConnection()
                return
        }

        loadingState = IMSLoadingState.Trying(connection)
    }


    private func resetConnection() {
        logError("Resetting IMS server connection")

        loadingState = IMSLoadingState.Reset

        guard let session = _httpSession else {
            return
        }
        
        _httpSession = nil
        
        session.invalidate()
    }
    
    
    private func loadIncidentTypes() {
        let typesURL = "\(self.url)incident_types/"

        func onResponse(json: AnyObject?) {
            logInfo("Loaded incident types")

            removeConnectionForLoadingGroup(
                group: IMSLoadingGroup.IncidentTypes,
                id: IMSConnectionID.IncidentTypes
            )

            guard let json = json else {
                logError("Incident types request retrieved no JSON data")
                return
            }

            guard let incidentTypes = json as? Array<String> else {
                logError("Incident Types JSON is non-conforming: \(json)")
                return
            }

            _incidentTypes = Set(incidentTypes)
        }

        func onError(message: String) {
            logError("Error while attempting incident types request: \(message)")
            resetConnection()
        }

        logInfo("Sending incident types request to: \(typesURL)")

        guard let connection = self.httpSession.sendJSON(
            url: typesURL,
            json: nil,
            responseHandler: onResponse,
            errorHandler: onError
            ) else {
                logError("Unable to create incident types connection?")
                resetConnection()
                return
        }

        addConnectionForLoadingGroup(
            group: IMSLoadingGroup.IncidentTypes,
            id: IMSConnectionID.IncidentTypes,
            connection: connection
        )
    }
    
    
    private func loadPersonnel() {
        let typesURL = "\(self.url)personnel/"

        func onResponse(json: AnyObject?) {
            logInfo("Loaded personnel")

            removeConnectionForLoadingGroup(
                group: IMSLoadingGroup.Personnel,
                id: IMSConnectionID.Personnel
            )

            guard let json = json else {
                logError("Personnel request retrieved no JSON data")
                return
            }

            guard let personnel = json as? Array<[String: String]> else {
                logError("Personnel JSON is non-conforming: \(json)")
                return
            }

            var rangersByHandle: [String: Ranger] = [:]

            for person in personnel {
                guard
                    let handle = person["handle"],
                    let name   = person["name"  ],
                    let status = person["status"]
                else {
                    logError("Incomplete personnel record: \(person)")
                    continue
                }
                let ranger = Ranger(handle: handle, name: name, status: status)
                rangersByHandle[handle] = ranger
            }

            _rangersByHandle = rangersByHandle
        }

        func onError(message: String) {
            logError("Error while attempting personnel request: \(message)")
            resetConnection()
        }

        logInfo("Sending personnel request to: \(typesURL)")

        guard let connection = self.httpSession.sendJSON(
            url: typesURL,
            json: nil,
            responseHandler: onResponse,
            errorHandler: onError
            ) else {
                logError("Unable to create personnel connection?")
                resetConnection()
                return
        }

        addConnectionForLoadingGroup(
            group: IMSLoadingGroup.Personnel,
            id: IMSConnectionID.Personnel,
            connection: connection
        )
    }
    
    
    private func loadLocations() {
        let typesURL = "\(self.url)locations/"

        func onResponse(json: AnyObject?) {
            logInfo("Loaded locations")

            removeConnectionForLoadingGroup(
                group: IMSLoadingGroup.Locations,
                id: IMSConnectionID.Locations
            )

            guard let json = json else {
                logError("Locations request retrieved no JSON data")
                return
            }

            guard let locations = json as? Array<[String: String]> else {
                logError("Locations JSON is non-conforming: \(json)")
                return
            }

//            var rangersByHandle: [String: Ranger] = [:]
//
//            for location in locations {
//                guard
//                    let handle = person["handle"],
//                    let name   = person["name"  ],
//                    let status = person["status"]
//                    else {
//                        logError("Incomplete location record: \(person)")
//                        continue
//                }
//                let ranger = Ranger(handle: handle, name: name, status: status)
//                rangersByHandle[handle] = ranger
//            }
//
//            _rangersByHandle = rangersByHandle
        }

        func onError(message: String) {
            logError("Error while attempting locations request: \(message)")
            resetConnection()
        }

        logInfo("Sending locations request to: \(typesURL)")

        guard let connection = self.httpSession.sendJSON(
            url: typesURL,
            json: nil,
            responseHandler: onResponse,
            errorHandler: onError
            ) else {
                logError("Unable to create locations connection?")
                resetConnection()
                return
        }

        addConnectionForLoadingGroup(
            group: IMSLoadingGroup.Locations,
            id: IMSConnectionID.Locations,
            connection: connection
        )
    }


//    private func connectionsForLoadingGroup(
//        group: IMSLoadingGroup
//    ) throws -> [IMSConnectionID: HTTPConnection] {
//
//        switch loadingState {
//            case .Loading(let loading):
//                guard let connections = loading[group] else {
//                    return [:]
//                }
//                return connections
//            default:
//                throw IMSInternalError.IncorrectLoadingState
//        }
//    }


    private func addConnectionForLoadingGroup(
        group group: IMSLoadingGroup,
        id: IMSConnectionID,
        connection: HTTPConnection
        ) {
            guard case .Loading(var loading) = loadingState else {
                logError("Incorrect loading state.")
                return
            }

            if loading[group] == nil {
                loading[group] = [:]
            }

            loading[group]![id] = connection

            loadingState = IMSLoadingState.Loading(loading)
    }


    private func removeConnectionForLoadingGroup(
        group group: IMSLoadingGroup,
        id: IMSConnectionID
        ) {
            guard case .Loading(var loading) = loadingState else {
                logError("Incorrect loading state.")
                return
            }

            if loading[group] == nil {
                logError("No such connection.")
                return
            }

            if loading[group]!.removeValueForKey(id) == nil {
                logError("No such connection.")
                return
            }

            if loading[group]!.count == 0 {
                // Nothing left for this group; remove the group
                loading.removeValueForKey(group)

                if loading.count == 0 {
                    // No groups loading data; switch to idle state
                    loadingState = IMSLoadingState.Idle
                    return
                }
            }
            
            loadingState = IMSLoadingState.Loading(loading)
    }
    
}



enum IMSLoadingState: CustomStringConvertible {
    case Reset
    case Trying(HTTPConnection)
    case Idle
    case Loading([IMSLoadingGroup: [IMSConnectionID: HTTPConnection]])

    var description: String {
        switch self {
            case .Reset:
                return "reset"

            case .Trying:
                return "trying"

            case .Idle:
                return "idle"

            case .Loading(let connections):
                var groups: [String] = []
                for (group, connections) in connections {
                    groups.append("\(group)(\(connections.count))")
                }

                var s = "loading("
                s += ", ".join(groups)
                s += ")"

                return s
        }
    }

}



enum IMSLoadingGroup: CustomStringConvertible {
    case IncidentTypes
    case Personnel
    case Locations

    var description: String {
        switch self {
            case .IncidentTypes: return "incident types"
            case .Personnel    : return "personnel"
            case .Locations    : return "locations"
        }
    }
}



enum IMSConnectionID {
    case IncidentTypes
    case Personnel
    case Locations
}



enum IMSError: ErrorType {
}



enum IMSInternalError: ErrorType {
    case IncorrectLoadingState
    case NoSuchConnection
}
