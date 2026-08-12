import Foundation

public enum ProviderEvent: Sendable {
    case success(TranslationResult)
    case failure(
        providerID: ProviderID,
        requestID: UUID,
        error: TranslationProviderError
    )
}

public struct TranslationCoordinator: Sendable {
    private let providers: [ProviderID: any TranslationProvider]

    public init(providers: [any TranslationProvider]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    public func events(
        for request: TranslationRequest,
        providerIDs: Set<ProviderID> = [.google, .llm]
    ) -> AsyncStream<ProviderEvent> {
        AsyncStream { continuation in
            let task = Task {
                // 结构化任务组让每个源独立完成并按完成顺序发布，同时统一管理子任务生命周期。
                await withTaskGroup(of: ProviderEvent.self) { group in
                    for (providerID, provider) in providers
                    where providerIDs.contains(providerID)
                    {
                        group.addTask {
                            do {
                                return .success(try await provider.translate(request))
                            } catch let error as TranslationProviderError {
                                return .failure(
                                    providerID: providerID,
                                    requestID: request.id,
                                    error: error
                                )
                            } catch {
                                return .failure(
                                    providerID: providerID,
                                    requestID: request.id,
                                    error: .invalidResponse
                                )
                            }
                        }
                    }

                    for await event in group {
                        continuation.yield(event)
                    }
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func retry(
        providerID: ProviderID,
        request: TranslationRequest
    ) async -> ProviderEvent {
        guard let provider = providers[providerID] else {
            return .failure(
                providerID: providerID,
                requestID: request.id,
                error: .unconfigured
            )
        }

        do {
            return .success(try await provider.translate(request))
        } catch let error as TranslationProviderError {
            return .failure(providerID: providerID, requestID: request.id, error: error)
        } catch {
            return .failure(
                providerID: providerID,
                requestID: request.id,
                error: .invalidResponse
            )
        }
    }
}
