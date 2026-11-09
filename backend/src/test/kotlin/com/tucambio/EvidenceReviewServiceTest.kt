package com.tucambio

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals

class EvidenceReviewServiceTest {
    @Test
    fun reviewPassesTenantActorKeyAndStableRequestHash() {
        val actor = UUID.fromString("91000000-0000-0000-0000-000000000001")
        val tenant = UUID.fromString("92000000-0000-0000-0000-000000000001")
        val evidence = UUID.fromString("93000000-0000-0000-0000-000000000001")
        val repository = CapturingEvidenceReviewRepository()
        val service = EvidenceReviewService(repository)
        val request = ReviewEvidenceRequest("OBSERVADA", "Comprobante ilegible")

        service.review(actor, tenant, evidence, request, "review-1")

        assertEquals(actor, repository.actor)
        assertEquals(tenant, repository.tenant)
        assertEquals(evidence, repository.evidence)
        assertEquals(request, repository.request)
        assertEquals("review-1", repository.key)
        assertEquals(32, repository.hash?.size)
        assertContentEquals(repository.hash, repository.hashCopy)
    }

    @Test
    fun changedReviewPayloadProducesDifferentIdempotencyHash() {
        val actor = UUID.fromString("91000000-0000-0000-0000-000000000001")
        val tenant = UUID.fromString("92000000-0000-0000-0000-000000000001")
        val evidence = UUID.fromString("93000000-0000-0000-0000-000000000001")
        val first = CapturingEvidenceReviewRepository()
        val second = CapturingEvidenceReviewRepository()
        EvidenceReviewService(first).review(actor, tenant, evidence, ReviewEvidenceRequest("VALIDA"), "same-key")
        EvidenceReviewService(second).review(actor, tenant, evidence, ReviewEvidenceRequest("OBSERVADA", "Motivo"), "same-key")
        assertEquals(false, first.hash!!.contentEquals(second.hash!!))
    }

    private class CapturingEvidenceReviewRepository : EvidenceReviewRepository {
        var actor: UUID? = null
        var tenant: UUID? = null
        var evidence: UUID? = null
        var request: ReviewEvidenceRequest? = null
        var key: String? = null
        var hash: ByteArray? = null
        var hashCopy: ByteArray? = null

        override fun review(
            actorUserId: UUID,
            tenantId: UUID,
            evidenceId: UUID,
            request: ReviewEvidenceRequest,
            idempotencyKey: String,
            requestHash: ByteArray
        ) = buildJsonObject { put("resourceId", "event-1"); put("replayed", false) }.also {
            actor = actorUserId
            tenant = tenantId
            evidence = evidenceId
            this.request = request
            key = idempotencyKey
            hash = requestHash
            hashCopy = requestHash.copyOf()
        }
    }
}
