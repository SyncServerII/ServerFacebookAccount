//
//  FacebookCreds.swift
//  Server
//
//  Created by Christopher Prince on 7/16/17.
//

import Foundation
import ServerShared
import Credentials
import Kitura
import LoggerAPI
import KituraNet
import ServerAccount

public protocol FacebookCredsConfiguration {
    var FacebookClientId:String? { get }
    var FacebookClientSecret:String?  { get }
}

public class FacebookCreds : AccountAPICall,  Account {
    public var accessToken: String!
    
    public static var accountScheme:AccountScheme {
        return .facebook
    }
    
    public var accountScheme:AccountScheme {
        return FacebookCreds.accountScheme
    }
    
   public  var owningAccountsNeedCloudFolderName: Bool {
        return false
    }

    weak var delegate:AccountDelegate?
    
    public var accountCreationUser:AccountCreationUser?
    var configuration: FacebookCredsConfiguration?
    
    required public init?(configuration: Any? = nil, delegate: AccountDelegate?) {
        super.init()
        self.delegate = delegate
        if let configuration = configuration as? FacebookCredsConfiguration {
            self.configuration = configuration
        }
        baseURL = "graph.facebook.com"
    }
    
    // There is no need to put any tokens into the database for Facebook. We don't need to access Facebook creds when the mobile user is offline, and this would just make an extra security issue.
    public func toJSON() -> String? {
        let jsonDict = [String:String]()
        return JSONExtras.toJSONString(dict: jsonDict)
    }
    
    // We're using token generation with Facebook to exchange a short-lived access token for a long-lived one. See https://developers.facebook.com/docs/facebook-login/access-tokens/expiration-and-extension and https://stackoverflow.com/questions/37674620/do-facebook-has-a-refresh-token-of-oauth/37683233
    // 7/3/20; Hmmm. I'm not sure why I ever do `generateTokes` for Facebook. With Google, I am using this to generate a refresh token from an auth code. Similarly, with Microsoft I use it to generate a refresh token and an access token. In general, for sharing accounts we need access tokens and refresh tokens in an ongoing manner because they are needed for access to files.
    // For Apple (a sharing account), it helps us do the periodic checks to see if the user is still valid (because we can't do those checks in te Kitura credentials plugin).
    // I think we don't need to for Facebook. For Facebook, the Kitura-CredentialsFacebook plugin checks with Facebook servers.
    public func needToGenerateTokens(dbCreds:Account? = nil) -> Bool {
        // 11/5/17; See SharingAccountsController.swift comment with the same date for the reason for this conditional compilation. When running the server XCTest cases, make sure to turn on this flag.
#if DEVTESTING
        return false
#else
        return true
#endif
    }

    enum GenerateTokensError : Swift.Error {
        case non200ErrorCode(Int?)
        case didNotReceiveJSON
        case noAccessTokenInResult
        case noAppIdOrSecret
    }
    
    public func generateTokens(completion:@escaping (Swift.Error?)->()) {
        guard let fbAppId = configuration?.FacebookClientId,
            let fbAppSecret = configuration?.FacebookClientSecret else {
            completion(GenerateTokensError.noAppIdOrSecret)
            return
        }
        
        let urlParameters = "grant_type=fb_exchange_token&client_id=\(fbAppId)&client_secret=\(fbAppSecret)&fb_exchange_token=\(accessToken!)"

        Log.debug("urlParameters: \(urlParameters)")
        /*
        GET /oauth/access_token?
         grant_type=fb_exchange_token&amp;
         client_id={app-id}&amp;
         client_secret={app-secret}&amp;
         fb_exchange_token={short-lived-token}
        */
        
        apiCall(method: "GET", path: "/oauth/access_token",
                urlParameters: urlParameters) { apiCallResult, httpStatus, responseHeaders in
            if httpStatus == HTTPStatusCode.OK {
                switch apiCallResult {
                case .some(.dictionary(let dictionary)):
                    guard let accessToken = dictionary["access_token"] as? String else {
                        completion(GenerateTokensError.noAccessTokenInResult)
                        return
                    }
                    
                    self.accessToken = accessToken
                    completion(nil)
                    
                default:
                    completion(GenerateTokensError.didNotReceiveJSON)
                }
            }
            else {
                Log.debug("apiCallResult: \(String(describing: apiCallResult))")
                completion(GenerateTokensError.non200ErrorCode(httpStatus.map { $0.rawValue }))
            }
        }
    }
    
    public func merge(withNewer account:Account) {
    }
    
    public static func getProperties(fromHeaders headers:AccountHeaders) -> [String: Any] {
        if let accessToken = headers[ServerConstants.HTTPOAuth2AccessTokenKey] {
            return [ServerConstants.HTTPOAuth2AccessTokenKey: accessToken]
        } else {
            return [:]
        }
    }
    
    public static func fromProperties(_ properties: AccountProperties, user:AccountCreationUser?, configuration: Any?, delegate:AccountDelegate?) -> Account? {
        guard let creds = FacebookCreds(configuration: configuration, delegate: delegate) else {
            return nil
        }
        
        creds.accountCreationUser = user
        creds.accessToken = properties.properties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        return creds
    }
    
    public static func fromJSON(_ json:String, user:AccountCreationUser, configuration: Any?, delegate:AccountDelegate?) throws -> Account? {
        
        guard let creds = FacebookCreds(configuration: configuration, delegate: delegate) else {
            return nil
        }
        
        creds.accountCreationUser = user
        
        return creds
    }
}

