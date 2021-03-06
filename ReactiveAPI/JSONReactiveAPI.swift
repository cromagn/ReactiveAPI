import Foundation
import RxSwift
import RxCocoa

open class JSONReactiveAPI: ReactiveAPI {
    internal let session: Reactive<URLSession>
    internal let decoder: ReactiveAPIDecoder
    private let baseUrl: URL
    public var authenticator: ReactiveAPIAuthenticator? = nil
    public var requestInterceptors: [ReactiveAPIRequestInterceptor] = []
    public var cache: ReactiveAPICache? = nil
    
    required public init(session: Reactive<URLSession>, decoder: ReactiveAPIDecoder, baseUrl: URL) {
        self.session = session
        self.decoder = decoder
        self.baseUrl = baseUrl
    }
    
    public func absoluteURL(_ endpoint: String) -> URL {
        return baseUrl.appendingPathComponent(endpoint)
    }
    
    // every request must pass here
    private func rxDataRequest(_ request: URLRequest) -> Single<Data> {
        
        var mutableRequest = request
        
        requestInterceptors.forEach { mutableRequest = $0.intercept(mutableRequest) }
        
        return session.response(request: mutableRequest)
            .flatMap { [unowned self] (response, data) -> Observable<Data>  in
                if response.statusCode < 200 || response.statusCode >= 300 {
                    return Observable.error(ReactiveAPIError.httpError(response: response, data: data))
                }

                if
                    let cache = self.cache,
                    let urlCache = self.session.base.configuration.urlCache,
                    let cachedResponse = cache.cache(response,
                                                     request: mutableRequest,
                                                     data: data) {
                    urlCache.storeCachedResponse(cachedResponse,
                                                 for: mutableRequest)
                }
                
                return Observable.just(data)
            }
            .asSingle()
            .catchError({ [unowned self] (error) -> Single<Data> in
                guard
                    let authenticator = self.authenticator,
                    case let RxCocoaURLError.httpRequestFailed(response, data) = error,
                    let retryRequest = authenticator.authenticate(session: self.session,
                                                                  request: mutableRequest,
                                                                  response: response,
                                                                  data: data)
                    else { throw error }
                
                return retryRequest
            })
    }
    
    private func rxDataRequest<D: Decodable>(_ request: URLRequest) -> Single<D> {
        return rxDataRequest(request).flatMap { [unowned self] data in
            do {
                let decoded = try self.decoder.decode(D.self, from: data)
                return Single.just(decoded)
            } catch {
                return Single.error(error)
            }
        }
    }

    private func rxDataRequestArray<D: Decodable>(_ request: URLRequest) -> Single<[D]> {
        return rxDataRequest(request).flatMap { data in
            do {
                let decoded = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())

                if let decodedArray = decoded as? [D] {
                    return Single.just(decodedArray)
                } else {
                    return Single.error(ReactiveAPIError.jsonDeserializationError("unable to deserialize to JSON Array", data))
                }
            } catch {
                return Single.error(error)
            }
        }
    }
    
    private func rxDataRequestDiscardingPayload(_ request: URLRequest) -> Single<Void> {
        return rxDataRequest(request).map { _ in () }
    }
}

public extension JSONReactiveAPI {
    // body params as dictionary and generic response type
    public func request<D: Decodable>(_ method: ReactiveAPIHTTPMethod = .get,
                                      url: URL,
                                      headers: [String: String?]? = nil,
                                      queryParams: [String: Any?]? = nil,
                                      bodyParams: [String: Any?]? = nil) -> Single<D> {
        do {
            let request = try URLRequest.createForJSON(with: url,
                                                       method: method,
                                                       headers: headers,
                                                       queryParams: queryParams,
                                                       bodyParams: bodyParams)
            return rxDataRequest(request)
        } catch {
            return Single.error(error)
        }
    }

    // body params as encodable and generic response type
    public func request<E: Encodable, D: Decodable>(_ method: ReactiveAPIHTTPMethod = .get,
                                                    url: URL,
                                                    headers: [String: String?]? = nil,
                                                    queryParams: [String: Any?]? = nil,
                                                    body: E? = nil) -> Single<D> {
        do {
            let request = try URLRequest.createForJSON(with: url,
                                                       method: method,
                                                       headers: headers,
                                                       queryParams: queryParams,
                                                       body: body)
            return rxDataRequest(request)
        } catch {
            return Single.error(error)
        }
    }

    // body params as dictionary and void response type
    public func request(_ method: ReactiveAPIHTTPMethod = .get,
                        url: URL,
                        headers: [String: String?]? = nil,
                        queryParams: [String: Any?]? = nil,
                        bodyParams: [String: Any?]? = nil) -> Single<Void> {
        do {
            let request = try URLRequest.createForJSON(with: url,
                                                       method: method,
                                                       headers: headers,
                                                       queryParams: queryParams,
                                                       bodyParams: bodyParams)
            return rxDataRequestDiscardingPayload(request)
        } catch {
            return Single.error(error)
        }
    }

    // body params as encodable and void response type
    public func request<E: Encodable>(_ method: ReactiveAPIHTTPMethod = .get,
                                      url: URL,
                                      headers: [String: String?]? = nil,
                                      queryParams: [String: Any?]? = nil,
                                      body: E? = nil) -> Single<Void> {
        do {
            let request = try URLRequest.createForJSON(with: url,
                                                       method: method,
                                                       headers: headers,
                                                       queryParams: queryParams,
                                                       body: body)
            return rxDataRequestDiscardingPayload(request)
        } catch {
            return Single.error(error)
        }
    }

    // body params as dictionary and array response type
    public func request<D: Decodable>(_ method: ReactiveAPIHTTPMethod = .get,
                                      url: URL,
                                      headers: [String: String?]? = nil,
                                      queryParams: [String: Any?]? = nil,
                                      bodyParams: [String: Any?]? = nil) -> Single<[D]> {
        do {
            let request = try URLRequest.createForJSON(with: url,
                                                       method: method,
                                                       headers: headers,
                                                       queryParams: queryParams,
                                                       bodyParams: bodyParams)
            return rxDataRequestArray(request)
        } catch {
            return Single.error(error)
        }
    }

    // body params as encodable and array response type
    public func request<E: Encodable, D: Decodable>(_ method: ReactiveAPIHTTPMethod = .get,
                                                    url: URL,
                                                    headers: [String: String?]? = nil,
                                                    queryParams: [String: Any?]? = nil,
                                                    body: E? = nil) -> Single<[D]> {
        do {
            let request = try URLRequest.createForJSON(with: url,
                                                       method: method,
                                                       headers: headers,
                                                       queryParams: queryParams,
                                                       body: body)
            return rxDataRequestArray(request)
        } catch {
            return Single.error(error)
        }
    }
}
