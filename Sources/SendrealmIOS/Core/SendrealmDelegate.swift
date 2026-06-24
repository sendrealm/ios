import Foundation

@objc public protocol SendrealmDelegate: AnyObject {
    @objc(sendrealm:didReceiveEvent:body:)
    func sendrealm(_ sdk: Sendrealm, didReceiveEvent name: String, body: NSDictionary)
}
