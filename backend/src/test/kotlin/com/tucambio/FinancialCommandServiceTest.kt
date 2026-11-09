package com.tucambio

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals

class FinancialCommandServiceTest {
    private val actor = UUID.fromString("10000000-0000-0000-0000-000000000001")
    private val tenant = UUID.fromString("20000000-0000-0000-0000-000000000001")
    private val repository = CapturingRepository()
    private val service = FinancialCommandService(repository)

    @Test
    fun sameTypedRequestProducesStableSha256AndPreservesIdempotencyKey() {
        val request = CreateCurrencyRequest("BOB", "Boliviano", 2)

        service.createCurrency(actor, tenant, request, "request-1")
        val firstHash = repository.lastHash!!.copyOf()
        service.createCurrency(actor, tenant, request, "request-1")

        assertContentEquals(firstHash, repository.lastHash)
        assertEquals("request-1", repository.lastKey)
        assertEquals(32, repository.lastHash!!.size)
    }

    @Test
    fun changedRequestProducesDifferentSha256() {
        service.createCurrency(actor, tenant, CreateCurrencyRequest("BOB", "Boliviano", 2), "request-1")
        val firstHash = repository.lastHash!!.copyOf()

        service.createCurrency(actor, tenant, CreateCurrencyRequest("USD", "US Dollar", 2), "request-1")

        assertNotEquals(firstHash.toList(), repository.lastHash!!.toList())
    }

    private class CapturingRepository : FinancialCommandRepository {
        var lastHash: ByteArray? = null
        var lastKey: String? = null

        private fun capture(key: String, hash: ByteArray): JsonObject {
            lastKey = key
            lastHash = hash.copyOf()
            return buildJsonObject {
                put("resourceId", "30000000-0000-0000-0000-000000000001")
                put("replayed", false)
            }
        }

        override fun createCurrency(actorId: UUID, tenantId: UUID, request: CreateCurrencyRequest, key: String, hash: ByteArray) = capture(key, hash)
        override fun createCurrencyPair(actorId: UUID, tenantId: UUID, request: CreateCurrencyPairRequest, key: String, hash: ByteArray) = capture(key, hash)
        override fun createCurrencyRate(actorId: UUID, tenantId: UUID, request: CreateCurrencyRateRequest, key: String, hash: ByteArray) = capture(key, hash)
        override fun createOperation(actorId: UUID, tenantId: UUID, request: CreateFinancialOperationRequest, key: String, hash: ByteArray) = capture(key, hash)
        override fun createMovement(actorId: UUID, tenantId: UUID, request: CreateExternalMovementRequest, key: String, hash: ByteArray) = capture(key, hash)
        override fun associateMovement(actorId: UUID, tenantId: UUID, request: AssociateExternalMovementRequest, key: String, hash: ByteArray) = capture(key, hash)
        override fun transitionMovement(actorId: UUID, tenantId: UUID, movementId: String, request: TransitionExternalMovementRequest, key: String, hash: ByteArray) = capture(key, hash)
        override fun applyOperationRate(actorId: UUID, tenantId: UUID, operationId: String, key: String, hash: ByteArray) = capture(key, hash)
    }
}
