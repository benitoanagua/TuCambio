package com.tucambio

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals

class EvidenceFinancialLinkServiceTest {
    private val actor = UUID.fromString("10000000-0000-0000-0000-000000000001")
    private val tenant = UUID.fromString("20000000-0000-0000-0000-000000000001")
    private val repository = CapturingRepository()
    private val service = EvidenceFinancialLinkService(repository)

    @Test
    fun normalizesTargetTypeAndUsesStableRequestHash() {
        val request = LinkFinancialEvidenceRequest(
            evidenceId = "30000000-0000-0000-0000-000000000001",
            targetType = " operation ",
            targetId = "40000000-0000-0000-0000-000000000001"
        )

        service.link(actor, tenant, request, "link-1")
        val firstHash = repository.lastHash!!.copyOf()
        service.link(actor, tenant, request, "link-1")

        assertEquals("OPERATION", repository.lastRequest!!.targetType)
        assertEquals("link-1", repository.lastKey)
        assertContentEquals(firstHash, repository.lastHash)
    }

    @Test
    fun changedTargetProducesDifferentHash() {
        val evidenceId = "30000000-0000-0000-0000-000000000001"
        service.link(actor, tenant, LinkFinancialEvidenceRequest(
            evidenceId, "OPERATION", "40000000-0000-0000-0000-000000000001"
        ), "link-1")
        val firstHash = repository.lastHash!!.copyOf()

        service.link(actor, tenant, LinkFinancialEvidenceRequest(
            evidenceId, "MOVEMENT", "50000000-0000-0000-0000-000000000001"
        ), "link-1")

        assertNotEquals(firstHash.toList(), repository.lastHash!!.toList())
    }

    @Test
    fun rejectsUnknownTargetTypeAndInvalidIdentifiersBeforeRepositoryCall() {
        val request = LinkFinancialEvidenceRequest("not-a-uuid", "UNKNOWN", "also-invalid")
        assertFailsWith<FinancialCommandValidationException> {
            service.link(actor, tenant, request, "link-1")
        }
        assertEquals(null, repository.lastRequest)
    }

    private class CapturingRepository : EvidenceFinancialLinkRepository {
        var lastRequest: LinkFinancialEvidenceRequest? = null
        var lastHash: ByteArray? = null
        var lastKey: String? = null

        override fun link(
            actorId: UUID,
            tenantId: UUID,
            request: LinkFinancialEvidenceRequest,
            key: String,
            hash: ByteArray
        ): JsonObject {
            lastRequest = request
            lastHash = hash.copyOf()
            lastKey = key
            return buildJsonObject {
                put("resourceId", request.evidenceId)
                put("replayed", false)
            }
        }
    }
}
